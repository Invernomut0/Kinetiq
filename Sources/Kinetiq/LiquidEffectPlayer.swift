// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import CoreVideo
import KinetiqCore
import KinetiqEffects
import MetalKit
import QuartzCore

/// Owns desktop-space fluid, real capture lifetimes and click-through overlays.
/// Each display has its own floor; no rectangular union creates an imaginary floor
/// across gaps between monitors. The Dock and menus remain live above the liquid.
@MainActor
final class LiquidEffectPlayer: NSObject, OverlayContent {
    /// Immutable CoreVideo mapping; retaining it never accesses the main-actor scene.
    private final class CaptureBacking: @unchecked Sendable {
        let texture: CVMetalTexture
        init(_ texture: CVMetalTexture) { self.texture = texture }
    }

    private struct Playing {
        let world: LiquidWorld
        let sourceID: CGWindowID
        let texture: MTLTexture
        /// Keeps the IOSurface mapped for all in-flight GPU frames.
        let backing: CaptureBacking
        let uvRect: SIMD4<Float>
        let deadline: CFTimeInterval
    }

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let renderer: LiquidEffectRenderer
    private var textureCache: CVMetalTextureCache?
    private var playing: [Playing] = []
    private var overlays: [OverlayWindow] = []
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var nextObstacleRefresh: CFTimeInterval = 0

    var hasScene: Bool { !playing.isEmpty }
    var sceneBounds: CGRect { playing.reduce(.null) { $0.union($1.world.screenBounds) } }

    /// Shader compilation is done at controller setup, never on a minimize click.
    static func make() -> LiquidEffectPlayer? {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        do { return try LiquidEffectPlayer(device: device, queue: queue) }
        catch { NSLog("Kinetiq: liquid renderer unavailable: \(error)"); return nil }
    }

    private init(device: MTLDevice, queue: MTLCommandQueue) throws {
        self.device = device
        self.queue = queue
        renderer = try LiquidEffectRenderer(device: device)
        super.init()
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(cancelAll), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(cancelAll), name: NSWorkspace.willSleepNotification, object: nil)
    }

    /// Returns false without touching the real window if resources are unavailable.
    /// At most two captures (up to 1500 particles/display each) may remain alive.
    @discardableResult
    func play(_ frame: CapturedFrame, windowFrame: CGRect, durationScale: Double) -> Bool {
        let sources = Set(playing.map(\.sourceID))
        guard sources.count < 2, !sources.contains(frame.windowID), frame.isPainted,
              frame.pointSize == windowFrame.size, let textureCache else { return false }
        let screens = NSScreen.screens.filter { $0.cgFrame.intersects(windowFrame) }
        guard !screens.isEmpty else { return false }
        let buffer = frame.pixelBuffer
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        var backing: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, textureCache, buffer, nil, .bgra8Unorm, width, height, 0, &backing)
        guard status == kCVReturnSuccess, let backing, let texture = CVMetalTextureGetTexture(backing) else { return false }
        let retainedBacking = CaptureBacking(backing)
        let scale = durationScale.isFinite ? min(3, max(0.25, durationScale)) : 1
        let obstacles = WindowLocator.liquidObstacles(excluding: Set(playing.map(\.sourceID)).union([frame.windowID]))
        let uv = SIMD4(Float(frame.windowRect.minX) / Float(width), Float(frame.windowRect.minY) / Float(height),
                       Float(frame.windowRect.width) / Float(width), Float(frame.windowRect.height) / Float(height))
        let additions = screens.compactMap { screen -> Playing? in
            let world = LiquidWorld(windowFrame: windowFrame, screenBounds: screen.cgFrame,
                                    obstacles: obstacles, durationScale: Float(scale))
            guard !world.isFinished else { return nil }
            return Playing(world: world, sourceID: frame.windowID, texture: texture, backing: retainedBacking, uvRect: uv,
                           deadline: CACurrentMediaTime() + 15 * scale)
        }
        guard !additions.isEmpty else { return false }
        if displayLink == nil {
            guard let link = screens.first?.displayLink(target: self, selector: #selector(tick(_:))) else { return false }
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            displayLink = link
            lastTimestamp = 0
        }
        playing += additions
        if overlays.isEmpty {
            let belowDock = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
            overlays = NSScreen.screens.map { OverlayWindow(screen: $0, renderer: self, level: belowDock) }
        }
        overlays.forEach { $0.render() }
        overlays.forEach { $0.show() }
        return true
    }

    @objc func cancelAll() {
        playing.removeAll()
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = 0
        overlays.forEach { $0.render(); $0.hide() }
    }

    @objc private func screensChanged() {
        cancelAll()
        overlays.forEach { $0.close() }
        overlays.removeAll()
    }

    @objc private func tick(_ link: CADisplayLink) {
        let dt = lastTimestamp == 0 ? 1.0 / 60 : link.timestamp - lastTimestamp
        lastTimestamp = link.timestamp
        let now = CACurrentMediaTime()
        if now >= nextObstacleRefresh {
            let obstacles = WindowLocator.liquidObstacles(excluding: Set(playing.map(\.sourceID)))
            playing.forEach { $0.world.setObstacles(obstacles) }
            nextObstacleRefresh = now + 0.15
        }
        playing.forEach { $0.world.step(Float(dt)) }
        playing.removeAll { $0.world.isFinished || now >= $0.deadline }
        overlays.forEach { $0.render() }
        if playing.isEmpty { cancelAll() }
    }

    func draw(in view: MTKView, screenRect: CGRect) {
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let command = queue.makeCommandBuffer(),
              let clear = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        clear.endEncoding()
        for item in playing where item.world.screenBounds == screenRect {
            renderer.encode(world: item.world, texture: item.texture, uvRect: item.uvRect,
                            into: command, target: drawable.texture, screenRect: screenRect)
        }
        // CoreVideo explicitly requires its mapping (not just the MTLTexture) to
        // outlive GPU use, even if cancellation removes the scene immediately.
        let backings = playing.filter { $0.world.screenBounds == screenRect }.map(\.backing)
        command.addCompletedHandler { _ in withExtendedLifetime(backings) {} }
        command.present(drawable)
        command.commit()
    }
}