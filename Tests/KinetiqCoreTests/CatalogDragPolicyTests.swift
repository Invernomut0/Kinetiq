// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import KinetiqCore
import simd
import XCTest

final class CatalogDragPolicyTests: XCTestCase {
    /// Actual display dimensions, converted to the app's global Y-down coordinates.
    /// Derived rectangles exercise layout math; no capture images or desktop APIs are mocked.
    @MainActor private func geometry() throws -> (bounds: CGRect, frame: CGRect) {
        guard let screen = NSScreen.screens.first else { throw XCTSkip("A real display is required") }
        let visible = screen.visibleFrame
        let bounds = CGRect(x: visible.minX, y: screen.frame.height - visible.maxY,
                            width: visible.width, height: visible.height)
        guard bounds.width >= 400, bounds.height >= 300 else { throw XCTSkip("A usable real display is required") }
        let frame = CGRect(x: bounds.minX + bounds.width * 0.35, y: bounds.minY + bounds.height * 0.35,
                           width: bounds.width * 0.2, height: bounds.height * 0.2)
        return (bounds, frame)
    }

    private func preset(_ effect: EffectID, duration: Double = 1) -> EffectPreset {
        var result = EffectPreset(effect: effect)
        result.trigger = .drag
        result.duration = duration
        return result
    }

    func testOnlyExplicitSupportedDragAssignmentsParticipate() {
        XCTAssertNil(CatalogDragPolicy(preset: nil))
        XCTAssertNil(CatalogDragPolicy(preset: EffectPreset(effect: .wobbly)))
        XCTAssertNil(CatalogDragPolicy(preset: preset(.burn)))
        for effect: EffectID in [.wobbly, .float, .ripple, .magnet, .gravity] {
            XCTAssertEqual(CatalogDragPolicy(preset: preset(effect))?.preset.effect, effect)
        }
        var open = preset(.wobbly)
        open.trigger = .open
        XCTAssertNil(CatalogDragPolicy(preset: open))
    }

    func testGestureSnapshotDoesNotReadSubsequentPresetEdits() throws {
        var selected = preset(.wobbly)
        selected.parameters["stiffness"] = 6
        let policy = try XCTUnwrap(CatalogDragPolicy(preset: selected))
        selected.parameters["stiffness"] = 1
        selected.tracks = [AnimationTrack(parameter: "stiffness", keyframes: [.init(time: 0, value: 10)])]
        XCTAssertEqual(policy.parameters(at: 0)["stiffness"], 6)
        XCTAssertTrue(policy.preset.tracks.isEmpty)
    }

    func testDurationPresetCurveAndOutgoingKeyCurveAreEachAppliedOnce() throws {
        var selected = preset(.wobbly, duration: 2)
        selected.curve = .easeIn
        selected.tracks = [AnimationTrack(parameter: "amplitude", keyframes: [
            .init(time: 0, value: 0, curve: .linear), .init(time: 1, value: 2)
        ])]
        let policy = try XCTUnwrap(CatalogDragPolicy(preset: selected))
        XCTAssertEqual(try XCTUnwrap(policy.parameters(at: 1)["amplitude"]), 0.5, accuracy: 1e-12)
        XCTAssertEqual(policy.parameters(at: -1)["amplitude"], 0)
        XCTAssertEqual(policy.parameters(at: 200)["amplitude"], 2)
        selected.tracks[0].keyframes[0].curve = .easeIn
        let curved = try XCTUnwrap(CatalogDragPolicy(preset: selected))
        XCTAssertEqual(try XCTUnwrap(curved.parameters(at: 1)["amplitude"]), 0.125, accuracy: 1e-12)
    }

    func testMutedTracksAndNonfiniteElapsedUseSafeSampling() throws {
        var selected = preset(.wobbly)
        selected.parameters["amplitude"] = 0.7
        selected.tracks = [AnimationTrack(parameter: "amplitude", keyframes: [
            .init(time: 0, value: 2), .init(time: 1, value: 0)
        ], muted: true)]
        let policy = try XCTUnwrap(CatalogDragPolicy(preset: selected))
        for time in [Double.nan, -.infinity, .infinity, 0, 0.5, 10] {
            XCTAssertEqual(policy.parameters(at: time)["amplitude"], 0.7)
        }
    }

    func testWobblyMapsSpringFrictionWithoutChangingMassOrLegacySpeedup() throws {
        var selected = preset(.wobbly)
        selected.parameters["stiffness"] = 8
        selected.parameters["friction"] = 2
        let policy = try XCTUnwrap(CatalogDragPolicy(preset: selected))
        let physics = policy.wobblySettings(base: .exaggerated, at: 0.5)
        XCTAssertEqual(physics.spring, 8)
        XCTAssertEqual(physics.friction, 2)
        XCTAssertEqual(physics.mass, KinetiqSettings.exaggerated.mass)
        XCTAssertEqual(physics.speedup, KinetiqSettings.exaggerated.speedup)
        let other = try XCTUnwrap(CatalogDragPolicy(preset: preset(.gravity)))
        XCTAssertEqual(other.wobblySettings(base: .extreme, at: 0), .extreme)
    }

    @MainActor func testWobblySpeedMultipliesFixedSimulationRateNotInputCadence() throws {
        let (_, frame) = try geometry()
        let size = SIMD2(Float(frame.width), Float(frame.height))
        let origin = SIMD2(Float(frame.minX), Float(frame.minY))
        let fast = KinetiqModel(size: size, origin: origin)
        let reference = KinetiqModel(size: size, origin: origin)
        for model in [fast, reference] { model.shear(amount: 0.1) }
        fast.updateSettings(.realistic, speed: 2)
        for _ in 0..<120 {
            fast.step(1 / 120)
            reference.step(1 / 60)
        }
        XCTAssertEqual(fast.positions, reference.positions)
        XCTAssertEqual(fast.origin, reference.origin)
    }

    @MainActor func testTranslatePreservesEveryNodeAndDeformationAtFinalOrigin() throws {
        let (bounds, frame) = try geometry()
        let origin = SIMD2(Float(frame.minX), Float(frame.minY))
        let size = SIMD2(Float(frame.width), Float(frame.height))
        let model = KinetiqModel(size: size, origin: origin)
        model.shear(amount: 0.15)
        model.step(1 / 60)
        let before = model.positions
        let displacement = model.displacement(u: 0.4, v: 0.7)
        let final = SIMD2(Float(bounds.minX), Float(bounds.maxY - frame.height))
        model.translate(to: final)
        XCTAssertEqual(model.origin, final)
        for index in before.indices {
            XCTAssertEqual(model.positions[index].x, before[index].x + final.x - origin.x, accuracy: 0.001)
            XCTAssertEqual(model.positions[index].y, before[index].y + final.y - origin.y, accuracy: 0.001)
        }
        XCTAssertEqual(model.displacement(u: 0.4, v: 0.7).x, displacement.x, accuracy: 0.002)
        XCTAssertEqual(model.displacement(u: 0.4, v: 0.7).y, displacement.y, accuracy: 0.002)
        model.snapToRest()
        XCTAssertEqual(model.origin, final, "Restoration must not return to the pre-drag origin")
        XCTAssertLessThan(model.maxDisplacement, 0.002)
    }

    @MainActor func testTranslateRejectsNonfiniteCoordinatesAndPreservesGrab() throws {
        let (_, frame) = try geometry()
        let origin = SIMD2(Float(frame.minX), Float(frame.minY))
        let model = KinetiqModel(size: SIMD2(Float(frame.width), Float(frame.height)), origin: origin)
        let grab = origin + SIMD2(10, 10)
        model.grab(at: grab)
        let before = model.positions
        model.translate(to: SIMD2(.nan, 0))
        model.translate(to: SIMD2(0, .infinity))
        XCTAssertEqual(model.positions, before)
        XCTAssertEqual(model.origin, origin)
        let delta = SIMD2<Float>(20, 30)
        model.translate(to: origin + delta)
        model.moveGrab(to: grab + delta, origin: origin + delta)
        XCTAssertEqual(model.positions, before.map { $0 + delta })
        XCTAssertTrue(model.isGrabbed)
    }

    @MainActor func testFloatContinuesAmbientMotionAfterParameterTimelineEnds() throws {
        let (_, frame) = try geometry()
        var selected = preset(.float, duration: 0.1)
        selected.parameters["frequency"] = 0.5
        selected.parameters["speed"] = 2
        selected.parameters["amplitude"] = 1.5
        selected.parameters["distance"] = 0.1
        let policy = try XCTUnwrap(CatalogDragPolicy(preset: selected))
        let size = SIMD2(Float(frame.width), Float(frame.height))
        let a = policy.ambientOffset(size: size, elapsed: 2.25)
        let b = policy.ambientOffset(size: size, elapsed: 2.75)
        XCTAssertEqual(a.y, size.y * 0.15, accuracy: 0.001)
        XCTAssertEqual(b.y, -size.y * 0.15, accuracy: 0.001)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(policy.ambientOffset(size: size, elapsed: .nan), .zero)
    }

    func testFloatReleaseFadesContinuouslyToExactlyZeroWithinHalfASecond() throws {
        for duration in [0.1, 0.25, 1, 12] {
            let policy = try XCTUnwrap(CatalogDragPolicy(preset: preset(.float, duration: duration)))
            let offset = SIMD2<Float>(8, -15)
            XCTAssertEqual(policy.releaseOffset(offset, elapsed: 0), offset)
            XCTAssertGreaterThan(simd_length(policy.releaseOffset(offset, elapsed: min(0.5, duration) * 0.5)), 0)
            XCTAssertEqual(policy.releaseOffset(offset, elapsed: min(0.5, duration)), .zero)
            XCTAssertEqual(policy.releaseOffset(offset, elapsed: 100), .zero)
        }
    }

    @MainActor func testRippleUsesActualPresetValuesAndExpires() throws {
        let (_, frame) = try geometry()
        var selected = preset(.ripple, duration: 0.25)
        selected.parameters["amplitude"] = 1.75
        selected.parameters["speed"] = 2.5
        selected.parameters["wavelength"] = 80
        selected.parameters["decay"] = 0.8
        let policy = try XCTUnwrap(CatalogDragPolicy(preset: selected))
        let values = policy.parameters(at: 0)
        let model = KinetiqModel(size: SIMD2(Float(frame.width), Float(frame.height)),
                                 origin: SIMD2(Float(frame.minX), Float(frame.minY)))
        model.ripple(atLocal: model.size / 2, amplitude: Float(try XCTUnwrap(values["amplitude"])) * 7,
                     wavelength: Float(try XCTUnwrap(values["wavelength"])),
                     speed: Float(try XCTUnwrap(values["speed"])) * 700,
                     duration: Float(policy.releaseDuration), decay: Float(try XCTUnwrap(values["decay"])))
        var peak: Float = 0
        for _ in 0..<20 {
            model.step(1 / 120)
            peak = max(peak, model.maxDisplacement)
        }
        XCTAssertGreaterThan(peak, 0.1)
        for _ in 0..<20 { model.step(1 / 120) }
        XCTAssertFalse(model.isRippling)
    }

    @MainActor func testMagnetAttractsToRealDisplayEdgeAndSnapsOnRelease() throws {
        let (bounds, original) = try geometry()
        var frame = original
        frame.origin.x = bounds.minX + 8
        let values = preset(.magnet).parameters
        let moved = CatalogDragPolicy.magnetOrigin(frame: frame, bounds: bounds, targets: [], parameters: values, dt: 1 / 120)
        XCTAssertLessThan(moved.x, frame.minX)
        XCTAssertGreaterThan(moved.x, bounds.minX)
        frame.origin.x = bounds.minX + 0.75
        XCTAssertEqual(CatalogDragPolicy.magnetOrigin(frame: frame, bounds: bounds, targets: [], parameters: values,
                                                     dt: 1 / 120, snap: true).x, bounds.minX)
    }

    @MainActor func testMagnetIgnoresXTargetsWithoutVerticalSegmentOverlap() throws {
        let (bounds, frame) = try geometry()
        let remote = CGRect(x: frame.maxX + 4, y: bounds.minY, width: frame.width, height: frame.height * 0.5)
        var values = preset(.magnet).parameters
        values["radius"] = 10
        let actual = CatalogDragPolicy.magnetOrigin(frame: frame, bounds: bounds, targets: [remote], parameters: values, dt: 1 / 60)
        XCTAssertEqual(actual, frame.origin)
        let nearby = CGRect(x: remote.minX, y: frame.minY, width: remote.width, height: frame.height)
        let attracted = CatalogDragPolicy.magnetOrigin(frame: frame, bounds: bounds, targets: [nearby], parameters: values, dt: 1 / 60)
        XCTAssertGreaterThan(attracted.x, frame.minX)
        XCTAssertEqual(attracted.y, frame.minY)
    }

    @MainActor func testMagnetIgnoresYTargetsWithoutHorizontalSegmentOverlap() throws {
        let (bounds, frame) = try geometry()
        let remote = CGRect(x: bounds.minX, y: frame.maxY + 4, width: frame.width * 0.5, height: frame.height)
        var values = preset(.magnet).parameters
        values["radius"] = 10
        XCTAssertEqual(CatalogDragPolicy.magnetOrigin(frame: frame, bounds: bounds, targets: [remote],
                       parameters: values, dt: 1 / 60), frame.origin)
        let nearby = CGRect(x: frame.minX, y: remote.minY, width: frame.width, height: frame.height)
        XCTAssertGreaterThan(CatalogDragPolicy.magnetOrigin(frame: frame, bounds: bounds, targets: [nearby],
                             parameters: values, dt: 1 / 60).y, frame.minY)
    }

    @MainActor func testMagnetRadiusStrengthAmplitudeAndSpeedControlRealAttraction() throws {
        let (bounds, frame) = try geometry()
        let target = frame.offsetBy(dx: frame.width + 8, dy: 0)
        var values = preset(.magnet).parameters
        values["radius"] = 20
        func moved(_ parameters: [String: Double]) -> CGPoint {
            CatalogDragPolicy.magnetOrigin(frame: frame, bounds: bounds, targets: [target], parameters: parameters, dt: 1 / 120)
        }
        let baseline = moved(values)
        XCTAssertGreaterThan(baseline.x, frame.minX)
        values["strength"] = 0
        XCTAssertEqual(moved(values), frame.origin)
        values["strength"] = 1
        values["amplitude"] = 0
        XCTAssertEqual(moved(values), frame.origin)
        values["amplitude"] = 1
        values["speed"] = 3
        XCTAssertGreaterThan(moved(values).x, baseline.x)
        values["radius"] = 10
        let far = target.offsetBy(dx: 20, dy: 0)
        XCTAssertEqual(CatalogDragPolicy.magnetOrigin(frame: frame, bounds: bounds, targets: [far],
                       parameters: values, dt: 1 / 120), frame.origin)
    }

    @MainActor func testMagnetConvergesOnReleaseWithoutOvershootOrFarAxisSnap() throws {
        let (bounds, original) = try geometry()
        var frame = original
        frame.origin.x = bounds.minX + 12
        var values = preset(.magnet).parameters
        values["radius"] = 30
        for _ in 0..<240 {
            let before = frame.origin
            frame.origin = CatalogDragPolicy.magnetOrigin(frame: frame, bounds: bounds, targets: [],
                parameters: values, dt: 1 / 120, snap: true)
            XCTAssertLessThanOrEqual(frame.minX, before.x)
            XCTAssertGreaterThanOrEqual(frame.minX, bounds.minX)
            XCTAssertEqual(frame.minY, original.minY)
        }
        XCTAssertEqual(frame.minX, bounds.minX)
    }

    @MainActor func testMagnetRejectsInvalidGeometryAndTimeWithoutMoving() throws {
        let (bounds, frame) = try geometry()
        var values = preset(.magnet).parameters
        values["radius"] = 10
        for dt in [Double.nan, .infinity, -1, 0] {
            XCTAssertEqual(CatalogDragPolicy.magnetOrigin(frame: frame, bounds: bounds, targets: [],
                           parameters: values, dt: dt), frame.origin)
        }
        XCTAssertEqual(CatalogDragPolicy.magnetOrigin(frame: frame, bounds: .null, targets: [],
                       parameters: values, dt: 1 / 60), frame.origin)
        XCTAssertEqual(CatalogDragPolicy.magnetOrigin(frame: frame, bounds: bounds, targets: [.null, .infinite],
                       parameters: values, dt: 1 / 60), frame.origin)
    }

    @MainActor func testBudgetRippleCancellationPreservesGrabAndSpringGeometry() throws {
        let (_, frame) = try geometry()
        let origin = SIMD2(Float(frame.minX), Float(frame.minY))
        let model = KinetiqModel(size: SIMD2(Float(frame.width), Float(frame.height)), origin: origin)
        model.grab(at: origin + SIMD2(10, 10))
        model.moveGrab(to: origin + SIMD2(30, 20), origin: origin + SIMD2(20, 10))
        model.ripple(atLocal: model.size / 2, duration: 12)
        model.step(1 / 120)
        let positions = model.positions
        let target = model.origin
        XCTAssertTrue(model.isRippling)
        model.cancelRipples()
        XCTAssertFalse(model.isRippling)
        XCTAssertTrue(model.isGrabbed)
        XCTAssertEqual(model.positions, positions)
        XCTAssertEqual(model.origin, target)
    }

    @MainActor func testGravityTranslatesModelToComputedBoundedFinalPositionAtDuration() throws {
        let (bounds, frame) = try geometry()
        let policy = try XCTUnwrap(CatalogDragPolicy(preset: preset(.gravity, duration: 0.5)))
        var dynamics = CatalogDynamics(frame: frame, bounds: bounds)
        let model = KinetiqModel(size: SIMD2(Float(frame.width), Float(frame.height)),
                                 origin: SIMD2(Float(frame.minX), Float(frame.minY)))
        for tick in 1...60 {
            dynamics.advance(1 / 120, effect: .gravity, parameters: policy.parameters(at: Double(tick) / 120))
            model.translate(to: SIMD2(Float(dynamics.body.frame.minX), Float(dynamics.body.frame.minY)))
            XCTAssertTrue(bounds.insetBy(dx: -0.001, dy: -0.001).contains(dynamics.body.frame))
        }
        XCTAssertEqual(dynamics.elapsed, policy.releaseDuration, accuracy: 1e-10)
        XCTAssertGreaterThan(model.origin.y, Float(frame.minY))
        let final = model.origin
        model.snapToRest()
        XCTAssertEqual(model.origin, final)
        XCTAssertEqual(model.origin.y, Float(dynamics.body.frame.minY), accuracy: 0.001)
        XCTAssertLessThan(model.maxDisplacement, 0.002)
    }

    @MainActor func testGravityConsumesAccelerationAndRestitutionInsteadOfLegacyGlide() throws {
        let (bounds, original) = try geometry()
        var frame = original
        frame.origin.y = bounds.maxY - frame.height - 1
        var selected = preset(.gravity)
        selected.parameters["acceleration"] = 1500
        selected.parameters["restitution"] = 0.8
        let policy = try XCTUnwrap(CatalogDragPolicy(preset: selected))
        var bouncing = CatalogDynamics(frame: frame, bounds: bounds)
        var stopped = bouncing
        var noBounce = policy.parameters(at: 0)
        noBounce["restitution"] = 0
        var didBounce = false
        for tick in 1...120 {
            bouncing.advance(1 / 120, effect: .gravity, parameters: policy.parameters(at: Double(tick) / 120))
            stopped.advance(1 / 120, effect: .gravity, parameters: noBounce)
            if bouncing.body.velocity.y < 0 { didBounce = true }
        }
        XCTAssertTrue(didBounce)
        XCTAssertEqual(stopped.body.frame.maxY, bounds.maxY, accuracy: 0.001)
        XCTAssertEqual(bouncing.body.frame.minX, frame.minX)
        XCTAssertTrue(bounds.insetBy(dx: -0.001, dy: -0.001).contains(bouncing.body.frame))
    }

    func testMeshBudgetCapsActualTopologyIncludingShadowRing() {
        for quality: RenderQuality in [.low, .balanced, .high, .ultra] {
            let budget = RenderBudget.forQuality(quality)
            for requested in [Int.min, -1, 0, 3, 16, 64, Int.max] {
                let tiles = CatalogDragPolicy.meshTiles(requested: requested, meshLimit: budget.meshLimit)
                XCTAssertGreaterThanOrEqual(tiles, 3)
                XCTAssertLessThanOrEqual(tiles + 2, budget.meshLimit)
                XCTAssertLessThanOrEqual(tiles + 2, 64)
                XCTAssertLessThan((tiles + 3) * (tiles + 3), Int(UInt16.max))
            }
        }
    }

    func testMeshBudgetHandlesTinyLimitsAndLiveQualityChanges() {
        XCTAssertEqual(CatalogDragPolicy.meshTiles(requested: 64, meshLimit: 0), 1)
        XCTAssertEqual(CatalogDragPolicy.meshTiles(requested: 64, meshLimit: Int.min), 1)
        XCTAssertEqual(CatalogDragPolicy.meshTiles(requested: 64, meshLimit: Int.max), 62)
        let high = CatalogDragPolicy.meshTiles(requested: 48, meshLimit: 48)
        let low = CatalogDragPolicy.meshTiles(requested: 48, meshLimit: 16)
        XCTAssertEqual(high, 46)
        XCTAssertEqual(low, 14)
        XCTAssertEqual(CatalogDragPolicy.meshTiles(requested: 48, meshLimit: 48), high)
    }
}