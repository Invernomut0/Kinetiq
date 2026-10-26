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
        for t in tiles {
            XCTAssertGreaterThanOrEqual(t.verts.count, 3)
            XCTAssertGreaterThan(t.area, 4, "no degenerate pieces")
            for p in t.verts {
                XCTAssertTrue(p.x >= -0.01 && p.y >= -0.01 && p.x <= Float(window.size.width) + 0.01 && p.y <= Float(window.size.height) + 0.01)
            }
        }
    }

    func testTheTilesAreIrregularConvexPolygons() throws {
        let window = try XCTUnwrap(ChaosFixture.window())
        let tiles = ChaosTiling.tiles(of: window.image, size: window.size, tile: 48)
        for t in tiles {
            var signs = Set<Bool>()
            for i in t.verts.indices {
                let a = t.verts[i], b = t.verts[(i + 1) % t.verts.count], c = t.verts[(i + 2) % t.verts.count]
                let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
                if abs(cross) > 1e-3 { signs.insert(cross > 0) }
            }
            XCTAssertLessThanOrEqual(signs.count, 1, "convex")
        }
        let inner = tiles.filter { t in t.verts.allSatisfy { $0.x > 1 && $0.y > 1 && $0.x < Float(window.size.width) - 1 && $0.y < Float(window.size.height) - 1 } }
        XCTAssertGreaterThan(inner.count, 10)
        XCTAssertGreaterThan(Set(inner.map(\.verts.count)).count, 1, "pieces with different numbers of sides")
        XCTAssertGreaterThanOrEqual(inner.filter { $0.verts.count >= 5 }.count, inner.count / 3, "mostly more than four sides")
        let areas = tiles.map(\.area)
        XCTAssertGreaterThan(areas.max()! / areas.min()!, 1.8, "pieces of different sizes")
        XCTAssertEqual(ChaosTiling.tiles(of: window.image, size: window.size, tile: 48).map(\.verts), tiles.map(\.verts), "the same window breaks the same way")
    }

    func testAPolygonKnowsWhichPointsAreInside() {
        let polygon = ChaosPolygon(verts: [SIMD2(-10, -10), SIMD2(20, -10), SIMD2(-10, 20)], uvOffset: .zero, uvScale: SIMD2(1, 1))
        XCTAssertTrue(polygon.contains(SIMD2(0, 0)))
        XCTAssertTrue(polygon.contains(SIMD2(-9, -9)))
        XCTAssertFalse(polygon.contains(SIMD2(15, 15)))
        XCTAssertFalse(polygon.contains(SIMD2(-12, 0)))
        XCTAssertEqual(polygon.area, 450, accuracy: 0.01)
    }

    func testVoronoiCellsShareTheSquareBetweenThem() {
        let square: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(100, 0), SIMD2(100, 100), SIMD2(0, 100)]
        let sites: [SIMD2<Float>] = [SIMD2(20, 30), SIMD2(70, 20), SIMD2(50, 80), SIMD2(90, 70)]
        var total: Float = 0
        for i in sites.indices {
            let cell = ChaosGeometry.cell(of: i, in: sites, bounds: square)
            XCTAssertTrue(ChaosGeometry.contains(cell, sites[i]), "each cell holds its own site")
            total += ChaosGeometry.area(cell)
        }
        XCTAssertEqual(total, 10_000, accuracy: 0.5)
    }

    func testTransparentChunksAreLeftOut() throws {
        let dock = try XCTUnwrap(ChaosFixture.dock())
        let tiles = ChaosTiling.tiles(of: dock.image, size: dock.size, tile: 20)
        let cells = Int((dock.size.width / 20).rounded()) * Int((dock.size.height / 20).rounded())
        XCTAssertEqual(tiles.count, cells, "the dock bar is painted everywhere")

        let w = 200, h = 200
        let context = try XCTUnwrap(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))   // bottom-left in CG, i.e. the lower left quarter of the picture
        let half = try XCTUnwrap(context.makeImage())
        let kept = ChaosTiling.tiles(of: half, size: CGSize(width: 200, height: 200), tile: 50)
        XCTAssertGreaterThan(kept.count, 0)
        XCTAssertLessThan(kept.count, 12, "the unpainted area is mostly left out (of 16 chunks)")
        for t in kept { XCTAssertTrue(t.verts.map(\.x).min()! < 110 && t.verts.map(\.y).max()! > 90) }
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

    func testFragmentsAreCracksOfTheirParentPieces() {
        let world = world(intensity: 2, automatic: false)
        let source = Self.fixture.scene
        world.run(.bomb)
        let fragments = world.bodies.filter { $0.isChild }
        XCTAssertGreaterThanOrEqual(fragments.count, 3)
        for b in fragments {
            let poly = world.polygons[Int(b.polygon)]
            XCTAssertGreaterThanOrEqual(poly.verts.count, 3)
            XCTAssertGreaterThan(poly.area, 6)
            // The picture on a fragment is the same picture that was on the parent at that place.
            let frame = source.frames[b.group]
            for v in poly.verts {
                let uv = poly.uv(v)
                XCTAssertEqual(uv.x * Float(frame.width) + Float(frame.minX), b.home.x + v.x, accuracy: 0.05)
                XCTAssertEqual(uv.y * Float(frame.height) + Float(frame.minY), b.home.y + v.y, accuracy: 0.05)
            }
        }
        let parents = world.bodies.prefix(world.originalCount).filter { $0.kind == .shard && $0.state == .gone }
        let parentArea = parents.reduce(Float(0)) { $0 + world.polygons[Int($1.polygon)].area }
        let fragmentArea = fragments.reduce(Float(0)) { $0 + world.polygons[Int($1.polygon)].area }
        XCTAssertEqual(fragmentArea, parentArea, accuracy: parentArea * 0.05, "the fragments add up to the broken pieces")
        XCTAssertLessThan(fragmentArea / Float(fragments.count), parentArea / Float(parents.count) / 2, "the fragments are much smaller than the pieces")
        XCTAssertGreaterThan(Set(fragments.map { world.polygons[Int($0.polygon)].verts.count }).count, 1, "fragments with different numbers of sides")
    }

    func testASegmentIsClippedToThePartInsideAPolygon() {
        let square: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(10, 0), SIMD2(10, 10), SIMD2(0, 10)]
        let inside = ChaosGeometry.clipSegment(SIMD2(-5, 5), SIMD2(15, 5), to: square)
        XCTAssertEqual(inside?.0.x ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(inside?.1.x ?? -1, 10, accuracy: 0.001)
        XCTAssertNil(ChaosGeometry.clipSegment(SIMD2(-5, -5), SIMD2(-1, 20), to: square))
        let whole = ChaosGeometry.clipSegment(SIMD2(2, 2), SIMD2(8, 7), to: square.reversed())
        XCTAssertEqual(whole?.0 ?? .zero, SIMD2(2, 2))
        XCTAssertEqual(whole?.1 ?? .zero, SIMD2(8, 7))
    }

    func testABlastLeavesCracksOnThePiecesAroundIt() {
        let world = world(intensity: 2, automatic: false)
        world.run(.bomb)
        let cracked = world.bodies.filter { $0.crack >= 0 }
        XCTAssertGreaterThan(cracked.count, 2, "the neighbours of the blast are cracked")
        for b in cracked {
            let poly = world.polygons[Int(b.polygon)]
            let segments = world.crackSets[Int(b.crack)]
            XCTAssertFalse(segments.isEmpty)
            for s in segments {
                for p in [SIMD2(s.x, s.y), SIMD2(s.z, s.w)] {
                    XCTAssertTrue(p.x >= poly.boundsMin.x - 0.01 && p.x <= poly.boundsMax.x + 0.01 && p.y >= poly.boundsMin.y - 0.01 && p.y <= poly.boundsMax.y + 0.01,
                                  "cracks stay inside the piece they are on")
                }
            }
        }
        XCTAssertTrue(cracked.contains { $0.state == .attached || $0.state == .pending }, "some pieces hold with their cracks")
    }

    func testACrumblingWindowGetsCracksToo() {
        let world = world(automatic: false)
        world.run(.shardCrumble)
        XCTAssertTrue(world.bodies.contains { $0.crack >= 0 })
    }

    func testBrokenEdgesAreScorchedAndGlowUntilTheyCool() {
        let world = world(intensity: 2, automatic: false)
        world.run(.bomb)
        let fragments = world.bodies.filter { $0.isChild }
        XCTAssertFalse(fragments.isEmpty)
        XCTAssertTrue(fragments.allSatisfy { $0.burn > 0.4 && $0.heat == 1 }, "charred and hot")
        run(world, seconds: 5)
        let later = world.bodies.filter { $0.isChild && $0.state == .loose }
        XCTAssertFalse(later.isEmpty)
        XCTAssertTrue(later.allSatisfy { $0.heat < 0.3 && $0.burn > 0.4 }, "the glow fades, the char stays")
    }

    func testBlastsMakeSparksAndDust() {
        let world = world(automatic: false)
        world.run(.bomb)
        run(world, seconds: 0.3)
        let kinds = world.puffs.reduce(into: [ChaosPuff.Kind: Int]()) { $0[$1.kind, default: 0] += 1 }
        XCTAssertGreaterThan(kinds[.spark] ?? 0, 30, "sparks")
        XCTAssertGreaterThan(kinds[.mote] ?? 0, 30, "fine dust in the air")
        XCTAssertGreaterThan(kinds[.dust] ?? 0, 3, "dust from the breaking window")
    }

    func testADockIconExplodesFarHarderThanAButton() {
        let source = Self.fixture
        func explosion(of pick: (ChaosBody) -> Bool) -> (reach: Float, puffs: Int, flash: Float, shake: Float) {
            let w = ChaosWorld(seeds: source.scene.seeds, size: source.screen, settings: ChaosSettings(intensity: 1, seed: 11, speed: 1))
            w.automaticEvents = false
            let i = w.bodies.firstIndex(where: pick)!
            w.detonate(i)
            run(w, seconds: 0.12)   // the fuse is 0.05 s: the blast has just gone off
            let puffs = w.puffs.count, flash = w.flash, shake = w.shake
            return (w.largestBlastRadius, puffs, flash, shake)
        }
        let dock = explosion { $0.isDock && $0.kind == .icon }
        let button = explosion { !$0.isDock && $0.kind == .button }
        XCTAssertGreaterThan(dock.reach, button.reach * 2.5, "the blast reaches much farther: \(dock.reach) against \(button.reach)")
        XCTAssertGreaterThan(dock.puffs, button.puffs * 2, "far more flames, smoke and sparks")
        XCTAssertGreaterThan(dock.flash, 0.2, "a flash of light")
        XCTAssertGreaterThan(dock.shake, button.shake + 5, "the screen shakes")
    }

    func testTheNukeIsAContainedBlastWithAFlashAShockWaveAndAMushroomCloud() {
        let world = world(automatic: false)
        let total = (0..<world.originalCount).filter { !world.isOccluded($0) }.count
        XCTAssertFalse(world.nukeSpent)
        XCTAssertTrue(world.run(.nuke))
        XCTAssertTrue(world.nukeSpent)
        XCTAssertFalse(world.run(.nuke), "only once")
        run(world, seconds: 0.12)
        XCTAssertGreaterThan(world.flash, 0.3, "a flash of light")
        XCTAssertLessThan(world.flash, 0.6, "but not a whiteout")
        XCTAssertGreaterThan(world.shake, 3)
        XCTAssertLessThan(world.shake, 12)
        run(world, seconds: 0.5)
        let early = Set(world.puffs.map { "\($0.kind)" })
        XCTAssertTrue(early.isSuperset(of: ["flame", "spark", "dust"]), "fireball, embers and a ring of dust at the start")
        var peakLoose = 0
        for _ in 0..<(3 * 60) {
            world.step(dt: 1 / 60)
            peakLoose = max(peakLoose, world.looseCount)
        }
        let c = world.nukeCenter
        XCTAssertGreaterThan(world.puffs.count, 80, "stem, cap and embers")
        XCTAssertLessThan(world.puffs.count, 1500, "a moderate number of particles")
        XCTAssertTrue(world.puffs.contains { $0.kind == .smoke && abs($0.pos.x - c.x) < 200 && $0.pos.y < world.size.y * 0.7 }, "the cloud rises above the ground burst")
        let intact = (0..<world.originalCount).filter { world.bodies[$0].state == .attached }.count
        XCTAssertGreaterThan(intact, total / 2, "most of the desktop is still there")
        XCTAssertLessThan(intact, total, "but the blast has hit what was near it")
        XCTAssertLessThan(peakLoose, 700, "a limited number of pieces comes loose")
        // Nothing farther than the reach of the wave is touched.
        for b in world.bodies where b.state != .attached && !b.isChild && simd_distance(b.home, c) > world.nukeReach + b.radius + 1 {
            XCTFail("a piece \(simd_distance(b.home, c)) points away was hit; the reach is \(world.nukeReach)")
        }
        let hit = world.bodies.filter { $0.state == .loose }
        XCTAssertTrue(hit.allSatisfy { $0.burn > 0.3 }, "all of it is charred")
        run(world, seconds: 12)
        XCTAssertEqual(world.flash, 0, accuracy: 0.001)
        XCTAssertEqual(world.shake, 0, accuracy: 0.001)
    }

    func testTheNukeComesRarelyAndOnlyOncePerSession() {
        let world = world(lifetime: 4, interval: 150)
        run(world, seconds: 20)
        XCTAssertFalse(world.nukeSpent, "not in the first 25 seconds")
        // One session: the nuke does not repeat after it has been used.
        let again = ChaosWorld(seeds: Self.fixture.scene.seeds, size: Self.fixture.screen, settings: ChaosSettings(seed: 3, speed: 1))
        again.nukeSpent = true
        XCTAssertFalse(again.run(.nuke))
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
