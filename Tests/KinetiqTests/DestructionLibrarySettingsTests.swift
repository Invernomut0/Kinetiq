// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import KinetiqCore
import KinetiqEffects
import XCTest
@testable import Kinetiq

/// Exercises the production settings and library adapters without touching shared preferences.
final class DestructionLibrarySettingsTests: XCTestCase {
    private func isolatedDefaults() throws -> UserDefaults {
        let name = "io.github.invernomut0.Kinetiq.destruction.library.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testDestructionRoundTripsWithoutChangingLegacyDefaultsOrShaderPool() throws {
        let defaults = try isolatedDefaults()
        let settings = Settings(defaults: defaults)
        XCTAssertEqual(settings.closeEffect, .effect(.fire))
        XCTAssertEqual(CloseEffectChoice(rawValue: nil), .effect(.fire))
        XCTAssertEqual(CloseEffectChoice(rawValue: "unknown"), .effect(.fire))
        for choice in [CloseEffectChoice.off, .random, .liquid, .destruction]
            + CloseEffect.allCases.map(CloseEffectChoice.effect) {
            XCTAssertEqual(CloseEffectChoice(rawValue: choice.rawValue), choice)
        }
        settings.closeEffect = .destruction
        XCTAssertEqual(defaults.string(forKey: "closeEffect"), "destruction")
        XCTAssertEqual(Settings(defaults: defaults).closeEffect, .destruction)
        XCTAssertEqual(settings.openEffect, .off)
        XCTAssertEqual(settings.minimizeEffect, .off)
        XCTAssertNil(CloseEffect(rawValue: "destruction"))
        XCTAssertEqual(CloseEffect.allCases.count, 30)
        var generator = SystemRandomNumberGenerator()
        XCTAssertNil(CloseEffectChoice.destruction.resolve(using: &generator))
        XCTAssertNotNil(CloseEffectChoice.random.resolve(using: &generator))
        settings.resetToDefaults()
        XCTAssertEqual(settings.closeEffect, .effect(.fire))
    }

    func testPerAppDestructionPersistsAndOverridesGlobalChoice() throws {
        let defaults = try isolatedDefaults()
        let settings = Settings(defaults: defaults)
        settings.closeEffect = .effect(.portal)
        settings.appCloseEffects = ["com.apple.TextEdit": "destruction", "com.apple.Preview": "off"]
        let restored = Settings(defaults: defaults)
        XCTAssertEqual(restored.closeEffect(forBundleID: "com.apple.TextEdit"), .destruction)
        XCTAssertEqual(restored.closeEffect(forBundleID: "com.apple.Preview"), .off)
        XCTAssertEqual(restored.closeEffect(forBundleID: "com.apple.finder"), .effect(.portal))
        XCTAssertEqual(restored.closeEffect(forBundleID: nil), .effect(.portal))
    }

    @MainActor
    func testDiscoveryAndMenuTokenExposeOnlyClose() {
        let effect = LibraryEffect.destruction
        XCTAssertEqual(effect.id, "destruction")
        XCTAssertEqual(LibraryEffect.find(effect.id), effect)
        XCTAssertEqual(effect.title, "Window Destruction")
        XCTAssertEqual(effect.kindLabel, "Built-in")
        XCTAssertFalse(effect.isStudio)
        XCTAssertEqual(effect.category, .destruction)
        XCTAssertEqual(effect.submenu, "Fragmentation")
        XCTAssertEqual(effect.triggers, [.close])
        XCTAssertEqual(effect.automaticTriggers, [.close])
        XCTAssertEqual(LibrarySelection.primary(effect).trigger, .close)
        XCTAssertEqual(LibraryEffect.all.filter { $0 == effect }.count, 1)
        XCTAssertEqual(LibraryEffect.all.count, 66)
        XCTAssertEqual(Set(LibraryEffect.all.map(\.id)).count, LibraryEffect.all.count)
        for trigger in EffectTrigger.allCases {
            XCTAssertEqual(LibraryEffect.supporting(trigger).contains(effect), trigger == .close)
        }
        let token = AppDelegate.menuToken(effect, .close)
        XCTAssertEqual(token, "destruction|close")
        XCTAssertEqual(AppDelegate.parseToken(token)?.0, effect)
        XCTAssertEqual(AppDelegate.parseToken(token)?.1, .close)
    }

    @MainActor
    func testAssignmentReleasesOnlyCloseOwnerAndRejectsOtherTriggersAtomically() throws {
        let defaults = try isolatedDefaults()
        let settings = Settings(defaults: defaults)
        let store = CatalogStore(defaults: defaults)
        var owner = EffectPreset(effect: .fold)
        owner.trigger = .close
        owner.duration = 2.5
        try store.save(owner)
        settings.appCloseEffects = ["com.apple.Preview": "off"]
        settings.openEffect = .wobble(.quake)
        settings.minimizeEffect = .liquid
        settings.closeDuration = 1.75
        let exclusions = settings.excludedApps
        XCTAssertFalse(OriginalEffectAssignment.isSelected(.destruction, trigger: .close, settings: settings, store: store))
        try OriginalEffectAssignment.apply(.destruction, trigger: .close, settings: settings, store: store)
        owner.trigger = .manual
        XCTAssertEqual(store.preset(.fold), owner)
        XCTAssertNil(store.assigned(to: .close))
        XCTAssertEqual(settings.closeEffect, .destruction)
        XCTAssertEqual(settings.openEffect, .wobble(.quake))
        XCTAssertEqual(settings.minimizeEffect, .liquid)
        XCTAssertEqual(settings.appCloseEffects, ["com.apple.Preview": "off"])
        XCTAssertEqual(settings.excludedApps, exclusions)
        XCTAssertEqual(settings.closeDuration, 1.75)
        let restored = Settings(defaults: defaults)
        let restoredStore = CatalogStore(defaults: defaults)
        XCTAssertEqual(TriggerAssignment.current(.close, settings: restored, store: restoredStore), .effect(.destruction))
        XCTAssertTrue(OriginalEffectAssignment.isSelected(.destruction, trigger: .close, settings: restored, store: restoredStore))
        let before = defaults.dictionaryRepresentation() as NSDictionary
        for trigger in EffectTrigger.allCases where trigger != .close {
            XCTAssertThrowsError(try OriginalEffectAssignment.apply(.destruction, trigger: trigger, settings: restored, store: restoredStore))
            XCTAssertFalse(OriginalEffectAssignment.isSelected(.destruction, trigger: trigger, settings: restored, store: restoredStore))
            XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
        }
        owner.trigger = .close
        try restoredStore.save(owner)
        XCTAssertEqual(TriggerAssignment.current(.close, settings: restored, store: restoredStore), .effect(.catalog(.fold)))
        XCTAssertFalse(OriginalEffectAssignment.isSelected(.destruction, trigger: .close, settings: restored, store: restoredStore))
    }
}