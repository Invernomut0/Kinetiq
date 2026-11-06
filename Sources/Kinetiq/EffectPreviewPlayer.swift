// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import KinetiqCore
import SwiftUI

/// The preview source chosen once and shared by every effect page and the Studio.
@MainActor
final class PreviewSourceStore: ObservableObject {
    static let shared = PreviewSourceStore()
    @Published var source: PreviewSource = .sample
    @Published private(set) var windows: [ManagedWindow] = []

    func refresh() {
        windows = CatalogRuntime.shared.availableWindows()
        if let id = source.windowID, !windows.contains(where: { $0.id == id }) { source = .sample }
    }
}

/// Lets the Effects library hand a preset to the Studio ("Open in Animation Studio").
@MainActor
final class StudioLaunchRequest: ObservableObject {
    static let shared = StudioLaunchRequest()
    @Published var preset: EffectPreset?
}

/// What the player shows: one library effect (with an optional edited preset) or a Studio document.
enum PreviewSubject: Equatable {
    case effect(LibraryEffect, EffectPreset?)
    case document(StudioDocument)
}

private struct StaticPreviewRequest: Equatable {
    let subject: PreviewSubject
    let source: PreviewSource
    let time: Double
    let active: Bool
}

/// Autoplaying, loopable preview of any effect on the sample window or a real one.
/// Rendering is offscreen and read-only: no window is moved, closed or minimized.
@MainActor
struct EffectPreviewPlayer: View {
    let subject: PreviewSubject
    let settings: Settings
    /// Studio drives its own playhead; the library lets the player own it.
    var externalTime: Binding<Double>?
    var showsSourcePicker = true
    var autoplay = true
    /// Where the playhead starts when the player owns it (e.g. mid-animation for overview layouts).
    var startTime: Double?

    @ObservedObject private var sources = PreviewSourceStore.shared
    @State private var renderer = OriginalPreviewRenderer()
    @State private var ownTime = 0.0
    @State private var playing = false
    @State private var image: NSImage?
    @State private var error: String?
    @State private var rendering = false
    @State private var visible = true
    @State private var revision = 0
    /// One render at a time; a request arriving mid-render is kept and rendered afterwards.
    @State private var pendingTime: Double?

    private var time: Binding<Double> { externalTime ?? $ownTime }

    private var duration: Double {
        switch subject {
        case .effect(let effect, let preset):
            return OriginalPreviewRenderer.timelineSeconds(effect: effect, preset: preset, settings: settings)
        case .document(let document): return max(0.1, document.duration)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                PreviewBackdrop()
                if let image {
                    Image(nsImage: image).resizable().scaledToFit().padding(10)
                        .accessibilityLabel("Effect preview frame")
                } else if error == nil {
                    VStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Rendering preview…").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle").font(.title2).foregroundStyle(.orange)
                        Text(error).font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
                            .textSelection(.enabled).frame(maxWidth: 360)
                        Button("Try Again") { self.error = nil; revision += 1 }.controlSize(.small)
                    }
                    .padding()
                }
                if rendering, image != nil {
                    ProgressView().controlSize(.mini).padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .frame(minHeight: 220, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.08)))
            controls
        }
        .task(id: playing && visible) {
            guard playing, visible else { return }
            await playbackLoop()
        }
        .task(id: StaticPreviewRequest(subject: subject, source: sources.source, time: time.wrappedValue,
                                       active: !playing && visible)) {
            guard !playing, visible else { return }
            do {
                try await Task.sleep(for: .milliseconds(40))
                try Task.checkCancellation()
            } catch { return /* superseded by a newer request before it started */ }
            // Not cancellable from here on: the render queue keeps the newest request instead.
            await Task { @MainActor in await renderFrame(at: time.wrappedValue) }.value
        }
        .task(id: revision) { if revision > 0, !playing { await renderFrame(at: time.wrappedValue) } }
        .onAppear {
            visible = true
            if sources.windows.isEmpty { sources.refresh() }
            if let startTime, externalTime == nil { ownTime = min(duration, max(0, startTime)) }
            if autoplay && externalTime == nil { playing = true }
        }
        .onDisappear { visible = false; playing = false; renderer.cancel() }
        .onChange(of: subject) { old, new in
            if case .effect(let a, _) = old, case .effect(let b, _) = new, a == b { return }
            if externalTime == nil { ownTime = 0 }
            image = nil; error = nil
            if autoplay && externalTime == nil && visible { playing = true }
        }
        .onChange(of: sources.source) { _, _ in image = nil; error = nil }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            if isManagementWindow(note) { visible = false; playing = false; renderer.cancel() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            if isManagementWindow(note) { visible = true }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if externalTime == nil {
                Button {
                    if !playing, time.wrappedValue >= duration - 0.001 { time.wrappedValue = 0 }
                    playing.toggle()
                } label: { Image(systemName: playing ? "pause.fill" : "play.fill").frame(width: 14) }
                    .help(playing ? "Pause" : "Play (loops)")
                    .accessibilityLabel(playing ? "Pause preview" : "Play preview")
            }
            Slider(value: Binding(get: { min(time.wrappedValue, duration) }, set: { value in
                playing = false
                time.wrappedValue = value
            }), in: 0...duration)
                .accessibilityLabel("Preview time")
            Text("\(time.wrappedValue, specifier: "%.2f") / \(duration, specifier: "%.1f") s")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 92, alignment: .trailing)
            if showsSourcePicker { sourceMenu }
        }
    }

    private var sourceMenu: some View {
        Menu {
            Button {
                sources.source = .sample
            } label: { Label("Sample window", systemImage: sources.source == .sample ? "checkmark" : "macwindow") }
            Divider()
            if sources.windows.isEmpty {
                Text("No eligible windows on this Space")
            }
            ForEach(sources.windows) { window in
                Button {
                    sources.source = .window(window.id)
                } label: {
                    Label("\(window.owner) — \(window.title.isEmpty ? "Untitled" : window.title)",
                          systemImage: sources.source == .window(window.id) ? "checkmark" : "macwindow.on.rectangle")
                }
            }
            Divider()
            Button("Refresh Window List") { sources.refresh() }
            if sources.source != .sample {
                Button("Recapture") { image = nil; revision += 1 }
            }
        } label: {
            Label(sourceTitle, systemImage: "camera.viewfinder").lineLimit(1)
        }
        .menuStyle(.borderlessButton).fixedSize()
        .help("Preview on the built-in sample window or on one of your real windows. Real windows are only captured, never moved.")
    }

    private var sourceTitle: String {
        switch sources.source {
        case .sample: return "Sample window"
        case .window(let id):
            guard let window = sources.windows.first(where: { $0.id == id }) else { return "Window" }
            return window.owner
        }
    }

    /// Self-paced: each frame starts after the previous one finished, so slow simulations
    /// (Liquid replays several seconds of fluid) drop frames instead of piling up requests.
    private func playbackLoop() async {
        var last = ProcessInfo.processInfo.systemUptime
        var holdUntil: Double?
        while !Task.isCancelled, playing, visible {
            let now = ProcessInfo.processInfo.systemUptime
            if let hold = holdUntil {
                if now >= hold { holdUntil = nil; time.wrappedValue = 0 }
            } else {
                time.wrappedValue = min(duration, time.wrappedValue + min(0.25, now - last))
            }
            last = now
            let started = ProcessInfo.processInfo.systemUptime
            await renderFrame(at: time.wrappedValue)
            if holdUntil == nil, time.wrappedValue >= duration - 0.0005 {
                // Linger on the final frame so the ending is readable, then loop.
                holdUntil = ProcessInfo.processInfo.systemUptime + 0.6
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            let minimum = 1.0 / 20
            if elapsed < minimum {
                try? await Task.sleep(for: .milliseconds(Int((minimum - elapsed) * 1000)))
            }
        }
    }

    private func renderFrame(at seconds: Double) async {
        guard visible else { return }
        if rendering { pendingTime = seconds; return }
        rendering = true
        var next: Double? = seconds
        while let current = next {
            next = nil
            await renderOnce(at: current)
            if let queued = pendingTime { pendingTime = nil; next = queued }
        }
        rendering = false
    }

    private func renderOnce(at seconds: Double) async {
        do {
            let result: NSImage
            switch subject {
            case .effect(let effect, let preset):
                let progress = duration > 0 ? min(1, max(0, seconds / duration)) : 0
                result = try await renderer.preview(effect: effect, preset: preset, source: sources.source,
                                                    progress: progress, settings: settings)
            case .document(let document):
                result = try await renderer.preview(document: document, time: seconds, source: sources.source, settings: settings)
            }
            guard visible else { return }
            image = result
            error = nil
        } catch is CancellationError {
        } catch {
            guard visible else { return }
            self.error = error.localizedDescription
            playing = false
        }
    }
}

/// Soft desktop-like gradient so transparency and shadows read correctly.
private struct PreviewBackdrop: View {
    var body: some View {
        LinearGradient(colors: [Color(nsColor: .underPageBackgroundColor), Color(nsColor: .controlBackgroundColor)],
                       startPoint: .top, endPoint: .bottom)
            .overlay(
                RadialGradient(colors: [Color.accentColor.opacity(0.12), .clear], center: .center, startRadius: 10, endRadius: 420)
            )
    }
}
