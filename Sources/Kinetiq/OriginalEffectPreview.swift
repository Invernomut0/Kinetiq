// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import CoreVideo
import KinetiqCore
import KinetiqEffects
@preconcurrency import Metal
import SwiftUI

private enum OriginalPreviewError: String, LocalizedError {
    case window = "The selected window is no longer eligible. Refresh the window list."
    case capture = "The window capture is empty or invalid."
    case metal = "Metal could not prepare this original effect."
    case gpu = "The GPU did not complete the preview."
    case budget = "The preview exceeds the current rendering safety budget."
    case progress = "Preview progress must be finite and between zero and one."
    case disabled = "Effects are paused."
    case settings = "The original effect settings contain invalid simulation parameters."
    var errorDescription: String? { rawValue }
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

/// Read-only, offscreen adapter for the original shader and physics paths.
/// No AX APIs, overlays, native close/minimize actions or preference writes.
@MainActor
final class OriginalPreviewRenderer {
    private let budgetProvider: @MainActor () -> RenderBudget
    private let capture = WindowCapture()
    private var gpu: GPU?
    private var generation = UUID()
    private(set) var inFlight = 0

    init(budget: @escaping @MainActor () -> RenderBudget = { RenderQualityManager.shared.budget }) {
        budgetProvider = budget
    }

    /// Invalidates results immediately; committed GPU work still retains its backing.
    func cancel() { generation = UUID() }

    func preview(effect: LibraryEffect, windowID: CGWindowID, progress: Double, settings: Settings) async throws -> NSImage {
        let token = try begin(progress: progress, settings: settings)
        defer { inFlight -= 1 }
        let runtime = CatalogRuntime(settings: settings, budget: budgetProvider)
        guard runtime.availableWindows().contains(where: { $0.id == windowID }),
              let rect = WindowLocator.frame(of: windowID) else { throw OriginalPreviewError.window }
        if case .catalog(let id) = effect {
            let preset = EffectPreset(effect: id)
            let image = try await runtime.preview(document: StudioDocument(duration: preset.duration,
                layers: [StudioLayer(preset: preset)]), time: progress * preset.duration, windowID: windowID)
            try validate(token, settings: settings)
            return image
        }
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
        let image = try await render(effect: effect, frame: frame, windowFrame: rect, progress: progress,
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
        return try await render(effect: effect, frame: frame, windowFrame: windowFrame,
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

    private func render(effect: LibraryEffect, frame: CapturedFrame, windowFrame: CGRect,
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
        if case .catalog(let id) = effect {
            let preset = EffectPreset(effect: id)
            let runtime = CatalogRuntime(settings: settings, budget: budgetProvider)
            let image = try await runtime.previewCaptured(frame, windowFrame: windowFrame,
                document: StudioDocument(duration: preset.duration, layers: [StudioLayer(preset: preset)]),
                time: progress * preset.duration)
            try validate(token, settings: settings)
            return image
        }
        let budget = budgetProvider()
        guard budget.textureScale.isFinite, budget.textureScale > 0, budget.meshLimit > 0 else {
            throw OriginalPreviewError.budget
        }
        if gpu == nil { gpu = try GPU() }
        guard let gpu else { throw OriginalPreviewError.metal }
        let source = try OriginalPreviewCapture(frame, cache: gpu.cache)
        let origin = SIMD2(Float(windowFrame.minX), Float(windowFrame.minY))
        let size = SIMD2(Float(windowFrame.width), Float(windowFrame.height))
        let margin = max(24, windowFrame.width * 0.15,
                         frame.shadow.left, frame.shadow.right, frame.shadow.top, frame.shadow.bottom)
        var stage = windowFrame.insetBy(dx: -margin, dy: -margin)
        var scene: EffectScene?
        var deformer: (any WindowDeformer)?
        var world: LiquidWorld?
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
        case .liquid:
            guard budget.allowsExpensive, budget.maxParticles > 0 else { throw OriginalPreviewError.budget }
            stage.size.height += windowFrame.height * 0.85
            let liquid = LiquidWorld(windowFrame: windowFrame, screenBounds: stage, obstacles: [],
                durationScale: Float(settings.closeDuration), maxParticles: budget.maxParticles)
            // Six normalized seconds includes complete melting, fall and pooling.
            // Keep the entire stage, not the now-empty original-window crop.
            try await advance(liquid, seconds: progress * 6 * settings.closeDuration, token: token, settings: settings)
            if gpu.liquid == nil { gpu.liquid = try LiquidEffectRenderer(device: gpu.device) }
            gpu.liquid?.geometryScale = budget.textureScale
            world = liquid
        case .catalog: preconditionFailure("Catalog uses its existing renderer")
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

private struct OriginalPreviewRequest: Equatable {
    let effect: LibraryEffect
    let window: CGWindowID?
    let progress: Double
    let revision: Int
    let visible: Bool
}

/// Embedded preview only; the five detail tabs and assignments belong to the library.
@MainActor
struct OriginalEffectPreview: View {
    let effect: LibraryEffect
    let settings: Settings
    @State private var renderer = OriginalPreviewRenderer()
    @State private var windowID: CGWindowID?
    @State private var progress = 0.0
    @State private var image: NSImage?
    @State private var error: String?
    @State private var rendering = false
    @State private var revision = 0
    @State private var visible = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CatalogWindowPicker(selection: $windowID)
            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                if let image {
                    Image(nsImage: image).resizable().scaledToFit().padding(12)
                        .accessibilityLabel("Original effect rendered from the selected window capture")
                } else {
                    Label(windowID == nil ? "Choose a real window to preview" : "Captured-window preview", systemImage: "macwindow")
                        .foregroundStyle(.secondary)
                }
                if rendering { ProgressView().padding().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing) }
            }
            .frame(minHeight: 140, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Slider(value: $progress, in: 0...1) { Text("Original effect progress") }
                .accessibilityLabel("Original effect progress")
            HStack {
                Text("\(progress * 100, specifier: "%.0f")%").font(.caption.monospacedDigit())
                Spacer()
                Button("Recapture") { revision += 1 }.disabled(windowID == nil)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            Text(disclosure).font(.caption).foregroundStyle(.secondary)
        }
        .task(id: OriginalPreviewRequest(effect: effect, window: windowID, progress: progress, revision: revision, visible: visible)) {
            image = nil; error = nil; rendering = false
            guard visible, let windowID else { return }
            do {
                try await Task.sleep(for: .milliseconds(80))
                try Task.checkCancellation()
                rendering = true
                let result = try await renderer.preview(effect: effect, windowID: windowID, progress: progress, settings: settings)
                try Task.checkCancellation()
                image = result; rendering = false
            } catch is CancellationError {
                // The replacement structured task owns the view state.
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription; rendering = false
            }
        }
        .onAppear { visible = true }
        .onDisappear { visible = false; renderer.cancel(); image = nil }
        .onChange(of: effect) { _, _ in progress = 0; image = nil }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            if isManagementWindow(note) { visible = false; renderer.cancel(); image = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            if isManagementWindow(note) { visible = true }
        }
    }

    private var disclosure: String {
        switch effect {
        case .minimize:
            return "Original Dock morph physics; destination is local to this preview panel, not the actual Dock. The live window is never moved or minimized."
        case .liquid:
            return "Original Liquid simulation, 0–6 normalized seconds, with a retained local floor stage and no desktop obstacles. The live window is never closed or minimized."
        default:
            return "Original rendering path on an actual captured window. Preview only: no live window movement, closing or minimizing."
        }
    }
}