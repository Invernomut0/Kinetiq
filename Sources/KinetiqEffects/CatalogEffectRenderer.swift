// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import KinetiqCore
import Metal
import simd

/// Draws one real capture in global, Y-down screen points into a BGRA8Unorm pass.
/// Captures and output use premultiplied alpha; `uvRect` is (offset.x, offset.y, scale.x, scale.y).
/// The caller owns clearing, viewport, presentation, capture lifetime and restoration.
///
/// Genie, shatter, explode, dissolve, burn and portal close monotonically to transparent.
/// Other styles use a sine envelope and restore the original at both endpoints. Physics
/// styles are visual previews only: this renderer never changes actual window positions.
/// Workspace styles transform only this capture; a multiwindow player must supply each
/// real capture every frame, ordering back-to-front (no depth attachment is required).
public final class CatalogEffectRenderer {
    // Float4-only layout is shared verbatim with Metal, including integer-valued lanes.
    private struct Uniforms {
        var screen: SIMD4<Float>
        var window: SIMD4<Float>
        var uvRect: SIMD4<Float>
        // Progress, amplitude, speed, explicit shader style (not EffectID.rawValue).
        var motion: SIMD4<Float>
        // Mesh subdivisions, fragment columns, fragment rows, blur sampling rings.
        var quality: SIMD4<Float>
        // First and second effect-specific descriptor values, in catalog units.
        var extras: SIMD4<Float>
    }

    /// Actual bounded draw workload, exposed internally for budget regression tests.
    struct Workload: Equatable {
        let subdivisions: Int
        let columns: Int
        let rows: Int
        let blurRings: Int
        let fragmented: Bool
        var instanceCount: Int { fragmented ? columns * rows : 1 }
        var vertexCount: Int { fragmented ? 6 : subdivisions * subdivisions * 6 }
    }

    private let pipeline: MTLRenderPipelineState
    private let device: MTLDevice

    /// Compiles every inline entry point immediately; Metal errors are propagated.
    public init(device: MTLDevice) throws {
        self.device = device
        let options = MTLCompileOptions()
        options.fastMathEnabled = false
        let library = try device.makeLibrary(source: Self.shaderSource, options: options)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Catalog capture mesh and material"
        descriptor.vertexFunction = library.makeFunction(name: "catalogVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "catalogFragment")
        let color = descriptor.colorAttachments[0]!
        color.pixelFormat = .bgra8Unorm
        color.isBlendingEnabled = true
        color.rgbBlendOperation = .add
        color.alphaBlendOperation = .add
        color.sourceRGBBlendFactor = .one
        color.sourceAlphaBlendFactor = .one
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// Encodes without allocating mutable in-flight buffers. Invalid rectangles, UVs,
    /// scalars or incompatible source textures skip the draw without clearing the pass.
    /// `meshLimit` caps subdivisions per axis (1...64); zero skips mesh draws.
    /// `particleLimit` caps actual transported quads (0...4096), not decorative dots.
    /// `blurPasses` means concentric eight-tap sampling rings (0...4), not render passes;
    /// zero performs exactly one sharp capture sample for depth of field.
    /// `speed` changes internal oscillation frequency, never the endpoint contract.
    /// `parameters` accepts the runtime's evaluated preset dictionary. Recognized values
    /// override legacy amplitude/speed arguments; missing custom values use descriptor
    /// defaults, nonfinite dictionary values use defaults, and finite values are clamped
    /// to descriptor bounds. Invalid legacy scalars still skip drawing. Unknown keys
    /// are ignored. Time-dependent materials use a one-second normalized preview clock
    /// (`progress * speed`), not wall time or the runtime's physics integration clock.
    /// Physics and multiwindow parameters affect local surface/material only: `frame`
    /// must already contain the runtime's layout/physics position. No orbit, spacing,
    /// attraction or acceleration translation is applied a second time here.
    public func encode(effect: EffectID, texture: MTLTexture, uvRect: SIMD4<Float>,
                       frame: CGRect, screenRect: CGRect, progress: Float,
                       amplitude: Float = 1, speed: Float = 1, meshLimit: Int = 24,
                       particleLimit: Int = 1500, blurPasses: Int = 2,
                       parameters: [String: Float] = [:],
                       into encoder: MTLRenderCommandEncoder) {
        guard Self.valid(frame), Self.valid(screenRect),
              progress.isFinite, amplitude.isFinite, speed.isFinite,
              uvRect.x.isFinite, uvRect.y.isFinite, uvRect.z.isFinite, uvRect.w.isFinite,
              uvRect.x >= 0, uvRect.y >= 0, uvRect.z > 0, uvRect.w > 0,
              uvRect.x + uvRect.z <= 1.00001, uvRect.y + uvRect.w <= 1.00001,
              texture.device === device, encoder.device === device,
              texture.textureType == .type2D, texture.sampleCount == 1,
              texture.width > 0, texture.height > 0,
              [.bgra8Unorm, .rgba8Unorm, .bgra8Unorm_srgb, .rgba8Unorm_srgb].contains(texture.pixelFormat),
              texture.usage.isEmpty || texture.usage.contains(.shaderRead) else { return }
        let values = Self.resolvedParameters(effect: effect, parameters: parameters,
                             amplitude: amplitude, speed: speed)
        let custom = EffectCatalog.descriptor(effect).parameters.filter { $0.id != "amplitude" && $0.id != "speed" }
        let extras = SIMD4<Float>(custom.first.flatMap { values[$0.id] } ?? 0,
                      custom.dropFirst().first.flatMap { values[$0.id] } ?? 0, 0, 0)
        let work = Self.workload(effect: effect, meshLimit: meshLimit,
                     particleLimit: particleLimit, blurPasses: blurPasses,
                     parameters: values)
        guard work.instanceCount > 0, work.vertexCount > 0 else { return }
        var uniforms = Uniforms(
            // Subtract in CGFloat before narrowing: large/negative display origins must
            // not erase small local positions through Float cancellation.
            screen: SIMD4(0, 0, Float(screenRect.width), Float(screenRect.height)),
            window: SIMD4(Float(frame.minX - screenRect.minX), Float(frame.minY - screenRect.minY),
                          Float(frame.width), Float(frame.height)),
            uvRect: uvRect,
            motion: SIMD4(min(1, max(0, progress)), values["amplitude"]!,
                          values["speed"]!, Float(Self.style(effect))),
            quality: SIMD4(Float(work.subdivisions), Float(work.columns), Float(work.rows), Float(work.blurRings)),
            extras: extras)
        encoder.setRenderPipelineState(pipeline)
        encoder.setCullMode(.none)
        encoder.setTriangleFillMode(.fill)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: work.vertexCount,
                               instanceCount: work.instanceCount)
    }

    /// Shared CPU sanitization also makes defaults/bounds testable without a GPU.
    static func resolvedParameters(effect: EffectID, parameters: [String: Float],
                                   amplitude: Float = 1, speed: Float = 1) -> [String: Float] {
        var result: [String: Float] = [:]
        for spec in EffectCatalog.descriptor(effect).parameters {
            let fallback = Float(spec.defaultValue)
            let legacy: Float
            switch spec.id {
            case "amplitude": legacy = amplitude
            case "speed": legacy = speed
            default: legacy = fallback
            }
            let value = parameters[spec.id] ?? legacy
            result[spec.id] = value.isFinite
                ? min(Float(spec.maximum), max(Float(spec.minimum), value)) : fallback
        }
        return result
    }

    static func workload(effect: EffectID, meshLimit: Int, particleLimit: Int, blurPasses: Int,
                         parameters: [String: Float] = [:]) -> Workload {
        let fragmented = effect == .shatter || effect == .explode
        let values = resolvedParameters(effect: effect, parameters: parameters)
        let requested = Int(values["fragments"] ?? 4096)
        let budget = min(requested, min(4096, max(0, particleLimit)))
        let columns = budget > 0 ? max(1, Int(Double(budget).squareRoot())) : 0
        let rows = columns > 0 ? budget / columns : 0
        return Workload(subdivisions: min(64, max(0, meshLimit)), columns: columns, rows: rows,
                        blurRings: effect == .depthOfField && values["blur"] == 0 ? 0 : min(4, max(0, blurPasses)),
                        fragmented: fragmented)
    }

    private static func valid(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && rect.width >= 0.001 && rect.height >= 0.001
            && [rect.minX, rect.minY, rect.maxX, rect.maxY, rect.width, rect.height]
                .allSatisfy { $0.isFinite && abs($0) < 1e9 }
    }

    // Explicit mapping isolates the shader ABI from catalog declaration order/raw values.
    private static func style(_ effect: EffectID) -> Int {
        switch effect {
        case .wobbly: return 0
        case .genie: return 1
        case .morph: return 2
        case .fold: return 3
        case .flip: return 4
        case .magnet: return 5
        case .float: return 6
        case .shatter: return 7
        case .explode: return 8
        case .dissolve: return 9
        case .burn: return 10
        case .portal: return 11
        case .depthOfField: return 12
        case .ripple: return 13
        case .liquidMorph: return 14
        case .workspaceCube: return 15
        case .orbit: return 16
        case .gravity: return 17
        case .expose3D: return 18
        }
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct CatalogUniforms {
        float4 screen;
        float4 window;
        float4 uvRect;
        float4 motion;
        float4 quality;
        float4 extras;
    };
    struct CatalogVertex {
        float4 position [[position]];
        float2 uv;
        float3 surface;
    };
    constant float PI = 3.14159265358979323846;
    // extras.xy follows each descriptor's custom key order (no enum/raw-ID ABI).
    // Angles: degrees -> radians. Points: global Y-down screen points, not texels.
    // Fractions use the named window/viewport edge, including portrait captures.
    // Clock: progress * speed seconds of a one-second preview; endpoints stay exact.
    // 0 stiffness/friction: membrane frequency and exponential damping (unitless).
    // 1 curvature: funnel exponent; 2 roundness: radius / window short edge.
    // 3/4 angle: fold's total hinge angle (half per panel), flip's yaw in degrees.
    // 5 radius/strength: local magnetic bulge footprint in points and magnitude.
    // 6 distance/frequency: travel / window height and cycles / second.
    // 7/8 fragments/spread: CPU quad count and velocity / window width / preview s.
    // 9 scale/softness: noise cells / short edge and normalized threshold width.
    // 10 edgeWidth: burn field width / window height (field's vertical gradient .72).
    // 11 radius/twist: portal radius / short edge and swirl degrees.
    // 12 focus/blur: focal depth [0,1] along local Y and maximum disk radius in points.
    // 13 wavelength/decay: radial wave period in points and exponential lifetime in s.
    // 14 viscosity/refraction: normalized temporal drag and UV displacement multiplier.
    // 15 angle/perspective: face yaw degrees and projective depth strength [0,1].
    // 16 radius/angle: viewport-short-edge fraction for local depth, yaw phase degrees.
    // 17 acceleration/restitution: points/s^2 for local sag, rebound coefficient.
    // 18 angle/spacing: pitch degrees and local depth separation / window width.
    // 5,15,16,17,18 never translate centers: runtime owns forces and multiwindow layout.
    constant float2 corners[6] = {
        float2(0,0), float2(1,0), float2(0,1),
        float2(1,0), float2(1,1), float2(0,1)
    };
    constexpr sampler captureSampler(coord::normalized, address::clamp_to_edge, filter::linear);

    float hash21(float2 p) {
        float3 q = fract(float3(p.x, p.y, p.x) * float3(0.1031, 0.1030, 0.0973));
        q += dot(q, q.yzx + 33.33);
        return fract((q.x + q.y) * q.z);
    }
    float noise21(float2 p) {
        float2 i = floor(p), f = fract(p);
        f = f * f * (3 - 2 * f);
        return mix(mix(hash21(i), hash21(i + float2(1,0)), f.x),
                   mix(hash21(i + float2(0,1)), hash21(i + 1), f.x), f.y);
    }
    float envelope(float t) { return t <= 0 || t >= 1 ? 0.0 : sin(PI * t); }
    float3 yaw(float3 p, float angle) {
        float c = cos(angle), s = sin(angle);
        return float3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);
    }
    float3 pitch(float3 p, float angle) {
        float c = cos(angle), s = sin(angle);
        return float3(p.x, c * p.y - s * p.z, s * p.y + c * p.z);
    }

    vertex CatalogVertex catalogVertex(uint id [[vertex_id]], uint instance [[instance_id]],
                                       constant CatalogUniforms &u [[buffer(0)]]) {
        int style = int(u.motion.w);
        float t = u.motion.x, a = u.motion.y, e = envelope(t) * a;
        float seconds = t * u.motion.z;
        float phase = seconds * 2 * PI;
        float x = u.extras.x, y = u.extras.y;
        bool fragmented = style == 7 || style == 8;
        uint n = uint(max(1.0, u.quality.x));
        uint cell = id / 6;
        float2 uv = (float2(cell % n, cell / n) + corners[id % 6]) / float(n);
        if (fragmented) {
            uint columns = uint(u.quality.y);
            uv = (float2(instance % columns, instance / columns) + corners[id % 6]) / u.quality.yz;
        }
        float2 size = u.window.zw;
        float3 p = float3((uv - 0.5) * size, 0);
        float2 translation = float2(0);

        if (fragmented) {
            uint columns = uint(u.quality.y);
            float2 cellID = float2(instance % columns, instance / columns);
            float2 centerUV = (cellID + 0.5) / u.quality.yz;
            float2 center = (centerUV - 0.5) * size;
            float seed = hash21(cellID + 13.7);
            float spin = (seed - 0.5) * t * a * 7;
            float2 local = (uv - centerUV) * size * (1 - 0.22 * t);
            p = yaw(pitch(float3(local, 0), spin * 0.7), spin);
            float2 velocity;
            if (style == 7) {
                // Gravity-driven, independently tumbling glass tiles; no point sprites.
                velocity = float2((seed - 0.5) * size.x * y,
                                  size.y * (0.25 + 1.4 * t));
            } else {
                float2 direction = normalize(centerUV - 0.5 + float2(0.001, 0.002));
                velocity = direction * size.x * y * (0.55 + seed * 0.9);
            }
            p.xy += center + velocity * t * a;
            p.z += sin(seed * 27) * min(size.x, size.y) * 0.3 * t * a;
        } else if (style == 0) {
            // Anchored, damped membrane: material UV stays attached to every vertex.
            float springPhase = phase * sqrt(x / 3.8);
            float damping = exp(-y * seconds * 0.15);
            p.x += sin(uv.y * 8 + springPhase) * size.x * 0.055 * e * uv.y * damping;
            p.y += sin(uv.x * 7 - springPhase * 1.3) * size.y * 0.045 * e * damping;
            p.z = sin(uv.x * PI) * sin(uv.y * PI) * size.y * 0.10 * e * damping;
        } else if (style == 1) {
            // Funnel into the bottom-center of this display, not the window's bottom.
            float pull = t * t * (3 - 2 * t);
            float neck = pow(t, 0.7 + (1 - uv.y) * x * 4.166667);
            float2 target = float2(u.screen.x + u.screen.z * 0.5,
                                   u.screen.y + u.screen.w - 2);
            float2 point = u.window.xy + uv * size;
            point.x = mix(point.x, target.x, neck * 0.98);
            point.y = mix(point.y, target.y, pull);
            p.xy = point - (u.window.xy + size * 0.5);
        } else if (style == 2) {
            // A rounded, breathing lens, distinct from wave and liquid transport.
            p.xy *= float2(1 - 0.26 * e, 1 + 0.18 * e);
            p.x += sin(uv.y * PI) * size.x * 0.09 * e;
            p.z = sin(uv.x * PI) * sin(uv.y * PI) * min(size.x, size.y) * 0.38 * e;
        } else if (style == 3) {
            // Four physical accordion panels: piecewise planar Z with true creases.
            float angle = x * PI / 360 * e;
            float ridge = 1 - abs(fract(uv.x * 2) * 2 - 1);
            p.x *= cos(angle);
            p.z = ridge * size.x * 0.25 * sin(angle);
            p = pitch(p, -0.13 * sin(angle));
        } else if (style == 4) {
            p = pitch(yaw(p, x * PI / 180 * e), 0.22 * e * abs(x) / 180);
        } else if (style == 5) {
            // Only a preview of attraction; CPU/runtime owns real magnetic forces.
            float footprint = exp(-dot(p.xy, p.xy) / max(x * x, 1.0));
            p.z = -min(size.x, size.y) * 0.12 * e * y * footprint;
            p = yaw(p, -0.10 * e * y * x / 600);
        } else if (style == 6) {
            float floatPhase = phase * y;
            translation = float2(sin(floatPhase) * size.y * x * 0.35,
                                  -cos(floatPhase) * size.y * x) * e;
            p = pitch(yaw(p, sin(floatPhase) * 0.18 * e * x / 0.25), 0.12 * e * x / 0.25);
        } else if (style == 11) {
            p.xy *= max(0.12, 1 - 0.8 * t);
        } else if (style == 13) {
            float r = length((uv - 0.5) * size);
            p.z = sin(r * 2 * PI / x - phase * 2) * exp(-seconds / y)
                * exp(-r / min(size.x, size.y) * 2) * min(size.x, size.y) * 0.065 * e;
        } else if (style == 14) {
            // Connected incompressible-looking shear, not a simulated particle world.
            float dragPhase = phase / (1 + x * 4);
            float flow = 1 - x * 0.65;
            p.x += sin(uv.y * 9 + dragPhase) * size.x * 0.07 * e * flow;
            p.y += sin(uv.x * 8 - dragPhase) * size.y * 0.055 * e * flow;
            p.z = cos(uv.x * 8 + uv.y * 6 + dragPhase) * min(size.x, size.y) * 0.08 * e * flow;
        } else if (style == 15) {
            // One face only. The caller supplies and sorts the other real windows.
            p = yaw(p, x * PI / 180 * e);
            p.z *= y;
        } else if (style == 16) {
            float orbitPhase = phase + y * PI / 180;
            p = yaw(p, sin(orbitPhase) * 0.7 * e);
            p.xy *= 1 - 0.18 * e;
            p.z += (1 + sin(orbitPhase)) * min(u.screen.z, u.screen.w) * x * 0.25 * e;
        } else if (style == 17) {
            float sag = min(size.y * 0.20, x * seconds * seconds * 0.025);
            p.z = sin(uv.x * PI) * sin(uv.y * PI) * sag * e
                * (1 + y * sin(phase * 2));
            p = pitch(p, x / 3000 * 0.35 * e * (1 - y * 0.5));
        } else if (style == 18) {
            p.xy *= 1 - min(0.65, e * 0.38);
            p = pitch(yaw(p, -0.3 * e), x * PI / 180 * e);
            p.z += size.x * y * e;
        }

        // Homogeneous perspective keeps UV interpolation perspective-correct. Positive
        // Z goes away from the viewer; bounded W prevents camera-plane singularities.
        float distance = max(max(size.x, size.y) * 2.5, 800.0);
        p.z = clamp(p.z, -distance * 0.45, distance * 0.7);
        float w = 1 + p.z / distance;
        float2 pivot = u.window.xy + size * 0.5 + translation;
        float2 centerClip = (pivot - u.screen.xy) / u.screen.zw * 2 - 1;
        CatalogVertex out;
        out.position = float4(centerClip.x * w + 2 * p.x / u.screen.z,
                              -centerClip.y * w - 2 * p.y / u.screen.w,
                              0.5 * w, w);
        out.uv = uv;
        out.surface = p;
        return out;
    }

    float4 captureColor(texture2d<float> image, float2 uv, constant CatalogUniforms &u) {
        // Do not sample outside the caller's crop, including during refraction/blur.
        float2 halfTexel = 0.5 / float2(image.get_width(), image.get_height());
        float2 lo = u.uvRect.xy + min(halfTexel, u.uvRect.zw * 0.5);
        float2 hi = u.uvRect.xy + u.uvRect.zw - min(halfTexel, u.uvRect.zw * 0.5);
        return image.sample(captureSampler, clamp(u.uvRect.xy + uv * u.uvRect.zw, lo, hi));
    }

    fragment float4 catalogFragment(CatalogVertex in [[stage_in]],
                                     constant CatalogUniforms &u [[buffer(0)]],
                                     texture2d<float> image [[texture(0)]]) {
        int style = int(u.motion.w);
        float t = u.motion.x, a = u.motion.y, e = envelope(t) * a;
        float seconds = t * u.motion.z;
        float phase = seconds * 2 * PI;
        float x = u.extras.x, y = u.extras.y;
        float2 uv = in.uv;
        bool closing = style == 1 || style == 7 || style == 8 || style == 9 || style == 10 || style == 11;
        if (closing && t >= 1) return float4(0);
        // Exact endpoint identity, including lighting, masks and refraction.
        if (t <= 0 || (!closing && t >= 1)) return captureColor(image, uv, u);

        if (style == 13) {
            float2 delta = (uv - 0.5) * u.window.zw;
            float r = length(delta);
            uv += delta / max(r, 0.02) * cos(r * 2 * PI / x - phase * 2)
                * exp(-seconds / y) * exp(-r / min(u.window.z, u.window.w) * 2) * 0.016 * e;
        } else if (style == 14) {
            float dragPhase = phase / (1 + x * 4);
            uv += float2(cos(uv.y * 9 + dragPhase), sin(uv.x * 8 - dragPhase)) * 0.0175 * e * y;
        } else if (style == 11) {
            float2 aspect = u.window.zw / min(u.window.z, u.window.w);
            float2 d = (uv - 0.5) * aspect;
            float r = length(d), angle = t * a * y * PI / 180 * max(0.0, 1 - r / x);
            float c = cos(angle), s = sin(angle);
            uv = float2(c * d.x - s * d.y, s * d.x + c * d.y) / aspect + 0.5;
        }
        float4 color = captureColor(image, uv, u);

        if (style == 12 && u.quality.w > 0 && e > 0) {
            // Real variable-radius disk integration. Each quality ring costs 8 samples;
            // no offscreen render pass or unbounded loop is hidden behind blurPasses.
            float radius = y * e * min(1.0, abs(in.uv.y - x) * 2);
            float weight = 1;
            for (int ring = 1; ring <= int(u.quality.w); ++ring) {
                float r = radius * float(ring) / u.quality.w;
                float ringWeight = exp(-2 * float(ring * ring) / (u.quality.w * u.quality.w));
                for (int tap = 0; tap < 8; ++tap) {
                    float angle = (float(tap) + float(ring % 2) * 0.5) * PI / 4;
                    float2 offset = float2(cos(angle), sin(angle)) * r / u.window.zw;
                    color += captureColor(image, uv + offset, u) * ringWeight;
                    weight += ringWeight;
                }
            }
            color /= weight;
        }

        float coverage = 1;
        float3 emission = float3(0);
        if (style == 1) {
            coverage = 1 - smoothstep(0.78, 1.0, t);
        } else if (style == 7 || style == 8) {
            coverage = 1 - smoothstep(0.55, 1.0, t);
        } else if (style == 9) {
            float2 cells = u.window.zw / min(u.window.z, u.window.w) * x;
            float threshold = hash21(floor(in.uv * cells));
            float softness = max(0.0001, y * 0.5);
            coverage = smoothstep(t - softness, t + softness, threshold);
            coverage *= 1 - smoothstep(0.97, 1.0, t);
        } else if (style == 10) {
            // Coherent advancing combustion front, with multiscale turbulence and a
            // moving hot/charred edge. Emission is composited in premultiplied LDR.
            float field = (1 - in.uv.y) * 0.72
                + noise21(in.uv * float2(12, 18)) * 0.20
                + noise21(in.uv * 47) * 0.08;
            float distance = field - t;
            float aa = max(fwidth(field), 0.006);
            coverage = smoothstep(-aa, aa, distance);
            float edge = exp(-abs(distance) / max(x * 0.72, 0.0001)) * envelope(t);
            float caustic = 0.5 + 0.5 * sin(in.uv.x * 85 + phase * 3
                                           + sin(in.uv.y * 39 - phase) * 3);
            color.rgb *= 1 - exp(-max(distance, 0.0) * 24) * 0.85;
            emission = mix(float3(1, 0.12, 0.005), float3(1, 0.92, 0.25), caustic) * edge * 2;
            coverage = max(coverage, edge * 0.85);
            coverage *= 1 - smoothstep(0.97, 1.0, t);
        } else if (style == 11) {
            float2 aspect = u.window.zw / min(u.window.z, u.window.w);
            float r = length((in.uv - 0.5) * aspect);
            float radius = x * (1 - t);
            float aa = max(fwidth(r), 0.004);
            coverage = 1 - smoothstep(radius - aa, radius + aa, r);
            float rim = exp(-abs(r - radius) * 95) * envelope(t);
            emission = float3(0.20, 0.48, 1) * rim;
        } else if (style == 2) {
            float shortEdge = min(u.window.z, u.window.w);
            float radius = x * shortEdge * min(e, 1.0);
            float2 q = abs((in.uv - 0.5) * u.window.zw) - (u.window.zw * 0.5 - radius);
            float sd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
            float aa = max(fwidth(sd), 0.01);
            coverage = 1 - smoothstep(-aa, aa, sd);
        }

        bool lit = style == 3 || style == 4 || style == 7 || style == 8
            || style == 13 || style == 14 || style == 15 || style == 16 || style == 18;
        if (lit) {
            float3 normal = cross(dfdx(in.surface), dfdy(in.surface));
            normal /= max(length(normal), 0.00001);
            if (normal.z < 0) normal = -normal;
            float diffuse = abs(dot(normal, normalize(float3(-0.35, -0.45, 1))));
            float lighting = 0.35 + 0.65 * diffuse;
            color.rgb *= mix(1.0, lighting, min(1.0, closing ? t * 4 : e));
        }
        float alpha = saturate(color.a * coverage);
        float3 rgb = color.rgb * coverage + emission * alpha;
        // Captures are premultiplied already. Clamp also protects malformed source
        // RGB in transparent pixels and guarantees valid native BGRA8 composition.
        return float4(clamp(rgb, float3(0), float3(alpha)), alpha);
    }
    """
}