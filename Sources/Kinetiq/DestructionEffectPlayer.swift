// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import CoreVideo
import KinetiqCore
import KinetiqSaverSupport
import MetalKit

/// Shared capture-to-scene adapter for live destruction and its read-only preview.
enum DestructionScene {
    static let duration: Double = 6

    /// Copies the window pixels, excluding the native shadow and any buffer padding.
    /// No IOSurface is retained by the GPU: the saver renderer uploads owned textures.
    static func image(_ frame: CapturedFrame) -> CGImage? {
        let buffer = frame.pixelBuffer
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let rect = frame.windowRect
        guard width > 0, height > 0, width <= 16384, height <= 16384,
              width * height <= 32_000_000,
              CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
              rect.width >= 8, rect.height >= 8,
              [rect.minX, rect.minY, rect.maxX, rect.maxY].allSatisfy(\.isFinite),
              CGRect(x: 0, y: 0, width: width, height: height).contains(rect) else { return nil }
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let data = Data(bytes: base, count: stride * height)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: stride, space: CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return image.cropping(to: rect)
    }

    /// Clips to each display before extraction, so spanning windows never duplicate material.
    static func build(frame: CapturedFrame, windowFrame: CGRect, stage: CGRect) -> ChaosScene? {
        guard frame.pointSize == windowFrame.size,
              windowFrame.width > 0, windowFrame.height > 0, stage.width > 0, stage.height > 0,
              [windowFrame.minX, windowFrame.minY, windowFrame.maxX, windowFrame.maxY,
               stage.minX, stage.minY, stage.maxX, stage.maxY].allSatisfy({ $0.isFinite && abs($0) < 10_000_000 }),
              let image = image(frame) else { return nil }
        let visible = windowFrame.intersection(stage)
        guard !visible.isNull, visible.width >= 8, visible.height >= 8 else { return nil }
        let sx = CGFloat(image.width) / windowFrame.width, sy = CGFloat(image.height) / windowFrame.height
        let crop = CGRect(x: (visible.minX - windowFrame.minX) * sx, y: (visible.minY - windowFrame.minY) * sy,
                          width: visible.width * sx, height: visible.height * sy)
        guard let clipped = image.cropping(to: crop),
              let extraction = UIObjectExtractor.extract(from: clipped, size: visible.size, maxGlyphs: 1200, maxOthers: 160) else { return nil }
        return ChaosSceneBuilder.build(windows: [ChaosWindowInput(
            frame: visible.offsetBy(dx: -stage.minX, dy: -stage.minY), extraction: extraction)], maxTiles: 256)
    }

    static func renderer(device: MTLDevice, scene: ChaosScene, size: CGSize, scale: CGFloat) throws -> ChaosRenderer {
        try ChaosRenderer(device: device, scene: scene, screenSize: size, pixelScale: scale, wallpaper: nil,
                          settings: ChaosSettings(lifetime: 3, seed: 42, speed: 1), oneShot: true)
    }
}

/// A bounded, one-shot use of the actual screensaver physics over the live desktop.
/// Windows remain native: this class only animates an owned copy after a real close.
@MainActor
final class DestructionEffectPlayer: NSObject, OverlayContent {
    private struct Playing {
        let renderer: ChaosRenderer
        let sourceID: CGWindowID
        let screen: CGRect
        let scale: Float
        let deadline: CFTimeInterval
    }

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private var playing: [Playing] = []
    private var pending = Set<CGWindowID>()
    private var generation = UUID()
    private var overlays: [OverlayWindow] = []
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    var hasScene: Bool { !playing.isEmpty }
    var sceneBounds: CGRect { playing.reduce(.null) { $0.union($1.screen) } }

    static func make() -> DestructionEffectPlayer? {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        return DestructionEffectPlayer(device: device, queue: queue)
    }

    private init(device: MTLDevice, queue: MTLCommandQueue) {
        self.device = device
        self.queue = queue
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.willSleepNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(cancelAll), name: name, object: nil)
        }
    }

    /// Off-main extraction cannot resurrect a cancelled generation or consume more than two source slots.
    @discardableResult
    func play(_ frame: CapturedFrame, windowFrame: CGRect, durationScale: Double,
              isValid: @MainActor () -> Bool = { true }) async -> Bool {
        RenderQualityManager.shared.refreshEnvironment()
        let sources = Set(playing.map(\.sourceID)).union(pending)
        guard !Task.isCancelled, isValid(), RenderQualityManager.shared.budget.allowsExpensive, durationScale.isFinite,
              sources.count < 2, !sources.contains(frame.windowID) else { return false }
        let screens = NSScreen.screens.filter { $0.cgFrame.intersects(windowFrame) }
        guard !screens.isEmpty else { return false }
        pending.insert(frame.windowID)
        let token = generation
        defer { if generation == token { pending.remove(frame.windowID) } }
        let bounds = screens.map(\.cgFrame)
        let scenes = await Task.detached(priority: .userInitiated) {
            bounds.map { DestructionScene.build(frame: frame, windowFrame: windowFrame, stage: $0) }
        }.value
        guard generation == token, !Task.isCancelled, isValid() else { return false }
        let scale = Float(min(3, max(0.25, durationScale)))
        var additions: [Playing] = []
        do {
            for (index, screen) in screens.enumerated() {
                guard let scene = scenes[index] else { continue }
                let renderer = try DestructionScene.renderer(device: device, scene: scene,
                    size: screen.frame.size, scale: screen.backingScaleFactor)
                additions.append(Playing(renderer: renderer, sourceID: frame.windowID, screen: bounds[index], scale: scale,
                    deadline: CACurrentMediaTime() + (DestructionScene.duration + 1) * Double(scale)))
            }
        } catch { NSLog("Kinetiq: window destruction unavailable: \(error)"); return false }
        guard !additions.isEmpty else { return false }
        if displayLink == nil {
            guard let link = screens.first?.displayLink(target: self, selector: #selector(tick(_:))) else { return false }
            link.add(to: .main, forMode: .common)
            displayLink = link
            lastTimestamp = CACurrentMediaTime()
        }
        playing += additions
        if overlays.isEmpty {
            let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
            overlays = NSScreen.screens.map { OverlayWindow(screen: $0, renderer: self, level: level) }
        }
        overlays.forEach { $0.render(); $0.show() }
        return true
    }

    @objc func cancelAll() {
        generation = UUID()
        pending.removeAll()
        playing.removeAll()
        stopOutput()
    }

    /// Natural completion must not invalidate another source's in-progress extraction.
    private func stopOutput() {
        displayLink?.invalidate()
        displayLink = nil
        overlays.forEach { $0.render(); $0.hide() }
    }

    @objc private func screensChanged() {
        cancelAll()
        overlays.forEach { $0.close() }
        overlays.removeAll()
    }

    @objc private func tick(_ link: CADisplayLink) {
        let fps = Float(min(120, max(15, RenderQualityManager.shared.budget.secondaryFPS)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: min(30, fps), maximum: fps, preferred: fps)
        // Fixed-size slices preserve ChaosWorld's 120 Hz physics at low display rates.
        let dt = Float(max(0, min(0.1, link.timestamp - lastTimestamp)))
        lastTimestamp = link.timestamp
        for item in playing {
            var remaining = dt / item.scale
            while remaining > 0 {
                let step = min(remaining, 1 / 120)
                item.renderer.simulate(step)
                remaining -= step
            }
        }
        playing.removeAll { $0.renderer.isFinished || CACurrentMediaTime() >= $0.deadline }
        overlays.forEach { $0.render() }
        if playing.isEmpty { stopOutput() }
    }

    func draw(in view: MTKView, screenRect: CGRect) {
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let command = queue.makeCommandBuffer(), let clear = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        clear.endEncoding()
        let renderers = playing.filter { $0.screen == screenRect }.map(\.renderer)
        for renderer in renderers {
            renderer.encodeFrame(commands: command, target: drawable.texture, dt: 0, clear: false)
        }
        // Metal retains the uploaded textures and buffers referenced by these encoders.
        if !renderers.isEmpty { trackGPUCompletion(command) }
        command.present(drawable)
        command.commit()
    }
}