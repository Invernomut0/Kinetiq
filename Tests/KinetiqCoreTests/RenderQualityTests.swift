// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import XCTest
@testable import KinetiqCore

/// Pure numerical policy tests use injected monotonic times, not fake GPU loads.
final class RenderQualityTests: XCTestCase {
    func testChoiceContractAndCodableRoundTrip() throws {
        XCTAssertEqual(RenderQuality.allCases.map(\.rawValue), ["auto", "low", "balanced", "high", "ultra"])
        for quality in RenderQuality.allCases {
            XCTAssertFalse(quality.title.isEmpty)
            XCTAssertEqual(try JSONDecoder().decode(RenderQuality.self, from: JSONEncoder().encode(quality)), quality)
            let budget = RenderBudget.forQuality(quality)
            XCTAssertTrue((0.25...1).contains(budget.textureScale))
            XCTAssertTrue((1...1500).contains(budget.maxParticles))
            XCTAssertTrue((15...120).contains(budget.secondaryFPS))
        }
        let policy = RenderQualityPolicy()
        XCTAssertNil(policy.gpuMilliseconds)
        XCTAssertEqual(policy.resolvedQuality, .high)
        XCTAssertEqual(policy.budget, .forQuality(.high))
    }

    func testDegradationChangesExactlyOneResourceInRequiredOrder() {
        let budgets = RenderQualityPolicy.autoBudgets
        XCTAssertEqual(budgets.first, .forQuality(.high))
        XCTAssertEqual(budgets.last, .forQuality(.low))
        var resources: [Int] = []
        for (a, b) in zip(budgets, budgets.dropFirst()) {
            let changes = [a.textureScale != b.textureScale, a.maxParticles != b.maxParticles,
                           a.blurPasses != b.blurPasses, a.meshLimit != b.meshLimit,
                           a.secondaryFPS != b.secondaryFPS, a.allowsExpensive != b.allowsExpensive]
            XCTAssertEqual(changes.filter { $0 }.count, 1)
            resources.append(changes.firstIndex(of: true)!)
            XCTAssertLessThanOrEqual(b.textureScale, a.textureScale)
            XCTAssertLessThanOrEqual(b.maxParticles, a.maxParticles)
            XCTAssertLessThanOrEqual(b.blurPasses, a.blurPasses)
            XCTAssertLessThanOrEqual(b.meshLimit, a.meshLimit)
            XCTAssertLessThanOrEqual(b.secondaryFPS, a.secondaryFPS)
        }
        XCTAssertEqual(resources, resources.sorted())
        XCTAssertEqual(Set(resources), Set(0...5))
    }

    func testSustainedOverloadTraversesEntireLadderWithCooldown() {
        var policy = RenderQualityPolicy()
        var transitions: [RenderBudget] = [policy.budget]
        var changedAt: [Double] = []
        for sample in 0..<900 {
            let time = Double(sample) / 10
            let previous = policy.budget
            policy.recordGPUTime(0.020, at: time)
            if policy.budget != previous {
                transitions.append(policy.budget)
                changedAt.append(time)
            }
        }
        XCTAssertEqual(transitions, RenderQualityPolicy.autoBudgets)
        for (a, b) in zip(changedAt, changedAt.dropFirst()) { XCTAssertGreaterThanOrEqual(b - a, 3 - 1e-9) }
        XCTAssertFalse(policy.budget.allowsExpensive)
        XCTAssertEqual(policy.resolvedQuality, .low)
    }

    func testHysteresisRejectsSpikesDeadbandAndIdleEvidence() {
        var policy = RenderQualityPolicy()
        policy.recordGPUTime(0.020, at: 0)
        for sample in 1...50 { policy.recordGPUTime(0.008, at: Double(sample) / 10) }
        XCTAssertEqual(policy.degradationStep, 0, "An isolated spike is not sustained overload")
        XCTAssertEqual(policy.gpuMilliseconds!, 8, accuracy: 0.01)

        var idle = RenderQualityPolicy()
        for sample in 0..<10 { idle.recordGPUTime(0.020, at: Double(sample) * 2) }
        XCTAssertEqual(idle.degradationStep, 0, "Time spent idle is not rendering evidence")

        var burst = RenderQualityPolicy()
        for sample in 0..<100 { burst.recordGPUTime(0.020, at: Double(sample) / 1000) }
        XCTAssertEqual(burst.degradationStep, 0, "Many completions in one burst cannot bypass dwell time")
    }

    func testRecoveryIsSlowerAndReversesOnlyOneStepAtATime() {
        var policy = RenderQualityPolicy()
        for sample in 0..<400 { policy.recordGPUTime(0.025, at: Double(sample) / 10) }
        XCTAssertEqual(policy.degradationStep, RenderQualityPolicy.autoBudgets.count - 1)
        var lastStep = policy.degradationStep
        var changedAt: [Double] = []
        for sample in 400..<2200 {
            let time = Double(sample) / 10
            policy.recordGPUTime(0.002, at: time)
            if policy.degradationStep != lastStep {
                XCTAssertEqual(policy.degradationStep, lastStep - 1)
                lastStep = policy.degradationStep
                changedAt.append(time)
            }
        }
        XCTAssertEqual(lastStep, 0)
        XCTAssertEqual(policy.budget, .forQuality(.high))
        XCTAssertGreaterThan(changedAt.first ?? 0, 45)
        for (a, b) in zip(changedAt, changedAt.dropFirst()) { XCTAssertGreaterThanOrEqual(b - a, 8 - 1e-9) }
    }

    func testInvalidSamplesAndReversedTimeHaveNoEffect() {
        var policy = RenderQualityPolicy()
        for input in [Double.nan, .infinity, -.infinity, -1, 0, 0.000009, 1.001] {
            policy.recordGPUTime(input, at: 0)
        }
        policy.recordGPUTime(0.02, at: .nan)
        XCTAssertNil(policy.gpuMilliseconds)
        policy.recordGPUTime(0.00001, at: 1)
        XCTAssertEqual(policy.gpuMilliseconds!, 0.01, accuracy: 1e-12)
        policy.recordGPUTime(1, at: 1)
        policy.recordGPUTime(1, at: 0)
        XCTAssertEqual(policy.gpuMilliseconds!, 0.01, accuracy: 1e-12)
        policy.recordGPUTime(1, at: 2)
        XCTAssertEqual(policy.gpuMilliseconds!, 0.01 + 0.15 * (1000 - 0.01), accuracy: 1e-9)
    }

    func testManualChoicesIgnoreAutomaticAdaptationAndHonorSafety() {
        for quality in [RenderQuality.low, .balanced, .high, .ultra] {
            var policy = RenderQualityPolicy(selection: quality)
            for sample in 0..<200 { policy.recordGPUTime(0.1, at: Double(sample) / 10) }
            XCTAssertEqual(policy.budget, .forQuality(quality))
            XCTAssertEqual(policy.resolvedQuality, quality)
            policy.refreshEnvironment(thermalState: .nominal, lowPowerMode: true)
            XCTAssertLessThanOrEqual(policy.budget.secondaryFPS, 60)
            policy.refreshEnvironment(thermalState: .serious, lowPowerMode: false)
            XCTAssertFalse(policy.budget.allowsExpensive)
            XCTAssertEqual(policy.resolvedQuality, .low)
            policy.refreshEnvironment(thermalState: .critical, lowPowerMode: true)
            XCTAssertEqual(policy.budget.secondaryFPS, 15)
            XCTAssertEqual(policy.selection, quality)
            policy.refreshEnvironment(thermalState: .nominal, lowPowerMode: false)
            XCTAssertEqual(policy.budget, .forQuality(quality))
        }
    }

    func testSwitchingChoiceClearsEvidenceWithoutLosingSafety() {
        var policy = RenderQualityPolicy()
        for sample in 0..<80 { policy.recordGPUTime(0.020, at: Double(sample) / 10) }
        XCTAssertGreaterThan(policy.degradationStep, 0)
        policy.refreshEnvironment(thermalState: .serious, lowPowerMode: true)
        policy.select(.ultra)
        XCTAssertNil(policy.gpuMilliseconds)
        XCTAssertEqual(policy.degradationStep, 0)
        XCTAssertEqual(policy.resolvedQuality, .low)
        policy.select(.auto)
        policy.refreshEnvironment(thermalState: .nominal, lowPowerMode: false)
        XCTAssertEqual(policy.budget, .forQuality(.high))
    }

    func testParticleLimitClampsAndDefaultRemainsBackwardsCompatible() {
        // A mathematical sampling domain, not an image or substituted desktop.
        let domain = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let original = LiquidWorld(windowFrame: domain, screenBounds: domain, obstacles: [])
        let explicit = LiquidWorld(windowFrame: domain, screenBounds: domain, obstacles: [], maxParticles: 1500)
        XCTAssertEqual(original.particles.map(\.position), explicit.particles.map(\.position))
        for limit in [Int.min, -1, 0, 1, 400, 700, 1000, 1500, Int.max] {
            let world = LiquidWorld(windowFrame: domain, screenBounds: domain, obstacles: [], maxParticles: limit)
            XCTAssertGreaterThan(world.particles.count, 0)
            XCTAssertLessThanOrEqual(world.particles.count, min(1500, max(1, limit)))
            XCTAssertTrue(world.spacing.isFinite)
            let identity = world.particles.map(\.uv)
            world.step(0.1)
            XCTAssertEqual(world.particles.map(\.uv), identity)
        }
    }
}