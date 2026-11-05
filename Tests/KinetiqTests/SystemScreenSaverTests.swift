// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import KinetiqCore
import KinetiqSaverSupport
import KinetiqScreenSaver
import Metal
import PaperSaverKit
import ScreenSaver
import class SwiftUI.NSHostingView
import XCTest
@testable import Kinetiq

/// Uses real system data read-only; all writes belong to disposable files or defaults suites.
final class SystemScreenSaverTests: XCTestCase {
    private enum SectionLocation: Hashable {
        case all, system, display(String), space(String), spaceDisplay(String, String)
    }

    /// Retains section identities rather than relying on dictionary traversal order.
    private func sections(_ store: WallpaperStore) -> [SectionLocation: StoreSection] {
        var result: [SectionLocation: StoreSection] = [:]
        result[.all] = store.allSpacesAndDisplays
        result[.system] = store.systemDefault
        for (id, section) in store.displays { result[.display(id)] = section }
        for (id, entry) in store.spaces {
            result[.space(id)] = entry.default
            for (display, section) in entry.displays { result[.spaceDisplay(id, display)] = section }
        }
        return result
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Kinetiq-SystemSaverTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let suite = "io.github.invernomut0.Kinetiq.SystemScreenSaverTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    @MainActor
    private func isKinetiq(_ slot: SlotConfiguration?) -> Bool {
        guard case .screenSaver(let url)? = slot?.configuration else { return false }
        return url.standardizedFileURL == SystemScreenSaver.installedURL.standardizedFileURL
    }

    @MainActor
    private func candidate(from original: WallpaperStore) throws -> WallpaperStore {
        try original.setting(.screensaver, to: SlotConfiguration(
            choice: try WallpaperChoice(provider: .screenSaver, configuration: .screenSaver(moduleURL: SystemScreenSaver.installedURL)),
            optionValues: .null), in: .everywhere)
    }

    /// Captures only after a nonprompting permission check; never writes the user's scene cache.
    @MainActor
    private func capturedArchive() async throws -> SaverArchive {
        guard CGPreflightScreenCaptureAccess() else {
            throw XCTSkip("Screen Recording is not already granted; no permission will be requested.")
        }
        let windows: [SnapshotWindow]
        do {
            windows = try await DesktopSnapshot.capture()
        } catch SnapshotError.nothingToCapture {
            throw XCTSkip("No real desktop windows are available to capture.")
        }
        let primaryHeight = try XCTUnwrap(NSScreen.screens.first).frame.height
        var displays: [SaverArchive.Display] = []
        for screen in NSScreen.screens {
            let id = try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
            let capturedWallpaper = await DesktopSnapshot.wallpaper(for: screen)
            let wallpaper = try XCTUnwrap(capturedWallpaper)
            let frame = CGRect(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY,
                               width: screen.frame.width, height: screen.frame.height)
            let localWindows = try windows.filter { frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }.map {
                try SaverArchive.Window(frame: $0.frame.offsetBy(dx: -frame.minX, dy: -frame.minY),
                                        image: $0.image, isDock: $0.owner == "Dock")
            }
            displays.append(try SaverArchive.Display(id: id, size: screen.frame.size, wallpaper: wallpaper, windows: localWindows))
        }
        XCTAssertFalse(windows.isEmpty)
        return SaverArchive(displays: displays, settings: Settings(defaults: try isolatedDefaults()).chaosSettings)
    }

    @MainActor
    func testRealStoreRoundtripAndSnapshotRestoreUseOnlyTemporaryCopy() async throws {
        let original = try StoreFile().read()
        let url = try temporaryDirectory().appendingPathComponent("Index.plist")
        try FileManager.default.copyItem(at: StoreFile().url, to: url)
        let copy = StoreFile(url: url)
        let copied = try copy.read()
        let originalBytes = try copy.readRaw()
        let derived = try candidate(from: original)
        let snapshot = try copy.write(derived)
        XCTAssertEqual(try copy.read(), derived)
        XCTAssertEqual(snapshot.previousContents, originalBytes)
        XCTAssertEqual(try Data(contentsOf: copy.backupURL), originalBytes)
        try copy.restore(snapshot)
        XCTAssertEqual(try copy.readRaw(), originalBytes)
        XCTAssertEqual(try copy.read(), copied)
        try copy.write(original)
        XCTAssertEqual(try copy.read(), original)
    }

    @MainActor
    func testRestoreMatchesOriginalDesktopAndIdleInEveryRealSection() async throws {
        let original = try StoreFile().read()
        XCTAssertFalse(original.allSections.isEmpty)
        let derived = try candidate(from: original)
        XCTAssertTrue(derived.allSections.allSatisfy { isKinetiq($0.idle) })
        let restored = SystemScreenSaver.restoringScreenSaver(in: derived, from: original)
        let previous = sections(original)
        let current = sections(derived)
        let result = sections(restored)
        XCTAssertEqual(Set(result.keys), Set(current.keys))
        XCTAssertEqual(restored.extra, original.extra)
        for (location, section) in result {
            let old = previous[location]
            XCTAssertEqual(section.desktop, old?.desktop ?? old?.linked, "Desktop at \(location)")
            XCTAssertEqual(section.idle, old?.idle ?? old?.linked ?? original.slot(.screensaver), "Idle at \(location)")
            XCTAssertNil(section.linked, "Linked at \(location)")
            XCTAssertEqual(section.type, section.desktop == nil ? .idle : .individual)
            XCTAssertEqual(section.extra, current[location]?.extra)
        }
        for (id, entry) in original.spaces { XCTAssertEqual(restored.spaces[id]?.extra, entry.extra) }
    }

    @MainActor
    func testRestoreLeavesRealNonKinetiqUserChoiceUntouchedInMixedStore() async throws {
        let original = try StoreFile().read()
        let choices = sections(original).filter { !isKinetiq($0.value.idle ?? $0.value.linked) && ($0.value.idle ?? $0.value.linked) != nil }
        guard let (location, userSection) = choices.first else {
            throw XCTSkip("The real store has no non-Kinetiq screensaver choice to preserve.")
        }
        var mixed = try candidate(from: original)
        switch location {
        case .all: mixed.allSpacesAndDisplays = userSection
        case .system: mixed.systemDefault = userSection
        case .display(let id): mixed.displays[id] = userSection
        case .space(let id): mixed.spaces[id]?.default = userSection
        case .spaceDisplay(let id, let display): mixed.spaces[id]?.displays[display] = userSection
        }
        let restored = SystemScreenSaver.restoringScreenSaver(in: mixed, from: original)
        XCTAssertEqual(sections(restored)[location], userSection)
        for (key, section) in sections(mixed) where !isKinetiq(section.idle ?? section.linked) {
            XCTAssertEqual(sections(restored)[key], section, "User choice at \(key)")
        }
        for (key, section) in sections(mixed) where isKinetiq(section.idle ?? section.linked) {
            let previous = sections(original)[key]
            XCTAssertEqual(sections(restored)[key]?.idle, previous?.idle ?? previous?.linked ?? original.slot(.screensaver),
                           "Kinetiq-owned slot at \(key) must still be restored")
        }
    }

    @MainActor
    func testInstalledNativePrincipalIsScreenSaverViewAndInitializesWithoutStarting() async throws {
        _ = NSApplication.shared
        let packaged = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/Kinetiq.app/Contents/Resources/Kinetiq.saver")
        guard let bundle = [packaged, SystemScreenSaver.installedURL].compactMap({ Bundle(url: $0) }).first else {
            throw XCTSkip("Build the packaged app to inspect the actual native module's metadata.")
        }
        XCTAssertEqual(bundle.bundleIdentifier, "io.github.invernomut0.Kinetiq.ScreenSaver")
        let name = try XCTUnwrap(bundle.object(forInfoDictionaryKey: "NSPrincipalClass") as? String)
        let principal = try XCTUnwrap(NSClassFromString(name) as? ScreenSaverView.Type)
        XCTAssertEqual(ObjectIdentifier(principal), ObjectIdentifier(KinetiqScreenSaverView.self))
        let view = try XCTUnwrap(principal.init(frame: NSRect(x: 0, y: 0, width: 640, height: 360), isPreview: true))
        XCTAssertFalse(view.isAnimating)
        XCTAssertEqual(view.animationTimeInterval, 1 / 60, accuracy: 0.000001)
        XCTAssertTrue(view.subviews.isEmpty, "Initialization must not load the real scene cache")
        view.animateOneFrame()
        view.stopAnimation()
        XCTAssertFalse(view.isAnimating)
    }

    @MainActor
    func testNativeLifecycleWithoutArchiveNeedsNoCapturePermission() async throws {
        guard !FileManager.default.fileExists(atPath: SaverArchive.url.path) else {
            throw XCTSkip("A real scene cache exists; leave it untouched and do not start its renderer.")
        }
        _ = NSApplication.shared
        let view = try XCTUnwrap(KinetiqScreenSaverView(frame: NSRect(x: 0, y: 0, width: 320, height: 180), isPreview: true))
        defer { view.stopAnimation() }
        view.startAnimation()
        XCTAssertTrue(view.isAnimating)
        // Yield without waiting for archive preparation or requesting any capture access.
        await Task.yield()
        view.animateOneFrame()
        view.stopAnimation()
        view.stopAnimation()
        XCTAssertFalse(view.isAnimating)
        XCTAssertTrue(view.subviews.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: SaverArchive.url.path))
    }

    @MainActor
    func testRealDesktopArchiveRoundtripHasPrivatePermissionsAndExtractedScene() async throws {
        let archive = try await capturedArchive()
        let url = try temporaryDirectory().appendingPathComponent("scene/desktop.plist")
        try archive.write(to: url)
        let restored = try SaverArchive.read(from: url)
        XCTAssertEqual(restored.schema, archive.schema)
        XCTAssertEqual(restored.capturedAt, archive.capturedAt)
        XCTAssertEqual(restored.eventInterval, archive.eventInterval)
        XCTAssertEqual(restored.lifetime, archive.lifetime)
        XCTAssertEqual(restored.intensity, archive.intensity)
        XCTAssertEqual(restored.speed, archive.speed)
        XCTAssertEqual(restored.displays.count, archive.displays.count)
        let fileMode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)
        let directoryMode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)[.posixPermissions] as? NSNumber)
        XCTAssertEqual(fileMode.intValue & 0o777, 0o600)
        XCTAssertEqual(directoryMode.intValue & 0o777, 0o700)
        for (display, source) in zip(restored.displays, archive.displays) {
            XCTAssertEqual(display.id, source.id)
            XCTAssertEqual(display.size, source.size)
            XCTAssertEqual(display.wallpaper, source.wallpaper)
            XCTAssertNotNil(SaverArchive.image(display.wallpaper))
            XCTAssertEqual(display.windows.count, source.windows.count)
            for (window, original) in zip(display.windows, source.windows) {
                XCTAssertEqual(window.frame, original.frame)
                XCTAssertEqual(window.image, original.image)
                XCTAssertEqual(window.isDock, original.isDock)
                XCTAssertNotNil(SaverArchive.image(window.image))
            }
            if !display.windows.isEmpty {
                let scene = display.scene()
                XCTAssertFalse(scene.seeds.isEmpty)
                XCTAssertFalse(scene.pictures.isEmpty)
                XCTAssertEqual(scene.frames, display.windows.map(\.frame))
            }
        }
    }

    func testUnavailableArchiveThrowsWithoutUsingRealCache() throws {
        let url = try temporaryDirectory().appendingPathComponent("unavailable.plist")
        XCTAssertThrowsError(try SaverArchive.read(from: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor
    func testRealArchiveRendersOffscreenInMetalAndAdvancesTime() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal is unavailable on this host.") }
        let archive: SaverArchive
        if FileManager.default.fileExists(atPath: SaverArchive.url.path) {
            archive = try SaverArchive.read()
        } else {
            archive = try await capturedArchive()
        }
        let display = try XCTUnwrap(archive.displays.first)
        let wallpaper = try XCTUnwrap(SaverArchive.image(display.wallpaper))
        let renderer = try ChaosRenderer(device: device, scene: display.scene(), screenSize: display.size,
                                         pixelScale: 1, wallpaper: wallpaper, settings: archive.settings)
        renderer.simulate(1 / 60)
        let image = try XCTUnwrap(renderer.snapshot())
        XCTAssertEqual(image.width, Int(display.size.width))
        XCTAssertEqual(image.height, Int(display.size.height))
        XCTAssertGreaterThan(renderer.elapsed, 0)
        XCTAssertEqual(renderer.frames, 1)
        XCTAssertNotNil(image.dataProvider?.data)
    }

    func testPreviousIdleTimePersistsAndClearsInIsolatedSettings() throws {
        let defaults = try isolatedDefaults()
        let settings = Settings(defaults: defaults)
        XCTAssertNil(settings.chaosPreviousIdleSeconds)
        let realIdleTime = PaperSaver().getIdleTime()
        settings.chaosPreviousIdleSeconds = realIdleTime
        XCTAssertEqual(Settings(defaults: defaults).chaosPreviousIdleSeconds, realIdleTime)
        settings.chaosPreviousIdleSeconds = nil
        XCTAssertNil(Settings(defaults: defaults).chaosPreviousIdleSeconds)
        XCTAssertNil(defaults.object(forKey: "chaosPreviousIdleSeconds"))
    }

    @MainActor
    func testUnpackagedRunnerReportsEnableFailureWithoutChangingSystemSelection() async throws {
        let original = try StoreFile().readRaw()
        let settings = Settings(defaults: try isolatedDefaults())
        let manager = SystemScreenSaver(settings: settings)
        await manager.setEnabled(true)
        XCTAssertFalse(settings.chaosEnabled)
        XCTAssertFalse(manager.isChanging)
        XCTAssertNotNil(manager.errorMessage)
        XCTAssertEqual(try StoreFile().readRaw(), original, "An unpackaged runner cannot install or select a saver")
    }

    @MainActor
    func testInactiveIdleControlClampsOnlyIsolatedPreferences() async throws {
        let original = PaperSaver().getIdleTime()
        let settings = Settings(defaults: try isolatedDefaults())
        let manager = SystemScreenSaver(settings: settings)
        manager.setIdleMinutes(0)
        XCTAssertEqual(settings.chaosIdleMinutes, Settings.chaosIdleRange.lowerBound)
        manager.setIdleMinutes(1000)
        XCTAssertEqual(settings.chaosIdleMinutes, Settings.chaosIdleRange.upperBound)
        XCTAssertEqual(PaperSaver().getIdleTime(), original)
        XCTAssertNil(manager.errorMessage)
    }

    @MainActor
    func testSystemSaverControlsLayOutWithActualManagerAndIsolatedSettings() async throws {
        _ = NSApplication.shared
        let settings = Settings(defaults: try isolatedDefaults())
        let manager = SystemScreenSaver(settings: settings)
        defer { manager.stopWatching() }
        let view = NSHostingView(rootView: SystemSaverControls(manager: manager, settings: settings))
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.frame.size, NSSize(width: 640, height: 480))
        XCTAssertGreaterThan(view.subviews.count, 0)
        XCTAssertGreaterThan(view.fittingSize.height, 0)
        XCTAssertFalse(manager.isChanging)
        XCTAssertNil(manager.errorMessage)
        XCTAssertFalse(settings.chaosEnabled, "Layout must never enable the system saver")
    }
}