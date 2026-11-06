// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
@preconcurrency import ApplicationServices
import CoreVideo
import Darwin
import KinetiqCore
@testable import KinetiqEffects
import KinetiqSaverSupport
import Metal
import QuartzCore
import class SwiftUI.NSHostingView
import XCTest
@testable import Kinetiq

/// Real preferences, AppKit windows, ScreenCaptureKit IOSurfaces and Metal commands.
/// Only windows created here may be closed, moved or minimized. Desktop metadata is
/// read-only. Screenshots require KINETIQ_LIQUID_TEST_DUMP or
/// KINETIQ_DESTRUCTION_TEST_DUMP to explicitly opt in.
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
    func testCapturedREADMEThroughMetalMeltPoolDrainAndGlobalOrigins() async throws {
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
        for time in [0.0, 0.4, 1, 2, 5, Double(world.drainStart) + 2, Double(world.drainStart) + 4, Double(world.duration)] {
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
                XCTAssertEqual(world.alpha, 1, "The floor pool must linger before draining")
                XCTAssertGreaterThan(output.meanAlpha(in: floor, screen: screen.cgFrame), 0.001)
                XCTAssertGreaterThan(world.particles.filter { $0.position.y > Float(floor.minY) }.count, 0)
            }
        }
        XCTAssertEqual(world.particles.map(\.uv), identity)
        let pool = try XCTUnwrap(frames.first { $0.0 == 5 }?.1)
        let late = try XCTUnwrap(frames.last?.1)
        XCTAssertLessThan(late.alphaMass, pool.alphaMass, "The material must leave the display, not fade")
        XCTAssertTrue(world.isFinished)
        XCTAssertTrue(world.particles.allSatisfy { $0.position.y > Float(screen.cgFrame.maxY) + world.spacing * 1.5 })
        XCTAssertEqual(world.alpha, 0)
        XCTAssertEqual(try gpu.render(world, screen: screen.cgFrame).alphaMass, 0)
        try dumpIfRequested(frames)
    }

    /// Actual captured material remains opaque while part of its pool flows offscreen.
    @MainActor
    func testCapturedREADMEPhysicalDrainRetainsOpaquePixelsUntilMaterialExits() async throws {
        let screen = try captureScreen()
        let window = try readmeWindow(on: screen)
        defer { window.close() }
        let (info, frame) = try await captured(window, using: WindowCapture())
        let bounds = screen.cgFrame
        let gpu = try GPU(device: metalDevice(), frame: frame, screen: bounds)
        let world = LiquidWorld(windowFrame: info.frame, screenBounds: bounds, obstacles: [])
        advance(world, to: world.drainStart)
        let pooled = try gpu.render(world, screen: bounds)
        var partialFrames = 0
        var opaquePartialFrames = 0
        while !world.isFinished && world.elapsed < world.duration {
            world.step(1 / 120)
            let exited = world.particles.filter { $0.position.y > Float(bounds.maxY) }.count
            if exited > 0, exited < world.particles.count / 2, partialFrames < 3 {
                let output = try gpu.render(world, screen: bounds)
                XCTAssertEqual(world.alpha, 1, "Visible material must not fade during drainage")
                if output.maximumAlpha > 0.98 { opaquePartialFrames += 1 }
                XCTAssertGreaterThan(output.alphaMass, 0)
                partialFrames += 1
                advance(world, to: world.elapsed + 0.15)
            }
        }
        XCTAssertGreaterThan(partialFrames, 0, "A real captured pool must leave the display progressively")
        XCTAssertGreaterThan(opaquePartialFrames, 0, "The remaining real material must retain fully opaque pixels")
        XCTAssertTrue(world.isFinished)
        XCTAssertTrue(world.particles.allSatisfy { $0.position.y > Float(bounds.maxY) + world.spacing * 1.5 })
        XCTAssertGreaterThan(pooled.alphaMass, 10)
        XCTAssertEqual(try gpu.render(world, screen: bounds).alphaMass, 0)
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
    private func assertCloseTriggerCancellation(beforeClose: Bool, choice: CloseEffectChoice = .liquid) async throws {
        let screen = try captureScreen()
        _ = try metalDevice()
        let document = try await childDocument(on: screen)
        let priorWindows = Set(NSApp.windows.map(\.windowNumber))
        let capture = WindowCapture()
        _ = await capture.refreshContent()
        let warm = try await capture.capture(document.info)
        XCTAssertTrue(warm.isPainted)
        let (settings, _) = try preferences()
        settings.closeEffect = choice
        let liquid = try XCTUnwrap(LiquidEffectPlayer.make())
        let shaders = try XCTUnwrap(CloseEffectPlayer.make())
        let destruction = choice == .destruction ? try XCTUnwrap(shaders.destructionPlayer) : nil
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
        XCTAssertFalse(destruction?.hasScene ?? false)
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
        let restarted = try await eventually(seconds: 0.7) { liquid.hasScene || shaders.hasScene || destruction?.hasScene == true }
        XCTAssertFalse(restarted, "Cancelled capture/watch work must never start or restart an effect")
        XCTAssertTrue(liquid.sceneBounds.isNull)
        if let destruction {
            XCTAssertFalse(destruction.hasScene)
            XCTAssertTrue(destruction.sceneBounds.isNull)
        }
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

    // MARK: - Real window destruction (shared native README fixtures)

    /// Global origins must not affect local material, extraction or native Metal output.
    @MainActor
    func testDestructionCapturedREADMENegativeOriginsPreserveSceneAndNativeSnapshots() async throws {
        let screen = try captureScreen()
        let device = try metalDevice()
        let window = try readmeWindow(on: screen)
        defer { window.close() }
        let (info, frame) = try await captured(window, using: WindowCapture())
        let bounds = screen.cgFrame
        let delta = CGPoint(x: -bounds.maxX - 137, y: -bounds.maxY - 83)
        let shiftedStage = bounds.offsetBy(dx: delta.x, dy: delta.y)
        let shiftedWindow = info.frame.offsetBy(dx: delta.x, dy: delta.y)
        XCTAssertLessThan(shiftedStage.maxX, 0)
        XCTAssertLessThan(shiftedStage.maxY, 0)
        XCTAssertLessThan(shiftedWindow.maxX, 0)
        XCTAssertLessThan(shiftedWindow.maxY, 0)
        let scene = try XCTUnwrap(DestructionScene.build(frame: frame, windowFrame: info.frame, stage: bounds))
        let translated = try XCTUnwrap(DestructionScene.build(frame: frame, windowFrame: shiftedWindow, stage: shiftedStage))
        try assertSameDestructionScene(scene, translated)
        XCTAssertTrue(scene.seeds.contains { $0.kind == .glyph })
        XCTAssertTrue(scene.seeds.contains { $0.kind == .shard })
        let renderer = try DestructionScene.renderer(device: device, scene: scene, size: bounds.size,
                                                     scale: screen.backingScaleFactor)
        let shifted = try DestructionScene.renderer(device: device, scene: translated, size: shiftedStage.size,
                                                    scale: screen.backingScaleFactor)
        let nativeFrame = window.frame
        var frames: [(Double, Pixels)] = []
        var tick = 0
        for time in [0.0, 0.3, 0.8, 1.4, 2.4, 6.0] {
            let target = Int((time * 120).rounded())
            while tick < target {
                renderer.simulate(1 / 120)
                shifted.simulate(1 / 120)
                tick += 1
            }
            let output = try destructionPixels(XCTUnwrap(renderer.snapshot()))
            let shiftedOutput = try destructionPixels(XCTUnwrap(shifted.snapshot()))
            XCTAssertEqual(output.width, Int(Float(bounds.width) * Float(screen.backingScaleFactor)))
            XCTAssertEqual(output.height, Int(Float(bounds.height) * Float(screen.backingScaleFactor)))
            XCTAssertEqual(output.width, shiftedOutput.width)
            XCTAssertEqual(output.height, shiftedOutput.height)
            XCTAssertTrue(output.bytes == shiftedOutput.bytes, "Negative global origins must preserve every GPU byte at \(time)s")
            if time == 0 { XCTAssertGreaterThan(output.alphaMass, 10) }
            if time == 6 {
                XCTAssertTrue(renderer.isFinished)
                XCTAssertTrue(shifted.isFinished)
                XCTAssertEqual(output.alphaMass, 0)
            }
            frames.append((time, output))
        }
        try dumpDestructionIfRequested(frames)
        XCTAssertEqual(window.frame, nativeFrame)
        XCTAssertTrue(window.isVisible && !window.isMiniaturized)
    }

    /// Two adjacent display stages partition the actual capture, not two copies of it.
    @MainActor
    func testDestructionCapturedREADMESplitStagesClipLocalHomesUVsAndSourceArea() async throws {
        let screen = try captureScreen()
        let device = try metalDevice()
        let window = try readmeWindow(on: screen)
        defer { window.close() }
        let (info, frame) = try await captured(window, using: WindowCapture())
        let source = try XCTUnwrap(DestructionScene.image(frame))
        // Put the shared edge on an actual captured pixel boundary, even at odd widths.
        let splitPixel = source.width / 2
        let splitX = info.frame.minX + CGFloat(splitPixel) / CGFloat(source.width) * info.frame.width
        let margin = info.frame.width * 0.25
        let stage = info.frame.insetBy(dx: -margin, dy: -margin)
        let stages = [CGRect(x: stage.minX, y: stage.minY, width: splitX - stage.minX, height: stage.height),
                      CGRect(x: splitX, y: stage.minY, width: stage.maxX - splitX, height: stage.height)]
        let crops = [CGRect(x: 0, y: 0, width: splitPixel, height: source.height),
                     CGRect(x: splitPixel, y: 0, width: source.width - splitPixel, height: source.height)]
        XCTAssertEqual(crops[0].maxX, crops[1].minX)
        XCTAssertEqual(crops.reduce(0) { $0 + $1.width * $1.height }, CGFloat(source.width * source.height))
        var globalFrames: [CGRect] = []
        var pictureArea = 0
        var shardArea: Double = 0
        for index in stages.indices {
            let display = stages[index]
            let visible = info.frame.intersection(display)
            let local = visible.offsetBy(dx: -display.minX, dy: -display.minY)
            let scene = try XCTUnwrap(DestructionScene.build(frame: frame, windowFrame: info.frame, stage: display))
            XCTAssertEqual(scene.frames, [local], "Each display must retain only its clipped local window frame")
            globalFrames.append(try XCTUnwrap(scene.frames.first).offsetBy(dx: display.minX, dy: display.minY))
            let picture = try XCTUnwrap(scene.pictures.first)
            XCTAssertEqual(scene.pictures.count, 1)
            XCTAssertEqual(picture.width, Int(crops[index].width))
            XCTAssertEqual(picture.height, source.height)
            pictureArea += picture.width * picture.height
            // Independent crop/extraction from the original captured image checks which
            // source half was used; dimensions alone would miss duplicated left pixels.
            let reference = try XCTUnwrap(UIObjectExtractor.extract(from: XCTUnwrap(source.cropping(to: crops[index])),
                size: visible.size, maxGlyphs: 1200, maxOthers: 160))
            try assertSameImagePixels(picture, reference.cleaned)
            XCTAssertEqual(scene.sprites.count, reference.objects.count)
            XCTAssertTrue(zip(scene.sprites, reference.objects).allSatisfy { $0.frame == $1.frame && $0.rgba == $1.rgba })
            XCTAssertFalse(scene.seeds.isEmpty)
            let shards = scene.seeds.filter { $0.kind == .shard }
            XCTAssertFalse(shards.isEmpty)
            let world = ChaosWorld(seeds: scene.seeds, size: SIMD2(Float(display.width), Float(display.height)),
                                   settings: ChaosSettings(seed: 42))
            XCTAssertEqual(world.bodies.map(\.home), scene.seeds.map(\.center))
            for seed in scene.seeds {
                XCTAssertEqual(seed.group, 0)
                XCTAssertTrue(local.insetBy(dx: -0.01, dy: -0.01).contains(CGPoint(x: CGFloat(seed.center.x), y: CGFloat(seed.center.y))))
                guard seed.kind == .shard else { continue }
                let polygon = try XCTUnwrap(seed.polygon)
                shardArea += Double(polygon.area)
                for vertex in polygon.verts {
                    let position = seed.center + vertex
                    XCTAssertTrue(local.insetBy(dx: -0.01, dy: -0.01).contains(CGPoint(x: CGFloat(position.x), y: CGFloat(position.y))))
                    let uv = polygon.uv(vertex)
                    XCTAssertEqual(uv.x, (position.x - Float(local.minX)) / Float(local.width), accuracy: 0.00001)
                    XCTAssertEqual(uv.y, (position.y - Float(local.minY)) / Float(local.height), accuracy: 0.00001)
                    XCTAssertTrue((-0.00001...1.00001).contains(uv.x) && (-0.00001...1.00001).contains(uv.y))
                }
            }
            let renderer = try DestructionScene.renderer(device: device, scene: scene, size: display.size,
                                                         scale: screen.backingScaleFactor)
            XCTAssertEqual(renderer.world.bodies.map(\.home), scene.seeds.map(\.center))
            XCTAssertGreaterThan(try destructionPixels(XCTUnwrap(renderer.snapshot())).alphaMass, 10)
        }
        XCTAssertEqual(globalFrames[0].maxX, globalFrames[1].minX, accuracy: 0.00001)
        XCTAssertEqual(globalFrames[0].union(globalFrames[1]), info.frame)
        XCTAssertEqual(globalFrames.reduce(0) { $0 + $1.width * $1.height }, info.frame.width * info.frame.height, accuracy: 0.001)
        XCTAssertEqual(pictureArea, source.width * source.height, "Captured source pixels must be partitioned, never duplicated")
        XCTAssertEqual(shardArea, Double(info.frame.width * info.frame.height), accuracy: Double(info.frame.width * info.frame.height) * 0.001)
    }

    /// Invalid metadata never licenses reading outside an actual captured IOSurface.
    @MainActor
    func testDestructionCapturedREADMERejectsMalformedRectsSizesAndDeclaredFormat() async throws {
        let screen = try captureScreen()
        let window = try readmeWindow(on: screen)
        defer { window.close() }
        let (info, frame) = try await captured(window, using: WindowCapture())
        XCTAssertNotNil(DestructionScene.build(frame: frame, windowFrame: info.frame, stage: screen.cgFrame))
        func metadata(rect: CGRect, size: CGSize? = nil, buffer: CVPixelBuffer? = nil) -> CapturedFrame {
            CapturedFrame(windowID: frame.windowID, pixelBuffer: buffer ?? frame.pixelBuffer,
                          pointSize: size ?? frame.pointSize, windowRect: rect,
                          shadow: frame.shadow, capturedAt: frame.capturedAt)
        }
        let width = CVPixelBufferGetWidth(frame.pixelBuffer), height = CVPixelBufferGetHeight(frame.pixelBuffer)
        for rect in [CGRect.zero, CGRect(x: 0, y: 0, width: 7, height: 8),
                     CGRect(x: -1, y: 0, width: width, height: height),
                     CGRect(x: 0, y: -1, width: width, height: height),
                     CGRect(x: 0, y: 0, width: width + 1, height: height),
                     CGRect(x: 0, y: 0, width: width, height: height + 1),
                     CGRect(x: CGFloat.nan, y: 0, width: 20, height: 20),
                     CGRect(x: 0, y: CGFloat.infinity, width: 20, height: 20),
                     CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 20),
                     CGRect(x: 0, y: 0, width: 20, height: CGFloat.nan)] {
            let malformed = metadata(rect: rect)
            XCTAssertTrue(malformed.pixelBuffer === frame.pixelBuffer)
            XCTAssertNil(DestructionScene.image(malformed), "Reject malformed windowRect: \(rect)")
            XCTAssertNil(DestructionScene.build(frame: malformed, windowFrame: info.frame, stage: screen.cgFrame))
        }
        for size in [CGSize.zero, CGSize(width: frame.pointSize.width + 1, height: frame.pointSize.height),
                     CGSize(width: CGFloat.nan, height: frame.pointSize.height),
                     CGSize(width: frame.pointSize.width, height: CGFloat.infinity)] {
            XCTAssertNil(DestructionScene.build(frame: metadata(rect: frame.windowRect, size: size),
                                               windowFrame: info.frame, stage: screen.cgFrame))
        }
        for invalid in [CGRect(x: CGFloat.nan, y: 0, width: info.frame.width, height: info.frame.height),
                        CGRect(x: 0, y: CGFloat.infinity, width: info.frame.width, height: info.frame.height), .zero] {
            XCTAssertNil(DestructionScene.build(frame: frame, windowFrame: invalid, stage: screen.cgFrame))
            XCTAssertNil(DestructionScene.build(frame: frame, windowFrame: info.frame, stage: invalid))
        }
        XCTAssertNil(DestructionScene.build(frame: frame, windowFrame: info.frame,
                                           stage: info.frame.offsetBy(dx: info.frame.width, dy: 0)))
        // Format is immutable on CVPixelBuffer. Alias the SAME captured storage with
        // an incorrect format declaration; no image is generated, copied or painted.
        XCTAssertEqual(CVPixelBufferLockBaseAddress(frame.pixelBuffer, .readOnly), kCVReturnSuccess)
        defer { CVPixelBufferUnlockBaseAddress(frame.pixelBuffer, .readOnly) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(frame.pixelBuffer))
        var declaredARGB: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreateWithBytes(nil, width, height, kCVPixelFormatType_32ARGB, base,
            CVPixelBufferGetBytesPerRow(frame.pixelBuffer), nil, nil, nil, &declaredARGB), kCVReturnSuccess)
        let alias = try XCTUnwrap(declaredARGB)
        CVPixelBufferLockBaseAddress(alias, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(alias, .readOnly) }
        XCTAssertEqual(CVPixelBufferGetBaseAddress(alias), base)
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(alias), kCVPixelFormatType_32ARGB)
        let wrongFormat = metadata(rect: frame.windowRect, buffer: alias)
        XCTAssertNil(DestructionScene.image(wrongFormat))
        XCTAssertNil(DestructionScene.build(frame: wrongFormat, windowFrame: info.frame, stage: screen.cgFrame))
    }

    /// Repeating the real one-shot command must neither reschedule pieces nor restore them.
    @MainActor
    func testDestructionCapturedREADMERepeatedDestroyIsIdempotentThroughSixSecondsAndBeyond() async throws {
        let screen = try captureScreen()
        let device = try metalDevice()
        let window = try readmeWindow(on: screen)
        defer { window.close() }
        let (info, frame) = try await captured(window, using: WindowCapture())
        let scene = try XCTUnwrap(DestructionScene.build(frame: frame, windowFrame: info.frame, stage: screen.cgFrame))
        XCTAssertFalse(scene.seeds.isEmpty)
        let once = try DestructionScene.renderer(device: device, scene: scene, size: screen.cgFrame.size, scale: 1)
        let repeated = try DestructionScene.renderer(device: device, scene: scene, size: screen.cgFrame.size, scale: 1)
        let world = repeated.world
        XCTAssertEqual(world.originalCount, scene.seeds.count)
        for tick in 0...960 {
            if tick > 0 { once.simulate(1 / 120); repeated.simulate(1 / 120) }
            if [0, 36, 96, 168, 288, 720, 960].contains(tick) {
                let before = world.bodies
                let cracks = world.crackSets
                for _ in 0..<3 { world.destroyWindow() }
                XCTAssertEqual(world.bodies.map(\.state), before.map(\.state))
                XCTAssertEqual(world.bodies.map(\.timer), before.map(\.timer))
                XCTAssertEqual(world.bodies.map(\.vel), before.map(\.vel))
                XCTAssertEqual(world.bodies.map(\.angVel), before.map(\.angVel))
                XCTAssertEqual(world.crackSets, cracks)
                XCTAssertEqual(world.bodies.map(\.pos), once.world.bodies.map(\.pos))
                XCTAssertEqual(world.bodies.map(\.age), once.world.bodies.map(\.age))
                let actual = try destructionPixels(XCTUnwrap(repeated.snapshot()))
                let expected = try destructionPixels(XCTUnwrap(once.snapshot()))
                XCTAssertTrue(actual.bytes == expected.bytes, "Repeated destroy must preserve the real single-call simulation at tick \(tick)")
                if tick >= 720 {
                    XCTAssertEqual(world.bodies.count, world.originalCount)
                    XCTAssertTrue(world.bodies.prefix(world.originalCount).allSatisfy { $0.state == .gone })
                    XCTAssertTrue(world.puffs.isEmpty)
                    XCTAssertTrue(repeated.isFinished)
                    XCTAssertTrue(repeated.world === world, "One-shot exhaustion must not restore a new world")
                    XCTAssertEqual(actual.alphaMass, 0)
                }
            }
            XCTAssertFalse(world.automaticEvents)
            XCTAssertEqual(world.eventCount, 0)
            XCTAssertNil(world.lastEvent)
        }
    }

    /// Real isolated preferences invalidate admission across the actual detached extraction.
    @MainActor
    func testDestructionRealPlayerRevalidatesChangedSettingsAfterExtractionAndReleasesSlot() async throws {
        let screen = try captureScreen()
        _ = try metalDevice()
        let window = try readmeWindow(on: screen)
        defer { window.close() }
        let (info, frame) = try await captured(window, using: WindowCapture())
        let (settings, _) = try preferences()
        settings.enabled = true
        settings.closeEffect = .off
        let player = try XCTUnwrap(DestructionEffectPlayer.make())
        let existing = Set(NSApp.windows.map(\.windowNumber))
        defer {
            player.cancelAll()
            NSApp.windows.filter { !existing.contains($0.windowNumber) }.forEach { $0.close() }
        }
        var validations = 0
        let rejected = await player.play(frame, windowFrame: info.frame, durationScale: 1, isValid: {
            validations += 1
            return settings.enabled && settings.closeEffect == .destruction
        })
        XCTAssertFalse(rejected)
        XCTAssertEqual(validations, 1, "Invalid initial settings must reject before detached extraction")
        XCTAssertFalse(player.hasScene)
        XCTAssertEqual(Set(NSApp.windows.map(\.windowNumber)), existing)
        settings.closeEffect = .destruction
        validations = 0
        let pending = Task { @MainActor in
            await player.play(frame, windowFrame: info.frame, durationScale: 1, isValid: {
                validations += 1
                return settings.enabled && settings.closeEffect == .destruction
            })
        }
        defer { pending.cancel() }
        for _ in 0..<64 {
            await Task.yield()
            if validations > 0 { break }
        }
        XCTAssertEqual(validations, 1, "Change real settings only after admission, while extraction yields the actor")
        XCTAssertFalse(player.hasScene)
        settings.enabled = false
        let staleAccepted = await pending.value
        XCTAssertFalse(staleAccepted)
        XCTAssertEqual(validations, 2, "A completed extraction must re-read current settings before publishing")
        XCTAssertFalse(player.hasScene)
        XCTAssertTrue(player.sceneBounds.isNull)
        XCTAssertEqual(Set(NSApp.windows.map(\.windowNumber)), existing, "Stale extraction must not allocate overlays")
        settings.enabled = true
        let restarted = await player.play(frame, windowFrame: info.frame, durationScale: 1)
        XCTAssertTrue(restarted, "Rejected stale admission must release its real source slot; default validation accepts")
        player.cancelAll()
        XCTAssertTrue(window.isVisible && !window.isMiniaturized)
    }

    /// Replay six seconds of genuine captured material without waiting six wall-clock seconds.
    @MainActor
    func testDestructionCapturedREADMEReleasesTextBeforeShardsBouncesAndFinishesTransparent() async throws {
        let screen = try captureScreen()
        let device = try metalDevice()
        let window = try readmeWindow(on: screen)
        defer { window.close() }
        let (info, frame) = try await captured(window, using: WindowCapture())
        let nativeFrame = window.frame
        let margin = max(24, info.frame.width * 0.15)
        var stage = info.frame.insetBy(dx: -margin, dy: -margin)
        stage.size.height += info.frame.height * 0.85
        let scene = try XCTUnwrap(DestructionScene.build(frame: frame, windowFrame: info.frame, stage: stage))
        let glyphs = scene.seeds.filter { $0.kind == .glyph }
        let shards = scene.seeds.filter { $0.kind == .shard }
        XCTAssertGreaterThan(glyphs.count, 0, "The real README must yield actual letters")
        XCTAssertGreaterThan(shards.count, 0, "The cleaned capture must yield window fragments")
        XCTAssertTrue(shards.allSatisfy { ($0.polygon?.verts.count ?? 0) >= 3 })
        let scale = frame.windowRect.width / frame.pointSize.width
        let renderer = try DestructionScene.renderer(device: device, scene: scene, size: stage.size, scale: scale)
        XCTAssertEqual(DestructionScene.duration, 6)
        XCTAssertFalse(renderer.isFinished)
        XCTAssertFalse(renderer.world.automaticEvents, "A close must not run random repeating saver events")
        XCTAssertEqual(renderer.world.polygons.count, shards.count)
        XCTAssertTrue(renderer.world.bodies.allSatisfy { $0.state == .pending })
        let initial = try destructionPixels(XCTUnwrap(renderer.snapshot()))
        XCTAssertGreaterThan(initial.alphaMass, 10)
        XCTAssertLessThan(try sourceDifference(initial, frame: frame, info: info, screen: stage), 0.2,
                          "Rendered RGB must come from the captured document, allowing the real crack overlay")
        // Inspect every outside pixel, not only a few empty desktop samples. A one-pixel
        // boundary accommodates rasterization of the captured edge and sprite margins.
        let materialBounds = info.frame.insetBy(dx: -1, dy: -1)
        var outsideAlpha = 0
        for y in 0..<initial.height {
            for x in 0..<initial.width {
                let point = CGPoint(x: stage.minX + (CGFloat(x) + 0.5) * stage.width / CGFloat(initial.width),
                                    y: stage.minY + (CGFloat(y) + 0.5) * stage.height / CGFloat(initial.height))
                if !materialBounds.contains(point) { outsideAlpha += Int(initial.bytes[(y * initial.width + x) * 4 + 3]) }
            }
        }
        XCTAssertEqual(outsideAlpha, 0, "No wallpaper, native shadow or opaque fullscreen fade may cover the desktop")

        var fell = false, bounced = false, finite = true
        for tick in 1...720 {
            let previous = renderer.world.bodies
            renderer.simulate(1 / 120)
            let bodies = renderer.world.bodies
            finite = finite && bodies.allSatisfy {
                $0.pos.x.isFinite && $0.pos.y.isFinite && $0.vel.x.isFinite && $0.vel.y.isFinite
                    && $0.angle.isFinite && $0.angVel.isFinite && $0.alpha.isFinite && (0...1).contains($0.alpha)
            }
            for index in bodies.indices where index < previous.count && bodies[index].state == .loose {
                let body = bodies[index]
                fell = fell || (body.pos.y > body.home.y + 10 && body.vel.y > 70)
                // Observe an actual downward-to-upward contact near the real stage floor.
                bounced = bounced || (previous[index].state == .loose && previous[index].vel.y > 70
                    && body.vel.y < -1 && body.pos.y > renderer.world.size.y - body.radius * 3 - 12)
            }
            if tick == 36 {
                XCTAssertTrue(bodies.filter { $0.kind == .glyph }.allSatisfy { $0.state == .loose })
                XCTAssertTrue(bodies.filter { $0.kind == .shard }.allSatisfy { $0.state == .pending },
                              "At 0.3 s letters fall while the window fragments still wait")
                XCTAssertGreaterThan(try destructionPixels(XCTUnwrap(renderer.snapshot())).alphaMass, 10)
            }
            if tick == 168 {
                XCTAssertTrue(bodies.allSatisfy { $0.state == .loose }, "By 1.4 s no intact or pending island may remain")
                XCTAssertFalse(renderer.isFinished)
            }
        }
        XCTAssertTrue(finite, "Every actual fall/contact must keep the physics finite")
        XCTAssertTrue(fell)
        XCTAssertTrue(bounced, "Captured pieces must physically bounce, not just translate or fade")
        XCTAssertTrue(renderer.world.bodies.allSatisfy { $0.state == .gone })
        XCTAssertTrue(renderer.world.puffs.isEmpty)
        XCTAssertTrue(renderer.isFinished)
        XCTAssertEqual(try destructionPixels(XCTUnwrap(renderer.snapshot())).alphaMass, 0)
        for _ in 0..<60 { renderer.simulate(1 / 120) }
        XCTAssertTrue(renderer.isFinished, "The saver must never restore the closed source in one-shot mode")
        XCTAssertEqual(try destructionPixels(XCTUnwrap(renderer.snapshot())).alphaMass, 0)

        // Render ONLY the extracted real glyphs so opaque window shards cannot conceal
        // a missing atlas. No seed, image or texture is fabricated or replaced.
        var textScene = scene
        textScene.seeds = glyphs
        let textRenderer = try DestructionScene.renderer(device: device, scene: textScene, size: stage.size, scale: scale)
        let text = try destructionPixels(XCTUnwrap(textRenderer.snapshot()))
        var samples = 0, visible = 0, rgbaError = 0.0
        for body in textRenderer.world.bodies {
            let sprite = scene.sprites[body.sprite]
            let peak = try XCTUnwrap(stride(from: 3, to: sprite.rgba.count, by: 4).max {
                sprite.rgba[$0] < sprite.rgba[$1]
            }) - 3
            guard sprite.rgba[peak + 3] > 128 else { continue }
            let sx = peak / 4 % sprite.pixelWidth, sy = peak / 4 / sprite.pixelWidth
            let point = CGPoint(x: CGFloat(body.pos.x) + ((CGFloat(sx) + 0.5) / CGFloat(sprite.pixelWidth) - 0.5) * CGFloat(body.size.x) + stage.minX,
                                y: CGFloat(body.pos.y) + ((CGFloat(sy) + 0.5) / CGFloat(sprite.pixelHeight) - 0.5) * CGFloat(body.size.y) + stage.minY)
            let offset = text.offset(at: point, screen: stage)
            samples += 1
            if text.bytes[offset + 3] > 64 { visible += 1 }
            for channel in 0..<4 {
                let sourceChannel = channel < 3 ? 2 - channel : 3 // extracted RGBA -> snapshot BGRA
                rgbaError += abs(Double(text.bytes[offset + channel]) - Double(sprite.rgba[peak + sourceChannel])) / 255
            }
        }
        XCTAssertGreaterThan(samples, 0)
        XCTAssertGreaterThan(Double(visible) / Double(max(1, samples)), 0.8, "Captured glyph alpha must survive atlas upload")
        XCTAssertLessThan(rgbaError / Double(max(1, samples) * 4), 0.22, "Glyph textures must retain captured color and coverage")
        for _ in 0..<36 { textRenderer.simulate(1 / 120) }
        let releasedText = try destructionPixels(XCTUnwrap(textRenderer.snapshot()))
        XCTAssertGreaterThan(releasedText.alphaMass, 1, "Loose letters must still render their real textures")
        XCTAssertNotEqual(text.bytes, releasedText.bytes)
        XCTAssertEqual(window.frame, nativeFrame)
        XCTAssertTrue(window.isVisible)
        XCTAssertFalse(window.isMiniaturized)
    }

    @MainActor
    func testDestructionRealPlayerBoundsTwoSourcesRejectsDuplicateCancelsAndRestarts() async throws {
        let screen = try captureScreen()
        _ = try metalDevice()
        let first = try readmeWindow(on: screen)
        defer { first.close() }
        let second = try readmeWindow(on: screen)
        defer { second.close() }
        let third = try readmeWindow(on: screen)
        defer { third.close() }
        let capture = WindowCapture()
        let (a, fa) = try await captured(first, using: capture)
        let (b, fb) = try await captured(second, using: capture)
        let (c, fc) = try await captured(third, using: capture)
        XCTAssertEqual(Set([fa.windowID, fb.windowID, fc.windowID]).count, 3)
        let owner = try XCTUnwrap(CloseEffectPlayer.make())
        let player = try XCTUnwrap(owner.destructionPlayer)
        let existing = Set(NSApp.windows.map(\.windowNumber))
        defer {
            owner.cancelAll()
            NSApp.windows.filter { !existing.contains($0.windowNumber) }.forEach { $0.close() }
        }
        XCTAssertFalse(player.hasScene)
        XCTAssertTrue(player.sceneBounds.isNull)
        let acceptedFirst = await player.play(fa, windowFrame: a.frame, durationScale: 3)
        XCTAssertTrue(acceptedFirst)
        let duplicate = await player.play(fa, windowFrame: a.frame, durationScale: 3)
        XCTAssertFalse(duplicate)
        let acceptedSecond = await player.play(fb, windowFrame: b.frame, durationScale: 3)
        XCTAssertTrue(acceptedSecond, "A duplicate must not consume the second slot")
        let overflow = await player.play(fc, windowFrame: c.frame, durationScale: 3)
        XCTAssertFalse(overflow)
        let expected = NSScreen.screens.filter { $0.cgFrame.intersects(a.frame) || $0.cgFrame.intersects(b.frame) }
            .reduce(CGRect.null) { $0.union($1.cgFrame) }
        XCTAssertEqual(player.sceneBounds, expected)
        XCTAssertFalse(owner.hasScene, "Physical destruction must not allocate a bounded shader scene")
        let overlays = NSApp.windows.filter { !existing.contains($0.windowNumber) && $0.isVisible }
        XCTAssertEqual(overlays.count, NSScreen.screens.count)
        for overlay in overlays {
            XCTAssertEqual(overlay.level.rawValue, Int(CGWindowLevelForKey(.dockWindow)) - 1)
            XCTAssertTrue(overlay.ignoresMouseEvents)
            XCTAssertFalse(overlay.isOpaque)
            XCTAssertTrue(NSScreen.screens.contains { $0.frame == overlay.frame })
        }
        try await pause(0.05)
        owner.cancelAll() // Exercise cancellation through the actual owner, not just the leaf.
        XCTAssertFalse(player.hasScene)
        XCTAssertTrue(player.sceneBounds.isNull)
        XCTAssertTrue(overlays.allSatisfy { !$0.isVisible })
        owner.cancelAll()
        let restarted = await player.play(fc, windowFrame: c.frame, durationScale: 1)
        let reused = await player.play(fa, windowFrame: a.frame, durationScale: 1)
        XCTAssertTrue(restarted)
        XCTAssertTrue(reused)
        let fullAgain = await player.play(fb, windowFrame: b.frame, durationScale: 1)
        XCTAssertFalse(fullAgain)
        owner.cancelAll()
        XCTAssertTrue(player.sceneBounds.isNull)
        XCTAssertTrue([first, second, third].allSatisfy { $0.isVisible && !$0.isMiniaturized })
    }

    @MainActor
    func testDestructionPendingExtractionTaskAndGenerationCancellationCannotResurrectScene() async throws {
        let screen = try captureScreen()
        _ = try metalDevice()
        let window = try readmeWindow(on: screen)
        defer { window.close() }
        let (info, frame) = try await captured(window, using: WindowCapture())
        let owner = try XCTUnwrap(CloseEffectPlayer.make())
        let player = try XCTUnwrap(owner.destructionPlayer)
        let existing = Set(NSApp.windows.map(\.windowNumber))
        defer {
            owner.cancelAll()
            NSApp.windows.filter { !existing.contains($0.windowNumber) }.forEach { $0.close() }
        }
        for cancelGeneration in [false, true] {
            var entered = false
            let pending = Task { @MainActor in
                entered = true
                return await player.play(frame, windowFrame: info.frame, durationScale: 1)
            }
            defer { pending.cancel() }
            // Wait only for task entry, never for a guessed extraction duration. The
            // actor yields at the actual detached capture-to-scene conversion.
            for _ in 0..<64 {
                await Task.yield()
                if entered { break }
            }
            XCTAssertTrue(entered, "Cancellation must exercise a started request, not an unstarted task")
            XCTAssertFalse(player.hasScene, "The request must still be preparing its real captured scene")
            if cancelGeneration { owner.cancelAll() } else { pending.cancel() }
            // Invalidate while extraction is suspended; restart before awaiting its
            // stale completion to exercise generation-safe pending-slot ownership.
            if cancelGeneration {
                let replacement = await player.play(frame, windowFrame: info.frame, durationScale: 1)
                XCTAssertTrue(replacement)
            }
            let staleAccepted = await pending.value
            XCTAssertFalse(staleAccepted, "Cancelled extraction must never publish an overlay")
            if cancelGeneration {
                XCTAssertTrue(player.hasScene, "Old-generation completion must not erase the replacement")
                let duplicate = await player.play(frame, windowFrame: info.frame, durationScale: 1)
                XCTAssertFalse(duplicate)
            } else {
                XCTAssertFalse(player.hasScene)
                XCTAssertTrue(player.sceneBounds.isNull)
                let restarted = await player.play(frame, windowFrame: info.frame, durationScale: 1)
                XCTAssertTrue(restarted, "Task cancellation must release pending capacity")
            }
            owner.cancelAll()
            await Task.yield()
            XCTAssertFalse(player.hasScene)
            XCTAssertTrue(player.sceneBounds.isNull)
        }
    }

    @MainActor
    func testDestructionRealPlayerCancelsOnLocalSleepAndSpaceNotifications() async throws {
        let screen = try captureScreen()
        _ = try metalDevice()
        let window = try readmeWindow(on: screen)
        defer { window.close() }
        let (info, frame) = try await captured(window, using: WindowCapture())
        let owner = try XCTUnwrap(CloseEffectPlayer.make())
        let player = try XCTUnwrap(owner.destructionPlayer)
        let existing = Set(NSApp.windows.map(\.windowNumber))
        defer {
            owner.cancelAll()
            NSApp.windows.filter { !existing.contains($0.windowNumber) }.forEach { $0.close() }
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            let started = await player.play(frame, windowFrame: info.frame, durationScale: 1)
            XCTAssertTrue(started)
            XCTAssertTrue(player.hasScene)
            let overlays = NSApp.windows.filter { !existing.contains($0.windowNumber) && $0.isVisible }
            XCTAssertEqual(overlays.count, NSScreen.screens.count)
            try await pause(0.05)
            // Process-local delivery: never actually put the Mac to sleep or switch Spaces.
            NSWorkspace.shared.notificationCenter.post(name: name, object: nil)
            XCTAssertFalse(player.hasScene)
            XCTAssertTrue(player.sceneBounds.isNull)
            XCTAssertTrue(overlays.allSatisfy { !$0.isVisible })
            let resurrected = try await eventually(seconds: 0.12) { player.hasScene }
            XCTAssertFalse(resurrected, "Queued GPU/display work after \(name.rawValue) must remain cancelled")
        }
        XCTAssertTrue(window.isVisible)
        XCTAssertFalse(window.isMiniaturized)
    }

    @MainActor
    func testActualCloseOfDisposableWindowRoutesOnlyToDestructionAndTriggerCancelsPhysics() async throws {
        let screen = try captureScreen()
        _ = try metalDevice()
        let document = try await childDocument(on: screen)
        let existing = Set(NSApp.windows.map(\.windowNumber))
        let capture = WindowCapture()
        _ = await capture.refreshContent()
        let warm = try await capture.capture(document.info)
        XCTAssertTrue(warm.isPainted)
        let (settings, _) = try preferences()
        settings.closeEffect = .destruction
        let shaders = try XCTUnwrap(CloseEffectPlayer.make())
        let destruction = try XCTUnwrap(shaders.destructionPlayer)
        let liquid = try XCTUnwrap(LiquidEffectPlayer.make())
        let trigger = CloseEffectTrigger(settings: settings, capture: capture, player: shaders, liquid: liquid, isBusy: { false })
        defer {
            trigger.cancelAll(); liquid.cancelAll()
            NSApp.windows.filter { !existing.contains($0.windowNumber) }.forEach { $0.close() }
        }
        XCTAssertEqual(try XCTUnwrap(WindowLocator.window(at: document.closePoint)).id, document.info.id)
        trigger.mouseDown(at: document.closePoint, windows: WindowList())
        trigger.mouseUp()
        try await pause(0.2)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(WindowLocator.snapshot(of: document.info.id)).alpha, 0.99)
        XCTAssertFalse(destruction.hasScene, "Arming/capturing an opaque document must not destroy it")
        XCTAssertFalse(shaders.hasScene)
        try document.send("close")
        let started = try await eventually(seconds: 1.5) { destruction.hasScene }
        let closed = try await eventually(seconds: 0.5) { !WindowLocator.exists(document.info.id) }
        XCTAssertTrue(closed, "The child must release its actual AppKit window, not simply hide it")
        XCTAssertTrue(started, "The real close must asynchronously start physical destruction")
        XCTAssertFalse(shaders.hasScene)
        XCTAssertFalse(liquid.hasScene)
        XCTAssertFalse(destruction.sceneBounds.isNull)
        let overlays = NSApp.windows.filter { !existing.contains($0.windowNumber) && $0.isVisible }
        trigger.cancelAll() // Do not cancel destruction directly: verify the public trigger chain.
        XCTAssertFalse(destruction.hasScene)
        XCTAssertTrue(destruction.sceneBounds.isNull)
        XCTAssertTrue(overlays.allSatisfy { !$0.isVisible })
        let restarted = try await eventually(seconds: 0.15) { destruction.hasScene || shaders.hasScene || liquid.hasScene }
        XCTAssertFalse(restarted)
    }

    @MainActor
    func testDestructionTriggerCancelledWhileWatchingNeverPlaysAfterActualClose() async throws {
        try await assertCloseTriggerCancellation(beforeClose: true, choice: .destruction)
    }

    @MainActor
    func testDestructionTriggerCancelledAfterActualCloseNeverRestarts() async throws {
        try await assertCloseTriggerCancellation(beforeClose: false, choice: .destruction)
    }

    @MainActor
    func testDestructionPreviewRealCaptureAtStartMiddleEndLeavesNativeWindowUntouched() async throws {
        let screen = try captureScreen()
        _ = try metalDevice()
        let window = try readmeWindow(on: screen)
        defer { window.close() }
        let (info, frame) = try await captured(window, using: WindowCapture())
        let nativeFrame = window.frame
        let existing = Set(NSApp.windows.map(\.windowNumber))
        let (settings, defaults) = try preferences()
        let savedPreferences = defaults.dictionaryRepresentation()
        let preview = OriginalPreviewRenderer(budget: { .forQuality(.high) })
        defer { preview.cancel() }
        XCTAssertEqual(OriginalPreviewRenderer.timelineSeconds(effect: .destruction, preset: nil, settings: settings,
                                                               source: .window(info.id)), 6 * settings.closeDuration)
        var outputs: [Pixels] = []
        var sizes: [CGSize] = []
        for progress in [0.0, 0.5, 1.0] {
            let image = try await preview.previewCaptured(effect: .destruction, frame: frame, windowFrame: info.frame,
                                                          progress: progress, settings: settings)
            var proposed = CGRect(origin: .zero, size: image.size)
            let cg = try XCTUnwrap(image.cgImage(forProposedRect: &proposed, context: nil, hints: nil))
            XCTAssertLessThanOrEqual(cg.width * cg.height, 8_000_000)
            XCTAssertLessThanOrEqual(max(cg.width, cg.height), 8192)
            outputs.append(try destructionPixels(cg))
            sizes.append(image.size)
            XCTAssertEqual(window.frame, nativeFrame)
            XCTAssertEqual(WindowLocator.frame(of: info.id), info.frame)
            XCTAssertTrue(WindowLocator.exists(info.id))
            XCTAssertTrue(window.isVisible)
            XCTAssertFalse(window.isMiniaturized)
            XCTAssertEqual(preview.inFlight, 0)
        }
        XCTAssertEqual(sizes[0], sizes[1])
        XCTAssertEqual(sizes[0], sizes[2])
        XCTAssertGreaterThan(outputs[0].alphaMass, 10)
        XCTAssertGreaterThan(outputs[1].alphaMass, 1, "A scrub at 3 s must still show the falling/bouncing captured material")
        XCTAssertNotEqual(outputs[0].bytes, outputs[1].bytes)
        XCTAssertEqual(outputs[2].alphaMass, 0, "The six-second preview must finish with an empty transparent stage")
        XCTAssertEqual(Set(NSApp.windows.map(\.windowNumber)), existing, "Read-only preview must not create desktop overlays")
        XCTAssertTrue(NSDictionary(dictionary: savedPreferences).isEqual(to: defaults.dictionaryRepresentation()))
    }

    /// Compare owned extraction pixels row by row without imposing a BGRA layout on RGBA pictures.
    private func assertSameImagePixels(_ actual: CGImage, _ expected: CGImage,
                                       file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(actual.width, expected.width, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, file: file, line: line)
        XCTAssertEqual(actual.bitsPerComponent, expected.bitsPerComponent, file: file, line: line)
        XCTAssertEqual(actual.bitsPerPixel, 32, file: file, line: line)
        XCTAssertEqual(actual.bitsPerPixel, expected.bitsPerPixel, file: file, line: line)
        XCTAssertEqual(actual.bitmapInfo, expected.bitmapInfo, file: file, line: line)
        guard actual.width == expected.width, actual.height == expected.height,
              actual.bitsPerPixel == 32, expected.bitsPerPixel == 32 else { return }
        let a = try XCTUnwrap(actual.dataProvider?.data, file: file, line: line) as Data
        let b = try XCTUnwrap(expected.dataProvider?.data, file: file, line: line) as Data
        XCTAssertGreaterThanOrEqual(a.count, actual.bytesPerRow * actual.height, file: file, line: line)
        XCTAssertGreaterThanOrEqual(b.count, expected.bytesPerRow * expected.height, file: file, line: line)
        guard a.count >= actual.bytesPerRow * actual.height, b.count >= expected.bytesPerRow * expected.height else { return }
        for y in 0..<actual.height {
            let ar = y * actual.bytesPerRow, br = y * expected.bytesPerRow
            XCTAssertTrue(a[ar..<(ar + actual.width * 4)] == b[br..<(br + expected.width * 4)],
                          "Actual captured image differs on row \(y)", file: file, line: line)
        }
    }

    /// Global translation must preserve all seed geometry, picture UVs and captured sprite bytes.
    private func assertSameDestructionScene(_ actual: ChaosScene, _ expected: ChaosScene,
                                            file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(actual.frames, expected.frames, file: file, line: line)
        XCTAssertEqual(actual.seeds.count, expected.seeds.count, file: file, line: line)
        for (a, b) in zip(actual.seeds, expected.seeds) {
            XCTAssertEqual(a.kind, b.kind, file: file, line: line)
            XCTAssertEqual(a.center, b.center, file: file, line: line)
            XCTAssertEqual(a.size, b.size, file: file, line: line)
            XCTAssertEqual(a.bodySize, b.bodySize, file: file, line: line)
            XCTAssertEqual(a.group, b.group, file: file, line: line)
            XCTAssertEqual(a.sprite, b.sprite, file: file, line: line)
            XCTAssertEqual(a.isDock, b.isDock, file: file, line: line)
            XCTAssertEqual(a.polygon?.verts, b.polygon?.verts, file: file, line: line)
            XCTAssertEqual(a.polygon?.uvOffset, b.polygon?.uvOffset, file: file, line: line)
            XCTAssertEqual(a.polygon?.uvScale, b.polygon?.uvScale, file: file, line: line)
        }
        XCTAssertEqual(actual.tiles.count, expected.tiles.count, file: file, line: line)
        for (a, b) in zip(actual.tiles, expected.tiles) {
            XCTAssertEqual(a.verts, b.verts, file: file, line: line)
        }
        XCTAssertEqual(actual.sprites.count, expected.sprites.count, file: file, line: line)
        for (a, b) in zip(actual.sprites, expected.sprites) {
            XCTAssertEqual(a.kind, b.kind, file: file, line: line)
            XCTAssertEqual(a.frame, b.frame, file: file, line: line)
            XCTAssertEqual(a.margin, b.margin, file: file, line: line)
            XCTAssertEqual(a.pixelWidth, b.pixelWidth, file: file, line: line)
            XCTAssertEqual(a.pixelHeight, b.pixelHeight, file: file, line: line)
            XCTAssertTrue(a.rgba == b.rgba, "Captured sprite bytes changed", file: file, line: line)
        }
        XCTAssertEqual(actual.pictures.count, expected.pictures.count, file: file, line: line)
        for (a, b) in zip(actual.pictures, expected.pictures) {
            try assertSameImagePixels(a, b, file: file, line: line)
        }
    }

    /// Opt-in real README only: native Metal frames plus a labelled contact sheet.
    /// Resolve symlinks before enforcing /tmp; exclusive descriptor-relative creation
    /// keeps each run private (0700/0600), without following pre-existing output links.
    @MainActor
    private func dumpDestructionIfRequested(_ frames: [(Double, Pixels)]) throws {
        guard let path = ProcessInfo.processInfo.environment["KINETIQ_DESTRUCTION_TEST_DUMP"], !path.isEmpty else { return }
        let temporary = URL(fileURLWithPath: "/tmp", isDirectory: true).resolvingSymlinksInPath()
        func allowed(_ url: URL) -> Bool {
            url.path == temporary.path || url.path.hasPrefix(temporary.path + "/")
        }
        var directory = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        guard allowed(directory) else {
            XCTFail("KINETIQ_DESTRUCTION_TEST_DUMP must resolve inside /tmp; no captured image was saved")
            return
        }
        let first = try XCTUnwrap(frames.first?.1)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        directory = directory.resolvingSymlinksInPath()
        guard allowed(directory) else {
            XCTFail("Destruction dump directory escaped /tmp; no captured image was saved")
            return
        }
        let parent = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parent >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(parent) }
        let run = "destruction-readme-\(UUID().uuidString)"
        guard mkdirat(parent, run, 0o700) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let output = openat(parent, run, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard output >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(output) }
        var directoryStatus = stat()
        XCTAssertEqual(fstat(output, &directoryStatus), 0)
        XCTAssertEqual(directoryStatus.st_mode & 0o777, 0o700)
        func save(_ png: Data, named name: String) throws {
            let descriptor = openat(output, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            defer { try? handle.close() }
            var status = stat()
            XCTAssertEqual(fstat(descriptor, &status), 0)
            XCTAssertEqual(status.st_mode & 0o777, 0o600, "Permissions must be private BEFORE writing captured content")
            try handle.write(contentsOf: png)
        }
        for (index, entry) in frames.enumerated() {
            let bitmap = NSBitmapImageRep(cgImage: try entry.1.image())
            try save(XCTUnwrap(bitmap.representation(using: .png, properties: [:])),
                     named: String(format: "destruction-real-readme-native-%02d-%.3fs.png", index, entry.0))
        }
        let columns = 3, rows = (frames.count + 2) / 3, tileWidth = 480, labelHeight = 28
        let tileHeight = max(1, tileWidth * first.height / first.width)
        let sheet = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: tileWidth * columns,
            pixelsHigh: (tileHeight + labelHeight) * rows, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: sheet))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        NSColor(calibratedWhite: 0.18, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: sheet.pixelsWide, height: sheet.pixelsHigh).fill()
        for (index, entry) in frames.enumerated() {
            let x = index % columns * tileWidth, y = (rows - 1 - index / columns) * (tileHeight + labelHeight)
            let image = NSImage(cgImage: try entry.1.image(), size: NSSize(width: entry.1.width, height: entry.1.height))
            image.draw(in: NSRect(x: x, y: y, width: tileWidth, height: tileHeight))
            (String(format: "README · %.1f s", entry.0) as NSString).draw(
                at: NSPoint(x: x + 10, y: y + tileHeight + 5),
                withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.white])
        }
        try save(XCTUnwrap(sheet.representation(using: .png, properties: [:])),
                 named: "destruction-real-readme-contact-sheet.png")
        print("DESTRUCTION_TEST_DUMP \(directory.appendingPathComponent(run).path) frames=\(frames.count) nativePixels=\(first.width)x\(first.height)")
    }

    /// Copy an actual renderer/preview BGRA readback, retaining row order and removing padding.
    private func destructionPixels(_ image: CGImage) throws -> Pixels {
        XCTAssertEqual(image.bitsPerComponent, 8)
        XCTAssertEqual(image.bitsPerPixel, 32)
        XCTAssertEqual(image.alphaInfo, .premultipliedFirst)
        XCTAssertTrue(image.bitmapInfo.contains(.byteOrder32Little))
        let data = try XCTUnwrap(image.dataProvider?.data) as Data
        let rowBytes = image.width * 4
        XCTAssertGreaterThanOrEqual(data.count, image.bytesPerRow * image.height)
        var bytes = [UInt8]()
        bytes.reserveCapacity(rowBytes * image.height)
        for y in 0..<image.height {
            let start = y * image.bytesPerRow
            bytes.append(contentsOf: data[start..<(start + rowBytes)])
        }
        return Pixels(width: image.width, height: image.height, bytes: bytes)
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
                && $0.position.x >= Float(world.screenBounds.minX) && $0.position.x <= Float(world.screenBounds.maxX)
                && $0.position.y >= Float(world.screenBounds.minY)
                && $0.position.y <= Float(world.screenBounds.maxY) + world.spacing * 1.5 + 1.01
            }, "Simulation must retain finite samples within the display and its bottom exit margin", file: file, line: line)
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
        var maximumAlpha: Double { Double(stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] }.max() ?? 0) / 255 }

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