// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
@preconcurrency import ApplicationServices
import Combine
import CoreVideo
import KinetiqCore
import KinetiqEffects
@preconcurrency import Metal
import MetalKit

/// An IOSurface, its CV texture wrapper and its Metal view have one immutable lifetime.
/// Command completion handlers retain this object, even after stop releases the scene.
private final class CatalogCapture: @unchecked Sendable {
    let frame: CapturedFrame
    let backing: CVMetalTexture
    let texture: MTLTexture
    let uv: SIMD4<Float>

    init(_ frame: CapturedFrame, cache: CVMetalTextureCache) throws {
        self.frame = frame
        let w = CVPixelBufferGetWidth(frame.pixelBuffer), h = CVPixelBufferGetHeight(frame.pixelBuffer)
        var backing: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(nil, cache, frame.pixelBuffer, nil,
                .bgra8Unorm, w, h, 0, &backing) == kCVReturnSuccess,
              let backing, let texture = CVMetalTextureGetTexture(backing) else { throw CatalogFailure.texture }
        self.backing = backing
        self.texture = texture
        uv = SIMD4(Float(frame.windowRect.minX) / Float(w), Float(frame.windowRect.minY) / Float(h),
                   Float(frame.windowRect.width) / Float(w), Float(frame.windowRect.height) / Float(h))
    }
}

private enum CatalogFailure: String, LocalizedError {
    case disabled = "Effects are paused."
    case window = "No eligible standard window is available on the current Space."
    case texture = "Unable to create the captured window texture."
    case metal = "Metal rendering is unavailable."
    case gpu = "The GPU could not render the captured window."
    case accessibility = "Accessibility could not safely move this exact window."
    case thermal = "macOS reports critical thermal pressure. Heavy effects are temporarily paused by the safety budget."
    case budget = "The rendering budget has no usable mesh or particle resources."
    case captureLimit = "The window capture exceeds the 32-megapixel memory limit. Try a smaller window."
    case allocation = "The effect could not allocate its render textures. Try again or reduce render quality."
    case busy = "Rendering is finishing another frame. Try again in a moment."
    case composition = "Physics and interactive overviews require a single enabled layer."
    var errorDescription: String? { rawValue }
}

/// Serial AX ownership: cancellation closes the gate immediately, then enqueues an
/// exact-origin restore behind any in-flight move. No stale move can follow restore.
final class CatalogWindowLease: @unchecked Sendable {
    let element: AXUIElement
    let info: WindowInfo
    private let lock = NSLock()
    private let mutationLock = NSLock()
    private var cancelled = false
    private var pending: CGPoint?
    private var scheduled = false

    init(element: AXUIElement, info: WindowInfo) {
        self.element = element; self.info = info
        AXUIElementSetMessagingTimeout(element, 0.25)
    }

    func move(to point: CGPoint) {
        lock.lock()
        guard !cancelled else { lock.unlock(); return }
        pending = point
        let submit = !scheduled
        scheduled = true
        lock.unlock()
        guard submit else { return }
        AXBridge.queue(for: info.pid).async { [self] in
            mutationLock.lock()
            defer { mutationLock.unlock() }
            lock.lock()
            let point = cancelled ? nil : pending
            pending = nil; scheduled = false
            lock.unlock()
            if let point { AXBridge.setPosition(element, point) }
        }
    }

    func park() async -> Bool {
        let (point, screens) = await MainActor.run { (NSScreen.parkingPoint, NSScreen.screens.map(\.cgFrame)) }
        let moved: Bool = await withCheckedContinuation { continuation in
            AXBridge.queue(for: info.pid).async { [self] in
                mutationLock.lock()
                defer { mutationLock.unlock() }
                lock.lock(); let allowed = !cancelled; lock.unlock()
                guard allowed, AXBridge.frame(of: element) == info.frame else { continuation.resume(returning: false); return }
                var origin = point
                guard let value = AXValueCreate(.cgPoint, &origin) else { continuation.resume(returning: false); return }
                continuation.resume(returning: AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success)
            }
        }
        guard moved else { return false }
        // AppKit may acknowledge AXPosition before applying/constraining the frame.
        // Verify the visible footprint, not an origin AppKit is allowed to adjust.
        for attempt in 0..<6 {
            if attempt > 0 { try? await Task.sleep(for: .milliseconds(16)) }
            let parked: Bool = await withCheckedContinuation { continuation in
                AXBridge.queue(for: info.pid).async { [self] in
                    lock.lock(); let allowed = !cancelled; lock.unlock()
                    guard allowed, let actual = AXBridge.frame(of: element), actual.size == info.frame.size else {
                        continuation.resume(returning: false); return
                    }
                    continuation.resume(returning: screens.allSatisfy {
                        let overlap = actual.intersection($0)
                        return overlap.isNull || overlap.width <= 2 || overlap.height <= 2
                    })
                }
            }
            if parked { return true }
            if Task.isCancelled { return false }
        }
        return false
    }

    /// Minimize is a real native action. The original origin is still restored,
    /// while the minimized state is deliberately left owned by the user's click.
    func minimize() {
        AXBridge.queue(for: info.pid).async { [self] in
            mutationLock.lock()
            defer { mutationLock.unlock() }
            lock.lock(); let allowed = !cancelled; lock.unlock()
            if allowed { AXBridge.setMinimized(element, true) }
        }
    }

    func isMinimized() async -> Bool? {
        await withCheckedContinuation { continuation in
            AXBridge.urgentQueue.async { [self] in
                var value: CFTypeRef?
                guard AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &value) == .success,
                      let minimized = value as? NSNumber else { continuation.resume(returning: nil); return }
                continuation.resume(returning: minimized.boolValue)
            }
        }
    }

    func restore(completion: @escaping @Sendable () -> Void = {}) {
        lock.lock(); cancelled = true; pending = nil; lock.unlock()
        AXBridge.queue(for: info.pid).async { [self] in
            mutationLock.lock()
            restoreOrigin()
            mutationLock.unlock()
            completion()
        }
    }

    /// Quit cannot depend on the main run loop or a stalled per-app queue.
    /// The lock serializes this urgent restore behind any AX mutation already running.
    func restoreForTermination(in group: DispatchGroup) {
        lock.lock(); cancelled = true; pending = nil; lock.unlock()
        group.enter()
        AXBridge.urgentQueue.async { [self] in
            mutationLock.lock()
            restoreOrigin()
            mutationLock.unlock()
            group.leave()
        }
    }

    /// AXSet may acknowledge a move before AppKit/WindowServer apply it.
    /// Poll on this worker only; the termination caller has its own global 0.8s cap.
    private func restoreOrigin() {
        AXUIElementSetMessagingTimeout(element, 0.1)
        AXBridge.setPosition(element, info.frame.origin)
        let deadline = CACurrentMediaTime() + 0.6
        repeat {
            if AXBridge.frame(of: element)?.origin == info.frame.origin,
               WindowLocator.frame(of: info.id)?.origin == info.frame.origin { return }
            Thread.sleep(forTimeInterval: 0.01)
        } while CACurrentMediaTime() < deadline
    }
}

/// Real desktop catalog adapter. Preview never parks, raises, minimizes or closes a window.
@MainActor
final class CatalogRuntime: NSObject, ObservableObject, OverlayContent {
    static let shared = CatalogRuntime()
    @Published private(set) var isPlaying = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var shaderStatus = "Not compiled"

    private let settings: Settings
    private let budgetProvider: @MainActor () -> RenderBudget
    private let windowFilter: @MainActor (WindowInfo) -> Bool
    private let qualityManager: RenderQualityManager?
    private var qualityObservation: AnyCancellable?
    private var lastFailure: CatalogFailure?
    private let capture = WindowCapture()
    private var metal: MTLDevice?
    private var queue: MTLCommandQueue?
    private var renderer: CatalogEffectRenderer?
    private var compositor: LayerCompositor?
    /// Set while a document with built-in layers plays: compositions cover this rect, not the window.
    private var compositeStage: CGRect?
    private var cache: CVMetalTextureCache?
    private var generation = UUID()
    private var previewGeneration = UUID()
    private var cached: (info: WindowInfo, capture: CatalogCapture)?
    private var captureTask: (id: CGWindowID, task: Task<CapturedFrame, Error>)?
    private var overlays: [OverlayWindow] = []
    private var shields: [NSWindow] = []
    private var timer: Timer?
    private var leases: [CatalogWindowLease] = []
    private var restoringLeases: [ObjectIdentifier: CatalogWindowLease] = [:]
    private var minimizeRestorations: [ObjectIdentifier: @MainActor () -> Void] = [:]
    private var entries: [Entry] = []
    private var document: StudioDocument?
    private var began: Double = 0
    private var previous: Double = 0
    private var lastRendered: Double = 0
    private var overview = false
    private var overviewStage: CGRect?
    private enum OverviewPhase { case entering(Double), shown, leaving(Double, chosen: Int?) }
    private var overviewPhase = OverviewPhase.shown
    private var overviewState = OverviewState()
    private var overviewOrder: [Int] = []
    private var overviewSelected: Int?
    private var overviewFocusTarget = 0.0
    private var overviewSpinVelocity = 0.0
    private var overviewTick = 0.0
    private var overviewTitles: [String] = []
    private var overviewEffect: EffectPreset?
    private var dynamics: CatalogDynamics?
    private var targets: [CGRect] = []
    private var composed: MTLTexture?
    private var composing = false
    private var resourceFailures = 0
    private var inFlightCompositions = 0

    private struct Entry {
        let source: CatalogCapture
        let info: WindowInfo
        var rect: CGRect
        var preset: EffectPreset
    }

    /// Isolated Settings/budgets let tests avoid changing standard preferences.
    init(settings: Settings = Settings(), budget: @escaping @MainActor () -> RenderBudget = { RenderQualityManager.shared.budget },
         qualityManager: RenderQualityManager? = nil,
         windowFilter: @escaping @MainActor (WindowInfo) -> Bool = { _ in true }) {
        self.settings = settings
        budgetProvider = budget
        self.windowFilter = windowFilter
        self.qualityManager = qualityManager
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(interrupted), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        center.addObserver(self, selector: #selector(preferencesChanged), name: UserDefaults.didChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(terminating), name: NSApplication.willTerminateNotification, object: nil)
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.willSleepNotification,
                     NSWorkspace.screensDidSleepNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(interrupted), name: name, object: nil)
        }
        qualityObservation = (qualityManager ?? .shared).$budget.dropFirst().sink { [weak self] budget in
            guard let self, self.lastFailure == .thermal, budget.allowsExpensive else { return }
            self.clearError()
        }
    }

    @objc nonisolated private func interrupted() {
        if Thread.isMainThread { MainActor.assumeIsolated { stop() } }
        else { Task { @MainActor [weak self] in self?.stop() } }
    }
    @objc private func terminating() { stop(terminating: true) }
    @objc nonisolated private func preferencesChanged() {
        if Thread.isMainThread { MainActor.assumeIsolated { if !settings.enabled { stop() } } }
        else { Task { @MainActor [weak self] in if let self, !self.settings.enabled { self.stop() } } }
    }

    var device: MTLDevice { metal! }
    var hasScene: Bool { !entries.isEmpty }
    var capturedWindowCount: Int { entries.count }
    var capturedPixelCount: Int { entries.reduce(0) { $0 + $1.source.texture.width * $1.source.texture.height } }
    var sceneBounds: CGRect { entries.isEmpty ? .null : NSScreen.screens.reduce(.null) { $0.union($1.cgFrame) } }

    /// A page change/edit or new attempt must not display a previous operation's refusal.
    func clearError() { lastFailure = nil; errorMessage = nil }

    private func report(_ error: Error) {
        lastFailure = error as? CatalogFailure
        errorMessage = error.localizedDescription
    }

    /// Filtering is shared with capture; an explicit invalid ID never falls back to another window.
    func availableWindows() -> [ManagedWindow] {
        let windows = Dictionary(uniqueKeysWithValues: eligible().map { ($0.id, $0) })
        let metadata = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return metadata.compactMap { entry in
            guard let id = entry[kCGWindowNumber as String] as? UInt32, let info = windows[id] else { return nil }
            return ManagedWindow(id: id, owner: entry[kCGWindowOwnerName as String] as? String ?? "Unknown app",
                title: entry[kCGWindowName as String] as? String ?? "", width: Int(info.frame.width), height: Int(info.frame.height))
        }
    }

    private func eligible() -> [WindowInfo] {
        let own = ProcessInfo.processInfo.processIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { e in
            guard (e[kCGWindowLayer as String] as? Int) == 0,
                  (e[kCGWindowAlpha as String] as? Double ?? 1) > 0.97,
                  let id = e[kCGWindowNumber as String] as? UInt32,
                  let pid = e[kCGWindowOwnerPID as String] as? Int, pid_t(pid) != own,
                  !AppExclusions.contains(pid: pid_t(pid)),
                  let bounds = e[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds), rect.width >= 80, rect.height >= 40,
                  NSScreen.screens.contains(where: { $0.cgVisibleFrame.intersects(rect) }) else { return nil }
            let info = WindowInfo(id: id, pid: pid_t(pid), frame: rect)
            return windowFilter(info) ? info : nil
        }
    }

    private func selected(_ id: CGWindowID?) throws -> WindowInfo {
        let windows = eligible()
        if let id { guard let w = windows.first(where: { $0.id == id }) else { throw CatalogFailure.window }; return w }
        // The frontmost app's window, or, when that is Kinetiq itself (its own windows are never
        // targets), the topmost eligible window. An explicit ID above never falls back.
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let w = windows.first(where: { $0.pid == pid }) ?? windows.first else { throw CatalogFailure.window }
        return w
    }

    /// The frontmost app's eligible window and its exact AX element, for one-off desktop actions.
    func frontTarget(_ id: CGWindowID? = nil) async -> (WindowInfo, AXUIElement)? {
        guard settings.enabled, let info = try? selected(id), let element = await exactElement(info) else { return nil }
        return (info, element)
    }

    private func exactElement(_ info: WindowInfo) async -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        return await withCheckedContinuation { continuation in
            AXBridge.queue(for: info.pid).async {
                let element = AXBridge.findWindow(info, hitPoint: CGPoint(x: info.frame.midX, y: info.frame.minY + 12))
                guard let element, AXBridge.windowID(of: element) == info.id,
                      AXBridge.isStandardWindow(element), !AXBridge.isFullScreen(element),
                      AXBridge.frame(of: element) == info.frame else { continuation.resume(returning: nil); return }
                continuation.resume(returning: element)
            }
        }
    }

    private func prepare() throws {
        if renderer != nil { return }
        guard let metal = MTLCreateSystemDefaultDevice(), let queue = metal.makeCommandQueue() else { throw CatalogFailure.metal }
        do {
            let renderer = try CatalogEffectRenderer(device: metal)
            var cache: CVMetalTextureCache?
            guard CVMetalTextureCacheCreate(nil, nil, metal, nil, &cache) == kCVReturnSuccess, let cache else { throw CatalogFailure.texture }
            self.metal = metal; self.queue = queue; self.renderer = renderer; self.cache = cache
            compositor = LayerCompositor(device: metal)
            shaderStatus = "Metal compiled · BGRA8 Display P3"
        } catch { shaderStatus = error.localizedDescription; throw error }
    }

    private func check(_ layer: StudioLayer) throws {
        guard settings.enabled else { throw CatalogFailure.disabled }
        if layer.isBuiltin {
            do { try LayerCompositor.check(layer, budget: budgetProvider()) }
            catch CompositorError.thermal { throw CatalogFailure.thermal }
            catch CompositorError.budget { throw CatalogFailure.budget }
            return
        }
        try check(layer.preset)
    }

    private func check(_ preset: EffectPreset) throws {
        guard settings.enabled else { throw CatalogFailure.disabled }
        _ = try preset.validated()
        let budget = budgetProvider()
        guard !EffectCatalog.descriptor(preset.effect).expensive || budget.allowsExpensive else { throw CatalogFailure.thermal }
        guard budget.meshLimit > 0,
              (preset.effect != .shatter && preset.effect != .explode) || budget.maxParticles > 0 else { throw CatalogFailure.budget }
    }

    private func source(_ info: WindowInfo) async throws -> CatalogCapture {
        if let cached, cached.info.id == info.id, cached.info.pid == info.pid, cached.info.frame == info.frame,
           CACurrentMediaTime() - cached.capture.frame.capturedAt <= 2 { return cached.capture }
        // Reject oversized captures before ScreenCaptureKit allocates a native IOSurface.
        let scale = NSScreen.containing(cgPoint: CGPoint(x: info.frame.midX, y: info.frame.midY))?.backingScaleFactor ?? 2
        guard WindowCapture.estimatedPixelCount(windowSize: info.frame.size, scale: scale)
            <= Double(WindowCapture.maximumPixelCount) else { throw CatalogFailure.captureLimit }
        let task: Task<CapturedFrame, Error>
        if let current = captureTask, current.id == info.id { task = current.task }
        else {
            task = Task {
                for _ in 0..<5 {
                    try Task.checkCancellation()
                    let frame = try await capture.capture(info)
                    if frame.isPainted { return frame }
                    try await Task.sleep(for: .milliseconds(16))
                }
                throw CaptureError.emptySample
            }
            captureTask = (info.id, task)
        }
        let frame: CapturedFrame
        do { frame = try await task.value }
        catch { if captureTask?.id == info.id { captureTask = nil }; throw error }
        if captureTask?.id == info.id { captureTask = nil }
        guard !Task.isCancelled, frame.isPainted, frame.pointSize == info.frame.size else { throw CancellationError() }
        guard CVPixelBufferGetWidth(frame.pixelBuffer) * CVPixelBufferGetHeight(frame.pixelBuffer)
            <= WindowCapture.maximumPixelCount else { throw CatalogFailure.captureLimit }
        return try CatalogCapture(frame, cache: cache!)
    }

    /// Offscreen Studio composition uses only actual capture pixels and local layer seconds.
    func preview(document: StudioDocument, time: Double, windowID: CGWindowID? = nil) async throws -> NSImage {
        let document = try document.validated()
        guard time.isFinite else { throw CatalogFailure.gpu }
        guard settings.enabled else { throw CatalogFailure.disabled }
        let token = UUID(); previewGeneration = token
        try prepare()
        let info = try selected(windowID)
        try validatePreview(token)
        let source = try await source(info)
        try validatePreview(token)
        guard eligible().contains(where: { $0.id == info.id && $0.frame == info.frame }) else { throw CatalogFailure.window }
        cached = (info, source); captureTask = nil
        let texture = try await renderImage(source: source, rect: info.frame, document: document, time: time)
        try validatePreview(token)
        return try image(texture, size: info.frame.size)
    }

    /// Also used by native integration tests with their own disposable document;
    /// unlike desktop playback this never requires or performs an AX mutation.
    func previewCaptured(_ frame: CapturedFrame, windowFrame: CGRect,
                         document: StudioDocument, time: Double) async throws -> NSImage {
        let document = try document.validated()
        guard settings.enabled else { throw CatalogFailure.disabled }
        guard time.isFinite, frame.isPainted, frame.pointSize == windowFrame.size else { throw CatalogFailure.window }
        let token = UUID(); previewGeneration = token
        try prepare()
        let source = try CatalogCapture(frame, cache: cache!)
        let output = try await renderImage(source: source, rect: windowFrame, document: document, time: time)
        try validatePreview(token)
        return try image(output, size: windowFrame.size)
    }

    private func validatePreview(_ token: UUID) throws {
        guard token == previewGeneration, !Task.isCancelled, settings.enabled else { throw CancellationError() }
    }

    func play(_ preset: EffectPreset, windowID: CGWindowID? = nil, trigger: EffectTrigger = .manual) async {
        await playDocument(StudioDocument(duration: preset.duration, layers: [StudioLayer(preset: preset)]),
                           windowID: windowID, trigger: trigger, effect: .catalog(preset.effect))
    }

    func playDocument(_ document: StudioDocument, windowID: CGWindowID? = nil,
                      trigger: EffectTrigger = .manual, effect: LibraryEffect? = nil) async {
        stop()
        let token = generation
        do {
            let document = try document.validated()
            let enabled = document.layers.filter(\.enabled)
            guard let primary = enabled.first?.preset else { return }
            for layer in enabled { try check(layer) }
            let specialized = enabled.contains {
                guard !$0.isBuiltin else { return false }
                let kind = EffectCatalog.descriptor($0.preset.effect).rendering
                return kind == .dynamics || kind == .multiWindow
            }
            guard !specialized || enabled.count == 1 else { throw CatalogFailure.composition }
            isPlaying = true // Includes capture/AX preparation, preventing competing hooks.
            try prepare()
            let primaryInfo = try selected(windowID)
            let multi = !enabled[0].isBuiltin && EffectCatalog.descriptor(primary.effect).rendering == .multiWindow
            let infos = multi ? Array(([primaryInfo] + eligible().filter { $0.id != primaryInfo.id }).prefix(8)) : [primaryInfo]
            var prepared: [Entry] = []
            var elements: [(AXUIElement, WindowInfo)] = []
            for info in infos {
                let pixels = prepared.reduce(0) { $0 + $1.source.texture.width * $1.source.texture.height }
                let scale = NSScreen.containing(cgPoint: CGPoint(x: info.frame.midX, y: info.frame.midY))?.backingScaleFactor ?? 2
                if Double(pixels) + WindowCapture.estimatedPixelCount(windowSize: info.frame.size, scale: scale)
                    > Double(WindowCapture.maximumPixelCount) {
                    if info.id == primaryInfo.id { throw CatalogFailure.captureLimit }
                    continue
                }
                guard let element = await exactElement(info) else {
                    if info.id == primaryInfo.id { throw CatalogFailure.window }; continue
                }
                try validPlayback(token)
                let captured: CatalogCapture
                do { captured = try await source(info) }
                catch CatalogFailure.captureLimit {
                    if info.id == primaryInfo.id { throw CatalogFailure.captureLimit }
                    continue
                }
                try validPlayback(token)
                // The filter's actual scale can differ from the display estimate. Keep the
                // primary and already-admitted captures if an extra window still does not fit.
                guard pixels + captured.texture.width * captured.texture.height <= WindowCapture.maximumPixelCount else {
                    if info.id == primaryInfo.id { throw CatalogFailure.captureLimit }
                    continue
                }
                prepared.append(Entry(source: captured, info: info, rect: info.frame, preset: primary))
                elements.append((element, info))
            }
            guard let first = prepared.first else { throw CatalogFailure.window }
            // Compile, encode, and complete real GPU work BEFORE any live-window mutation.
            let composite = LayerCompositor.needsCompositor(document)
            let ready = composite
                ? try await composeImage(source: first.source, rect: first.info.frame, document: document, time: 0)
                : try await renderImage(source: first.source, rect: first.info.frame, document: document, time: 0)
            try validPlayback(token)
            guard elements.allSatisfy({ pair in eligible().contains { $0.id == pair.1.id && $0.frame == pair.1.frame } }) else { throw CatalogFailure.window }
            self.document = document
            entries = prepared
            composed = ready
            compositeStage = composite ? LayerCompositor.stage(windowFrame: first.info.frame, shadow: first.source.frame.shadow) : nil
            began = CACurrentMediaTime()
            if multi {
                overview = true
                beginOverview(primary)
                showOverviewInput()
            } else {
                let lease = CatalogWindowLease(element: elements[0].0, info: elements[0].1)
                leases = [lease]
                if !composite, primary.effect == .magnet || primary.effect == .gravity {
                    let bounds = NSScreen.containing(cgPoint: CGPoint(x: primaryInfo.frame.midX, y: primaryInfo.frame.midY))?.cgVisibleFrame
                    guard let bounds else { throw CatalogFailure.window }
                    dynamics = CatalogDynamics(frame: primaryInfo.frame, bounds: bounds)
                    targets = eligible().filter { $0.id != primaryInfo.id }.map(\.frame)
                    entries = [] // Actual AX physics, never a shader stand-in over the live window.
                } else {
                    showOverlays()
                    guard await lease.park() else { throw CatalogFailure.accessibility }
                    try validPlayback(token)
                }
            }
            startClock()
            KinetiqTelemetry.emit(trigger.usageEvent(effectID: effect?.id ?? "custom"))
        } catch {
            // An obsolete async caller must not tear down a newer scene.
            if generation == token { stop(); if !(error is CancellationError) { report(error) } }
        }
    }

    private func validPlayback(_ token: UUID) throws {
        guard token == generation, !Task.isCancelled, settings.enabled else { throw CancellationError() }
    }

    /// A saved Studio composition on a frozen capture (Close/Minimize of a custom effect).
    /// Returns false, before any overlay appears, if the first frame cannot be rendered.
    @discardableResult
    func playCaptured(_ frame: CapturedFrame, windowFrame: CGRect, document: StudioDocument,
                      trigger: EffectTrigger = .close) async -> Bool {
        guard !isPlaying, frame.isPainted, frame.pointSize == windowFrame.size,
              let document = try? document.validated(), !document.layers.filter(\.enabled).isEmpty else { return false }
        do {
            for layer in document.layers where layer.enabled { try check(layer) }
            try prepare()
            let source = try CatalogCapture(frame, cache: cache!)
            let ready = try await composeImage(source: source, rect: windowFrame, document: document, time: 0)
            guard !isPlaying, settings.enabled else { return false }
            stop()
            entries = [Entry(source: source, info: WindowInfo(id: frame.windowID, pid: 0, frame: windowFrame),
                             rect: windowFrame, preset: document.layers[0].preset)]
            self.document = document
            composed = ready
            compositeStage = LayerCompositor.stage(windowFrame: windowFrame, shadow: frame.shadow)
            began = CACurrentMediaTime()
            showOverlays(); startClock()
            KinetiqTelemetry.emit(trigger.usageEvent(effectID: "custom"))
            return true
        } catch { report(error); return false }
    }

    /// Close/minimize hooks own their native lifecycle; this path NEVER recaptures or moves windows.
    @discardableResult
    func playCaptured(_ frame: CapturedFrame, windowFrame: CGRect, preset: EffectPreset,
                      trigger: EffectTrigger? = nil) -> Bool {
        guard !isPlaying, frame.isPainted, frame.pointSize == windowFrame.size else { return false }
        do {
            try check(preset); try prepare()
            let source = try CatalogCapture(frame, cache: cache!)
            // Validate allocations before a native hook parks its live window.
            _ = try makeTargets(source: source)
            stop()
            entries = [Entry(source: source, info: WindowInfo(id: frame.windowID, pid: 0, frame: windowFrame), rect: windowFrame, preset: preset)]
            document = StudioDocument(duration: preset.duration, layers: [StudioLayer(preset: preset)])
            began = CACurrentMediaTime()
            showOverlays(); startClock()
            KinetiqTelemetry.emit((trigger ?? preset.trigger).usageEvent(effectID: LibraryEffect.catalog(preset.effect).id))
            return true
        } catch { report(error); return false }
    }

    func stop(terminating: Bool = false, preservingMinimize: Bool = false) {
        generation = UUID(); previewGeneration = UUID()
        captureTask?.task.cancel(); captureTask = nil
        timer?.invalidate(); timer = nil
        let restoring = leases.filter { !preservingMinimize || minimizeRestorations[ObjectIdentifier($0)] == nil }
        leases.removeAll { lease in restoring.contains { $0 === lease } }
        let oldOverlays = overlays; overlays = []
        let oldShields = shields; shields = []
        let callbacks = restoring.compactMap { minimizeRestorations.removeValue(forKey: ObjectIdentifier($0)) }
        let group = DispatchGroup()
        let urgent = terminating ? Array(restoringLeases.values) : []
        for lease in restoring + urgent {
            if terminating { lease.restoreForTermination(in: group) }
            else {
                restoringLeases[ObjectIdentifier(lease)] = lease
                group.enter()
                lease.restore { group.leave() }
            }
        }
        let dismiss: @MainActor () -> Void = {
            for lease in restoring { self.restoringLeases.removeValue(forKey: ObjectIdentifier(lease)) }
            oldOverlays.forEach { $0.close() }
            oldShields.forEach { $0.close() }
            callbacks.forEach { $0() }
        }
        if terminating {
            _ = group.wait(timeout: .now() + 0.8)
            dismiss()
        } else if restoring.isEmpty { dismiss() }
        else { group.notify(queue: .main) { MainActor.assumeIsolated { dismiss() } } }
        entries = []; dynamics = nil; document = nil; overview = false; compositeStage = nil
        overviewStage = nil; overviewEffect = nil; overviewOrder = []; overviewTitles = []
        composed = nil; composing = false
        resourceFailures = 0
        isPlaying = false
        clearError()
    }

    /// Native minimize shares the same Space/sleep/disable restoration boundary.
    func ownMinimizeLease(_ lease: CatalogWindowLease, afterRestore: @escaping @MainActor () -> Void = {}) {
        leases.append(lease)
        minimizeRestorations[ObjectIdentifier(lease)] = afterRestore
    }
    func releaseMinimizeLease(_ lease: CatalogWindowLease, completion: @escaping @MainActor () -> Void = {}) {
        let callback = minimizeRestorations.removeValue(forKey: ObjectIdentifier(lease))
        restoringLeases[ObjectIdentifier(lease)] = lease
        lease.restore { [weak self] in
            DispatchQueue.main.async {
                self?.restoringLeases.removeValue(forKey: ObjectIdentifier(lease))
                callback?()
                completion()
            }
        }
        leases.removeAll { $0 === lease }
    }

    private func trackCompletion(_ command: MTLCommandBuffer) {
        guard let qualityManager else { RenderQualityManager.trackGPUCompletion(command); return }
        command.addCompletedHandler { completed in
            guard completed.status == .completed, completed.gpuStartTime > 0 else { return }
            let seconds = completed.gpuEndTime - completed.gpuStartTime
            guard seconds.isFinite, (0.00001...1).contains(seconds) else { return }
            Task { @MainActor in qualityManager.recordGPUTime(seconds) }
        }
    }

    private func startClock() {
        clearError(); isPlaying = true
        began = CACurrentMediaTime(); previous = began
        lastRendered = 0
        let fps = max(1, min(120, budgetProvider().secondaryFPS))
        timer = Timer(timeInterval: 1 / Double(fps), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func tick() {
        guard settings.enabled, let document else { stop(); return }
        let now = CACurrentMediaTime(), time = now - began
        let budget = budgetProvider()
        do { for layer in document.layers where layer.enabled { try check(layer) } }
        catch { stop(); report(error); return }
        if !overview && time >= document.duration { stop(preservingMinimize: true); return }
        if var dynamics, let layer = document.layers.first(where: { $0.enabled && time >= $0.start && time <= $0.start + $0.preset.duration }) {
            dynamics.advance(now - previous, effect: layer.preset.effect,
                             parameters: values(layer.preset, time: time - layer.start).mapValues(Double.init), targets: targets)
            self.dynamics = dynamics
            leases.first?.move(to: dynamics.body.frame.origin)
        }
        previous = now
        // The overview's travel and highlight follow the display, not the secondary-rate budget.
        if overview { advanceOverview(now); overlays.forEach { $0.render() }; return }
        guard now - lastRendered >= 1 / Double(max(1, min(120, budget.secondaryFPS))) else { return }
        lastRendered = now
        if !overview, dynamics == nil, !composing, compositeStage != nil || document.layers.filter(\.enabled).count > 1,
           let entry = entries.first {
            composing = true
            let token = generation
            let composite = compositeStage != nil
            Task {
                do {
                    let output = composite
                        ? try await composeImage(source: entry.source, rect: entry.rect, document: document, time: time)
                        : try await renderImage(source: entry.source, rect: entry.rect, document: document, time: time)
                    guard generation == token, settings.enabled else { return }
                    composed = output; composing = false
                } catch {
                    guard generation == token else { return }
                    stop(); report(error)
                }
            }
        }
        overlays.forEach { $0.render() }
    }

    private func showOverlays() {
        overlays = NSScreen.screens.map { OverlayWindow(screen: $0, renderer: self, level: NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)) }
        overlays.forEach { $0.show(); $0.render() }
    }

    // MARK: - Interactive overview

    /// Windows start where they really are and fly into the arrangement.
    private func beginOverview(_ preset: EffectPreset) {
        guard let screen = NSScreen.containing(cgPoint: CGPoint(x: entries[0].rect.midX, y: entries[0].rect.midY)) ?? NSScreen.screens.first else { return }
        overviewStage = screen.cgVisibleFrame.insetBy(dx: 60, dy: 70)
        overviewEffect = preset
        overviewState = OverviewState(amount: 0, focus: 0, spin: 0, hover: Array(repeating: 0, count: entries.count))
        overviewSelected = 0
        overviewFocusTarget = 0
        overviewSpinVelocity = 0
        overviewPhase = .entering(CACurrentMediaTime())
        overviewTick = CACurrentMediaTime()
        let metadata = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        overviewTitles = entries.map { entry in
            let app = NSRunningApplication(processIdentifier: entry.info.pid)?.localizedName ?? "Window"
            let title = metadata.first { ($0[kCGWindowNumber as String] as? UInt32) == entry.info.id }?[kCGWindowName as String] as? String ?? ""
            return title.isEmpty ? app : "\(app) — \(title)"
        }
        applyOverviewLayout()
    }

    private func applyOverviewLayout() {
        guard let stage = overviewStage, let preset = overviewEffect else { return }
        let result = OverviewLayout.place(effect: preset.effect, preset: preset, homes: entries.map(\.info.frame),
                                          stage: stage, state: overviewState)
        for (index, placement) in result.placements.enumerated() where index < entries.count {
            entries[index].rect = placement.rect
            entries[index].preset = placement.preset
        }
        overviewOrder = result.order
        if case .leaving(_, let chosen?) = overviewPhase {
            overviewOrder.removeAll { $0 == chosen }
            overviewOrder.append(chosen)
        }
    }

    private func advanceOverview(_ now: Double) {
        let dt = min(0.05, max(0, now - overviewTick))
        overviewTick = now
        switch overviewPhase {
        case .entering(let start):
            let t = (now - start) / OverviewLayout.enterDuration
            overviewState.amount = OverviewLayout.enter(t)
            if t >= 1 { overviewPhase = .shown; overviewState.amount = 1 }
        case .shown:
            overviewState.amount = 1
        case .leaving(let start, let chosen):
            let t = (now - start) / OverviewLayout.leaveDuration
            overviewState.amount = 1 - OverviewLayout.leave(t)
            if t >= 1 { finishOverview(chosen); return }
        }
        let leaving: Bool = { if case .leaving = overviewPhase { return true }; return false }()
        for index in overviewState.hover.indices {
            let target = !leaving && index == overviewSelected ? 1.0 : 0
            overviewState.hover[index] += (target - overviewState.hover[index]) * min(1, dt * 14)
        }
        overviewState.focus += (overviewFocusTarget - overviewState.focus) * min(1, dt * 10)
        if overviewEffect?.effect == .orbit, !leaving {
            overviewState.spin += dt * (0.12 + overviewSpinVelocity)
            overviewSpinVelocity *= exp(-dt * 3)
        }
        applyOverviewLayout()
        let fade = min(1, max(0, overviewState.amount))
        shields.forEach { $0.alphaValue = CGFloat(fade) }
        updateOverviewLabel()
    }

    private func updateOverviewLabel() {
        let leaving: Bool = { if case .leaving = overviewPhase { return true }; return false }()
        for shield in shields {
            guard let input = shield.contentView as? CatalogOverviewInput else { continue }
            guard !leaving, let index = overviewSelected, index < entries.count, index < overviewTitles.count else {
                input.showLabel(nil, below: .zero); continue
            }
            let rect = entries[index].rect
            let screen = shield.frame
            let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.height
            // Global Y-down to this shield's view coordinates.
            let local = CGRect(x: rect.minX - screen.minX, y: primaryHeight - rect.maxY - screen.minY,
                               width: rect.width, height: rect.height)
            input.showLabel(overviewTitles[index], below: local)
        }
    }

    private func showOverviewInput() {
        NSApp.activate()
        for screen in NSScreen.screens {
            let panel = CatalogOverviewWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false; panel.level = .floating
            panel.backgroundColor = NSColor.black.withAlphaComponent(0.72); panel.isOpaque = false
            panel.alphaValue = 0
            panel.acceptsMouseMovedEvents = true
            panel.collectionBehavior = [.fullScreenAuxiliary, .stationary]
            let input = CatalogOverviewInput(frame: CGRect(origin: .zero, size: screen.frame.size))
            input.dismiss = { [weak self] in self?.leaveOverview(chosen: nil) }
            input.choose = { [weak self] point in self?.chooseOverview(point) }
            input.hover = { [weak self] point in self?.hoverOverview(point) }
            input.scroll = { [weak self] dx, dy in self?.scrollOverview(dx: dx, dy: dy) }
            input.key = { [weak self] key in self?.overviewKey(key) }
            panel.contentView = input; panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(input)
            shields.append(panel)
        }
        showOverlays()
    }

    /// Index of the frontmost window under `point`, tested against the projected surface.
    private func overviewHit(_ point: CGPoint) -> Int? {
        guard let stage = overviewStage else { return nil }
        let screen = NSScreen.containing(cgPoint: CGPoint(x: stage.midX, y: stage.midY))?.cgFrame ?? stage
        return overviewOrder.reversed().first { index in
            index < entries.count && Self.overviewContains(point, rect: entries[index].rect, preset: entries[index].preset,
                                                           stage: screen, time: 0, screen: screen)
        }
    }

    /// Puts an open overview away with its exit animation; stops anything else.
    func dismissOverview() {
        if overview { leaveOverview(chosen: nil) } else { stop() }
    }

    private var overviewInteractive: Bool {
        if case .leaving = overviewPhase { return false }
        return overview
    }

    private func hoverOverview(_ point: CGPoint) {
        guard overviewInteractive, let index = overviewHit(point) else { return }
        overviewSelected = index
    }

    private func chooseOverview(_ point: CGPoint) {
        guard overviewInteractive else { return }
        guard let index = overviewHit(point) else { leaveOverview(chosen: nil); return }
        // A side card of the carousel comes to the front first; the front one is chosen.
        if overviewEffect?.effect == .workspaceCube, abs(Double(index) - overviewState.focus) > 0.5 {
            overviewFocusTarget = Double(index); overviewSelected = index
            return
        }
        leaveOverview(chosen: index)
    }

    private func scrollOverview(dx: CGFloat, dy: CGFloat) {
        guard overviewInteractive else { return }
        let delta = Double(abs(dx) > abs(dy) ? dx : dy)
        switch overviewEffect?.effect {
        case .workspaceCube?:
            overviewFocusTarget = min(Double(entries.count - 1), max(0, overviewFocusTarget - delta / 40))
            overviewSelected = Int(overviewFocusTarget.rounded())
        case .orbit?:
            overviewSpinVelocity += delta * 0.04
        default: break
        }
    }

    enum OverviewKey { case left, right, up, down, choose, next, dismiss }

    private func overviewKey(_ key: OverviewKey) {
        guard overviewInteractive, !entries.isEmpty else { return }
        let count = entries.count
        let current = overviewSelected ?? 0
        let columns = min(4, max(1, Int(ceil(sqrt(Double(count))))))
        func select(_ index: Int) {
            let index = (index % count + count) % count
            overviewSelected = index
            if overviewEffect?.effect == .workspaceCube { overviewFocusTarget = Double(index) }
            if overviewEffect?.effect == .orbit {
                // Turn the ring so the chosen window comes to the front.
                let theta = 2 * Double.pi * Double(index) / Double(count) + overviewState.spin
                    + (overviewEffect?.value("angle", at: 0) ?? 0) * .pi / 180
                overviewSpinVelocity = remainder(.pi / 2 - theta, 2 * .pi) * 3
            }
        }
        switch key {
        case .left: select(current - 1)
        case .right, .next: select(current + 1)
        case .up: select(overviewEffect?.effect == .expose3D ? current - columns : current - 1)
        case .down: select(overviewEffect?.effect == .expose3D ? current + columns : current + 1)
        case .choose: leaveOverview(chosen: current)
        case .dismiss: leaveOverview(chosen: nil)
        }
    }

    /// Every window flies back to its real frame; the chosen one stays on top and is raised.
    private func leaveOverview(chosen: Int?) {
        guard overview else { stop(); return }
        if case .leaving = overviewPhase { return }
        overviewPhase = .leaving(CACurrentMediaTime(), chosen: chosen)
        shields.forEach { ($0.contentView as? CatalogOverviewInput)?.showLabel(nil, below: .zero) }
    }

    private func finishOverview(_ chosen: Int?) {
        guard let chosen, chosen < entries.count else { stop(); return }
        let info = entries[chosen].info
        let token = generation
        Task {
            let element = await exactElement(info)
            guard generation == token else { return }
            stop()
            if let element { AXBridge.queue(for: info.pid).async { AXBridge.raise(element, pid: info.pid) } }
        }
    }

    /// Matches the renderer's planar overview geometry at its fixed 0.5 progress.
    /// Test the projected quad, not the untransformed layout cell or its bounding box.
    static func overviewContains(_ point: CGPoint, rect: CGRect, preset: EffectPreset, stage: CGRect,
                                 time: Double = 0, screen: CGRect? = nil) -> Bool {
        guard stage.contains(point) else { return false }
        let time = min(preset.duration, max(0, time))
        let amplitude = preset.value("amplitude", at: time)
        let viewport = screen ?? stage
        let yaw: Double, pitch: Double, scale: Double, depth: Double, depthScale: Double
        switch preset.effect {
        case .workspaceCube:
            yaw = preset.value("angle", at: time) * .pi / 180 * amplitude
            pitch = 0; scale = 1; depth = 0
            depthScale = preset.value("perspective", at: time)
        case .orbit:
            let phase = Double.pi * preset.value("speed", at: time) + preset.value("angle", at: time) * .pi / 180
            yaw = sin(phase) * 0.7 * amplitude; pitch = 0
            scale = 1 - 0.18 * amplitude
            depth = (1 + sin(phase)) * min(viewport.width, viewport.height) * preset.value("radius", at: time) * 0.25 * amplitude
            depthScale = 1
        case .expose3D:
            yaw = -0.3 * amplitude
            pitch = preset.value("angle", at: time) * .pi / 180 * amplitude
            scale = 1 - min(0.65, amplitude * 0.38)
            depth = rect.width * preset.value("spacing", at: time) * amplitude
            depthScale = 1
        default: return rect.contains(point)
        }
        let distance = max(max(rect.width, rect.height) * 2.5, 800)
        let corners: [CGPoint] = [CGPoint(x: -0.5, y: -0.5), CGPoint(x: 0.5, y: -0.5),
                                  CGPoint(x: 0.5, y: 0.5), CGPoint(x: -0.5, y: 0.5)]
        let polygon = corners.map { corner -> CGPoint in
            let x = corner.x * rect.width * (preset.effect == .expose3D ? scale : 1)
            let y = corner.y * rect.height * (preset.effect == .expose3D ? scale : 1)
            var px = cos(yaw) * x
            var py = cos(pitch) * y + sin(pitch) * sin(yaw) * x
            var z = sin(pitch) * y - cos(pitch) * sin(yaw) * x
            if preset.effect == .workspaceCube { z *= depthScale }
            if preset.effect == .orbit { px *= scale; py *= scale }
            z = min(distance * 0.7, max(-distance * 0.45, z + depth))
            let w = 1 + z / distance
            return CGPoint(x: rect.midX + px / w, y: rect.midY + py / w)
        }
        var sign = 0.0
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            let cross = (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x)
            if abs(cross) < 0.000001 { continue }
            if sign != 0, cross * sign < 0 { return false }
            sign = cross
        }
        return sign != 0
    }

    private func values(_ preset: EffectPreset, time: Double) -> [String: Float] {
        Dictionary(uniqueKeysWithValues: EffectCatalog.descriptor(preset.effect).parameters.map { ($0.id, Float(preset.value($0.id, at: time))) })
    }

    private func encode(_ preset: EffectPreset, time: Double, texture: MTLTexture, uv: SIMD4<Float>, rect: CGRect,
                        screen: CGRect, encoder: MTLRenderCommandEncoder, overview: Bool = false, reverse: Bool = false,
                        budget override: RenderBudget? = nil) {
        let budget = override ?? budgetProvider()
        guard !EffectCatalog.descriptor(preset.effect).expensive || budget.allowsExpensive else { return }
        let parameters = values(preset, time: time)
        let clock = preset.curve.value(at: time / preset.duration)
        let progress = overview ? 0.5 : reverse ? 1 - clock : clock
        renderer?.encode(effect: preset.effect, texture: texture, uvRect: uv, frame: rect, screenRect: screen,
                         progress: Float(progress), amplitude: parameters["amplitude"] ?? 1,
                         speed: parameters["speed"] ?? 1, meshLimit: budget.meshLimit,
                         particleLimit: budget.maxParticles, blurPasses: budget.blurPasses,
                         parameters: parameters, into: encoder)
    }

    func draw(in view: MTKView, screenRect: CGRect) {
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let command = queue?.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            resourceFailures += 1
            if resourceFailures >= 3 { stop(); report(CatalogFailure.gpu) }
            return
        }
        resourceFailures = 0
        let sources = entries.map(\.source)
        let composition = composed
        let time = max(0, CACurrentMediaTime() - began)
        if overview {
            // Back to front; windows travel across the whole screen while entering and leaving.
            for index in overviewOrder where index < entries.count {
                let entry = entries[index]
                guard entry.rect.intersects(screenRect.insetBy(dx: -entry.rect.width, dy: -entry.rect.height)) else { continue }
                encode(entry.preset, time: 0, texture: entry.source.texture, uv: entry.source.uv,
                       rect: entry.rect, screen: screenRect, encoder: encoder, overview: true)
            }
        }
        for entry in entries.reversed() where !overview {
            if let document {
                // Multi-layer and built-in documents are composed offscreen, not independently overdrawn.
                if compositeStage != nil || document.layers.filter(\.enabled).count > 1, let composition {
                    var identity = EffectPreset(effect: .wobbly); identity.parameters["amplitude"] = 0
                    encode(identity, time: 0, texture: composition, uv: SIMD4(0, 0, 1, 1), rect: compositeStage ?? entry.rect,
                           screen: screenRect, encoder: encoder)
                    continue
                }
                for layer in document.layers where layer.enabled && time >= layer.start && time <= layer.start + layer.preset.duration {
                    let local = time - layer.start
                    let reversed = layer.preset.trigger == .open
                          encode(layer.preset, time: local,
                              texture: entry.source.texture, uv: entry.source.uv, rect: entry.rect,
                              screen: screenRect, encoder: encoder, reverse: reversed)
                }
                if !document.layers.contains(where: { $0.enabled && time >= $0.start && time <= $0.start + $0.preset.duration }) {
                    var identity = EffectPreset(effect: .wobbly); identity.parameters["amplitude"] = 0
                    encode(identity, time: 0, texture: entry.source.texture, uv: entry.source.uv, rect: entry.rect,
                           screen: screenRect, encoder: encoder)
                }
            }
        }
        encoder.endEncoding()
        command.addCompletedHandler { [sources, composition] _ in withExtendedLifetime((sources, composition)) {} }
        trackCompletion(command)
        let token = generation
        command.addCompletedHandler { [weak self] command in
            if command.status == .error {
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    self.stop(); self.report(CatalogFailure.gpu)
                }
            }
        }
        command.present(drawable); command.commit()
    }

    /// Aspect-preserving target dimensions, bounded before integer conversion/allocation.
    static func targetSize(_ size: CGSize, scale: Double, maximumDimension: Int = 8192) throws -> (width: Int, height: Int) {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              scale.isFinite, scale > 0, maximumDimension > 0 else { throw CatalogFailure.budget }
        let dimension = Double(min(8192, maximumDimension))
        let factor = min(1, scale, dimension / size.width, dimension / size.height,
                         sqrt(8_000_000 / size.width / size.height))
        return (max(1, Int(floor(size.width * factor))), max(1, Int(floor(size.height * factor))))
    }

    /// Three bounded quality attempts. Exhaustion leaves the native window untouched.
    private func makeTargets(source: CatalogCapture) throws -> (MTLTexture, MTLTexture, RenderBudget) {
        guard let metal else { throw CatalogFailure.metal }
        var budget = budgetProvider()
        for _ in 0..<3 {
            let size = try Self.targetSize(source.frame.windowRect.size, scale: budget.textureScale)
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                width: size.width, height: size.height, mipmapped: false)
            descriptor.storageMode = .shared; descriptor.usage = [.renderTarget, .shaderRead]
            if let a = metal.makeTexture(descriptor: descriptor), let b = metal.makeTexture(descriptor: descriptor) {
                return (a, b, budget)
            }
            budget.textureScale *= 0.5
        }
        throw CatalogFailure.allocation
    }

    /// Built-in and catalog layers through the shared compositor, into a budget-scaled stage texture.
    private func composeImage(source: CatalogCapture, rect: CGRect, document: StudioDocument, time: Double) async throws -> MTLTexture {
        guard inFlightCompositions < 2 else { throw CatalogFailure.busy }
        inFlightCompositions += 1
        defer { inFlightCompositions -= 1 }
        guard let metal, let compositor, let command = queue?.makeCommandBuffer() else { throw CatalogFailure.metal }
        let stage = LayerCompositor.stage(windowFrame: rect, shadow: source.frame.shadow)
        let nativeScale = Double(source.frame.windowRect.width / max(1, source.frame.pointSize.width))
        let budget = budgetProvider()
        let size = try Self.targetSize(CGSize(width: stage.width * nativeScale, height: stage.height * nativeScale),
                                       scale: budget.textureScale)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: size.width, height: size.height, mipmapped: false)
        descriptor.storageMode = .shared; descriptor.usage = [.renderTarget, .shaderRead]
        let layers = LayerCompositor.active(document, at: time).count
        guard let final = metal.makeTexture(descriptor: descriptor) else { throw CatalogFailure.allocation }
        let scratch = layers > 1 ? metal.makeTexture(descriptor: descriptor) : nil
        guard layers <= 1 || scratch != nil else { throw CatalogFailure.allocation }
        do {
            try compositor.encode(document: document, time: time,
                source: LayerCompositor.Source(texture: source.texture, uv: source.uv, shadow: source.frame.shadow),
                windowFrame: rect, stage: stage, final: final, scratch: scratch, budget: budget,
                physics: settings.physics, seed: UInt64(source.frame.windowID), command: command)
        } catch CompositorError.thermal { throw CatalogFailure.thermal }
        catch CompositorError.budget { throw CatalogFailure.budget }
        trackCompletion(command)
        let success: Bool = await withCheckedContinuation { continuation in
            command.addCompletedHandler { [source] completed in
                withExtendedLifetime(source) { continuation.resume(returning: completed.status == .completed) }
            }
            command.commit()
        }
        guard success else { throw CatalogFailure.gpu }
        return final
    }

    /// Sequential budget-scaled ping-pong passes; point size and P3 survive readback.
    private func renderImage(source: CatalogCapture, rect: CGRect, document: StudioDocument, time: Double) async throws -> MTLTexture {
        // Superseded previews still own their GPU resources until completion.
        guard inFlightCompositions < 2 else { throw CatalogFailure.busy }
        inFlightCompositions += 1
        defer { inFlightCompositions -= 1 }
        let (a, b, budget) = try makeTargets(source: source)
        guard let command = queue?.makeCommandBuffer() else { throw CatalogFailure.metal }
        var texture = source.texture, uv = source.uv
        var layers = document.layers.filter { $0.enabled && time >= $0.start && time <= $0.start + $0.preset.duration }
        if layers.isEmpty {
            var identity = EffectPreset(effect: .wobbly); identity.parameters["amplitude"] = 0
            layers = [StudioLayer(preset: identity, start: time)]
        }
        for (index, layer) in layers.enumerated() {
            try check(layer.preset)
            let output = index % 2 == 0 ? a : b
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = output; pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store; pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw CatalogFailure.gpu }
            encode(layer.preset, time: time - layer.start, texture: texture, uv: uv, rect: rect, screen: rect,
                 encoder: encoder, reverse: layer.preset.trigger == .open, budget: budget)
            encoder.endEncoding(); texture = output; uv = SIMD4(0, 0, 1, 1)
        }
        trackCompletion(command)
        let success: Bool = await withCheckedContinuation { continuation in
            command.addCompletedHandler { [source] completed in
                withExtendedLifetime(source) { continuation.resume(returning: completed.status == .completed) }
            }
            command.commit()
        }
        guard success else { throw CatalogFailure.gpu }
        return texture
    }

    private func image(_ texture: MTLTexture, size: CGSize) throws -> NSImage {
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        texture.getBytes(&bytes, bytesPerRow: texture.width * 4, from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: texture.width, height: texture.height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: texture.width * 4, space: WindowCapture.colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw CatalogFailure.gpu }
        return NSImage(cgImage: image, size: size)
    }
}

private final class CatalogOverviewWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private final class CatalogOverviewInput: NSView {
    var dismiss: (() -> Void)?
    var choose: ((CGPoint) -> Void)?
    var hover: ((CGPoint) -> Void)?
    var scroll: ((CGFloat, CGFloat) -> Void)?
    var key: ((CatalogRuntime.OverviewKey) -> Void)?
    private let label = NSTextField(labelWithString: "")
    private var tracking: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        label.layer?.cornerRadius = 8
        label.isHidden = true
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    /// `rect` in this view's coordinates; nil hides the label.
    func showLabel(_ text: String?, below rect: CGRect) {
        guard let text, bounds.intersects(rect) else { label.isHidden = true; return }
        label.stringValue = "  \(text)  "
        label.sizeToFit()
        let width = min(max(label.frame.width + 12, 120), max(160, bounds.width * 0.5))
        let y = max(8, rect.minY - label.frame.height - 14)
        label.frame = CGRect(x: rect.midX - width / 2, y: y, width: width, height: label.frame.height + 6)
        label.isHidden = false
    }

    private func global(_ event: NSEvent) -> CGPoint? {
        guard let window else { return nil }
        let p = window.convertPoint(toScreen: event.locationInWindow)
        return CGPoint(x: p.x, y: (NSScreen.screens.first?.frame.height ?? 0) - p.y)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: key?(.dismiss)
        case 123: key?(.left)
        case 124: key?(.right)
        case 125: key?(.down)
        case 126: key?(.up)
        case 36, 76, 49: key?(.choose)
        case 48: key?(.next)
        default: super.keyDown(with: event)
        }
    }

    override func mouseMoved(with event: NSEvent) { if let p = global(event) { hover?(p) } }
    override func mouseDown(with event: NSEvent) { if let p = global(event) { choose?(p) } }
    override func rightMouseDown(with event: NSEvent) { dismiss?() }
    override func scrollWheel(with event: NSEvent) { scroll?(event.scrollingDeltaX, event.scrollingDeltaY) }
}
