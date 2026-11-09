// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import simd
import XCTest
@testable import KinetiqCore

final class LiquidWorldTests: XCTestCase {
    private let h: Float = 1 / 120

    /// Read-only WindowServer data, not a mocked display or an invented window list.
    private func desktop() throws -> (screen: CGRect, windows: [CGRect]) {
        let screen = CGDisplayBounds(CGMainDisplayID())
        guard screen.width > 0, screen.height > 0, !screen.isInfinite else {
            throw XCTSkip("A live WindowServer display is required")
        }
        let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let windows = entries.compactMap { entry -> CGRect? in
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  rect.width >= 40, rect.height >= 30,
                  rect.intersects(screen) else { return nil }
            return rect
        }
        return (screen, windows)
    }

    /// Mathematical test domain derived from the current display. Scaling reduces
    /// test cost without substituting fake data for the real-desktop integration test.
    private func domain() throws -> CGRect {
        let screen = try desktop().screen
        return CGRect(x: screen.minX, y: screen.minY,
                      width: min(240, screen.width / 4), height: min(180, screen.height / 4))
    }

    private func source(in screen: CGRect) -> CGRect {
        CGRect(x: screen.minX + screen.width * 0.3, y: screen.minY + screen.height * 0.1,
               width: screen.width * 0.28, height: screen.height * 0.2)
    }

    private func advance(_ world: LiquidWorld, seconds: Float, scale: Float = 1) {
        for _ in 0..<Int((seconds * 120).rounded()) { world.step(h * scale) }
    }

    private func assertFiniteAndBounded(_ world: LiquidWorld, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThanOrEqual(world.particles.count, 1500, file: file, line: line)
        XCTAssertTrue(world.elapsed.isFinite, file: file, line: line)
        XCTAssertTrue((0...1).contains(world.alpha), file: file, line: line)
        for p in world.particles {
            XCTAssertTrue(p.position.x.isFinite && p.position.y.isFinite, file: file, line: line)
            XCTAssertTrue(p.velocity.x.isFinite && p.velocity.y.isFinite, file: file, line: line)
            XCTAssertLessThanOrEqual(simd_length(p.velocity), 1200.01, file: file, line: line)
            XCTAssertGreaterThanOrEqual(p.position.x, Float(world.screenBounds.minX) - 0.01, file: file, line: line)
            XCTAssertLessThanOrEqual(p.position.x, Float(world.screenBounds.maxX) + 0.01, file: file, line: line)
            XCTAssertGreaterThanOrEqual(p.position.y, Float(world.screenBounds.minY) - 0.01, file: file, line: line)
            XCTAssertLessThanOrEqual(p.position.y, Float(world.screenBounds.maxY) + world.spacing * 1.5 + 1.01, file: file, line: line)
        }
    }

    func testRealCurrentDisplayAndWindowGeometry() throws {
        let scene = try desktop()
        guard let frame = scene.windows.first else {
            throw XCTSkip("No normal on-screen window is available to sample")
        }
        let world = LiquidWorld(windowFrame: frame, screenBounds: scene.screen, obstacles: Array(scene.windows.dropFirst()))
        XCTAssertFalse(world.particles.isEmpty)
        XCTAssertEqual(world.windowFrame, frame)
        XCTAssertEqual(world.screenBounds, scene.screen)
        for p in world.particles {
            XCTAssertEqual(p.position.x, Float(frame.minX + CGFloat(p.uv.x) * frame.width), accuracy: 0.01)
            XCTAssertEqual(p.position.y, Float(frame.minY + CGFloat(p.uv.y) * frame.height), accuracy: 0.01)
            XCTAssertEqual(p.releaseTime, LiquidWorld.releaseFraction(u: p.uv.x, v: p.uv.y) * world.meltDuration)
        }
        advance(world, seconds: 0.35)
        assertFiniteAndBounded(world)
    }

    func testExactDiagonalReleaseContractAndAttachedSamplesStayStill() throws {
        XCTAssertEqual(LiquidWorld.releaseFraction(u: 1, v: 0), 0)
        XCTAssertEqual(LiquidWorld.releaseFraction(u: 0, v: 1), 1)
        XCTAssertEqual(LiquidWorld.releaseFraction(u: 0, v: 0), 0.58)
        XCTAssertEqual(LiquidWorld.releaseFraction(u: 1, v: 1), 0.42)
        let screen = try domain()
        let world = LiquidWorld(windowFrame: source(in: screen), screenBounds: screen, obstacles: [])
        let initial = world.particles
        advance(world, seconds: 0.3)
        XCTAssertTrue(world.particles.contains(where: \.isReleased))
        XCTAssertTrue(world.particles.contains(where: { !$0.isReleased }))
        for i in initial.indices {
            let p = world.particles[i]
            XCTAssertEqual(p.isReleased, p.releaseTime <= world.elapsed)
            if !p.isReleased { XCTAssertEqual(p.position, initial[i].position); XCTAssertEqual(p.velocity, .zero) }
        }
        let earliest = initial.min { $0.releaseTime < $1.releaseTime }!
        let latest = initial.max { $0.releaseTime < $1.releaseTime }!
        XCTAssertGreaterThan(earliest.uv.x, latest.uv.x)
        XCTAssertLessThan(earliest.uv.y, latest.uv.y)
        advance(world, seconds: 1.2)
        XCTAssertTrue(world.particles.allSatisfy(\.isReleased))
    }

    func testDeterminismAndEquivalentFramePartitions() throws {
        let screen = try domain(), frame = source(in: screen)
        let a = LiquidWorld(windowFrame: frame, screenBounds: screen, obstacles: [])
        let b = LiquidWorld(windowFrame: frame, screenBounds: screen, obstacles: [])
        advance(a, seconds: 12)
        for _ in 0..<720 { b.step(1 / 60) }
        XCTAssertEqual(a.elapsed, b.elapsed)
        for (lhs, rhs) in zip(a.particles, b.particles) {
            XCTAssertEqual(lhs.position, rhs.position)
            XCTAssertEqual(lhs.velocity, rhs.velocity)
            XCTAssertEqual(lhs.isReleased, rhs.isReleased)
        }
    }

    func testDurationScaleNormalizesPhysicsAndRendererTimeline() throws {
        let screen = try domain(), frame = source(in: screen)
        let normal = LiquidWorld(windowFrame: frame, screenBounds: screen, obstacles: [])
        advance(normal, seconds: 9)
        for scale: Float in [0.25, 0.5, 3] {
            let world = LiquidWorld(windowFrame: frame, screenBounds: screen, obstacles: [], durationScale: scale)
            advance(world, seconds: 9, scale: scale)
            XCTAssertEqual(world.meltDuration, 1.4 * scale)
            XCTAssertEqual(world.elapsed, normal.elapsed * scale, accuracy: 0.00001)
            XCTAssertEqual(world.alpha, normal.alpha)
            for (p, reference) in zip(world.particles, normal.particles) {
                XCTAssertEqual(p.position, reference.position, "Scaling must not change the fluid trajectory")
                XCTAssertEqual(p.velocity, reference.velocity)
                XCTAssertEqual(p.releaseTime, reference.releaseTime * scale, accuracy: 0.000001)
            }
        }
        for (input, expected): (Float, Float) in [(-1, 0.25), (100, 3), (.nan, 1), (.infinity, 1), (-.infinity, 1)] {
            let world = LiquidWorld(windowFrame: frame, screenBounds: screen, obstacles: [], durationScale: input)
            XCTAssertEqual(world.meltDuration, 1.4 * expected)
        }
    }

    func testTinyWindowFallsUnderGravityWithoutAnInitialKick() throws {
        let screen = try domain()
        let frame = CGRect(x: screen.midX, y: screen.minY + 2, width: 0.5, height: 0.5)
        let world = LiquidWorld(windowFrame: frame, screenBounds: screen, obstacles: [])
        XCTAssertEqual(world.particles.count, 1)
        let initial = world.particles[0].position
        advance(world, seconds: 0.6)
        XCTAssertEqual(world.particles[0].position, initial)
        advance(world, seconds: 0.3)
        XCTAssertGreaterThan(world.particles[0].position.y, initial.y + 5)
        XCTAssertGreaterThan(world.particles[0].velocity.y, 100)
        XCTAssertEqual(world.particles[0].velocity.x, 0)
        assertFiniteAndBounded(world)
    }

    func testSweptShelfContactFlowsSidewaysAndSpillsWithoutBounce() throws {
        let screen = try domain()
        let shelf = CGRect(x: screen.minX + screen.width * 0.2, y: screen.minY + screen.height * 0.5,
                           width: screen.width * 0.6, height: screen.height * 0.3)
        let frame = CGRect(x: shelf.minX + shelf.width * 0.3, y: screen.minY + 2, width: 1, height: 1)
        let world = LiquidWorld(windowFrame: frame, screenBounds: screen, obstacles: [shelf])
        var touched = false, flowed = false, spilled = false
        for _ in 0..<480 {
            let old = world.particles[0]
            world.step(h)
            let p = world.particles[0]
            if p.isReleased, p.position.x >= Float(shelf.minX), p.position.x <= Float(shelf.maxX),
                    abs(p.position.y - (Float(shelf.minY) - world.spacing * 0.38)) < 0.001 {
                touched = true
                XCTAssertEqual(p.velocity.y, 0, accuracy: 0.001, "No rigid bounce from a window top")
                if p.velocity.x < -1 { flowed = true }
            }
            if p.isReleased, p.position.x >= Float(shelf.minX), p.position.x <= Float(shelf.maxX), touched {
                XCTAssertGreaterThanOrEqual(p.velocity.y, 0, "A supported drop must never rebound upwards")
            }
            if old.position.y < Float(shelf.minY), p.position.y >= Float(shelf.minY), !touched {
                XCTFail("Particle tunneled through the shelf")
            }
            if touched, p.position.x < Float(shelf.minX), p.position.y > Float(shelf.minY) + 2 { spilled = true }
        }
        XCTAssertTrue(touched)
        XCTAssertTrue(flowed)
        XCTAssertTrue(spilled)
        XCTAssertGreaterThan(world.particles[0].position.y, Float(screen.maxY) - 1)
    }

    func testInitiallyInsideBehindSourceWindowNeverEjectsOntoItsTop() throws {
        let screen = try domain()
        let frame = CGRect(x: screen.midX, y: screen.minY + screen.height * 0.4, width: 1, height: 1)
        let behind = screen.insetBy(dx: screen.width * 0.1, dy: screen.height * 0.1)
        let world = LiquidWorld(windowFrame: frame, screenBounds: screen, obstacles: [behind, frame])
        let start = world.particles[0].position.y
        for _ in 0..<240 {
            world.step(h)
            XCTAssertGreaterThanOrEqual(world.particles[0].position.y, start)
        }
        XCTAssertGreaterThan(world.particles[0].position.y, Float(screen.maxY) - 1)
    }

    func testMovingOrRemovedShelfReleasesSupportWithoutTeleportation() throws {
        let screen = try domain()
        let shelf = CGRect(x: screen.minX, y: screen.midY, width: screen.width, height: screen.height * 0.2)
        let frame = CGRect(x: screen.midX, y: screen.minY + 2, width: 1, height: 1)
        for remove in [false, true] {
            let world = LiquidWorld(windowFrame: frame, screenBounds: screen, obstacles: [shelf])
            var contact = false
            for _ in 0..<240 {
                world.step(h)
                if abs(world.particles[0].position.y - Float(shelf.minY)) < 1, world.particles[0].velocity.y == 0 {
                    contact = true
                    break
                }
            }
            XCTAssertTrue(contact)
            let before = world.particles[0].position
            world.setObstacles([shelf]) // A regular refresh must not move any sample.
            XCTAssertEqual(world.particles[0].position, before)
            world.setObstacles(remove ? [] : [shelf.offsetBy(dx: 0, dy: -screen.height * 0.2)])
            XCTAssertEqual(world.particles[0].position, before)
            advance(world, seconds: 0.15)
            XCTAssertGreaterThan(world.particles[0].position.y, before.y + 5)
        }
    }

    func testSheetPoolsWithFiniteVolumeAndConservesParticleIdentity() throws {
        let screen = try domain()
        let world = LiquidWorld(windowFrame: source(in: screen), screenBounds: screen, obstacles: [])
        let original = world.particles
        advance(world, seconds: 4.5)
        XCTAssertEqual(world.particles.count, original.count)
        XCTAssertEqual(world.particles.map(\.uv), original.map(\.uv))
        XCTAssertEqual(world.particles.map(\.releaseTime), original.map(\.releaseTime))
        XCTAssertEqual(world.alpha, 1)
        XCTAssertTrue(world.particles.allSatisfy(\.isReleased))
        let ys = world.particles.map { $0.position.y }
        XCTAssertGreaterThan(ys.max()!, Float(screen.maxY) - world.spacing)
        XCTAssertGreaterThan(ys.max()! - ys.min()!, world.spacing * 0.2, "The fluid must not collapse into a zero-volume floor line")
        XCTAssertGreaterThan(world.particles.filter { $0.position.y > Float(screen.maxY) - 4 * world.spacing }.count,
                             world.particles.count / 2)
        assertFiniteAndBounded(world)
    }

    func testShelfSheetStabilityAndObstacleRefreshDuringLongRun() throws {
        let screen = try domain(), frame = source(in: screen)
        let shelf = CGRect(x: screen.minX + screen.width * 0.1, y: screen.midY,
                           width: screen.width * 0.75, height: screen.height * 0.3)
        let world = LiquidWorld(windowFrame: frame, screenBounds: screen, obstacles: [shelf])
        let count = world.particles.count
        var observedDrain = false
        for tick in 0..<Int(ceil(world.duration * 120)) {
            if tick.isMultiple(of: 60) { world.setObstacles(tick < 480 ? [shelf] : []) }
            world.step(h)
            if tick.isMultiple(of: 120) { assertFiniteAndBounded(world) }
            XCTAssertEqual(world.alpha, world.isFinished ? 0 : 1)
            if world.particles.contains(where: { $0.position.y > Float(screen.maxY) }) { observedDrain = true }
        }
        XCTAssertTrue(observedDrain)
        XCTAssertTrue(world.isFinished)
        XCTAssertEqual(world.alpha, 0)
        XCTAssertLessThanOrEqual(world.elapsed, world.duration)
        XCTAssertEqual(world.particles.count, count)
        let finalTime = world.elapsed
        world.step(1)
        XCTAssertEqual(world.elapsed, finalTime)
    }

    func testDrainLingersThenLeavesBottomWithoutFadingAtEveryDurationScale() throws {
        let screen = try domain()
        let frame = CGRect(x: screen.midX, y: screen.minY + 2, width: 1, height: 1)
        for scale: Float in [0.25, 3] {
            let world = LiquidWorld(windowFrame: frame, screenBounds: screen, obstacles: [], durationScale: scale)
            advance(world, seconds: 4.4, scale: scale)
            XCTAssertEqual(world.alpha, 1, "Melting and a three-second linger must precede drainage")
            XCTAssertLessThanOrEqual(world.particles[0].position.y, Float(screen.maxY))
            var observedDownwardExit = false
            while !world.isFinished && world.elapsed < world.duration {
                world.step(h * scale)
                XCTAssertEqual(world.alpha, world.isFinished ? 0 : 1, "Drainage must not reduce material opacity")
                if world.particles[0].position.y > Float(screen.maxY) {
                    observedDownwardExit = true
                    XCTAssertGreaterThan(world.elapsed, world.drainStart)
                }
            }
            XCTAssertTrue(world.isFinished)
            XCTAssertEqual(world.alpha, 0)
            XCTAssertTrue(observedDownwardExit)
            XCTAssertGreaterThan(world.particles[0].position.y, Float(screen.maxY) + world.spacing * 1.5)
            XCTAssertLessThanOrEqual(world.elapsed, world.duration)
        }
    }

    func testBottomOutletsDrainFromEdgesProgressivelyAndRetainOpaqueMaterial() throws {
        let screen = try domain()
        let world = LiquidWorld(windowFrame: screen, screenBounds: screen, obstacles: [])
        let identity = world.particles.map(\.uv)
        advance(world, seconds: world.drainStart)
        XCTAssertEqual(world.alpha, 1)
        XCTAssertTrue(world.particles.allSatisfy { $0.position.y <= Float(screen.maxY) })
        var partialTicks = 0
        var firstExit: SIMD2<Float>?
        while !world.isFinished && world.elapsed < world.duration {
            world.step(h)
            let outside = world.particles.filter { $0.position.y > Float(screen.maxY) }
            if firstExit == nil { firstExit = outside.first?.position }
            if !outside.isEmpty && outside.count < world.particles.count {
                partialTicks += 1
                XCTAssertEqual(world.alpha, 1)
            }
            assertFiniteAndBounded(world)
        }
        let exit = try XCTUnwrap(firstExit)
        XCTAssertLessThan(min(exit.x - Float(screen.minX), Float(screen.maxX) - exit.x), Float(screen.width) * 0.25)
        XCTAssertGreaterThan(partialTicks, 120, "The pool must drain gradually, not vanish in a single frame")
        XCTAssertTrue(world.isFinished)
        XCTAssertTrue(world.particles.allSatisfy { $0.position.y > Float(screen.maxY) + world.spacing * 1.5 })
        XCTAssertEqual(world.particles.map(\.uv), identity)
    }

    func testThinSourceAtBottomCannotLeakBeforeOutletsOpen() throws {
        let screen = try domain()
        let frame = CGRect(x: screen.minX + 1, y: screen.maxY - 1, width: screen.width - 2, height: 1)
        let world = LiquidWorld(windowFrame: frame, screenBounds: screen, obstacles: [])
        while world.elapsed + h < world.drainStart {
            world.step(h)
            XCTAssertEqual(world.alpha, 1)
            XCTAssertTrue(world.particles.allSatisfy { $0.position.y <= Float(screen.maxY) })
        }
        advance(world, seconds: world.duration - world.elapsed)
        XCTAssertTrue(world.isFinished)
        assertFiniteAndBounded(world)
    }

    func testTranslationToNegativeScreenOriginsPreservesDynamics() throws {
        let original = try domain()
        let screen = CGRect(x: 0, y: 0, width: original.width, height: original.height)
        let dx = -screen.width * 2, dy = -screen.height * 2
        let negative = screen.offsetBy(dx: dx, dy: dy)
        let a = LiquidWorld(windowFrame: source(in: screen), screenBounds: screen, obstacles: [])
        let b = LiquidWorld(windowFrame: source(in: negative), screenBounds: negative, obstacles: [])
        advance(a, seconds: 0.3)
        advance(b, seconds: 0.3)
        for (p, q) in zip(a.particles, b.particles) {
            XCTAssertEqual(q.position.x - Float(dx), p.position.x, accuracy: 0.01)
            XCTAssertEqual(q.position.y - Float(dy), p.position.y, accuracy: 0.01)
        }
        // After nonlinear pool contacts, floating-point roundoff can change individual
        // neighbors. Verify the physical boundary and conserved identity, not bitwise
        // equivalence between differently translated Float coordinate systems.
        advance(b, seconds: 2.7)
        XCTAssertEqual(b.particles.map(\.uv), a.particles.map(\.uv))
        XCTAssertGreaterThan(b.particles.map { $0.position.y }.max()!, Float(negative.maxY) - b.spacing)
        assertFiniteAndBounded(b)
        advance(b, seconds: b.duration)
        XCTAssertTrue(b.isFinished)
        XCTAssertTrue(b.particles.allSatisfy { $0.position.y > Float(negative.maxY) + b.spacing * 1.5 })
        assertFiniteAndBounded(b)
    }

    func testFullDisplayParticleBudgetRemainsStableThroughPoolingAndDrainage() throws {
        let screen = try desktop().screen
        let world = LiquidWorld(windowFrame: screen, screenBounds: screen, obstacles: [])
        let initialCount = world.particles.count
        XCTAssertGreaterThan(initialCount, 0)
        XCTAssertLessThanOrEqual(initialCount, 1500)
        var observedPool = false
        for tick in 0..<Int(ceil(world.duration * 120)) {
            world.step(h)
            if tick.isMultiple(of: 120) { assertFiniteAndBounded(world) }
            if world.elapsed > world.meltDuration, world.alpha == 1 {
                let floorCount = world.particles.filter { $0.position.y > Float(screen.maxY) - 6 * world.spacing }.count
                if floorCount > initialCount / 2 { observedPool = true }
            }
        }
        XCTAssertTrue(observedPool)
        XCTAssertEqual(world.particles.count, initialCount)
        XCTAssertTrue(world.isFinished)
        XCTAssertEqual(world.alpha, 0)
        XCTAssertLessThanOrEqual(world.elapsed, world.duration)
    }

    func testInvalidDeltaAndLongFrameNeverAccumulateUnboundedCatchup() throws {
        let screen = try domain(), frame = source(in: screen)
        let a = LiquidWorld(windowFrame: frame, screenBounds: screen, obstacles: [])
        let b = LiquidWorld(windowFrame: frame, screenBounds: screen, obstacles: [])
        for dt: Float in [0, -1, .nan, .infinity, -.infinity] { a.step(dt) }
        XCTAssertEqual(a.elapsed, 0)
        XCTAssertEqual(a.particles.map(\.position), b.particles.map(\.position))
        a.step(.greatestFiniteMagnitude)
        b.step(0.1)
        XCTAssertEqual(a.elapsed, 0.1, accuracy: 0.00001)
        a.step(h)
        b.step(h)
        XCTAssertEqual(a.elapsed, b.elapsed)
        XCTAssertEqual(a.particles.map(\.position), b.particles.map(\.position))
        let before = a.elapsed
        a.step(h / 4)
        XCTAssertEqual(a.elapsed, before, "Substep remainders must be retained, not run as variable steps")
        for _ in 0..<3 { a.step(h / 4) }
        XCTAssertEqual(a.elapsed, before + h, accuracy: 0.00001)
    }

    func testInvalidGeometryAndHugeWindowsAreAllocationBounded() throws {
        let screen = try desktop().screen
        let invalid: [CGRect] = [.null, .infinite, .zero,
                                 CGRect(x: CGFloat.nan, y: 0, width: 20, height: 20),
                                 CGRect(x: 0, y: 0, width: -1, height: 20)]
        for rect in invalid {
            let world = LiquidWorld(windowFrame: rect, screenBounds: screen, obstacles: invalid)
            XCTAssertTrue(world.particles.isEmpty)
            XCTAssertTrue(world.isFinished)
            XCTAssertEqual(world.alpha, 0)
            world.step(1)
            XCTAssertEqual(world.elapsed, 0)
            let badScreen = LiquidWorld(windowFrame: screen, screenBounds: rect, obstacles: [])
            XCTAssertTrue(badScreen.isFinished)
        }
        let huge = CGRect(x: -1e100, y: -1e100, width: 2e100, height: 2e100)
        let world = LiquidWorld(windowFrame: huge, screenBounds: screen, obstacles: invalid)
        XCTAssertFalse(world.particles.isEmpty)
        XCTAssertLessThanOrEqual(world.particles.count, 1500)
        XCTAssertTrue(world.spacing.isFinite)
        XCTAssertTrue(world.particles.allSatisfy { $0.uv.x.isFinite && $0.uv.y.isFinite && $0.releaseTime.isFinite })
        assertFiniteAndBounded(world)
        let offscreen = LiquidWorld(windowFrame: screen.offsetBy(dx: screen.width * 4, dy: 0), screenBounds: screen, obstacles: [])
        XCTAssertTrue(offscreen.isFinished)
    }
}