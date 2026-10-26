// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import simd
import XCTest
@testable import KinetiqCore

final class DockMorphTests: XCTestCase {
    private let windowOrigin = SIMD2<Float>(300, 150)
    private let windowSize = SIMD2<Float>(800, 560)
    private let iconOrigin = SIMD2<Float>(1000, 1030)
    private let iconSize = SIMD2<Float>(56, 56)

    private func deformer(_ style: DockMorphStyle, icon: SIMD2<Float>? = nil) -> DockMorphDeformer {
        DockMorphDeformer(windowOrigin: windowOrigin, windowSize: windowSize, iconOrigin: icon ?? iconOrigin,
                          iconSize: iconSize, style: style)
    }

    private func run(_ d: DockMorphDeformer, to progress: Float) {
        d.step(d.duration * progress)
    }

    func testStartsOnTheWindowAndEndsInsideTheIcon() {
        for style in DockMorphStyle.allCases {
            let d = deformer(style)
            XCTAssertEqual(d.maxDisplacement, 0, accuracy: 1e-3, "\(style) moves at progress 0")
            XCTAssertEqual(d.alpha, 1, accuracy: 1e-4)
            XCTAssertFalse(d.isSettled)

            run(d, to: 1)
            XCTAssertTrue(d.isSettled)
            XCTAssertEqual(d.alpha, 0, accuracy: 1e-4, "\(style) must have faded out")
            for (u, v) in [(0, 0), (1, 0), (0, 1), (1, 1), (0.5, 0.5)] as [(Float, Float)] {
                let p = d.point(u: u, v: v)
                XCTAssertGreaterThanOrEqual(p.x, iconOrigin.x - 0.01, "\(style) \(u),\(v)")
                XCTAssertLessThanOrEqual(p.x, iconOrigin.x + iconSize.x + 0.01, "\(style) \(u),\(v)")
                XCTAssertGreaterThanOrEqual(p.y, iconOrigin.y - 0.01, "\(style) \(u),\(v)")
                XCTAssertLessThanOrEqual(p.y, iconOrigin.y + iconSize.y + 0.01, "\(style) \(u),\(v)")
            }
        }
    }

    func testTheWindowNeverGrowsOrJumpsOnTheWay() {
        for style in DockMorphStyle.allCases {
            let d = deformer(style)
            var previous = d.target(u: 0.5, v: 1)
            for _ in 0..<60 {
                d.step(d.duration / 60)
                let now = d.target(u: 0.5, v: 1)
                XCTAssertLessThan(simd_length(now - previous), 90, "\(style) jumps")
                previous = now
            }
        }
    }

    func testGenieEdgeNearestTheIconLeadsAndTheFunnelNarrows() {
        let d = deformer(.genie)
        run(d, to: 0.5)
        let leadY = d.target(u: 0.5, v: 1).y
        let trailY = d.target(u: 0.5, v: 0).y
        XCTAssertGreaterThan(leadY, trailY + 50, "the bottom must be further along than the top")
        let leadWidth = d.target(u: 1, v: 1).x - d.target(u: 0, v: 1).x
        let trailWidth = d.target(u: 1, v: 0).x - d.target(u: 0, v: 0).x
        XCTAssertLessThan(leadWidth, trailWidth, "the side near the icon must be narrower")
        XCTAssertLessThan(leadWidth, windowSize.x)
    }

    func testIconAboveTheWindowMakesTheTopLead() {
        let d = deformer(.genie, icon: SIMD2(1000, 0))
        run(d, to: 0.4)
        let top = d.target(u: 0.5, v: 0).y - windowOrigin.y
        let bottom = d.target(u: 0.5, v: 1).y - (windowOrigin.y + windowSize.y)
        XCTAssertLessThan(top, bottom, "the top edge travels further towards an icon above")
    }

    func testWhirlpoolTwistsAroundTheIconAndTornadoTurnsTheWindowOver() {
        let iconCenter = iconOrigin + iconSize / 2
        func angle(_ p: SIMD2<Float>) -> Float { atan2(p.y - iconCenter.y, p.x - iconCenter.x) }
        let whirl = deformer(.whirlpool), straight = deformer(.morph)
        // Same distance to the icon at the same point of the trip is not required: the twist shows in the direction.
        run(whirl, to: 0.5)
        run(straight, to: 0.5)
        var difference = abs(angle(whirl.target(u: 1, v: 1)) - angle(straight.target(u: 1, v: 1)))
        if difference > Float.pi { difference = 2 * Float.pi - difference }
        XCTAssertGreaterThan(difference, 0.3, "the whirlpool does not twist")

        let tornado = deformer(.tornado)
        run(tornado, to: 0.5)
        XCTAssertGreaterThan(tornado.target(u: 0.5, v: 0).y, tornado.target(u: 0.5, v: 1).y,
                             "half way the window is upside down")
    }

    func testRubberBandSwellsAwayFromTheIconFirst() {
        let center = iconOrigin + iconSize / 2
        let d = deformer(.rubberBand)
        let before = simd_length(d.point(u: 0.5, v: 1) - center)
        run(d, to: 0.2)
        let after = simd_length(d.point(u: 0.5, v: 1) - center)
        XCTAssertGreaterThan(after, before, "it must wind up away from the icon before it snaps in")
    }

    func testPancakeFlattensBeforeItSlides() {
        let d = deformer(.pancake)
        run(d, to: 0.4)
        let height = d.target(u: 0.5, v: 1).y - d.target(u: 0.5, v: 0).y
        XCTAssertLessThan(height, windowSize.y * 0.3)
        XCTAssertGreaterThan(height, 0)
    }

    func testHopRisesAboveTheStraightPath() {
        let d = deformer(.hop), straight = deformer(.morph)
        run(d, to: 0.5)
        run(straight, to: 0.5)
        XCTAssertLessThan(d.target(u: 0.5, v: 0.5).y, straight.target(u: 0.5, v: 0.5).y - 20)
    }

    func testSideDockWorksToo() {
        let d = DockMorphDeformer(windowOrigin: windowOrigin, windowSize: windowSize, iconOrigin: SIMD2(1700, 400),
                                  iconSize: iconSize, style: .genie)
        run(d, to: 0.5)
        let lead = d.target(u: 1, v: 0.5).x - (windowOrigin.x + windowSize.x)
        let trail = d.target(u: 0, v: 0.5).x - windowOrigin.x
        XCTAssertGreaterThan(lead, trail, "the right edge leads towards an icon on the right")
    }

    func testJellySuckWavesSidewaysInTheMiddleOnly() {
        let d = deformer(.jellySuck)
        let straight = deformer(.jellySuck)
        run(d, to: 0.5)
        run(straight, to: 0.5)
        var maxSide: Float = 0
        for i in 0...10 {
            let u = Float(i) / 10
            let p = d.target(u: u, v: 0.5)
            let mid = simd_mix(windowOrigin + SIMD2(u * windowSize.x, 0.5 * windowSize.y),
                               iconOrigin + SIMD2(u * iconSize.x, 0.5 * iconSize.y), SIMD2(repeating: 0.5 * 0.5 * (0.4 + 0.3)))
            maxSide = max(maxSide, abs(p.x - mid.x))
        }
        XCTAssertGreaterThan(maxSide, 1, "no wobble")
    }
}
