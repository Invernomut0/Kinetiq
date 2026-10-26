// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import XCTest
import simd
@testable import KinetiqCore

/// Real AppKit-rendered windows and Dock icons go through the extractor, the tiling and the physics world.
@MainActor
final class ChaosTests: XCTestCase {
    private static let fixture = ChaosFixture.scene()!
    private static let overlapping = ChaosFixture.scene(extra: true)!

    private func world(lifetime: Double = 25, interval: Double = 700, intensity: Double = 1, seed: UInt64 = 7, automatic: Bool = true,
                       overlapping: Bool = false) -> ChaosWorld {
        let source = overlapping ? Self.overlapping : Self.fixture
        let world = ChaosWorld(seeds: source.scene.seeds, size: source.screen,
                               settings: ChaosSettings(eventInterval: interval, lifetime: lifetime, intensity: intensity, seed: seed, speed: 1))
        world.automaticEvents = automatic
        return world
    }

    private func run(_ world: ChaosWorld, seconds: Float) {
        for _ in 0..<Int(seconds * 60) { world.step(dt: 1 / 60) }
    }

    // MARK: - Extraction and tiling

    func testFindsLettersButtonsAndDockIcons() {
        let seeds = Self.fixture.scene.seeds
        let letters = ChaosFixture.lines.joined().filter { !$0.isWhitespace && $0 != "," }.count + "Kinetiq".count
        let glyphs = seeds.filter { $0.kind == .glyph }.count
        XCTAssertGreaterThan(glyphs, letters * 7 / 10, "found \(glyphs) glyphs for \(letters) letters")
        XCTAssertLessThan(glyphs, letters * 13 / 10)
        XCTAssertGreaterThanOrEqual(seeds.filter { $0.kind == .button }.count, 3)
        XCTAssertGreaterThanOrEqual(seeds.filter { $0.kind == .icon }.count, ChaosFixture.dockApps.count - 2)
    }

    func testTilesPutSideBySideCoverTheWholeWindow() throws {
        let window = try XCTUnwrap(ChaosFixture.window())
        let tiles = ChaosTiling.tiles(of: window.image, size: window.size, tile: 48)
        let windowArea = Float(window.size.width * window.size.height)
        XCTAssertEqual(tiles.reduce(0) { $0 + $1.area }, windowArea, accuracy: windowArea * 0.01)
        let toPoints = SIMD2(Float(window.size.width), Float(window.size.height))
        for t in tiles {
            for (p, u) in [(t.a, t.ua), (t.b, t.ub), (t.c, t.uc)] {
                XCTAssertTrue(u.x >= 0 && u.x <= 1 && u.y >= 0 && u.y <= 1)
                XCTAssertEqual(p.x, u.x * toPoints.x, accuracy: 0.01)
                XCTAssertEqual(p.y, u.y * toPoints.y, accuracy: 0.01)
            }
            XCTAssertGreaterThan(t.area, 1, "no degenerate triangles")
        }
    }

    func testTheTilesAreIrregularTriangles() throws {
        let window = try XCTUnwrap(ChaosFixture.window())
        let tiles = ChaosTiling.tiles(of: window.image, size: window.size, tile: 48)
        func axisAligned(_ t: ChaosTile) -> Bool {
            [(t.a, t.b), (t.b, t.c), (t.c, t.a)].contains { abs($0.0.x - $0.1.x) < 0.01 || abs($0.0.y - $0.1.y) < 0.01 }
        }
        let inner = tiles.filter { t in [t.a, t.b, t.c].allSatisfy { $0.x > 1 && $0.y > 1 && $0.x < Float(window.size.width) - 1 && $0.y < Float(window.size.height) - 1 } }
        XCTAssertGreaterThan(inner.count, 20)
        XCTAssertLessThan(inner.filter(axisAligned).count, inner.count / 10, "no rectangles: the corners are moved at random")
        let areas = tiles.map(\.area)
        XCTAssertGreaterThan(areas.max()! / areas.min()!, 1.5, "triangles of different sizes")
        XCTAssertEqual(ChaosTiling.tiles(of: window.image, size: window.size, tile: 48).map(\.a), tiles.map(\.a), "the same window breaks the same way")
    }

    func testAShapeKnowsWhichPointsAreInside() {
        let shape = ChaosShape(a: SIMD2(-10, -10), b: SIMD2(20, -10), c: SIMD2(-10, 20), ua: .zero, ub: .zero, uc: .zero)
        XCTAssertTrue(shape.contains(SIMD2(0, 0)))
        XCTAssertTrue(shape.contains(SIMD2(-9, -9)))
        XCTAssertFalse(shape.contains(SIMD2(15, 15)))
        XCTAssertFalse(shape.contains(SIMD2(-12, 0)))
        XCTAssertEqual(shape.area, 450, accuracy: 0.01)
    }

    func testTransparentTrianglesAreLeftOut() throws {
        let dock = try XCTUnwrap(ChaosFixture.dock())
        let tiles = ChaosTiling.tiles(of: dock.image, size: dock.size, tile: 20)
        let cells = Int((dock.size.width / 20).rounded()) * Int((dock.size.height / 20).rounded())
        XCTAssertEqual(tiles.count, cells * 2, "the dock bar is painted everywhere")

        let w = 200, h = 200
        let context = try XCTUnwrap(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))   // bottom-left in CG, i.e. the lower left quarter of the picture
        let half = try XCTUnwrap(context.makeImage())
        let kept = ChaosTiling.tiles(of: half, size: CGSize(width: 200, height: 200), tile: 50)
        XCTAssertGreaterThan(kept.count, 0)
        XCTAssertLessThan(kept.count, 24, "the unpainted area is mostly left out (of 32 triangles)")
        for t in kept { XCTAssertTrue(min(t.a.x, t.b.x, t.c.x) < 110 && max(t.a.y, t.b.y, t.c.y) > 90) }
    }

    func testTheSceneHasShardsAndObjects() {
        let scene = Self.fixture.scene
        XCTAssertEqual(scene.seeds.filter { $0.kind == .shard }.count, scene.tiles.count)
        XCTAssertEqual(scene.seeds.filter { $0.kind != .shard }.count, scene.sprites.count)
        XCTAssertEqual(scene.pictures.count, 2)
        for s in scene.seeds where s.kind != .shard { XCTAssertLessThan(s.sprite, scene.sprites.count) }
    }

    // MARK: - Events

    func testNothingMovesBeforeTheFirstEvent() {
        let world = world(automatic: false)
        run(world, seconds: 2)
        XCTAssertEqual(world.looseCount, 0)
        XCTAssertEqual(world.intactFraction, 1)
        XCTAssertTrue(world.bodies.allSatisfy { $0.pos == $0.home })
    }

    func testABombBreaksShardsIntoFragmentsAndThrowsPieces() {
        let world = world(intensity: 2, automatic: false)
        XCTAssertTrue(world.run(.bomb))
        run(world, seconds: 1)
        XCTAssertGreaterThan(world.bodies.count, world.originalCount, "shards near the blast break into fragments")
        XCTAssertTrue(world.bodies.contains { $0.isChild && $0.state == .loose })
        XCTAssertGreaterThan(world.looseCount, 10)
        XCTAssertLessThan(world.intactFraction, 1)
        XCTAssertFalse(world.puffs.isEmpty, "flames, sparks and smoke")
    }

    func testFragmentsAreTrianglesOfTheirParent() {
        let world = world(intensity: 2, automatic: false)
        world.run(.bomb)
        run(world, seconds: 0.2)
        let fragments = world.bodies.filter { $0.isChild }
        XCTAssertFalse(fragments.isEmpty)
        XCTAssertEqual(fragments.count % 3, 0, "a shard breaks into three")
        for b in fragments {
            XCTAssertGreaterThan(b.shape.area, 1)
            for u in [b.shape.ua, b.shape.ub, b.shape.uc] { XCTAssertTrue(u.x >= 0 && u.x <= 1 && u.y >= 0 && u.y <= 1) }
        }
        let intact = world.bodies.prefix(world.originalCount).filter { $0.kind == .shard && $0.state == .gone }
        let parentArea = intact.reduce(Float(0)) { $0 + $1.shape.area }
        XCTAssertEqual(fragments.reduce(Float(0)) { $0 + $1.shape.area }, parentArea, accuracy: parentArea * 0.02, "the fragments add up to the broken shards")
    }

    func testAButtonBlinksThenExplodesAndHurtsItsNeighbours() {
        let world = world(automatic: false)
        XCTAssertTrue(world.run(.buttonBlast))
        XCTAssertTrue(world.bodies.contains { $0.state == .fuse })
        run(world, seconds: 0.4)
        XCTAssertTrue(world.bodies.contains { $0.state == .fuse && $0.tint.w > 0 }, "blinks red before it explodes")
        run(world, seconds: 2)
        XCTAssertFalse(world.bodies.contains { $0.state == .fuse })
        XCTAssertTrue(world.bodies.contains { $0.state == .gone }, "the exploded piece is removed")
        XCTAssertFalse(world.puffs.isEmpty && world.looseCount == 0)
    }

    func testLetterShedReleasesLettersOnly() {
        let world = world(automatic: false)
        XCTAssertTrue(world.run(.letterShed))
        run(world, seconds: 2)
        let moved = world.bodies.filter { $0.state == .loose }
        XCTAssertFalse(moved.isEmpty)
        XCTAssertTrue(moved.allSatisfy { $0.kind == .glyph })
    }

    func testACrackLoosensShardsAndTheLettersOnThem() {
        let world = world(automatic: false)
        XCTAssertTrue(world.run(.shardCrumble))
        run(world, seconds: 3)
        XCTAssertTrue(world.bodies.contains { $0.kind == .shard && $0.state == .loose })
        let fallenShards = world.bodies.filter { $0.kind == .shard && $0.state == .loose }
        XCTAssertTrue(fallenShards.allSatisfy { $0.pos.y > $0.home.y || $0.angle != 0 })
    }

    func testTheSpeedSettingSlowsEverythingDown() {
        let source = Self.fixture
        func make(_ speed: Double) -> ChaosWorld {
            let w = ChaosWorld(seeds: source.scene.seeds, size: source.screen, settings: ChaosSettings(eventInterval: 1000, lifetime: 30, seed: 5, speed: speed))
            w.automaticEvents = false
            return w
        }
        let normal = make(1), slow = make(0.4)
        normal.run(.bomb); slow.run(.bomb)
        run(normal, seconds: 1.5)
        run(slow, seconds: 1.5)
        let fall = { (w: ChaosWorld) in w.bodies.filter { $0.state == .loose }.map { $0.pos.y - $0.home.y }.reduce(0, +) / Float(max(w.looseCount, 1)) }
        XCTAssertGreaterThan(fall(normal), fall(slow) + 20, "in slow motion the pieces have fallen less far")
        XCTAssertEqual(ChaosSettings(speed: 9).speed, 1.5, accuracy: 0.001)
    }

    func testTheAutomaticEventsFollowTheInterval() {
        let fast = world(interval: 200)
        let slow = world(interval: 2500)
        run(fast, seconds: 10)
        run(slow, seconds: 10)
        XCTAssertGreaterThan(fast.eventCount, 12, "an event every ~200 ms until nothing is left to break")
        XCTAssertLessThan(slow.eventCount, 8)
        XCTAssertGreaterThan(fast.eventCount, slow.eventCount * 2)
    }

    // MARK: - Physics

    func testFallenPiecesPileUpAtTheBottomOfTheScreen() {
        let world = world(lifetime: 120, interval: 150, intensity: 1.5)
        run(world, seconds: 25)
        let loose = world.bodies.filter { $0.state == .loose }
        XCTAssertGreaterThan(loose.count, 100)
        for b in loose {
            XCTAssertLessThanOrEqual(b.pos.y + b.radius, world.size.y + 1)
            XCTAssertGreaterThanOrEqual(b.pos.x - b.radius, -1)
            XCTAssertLessThanOrEqual(b.pos.x + b.radius, world.size.x + 1)
        }
        let resting = loose.filter { $0.asleep }
        XCTAssertFalse(resting.isEmpty, "settled pieces fall asleep")
        XCTAssertGreaterThan(loose.filter { $0.pos.y > world.size.y - 40 }.count, 20, "a layer of pieces lies on the floor")
        XCTAssertTrue(loose.contains { $0.pos.y < world.size.y - 60 }, "and more pieces stack on it")
    }

    func testPiecesFadeAwayAfterTheirLifetime() {
        let world = world(lifetime: 4, automatic: false)
        world.run(.letterShed)
        world.run(.bomb)
        run(world, seconds: 2)
        XCTAssertGreaterThan(world.looseCount, 5)
        XCTAssertTrue(world.bodies.filter { $0.state == .loose }.allSatisfy { $0.alpha > 0.2 || $0.age > 2.5 })
        run(world, seconds: 3.5)
        XCTAssertTrue(world.bodies.filter { $0.state == .loose }.contains { $0.alpha < 1 } || world.looseCount == 0)
        run(world, seconds: 3)
        XCTAssertEqual(world.looseCount, 0, "everything that fell has vanished")
        XCTAssertTrue(world.bodies.allSatisfy { $0.state != .loose })
        XCTAssertEqual(world.bodies.count, world.originalCount, "fragments are dropped")
    }

    func testLooseCountStaysBoundedUnderHeavyLoad() {
        let world = world(lifetime: 120, interval: 100, intensity: 2.5)
        run(world, seconds: 25)
        XCTAssertLessThan(world.bodies.count, world.maxBodies)
        XCTAssertLessThanOrEqual(world.puffs.count, 2500)
    }

    func testPiecesBehindAnotherWindowAreOccluded() {
        let world = world(automatic: false, overlapping: true)
        let source = Self.overlapping.scene
        let groupCount = source.pictures.count
        XCTAssertEqual(groupCount, 3)
        // Window 1 (group 1) covers part of window 0.
        let hidden = (0..<world.originalCount).filter { world.bodies[$0].group == 0 && world.isOccluded($0) }
        let visibleFront = (0..<world.originalCount).filter { world.bodies[$0].group == 1 && world.isOccluded($0) }
        XCTAssertFalse(hidden.isEmpty)
        XCTAssertTrue(visibleFront.isEmpty, "nothing covers the front window")
        for i in hidden {
            let p = world.bodies[i].home
            XCTAssertTrue(p.x > 300 - 50 && p.y > 150 - 50, "occluded pieces lie under the front window")
        }
    }

    func testBlastsDoNotReleaseWhatIsHiddenBehindAWindow() {
        let world = world(intensity: 2.5, automatic: false, overlapping: true)
        let hidden = Set((0..<world.originalCount).filter { world.bodies[$0].group == 0 && world.isOccluded($0) })
        for _ in 0..<6 { world.run(.bomb) }
        for _ in 0..<6 { world.run(.letterShed) }
        run(world, seconds: 1.5)
        // A piece may be released only if its front window piece is not there anymore; right at the start all hidden pieces stay.
        let released = hidden.filter { world.bodies[$0].state != .attached && world.bodies[$0].state != .fuse }
        for i in released {
            XCTAssertFalse(world.isOccluded(i), "a hidden piece only comes loose once nothing is in front of it")
        }
    }

    func testTheSameSeedReplaysTheSameRun() {
        let a = world(seed: 42), b = world(seed: 42)
        run(a, seconds: 8)
        run(b, seconds: 8)
        XCTAssertEqual(a.bodies.count, b.bodies.count)
        XCTAssertEqual(a.eventCount, b.eventCount)
        for (x, y) in zip(a.bodies, b.bodies) { XCTAssertEqual(x.pos, y.pos) }
        let c = world(seed: 43)
        run(c, seconds: 8)
        XCTAssertNotEqual(a.bodies.map(\.pos), c.bodies.map(\.pos))
    }

    func testTheDesktopIsExhaustedWhenMostOfItIsGone() {
        let world = world(lifetime: 3, interval: 100, intensity: 2.5)
        XCTAssertFalse(world.isExhausted)
        run(world, seconds: 60)
        XCTAssertLessThan(world.intactFraction, 0.5, "the desktop has been destroyed")
        if world.intactFraction < 0.07 { XCTAssertTrue(world.isExhausted || world.looseCount >= 40) }
    }
}
