// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
@preconcurrency import ApplicationServices
import CoreVideo
import KinetiqCore
@testable import KinetiqEffects
import Metal
import QuartzCore
import class SwiftUI.NSHostingView
import XCTest
@testable import Kinetiq

/// Real preferences, AppKit windows, ScreenCaptureKit IOSurfaces and Metal commands.
/// Only windows created here may be closed, moved or minimized. Desktop metadata is
/// read-only. No screenshot is persisted unless KINETIQ_LIQUID_TEST_DUMP opts in.
final class LiquidIntegrationTests: XCTestCase {
    @MainActor private static var preparedApplication = false

    private func preferences() throws -> (Settings, UserDefaults) {
        let suite = "io.github.invernomut0.Kinetiq.liquid-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return (Settings(defaults: defaults), defaults)
    }

    func testLiquidStableChoiceAndIsolatedPreferencesRoundTrip() throws {
        let (settings, defaults) = try preferences()
        XCTAssertEqual(CloseEffectChoice.liquid.rawValue, "liquid")
        XCTAssertEqual(MinimizeEffectChoice.liquid.rawValue, "liquid")
        for choice in [CloseEffectChoice.off, .random, .liquid] + CloseEffect.allCases.map(CloseEffectChoice.effect) {
            settings.closeEffect = choice
            XCTAssertEqual(defaults.string(forKey: "closeEffect"), choice.rawValue)
            XCTAssertEqual(Settings(defaults: defaults).closeEffect, choice)
        }
        for choice in [MinimizeEffectChoice.off, .random, .liquid] + DockMorphStyle.allCases.map(MinimizeEffectChoice.morph) {
            settings.minimizeEffect = choice
            XCTAssertEqual(defaults.string(forKey: "minimizeEffect"), choice.rawValue)
            XCTAssertEqual(Settings(defaults: defaults).minimizeEffect, choice)
        }
        settings.closeEffect = .liquid
        settings.minimizeEffect = .liquid
        var generator = SystemRandomNumberGenerator()
        XCTAssertNil(settings.closeEffect.resolve(using: &generator), "Liquid must not resolve to a bounded close shader")
        XCTAssertFalse(CloseEffect.allCases.map(\.rawValue).contains("liquid"))
    }

    func testDefaultsLegacyMigrationAndResetDoNotSilentlyEnableLiquid() throws {
        let (settings, defaults) = try preferences()
        XCTAssertEqual(settings.closeEffect, Settings.defaultCloseEffect)
        XCTAssertEqual(settings.minimizeEffect, .off)
        XCTAssertEqual(settings.openEffect, .off)
        for effect in CloseEffect.allCases {
            defaults.set(effect.rawValue, forKey: "closeEffect")
            defaults.set(effect.rawValue, forKey: "minimizeEffect")
            XCTAssertEqual(settings.closeEffect, .effect(effect))
            XCTAssertEqual(settings.minimizeEffect, .morph(.genie), "Legacy minimize shaders stay enabled as Genie")
        }
        defaults.set("unknown-future-effect", forKey: "closeEffect")
        defaults.set("morph:unknown", forKey: "minimizeEffect")
        XCTAssertEqual(settings.closeEffect, .effect(.fire))
        XCTAssertEqual(settings.minimizeEffect, .morph(.genie))
        settings.closeEffect = .liquid
        settings.minimizeEffect = .liquid
        settings.appCloseEffects = ["com.apple.finder": "liquid"]
        settings.enabled = false
        settings.resetToDefaults()
        XCTAssertEqual(settings.closeEffect, Settings.defaultCloseEffect)
        XCTAssertEqual(settings.minimizeEffect, .off)
        XCTAssertTrue(settings.appCloseEffects.isEmpty)
        XCTAssertFalse(settings.enabled)
    }

    @MainActor
    func testPerAppLiquidOverridesAndFallbackUseInstalledAppIdentity() async throws {
        let url = try XCTUnwrap(NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder"))
        let id = try XCTUnwrap(Bundle(url: url)?.bundleIdentifier)
        let (settings, defaults) = try preferences()
        settings.closeEffect = .effect(.fire)
        let model = setupModel(settings)
        model.addAppEffect(id)
        model.setAppEffect(id, "liquid")
        XCTAssertEqual(Settings(defaults: defaults).closeEffect(forBundleID: id), .liquid)
        XCTAssertEqual(settings.closeEffect(forBundleID: nil), .effect(.fire))
        model.selectCloseEffect("liquid")
        model.setAppEffect(id, "off")
        XCTAssertEqual(settings.closeEffect(forBundleID: id), .off)
        XCTAssertEqual(settings.closeEffect(forBundleID: nil), .liquid)
        model.removeAppEffect(id)
        XCTAssertEqual(Settings(defaults: defaults).closeEffect(forBundleID: id), .liquid)
    }

    @MainActor
    func testLiquidPickersInRealNativeHostingViews() async throws {
        _ = try graphicalScreen()
        let (settings, _) = try preferences()
        settings.closeEffect = .liquid
        // Do not call selectMinimizeEffect: that method changes the user's Dock defaults.
        settings.minimizeEffect = .liquid
        settings.appCloseEffects = ["com.apple.finder": "liquid"]
        let model = setupModel(settings)
        for page in [ManagementPage.effects, .rules] {
            let host = NSHostingView(rootView: SetupControlsView(model: model, page: page))
            let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 720, height: 650),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.animationBehavior = .none
            window.contentView = host
            defer { window.close() }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            host.frame = NSRect(x: 0, y: 0, width: 720, height: 650)
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            try await pause(0.15)
            // SwiftUI can use semantic popup elements rather than NSPopUpButton subviews.
            let pickers = accessibilityElements(in: host).filter { accessibilityValue($0, "accessibilityRole") as? String == "AXPopUpButton" }
            let selectedLiquid = pickers.filter {
                (accessibilityValue($0, "accessibilityValue") as? String) == "Liquid"
                    || (accessibilityValue($0, "accessibilityTitle") as? String) == "Liquid"
            }
            XCTAssertGreaterThanOrEqual(selectedLiquid.count, page == .effects ? 2 : 1,
                                        "Persisted Liquid tags must select the real accessible pickers in \(page.title)")
        }
    }

    @MainActor
    func testCapturedREADMEThroughMetalMeltPoolFadeAndGlobalOrigins() async throws {
        let screen = try captureScreen()
        let device = try metalDevice()
        let window = try readmeWindow(on: screen)
        defer { window.close() }
        let capture = WindowCapture()
        let (info, frame) = try await captured(window, using: capture)
        let gpu = try GPU(device: device, frame: frame, screen: screen.cgFrame)
        let obstacles = WindowLocator.liquidObstacles(excluding: [info.id])
        let world = LiquidWorld(windowFrame: info.frame, screenBounds: screen.cgFrame, obstacles: obstacles)
        XCTAssertFalse(world.particles.isEmpty)
        let identity = world.particles.map(\.uv)
        let interior = info.frame.insetBy(dx: 24, dy: 35)
        let floor = CGRect(x: screen.cgFrame.minX, y: screen.cgFrame.maxY - max(70, CGFloat(world.spacing) * 6),
                           width: screen.cgFrame.width, height: max(70, CGFloat(world.spacing) * 6))
        var frames: [(Double, Pixels)] = []
        for time in [0.0, 0.4, 1, 2, 5, 8, 11] {
            advance(world, to: Float(time))
            assertFinite(world)
            let output = try gpu.render(world, screen: screen.cgFrame)
            frames.append((time, output))
            if time == 0 {
                XCTAssertGreaterThan(output.meanAlpha(in: interior, screen: screen.cgFrame), 0.98)
                XCTAssertLessThan(output.meanAlpha(in: floor, screen: screen.cgFrame), 0.01)
                // Compare actual captured color as well as alpha: a solid fake quad must fail.
                XCTAssertLessThan(try sourceDifference(output, frame: frame, info: info, screen: screen.cgFrame), 0.08)
                let delta = CGPoint(x: -screen.cgFrame.maxX - 137, y: -screen.cgFrame.maxY - 83)
                let shiftedScreen = screen.cgFrame.offsetBy(dx: delta.x, dy: delta.y)
                let translated = LiquidWorld(windowFrame: info.frame.offsetBy(dx: delta.x, dy: delta.y),
                                             screenBounds: shiftedScreen,
                                             obstacles: obstacles.map { $0.offsetBy(dx: delta.x, dy: delta.y) })
                let shifted = try gpu.render(translated, screen: shiftedScreen)
                XCTAssertLessThan(output.meanDifference(from: shifted), 0.002, "Global negative origins must not shift UVs or clip space")
            }
            if time == 2 {
                XCTAssertTrue(world.particles.allSatisfy(\.isReleased))
                let sampled = world.particles.filter { (0.15...0.85).contains($0.uv.x) && (0.15...0.85).contains($0.uv.y) }
                XCTAssertGreaterThan(sampled.map { output.alpha(at: CGPoint(x: CGFloat($0.position.x), y: CGFloat($0.position.y)), screen: screen.cgFrame) }.max() ?? 0, 0.5,
                                     "Released samples must form a visible density surface, not disappear with the source pass")
                XCTAssertGreaterThan(output.alphaMass, 20)
                XCTAssertLessThan(output.meanAlpha(in: interior, screen: screen.cgFrame), 0.8)
            }
            if time == 5 {
                XCTAssertEqual(world.alpha, 1, "The floor pool must linger before fading")
                XCTAssertGreaterThan(output.meanAlpha(in: floor, screen: screen.cgFrame), 0.001)
                XCTAssertGreaterThan(world.particles.filter { $0.position.y > Float(floor.minY) }.count, 0)
            }
        }
        XCTAssertEqual(world.particles.map(\.uv), identity)
        let pool = try XCTUnwrap(frames.first { $0.0 == 5 }?.1)
        let late = try XCTUnwrap(frames.last?.1)
        XCTAssertLessThan(late.alphaMass, pool.alphaMass, "Late opacity must fade the pooled surface")
        // Tall real displays may finish after eleven seconds. Verify the actual bounded lifetime too.
        advance(world, to: 14.1)
        XCTAssertTrue(world.isFinished)
        XCTAssertEqual(world.alpha, 0)
        XCTAssertEqual(try gpu.render(world, screen: screen.cgFrame).alphaMass, 0)
        try dumpIfRequested(frames)
    }

    /// Sharpness regression on a real README capture, at native display resolution. No desktop
    /// image or user-window geometry participates in the isolated simulation.
    @MainActor
    func testCapturedREADMEOpticsPreserveNativeTextContrast() async throws {
        let screen = try captureScreen()
        let device = try metalDevice()
        let window = try readmeWindow(on: screen)
        defer { window.close() }
        let (info, frame) = try await captured(window, using: WindowCapture())
        let bounds = screen.cgFrame
        let scale = screen.backingScaleFactor
        let gpu = try GPU(device: device, frame: frame, screen: bounds, targetPixelScale: scale)
        let world = LiquidWorld(windowFrame: info.frame, screenBounds: bounds, obstacles: [])
        let original = try capturedPixels(frame)
        XCTAssertEqual(gpu.target.width, Int(bounds.width * scale))
        XCTAssertEqual(gpu.target.height, Int(bounds.height * scale))
        let benchmark = ProcessInfo.processInfo.environment["KINETIQ_LIQUID_BENCHMARK"] == "1"
        print("LIQUID_OPTICS_PROFILE device=\(device.name) backingScale=\(scale) screenPoints=\(bounds) windowPoints=\(info.frame) sourcePixels=\(original.width)x\(original.height) sourceWindowPixels=\(frame.windowRect) targetPixels=\(gpu.target.width)x\(gpu.target.height) obstacles=0 benchmark=\(benchmark) framesPerState=40 warmup=3")
        var frames: [(Double, Pixels)] = []
        for time in [0.0, 0.12, 0.25, 0.5, 1.5, 5.0] {
            advance(world, to: Float(time))
            assertFinite(world)
            if benchmark && [0.5, 1.5, 5.0].contains(time) {
                let timing = try gpu.benchmark(world, screen: bounds, frames: 40)
                XCTAssertEqual(timing.gpuMilliseconds.count, 40)
                XCTAssertTrue(timing.gpuMilliseconds.allSatisfy { $0.isFinite && $0 > 0 },
                              "Metal must supply actual completed-command GPU timestamps")
                print(String(format: "LIQUID_OPTICS_GPU time=%.3f particles=%d released=%d targetPixels=%dx%d frames=%d gpuSumMS=%.3f gpuMeanMS=%.3f gpuMedianMS=%.3f gpuP95MS=%.3f cpuEncodeSubmitWaitMeanMS=%.3f",
                             time, world.particles.count, world.particles.filter(\.isReleased).count,
                             gpu.target.width, gpu.target.height, timing.gpuMilliseconds.count,
                             timing.gpuMilliseconds.reduce(0, +), timing.meanGPU, timing.percentile(0.5),
                             timing.percentile(0.95), timing.cpuMilliseconds.reduce(0, +) / Double(timing.cpuMilliseconds.count)))
            }
            let output = try gpu.render(world, screen: bounds)
            XCTAssertGreaterThan(output.alphaMass, 0, "The benchmark must render the captured document, not an empty target")
            if time == 0 {
                XCTAssertLessThan(try sourceDifference(output, frame: frame, info: info, screen: bounds), 0.08)
            } else {
                let metrics = transportContrast(output, original: original, frame: frame,
                                                info: info, world: world, screen: bounds)
                print(String(format: "LIQUID_OPTICS_TRANSPORT time=%.3f coherentEdgeSamples=%d expectedRGBContrast=%.6f renderedRGBContrast=%.6f contrastRatio=%.6f materialUVRGBError=%.6f",
                             time, metrics.count, metrics.expected, metrics.rendered, metrics.ratio, metrics.error))
                if time == 1.5 {
                    // Keep production optics enabled: tolerate their small displacement
                    // and lighting, but reject the old preblurred RGB field (~0.128).
                    XCTAssertGreaterThan(metrics.count, 32, "The real capture must supply enough coherent text edges")
                    XCTAssertGreaterThan(metrics.ratio, 0.65, "Released text must retain native-resolution edge contrast")
                    XCTAssertLessThan(metrics.error, 0.18, "Transported material must retain the captured document colors")
                }
            }
            frames.append((time, output))
        }
        try dumpIfRequested(frames)
    }

    /// Compare the public automatic path with explicit float32 bilinear reconstruction.
    @MainActor
    func testCapturedREADMEManualFieldFilteringMatchesAutomatic() async throws {
        let screen = try captureScreen()
        let device = try metalDevice()
        let window = try readmeWindow(on: screen)
        defer { window.close() }
        let (info, frame) = try await captured(window, using: WindowCapture())
        let bounds = screen.cgFrame
        let automatic = try GPU(device: device, frame: frame, screen: bounds,
                                targetPixelScale: screen.backingScaleFactor)
        let manual = try GPU(device: device, frame: frame, screen: bounds,
                             targetPixelScale: screen.backingScaleFactor, manualFieldFiltering: true)
        let world = LiquidWorld(windowFrame: info.frame, screenBounds: bounds, obstacles: [])
        advance(world, to: 1.5)
        assertFinite(world)
        let expected = try automatic.render(world, screen: bounds)
        let actual = try manual.render(world, screen: bounds)
        let difference = actual.visibleDifference(from: expected)
        print("LIQUID_OPTICS_FILTER hardwareFloat32Filtering=\(device.supports32BitFloatFiltering) visiblePixels=\(difference.count) rgbaError=\(difference.rgba) alphaError=\(difference.alpha) maxAlphaError=\(difference.maxAlpha)")
        XCTAssertGreaterThan(difference.count, 32, "Equivalence must compare actual visible fluid, not empty targets")
        XCTAssertLessThan(actual.meanDifference(from: expected), 0.002)
        XCTAssertLessThan(difference.rgba, 0.002, "Transparent screen area must not hide a filtering discrepancy")
        XCTAssertLessThan(difference.alpha, 0.002)
        XCTAssertLessThanOrEqual(difference.maxAlpha, 2.0 / 255, "Coverage may differ by at most two BGRA8 steps")
    }

    /// Freeze real simulated fluid, including its pool, while changing only optical strengths.
    @MainActor
    func testCapturedREADMERefractionAndReflectionLeaveAlphaUnchanged() async throws {
        let screen = try captureScreen()
        let device = try metalDevice()
        let window = try readmeWindow(on: screen)
        defer { window.close() }
        let (info, frame) = try await captured(window, using: WindowCapture())
        let bounds = screen.cgFrame
        let gpu = try GPU(device: device, frame: frame, screen: bounds,
                          targetPixelScale: screen.backingScaleFactor)
        XCTAssertEqual(gpu.renderer.opticalStrength, SIMD2<Float>(1, 1))
        let world = LiquidWorld(windowFrame: info.frame, screenBounds: bounds, obstacles: [])
        for time: Float in [1.5, 5] {
            advance(world, to: time)
            assertFinite(world)
            var outputs: [Pixels] = []
            for strength in [SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(0, 1), SIMD2<Float>(1, 1)] {
                gpu.renderer.opticalStrength = strength
                outputs.append(try gpu.render(world, screen: bounds))
            }
            // Both effects must work independently AND when the other effect is enabled.
            for (a, b) in [(0, 1), (0, 2), (1, 3), (2, 3)] {
                XCTAssertTrue(stride(from: 3, to: outputs[a].bytes.count, by: 4).allSatisfy {
                    outputs[a].bytes[$0] == outputs[b].bytes[$0]
                }, "Optics must preserve every alpha byte at \(time)s (\(a) vs \(b))")
                let difference = outputs[a].visibleDifference(from: outputs[b])
                print("LIQUID_OPTICS_ISOLATION time=\(time) pair=\(a),\(b) visiblePixels=\(difference.count) changedRGBPixels=\(difference.changedRGB) rgbError=\(difference.rgb)")
                XCTAssertGreaterThan(difference.changedRGB, 32, "Each optical control must visibly affect the actual captured material")
                XCTAssertGreaterThan(difference.rgb, 0.0001, "Optical controls must not be inert at \(time)s (\(a) vs \(b))")
            }
        }
    }

    @MainActor
    func testRealPlayerStartsBelowDockCoversScreensAndCancels() async throws {
        let screen = try captureScreen()
        _ = try metalDevice()
        let window = try readmeWindow(on: screen)
        defer { window.close() }
        let secondWindow = try readmeWindow(on: screen)
        defer { secondWindow.close() }
        let thirdWindow = try readmeWindow(on: screen)
        defer { thirdWindow.close() }
        let capture = WindowCapture()
        // All three sources remain real, live windows throughout capture and playback.
        let (info, frame) = try await captured(window, using: capture)
        let (secondInfo, secondFrame) = try await captured(secondWindow, using: capture)
        let (thirdInfo, thirdFrame) = try await captured(thirdWindow, using: capture)
        XCTAssertEqual(Set([frame.windowID, secondFrame.windowID, thirdFrame.windowID]).count, 3)
        let player = try XCTUnwrap(LiquidEffectPlayer.make(), "Metal exists: player initialization must succeed")
        let existing = Set(NSApp.windows.map(\.windowNumber))
        defer {
            player.cancelAll()
            NSApp.windows.filter { !existing.contains($0.windowNumber) }.forEach { $0.close() }
        }
        XCTAssertFalse(player.hasScene)
        XCTAssertTrue(player.sceneBounds.isNull)
        XCTAssertTrue(player.play(frame, windowFrame: info.frame, durationScale: 1))
        XCTAssertTrue(player.hasScene)
        XCTAssertFalse(player.play(frame, windowFrame: info.frame, durationScale: 1), "An active source must reject duplicate playback")
        XCTAssertTrue(player.play(secondFrame, windowFrame: secondInfo.frame, durationScale: 1),
                  "Rejecting a duplicate must not consume the second distinct-source slot")
        XCTAssertFalse(player.play(thirdFrame, windowFrame: thirdInfo.frame, durationScale: 1),
                   "A third real capture must be rejected while two distinct sources are active")
        let expected = NSScreen.screens.filter { $0.cgFrame.intersects(info.frame) }
            .reduce(CGRect.null) { $0.union($1.cgFrame) }
        XCTAssertEqual(player.sceneBounds, expected)
        let overlays = NSApp.windows.filter { !existing.contains($0.windowNumber) && $0.isVisible }
        XCTAssertEqual(overlays.count, NSScreen.screens.count)
        for overlay in overlays {
            XCTAssertEqual(overlay.level.rawValue, Int(CGWindowLevelForKey(.dockWindow)) - 1)
            XCTAssertTrue(overlay.ignoresMouseEvents)
            XCTAssertFalse(overlay.isOpaque)
            XCTAssertTrue(NSScreen.screens.contains { $0.frame == overlay.frame })
        }
        try await pause(0.08)
        player.cancelAll()
        XCTAssertFalse(player.hasScene)
        XCTAssertTrue(player.sceneBounds.isNull)
        XCTAssertTrue(overlays.allSatisfy { !$0.isVisible })
        player.cancelAll()
        XCTAssertTrue(player.play(thirdFrame, windowFrame: thirdInfo.frame, durationScale: 0.25), "Cancel must release distinct-source capacity immediately")
        XCTAssertTrue(player.play(frame, windowFrame: info.frame, durationScale: 0.25), "Cancel must allow immediate restart of a previous source")
        XCTAssertFalse(player.play(secondFrame, windowFrame: secondInfo.frame, durationScale: 0.25))
        player.cancelAll()
    }

    @MainActor
    func testRealPlayerCancelsOnLocalSpaceAndSleepNotifications() async throws {
        let screen = try captureScreen()
        _ = try metalDevice()
        let window = try readmeWindow(on: screen)
        defer { window.close() }
        let (info, frame) = try await captured(window, using: WindowCapture())
        let existing = Set(NSApp.windows.map(\.windowNumber))
        let player = try XCTUnwrap(LiquidEffectPlayer.make())
        defer {
            player.cancelAll()
            NSApp.windows.filter { !existing.contains($0.windowNumber) }.forEach { $0.close() }
        }
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.willSleepNotification] {
            XCTAssertTrue(player.play(frame, windowFrame: info.frame, durationScale: 1))
            XCTAssertTrue(player.hasScene)
            let overlays = NSApp.windows.filter { !existing.contains($0.windowNumber) && $0.isVisible }
            XCTAssertEqual(overlays.count, NSScreen.screens.count)
            try await pause(0.08) // Submit real GPU work before immediate scene removal.
            // Local delivery only: no distributed notification, actual Space switch or system sleep.
            // This can notify other observers in this test process, never other applications.
            NSWorkspace.shared.notificationCenter.post(name: name, object: nil)
            XCTAssertFalse(player.hasScene, "\(name.rawValue) must synchronously cancel the player")
            XCTAssertTrue(player.sceneBounds.isNull)
            XCTAssertTrue(overlays.allSatisfy { !$0.isVisible })
            try await pause(0.08)
            XCTAssertFalse(player.hasScene, "Queued display/GPU completion must not resurrect a cancelled scene")
        }
    }

    @MainActor
    func testLiveObstacleQueryExcludesSourceAndClipsCoveredTopGeometry() async throws {
        let screen = try graphicalScreen()
        let shelf = try readmeWindow(on: screen)
        let front = try readmeWindow(on: screen)
        defer { front.close(); shelf.close() }
        let shelfRect = shelf.frame
        front.setFrameOrigin(NSPoint(x: shelfRect.midX, y: shelfRect.minY + 45))
        shelf.orderFrontRegardless()
        front.orderFrontRegardless()
        try await pause(0.12)
        let sourceID = CGWindowID(front.windowNumber), shelfID = CGWindowID(shelf.windowNumber)
        let sourceFrame = try XCTUnwrap(WindowLocator.frame(of: sourceID))
        let shelfFrame = try XCTUnwrap(WindowLocator.frame(of: shelfID))
        let both = WindowLocator.liquidObstacles(excluding: [])
        let exposed = both.filter { abs($0.minY - shelfFrame.minY) < 0.1 && $0.minX >= shelfFrame.minX && $0.maxX <= shelfFrame.maxX }
        XCTAssertTrue(exposed.contains { abs($0.minX - shelfFrame.minX) < 0.1 && abs($0.maxX - sourceFrame.minX) < 0.1 },
                      "A foreground window must remove only the covered portion of the real shelf top")
        let excludingSource = WindowLocator.liquidObstacles(excluding: [sourceID])
        XCTAssertFalse(excludingSource.contains(sourceFrame))
        XCTAssertTrue(excludingSource.contains(shelfFrame), "Excluded source must neither collide nor occlude another top")
        XCTAssertFalse(WindowLocator.liquidObstacles(excluding: [sourceID, shelfID]).contains(shelfFrame))
        // Refresh from a real move of our disposable window, never from invented geometry.
        front.setFrameOrigin(NSPoint(x: front.frame.minX + 30, y: front.frame.minY + 20))
        try await pause(0.08)
        let moved = try XCTUnwrap(WindowLocator.frame(of: sourceID))
        XCTAssertNotEqual(moved, sourceFrame)
        let refreshed = WindowLocator.liquidObstacles(excluding: [shelfID])
        XCTAssertTrue(refreshed.contains(moved))
        XCTAssertFalse(refreshed.contains(sourceFrame))
    }

    @MainActor
    func testActualCloseOfDisposableWindowStartsLiquidScene() async throws {
        let screen = try captureScreen()
        _ = try metalDevice()
        let document = try await childDocument(on: screen)
        let priorWindows = Set(NSApp.windows.map(\.windowNumber))
        let capture = WindowCapture()
        let info = document.info
        _ = await capture.refreshContent()
        let warm = try await capture.capture(info)
        XCTAssertTrue(warm.isPainted)
        let (settings, _) = try preferences()
        settings.closeEffect = .liquid
        let liquid = try XCTUnwrap(LiquidEffectPlayer.make())
        let shaders = try XCTUnwrap(CloseEffectPlayer.make())
        let trigger = CloseEffectTrigger(settings: settings, capture: capture, player: shaders, liquid: liquid, isBusy: { false })
        defer {
            trigger.cancelAll(); liquid.cancelAll()
            NSApp.windows.filter { !priorWindows.contains($0.windowNumber) }.forEach { $0.close() }
        }
        let point = document.closePoint
        XCTAssertEqual(try XCTUnwrap(WindowLocator.window(at: point)).id, info.id, "Test click must target only its own window")
        trigger.mouseDown(at: point, windows: WindowList())
        trigger.mouseUp()
        try await pause(0.2) // Let the real pending capture and opaque-window poll finish.
        XCTAssertFalse(liquid.hasScene, "Arming alone must never play the close animation")
        try document.send("close") // The child performs its actual red NSButton action and releases its document.
        let started = try await eventually(seconds: 1.2) { liquid.hasScene }
        XCTAssertFalse(WindowLocator.exists(info.id), "The actual AppKit close must destroy this test window, not merely hide it")
        XCTAssertTrue(started, "Actual close must route the captured window to the liquid player")
        XCTAssertFalse(shaders.hasScene, "Liquid must not be sent to a bounded shader")
    }

    @MainActor
    func testCloseTriggerCancelledWhileWatchingDoesNotPlayAfterActualClose() async throws {
        try await assertCloseTriggerCancellation(beforeClose: true)
    }

    @MainActor
    func testCloseTriggerCancelledImmediatelyAfterActualCloseDoesNotRestart() async throws {
        try await assertCloseTriggerCancellation(beforeClose: false)
    }

    /// Exercise genuine asynchronous capture and WindowServer disappearance without posting clicks.
    @MainActor
    private func assertCloseTriggerCancellation(beforeClose: Bool) async throws {
        let screen = try captureScreen()
        _ = try metalDevice()
        let document = try await childDocument(on: screen)
        let priorWindows = Set(NSApp.windows.map(\.windowNumber))
        let capture = WindowCapture()
        _ = await capture.refreshContent()
        let warm = try await capture.capture(document.info)
        XCTAssertTrue(warm.isPainted)
        let (settings, _) = try preferences()
        settings.closeEffect = .liquid
        let liquid = try XCTUnwrap(LiquidEffectPlayer.make())
        let shaders = try XCTUnwrap(CloseEffectPlayer.make())
        let trigger = CloseEffectTrigger(settings: settings, capture: capture, player: shaders, liquid: liquid, isBusy: { false })
        defer {
            trigger.cancelAll(); liquid.cancelAll()
            NSApp.windows.filter { !priorWindows.contains($0.windowNumber) }.forEach { $0.close() }
        }
        XCTAssertFalse(liquid.hasScene)
        XCTAssertFalse(shaders.hasScene)
        XCTAssertEqual(try XCTUnwrap(WindowLocator.window(at: document.closePoint)).id, document.info.id)
        trigger.mouseDown(at: document.closePoint, windows: WindowList())
        trigger.mouseUp()
        // Give the 4 ms watch poll time to observe the real opaque window before closing it.
        try await pause(0.2)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(WindowLocator.snapshot(of: document.info.id)).alpha, 0.99)
        XCTAssertFalse(liquid.hasScene, "Arming an opaque document must not start playback")
        if beforeClose {
            trigger.cancelAll()
            liquid.cancelAll()
        }
        try document.send("close")
        if !beforeClose {
            let closed = try await eventually(seconds: 1.2) { !WindowLocator.exists(document.info.id) }
            XCTAssertTrue(closed, "The disposable document must actually close before cancellation")
            // The poll may already have played: cancel both owners, exactly as the controller does.
            trigger.cancelAll()
            liquid.cancelAll()
        }
        XCTAssertFalse(liquid.hasScene)
        let closed = try await eventually(seconds: 1.2) { !WindowLocator.exists(document.info.id) }
        XCTAssertTrue(closed, "Cancellation must not prevent the child's genuine AppKit close")
        // The trigger has no public capture task to await. Observe continuously beyond its
        // 0.4 s latest-start limit, allowing pending captures and queued callbacks to settle.
        let restarted = try await eventually(seconds: 0.7) { liquid.hasScene || shaders.hasScene }
        XCTAssertFalse(restarted, "Cancelled capture/watch work must never start or restart an effect")
        XCTAssertTrue(liquid.sceneBounds.isNull)
    }

    @MainActor
    func testYellowClickMinimizesOnlyDisposableWindowAndRestoresAXParking() async throws {
        guard AXIsProcessTrusted() else { throw XCTSkip("Accessibility permission is required for the real yellow-button/AX integration") }
        let screen = try captureScreen()
        _ = try metalDevice()
        let document = try await childDocument(on: screen)
        let priorWindows = Set(NSApp.windows.map(\.windowNumber))
        let capture = WindowCapture()
        let info = document.info
        _ = await capture.refreshContent()
        let warm = try await capture.capture(info)
        XCTAssertTrue(warm.isPainted)
        let liquid = try XCTUnwrap(LiquidEffectPlayer.make())
        let morph = try XCTUnwrap(MorphPlayer())
        let (settings, _) = try preferences()
        settings.minimizeEffect = .liquid // Avoid DockGenie.sync and any user preference changes.
        let point = document.minimizePoint
        let element: AXUIElement? = await withCheckedContinuation { continuation in
            AXBridge.queue(for: info.pid).async {
                continuation.resume(returning: AXBridge.findWindow(info, hitPoint: point))
            }
        }
        let ownElement = try XCTUnwrap(element.flatMap { AXBridge.windowID(of: $0) == info.id ? $0 : nil },
                           "Granted AX must expose the exact disposable window; never park another element")
        let trigger = MinimizeEffectTrigger(settings: settings, capture: capture, morph: morph, liquid: liquid, isBusy: { false },
                                            replay: { down, up in
            // Genuine fallback action in our child only; never post events onto user windows.
            if down.location == point && up.location == point { try? document.send("yellow") }
        })
        defer {
            trigger.cancel(); liquid.cancelAll()
            NSApp.windows.filter { !priorWindows.contains($0.windowNumber) }.forEach { $0.close() }
        }
        XCTAssertEqual(try XCTUnwrap(WindowLocator.window(at: point)).id, info.id)
        let down = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left))
        let up = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left))
        XCTAssertTrue(trigger.mouseDown(down, windows: WindowList()), "Actual yellow-button geometry must arm the trigger")
        XCTAssertTrue(trigger.isPending)
        XCTAssertTrue(trigger.mouseUp(up))
        let deadline = CACurrentMediaTime() + 4
        var state = await axState(ownElement)
        while CACurrentMediaTime() < deadline,
              !state.minimized || state.frame.map({ abs($0.minX - info.frame.minX) >= 2 || abs($0.minY - info.frame.minY) >= 2 }) != false {
            try await pause(0.03)
            state = await axState(ownElement)
        }
        XCTAssertTrue(state.minimized)
        XCTAssertTrue(liquid.hasScene, "Native fallback alone is not a successful liquid minimize")
        XCTAssertEqual(try XCTUnwrap(state.frame).minX, info.frame.minX, accuracy: 2, "AX parking must restore X while minimized")
        XCTAssertEqual(try XCTUnwrap(state.frame).minY, info.frame.minY, accuracy: 2, "AX parking must restore Y while minimized")
        XCTAssertFalse(trigger.isPending)
        try document.send("restore")
        let visible = try await eventually(seconds: 2) {
            guard let entries = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return false }
            return entries.contains { ($0[kCGWindowNumber as String] as? Int) == Int(info.id) }
        }
        XCTAssertTrue(visible)
    }

    // MARK: - Real desktop fixtures

    @MainActor
    private func graphicalScreen() throws -> NSScreen {
        _ = NSApplication.shared
        guard let screen = NSScreen.screens.first, screen.frame.width > 0, screen.frame.height > 0,
              CGSessionCopyCurrentDictionary() != nil else { throw XCTSkip("A live graphical WindowServer session is required") }
        if !Self.preparedApplication {
            // XCTest does not run NSApplicationMain. AX and NSRunningApplication need
            // a registered native application, not just an allocated NSApplication.
            NSApp.setActivationPolicy(.regular)
            NSApp.finishLaunching()
            if AXIsProcessTrusted() {
                let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
                AXUIElementSetAttributeValue(application, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            }
            Self.preparedApplication = true
        }
        return screen
    }

    @MainActor
    private func captureScreen() throws -> NSScreen {
        let screen = try graphicalScreen()
        guard CGPreflightScreenCaptureAccess() else { throw XCTSkip("Screen Recording permission is not granted; tests never prompt") }
        return screen
    }

    private func metalDevice() throws -> MTLDevice {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device is available") }
        return device
    }

    /// Opaque native document content, not a generated texture or fabricated image.
    @MainActor
    private func readmeWindow(on screen: NSScreen) throws -> NSWindow {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: repository.appendingPathComponent("README.md"), encoding: .utf8)
        XCTAssertFalse(text.isEmpty)
        let visible = screen.visibleFrame
        let rect = NSRect(x: visible.minX + 35, y: visible.minY + 80,
                          width: min(420, visible.width * 0.6), height: min(230, visible.height * 0.4))
        let window = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Kinetiq Liquid Integration — README.md"
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.isOpaque = true
        window.backgroundColor = .textBackgroundColor
        let scroll = NSScrollView(frame: NSRect(origin: .zero, size: rect.size))
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]
        let document = NSTextView(frame: scroll.contentView.bounds)
        document.string = text
        document.isEditable = false
        document.isRichText = false
        document.drawsBackground = true
        document.backgroundColor = .textBackgroundColor
        document.textColor = .textColor
        document.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        document.isVerticallyResizable = true
        document.autoresizingMask = [.width]
        document.textContainer?.widthTracksTextView = true
        scroll.documentView = document
        window.contentView = scroll
        window.orderFrontRegardless()
        window.displayIfNeeded()
        return window
    }

    @MainActor
    private func captured(_ window: NSWindow, using capture: WindowCapture) async throws -> (WindowInfo, CapturedFrame) {
        try await pause(0.12)
        let id = CGWindowID(window.windowNumber)
        let rect = try XCTUnwrap(WindowLocator.frame(of: id), "Disposable window must exist in the real WindowServer list")
        let info = WindowInfo(id: id, pid: ProcessInfo.processInfo.processIdentifier, frame: rect)
        let refreshed = await capture.refreshContent()
        let content = try XCTUnwrap(refreshed, "Granted Screen Recording must provide shareable content")
        XCTAssertTrue(content.windows.contains { $0.windowID == id })
        let frame = try await capture.capture(info)
        XCTAssertEqual(frame.windowID, id)
        XCTAssertEqual(frame.pointSize, rect.size)
        XCTAssertTrue(frame.isPainted)
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(frame.pixelBuffer), kCVPixelFormatType_32BGRA)
        return (info, frame)
    }

    @MainActor
    private func setupModel(_ settings: Settings) -> SetupModel {
        SetupModel(settings: settings, closeEffectChanged: {}, startChaos: {}, enabledChanged: {},
                   runtimeStatus: { ManagementRuntimeStatus(metalAvailable: MTLCreateSystemDefaultDevice() != nil, eventTapRunning: false) })
    }

    @MainActor
    private func accessibilityElements(in root: Any) -> [NSObject] {
        var visited = Set<ObjectIdentifier>()
        func visit(_ item: Any) -> [NSObject] {
            guard let element = item as? NSObject,
                  visited.insert(ObjectIdentifier(element)).inserted else { return [] }
            return [element] + ((accessibilityValue(element, "accessibilityChildren") as? [Any]) ?? []).flatMap { visit($0) }
        }
        return visit(root)
    }

    @MainActor
    private func accessibilityValue(_ element: NSObject, _ name: String) -> Any? {
        let selector = NSSelectorFromString(name)
        return element.responds(to: selector) ? element.perform(selector)?.takeUnretainedValue() : nil
    }

    private func axState(_ element: AXUIElement) async -> (frame: CGRect?, minimized: Bool) {
        await withCheckedContinuation { continuation in
            AXBridge.queue(for: element).async {
                var minimized: CFTypeRef?
                let status = AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &minimized)
                continuation.resume(returning: (AXBridge.frame(of: element), status == .success && (minimized as? Bool == true)))
            }
        }
    }

    /// AX changes must target a separate app: AppKit handles self-process AX mutations
    /// synchronously on the calling queue, where NSWindow movement would trap off-main.
    /// This child is a real native document, not a stand-in for an engine dependency.
    private final class ChildDocument {
        let process: Process
        let input: Pipe
        let info: WindowInfo
        let closePoint: CGPoint
        let minimizePoint: CGPoint

        init(process: Process, input: Pipe, info: WindowInfo, closePoint: CGPoint, minimizePoint: CGPoint) {
            self.process = process
            self.input = input
            self.info = info
            self.closePoint = closePoint
            self.minimizePoint = minimizePoint
        }

        func send(_ command: String) throws {
            try input.fileHandleForWriting.write(contentsOf: Data((command + "\n").utf8))
        }

        static func stop(process: Process, input: Pipe) async {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            // Reap only our helper, off the AppKit thread so AX/run-loop work can finish.
            await Task.detached { process.waitUntilExit() }.value
            XCTAssertFalse(process.isRunning, "Disposable AppKit helper must terminate before teardown completes")
        }
    }

    @MainActor
    private func childDocument(on screen: NSScreen) async throws -> ChildDocument {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let process = Process()
        let input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = ["-e", Self.childProgram, repository.appendingPathComponent("README.md").path,
                             String(Double(screen.visibleFrame.minX + 35)), String(Double(screen.visibleFrame.minY + 100))]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.standardError
        try process.run()
        addTeardownBlock { await ChildDocument.stop(process: process, input: input) }
        // The helper emits one small metadata line, never any captured or user content.
        let data = await Task.detached { output.fileHandleForReading.availableData }.value
        let parts = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|")
        guard parts.count == 5, let id = CGWindowID(parts[0]), let cx = Double(parts[1]), let cy = Double(parts[2]),
              let mx = Double(parts[3]), let my = Double(parts[4]) else {
            let diagnostic = process.isRunning ? "Invalid document metadata" : "Helper exited: \(process.terminationStatus); see helper stderr"
            XCTFail("Real AppKit helper failed: \(diagnostic.prefix(600))")
            throw CaptureError.windowNotShareable
        }
        try await pause(0.12)
        let info = WindowInfo(id: id, pid: process.processIdentifier,
                              frame: try XCTUnwrap(WindowLocator.frame(of: id)))
        let entries = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]]
        XCTAssertEqual(entries?.first?[kCGWindowOwnerPID as String] as? Int, Int(process.processIdentifier))
        XCTAssertEqual(entries?.first?[kCGWindowLayer as String] as? Int, 0, "Helper must remain a standard normal-level window")
        let closePoint = CGPoint(x: cx, y: cy), minimizePoint = CGPoint(x: mx, y: my)
        let front = try await eventually(seconds: 2) {
            WindowLocator.window(at: closePoint)?.id == id && WindowLocator.window(at: minimizePoint)?.id == id
        }
        guard front else {
            XCTFail("Helper is not frontmost: pid=\(process.processIdentifier) id=\(id) frame=\(info.frame) ownMetadata=\(entries ?? [])")
            throw CaptureError.windowNotShareable
        }
        return ChildDocument(process: process, input: input, info: info,
                             closePoint: closePoint, minimizePoint: minimizePoint)
    }

    /// Passed directly to the system Swift interpreter; no helper source files or app preferences are written.
    private static let childProgram = #"""
    import AppKit
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    app.finishLaunching()
    let arguments = CommandLine.arguments
    // Objects autoreleased before app.run() otherwise outlive its per-event pools,
    // keeping a closed NSWindow (and its WindowServer ID) alive until process exit.
    var window: NSWindow? = try autoreleasepool {
        let document = NSWindow(contentRect: NSRect(x: Double(arguments[2])!, y: Double(arguments[3])!, width: 420, height: 230),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        document.isReleasedWhenClosed = false
        document.animationBehavior = .none
        document.title = "Kinetiq Liquid Integration — README.md"
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 230))
        text.string = try String(contentsOfFile: arguments[1], encoding: .utf8)
        text.isEditable = false
        text.drawsBackground = true
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        document.contentView = text
        return document
    }
    func center(_ kind: NSWindow.ButtonType) -> CGPoint {
        let button = window!.standardWindowButton(kind)!
        let local = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        let p = window!.convertPoint(toScreen: local)
        return CGPoint(x: p.x, y: NSScreen.screens.first!.frame.height - p.y)
    }
    // readLine owns stdio buffering: do not mix it with descriptor-readiness callbacks,
    // which cannot see lines already buffered by stdio. Keep the reader alive for app.run().
    let reader = Thread {
        while let command = readLine() {
            DispatchQueue.main.async {
                autoreleasepool {
                    switch command {
                    case "close":
                        window?.standardWindowButton(.closeButton)?.performClick(nil)
                        window = nil
                    case "yellow": window?.standardWindowButton(.miniaturizeButton)?.performClick(nil)
                    case "restore": window?.deminiaturize(nil)
                    default: break
                    }
                }
            }
        }
        DispatchQueue.main.async { exit(0) }
    }
    reader.start()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        // Launch activation is asynchronous; make ordering the final operation after it.
        app.activate(ignoringOtherApps: true)
        window!.makeKeyAndOrderFront(nil)
        window!.orderFrontRegardless()
        window!.displayIfNeeded()
        let c = center(.closeButton), m = center(.miniaturizeButton)
        FileHandle.standardOutput.write(Data("\(window!.windowNumber)|\(c.x)|\(c.y)|\(m.x)|\(m.y)\n".utf8))
    }
    // A hard safety deadline also cleans up if the test host dies before closing stdin.
    DispatchQueue.main.asyncAfter(deadline: .now() + 20) { exit(0) }
    app.run()
    """#

    private func pause(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    @MainActor
    private func eventually(seconds: Double, _ condition: () -> Bool) async throws -> Bool {
        let deadline = CACurrentMediaTime() + seconds
        while !condition(), CACurrentMediaTime() < deadline { try await pause(0.02) }
        return condition()
    }

    private func advance(_ world: LiquidWorld, to seconds: Float) {
        let steps = max(0, Int(((seconds - world.elapsed) * 120).rounded()))
        for _ in 0..<steps { world.step(1 / 120) }
    }

    private func assertFinite(_ world: LiquidWorld, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(world.elapsed.isFinite && world.alpha.isFinite && (0...1).contains(world.alpha), file: file, line: line)
        XCTAssertTrue(world.particles.allSatisfy {
            $0.position.x.isFinite && $0.position.y.isFinite && $0.velocity.x.isFinite && $0.velocity.y.isFinite
                && $0.uv.x.isFinite && $0.uv.y.isFinite && $0.releaseTime.isFinite
                && world.screenBounds.insetBy(dx: -0.1, dy: -0.1).contains(CGPoint(x: CGFloat($0.position.x), y: CGFloat($0.position.y)))
        }, "Simulation must retain finite, screen-bounded samples", file: file, line: line)
    }

    // MARK: - Offscreen Metal, backed exclusively by the real captured IOSurface

    private final class GPU {
        let device: MTLDevice
        let queue: MTLCommandQueue
        let renderer: LiquidEffectRenderer
        let cache: CVMetalTextureCache
        let backing: CVMetalTexture
        let source: MTLTexture
        let uv: SIMD4<Float>
        let target: MTLTexture

        init(device: MTLDevice, frame: CapturedFrame, screen: CGRect, targetPixelScale: CGFloat? = nil,
             manualFieldFiltering: Bool? = nil) throws {
            self.device = device
            queue = try XCTUnwrap(device.makeCommandQueue())
            if let manualFieldFiltering {
                renderer = try LiquidEffectRenderer(device: device, manualFieldFiltering: manualFieldFiltering)
            } else {
                renderer = try LiquidEffectRenderer(device: device)
            }
            var cache: CVMetalTextureCache?
            XCTAssertEqual(CVMetalTextureCacheCreate(nil, nil, device, nil, &cache), kCVReturnSuccess)
            self.cache = try XCTUnwrap(cache)
            let w = CVPixelBufferGetWidth(frame.pixelBuffer), h = CVPixelBufferGetHeight(frame.pixelBuffer)
            var backing: CVMetalTexture?
            XCTAssertEqual(CVMetalTextureCacheCreateTextureFromImage(nil, self.cache, frame.pixelBuffer, nil,
                                                                    .bgra8Unorm, w, h, 0, &backing), kCVReturnSuccess)
            self.backing = try XCTUnwrap(backing)
            source = try XCTUnwrap(CVMetalTextureGetTexture(self.backing))
            uv = SIMD4(Float(frame.windowRect.minX) / Float(w), Float(frame.windowRect.minY) / Float(h),
                       Float(frame.windowRect.width) / Float(w), Float(frame.windowRect.height) / Float(h))
            let scale = targetPixelScale ?? min(1, 1000 / max(screen.width, screen.height))
            guard scale.isFinite, scale > 0 else {
                throw NSError(domain: "LiquidIntegrationTests", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Target pixel scale must be finite and positive"])
            }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                width: max(1, Int(screen.width * scale)), height: max(1, Int(screen.height * scale)), mipmapped: false)
            descriptor.storageMode = .shared
            descriptor.usage = [.renderTarget, .shaderRead]
            target = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        }

        /// Encode the same real rendering path for readback and GPU-only timing.
        private func submit(_ world: LiquidWorld, screen: CGRect) throws -> MTLCommandBuffer {
            let command = try XCTUnwrap(queue.makeCommandBuffer())
            let clear = MTLRenderPassDescriptor()
            clear.colorAttachments[0].texture = target
            clear.colorAttachments[0].loadAction = .clear
            clear.colorAttachments[0].storeAction = .store
            clear.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            let encoder = try XCTUnwrap(command.makeRenderCommandEncoder(descriptor: clear))
            encoder.endEncoding()
            renderer.encode(world: world, texture: source, uvRect: uv, into: command, target: target, screenRect: screen)
            command.commit()
            command.waitUntilCompleted()
            XCTAssertEqual(command.status, .completed, command.error?.localizedDescription ?? "Metal command failed")
            XCTAssertNil(command.error)
            return command
        }

        struct Timing {
            let gpuMilliseconds: [Double]
            let cpuMilliseconds: [Double]

            var meanGPU: Double { gpuMilliseconds.reduce(0, +) / Double(gpuMilliseconds.count) }

            func percentile(_ fraction: Double) -> Double {
                let sorted = gpuMilliseconds.sorted()
                return sorted[min(sorted.count - 1, max(0, Int(ceil(fraction * Double(sorted.count))) - 1))]
            }
        }

        /// Frozen simulation, three untimed warmups, no texture readback in the
        /// measured loop. GPU timestamps include target clear and all liquid passes;
        /// CPU timing includes encoding, submission and the completion wait.
        func benchmark(_ world: LiquidWorld, screen: CGRect, frames: Int) throws -> Timing {
            precondition(frames > 0)
            for _ in 0..<3 { _ = try submit(world, screen: screen) }
            var gpu: [Double] = [], cpu: [Double] = []
            for _ in 0..<frames {
                let begin = CACurrentMediaTime()
                let command = try submit(world, screen: screen)
                cpu.append((CACurrentMediaTime() - begin) * 1000)
                gpu.append((command.gpuEndTime - command.gpuStartTime) * 1000)
            }
            return Timing(gpuMilliseconds: gpu, cpuMilliseconds: cpu)
        }

        func render(_ world: LiquidWorld, screen: CGRect) throws -> Pixels {
            _ = try submit(world, screen: screen)
            var bytes = [UInt8](repeating: 0, count: target.width * target.height * 4)
            target.getBytes(&bytes, bytesPerRow: target.width * 4,
                            from: MTLRegionMake2D(0, 0, target.width, target.height), mipmapLevel: 0)
            return Pixels(width: target.width, height: target.height, bytes: bytes)
        }
    }

    private struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        var alphaMass: Double { stride(from: 3, to: bytes.count, by: 4).reduce(0) { $0 + Double(bytes[$1]) / 255 } }

        func offset(at point: CGPoint, screen: CGRect) -> Int {
            let x = min(width - 1, max(0, Int((point.x - screen.minX) / screen.width * CGFloat(width))))
            let y = min(height - 1, max(0, Int((point.y - screen.minY) / screen.height * CGFloat(height))))
            return (y * width + x) * 4
        }

        func alpha(at point: CGPoint, screen: CGRect) -> Double { Double(bytes[offset(at: point, screen: screen) + 3]) / 255 }

        /// Bilinear normalized RGB at Metal pixel-center coordinates. Source data
        /// is always the real captured BGRA buffer, never a manufactured texture.
        func rgb(x: Double, y: Double) -> SIMD3<Double> {
            let x = min(Double(width - 1), max(0, x)), y = min(Double(height - 1), max(0, y))
            let ix = Int(x), iy = Int(y), fx = x - Double(ix), fy = y - Double(iy)
            func color(_ px: Int, _ py: Int) -> SIMD3<Double> {
                let offset = (min(height - 1, py) * width + min(width - 1, px)) * 4
                return SIMD3(Double(bytes[offset + 2]), Double(bytes[offset + 1]), Double(bytes[offset])) / 255
            }
            return (color(ix, iy) * (1 - fx) + color(ix + 1, iy) * fx) * (1 - fy)
                + (color(ix, iy + 1) * (1 - fx) + color(ix + 1, iy + 1) * fx) * fy
        }

        func meanAlpha(in rect: CGRect, screen: CGRect) -> Double {
            let clipped = rect.intersection(screen)
            guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return 0 }
            var total = 0.0
            for y in 0..<30 {
                for x in 0..<60 {
                    total += alpha(at: CGPoint(x: clipped.minX + (CGFloat(x) + 0.5) * clipped.width / 60,
                                              y: clipped.minY + (CGFloat(y) + 0.5) * clipped.height / 30), screen: screen)
                }
            }
            return total / 1800
        }

        func meanDifference(from other: Pixels) -> Double {
            guard bytes.count == other.bytes.count else { return .infinity }
            return zip(bytes, other.bytes).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(bytes.count * 255)
        }

        /// Normalize over visible pixels only, so empty desktop cannot dilute errors.
        /// Maximum alpha error still covers every pixel, including transparent edges.
        func visibleDifference(from other: Pixels) -> (count: Int, changedRGB: Int, rgb: Double, rgba: Double, alpha: Double, maxAlpha: Double) {
            precondition(width == other.width && height == other.height)
            var count = 0, changedRGB = 0
            var rgb = 0.0, alpha = 0.0, maxAlpha = 0.0
            for offset in stride(from: 0, to: bytes.count, by: 4) {
                let alphaError = abs(Double(bytes[offset + 3]) - Double(other.bytes[offset + 3])) / 255
                maxAlpha = max(maxAlpha, alphaError)
                guard max(bytes[offset + 3], other.bytes[offset + 3]) > 25 else { continue }
                count += 1
                var colorError = 0.0
                for channel in 0..<3 {
                    colorError += abs(Double(bytes[offset + channel]) - Double(other.bytes[offset + channel])) / 255
                }
                if colorError > 0 { changedRGB += 1 }
                rgb += colorError
                alpha += alphaError
            }
            guard count > 0 else { return (0, 0, .infinity, .infinity, .infinity, maxAlpha) }
            return (count, changedRGB, rgb / Double(count * 3), (rgb + alpha) / Double(count * 4),
                    alpha / Double(count), maxAlpha)
        }

        func image() throws -> CGImage {
            let data = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
            return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little),
                provider: data, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        }
    }

    /// Copy only the README window's captured IOSurface, respecting its row stride.
    private func capturedPixels(_ frame: CapturedFrame) throws -> Pixels {
        let buffer = frame.pixelBuffer
        XCTAssertEqual(CVPixelBufferLockBaseAddress(buffer, .readOnly), kCVReturnSuccess)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        var bytes = [UInt8]()
        bytes.reserveCapacity(width * height * 4)
        for y in 0..<height { bytes.append(contentsOf: UnsafeBufferPointer(start: base + y * stride, count: width * 4)) }
        return Pixels(width: width, height: height, bytes: bytes)
    }

    private struct TransportContrast {
        var count = 0
        var expected = 0.0
        var rendered = 0.0
        var error = 0.0
        var ratio: Double { expected > 0 ? rendered / expected : 0 }
    }

    /// Material-UV reference from the actual released particles and the polynomial
    /// support kernel (1-r²)^3, radius 1.5 * spacing. Restrict to opaque text-content
    /// UVs, outside the intact source, with locally coherent transport. Reconstruct
    /// local UV offsets exactly as the shader does; optical lighting/displacement
    /// is deliberately not included in this unlit captured-material reference.
    private func transportContrast(_ output: Pixels, original: Pixels, frame: CapturedFrame,
                                   info: WindowInfo, world: LiquidWorld, screen: CGRect) -> TransportContrast {
        let particles = world.particles.filter(\.isReleased)
        let radius = Double(world.spacing) * 1.5
        let dx = Double(screen.width) / Double(output.width)
        let dy = Double(screen.height) / Double(output.height)
        func materialUV(_ point: CGPoint) -> SIMD2<Double>? {
            var weight = 0.0, moments = SIMD2<Double>.zero
            for particle in particles {
                let x = (Double(point.x) - Double(particle.position.x)) / radius
                let y = (Double(point.y) - Double(particle.position.y)) / radius
                let r2 = x * x + y * y
                guard r2 < 1 else { continue }
                // All contributors must be opaque document interior. No invented
                // alpha or source pixels are substituted for capture boundaries.
                guard (0.05...0.95).contains(particle.uv.x), (0.18...0.92).contains(particle.uv.y) else { return nil }
                let k = (1 - r2) * (1 - r2) * (1 - r2)
                weight += k
                let localUV = SIMD2((Double(point.x) - Double(particle.position.x)) / Double(info.frame.width),
                                    (Double(point.y) - Double(particle.position.y)) / Double(info.frame.height))
                moments += (SIMD2(Double(particle.uv.x), Double(particle.uv.y)) + localUV) * k
            }
            return weight > 0.8 ? moments / weight : nil
        }
        func source(_ uv: SIMD2<Double>) -> SIMD3<Double> {
            original.rgb(x: Double(frame.windowRect.minX) + uv.x * Double(frame.windowRect.width) - 0.5,
                         y: Double(frame.windowRect.minY) + uv.y * Double(frame.windowRect.height) - 0.5)
        }
        func magnitude(_ rgb: SIMD3<Double>) -> Double { (abs(rgb.x) + abs(rgb.y) + abs(rgb.z)) / 3 }
        var result = TransportContrast()
        var visited = Set<Int>()
        for particle in particles {
            let index = output.offset(at: CGPoint(x: CGFloat(particle.position.x), y: CGFloat(particle.position.y)), screen: screen)
            guard visited.insert(index).inserted else { continue }
            let px = index / 4 % output.width, py = index / 4 / output.width
            guard px > 0, px + 1 < output.width, py > 0, py + 1 < output.height else { continue }
            let center = CGPoint(x: Double(screen.minX) + (Double(px) + 0.5) * dx,
                                 y: Double(screen.minY) + (Double(py) + 0.5) * dy)
            guard !info.frame.insetBy(dx: -radius, dy: -radius).contains(center),
                  let uv = materialUV(center) else { continue }
            for axis in [CGPoint(x: dx, y: 0), CGPoint(x: 0, y: dy)] {
                let before = CGPoint(x: center.x - axis.x, y: center.y - axis.y)
                let after = CGPoint(x: center.x + axis.x, y: center.y + axis.y)
                guard output.alpha(at: before, screen: screen) > 0.98,
                      output.alpha(at: after, screen: screen) > 0.98,
                      let a = materialUV(before), let b = materialUV(after) else { continue }
                let curvature = (a + b - uv * 2) * SIMD2(Double(frame.windowRect.width), Double(frame.windowRect.height))
                guard abs(curvature.x) + abs(curvature.y) < 0.25 else { continue }
                let expected = magnitude(source(b) - source(a))
                guard expected > 0.08 else { continue } // Real readable edges, not blank background.
                let renderedA = output.rgb(x: Double(px) - Double(axis.x) / dx, y: Double(py) - Double(axis.y) / dy)
                let renderedB = output.rgb(x: Double(px) + Double(axis.x) / dx, y: Double(py) + Double(axis.y) / dy)
                result.count += 1
                result.expected += expected
                result.rendered += magnitude(renderedB - renderedA)
                result.error += (magnitude(renderedA - source(a)) + magnitude(renderedB - source(b))) / 2
            }
        }
        if result.count > 0 {
            result.expected /= Double(result.count)
            result.rendered /= Double(result.count)
            result.error /= Double(result.count)
        }
        return result
    }

    /// Compare interior RGB to real capture pixels, allowing linear resampling and P3 metadata differences.
    private func sourceDifference(_ output: Pixels, frame: CapturedFrame, info: WindowInfo, screen: CGRect) throws -> Double {
        let buffer = frame.pixelBuffer
        XCTAssertEqual(CVPixelBufferLockBaseAddress(buffer, .readOnly), kCVReturnSuccess)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var difference = 0.0
        for y in 1...8 {
            for x in 1...12 {
                let u = CGFloat(x) / 13, v = CGFloat(y) / 9
                let point = CGPoint(x: info.frame.minX + u * info.frame.width, y: info.frame.minY + v * info.frame.height)
                let out = output.offset(at: point, screen: screen)
                // Sample capture at the center of the actual output pixel, not the pre-quantized point.
                let px = out / 4 % output.width, py = out / 4 / output.width
                let gu = (screen.minX + (CGFloat(px) + 0.5) / CGFloat(output.width) * screen.width - info.frame.minX) / info.frame.width
                let gv = (screen.minY + (CGFloat(py) + 0.5) / CGFloat(output.height) * screen.height - info.frame.minY) / info.frame.height
                let sx = Int(frame.windowRect.minX + gu * frame.windowRect.width)
                let sy = Int(frame.windowRect.minY + gv * frame.windowRect.height)
                for c in 0..<3 { difference += abs(Double(base[sy * rowBytes + sx * 4 + c]) - Double(output.bytes[out + c])) / 255 }
            }
        }
        return difference / (8 * 12 * 3)
    }

    /// Explicit opt-in only. Resolve symlinks before enforcing the temporary-directory boundary.
    /// KINETIQ_LIQUID_TEST_DUMP_FRAMES=1 additionally saves unscaled standalone PNGs.
    @MainActor
    private func dumpIfRequested(_ frames: [(Double, Pixels)]) throws {
        guard let path = ProcessInfo.processInfo.environment["KINETIQ_LIQUID_TEST_DUMP"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        let temporary = URL(fileURLWithPath: "/tmp", isDirectory: true).resolvingSymlinksInPath()
        guard directory.path == temporary.path || directory.path.hasPrefix(temporary.path + "/") else {
            XCTFail("KINETIQ_LIQUID_TEST_DUMP must point inside /tmp; no desktop images were saved")
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        if ProcessInfo.processInfo.environment["KINETIQ_LIQUID_TEST_DUMP_FRAMES"] == "1" {
            for (index, entry) in frames.enumerated() {
                let bitmap = NSBitmapImageRep(cgImage: try entry.1.image())
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                let filename = String(format: "liquid-real-window-native-%02d-%.3fs.png", index, entry.0)
                let destination = directory.appendingPathComponent(filename)
                // Set restrictive permissions before writing any captured content.
                guard FileManager.default.createFile(atPath: destination.path, contents: nil,
                                                     attributes: [.posixPermissions: 0o600]) else {
                    throw NSError(domain: "LiquidIntegrationTests", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "Cannot create private native frame dump"])
                }
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
                try png.write(to: destination)
            }
        }
        let tileWidth = 480, labelHeight = 28
        let first = try XCTUnwrap(frames.first?.1)
        let tileHeight = max(1, tileWidth * first.height / first.width)
        let sheet = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: tileWidth * 4,
            pixelsHigh: (tileHeight + labelHeight) * 2, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: sheet))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        NSColor(calibratedWhite: 0.18, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: sheet.pixelsWide, height: sheet.pixelsHigh).fill()
        for (index, entry) in frames.enumerated() {
            let x = (index % 4) * tileWidth, y = (1 - index / 4) * (tileHeight + labelHeight)
            let image = NSImage(cgImage: try entry.1.image(), size: NSSize(width: entry.1.width, height: entry.1.height))
            image.draw(in: NSRect(x: x, y: y, width: tileWidth, height: tileHeight))
            let label = entry.0 == 0 ? "start · 0 s" : String(format: "%.1f s", entry.0)
            (label as NSString).draw(at: NSPoint(x: x + 10, y: y + tileHeight + 5),
                                    withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.white])
        }
        let png = try XCTUnwrap(sheet.representation(using: .png, properties: [:]))
        let destination = directory.appendingPathComponent("liquid-real-window-contact-sheet.png")
        try png.write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
}