// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO
import KinetiqCore
import Metal
import XCTest
@testable import KinetiqEffects

/// Real GPU integration tests. Input is the shipped brush PNG (not a generated
/// window or a procedural test texture), decoded into a premultiplied capture.
/// Only an unavailable Metal device skips tests; shader or command errors fail.
final class CatalogEffectTests: XCTestCase {
    private var device: MTLDevice!
    private var queue: MTLCommandQueue!
    private var renderer: CatalogEffectRenderer!
    private var capture: MTLTexture!
    private let width = 256
    private let height = 192
    private let screen = CGRect(x: -80, y: 40, width: 256, height: 192)
    private let window = CGRect(x: -48, y: 68, width: 144, height: 104)
    private let whole = SIMD4<Float>(0, 0, 1, 1)
    private let closing: Set<EffectID> = [.genie, .shatter, .explode, .dissolve, .burn, .portal]

    override func setUpWithError() throws {
        guard let available = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable on this host")
        }
        device = available
        queue = try XCTUnwrap(device.makeCommandQueue())
        // This compiles both inline entry points and the real native BGRA pipeline.
        renderer = try CatalogEffectRenderer(device: device)
        capture = try shippedCapture("brush")
    }

    /// Uploads an existing project asset once; subsequent commands only sample it.
    /// Unlike EffectTextureLoader's data-channel decoder this applies premultiplication,
    /// because the catalog consumes window/color captures rather than packed shader data.
    private func shippedCapture(_ name: String) throws -> MTLTexture {
        let url = try EffectResources.url(name, extension: "png", directory: "Textures")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { storage in
            let context = try XCTUnwrap(CGContext(
                data: storage.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        XCTAssertGreaterThan(Set(bytes).count, 32, "The shipped asset must contain real image detail")
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: image.width, height: image.height, mipmapped: false)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        texture.label = "Immutable shipped \(name).png capture"
        texture.replace(region: MTLRegionMake2D(0, 0, image.width, image.height), mipmapLevel: 0,
                        withBytes: bytes, bytesPerRow: image.width * 4)
        return texture
    }

    /// A private BGRA target plus explicit GPU-to-shared-buffer copy exercises the
    /// real render path without depending on managed texture synchronization rules.
    private func render(_ effect: EffectID, _ progress: Float, amplitude: Float = 1,
                        speed: Float = 1, mesh: Int = 24, particles: Int = 1500,
                        blur: Int = 2, uv: SIMD4<Float>? = nil, frame: CGRect? = nil,
                        screenRect: CGRect? = nil, source: MTLTexture? = nil,
                        parameters: [String: Float] = [:]) throws -> [UInt8] {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.storageMode = .private
        descriptor.usage = .renderTarget
        let target = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        let command = try XCTUnwrap(queue.makeCommandBuffer())
        command.label = "Catalog regression \(effect.rawValue) at \(progress)"
        let encoder = try XCTUnwrap(command.makeRenderCommandEncoder(descriptor: pass))
        renderer.encode(effect: effect, texture: source ?? capture, uvRect: uv ?? whole,
                        frame: frame ?? window, screenRect: screenRect ?? screen,
                        progress: progress, amplitude: amplitude, speed: speed, meshLimit: mesh,
                        particleLimit: particles, blurPasses: blur, parameters: parameters, into: encoder)
        encoder.endEncoding()
        let readback = try XCTUnwrap(device.makeBuffer(length: width * height * 4, options: .storageModeShared))
        let blit = try XCTUnwrap(command.makeBlitCommandEncoder())
        blit.copy(from: target, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: readback, destinationOffset: 0, destinationBytesPerRow: width * 4,
                  destinationBytesPerImage: width * height * 4)
        blit.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error { throw error }
        XCTAssertEqual(command.status, .completed, command.label ?? "GPU command")
        guard command.status == .completed else {
            throw EffectError.compilation("Catalog GPU command did not complete")
        }
        return Array(UnsafeBufferPointer(start: readback.contents().assumingMemoryBound(to: UInt8.self),
                                        count: width * height * 4))
    }

    private func alphaSum(_ pixels: [UInt8]) -> Int {
        stride(from: 3, to: pixels.count, by: 4).reduce(0) { $0 + Int(pixels[$1]) }
    }

    private func meanDifference(_ first: [UInt8], _ second: [UInt8]) -> Double {
        zip(first, second).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(first.count)
    }

    private func assertPremultiplied(_ pixels: [UInt8], _ message: String,
                                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(pixels.count, width * height * 4, file: file, line: line)
        let invalid = stride(from: 0, to: pixels.count, by: 4).first { offset in
            let alpha = pixels[offset + 3]
            return pixels[offset] > alpha || pixels[offset + 1] > alpha || pixels[offset + 2] > alpha
                || !(Float(alpha) / 255).isFinite
        }
        XCTAssertNil(invalid, "Non-premultiplied or invalid BGRA output: \(message)", file: file, line: line)
    }

    func testEveryStyleAnimatesTheRealAssetWithValidPremultipliedOutput() throws {
        XCTAssertEqual(EffectID.allCases.count, 19)
        let original = try render(.wobbly, 0)
        var middleFrames: [[UInt8]] = []
        let before = sourceBytes()
        for effect in EffectID.allCases {
            let middle = try render(effect, 0.37)
            let later = try render(effect, 0.71)
            assertPremultiplied(middle, effect.rawValue)
            assertPremultiplied(later, effect.rawValue)
            XCTAssertGreaterThan(alphaSum(middle), 1000, "\(effect) drew no capture")
            XCTAssertGreaterThan(meanDifference(original, middle), 0.05, "\(effect) is static")
            XCTAssertGreaterThan(meanDifference(middle, later), 0.01, "\(effect) does not evolve")
            XCTAssertFalse(middleFrames.contains(middle), "\(effect) aliases another style")
            middleFrames.append(middle)
        }
        XCTAssertTrue(before == sourceBytes(), "Rendering must never mutate its source asset")
    }

    private func sourceBytes() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: capture.width * capture.height * 4)
        capture.getBytes(&bytes, bytesPerRow: capture.width * 4,
                         from: MTLRegionMake2D(0, 0, capture.width, capture.height), mipmapLevel: 0)
        return bytes
    }

    func testEndpointContractForEveryStyle() throws {
        let original = try render(.wobbly, 0)
        for effect in EffectID.allCases {
            let start = try render(effect, 0)
            XCTAssertLessThan(meanDifference(original, start), 0.12, "\(effect) changes the start capture")
            let end = try render(effect, 1)
            if closing.contains(effect) {
                XCTAssertEqual(alphaSum(end), 0, "\(effect) must close completely")
            } else {
                XCTAssertLessThan(meanDifference(original, end), 0.12, "\(effect) must restore the capture")
            }
            let late = try render(effect, 0.94)
            assertPremultiplied(late, "\(effect) late frame")
        }
    }

    func testEveryStyleActuallySamplesTheSuppliedCapture() throws {
        let otherAsset = try shippedCapture("matrixFont")
        for effect in EffectID.allCases {
            let brush = try render(effect, 0.33)
            let font = try render(effect, 0.33, source: otherAsset)
            XCTAssertGreaterThan(meanDifference(brush, font), 0.05,
                                 "\(effect) substituted procedural output for capture transport")
        }
    }

    func testQualityExtremesRenderEveryStyleWithoutPlaceholderFallbacks() throws {
        for effect in EffectID.allCases {
            let minimal = try render(effect, 0.41, mesh: 1, particles: 1, blur: 0)
            let maximal = try render(effect, 0.41, mesh: .max, particles: .max, blur: .max)
            assertPremultiplied(minimal, "\(effect) minimum budget")
            assertPremultiplied(maximal, "\(effect) capped maximum budget")
            XCTAssertGreaterThan(alphaSum(minimal), 0, "\(effect) discarded the low-budget capture")
            XCTAssertGreaterThan(alphaSum(maximal), 0, "\(effect) discarded the capped capture")
        }
    }

    func testFragmentBudgetChangesTransportAndZeroDisablesOnlyFragmentation() throws {
        for effect in [EffectID.shatter, .explode] {
            let single = try render(effect, 0.43, particles: 1)
            let many = try render(effect, 0.43, particles: 127)
            XCTAssertGreaterThan(meanDifference(single, many), 0.1, "\(effect) ignores fragment count")
            XCTAssertEqual(alphaSum(try render(effect, 0.43, particles: 0)), 0)
            XCTAssertEqual(alphaSum(try render(effect, 0.43, particles: .min)), 0)
            XCTAssertGreaterThan(alphaSum(try render(effect, 0.43, mesh: 0, particles: 16)), 0)
        }
        XCTAssertGreaterThan(alphaSum(try render(.wobbly, 0.43, particles: 0)), 0)
        XCTAssertEqual(alphaSum(try render(.wobbly, 0.43, mesh: 0)), 0)
    }

    func testDepthOfFieldZeroIsSharpAndEverySamplingRingIsUsed() throws {
        let original = try render(.depthOfField, 0)
        let noBlur = try render(.depthOfField, 0.5, blur: 0)
        XCTAssertTrue(original == noBlur, "Zero blur rings must sample the unmodified capture")
        XCTAssertTrue(noBlur == (try render(.depthOfField, 0.5, blur: .min)))
        var previous = noBlur
        for rings in 1...4 {
            let blurred = try render(.depthOfField, 0.5, blur: rings)
            XCTAssertGreaterThan(meanDifference(previous, blurred), 0.001, "Ring \(rings) was ignored")
            assertPremultiplied(blurred, "DOF \(rings) rings")
            previous = blurred
        }
        XCTAssertTrue(previous == (try render(.depthOfField, 0.5, blur: .max)))
    }

    func testCropAndGlobalScreenOriginAreRespected() throws {
        let crop = SIMD4<Float>(0.23, 0.17, 0.55, 0.68)
        for effect in EffectID.allCases {
            let full = try render(effect, 0.31)
            let cropped = try render(effect, 0.31, uv: crop)
            XCTAssertGreaterThan(meanDifference(full, cropped), 0.05, "\(effect) ignores the UV crop")
            let translated = try render(effect, 0.31, uv: crop,
                                        frame: window.offsetBy(dx: 120, dy: -75),
                                        screenRect: screen.offsetBy(dx: 120, dy: -75))
            XCTAssertLessThan(meanDifference(cropped, translated), 0.15,
                              "\(effect) used local coordinates as global coordinates")
        }
    }

    func testGeometryIsPerspectiveLitAndBudgetDependent() throws {
        for effect in [EffectID.fold, .ripple, .liquidMorph] {
            let coarse = try render(effect, 0.43, mesh: 1)
            let tessellated = try render(effect, 0.43, mesh: 32)
            XCTAssertGreaterThan(meanDifference(coarse, tessellated), 0.05,
                                 "\(effect) does not use a genuinely deformed mesh")
        }
        let original = try render(.flip, 0)
        let flipped = try render(.flip, 0.5)
        // A 3D flip narrows the projected silhouette, not merely its source UVs.
        XCTAssertLessThan(alphaSum(flipped), alphaSum(original))
        XCTAssertGreaterThan(meanDifference(try render(.fold, 0.5), flipped), 0.1)
    }

    func testAmplitudeAndSpeedControlReversibleDeformations() throws {
        let original = try render(.wobbly, 0)
        for effect in [EffectID.wobbly, .fold, .flip, .ripple, .liquidMorph, .orbit] {
            let zero = try render(effect, 0.4, amplitude: 0)
            XCTAssertLessThan(meanDifference(original, zero), 0.12, "\(effect) ignores zero amplitude")
            XCTAssertGreaterThan(meanDifference(zero, try render(effect, 0.4, amplitude: 1.5)), 0.05)
        }
        for effect in [EffectID.wobbly, .float, .ripple, .liquidMorph, .orbit] {
            XCTAssertGreaterThan(meanDifference(try render(effect, 0.37, speed: 0.5),
                                                try render(effect, 0.37, speed: 2)), 0.01,
                                 "\(effect) ignores speed")
        }
    }

    func testMalformedInputsSkipAndProgressIsClamped() throws {
        for effect in EffectID.allCases {
            XCTAssertEqual(alphaSum(try render(effect, .nan)), 0)
            XCTAssertEqual(alphaSum(try render(effect, .infinity)), 0)
            XCTAssertEqual(alphaSum(try render(effect, 0.4, amplitude: .nan)), 0)
            XCTAssertEqual(alphaSum(try render(effect, 0.4, speed: .infinity)), 0)
            XCTAssertEqual(alphaSum(try render(effect, 0.4, uv: SIMD4(0, 0, -1, 1))), 0)
            XCTAssertEqual(alphaSum(try render(effect, 0.4, uv: SIMD4(0, 0, .nan, 1))), 0)
            XCTAssertEqual(alphaSum(try render(effect, 0.4, uv: SIMD4(0.8, 0, 0.5, 1))), 0)
            XCTAssertEqual(alphaSum(try render(effect, 0.4, frame: .null)), 0)
            XCTAssertEqual(alphaSum(try render(effect, 0.4, frame: .zero)), 0)
            XCTAssertEqual(alphaSum(try render(effect, 0.4, screenRect: .infinite)), 0)
            XCTAssertEqual(alphaSum(try render(effect, 0.4,
                                              screenRect: CGRect(x: 0, y: 0, width: 1e-200, height: 1))), 0)
            XCTAssertTrue((try render(effect, -10)) == (try render(effect, 0)))
            XCTAssertTrue((try render(effect, 10)) == (try render(effect, 1)))
        }
    }

    func testReplayingTheSameFrameIsDeterministic() throws {
        for effect in EffectID.allCases {
            XCTAssertTrue((try render(effect, 0.47)) == (try render(effect, 0.47)), "\(effect) is nondeterministic")
        }
    }

    func testEverySpecificParameterChangesActualShippedAssetPixels() throws {
        // Derive coverage from the live catalog, not a second hand-maintained key list.
        // Physics/layout keys are tested as local visual controls here, never as CPU
        // simulation or a claim that the GPU has moved any native windows.
        for descriptor in EffectCatalog.effects {
            for spec in descriptor.parameters where spec.id != "amplitude" && spec.id != "speed" {
                var largestDifference = 0.0
                for progress: Float in [0.19, 0.37, 0.63] {
                    let baseline = try render(descriptor.id, progress)
                    for value in [spec.minimum, spec.maximum] {
                        let changed = try render(descriptor.id, progress, parameters: [spec.id: Float(value)])
                        assertPremultiplied(changed, "\(descriptor.id).\(spec.id)=\(value)")
                        largestDifference = max(largestDifference, meanDifference(baseline, changed))
                    }
                    if largestDifference > 0.001 { break }
                }
                XCTAssertGreaterThan(largestDifference, 0.001,
                                     "\(descriptor.id).\(spec.id) is metadata, not an actual renderer input")
            }
        }
    }

    func testEvaluatedDictionaryOverridesLegacyAmplitudeAndSpeed() throws {
        for effect in [EffectID.wobbly, .float, .ripple, .liquidMorph, .orbit] {
            let legacy = try render(effect, 0.37, amplitude: 0.4, speed: 2)
            let evaluated = try render(effect, 0.37, amplitude: 1.8, speed: 0.5,
                                       parameters: ["amplitude": 0.4, "speed": 2])
            XCTAssertEqual(legacy, evaluated, "\(effect) ignored evaluated timeline values")
        }
    }

    func testParameterDefaultsNonfiniteFallbackAndClampsOnGPU() throws {
        for descriptor in EffectCatalog.effects {
            let defaults = Dictionary(uniqueKeysWithValues: descriptor.parameters.map { ($0.id, Float($0.defaultValue)) })
            let original = try render(descriptor.id, 0.37)
            XCTAssertEqual(original, try render(descriptor.id, 0.37, parameters: defaults))
            for invalid: Float in [.nan, .infinity, -.infinity] {
                let values = Dictionary(uniqueKeysWithValues: descriptor.parameters.map { ($0.id, invalid) })
                XCTAssertEqual(original, try render(descriptor.id, 0.37, parameters: values),
                               "\(descriptor.id) must fall back to descriptor defaults")
            }
            for upper in [false, true] {
                let outside = Dictionary(uniqueKeysWithValues: descriptor.parameters.map {
                    ($0.id, upper ? Float.greatestFiniteMagnitude : -Float.greatestFiniteMagnitude)
                })
                let bounded = Dictionary(uniqueKeysWithValues: descriptor.parameters.map {
                    ($0.id, Float(upper ? $0.maximum : $0.minimum))
                })
                let clamped = try render(descriptor.id, 0.37, parameters: outside)
                XCTAssertEqual(clamped, try render(descriptor.id, 0.37, parameters: bounded))
                assertPremultiplied(clamped, "\(descriptor.id) clamped parameters")
            }
            XCTAssertEqual(original, try render(descriptor.id, 0.37, parameters: ["unknown": .nan]))
        }
    }

    func testParameterExtremesKeepEndpointsAndPortraitCoordinatesValid() throws {
        let portrait = CGRect(x: -9, y: 58, width: 58, height: 148)
        let crop = SIMD4<Float>(0.12, 0.23, 0.72, 0.64)
        let original = try render(.wobbly, 0, uv: crop, frame: portrait)
        for descriptor in EffectCatalog.effects {
            for upper in [false, true] {
                let values = Dictionary(uniqueKeysWithValues: descriptor.parameters.map {
                    ($0.id, Float(upper ? $0.maximum : $0.minimum))
                })
                let start = try render(descriptor.id, 0, uv: crop, frame: portrait, parameters: values)
                XCTAssertLessThan(meanDifference(original, start), 0.12, "\(descriptor.id) extreme start")
                let end = try render(descriptor.id, 1, uv: crop, frame: portrait, parameters: values)
                if closing.contains(descriptor.id) {
                    XCTAssertEqual(alphaSum(end), 0)
                } else {
                    XCTAssertLessThan(meanDifference(original, end), 0.12, "\(descriptor.id) extreme end")
                }
                let middle = try render(descriptor.id, 0.37, uv: crop, frame: portrait, parameters: values)
                assertPremultiplied(middle, "\(descriptor.id) portrait extreme")
                let translated = try render(descriptor.id, 0.37, uv: crop,
                    frame: portrait.offsetBy(dx: 800_000_000, dy: -800_000_000),
                    screenRect: screen.offsetBy(dx: 800_000_000, dy: -800_000_000), parameters: values)
                XCTAssertEqual(middle, translated, "\(descriptor.id) lost precision at a global screen origin")
            }
        }
    }

    func testZeroControlsAndQualityBudgetsHaveRealShaderFallbacks() throws {
        let original = try render(.depthOfField, 0)
        XCTAssertEqual(original, try render(.depthOfField, 0.5, parameters: ["blur": 0]))
        XCTAssertEqual(original, try render(.float, 0.5, parameters: ["distance": 0]))
        // A zero hinge/yaw remains a valid rendered surface, not a discarded mesh
        // or a division-by-zero in the shader's geometry/lighting calculations.
        for effect in [EffectID.fold, .flip] {
            let zero = try render(effect, 0.37, parameters: ["angle": 0])
            assertPremultiplied(zero, "\(effect) zero angle")
            XCTAssertGreaterThan(alphaSum(zero), 0)
        }
        for quality in [RenderQuality.low, .balanced, .high, .ultra] {
            let budget = RenderBudget.forQuality(quality)
            let pixels = try render(.depthOfField, 0.5, mesh: budget.meshLimit,
                                     particles: budget.maxParticles, blur: budget.blurPasses,
                                     parameters: ["blur": 40, "focus": 0])
            assertPremultiplied(pixels, "DOF \(quality)")
            if budget.blurPasses == 0 {
                XCTAssertLessThan(meanDifference(original, pixels), 0.12)
            } else {
                XCTAssertGreaterThan(meanDifference(original, pixels), 0.001)
            }
        }
    }
}

/// Budget checks run even on hosts without Metal, and verify exact encoded work.
final class CatalogEffectBudgetTests: XCTestCase {
    func testEveryDescriptorParameterIsFiniteAndBoundedIncludingRuntimePhysicsKeys() {
        for descriptor in EffectCatalog.effects {
            let defaults = CatalogEffectRenderer.resolvedParameters(effect: descriptor.id, parameters: [:])
            XCTAssertEqual(defaults.count, descriptor.parameters.count)
            for spec in descriptor.parameters {
                XCTAssertEqual(defaults[spec.id], Float(spec.defaultValue))
                for input: Float in [.nan, .infinity, -.infinity, -.greatestFiniteMagnitude,
                                     .greatestFiniteMagnitude, 0, 1] {
                    let values = CatalogEffectRenderer.resolvedParameters(effect: descriptor.id,
                                                                           parameters: [spec.id: input])
                    let expected = input.isFinite
                        ? min(Float(spec.maximum), max(Float(spec.minimum), input)) : Float(spec.defaultValue)
                    XCTAssertEqual(values[spec.id], expected, "\(descriptor.id).\(spec.id)")
                    XCTAssertTrue(values.values.allSatisfy(\.isFinite))
                }
            }
        }
    }

    func testFragmentParameterAndRenderQualityBothLimitActualTransport() {
        for effect in [EffectID.shatter, .explode] {
            for requested: Float in [4, 17, 64, 96, 256, .nan, .infinity] {
                let sanitized = CatalogEffectRenderer.resolvedParameters(effect: effect,
                                                                         parameters: ["fragments": requested])
                for quality in [RenderQuality.low, .balanced, .high, .ultra] {
                    let budget = RenderBudget.forQuality(quality)
                    for particles in [0, 1, 7, budget.maxParticles, Int.max] {
                        let work = CatalogEffectRenderer.workload(effect: effect, meshLimit: budget.meshLimit,
                            particleLimit: particles, blurPasses: budget.blurPasses,
                            parameters: ["fragments": requested])
                        XCTAssertLessThanOrEqual(work.instanceCount, Int(sanitized["fragments"]!))
                        XCTAssertLessThanOrEqual(work.instanceCount, particles)
                        XCTAssertEqual(work.vertexCount, 6)
                    }
                }
            }
        }
        let zero = CatalogEffectRenderer.workload(effect: .depthOfField, meshLimit: 64,
            particleLimit: 1500, blurPasses: 4, parameters: ["blur": 0])
        XCTAssertEqual(zero.blurRings, 0, "Zero blur must cost no extra texture samples")
    }

    func testWorkloadBoundsForAllStylesAndExtremeIntegers() {
        for effect in EffectID.allCases {
            for limit in [Int.min, -1, 0, 1, 2, 7, 24, 127, 1500, 4096, Int.max] {
                let work = CatalogEffectRenderer.workload(effect: effect, meshLimit: limit,
                                                         particleLimit: limit, blurPasses: limit)
                XCTAssertEqual(work.subdivisions, min(64, max(0, limit)))
                XCTAssertEqual(work.blurRings, min(4, max(0, limit)))
                if effect == .shatter || effect == .explode {
                    XCTAssertTrue(work.fragmented)
                    XCTAssertEqual(work.vertexCount, 6)
                    XCTAssertLessThanOrEqual(work.instanceCount, min(4096, max(0, limit)))
                    if limit > 0 { XCTAssertGreaterThan(work.instanceCount, 0) }
                } else {
                    XCTAssertFalse(work.fragmented)
                    XCTAssertEqual(work.instanceCount, 1)
                    XCTAssertEqual(work.vertexCount, work.subdivisions * work.subdivisions * 6)
                    XCTAssertLessThanOrEqual(work.vertexCount, 64 * 64 * 6)
                }
            }
        }
    }
}