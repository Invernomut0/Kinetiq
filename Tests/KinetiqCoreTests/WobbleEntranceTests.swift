// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import simd
import XCTest
@testable import KinetiqCore

final class WobbleEntranceTests: XCTestCase {
    private let frame: Float = 1.0 / 120.0

    func testEveryEntranceMovesTheWindowThenSettlesBackExactlyWhereItWas() {
        let origin = SIMD2<Float>(300, 200)
        for entrance in WobbleEntrance.allCases {
            for preset in [KinetiqSettings.subtle, .realistic, .exaggerated, .extreme] {
                let model = KinetiqModel(size: SIMD2(700, 480), origin: origin, settings: preset)
                entrance.apply(to: model, drop: SIMD2(230, 170))
                XCTAssertFalse(model.isSettled, "\(entrance.title) does nothing")

                var peak: Float = 0
                var elapsed: Float = 0
                repeat {
                    model.step(frame)
                    elapsed += frame
                    peak = max(peak, model.maxDisplacement)
                } while !model.isSettled && elapsed < 20
                XCTAssertTrue(model.isSettled, "\(entrance.title) never settles")
                XCTAssertGreaterThan(peak, 3, "\(entrance.title) is invisible")
                XCTAssertLessThan(peak, 200, "\(entrance.title) tears the window apart")
                XCTAssertEqual(model.origin, origin, "\(entrance.title) moved the window")
                model.snapToRest()
                XCTAssertEqual(model.maxDisplacement, 0, accuracy: 1e-3)
            }
        }
    }

    func testStoneInWaterRingsStartAtTheDropPoint() {
        let model = KinetiqModel(size: SIMD2(700, 480), origin: .zero, settings: .realistic)
        WobbleEntrance.stoneInWater.apply(to: model, drop: SIMD2(100, 100))
        model.step(0.1)
        let near = simd_length(model.displacement(u: 0.2, v: 0.25))
        let far = simd_length(model.displacement(u: 1, v: 1))
        XCTAssertGreaterThan(near, far, "the wave must reach the drop point's surroundings first")
        XCTAssertEqual(far, 0, accuracy: 1e-3)
    }

    func testChainedRipplesStartLater() {
        let model = KinetiqModel(size: SIMD2(700, 480), origin: .zero, settings: .realistic)
        model.ripple(atLocal: SIMD2(350, 240), amplitude: 8, wavelength: 100, speed: 500, duration: 1, delay: 0.5)
        model.step(0.2)
        XCTAssertEqual(model.maxDisplacement, 0, accuracy: 1e-3, "the delayed wave has not started")
        XCTAssertTrue(model.isRippling)
        model.step(0.1)
        model.step(0.1)
        model.step(0.1)
        model.step(0.1)
        XCTAssertGreaterThan(model.maxDisplacement, 0)
    }
}
