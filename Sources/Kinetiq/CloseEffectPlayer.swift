// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import CoreVideo
import Metal
import MetalKit
import QuartzCore
import KinetiqEffects

/// Plays the close effects: the capture of the closed window is drawn by the effect's shader in transparent
/// overlays (one per screen), over whatever is on the desktop now. Several windows can be closing at once.
@MainActor
final class CloseEffectPlayer: NSObject, OverlayContent {
    private struct Playing {
        var scene: EffectScene
        var startedAt: CFTimeInterval?
        /// macOS' own fade-out is still running under the overlay: its shadow fades out as ours fades in.
        let underFade: Bool
        /// Keeps the capture's IOSurface mapped while the GPU may read it.
        let backing: CVMetalTexture
        /// Called once, shortly before the effect ends (the real window is brought back under the last frames).
        var nearEnd: (() -> Void)?
        /// Called once when the effect is over (or cancelled).
        var onFinish: (() -> Void)?
        /// Keeps drawing the last frame after the end, until `releaseHeld()`: the real window needs a moment to come back.
        var holdLastFrame = false
        var finishNotified = false
        var released = false
        var releaseTicks = 0
    }

    /// How long macOS takes to fade a closing window out.
    private static let nativeFadeTime: CFTimeInterval = 0.18

    let device: MTLDevice
    private(set) var hasScene = false
    private(set) var sceneBounds = CGRect.null

    private let renderer: CloseEffectRenderer
    private let queue: MTLCommandQueue
    private var textureCache: CVMetalTextureCache?
    private var playing: [Playing] = []
    private var overlays: [OverlayWindow] = []
    private var displayLink: CADisplayLink?
    /// Overlays stay in front, blank, while a window may be about to close, so the effect starts in the very frame
    /// the window disappears instead of one or two frames later.
    private var armed = false
    private var ready: Set<CloseEffect> = []
    private var warmUpTask: Task<Void, Never>?

    private init(device: MTLDevice, queue: MTLCommandQueue) {
        self.device = device
        self.queue = queue
        renderer = CloseEffectRenderer(device: device)
        super.init()
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    static func make() -> CloseEffectPlayer? {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        return CloseEffectPlayer(device: device, queue: queue)
    }

    // MARK: - Shaders

    /// Compiles the shaders the user may need, in the background, so the first close doesn't wait for the compiler.
    func warmUp(_ choices: [CloseEffectChoice]) {
        var effects: [CloseEffect] = []
        for choice in choices {
            switch choice {
            case .off: break
            case .random: effects.append(contentsOf: CloseEffect.allCases)
            case .effect(let effect): effects.append(effect)
            }
        }
        var seen = Set<CloseEffect>()
        let pending = effects.filter { !ready.contains($0) && seen.insert($0).inserted }
        guard !pending.isEmpty else { return }

        let renderer = renderer
        warmUpTask?.cancel()
        warmUpTask = Task.detached(priority: .utility) { [weak self] in
            for effect in pending {
                if Task.isCancelled { return }
                do {
                    try renderer.prepare(effect)
                    await self?.markReady(effect)
                } catch {
                    NSLog("Kinetiq: close effect \(effect.title) unavailable: \(error)")
                }
            }
        }
    }

    private func markReady(_ effect: CloseEffect) {
        ready.insert(effect)
    }

    /// The effect to play for the user's choice. A random pick favors the shaders that are already compiled.
    func effect(for choice: CloseEffectChoice) -> CloseEffect? {
        switch choice {
        case .off: return nil
        case .effect(let effect): return effect
        case .random: return ready.randomElement() ?? CloseEffect.allCases.randomElement()
        }
    }

    // MARK: - Overlays

    /// While armed, the overlays are in front (blank) so an effect can start without delay.
    func setArmed(_ on: Bool) {
        guard armed != on else { return }
        armed = on
        if on {
            ensureOverlays()
            overlays.forEach { $0.showBlank() }
        } else if playing.isEmpty {
            overlays.forEach { $0.hide() }
        }
    }

    private func ensureOverlays() {
        if overlays.isEmpty {
            overlays = NSScreen.screens.map { OverlayWindow(screen: $0, renderer: self) }
        }
    }

    @objc private func screensChanged() {
        overlays.forEach { $0.close() }
        overlays = []
        guard armed || !playing.isEmpty else { return }
        ensureOverlays()
        overlays.forEach { $0.showBlank() }
    }

    // MARK: - Playback

    /// Starts the effect on the capture of a window that is closing. Returns false if it can't be drawn.
    /// `nativeFade`: the real window is still fading out underneath, with its own shadow.
    @discardableResult
    func play(_ frame: CapturedFrame, windowFrame: CGRect, effect: CloseEffect, pointer: CGPoint, durationScale: Double,
              nativeFade: Bool, opening: Bool = false, nearEnd: (() -> Void)? = nil, onFinish: (() -> Void)? = nil,
              holdLastFrame: Bool = false) -> Bool {
        guard let textureCache else { return false }
        do {
            try renderer.prepare(effect)
        } catch {
            NSLog("Kinetiq: close effect \(effect.title) unavailable: \(error)")
            return false
        }

        let buffer = frame.pixelBuffer
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        var backing: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, buffer, nil, .bgra8Unorm, width, height, 0, &backing)
        guard status == kCVReturnSuccess, let backing, let texture = CVMetalTextureGetTexture(backing) else { return false }

        let bufferSize = SIMD2(Float(width), Float(height))
        let rect = frame.windowRect
        let insets = frame.shadow
        let screen = NSScreen.containing(cgPoint: CGPoint(x: windowFrame.midX, y: windowFrame.midY)) ?? NSScreen.screens.first
        let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB)
        let scene = {
            var scene = EffectScene(
                effect: effect, texture: texture,
                uvScale: SIMD2(Float(rect.width), Float(rect.height)) / bufferSize,
                uvOffset: SIMD2(Float(rect.minX), Float(rect.minY)) / bufferSize,
                windowFrame: windowFrame, padding: Float(max(insets.left, insets.top, insets.right, insets.bottom)),
                pointer: pointer, screenHeight: Float(screen?.frame.height ?? 1080),
                accentColor: accent.map { SIMD3(Float($0.redComponent), Float($0.greenComponent), Float($0.blueComponent)) }
                    ?? SIMD3(0.04, 0.52, 1),
                durationScale: Float(durationScale))
            scene.forOpening = opening
            return scene
        }()

        playing.append(Playing(scene: scene, startedAt: nil, underFade: nativeFade, backing: backing, nearEnd: nearEnd, onFinish: onFinish))
        playing[playing.count - 1].holdLastFrame = holdLastFrame
        playing[playing.count - 1].scene.shadowOpacity = nativeFade ? 0 : 1
        refreshBounds()
        ensureOverlays()
        overlays.forEach { $0.render() }
        overlays.forEach { $0.show() }
        startDisplayLink(near: CGPoint(x: windowFrame.midX, y: windowFrame.midY))
        return true
    }

    /// Stops every running effect (the screens changed, or the app is quitting).
    func cancelAll() {
        let pending = playing.compactMap(\.nearEnd)
        let finished = playing.compactMap(\.onFinish)
        playing.removeAll()
        pending.forEach { $0() }
        finished.forEach { $0() }
        refreshBounds()
        finishIfIdle()
    }

    private func refreshBounds() {
        sceneBounds = playing.reduce(CGRect.null) { $0.union($1.scene.quadRect) }
        hasScene = !playing.isEmpty
    }

    private func startDisplayLink(near point: CGPoint) {
        guard displayLink == nil else { return }
        let screen = NSScreen.containing(cgPoint: point) ?? NSScreen.screens.first
        guard let link = screen?.displayLink(target: self, selector: #selector(tick(_:))) else { return }
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Lets go of the effects that were kept on their last frame: the real window is back.
    /// Their shadow goes first, then they are removed a couple of frames later.
    func releaseHeld() {
        for index in playing.indices where playing[index].holdLastFrame { playing[index].released = true }
    }

    @objc private func tick(_ link: CADisplayLink) {
        var finished: [() -> Void] = []
        for index in playing.indices {
            // The first frame is drawn at progress 0, whenever the animation was requested.
            let start = playing[index].startedAt ?? link.timestamp
            playing[index].startedAt = start
            let elapsed = link.timestamp - start
            playing[index].scene.progress = Float(elapsed / Double(playing[index].scene.duration))
            if playing[index].underFade {
                playing[index].scene.shadowOpacity = Float(min(1, elapsed / Self.nativeFadeTime))
            }
            if playing[index].scene.progress >= 0.9, let nearEnd = playing[index].nearEnd {
                playing[index].nearEnd = nil
                nearEnd()
            }
            if playing[index].scene.progress >= 1, playing[index].holdLastFrame {
                playing[index].scene.progress = 1
                if playing[index].released {
                    // The real window's own shadow is back; the overlay stops drawing its copy.
                    playing[index].scene.shadowOpacity = 0
                    playing[index].releaseTicks += 1
                } else if !playing[index].finishNotified {
                    playing[index].finishNotified = true
                    if let onFinish = playing[index].onFinish { finished.append(onFinish) }
                }
            }
        }
        finished += playing.filter { !$0.holdLastFrame && $0.scene.progress >= 1 }.compactMap(\.onFinish)
        playing.removeAll { $0.holdLastFrame ? ($0.released && $0.releaseTicks >= 2) : $0.scene.progress >= 1 }
        refreshBounds()
        overlays.forEach { $0.render() }
        finishIfIdle()
        finished.forEach { $0() }
    }

    private func finishIfIdle() {
        guard playing.isEmpty else { return }
        overlays.forEach { $0.render() }
        displayLink?.invalidate()
        displayLink = nil
        if !armed { overlays.forEach { $0.hide() } }
    }

    // MARK: - OverlayContent

    func draw(in view: MTKView, screenRect: CGRect) {
        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        for item in playing where item.scene.quadRect.intersects(screenRect) {
            renderer.encode(item.scene, into: encoder, screenRect: screenRect)
        }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
