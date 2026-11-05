// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import KinetiqCore
import Metal
import simd

/// Renders a captured window as a connected, texture-colored liquid surface.
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
    }

    private let device: MTLDevice
    private let sourcePipeline: MTLRenderPipelineState
    private let densityPipeline: MTLRenderPipelineState
    private let surfacePipeline: MTLRenderPipelineState
    // Only the most recent size is retained. Encoded command buffers retain older
    // textures until completion, including when a display changes resolution.
    private var densityTexture: MTLTexture?

    /// Compiles all three inline Metal pipelines, surfacing compilation failures.
    public init(device: MTLDevice) throws {
        self.device = device
        let library = try device.makeLibrary(source: Self.shaderSource, options: nil)

        func pipeline(vertex: String, fragment: String, density: Bool = false) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = "Liquid \(fragment)"
            descriptor.vertexFunction = library.makeFunction(name: vertex)
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            let color = descriptor.colorAttachments[0]!
            color.pixelFormat = density ? .rgba16Float : .bgra8Unorm
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

        let scale = min(1, 1280 / Double(max(target.width, target.height)))
        let width = max(1, Int((Double(target.width) * scale).rounded(.down)))
        let height = max(1, Int((Double(target.height) * scale).rounded(.down)))
        let support = world.spacing * 1.5
        var uniforms = Uniforms(
            screen: SIMD4(Float(screenRect.minX), Float(screenRect.minY), Float(screenRect.width), Float(screenRect.height)),
            window: SIMD4(Float(world.windowFrame.minX), Float(world.windowFrame.minY),
                          Float(world.windowFrame.width), Float(world.windowFrame.height)),
            uvRect: uvRect,
            parameters: SIMD4(min(1, max(0, world.elapsed / world.meltDuration)), world.alpha, support, 0.32),
            field: SIMD4(1 / Float(width), 1 / Float(height),
                         Float(screenRect.width) / Float(width), Float(screenRect.height) / Float(height)))

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
            return Particle(centerRadius: SIMD4(particle.position.x, particle.position.y, support, 0),
                            uvExtras: SIMD4(particle.uv.x, particle.uv.y, 0, 0))
        }

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
            if densityTexture?.width != width || densityTexture?.height != height {
                // Release the cached size even if the replacement allocation fails.
                densityTexture = nil
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
                descriptor.storageMode = .private
                descriptor.usage = [.renderTarget, .shaderRead]
                densityTexture = device.makeTexture(descriptor: descriptor)
                densityTexture?.label = "Liquid additive color and density"
            }
            guard let densityTexture else { return }
            fieldTexture = densityTexture
        }

        func destinationPass() -> MTLRenderPassDescriptor {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .load
            pass.colorAttachments[0].storeAction = .store
            return pass
        }

        if uniforms.parameters.x < 1 {
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: destinationPass()) else { return }
            encoder.label = "Liquid intact window"
            encoder.setRenderPipelineState(sourcePipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
        }

        guard let fieldTexture, let particleBuffer else { return }
        let densityPass = MTLRenderPassDescriptor()
        densityPass.colorAttachments[0].texture = fieldTexture
        densityPass.colorAttachments[0].loadAction = .clear
        densityPass.colorAttachments[0].storeAction = .store
        densityPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        guard let densityEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: densityPass) else { return }
        densityEncoder.label = "Liquid Gaussian density"
        densityEncoder.setRenderPipelineState(densityPipeline)
        densityEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        densityEncoder.setVertexBuffer(particleBuffer, offset: 0, index: 1)
        densityEncoder.setFragmentTexture(texture, index: 0)
        densityEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        densityEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: particles.count)
        densityEncoder.endEncoding()

        guard let surfaceEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: destinationPass()) else { return }
        surfaceEncoder.label = "Liquid connected glossy surface"
        surfaceEncoder.setRenderPipelineState(surfacePipeline)
        surfaceEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        surfaceEncoder.setFragmentTexture(fieldTexture, index: 0)
        surfaceEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        surfaceEncoder.endEncoding()
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
        out.position = liquidClip(particle.centerRadius.xy + out.local * out.radius, u);
        return out;
    }

    fragment float4 liquidDensityFragment(LiquidVertex in [[stage_in]],
                                         constant LiquidUniforms &u [[buffer(0)]],
                                         texture2d<float> capture [[texture(0)]]) {
        float r2 = dot(in.local, in.local);
        if (r2 >= 1) discard_fragment();
        // A truncated Gaussian with zero value AND slope at its support edge.
        // At 1.5 spacings, neighboring kernels overlap into sheets and pools.
        float edge = exp(-3.0);
        float gaussian = (exp(-3 * r2) - edge) / (1 - edge);
        float kernelWeight = gaussian * (1 - smoothstep(0.72, 1.0, r2));
        // Transport a small textured patch, not a flat confetti-colored disc.
        float2 windowUV = in.sourceUV + in.local * in.radius / u.window.zw;
        float inside = all(windowUV >= 0.0) && all(windowUV <= 1.0) ? 1.0 : 0.0;
        float4 sample = capture.sample(liquidSampler, u.uvRect.xy + saturate(windowUV) * u.uvRect.zw);
        float sourceAlpha = sample.a * inside;
        float weight = kernelWeight * sourceAlpha;
        // Unpremultiply before density weighting; alpha must not darken corners twice.
        float3 color = sample.rgb / max(sample.a, 0.0001);
        return float4(color * weight, weight);
    }

    vertex LiquidVertex liquidSurfaceVertex(uint id [[vertex_id]]) {
        LiquidVertex out = {};
        out.uv = liquidCorners[id];
        out.position = float4(out.uv.x * 2 - 1, 1 - out.uv.y * 2, 0, 1);
        return out;
    }

    fragment float4 liquidSurfaceFragment(LiquidVertex in [[stage_in]],
                                         constant LiquidUniforms &u [[buffer(0)]],
                                         texture2d<float> density [[texture(0)]]) {
        float2 texel = u.field.xy;
        float4 center = density.sample(liquidSampler, in.uv);
        float left = density.sample(liquidSampler, in.uv - float2(texel.x, 0)).a;
        float right = density.sample(liquidSampler, in.uv + float2(texel.x, 0)).a;
        float top = density.sample(liquidSampler, in.uv - float2(0, texel.y)).a;
        float bottom = density.sample(liquidSampler, in.uv + float2(0, texel.y)).a;
        float2 gradient = float2(right - left, bottom - top) / (2 * u.field.zw);
        float threshold = u.parameters.w;
        // Account for BOTH final-pixel derivatives and the downsampled field's
        // footprint, so boundaries stay soft on Retina and low-resolution targets.
        float aa = max(0.025, max(fwidth(center.a), length(gradient * u.field.zw) * 0.65));
        aa = min(aa, threshold * 0.75);
        float coverage = smoothstep(threshold - aa, threshold + aa, center.a);
        if (coverage <= 0.0001) discard_fragment();

        float2 slope = gradient * u.parameters.z;
        float3 normal = normalize(float3(-slope, 1.25));
        float3 light = normalize(float3(-0.45, -0.65, 1.0));
        float3 halfway = normalize(light + float3(0, 0, 1));
        float specular = pow(saturate(dot(normal, halfway)), 52.0);
        float rim = pow(1 - normal.z, 3.0);
        float edgeLight = 1 - smoothstep(threshold, threshold + 1.2, center.a);

        float3 base = center.rgb / max(center.a, 0.0001);
        // A small normal-driven displacement of the transported COLOR field
        // resembles refraction without warping density or breaking connectivity.
        float2 bend = normal.xy * min(u.parameters.z * 0.10, 4.0) / u.screen.zw;
        float4 refracted = density.sample(liquidSampler, clamp(in.uv + bend, texel * 0.5, 1 - texel * 0.5));
        if (refracted.a > threshold * 0.6) {
            base = mix(base, refracted.rgb / refracted.a, 0.23);
        }
        float diffuse = dot(normal, light);
        float3 color = base * (0.94 + 0.06 * diffuse)
            + float3(0.90, 0.96, 1.0) * (0.22 * specular + 0.10 * rim) * edgeLight;
        float alpha = coverage * u.parameters.y;
        return float4(saturate(color) * alpha, alpha);
    }
    """
}