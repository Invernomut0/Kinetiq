// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import KinetiqCore

/// Exercises the shipped manifest and real serialization/math implementations, without renderers or mocks.
final class EffectCatalogTests: XCTestCase {
    func testManifestIsExhaustiveAndUnique() throws {
        XCTAssertEqual(EffectCatalog.effects.count, 19)
        XCTAssertEqual(Set(EffectCatalog.effects.map(\.id)), Set(EffectID.allCases))
        XCTAssertEqual(Set(EffectCatalog.effects.map(\.id)).count, EffectCatalog.effects.count)
        XCTAssertEqual(Set(EffectCatalog.effects.map(\.category)), Set(EffectCategory.allCases))
        for descriptor in EffectCatalog.effects {
            XCTAssertEqual(EffectCatalog.descriptor(descriptor.id).title, descriptor.title)
            XCTAssertFalse(descriptor.title.isEmpty)
            XCTAssertFalse(descriptor.summary.isEmpty)
            XCTAssertFalse(descriptor.fallback.isEmpty)
            XCTAssertFalse(descriptor.rendering.title.isEmpty)
            XCTAssertFalse(descriptor.category.title.isEmpty)
            XCTAssertFalse(descriptor.category.symbol.isEmpty)
            XCTAssertTrue(descriptor.triggers.contains(.manual))
            XCTAssertEqual(Set(descriptor.triggers).count, descriptor.triggers.count)
            for trigger in descriptor.triggers { XCTAssertFalse(trigger.title.isEmpty) }
            XCTAssertEqual(Set(descriptor.parameters.map(\.id)).count, descriptor.parameters.count)
            XCTAssertGreaterThan(descriptor.parameters.count, 2)
            for spec in descriptor.parameters {
                XCTAssertFalse(spec.title.isEmpty)
                XCTAssertTrue(spec.minimum.isFinite && spec.maximum.isFinite && spec.defaultValue.isFinite)
                XCTAssertLessThan(spec.minimum, spec.maximum)
                XCTAssertTrue((spec.minimum...spec.maximum).contains(spec.defaultValue))
            }
            let amplitude = try XCTUnwrap(descriptor.parameters.first { $0.id == "amplitude" })
            XCTAssertEqual(amplitude.minimum, 0)
            XCTAssertEqual(amplitude.maximum, 2)
            XCTAssertEqual(amplitude.defaultValue, 1)
            let speed = try XCTUnwrap(descriptor.parameters.first { $0.id == "speed" })
            XCTAssertEqual(speed.minimum, 0.1)
            XCTAssertEqual(speed.maximum, 4)
            XCTAssertEqual(speed.defaultValue, 1)
        }
    }

    func testExactMenuMappingAndWireIDs() {
        let expected: [EffectID: (EffectCategory, String)] = [
            .wobbly: (.windowMotion, "Elastic"), .float: (.windowMotion, "Ambient Motion"),
            .genie: (.transitions, "Minimize / Restore"), .morph: (.transitions, "Transform"),
            .ripple: (.transitions, "Distortion"), .liquidMorph: (.transitions, "Distortion"),
            .fold: (.spatial, "3D Transform"), .flip: (.spatial, "3D Transform"),
            .portal: (.spatial, "Distortion"), .depthOfField: (.spatial, "Depth & Lighting"),
            .magnet: (.physics, "Attraction & Snapping"), .gravity: (.physics, "Forces & Dynamics"),
            .shatter: (.destruction, "Fragmentation"), .explode: (.destruction, "Fragmentation"),
            .dissolve: (.destruction, "Dissolution"), .burn: (.destruction, "Dissolution"),
            .workspaceCube: (.workspace, "Workspace Navigation"),
            .orbit: (.workspace, "Window Arrangement"), .expose3D: (.workspace, "Window Overview"),
        ]
        for (id, mapping) in expected {
            XCTAssertEqual(EffectCatalog.descriptor(id).category, mapping.0)
            XCTAssertEqual(EffectCatalog.descriptor(id).submenu, mapping.1)
        }
        XCTAssertEqual(EffectID.depthOfField.rawValue, "depth-of-field")
        XCTAssertEqual(EffectID.liquidMorph.rawValue, "liquid-morph")
        XCTAssertEqual(EffectID.workspaceCube.rawValue, "workspace-cube")
        XCTAssertEqual(EffectID.expose3D.rawValue, "expose-3d")
        XCTAssertEqual(EffectCategory.allCases.map { category in
            EffectCatalog.effects.filter { $0.category == category }.count
        }, [2, 4, 4, 4, 2, 3])
        let cube = EffectCatalog.descriptor(.workspaceCube)
        XCTAssertTrue(cube.summary.contains("current Space"))
        XCTAssertTrue(cube.summary.contains("does not switch native Spaces"))
        XCTAssertEqual(cube.rendering, .multiWindow)
    }

    func testEveryShippedPresetValidatesAndRoundTripsDeterministically() throws {
        for descriptor in EffectCatalog.effects {
            XCTAssertEqual(descriptor.presets.count, 3)
            XCTAssertEqual(descriptor.defaultPreset, EffectPreset(effect: descriptor.id))
            for preset in descriptor.presets {
                XCTAssertEqual(try preset.validated(), preset)
                let data = try preset.encoded()
                XCTAssertEqual(try EffectPreset.decode(data), preset)
                XCTAssertEqual(try EffectPreset.decode(data).encoded(), data)
                XCTAssertEqual(try JSONDecoder().decode(EffectPreset.self, from: data), preset)
            }
        }
    }

    func testCurveEndpointsAndBoundsIncludingNonfiniteInputs() {
        for curve in AnimationCurve.allCases {
            XCTAssertEqual(curve.value(at: 0), 0)
            XCTAssertEqual(curve.value(at: 1), 1)
            XCTAssertEqual(curve.value(at: -1), 0)
            XCTAssertEqual(curve.value(at: 2), 1)
            XCTAssertEqual(curve.value(at: .nan), 0)
            XCTAssertEqual(curve.value(at: -.infinity), 0)
            XCTAssertEqual(curve.value(at: .infinity), 1)
            for i in 0...1000 {
                let sample = curve.value(at: Double(i) / 1000)
                XCTAssertTrue(sample.isFinite)
                XCTAssertTrue((0...1).contains(sample))
            }
        }
        XCTAssertEqual(AnimationCurve.linear.value(at: 0.25), 0.25)
        XCTAssertEqual(AnimationCurve.easeIn.value(at: 0.5), 0.25)
        XCTAssertEqual(AnimationCurve.easeOut.value(at: 0.5), 0.75)
        XCTAssertEqual(AnimationCurve.easeInOut.value(at: 0.25), 0.15625)
        let t = 0.2
        XCTAssertEqual(AnimationCurve.spring.value(at: t),
                       min(1, (1 - exp(-6 * t) * cos(8 * t)) / (1 - exp(-6) * cos(8))), accuracy: 1e-12)
    }

    func testLinearInterpolationUsesNormalizedTimeAndHoldsEndpoints() throws {
        var preset = EffectPreset(effect: .wobbly)
        preset.duration = 4
        preset.tracks = [AnimationTrack(parameter: "amplitude", keyframes: [
            AnimationKeyframe(time: 0.25, value: 0.2, curve: .linear),
            AnimationKeyframe(time: 0.75, value: 1.8),
        ])]
        _ = try preset.validated()
        for seconds in [-10.0, 0, 1] { XCTAssertEqual(preset.value("amplitude", at: seconds), 0.2) }
        XCTAssertEqual(preset.value("amplitude", at: 1.5), 0.6, accuracy: 1e-12)
        XCTAssertEqual(preset.value("amplitude", at: 2), 1, accuracy: 1e-12)
        for seconds in [3.0, 4, 100] { XCTAssertEqual(preset.value("amplitude", at: seconds), 1.8) }
        XCTAssertEqual(preset.value("amplitude", at: .nan), 0.2)
        XCTAssertEqual(preset.value("amplitude", at: -.infinity), 0.2)
        XCTAssertEqual(preset.value("amplitude", at: .infinity), 1.8)
    }

    func testOutgoingCurveAndMultipleSegmentsDescendingValues() throws {
        var preset = EffectPreset(effect: .flip)
        preset.duration = 2
        preset.curve = .spring
        preset.tracks = [AnimationTrack(parameter: "angle", keyframes: [
            AnimationKeyframe(time: 0, value: -180, curve: .easeIn),
            AnimationKeyframe(time: 0.5, value: 180, curve: .linear),
            AnimationKeyframe(time: 1, value: -180, curve: .spring),
        ])]
        _ = try preset.validated()
        XCTAssertEqual(preset.value("angle", at: 0.5), -90)
        XCTAssertEqual(preset.value("angle", at: 1), 180)
        XCTAssertEqual(preset.value("angle", at: 1.5), 0)
        XCTAssertEqual(preset.value("angle", at: 2), -180)
        let samples = (0...200).map { preset.value("angle", at: Double($0) / 100) }
        XCTAssertEqual(samples, (0...200).map { preset.value("angle", at: Double($0) / 100) })
        let decoded = try EffectPreset.decode(preset.encoded())
        XCTAssertEqual(samples, (0...200).map { decoded.value("angle", at: Double($0) / 100) })
    }

    func testMutedEmptySingleAndMissingTracks() throws {
        var preset = EffectPreset(effect: .ripple)
        preset.parameters["amplitude"] = 0.7
        XCTAssertEqual(preset.value("amplitude", at: 0.5), 0.7)
        preset.tracks = [AnimationTrack(parameter: "amplitude")]
        XCTAssertEqual(preset.value("amplitude", at: 0.5), 0.7)
        preset.tracks[0].keyframes = [AnimationKeyframe(time: 0.5, value: 1.8)]
        for t in [-1.0, 0, 0.5, 1, 2] { XCTAssertEqual(preset.value("amplitude", at: t), 1.8) }
        preset.tracks[0].muted = true
        XCTAssertEqual(preset.value("amplitude", at: 0.5), 0.7)
        preset.parameters = [:]
        XCTAssertEqual(preset.value("amplitude", at: 0.5), 1)
        XCTAssertEqual(preset.value("wavelength", at: 0.5), 150)
        XCTAssertEqual(preset.value("not-a-parameter", at: 0.5), 0)
        _ = try preset.validated()
    }

    func testAllParameterBoundsAndNonfiniteFailures() throws {
        for descriptor in EffectCatalog.effects {
            for spec in descriptor.parameters {
                for accepted in [spec.minimum, spec.maximum] {
                    var preset = descriptor.defaultPreset
                    preset.parameters[spec.id] = accepted
                    _ = try preset.validated()
                }
                for rejected in [spec.minimum.nextDown, spec.maximum.nextUp,
                                 Double.nan, Double.infinity, -Double.infinity] {
                    var preset = descriptor.defaultPreset
                    preset.parameters[spec.id] = rejected
                    assertInvalid(preset)
                }
            }
        }
    }

    func testPresetDurationBoundsAndSchema() throws {
        var preset = EffectPreset(effect: .wobbly)
        for duration in [0.1, 12.0] { preset.duration = duration; _ = try preset.validated() }
        for duration in [(0.1).nextDown, (12.0).nextUp, 0, -1, .nan, .infinity, -.infinity] {
            preset.duration = duration
            assertInvalid(preset)
        }
        preset.duration = 1
        for version in [0, -1, 2, Int.max] {
            preset.schemaVersion = version
            XCTAssertThrowsError(try preset.validated()) {
                XCTAssertEqual($0 as? AnimationValidationError, .unsupportedVersion(version))
            }
        }
    }

    func testUnknownParametersAndUnsupportedTriggers() {
        var preset = EffectPreset(effect: .wobbly)
        preset.parameters["typo"] = 1
        XCTAssertThrowsError(try preset.validated()) {
            XCTAssertEqual($0 as? AnimationValidationError, .unknownParameter("typo"))
        }
        preset.parameters.removeValue(forKey: "typo")
        preset.tracks = [AnimationTrack(parameter: "typo", muted: true)]
        assertInvalid(preset)
        preset.tracks = []
        preset.trigger = .close
        assertInvalid(preset)
    }

    func testKeyframeTimeValueAndOrderingFailuresEvenWhenMuted() {
        var preset = EffectPreset(effect: .wobbly)
        for time in [-0.01, 1.01, .nan, .infinity, -.infinity] {
            preset.tracks = [AnimationTrack(parameter: "amplitude", keyframes: [
                AnimationKeyframe(time: time, value: 1),
            ], muted: true)]
            assertInvalid(preset)
        }
        for value in [-0.01, 2.01, .nan, .infinity, -.infinity] {
            preset.tracks = [AnimationTrack(parameter: "amplitude", keyframes: [
                AnimationKeyframe(time: 0.5, value: value),
            ])]
            assertInvalid(preset)
        }
        for times in [[0.5, 0.5], [0.75, 0.25]] {
            preset.tracks = [AnimationTrack(parameter: "amplitude", keyframes:
                times.map { AnimationKeyframe(time: $0, value: 1) })]
            assertInvalid(preset)
        }
    }

    func testTrackAndKeyframeLimitsAndDuplicates() throws {
        var preset = EffectPreset(effect: .wobbly)
        preset.tracks = [AnimationTrack(parameter: "amplitude", keyframes: (0..<128).map {
            AnimationKeyframe(time: Double($0) / 127, value: Double($0) / 127)
        })]
        _ = try preset.validated()
        XCTAssertEqual(try EffectPreset.decode(preset.encoded()), preset)
        preset.tracks[0].keyframes.append(AnimationKeyframe(time: 1, value: 1))
        XCTAssertThrowsError(try preset.validated()) {
            XCTAssertEqual($0 as? AnimationValidationError, .limitExceeded(path: "keyframes", maximum: 128))
        }
        preset.tracks = (0..<65).map { AnimationTrack(parameter: "parameter\($0)") }
        XCTAssertThrowsError(try preset.validated()) {
            XCTAssertEqual($0 as? AnimationValidationError, .limitExceeded(path: "tracks", maximum: 64))
        }
        let track = AnimationTrack(parameter: "amplitude")
        preset.tracks = [track, track]
        assertInvalid(preset)
        preset.tracks = [track, AnimationTrack(parameter: "amplitude", muted: true)]
        assertInvalid(preset)
        var duplicateID = AnimationTrack(parameter: "speed")
        duplicateID.id = track.id
        preset.tracks = [track, duplicateID]
        assertInvalid(preset)
        let key = AnimationKeyframe(time: 0, value: 1)
        var later = key
        later.time = 1
        preset.tracks = [AnimationTrack(parameter: "amplitude", keyframes: [key, later])]
        assertInvalid(preset)
        preset.tracks = [AnimationTrack(parameter: "amplitude", keyframes: [key]),
                         AnimationTrack(parameter: "speed", keyframes: [key])]
        assertInvalid(preset)
    }

    func testStudioRoundTripPreservesAllStateAndIDs() throws {
        var preset = EffectCatalog.descriptor(.gravity).presets[2]
        preset.tracks = [AnimationTrack(parameter: "restitution", keyframes: [
            AnimationKeyframe(time: 0, value: 0.1, curve: .linear),
            AnimationKeyframe(time: 1, value: 0.9),
        ], muted: true)]
        var first = StudioLayer(preset: preset, start: 0.5)
        first.name = "Falling window"
        first.enabled = false
        let document = StudioDocument(name: "Gravity study", duration: 5, layers: [
            first, StudioLayer(preset: EffectPreset(effect: .workspaceCube), start: 3),
        ])
        XCTAssertEqual(try document.validated(), document)
        let data = try document.encoded()
        XCTAssertEqual(try StudioDocument.decode(data), document)
        XCTAssertEqual(try StudioDocument.decode(data).encoded(), data)
        XCTAssertEqual(try JSONDecoder().decode(StudioDocument.self, from: data), document)
        XCTAssertEqual(try StudioDocument.decode(StudioDocument().encoded()), StudioDocument())
    }

    func testStudioDurationLayerLimitsAndOffsets() throws {
        var document = StudioDocument(duration: 60, layers: (0..<32).map { _ in
            StudioLayer(preset: EffectPreset(effect: .wobbly), start: 59)
        })
        _ = try document.validated()
        XCTAssertEqual(try StudioDocument.decode(document.encoded()), document)
        document.layers.append(StudioLayer(preset: EffectPreset(effect: .wobbly)))
        XCTAssertThrowsError(try document.validated()) {
            XCTAssertEqual($0 as? AnimationValidationError, .limitExceeded(path: "layers", maximum: 32))
        }
        document.layers = []
        for duration in [0.1, 60] { document.duration = duration; _ = try document.validated() }
        for duration in [0, -1, (60.0).nextUp, .nan, .infinity, -.infinity] {
            document.duration = duration
            assertInvalid(document)
        }
        document.duration = 3
        document.layers = [StudioLayer(preset: EffectPreset(effect: .wobbly))]
        for start in [-1, 2.01, 3, .nan, .infinity, -.infinity] {
            document.layers[0].start = start
            document.layers[0].enabled = false
            assertInvalid(document)
        }
        document.layers[0].start = 2
        _ = try document.validated()
        document.layers.append(document.layers[0])
        assertInvalid(document)
        document.layers = []
        document.schemaVersion = 3
        assertInvalid(document)
        document.schemaVersion = 1
        _ = try document.validated()
    }

    func testSchemaOneDocumentsDecodeAndUpgradeWhileBuiltinLayersNeedSchemaTwo() throws {
        let legacy = StudioDocument(duration: 2, layers: [StudioLayer(preset: EffectPreset(effect: .fold))])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: legacy.encoded()) as? [String: Any])
        json["schemaVersion"] = 1
        var layers = try XCTUnwrap(json["layers"] as? [[String: Any]])
        layers[0]["builtin"] = nil
        layers[0]["reversed"] = nil
        json["layers"] = layers
        let decoded = try StudioDocument.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.schemaVersion, StudioDocument.currentSchemaVersion)
        XCTAssertEqual(decoded.layers[0].preset, legacy.layers[0].preset)
        XCTAssertFalse(decoded.layers[0].reversed)
        XCTAssertNil(decoded.layers[0].builtin)

        var builtin = StudioLayer(builtin: "close:incinerate", name: "Incinerate", duration: 2)
        builtin.reversed = true
        let document = StudioDocument(duration: 3, layers: [builtin])
        let roundTrip = try StudioDocument.decode(document.encoded())
        XCTAssertEqual(roundTrip.layers[0].builtin, "close:incinerate")
        XCTAssertTrue(roundTrip.layers[0].reversed)
        XCTAssertEqual(roundTrip.layers[0].duration, 2)
        XCTAssertEqual(roundTrip.layers[0].progress(at: 0), 1, accuracy: 1e-9)
        XCTAssertEqual(roundTrip.layers[0].progress(at: 2), 0, accuracy: 1e-9)

        var downgraded = try XCTUnwrap(JSONSerialization.jsonObject(with: document.encoded()) as? [String: Any])
        downgraded["schemaVersion"] = 1
        XCTAssertThrowsError(try StudioDocument.decode(JSONSerialization.data(withJSONObject: downgraded)))
        for invalid in ["", "close:", "liquid", "catalog:fold", "close:../x", String(repeating: "a", count: 200)] {
            var bad = document
            bad.layers[0].builtin = invalid
            assertInvalid(bad)
        }
    }

    func testStudioDecimalTimelineBoundaryAllowsOnlyRoundingError() throws {
        var preset = EffectPreset(effect: .wobbly)
        preset.duration = 0.1
        var document = StudioDocument(duration: 0.3, layers: [StudioLayer(preset: preset, start: 0.2)])
        _ = try document.validated()
        XCTAssertEqual(try StudioDocument.decode(document.encoded()), document)
        document.layers[0].start += 0.000001
        assertInvalid(document)
    }

    func testStudioValidatesNestedPresetsAndNames() {
        var document = StudioDocument(layers: [StudioLayer(preset: EffectPreset(effect: .wobbly))])
        document.layers[0].preset.parameters["amplitude"] = .nan
        assertInvalid(document)
        document.layers[0].preset = EffectPreset(effect: .wobbly)
        document.layers[0].name = "\n"
        assertInvalid(document)
        document.layers = []
        for name in ["", "   ", "line\nbreak", String(repeating: "a", count: 257), "bad\u{0}name"] {
            document.name = name
            assertInvalid(document)
            var preset = EffectPreset(effect: .wobbly)
            preset.name = name
            assertInvalid(preset)
        }
    }

    func testStrictPresetJSONRejectsUnknownMissingAndInvalidFields() throws {
        let preset = EffectPreset(effect: .wobbly)
        let object = try jsonObject(preset.encoded())
        for key in object.keys {
            var missing = object
            missing.removeValue(forKey: key)
            assertPresetJSONRejected(missing)
        }
        var unknown = object
        unknown["futureField"] = true
        assertPresetJSONRejected(unknown)
        for (field, value) in [("schemaVersion", 2 as Any), ("effect", "unknown"),
                               ("curve", "unknown"), ("trigger", "close"),
                               ("duration", 13), ("duration", NSNull()),
                               ("parameters", ["unknown": 1]), ("parameters", ["amplitude": 3]),
                               ("tracks", NSNull())] {
            var invalid = object
            invalid[field] = value
            assertPresetJSONRejected(invalid)
        }
        XCTAssertThrowsError(try EffectPreset.decode(Data("not JSON".utf8)))
        XCTAssertThrowsError(try EffectPreset.decode(Data("[]".utf8)))
        XCTAssertThrowsError(try EffectPreset.decode(Data("{\"duration\":1e999}".utf8)))
    }

    func testStrictNestedJSONRejectsUnknownFieldsAndBadTracks() throws {
        var preset = EffectPreset(effect: .wobbly)
        preset.tracks = [AnimationTrack(parameter: "amplitude", keyframes: [
            AnimationKeyframe(time: 0.5, value: 1),
        ])]
        let original = try jsonObject(preset.encoded())
        let originalTrack = try XCTUnwrap((original["tracks"] as? [[String: Any]])?.first)
        let originalKey = try XCTUnwrap((originalTrack["keyframes"] as? [[String: Any]])?.first)
        for key in originalTrack.keys {
            var track = originalTrack
            track.removeValue(forKey: key)
            var object = original
            object["tracks"] = [track]
            assertPresetJSONRejected(object)
        }
        for key in originalKey.keys {
            var frame = originalKey
            frame.removeValue(forKey: key)
            var track = originalTrack
            track["keyframes"] = [frame]
            var object = original
            object["tracks"] = [track]
            assertPresetJSONRejected(object)
        }
        for (field, value) in [("unknown", true as Any), ("time", -0.1),
                               ("time", 1.1), ("value", 3), ("curve", "unknown"), ("id", "bad UUID")] {
            var frame = originalKey
            frame[field] = value
            var track = originalTrack
            track["keyframes"] = [frame]
            var object = original
            object["tracks"] = [track]
            assertPresetJSONRejected(object)
        }
        for (field, value) in [("unknown", true as Any), ("parameter", "unknown"),
                               ("keyframes", Array(repeating: originalKey, count: 129))] {
            var track = originalTrack
            track[field] = value
            var object = original
            object["tracks"] = [track]
            assertPresetJSONRejected(object)
        }
        var object = original
        object["tracks"] = Array(repeating: originalTrack, count: 65)
        assertPresetJSONRejected(object)
    }

    func testStrictStudioJSONAndNestedLayerLimits() throws {
        let document = StudioDocument(layers: [StudioLayer(preset: EffectPreset(effect: .wobbly))])
        let original = try jsonObject(document.encoded())
        let layer = try XCTUnwrap((original["layers"] as? [[String: Any]])?.first)
        for field in original.keys {
            var object = original
            object.removeValue(forKey: field)
            assertStudioJSONRejected(object)
        }
        // `reversed` (schema 2) is optional so schema-1 layers still decode; every other field is required.
        for field in layer.keys where field != "reversed" {
            var missing = layer
            missing.removeValue(forKey: field)
            var object = original
            object["layers"] = [missing]
            assertStudioJSONRejected(object)
        }
        for (field, value) in [("unknown", 1 as Any), ("schemaVersion", 3), ("schemaVersion", 0), ("duration", 61),
                               ("layers", Array(repeating: layer, count: 33))] {
            var object = original
            object[field] = value
            assertStudioJSONRejected(object)
        }
        for (field, value) in [("unknown", 1 as Any), ("start", -1), ("start", 3), ("id", "bad UUID")] {
            var modified = layer
            modified[field] = value
            var object = original
            object["layers"] = [modified]
            assertStudioJSONRejected(object)
        }
    }

    func testNonfiniteJSONStringsAreRejectedEvenWithPermissiveDecoder() throws {
        var object = try jsonObject(EffectPreset(effect: .wobbly).encoded())
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        for value in ["NaN", "Infinity", "-Infinity"] {
            object["duration"] = value
            XCTAssertThrowsError(try decoder.decode(EffectPreset.self, from: JSONSerialization.data(withJSONObject: object)))
        }
    }

    func testOversizedJSONIsRejectedBeforeParsing() {
        let data = Data(repeating: 0x20, count: 32 * 1024 * 1024 + 1)
        XCTAssertThrowsError(try EffectPreset.decode(data)) {
            XCTAssertEqual($0 as? AnimationValidationError,
                           .limitExceeded(path: "JSON bytes", maximum: 32 * 1024 * 1024))
        }
        XCTAssertThrowsError(try StudioDocument.decode(data)) {
            XCTAssertEqual($0 as? AnimationValidationError,
                           .limitExceeded(path: "JSON bytes", maximum: 32 * 1024 * 1024))
        }
    }

    private func assertInvalid(_ preset: EffectPreset, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try preset.validated(), file: file, line: line)
        XCTAssertThrowsError(try preset.encoded(), file: file, line: line)
        XCTAssertThrowsError(try JSONEncoder().encode(preset), file: file, line: line)
    }

    private func assertInvalid(_ document: StudioDocument, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try document.validated(), file: file, line: line)
        XCTAssertThrowsError(try document.encoded(), file: file, line: line)
        XCTAssertThrowsError(try JSONEncoder().encode(document), file: file, line: line)
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func assertPresetJSONRejected(_ object: [String: Any], file: StaticString = #filePath,
                                          line: UInt = #line) {
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            XCTAssertThrowsError(try EffectPreset.decode(data), file: file, line: line)
            XCTAssertThrowsError(try JSONDecoder().decode(EffectPreset.self, from: data), file: file, line: line)
        } catch { XCTFail("Unable to serialize test input: \(error)", file: file, line: line) }
    }

    private func assertStudioJSONRejected(_ object: [String: Any], file: StaticString = #filePath,
                                          line: UInt = #line) {
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            XCTAssertThrowsError(try StudioDocument.decode(data), file: file, line: line)
            XCTAssertThrowsError(try JSONDecoder().decode(StudioDocument.self, from: data), file: file, line: line)
        } catch { XCTFail("Unable to serialize test input: \(error)", file: file, line: line) }
    }
}