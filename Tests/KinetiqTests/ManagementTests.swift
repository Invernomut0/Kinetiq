// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import KinetiqCore
import KinetiqEffects
import Metal
import ScreenCaptureKit
import class SwiftUI.NSHostingController
import XCTest
@testable import Kinetiq

/// Writes only isolated preferences; the production catalog is observed without changing standard defaults.
final class ManagementTests: XCTestCase {
    @MainActor private static var preparedApplication = false
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
        XCTAssertEqual(ManagementPage.allCases.count, 12)
        XCTAssertEqual(Set(ManagementPage.allCases.map(\.id)).count, 12)
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
        let model = model(settings: try isolatedSettings())
        let (window, shell) = try hostingWindow(model: model)
        defer { window.close() }
        let presets = CatalogStore.shared.presets
        let document = CatalogStore.shared.document
        let shaderStatus = CatalogRuntime.shared.shaderStatus
        let defaultsBefore = catalogPreferences()
        XCTAssertFalse(CatalogRuntime.shared.isPlaying)
        for size in [NSSize(width: 960, height: 700), NSSize(width: 1180, height: 780)] {
            window.setContentSize(size)
            for page in ManagementPage.allCases {
                model.requestedPage = page
                await settleLayout(shell, window: window)
                // NavigationSplitView installs a native toolbar/full-size content
                // view. setContentSize sizes the layout area, not that outer host.
                XCTAssertEqual(window.contentLayoutRect.width, size.width, page.title)
                XCTAssertGreaterThanOrEqual(window.contentLayoutRect.height, size.height, page.title)
                XCTAssertEqual(shell.bounds.size, window.contentView?.bounds.size, page.title)
                XCTAssertGreaterThan(shell.subviews.count, 0, page.title)
                XCTAssertEqual(window.title, "Kinetiq — \(page.title)", "Requested page was not rendered")
                assertFiniteLayout(shell, page: page)
                XCTAssertFalse(CatalogRuntime.shared.isPlaying, page.title)
                XCTAssertFalse(CatalogRuntime.shared.hasScene, page.title)
                XCTAssertEqual(CatalogRuntime.shared.shaderStatus, shaderStatus, "Navigation must not compile a captured preview")
            }
        }
        XCTAssertEqual(CatalogStore.shared.presets, presets)
        XCTAssertEqual(CatalogStore.shared.document, document)
        XCTAssertEqual(catalogPreferences(), defaultsBefore)
    }

    /// Reuses one shell, including nil and repeated requests, rather than recreating the destination views.
    @MainActor
    func testRequestedPageUpdatesMountedShellWithoutStartingPreviewOrPlayback() async throws {
        let model = model(settings: try isolatedSettings())
        model.requestedPage = .animationStudio
        let (window, shell) = try hostingWindow(model: model)
        defer { window.close() }
        let shaderStatus = CatalogRuntime.shared.shaderStatus
        XCTAssertFalse(CatalogRuntime.shared.isPlaying)
        await settleLayout(shell, window: window)
        XCTAssertEqual(window.title, "Kinetiq — Animation Studio")
        for page in [ManagementPage.effects, .effects, .layouts, .workspaces, .performance, .animationStudio, .overview] {
            model.requestedPage = page
            await settleLayout(shell, window: window)
            XCTAssertEqual(window.title, "Kinetiq — \(page.title)")
            model.requestedPage = nil
            await settleLayout(shell, window: window)
            XCTAssertEqual(window.title, "Kinetiq — \(page.title)", "nil must preserve the current selection")
            XCTAssertFalse(CatalogRuntime.shared.isPlaying)
            XCTAssertFalse(CatalogRuntime.shared.hasScene)
            XCTAssertEqual(CatalogRuntime.shared.shaderStatus, shaderStatus)
        }
    }

    /// Optional real-UI artifacts. Permission failures skip only this test, never the layout coverage.
    @MainActor
    func testOptInScreenshotsOfOwnEffectsStudioAndPerformanceWindow() async throws {
        guard let path = ProcessInfo.processInfo.environment["KINETIQ_UI_TEST_DUMP"] else {
            throw XCTSkip("Set KINETIQ_UI_TEST_DUMP to a directory under /tmp to save real UI")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        let temporary = URL(fileURLWithPath: "/tmp", isDirectory: true).resolvingSymlinksInPath()
        guard directory.path.hasPrefix(temporary.path + "/"), directory.path != temporary.path else {
            XCTFail("UI screenshots must remain in a directory under /tmp"); return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let model = model(settings: try isolatedSettings())
        let (window, shell) = try hostingWindow(model: model)
        defer { window.close() }
        XCTAssertFalse(CatalogRuntime.shared.isPlaying)
        for page in [ManagementPage.effects, .animationStudio, .performance] {
            model.requestedPage = page
            await settleLayout(shell, window: window)
            XCTAssertEqual(window.title, "Kinetiq — \(page.title)")
            let image = try await ownWindowImage(shell, window: window)
            XCTAssertGreaterThan(image.pixelsWide, 0)
            XCTAssertGreaterThan(image.pixelsHigh, 0)
            XCTAssertLessThanOrEqual(image.pixelsWide * image.pixelsHigh, 8_000_000)
            let png = try XCTUnwrap(image.representation(using: .png, properties: [:]))
            let url = directory.appendingPathComponent("\(page.rawValue).png")
            // Replace, rather than follow, a pre-existing symbolic link; create private before writing pixels.
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]))
            try png.write(to: url)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
            XCTAssertEqual(NSBitmapImageRep(data: try Data(contentsOf: url))?.pixelsWide, image.pixelsWide)
            print("KINETIQ_UI_TEST_DUMP: \(url.path)")
            XCTAssertFalse(CatalogRuntime.shared.isPlaying)
        }
    }

    /// Matches the real-window integration helpers without installing a delegate, tap, saver or signals.
    @MainActor
    private func hostingWindow(model: SetupModel) throws -> (NSWindow, NSView) {
        _ = NSApplication.shared
        guard NSScreen.screens.first != nil, CGSessionCopyCurrentDictionary() != nil else {
            throw XCTSkip("A graphical WindowServer session is required")
        }
        if !Self.preparedApplication {
            NSApp.setActivationPolicy(.regular)
            NSApp.finishLaunching()
            Self.preparedApplication = true
        }
        let window = NSWindow(contentRect: NSRect(x: 40, y: 60, width: 1180, height: 780),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.title = "Kinetiq — owned UI test window"
        // Match production so a controller manages native toolbar safe areas.
        let controller = NSHostingController(rootView: SetupView(model: model))
        window.contentViewController = controller
        let shell = controller.view
        shell.autoresizingMask = [.width, .height]
        window.setContentSize(NSSize(width: 1180, height: 780))
        NSApp.activate()
        window.orderFrontRegardless()
        return (window, shell)
    }

    /// Give SwiftUI's published selection and native split-view transactions a real asynchronous turn.
    @MainActor
    private func settleLayout(_ view: NSView, window: NSWindow) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                view.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                continuation.resume()
            }
        }
    }

    /// AppKit may lazily register framework defaults; only Kinetiq's catalog persistence is relevant here.
    @MainActor
    private func catalogPreferences() -> NSDictionary {
        let keys: Set<String> = ["catalogPresets.v1", "studioDocument.v1", "renderQuality"]
        return UserDefaults.standard.dictionaryRepresentation().filter { keys.contains($0.key) } as NSDictionary
    }

    @MainActor
    private func assertFiniteLayout(_ view: NSView, page: ManagementPage) {
        for component in [view.frame.origin.x, view.frame.origin.y, view.frame.width, view.frame.height] {
            XCTAssertTrue(component.isFinite, "Nonfinite native layout: \(page.title)")
        }
        XCTAssertGreaterThanOrEqual(view.frame.width, 0, page.title)
        XCTAssertGreaterThanOrEqual(view.frame.height, 0, page.title)
        for child in view.subviews { assertFiniteLayout(child, page: page) }
    }

    /// Capture the actual composed window, including its toolbar and native colors.
    @MainActor
    private func ownWindowImage(_ shell: NSView, window: NSWindow) async throws -> NSBitmapImageRep {
        guard CGPreflightScreenCaptureAccess() else {
            throw XCTSkip("Screen Recording is required only for optional own-window screenshots")
        }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let own = try XCTUnwrap(content.windows.first {
            $0.windowID == CGWindowID(window.windowNumber) && $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier
        })
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width * window.backingScaleFactor)
        config.height = Int(window.frame.height * window.backingScaleFactor)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.colorSpaceName = CGColorSpace.sRGB
        let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: own), configuration: config)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(cgImage: image).converting(to: .deviceRGB, renderingIntent: .default))
        XCTAssertTrue(hasVisiblePixels(bitmap), "The screenshot must contain the actual painted UI")
        return bitmap
    }

    @MainActor
    private func hasVisiblePixels(_ bitmap: NSBitmapImageRep) -> Bool {
        var colors = Set<String>()
        for y in 1...12 {
            for x in 1...16 {
                guard let color = bitmap.colorAt(x: bitmap.pixelsWide * x / 17, y: bitmap.pixelsHigh * y / 13)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.1 else { continue }
                colors.insert("\(Int(color.redComponent * 255)),\(Int(color.greenComponent * 255)),\(Int(color.blueComponent * 255))")
            }
        }
        return colors.count > 8
    }
}