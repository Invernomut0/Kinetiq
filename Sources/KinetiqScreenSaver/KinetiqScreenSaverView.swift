// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import KinetiqSaverSupport
import MetalKit
import ScreenSaver
import os

/// A real ScreenSaver.framework module. macOS owns inactivity, dismissal and authentication.
@objc(KinetiqScreenSaverView)
public final class KinetiqScreenSaverView: ScreenSaverView {
    private var metalView: MTKView?
    private var renderer: ChaosRenderer?
    private var preparation: Task<Void, Never>?
    private var generation = UUID()
    private var lastFrame: CFTimeInterval = 0
    private var stopObserver: NSObjectProtocol?
    private static let log = Logger(subsystem: "io.github.invernomut0.Kinetiq", category: "native-saver")

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1 / 60
        wantsLayer = true
        stopObserver = DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.screensaver.willstop"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopAnimation() }
        }
    }

    public required init?(coder: NSCoder) { super.init(coder: coder) }

    deinit {
        preparation?.cancel()
        if let stopObserver { DistributedNotificationCenter.default().removeObserver(stopObserver) }
    }

    public override func startAnimation() {
        super.startAnimation()
        guard renderer == nil, preparation == nil else { return }
        let generation = UUID()
        self.generation = generation
        let displayID = window?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32
        preparation = Task { [weak self] in
            do {
                let prepared = try await Task.detached(priority: .userInitiated) {
                    let archive = try SaverArchive.read()
                    let display = archive.displays.first(where: { $0.id == displayID }) ?? archive.displays[0]
                    return (archive, display, display.scene())
                }.value
                guard !Task.isCancelled, let self, self.generation == generation, self.isAnimating,
                      let device = MTLCreateSystemDefaultDevice(), let wallpaper = SaverArchive.image(prepared.1.wallpaper) else { return }
                let scale = min(self.window?.backingScaleFactor ?? 1, 2)
                let renderer = try ChaosRenderer(device: device, scene: prepared.2, screenSize: prepared.1.size,
                                                 pixelScale: scale, wallpaper: wallpaper, settings: prepared.0.settings)
                let view = MTKView(frame: self.bounds, device: device)
                view.autoresizingMask = [.width, .height]
                view.colorPixelFormat = .bgra8Unorm
                view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
                view.isPaused = true
                view.enableSetNeedsDisplay = false
                self.addSubview(view)
                self.metalView = view
                self.renderer = renderer
                self.lastFrame = CACurrentMediaTime()
                Self.log.notice("native scene ready, display \(prepared.1.id), pieces \(renderer.world.originalCount)")
            } catch {
                Self.log.error("native scene unavailable: \(error.localizedDescription)")
            }
            if self?.generation == generation { self?.preparation = nil }
        }
    }

    public override func stopAnimation() {
        generation = UUID()
        preparation?.cancel()
        preparation = nil
        metalView?.removeFromSuperview()
        metalView = nil
        renderer = nil
        super.stopAnimation()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopAnimation() }
    }

    public override func animateOneFrame() {
        guard let view = metalView, let renderer, let drawable = view.currentDrawable,
              let commands = renderer.queue.makeCommandBuffer() else { return }
        let now = CACurrentMediaTime()
        renderer.encodeFrame(commands: commands, target: drawable.texture, dt: Float(min(now - lastFrame, 0.1)))
        lastFrame = now
        commands.present(drawable)
        commands.commit()
    }

    public override func draw(_ rect: NSRect) {
        super.draw(rect)
        guard renderer == nil else { return }
        let text = "Kinetiq\nOpen Kinetiq to prepare the desktop scene."
        (text as NSString).draw(in: bounds.insetBy(dx: 24, dy: 24), withAttributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 16)])
    }
}