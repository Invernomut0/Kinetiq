// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import KinetiqCore
import XCTest
@testable import Kinetiq

/// Real, disposable preference domains exercise the same serialization used by the app.
final class CatalogStoreTests: XCTestCase {
    private let presetKey = "catalogPresets.v1"
    private let documentKey = "studioDocument.v1"

    private func isolatedDefaults() throws -> UserDefaults {
        let name = "io.github.invernomut0.Kinetiq.catalog.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    /// Animate genuine manifest parameters across their documented bounds, retaining IDs and curves.
    private func trackedPreset(_ effect: EffectID = .fold) throws -> EffectPreset {
        let descriptor = EffectCatalog.descriptor(effect)
        var preset = try XCTUnwrap(descriptor.presets.last)
        preset.tracks = descriptor.parameters.prefix(2).enumerated().map { index, spec in
            AnimationTrack(parameter: spec.id, keyframes: [
                AnimationKeyframe(time: 0, value: spec.minimum, curve: .linear),
                AnimationKeyframe(time: 0.5, value: spec.defaultValue, curve: .spring),
                AnimationKeyframe(time: 1, value: spec.maximum, curve: .easeOut)
            ], muted: index == 1)
        }
        return try preset.validated()
    }

    /// Derive invalid input from an actual encoded preset instead of maintaining a second schema.
    private func editingJSON(_ data: Data, _ edit: (inout [String: Any]) -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        edit(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    @MainActor
    func testBuiltInDefaultsRemainManualAndLeaveLegacyPreferencesUntouched() async throws {
        let defaults = try isolatedDefaults()
        let settings = Settings(defaults: defaults)
        settings.closeEffect = .liquid
        settings.openEffect = .random
        settings.minimizeEffect = .morph(.genie)
        settings.preset = .subtle
        let before = defaults.dictionaryRepresentation() as NSDictionary
        let store = CatalogStore(defaults: defaults)

        XCTAssertTrue(store.presets.isEmpty)
        XCTAssertNil(store.errorMessage)
        for descriptor in EffectCatalog.effects {
            XCTAssertEqual(store.preset(descriptor.id), descriptor.defaultPreset)
            XCTAssertEqual(store.preset(descriptor.id).trigger, .manual)
        }
        for trigger in EffectTrigger.allCases { XCTAssertNil(store.assigned(to: trigger)) }
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
        XCTAssertNil(defaults.data(forKey: presetKey))
        XCTAssertNil(defaults.data(forKey: documentKey))
        XCTAssertEqual(settings.closeEffect, .liquid)
        XCTAssertEqual(settings.openEffect, .random)
        XCTAssertEqual(settings.minimizeEffect, .morph(.genie))
        XCTAssertEqual(settings.preset, .subtle)
    }

    @MainActor
    func testEveryBuiltInPresetRoundTripsThroughSaveExportImportAndReload() async throws {
        let sourceDefaults = try isolatedDefaults()
        let targetDefaults = try isolatedDefaults()
        let source = CatalogStore(defaults: sourceDefaults)
        let target = CatalogStore(defaults: targetDefaults)
        for descriptor in EffectCatalog.effects {
            for preset in descriptor.presets {
                try source.save(preset)
                let exported = try source.exportPreset(descriptor.id)
                XCTAssertEqual(try EffectPreset.decode(exported), preset)
                try target.importPreset(exported)
                XCTAssertEqual(target.preset(descriptor.id), preset)
                XCTAssertEqual(try target.exportPreset(descriptor.id), exported)
                XCTAssertEqual(CatalogStore(defaults: targetDefaults).preset(descriptor.id), preset)
            }
        }
        let restored = CatalogStore(defaults: sourceDefaults)
        XCTAssertEqual(restored.presets.count, EffectID.allCases.count)
        XCTAssertEqual(restored.presets, source.presets)
        XCTAssertNil(restored.errorMessage)
        let saved = try XCTUnwrap(sourceDefaults.data(forKey: presetKey))
        XCTAssertEqual(try JSONDecoder().decode([EffectPreset].self, from: saved).map(\.effect), EffectID.allCases)
    }

    @MainActor
    func testExportUnsavedDefaultDoesNotCreateAssignmentOrPersistence() async throws {
        let defaults = try isolatedDefaults()
        let store = CatalogStore(defaults: defaults)
        for descriptor in EffectCatalog.effects {
            XCTAssertEqual(try EffectPreset.decode(store.exportPreset(descriptor.id)), descriptor.defaultPreset)
        }
        XCTAssertTrue(store.presets.isEmpty)
        XCTAssertNil(defaults.data(forKey: presetKey))
        XCTAssertNil(store.assigned(to: .manual))
    }

    @MainActor
    func testTrackedPresetRetainsAllTimelineDataAcrossImportAndReload() async throws {
        let defaults = try isolatedDefaults()
        let store = CatalogStore(defaults: defaults)
        var preset = try trackedPreset()
        preset.trigger = .open
        try store.importPreset(preset.encoded())
        let restored = CatalogStore(defaults: defaults)
        XCTAssertEqual(restored.preset(preset.effect), preset)
        XCTAssertEqual(restored.assigned(to: .open), preset)
        XCTAssertEqual(try EffectPreset.decode(restored.exportPreset(preset.effect)), preset)
        for seconds in [0.0, preset.duration * 0.25, preset.duration * 0.5, preset.duration] {
            for track in preset.tracks {
                XCTAssertEqual(restored.preset(preset.effect).value(track.parameter, at: seconds),
                               preset.value(track.parameter, at: seconds))
            }
        }
    }

    @MainActor
    func testImportRejectsUnknownFieldsInvalidParametersAndUnsupportedSchemaWithoutMutation() async throws {
        let defaults = try isolatedDefaults()
        let store = CatalogStore(defaults: defaults)
        let original = try trackedPreset()
        try store.save(original)
        let saved = defaults.data(forKey: presetKey)
        let encoded = try original.encoded()
        let mutations: [(String, (inout [String: Any]) -> Void)] = [
            ("schema", { $0["schemaVersion"] = EffectPreset.currentSchemaVersion + 1 }),
            ("unknown field", { $0["unexpected"] = true }),
            ("unknown effect", { $0["effect"] = "not-a-catalog-effect" }),
            ("unsupported trigger", { $0["trigger"] = EffectTrigger.drag.rawValue }),
            ("duration", { $0["duration"] = -1 }),
            ("unknown parameter", { $0["parameters"] = ["not-in-manifest": 1] }),
            ("out-of-range parameter", { $0["parameters"] = ["amplitude": 3] }),
            ("missing field", { $0.removeValue(forKey: "tracks") }),
            ("unknown track field", {
                var tracks = $0["tracks"] as! [[String: Any]]
                tracks[0]["unexpected"] = true
                $0["tracks"] = tracks
            }),
            ("unknown keyframe field", {
                var tracks = $0["tracks"] as! [[String: Any]]
                var keys = tracks[0]["keyframes"] as! [[String: Any]]
                keys[0]["unexpected"] = true
                tracks[0]["keyframes"] = keys
                $0["tracks"] = tracks
            })
        ]
        for (label, edit) in mutations {
            let data = try editingJSON(encoded, edit)
            XCTAssertThrowsError(try store.importPreset(data), label)
            XCTAssertEqual(store.presets, [original.effect.rawValue: original], label)
            XCTAssertEqual(defaults.data(forKey: presetKey), saved, label)
            XCTAssertEqual(CatalogStore(defaults: defaults).preset(original.effect), original, label)
        }
        for malformed in [Data(), Data("{".utf8), Data("[]".utf8)] {
            XCTAssertThrowsError(try store.importPreset(malformed))
            XCTAssertEqual(defaults.data(forKey: presetKey), saved)
        }
    }

    @MainActor
    func testSaveRejectsInvalidSchemaWithoutReplacingPreviousPreset() async throws {
        let defaults = try isolatedDefaults()
        let store = CatalogStore(defaults: defaults)
        let original = try trackedPreset()
        try store.save(original)
        let saved = defaults.data(forKey: presetKey)
        var invalid = original
        invalid.schemaVersion += 1
        XCTAssertThrowsError(try store.save(invalid)) { error in
            XCTAssertEqual(error as? AnimationValidationError, .unsupportedVersion(invalid.schemaVersion))
        }
        XCTAssertEqual(store.preset(original.effect), original)
        XCTAssertEqual(defaults.data(forKey: presetKey), saved)
    }

    @MainActor
    func testMalformedPersistedPresetDataReportsErrorWithoutOverwritingIt() async throws {
        for data in [Data(), Data("{".utf8), Data("{}".utf8)] {
            let defaults = try isolatedDefaults()
            defaults.set(data, forKey: presetKey)
            let store = CatalogStore(defaults: defaults)
            XCTAssertFalse(try XCTUnwrap(store.errorMessage).isEmpty)
            XCTAssertTrue(store.presets.isEmpty)
            XCTAssertNil(store.assigned(to: .close))
            XCTAssertEqual(defaults.data(forKey: presetKey), data)
        }
    }

    @MainActor
    func testPersistedUnsupportedPresetSchemaReportsExactValidationError() async throws {
        let defaults = try isolatedDefaults()
        let version = EffectPreset.currentSchemaVersion + 1
        let invalid = try editingJSON(trackedPreset().encoded()) { $0["schemaVersion"] = version }
        let array = Data("[".utf8) + invalid + Data("]".utf8)
        defaults.set(array, forKey: presetKey)
        let store = CatalogStore(defaults: defaults)
        XCTAssertEqual(store.errorMessage, AnimationValidationError.unsupportedVersion(version).localizedDescription)
        XCTAssertTrue(store.presets.isEmpty)
        XCTAssertEqual(defaults.data(forKey: presetKey), array)
    }

    @MainActor
    func testPersistedDuplicateEffectsAreRejectedInsteadOfChoosingAnOwner() async throws {
        let defaults = try isolatedDefaults()
        let original = try trackedPreset()
        var duplicate = original
        duplicate.name = "Subtle"
        let data = try JSONEncoder().encode([original, duplicate])
        defaults.set(data, forKey: presetKey)
        let store = CatalogStore(defaults: defaults)
        XCTAssertTrue(store.presets.isEmpty)
        XCTAssertEqual(store.errorMessage, AnimationValidationError.invalidValue(
            path: "presets", reason: "duplicate or excessive effects").localizedDescription)
        XCTAssertEqual(defaults.data(forKey: presetKey), data)
    }

    @MainActor
    func testPersistedDuplicateAutomaticTriggerOwnersAreRejected() async throws {
        let defaults = try isolatedDefaults()
        var first = try trackedPreset(.fold)
        var second = try trackedPreset(.flip)
        first.trigger = .close
        second.trigger = .close
        defaults.set(try JSONEncoder().encode([first, second]), forKey: presetKey)
        let store = CatalogStore(defaults: defaults)
        XCTAssertTrue(store.presets.isEmpty)
        XCTAssertNil(store.assigned(to: .close))
        XCTAssertEqual(store.errorMessage, AnimationValidationError.invalidValue(
            path: "triggers", reason: "multiple owners").localizedDescription)
    }

    @MainActor
    func testAssigningSameTriggerMakesOldOwnerManualWithoutLosingItsTracks() async throws {
        for trigger in EffectTrigger.allCases where trigger != .manual {
            let descriptors = EffectCatalog.effects.filter { $0.triggers.contains(trigger) }
            XCTAssertGreaterThanOrEqual(descriptors.count, 2)
            let defaults = try isolatedDefaults()
            let store = CatalogStore(defaults: defaults)
            var old = try trackedPreset(descriptors[0].id)
            var new = try trackedPreset(descriptors[1].id)
            old.trigger = trigger
            new.trigger = trigger
            try store.save(old)
            XCTAssertEqual(store.assigned(to: trigger), old)
            try store.importPreset(new.encoded())
            old.trigger = .manual
            XCTAssertEqual(store.preset(old.effect), old)
            XCTAssertEqual(store.assigned(to: trigger), new)
            XCTAssertNil(store.assigned(to: .manual))
            let restored = CatalogStore(defaults: defaults)
            XCTAssertEqual(restored.preset(old.effect), old)
            XCTAssertEqual(restored.assigned(to: trigger), new)
            XCTAssertEqual(restored.presets.values.filter { $0.trigger == trigger }.count, 1)
            XCTAssertNil(restored.errorMessage)
        }
    }

    @MainActor
    func testChangingAssignmentReleasesOldTriggerAndManualPresetsCoexist() async throws {
        let defaults = try isolatedDefaults()
        let store = CatalogStore(defaults: defaults)
        var preset = try trackedPreset(.fold)
        preset.trigger = .close
        try store.save(preset)
        preset.trigger = .open
        try store.save(preset)
        XCTAssertNil(store.assigned(to: .close))
        XCTAssertEqual(store.assigned(to: .open), preset)
        preset.trigger = .manual
        try store.save(preset)
        let other = try trackedPreset(.flip)
        try store.save(other)
        let restored = CatalogStore(defaults: defaults)
        XCTAssertEqual(restored.presets.count, 2)
        XCTAssertEqual(restored.preset(preset.effect), preset)
        XCTAssertEqual(restored.preset(other.effect), other)
        for trigger in EffectTrigger.allCases { XCTAssertNil(restored.assigned(to: trigger)) }
    }

    @MainActor
    func testSavedDocumentRetainsLayersTracksKeyframesAndDisabledStateAfterReload() async throws {
        let defaults = try isolatedDefaults()
        let store = CatalogStore(defaults: defaults)
        let first = StudioLayer(preset: try trackedPreset(.fold), start: 0.25)
        var second = StudioLayer(preset: try trackedPreset(.flip), start: 2)
        second.enabled = false
        let document = StudioDocument(name: "Layered window transitions", duration: 5, layers: [first, second])
        store.document = document
        try store.saveDocument()
        let bytes = try XCTUnwrap(defaults.data(forKey: documentKey))
        XCTAssertEqual(try StudioDocument.decode(bytes), document)
        let restored = CatalogStore(defaults: defaults)
        XCTAssertEqual(restored.document, document)
        XCTAssertNil(restored.errorMessage)
        XCTAssertFalse(restored.document.layers[1].enabled)
        XCTAssertEqual(restored.document.layers.flatMap { $0.preset.tracks }.count, 4)
        try restored.saveDocument()
        XCTAssertEqual(defaults.data(forKey: documentKey), bytes)
        XCTAssertTrue(restored.presets.isEmpty, "Studio layers must not become automatic assignments")
    }

    @MainActor
    func testInvalidDocumentSaveLeavesPreviousDocumentOnDisk() async throws {
        let defaults = try isolatedDefaults()
        let store = CatalogStore(defaults: defaults)
        let valid = StudioDocument(layers: [StudioLayer(preset: try trackedPreset())])
        store.document = valid
        try store.saveDocument()
        let bytes = defaults.data(forKey: documentKey)
        store.document.layers[0].preset.schemaVersion += 1
        XCTAssertThrowsError(try store.saveDocument())
        XCTAssertEqual(defaults.data(forKey: documentKey), bytes)
        XCTAssertEqual(CatalogStore(defaults: defaults).document, valid)
    }

    @MainActor
    func testMalformedAndUnsupportedDocumentsReportErrorWithoutLosingSavedPresets() async throws {
        let document = StudioDocument(layers: [StudioLayer(preset: try trackedPreset())])
        let unsupported = try editingJSON(document.encoded()) {
            $0["schemaVersion"] = StudioDocument.currentSchemaVersion + 1
        }
        let unknown = try editingJSON(document.encoded()) { $0["unexpected"] = true }
        for bytes in [Data("{".utf8), unsupported, unknown] {
            let defaults = try isolatedDefaults()
            let original = try trackedPreset()
            try CatalogStore(defaults: defaults).save(original)
            defaults.set(bytes, forKey: documentKey)
            let restored = CatalogStore(defaults: defaults)
            XCTAssertFalse(try XCTUnwrap(restored.errorMessage).isEmpty)
            XCTAssertEqual(restored.preset(original.effect), original)
            XCTAssertEqual(restored.document, StudioDocument())
            XCTAssertEqual(defaults.data(forKey: documentKey), bytes)
            if bytes == unsupported {
                XCTAssertEqual(restored.errorMessage, AnimationValidationError.unsupportedVersion(
                    StudioDocument.currentSchemaVersion + 1).localizedDescription)
            }
        }
    }

    @MainActor
    func testResetOneEffectPreservesOtherAssignmentsDocumentAndLegacyPreferences() async throws {
        let defaults = try isolatedDefaults()
        defaults.set("liquid", forKey: "closeEffect")
        let store = CatalogStore(defaults: defaults)
        var first = try trackedPreset(.fold)
        var second = try trackedPreset(.genie)
        first.trigger = .close
        second.trigger = .minimize
        try store.save(first)
        try store.save(second)
        let document = StudioDocument(layers: [StudioLayer(preset: first)])
        store.document = document
        try store.saveDocument()
        let documentBytes = defaults.data(forKey: documentKey)
        store.reset(first.effect)
        store.reset(.orbit) // Resetting an unsaved effect is harmless.
        let restored = CatalogStore(defaults: defaults)
        XCTAssertEqual(restored.presets, [second.effect.rawValue: second])
        XCTAssertEqual(restored.preset(first.effect), EffectCatalog.descriptor(first.effect).defaultPreset)
        XCTAssertNil(restored.assigned(to: .close))
        XCTAssertEqual(restored.assigned(to: .minimize), second)
        XCTAssertEqual(restored.document, document)
        XCTAssertEqual(defaults.data(forKey: documentKey), documentBytes)
        XCTAssertEqual(defaults.string(forKey: "closeEffect"), "liquid")
        XCTAssertNil(restored.errorMessage)
    }

    @MainActor
    func testResetAllRemovesOnlyCatalogKeysAndClearsErrorAndUnsavedDocument() async throws {
        let defaults = try isolatedDefaults()
        defaults.set("liquid", forKey: "closeEffect")
        defaults.set(RenderQuality.ultra.rawValue, forKey: "renderQuality")
        defaults.set(["com.apple.TextEdit"], forKey: "excludedApps")
        let unrelated = defaults.dictionaryRepresentation() as NSDictionary
        let initial = CatalogStore(defaults: defaults)
        try initial.save(trackedPreset())
        initial.document = StudioDocument(layers: [StudioLayer(preset: try trackedPreset())])
        try initial.saveDocument()
        defaults.set(Data("{".utf8), forKey: documentKey)
        let store = CatalogStore(defaults: defaults)
        XCTAssertNotNil(store.errorMessage)
        store.document = initial.document
        store.resetAll()
        store.resetAll()
        XCTAssertTrue(store.presets.isEmpty)
        XCTAssertEqual(store.document, StudioDocument())
        XCTAssertNil(store.errorMessage)
        XCTAssertNil(defaults.object(forKey: presetKey))
        XCTAssertNil(defaults.object(forKey: documentKey))
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, unrelated)
        let restored = CatalogStore(defaults: defaults)
        XCTAssertTrue(restored.presets.isEmpty)
        XCTAssertEqual(restored.document, StudioDocument())
        for trigger in EffectTrigger.allCases { XCTAssertNil(restored.assigned(to: trigger)) }
    }

    @MainActor
    func testSuccessfulSaveClearsLoadErrorWithoutTouchingOtherDomains() async throws {
        let defaults = try isolatedDefaults()
        let other = try isolatedDefaults()
        let otherStore = CatalogStore(defaults: other)
        let otherPreset = try trackedPreset(.flip)
        try otherStore.save(otherPreset)
        let otherBytes = other.data(forKey: presetKey)
        defaults.set(Data("{".utf8), forKey: presetKey)
        let store = CatalogStore(defaults: defaults)
        XCTAssertNotNil(store.errorMessage)
        let preset = try trackedPreset()
        try store.save(preset)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(CatalogStore(defaults: defaults).preset(preset.effect), preset)
        store.resetAll()
        XCTAssertEqual(other.data(forKey: presetKey), otherBytes)
        XCTAssertEqual(CatalogStore(defaults: other).preset(otherPreset.effect), otherPreset)
    }
}