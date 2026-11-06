// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import KinetiqCore
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
    case edit = "Edit", keyframes = "Keyframes", assign = "Use It", advanced = "Advanced"
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
    @State private var selectedLayer: UUID?
    @State private var parameter = "amplitude"
    @State private var tab: StudioInspectorTab = .edit
    @State private var time = 0.0
    @State private var playing = false
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
    private var unsaved: Bool { editor.document != store.document }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            toolbar
            if !introDismissed { intro }
            if let message = error ?? editor.errorMessage ?? runtime.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
            if let notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            if editor.document.layers.isEmpty {
                emptyState
            } else {
                HSplitView {
                    VStack(alignment: .leading, spacing: 10) {
                        EffectPreviewPlayer(subject: .document(editor.document), settings: model.settings,
                                            externalTime: $time, autoplay: false)
                        transport
                    }
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                    inspector.frame(minWidth: 300, idealWidth: 340, maxWidth: 440, maxHeight: .infinity)
                }
                Divider()
                timeline.frame(minHeight: 170, idealHeight: 220, maxHeight: 280)
            }
        }
        .padding(16)
        .task(id: playing) {
            guard playing else { return }
            let startTime = time
            let origin = ProcessInfo.processInfo.systemUptime
            do {
                // One finite structured loop, at most twenty playhead updates per second.
                while !Task.isCancelled && playing {
                    try await Task.sleep(for: .milliseconds(50))
                    try Task.checkCancellation()
                    time = min(editor.document.duration, startTime + ProcessInfo.processInfo.systemUptime - origin)
                    if time >= editor.document.duration { playing = false; break }
                }
            } catch { /* SwiftUI cancels playback when paused, hidden or closed. */ }
        }
        .onChange(of: editor.document) { _, document in
            if !document.layers.contains(where: { $0.id == selectedLayer }) { selectedLayer = document.layers.first?.id }
            time = min(time, document.duration)
            notice = nil
        }
        .onChange(of: selectedLayer) { _, _ in
            parameter = layer?.preset.tracks.first?.parameter ?? "amplitude"
        }
        .onChange(of: launch.preset, initial: true) { _, preset in
            guard let preset else { return }
            launch.preset = nil
            addLayer(preset)
            notice = "\(EffectCatalog.descriptor(preset.effect).title) added as a layer."
        }
        .onDisappear { playing = false; runTask?.cancel(); runtime.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            if isManagementWindow(note) { playing = false; runTask?.cancel(); runtime.stop() }
        }
    }

    // MARK: - Guidance

    private var intro: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "lightbulb").font(.title2).foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 6) {
                Text("How the Studio works").font(.headline)
                Text("1. **Add Layer** picks an effect and places it on the timeline. Layers play in order on the same window.\n2. Select a layer to **edit its parameters**; **Keyframes** let a value change while the effect plays.\n3. **Save Document** keeps your composition. To make a layer react to a window event, open **Use It** and choose the event.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button { introDismissed = true } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                .accessibilityLabel("Dismiss introduction")
        }
        .padding(14)
        .background(.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "square.3.layers.3d").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Start with a layer").font(.title2.bold())
            Text("A layer is one effect with its own parameters and timing. Combine several to build your own transition.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
            HStack {
                addLayerMenu.buttonStyle(.borderedProminent)
                Button("Load an Example", systemImage: "wand.and.stars") { loadExample() }
                Button("Import Document…") { importDocument() }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadExample() {
        var ripple = store.preset(.ripple)
        ripple.name = "Ripple in"
        ripple.duration = 1.2
        var fold = store.preset(.fold)
        fold.name = "Fold away"
        fold.duration = 1.4
        fold.tracks = [AnimationTrack(parameter: "angle", keyframes: [
            AnimationKeyframe(time: 0, value: 20, curve: .easeIn), AnimationKeyframe(time: 1, value: 160, curve: .easeOut)])]
        let document = StudioDocument(name: "Example — Ripple then Fold", duration: 3,
                                      layers: [StudioLayer(preset: ripple, start: 0), StudioLayer(preset: fold, start: 1.4)])
        editor.perform { $0 = document }
        selectedLayer = document.layers.first?.id
        time = 0
        notice = "Example loaded. Press Play, then try changing the Fold angle keyframes."
    }

    // MARK: - Toolbar and transport

    private var toolbar: some View {
        HStack(spacing: 8) {
            TextField("Document name", text: Binding(get: { editor.document.name }, set: { value in
                editor.perform { $0.name = value }
            }))
            .font(.headline).textFieldStyle(.roundedBorder).frame(maxWidth: 230)
            Button { playing = false; editor.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .disabled(editor.undoCount == 0).help("Undo").accessibilityLabel("Undo studio edit")
            Button { playing = false; editor.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                .disabled(editor.redoCount == 0).help("Redo").accessibilityLabel("Redo studio edit")
            if !introDismissed { EmptyView() } else {
                Button { introDismissed = false } label: { Image(systemName: "questionmark.circle") }
                    .buttonStyle(.borderless).help("Show how the Studio works").accessibilityLabel("Show introduction")
            }
            Spacer(minLength: 0)
            Menu("File") {
                Button("Import Document JSON…") { importDocument() }
                Button("Export Document JSON…") {
                    attempt { try CatalogFilePanels.write(editor.document.encoded(), name: "animation-studio.json") }
                }
                Divider()
                Button("Import Effect Preset as Layer…") { importPreset() }
                Divider()
                Button("New Empty Document") { editor.perform { $0 = StudioDocument() }; time = 0 }
            }
            .fixedSize()
            Button(unsaved ? "Save Document" : "Saved") {
                attempt {
                    let validated = try editor.document.validated()
                    let previous = store.document
                    store.document = validated
                    do { try store.saveDocument() } catch { store.document = previous; throw error }
                    notice = "Document saved."
                }
            }
            .buttonStyle(.borderedProminent).disabled(!unsaved)
        }
    }

    private var transport: some View {
        HStack(spacing: 8) {
            Button {
                if time >= editor.document.duration { time = 0 }
                playing.toggle()
            } label: { Image(systemName: playing ? "pause.fill" : "play.fill").frame(width: 14) }
                .disabled(editor.document.layers.isEmpty)
                .help(playing ? "Pause" : "Play the whole document")
                .accessibilityLabel(playing ? "Pause panel preview" : "Play panel preview")
            Button { playing = false; time = 0 } label: { Image(systemName: "backward.end.fill") }
                .help("Back to start").accessibilityLabel("Seek to start")
            Spacer(minLength: 0)
            Button("Run on Window", systemImage: "play.rectangle") {
                playing = false
                runTask?.cancel()
                runTask = Task { await runtime.playDocument(editor.document, windowID: sources.source.windowID) }
            }
            .disabled(runtime.isPlaying || editor.document.layers.isEmpty)
            .help(sources.source == .sample ? "Plays on the frontmost app's window and restores it. Choose a window as preview source to target it." : "Plays on the window chosen as preview source and restores it")
            Button { runTask?.cancel(); runtime.stop() } label: { Image(systemName: "stop.fill") }
                .disabled(!runtime.isPlaying).help("Stop & restore desktop").accessibilityLabel("Stop and restore desktop")
        }
    }

    // MARK: - Inspector

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(layer.map { $0.name } ?? "Layer").font(.headline).lineLimit(1)
                if let layer { Text(EffectCatalog.descriptor(layer.preset.effect).title).font(.caption).foregroundStyle(.secondary) }
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

    @ViewBuilder private func inspectorContent(_ layer: StudioLayer) -> some View {
        switch tab {
        case .edit:
            Text(EffectCatalog.descriptor(layer.preset.effect).summary).font(.callout).foregroundStyle(.secondary)
            TextField("Layer name", text: layerBinding(layer.id, \.name)).textFieldStyle(.roundedBorder)
            Toggle("Enabled", isOn: layerBinding(layer.id, \.enabled))
            HStack {
                Text("Starts at (seconds)")
                TextField("Start", value: layerBinding(layer.id, \.start), format: .number).frame(width: 80).textFieldStyle(.roundedBorder)
                Spacer()
                Text("ends \((layer.start + layer.preset.duration).formatted()) s").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("Variants").font(.caption)
                ForEach(EffectCatalog.descriptor(layer.preset.effect).presets, id: \.name) { preset in
                    Button(preset.name) { editor.updateLayer(layer.id) { $0.preset = preset } }.controlSize(.small)
                }
            }
            PresetParameterControls(preset: layerBinding(layer.id, \.preset))
            Text("Values here are static for the whole layer. Use Keyframes to animate one of them.")
                .font(.caption).foregroundStyle(.secondary)
        case .keyframes:
            Text("A keyframe track replaces one parameter's static value with a curve over the layer's own time (0 = layer start, 1 = layer end).")
                .font(.caption).foregroundStyle(.secondary)
            trackPicker(layer)
            trackEditor(layer)
        case .assign:
            let effect = LibraryEffect.catalog(layer.preset.effect)
            let events = effect.automaticTriggers
            Text("Saving a layer as the effect's preset makes it what Kinetiq plays for that effect, including in the Effects library.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Save Layer as \(EffectCatalog.descriptor(layer.preset.effect).title) Preset") {
                attempt {
                    var preset = layer.preset
                    preset.trigger = store.preset(layer.preset.effect).trigger
                    try store.save(preset); notice = "Preset saved."
                }
            }
            if events.isEmpty {
                Text("This effect has no automatic window event; run it from the menu bar.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Play it automatically:").font(.subheadline)
                ForEach(events, id: \.self) { trigger in
                    let active = model.isAssigned(effect, to: trigger)
                    Button(active ? "Active \(trigger.eventTitle.lowercased())" : "Use \(trigger.eventTitle.lowercased())",
                           systemImage: active ? "checkmark.circle.fill" : trigger.symbol) {
                        attempt {
                            var preset = layer.preset
                            preset.trigger = trigger
                            try store.save(preset)
                            if model.assign(effect, to: trigger) { notice = "\(effect.title) now plays \(trigger.eventTitle.lowercased())." }
                        }
                    }
                    .disabled(active)
                }
                Text("Saving the document alone does not change any window event.").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
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
        case .advanced:
            LabeledContent("Rendering", value: EffectCatalog.descriptor(layer.preset.effect).rendering.title)
            LabeledContent("Resource class", value: EffectCatalog.descriptor(layer.preset.effect).expensive ? "GPU-heavy" : "Standard")
            LabeledContent("Shader", value: runtime.shaderStatus)
            Text("Physics (Magnet, Gravity) and overview effects (Cube, Orbit, Exposé 3D) run on the desktop only as a single enabled layer.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Button("Reset Layer Preset", role: .destructive) {
                editor.updateLayer(layer.id) { $0.preset = EffectPreset(effect: layer.preset.effect) }
            }
            Text("Restores this layer's defaults. Name and start time are kept; undo is available.")
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
            ForEach(EffectCategory.allCases, id: \.self) { category in
                Section(category.title) {
                    ForEach(EffectCatalog.effects.filter { $0.category == category }) { effect in
                        Button(effect.title) { addLayer(store.preset(effect.id)) }
                            .help(effect.summary)
                    }
                }
            }
        } label: { Label("Add Layer", systemImage: "plus") }
        .disabled(editor.document.layers.count >= StudioDocument.maximumLayers)
    }

    private func addLayer(_ preset: EffectPreset) {
        let start = min(time, max(0, StudioDocument.maximumDuration - preset.duration))
        selectedLayer = editor.addLayer(preset, at: start)
        tab = .edit
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
                Text("Duration (s)").font(.caption)
                TextField("Document duration", value: Binding(get: { editor.document.duration }, set: { value in
                    editor.perform { $0.duration = value }
                }), format: .number)
                .frame(width: 65).textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("Playhead").font(.caption).frame(width: 58, alignment: .leading)
                Slider(value: Binding(get: { time }, set: { playing = false; time = $0 }), in: 0...editor.document.duration)
                    .accessibilityLabel("Scrub document timeline")
                Text("\(time, specifier: "%.2f") s").font(.caption.monospacedDigit()).frame(width: 52, alignment: .trailing)
            }
            ScrollView {
                VStack(spacing: 3) {
                    timelineRuler
                    ForEach(editor.document.layers) { layer in timelineRow(layer) }
                }
            }
            Text("Click a bar to select a layer. Bars show when each layer plays; diamonds mark keyframes.")
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
                }
                .frame(width: geometry.size.width)
            }
            .frame(height: 18)
        }
    }

    private func timelineRow(_ layer: StudioLayer) -> some View {
        HStack(spacing: 8) {
            Toggle("Enable \(layer.name)", isOn: layerBinding(layer.id, \.enabled)).labelsHidden().toggleStyle(.checkbox)
            Button { selectedLayer = layer.id } label: {
                Text(layer.name).lineLimit(1).frame(width: 125, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            GeometryReader { geometry in
                let width = geometry.size.width
                let x = width * layer.start / editor.document.duration
                let extent = width * layer.preset.duration / editor.document.duration
                ZStack(alignment: .leading) {
                    Rectangle().fill(.primary.opacity(0.035))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(layer.enabled ? Color.accentColor.opacity(selectedLayer == layer.id ? 0.75 : 0.38) : Color.gray.opacity(0.3))
                        .frame(width: max(2, extent)).offset(x: x)
                    ForEach(layer.preset.tracks.filter { !$0.muted }) { track in
                        ForEach(track.keyframes) { key in
                            Image(systemName: "diamond.fill").font(.system(size: 6)).foregroundStyle(.primary.opacity(0.8))
                                .offset(x: x + extent * key.time - 3)
                        }
                    }
                    Rectangle().fill(.primary).frame(width: 1).offset(x: width * time / editor.document.duration)
                }
                .contentShape(Rectangle())
                .onTapGesture { selectedLayer = layer.id }
                .accessibilityLabel("\(layer.name), starts \(layer.start) seconds, duration \(layer.preset.duration) seconds")
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
        playing = false
        do { try operation(); error = nil } catch { self.error = error.localizedDescription }
    }

    private func importDocument() {
        attempt {
            guard let data = try CatalogFilePanels.read() else { return }
            let document = try StudioDocument.decode(data)
            editor.perform { $0 = document }
            time = 0
            selectedLayer = document.layers.first?.id
        }
    }

    private func importPreset() {
        attempt {
            guard let data = try CatalogFilePanels.read() else { return }
            let preset = try EffectPreset.decode(data)
            addLayer(preset)
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