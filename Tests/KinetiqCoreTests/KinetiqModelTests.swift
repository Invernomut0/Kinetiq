// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import simd
import XCTest
@testable import KinetiqCore

final class KinetiqModelTests: XCTestCase {
    private let frame: Float = 1.0 / 120.0
    private let presets: [KinetiqSettings] = [.subtle, .realistic, .exaggerated, .extreme]

    /// Drags from the title bar a distance `delta` over `duration` seconds and releases.
    /// Returns the peak deformation and how long it takes to settle after release.
    private func simulateDrag(_ settings: KinetiqSettings, delta: SIMD2<Float>, duration: Float)
        -> (peak: Float, settle: Float, model: KinetiqModel) {
        let start = SIMD2<Float>(200, 150)
        let grabLocal = SIMD2<Float>(300, 12)
        let model = KinetiqModel(size: SIMD2(900, 600), origin: start, settings: settings)
        model.grab(at: start + grabLocal)

        var peak: Float = 0
        let steps = Int(duration / frame)
        for n in 1...steps {
            let t = Float(n) / Float(steps)
            let origin = start + delta * (t * t * (3 - 2 * t))
            model.moveGrab(to: origin + grabLocal, origin: origin)
            model.step(frame)
            peak = max(peak, model.maxDisplacement)
        }
        model.release(origin: start + delta)

        var elapsed: Float = 0
        repeat {
            model.step(frame)
            elapsed += frame
            peak = max(peak, model.maxDisplacement)
        } while !model.isSettled && elapsed < 10
        return (peak, elapsed, model)
    }

    func testRestStateIsTheRigidFrame() {
        let model = KinetiqModel(size: SIMD2(800, 500), origin: SIMD2(10, 20))
        XCTAssertEqual(model.maxDisplacement, 0, accuracy: 1e-3)
        XCTAssertEqual(model.point(u: 1, v: 1).x, 810, accuracy: 1e-3)
        XCTAssertEqual(model.point(u: 0.5, v: 0.5).y, 270, accuracy: 1e-3)
        for _ in 0..<240 { model.step(frame) }
        XCTAssertTrue(model.isSettled)
        XCTAssertEqual(model.maxDisplacement, 0, accuracy: 1e-3)
    }

    func testDragSettlesAtTheDropPointForEveryPreset() {
        for settings in presets {
            let result = simulateDrag(settings, delta: SIMD2(500, 120), duration: 0.4)
            print("\(settings): peak \(result.peak) pt, settles in \(result.settle) s")
            XCTAssertTrue(result.model.isSettled, "does not settle: \(settings)")
            XCTAssertLessThan(result.settle, 4)
            XCTAssertGreaterThan(result.peak, 5, "barely noticeable: \(settings)")
            XCTAssertLessThan(result.model.maxDisplacement, 1, "stays deformed: \(settings)")
            XCTAssertTrue(result.model.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        }
    }

    func testWorldFrictionLeavesATrailWhileDragging() {
        // The Compiz signature: at constant speed the window trails stretched behind the cursor.
        var origin = SIMD2<Float>(0, 0)
        let grabLocal = SIMD2<Float>(450, 10)
        let model = KinetiqModel(size: SIMD2(900, 600), origin: origin)
        model.grab(at: origin + grabLocal)
        for _ in 0..<240 {
            origin += SIMD2(1200, 0) * frame
            model.moveGrab(to: origin + grabLocal, origin: origin)
            model.step(frame)
        }
        let trail = model.displacement(u: 0.5, v: 1)
        XCTAssertLessThan(trail.x, -10, "the bottom edge should lag behind")
        XCTAssertTrue(trail.x.isFinite)
    }

    func testMaximizeAndUnmaximizeBounceAndSettle() {
        for settings in presets {
            for maximize in [true, false] {
                let model = KinetiqModel(size: SIMD2(1440, 860), origin: SIMD2(0, 38), settings: settings)
                if maximize { model.maximize() } else { model.unmaximize() }
                var peak: Float = 0
                var elapsed: Float = 0
                repeat {
                    model.step(frame)
                    elapsed += frame
                    peak = max(peak, model.maxDisplacement)
                } while !model.isSettled && elapsed < 10
                print("\(maximize ? "maximize" : "unmaximize") \(settings): peak \(peak) pt in \(elapsed) s")
                XCTAssertTrue(model.isSettled)
                XCTAssertGreaterThan(peak, 5)
                XCTAssertLessThan(model.maxDisplacement, 1)
            }
        }
    }

    func testHigherSpeedupFactorIsSlower() {
        XCTAssertGreaterThan(KinetiqSettings.subtle.stepsPerSecond, KinetiqSettings.extreme.stepsPerSecond)
        XCTAssertEqual(KinetiqSettings.realistic.stepsPerSecond, 1000 / 12 + 30, accuracy: 1e-3)
    }

    func testVertexGridHonoursTilesAndMargin() {
        let model = KinetiqModel(size: SIMD2(400, 200), origin: SIMD2(100, 100))
        var vertices: [SIMD4<Float>] = []
        model.fillVertices(tilesX: 16, tilesY: 14, margin: 40, into: &vertices)
        XCTAssertEqual(vertices.count, 17 * 15)
        XCTAssertEqual(vertices.first!.x, 60, accuracy: 1e-3)
        XCTAssertEqual(vertices.last!.y, 340, accuracy: 1e-3)
    }

    func testShadowRingWrapsTheWindowGrid() {
        let model = KinetiqModel(size: SIMD2(400, 200), origin: SIMD2(100, 100))
        var window: [SIMD4<Float>] = []
        var ringed: [SIMD4<Float>] = []
        model.fillVertices(tilesX: 16, tilesY: 14, into: &window)
        model.fillVertices(tilesX: 16, tilesY: 14, outset: (20, 10, 30, 40), into: &ringed)
        XCTAssertEqual(ringed.count, 19 * 17)
        XCTAssertEqual(ringed.first!.x, 80, accuracy: 1e-3)
        XCTAssertEqual(ringed.first!.y, 90, accuracy: 1e-3)
        XCTAssertEqual(ringed.last!.x, 530, accuracy: 1e-3)
        XCTAssertEqual(ringed.last!.y, 340, accuracy: 1e-3)
        // Inside the ring, the same vertices as the plain window grid.
        for j in 0...14 {
            for i in 0...16 {
                XCTAssertEqual(ringed[(j + 1) * 19 + i + 1], window[j * 17 + i])
            }
        }
    }

    func testResizeBounceKeepsThePickupRowStillAndEnds() {
        let bounce = ResizeBounce(
            size: SIMD2(800, 600), origin: SIMD2(0, 0), edges: [.right],
            pickup: SIMD2(800, 300), pointerTravel: SIMD2(200, 0), settings: .realistic)
        var peak: Float = 0
        var elapsed: Float = 0
        while !bounce.isSettled {
            bounce.step(frame)
            elapsed += frame
            XCTAssertEqual(bounce.displacement(u: 1, v: 0.5).x, 0, accuracy: 1e-3)
            peak = max(peak, abs(bounce.displacement(u: 1, v: 0).x))
        }
        print("resize bounce: peak \(peak) pt")
        XCTAssertEqual(elapsed, 1, accuracy: 0.02)
        XCTAssertGreaterThan(peak, 10)
        XCTAssertEqual(bounce.maxDisplacement, 0, accuracy: 1)
    }

    func testResizeEdgesDetection() {
        let old = (minX: Float(0), minY: Float(0), maxX: Float(800), maxY: Float(600))
        XCTAssertEqual(ResizeEdges.between(old, (0, 0, 900, 600)), [.right])
        XCTAssertEqual(ResizeEdges.between(old, (-50, 0, 800, 650)), [.left, .bottom])
        XCTAssertNil(ResizeEdges.between(old, (10, 0, 810, 600)), "that's a move, not a resize")
        XCTAssertNil(ResizeEdges.between(old, old))
    }

    func testFlungWindowBouncesOffTheBoundsAndSettlesInside() {
        let bounds = (min: SIMD2<Float>(0, 25), max: SIMD2<Float>(1000, 400))
        let model = KinetiqModel(size: SIMD2(600, 400), origin: SIMD2(100, 100), settings: .realistic)
        model.grab(at: SIMD2(300, 110))
        model.release(origin: SIMD2(100, 100))
        model.fling(velocity: SIMD2(4000, 0), bounds: bounds)
        XCTAssertTrue(model.isGliding)
        XCTAssertFalse(model.isSettled)

        var bounced = false
        var elapsed: Float = 0
        repeat {
            model.step(frame)
            elapsed += frame
            XCTAssertLessThanOrEqual(model.origin.x, bounds.max.x + 0.001)
            XCTAssertGreaterThanOrEqual(model.origin.x, bounds.min.x - 0.001)
            if model.origin.x >= bounds.max.x - 0.001 { bounced = true }
        } while !model.isSettled && elapsed < 15
        XCTAssertTrue(bounced, "the window never reached the right bound")
        XCTAssertTrue(model.isSettled)
        XCTAssertFalse(model.isGliding)
        XCTAssertEqual(model.origin.y, 100, accuracy: 0.001, "a horizontal fling must not move the window vertically")
    }

    /// A real flick: the window is dragged fast (nodes lag behind the cursor), then released while still moving.
    private func flick(_ preset: KinetiqSettings, velocity: SIMD2<Float>, bounds: (min: SIMD2<Float>, max: SIMD2<Float>))
        -> (model: KinetiqModel, firstStepDelta: SIMD2<Float>, settled: Bool) {
        let start = SIMD2<Float>(600, 350)
        let grabLocal = SIMD2<Float>(250, 12)
        let model = KinetiqModel(size: SIMD2(500, 350), origin: start, settings: preset)
        model.grab(at: start + grabLocal)
        var origin = start
        for _ in 0..<12 {
            origin += velocity * frame
            model.moveGrab(to: origin + grabLocal, origin: origin)
            model.step(frame)
        }
        model.release(origin: origin)
        model.fling(velocity: velocity, bounds: bounds)
        let before = model.origin
        model.step(frame)
        let firstStepDelta = model.origin - before

        var elapsed: Float = 0
        while !model.isSettled && elapsed < 20 {
            model.step(frame)
            elapsed += frame
        }
        return (model, firstStepDelta, model.isSettled)
    }

    func testFlickGlidesTowardsTheMovementAndSettlesExactlyAtTheOrigin() {
        let bounds = (min: SIMD2<Float>(0, 25), max: SIMD2<Float>(1228, 767))
        let velocities: [SIMD2<Float>] = [SIMD2(3000, 0), SIMD2(-3000, 0), SIMD2(0, 2500), SIMD2(0, -2500), SIMD2(2500, -1800)]
        for preset in presets {
            for velocity in velocities {
                let result = flick(preset, velocity: velocity, bounds: bounds)
                XCTAssertGreaterThan(simd_dot(result.firstStepDelta, velocity), 0, "glides against the movement for \(velocity)")
                XCTAssertTrue(result.settled, "never settles for \(velocity)")
                XCTAssertEqual(result.model.maxDisplacement, 0, accuracy: 1, "the mesh must end on the rigid frame")
                XCTAssertGreaterThanOrEqual(result.model.origin.x, bounds.min.x - 0.01)
                XCTAssertLessThanOrEqual(result.model.origin.x, bounds.max.x + 0.01)
                XCTAssertGreaterThanOrEqual(result.model.origin.y, bounds.min.y - 0.01)
                XCTAssertLessThanOrEqual(result.model.origin.y, bounds.max.y + 0.01)
            }
        }
    }

    func testWindowThatStartsPastABoundIsNotThrownBack() {
        // The bounds were widened to the window's own position, as the controller does for windows sticking out.
        let origin = SIMD2<Float>(300, 500)
        let bounds = (min: SIMD2<Float>(0, 25), max: SIMD2<Float>(1228, origin.y))
        let model = KinetiqModel(size: SIMD2(500, 700), origin: origin, settings: .realistic)
        model.grab(at: origin + SIMD2(250, 12))
        model.release(origin: origin)
        model.fling(velocity: SIMD2(1500, 0), bounds: bounds)
        for _ in 0..<30 { model.step(frame) }
        XCTAssertEqual(model.origin.y, origin.y, accuracy: 0.001, "a horizontal fling must leave the vertical position alone")
        XCTAssertGreaterThan(model.origin.x, origin.x)
    }

    func testSlowReleaseDoesNotGlide() {
        let model = KinetiqModel(size: SIMD2(600, 400), origin: SIMD2(100, 100), settings: .realistic)
        model.grab(at: SIMD2(300, 110))
        model.fling(velocity: SIMD2(10, 0), bounds: nil)
        XCTAssertFalse(model.isGliding)
    }

    func testGrabbingAgainStopsTheGlide() {
        let model = KinetiqModel(size: SIMD2(600, 400), origin: SIMD2(100, 100), settings: .realistic)
        model.grab(at: SIMD2(300, 110))
        model.fling(velocity: SIMD2(2000, 0), bounds: nil)
        model.step(frame)
        model.grab(at: model.positions[5])
        XCTAssertFalse(model.isGliding)
        XCTAssertTrue(model.isGrabbed)
    }

    func testRippleSpreadsFromTheDropPointAndDiesOut() {
        let model = KinetiqModel(size: SIMD2(800, 600), origin: SIMD2(100, 100), settings: .realistic)
        XCTAssertEqual(model.maxDisplacement, 0, accuracy: 1e-4, "no ripple, no deformation")
        model.ripple(atLocal: SIMD2(400, 300))
        XCTAssertTrue(model.isRippling)
        XCTAssertFalse(model.isSettled)

        // Before the wave has travelled anywhere, far corners are untouched.
        model.step(0.05)
        XCTAssertEqual(simd_length(model.displacement(u: 1, v: 1)), 0, accuracy: 1e-3)
        // Later it has reached them and deforms the window.
        var peak: Float = 0
        for _ in 0..<60 {
            model.step(frame)
            peak = max(peak, model.maxDisplacement)
        }
        XCTAssertGreaterThan(peak, 1)
        XCTAssertLessThan(peak, 10, "a ripple must not tear the window apart")

        var elapsed: Float = 0
        while !model.isSettled && elapsed < 5 {
            model.step(frame)
            elapsed += frame
        }
        XCTAssertTrue(model.isSettled)
        XCTAssertFalse(model.isRippling)
        XCTAssertEqual(model.maxDisplacement, 0, accuracy: 1e-4, "the real window takes over from a flat overlay")
    }

    func testSnapToRestCancelsTheRipple() {
        let model = KinetiqModel(size: SIMD2(800, 600), origin: SIMD2(100, 100), settings: .realistic)
        model.ripple(atLocal: SIMD2(10, 10))
        model.step(0.2)
        model.snapToRest()
        XCTAssertFalse(model.isRippling)
        XCTAssertEqual(model.maxDisplacement, 0, accuracy: 1e-4)
    }
}
