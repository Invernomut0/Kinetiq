// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import KinetiqCore
import KinetiqEffects
import Metal
import XCTest
@testable import Kinetiq

/// The built-in sample window needs no Screen Recording permission, so every library effect's
/// preview path is exercised on any machine with Metal. Set KINETIQ_PREVIEW_DUMP to a directory
/// under /tmp to also write one PNG per effect for visual inspection.
final class SampleWindowPreviewTests: XCTestCase {
    private func settings() throws -> Settings {
        let suite = "io.github.invernomut0.Kinetiq.sample-preview-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return Settings(defaults: defaults)
    }

    @MainActor private func requireMetal() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
    }

    @MainActor private func pixels(_ image: NSImage) throws -> CGImage {
        var proposed = CGRect(origin: .zero, size: image.size)
        return try XCTUnwrap(image.cgImage(forProposedRect: &proposed, context: nil, hints: nil))
    }

    private func bytes(_ image: CGImage) throws -> [UInt8] { Array(try XCTUnwrap(image.dataProvider?.data) as Data) }

    private func alphaMass(_ image: CGImage) throws -> Double {
        let bytes = try bytes(image)
        return stride(from: 3, to: bytes.count, by: 4).reduce(0.0) { $0 + Double(bytes[$1]) / 255 }
    }

    @MainActor private func dump(_ image: NSImage, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["KINETIQ_PREVIEW_DUMP"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cg = try pixels(image)
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
        try data.write(to: directory.appendingPathComponent("\(name).png"), options: .atomic)
    }

    @MainActor func testSampleWindowIsAPaintedCaptureWithShadowRoom() async throws {
        let frame = try SampleWindow.frame()
        XCTAssertEqual(frame.windowID, SampleWindow.windowID)
        XCTAssertEqual(frame.pointSize, SampleWindow.pointSize)
        XCTAssertTrue(frame.isPainted)
        XCTAssertEqual(frame.windowRect.width, SampleWindow.pointSize.width * SampleWindow.scale)
        XCTAssertGreaterThan(frame.windowRect.minX, 0, "The shadow room surrounds the window like a real capture")
        XCTAssertTrue(try SampleWindow.frame().pixelBuffer === frame.pixelBuffer, "The sample is drawn once")
    }

    @MainActor func testEveryLibraryEffectPreviewsOnTheSampleWindowAndAnimates() async throws {
        try requireMetal()
        let preferences = try settings()
        let renderer = OriginalPreviewRenderer(budget: { .forQuality(.high) })
        for effect in LibraryEffect.all {
            let start = try await renderer.preview(effect: effect, source: .sample, progress: 0, settings: preferences)
            let middle = try await renderer.preview(effect: effect, source: .sample, progress: 0.4, settings: preferences)
            let a = try pixels(start), b = try pixels(middle)
            XCTAssertGreaterThan(try alphaMass(a), 10, effect.id)
            XCTAssertGreaterThan(try alphaMass(b), 10, effect.id)
            XCTAssertFalse(try bytes(a) == bytes(b), "\(effect.id) must change between 0% and 40%")
            XCTAssertLessThanOrEqual(a.width * a.height, 8_000_000, effect.id)
            try dump(middle, name: effect.id.replacingOccurrences(of: ":", with: "-"))
        }
        XCTAssertEqual(renderer.inFlight, 0)
    }

    @MainActor func testWobblyPreviewReplaysTheSpringModelDeterministicallyAndFollowsThePreset() async throws {
        try requireMetal()
        let preferences = try settings()
        let renderer = OriginalPreviewRenderer(budget: { .forQuality(.high) })
        let size = SIMD2(Float(SampleWindow.pointSize.width), Float(SampleWindow.pointSize.height))
        XCTAssertEqual(OriginalPreviewRenderer.dragOffset(at: 0, size: size), .zero)
        XCTAssertEqual(OriginalPreviewRenderer.dragOffset(at: OriginalPreviewRenderer.wobblyReleaseSeconds, size: size).x, 0, accuracy: 0.01)
        XCTAssertGreaterThan(OriginalPreviewRenderer.dragOffset(at: OriginalPreviewRenderer.wobblyReleaseSeconds / 2, size: size).x, size.x * 0.2)
        XCTAssertEqual(OriginalPreviewRenderer.timelineSeconds(effect: .catalog(.wobbly), preset: nil, settings: preferences),
                       OriginalPreviewRenderer.wobblyPreviewSeconds)
        let a = try await renderer.preview(effect: .catalog(.wobbly), source: .sample, progress: 0.3, settings: preferences)
        let b = try await renderer.preview(effect: .catalog(.wobbly), source: .sample, progress: 0.3, settings: preferences)
        XCTAssertTrue(try bytes(pixels(a)) == bytes(pixels(b)), "Scrubbing must replay the same frame")
        // Mid-drag the window has moved right: the rendered stage is wider than the resting window.
        XCTAssertGreaterThan(a.size.width, SampleWindow.pointSize.width * 1.3)
        var stiff = EffectPreset(effect: .wobbly)
        stiff.parameters["stiffness"] = 10
        stiff.parameters["friction"] = 1
        let c = try await renderer.preview(effect: .catalog(.wobbly), preset: stiff, source: .sample, progress: 0.75, settings: preferences)
        let d = try await renderer.preview(effect: .catalog(.wobbly), source: .sample, progress: 0.75, settings: preferences)
        XCTAssertFalse(try bytes(pixels(c)) == bytes(pixels(d)), "Preset stiffness/friction must drive the spring replay")
        var still = EffectPreset(effect: .wobbly)
        still.parameters["amplitude"] = 0
        let e = try await renderer.preview(effect: .catalog(.wobbly), preset: still, source: .sample, progress: 0.75, settings: preferences)
        let f = try await renderer.preview(effect: .catalog(.wobbly), preset: still, source: .sample, progress: 1, settings: preferences)
        XCTAssertTrue(try bytes(pixels(e)) == bytes(pixels(f)), "Zero amplitude shows the undeformed window after release")
        try dump(a, name: "wobbly-drag"); try dump(d, name: "wobbly-settle")
    }

    @MainActor func testStudioDocumentsComposeLayersOnTheSampleWindow() async throws {
        try requireMetal()
        let preferences = try settings()
        let renderer = OriginalPreviewRenderer(budget: { .forQuality(.high) })
        var ripple = EffectPreset(effect: .ripple); ripple.duration = 1
        var fold = EffectPreset(effect: .fold); fold.duration = 1
        var flip = EffectPreset(effect: .flip); flip.duration = 1
        let document = StudioDocument(name: "Three layers", duration: 2, layers: [
            StudioLayer(preset: ripple, start: 0), StudioLayer(preset: fold, start: 0.5), StudioLayer(preset: flip, start: 0.5)
        ])
        let idle = try await renderer.preview(document: StudioDocument(name: "Empty", duration: 1), time: 0.5, source: .sample, settings: preferences)
        let single = try await renderer.preview(document: document, time: 0.3, source: .sample, settings: preferences)
        let triple = try await renderer.preview(document: document, time: 0.8, source: .sample, settings: preferences)
        XCTAssertGreaterThan(try alphaMass(pixels(idle)), 10)
        XCTAssertGreaterThan(try alphaMass(pixels(single)), 10)
        XCTAssertGreaterThan(try alphaMass(pixels(triple)), 10)
        XCTAssertFalse(try bytes(pixels(single)) == bytes(pixels(triple)))
        XCTAssertFalse(try bytes(pixels(idle)) == bytes(pixels(triple)))
        try dump(triple, name: "document-three-layers")
        do {
            _ = try await renderer.preview(document: document, time: .nan, source: .sample, settings: preferences)
            XCTFail("Nonfinite time must be rejected")
        } catch { XCTAssertTrue(error.localizedDescription.contains("progress")) }
    }

    @MainActor func testCriticalThermalBudgetAndDisabledStateRefuseSamplePreviewsWithoutFallback() async throws {
        try requireMetal()
        let preferences = try settings()
        var policy = RenderQualityPolicy()
        policy.refreshEnvironment(thermalState: .critical, lowPowerMode: false)
        let critical = OriginalPreviewRenderer(budget: { policy.budget })
        for effect in [LibraryEffect.close(.fire), .liquid, .destruction, .catalog(.shatter), .catalog(.burn)] {
            do {
                _ = try await critical.preview(effect: effect, source: .sample, progress: 0.3, settings: preferences)
                XCTFail("\(effect.id) must refuse when expensive effects are disallowed")
            } catch { XCTAssertTrue(error.localizedDescription.contains("budget"), effect.id) }
        }
        _ = try await critical.preview(effect: .catalog(.wobbly), source: .sample, progress: 0.3, settings: preferences)
        _ = try await critical.preview(effect: .minimize(.genie), source: .sample, progress: 0.3, settings: preferences)
        preferences.enabled = false
        do {
            _ = try await critical.preview(effect: .catalog(.fold), source: .sample, progress: 0.3, settings: preferences)
            XCTFail("Disabled effects must not preview")
        } catch { XCTAssertTrue(error.localizedDescription.contains("paused")) }
    }
}

/// Built-in engines as Studio layers and the overview demo, rendered on the sample window.
final class CompositionPreviewTests: XCTestCase {
    private func settings() throws -> Kinetiq.Settings {
        let suite = "io.github.invernomut0.Kinetiq.composition-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return Kinetiq.Settings(defaults: defaults)
    }

    @MainActor private func bytes(_ image: NSImage) throws -> [UInt8] {
        var proposed = CGRect(origin: .zero, size: image.size)
        let cg = try XCTUnwrap(image.cgImage(forProposedRect: &proposed, context: nil, hints: nil))
        return Array(try XCTUnwrap(cg.dataProvider?.data) as Data)
    }

    private func alpha(_ bytes: [UInt8]) -> Double { stride(from: 3, to: bytes.count, by: 4).reduce(0.0) { $0 + Double(bytes[$1]) / 255 } }

    @MainActor private func dump(_ image: NSImage, _ name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["KINETIQ_PREVIEW_DUMP"] else { return }
        var proposed = CGRect(origin: .zero, size: image.size)
        let cg = try XCTUnwrap(image.cgImage(forProposedRect: &proposed, context: nil, hints: nil))
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        try NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: path).appendingPathComponent("\(name).png"))
    }

    @MainActor func testEveryLayerAcceptsLowQualityButHonorsCriticalAndResourceLimits() throws {
        let layers = BuiltinLayer.all.map { $0.makeLayer() }
            + EffectCatalog.effects.map { StudioLayer(preset: $0.defaultPreset) }
        var policy = RenderQualityPolicy(selection: .ultra)
        policy.refreshEnvironment(thermalState: .critical, lowPowerMode: false)
        for layer in layers {
            XCTAssertNoThrow(try LayerCompositor.check(layer, budget: .forQuality(.low)), layer.name)
            let expensive: Bool
            if case .close = BuiltinLayer(layer.builtin) { expensive = true }
            else { expensive = !layer.isBuiltin && EffectCatalog.descriptor(layer.preset.effect).expensive }
            if expensive {
                XCTAssertThrowsError(try LayerCompositor.check(layer, budget: policy.budget), layer.name)
            } else {
                XCTAssertNoThrow(try LayerCompositor.check(layer, budget: policy.budget), layer.name)
            }
            var invalid = RenderBudget.forQuality(.low)
            invalid.meshLimit = 0
            XCTAssertThrowsError(try LayerCompositor.check(layer, budget: invalid), layer.name)
        }
        var noParticles = RenderBudget.forQuality(.low)
        noParticles.maxParticles = 0
        for effect in [EffectID.shatter, .explode] {
            XCTAssertThrowsError(try LayerCompositor.check(StudioLayer(preset: EffectPreset(effect: effect)), budget: noParticles))
        }
    }

    @MainActor func testEveryBuiltinLayerAnimatesInADocumentAndReverses() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        let preferences = try settings()
        let renderer = OriginalPreviewRenderer(budget: { .forQuality(.high) })
        for builtin in BuiltinLayer.all {
            let layer = builtin.makeLayer()
            let document = StudioDocument(name: builtin.effect.title, duration: layer.end, layers: [layer])
            let start = try bytes(await renderer.preview(document: document, time: 0, source: .sample, settings: preferences))
            let middle = try bytes(await renderer.preview(document: document, time: layer.duration * 0.45, source: .sample, settings: preferences))
            XCTAssertGreaterThan(alpha(start), 10, builtin.effect.id)
            XCTAssertFalse(start == middle, "\(builtin.effect.id) must animate as a layer")
            var reversed = document
            reversed.layers[0].reversed = true
            let back = try bytes(await renderer.preview(document: reversed, time: layer.duration * 0.45, source: .sample, settings: preferences))
            XCTAssertFalse(back == middle, "\(builtin.effect.id) must play differently in reverse")
        }
        XCTAssertEqual(renderer.inFlight, 0)
    }

    @MainActor func testOverlappingStudioAndBuiltinLayersCompose() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        let preferences = try settings()
        let renderer = OriginalPreviewRenderer(budget: { .forQuality(.high) })
        var ripple = EffectPreset(effect: .ripple); ripple.duration = 1.5
        let incinerate = BuiltinLayer.close(.incinerate).makeLayer(start: 0.5)
        let both = StudioDocument(duration: incinerate.end, layers: [StudioLayer(preset: ripple), incinerate])
        let onlyBuiltin = StudioDocument(duration: incinerate.end, layers: [incinerate])
        let composed = try await renderer.preview(document: both, time: 1.0, source: .sample, settings: preferences)
        let single = try await renderer.preview(document: onlyBuiltin, time: 1.0, source: .sample, settings: preferences)
        XCTAssertFalse(try bytes(composed) == bytes(single), "The Ripple layer must feed Incinerate")
        XCTAssertGreaterThan(alpha(try bytes(composed)), 10)
        let ended = try await renderer.preview(document: onlyBuiltin, time: incinerate.end, source: .sample, settings: preferences)
        XCTAssertLessThan(alpha(try bytes(ended)), alpha(try bytes(single)), "A close shader ends with less of the window")
        try dump(composed, "studio-ripple-incinerate")
        let low = OriginalPreviewRenderer(budget: { .forQuality(.low) })
        let lowOutput = try await low.preview(document: onlyBuiltin, time: 1, source: .sample, settings: preferences)
        XCTAssertGreaterThan(alpha(try bytes(lowOutput)), 10)
        var policy = RenderQualityPolicy()
        policy.refreshEnvironment(thermalState: .critical, lowPowerMode: false)
        let critical = OriginalPreviewRenderer(budget: { policy.budget })
        do {
            _ = try await critical.preview(document: onlyBuiltin, time: 1, source: .sample, settings: preferences)
            XCTFail("Close shaders are refused when expensive effects are off")
        } catch { XCTAssertTrue(error.localizedDescription.contains("budget")) }
    }

    @MainActor func testOverviewDemoFliesInBrowsesAndFliesBack() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        let preferences = try settings()
        let renderer = OriginalPreviewRenderer(budget: { .forQuality(.high) })
        for effect in Kinetiq.Settings.overviewLayouts {
            let preset = EffectPreset(effect: effect)
            let seconds = OriginalPreviewRenderer.overviewPreviewSeconds
            let rest = try await renderer.previewOverview(preset, progress: 0.2 / seconds, settings: preferences)
            let arranged = try await renderer.previewOverview(preset, progress: 1.5 / seconds, settings: preferences)
            let browsing = try await renderer.previewOverview(preset, progress: 3 / seconds, settings: preferences)
            let back = try await renderer.previewOverview(preset, progress: 4.5 / seconds, settings: preferences)
            XCTAssertEqual(rest.size, CGSize(width: 1440, height: 900))
            XCTAssertFalse(try bytes(rest) == bytes(arranged), "\(effect)")
            XCTAssertFalse(try bytes(arranged) == bytes(browsing), "\(effect) must browse while shown")
            XCTAssertTrue(try bytes(rest) == bytes(back), "\(effect) must return every window home")
            try dump(arranged, "overview-\(effect.rawValue)")
        }
    }
}
