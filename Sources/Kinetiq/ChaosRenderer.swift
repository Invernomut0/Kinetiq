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
                                         constant Sprite *sprites [[buffer(0)]], constant float2 &res [[buffer(1)]],
                                         constant float2 &shift [[buffer(3)]]) {
        Sprite s = sprites[iid];
        float2 c = float2(vid & 1, vid >> 1);
        float2 local = (c - .5) * s.size;
        float sn = sin(s.angle), co = cos(s.angle);
        float2 px = s.pos + shift + float2(co * local.x - sn * local.y, sn * local.x + co * local.y);
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
        float feather;  // 0 in place, 1 loose (soft edge), 2 in place with a burning edge
        float erode;    // how far the burning edge has been consumed, pixels
        float2 burn;    // burn (charred edge, 0...1), heat (glowing edge, 0...1)
        float4 tint;
    };

    struct TriOut {
        float4 position [[position]];
        float2 uv;
        float3 bary;
        float alpha;
        float flash;
        float feather;
        float erode;
        float2 burn;
        float4 tint;
    };

    float hash21(float2 p) {
        p = fract(p * float2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    float vnoise(float2 p) {
        float2 i = floor(p), f = fract(p);
        f = f * f * (3. - 2. * f);
        return mix(mix(hash21(i), hash21(i + float2(1., 0.)), f.x), mix(hash21(i + float2(0., 1.)), hash21(i + float2(1., 1.)), f.x), f.y);
    }

    vertex TriOut chaos_tri_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                   constant Tri *tris [[buffer(0)]], constant float2 &res [[buffer(1)]],
                                   constant float2 &shift [[buffer(3)]]) {
        Tri s = tris[iid];
        float2 local = vid == 0 ? s.a : (vid == 1 ? s.b : s.c);
        float sn = sin(s.angle), co = cos(s.angle);
        float2 px = s.pos + shift + float2(co * local.x - sn * local.y, sn * local.x + co * local.y);
        TriOut o;
        o.position = float4(px.x / res.x * 2. - 1., 1. - px.y / res.y * 2., 0., 1.);
        o.uv = vid == 0 ? s.ua : (vid == 1 ? s.ub : s.uc);
        o.bary = float3(vid == 0 ? 1. : 0., vid == 1 ? 1. : 0., vid == 2 ? 1. : 0.);
        o.alpha = s.alpha;
        o.flash = s.flash;
        o.feather = s.feather;
        o.erode = s.erode;
        o.burn = s.burn;
        o.tint = s.tint;
        return o;
    }

    // Premultiplied output; the edge of a loose piece fades over one pixel instead of being jagged.
    fragment float4 chaos_tri_fragment(TriOut in [[stage_in]], texture2d<float> tex [[texture(0)]], constant float &clock [[buffer(1)]]) {
        constexpr sampler smp(coord::normalized, address::clamp_to_edge, filter::linear);
        float4 t = tex.sample(smp, in.uv);
        float3 rgb = mix(t.rgb, in.tint.rgb * t.a, in.tint.a);
        rgb += in.flash * t.a * float3(1., .9, .7);
        float m = in.bary.x;   // 1 at the centre of the piece, 0 along its outer edge
        float d = m / max(fwidth(m), 1e-5);   // distance to the edge in pixels
        bool loose = in.feather > .5 && in.feather < 1.5;
        bool burning = in.feather > 1.5;
        float n = vnoise(in.uv * 1100.);
        // A burning edge is eaten away unevenly, so it is ragged instead of sharp.
        float cut = burning ? in.erode * (.35 + .65 * vnoise(in.uv * 520. + 3.7)) : 0.;
        float edge = loose ? clamp(d, 0., 1.) : (burning ? smoothstep(cut, cut + 1.6, d) : 1.);
        float dd = max(d - cut, 0.);
        // Broken edges are charred (dark, ragged) and glow while they are hot.
        float width = (5. + 11. * n) * in.burn.x;
        float charred = (loose || burning) ? in.burn.x * (1. - smoothstep(0., max(width, .001), dd)) : 0.;
        rgb = mix(rgb, rgb * .1 + float3(.025, .014, .008) * t.a, charred * .92);
        float flicker = burning ? .6 + .4 * vnoise(in.uv * 300. + clock * 1.7) : 1.;
        float ember = (loose || burning) ? in.burn.y * flicker * (1. - smoothstep(0., 2.2 + 2.4 * n, dd)) * (.55 + .45 * n) : 0.;
        rgb += ember * t.a * float3(1., .42, .08) * 1.5;
        // A thin pale rim, like the edge of broken glass.
        rgb += (loose ? (1. - clamp(d / 3., 0., 1.)) * .22 * (1. - in.burn.x) : 0.) * t.a * float3(.8, .9, 1.);
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
                                     constant float2 &res [[buffer(1)]], constant float &pixelScale [[buffer(2)]],
                                     constant float2 &shift [[buffer(3)]]) {
        Puff p = puffs[vid];
        PuffOut o;
        float2 at = p.pos + shift;
        o.position = float4(at.x / res.x * 2. - 1., 1. - at.y / res.y * 2., 0., 1.);
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

    struct Crack {
        float2 pos;     // piece position, points
        float2 p0, p1;  // segment relative to the piece
        float angle;
        float alpha;
        float width;
        float pad;
    };

    struct CrackOut {
        float4 position [[position]];
        float across;   // distance from the middle of the line, points
        float halfWidth;
        float alpha;
    };

    vertex CrackOut chaos_crack_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                       constant Crack *cracks [[buffer(0)]], constant float2 &res [[buffer(1)]],
                                       constant float2 &shift [[buffer(3)]]) {
        Crack c = cracks[iid];
        float2 d = c.p1 - c.p0;
        float len = max(length(d), 1e-3);
        float2 u = d / len, nrm = float2(-u.y, u.x);
        float hw = c.width * .5;
        float reach = hw + 1.2;   // room for the soft edge
        float along = (vid & 1) ? 1. : 0.;
        float side = (vid >> 1) ? 1. : -1.;
        float2 local = mix(c.p0 - u * hw, c.p1 + u * hw, along) + nrm * side * reach;
        float sn = sin(c.angle), co = cos(c.angle);
        float2 px = c.pos + shift + float2(co * local.x - sn * local.y, sn * local.x + co * local.y);
        CrackOut o;
        o.position = float4(px.x / res.x * 2. - 1., 1. - px.y / res.y * 2., 0., 1.);
        o.across = side * reach;
        o.halfWidth = hw;
        o.alpha = c.alpha;
        return o;
    }

    // A dark groove with a faint pale chip along its sides.
    fragment float4 chaos_crack_fragment(CrackOut in [[stage_in]]) {
        float x = abs(in.across);
        float core = 1. - smoothstep(in.halfWidth - .35, in.halfWidth + .45, x);
        float rim = (1. - smoothstep(in.halfWidth + .2, in.halfWidth + 1.1, x)) * (1. - core);
        float a = core * .8 + rim * .16;
        float3 rgb = float3(.02) * core * .8 + float3(.9, .95, 1.) * rim * .16;
        return float4(rgb, a) * in.alpha;
    }

    vertex float4 chaos_fade_vertex(uint vid [[vertex_id]]) {
        float2 p = float2((vid << 1) & 2, vid & 2);
        return float4(p * 2. - 1., 0., 1.);
    }

    fragment float4 chaos_fade_fragment(constant float4 &color [[buffer(0)]]) {
        return float4(color.rgb * color.a, color.a);
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
    var erode: Float = 0
    var pad0: Float = 0
    var burn = SIMD2<Float>(0, 0)
    var pad1 = SIMD2<Float>(0, 0)
    var tint = SIMD4<Float>(0, 0, 0, 0)
}

private struct CrackInstance {
    var pos: SIMD2<Float>
    var p0: SIMD2<Float>
    var p1: SIMD2<Float>
    var angle: Float
    var alpha: Float
    var width: Float
    var pad: Float = 0
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
    /// Frames drawn so far (debugging aid).
    private(set) var frames = 0

    private let spritePipeline: MTLRenderPipelineState
    private let triPipeline: MTLRenderPipelineState
    private let crackPipeline: MTLRenderPipelineState
    private let puffPipeline: MTLRenderPipelineState
    private let puffAdditivePipeline: MTLRenderPipelineState
    private let fadePipeline: MTLRenderPipelineState
    private let wallpaper: MTLTexture
    private let windowTextures: [MTLTexture?]
    private let atlas: ChaosAtlas?

    private let spriteCapacity: Int
    private let triCapacity: Int
    private let puffCapacity = ChaosWorld.maxPuffs
    private static let slots = 3
    private let spriteBuffers: [MTLBuffer]
    private let triBuffers: [MTLBuffer]
    private let crackBuffers: [MTLBuffer]
    private let crackCapacity = 40_000
    private let puffBuffers: [MTLBuffer]
    private let inFlight = DispatchSemaphore(value: ChaosRenderer.slots)
    private var slot = 0

    private var attachedShards: [[TriInstance]]
    private var attachedSprites: [[SpriteInstance]]
    private var looseShards: [[TriInstance]]
    private var attachedCracks: [[CrackInstance]]
    private var looseCracks: [[CrackInstance]]
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
        attachedCracks = Array(repeating: [], count: groups)
        looseCracks = Array(repeating: [], count: groups)

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
        crackPipeline = try pipeline("chaos_crack_vertex", "chaos_crack_fragment")
        puffPipeline = try pipeline("chaos_puff_vertex", "chaos_puff_fragment")
        puffAdditivePipeline = try pipeline("chaos_puff_vertex", "chaos_puff_fragment", additive: true)
        fadePipeline = try pipeline("chaos_fade_vertex", "chaos_fade_fragment")

        spriteCapacity = world.maxBodies + 8
        triCapacity = world.maxBodies * 5
        var sprites: [MTLBuffer] = [], tris: [MTLBuffer] = [], cracks: [MTLBuffer] = [], puffs: [MTLBuffer] = []
        for _ in 0..<Self.slots {
            guard let s = device.makeBuffer(length: spriteCapacity * MemoryLayout<SpriteInstance>.stride, options: .storageModeShared),
                  let t = device.makeBuffer(length: triCapacity * MemoryLayout<TriInstance>.stride, options: .storageModeShared),
                  let k = device.makeBuffer(length: crackCapacity * MemoryLayout<CrackInstance>.stride, options: .storageModeShared),
                  let p = device.makeBuffer(length: puffCapacity * MemoryLayout<PuffInstance>.stride, options: .storageModeShared)
            else { throw ChaosRendererError.noDevice }
            sprites.append(s)
            tris.append(t)
            cracks.append(k)
            puffs.append(p)
        }
        spriteBuffers = sprites
        triBuffers = tris
        crackBuffers = cracks
        puffBuffers = puffs
    }

    // MARK: - Frame

    func simulate(_ dt: Float) {
        elapsed += dt
        switch phase {
        case .playing:
            world.step(dt: dt)
            if world.isExhausted { phase = .fadingOut }
        case .fadingOut:
            world.step(dt: dt)
            fade = min(1, fade + dt / 1.0)
            if fade >= 1 {
                let spent = world.nukeSpent
                world = ChaosWorld(seeds: scene.seeds, size: screenSize, settings: settings)
                world.nukeSpent = spent   // one nuclear blast per session
                phase = .fadingIn
            }
        case .fadingIn:
            fade = max(0, fade - dt / 0.8)
            if fade <= 0 { phase = .playing }
        }
    }

    func encodeFrame(commands: MTLCommandBuffer, target: MTLTexture, dt: Float) {
        frames += 1
        inFlight.wait()
        commands.addCompletedHandler { [inFlight] _ in inFlight.signal() }
        simulate(dt)
        let s = slot
        slot = (slot + 1) % Self.slots

        buildInstances()
        var spriteOffset = 0, triOffset = 0
        let spritePointer = spriteBuffers[s].contents().bindMemory(to: SpriteInstance.self, capacity: spriteCapacity)
        let triPointer = triBuffers[s].contents().bindMemory(to: TriInstance.self, capacity: triCapacity)
        struct Segment { var start: Int; var count: Int; var texture: MTLTexture?; var kind: Int }   // kind: 0 sprites, 1 triangles, 2 cracks
        var segments: [Segment] = []
        var crackOffset = 0
        let crackPointer = crackBuffers[s].contents().bindMemory(to: CrackInstance.self, capacity: crackCapacity)
        func add(_ instances: [SpriteInstance], _ texture: MTLTexture?) {
            guard !instances.isEmpty, let texture, spriteOffset + instances.count <= spriteCapacity else { return }
            instances.withUnsafeBufferPointer { (spritePointer + spriteOffset).update(from: $0.baseAddress!, count: instances.count) }
            segments.append(Segment(start: spriteOffset, count: instances.count, texture: texture, kind: 0))
            spriteOffset += instances.count
        }
        func add(_ instances: [TriInstance], _ texture: MTLTexture?) {
            guard !instances.isEmpty, let texture, triOffset + instances.count <= triCapacity else { return }
            instances.withUnsafeBufferPointer { (triPointer + triOffset).update(from: $0.baseAddress!, count: instances.count) }
            segments.append(Segment(start: triOffset, count: instances.count, texture: texture, kind: 1))
            triOffset += instances.count
        }
        func add(_ instances: [CrackInstance]) {
            guard !instances.isEmpty, crackOffset + instances.count <= crackCapacity else { return }
            instances.withUnsafeBufferPointer { (crackPointer + crackOffset).update(from: $0.baseAddress!, count: instances.count) }
            segments.append(Segment(start: crackOffset, count: instances.count, texture: nil, kind: 2))
            crackOffset += instances.count
        }
        add([SpriteInstance(pos: screenSize / 2, size: screenSize + SIMD2(64, 64), uv: SIMD4(0, 0, 1, 1))], wallpaper)
        for g in scene.pictures.indices {
            add(attachedShards[g], windowTextures[g])
            add(attachedCracks[g])
            add(attachedSprites[g], atlas?.texture)
        }
        for g in scene.pictures.indices {
            add(looseShards[g], windowTextures[g])
            add(looseCracks[g])
        }
        add(looseSprites, atlas?.texture)

        let puffs = fillPuffs(into: puffBuffers[s])

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        var resolution = screenSize
        // The whole picture shakes with the big blasts.
        let shake = world.shake
        var shift = shake > 0.05 ? SIMD2(Float.random(in: -shake...shake), Float.random(in: -shake...shake)) : SIMD2<Float>(0, 0)
        encoder.setRenderPipelineState(spritePipeline)
        encoder.setVertexBytes(&resolution, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
        encoder.setVertexBytes(&shift, length: MemoryLayout<SIMD2<Float>>.size, index: 3)
        var clock = elapsed
        encoder.setFragmentBytes(&clock, length: MemoryLayout<Float>.size, index: 1)
        var current = 0
        for segment in segments {
            if segment.kind != current {
                current = segment.kind
                encoder.setRenderPipelineState(current == 0 ? spritePipeline : (current == 1 ? triPipeline : crackPipeline))
            }
            if let texture = segment.texture { encoder.setFragmentTexture(texture, index: 0) }
            switch segment.kind {
            case 1:
                encoder.setVertexBuffer(triBuffers[s], offset: segment.start * MemoryLayout<TriInstance>.stride, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3, instanceCount: segment.count)
            case 2:
                encoder.setVertexBuffer(crackBuffers[s], offset: segment.start * MemoryLayout<CrackInstance>.stride, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: segment.count)
            default:
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
        if world.flash > 0.01 {
            var color = SIMD4<Float>(1, 0.94, 0.8, min(1, world.flash))
            encoder.setRenderPipelineState(fadePipeline)
            encoder.setFragmentBytes(&color, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        if fade > 0.001 {
            var color = SIMD4<Float>(0, 0, 0, fade)
            encoder.setRenderPipelineState(fadePipeline)
            encoder.setFragmentBytes(&color, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
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
            attachedCracks[g].removeAll(keepingCapacity: true)
            looseCracks[g].removeAll(keepingCapacity: true)
        }
        looseSprites.removeAll(keepingCapacity: true)
        // Pieces in place overlap by half a pixel so no seam shows between them.
        let pad = 0.5 / pixelScale

        for (index, b) in world.bodies.enumerated() where b.state != .gone {
            let inPlace = b.state != .loose
            if b.kind == .shard {
                let poly = world.polygons[Int(b.polygon)]
                // In place, the piece grows a little about its centre so neighbours overlap and no seam shows.
                let k: Float = b.state == .attached ? 1 + 2 * pad / max(poly.meanRadius, 1) : 1
                let n = poly.verts.count
                for v in 0..<n {
                    let p1 = poly.verts[v] * k, p2 = poly.verts[(v + 1) % n] * k
                    var instance = TriInstance(pos: b.pos, a: .zero, b: p1, c: p2, ua: poly.uv(.zero), ub: poly.uv(p1), uc: poly.uv(p2),
                                               angle: b.angle, alpha: b.alpha, flash: b.flash, feather: inPlace ? 0 : 1,
                                               burn: SIMD2(b.burn, b.heat), tint: b.tint)
                    // The edge a broken-away neighbour left bare burns and is eaten away very slowly.
                    if b.state == .attached, index < world.originalCount {
                        let age = world.edgeBurnAge(body: index, edge: v)
                        if age >= 0 {
                            instance.feather = 2
                            instance.erode = min(9, age * 0.2)
                            instance.burn = SIMD2(min(1, 0.55 + age / 40), max(0.25, exp(-age / 45)))
                        }
                    }
                    if inPlace { attachedShards[b.group].append(instance) } else { looseShards[b.group].append(instance) }
                }
                if b.crack >= 0 {
                    for (index, segment) in world.crackSets[Int(b.crack)].enumerated() {
                        let width = 1.0 + 0.7 * Float((index * 7 + Int(b.crack)) % 5) / 4
                        let instance = CrackInstance(pos: b.pos, p0: SIMD2(segment.x, segment.y), p1: SIMD2(segment.z, segment.w), angle: b.angle,
                                                     alpha: b.alpha, width: width)
                        if inPlace { attachedCracks[b.group].append(instance) } else { looseCracks[b.group].append(instance) }
                    }
                }
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
                // Sparks cool from white-yellow to dull red.
                let color = mix(SIMD3(1, 0.9, 0.55), SIMD3(1, 0.32, 0.08), min(1, t * 1.4))
                additive.append(PuffInstance(pos: p.pos, size: p.size, alpha: 1 - t, color: SIMD4(color, 1)))
            case .mote:
                guard n < puffCapacity else { break }
                pointer[n] = PuffInstance(pos: p.pos, size: p.size, alpha: 0.6 * (1 - t) * min(1, p.age * 4), color: SIMD4(0.88, 0.82, 0.7, 1))
                n += 1
            }
        }
        let room = max(0, puffCapacity - n)
        for (i, p) in additive.prefix(room).enumerated() { pointer[n + i] = p }
        return (n, min(additive.count, room))
    }

    private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { a + (b - a) * t }
}
