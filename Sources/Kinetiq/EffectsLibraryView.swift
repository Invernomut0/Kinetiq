// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import KinetiqCore
import SwiftUI
import UniformTypeIdentifiers

enum EffectDetailTab: String, CaseIterable, Identifiable {
    case preview = "Preview", parameters = "Parameters", triggers = "Triggers"
    case performance = "Performance", reset = "Reset"
    var id: String { rawValue }
}

/// Six permanent categories; manifest entries, not navigation destinations, populate the library.
@MainActor
struct EffectsLibraryView: View {
    @ObservedObject var model: SetupModel
    @ObservedObject private var store = CatalogStore.shared
    @ObservedObject private var runtime = CatalogRuntime.shared
    @State private var category: EffectCategory
    @State private var selected: EffectID
    @State private var original: LibraryEffect?
    @State private var editing: EffectPreset
    @State private var tab: EffectDetailTab = .preview
    @State private var windowID: CGWindowID?
    @State private var previewTime = 0.0
    @State private var error: String?
    @State private var notice: String?
    @State private var legacyExpanded = false
    @State private var runTask: Task<Void, Never>?

    init(model: SetupModel, initialCategory: EffectCategory? = nil) {
        self.model = model
        let category = initialCategory ?? .windowMotion
        let first = EffectCatalog.effects.first(where: { $0.category == category })?.id ?? .wobbly
        _category = State(initialValue: category)
        _selected = State(initialValue: first)
        _editing = State(initialValue: CatalogStore.shared.preset(first))
        if let requested = model.requestedLibraryEffect.flatMap(LibraryEffect.find) {
            _category = State(initialValue: requested.category)
            if case .catalog(let id) = requested {
                _selected = State(initialValue: id)
                _editing = State(initialValue: CatalogStore.shared.preset(id))
            } else { _original = State(initialValue: requested) }
        }
    }

    private var descriptor: EffectDescriptor { EffectCatalog.descriptor(selected) }
    private var entries: [LibraryEffect] { LibraryEffect.all.filter { $0.category == category } }
    private var selection: LibraryEffect { original ?? .catalog(selected) }
    private var submenus: [String] { Array(Set(entries.map(\.submenu))).sorted() }

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                librarySidebar.frame(minWidth: 170, idealWidth: 190, maxWidth: 240)
                Group {
                    if let original {
                        OriginalEffectDetailView(effect: original, model: model).id(original.id)
                    } else { detail }
                }
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            DisclosureGroup("Window Trigger Assignments", isExpanded: $legacyExpanded) {
                SetupControlsView(model: model, page: .effects).frame(height: 310)
                if let error = model.effectError { Text(error).foregroundStyle(.red).font(.caption) }
            }
            .padding(12)
        }
        .onChange(of: category) { _, value in
            if selection.category != value,
               let first = LibraryEffect.all.first(where: { $0.category == value }) { select(first) }
        }
        .onChange(of: model.requestedLibraryEffect, initial: true) { _, id in
            if let effect = id.flatMap(LibraryEffect.find) {
                select(effect)
                model.requestedLibraryEffect = nil
            }
        }
        .onChange(of: editing.duration) { _, duration in previewTime = min(previewTime, duration) }
        .onDisappear { runTask?.cancel(); runtime.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            if isManagementWindow(note) { runTask?.cancel(); runtime.stop() }
        }
    }

    private var librarySidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LIBRARY · \(LibraryEffect.all.count) EFFECTS")
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary).padding(12)
            ForEach(EffectCategory.allCases, id: \.self) { item in
                Button {
                    category = item
                } label: {
                    HStack {
                        Label(item.title, systemImage: item.symbol)
                        Spacer(minLength: 3)
                        Text("\(LibraryEffect.all.filter { $0.category == item }.count)")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(category == item ? Color.accentColor.opacity(0.13) : .clear,
                                in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).padding(.horizontal, 6)
                .accessibilityAddTraits(category == item ? .isSelected : [])
            }
            Divider().padding(.top, 10)
            List {
                ForEach(submenus, id: \.self) { submenu in
                    Section(submenu) {
                        ForEach(entries.filter { $0.submenu == submenu }) { entry in
                            Button { select(entry) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.title)
                                        Text(entry.badge).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selection == entry { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 3)
                            .accessibilityLabel("\(entry.title), \(entry.badge)")
                            .accessibilityAddTraits(selection == entry ? .isSelected : [])
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .background(.background.opacity(0.5))
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(descriptor.category.title) / \(descriptor.submenu)").font(.caption).foregroundStyle(.secondary)
                    Text(descriptor.title).font(.title2.bold())
                    Text(descriptor.summary).font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Menu {
                    ForEach(descriptor.presets, id: \.name) { preset in
                        Button(preset.name) { editing = preset; notice = "Variant loaded. Save to apply." }
                    }
                    Divider()
                    Button("Import Preset…") { importPreset() }
                    Button("Export Saved Preset…") {
                        attempt { try CatalogFilePanels.write(store.exportPreset(selected), name: "\(selected.rawValue).json") }
                    }
                    Button("Copy Parameters") { attempt { try PresetClipboard.copy(editing) } }
                    Button("Paste Parameters") { attempt { editing = try PresetClipboard.paste(into: editing) } }
                } label: { Image(systemName: "ellipsis.circle") }
                .help("Presets and parameters")
            }
            Picker("Detail", selection: $tab) {
                ForEach(EffectDetailTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            if let error { Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            if let notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            if let error = runtime.errorMessage { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            tabContent.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            HStack {
                Text(editing == store.preset(selected) ? "Saved preset" : "Unsaved changes")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Revert") { editing = store.preset(selected); error = nil; notice = nil }
                Button("Save & Apply") {
                    attempt { try store.save(editing); notice = "Preset saved. Trigger assignment persisted." }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
    }

    @ViewBuilder private var tabContent: some View {
        switch tab {
        case .preview:
            VStack(alignment: .leading, spacing: 12) {
                CatalogWindowPicker(selection: $windowID)
                CapturedEffectPreview(document: StudioDocument(duration: editing.duration, layers: [StudioLayer(preset: editing)]),
                                      time: previewTime, windowID: windowID)
                Slider(value: $previewTime, in: 0...editing.duration) { Text("Preview time") }
                    .accessibilityLabel("Preview time")
                HStack {
                    Text("\(previewTime, specifier: "%.2f") s").monospacedDigit().font(.caption)
                    Spacer()
                    Button("Run on Window", systemImage: "play.rectangle") {
                        runTask?.cancel()
                        runTask = Task { await runtime.play(editing, windowID: windowID) }
                    }
                    .disabled(windowID == nil || runtime.isPlaying)
                    Button("Stop & Restore") { runTask?.cancel(); runtime.stop() }.disabled(!runtime.isPlaying)
                }
                Text("Preview only renders the captured target here. Run on Window performs a manual, restoring desktop action; it does not close the target.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .parameters:
            ScrollView { PresetParameterControls(preset: $editing).padding(.vertical, 4) }
        case .triggers:
            VStack(alignment: .leading, spacing: 16) {
                Picker("Trigger", selection: $editing.trigger) {
                    ForEach(descriptor.triggers, id: \.self) { Text($0.title).tag($0) }
                }
                Text("Save & Apply persists this preset and trigger. Original effects are available in these same categories; Window Trigger Assignments below also offers Off and Random.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        case .performance:
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Rendering", value: descriptor.rendering.title)
                LabeledContent("Resource class", value: descriptor.expensive ? "Expensive" : "Standard")
                LabeledContent("Shader status", value: runtime.shaderStatus)
                Text(descriptor.fallback).font(.caption).foregroundStyle(.secondary)
                PerformanceView()
            }
        case .reset:
            VStack(alignment: .leading, spacing: 16) {
                Text("Restore \(descriptor.title)").font(.headline)
                Text("Replace the saved preset, parameters, tracks and trigger with this effect’s catalog defaults. Other effects are unchanged.")
                    .foregroundStyle(.secondary)
                Button("Reset This Effect", role: .destructive) {
                    store.reset(selected)
                    editing = store.preset(selected)
                    notice = "Default preset restored."
                }
            }
        }
    }

    private func select(_ effect: LibraryEffect) {
        category = effect.category
        if case .catalog(let id) = effect { original = nil; select(id) }
        else { original = effect }
    }

    private func select(_ id: EffectID) {
        original = nil
        selected = id
        editing = store.preset(id)
        previewTime = 0
        error = nil
        notice = nil
    }

    private func attempt(_ operation: () throws -> Void) {
        do { try operation(); error = nil } catch { self.error = error.localizedDescription }
    }

    private func importPreset() {
        attempt {
            guard let data = try CatalogFilePanels.read() else { return }
            let preset = try EffectPreset.decode(data)
            try store.importPreset(data)
            category = EffectCatalog.descriptor(preset.effect).category
            select(preset.effect)
            notice = "Preset imported and saved."
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
                Text("Choose a real window…").tag(Optional<CGWindowID>.none)
                ForEach(windows) { window in
                    Text("\(window.owner) — \(window.title.isEmpty ? "Untitled" : window.title) (\(window.id))")
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

private struct PreviewRequest: Equatable {
    let document: StudioDocument
    let time: Double
    let windowID: CGWindowID?
    let visible: Bool
}

/// Structured, cancellable preview work. A target must be chosen; no synthetic window is drawn.
@MainActor
struct CapturedEffectPreview: View {
    let document: StudioDocument
    let time: Double
    let windowID: CGWindowID?
    @State private var image: NSImage?
    @State private var error: String?
    @State private var rendering = false
    @State private var visible = true

    var body: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
            if let image {
                Image(nsImage: image).resizable().scaledToFit().padding(12)
                    .accessibilityLabel("Rendered capture of selected window")
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "macwindow").font(.largeTitle).foregroundStyle(.secondary)
                    Text(windowID == nil ? "Choose a window to preview" : "Captured-window preview")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            if rendering { ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(10) }
        }
        .frame(minHeight: 140, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .bottomLeading) {
            if let error { Text(error).font(.caption).foregroundStyle(.red).padding(10).background(.regularMaterial).textSelection(.enabled) }
        }
        .task(id: PreviewRequest(document: document, time: time, windowID: windowID, visible: visible)) {
            guard visible, let windowID else { image = nil; rendering = false; return }
            do {
                try await Task.sleep(for: .milliseconds(60))
                try Task.checkCancellation()
                rendering = true
                let result = try await CatalogRuntime.shared.preview(document: document, time: time, windowID: windowID)
                try Task.checkCancellation()
                image = result
                error = nil
                rendering = false
            } catch is CancellationError {
                // A newer structured task owns the progress state now.
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
                image = nil
                rendering = false
            }
        }
        .onChange(of: windowID) { _, _ in image = nil; error = nil }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            if isManagementWindow(note) { visible = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            if isManagementWindow(note) { visible = true }
        }
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

/// Desktop composition is explicit and uses the same restoring runtime as the library.
@MainActor
struct CatalogArrangementView: View {
    let workspaces: Bool
    @ObservedObject private var runtime = CatalogRuntime.shared
    @State private var runTask: Task<Void, Never>?
    @State private var windowID: CGWindowID?

    private var effects: [EffectID] { workspaces ? [.workspaceCube, .orbit, .expose3D] : [.orbit, .expose3D] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Current Space only, no native Space switching", systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
                CatalogWindowPicker(selection: $windowID)
                ForEach(effects, id: \.self) { id in
                    let descriptor = EffectCatalog.descriptor(id)
                    GroupBox {
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: descriptor.category.symbol).font(.title2).foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(descriptor.title).font(.headline)
                                Text(descriptor.summary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Button("Run", systemImage: "play.fill") {
                                runTask?.cancel()
                                runTask = Task { await runtime.play(CatalogStore.shared.preset(id), windowID: windowID) }
                            }
                            .disabled(runtime.isPlaying || windowID == nil)
                        }
                        .padding(12)
                    }
                }
                Button("Stop & Restore Windows") { runTask?.cancel(); runtime.stop() }.disabled(!runtime.isPlaying)
                if let error = runtime.errorMessage { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                Text("Run composes actual eligible captured windows. Exclusions, permissions and restoration are enforced by the runtime. These controls do not move windows between native Spaces.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .onDisappear { runTask?.cancel(); runtime.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            if isManagementWindow(note) { runTask?.cancel(); runtime.stop() }
        }
    }
}