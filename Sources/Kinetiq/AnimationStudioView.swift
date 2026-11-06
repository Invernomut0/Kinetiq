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

@MainActor
struct AnimationStudioView: View {
    @ObservedObject private var store = CatalogStore.shared
    @ObservedObject private var runtime = CatalogRuntime.shared
    @StateObject private var editor: StudioEditorModel
    @State private var selectedLayer: UUID?
    @State private var parameter = "amplitude"
    @State private var tab: EffectDetailTab = .preview
    @State private var windowID: CGWindowID?
    @State private var time = 0.0
    @State private var playing = false
    @State private var error: String?
    @State private var notice: String?
    @State private var runTask: Task<Void, Never>?

    init() {
        let document = CatalogStore.shared.document
        _editor = StateObject(wrappedValue: StudioEditorModel(document: document))
        _selectedLayer = State(initialValue: document.layers.first?.id)
    }

    private var layer: StudioLayer? { editor.document.layers.first { $0.id == selectedLayer } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            toolbar
            if let message = error ?? editor.errorMessage ?? runtime.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
            if let notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            HSplitView {
                VStack(alignment: .leading, spacing: 10) {
                    CatalogWindowPicker(selection: $windowID)
                    CapturedEffectPreview(document: editor.document, time: time, windowID: windowID)
                    transport
                    Text("Panel preview only. Run on Window is a separate, restoring desktop action.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
                inspector.frame(minWidth: 280, idealWidth: 330, maxWidth: 430, maxHeight: .infinity)
            }
            Divider()
            timeline.frame(minHeight: 160, idealHeight: 210, maxHeight: 260)
        }
        .padding(16)
        .task(id: playing) {
            guard playing else { return }
            let startTime = time
            let origin = ProcessInfo.processInfo.systemUptime
            do {
                // One finite structured loop, at most ten preview requests per second.
                while !Task.isCancelled && playing {
                    try await Task.sleep(for: .milliseconds(100))
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
        .onDisappear { playing = false; runTask?.cancel(); runtime.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            if isManagementWindow(note) { playing = false; runTask?.cancel(); runtime.stop() }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            TextField("Document name", text: Binding(get: { editor.document.name }, set: { value in
                editor.perform { $0.name = value }
            }))
            .font(.headline).textFieldStyle(.roundedBorder).frame(maxWidth: 230)
            Button { playing = false; editor.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(editor.undoCount == 0).help("Undo").accessibilityLabel("Undo studio edit")
            Button { playing = false; editor.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(editor.redoCount == 0).help("Redo").accessibilityLabel("Redo studio edit")
            Spacer(minLength: 0)
            Menu("Presets") {
                if let layer {
                    ForEach(EffectCatalog.descriptor(layer.preset.effect).presets, id: \.name) { preset in
                        Button(preset.name) { editor.updateLayer(layer.id) { $0.preset = preset } }
                    }
                    Button("Load Saved Effect Preset") { editor.updateLayer(layer.id) { $0.preset = store.preset(layer.preset.effect) } }
                    Button("Save Layer as Effect Preset") { attempt { try store.save(layer.preset); notice = "Effect preset saved." } }
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
                    Divider()
                }
                Button("Import Effect Preset…") { importPreset() }
                Button("Import Document JSON…") { importDocument() }
                Button("Export Document JSON…") {
                    attempt { try CatalogFilePanels.write(editor.document.encoded(), name: "animation-studio.json") }
                }
            }
            Button("Save Document") {
                attempt {
                    let validated = try editor.document.validated()
                    let previous = store.document
                    store.document = validated
                    do { try store.saveDocument() } catch { store.document = previous; throw error }
                    notice = "Document saved."
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var transport: some View {
        HStack(spacing: 8) {
            Button {
                if time >= editor.document.duration { time = 0 }
                playing.toggle()
            } label: { Image(systemName: playing ? "pause.fill" : "play.fill") }
                .disabled(windowID == nil || editor.document.layers.isEmpty)
                .help(playing ? "Pause panel preview" : "Play panel preview")
                .accessibilityLabel(playing ? "Pause panel preview" : "Play panel preview")
            Button { playing = false; time = 0 } label: { Image(systemName: "backward.end.fill") }
                .help("Seek to start").accessibilityLabel("Seek to start")
            Text("\(time, specifier: "%.2f") / \(editor.document.duration, specifier: "%.2f") s")
                .font(.caption.monospacedDigit())
            Spacer(minLength: 0)
            Button("Run on Window") {
                playing = false
                runTask?.cancel()
                runTask = Task { await runtime.playDocument(editor.document, windowID: windowID) }
            }
            .disabled(windowID == nil || runtime.isPlaying || editor.document.layers.isEmpty)
            Button { runTask?.cancel(); runtime.stop() } label: { Image(systemName: "stop.fill") }
                .disabled(!runtime.isPlaying).help("Stop & restore desktop").accessibilityLabel("Stop and restore desktop")
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(layer.map { EffectCatalog.descriptor($0.preset.effect).title } ?? "Layer Inspector").font(.headline)
            Picker("Inspector", selection: $tab) {
                ForEach(EffectDetailTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            if let layer {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        inspectorContent(layer)
                    }
                    .padding(.trailing, 6)
                }
            } else {
                ContentUnavailableView("No layer selected", systemImage: "square.3.layers.3d",
                                       description: Text("Add an effect from the timeline menu to start composing."))
            }
        }
        .padding(.leading, 14)
    }

    @ViewBuilder private func inspectorContent(_ layer: StudioLayer) -> some View {
        switch tab {
        case .preview:
            Text(EffectCatalog.descriptor(layer.preset.effect).summary).font(.callout).foregroundStyle(.secondary)
            LabeledContent("Starts", value: "\(layer.start.formatted()) s")
            LabeledContent("Ends", value: "\((layer.start + layer.preset.duration).formatted()) s")
            Text("The preview at left samples the entire document at the playhead. Disabled layers are excluded.")
                .font(.caption).foregroundStyle(.secondary)
            trackPicker(layer)
            StudioCurveView(preset: layer.preset, parameter: parameter)
                .frame(height: 130)
        case .parameters:
            TextField("Layer name", text: layerBinding(layer.id, \.name))
            Toggle("Enabled", isOn: layerBinding(layer.id, \.enabled))
            HStack {
                Text("Start (seconds)")
                TextField("Start", value: layerBinding(layer.id, \.start), format: .number).frame(width: 80)
            }
            PresetParameterControls(preset: layerBinding(layer.id, \.preset))
            Divider()
            trackPicker(layer)
            trackEditor(layer)
        case .triggers:
            Picker("Trigger", selection: Binding(get: { layer.preset.trigger }, set: { value in
                editor.updateLayer(layer.id) { $0.preset.trigger = value }
            })) {
                ForEach(EffectCatalog.descriptor(layer.preset.effect).triggers, id: \.self) { Text($0.title).tag($0) }
            }
            Text("Layer playback uses document timing. Save Layer as Effect Preset persists this trigger for the effect; saving the document preserves layer trigger metadata.")
                .font(.caption).foregroundStyle(.secondary)
        case .performance:
            LabeledContent("Rendering", value: EffectCatalog.descriptor(layer.preset.effect).rendering.title)
            LabeledContent("Shader", value: runtime.shaderStatus)
            PerformanceView().frame(height: 520)
        case .reset:
            Text("Reset only the selected layer’s effect preset. Layer name and start are preserved. This edit can be undone.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Reset Layer Preset", role: .destructive) {
                editor.updateLayer(layer.id) { $0.preset = EffectPreset(effect: layer.preset.effect) }
            }
        }
    }

    private func trackPicker(_ layer: StudioLayer) -> some View {
        Picker("Parameter Track", selection: $parameter) {
            ForEach(EffectCatalog.descriptor(layer.preset.effect).parameters) { spec in
                Text(spec.title).tag(spec.id)
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
            Text("Key time is normalized (0–1). Curve applies to the outgoing segment.")
                .font(.caption).foregroundStyle(.secondary)
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
                    Picker("Outgoing Curve", selection: keyBinding(layer.id, key.id, \.curve, fallback: key.curve)) {
                        ForEach(AnimationCurve.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }
                .textFieldStyle(.roundedBorder)
                Divider()
            }
            Button("Add Keyframe at Playhead", systemImage: "diamond") {
                let normalized = min(1, max(0, (time - layer.start) / layer.preset.duration))
                editor.addKeyframe(layer: layer.id, parameter: parameter, time: normalized)
            }
            .disabled(track.keyframes.count >= EffectPreset.maximumKeyframes)
        } else {
            Text("This parameter currently uses its static value.").font(.caption).foregroundStyle(.secondary)
            Button("Add Parameter Track", systemImage: "plus") { editor.addTrack(layer: layer.id, parameter: parameter) }
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Timeline").font(.headline)
                Menu {
                    ForEach(EffectCategory.allCases, id: \.self) { category in
                        Menu(category.title) {
                            ForEach(EffectCatalog.effects.filter { $0.category == category }) { effect in
                                Button(effect.title) {
                                    selectedLayer = editor.addLayer(store.preset(effect.id), at: min(time, StudioDocument.maximumDuration - store.preset(effect.id).duration))
                                    tab = .parameters
                                }
                            }
                        }
                    }
                } label: { Label("Add Layer", systemImage: "plus") }
                .disabled(editor.document.layers.count >= StudioDocument.maximumLayers)
                Button {
                    if let selectedLayer { editor.removeLayer(selectedLayer) }
                } label: { Image(systemName: "minus") }
                .disabled(layer == nil).accessibilityLabel("Remove selected layer")
                Spacer()
                Text("Duration (s)").font(.caption)
                TextField("Document duration", value: Binding(get: { editor.document.duration }, set: { value in
                    editor.perform { $0.duration = value }
                }), format: .number)
                .frame(width: 65).textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("Seek").font(.caption).frame(width: 45, alignment: .leading)
                Slider(value: Binding(get: { time }, set: { playing = false; time = $0 }), in: 0...editor.document.duration)
                    .accessibilityLabel("Scrub document timeline")
            }
            if editor.document.layers.isEmpty {
                Text("No layers. Add an effect to create a timeline.").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 3) {
                        timelineRuler
                        ForEach(editor.document.layers) { layer in timelineRow(layer) }
                    }
                }
            }
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
            try store.importPreset(data)
            selectedLayer = editor.addLayer(preset)
            tab = .parameters
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