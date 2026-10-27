// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import KinetiqCore
import MetalKit
import UniformTypeIdentifiers
import os

/// Draws one screen's saver scene into an `MTKView`.
@MainActor
private final class ChaosViewDelegate: NSObject, MTKViewDelegate {
    let renderer: ChaosRenderer
    private var lastFrame = CACurrentMediaTime()

    init(renderer: ChaosRenderer) {
        self.renderer = renderer
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = Float(now - lastFrame)
        lastFrame = now
        guard let drawable = view.currentDrawable, let commands = renderer.queue.makeCommandBuffer() else { return }
        renderer.encodeFrame(commands: commands, target: drawable.texture, dt: dt)
        commands.present(drawable)
        commands.commit()
    }
}

/// The screen saver: after a while without input it covers the screens with a picture of the desktop that falls apart:
/// letters drop, buttons explode, windows break in pieces, and everything piles up at the bottom of the screen and fades.
/// Nothing real is touched, so ending the saver reveals the untouched desktop.
@MainActor
final class ChaosSaver: NSObject {
    private struct Overlay {
        let window: NSWindow
        let view: MTKView
        let delegate: ChaosViewDelegate
    }

    private static let log = Logger(subsystem: "io.github.invernomut0.Kinetiq", category: "chaos")

    private let settings: Settings
    private(set) var isRunning = false
    private var starting = false
    private var overlays: [Overlay] = []
    private var idleTimer: Timer?
    private var debugTimer: Timer?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var startedAt: CFTimeInterval = 0
    private var stoppedAt: CFTimeInterval = 0
    private var mouseTravel: CGFloat = 0
    private var previousApp: NSRunningApplication?
    private var dumped = Set<Int>()
    private var dockDetonated = false
    private var lastFPSLog: CFTimeInterval = 0
    private var lastFrames = 0

    /// Debugging aids: `KINETIQ_CHAOS_DUMP=<dir>` writes pictures of the saver, `KINETIQ_CHAOS_SECONDS=<n>` ends it by itself.
    private let environment = ProcessInfo.processInfo.environment

    init(settings: Settings) {
        self.settings = settings
    }

    func startIdleWatching() {
        idleTimer?.invalidate()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIdle() }
        }
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    private func checkIdle() {
        guard settings.chaosEnabled, !isRunning, !starting, Permissions.screenCaptureGranted else { return }
        let anyEvent = CGEventType(rawValue: ~0)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyEvent)
        if idle >= Double(settings.chaosIdleMinutes * 60) { start(manual: false) }
    }

    /// `manual` starts (from the Setup window) explain a missing permission instead of staying silent.
    func start(manual: Bool = true) {
        guard !isRunning, !starting, CACurrentMediaTime() - stoppedAt > 0.5 else {
            Self.log.info("start ignored: running \(self.isRunning) starting \(self.starting)")
            return
        }
        guard Permissions.screenCaptureGranted else {
            Self.log.error("start: Screen Recording permission missing")
            if manual {
                CGRequestScreenCaptureAccess()
                explainPermission()
            }
            return
        }
        starting = true
        Task {
            defer { starting = false }
            do {
                let elements = try await DesktopSnapshot.capture()
                var wallpapers: [CGDirectDisplayID: CGImage] = [:]
                for screen in NSScreen.screens {
                    guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                          let image = await DesktopSnapshot.wallpaper(for: screen) else { continue }
                    wallpapers[id] = image
                }
                let extractions = await Self.extractObjects(from: elements)
                present(elements, extractions: extractions, wallpapers: wallpapers)
            } catch {
                Self.log.error("could not start: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        stoppedAt = CACurrentMediaTime()
        isRunning = false
        debugTimer?.invalidate()
        debugTimer = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        for overlay in overlays {
            overlay.view.isPaused = true
            overlay.window.orderOut(nil)
        }
        overlays.removeAll()
        NSCursor.unhide()
        previousApp?.activate()
        previousApp = nil
    }

    /// Cuts the letters, buttons and icons out of every captured window, in parallel on background threads.
    private static func extractObjects(from windows: [SnapshotWindow]) async -> [CGWindowID: UIExtraction] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let lock = NSLock()
                var result: [CGWindowID: UIExtraction] = [:]
                DispatchQueue.concurrentPerform(iterations: windows.count) { i in
                    let w = windows[i]
                    let role: UIWindowRole = w.owner == "Dock" ? .dock : .app
                    if let extraction = UIObjectExtractor.extract(from: w.image, size: w.frame.size, role: role) {
                        lock.lock()
                        result[w.id] = extraction
                        lock.unlock()
                    }
                }
                continuation.resume(returning: result)
            }
        }
    }

    // MARK: - Presentation

    private func present(_ elements: [SnapshotWindow], extractions: [CGWindowID: UIExtraction], wallpapers: [CGDirectDisplayID: CGImage]) {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let chaos = settings.chaosSettings

        var created: [Overlay] = []
        for screen in NSScreen.screens {
            let frame = screen.frame
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID, let wallpaper = wallpapers[id] else { continue }
            // Window bounds are top-left based; NSScreen is bottom-left based.
            let global = CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
            let inputs = elements.compactMap { element -> ChaosWindowInput? in
                guard global.contains(CGPoint(x: element.frame.midX, y: element.frame.midY)), let extraction = extractions[element.id] else { return nil }
                return ChaosWindowInput(frame: element.frame.offsetBy(dx: -global.minX, dy: -global.minY), extraction: extraction)
            }
            let scale = min(screen.backingScaleFactor, 2)
            let pixelSize = CGSize(width: (frame.width * scale).rounded(.down), height: (frame.height * scale).rounded(.down))
            do {
                let renderer = try ChaosRenderer(device: device, scene: ChaosSceneBuilder.build(windows: inputs), screenSize: frame.size,
                                                 pixelScale: scale, wallpaper: wallpaper, settings: chaos)
                if environment["KINETIQ_CHAOS_OFFSCREEN"] != nil {
                    runOffscreen(renderer)
                    return
                }
                let view = MTKView(frame: NSRect(origin: .zero, size: frame.size), device: device)
                view.colorPixelFormat = .bgra8Unorm
                view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
                view.framebufferOnly = true
                view.autoResizeDrawable = false
                view.drawableSize = pixelSize
                view.preferredFramesPerSecond = 60
                let delegate = ChaosViewDelegate(renderer: renderer)
                view.delegate = delegate

                let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
                window.level = .screenSaver
                window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
                window.isOpaque = true
                window.backgroundColor = .black
                window.hasShadow = false
                window.isReleasedWhenClosed = false
                window.acceptsMouseMovedEvents = true
                window.animationBehavior = .none
                window.contentView = view
                window.setFrame(frame, display: true)
                created.append(Overlay(window: window, view: view, delegate: delegate))
            } catch {
                Self.log.error("renderer unavailable: \(String(describing: error))")
            }
        }
        guard !created.isEmpty else {
            Self.log.error("nothing to show: no screen could be set up (wallpapers \(wallpapers.count), screens \(NSScreen.screens.count))")
            return
        }

        overlays = created
        isRunning = true
        startedAt = CACurrentMediaTime()
        mouseTravel = 0
        dockDetonated = false
        dumped.removeAll()
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        NSApp.activate()
        for overlay in overlays { overlay.window.makeKeyAndOrderFront(nil) }
        NSCursor.hide()

        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return nil
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        if environment["KINETIQ_CHAOS_DUMP"] != nil || environment["KINETIQ_CHAOS_SECONDS"] != nil {
            debugTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.debugTick() }
            }
        }
    }

    /// Any key or click ends the saver; mouse movement must travel a little first.
    private func handle(_ event: NSEvent) {
        // The click or shortcut that started the saver may still be going on.
        guard CACurrentMediaTime() - startedAt > 1 else { return }
        if event.type == .mouseMoved {
            mouseTravel += abs(event.deltaX) + abs(event.deltaY)
            if mouseTravel > 12 { stop() }
        } else {
            stop()
        }
    }

    private func debugTick() {
        guard let renderer = overlays.first?.delegate.renderer else { return }
        let elapsed = renderer.elapsed
        if CACurrentMediaTime() - lastFPSLog > 2 {
            let fps = Double(renderer.frames - lastFrames) / (CACurrentMediaTime() - lastFPSLog)
            let loose = renderer.world.looseCount, puffs = renderer.world.puffs.count
            Self.log.info("t \(elapsed) fps \(fps) loose \(loose) puffs \(puffs)")
            lastFPSLog = CACurrentMediaTime()
            lastFrames = renderer.frames
        }
        if let at = environment["KINETIQ_CHAOS_NUKE"].flatMap(Float.init), elapsed >= at, !renderer.world.nukeSpent { renderer.world.run(.nuke) }
        if let at = environment["KINETIQ_CHAOS_DOCK"].flatMap(Float.init), elapsed >= at, !dockDetonated {
            dockDetonated = true
            if let i = renderer.world.bodies.firstIndex(where: { $0.isDock && $0.state == .attached }) { renderer.world.detonate(i) }
        }
        let times = (environment["KINETIQ_CHAOS_DUMP_TIMES"]?.split(separator: ",").compactMap { Double($0) }) ?? [1.5, 4.0, 8.0, 14.0, 22.0]
        if let directory = environment["KINETIQ_CHAOS_DUMP"] {
            for (index, second) in times.enumerated() where Float(second) <= elapsed && !dumped.contains(index) {
                dumped.insert(index)
                writeSnapshot(of: renderer, to: directory, second: second)
            }
        }
        if let seconds = environment["KINETIQ_CHAOS_SECONDS"].flatMap(Float.init), elapsed >= seconds { stop() }
    }

    private func writeSnapshot(of renderer: ChaosRenderer, to directory: String, second: Double) {
        guard let image = renderer.snapshot() else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent(String(format: "chaos-%02d.png", Int(second)))
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
        Self.log.info("dumped \(url.path) events \(renderer.world.eventCount) loose \(renderer.world.looseCount) intact \(renderer.world.intactFraction)")
    }

    /// Debugging aid: runs the simulation at 60 steps per second without showing anything on the screen and writes the
    /// pictures of `KINETIQ_CHAOS_DUMP_TIMES` (so the real desktop is never covered while the code is being tested).
    private func runOffscreen(_ renderer: ChaosRenderer) {
        guard let directory = environment["KINETIQ_CHAOS_DUMP"] else { return }
        let times = ((environment["KINETIQ_CHAOS_DUMP_TIMES"]?.split(separator: ",").compactMap { Double($0) }) ?? [4, 10, 20]).sorted()
        var next = 0, docked = false
        let nukeAt = environment["KINETIQ_CHAOS_NUKE"].flatMap(Float.init), dockAt = environment["KINETIQ_CHAOS_DOCK"].flatMap(Float.init)
        while next < times.count {
            renderer.simulate(1 / 60)
            let t = renderer.elapsed
            if let nukeAt, t >= nukeAt, !renderer.world.nukeSpent { renderer.world.run(.nuke) }
            if let dockAt, t >= dockAt, !docked {
                docked = true
                if let i = renderer.world.bodies.firstIndex(where: { $0.isDock && $0.state == .attached }) { renderer.world.detonate(i) }
            }
            while next < times.count, Float(times[next]) <= t {
                writeSnapshot(of: renderer, to: directory, second: times[next])
                next += 1
            }
        }
        Self.log.info("offscreen run done")
    }

    private func explainPermission() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Screen Recording permission needed"
        alert.informativeText = "The screen saver saves the content of your windows, which requires Screen Recording access. Enable Kinetiq in System Settings \u{2192} Privacy & Security \u{2192} Screen Recording, then start it again."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { Permissions.openPrivacySettings("Privacy_ScreenCapture") }
    }
}
