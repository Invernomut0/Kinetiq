// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import KinetiqCore
import KinetiqEffects
@preconcurrency import Metal

enum CompositorError: String, LocalizedError {
    case metal = "Metal could not prepare this composition."
    case gpu = "The GPU could not encode this composition."
    case thermal = "macOS reports critical thermal pressure. Heavy effects are temporarily paused by the safety budget."
    case budget = "The rendering budget has no usable mesh or particle resources."
    case builtin = "This built-in effect cannot be used as a Studio layer."
    var errorDescription: String? { rawValue }
}

/// A built-in engine that a Studio layer can play.
enum BuiltinLayer: Equatable {
    case close(CloseEffect)
    case entrance(WobbleEntrance)
    case minimize(DockMorphStyle)

    init?(_ id: String?) {
        guard let id, let effect = LibraryEffect.find(id) else { return nil }
        switch effect {
        case .close(let value): self = .close(value)
        case .entrance(let value): self = .entrance(value)
        case .minimize(let value): self = .minimize(value)
        // Liquid and Window Destruction are desktop-wide simulations with their own players.
        case .catalog, .liquid, .destruction: return nil
        }
    }

    var effect: LibraryEffect {
        switch self {
        case .close(let value): return .close(value)
        case .entrance(let value): return .entrance(value)
        case .minimize(let value): return .minimize(value)
        }
    }

    /// Length of the original animation at 1×; a layer's duration rescales it.
    var naturalDuration: Double {
        switch self {
        case .close(let value): return value.duration
        case .entrance: return 2.5
        case .minimize(let value): return Double(value.duration)
        }
    }

    /// Every built-in effect that can be a layer, in library order.
    static let all: [BuiltinLayer] = CloseEffect.allCases.map(Self.close)
        + WobbleEntrance.allCases.map(Self.entrance) + DockMorphStyle.allCases.map(Self.minimize)

    func makeLayer(start: Double = 0) -> StudioLayer {
        StudioLayer(builtin: effect.id, name: effect.title, duration: naturalDuration, start: start)
    }
}

/// A deformer with no displacement: draws the input unchanged, shadow included.
private final class RestDeformer: WindowDeformer {
    let size: SIMD2<Float>
    let origin: SIMD2<Float>
    init(frame: CGRect) {
        size = SIMD2(Float(frame.width), Float(frame.height))
        origin = SIMD2(Float(frame.minX), Float(frame.minY))
    }
    var isSettled: Bool { true }
    func step(_ dt: Float) {}
    func snapToRest() {}
    func displacement(u: Float, v: Float) -> SIMD2<Float> { .zero }
}

/// Plays a Studio document onto one window capture: catalog shaders and original engines
/// (close shaders, spring entrances, Dock morphs) in document order, each layer reading the
/// previous layer's output. All passes draw into one stage, the window plus room around it,
/// so fragments, funnels and flights are not cropped. Pure GPU work: no windows are touched.
@MainActor
final class LayerCompositor {
    struct Source {
        let texture: MTLTexture
        /// Window crop inside `texture`: (offset.x, offset.y, scale.x, scale.y).
        let uv: SIMD4<Float>
        let shadow: ShadowInsets
    }

    let device: MTLDevice
    private var catalog: CatalogEffectRenderer?
    private var close: CloseEffectRenderer?
    private var mesh: MTLRenderPipelineState?
    private var shade: MTLTexture?

    init(device: MTLDevice) { self.device = device }

    /// Room around the window that every composition draws into, in global points.
    static func stage(windowFrame: CGRect, shadow: ShadowInsets) -> CGRect {
        let dx = max(24, windowFrame.width * 0.3, shadow.left, shadow.right)
        let dy = max(24, windowFrame.height * 0.55, shadow.top, shadow.bottom)
        return windowFrame.insetBy(dx: -dx, dy: -dy)
    }

    /// The same refusals as playback: a preview never shows what the desktop would refuse.
    static func check(_ layer: StudioLayer, budget: RenderBudget) throws {
        guard budget.meshLimit > 0 else { throw CompositorError.budget }
        if let id = layer.builtin {
            guard let builtin = BuiltinLayer(id) else { throw CompositorError.builtin }
            if case .close = builtin, !budget.allowsExpensive { throw CompositorError.thermal }
            return
        }
        let descriptor = EffectCatalog.descriptor(layer.preset.effect)
        guard !descriptor.expensive || budget.allowsExpensive else { throw CompositorError.thermal }
        guard (layer.preset.effect != .shatter && layer.preset.effect != .explode) || budget.maxParticles > 0 else {
            throw CompositorError.budget
        }
    }

    static func needsCompositor(_ document: StudioDocument) -> Bool {
        document.layers.contains { $0.enabled && $0.isBuiltin }
    }

    /// Layers playing at `time`, in document order.
    static func active(_ document: StudioDocument, at time: Double) -> [StudioLayer] {
        document.layers.filter { $0.enabled && time >= $0.start && time <= $0.end }
    }

    /// Compiles what `document` needs up front, so the first desktop frame does not stall.
    func prepare(_ document: StudioDocument) throws {
        if catalog == nil { catalog = try CatalogEffectRenderer(device: device) }
        for layer in document.layers where layer.enabled {
            if case .close(let effect) = BuiltinLayer(layer.builtin) {
                if close == nil { close = CloseEffectRenderer(device: device) }
                try close?.prepare(effect)
            }
        }
    }

    /// Encodes the frame at document `time` into `final`. `scratch` must match `final` when more
    /// than one layer is active; the last layer always lands in `final`.
    func encode(document: StudioDocument, time: Double, source: Source, windowFrame: CGRect, stage: CGRect,
                final: MTLTexture, scratch: MTLTexture?, budget: RenderBudget, physics: KinetiqSettings,
                seed: UInt64, command: MTLCommandBuffer) throws {
        try prepare(document)
        var layers = Self.active(document, at: time)
        for layer in layers { try Self.check(layer, budget: budget) }
        let identity = layers.isEmpty
        if identity { layers = [StudioLayer(preset: EffectPreset(effect: .wobbly))] }
        guard layers.count == 1 || scratch != nil else { throw CompositorError.metal }
        let windowInStage = SIMD4(Float((windowFrame.minX - stage.minX) / stage.width),
                                  Float((windowFrame.minY - stage.minY) / stage.height),
                                  Float(windowFrame.width / stage.width), Float(windowFrame.height / stage.height))
        var input = source.texture, uv = source.uv
        for (index, layer) in layers.enumerated() {
            let output = (layers.count - 1 - index).isMultiple(of: 2) ? final : scratch!
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = output
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw CompositorError.gpu }
            do {
                if identity {
                    try encodeMesh(RestDeformer(frame: windowFrame), input: input, uv: uv, shadow: source.shadow,
                                   stage: stage, alpha: 1, tiles: (3, 3), encoder: encoder)
                } else if let builtin = BuiltinLayer(layer.builtin) {
                    try encodeBuiltin(builtin, layer: layer, time: time, input: input, uv: uv, shadow: source.shadow,
                                      windowFrame: windowFrame, stage: stage, budget: budget, physics: physics,
                                      seed: seed, encoder: encoder)
                } else {
                    try encodeCatalog(layer, time: time, input: input, uv: uv, windowFrame: windowFrame,
                                      stage: stage, budget: budget, encoder: encoder)
                }
            } catch { encoder.endEncoding(); throw error }
            encoder.endEncoding()
            input = output; uv = windowInStage
        }
    }

    /// One catalog surface at a fixed progress, e.g. a window inside an overview arrangement.
    func encodeSurface(_ preset: EffectPreset, progress: Float, input: MTLTexture, uv: SIMD4<Float>, frame: CGRect,
                       stage: CGRect, budget: RenderBudget, encoder: MTLRenderCommandEncoder) throws {
        if catalog == nil { catalog = try CatalogEffectRenderer(device: device) }
        guard let catalog else { throw CompositorError.metal }
        let values = Dictionary(uniqueKeysWithValues: EffectCatalog.descriptor(preset.effect).parameters.map {
            ($0.id, Float(preset.value($0.id, at: 0)))
        })
        catalog.encode(effect: preset.effect, texture: input, uvRect: uv, frame: frame, screenRect: stage,
                       progress: progress, amplitude: values["amplitude"] ?? 1, speed: values["speed"] ?? 1,
                       meshLimit: budget.meshLimit, particleLimit: budget.maxParticles,
                       blurPasses: budget.blurPasses, parameters: values, into: encoder)
    }

    /// A flat translucent rectangle (the overview's dimmed desktop), drawn from a 1×1 texture.
    func encodeShade(_ rect: CGRect, alpha: Float, stage: CGRect, encoder: MTLRenderCommandEncoder) throws {
        if shade == nil {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
            descriptor.usage = .shaderRead
            shade = device.makeTexture(descriptor: descriptor)
            var black: [UInt8] = [0, 0, 0, 255]
            shade?.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &black, bytesPerRow: 4)
        }
        guard let shade else { throw CompositorError.metal }
        try encodeMesh(RestDeformer(frame: rect), input: shade, uv: SIMD4(0, 0, 1, 1), shadow: ShadowInsets(),
                       stage: stage, alpha: alpha, tiles: (3, 3), encoder: encoder)
    }

    private func encodeCatalog(_ layer: StudioLayer, time: Double, input: MTLTexture, uv: SIMD4<Float>,
                               windowFrame: CGRect, stage: CGRect, budget: RenderBudget,
                               encoder: MTLRenderCommandEncoder) throws {
        guard let catalog else { throw CompositorError.metal }
        let preset = layer.preset
        let local = time - layer.start
        let values = Dictionary(uniqueKeysWithValues: EffectCatalog.descriptor(preset.effect).parameters.map {
            ($0.id, Float(preset.value($0.id, at: local)))
        })
        // An Open-owned catalog preset has always played reversed; the layer toggle flips that.
        let clock = preset.curve.value(at: local / preset.duration)
        let reverse = layer.reversed != (preset.trigger == .open)
        catalog.encode(effect: preset.effect, texture: input, uvRect: uv, frame: windowFrame, screenRect: stage,
                       progress: Float(reverse ? 1 - clock : clock), amplitude: values["amplitude"] ?? 1,
                       speed: values["speed"] ?? 1, meshLimit: budget.meshLimit, particleLimit: budget.maxParticles,
                       blurPasses: budget.blurPasses, parameters: values, into: encoder)
    }

    private func encodeBuiltin(_ builtin: BuiltinLayer, layer: StudioLayer, time: Double, input: MTLTexture,
                               uv: SIMD4<Float>, shadow: ShadowInsets, windowFrame: CGRect, stage: CGRect,
                               budget: RenderBudget, physics: KinetiqSettings, seed: UInt64,
                               encoder: MTLRenderCommandEncoder) throws {
        let clock = layer.preset.curve.value(at: (time - layer.start) / layer.duration)
        let size = SIMD2(Float(windowFrame.width), Float(windowFrame.height))
        let origin = SIMD2(Float(windowFrame.minX), Float(windowFrame.minY))
        let tiles = CatalogDragPolicy.meshTiles(requested: 20, meshLimit: min(64, budget.meshLimit))
        switch builtin {
        case .close(let effect):
            if close == nil { close = CloseEffectRenderer(device: device) }
            guard let close else { throw CompositorError.metal }
            try close.prepare(effect)
            let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB)
            var scene = EffectScene(effect: effect, texture: input, uvScale: SIMD2(uv.z, uv.w), uvOffset: SIMD2(uv.x, uv.y),
                windowFrame: windowFrame, padding: Float(max(shadow.left, shadow.top, shadow.right, shadow.bottom)),
                pointer: CGPoint(x: windowFrame.minX + 24, y: windowFrame.minY + 22), screenHeight: Float(stage.height),
                accentColor: accent.map { SIMD3(Float($0.redComponent), Float($0.greenComponent), Float($0.blueComponent)) }
                    ?? SIMD3(0.04, 0.52, 1),
                durationScale: Float(layer.duration / effect.duration), seed: seed)
            // The shaders implement their own opening direction.
            scene.progress = Float(clock)
            scene.forOpening = layer.reversed
            guard close.encode(scene, into: encoder, screenRect: stage) else { throw CompositorError.metal }
        case .entrance(let entrance):
            guard (1...10).contains(physics.friction), (1...10).contains(physics.spring),
                  (2...40).contains(physics.speedup), (20...80).contains(physics.mass) else { throw CompositorError.builtin }
            let model = KinetiqModel(size: size, origin: origin, settings: physics)
            entrance.apply(to: model, drop: size / 2)
            // Deterministic 120 Hz replay from rest, so scrubbing shows the same frame every time.
            let seconds = (layer.reversed ? 1 - clock : clock) * builtin.naturalDuration
            let ticks = Int((seconds * 120).rounded(.down))
            for _ in 0..<ticks { model.step(1 / 120) }
            try encodeMesh(model, input: input, uv: uv, shadow: shadow, stage: stage, alpha: 1,
                           tiles: (tiles, tiles), encoder: encoder)
        case .minimize(let style):
            // Local destination: the bottom center of the stage, not the real Dock.
            let model = DockMorphDeformer(windowOrigin: origin, windowSize: size,
                iconOrigin: SIMD2(Float(stage.midX - 24), Float(stage.maxY - 48)), iconSize: SIMD2(repeating: 48),
                style: style, duration: style.duration)
            model.step(model.duration * Float(layer.reversed ? 1 - clock : clock))
            try encodeMesh(model, input: input, uv: uv, shadow: shadow, stage: stage, alpha: model.alpha,
                           tiles: (tiles + 4, tiles), encoder: encoder)
        }
    }

    /// MeshRenderer's vertex/fragment mapping for an explicit offscreen pass; all displacement
    /// comes from Core deformers. The outer vertex ring carries the shadow around the window.
    func encodeMesh(_ model: any WindowDeformer, input: MTLTexture, uv: SIMD4<Float>, shadow: ShadowInsets,
                    stage: CGRect, alpha: Float, tiles: (Int, Int), encoder: MTLRenderCommandEncoder) throws {
        if mesh == nil {
            let library = try device.makeLibrary(source: Self.meshShader, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "compositorMeshVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "compositorMeshFragment")
            let color = descriptor.colorAttachments[0]!
            color.pixelFormat = .bgra8Unorm
            color.isBlendingEnabled = true
            color.sourceRGBBlendFactor = .one
            color.sourceAlphaBlendFactor = .one
            color.destinationRGBBlendFactor = .oneMinusSourceAlpha
            color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            mesh = try device.makeRenderPipelineState(descriptor: descriptor)
        }
        let (tilesX, tilesY) = tiles
        var vertices: [SIMD4<Float>] = []
        model.fillVertices(tilesX: tilesX, tilesY: tilesY,
            outset: (Float(shadow.left), Float(shadow.top), Float(shadow.right), Float(shadow.bottom)), into: &vertices)
        guard vertices.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { throw CompositorError.gpu }
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
            throw CompositorError.metal
        }
        var uniforms = [SIMD4(Float(stage.minX), Float(stage.minY), Float(stage.width), Float(stage.height)),
                        uv, SIMD4(alpha, 0, 0, 0)]
        encoder.setRenderPipelineState(mesh)
        encoder.setVertexBuffer(vb, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: 3 * MemoryLayout<SIMD4<Float>>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: 3 * MemoryLayout<SIMD4<Float>>.stride, index: 1)
        encoder.setFragmentTexture(input, index: 0)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: indices.count,
            indexType: .uint16, indexBuffer: ib, indexBufferOffset: 0)
    }

    private static let meshShader = """
    #include <metal_stdlib>
    using namespace metal;
    struct U { float4 screen; float4 uv; float4 opacity; };
    struct V { float4 position [[position]]; float2 uv; };
    vertex V compositorMeshVertex(uint id [[vertex_id]], const device float4 *vertices [[buffer(0)]],
                                  constant U &u [[buffer(1)]]) {
        float4 v = vertices[id];
        float2 p = (v.xy - u.screen.xy) / u.screen.zw;
        V out;
        out.position = float4(p.x * 2 - 1, 1 - p.y * 2, 0, 1);
        out.uv = v.zw;
        return out;
    }
    fragment float4 compositorMeshFragment(V in [[stage_in]], texture2d<float> image [[texture(0)]],
                                           constant U &u [[buffer(1)]]) {
        constexpr sampler s(filter::linear, address::clamp_to_zero);
        return image.sample(s, in.uv * u.uv.zw + u.uv.xy) * u.opacity.x;
    }
    """
}
