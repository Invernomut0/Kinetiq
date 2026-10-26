// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import simd
import XCTest
@testable import KinetiqCore

final class TiltTests: XCTestCase {
    func testAtRestNothingMoves() {
        let p = SIMD2<Float>(130, 70)
        XCTAssertEqual(Tilt.project(p, pivot: SIMD2(100, 100), angles: .zero), p)
        XCTAssertEqual(Tilt.target(for: .zero), .zero)
    }

    func testPivotStaysPut() {
        let pivot = SIMD2<Float>(400, 300)
        let projected = Tilt.project(pivot, pivot: pivot, angles: SIMD2(0.3, -0.3))
        XCTAssertEqual(projected.x, pivot.x, accuracy: 1e-4)
        XCTAssertEqual(projected.y, pivot.y, accuracy: 1e-4)
    }

    func testMovingRightPushesTheRightEdgeAway() {
        let pivot = SIMD2<Float>(0, 0)
        let angles = Tilt.target(for: SIMD2(Tilt.fullSpeed, 0))
        let right = Tilt.project(SIMD2(400, 0), pivot: pivot, angles: angles)
        let left = Tilt.project(SIMD2(-400, 0), pivot: pivot, angles: angles)
        // The far edge looks closer to the center, the near edge farther from it.
        XCTAssertLessThan(right.x, 400)
        XCTAssertGreaterThan(left.x, -400 - 400 * 0.5)
        XCTAssertLessThan(abs(right.x), abs(left.x))
    }

    func testMovingDownPushesTheBottomEdgeAway() {
        let angles = Tilt.target(for: SIMD2(0, Tilt.fullSpeed))
        let bottom = Tilt.project(SIMD2(0, 300), pivot: .zero, angles: angles)
        let top = Tilt.project(SIMD2(0, -300), pivot: .zero, angles: angles)
        XCTAssertLessThan(abs(bottom.y), abs(top.y))
    }

    func testTargetIsCappedAtTheMaximumAngle() {
        let angles = Tilt.target(for: SIMD2(100_000, 100_000))
        XCTAssertLessThanOrEqual(simd_length(angles), Tilt.maxAngle + 1e-4)
    }

    func testLeanFollowsAndSnapsBackToExactlyZero() {
        var lean = SIMD2<Float>.zero
        let target = Tilt.target(for: SIMD2(1800, 0))
        for _ in 0..<120 { lean = Tilt.follow(lean, target: target, dt: 1.0 / 120) }
        XCTAssertEqual(lean.y, target.y, accuracy: 0.01)
        for _ in 0..<600 { lean = Tilt.follow(lean, target: .zero, dt: 1.0 / 120) }
        XCTAssertEqual(lean, .zero, "the real window must take over from a perfectly flat overlay")
    }
}
