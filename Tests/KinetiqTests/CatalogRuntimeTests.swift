// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
@preconcurrency import ApplicationServices
import CoreVideo
import KinetiqCore
import Metal
import XCTest
@testable import Kinetiq

/// Real README document -> ScreenCaptureKit IOSurface -> runtime Metal -> P3 NSImage.
/// Only test-owned NSWindows are shown. User windows and standard defaults are untouched.
final class CatalogRuntimeTests: XCTestCase {
    @MainActor private static var preparedApplication = false

    @MainActor private func runtime(enabled: Bool = true, quality: RenderQuality = .high) throws -> CatalogRuntime {
        let suite = "io.github.invernomut0.Kinetiq.catalog-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let settings = Settings(defaults: defaults)
        settings.enabled = enabled
        return CatalogRuntime(settings: settings, budget: { .forQuality(quality) },
                      qualityManager: RenderQualityManager(defaults: defaults))
    }

    @MainActor func testDisabledAndExplicitMissingWindowNeverFallbackOrMoveAnything() async throws {
        let runtime = try runtime(enabled: false)
        await runtime.play(EffectPreset(effect: .gravity))
        XCTAssertFalse(runtime.isPlaying)
        XCTAssertNotNil(runtime.errorMessage)
        let enabled = try self.runtime()
        await enabled.play(EffectPreset(effect: .fold), windowID: .max)
        XCTAssertFalse(enabled.isPlaying)
        XCTAssertNotNil(enabled.errorMessage)
        runtime.stop(); enabled.stop()
    }

    @MainActor func testTargetSizesRespectRealScreenBudgetsAndRejectInvalidInputs() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let native = CGSize(width: screen.frame.width * screen.backingScaleFactor,
                            height: screen.frame.height * screen.backingScaleFactor)
        for quality in [RenderQuality.high, .balanced, .low] {
            let budget = RenderBudget.forQuality(quality)
            for multiplier in [1.0, 4, 32] {
                let size = CGSize(width: native.width * multiplier, height: native.height * multiplier)
                let target = try CatalogRuntime.targetSize(size, scale: budget.textureScale)
                XCTAssertGreaterThan(target.width, 0); XCTAssertGreaterThan(target.height, 0)
                XCTAssertLessThanOrEqual(target.width, 8192); XCTAssertLessThanOrEqual(target.height, 8192)
                XCTAssertLessThanOrEqual(target.width * target.height, 8_000_000)
                XCTAssertLessThanOrEqual(Double(target.width), size.width * budget.textureScale)
                XCTAssertEqual(Double(target.width) / Double(target.height), size.width / size.height, accuracy: 0.01)
            }
        }
        let hardwareLimited = try CatalogRuntime.targetSize(native, scale: 1, maximumDimension: 1024)
        XCTAssertLessThanOrEqual(max(hardwareLimited.width, hardwareLimited.height), 1024)
        for scale in [Double.nan, .infinity, -1, 0] {
            XCTAssertThrowsError(try CatalogRuntime.targetSize(native, scale: scale))
        }
        XCTAssertThrowsError(try CatalogRuntime.targetSize(CGSize(width: CGFloat.infinity, height: 100), scale: 1))
        XCTAssertThrowsError(try CatalogRuntime.targetSize(.zero, scale: 1))
    }

    @MainActor func testOverviewSelectionUsesProjectedSurfaceRatherThanLayoutRectangle() throws {
        let stage = try XCTUnwrap(NSScreen.screens.first).cgVisibleFrame.insetBy(dx: 45, dy: 45)
        let rect = CGRect(x: stage.midX - stage.width / 6, y: stage.midY - stage.height / 6,
                          width: stage.width / 3, height: stage.height / 3)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let corner = CGPoint(x: rect.minX + 1, y: rect.minY + 1)
        for effect in [EffectID.workspaceCube, .orbit, .expose3D] {
            var preset = EffectPreset(effect: effect)
            if effect == .workspaceCube { preset.parameters["angle"] = 65 }
            XCTAssertTrue(CatalogRuntime.overviewContains(center, rect: rect, preset: preset, stage: stage))
            XCTAssertTrue(rect.contains(corner))
            XCTAssertFalse(CatalogRuntime.overviewContains(corner, rect: rect, preset: preset, stage: stage))
            XCTAssertFalse(CatalogRuntime.overviewContains(CGPoint(x: stage.maxX + 1, y: stage.midY),
                                                         rect: rect, preset: preset, stage: stage))
        }
    }

    @MainActor private func documentWindow() throws -> NSWindow {
        _ = NSApplication.shared
        guard let screen = NSScreen.screens.first, CGSessionCopyCurrentDictionary() != nil else {
            throw XCTSkip("A graphical WindowServer session is required")
        }
        guard CGPreflightScreenCaptureAccess() else { throw XCTSkip("Screen Recording permission required; no prompt") }
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        if !Self.preparedApplication {
            NSApp.setActivationPolicy(.regular)
            NSApp.finishLaunching()
            Self.preparedApplication = true
        }
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: repository.appendingPathComponent("README.md"), encoding: .utf8)
        XCTAssertFalse(text.isEmpty)
        let visible = screen.visibleFrame
        let rect = CGRect(x: visible.minX + 40, y: visible.minY + 60,
                          width: min(460, visible.width / 2), height: min(300, visible.height / 2))
        let window = NSWindow(contentRect: rect, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.animationBehavior = .none
        window.title = "Catalog runtime — README.md"
        let view = NSTextView(frame: CGRect(origin: .zero, size: rect.size))
        view.isVerticallyResizable = false; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width, .height]
        view.string = text; view.isEditable = false; view.drawsBackground = true
        view.backgroundColor = .textBackgroundColor; view.textColor = .textColor
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        window.contentView = view
        window.orderFrontRegardless(); window.displayIfNeeded()
        return window
    }

    @MainActor private func captured(_ window: NSWindow) async throws -> (CapturedFrame, CGRect) {
        try await Task.sleep(for: .milliseconds(150))
        let id = CGWindowID(window.windowNumber)
        let rect = try XCTUnwrap(WindowLocator.frame(of: id))
        let capture = WindowCapture()
        _ = await capture.refreshContent()
        let frame = try await capture.capture(WindowInfo(id: id, pid: ProcessInfo.processInfo.processIdentifier, frame: rect))
        XCTAssertTrue(frame.isPainted)
        return (frame, rect)
    }

    @MainActor func testRealCapturePreviewPreservesPixelsP3AndDoesNotMutateWindow() async throws {
        let window = try documentWindow(); defer { window.close() }
        let original = window.frame
        let (frame, rect) = try await captured(window)
        let runtime = try runtime(); defer { runtime.stop() }
        let document = StudioDocument(duration: 1, layers: [StudioLayer(preset: EffectPreset(effect: .fold))])
        let output = try await runtime.previewCaptured(frame, windowFrame: rect, document: document, time: 0)
        var proposed = CGRect(origin: .zero, size: output.size)
        let image = try XCTUnwrap(output.cgImage(forProposedRect: &proposed, context: nil, hints: nil))
        XCTAssertEqual(image.colorSpace?.name, WindowCapture.colorSpace.name)
        XCTAssertEqual(image.width, Int(frame.windowRect.width))
        XCTAssertEqual(image.height, Int(frame.windowRect.height))
        let data = try XCTUnwrap(image.dataProvider?.data)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        CVPixelBufferLockBaseAddress(frame.pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(frame.pixelBuffer, .readOnly) }
        let source = try XCTUnwrap(CVPixelBufferGetBaseAddress(frame.pixelBuffer)).assumingMemoryBound(to: UInt8.self)
        var difference = 0.0
        for y in 1...8 {
            for x in 1...12 {
                let px = image.width * x / 13, py = image.height * y / 9
                let sx = Int(frame.windowRect.minX) + px, sy = Int(frame.windowRect.minY) + py
                for channel in 0..<4 {
                    difference += abs(Double(bytes[py * image.bytesPerRow + px * 4 + channel])
                        - Double(source[sy * CVPixelBufferGetBytesPerRow(frame.pixelBuffer) + sx * 4 + channel]))
                }
            }
        }
        XCTAssertLessThan(difference / Double(8 * 12 * 4 * 255), 0.015)
        XCTAssertEqual(window.frame, original)
        XCTAssertFalse(runtime.isPlaying)
        XCTAssertTrue(runtime.shaderStatus.contains("compiled"))
    }

    @MainActor func testLayerClockDisabledLayersAndRealKeyframesAffectCapturedPixels() async throws {
        let window = try documentWindow(); defer { window.close() }
        let (frame, rect) = try await captured(window)
        let runtime = try runtime(); defer { runtime.stop() }
        var preset = EffectPreset(effect: .fold)
        preset.curve = .linear
        preset.tracks = [AnimationTrack(parameter: "angle", keyframes: [
            AnimationKeyframe(time: 0, value: 0, curve: .easeIn), AnimationKeyframe(time: 1, value: 180)])]
        var layer = StudioLayer(preset: preset, start: 1)
        let active = StudioDocument(duration: 3, layers: [layer])
        layer.enabled = false
        let inactive = StudioDocument(duration: 3, layers: [layer])
        let before = try await runtime.previewCaptured(frame, windowFrame: rect, document: active, time: 0.5)
        let disabled = try await runtime.previewCaptured(frame, windowFrame: rect, document: inactive, time: 1.5)
        let changed = try await runtime.previewCaptured(frame, windowFrame: rect, document: active, time: 1.5)
        XCTAssertEqual(pixels(before), pixels(disabled))
        XCTAssertNotEqual(pixels(changed), pixels(disabled))
        XCTAssertEqual(preset.value("angle", at: 0.5), 45, accuracy: 1e-10)
        XCTAssertFalse(runtime.isPlaying)
    }

    @MainActor func testQualityScaledPreviewKeepsPointSizeAndLiveWindowUntouched() async throws {
        let window = try documentWindow(); defer { window.close() }
        let original = window.frame
        let (frame, rect) = try await captured(window)
        let document = StudioDocument(duration: 1, layers: [StudioLayer(preset: EffectPreset(effect: .fold))])
        for quality in [RenderQuality.high, .balanced, .low] {
            let runtime = try runtime(quality: quality)
            defer { runtime.stop() }
            let output = try await runtime.previewCaptured(frame, windowFrame: rect, document: document, time: 0)
            let expected = try CatalogRuntime.targetSize(frame.windowRect.size, scale: RenderBudget.forQuality(quality).textureScale)
            XCTAssertEqual(output.size, rect.size)
            var proposed = CGRect(origin: .zero, size: output.size)
            let image = try XCTUnwrap(output.cgImage(forProposedRect: &proposed, context: nil, hints: nil))
            XCTAssertEqual(image.width, expected.width); XCTAssertEqual(image.height, expected.height)
            XCTAssertEqual(image.colorSpace?.name, WindowCapture.colorSpace.name)
            XCTAssertEqual(window.frame, original)
            XCTAssertFalse(runtime.isPlaying)
        }
    }

    @MainActor func testCapturedPlaybackStopsSynchronouslyOnSpaceSleepAndNeverResurrects() async throws {
        let window = try documentWindow(); defer { window.close() }
        let original = window.frame
        let (frame, rect) = try await captured(window)
        let runtime = try runtime(); defer { runtime.stop() }
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.willSleepNotification] {
            XCTAssertTrue(runtime.playCaptured(frame, windowFrame: rect, preset: EffectPreset(effect: .fold)))
            XCTAssertTrue(runtime.isPlaying)
            try await Task.sleep(for: .milliseconds(60))
            NSWorkspace.shared.notificationCenter.post(name: name, object: nil)
            XCTAssertFalse(runtime.isPlaying)
            XCTAssertFalse(runtime.hasScene)
            try await Task.sleep(for: .milliseconds(80))
            XCTAssertFalse(runtime.isPlaying)
        }
        XCTAssertEqual(window.frame, original)
    }

    @MainActor func testLowBudgetRejectsExpensiveCaptureWithoutChangingLiveDocument() async throws {
        let window = try documentWindow(); defer { window.close() }
        let original = window.frame
        let (frame, rect) = try await captured(window)
        let runtime = try runtime(quality: .low); defer { runtime.stop() }
        XCTAssertFalse(runtime.playCaptured(frame, windowFrame: rect, preset: EffectPreset(effect: .shatter)))
        XCTAssertFalse(runtime.isPlaying)
        XCTAssertFalse(runtime.hasScene)
        XCTAssertNotNil(runtime.errorMessage)
        XCTAssertEqual(window.frame, original)
    }

    @MainActor private func helperWindow() async throws -> (Process, CGWindowID) {
        let permissionWindow = try documentWindow()
        permissionWindow.close()
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = ["-e", Self.helperProgram, root.appendingPathComponent("README.md").path]
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.standardError
        try process.run()
        addTeardownBlock {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            await Task.detached { process.waitUntilExit() }.value
        }
        let data = await Task.detached { output.fileHandleForReading.availableData }.value
        let fields = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isWhitespace)
        XCTAssertEqual(fields.count, 3)
        guard fields.count == 3 else { throw StudioUIError.message("Invalid helper window metadata.") }
        let id = try XCTUnwrap(CGWindowID(fields[0]))
        let expectedOrigin = CGPoint(x: try XCTUnwrap(Double(fields[1])), y: try XCTUnwrap(Double(fields[2])))
        // AppKit's display call precedes WindowServer's native fade completion.
        // Wait for both opacity and the child's actual AppKit origin: WindowServer
        // can report an opaque but still sliding intermediate window position.
        let deadline = CACurrentMediaTime() + 2
        repeat {
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] ?? []
            if windows.contains(where: {
                ($0[kCGWindowNumber as String] as? UInt32) == id
                    && ($0[kCGWindowAlpha as String] as? Double ?? 0) > 0.97
            }), WindowLocator.frame(of: id)?.origin == expectedOrigin { return (process, id) }
            try await Task.sleep(for: .milliseconds(20))
        } while CACurrentMediaTime() < deadline
        throw StudioUIError.message("The owned helper did not settle at its AppKit origin.")
    }

    @MainActor func testSelectedHelperPreviewRequiresNoAccessibilityAndKeepsItsOrigin() async throws {
        let (_, id) = try await helperWindow()
        let original = try XCTUnwrap(WindowLocator.frame(of: id))
        let runtime = try runtime(); defer { runtime.stop() }
        let document = StudioDocument(duration: 1, layers: [StudioLayer(preset: EffectPreset(effect: .fold))])
        let output = try await runtime.preview(document: document, time: 0.4, windowID: id)
        XCTAssertEqual(output.size, original.size)
        XCTAssertEqual(WindowLocator.frame(of: id), original)
        XCTAssertFalse(runtime.isPlaying)
    }

    /// Only this child may be parked. AX never mutates self-process AppKit from
    /// a background queue, and never selects a pre-existing desktop window.
    @MainActor func testManualPlaybackAndCancellationRestoreExactHelperWindowOrigin() async throws {
        guard AXIsProcessTrusted() else { throw XCTSkip("Accessibility permission required; no prompt") }
        let (process, id) = try await helperWindow()
        let original = try XCTUnwrap(WindowLocator.frame(of: id))
        let runtime = try runtime(); defer { runtime.stop() }
        XCTAssertTrue(runtime.availableWindows().contains { $0.id == id })
        let info = WindowInfo(id: id, pid: process.processIdentifier, frame: original)
        let element: AXUIElement? = await withCheckedContinuation { continuation in
            AXBridge.queue(for: info.pid).async {
                let candidate = AXBridge.findWindow(info, hitPoint: CGPoint(x: original.midX, y: original.minY + 12))
                continuation.resume(returning: candidate.flatMap { AXBridge.windowID(of: $0) == id ? $0 : nil })
            }
        }
        let ownElement = try XCTUnwrap(element)
        var preset = EffectPreset(effect: .fold); preset.duration = 0.3
        for cancel in [true, false] {
            await runtime.play(preset, windowID: id)
            XCTAssertTrue(runtime.isPlaying, runtime.errorMessage ?? "The real helper must start playback")
            if cancel { runtime.stop() }
            let deadline = CACurrentMediaTime() + 3
            var actual: CGRect?
            repeat {
                try await Task.sleep(for: .milliseconds(20))
                actual = await withCheckedContinuation { continuation in
                    AXBridge.queue(for: info.pid).async { continuation.resume(returning: AXBridge.frame(of: ownElement)) }
                }
            } while (runtime.isPlaying || actual != original) && CACurrentMediaTime() < deadline
            XCTAssertFalse(runtime.isPlaying)
            XCTAssertEqual(try XCTUnwrap(actual), original, "Both cancellation and natural completion must restore the exact original CGRect")
        }
        // A preview of the same selected helper must not park or resize it.
        let document = StudioDocument(duration: 1, layers: [StudioLayer(preset: EffectPreset(effect: .fold))])
        _ = try await runtime.preview(document: document, time: 0.4, windowID: id)
        XCTAssertEqual(WindowLocator.frame(of: id), original)
        XCTAssertFalse(runtime.isPlaying)

        // A failed second park must still release ownership and restore before its callback.
        let lease = CatalogWindowLease(element: ownElement, info: info)
        runtime.ownMinimizeLease(lease)
        let parked = await lease.park()
        XCTAssertTrue(parked, "Requested park \(NSScreen.parkingPoint); actual \(String(describing: WindowLocator.frame(of: id))); original \(original)")
        let parkedAgain = await lease.park()
        XCTAssertFalse(parkedAgain)
        await withCheckedContinuation { continuation in
            runtime.releaseMinimizeLease(lease) { continuation.resume() }
        }
        XCTAssertEqual(WindowLocator.frame(of: id), original)
        lease.move(to: NSScreen.parkingPoint) // A cancelled lease must never move again.

        // Quit restores synchronously, including a restore already pending on the app queue.
        let quitLease = CatalogWindowLease(element: ownElement, info: info)
        runtime.ownMinimizeLease(quitLease)
        let quitParked = await quitLease.park()
        XCTAssertTrue(quitParked)
        runtime.releaseMinimizeLease(quitLease)
        let began = CACurrentMediaTime()
        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: NSApp)
        XCTAssertLessThan(CACurrentMediaTime() - began, 1)
        XCTAssertEqual(WindowLocator.frame(of: id), original)
        XCTAssertFalse(runtime.isPlaying)

        let nativeLease = CatalogWindowLease(element: ownElement, info: info)
        runtime.ownMinimizeLease(nativeLease)
        let nativeParked = await nativeLease.park()
        XCTAssertTrue(nativeParked)
        let beforeMinimize = await nativeLease.isMinimized()
        XCTAssertEqual(beforeMinimize, false, "Parking alone is not a native minimize")
        nativeLease.minimize()
        let deadline = CACurrentMediaTime() + 2
        var minimized = await nativeLease.isMinimized()
        while minimized != true, CACurrentMediaTime() < deadline {
            try await Task.sleep(for: .milliseconds(25))
            minimized = await nativeLease.isMinimized()
        }
        XCTAssertEqual(minimized, true)
        await withCheckedContinuation { continuation in
            runtime.releaseMinimizeLease(nativeLease) { continuation.resume() }
        }
        let restored: CGRect? = await withCheckedContinuation { continuation in
            AXBridge.queue(for: info.pid).async { continuation.resume(returning: AXBridge.frame(of: ownElement)) }
        }
        XCTAssertEqual(restored, original)
        let stillMinimized = await nativeLease.isMinimized()
        XCTAssertEqual(stillMinimized, true, "Restoration must not undo the native user action")
    }

    private static let helperProgram = #"""
    import AppKit
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    app.finishLaunching()
    let screen = NSScreen.screens.first!
    let visible = screen.visibleFrame
    let window = NSWindow(contentRect: NSRect(x: visible.minX + 60, y: visible.minY + 90, width: 420, height: 240),
        styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.animationBehavior = .none
    window.title = "Catalog runtime helper — README.md"
    let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 240))
    text.isVerticallyResizable = false
    text.isHorizontallyResizable = false
    text.autoresizingMask = [.width, .height]
    text.string = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
    text.isEditable = false
    text.drawsBackground = true
    text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    window.contentView = text
    let reader = Thread {
        while readLine() != nil {}
        DispatchQueue.main.async { exit(0) }
    }
    reader.start()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
        app.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.displayIfNeeded()
        let top = NSScreen.screens.first!.frame.maxY
        FileHandle.standardOutput.write(Data("\(window.windowNumber) \(window.frame.minX) \(top - window.frame.maxY)\n".utf8))
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 20) { exit(0) }
    app.run()
    """#

    @MainActor private func pixels(_ image: NSImage) -> Data? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)?.dataProvider?.data as Data?
    }
}