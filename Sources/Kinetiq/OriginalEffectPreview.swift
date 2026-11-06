// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import CoreVideo
import KinetiqCore
import KinetiqEffects
import KinetiqSaverSupport
@preconcurrency import Metal
import SwiftUI

private enum OriginalPreviewError: String, LocalizedError {
    case window = "The selected window is no longer eligible. Refresh the window list."
    case capture = "The window capture is empty or invalid."
    case metal = "Metal could not prepare this effect."
    case gpu = "The GPU did not complete the preview."
    case budget = "The preview exceeds the current rendering safety budget."
    case progress = "Preview progress must be finite and between zero and one."
    case disabled = "Effects are paused."
    case settings = "The original effect settings contain invalid simulation parameters."
    var errorDescription: String? { rawValue }
}

/// What a preview is rendered from: the built-in drawn sample window, or a real one on screen.
enum PreviewSource: Hashable {
    case sample
    case window(CGWindowID)

    var windowID: CGWindowID? {
        if case .window(let id) = self { return id }
        return nil
    }
}

/// Owns the IOSurface AND its CoreVideo mapping until command completion, even
/// when the requesting SwiftUI task has disappeared or been superseded.
private final class OriginalPreviewCapture: @unchecked Sendable {
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
            let backing, let texture = CVMetalTextureGetTexture(backing) else { throw OriginalPreviewError.capture }
        self.backing = backing
        self.texture = texture
        uv = SIMD4(Float(frame.windowRect.minX) / Float(w), Float(frame.windowRect.minY) / Float(h),
                   Float(frame.windowRect.width) / Float(w), Float(frame.windowRect.height) / Float(h))
    }
}

/// Multiplies the displacement of another deformer, like the live overlay's `deformationScale`.
private final class ScaledDeformer: WindowDeformer {
    let base: any WindowDeformer
    let scale: Float
    init(_ base: any WindowDeformer, scale: Float) { self.base = base; self.scale = scale }
    var size: SIMD2<Float> { base.size }
    var origin: SIMD2<Float> { base.origin }
    var isSettled: Bool { base.isSettled }
    func step(_ dt: Float) { base.step(dt) }
    func snapToRest() { base.snapToRest() }
    func displacement(u: Float, v: Float) -> SIMD2<Float> { base.displacement(u: u, v: v) * scale }
}

/// Read-only, offscreen renderer for every library effect: original shaders and physics,
/// Studio catalog materials and the real spring model behind Wobbly.
/// No AX APIs, overlays, native close/minimize actions or preference writes.
@MainActor
final class OriginalPreviewRenderer {
    /// Seconds of scripted drag-and-release that the Wobbly preview replays.
    static let wobblyPreviewSeconds = 3.0
    /// Seconds of the scripted drag before the window is let go.
    static let wobblyReleaseSeconds = 1.8

    private let budgetProvider: @MainActor () -> RenderBudget
    private let capture = WindowCapture()
    private var gpu: GPU?
    private var generation = UUID()
    private var sampleCapture: OriginalPreviewCapture?
    private(set) var inFlight = 0

    init(budget: @escaping @MainActor () -> RenderBudget = { RenderQualityManager.shared.budget }) {
        budgetProvider = budget
    }

    /// Invalidates results immediately; committed GPU work still retains its backing.
    func cancel() { generation = UUID() }

    /// The timeline length a preview scrubs through, in seconds.
    static func timelineSeconds(effect: LibraryEffect, preset: EffectPreset?, settings: Settings,
                                source: PreviewSource = .sample) -> Double {
        switch effect {
        case .catalog(.wobbly): return wobblyPreviewSeconds
        case .catalog(let id): return preset?.duration ?? EffectPreset(effect: id).duration
        case .close(let close): return close.duration * settings.closeDuration
        case .entrance: return 2.5
        case .minimize(let style): return Double(style.duration) * settings.closeDuration
        case .destruction: return DestructionScene.duration * settings.closeDuration
        case .liquid:
            let frame = source.windowID.flatMap { WindowLocator.frame(of: $0) } ?? SampleWindow.frameOnStage
            return Double(LiquidWorld.duration(for: liquidStage(frame), durationScale: Float(settings.closeDuration)))
        }
    }

    /// The same local floor and timing for the scrubber and captured render path.
    private static func liquidStage(_ frame: CGRect) -> CGRect {
        let margin = max(24, frame.width * 0.15)
        var stage = frame.insetBy(dx: -margin, dy: -margin)
        stage.size.height += frame.height * 0.85
        return stage
    }

    /// Library entry point: any effect, from the sample window or a real one.
    func preview(effect: LibraryEffect, preset: EffectPreset? = nil, source: PreviewSource,
                 progress: Double, settings: Settings) async throws -> NSImage {
        let document = preset.map { StudioDocument(duration: $0.duration, layers: [StudioLayer(preset: $0)]) }
        switch source {
        case .sample:
            let token = try begin(progress: progress, settings: settings)
            defer { inFlight -= 1 }
            let frame = try SampleWindow.frame()
            return try await render(effect: effect, document: document, frame: frame, windowFrame: SampleWindow.frameOnStage,
                                    progress: progress, settings: settings, token: token)
        case .window(let id):
            return try await preview(effect: effect, document: document, windowID: id, progress: progress, settings: settings)
        }
    }

    /// Studio composition on the sample window or a real one, at a document time in seconds.
    func preview(document: StudioDocument, time: Double, source: PreviewSource, settings: Settings) async throws -> NSImage {
        let document = try document.validated()
        guard time.isFinite, document.duration > 0 else { throw OriginalPreviewError.progress }
        let progress = min(1, max(0, time / document.duration))
        let effect: LibraryEffect = .catalog(document.layers.first?.preset.effect ?? .wobbly)
        switch source {
        case .sample:
            let token = try begin(progress: progress, settings: settings)
            defer { inFlight -= 1 }
            let frame = try SampleWindow.frame()
            return try await render(effect: effect, document: document, frame: frame, windowFrame: SampleWindow.frameOnStage,
                                    progress: progress, settings: settings, token: token)
        case .window(let id):
            return try await preview(effect: effect, document: document, windowID: id, progress: progress, settings: settings)
        }
    }

    func preview(effect: LibraryEffect, windowID: CGWindowID, progress: Double, settings: Settings) async throws -> NSImage {
        try await preview(effect: effect, document: nil, windowID: windowID, progress: progress, settings: settings)
    }

    private func preview(effect: LibraryEffect, document: StudioDocument?, windowID: CGWindowID,
                         progress: Double, settings: Settings) async throws -> NSImage {
        let token = try begin(progress: progress, settings: settings)
        defer { inFlight -= 1 }
        let runtime = CatalogRuntime(settings: settings, budget: budgetProvider)
        guard runtime.availableWindows().contains(where: { $0.id == windowID }),
              let rect = WindowLocator.frame(of: windowID) else { throw OriginalPreviewError.window }
        // Bound native capture allocation too, including WindowCapture's shadow room.
        let scale = NSScreen.containing(cgPoint: CGPoint(x: rect.midX, y: rect.midY))?.backingScaleFactor ?? 2
        guard (rect.width + 200) * (rect.height + 200) * scale * scale <= 32_000_000,
              max(rect.width + 200, rect.height + 200) * scale <= 16384 else { throw OriginalPreviewError.budget }
        let metadata = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]]
        guard let pid = metadata?.first?[kCGWindowOwnerPID as String] as? Int else { throw OriginalPreviewError.window }
        let frame = try await capture.capture(WindowInfo(id: windowID, pid: pid_t(pid), frame: rect))
        try validate(token, settings: settings)
        guard runtime.availableWindows().contains(where: { $0.id == windowID }),
              WindowLocator.frame(of: windowID) == rect else { throw OriginalPreviewError.window }
        let image = try await render(effect: effect, document: document, frame: frame, windowFrame: rect, progress: progress,
                                     settings: settings, token: token)
        try validate(token, settings: settings)
        guard runtime.availableWindows().contains(where: { $0.id == windowID }),
              WindowLocator.frame(of: windowID) == rect else { throw OriginalPreviewError.window }
        return image
    }

    /// Real-capture seam: callers supply an actual ScreenCaptureKit frame, e.g.
    /// their own disposable document (intentionally excluded by availableWindows).
    func previewCaptured(effect: LibraryEffect, frame: CapturedFrame, windowFrame: CGRect,
                         progress: Double, settings: Settings) async throws -> NSImage {
        let token = try begin(progress: progress, settings: settings)
        defer { inFlight -= 1 }
        return try await render(effect: effect, document: nil, frame: frame, windowFrame: windowFrame,
                                progress: progress, settings: settings, token: token)
    }

    private func begin(progress: Double, settings: Settings) throws -> UUID {
        try Task.checkCancellation()
        guard progress.isFinite, (0...1).contains(progress) else { throw OriginalPreviewError.progress }
        guard settings.enabled else { throw OriginalPreviewError.disabled }
        guard settings.closeDuration.isFinite else { throw OriginalPreviewError.settings }
        guard inFlight < 2 else { throw OriginalPreviewError.budget }
        generation = UUID()
        inFlight += 1
        return generation
    }

    private func validate(_ token: UUID, settings: Settings) throws {
        try Task.checkCancellation()
        guard generation == token else { throw CancellationError() }
        guard settings.enabled else { throw OriginalPreviewError.disabled }
    }

    private func source(for frame: CapturedFrame, gpu: GPU) throws -> OriginalPreviewCapture {
        if frame.windowID == SampleWindow.windowID, let sampleCapture,
           sampleCapture.frame.pixelBuffer === frame.pixelBuffer { return sampleCapture }
        let capture = try OriginalPreviewCapture(frame, cache: gpu.cache)
        if frame.windowID == SampleWindow.windowID { sampleCapture = capture }
        return capture
    }

    private func render(effect: LibraryEffect, document: StudioDocument?, frame: CapturedFrame, windowFrame: CGRect,
                        progress: Double, settings: Settings, token: UUID) async throws -> NSImage {
        let buffer = frame.pixelBuffer
        let bounds = CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        guard bounds.width * bounds.height <= 32_000_000,
              max(bounds.width, bounds.height) <= 16384 else { throw OriginalPreviewError.budget }
        guard Self.valid(windowFrame), windowFrame.size == frame.pointSize,
              Self.valid(frame.windowRect), bounds.contains(frame.windowRect),
              frame.windowRect.width >= 1, frame.windowRect.height >= 1,
              [frame.shadow.left, frame.shadow.top, frame.shadow.right, frame.shadow.bottom]
                .allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1000 }),
              CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
              frame.isPainted else { throw OriginalPreviewError.capture }
        try validate(token, settings: settings)
        let budget = budgetProvider()
        guard budget.textureScale.isFinite, budget.textureScale > 0, budget.meshLimit > 0 else {
            throw OriginalPreviewError.budget
        }
        if gpu == nil { gpu = try GPU() }
        guard let gpu else { throw OriginalPreviewError.metal }
        let source = try source(for: frame, gpu: gpu)
        let origin = SIMD2(Float(windowFrame.minX), Float(windowFrame.minY))
        let size = SIMD2(Float(windowFrame.width), Float(windowFrame.height))
        let margin = max(24, windowFrame.width * 0.15,
                         frame.shadow.left, frame.shadow.right, frame.shadow.top, frame.shadow.bottom)
        var stage = windowFrame.insetBy(dx: -margin, dy: -margin)
        var scene: EffectScene?
        var deformer: (any WindowDeformer)?
        var world: LiquidWorld?
        var destruction: ChaosRenderer?
        var catalog: StudioDocument?
        var alpha: Float = 1
        var tilesX = CatalogDragPolicy.meshTiles(requested: settings.tilesX, meshLimit: min(64, budget.meshLimit))
        var tilesY = CatalogDragPolicy.meshTiles(requested: settings.tilesY, meshLimit: min(64, budget.meshLimit))
        switch effect {
        case .close(let effect):
            // These shaders have no scalable particle/blur knobs. Do not silently
            // replace them with Glide when the expensive-effects gate is closed.
            guard budget.allowsExpensive else { throw OriginalPreviewError.budget }
            if gpu.close == nil { gpu.close = CloseEffectRenderer(device: gpu.device) }
            try gpu.close?.prepare(effect)
            let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB)
            var value = EffectScene(effect: effect, texture: source.texture,
                uvScale: SIMD2(source.uv.z, source.uv.w), uvOffset: SIMD2(source.uv.x, source.uv.y),
                windowFrame: windowFrame, padding: Float(max(frame.shadow.left, frame.shadow.top,
                    frame.shadow.right, frame.shadow.bottom)), pointer: CGPoint(x: windowFrame.midX, y: windowFrame.midY),
                screenHeight: Float(NSScreen.containing(cgPoint: windowFrame.origin)?.frame.height ?? stage.height),
                accentColor: accent.map { SIMD3(Float($0.redComponent), Float($0.greenComponent), Float($0.blueComponent)) }
                    ?? SIMD3(0.04, 0.52, 1), durationScale: Float(settings.closeDuration), seed: UInt64(frame.windowID))
            value.progress = Float(progress)
            stage = stage.union(value.quadRect)
            scene = value
        case .entrance(let entrance):
            let physics = settings.physics
            guard (1...10).contains(physics.friction), (1...10).contains(physics.spring),
                  (2...40).contains(physics.speedup), (20...80).contains(physics.mass) else {
                throw OriginalPreviewError.settings
            }
            let model = KinetiqModel(size: size, origin: origin, settings: physics)
            entrance.apply(to: model, drop: size / 2)
            // Deterministic 120 Hz replay, not one large clamped simulation step.
            try await advance(model, seconds: progress * 2.5, token: token, settings: settings)
            deformer = model
        case .minimize(let style):
            stage.size.height += windowFrame.height * 0.5
            // Deliberately local: querying/guessing an app icon is not the actual
            // minimized-window Dock tile. The UI discloses this destination.
            let icon = SIMD2(Float(stage.midX - 24), Float(stage.maxY - 48))
            let model = DockMorphDeformer(windowOrigin: origin, windowSize: size,
                iconOrigin: icon, iconSize: SIMD2(repeating: 48), style: style,
                duration: style.duration * Float(settings.closeDuration))
            model.step(model.duration * Float(progress))
            alpha = model.alpha
            deformer = model
            tilesX = CatalogDragPolicy.meshTiles(requested: 24, meshLimit: min(64, budget.meshLimit))
            tilesY = CatalogDragPolicy.meshTiles(requested: 20, meshLimit: min(64, budget.meshLimit))
        case .destruction:
            guard budget.allowsExpensive else { throw OriginalPreviewError.budget }
            stage = Self.liquidStage(windowFrame)
            let localStage = stage
            guard let pieces = await Task.detached(priority: .userInitiated, operation: {
                DestructionScene.build(frame: frame, windowFrame: windowFrame, stage: localStage)
            }).value else { throw OriginalPreviewError.capture }
            try validate(token, settings: settings)
            let renderer = try DestructionScene.renderer(device: gpu.device, scene: pieces, size: stage.size,
                scale: CGFloat(frame.windowRect.width / frame.pointSize.width))
            let ticks = Int((progress * DestructionScene.duration * 120).rounded(.down))
            for tick in 0..<ticks {
                if tick.isMultiple(of: 24) { await Task.yield(); try validate(token, settings: settings) }
                renderer.simulate(1 / 120)
            }
            destruction = renderer
        case .liquid:
            guard budget.allowsExpensive, budget.maxParticles > 0 else { throw OriginalPreviewError.budget }
            stage = Self.liquidStage(windowFrame)
            let liquid = LiquidWorld(windowFrame: windowFrame, screenBounds: stage, obstacles: [],
                durationScale: Float(settings.closeDuration), maxParticles: budget.maxParticles)
            // Replay the complete physical drainage too, without cropping the local floor.
            try await advance(liquid, seconds: progress * Double(liquid.duration), token: token, settings: settings)
            if gpu.liquid == nil { gpu.liquid = try LiquidEffectRenderer(device: gpu.device) }
            gpu.liquid?.geometryScale = budget.textureScale
            world = liquid
        case .catalog(let id):
            let document = try (document ?? StudioDocument(duration: EffectPreset(effect: id).duration,
                                                           layers: [StudioLayer(preset: EffectPreset(effect: id))])).validated()
            let active = document.layers.filter(\.enabled)
            for layer in active { try Self.allowed(layer.preset, budget: budget) }
            if active.count == 1, active[0].preset.effect == .wobbly {
                // The preview of Wobbly is the real spring mesh under a scripted drag,
                // not the shader membrane used for timeline compositions.
                let preset = active[0].preset
                let physics = settings.physics
                guard (1...10).contains(physics.friction), (1...10).contains(physics.spring),
                      (2...40).contains(physics.speedup), (20...80).contains(physics.mass) else {
                    throw OriginalPreviewError.settings
                }
                let seconds = progress * Self.wobblyPreviewSeconds
                let model = KinetiqModel(size: size, origin: origin, settings: physics)
                try await scriptedDrag(model, preset: preset, seconds: seconds, token: token, settings: settings)
                let amplitude = Float(preset.value("amplitude", at: min(preset.duration, seconds)))
                deformer = ScaledDeformer(model, scale: amplitude)
                let reach = Self.dragOffset(at: Self.wobblyReleaseSeconds * 0.5, size: size)
                stage = stage.insetBy(dx: -CGFloat(abs(reach.x)) - 8, dy: -CGFloat(abs(reach.y)) - 8)
            } else {
                // Room below for Genie's funnel and for fragments that fall.
                stage.size.height += windowFrame.height * 0.6
                catalog = document
            }
        }
        try validate(token, settings: settings)
        let nativeScale = Double(frame.windowRect.width / frame.pointSize.width)
        let dimensions = try CatalogRuntime.targetSize(CGSize(width: stage.width * nativeScale,
            height: stage.height * nativeScale), scale: budget.textureScale)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: dimensions.width, height: dimensions.height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead]
        guard let target = gpu.device.makeTexture(descriptor: descriptor),
              let command = gpu.queue.makeCommandBuffer() else { throw OriginalPreviewError.metal }
        if let destruction {
            destruction.encodeFrame(commands: command, target: target, dt: 0)
        } else if let catalog {
            try gpu.encodeCatalog(catalog, time: progress * catalog.duration, source: source, windowFrame: windowFrame,
                                  stage: stage, target: target, descriptor: descriptor, budget: budget, command: command)
        } else {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw OriginalPreviewError.gpu }
            if let scene {
                guard gpu.close?.encode(scene, into: encoder, screenRect: stage) == true else {
                    encoder.endEncoding()
                    throw OriginalPreviewError.metal
                }
            }
            if let deformer {
                do {
                    try gpu.encodeMesh(deformer, source: source, stage: stage, alpha: alpha,
                                       tilesX: tilesX, tilesY: tilesY, encoder: encoder)
                } catch { encoder.endEncoding(); throw error }
            }
            encoder.endEncoding()
            if let world {
                gpu.liquid?.encode(world: world, texture: source.texture, uvRect: source.uv,
                                   into: command, target: target, screenRect: stage)
            }
        }
        RenderQualityManager.trackGPUCompletion(command)
        let success: Bool = await withCheckedContinuation { continuation in
            command.addCompletedHandler { [source] completed in
                withExtendedLifetime(source) {
                    continuation.resume(returning: completed.status == .completed && completed.error == nil)
                }
            }
            command.commit()
        }
        guard success else { throw OriginalPreviewError.gpu }
        try validate(token, settings: settings)
        return try Self.image(target, pointSize: stage.size)
    }

    /// Mirrors the runtime's safety checks so a preview never shows what playback would refuse.
    private static func allowed(_ preset: EffectPreset, budget: RenderBudget) throws {
        let descriptor = EffectCatalog.descriptor(preset.effect)
        guard !descriptor.expensive || budget.allowsExpensive else { throw OriginalPreviewError.budget }
        guard budget.meshLimit > 0,
              (preset.effect != .shatter && preset.effect != .explode) || budget.maxParticles > 0 else {
            throw OriginalPreviewError.budget
        }
    }

    /// Pointer travel of the scripted Wobbly drag: a wide swing to the right that comes back home.
    static func dragOffset(at seconds: Double, size: SIMD2<Float>) -> SIMD2<Float> {
        let s = min(1, max(0, seconds / wobblyReleaseSeconds))
        let eased = s * s * (3 - 2 * s)
        return SIMD2(Float(sin(.pi * eased)) * size.x * 0.22, Float(sin(2 * .pi * eased)) * size.y * 0.07)
    }

    /// Grab the title bar, move for `wobblyReleaseSeconds`, let go and let the springs settle. 120 Hz replay.
    private func scriptedDrag(_ model: KinetiqModel, preset: EffectPreset, seconds: Double,
                              token: UUID, settings: Settings) async throws {
        let home = model.origin
        let grab = home + SIMD2(model.size.x * 0.5, 14)
        model.grab(at: grab)
        let dt = 1.0 / 120
        let ticks = Int((seconds * 120).rounded(.down))
        var released = false
        for tick in 0..<ticks {
            if tick.isMultiple(of: 24) { await Task.yield(); try validate(token, settings: settings) }
            let now = Double(tick) * dt
            if preset.effect == .wobbly {
                var physics = settings.physics
                physics.spring = Float(preset.value("stiffness", at: min(preset.duration, now)))
                physics.friction = Float(preset.value("friction", at: min(preset.duration, now)))
                model.updateSettings(physics, speed: Float(preset.value("speed", at: min(preset.duration, now))))
            }
            if now < Self.wobblyReleaseSeconds {
                let offset = Self.dragOffset(at: now, size: model.size)
                model.moveGrab(to: grab + offset, origin: home + offset)
            } else if !released {
                model.release(origin: home)
                released = true
            }
            model.step(Float(dt))
        }
        if seconds >= Self.wobblyReleaseSeconds, !released { model.release(origin: home) }
    }

    private func advance(_ model: any WindowDeformer, seconds: Double, token: UUID, settings: Settings) async throws {
        let ticks = Int((seconds * 120).rounded(.down))
        for tick in 0..<ticks {
            if tick.isMultiple(of: 24) { await Task.yield(); try validate(token, settings: settings) }
            model.step(1 / 120)
        }
        model.step(Float(seconds - Double(ticks) / 120))
    }

    private func advance(_ world: LiquidWorld, seconds: Double, token: UUID, settings: Settings) async throws {
        // durationScale also scales the simulation's internal fixed tick.
        let ticks = Int((seconds / settings.closeDuration * 120).rounded(.down))
        for tick in 0..<ticks {
            if tick.isMultiple(of: 24) { await Task.yield(); try validate(token, settings: settings) }
            world.step(Float(settings.closeDuration) / 120)
        }
    }

    private static func valid(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && rect.width > 0 && rect.height > 0
            && [rect.minX, rect.minY, rect.maxX, rect.maxY].allSatisfy { $0.isFinite && abs($0) < 10_000_000 }
    }

    private static func image(_ texture: MTLTexture, pointSize: CGSize) throws -> NSImage {
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        texture.getBytes(&bytes, bytesPerRow: texture.width * 4,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: texture.width, height: texture.height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: texture.width * 4, space: WindowCapture.colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw OriginalPreviewError.gpu
        }
        return NSImage(cgImage: image, size: pointSize)
    }

    /// MeshRenderer's original vertex/fragment mapping, adapted ONLY for an
    /// explicit offscreen pass; all displacement still comes from Core deformers.
    @MainActor private final class GPU {
        let device: MTLDevice
        let queue: MTLCommandQueue
        let cache: CVMetalTextureCache
        var close: CloseEffectRenderer?
        var liquid: LiquidEffectRenderer?
        private var catalog: CatalogEffectRenderer?
        private var mesh: MTLRenderPipelineState?

        init() throws {
            guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
                throw OriginalPreviewError.metal
            }
            self.device = device
            self.queue = queue
            var cache: CVMetalTextureCache?
            guard CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess, let cache else {
                throw OriginalPreviewError.capture
            }
            self.cache = cache
        }

        /// Sequential layer composition over the stage, like the runtime's offscreen ping-pong,
        /// but with room around the window so fragments and funnels are not cropped.
        func encodeCatalog(_ document: StudioDocument, time: Double, source: OriginalPreviewCapture, windowFrame: CGRect,
                           stage: CGRect, target: MTLTexture, descriptor: MTLTextureDescriptor, budget: RenderBudget,
                           command: MTLCommandBuffer) throws {
            if catalog == nil { catalog = try CatalogEffectRenderer(device: device) }
            guard let catalog else { throw OriginalPreviewError.metal }
            var layers = document.layers.filter { $0.enabled && time >= $0.start && time <= $0.start + $0.preset.duration }
            if layers.isEmpty {
                var identity = EffectPreset(effect: .wobbly); identity.parameters["amplitude"] = 0
                layers = [StudioLayer(preset: identity, start: time)]
            }
            if layers.count > 1 {
                guard let scratch = device.makeTexture(descriptor: descriptor) else { throw OriginalPreviewError.metal }
                try encodeLayers(layers, time: time, catalog: catalog, source: source, windowFrame: windowFrame,
                                 stage: stage, final: target, scratch: scratch, budget: budget, command: command)
            } else {
                try encodeLayers(layers, time: time, catalog: catalog, source: source, windowFrame: windowFrame,
                                 stage: stage, final: target, scratch: nil, budget: budget, command: command)
            }
        }

        private func encodeLayers(_ layers: [StudioLayer], time: Double, catalog: CatalogEffectRenderer,
                                  source: OriginalPreviewCapture, windowFrame: CGRect, stage: CGRect,
                                  final: MTLTexture, scratch: MTLTexture?, budget: RenderBudget, command: MTLCommandBuffer) throws {
            var texture = source.texture, uv = source.uv, frame = windowFrame
            for (index, layer) in layers.enumerated() {
                // Count back from the end so the last layer lands in the final target and
                // consecutive layers always alternate between the two textures.
                let output = (layers.count - 1 - index).isMultiple(of: 2) ? final : (scratch ?? final)
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = output
                pass.colorAttachments[0].loadAction = .clear
                pass.colorAttachments[0].storeAction = .store
                pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
                guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw OriginalPreviewError.gpu }
                let preset = layer.preset
                let local = time - layer.start
                let values = Dictionary(uniqueKeysWithValues: EffectCatalog.descriptor(preset.effect).parameters.map {
                    ($0.id, Float(preset.value($0.id, at: local)))
                })
                let clock = preset.curve.value(at: local / preset.duration)
                let progress = preset.trigger == .open ? 1 - clock : clock
                catalog.encode(effect: preset.effect, texture: texture, uvRect: uv, frame: frame, screenRect: stage,
                               progress: Float(progress), amplitude: values["amplitude"] ?? 1, speed: values["speed"] ?? 1,
                               meshLimit: budget.meshLimit, particleLimit: budget.maxParticles,
                               blurPasses: budget.blurPasses, parameters: values, into: encoder)
                encoder.endEncoding()
                texture = output; uv = SIMD4(0, 0, 1, 1); frame = stage
            }
        }

        func encodeMesh(_ model: any WindowDeformer, source: OriginalPreviewCapture, stage: CGRect,
                        alpha: Float, tilesX: Int, tilesY: Int, encoder: MTLRenderCommandEncoder) throws {
            if mesh == nil {
                let library = try device.makeLibrary(source: Self.meshShader, options: nil)
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = library.makeFunction(name: "originalMeshVertex")
                descriptor.fragmentFunction = library.makeFunction(name: "originalMeshFragment")
                let color = descriptor.colorAttachments[0]!
                color.pixelFormat = .bgra8Unorm
                color.isBlendingEnabled = true
                color.sourceRGBBlendFactor = .one
                color.sourceAlphaBlendFactor = .one
                color.destinationRGBBlendFactor = .oneMinusSourceAlpha
                color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                mesh = try device.makeRenderPipelineState(descriptor: descriptor)
            }
            let shadow = source.frame.shadow
            var vertices: [SIMD4<Float>] = []
            model.fillVertices(tilesX: tilesX, tilesY: tilesY,
                outset: (Float(shadow.left), Float(shadow.top), Float(shadow.right), Float(shadow.bottom)), into: &vertices)
            guard vertices.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { throw OriginalPreviewError.capture }
            var indices: [UInt16] = []
            let columns = tilesX + 3
            for y in 0..<(tilesY + 2) {
                for x in 0..<(tilesX + 2) {
                    let a = UInt16(y * columns + x), b = a + 1, c = a + UInt16(columns), d = c + 1
                    indices += [a, b, c, b, d, c]
                }
            }
            guard let mesh,
                  let vb = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<SIMD4<Float>>.stride),
                  let ib = device.makeBuffer(bytes: indices, length: indices.count * MemoryLayout<UInt16>.stride) else {
                throw OriginalPreviewError.metal
            }
            // Float4-only ABI keeps Swift/Metal alignment explicit.
            var uniforms = [SIMD4(Float(stage.minX), Float(stage.minY), Float(stage.width), Float(stage.height)),
                            source.uv, SIMD4(alpha, 0, 0, 0)]
            encoder.setRenderPipelineState(mesh)
            encoder.setVertexBuffer(vb, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: 3 * MemoryLayout<SIMD4<Float>>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: 3 * MemoryLayout<SIMD4<Float>>.stride, index: 1)
            encoder.setFragmentTexture(source.texture, index: 0)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: indices.count,
                indexType: .uint16, indexBuffer: ib, indexBufferOffset: 0)
        }

        private static let meshShader = """
        #include <metal_stdlib>
        using namespace metal;
        struct U { float4 screen; float4 uv; float4 opacity; };
        struct V { float4 position [[position]]; float2 uv; };
        vertex V originalMeshVertex(uint id [[vertex_id]], const device float4 *vertices [[buffer(0)]],
                                    constant U &u [[buffer(1)]]) {
            float4 v = vertices[id];
            float2 p = (v.xy - u.screen.xy) / u.screen.zw;
            V out;
            out.position = float4(p.x * 2 - 1, 1 - p.y * 2, 0, 1);
            out.uv = v.zw;
            return out;
        }
        fragment float4 originalMeshFragment(V in [[stage_in]], texture2d<float> image [[texture(0)]],
                                             constant U &u [[buffer(1)]]) {
            constexpr sampler s(filter::linear, address::clamp_to_edge);
            return image.sample(s, in.uv * u.uv.zw + u.uv.xy) * u.opacity.x;
        }
        """
    }
}
