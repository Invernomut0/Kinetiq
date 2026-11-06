// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import KinetiqCore
import Metal
import XCTest
@testable import Kinetiq

final class RenderQualityManagerTests: XCTestCase {
    private func isolatedDefaults(
        named name: String = "io.github.invernomut0.Kinetiq.renderQuality.tests.\(UUID().uuidString)"
    ) throws -> UserDefaults {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    @MainActor
    func testInitializationPersistsOnlyDefaultChoiceAndDoesNotMutateOtherDomains() async throws {
        let name = "io.github.invernomut0.Kinetiq.renderQuality.tests.\(UUID().uuidString)"
        let defaults = try isolatedDefaults(named: name)
        let other = try isolatedDefaults()
        other.set(RenderQuality.low.rawValue, forKey: RenderQualityManager.preferenceKey)
        defaults.set("liquid", forKey: "closeEffect")
        let manager = RenderQualityManager(defaults: defaults)
        XCTAssertEqual(manager.selection, .auto)
        XCTAssertNil(manager.gpuMilliseconds)
        XCTAssertEqual(defaults.persistentDomain(forName: name) as NSDictionary?,
                       ["closeEffect": "liquid", "renderQuality": "auto"] as NSDictionary)
        manager.selection = .ultra
        manager.refreshEnvironment()
        manager.reset()
        XCTAssertEqual(defaults.persistentDomain(forName: name) as NSDictionary?,
                       ["closeEffect": "liquid", "renderQuality": "auto"] as NSDictionary)
        XCTAssertEqual(RenderQualityManager(defaults: other).selection, .low)
    }

    @MainActor
    func testChoiceReloadsFromNewUserDefaultsInstanceAndResetPersists() async throws {
        let name = "io.github.invernomut0.Kinetiq.renderQuality.tests.\(UUID().uuidString)"
        let defaults = try isolatedDefaults(named: name)
        let manager = RenderQualityManager(defaults: defaults)
        for choice in RenderQuality.allCases {
            manager.selection = choice
            let reopenedDefaults = try XCTUnwrap(UserDefaults(suiteName: name))
            let reopened = RenderQualityManager(defaults: reopenedDefaults)
            XCTAssertEqual(reopened.selection, choice)
            XCTAssertNil(reopened.gpuMilliseconds)
            XCTAssertEqual(reopenedDefaults.persistentDomain(forName: name) as NSDictionary?,
                           [RenderQualityManager.preferenceKey: choice.rawValue] as NSDictionary)
        }
        manager.reset()
        XCTAssertEqual(RenderQualityManager(defaults: try XCTUnwrap(UserDefaults(suiteName: name))).selection, .auto)
        XCTAssertNil(manager.gpuMilliseconds)
    }

    @MainActor
    func testCorruptPreferencesRecoverToAutoWithoutRuntimeSamples() async throws {
        for value: Any in ["unknown", 42, ["selection": "ultra"], Data([0, 1])] {
            let defaults = try isolatedDefaults()
            defaults.set(value, forKey: "renderQuality")
            let manager = RenderQualityManager(defaults: defaults)
            XCTAssertEqual(manager.selection, .auto)
            XCTAssertEqual(defaults.string(forKey: "renderQuality"), "auto")
            XCTAssertNil(manager.gpuMilliseconds)
            XCTAssertFalse(manager.reason.isEmpty)
        }
    }

    @MainActor
    func testEveryManualChoicePersistsButRuntimeSamplesDoNot() async throws {
        let defaults = try isolatedDefaults()
        let manager = RenderQualityManager(defaults: defaults)
        for quality in RenderQuality.allCases {
            manager.selection = quality
            XCTAssertEqual(defaults.string(forKey: "renderQuality"), quality.rawValue)
            let restored = RenderQualityManager(defaults: defaults)
            XCTAssertEqual(restored.selection, quality)
            XCTAssertNil(restored.gpuMilliseconds)
            XCTAssertFalse(restored.title.isEmpty)
        }
        manager.recordGPUTime(.nan)
        manager.recordGPUTime(-1)
        XCTAssertNil(manager.gpuMilliseconds)
        manager.reset()
        XCTAssertEqual(manager.selection, .auto)
        XCTAssertEqual(defaults.string(forKey: "renderQuality"), "auto")
        XCTAssertNil(manager.gpuMilliseconds)
    }

    @MainActor
    func testRefreshMatchesRealProcessInfoSafetyForEveryChoice() async throws {
        let manager = RenderQualityManager(defaults: try isolatedDefaults())
        for quality in RenderQuality.allCases {
            manager.selection = quality
            manager.refreshEnvironment()
            var expected = RenderQualityPolicy(selection: quality)
            let state: RenderQualityPolicy.ThermalState
            switch ProcessInfo.processInfo.thermalState {
            case .nominal: state = .nominal
            case .fair: state = .fair
            case .serious: state = .serious
            case .critical: state = .critical
            @unknown default: state = .serious
            }
            expected.refreshEnvironment(thermalState: state, lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
            XCTAssertEqual(manager.budget, expected.budget)
            XCTAssertEqual(manager.resolvedQuality, expected.resolvedQuality)
            XCTAssertEqual(manager.selection, quality)
            XCTAssertEqual(manager.reason, expected.reason)
            XCTAssertEqual(manager.title, quality == .auto ? "Auto · \(expected.resolvedQuality.title)" : expected.resolvedQuality.title)
            XCTAssertNotEqual(manager.resolvedQuality, .auto)
            XCTAssertNil(manager.gpuMilliseconds)
            let requested = RenderBudget.forQuality(quality)
            XCTAssertLessThanOrEqual(manager.budget.textureScale, requested.textureScale)
            XCTAssertLessThanOrEqual(manager.budget.maxParticles, requested.maxParticles)
            XCTAssertLessThanOrEqual(manager.budget.blurPasses, requested.blurPasses)
            XCTAssertLessThanOrEqual(manager.budget.meshLimit, requested.meshLimit)
            XCTAssertLessThanOrEqual(manager.budget.secondaryFPS, requested.secondaryFPS)
            XCTAssertFalse(manager.budget.allowsExpensive && !requested.allowsExpensive)
            switch state {
            case .critical:
                XCTAssertLessThanOrEqual(manager.budget.secondaryFPS, 15)
                XCTAssertFalse(manager.budget.allowsExpensive)
            case .serious:
                XCTAssertLessThanOrEqual(manager.budget.secondaryFPS, 30)
                XCTAssertFalse(manager.budget.allowsExpensive)
            case .fair:
                XCTAssertLessThanOrEqual(manager.budget.secondaryFPS, 60)
            case .nominal:
                if ProcessInfo.processInfo.isLowPowerModeEnabled {
                    XCTAssertLessThanOrEqual(manager.budget.secondaryFPS, 60)
                }
            }
        }
    }

    @MainActor
    func testActualMetalCompletionFeedsMetricAndResetClearsIt() async throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let buffer = device.makeBuffer(length: 16 * 1024 * 1024, options: .storageModePrivate),
              let command = queue.makeCommandBuffer(), let blit = command.makeBlitCommandEncoder() else {
            throw XCTSkip("Metal resources unavailable")
        }
        blit.fill(buffer: buffer, range: 0..<buffer.length, value: 0)
        blit.endEncoding()
        await withCheckedContinuation { continuation in
            command.addCompletedHandler { _ in continuation.resume() }
            command.commit()
        }
        XCTAssertEqual(command.status, .completed)
        let seconds = command.gpuEndTime - command.gpuStartTime
        guard command.gpuStartTime > 0, seconds.isFinite, (0.00001...1).contains(seconds) else {
            throw XCTSkip("GPU completion timestamps are unavailable or outside accepted sample range")
        }
        let name = "io.github.invernomut0.Kinetiq.renderQuality.tests.\(UUID().uuidString)"
        let defaults = try isolatedDefaults(named: name)
        let manager = RenderQualityManager(defaults: defaults)
        manager.selection = .ultra
        manager.recordGPUTime(seconds)
        XCTAssertEqual(try XCTUnwrap(manager.gpuMilliseconds), seconds * 1000, accuracy: 1e-9)
        XCTAssertEqual(manager.selection, .ultra, "Safety ceilings must not overwrite the user's choice")
        XCTAssertEqual(defaults.persistentDomain(forName: name) as NSDictionary?,
                       [RenderQualityManager.preferenceKey: "ultra"] as NSDictionary)
        XCTAssertNil(RenderQualityManager(defaults: defaults).gpuMilliseconds)
        manager.reset()
        XCTAssertNil(manager.gpuMilliseconds)
        XCTAssertEqual(manager.selection, .auto)
        XCTAssertEqual(defaults.persistentDomain(forName: name) as NSDictionary?,
                       [RenderQualityManager.preferenceKey: "auto"] as NSDictionary)
    }
}