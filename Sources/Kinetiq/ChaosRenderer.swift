// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import KinetiqCore
import Metal
import MetalKit
import simd

enum ChaosRendererError: Error {
    case noDevice
    case shaderFailed(String)
}

/// Metal shaders of the chaos screen saver: instanced quads (window pieces, letters, buttons, icons), soft point sprites
/// (smoke, flames, sparks, dust) and a full-screen fade.
private enum ChaosShaders {
    static let source = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct Sprite {
        float2 pos;     // centre, points
        float2 size;    // points
        float4 uv;      // u0, v0, u1, v1
        float angle;
        float alpha;
        float flash;
        float pad;
        float4 tint;    // rgb colour, amount
    };

    struct SpriteOut {
        float4 position [[position]];
        float2 uv;
        float alpha;
        float flash;
        float4 tint;
    };

    vertex SpriteOut chaos_sprite_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                         constant Sprite *sprites [[buffer(0)]], constant float2 &res [[buffer(1)]]) {
        Sprite s = sprites[iid];
        float2 c = float2(vid & 1, vid >> 1);
        float2 local = (c - .5) * s.size;
        float sn = sin(s.angle), co = cos(s.angle);
        float2 px = s.pos + float2(co * local.x - sn * local.y, sn * local.x + co * local.y);
        SpriteOut o;
        o.position = float4(px.x / res.x * 2. - 1., 1. - px.y / res.y * 2., 0., 1.);
        o.uv = mix(s.uv.xy, s.uv.zw, c);
        o.alpha = s.alpha;
        o.flash = s.flash;
        o.tint = s.tint;
        return o;
    }

    // Premultiplied output.
    fragment float4 chaos_sprite_fragment(SpriteOut in [[stage_in]], texture2d<float> tex [[texture(0)]]) {
        constexpr sampler smp(coord::normalized, address::clamp_to_edge, filter::linear);
        float4 t = tex.sample(smp, in.uv);
        float3 rgb = mix(t.rgb, in.tint.rgb * t.a, in.tint.a);
        rgb += in.flash * t.a * float3(1., .9, .7);
        return float4(rgb, t.a) * in.alpha;
    }

    struct Tri {
        float2 pos;     // centroid, points
        float2 a, b, c; // corners relative to pos
        float2 ua, ub, uc;
        float angle;
        float alpha;
        float flash;
        float feather;  // 1 = soften the edges (loose pieces)
        float2 pad;
        float4 tint;
    };

    struct TriOut {
        float4 position [[position]];
        float2 uv;
        float3 bary;
        float alpha;
        float flash;
        float feather;
        float4 tint;
    };

    vertex TriOut chaos_tri_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                   constant Tri *tris [[buffer(0)]], constant float2 &res [[buffer(1)]]) {
        Tri s = tris[iid];
        float2 local = vid == 0 ? s.a : (vid == 1 ? s.b : s.c);
        float sn = sin(s.angle), co = cos(s.angle);
        float2 px = s.pos + float2(co * local.x - sn * local.y, sn * local.x + co * local.y);
        TriOut o;
        o.position = float4(px.x / res.x * 2. - 1., 1. - px.y / res.y * 2., 0., 1.);
        o.uv = vid == 0 ? s.ua : (vid == 1 ? s.ub : s.uc);
        o.bary = float3(vid == 0 ? 1. : 0., vid == 1 ? 1. : 0., vid == 2 ? 1. : 0.);
        o.alpha = s.alpha;
        o.flash = s.flash;
        o.feather = s.feather;
        o.tint = s.tint;
        return o;
    }

    // Premultiplied output; the edge of a loose piece fades over one pixel instead of being jagged.
    fragment float4 chaos_tri_fragment(TriOut in [[stage_in]], texture2d<float> tex [[texture(0)]]) {
        constexpr sampler smp(coord::normalized, address::clamp_to_edge, filter::linear);
        float4 t = tex.sample(smp, in.uv);
        float3 rgb = mix(t.rgb, in.tint.rgb * t.a, in.tint.a);
        rgb += in.flash * t.a * float3(1., .9, .7);
        float m = min(min(in.bary.x, in.bary.y), in.bary.z);
        float edge = in.feather > .5 ? clamp(m / max(fwidth(m), 1e-5), 0., 1.) : 1.;
        return float4(rgb, t.a) * (in.alpha * edge);
    }

    struct Puff {
        float2 pos;
        float size;     // radius, points
        float alpha;
        float4 color;
    };

    struct PuffOut {
        float4 position [[position]];
        float pointSize [[point_size]];
        float4 color;
    };

    vertex PuffOut chaos_puff_vertex(uint vid [[vertex_id]], constant Puff *puffs [[buffer(0)]],
                                     constant float2 &res [[buffer(1)]], constant float &pixelScale [[buffer(2)]]) {
        Puff p = puffs[vid];
        PuffOut o;
        o.position = float4(p.pos.x / res.x * 2. - 1., 1. - p.pos.y / res.y * 2., 0., 1.);
        o.pointSize = clamp(p.size * 2. * pixelScale, 1., 480.);
        o.color = float4(p.color.rgb, p.color.a * p.alpha);
        return o;
    }

    fragment float4 chaos_puff_fragment(PuffOut in [[stage_in]], float2 pc [[point_coord]]) {
        float d = length(pc - .5) * 2.;
        float a = 1. - smoothstep(0., 1., d);
        a *= a;
        float al = in.color.a * a;
        return float4(in.color.rgb * al, al);
    }

    vertex float4 chaos_fade_vertex(uint vid [[vertex_id]]) {
        float2 p = float2((vid << 1) & 2, vid & 2);
        return float4(p * 2. - 1., 0., 1.);
    }

    fragment float4 chaos_fade_fragment(constant float &a [[buffer(0)]]) {
        return float4(0., 0., 0., a);
    }
    """#
}

private struct SpriteInstance {
    var pos: SIMD2<Float>
    var size: SIMD2<Float>
    var uv: SIMD4<Float>
    var angle: Float = 0
    var alpha: Float = 1
    var flash: Float = 0
    var pad: Float = 0
    var tint = SIMD4<Float>(0, 0, 0, 0)
}

private struct TriInstance {
    var pos: SIMD2<Float>
    var a: SIMD2<Float>
    var b: SIMD2<Float>
    var c: SIMD2<Float>
    var ua: SIMD2<Float>
    var ub: SIMD2<Float>
    var uc: SIMD2<Float>
    var angle: Float = 0
    var alpha: Float = 1
    var flash: Float = 0
    var feather: Float = 0
    var pad = SIMD2<Float>(0, 0)
    var tint = SIMD4<Float>(0, 0, 0, 0)
}

private struct PuffInstance {
    var pos: SIMD2<Float>
    var size: Float
    var alpha: Float
    var color: SIMD4<Float>
}

/// Letters, buttons and icons of every window packed into one premultiplied RGBA texture.
private final class ChaosAtlas {
    let texture: MTLTexture
    /// Atlas rectangle (u0, v0, u1, v1) of every sprite; nil when it did not fit.
    let rects: [SIMD4<Float>?]

    private static let width = 4096
    private static let maxHeight = 4096

    init?(device: MTLDevice, objects: [UIObject]) {
        let order = objects.indices.sorted { objects[$0].pixelHeight > objects[$1].pixelHeight }
        var origins = [(x: Int, y: Int)?](repeating: nil, count: objects.count)
        var x = 0, y = 0, shelf = 0
        for i in order {
            let o = objects[i]
            guard o.pixelWidth <= Self.width, o.pixelHeight <= Self.maxHeight else { continue }
            if x + o.pixelWidth + 1 > Self.width { y += shelf + 1; x = 0; shelf = 0 }
            guard y + o.pixelHeight <= Self.maxHeight else { continue }
            origins[i] = (x, y)
            x += o.pixelWidth + 1
            shelf = max(shelf, o.pixelHeight)
        }
        let height = max(64, ((y + shelf + 63) / 64) * 64)
        var data = [UInt8](repeating: 0, count: Self.width * height * 4)
        var rects = [SIMD4<Float>?](repeating: nil, count: objects.count)
        for i in objects.indices {
            guard let origin = origins[i] else { continue }
            let o = objects[i]
            for row in 0..<o.pixelHeight {
                let src = row * o.pixelWidth * 4, dst = ((origin.y + row) * Self.width + origin.x) * 4
                data.replaceSubrange(dst..<(dst + o.pixelWidth * 4), with: o.rgba[src..<(src + o.pixelWidth * 4)])
            }
            rects[i] = SIMD4(Float(origin.x) / Float(Self.width), Float(origin.y) / Float(height),
                             Float(origin.x + o.pixelWidth) / Float(Self.width), Float(origin.y + o.pixelHeight) / Float(height))
        }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: Self.width, height: height, mipmapped: false)
        d.usage = .shaderRead
        d.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: d) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, Self.width, height), mipmapLevel: 0, withBytes: data, bytesPerRow: Self.width * 4)
        self.texture = texture
        self.rects = rects
    }
}

enum ChaosTexture {
    /// Uploads a picture as premultiplied RGBA. Pictures that already are 8-bit RGBA are copied byte for byte.
    static func make(device: MTLDevice, image: CGImage) -> MTLTexture? {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
        d.usage = .shaderRead
        d.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: d) else { return nil }
        let region = MTLRegionMake2D(0, 0, w, h)
        let native = image.bitsPerComponent == 8 && image.bitsPerPixel == 32 && image.alphaInfo == .premultipliedLast
            && image.byteOrderInfo != .order32Big && image.bytesPerRow == w * 4
        if native, let data = image.dataProvider?.data, CFDataGetLength(data) >= w * h * 4 {
            texture.replace(region: region, mipmapLevel: 0, withBytes: CFDataGetBytePtr(data), bytesPerRow: w * 4)
            return texture
        }
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        texture.replace(region: region, mipmapLevel: 0, withBytes: pixels, bytesPerRow: w * 4)
        return texture
    }
}

/// Draws one screen of the chaos screen saver: the wallpaper, the windows as a grid of pieces, the letters, buttons
/// and icons on top, and the smoke and flames of the blasts. Runs the `ChaosWorld` and restores the desktop (with a fade)
/// once most of it has been destroyed.
final class ChaosRenderer {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let screenSize: SIMD2<Float>
    let pixelScale: Float

    private enum Phase { case playing, fadingOut, fadingIn }

    private let scene: ChaosScene
    private let settings: ChaosSettings
    private(set) var world: ChaosWorld
    private var phase = Phase.playing
    private var fade: Float = 0
    /// Seconds since the saver started.
    private(set) var elapsed: Float = 0

    private let spritePipeline: MTLRenderPipelineState
    private let triPipeline: MTLRenderPipelineState
    private let puffPipeline: MTLRenderPipelineState
    private let puffAdditivePipeline: MTLRenderPipelineState
    private let fadePipeline: MTLRenderPipelineState
    private let wallpaper: MTLTexture
    private let windowTextures: [MTLTexture?]
    private let atlas: ChaosAtlas?

    private let spriteCapacity: Int
    private let puffCapacity = ChaosWorld.maxPuffs
    private static let slots = 3
    private let spriteBuffers: [MTLBuffer]
    private let triBuffers: [MTLBuffer]
    private let puffBuffers: [MTLBuffer]
    private let inFlight = DispatchSemaphore(value: ChaosRenderer.slots)
    private var slot = 0

    private var attachedShards: [[TriInstance]]
    private var attachedSprites: [[SpriteInstance]]
    private var looseShards: [[TriInstance]]
    private var looseSprites: [SpriteInstance] = []

    private static var library: MTLLibrary?

    init(device: MTLDevice, scene: ChaosScene, screenSize: CGSize, pixelScale: CGFloat, wallpaper: CGImage, settings: ChaosSettings) throws {
        guard let queue = device.makeCommandQueue(), let wallpaperTexture = ChaosTexture.make(device: device, image: wallpaper) else {
            throw ChaosRendererError.noDevice
        }
        self.device = device
        self.queue = queue
        self.scene = scene
        self.settings = settings
        self.wallpaper = wallpaperTexture
        self.screenSize = SIMD2(Float(screenSize.width), Float(screenSize.height))
        self.pixelScale = Float(pixelScale)
        world = ChaosWorld(seeds: scene.seeds, size: self.screenSize, settings: settings)
        windowTextures = scene.pictures.map { ChaosTexture.make(device: device, image: $0) }
        atlas = scene.sprites.isEmpty ? nil : ChaosAtlas(device: device, objects: scene.sprites)
        let groups = scene.pictures.count
        attachedShards = Array(repeating: [], count: groups)
        attachedSprites = Array(repeating: [], count: groups)
        looseShards = Array(repeating: [], count: groups)

        let library: MTLLibrary
        if let cached = Self.library { library = cached } else {
            do { library = try device.makeLibrary(source: ChaosShaders.source, options: nil) } catch {
                throw ChaosRendererError.shaderFailed(error.localizedDescription)
            }
            Self.library = library
        }
        func pipeline(_ vertex: String, _ fragment: String, additive: Bool = false) throws -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: vertex)
            d.fragmentFunction = library.makeFunction(name: fragment)
            d.colorAttachments[0].pixelFormat = .bgra8Unorm
            let c = d.colorAttachments[0]!
            c.isBlendingEnabled = true
            c.rgbBlendOperation = .add
            c.alphaBlendOperation = .add
            c.sourceRGBBlendFactor = .one
            c.sourceAlphaBlendFactor = .one
            c.destinationRGBBlendFactor = additive ? .one : .oneMinusSourceAlpha
            c.destinationAlphaBlendFactor = additive ? .one : .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor: d)
        }
        spritePipeline = try pipeline("chaos_sprite_vertex", "chaos_sprite_fragment")
        triPipeline = try pipeline("chaos_tri_vertex", "chaos_tri_fragment")
        puffPipeline = try pipeline("chaos_puff_vertex", "chaos_puff_fragment")
        puffAdditivePipeline = try pipeline("chaos_puff_vertex", "chaos_puff_fragment", additive: true)
        fadePipeline = try pipeline("chaos_fade_vertex", "chaos_fade_fragment")

        spriteCapacity = world.maxBodies + 8
        var sprites: [MTLBuffer] = [], tris: [MTLBuffer] = [], puffs: [MTLBuffer] = []
        for _ in 0..<Self.slots {
            guard let s = device.makeBuffer(length: spriteCapacity * MemoryLayout<SpriteInstance>.stride, options: .storageModeShared),
                  let t = device.makeBuffer(length: spriteCapacity * MemoryLayout<TriInstance>.stride, options: .storageModeShared),
                  let p = device.makeBuffer(length: puffCapacity * MemoryLayout<PuffInstance>.stride, options: .storageModeShared)
            else { throw ChaosRendererError.noDevice }
            sprites.append(s)
            tris.append(t)
            puffs.append(p)
        }
        spriteBuffers = sprites
        triBuffers = tris
        puffBuffers = puffs
    }

    // MARK: - Frame

    private func advance(_ dt: Float) {
        elapsed += dt
        switch phase {
        case .playing:
            world.step(dt: dt)
            if world.isExhausted { phase = .fadingOut }
        case .fadingOut:
            world.step(dt: dt)
            fade = min(1, fade + dt / 1.0)
            if fade >= 1 {
                world = ChaosWorld(seeds: scene.seeds, size: screenSize, settings: settings)
                phase = .fadingIn
            }
        case .fadingIn:
            fade = max(0, fade - dt / 0.8)
            if fade <= 0 { phase = .playing }
        }
    }

    func encodeFrame(commands: MTLCommandBuffer, target: MTLTexture, dt: Float) {
        inFlight.wait()
        commands.addCompletedHandler { [inFlight] _ in inFlight.signal() }
        advance(dt)
        let s = slot
        slot = (slot + 1) % Self.slots

        buildInstances()
        var spriteOffset = 0, triOffset = 0
        let spritePointer = spriteBuffers[s].contents().bindMemory(to: SpriteInstance.self, capacity: spriteCapacity)
        let triPointer = triBuffers[s].contents().bindMemory(to: TriInstance.self, capacity: spriteCapacity)
        struct Segment { var start: Int; var count: Int; var texture: MTLTexture; var triangles: Bool }
        var segments: [Segment] = []
        func add(_ instances: [SpriteInstance], _ texture: MTLTexture?) {
            guard !instances.isEmpty, let texture, spriteOffset + instances.count <= spriteCapacity else { return }
            instances.withUnsafeBufferPointer { (spritePointer + spriteOffset).update(from: $0.baseAddress!, count: instances.count) }
            segments.append(Segment(start: spriteOffset, count: instances.count, texture: texture, triangles: false))
            spriteOffset += instances.count
        }
        func add(_ instances: [TriInstance], _ texture: MTLTexture?) {
            guard !instances.isEmpty, let texture, triOffset + instances.count <= spriteCapacity else { return }
            instances.withUnsafeBufferPointer { (triPointer + triOffset).update(from: $0.baseAddress!, count: instances.count) }
            segments.append(Segment(start: triOffset, count: instances.count, texture: texture, triangles: true))
            triOffset += instances.count
        }
        add([SpriteInstance(pos: screenSize / 2, size: screenSize, uv: SIMD4(0, 0, 1, 1))], wallpaper)
        for g in scene.pictures.indices {
            add(attachedShards[g], windowTextures[g])
            add(attachedSprites[g], atlas?.texture)
        }
        for g in scene.pictures.indices { add(looseShards[g], windowTextures[g]) }
        add(looseSprites, atlas?.texture)

        let puffs = fillPuffs(into: puffBuffers[s])

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        var resolution = screenSize
        encoder.setRenderPipelineState(spritePipeline)
        encoder.setVertexBytes(&resolution, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
        var usingTriangles = false
        for segment in segments {
            if segment.triangles != usingTriangles {
                usingTriangles = segment.triangles
                encoder.setRenderPipelineState(usingTriangles ? triPipeline : spritePipeline)
            }
            encoder.setFragmentTexture(segment.texture, index: 0)
            if segment.triangles {
                encoder.setVertexBuffer(triBuffers[s], offset: segment.start * MemoryLayout<TriInstance>.stride, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3, instanceCount: segment.count)
            } else {
                encoder.setVertexBuffer(spriteBuffers[s], offset: segment.start * MemoryLayout<SpriteInstance>.stride, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: segment.count)
            }
        }
        var scale = pixelScale
        if puffs.normal > 0 {
            encoder.setRenderPipelineState(puffPipeline)
            encoder.setVertexBuffer(puffBuffers[s], offset: 0, index: 0)
            encoder.setVertexBytes(&resolution, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
            encoder.setVertexBytes(&scale, length: MemoryLayout<Float>.size, index: 2)
            encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: puffs.normal)
        }
        if puffs.additive > 0 {
            encoder.setRenderPipelineState(puffAdditivePipeline)
            encoder.setVertexBuffer(puffBuffers[s], offset: 0, index: 0)
            encoder.setVertexBytes(&resolution, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
            encoder.setVertexBytes(&scale, length: MemoryLayout<Float>.size, index: 2)
            encoder.drawPrimitives(type: .point, vertexStart: puffs.normal, vertexCount: puffs.additive)
        }
        if fade > 0.001 {
            var alpha = fade
            encoder.setRenderPipelineState(fadePipeline)
            encoder.setFragmentBytes(&alpha, length: MemoryLayout<Float>.size, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        encoder.endEncoding()
    }

    /// Renders the current state once into a picture (debugging aid); the world does not advance.
    func snapshot() -> CGImage? {
        let width = Int(screenSize.x * pixelScale), height = Int(screenSize.y * pixelScale)
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: d), let commands = queue.makeCommandBuffer() else { return nil }
        encodeFrame(commands: commands, target: texture, dt: 0)
        commands.commit()
        commands.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    // MARK: - Instances

    private func buildInstances() {
        for g in scene.pictures.indices {
            attachedShards[g].removeAll(keepingCapacity: true)
            attachedSprites[g].removeAll(keepingCapacity: true)
            looseShards[g].removeAll(keepingCapacity: true)
        }
        looseSprites.removeAll(keepingCapacity: true)
        // Pieces in place overlap by half a pixel so no seam shows between them.
        let pad = 0.5 / pixelScale

        for b in world.bodies where b.state != .gone {
            let inPlace = b.state != .loose
            if b.kind == .shard {
                var s = b.shape
                if b.state == .attached {
                    // Grow the triangle about its centre so neighbours overlap a little and no seam shows.
                    let k = 1 + 2 * pad / max(s.meanRadius, 1)
                    let uvCenter = (s.ua + s.ub + s.uc) / 3
                    s.a *= k; s.b *= k; s.c *= k
                    s.ua = uvCenter + (s.ua - uvCenter) * k
                    s.ub = uvCenter + (s.ub - uvCenter) * k
                    s.uc = uvCenter + (s.uc - uvCenter) * k
                }
                let instance = TriInstance(pos: b.pos, a: s.a, b: s.b, c: s.c, ua: s.ua, ub: s.ub, uc: s.uc, angle: b.angle, alpha: b.alpha,
                                           flash: b.flash, feather: inPlace ? 0 : 1, tint: b.tint)
                if inPlace { attachedShards[b.group].append(instance) } else { looseShards[b.group].append(instance) }
            } else if let atlas, let uv = atlas.rects[b.sprite] {
                let instance = SpriteInstance(pos: b.pos, size: b.size * b.scale, uv: uv, angle: b.angle, alpha: b.alpha, flash: b.flash, tint: b.tint)
                if inPlace { attachedSprites[b.group].append(instance) } else { looseSprites.append(instance) }
            }
        }
    }

    private func fillPuffs(into buffer: MTLBuffer) -> (normal: Int, additive: Int) {
        let pointer = buffer.contents().bindMemory(to: PuffInstance.self, capacity: puffCapacity)
        var n = 0
        var additive: [PuffInstance] = []
        for p in world.puffs {
            let t = min(1, p.age / p.life)
            switch p.kind {
            case .smoke:
                guard n < puffCapacity else { break }
                pointer[n] = PuffInstance(pos: p.pos, size: p.size, alpha: 0.5 * (1 - t) * min(1, p.age * 5), color: SIMD4(0.17, 0.17, 0.19, 1))
                n += 1
            case .dust:
                guard n < puffCapacity else { break }
                pointer[n] = PuffInstance(pos: p.pos, size: p.size, alpha: 0.35 * (1 - t), color: SIMD4(0.82, 0.79, 0.74, 1))
                n += 1
            case .flame:
                let color = t < 0.35 ? mix(SIMD3(1, 0.96, 0.7), SIMD3(1, 0.55, 0.12), t / 0.35) : mix(SIMD3(1, 0.55, 0.12), SIMD3(0.45, 0.06, 0.02), (t - 0.35) / 0.65)
                additive.append(PuffInstance(pos: p.pos, size: p.size, alpha: 0.9 * (1 - t), color: SIMD4(color, 1)))
            case .spark:
                additive.append(PuffInstance(pos: p.pos, size: p.size, alpha: 1 - t, color: SIMD4(1, 0.78, 0.35, 1)))
            }
        }
        let room = max(0, puffCapacity - n)
        for (i, p) in additive.prefix(room).enumerated() { pointer[n + i] = p }
        return (n, min(additive.count, room))
    }

    private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { a + (b - a) * t }
}
