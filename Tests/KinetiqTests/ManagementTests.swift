// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import KinetiqCore
import KinetiqEffects
import Metal
import class SwiftUI.NSHostingView
import XCTest
@testable import Kinetiq

/// Exercises real preferences and system metadata, never the user's standard defaults.
final class ManagementTests: XCTestCase {
    private func isolatedSettings() throws -> Settings {
        let suite = "io.github.invernomut0.Kinetiq.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return Settings(defaults: defaults)
    }

    @MainActor
    private func model(settings: Settings, enabledChanged: @escaping () -> Void = {}) -> SetupModel {
        SetupModel(settings: settings, closeEffectChanged: {}, startChaos: {}, enabledChanged: enabledChanged,
                   runtimeStatus: { ManagementRuntimeStatus(metalAvailable: MTLCreateSystemDefaultDevice() != nil, eventTapRunning: false) })
    }

    func testEveryDestinationHasUniqueIdentityAndAvailableSystemSymbol() {
        XCTAssertEqual(ManagementPage.allCases.count, 8)
        XCTAssertEqual(Set(ManagementPage.allCases.map(\.id)).count, 8)
        for page in ManagementPage.allCases {
            XCTAssertFalse(page.title.isEmpty)
            XCTAssertFalse(page.subtitle.isEmpty)
            XCTAssertNotNil(NSImage(systemSymbolName: page.symbol, accessibilityDescription: nil), page.title)
        }
    }

    @MainActor
    func testEnableControlPersistsBeforeCallingEngineAction() async throws {
        let settings = try isolatedSettings()
        var observed: [Bool] = []
        let model = model(settings: settings, enabledChanged: { observed.append(settings.enabled) })
        model.setEnabled(false)
        XCTAssertFalse(settings.enabled)
        model.setEnabled(true)
        XCTAssertTrue(settings.enabled)
        XCTAssertEqual(observed, [false, true])
    }

    @MainActor
    func testPhysicsBindingWritesRealPreferencesAndSelectsCustomPreset() async throws {
        let settings = try isolatedSettings()
        settings.preset = .subtle
        let model = model(settings: settings)
        let binding = model.physicsBinding({ $0.friction }, { $0.friction = $1 })
        binding.wrappedValue = Settings.frictionRange.upperBound
        XCTAssertEqual(settings.physics.friction, Float(Settings.frictionRange.upperBound))
        XCTAssertEqual(settings.preset, .custom)
        XCTAssertEqual(binding.wrappedValue, Settings.frictionRange.upperBound)
        XCTAssertTrue(model.visibleWindows.isEmpty, "Changing physics must not enumerate desktop windows")
    }

    @MainActor
    func testAppRulesUseInstalledFinderAndKeepExclusionsUnique() async throws {
        let url = try XCTUnwrap(NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder"))
        let id = try XCTUnwrap(Bundle(url: url)?.bundleIdentifier)
        let settings = try isolatedSettings()
        let model = model(settings: settings)
        model.addExclusion(id)
        model.addExclusion(id)
        XCTAssertEqual(settings.excludedApps.filter { $0 == id }.count, 1)
        model.addAppEffect(id)
        XCTAssertEqual(settings.appCloseEffects[id], settings.closeEffect.rawValue)
        model.setAppEffect(id, CloseEffectChoice.off.rawValue)
        XCTAssertEqual(settings.closeEffect(forBundleID: id), .off)
        model.removeAppEffect(id)
        XCTAssertNil(settings.appCloseEffects[id])
        model.removeExclusion(id)
        XCTAssertFalse(settings.excludedApps.contains(id))
    }

    func testResetPreservesGeneralControlsAndRestoresEffectDefaults() throws {
        let settings = try isolatedSettings()
        settings.enabled = false
        settings.titleBarDrag = false
        settings.modifier = .option
        settings.preset = .extreme
        settings.closeEffect = .off
        settings.excludedApps = []
        settings.chaosEnabled = true
        settings.resetToDefaults()
        XCTAssertFalse(settings.enabled)
        XCTAssertFalse(settings.titleBarDrag)
        XCTAssertEqual(settings.modifier, .option)
        XCTAssertEqual(settings.preset, .realistic)
        XCTAssertEqual(settings.closeEffect, Settings.defaultCloseEffect)
        XCTAssertEqual(settings.excludedApps, Settings.defaultExcludedApps)
        XCTAssertFalse(settings.chaosEnabled)
    }

    @MainActor
    func testRealDesktopSnapshotHasValidUniqueWindowMetadata() async {
        let windows = ManagedWindow.onScreen()
        XCTAssertEqual(Set(windows.map(\.id)).count, windows.count)
        for window in windows {
            XCTAssertGreaterThan(window.id, 0)
            XCTAssertFalse(window.owner.isEmpty)
            XCTAssertGreaterThan(window.width, 1)
            XCTAssertGreaterThan(window.height, 1)
        }
    }

    @MainActor
    func testEverySettingsPageLaysOutInRealHostingView() async throws {
        _ = NSApplication.shared
        let model = model(settings: try isolatedSettings())
        for page in [ManagementPage.effects, .physics, .screenSaver, .rules, .settings] {
            let view = NSHostingView(rootView: SetupControlsView(model: model, page: page))
            view.frame = NSRect(x: 0, y: 0, width: 640, height: 600)
            view.layoutSubtreeIfNeeded()
            XCTAssertEqual(view.frame.width, 640, page.title)
            XCTAssertGreaterThan(view.subviews.count, 0, page.title)
        }
        let shell = NSHostingView(rootView: SetupView(model: model))
        shell.frame = NSRect(x: 0, y: 0, width: 1040, height: 740)
        shell.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(shell.subviews.count, 0)
    }
}