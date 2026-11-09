// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import KinetiqCore
import QuartzCore

/// Plays the morph of a window into its Dock icon: the capture of the window is drawn on a mesh that a
/// `DockMorphDeformer` bends towards the icon, in transparent overlays over the screens.
@MainActor
final class MorphPlayer {
    private let renderer: MeshRenderer
    private var overlays: [OverlayWindow] = []
    private var displayLink: CADisplayLink?
    private var deformer: DockMorphDeformer?
    private var completion: (() -> Void)?
    private var lastTimestamp: CFTimeInterval = 0

    init?() {
        guard let renderer = MeshRenderer() else { return nil }
        self.renderer = renderer
    }

    var isPlaying: Bool { deformer != nil }

    /// Starts the morph. Returns false if the capture can't be drawn. `completion` runs once the window is in the icon.
    func play(_ frame: CapturedFrame, windowFrame: CGRect, icon: CGRect, style: DockMorphStyle, durationScale: Double,
              trigger: EffectTrigger? = nil, completion: @escaping () -> Void) -> Bool {
        guard !isPlaying, renderer.setFrame(frame) else { return false }
        let deformer = DockMorphDeformer(
            windowOrigin: SIMD2(Float(windowFrame.minX), Float(windowFrame.minY)),
            windowSize: SIMD2(Float(windowFrame.width), Float(windowFrame.height)),
            iconOrigin: SIMD2(Float(icon.minX), Float(icon.minY)), iconSize: SIMD2(Float(icon.width), Float(icon.height)),
            style: style, duration: style.duration * Float(max(durationScale, 0.05)))
        self.deformer = deformer
        self.completion = completion
        renderer.alpha = 1
        renderer.shadowOpacity = 1
        updateMesh(deformer)

        if overlays.isEmpty { overlays = NSScreen.screens.map { OverlayWindow(screen: $0, renderer: renderer) } }
        overlays.forEach { $0.render() }
        overlays.forEach { $0.show() }

        let screen = NSScreen.containing(cgPoint: CGPoint(x: windowFrame.midX, y: windowFrame.midY)) ?? NSScreen.screens.first
        guard let link = screen?.displayLink(target: self, selector: #selector(tick(_:))) else {
            finish()
            return true
        }
        updateFrameRate(link)
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastTimestamp = CACurrentMediaTime()
        KinetiqTelemetry.emit((trigger ?? .minimize).usageEvent(effectID: LibraryEffect.minimize(style).id))
        return true
    }

    func cancel() {
        if deformer != nil { finish() }
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let deformer else { return }
        updateFrameRate(link)
        let dt = max(0, link.timestamp - lastTimestamp)
        lastTimestamp = link.timestamp
        deformer.step(Float(dt))
        renderer.alpha = deformer.alpha
        updateMesh(deformer)
        overlays.forEach { $0.render() }
        if deformer.isSettled { finish() }
    }

    private func updateFrameRate(_ link: CADisplayLink) {
        let fps = Float(min(120, max(15, RenderQualityManager.shared.budget.secondaryFPS)))
        if link.preferredFrameRateRange.preferred != fps {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: min(30, fps), maximum: fps, preferred: fps)
        }
    }

    private func updateMesh(_ deformer: DockMorphDeformer) {
        let limit = RenderQualityManager.shared.budget.meshLimit
        renderer.update(from: deformer, tilesX: min(24, limit), tilesY: min(20, limit))
    }

    private func finish() {
        displayLink?.invalidate()
        displayLink = nil
        deformer = nil
        renderer.clearScene()
        overlays.forEach {
            $0.render()
            $0.hide()
        }
        let done = completion
        completion = nil
        done?()
    }
}
