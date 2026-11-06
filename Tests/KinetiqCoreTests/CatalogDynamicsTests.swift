// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import KinetiqCore
import XCTest

final class CatalogDynamicsTests: XCTestCase {
    @MainActor private func geometry() throws -> (CGRect, CGRect) {
        guard let screen = NSScreen.screens.first else { throw XCTSkip("A real screen is required") }
        let b = screen.visibleFrame
        guard b.width > 100, b.height > 100 else { throw XCTSkip("No usable screen geometry") }
        let window = CGRect(x: b.minX + min(80, b.width * 0.1), y: b.minY + min(60, b.height * 0.1),
                            width: b.width * 0.3, height: b.height * 0.3)
        return (b, window)
    }

    @MainActor func testFixed120HzIsIndependentOfRenderCadenceOnRealScreen() throws {
        let (bounds, frame) = try geometry()
        var a = CatalogDynamics(frame: frame, bounds: bounds)
        var b = a
        let parameters = EffectPreset(effect: .gravity).parameters
        for _ in 0..<120 { a.advance(1 / 120, effect: .gravity, parameters: parameters) }
        for _ in 0..<60 { b.advance(1 / 60, effect: .gravity, parameters: parameters) }
        XCTAssertEqual(a.body, b.body)
        XCTAssertEqual(a.elapsed, 1, accuracy: 1e-10)
        XCTAssertGreaterThan(a.body.frame.minY, frame.minY)
    }

    @MainActor func testGravityStaysInsideVisibleFrameAndDropsStalledBacklog() throws {
        let (bounds, frame) = try geometry()
        var dynamics = CatalogDynamics(frame: frame, bounds: bounds)
        let parameters = EffectPreset(effect: .gravity).parameters
        dynamics.advance(600, effect: .gravity, parameters: parameters)
        XCTAssertEqual(dynamics.elapsed, 0.1, accuracy: 1e-10)
        let prior = dynamics.body
        for interval in [Double.nan, .infinity, -1, 0] {
            dynamics.advance(interval, effect: .gravity, parameters: parameters)
        }
        XCTAssertEqual(prior, dynamics.body)
        for _ in 0..<1200 {
            dynamics.advance(1 / 120, effect: .gravity, parameters: parameters)
            XCTAssertTrue(bounds.insetBy(dx: -0.001, dy: -0.001).contains(dynamics.body.frame))
            XCTAssertTrue(dynamics.body.velocity.x.isFinite && dynamics.body.velocity.y.isFinite)
        }
    }

    @MainActor func testMagnetUsesVisibleEdgeAndZeroStrengthIsInert() throws {
        let (bounds, frame) = try geometry()
        var moving = CatalogDynamics(frame: frame, bounds: bounds)
        var inert = moving
        var parameters = EffectPreset(effect: .magnet).parameters
        parameters["radius"] = 600
        for _ in 0..<240 { moving.advance(1 / 120, effect: .magnet, parameters: parameters) }
        parameters["strength"] = 0
        for _ in 0..<240 { inert.advance(1 / 120, effect: .magnet, parameters: parameters) }
        XCTAssertEqual(inert.body.frame, frame)
        XCTAssertNotEqual(moving.body.frame, frame)
        XCTAssertTrue(bounds.insetBy(dx: -0.001, dy: -0.001).contains(moving.body.frame))
    }
}