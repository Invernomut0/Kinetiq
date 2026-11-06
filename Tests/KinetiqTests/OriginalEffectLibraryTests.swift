// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import Combine
import Foundation
import KinetiqCore
import KinetiqEffects
import XCTest
@testable import Kinetiq

/// Production preference domains and catalog presets; never invokes native actions or shared stores.
final class OriginalEffectLibraryTests: XCTestCase {
    private let presetKey = "catalogPresets.v1"

    private func isolatedDefaults() throws -> UserDefaults {
        let name = "io.github.invernomut0.Kinetiq.original.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    /// Build animated presets from the real catalog schema, including muted tracks and stable key IDs.
    @MainActor
    private func seed(_ store: CatalogStore) throws {
        let owners: [(EffectID, EffectTrigger)] = [
            (.fold, .close), (.genie, .minimize), (.morph, .open),
            (.wobbly, .drag), (.depthOfField, .overview), (.liquidMorph, .manual)
        ]
        for (effect, trigger) in owners {
            var preset = EffectPreset(effect: effect)
            preset.name = "Animated \(effect.rawValue)"
            preset.duration = 2.5
            preset.curve = .spring
            preset.trigger = trigger
            preset.parameters["amplitude"] = 1.25
            preset.tracks = EffectCatalog.descriptor(effect).parameters.prefix(2).enumerated().map { index, spec in
                AnimationTrack(parameter: spec.id, keyframes: [
                    AnimationKeyframe(time: 0, value: spec.minimum, curve: .linear),
                    AnimationKeyframe(time: 0.5, value: spec.defaultValue, curve: .spring),
                    AnimationKeyframe(time: 1, value: spec.maximum, curve: .easeOut)
                ], muted: index == 1)
            }
            try store.save(preset)
        }
        store.document = StudioDocument(name: "Original selection preserves Studio", duration: 3,
                                       layers: [StudioLayer(preset: store.preset(.fold))])
        try store.saveDocument()
    }

    func testEveryOriginalIncludingDestructionHasExactPlacementIdentityTitleAndTrigger() throws {
        let closeGroups: [(EffectCategory, String, [CloseEffect])] = [
            (.destruction, "Fragmentation", [.brokenGlass, .mushroom, .tRexAttack]),
            (.destruction, "Dissolution", [.doom, .energizeA, .energizeB, .fire, .incinerate, .snapOfDisintegration, .wisps]),
            (.spatial, "Depth & Lighting", [.auraGlow, .focus]),
            (.spatial, "3D Transform", [.aperturePanels, .teamRocket]),
            (.spatial, "Distortion", [.portal, .wormhole]),
            (.transitions, "Transform", [.apparition, .glide, .materialize, .morph, .tvEffect]),
            (.transitions, "Distortion", [.glitch, .rgbWarp, .tvGlitch]),
            (.transitions, "Pixel Transitions", [.hexagon, .matrix, .paintBrush, .pixelate, .pixelWheel, .pixelWipe])
        ]
        XCTAssertEqual(closeGroups.flatMap { $0.2 }.count, 30)
        XCTAssertEqual(Set(closeGroups.flatMap { $0.2 }), Set(CloseEffect.allCases))
        for (category, submenu, values) in closeGroups {
            for value in values {
                let effect = LibraryEffect.close(value)
                XCTAssertEqual(effect.id, "close:" + value.rawValue)
                XCTAssertEqual(effect.title, value.title)
                XCTAssertEqual(effect.category, category)
                XCTAssertEqual(effect.submenu, submenu)
                XCTAssertEqual(effect.triggers, [.close])
                XCTAssertEqual(effect.badge, "Original Close")
                XCTAssertEqual(effect.menuTitle, value.title + " — Original Close…")
            }
        }
        let entrances: [(WobbleEntrance, EffectCategory, String)] = [
            (.wobblePop, .windowMotion, "Elastic Entrances"),
            (.ripple, .transitions, "Distortion"),
            (.stoneInWater, .transitions, "Distortion"),
            (.shockwave, .transitions, "Distortion"),
            (.jellySquash, .windowMotion, "Elastic Entrances"),
            (.quake, .windowMotion, "Elastic Entrances")
        ]
        XCTAssertEqual(entrances.count, 6)
        XCTAssertEqual(Set(entrances.map { $0.0 }), Set(WobbleEntrance.allCases))
        for (value, category, submenu) in entrances {
            let effect = LibraryEffect.entrance(value)
            XCTAssertEqual(effect.id, "open:" + value.rawValue)
            XCTAssertEqual(effect.title, value.title)
            XCTAssertEqual(effect.category, category)
            XCTAssertEqual(effect.submenu, submenu)
            XCTAssertEqual(effect.triggers, [.open])
            XCTAssertEqual(effect.badge, "Original Open")
            XCTAssertEqual(effect.menuTitle, value.title + " — Original Open…")
        }
        XCTAssertEqual(DockMorphStyle.allCases.count, 9)
        for value in DockMorphStyle.allCases {
            let effect = LibraryEffect.minimize(value)
            XCTAssertEqual(effect.id, "minimize:" + value.rawValue)
            XCTAssertEqual(effect.title, value.title)
            XCTAssertEqual(effect.category, .transitions)
            XCTAssertEqual(effect.submenu, "Minimize / Restore")
            XCTAssertEqual(effect.triggers, [.minimize])
            XCTAssertEqual(effect.badge, "Original Minimize")
            XCTAssertEqual(effect.menuTitle, value.title + " — Original Minimize…")
        }
        let liquid = LibraryEffect.liquid
        XCTAssertEqual(liquid.id, "liquid")
        XCTAssertEqual(liquid.title, "Liquid")
        XCTAssertEqual(liquid.category, .transitions)
        XCTAssertEqual(liquid.submenu, "Fluid")
        XCTAssertEqual(liquid.triggers, [.close, .minimize])
        XCTAssertEqual(liquid.badge, "Original Close / Minimize")
        XCTAssertEqual(liquid.menuTitle, "Liquid — Original Close / Minimize…")
        let destruction = LibraryEffect.destruction
        XCTAssertEqual(destruction.id, "destruction")
        XCTAssertEqual(destruction.title, "Window Destruction")
        XCTAssertEqual(destruction.category, .destruction)
        XCTAssertEqual(destruction.submenu, "Fragmentation")
        XCTAssertEqual(destruction.triggers, [.close])
        XCTAssertEqual(destruction.badge, "Original Close")
        XCTAssertEqual(destruction.menuTitle, "Window Destruction — Original Close…")
    }

    func testAll66EffectsRemainUniqueInSixPermanentCategoriesAndCatalogMetadataIsUnchanged() {
        XCTAssertEqual(LibraryEffect.all, EffectID.allCases.map(LibraryEffect.catalog)
                       + CloseEffect.allCases.map(LibraryEffect.close)
                       + WobbleEntrance.allCases.map(LibraryEffect.entrance)
                       + DockMorphStyle.allCases.map(LibraryEffect.minimize) + [.liquid, .destruction])
        XCTAssertEqual(LibraryEffect.all.count, 66)
        XCTAssertEqual(Set(LibraryEffect.all).count, 66)
        XCTAssertEqual(Set(LibraryEffect.all.map(\.id)).count, 66)
        XCTAssertEqual(Set(LibraryEffect.all.map(\.menuTitle)).count, 66)
        XCTAssertEqual(EffectCategory.allCases, [.windowMotion, .transitions, .destruction, .spatial, .physics, .workspace])
        XCTAssertEqual(EffectCategory.allCases.map { category in
            LibraryEffect.all.filter { $0.category == category }.count
        }, [5, 31, 15, 10, 2, 3])
        for effect in LibraryEffect.all { XCTAssertEqual(LibraryEffect.find(effect.id), effect) }
        for id in ["", "genie", "morph", "portal", "ripple", "close:unknown", "catalog:liquid"] {
            XCTAssertNil(LibraryEffect.find(id), id)
        }
        for descriptor in EffectCatalog.effects {
            let effect = LibraryEffect.catalog(descriptor.id)
            XCTAssertEqual(effect.id, "catalog:" + descriptor.id.rawValue)
            XCTAssertEqual(effect.title, descriptor.title)
            XCTAssertEqual(effect.menuTitle, descriptor.title)
            XCTAssertEqual(effect.badge, "Studio")
            XCTAssertEqual(effect.category, descriptor.category)
            XCTAssertEqual(effect.submenu, descriptor.submenu)
            XCTAssertEqual(effect.triggers, descriptor.triggers)
        }
        let collisions: [[LibraryEffect]] = [
            [.catalog(.morph), .close(.morph), .minimize(.morph)],
            [.catalog(.genie), .minimize(.genie)],
            [.catalog(.portal), .close(.portal)],
            [.catalog(.ripple), .entrance(.ripple)],
            [.catalog(.liquidMorph), .liquid]
        ]
        for effects in collisions {
            XCTAssertEqual(Set(effects.map(\.id)).count, effects.count)
            XCTAssertEqual(Set(effects.map(\.menuTitle)).count, effects.count)
        }
    }

    @MainActor
    func testExistingAndDestructionRawPreferencesReloadWithoutMigrationOrCatalogWrites() async throws {
        let standardBefore = UserDefaults.standard.dictionaryRepresentation() as NSDictionary
        let defaults = try isolatedDefaults()
        XCTAssertEqual(CloseEffectChoice.destruction.rawValue, "destruction")
        XCTAssertEqual(CloseEffectChoice(rawValue: "destruction"), .destruction)
        let closeRaw = CloseEffect.allCases.map(\.rawValue) + ["off", "random", "liquid", "destruction"]
        let openRaw = WobbleEntrance.allCases.map { "wobble:" + $0.rawValue } + ["off", "random"]
        let minimizeRaw = DockMorphStyle.allCases.map { "morph:" + $0.rawValue } + ["off", "random", "liquid"]
        for (key, values) in [("closeEffect", closeRaw), ("openEffect", openRaw), ("minimizeEffect", minimizeRaw)] {
            for raw in values {
                defaults.set(raw, forKey: key)
                let before = defaults.dictionaryRepresentation() as NSDictionary
                let settings = Settings(defaults: defaults)
                let store = CatalogStore(defaults: defaults)
                XCTAssertEqual(settings.closeEffect.rawValue, defaults.string(forKey: "closeEffect") ?? "fire")
                XCTAssertEqual(settings.openEffect.rawValue, defaults.string(forKey: "openEffect") ?? "off")
                XCTAssertEqual(settings.minimizeEffect.rawValue, defaults.string(forKey: "minimizeEffect") ?? "off")
                XCTAssertTrue(store.presets.isEmpty)
                XCTAssertNil(store.errorMessage)
                XCTAssertNil(defaults.object(forKey: presetKey))
                XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
            }
        }
        XCTAssertEqual(UserDefaults.standard.dictionaryRepresentation() as NSDictionary, standardBefore)
    }

    @MainActor
    func testApplyingAll48OriginalTriggerChoicesIncludingDestructionPreservesUnrelatedDataAndRestoresEffectiveSelection() async throws {
        let standardBefore = UserDefaults.standard.dictionaryRepresentation() as NSDictionary
        var applications = 0
        for effect in LibraryEffect.all {
            if case .catalog = effect { continue }
            for trigger in effect.triggers {
                let defaults = try isolatedDefaults()
                let settings = Settings(defaults: defaults)
                settings.closeEffect = .random
                settings.openEffect = .random
                settings.minimizeEffect = .random
                settings.appCloseEffects = ["com.apple.TextEdit": "portal", "com.apple.Preview": "off"]
                settings.excludedApps = ["com.apple.finder", "io.github.invernomut0.Kinetiq"]
                settings.closeDuration = 1.75
                let store = CatalogStore(defaults: defaults)
                try seed(store)
                var expected = store.presets
                var released = try XCTUnwrap(store.assigned(to: trigger))
                released.trigger = .manual
                expected[released.effect.rawValue] = released
                XCTAssertFalse(OriginalEffectAssignment.isSelected(effect, trigger: trigger, settings: settings, store: store))
                let before = defaults.dictionaryRepresentation()
                try OriginalEffectAssignment.apply(effect, trigger: trigger, settings: settings, store: store)
                let key: String
                let raw: String
                switch effect {
                case .close(let value): key = "closeEffect"; raw = value.rawValue
                case .destruction: key = "closeEffect"; raw = "destruction"
                case .entrance(let value): key = "openEffect"; raw = "wobble:" + value.rawValue
                case .minimize(let value): key = "minimizeEffect"; raw = "morph:" + value.rawValue
                case .liquid: key = trigger == .close ? "closeEffect" : "minimizeEffect"; raw = "liquid"
                case .catalog: return XCTFail("Catalog must not be applied as an original")
                }
                var expectedDefaults = before
                expectedDefaults[key] = raw
                expectedDefaults[presetKey] = defaults.data(forKey: presetKey)
                XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, expectedDefaults as NSDictionary, effect.id)
                XCTAssertEqual(defaults.string(forKey: key), raw)
                XCTAssertEqual(store.presets, expected)
                XCTAssertNil(store.assigned(to: trigger))
                XCTAssertEqual(settings.appCloseEffects, ["com.apple.TextEdit": "portal", "com.apple.Preview": "off"])
                XCTAssertEqual(settings.excludedApps, ["com.apple.finder", "io.github.invernomut0.Kinetiq"])
                XCTAssertEqual(settings.closeEffect(forBundleID: "com.apple.TextEdit"), .effect(.portal))
                XCTAssertEqual(settings.closeEffect(forBundleID: "com.apple.Preview"), .off)
                let restoredSettings = Settings(defaults: defaults)
                let restored = CatalogStore(defaults: defaults)
                XCTAssertEqual(restored.presets, expected)
                XCTAssertEqual(restored.document, store.document)
                XCTAssertNil(restored.errorMessage)
                for candidate in LibraryEffect.all {
                    XCTAssertEqual(OriginalEffectAssignment.isSelected(candidate, trigger: trigger, settings: restoredSettings, store: restored),
                                   candidate == effect, "\(effect.id) / \(candidate.id)")
                }
                XCTAssertTrue(OriginalEffectAssignment.isSelected(effect, trigger: trigger, settings: settings, store: store))
                for other in EffectTrigger.allCases where other != trigger {
                    XCTAssertFalse(OriginalEffectAssignment.isSelected(effect, trigger: other, settings: settings, store: store))
                }
                released.trigger = trigger
                try restored.save(released)
                XCTAssertFalse(OriginalEffectAssignment.isSelected(effect, trigger: trigger, settings: restoredSettings, store: restored),
                               "An explicit catalog owner takes precedence over the same saved original choice")
                try restored.releaseAssignment(to: trigger)
                XCTAssertTrue(OriginalEffectAssignment.isSelected(effect, trigger: trigger, settings: restoredSettings, store: restored))
                applications += 1
            }
        }
        XCTAssertEqual(applications, 48)
        XCTAssertEqual(UserDefaults.standard.dictionaryRepresentation() as NSDictionary, standardBefore)
    }

    @MainActor
    func testUnsupportedTriggersAndEveryCatalogApplicationFailAtomically() async throws {
        let standardBefore = UserDefaults.standard.dictionaryRepresentation() as NSDictionary
        let defaults = try isolatedDefaults()
        let settings = Settings(defaults: defaults)
        settings.closeEffect = .liquid
        settings.openEffect = .wobble(.quake)
        settings.minimizeEffect = .morph(.hop)
        let store = CatalogStore(defaults: defaults)
        try seed(store)
        let before = defaults.dictionaryRepresentation() as NSDictionary
        let presets = store.presets
        let document = store.document
        for effect in LibraryEffect.all {
            for trigger in EffectTrigger.allCases {
                switch effect {
                case .catalog: break
                default:
                    if effect.triggers.contains(trigger) { continue }
                }
                XCTAssertThrowsError(try OriginalEffectAssignment.apply(effect, trigger: trigger, settings: settings, store: store),
                                     "\(effect.id) / \(trigger)")
                XCTAssertEqual(store.presets, presets)
                XCTAssertEqual(store.document, document)
                XCTAssertNil(store.errorMessage)
                XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
                XCTAssertFalse(OriginalEffectAssignment.isSelected(effect, trigger: trigger, settings: settings, store: store))
            }
        }
        XCTAssertEqual(CatalogStore(defaults: defaults).presets, presets)
        XCTAssertEqual(UserDefaults.standard.dictionaryRepresentation() as NSDictionary, standardBefore)
    }

    @MainActor
    func testReleaseEveryOwnerPreservesAllPresetDataAndOtherOwnersAfterReload() async throws {
        let standardBefore = UserDefaults.standard.dictionaryRepresentation() as NSDictionary
        for trigger in EffectTrigger.allCases where trigger != .manual {
            let defaults = try isolatedDefaults()
            let store = CatalogStore(defaults: defaults)
            try seed(store)
            var expected = store.presets
            var released = try XCTUnwrap(store.assigned(to: trigger))
            released.trigger = .manual
            expected[released.effect.rawValue] = released
            let documentBytes = defaults.data(forKey: "studioDocument.v1")
            try store.releaseAssignment(to: trigger)
            XCTAssertEqual(store.presets, expected)
            XCTAssertNil(store.assigned(to: trigger))
            let restored = CatalogStore(defaults: defaults)
            XCTAssertEqual(restored.presets, expected)
            XCTAssertEqual(restored.document, store.document)
            XCTAssertEqual(defaults.data(forKey: "studioDocument.v1"), documentBytes)
            XCTAssertNil(restored.errorMessage)
        }
        XCTAssertEqual(UserDefaults.standard.dictionaryRepresentation() as NSDictionary, standardBefore)
    }

    @MainActor
    func testReleaseWithoutOwnerDoesNotWriteOrPublishIncludingManualAndRepeatedRelease() async throws {
        let standardBefore = UserDefaults.standard.dictionaryRepresentation() as NSDictionary
        let defaults = try isolatedDefaults()
        let empty = CatalogStore(defaults: defaults)
        let emptyBefore = defaults.dictionaryRepresentation() as NSDictionary
        var publications = 0
        let emptyObservation = empty.$presets.dropFirst().sink { _ in publications += 1 }
        for trigger in EffectTrigger.allCases { try empty.releaseAssignment(to: trigger) }
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, emptyBefore)
        XCTAssertNil(defaults.object(forKey: presetKey))
        XCTAssertEqual(publications, 0)
        withExtendedLifetime(emptyObservation) { }

        try seed(empty)
        try empty.releaseAssignment(to: .close)
        // A noncanonical, valid encoding detects an accidental rewrite even if values are identical.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let reversedPresets = Array(EffectID.allCases.compactMap { empty.presets[$0.rawValue] }.reversed())
        defaults.set(try encoder.encode(reversedPresets), forKey: presetKey)
        let store = CatalogStore(defaults: defaults)
        let before = defaults.dictionaryRepresentation() as NSDictionary
        let presets = store.presets
        var writes = 0
        let observation = store.$presets.dropFirst().sink { _ in writes += 1 }
        try store.releaseAssignment(to: .close)
        try store.releaseAssignment(to: .manual)
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(store.presets, presets)
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
        XCTAssertEqual(CatalogStore(defaults: defaults).presets, presets)
        withExtendedLifetime(observation) { }
        XCTAssertEqual(UserDefaults.standard.dictionaryRepresentation() as NSDictionary, standardBefore)
    }
}