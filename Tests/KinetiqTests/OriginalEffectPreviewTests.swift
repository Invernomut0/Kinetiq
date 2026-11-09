// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import CoreVideo
import KinetiqCore
import KinetiqEffects
import Metal
import XCTest
@testable import Kinetiq

/// Genuine README document -> WindowServer -> ScreenCaptureKit -> original GPU
/// path. No fabricated captures, injected renderer mocks, or standard-default writes.
final class OriginalEffectPreviewTests: XCTestCase {
    @MainActor private static var preparedApplication = false

    private func settings() throws -> Settings {
        let suite = "io.github.invernomut0.Kinetiq.original-preview-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return Settings(defaults: defaults)
    }

    @MainActor private func document() async throws -> (NSWindow, CapturedFrame, CGRect) {
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
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
        XCTAssertFalse(text.isEmpty)
        let rect = CGRect(x: screen.visibleFrame.minX + 40, y: screen.visibleFrame.minY + 70,
                          width: min(420, screen.visibleFrame.width / 2), height: min(260, screen.visibleFrame.height / 2))
        let window = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.title = "Original effect preview — README.md"
        let view = NSTextView(frame: CGRect(origin: .zero, size: rect.size))
        view.string = text
        view.isEditable = false
        view.isRichText = false
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width, .height]
        view.drawsBackground = true
        view.backgroundColor = .textBackgroundColor
        view.textColor = .textColor
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        window.contentView = view
        window.orderFrontRegardless()
        window.displayIfNeeded()
        do {
            // Let AppKit paint its real document before asking ScreenCaptureKit.
            try await Task.sleep(for: .milliseconds(150))
            let id = CGWindowID(window.windowNumber)
            let frame = try XCTUnwrap(WindowLocator.frame(of: id))
            let capture = WindowCapture()
            _ = await capture.refreshContent()
            let captured = try await capture.capture(WindowInfo(id: id, pid: ProcessInfo.processInfo.processIdentifier, frame: frame))
            XCTAssertTrue(captured.isPainted)
            return (window, captured, frame)
        } catch { window.close(); throw error }
    }

    @MainActor private func pixels(_ image: NSImage) throws -> CGImage {
        var proposed = CGRect(origin: .zero, size: image.size)
        let cg = try XCTUnwrap(image.cgImage(forProposedRect: &proposed, context: nil, hints: nil))
        XCTAssertLessThanOrEqual(cg.width * cg.height, 8_000_000)
        XCTAssertLessThanOrEqual(max(cg.width, cg.height), 8192)
        XCTAssertEqual(cg.colorSpace?.name, WindowCapture.colorSpace.name)
        return cg
    }

    private func bytes(_ image: CGImage) throws -> [UInt8] {
        let data = try XCTUnwrap(image.dataProvider?.data)
        return Array(data as Data)
    }

    private func alphaMass(_ image: CGImage, lowerFraction: Double = 0) throws -> Double {
        let bytes = try bytes(image)
        let first = Int(Double(image.height) * lowerFraction) * image.bytesPerRow
        return stride(from: first + 3, to: bytes.count, by: 4).reduce(0.0) { $0 + Double(bytes[$1]) / 255 }
    }

    @MainActor func testAllThirtyOriginalCloseShadersRenderRealDocumentAndChangePixels() async throws {
        let (window, frame, rect) = try await document()
        defer { window.close() }
        let original = window.frame, preferences = try settings()
        let renderer = OriginalPreviewRenderer(budget: { .forQuality(.high) })
        XCTAssertEqual(CloseEffect.allCases.count, 30)
        for effect in CloseEffect.allCases {
            let start = try await renderer.previewCaptured(effect: .close(effect), frame: frame,
                windowFrame: rect, progress: 0, settings: preferences)
            let middle = try await renderer.previewCaptured(effect: .close(effect), frame: frame,
                windowFrame: rect, progress: 0.35, settings: preferences)
            let a = try pixels(start), b = try pixels(middle)
            XCTAssertGreaterThan(try alphaMass(a), 10, effect.title)
            XCTAssertGreaterThan(try alphaMass(b), 10, effect.title)
            XCTAssertNotEqual(try bytes(a), try bytes(b), "Original shader must respond to its own clock: \(effect.title)")
            XCTAssertEqual(window.frame, original)
            XCTAssertFalse(window.isMiniaturized)
            XCTAssertTrue(window.isVisible)
        }
        XCTAssertEqual(renderer.inFlight, 0)
    }

    @MainActor func testAllSixOriginalEntrancesReplayTheirPhysicsAndKeepSourceUntouched() async throws {
        let (window, frame, rect) = try await document()
        defer { window.close() }
        let original = window.frame, preferences = try settings()
        let renderer = OriginalPreviewRenderer(budget: { .forQuality(.high) })
        XCTAssertEqual(WobbleEntrance.allCases.count, 6)
        for entrance in WobbleEntrance.allCases {
            let start = try await renderer.previewCaptured(effect: .entrance(entrance), frame: frame,
                windowFrame: rect, progress: 0, settings: preferences)
            let middle = try await renderer.previewCaptured(effect: .entrance(entrance), frame: frame,
                windowFrame: rect, progress: 0.12, settings: preferences)
            let repeated = try await renderer.previewCaptured(effect: .entrance(entrance), frame: frame,
                windowFrame: rect, progress: 0.12, settings: preferences)
            let a = try pixels(start), b = try pixels(middle), c = try pixels(repeated)
            XCTAssertGreaterThan(try alphaMass(b), 10)
            XCTAssertNotEqual(try bytes(a), try bytes(b), entrance.title)
            XCTAssertEqual(try bytes(b), try bytes(c), "Scrubbing must deterministically replay \(entrance.title)")
            XCTAssertEqual(window.frame, original)
            XCTAssertTrue(window.isVisible)
        }
    }

    @MainActor func testAllNineOriginalDockMorphsUseTheirOwnDeformerAndFadeAtDestination() async throws {
        let (window, frame, rect) = try await document()
        defer { window.close() }
        let original = window.frame, preferences = try settings()
        let renderer = OriginalPreviewRenderer(budget: { .forQuality(.high) })
        XCTAssertEqual(DockMorphStyle.allCases.count, 9)
        var distinct = Set<Data>()
        for style in DockMorphStyle.allCases {
            let start = try await renderer.previewCaptured(effect: .minimize(style), frame: frame,
                windowFrame: rect, progress: 0, settings: preferences)
            let middle = try await renderer.previewCaptured(effect: .minimize(style), frame: frame,
                windowFrame: rect, progress: 0.5, settings: preferences)
            let end = try await renderer.previewCaptured(effect: .minimize(style), frame: frame,
                windowFrame: rect, progress: 1, settings: preferences)
            let a = try pixels(start), b = try pixels(middle), c = try pixels(end)
            XCTAssertGreaterThan(try alphaMass(b), 10, style.title)
            XCTAssertNotEqual(try bytes(a), try bytes(b), style.title)
            XCTAssertEqual(try alphaMass(c), 0, accuracy: 0.01, style.title)
            distinct.insert(Data(try bytes(b)))
            XCTAssertEqual(window.frame, original)
            XCTAssertFalse(window.isMiniaturized)
        }
        XCTAssertEqual(distinct.count, 9, "No catalog substitute or shared approximation for the original morphs")
    }

    @MainActor func testLiquidRetainsFullStageAfterMeltingAndShowsLocalFloorPool() async throws {
        let (window, frame, rect) = try await document()
        defer { window.close() }
        let preferences = try settings(), original = window.frame
        let renderer = OriginalPreviewRenderer(budget: { .forQuality(.high) })
        let duration = OriginalPreviewRenderer.timelineSeconds(effect: .liquid, preset: nil, settings: preferences,
                                                               source: .window(frame.windowID))
        let start = try await renderer.previewCaptured(effect: .liquid, frame: frame,
            windowFrame: rect, progress: 0, settings: preferences)
        let melt = try await renderer.previewCaptured(effect: .liquid, frame: frame,
            windowFrame: rect, progress: 1.8 / duration, settings: preferences)
        let pool = try await renderer.previewCaptured(effect: .liquid, frame: frame,
            windowFrame: rect, progress: 5 / duration, settings: preferences)
        let end = try await renderer.previewCaptured(effect: .liquid, frame: frame,
            windowFrame: rect, progress: 1, settings: preferences)
        let a = try pixels(start), b = try pixels(melt), c = try pixels(pool)
        XCTAssertEqual(start.size, melt.size)
        XCTAssertEqual(start.size, pool.size)
        XCTAssertGreaterThan(start.size.height, rect.height * 1.8)
        XCTAssertGreaterThan(try alphaMass(b), 10, "Released material must remain visible after 1.4 seconds")
        XCTAssertGreaterThan(try alphaMass(c, lowerFraction: 0.85), 10, "Actual simulated material must reach the retained local floor")
        XCTAssertEqual(try alphaMass(a, lowerFraction: 0.85), 0, accuracy: 0.01)
        XCTAssertNotEqual(try bytes(a), try bytes(b))
        XCTAssertEqual(end.size, start.size)
        XCTAssertEqual(try alphaMass(pixels(end)), 0, "The full preview must include physical drainage")
        XCTAssertEqual(window.frame, original)
        XCTAssertFalse(window.isMiniaturized)
    }

    @MainActor func testMeshIdentitySamplesActualCaptureRatherThanAFlatPlaceholder() async throws {
        let (window, frame, rect) = try await document()
        defer { window.close() }
        let renderer = OriginalPreviewRenderer(budget: { .forQuality(.high) })
        let result = try await renderer.previewCaptured(effect: .minimize(.morph), frame: frame,
            windowFrame: rect, progress: 0, settings: settings())
        let image = try pixels(result), output = try bytes(image)
        let margin = max(24, rect.width * 0.15, frame.shadow.left, frame.shadow.right, frame.shadow.top, frame.shadow.bottom)
        let stage = CGRect(x: rect.minX - margin, y: rect.minY - margin,
            width: rect.width + margin * 2, height: rect.height * 1.5 + margin * 2)
        CVPixelBufferLockBaseAddress(frame.pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(frame.pixelBuffer, .readOnly) }
        let source = try XCTUnwrap(CVPixelBufferGetBaseAddress(frame.pixelBuffer)).assumingMemoryBound(to: UInt8.self)
        let rowBytes = CVPixelBufferGetBytesPerRow(frame.pixelBuffer)
        var error = 0.0
        for y in 1...8 {
            for x in 1...12 {
                let gx = rect.minX + CGFloat(x) / 13 * rect.width, gy = rect.minY + CGFloat(y) / 9 * rect.height
                let px = Int((gx - stage.minX) / stage.width * CGFloat(image.width))
                let py = Int((gy - stage.minY) / stage.height * CGFloat(image.height))
                let u = (stage.minX + (CGFloat(px) + 0.5) / CGFloat(image.width) * stage.width - rect.minX) / rect.width
                let v = (stage.minY + (CGFloat(py) + 0.5) / CGFloat(image.height) * stage.height - rect.minY) / rect.height
                let sx = Int(frame.windowRect.minX + u * frame.windowRect.width)
                let sy = Int(frame.windowRect.minY + v * frame.windowRect.height)
                for c in 0..<4 {
                    error += abs(Double(source[sy * rowBytes + sx * 4 + c]) - Double(output[py * image.bytesPerRow + px * 4 + c])) / 255
                }
            }
        }
        XCTAssertLessThan(error / (8 * 12 * 4), 0.06, "Readback must match the captured README's actual pixels")
    }

    @MainActor func testActualQualityBudgetsReduceOutputWithoutWritingPreferences() async throws {
        let (window, frame, rect) = try await document()
        defer { window.close() }
        let preferences = try settings()
        let savedPhysics = preferences.physics, savedTiles = preferences.tilesX, savedDuration = preferences.closeDuration
        var previousWidth = Int.max
        for quality in [RenderQuality.high, .balanced, .low] {
            let renderer = OriginalPreviewRenderer(budget: { .forQuality(quality) })
            let result = try await renderer.previewCaptured(effect: .minimize(.genie), frame: frame,
                windowFrame: rect, progress: 0.3, settings: preferences)
            let image = try pixels(result)
            XCTAssertLessThan(image.width, previousWidth)
            previousWidth = image.width
            XCTAssertGreaterThan(try alphaMass(image), 10)
        }
        let low = OriginalPreviewRenderer(budget: { .forQuality(.low) })
        do {
            _ = try await low.previewCaptured(effect: .close(.fire), frame: frame, windowFrame: rect, progress: 0.3, settings: preferences)
            XCTFail("Budget must refuse an unscalable shader, never substitute another effect")
        } catch { XCTAssertTrue(error.localizedDescription.contains("budget")) }
        do {
            _ = try await low.previewCaptured(effect: .liquid, frame: frame, windowFrame: rect, progress: 0.3, settings: preferences)
            XCTFail("Liquid must respect the same expensive-effects gate as native playback")
        } catch { XCTAssertTrue(error.localizedDescription.contains("budget")) }
        XCTAssertEqual(preferences.physics, savedPhysics)
        XCTAssertEqual(preferences.tilesX, savedTiles)
        XCTAssertEqual(preferences.closeDuration, savedDuration)
    }

    @MainActor func testCancellationSupersessionAndCapacityRecoverWithRealGPUWork() async throws {
        let (window, frame, rect) = try await document()
        defer { window.close() }
        let preferences = try settings(), original = window.frame
        let renderer = OriginalPreviewRenderer(budget: { .forQuality(.high) })
        let cancelled = Task { @MainActor in
            try await renderer.previewCaptured(effect: .liquid, frame: frame, windowFrame: rect, progress: 1, settings: preferences)
        }
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("A cancelled task must never return an image") }
        catch { XCTAssertTrue(error is CancellationError) }
        let stale = Task { @MainActor in
            try await renderer.previewCaptured(effect: .liquid, frame: frame, windowFrame: rect, progress: 1, settings: preferences)
        }
        await Task.yield()
        renderer.cancel()
        do { _ = try await stale.value; XCTFail("Explicit cancellation must invalidate simulation/readback") }
        catch { XCTAssertTrue(error is CancellationError) }
        // Two progress-zero calls submit GPU work, then yield at completion. The
        // newer request must supersede the older one without releasing its backing.
        let older = Task { @MainActor in
            try await renderer.previewCaptured(effect: .minimize(.genie), frame: frame, windowFrame: rect, progress: 0, settings: preferences)
        }
        await Task.yield()
        let latest = try await renderer.previewCaptured(effect: .minimize(.hop), frame: frame,
            windowFrame: rect, progress: 0.5, settings: preferences)
        do { _ = try await older.value } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertGreaterThan(try alphaMass(pixels(latest)), 10)
        XCTAssertEqual(renderer.inFlight, 0)
        XCTAssertEqual(window.frame, original)
        XCTAssertFalse(window.isMiniaturized)
    }

    @MainActor func testInvalidProgressMissingOrSelfTargetAndDisabledNeverFallback() async throws {
        let renderer = OriginalPreviewRenderer(budget: { .forQuality(.high) })
        let preferences = try settings()
        for progress in [Double.nan, .infinity, -0.1, 1.1] {
            do {
                _ = try await renderer.preview(effect: .liquid, windowID: .max, progress: progress, settings: preferences)
                XCTFail("Invalid progress must be rejected")
            } catch { XCTAssertTrue(error.localizedDescription.contains("progress")) }
        }
        do {
            _ = try await renderer.preview(effect: .liquid, windowID: .max, progress: 0.4, settings: preferences)
            XCTFail("An explicit missing ID must not select a different document")
        } catch { XCTAssertTrue(error.localizedDescription.contains("eligible")) }
        preferences.enabled = false
        do {
            _ = try await renderer.preview(effect: .close(.fire), windowID: .max, progress: 0, settings: preferences)
            XCTFail("Disabled effects must not capture")
        } catch { XCTAssertTrue(error.localizedDescription.contains("paused")) }
        XCTAssertEqual(renderer.inFlight, 0)
        preferences.enabled = true
        let (window, frame, rect) = try await document()
        defer { window.close() }
        do {
            _ = try await renderer.preview(effect: .liquid, windowID: frame.windowID, progress: 0, settings: preferences)
            XCTFail("Own process windows must remain excluded from public selection")
        } catch { XCTAssertTrue(error.localizedDescription.contains("eligible")) }
        for invalid in [CGRect.null, .zero, CGRect(x: 0, y: 0, width: CGFloat.infinity, height: rect.height)] {
            do {
                _ = try await renderer.previewCaptured(effect: .liquid, frame: frame,
                    windowFrame: invalid, progress: 0, settings: preferences)
                XCTFail("Invalid target geometry must be rejected before allocation")
            } catch { XCTAssertTrue(error.localizedDescription.contains("invalid")) }
        }
    }
}