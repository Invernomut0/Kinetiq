// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import KinetiqCore
import KinetiqEffects
import SwiftUI

/// Value-snapshot editing: validation is atomic and failed edits never enter history.
@MainActor
final class StudioEditorModel: ObservableObject {
    static let historyLimit = 100
    @Published private(set) var document: StudioDocument
    @Published private(set) var errorMessage: String?
    @Published private(set) var undoCount = 0
    @Published private(set) var redoCount = 0
    private var past: [StudioDocument] = []
    private var future: [StudioDocument] = []

    init(document: StudioDocument) {
        self.document = document
        do { _ = try document.validated() } catch { errorMessage = error.localizedDescription }
    }

    @discardableResult
    func perform(_ edit: (inout StudioDocument) throws -> Void) -> Bool {
        do {
            var next = document
            try edit(&next)
            _ = try next.validated()
            errorMessage = nil
            guard next != document else { return true }
            past.append(document)
            if past.count > Self.historyLimit { past.removeFirst(past.count - Self.historyLimit) }
            future.removeAll()
            document = next
            publishHistory()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func undo() {
        guard let previous = past.popLast() else { return }
        future.append(document)
        document = previous
        errorMessage = nil
        publishHistory()
    }

    func redo() {
        guard let next = future.popLast() else { return }
        past.append(document)
        document = next
        errorMessage = nil
        publishHistory()
    }

    @discardableResult
    func addLayer(_ preset: EffectPreset, at start: Double = 0) -> UUID? {
        let layer = StudioLayer(preset: preset, start: start)
        return perform {
            $0.layers.append(layer)
            $0.duration = max($0.duration, start + preset.duration)
        } ? layer.id : nil
    }

    func removeLayer(_ id: UUID) { perform { $0.layers.removeAll { $0.id == id } } }

    func updateLayer(_ id: UUID, _ edit: (inout StudioLayer) throws -> Void) {
        perform { document in
            guard let index = document.layers.firstIndex(where: { $0.id == id }) else {
                throw StudioUIError.message("The selected layer no longer exists.")
            }
            try edit(&document.layers[index])
            document.duration = max(document.duration, document.layers[index].start + document.layers[index].preset.duration)
        }
    }

    func addTrack(layer id: UUID, parameter: String) {
        updateLayer(id) { layer in
            guard !layer.preset.tracks.contains(where: { $0.parameter == parameter }) else {
                throw StudioUIError.message("A track for this parameter already exists.")
            }
            let value = layer.preset.value(parameter, at: 0)
            layer.preset.tracks.append(AnimationTrack(parameter: parameter, keyframes: [
                AnimationKeyframe(time: 0, value: value), AnimationKeyframe(time: 1, value: value)
            ]))
        }
    }

    func removeTrack(layer id: UUID, parameter: String) {
        updateLayer(id) { $0.preset.tracks.removeAll { $0.parameter == parameter } }
    }

    func updateTrack(layer id: UUID, parameter: String, _ edit: (inout AnimationTrack) throws -> Void) {
        updateLayer(id) { layer in
            guard let index = layer.preset.tracks.firstIndex(where: { $0.parameter == parameter }) else {
                throw StudioUIError.message("Add a track before editing its keyframes.")
            }
            try edit(&layer.preset.tracks[index])
            layer.preset.tracks[index].keyframes.sort { $0.time < $1.time }
        }
    }

    /// Key times are normalized inside a layer, not document seconds.
    func addKeyframe(layer id: UUID, parameter: String, time: Double) {
        guard let layer = document.layers.first(where: { $0.id == id }) else { return }
        let value = layer.preset.value(parameter, at: time * layer.preset.duration)
        updateTrack(layer: id, parameter: parameter) { track in
            guard !track.keyframes.contains(where: { abs($0.time - time) < 0.000001 }) else {
                throw StudioUIError.message("A keyframe already exists at this time. Move the playhead or edit that keyframe.")
            }
            track.keyframes.append(AnimationKeyframe(time: time, value: value))
        }
    }

    private func publishHistory() { undoCount = past.count; redoCount = future.count }
}

/// Inspector pages named after what the user wants to do with a layer.
enum StudioInspectorTab: String, CaseIterable, Identifiable {
    case edit = "Edit", keyframes = "Keyframes", advanced = "Advanced"
    var id: String { rawValue }
}

@MainActor
struct AnimationStudioView: View {
    @ObservedObject var model: SetupModel
    @ObservedObject private var store = CatalogStore.shared
    @ObservedObject private var runtime = CatalogRuntime.shared
    @ObservedObject private var sources = PreviewSourceStore.shared
    @ObservedObject private var launch = StudioLaunchRequest.shared
    @StateObject private var editor: StudioEditorModel
    @AppStorage("studioIntroDismissed") private var introDismissed = false
    /// The "My Effects" entry this document was opened from or saved as.
    @AppStorage("studioEditingCustomID") private var editingRaw = ""
    @State private var selectedLayer: UUID?
    @State private var parameter = "amplitude"
    @State private var tab: StudioInspectorTab = .edit
    @State private var time = 0.0
    @State private var error: String?
    @State private var notice: String?
    @State private var runTask: Task<Void, Never>?

    init(model: SetupModel) {
        self.model = model
        let document = CatalogStore.shared.document
        _editor = StateObject(wrappedValue: StudioEditorModel(document: document))
        _selectedLayer = State(initialValue: document.layers.first?.id)
    }

    private var layer: StudioLayer? { editor.document.layers.first { $0.id == selectedLayer } }
    private var editingID: UUID? { UUID(uuidString: editingRaw) }
    private var editing: CustomEffect? { editingID.flatMap { store.customEffect($0) } }
    private var unsaved: Bool { editing?.document != editor.document }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            toolbar
            statusStrip
            if !introDismissed { intro }
            if let message = error ?? editor.errorMessage ?? runtime.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
            if let notice { Label(notice, systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary) }
            if editor.document.layers.isEmpty {
                emptyState
            } else {
                HSplitView {
                    VStack(alignment: .leading, spacing: 8) {
                        EffectPreviewPlayer(subject: .document(editor.document), settings: model.settings,
                                            externalTime: $time, autoplay: true)
                        HStack {
                            Text("The preview loops on the sample window. Pick a real window in the source menu, or run it on the desktop.")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            runButtons
                        }
                    }
                    .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                    inspector.frame(minWidth: 300, idealWidth: 340, maxWidth: 440, maxHeight: .infinity)
                }
                .frame(minHeight: 300)
                Divider()
                timeline.frame(minHeight: 150, idealHeight: 200, maxHeight: 260)
            }
        }
        .padding(16)
        .onChange(of: editor.document) { _, document in
            if !document.layers.contains(where: { $0.id == selectedLayer }) { selectedLayer = document.layers.first?.id }
            time = min(time, document.duration)
            store.document = document
            try? store.saveDocument()
        }
        .onChange(of: selectedLayer) { _, _ in
            parameter = layer.flatMap { EffectCatalog.descriptor($0.preset.effect).parameters.first?.id } ?? "amplitude"
            if let track = layer?.preset.tracks.first { parameter = track.parameter }
        }
        .onChange(of: launch.preset, initial: true) { _, preset in
            guard let preset else { return }
            launch.preset = nil
            addLayer(StudioLayer(preset: preset))
            notice = "\(EffectCatalog.descriptor(preset.effect).title) added as a layer."
        }
        .onChange(of: launch.builtin, initial: true) { _, id in
            guard let id, let builtin = BuiltinLayer(id) else { return }
            launch.builtin = nil
            addLayer(builtin.makeLayer())
            notice = "\(builtin.effect.title) added as a layer."
        }
        .onChange(of: launch.customID, initial: true) { _, id in
            guard let id, let custom = store.customEffect(id) else { return }
            launch.customID = nil
            open(custom)
        }
        .onDisappear { runTask?.cancel(); runtime.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            if isManagementWindow(note) { runTask?.cancel(); runtime.stop() }
        }
    }

    // MARK: - Guidance

    private var intro: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "lightbulb").font(.title2).foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 6) {
                Text("Build your own effect in three steps").font(.headline)
                Text("1. **Add Layer** — any Studio effect or built-in effect (Incinerate, Genie, Wobble Pop…). Layers play in order on the same window; overlap them to combine.\n2. **Edit** a layer's timing, direction and parameters. The preview loops while you work; **Keyframes** make a value change over time.\n3. **Save** it to My Effects, then **Use when…** to play it when a window opens, closes or is minimized.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button { introDismissed = true } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                .accessibilityLabel("Dismiss introduction")
        }
        .padding(14)
        .background(.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var statusStrip: some View {
        HStack(spacing: 8) {
            if let editing {
                Image(systemName: "star.circle.fill").foregroundStyle(Color.accentColor)
                Text("My Effect “\(editing.name)”").fontWeight(.medium)
                if editing.trigger == .manual {
                    Text("· saved, not used by any event yet").foregroundStyle(.secondary)
                } else {
                    Text("· plays \(editing.trigger.eventTitle.lowercased())").foregroundStyle(.green)
                }
                if unsaved { Text("· unsaved changes").foregroundStyle(.orange) }
            } else if !editor.document.layers.isEmpty {
                Image(systemName: "circle.dashed").foregroundStyle(.secondary)
                Text("Not saved yet. Save adds it to My Effects; Use when… makes it play automatically.").foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.caption)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "square.3.layers.3d").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Start with a layer").font(.title2.bold())
            Text("A layer is one effect with its own timing. Combine Studio effects and built-in ones like Incinerate or Genie into a transition of your own, then use it when a window opens, closes or is minimized.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 460)
            HStack {
                addLayerMenu.buttonStyle(.borderedProminent).fixedSize()
                Button("Load an Example", systemImage: "wand.and.stars") { loadExample() }
                if !store.customEffects.isEmpty { myEffectsMenu.fixedSize() }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadExample() {
        var ripple = store.preset(.ripple)
        ripple.name = "Ripple"
        ripple.duration = 1.2
        let incinerate = BuiltinLayer.close(.incinerate).makeLayer(start: 0.9)
        let document = StudioDocument(name: "Ripple, then Incinerate", duration: max(3, incinerate.end + 0.2),
                                      layers: [StudioLayer(preset: ripple, start: 0), incinerate])
        newDocument(document)
        notice = "Example loaded: a Studio Ripple followed by the built-in Incinerate. Save it, then use it when a window closes."
    }

    private func newDocument(_ document: StudioDocument) {
        editor.perform { $0 = document }
        editingRaw = ""
        selectedLayer = document.layers.first?.id
        time = 0
    }

    private func open(_ custom: CustomEffect) {
        editor.perform { $0 = custom.document }
        editingRaw = custom.id.uuidString
        selectedLayer = custom.document.layers.first?.id
        time = 0
        notice = "Editing “\(custom.name)”."
    }

    // MARK: - Toolbar

    private var myEffectsMenu: some View {
        Menu {
            Button("New Effect", systemImage: "plus") { newDocument(StudioDocument(name: "My Effect")) }
            if !store.customEffects.isEmpty {
                Divider()
                ForEach(store.customEffects) { custom in
                    Button {
                        open(custom)
                    } label: {
                        Label(custom.name + (custom.trigger == .manual ? "" : " — \(custom.trigger.shortTitle)"),
                              systemImage: custom.id == editingID ? "checkmark" : "star")
                    }
                }
            }
            if let editing {
                Divider()
                Button("Delete “\(editing.name)”", role: .destructive) {
                    store.deleteCustom(editing.id)
                    editingRaw = ""
                    model.closeEffectChangedPublic()
                    notice = "Deleted from My Effects."
                }
            }
        } label: { Label("My Effects", systemImage: "star.square.on.square") }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            myEffectsMenu.fixedSize()
            TextField("Effect name", text: Binding(get: { editor.document.name }, set: { value in
                editor.perform { $0.name = value }
            }))
            .font(.headline).textFieldStyle(.roundedBorder).frame(maxWidth: 230)
            Button { editor.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(editor.undoCount == 0).help("Undo").accessibilityLabel("Undo studio edit")
            Button { editor.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(editor.redoCount == 0).help("Redo").accessibilityLabel("Redo studio edit")
            if introDismissed {
                Button { introDismissed = false } label: { Image(systemName: "questionmark.circle") }
                    .buttonStyle(.borderless).help("Show how the Studio works").accessibilityLabel("Show introduction")
            }
            Spacer(minLength: 0)
            Menu("File") {
                Button("Import Document JSON…") { importDocument() }
                Button("Export Document JSON…") {
                    attempt { try CatalogFilePanels.write(editor.document.encoded(), name: "\(editor.document.name).json") }
                }
                Divider()
                Button("Import Effect Preset as Layer…") { importPreset() }
            }
            .fixedSize()
            Button("Save", systemImage: "square.and.arrow.down") { _ = saveToMyEffects() }
                .disabled(editor.document.layers.isEmpty || (!unsaved && editing != nil))
                .keyboardShortcut("s", modifiers: .command)
                .help("Save to My Effects")
            useWhenMenu
        }
    }

    private var useWhenMenu: some View {
        Menu {
            ForEach(CustomEffect.assignableTriggers, id: \.self) { trigger in
                Button {
                    guard let id = saveToMyEffects() else { return }
                    if model.assignCustom(id, to: trigger) {
                        notice = "“\(editor.document.name)” now plays \(trigger.eventTitle.lowercased())."
                    }
                } label: {
                    Label(trigger.eventTitle, systemImage: editing?.trigger == trigger ? "checkmark" : trigger.symbol)
                }
            }
            if let editing, editing.trigger != .manual {
                Divider()
                Button("Stop using it automatically") {
                    if model.releaseTrigger(editing.trigger) {
                        notice = "Not used by any event. \(editing.trigger.shortTitle) plays \(model.assignment(for: editing.trigger).title) again."
                    }
                }
            }
            Divider()
            Text("Close and Minimize work best when the last layer makes the window disappear.")
        } label: { Label("Use when…", systemImage: "bolt.fill") }
        .menuStyle(.button).buttonStyle(.borderedProminent).fixedSize()
        .disabled(editor.document.layers.isEmpty)
    }

    /// Saves the document as a new or updated My Effect, keeping its event. Returns its ID.
    @discardableResult
    private func saveToMyEffects() -> UUID? {
        do {
            let document = try editor.document.validated()
            let id = editingID ?? UUID()
            let trigger = store.customEffect(id)?.trigger ?? .manual
            try store.saveCustom(CustomEffect(id: id, document: document, trigger: trigger))
            editingRaw = id.uuidString
            error = nil
            notice = trigger == .manual ? "Saved to My Effects. Choose Use when… to play it automatically." : "Saved."
            model.closeEffectChangedPublic()
            return id
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    private var runButtons: some View {
        HStack(spacing: 6) {
            Button("Run on Window", systemImage: "play.rectangle") {
                runTask?.cancel()
                runTask = Task { await runtime.playDocument(editor.document, windowID: sources.source.windowID) }
            }
            .disabled(runtime.isPlaying || editor.document.layers.isEmpty)
            .help(sources.source == .sample ? "Plays on the frontmost app's window and puts it back. Choose a window as preview source to target it." : "Plays on the window chosen as preview source and puts it back")
            Button { runTask?.cancel(); runtime.stop() } label: { Image(systemName: "stop.fill") }
                .disabled(!runtime.isPlaying).help("Stop & restore desktop").accessibilityLabel("Stop and restore desktop")
        }
        .controlSize(.small)
    }

    // MARK: - Inspector

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(layer.map { $0.name } ?? "Layer").font(.headline).lineLimit(1)
                if let layer { Text(kindTitle(layer)).font(.caption).foregroundStyle(.secondary) }
            }
            Picker("Inspector", selection: $tab) {
                ForEach(StudioInspectorTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            if let layer {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        inspectorContent(layer)
                    }
                    .padding(.trailing, 6)
                }
            } else {
                ContentUnavailableView("No layer selected", systemImage: "square.3.layers.3d",
                                       description: Text("Click a layer in the timeline to edit it."))
            }
        }
        .padding(.leading, 14)
    }

    private func kindTitle(_ layer: StudioLayer) -> String {
        if let builtin = BuiltinLayer(layer.builtin) { return "Built-in · \(builtin.effect.title)" }
        return "Studio · \(EffectCatalog.descriptor(layer.preset.effect).title)"
    }

    private func blurb(_ layer: StudioLayer) -> String {
        BuiltinLayer(layer.builtin)?.effect.blurb ?? EffectCatalog.descriptor(layer.preset.effect).summary
    }

    @ViewBuilder private func inspectorContent(_ layer: StudioLayer) -> some View {
        switch tab {
        case .edit:
            Text(blurb(layer)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("Layer name", text: layerBinding(layer.id, \.name)).textFieldStyle(.roundedBorder)
            Toggle("Enabled", isOn: layerBinding(layer.id, \.enabled))
            Toggle("Play in reverse", isOn: layerBinding(layer.id, \.reversed))
                .help("Plays the layer backwards: a close effect becomes an entrance, a minimize becomes a restore.")
            HStack {
                Text("Starts at (seconds)")
                TextField("Start", value: layerBinding(layer.id, \.start), format: .number).frame(width: 80).textFieldStyle(.roundedBorder)
                Spacer()
                Text("ends \(layer.end.formatted(.number.precision(.fractionLength(2)))) s").font(.caption).foregroundStyle(.secondary)
            }
            if let builtin = BuiltinLayer(layer.builtin) {
                HStack {
                    Text("Duration (seconds)")
                    Spacer()
                    TextField("Duration", value: layerBinding(layer.id, \.preset.duration), format: .number)
                        .frame(width: 80).textFieldStyle(.roundedBorder)
                    Stepper("Duration", value: layerBinding(layer.id, \.preset.duration), in: EffectPreset.durationRange, step: 0.1).labelsHidden()
                }
                Picker("Speed curve", selection: layerBinding(layer.id, \.preset.curve)) {
                    ForEach(AnimationCurve.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Button("Natural duration (\(builtin.naturalDuration.formatted()) s)") {
                    editor.updateLayer(layer.id) { $0.preset.duration = builtin.naturalDuration }
                }
                .controlSize(.small)
                Text("Built-in effects keep their original look; you control when they start, how long they take and their direction.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("Variants").font(.caption)
                    ForEach(EffectCatalog.descriptor(layer.preset.effect).presets, id: \.name) { preset in
                        Button(preset.name) { editor.updateLayer(layer.id) { $0.preset = preset } }.controlSize(.small)
                    }
                }
                PresetParameterControls(preset: layerBinding(layer.id, \.preset))
                Text("Values here are static for the whole layer. Use Keyframes to animate one of them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .keyframes:
            if layer.isBuiltin {
                Text("Built-in effects have no parameters to animate. Change their timing on Edit, or overlap them with a Studio layer.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("A keyframe track replaces one parameter's static value with a curve over the layer's own time (0 = layer start, 1 = layer end).")
                    .font(.caption).foregroundStyle(.secondary)
                trackPicker(layer)
                trackEditor(layer)
            }
        case .advanced:
            if let builtin = BuiltinLayer(layer.builtin) {
                LabeledContent("Engine", value: builtin.effect.badge)
                LabeledContent("Identifier", value: builtin.effect.id)
                if case .close = builtin {
                    Text("Close shaders are GPU-heavy: they are refused when Render Quality disallows expensive effects.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if case .minimize = builtin {
                    Text("Minimize morphs travel to the bottom of the stage, below the window, not to the real Dock.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                LabeledContent("Rendering", value: EffectCatalog.descriptor(layer.preset.effect).rendering.title)
                LabeledContent("Resource class", value: EffectCatalog.descriptor(layer.preset.effect).expensive ? "GPU-heavy" : "Standard")
                Button("Save Layer as \(EffectCatalog.descriptor(layer.preset.effect).title) Preset") {
                    attempt {
                        var preset = layer.preset
                        preset.trigger = store.preset(layer.preset.effect).trigger
                        try store.save(preset); notice = "Preset saved for the Effects library."
                    }
                }
                Menu("Copy / Paste / Export") {
                    Button("Load Saved Effect Preset") { editor.updateLayer(layer.id) { $0.preset = store.preset(layer.preset.effect) } }
                    Button("Export Layer Preset…") {
                        attempt { try CatalogFilePanels.write(layer.preset.encoded(), name: "\(layer.preset.effect.rawValue).json") }
                    }
                    Button("Copy Parameters") { attempt { try PresetClipboard.copy(layer.preset) } }
                    Button("Paste Parameters") {
                        attempt {
                            let preset = try PresetClipboard.paste(into: layer.preset)
                            editor.updateLayer(layer.id) { $0.preset = preset }
                        }
                    }
                }
                .fixedSize()
                Button("Reset Layer Preset", role: .destructive) {
                    editor.updateLayer(layer.id) { $0.preset = EffectPreset(effect: layer.preset.effect) }
                }
            }
            LabeledContent("Shader", value: runtime.shaderStatus).font(.caption)
            Text("On the desktop, Magnet, Gravity, Cube, Orbit and Exposé 3D only run as a single enabled layer.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func trackPicker(_ layer: StudioLayer) -> some View {
        Picker("Parameter", selection: $parameter) {
            ForEach(EffectCatalog.descriptor(layer.preset.effect).parameters) { spec in
                Text(spec.title + (layer.preset.tracks.contains { $0.parameter == spec.id } ? " ◆" : "")).tag(spec.id)
            }
        }
    }

    @ViewBuilder private func trackEditor(_ layer: StudioLayer) -> some View {
        if let track = layer.preset.tracks.first(where: { $0.parameter == parameter }),
           let spec = EffectCatalog.descriptor(layer.preset.effect).parameters.first(where: { $0.id == parameter }) {
            HStack {
                Toggle("Track enabled", isOn: Binding(get: { !track.muted }, set: { value in
                    editor.updateTrack(layer: layer.id, parameter: parameter) { $0.muted = !value }
                }))
                Spacer()
                Button(role: .destructive) { editor.removeTrack(layer: layer.id, parameter: parameter) } label: { Image(systemName: "trash") }
                    .help("Remove parameter track").accessibilityLabel("Remove parameter track")
            }
            StudioCurveView(preset: layer.preset, parameter: parameter).frame(height: 130)
            Button("Add Keyframe at Playhead", systemImage: "diamond") {
                let normalized = min(1, max(0, (time - layer.start) / layer.preset.duration))
                editor.addKeyframe(layer: layer.id, parameter: parameter, time: normalized)
            }
            .disabled(track.keyframes.count >= EffectPreset.maximumKeyframes)
            ForEach(track.keyframes) { key in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Time").font(.caption)
                        TextField("Normalized time", value: keyBinding(layer.id, key.id, \.time, fallback: key.time), format: .number)
                        Text("Value").font(.caption)
                        TextField("Key value", value: keyBinding(layer.id, key.id, \.value, fallback: key.value), format: .number)
                        Button(role: .destructive) {
                            editor.updateTrack(layer: layer.id, parameter: parameter) { $0.keyframes.removeAll { $0.id == key.id } }
                        } label: { Image(systemName: "minus.circle") }
                        .accessibilityLabel("Delete keyframe")
                    }
                    Slider(value: keyBinding(layer.id, key.id, \.time, fallback: key.time), in: 0...1)
                        .accessibilityLabel("Move keyframe time")
                    Slider(value: keyBinding(layer.id, key.id, \.value, fallback: key.value), in: spec.minimum...spec.maximum)
                        .accessibilityLabel("Keyframe value")
                    Picker("Curve to next key", selection: keyBinding(layer.id, key.id, \.curve, fallback: key.curve)) {
                        ForEach(AnimationCurve.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }
                .textFieldStyle(.roundedBorder)
                Divider()
            }
        } else {
            Text("\(EffectCatalog.descriptor(layer.preset.effect).parameters.first { $0.id == parameter }?.title ?? parameter) is static. Add a track to animate it between keyframes.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Add Keyframe Track", systemImage: "plus") { editor.addTrack(layer: layer.id, parameter: parameter) }
            StudioCurveView(preset: layer.preset, parameter: parameter).frame(height: 130)
        }
    }

    // MARK: - Timeline

    private var addLayerMenu: some View {
        Menu {
            Section("Studio effects — editable parameters") {
                ForEach(EffectCategory.allCases, id: \.self) { category in
                    Menu(category.title) {
                        ForEach(EffectCatalog.effects.filter { $0.category == category }) { effect in
                            Button(effect.title) { addLayer(StudioLayer(preset: store.preset(effect.id))) }
                        }
                    }
                }
            }
            Section("Built-in effects — original engines") {
                Menu("Close effects (\(CloseEffect.allCases.count))") {
                    ForEach(CloseEffect.allCases, id: \.self) { effect in
                        Button(effect.title) { addLayer(BuiltinLayer.close(effect).makeLayer()) }
                    }
                }
                Menu("Entrances (\(WobbleEntrance.allCases.count))") {
                    ForEach(WobbleEntrance.allCases, id: \.self) { entrance in
                        Button(entrance.title) { addLayer(BuiltinLayer.entrance(entrance).makeLayer()) }
                    }
                }
                Menu("Minimize morphs (\(DockMorphStyle.allCases.count))") {
                    ForEach(DockMorphStyle.allCases, id: \.self) { style in
                        Button(style.title) { addLayer(BuiltinLayer.minimize(style).makeLayer()) }
                    }
                }
            }
        } label: { Label("Add Layer", systemImage: "plus") }
        .disabled(editor.document.layers.count >= StudioDocument.maximumLayers)
    }

    /// New layers start where the previous ones end, so adding several builds a sequence.
    private func addLayer(_ new: StudioLayer) {
        var layer = new
        let after = editor.document.layers.map(\.end).max() ?? 0
        layer.start = min(max(0, StudioDocument.maximumDuration - layer.duration), after)
        let added = layer
        let ok = editor.perform {
            $0.layers.append(added)
            $0.duration = max($0.duration, added.end)
        }
        if ok { selectedLayer = layer.id; tab = .edit }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Timeline").font(.headline)
                addLayerMenu.fixedSize()
                Button {
                    if let selectedLayer { editor.removeLayer(selectedLayer) }
                } label: { Image(systemName: "minus") }
                .disabled(layer == nil).accessibilityLabel("Remove selected layer").help("Remove selected layer")
                Spacer()
                Text("Total length (s)").font(.caption)
                TextField("Document duration", value: Binding(get: { editor.document.duration }, set: { value in
                    editor.perform { $0.duration = value }
                }), format: .number)
                .frame(width: 65).textFieldStyle(.roundedBorder)
                Button("Fit") {
                    let end = editor.document.layers.map(\.end).max() ?? editor.document.duration
                    editor.perform { $0.duration = max(0.1, end) }
                }
                .controlSize(.small).help("Shorten the document to end with its last layer")
            }
            ScrollView {
                VStack(spacing: 3) {
                    timelineRuler
                    ForEach(editor.document.layers) { layer in timelineRow(layer) }
                }
            }
            Text("Click a bar to select a layer, click the ruler to move the playhead. ◆ marks keyframes, ↺ a reversed layer.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var timelineRuler: some View {
        HStack(spacing: 8) {
            Text("LAYERS · \(editor.document.layers.count)").font(.caption2).foregroundStyle(.secondary).frame(width: 155, alignment: .leading)
            GeometryReader { geometry in
                Canvas { context, size in
                    for index in 0...4 {
                        let x = size.width * Double(index) / 4
                        context.draw(Text("\((editor.document.duration * Double(index) / 4).formatted(.number.precision(.fractionLength(1)))) s").font(.caption2).foregroundColor(.secondary),
                                     at: CGPoint(x: min(size.width - 16, max(16, x)), y: size.height / 2))
                    }
                    let x = size.width * time / editor.document.duration
                    context.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)), with: .color(.accentColor))
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    time = min(editor.document.duration, max(0, value.location.x / max(1, geometry.size.width) * editor.document.duration))
                })
                .frame(width: geometry.size.width)
            }
            .frame(height: 18)
        }
    }

    private func timelineRow(_ layer: StudioLayer) -> some View {
        HStack(spacing: 8) {
            Toggle("Enable \(layer.name)", isOn: layerBinding(layer.id, \.enabled)).labelsHidden().toggleStyle(.checkbox)
            Button { selectedLayer = layer.id } label: {
                HStack(spacing: 4) {
                    Image(systemName: layer.isBuiltin ? "flame" : "slider.horizontal.3").font(.caption2).foregroundStyle(.secondary)
                    Text(layer.name).lineLimit(1)
                    if layer.reversed { Text("↺").foregroundStyle(.secondary) }
                }
                .frame(width: 125, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            GeometryReader { geometry in
                let width = geometry.size.width
                let x = width * layer.start / editor.document.duration
                let extent = width * layer.duration / editor.document.duration
                ZStack(alignment: .leading) {
                    Rectangle().fill(.primary.opacity(0.035))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(layer.enabled ? (layer.isBuiltin ? Color.orange : Color.accentColor).opacity(selectedLayer == layer.id ? 0.75 : 0.38) : Color.gray.opacity(0.3))
                        .frame(width: max(2, extent)).offset(x: x)
                    ForEach(layer.preset.tracks.filter { !$0.muted && !layer.isBuiltin }) { track in
                        ForEach(track.keyframes) { key in
                            Image(systemName: "diamond.fill").font(.system(size: 6)).foregroundStyle(.primary.opacity(0.8))
                                .offset(x: x + extent * key.time - 3)
                        }
                    }
                    Rectangle().fill(Color.accentColor).frame(width: 1).offset(x: width * time / editor.document.duration)
                }
                .contentShape(Rectangle())
                .onTapGesture { selectedLayer = layer.id }
                .accessibilityLabel("\(layer.name), starts \(layer.start) seconds, duration \(layer.duration) seconds")
            }
            .frame(height: 26)
        }
        .padding(3)
        .background(selectedLayer == layer.id ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 4))
    }

    private func layerBinding<T>(_ id: UUID, _ path: WritableKeyPath<StudioLayer, T>) -> Binding<T> {
        // The binding is created only for a currently existing layer; its snapshot survives removal during layout.
        let snapshot = editor.document.layers.first { $0.id == id }!
        return Binding(get: { (editor.document.layers.first { $0.id == id } ?? snapshot)[keyPath: path] }, set: { value in
            editor.updateLayer(id) { $0[keyPath: path] = value }
        })
    }

    private func keyBinding<T>(_ layerID: UUID, _ keyID: UUID, _ path: WritableKeyPath<AnimationKeyframe, T>, fallback: T) -> Binding<T> {
        let parameter = parameter
        return Binding(get: {
            editor.document.layers.first(where: { $0.id == layerID })?.preset.tracks.first(where: { $0.parameter == parameter })?
                .keyframes.first(where: { $0.id == keyID })?[keyPath: path] ?? fallback
        }, set: { value in
            editor.updateTrack(layer: layerID, parameter: parameter) { track in
                if let index = track.keyframes.firstIndex(where: { $0.id == keyID }) { track.keyframes[index][keyPath: path] = value }
            }
        })
    }

    private func attempt(_ operation: () throws -> Void) {
        do { try operation(); error = nil } catch { self.error = error.localizedDescription }
    }

    private func importDocument() {
        attempt {
            guard let data = try CatalogFilePanels.read() else { return }
            newDocument(try StudioDocument.decode(data))
        }
    }

    private func importPreset() {
        attempt {
            guard let data = try CatalogFilePanels.read() else { return }
            addLayer(StudioLayer(preset: try EffectPreset.decode(data)))
        }
    }
}

/// Draws the actual Core evaluator, including outgoing easing and muted/static tracks.
struct StudioCurveView: View {
    let preset: EffectPreset
    let parameter: String

    var body: some View {
        Canvas { context, size in
            guard let spec = EffectCatalog.descriptor(preset.effect).parameters.first(where: { $0.id == parameter }) else { return }
            let inset: CGFloat = 8
            let width = max(1, size.width - 2 * inset)
            let height = max(1, size.height - 2 * inset)
            var grid = Path()
            for index in 0...4 {
                let fraction = CGFloat(index) / 4
                grid.move(to: CGPoint(x: inset + width * fraction, y: inset))
                grid.addLine(to: CGPoint(x: inset + width * fraction, y: inset + height))
                grid.move(to: CGPoint(x: inset, y: inset + height * fraction))
                grid.addLine(to: CGPoint(x: inset + width, y: inset + height * fraction))
            }
            context.stroke(grid, with: .color(.secondary.opacity(0.15)), lineWidth: 0.5)
            var curve = Path()
            for index in 0...120 {
                let t = Double(index) / 120
                let value = preset.value(parameter, at: t * preset.duration)
                let y = (value - spec.minimum) / max(0.000001, spec.maximum - spec.minimum)
                let point = CGPoint(x: inset + width * t, y: inset + height * (1 - y))
                if index == 0 { curve.move(to: point) } else { curve.addLine(to: point) }
            }
            context.stroke(curve, with: .color(.accentColor), lineWidth: 2)
            if let track = preset.tracks.first(where: { $0.parameter == parameter && !$0.muted }) {
                for key in track.keyframes {
                    let y = (key.value - spec.minimum) / max(0.000001, spec.maximum - spec.minimum)
                    let rect = CGRect(x: inset + width * key.time - 3, y: inset + height * (1 - y) - 3, width: 6, height: 6)
                    context.fill(Path(ellipseIn: rect), with: .color(.primary))
                }
            }
        }
        .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel("Evaluated \(parameter) curve over \(preset.duration) seconds")
        .accessibilityValue("Start \(preset.value(parameter, at: 0)), end \(preset.value(parameter, at: preset.duration))")
    }
}