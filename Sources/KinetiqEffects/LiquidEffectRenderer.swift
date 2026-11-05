// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import KinetiqCore
import Metal
import simd

/// Transports material UVs through a connected liquid surface, sampling the
/// original capture only at destination resolution so small text stays sharp.
/// Call serially, on the same command queue as the destination's other writers.
/// The caller clears the BGRA8 destination once; every destination pass loads it.
public final class LiquidEffectRenderer {
    // Float4-only layouts deliberately match Metal's 16-byte alignment.
    private struct Particle {
        var centerRadius: SIMD4<Float>
        var uvExtras: SIMD4<Float>
    }

    private struct Uniforms {
        var screen: SIMD4<Float>
        var window: SIMD4<Float>
        var uvRect: SIMD4<Float>
        // Melt progress, late world opacity, support radius, density threshold.
        var parameters: SIMD4<Float>
        // Inverse density dimensions and size of a density texel in screen points.
        var field: SIMD4<Float>
        // Cropped fluid domain in global CG points, independent of the screen.
        var region: SIMD4<Float>
        // Refraction and reflection strengths; remaining lanes reserved.
        var optics: SIMD4<Float>
    }

    private let device: MTLDevice
    private let sourcePipeline: MTLRenderPipelineState
    private let densityPipeline: MTLRenderPipelineState
    private let surfacePipeline: MTLRenderPipelineState
    // Small LRU, capped at 32 MiB (or one maximum-size field). Submitted command
    // buffers retain evicted textures until completion on this same serial queue.
    private var densityTextures: [MTLTexture] = []
    /// Internal optical isolation for real-capture regression tests, not UI state.
    var opticalStrength = SIMD2<Float>(1, 1)

    /// Compiles all three inline Metal pipelines, surfacing compilation failures.
    public convenience init(device: MTLDevice) throws {
        try self.init(device: device, manualFieldFiltering: !device.supports32BitFloatFiltering)
    }

    /// Older GPUs can reconstruct the same precise UV field with explicit bilinear
    /// reads rather than relying on optional float32 hardware filtering.
    init(device: MTLDevice, manualFieldFiltering: Bool) throws {
        self.device = device
        let source = "#define LIQUID_MANUAL_FIELD_FILTER \(manualFieldFiltering ? 1 : 0)\n" + Self.shaderSource
        let library = try device.makeLibrary(source: source, options: nil)

        func pipeline(vertex: String, fragment: String, density: Bool = false) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = "Liquid \(fragment)"
            descriptor.vertexFunction = library.makeFunction(name: vertex)
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            let color = descriptor.colorAttachments[0]!
            color.pixelFormat = density ? .rgba32Float : .bgra8Unorm
            color.isBlendingEnabled = true
            color.rgbBlendOperation = .add
            color.alphaBlendOperation = .add
            color.sourceRGBBlendFactor = .one
            color.sourceAlphaBlendFactor = .one
            color.destinationRGBBlendFactor = density ? .one : .oneMinusSourceAlpha
            color.destinationAlphaBlendFactor = density ? .one : .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }

        sourcePipeline = try pipeline(vertex: "liquidSourceVertex", fragment: "liquidSourceFragment")
        densityPipeline = try pipeline(vertex: "liquidParticleVertex", fragment: "liquidDensityFragment", density: true)
        surfacePipeline = try pipeline(vertex: "liquidSurfaceVertex", fragment: "liquidSurfaceFragment")
    }

    /// Encodes the intact remainder and released liquid in global Y-down points.
    /// `uvRect` is (offset.x, offset.y, scale.x, scale.y) within the shadow capture.
    /// Allocation/encoder failure skips the frame without clearing the destination.
    public func encode(world: LiquidWorld, texture: MTLTexture, uvRect: SIMD4<Float>,
                       into commandBuffer: MTLCommandBuffer, target: MTLTexture, screenRect: CGRect) {
        guard target.width > 0, target.height > 0, target.pixelFormat == .bgra8Unorm,
              target.sampleCount == 1, texture.width > 0, texture.height > 0,
              Self.valid(screenRect), Self.valid(world.windowFrame),
              uvRect.x.isFinite, uvRect.y.isFinite, uvRect.z.isFinite, uvRect.w.isFinite,
              uvRect.z > 0, uvRect.w > 0, world.alpha > 0,
              world.spacing.isFinite, world.spacing > 0,
              world.elapsed.isFinite, world.meltDuration.isFinite, world.meltDuration > 0 else { return }

        let support = world.spacing * 1.5
        var fluidBounds = CGRect.null
        let particles = world.particles.compactMap { particle -> Particle? in
            guard particle.isReleased, particle.position.x.isFinite, particle.position.y.isFinite,
                  particle.uv.x.isFinite, particle.uv.y.isFinite else { return nil }
            // Cull by support, not by center: droplets straddling a display edge
            // must still contribute to its continuous surface.
            let x = Double(particle.position.x), y = Double(particle.position.y)
            guard x + Double(support) >= Double(screenRect.minX),
                  x - Double(support) <= Double(screenRect.maxX),
                  y + Double(support) >= Double(screenRect.minY),
                  y - Double(support) <= Double(screenRect.maxY) else { return nil }
            fluidBounds = fluidBounds.union(CGRect(x: x - Double(support), y: y - Double(support),
                                      width: Double(support * 2), height: Double(support * 2)))
            return Particle(centerRadius: SIMD4(particle.position.x, particle.position.y, support, 0),
                            uvExtras: SIMD4(particle.uv.x, particle.uv.y, 0, 0))
        }

                // Geometry needs roughly one sample per logical point, not Retina pixel.
                // Crop BOTH the field and the final quad; a floor pool no longer shades a
                // whole display. Float32 moments avoid half-float UV jitter on fine glyphs.
                let region = particles.isEmpty ? screenRect : fluidBounds.insetBy(dx: -1, dy: -1).intersection(screenRect)
                let scale = min(1, 1280 / max(region.width, region.height))
        // Bucket dimensions to avoid allocating a new texture for every falling
        // pixel. Two source windows can reuse their own fields rather than thrash.
        let width = max(32, (Int((region.width * scale).rounded(.up)) + 31) / 32 * 32)
        let height = max(32, (Int((region.height * scale).rounded(.up)) + 31) / 32 * 32)
                var uniforms = Uniforms(
            screen: SIMD4(Float(screenRect.minX), Float(screenRect.minY), Float(screenRect.width), Float(screenRect.height)),
            window: SIMD4(Float(world.windowFrame.minX), Float(world.windowFrame.minY),
                      Float(world.windowFrame.width), Float(world.windowFrame.height)),
            uvRect: uvRect,
            parameters: SIMD4(min(1, max(0, world.elapsed / world.meltDuration)), world.alpha, support, 0.32),
            field: SIMD4(1 / Float(width), 1 / Float(height), Float(region.width) / Float(width), Float(region.height) / Float(height)),
            region: SIMD4(Float(region.minX), Float(region.minY), Float(region.width), Float(region.height)),
            optics: SIMD4(opticalStrength.x, opticalStrength.y, 0, 0))

        // Copy each frame into a new buffer: no CPU writes to in-flight storage.
        var particleBuffer: MTLBuffer?
        var fieldTexture: MTLTexture?
        if !particles.isEmpty {
            particleBuffer = particles.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return nil }
                return device.makeBuffer(bytes: base, length: buffer.count * MemoryLayout<Particle>.stride,
                                         options: .storageModeShared)
            }
            guard particleBuffer != nil else { return }
            guard let field = materialField(width: width, height: height) else { return }
            fieldTexture = field
        }

        func destinationPass() -> MTLRenderPassDescriptor {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .load
            pass.colorAttachments[0].storeAction = .store
            return pass
        }

        if let fieldTexture, let particleBuffer {
            let densityPass = MTLRenderPassDescriptor()
            densityPass.colorAttachments[0].texture = fieldTexture
            densityPass.colorAttachments[0].loadAction = .clear
            densityPass.colorAttachments[0].storeAction = .store
            densityPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: densityPass) else { return }
            encoder.label = "Liquid polynomial density and material transport"
            encoder.setRenderPipelineState(densityPipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.setVertexBuffer(particleBuffer, offset: 0, index: 1)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: particles.count)
            encoder.endEncoding()
        }

        // One destination load/store for the intact image and fluid together.
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: destinationPass()) else { return }
        encoder.label = "Liquid sharp material and water optics"
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        if uniforms.parameters.x < 1 {
            encoder.setRenderPipelineState(sourcePipeline)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        if let fieldTexture {
            encoder.setRenderPipelineState(surfacePipeline)
            encoder.setFragmentTexture(fieldTexture, index: 0)
            encoder.setFragmentTexture(texture, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        encoder.endEncoding()
    }

    private func materialField(width: Int, height: Int) -> MTLTexture? {
        let field: MTLTexture
        if let index = densityTextures.firstIndex(where: { $0.width == width && $0.height == height }) {
            field = densityTextures.remove(at: index)
        } else {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
            descriptor.storageMode = .private
            descriptor.usage = [.renderTarget, .shaderRead]
            guard let allocated = device.makeTexture(descriptor: descriptor) else { return nil }
            field = allocated
            field.label = "Liquid cropped material UV moments and density"
        }
        densityTextures.insert(field, at: 0)
        while densityTextures.count > 1 && (densityTextures.count > 4
            || densityTextures.reduce(0, { $0 + $1.width * $1.height * 16 }) > 32 * 1024 * 1024) {
            densityTextures.removeLast()
        }
        return field
    }

    private static func valid(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && rect.width > 0 && rect.height > 0
            && [rect.minX, rect.minY, rect.maxX, rect.maxY, rect.width, rect.height]
                .allSatisfy { $0.isFinite && abs($0) < 1e12 }
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct LiquidUniforms {
        float4 screen;
        float4 window;
        float4 uvRect;
        float4 parameters;
        float4 field;
        float4 region;
        float4 optics;
    };
    struct LiquidParticle {
        float4 centerRadius;
        float4 uvExtras;
    };
    struct LiquidVertex {
        float4 position [[position]];
        float2 uv;
        float2 local;
        float2 sourceUV [[flat]];
        float radius [[flat]];
    };

    constant float2 liquidCorners[4] = { float2(0, 0), float2(1, 0), float2(0, 1), float2(1, 1) };
    constexpr sampler liquidSampler(coord::normalized, address::clamp_to_edge, filter::linear);

    float4 liquidFieldSample(texture2d<float> field, float2 uv) {
    #if LIQUID_MANUAL_FIELD_FILTER
        float2 size = float2(field.get_width(), field.get_height());
        float2 pixel = uv * size - 0.5;
        int2 origin = int2(floor(pixel));
        int2 limit = int2(size) - 1;
        float2 blend = fract(pixel);
        float4 a = field.read(uint2(clamp(origin, int2(0), limit)));
        float4 b = field.read(uint2(clamp(origin + int2(1, 0), int2(0), limit)));
        float4 c = field.read(uint2(clamp(origin + int2(0, 1), int2(0), limit)));
        float4 d = field.read(uint2(clamp(origin + int2(1, 1), int2(0), limit)));
        return mix(mix(a, b, blend.x), mix(c, d, blend.x), blend.y);
    #else
        return field.sample(liquidSampler, uv);
    #endif
    }

    float4 liquidClip(float2 point, constant LiquidUniforms &u) {
        float2 p = (point - u.screen.xy) / u.screen.zw;
        return float4(p.x * 2 - 1, 1 - p.y * 2, 0, 1);
    }

    vertex LiquidVertex liquidSourceVertex(uint id [[vertex_id]], constant LiquidUniforms &u [[buffer(0)]]) {
        LiquidVertex out = {};
        out.uv = liquidCorners[id];
        out.position = liquidClip(u.window.xy + out.uv * u.window.zw, u);
        return out;
    }

    fragment float4 liquidSourceFragment(LiquidVertex in [[stage_in]],
                                        constant LiquidUniforms &u [[buffer(0)]],
                                        texture2d<float> capture [[texture(0)]]) {
        // Exact LiquidWorld.releaseFraction contract: top-right to bottom-left.
        float releaseFraction = (1 - in.uv.x) * 0.58 + in.uv.y * 0.42;
        float spacing = u.parameters.z / 1.5;
        float frontier = max(fwidth(releaseFraction),
                             0.55 * spacing * (0.58 / u.window.z + 0.42 / u.window.w));
        float intact = u.parameters.x <= 0 ? 1.0 :
            smoothstep(u.parameters.x - frontier, u.parameters.x + frontier, releaseFraction);
        // Captures are already premultiplied; preserve their transparent corners.
        return capture.sample(liquidSampler, u.uvRect.xy + in.uv * u.uvRect.zw)
            * (intact * u.parameters.y);
    }

    vertex LiquidVertex liquidParticleVertex(uint id [[vertex_id]], uint instance [[instance_id]],
                                            constant LiquidUniforms &u [[buffer(0)]],
                                            const device LiquidParticle *particles [[buffer(1)]]) {
        LiquidParticle particle = particles[instance];
        LiquidVertex out = {};
        out.local = liquidCorners[id] * 2 - 1;
        out.radius = particle.centerRadius.z;
        out.sourceUV = particle.uvExtras.xy;
        float2 p = (particle.centerRadius.xy + out.local * out.radius - u.region.xy) / u.region.zw;
        out.position = float4(p.x * 2 - 1, 1 - p.y * 2, 0, 1);
        return out;
    }

    fragment float4 liquidDensityFragment(LiquidVertex in [[stage_in]],
                                         constant LiquidUniforms &u [[buffer(0)]],
                                         texture2d<float> capture [[texture(0)]]) {
        float r2 = dot(in.local, in.local);
        if (r2 >= 1) discard_fragment();
        // Compact C2 polynomial: no per-fragment exponential or extra smoothstep.
        float q = 1 - r2;
        float kernelWeight = q * q * q;
        float2 windowUV = in.sourceUV + in.local * in.radius / u.window.zw;
        float inside = all(windowUV >= 0.0) && all(windowUV <= 1.0) ? 1.0 : 0.0;
        float sourceAlpha = capture.sample(liquidSampler, u.uvRect.xy + saturate(windowUV) * u.uvRect.zw).a * inside;
        float weight = kernelWeight * sourceAlpha;
        // Blend coordinates, NEVER RGB. Text is read once from the original capture
        // by the final fragment, not preblurred in the low-resolution geometry field.
        return float4(windowUV * weight, weight, 0);
    }

    vertex LiquidVertex liquidSurfaceVertex(uint id [[vertex_id]], constant LiquidUniforms &u [[buffer(0)]]) {
        LiquidVertex out = {};
        out.uv = liquidCorners[id];
        out.position = liquidClip(u.region.xy + out.uv * u.region.zw, u);
        return out;
    }

    fragment float4 liquidSurfaceFragment(LiquidVertex in [[stage_in]],
                                         constant LiquidUniforms &u [[buffer(0)]],
                                         texture2d<float> density [[texture(0)]],
                                         texture2d<float> capture [[texture(1)]]) {
        float2 texel = u.field.xy;
        float4 center = liquidFieldSample(density, in.uv);
        float left = liquidFieldSample(density, in.uv - float2(texel.x, 0)).b;
        float right = liquidFieldSample(density, in.uv + float2(texel.x, 0)).b;
        float top = liquidFieldSample(density, in.uv - float2(0, texel.y)).b;
        float bottom = liquidFieldSample(density, in.uv + float2(0, texel.y)).b;
        float2 gradient = float2(right - left, bottom - top) / (2 * u.field.zw);
        float threshold = u.parameters.w;
        // Account for BOTH final-pixel derivatives and the downsampled field's
        // footprint, so boundaries stay soft on Retina and low-resolution targets.
        float aa = max(0.025, max(fwidth(center.b), length(gradient * u.field.zw) * 0.65));
        aa = min(aa, threshold * 0.75);
        float coverage = smoothstep(threshold - aa, threshold + aa, center.b);
        if (coverage <= 0.0001) discard_fragment();

        float2 slope = gradient * u.parameters.z;
        float3 normal = normalize(float3(-slope, 1.25));
        float2 materialUV = center.rg / max(center.b, 0.0001);
        // Snell refraction for water (n=1.333). Displace the ORIGINAL material,
        // not an already blurred color field. Limit the lens to protect glyphs.
        float3 transmitted = refract(float3(0, 0, -1), normal, 0.75019);
        float thickness = min(2.0, u.parameters.z * 0.075) * u.optics.x;
        float2 bend = transmitted.xy * (thickness / max(0.35, -transmitted.z));
        float2 sourceUV = saturate(materialUV + bend / u.window.zw);
        float4 material = capture.sample(liquidSampler, u.uvRect.xy + sourceUV * u.uvRect.zw);
        float3 base = material.rgb / max(material.a, 0.0001);

        // Schlick Fresnel, F0 for an air/water boundary. Multiplications replace
        // generic powers; procedural studio lights need no environment capture.
        float grazing = 1 - saturate(normal.z);
        float grazing2 = grazing * grazing;
        float fresnel = (0.02037 + 0.97963 * grazing2 * grazing2 * grazing) * u.optics.y;
        float3 reflected = reflect(float3(0, 0, -1), normal);
        float sky = saturate(0.5 - reflected.y * 0.5);
        float3 environment = mix(float3(0.025, 0.035, 0.055), float3(0.65, 0.78, 0.90), sky);
        float softbox = (1 - smoothstep(0.08, 0.18, abs(reflected.x + 0.38)))
            * (1 - smoothstep(0.42, 0.65, abs(reflected.y + 0.12)));
        float strip = (1 - smoothstep(0.025, 0.07, abs(reflected.x - 0.48)))
            * (1 - smoothstep(0.30, 0.60, abs(reflected.y - 0.20)));
        float3 reflection = environment * 0.45 + float3(1.0, 0.97, 0.90) * softbox * 2.2
            + float3(0.70, 0.85, 1.0) * strip;
        float3 color = mix(base, reflection, fresnel);
        float alpha = coverage * u.parameters.y;
        return float4(saturate(color) * alpha, alpha);
    }
    """
}