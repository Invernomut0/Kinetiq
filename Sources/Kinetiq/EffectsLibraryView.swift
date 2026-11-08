// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import KinetiqCore
import SwiftUI
import UniformTypeIdentifiers

/// One row of the library: an effect seen through the window event it would react to.
struct LibrarySelection: Hashable {
    let effect: LibraryEffect
    let trigger: EffectTrigger

    /// The section an effect is shown in when nothing more specific was requested.
    static func primary(_ effect: LibraryEffect) -> LibrarySelection {
        let trigger = EffectTrigger.librarySections.first { effect.triggers.contains($0) } ?? .manual
        return LibrarySelection(effect: effect, trigger: trigger)
    }
}

/// A sidebar row: a library effect seen through one event, or a saved Studio composition.
enum LibraryItem: Hashable {
    case effect(LibrarySelection)
    case custom(UUID)

    static let customPrefix = "custom:"

    /// Resolves `SetupModel.requestedLibraryEffect`: a `LibraryEffect` ID or `custom:<uuid>`.
    @MainActor static func requested(_ id: String?, store: CatalogStore) -> LibraryItem? {
        guard let id else { return nil }
        if id.hasPrefix(customPrefix), let uuid = UUID(uuidString: String(id.dropFirst(customPrefix.count))),
           store.customEffect(uuid) != nil { return .custom(uuid) }
        return LibraryEffect.find(id).map { .effect(.primary($0)) }
    }
}

/// Effects grouped by what the user does (drag, open, close, minimize), each with a live preview
/// and one obvious action: use it for that event. Studio and built-in effects share the same page.
@MainActor
struct EffectsLibraryView: View {
    @ObservedObject var model: SetupModel
    @ObservedObject private var store = CatalogStore.shared
    @State private var selection: LibraryItem
    @State private var search = ""

    init(model: SetupModel, initialCategory: EffectCategory? = nil) {
        self.model = model
        var initial = LibraryItem.effect(.primary(.catalog(.wobbly)))
        if let category = initialCategory,
           let first = LibraryEffect.all.first(where: { $0.category == category }) {
            initial = .effect(.primary(first))
        }
        if let requested = LibraryItem.requested(model.requestedLibraryEffect, store: .shared) { initial = requested }
        _selection = State(initialValue: initial)
    }

    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 250, idealWidth: 280, maxWidth: 340)
            Group {
                switch selection {
                case .effect(let value): EffectDetailView(selection: value, model: model)
                case .custom(let id): CustomEffectDetailView(id: id, model: model)
                }
            }
            .id(selection)
            .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: model.requestedLibraryEffect, initial: true) { _, id in
            if let item = LibraryItem.requested(id, store: store) {
                selection = item
                search = ""
                model.requestedLibraryEffect = nil
            }
        }
        .onChange(of: store.customEffects) { _, customs in
            if case .custom(let id) = selection, !customs.contains(where: { $0.id == id }) {
                selection = .effect(.primary(.catalog(.wobbly)))
            }
        }
    }

    // MARK: - Sidebar

    private var matches: [LibraryEffect] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return LibraryEffect.all.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.blurb.localizedCaseInsensitiveContains(query)
        }
    }

    private var customMatches: [CustomEffect] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return store.customEffects.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private func customRow(_ custom: CustomEffect) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(custom.name)
                Text("\(custom.document.layers.count) layer\(custom.document.layers.count == 1 ? "" : "s") · \(custom.trigger == .manual ? "not used yet" : custom.trigger.eventTitle.lowercased())")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 2)
            if custom.trigger != .manual {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor).accessibilityLabel("Active")
            }
        }
        .padding(.vertical, 2)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search \(LibraryEffect.all.count) effects", text: $search).textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }
            .padding(8)
            .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .padding(10)
            List(selection: Binding(get: { Optional(selection) }, set: { if let value = $0 { selection = value } })) {
                if search.isEmpty {
                    Section {
                        ForEach(store.customEffects) { custom in customRow(custom).tag(LibraryItem.custom(custom.id)) }
                        Button {
                            model.requestedPage = .animationStudio
                        } label: {
                            Label(store.customEffects.isEmpty ? "Create one in Animation Studio" : "New in Animation Studio",
                                  systemImage: "plus.circle")
                        }
                        .buttonStyle(.borderless)
                    } header: { Label("My Effects", systemImage: "star.square.on.square") }
                    ForEach(EffectTrigger.librarySections, id: \.self) { trigger in
                        Section {
                            ForEach(LibraryEffect.supporting(trigger)) { effect in
                                row(effect, trigger: trigger).tag(LibraryItem.effect(LibrarySelection(effect: effect, trigger: trigger)))
                            }
                        } header: { sectionHeader(trigger) }
                    }
                } else if matches.isEmpty && customMatches.isEmpty {
                    Text("No effect matches “\(search)”.").foregroundStyle(.secondary)
                } else {
                    Section("Results") {
                        ForEach(customMatches) { custom in customRow(custom).tag(LibraryItem.custom(custom.id)) }
                        ForEach(matches) { effect in
                            row(effect, trigger: LibrarySelection.primary(effect).trigger)
                                .tag(LibraryItem.effect(.primary(effect)))
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .background(.background.opacity(0.5))
    }

    private func sectionHeader(_ trigger: EffectTrigger) -> some View {
        let assignment = model.assignment(for: trigger)
        return HStack(spacing: 6) {
            Label(trigger.eventTitle, systemImage: trigger.symbol)
            Spacer(minLength: 4)
            if trigger != .overview {
                Menu {
                    Text("Now: \(assignment.title)")
                    Divider()
                    if trigger != .drag {
                        Button("Off") { model.setTrigger(trigger, random: false) }
                        Button("Random") { model.setTrigger(trigger, random: true) }
                        if !store.customEffects.isEmpty {
                            Divider()
                            Section("My Effects") {
                                ForEach(store.customEffects) { custom in
                                    Button(custom.name) { model.assignCustom(custom.id, to: trigger) }
                                }
                            }
                        }
                    } else {
                        Button("Classic wobble (no Studio preset)") { model.setTrigger(.drag, random: false) }
                    }
                } label: {
                    Text(assignment.title).font(.caption).lineLimit(1)
                }
                .menuStyle(.borderlessButton).fixedSize()
                .help("What this event currently plays. Choose Off or Random here; pick an effect in the list to use it.")
            }
        }
    }

    private func row(_ effect: LibraryEffect, trigger: EffectTrigger) -> some View {
        let active = model.isAssigned(effect, to: trigger)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(effect.title)
                Text(effect.blurb).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 2)
            if effect.isStudio {
                Image(systemName: "slider.horizontal.3").font(.caption2).foregroundStyle(.tertiary)
                    .help("Studio preset: parameters and timeline can be edited")
            }
            if active {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Active")
            }
        }
        .padding(.vertical, 2)
        .accessibilityLabel("\(effect.title), \(effect.kindLabel)\(active ? ", active" : "")")
    }
}

/// Preview first, then the one decision that matters, then optional tuning.
@MainActor
struct EffectDetailView: View {
    let selection: LibrarySelection
    @ObservedObject var model: SetupModel
    @ObservedObject private var store = CatalogStore.shared
    @ObservedObject private var runtime = CatalogRuntime.shared
    @ObservedObject private var sources = PreviewSourceStore.shared
    @State private var editing: EffectPreset?
    @State private var customizeExpanded = false
    @State private var moreExpanded = false
    @State private var notice: String?
    @State private var error: String?
    @State private var runTask: Task<Void, Never>?

    private var effect: LibraryEffect { selection.effect }
    private var catalogID: EffectID? { if case .catalog(let id) = effect { return id }; return nil }
    private var saved: EffectPreset? { catalogID.map { store.preset($0) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                EffectPreviewPlayer(subject: .effect(effect, editing ?? saved), settings: model.settings)
                    .frame(height: 340)
                assignBar
                if let message = error ?? model.effectError ?? runtime.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red).textSelection(.enabled)
                }
                if let notice { Label(notice, systemImage: "checkmark.circle").font(.callout).foregroundStyle(.secondary) }
                DisclosureGroup(isExpanded: $customizeExpanded) {
                    customize.padding(.top, 8)
                } label: {
                    Label(effect.isStudio ? "Customize parameters" : "Adjust", systemImage: "slider.horizontal.3").font(.headline)
                }
                DisclosureGroup(isExpanded: $moreExpanded) {
                    more.padding(.top, 8)
                } label: { Label("More", systemImage: "ellipsis.circle").font(.headline) }
            }
            .padding(20)
        }
        .onAppear { editing = saved }
        .onChange(of: store.presets) { _, _ in if editing == nil { editing = saved } }
        .onDisappear { runTask?.cancel(); runtime.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            if isManagementWindow(note) { runTask?.cancel(); runtime.stop() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(effect.title).font(.title.bold())
                Text(effect.kindLabel).font(.caption.weight(.medium)).padding(.horizontal, 7).padding(.vertical, 2)
                    .background(effect.isStudio ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.07), in: Capsule())
                Spacer()
                if effect.isStudio, let editing, let saved, editing != saved {
                    Text("Unsaved changes").font(.caption).foregroundStyle(.orange)
                }
            }
            Text(effect.blurb).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(effectDetails).font(.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var effectDetails: String {
        switch effect {
        case .catalog(let id):
            let descriptor = EffectCatalog.descriptor(id)
            let events = descriptor.triggers.filter { $0 != .manual }.map(\.shortTitle)
            return "Rendering: \(descriptor.rendering.title)\(descriptor.expensive ? " (GPU-heavy)" : "")."
                + (events.isEmpty ? " Runs manually only." : " Can react to: \(events.joined(separator: ", ")).")
        case .entrance: return "Uses the spring settings from Physics. Shown on the window that just opened."
        case .close: return "Plays on the captured image of the window after it has really closed. Duration follows the shared multiplier."
        case .minimize: return "Travels to the window's Dock icon. In this preview the destination is local, not your actual Dock."
        case .liquid: return "A particle fluid simulation. Here it pools on a local floor instead of behind your Dock."
        }
    }

    // MARK: - Assign

    private var assignBar: some View {
        let triggers = effect.automaticTriggers
        return VStack(alignment: .leading, spacing: 8) {
            if triggers.isEmpty {
                HStack {
                    Text("This effect has no automatic event. Run it on a window from the menu bar or below.")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    runButtons
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { assignButtons(triggers) }
                    VStack(alignment: .leading, spacing: 8) { assignButtons(triggers) }
                }
                Text(selection.trigger.explanation).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private func assignButtons(_ triggers: [EffectTrigger]) -> some View {
        ForEach(triggers, id: \.self) { trigger in
            let active = model.isAssigned(effect, to: trigger)
            let current = model.assignment(for: trigger)
            HStack(spacing: 4) {
                Button {
                    if effect.isStudio, let editing, editing != saved { attempt { try store.save(editing) } }
                    if model.assign(effect, to: trigger) { notice = "\(effect.title) now plays \(trigger.eventTitle.lowercased())." }
                } label: {
                    Label(active ? "Active \(trigger.eventTitle.lowercased())" : "Use \(trigger.eventTitle.lowercased())",
                          systemImage: active ? "checkmark.circle.fill" : trigger.symbol)
                }
                .buttonStyle(.borderedProminent)
                .tint(active ? .green : .accentColor)
                .disabled(active)
                .help(active ? "Currently in use" : "Replaces: \(current.title)")
                if active, trigger != .drag {
                    Button("Turn off") { if model.setTrigger(trigger, random: false) { notice = "\(trigger.shortTitle) effects are off." } }
                        .buttonStyle(.bordered)
                } else if active, trigger == .drag {
                    Button("Use classic wobble") { if model.setTrigger(.drag, random: false) { notice = "Drag uses the classic spring wobble." } }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - Customize

    @ViewBuilder private var customize: some View {
        if let id = catalogID, let saved {
            let descriptor = EffectCatalog.descriptor(id)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Variants").font(.subheadline)
                    ForEach(descriptor.presets, id: \.name) { preset in
                        Button(preset.name) { editing = preset; notice = nil }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                    Spacer()
                }
                PresetParameterControls(preset: Binding(get: { editing ?? saved }, set: { editing = $0 }))
                HStack {
                    Text("Changes show in the preview right away. Save to keep them.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Revert") { editing = saved; notice = nil }.disabled(editing == saved)
                    Button("Save") {
                        if let editing { attempt { try store.save(editing); notice = "Preset saved." } }
                    }
                    .buttonStyle(.borderedProminent).disabled(editing == saved)
                }
            }
        } else if case .entrance = effect {
            VStack(alignment: .leading, spacing: 10) {
                Text("Entrances replay the same spring model as dragging. Tune stiffness, friction and mass on the Physics page.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Open Physics", systemImage: "atom") { model.requestedPage = .physics }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Duration")
                    Slider(value: model.binding({ model.settings.closeDuration }, { model.settings.closeDuration = $0 }),
                           in: Settings.closeSpeedRange).frame(maxWidth: 320)
                        .accessibilityLabel("Duration multiplier")
                    Text("\(model.settings.closeDuration, specifier: "%.2f")×").monospacedDigit().frame(width: 52, alignment: .trailing)
                    Button("1×") { model.settings.closeDuration = 1; model.refresh() }.controlSize(.small)
                        .disabled(model.settings.closeDuration == 1)
                }
                Text("Shared by all built-in close and minimize effects. 1× is each effect's own default speed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - More

    @ViewBuilder private var more: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let id = catalogID {
                HStack {
                    Text("Try it on a real window").font(.subheadline)
                    Spacer()
                    runButtons
                }
                Text("Plays the saved preset once on the window selected as preview source. The window is captured, animated and put back exactly where it was. Nothing is closed or minimized.")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                HStack {
                    Button("Open in Animation Studio", systemImage: "timeline.selection") {
                        StudioLaunchRequest.shared.preset = editing ?? store.preset(id)
                        model.requestedPage = .animationStudio
                    }
                    Menu("Import / Export") {
                        Button("Import Preset…") { importPreset() }
                        Button("Export Saved Preset…") {
                            attempt { try CatalogFilePanels.write(store.exportPreset(id), name: "\(id.rawValue).json") }
                        }
                        Divider()
                        Button("Copy Parameters") { attempt { try PresetClipboard.copy(editing ?? store.preset(id)) } }
                        Button("Paste Parameters") { attempt { editing = try PresetClipboard.paste(into: editing ?? store.preset(id)) } }
                    }
                    .fixedSize()
                    Spacer()
                    Button("Reset to Defaults", role: .destructive) {
                        store.reset(id); editing = store.preset(id); notice = "Default preset restored."
                    }
                }
                Divider()
                LabeledContent("Shader status", value: runtime.shaderStatus).font(.caption)
            } else {
                Text("Built-in effects keep their original engines and compiled defaults. They have no JSON preset; per-app close rules and exclusions live on the Rules page.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Rules", systemImage: "line.3.horizontal.decrease.circle") { model.requestedPage = .rules }
                    Button("Performance", systemImage: "gauge.with.dots.needle.67percent") { model.requestedPage = .performance }
                }
            }
        }
    }

    private var runButtons: some View {
        HStack(spacing: 6) {
            Button("Run on Window", systemImage: "play.rectangle") {
                guard let id = catalogID else { return }
                runTask?.cancel()
                let preset = store.preset(id)
                runTask = Task { await runtime.play(preset, windowID: sources.source.windowID) }
            }
            .disabled(catalogID == nil || runtime.isPlaying)
            .help(sources.source == .sample ? "Uses the frontmost app's window. Pick a window as preview source to target it." : "Runs on the window chosen as preview source")
            Button { runTask?.cancel(); runtime.stop() } label: { Image(systemName: "stop.fill") }
                .disabled(!runtime.isPlaying).help("Stop and restore the window").accessibilityLabel("Stop and restore")
        }
    }

    private func attempt(_ operation: () throws -> Void) {
        do { try operation(); error = nil } catch { self.error = error.localizedDescription }
    }

    private func importPreset() {
        attempt {
            guard let data = try CatalogFilePanels.read() else { return }
            let preset = try EffectPreset.decode(data)
            guard preset.effect == catalogID else {
                throw StudioUIError.message("That file is a \(EffectCatalog.descriptor(preset.effect).title) preset. Select that effect first.")
            }
            try store.importPreset(data)
            editing = store.preset(preset.effect)
            notice = "Preset imported and saved."
        }
    }
}

/// A saved Studio composition: preview, the events it can play on, and a way back to the Studio.
@MainActor
struct CustomEffectDetailView: View {
    let id: UUID
    @ObservedObject var model: SetupModel
    @ObservedObject private var store = CatalogStore.shared
    @ObservedObject private var runtime = CatalogRuntime.shared
    @ObservedObject private var sources = PreviewSourceStore.shared
    @State private var notice: String?
    @State private var confirmingDelete = false
    @State private var runTask: Task<Void, Never>?

    var body: some View {
        if let custom = store.customEffect(id) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(custom.name).font(.title.bold())
                            Text("My Effect").font(.caption.weight(.medium)).padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                        }
                        Text(custom.document.layers.map { $0.name + ($0.reversed ? " (reversed)" : "") }.joined(separator: " → "))
                            .foregroundStyle(.secondary)
                        Text("\(custom.document.duration.formatted(.number.precision(.fractionLength(1)))) s · made in Animation Studio")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    EffectPreviewPlayer(subject: .document(custom.document), settings: model.settings).frame(height: 340)
                    VStack(alignment: .leading, spacing: 8) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) { assignButtons(custom) }
                            VStack(alignment: .leading, spacing: 8) { assignButtons(custom) }
                        }
                        Text("Close and Minimize play on the window's last image after it is gone, so end with a layer that makes it disappear.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                    if let message = model.effectError ?? runtime.errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    }
                    if let notice { Label(notice, systemImage: "checkmark.circle").font(.callout).foregroundStyle(.secondary) }
                    HStack {
                        Button("Edit in Animation Studio", systemImage: "timeline.selection") {
                            StudioLaunchRequest.shared.customID = custom.id
                            model.requestedPage = .animationStudio
                        }
                        Button("Run on Window", systemImage: "play.rectangle") {
                            runTask?.cancel()
                            runTask = Task { await runtime.playDocument(custom.document, windowID: sources.source.windowID) }
                        }
                        .disabled(runtime.isPlaying)
                        Spacer()
                        Button("Delete", role: .destructive) { confirmingDelete = true }
                    }
                }
                .padding(20)
            }
            .alert("Delete “\(custom.name)”?", isPresented: $confirmingDelete) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    store.deleteCustom(custom.id)
                    model.closeEffectChangedPublic()
                }
            } message: { Text("It is removed from My Effects and stops playing on any event. This cannot be undone.") }
            .onDisappear { runTask?.cancel(); runtime.stop() }
        } else {
            ContentUnavailableView("Effect deleted", systemImage: "star.slash")
        }
    }

    @ViewBuilder private func assignButtons(_ custom: CustomEffect) -> some View {
        ForEach(CustomEffect.assignableTriggers, id: \.self) { trigger in
            let active = custom.trigger == trigger
            HStack(spacing: 4) {
                Button {
                    if model.assignCustom(custom.id, to: trigger) { notice = "“\(custom.name)” now plays \(trigger.eventTitle.lowercased())." }
                } label: {
                    Label(active ? "Active \(trigger.eventTitle.lowercased())" : "Use \(trigger.eventTitle.lowercased())",
                          systemImage: active ? "checkmark.circle.fill" : trigger.symbol)
                }
                .buttonStyle(.borderedProminent).tint(active ? .green : .accentColor).disabled(active)
                .help(active ? "Currently in use" : "Replaces: \(model.assignment(for: trigger).title)")
                if active {
                    Button("Stop using") {
                        if model.releaseTrigger(trigger) {
                            notice = "\(trigger.shortTitle) plays \(model.assignment(for: trigger).title) again."
                        }
                    }
                    .buttonStyle(.bordered)
                    .help("Releases this event; the effect chosen before plays again")
                }
            }
        }
    }
}

/// Shared scalar inspector. Every catalog parameter is exposed in its declared range and units.
struct PresetParameterControls: View {
    @Binding var preset: EffectPreset

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Preset name", text: $preset.name)
            HStack {
                Text("Duration (seconds)")
                Spacer()
                TextField("Duration", value: duration, format: .number)
                    .frame(width: 80)
                Stepper("Duration", value: duration, in: EffectPreset.durationRange, step: 0.1).labelsHidden()
            }
            Picker("Playback curve", selection: $preset.curve) {
                ForEach(AnimationCurve.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Divider()
            ForEach(EffectCatalog.descriptor(preset.effect).parameters) { spec in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(spec.title)
                        Spacer()
                        TextField(spec.title, value: parameter(spec), format: .number.precision(.fractionLength(3)))
                            .multilineTextAlignment(.trailing).frame(width: 80)
                    }
                    Slider(value: parameter(spec), in: spec.minimum...spec.maximum)
                        .accessibilityLabel(spec.title)
                }
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private func parameter(_ spec: EffectParameterSpec) -> Binding<Double> {
        Binding(get: { preset.parameters[spec.id] ?? spec.defaultValue }, set: {
            guard $0.isFinite else { return }
            preset.parameters[spec.id] = min(spec.maximum, max(spec.minimum, $0))
        })
    }

    private var duration: Binding<Double> {
        Binding(get: { preset.duration }, set: {
            guard $0.isFinite else { return }
            preset.duration = min(EffectPreset.durationRange.upperBound, max(EffectPreset.durationRange.lowerBound, $0))
        })
    }
}

@MainActor
struct CatalogWindowPicker: View {
    @Binding var selection: CGWindowID?
    @State private var windows: [ManagedWindow] = []

    var body: some View {
        HStack {
            Picker("Target", selection: $selection) {
                Text("Frontmost app's window").tag(Optional<CGWindowID>.none)
                ForEach(windows) { window in
                    Text("\(window.owner) — \(window.title.isEmpty ? "Untitled" : window.title)")
                        .tag(Optional(window.id))
                }
            }
            Button { refresh() } label: { Image(systemName: "arrow.clockwise") }
                .help("Refresh available windows").accessibilityLabel("Refresh available windows")
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        windows = CatalogRuntime.shared.availableWindows()
        if let selection, !windows.contains(where: { $0.id == selection }) { self.selection = nil }
    }
}

@MainActor
func isManagementWindow(_ notification: Notification) -> Bool {
    (notification.object as? NSWindow)?.frameAutosaveName == "KinetiqManagement"
}

/// Real file panels; only runtime user-selected files are read or written.
@MainActor
enum CatalogFilePanels {
    static func read() throws -> Data? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 32 * 1024 * 1024 else { throw StudioUIError.message("JSON exceeds 32 MiB.") }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    static func write(_ data: Data, name: String) throws {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try data.write(to: url, options: .atomic)
    }
}

enum StudioUIError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

/// Strict preset decoding rejects unknown fields, versions and incompatible effect schemas.
@MainActor
enum PresetClipboard {
    static func applying(_ data: Data, to target: EffectPreset) throws -> EffectPreset {
        let source = try EffectPreset.decode(data)
        guard source.effect == target.effect else {
            throw StudioUIError.message("Parameters belong to \(EffectCatalog.descriptor(source.effect).title), not \(EffectCatalog.descriptor(target.effect).title).")
        }
        var result = target
        result.parameters = source.parameters
        return try result.validated()
    }

    static func copy(_ preset: EffectPreset) throws {
        let data = try preset.encoded()
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(String(decoding: data, as: UTF8.self), forType: .string) else {
            throw StudioUIError.message("Could not write parameters to the clipboard.")
        }
    }

    static func paste(into preset: EffectPreset) throws -> EffectPreset {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            throw StudioUIError.message("The clipboard does not contain preset JSON.")
        }
        return try applying(Data(text.utf8), to: preset)
    }
}

/// Window arrangements for the current Space: a global shortcut, a live demo of each layout
/// with several windows, adjustable look, and the keys that drive it on the desktop.
@MainActor
struct CatalogArrangementView: View {
    @ObservedObject private var runtime = CatalogRuntime.shared
    @ObservedObject private var store = CatalogStore.shared
    @ObservedObject var model: SetupModel
    @State private var runTask: Task<Void, Never>?

    private var settings: Settings { model.settings }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                ForEach(Settings.overviewLayouts, id: \.self) { id in card(id) }
                if let error = runtime.errorMessage { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                Text("Uses captures of up to eight windows on the current Space. Windows are never moved: they are put back exactly where they were, and the one you click is brought to the front. Kinetiq does not switch native Spaces.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
        }
        .onDisappear { runTask?.cancel() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "rectangle.3.group").font(.system(size: 30)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("See all your windows at once").font(.title3.bold())
                    Text("Windows fly out of place into a 3D arrangement. Point at one to lift it and see its name, click it to bring it forward, or press Escape to send everything back.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Try It Now", systemImage: "play.fill") { start(settings.overviewLayout) }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(runtime.isPlaying)
            }
            Divider()
            HStack(spacing: 18) {
                Toggle(isOn: model.binding({ settings.overviewShortcut }, { settings.overviewShortcut = $0 })) {
                    Text("Shortcut \(GlobalHotKey.overviewTitle) anywhere")
                }
                Picker("Opens", selection: model.binding({ settings.overviewLayout }, { settings.overviewLayout = $0 })) {
                    ForEach(Settings.overviewLayouts, id: \.self) { Text(EffectCatalog.descriptor($0).title).tag($0) }
                }
                .pickerStyle(.segmented).frame(maxWidth: 320)
                Spacer()
            }
            HStack(spacing: 16) {
                hint("cursorarrow.motionlines", "Hover to lift")
                hint("cursorarrow.click", "Click to bring forward")
                hint("arrow.left.and.right", "Arrows to move")
                hint("scroll", "Scroll to spin")
                hint("escape", "Esc to put back")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
    }

    private func hint(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
    }

    private func card(_ id: EffectID) -> some View {
        let descriptor = EffectCatalog.descriptor(id)
        let preset = store.preset(id)
        let isDefault = settings.overviewLayout == id
        return GroupBox {
            HStack(alignment: .top, spacing: 18) {
                EffectPreviewPlayer(subject: .overview(preset), settings: settings, showsSourcePicker: false)
                    .frame(width: 380, height: 270)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(descriptor.title).font(.title3.bold())
                        if isDefault {
                            Text("Shortcut").font(.caption.weight(.medium)).padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                        }
                    }
                    Text(blurb(id)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    ForEach(descriptor.parameters.filter { $0.id != "speed" }) { spec in
                        HStack {
                            Text(spec.id == "amplitude" ? "Intensity" : spec.title).font(.caption).frame(width: 170, alignment: .leading)
                            Slider(value: Binding(get: { store.preset(id).parameters[spec.id] ?? spec.defaultValue }, set: { value in
                                var next = store.preset(id)
                                next.parameters[spec.id] = min(spec.maximum, max(spec.minimum, value))
                                try? store.save(next)
                            }), in: spec.minimum...spec.maximum)
                            .accessibilityLabel(spec.title)
                        }
                    }
                    HStack {
                        Button("Start", systemImage: "play.fill") { start(id) }
                            .buttonStyle(.borderedProminent).disabled(runtime.isPlaying)
                        Button("Use for Shortcut") { settings.overviewLayout = id; model.refresh() }.disabled(isDefault)
                        Button("Defaults") { store.reset(id) }.disabled(store.preset(id) == EffectPreset(effect: id))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
        }
    }

    private func blurb(_ id: EffectID) -> String {
        switch id {
        case .expose3D: return "A tilted grid of every window. The one you point at straightens up to face you. Arrow keys move around the grid."
        case .orbit: return "Windows ride a slowly turning ring; the front ones are larger. Scroll to spin it, arrows bring the next window to the front."
        default: return "A carousel: one window faces you, the others turn away at the sides like a cube. Scroll or use the arrows to rotate; click a side window to bring it round."
        }
    }

    private func start(_ id: EffectID) {
        runTask?.cancel()
        runTask = Task { await runtime.play(store.preset(id)) }
    }
}
