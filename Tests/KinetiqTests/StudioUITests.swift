// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import KinetiqCore
import XCTest
@testable import Kinetiq

/// Real catalog presets and the production editor/evaluator, without desktop mutations or mocks.
final class StudioUITests: XCTestCase {
    /// Builds only a disposable native menu: never launches the delegate or invokes desktop actions.
    @MainActor
    func testNativeTriggerMenusListEveryCompatibleEffectAndTheirCurrentChoice() async throws {
        _ = NSApplication.shared
        let delegate = AppDelegate()
        let menu = NSMenu(title: "Trigger UI test")
        let presets = CatalogStore.shared.presets
        let document = CatalogStore.shared.document
        let defaultsBefore = UserDefaults.standard.dictionaryRepresentation() as NSDictionary
        XCTAssertFalse(CatalogRuntime.shared.isPlaying)
        delegate.menuNeedsUpdate(menu)
        let settings = Settings()
        var tokens: [String] = []
        for trigger in [EffectTrigger.drag, .open, .close, .minimize] {
            let assignment = TriggerAssignment.current(trigger, settings: settings, store: .shared)
            let item = try XCTUnwrap(menu.items.first { $0.title.hasPrefix("\(trigger.shortTitle): ") }, trigger.rawValue)
            XCTAssertEqual(item.title, "\(trigger.shortTitle): \(assignment.title)")
            let submenu = try XCTUnwrap(item.submenu)
            // Built-ins first, then Studio presets under their own header.
            let supporting = LibraryEffect.supporting(trigger)
            let expected = supporting.filter { !$0.isStudio } + supporting.filter(\.isStudio)
            let entries = submenu.items.filter {
                $0.action == NSSelectorFromString("assignEffect:")
                    && !(($0.representedObject as? String)?.hasPrefix(LibraryItem.customPrefix) ?? false)
            }
            XCTAssertEqual(entries.map(\.title), expected.map(\.title), trigger.rawValue)
            for (entry, effect) in zip(entries, expected) {
                XCTAssertTrue(entry.target === delegate)
                XCTAssertEqual(entry.representedObject as? String, AppDelegate.menuToken(effect, trigger))
                XCTAssertEqual(entry.state, assignment == .effect(effect) ? .on : .off, effect.id)
                XCTAssertTrue(delegate.responds(to: try XCTUnwrap(entry.action)))
                let parsed = try XCTUnwrap(AppDelegate.parseToken(try XCTUnwrap(entry.representedObject as? String)))
                XCTAssertEqual(parsed.0, effect)
                XCTAssertEqual(parsed.1, trigger)
                tokens.append(entry.representedObject as! String)
            }
            let choices = submenu.items.filter { $0.action == NSSelectorFromString("setTriggerChoice:") }
            if trigger == .drag {
                XCTAssertEqual(choices.map(\.title), [TriggerAssignment.classicWobble.title])
                let presetItems = submenu.items.filter { $0.action == NSSelectorFromString("selectWobblePreset:") }
                XCTAssertEqual(presetItems.filter { $0.state == .on }.count, 1)
            } else {
                XCTAssertEqual(choices.map(\.title), ["Off", "Random"])
                XCTAssertEqual(choices.map { $0.representedObject as? String }, ["off|\(trigger.rawValue)", "random|\(trigger.rawValue)"])
            }
            // Exactly one choice is checked per trigger, counting Off/Random/classic and effects.
            XCTAssertEqual((entries + choices).filter { $0.state == .on }.count, 1, trigger.rawValue)
        }
        XCTAssertEqual(Set(tokens).count, tokens.count)
        // Every effect with an automatic trigger is reachable from at least one trigger menu.
        let reachable = Set(tokens.compactMap { AppDelegate.parseToken($0)?.0 })
        XCTAssertEqual(reachable, Set(LibraryEffect.all.filter { !$0.automaticTriggers.filter { [.drag, .open, .close, .minimize].contains($0) }.isEmpty }))
        let tryMenu = try XCTUnwrap(menu.item(withTitle: "Try an Effect on the Front Window")?.submenu)
        func flatten(_ menu: NSMenu) -> [NSMenuItem] { menu.items.flatMap { [$0] + ($0.submenu.map(flatten) ?? []) } }
        let tryItems = flatten(tryMenu)
        let studio = tryItems.filter { $0.action == NSSelectorFromString("runCatalogEffect:") }
        XCTAssertEqual(studio.map { $0.representedObject as? String }, EffectCategory.allCases.flatMap { category in
            EffectCatalog.effects.filter { $0.category == category }.map(\.id.rawValue)
        })
        let builtins = tryItems.filter { $0.action == NSSelectorFromString("runBuiltinEffect:") }
        XCTAssertEqual(builtins.compactMap { $0.representedObject as? String }, BuiltinLayer.all.map(\.effect.id))
        XCTAssertEqual(tryItems.filter { $0.action == NSSelectorFromString("runLiquid") }.count, 1)
        XCTAssertEqual(tryItems.filter { $0.action == NSSelectorFromString("runDestruction") }.count, 1)
        // Every library effect can be tried: 19 Studio + 45 layerable built-ins + Liquid + Window Destruction.
        XCTAssertEqual(studio.count + builtins.count + 2, LibraryEffect.all.count)
        for item in tryItems where item.action != nil && item.submenu == nil {
            XCTAssertTrue(item.target === delegate, item.title)
            XCTAssertTrue(delegate.responds(to: try XCTUnwrap(item.action)), item.title)
        }
        let arrange = try XCTUnwrap(menu.items.first { $0.title.hasPrefix("Arrange Windows") })
        XCTAssertEqual(arrange.action, NSSelectorFromString("showOverview"))
        XCTAssertNil(menu.items.first { EffectCategory.allCases.map(\.title).contains($0.title) }, "Abstract categories are no longer top-level")
        XCTAssertEqual(CatalogStore.shared.presets, presets)
        XCTAssertEqual(CatalogStore.shared.document, document)
        XCTAssertEqual(UserDefaults.standard.dictionaryRepresentation() as NSDictionary, defaultsBefore)
        XCTAssertFalse(CatalogRuntime.shared.isPlaying)
    }

    @MainActor
    func testTriggerAssignmentResolvesStoreOwnerBeforeOriginalSettingsIncludingDestruction() async throws {
        let suite = "io.github.invernomut0.Kinetiq.assignment.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = Settings(defaults: defaults)
        let store = CatalogStore(defaults: defaults)
        settings.closeEffect = .effect(.fire)
        XCTAssertEqual(TriggerAssignment.current(.close, settings: settings, store: store), .effect(.close(.fire)))
        settings.closeEffect = .destruction
        XCTAssertEqual(defaults.string(forKey: "closeEffect"), "destruction")
        XCTAssertEqual(TriggerAssignment.current(.close, settings: settings, store: store), .effect(.destruction))
        var fold = EffectPreset(effect: .fold); fold.trigger = .close
        try store.save(fold)
        XCTAssertEqual(TriggerAssignment.current(.close, settings: settings, store: store), .effect(.catalog(.fold)))
        try store.releaseAssignment(to: .close)
        XCTAssertEqual(TriggerAssignment.current(.close, settings: settings, store: store), .effect(.destruction))
        settings.closeEffect = .random
        XCTAssertEqual(TriggerAssignment.current(.close, settings: settings, store: store), .random)
        settings.minimizeEffect = .liquid
        XCTAssertEqual(TriggerAssignment.current(.minimize, settings: settings, store: store), .effect(.liquid))
        settings.openEffect = .off
        XCTAssertEqual(TriggerAssignment.current(.open, settings: settings, store: store), .off)
        XCTAssertEqual(TriggerAssignment.current(.drag, settings: settings, store: store), .classicWobble)
        for effect in LibraryEffect.all {
            XCTAssertEqual(Set(effect.automaticTriggers), Set(effect.triggers).subtracting([.manual]), effect.id)
            XCTAssertFalse(effect.blurb.isEmpty, effect.id)
            XCTAssertTrue(effect.triggers.contains(LibrarySelection.primary(effect).trigger), effect.id)
        }
        for trigger in EffectTrigger.librarySections {
            XCTAssertFalse(LibraryEffect.supporting(trigger).isEmpty, trigger.rawValue)
            XCTAssertFalse(trigger.eventTitle.isEmpty)
            XCTAssertNotNil(NSImage(systemSymbolName: trigger.symbol, accessibilityDescription: nil), trigger.rawValue)
        }
    }

    @MainActor
    func testNativeQualityAndStudioActionsAreConnectedWithoutExecutingThem() async throws {
        _ = NSApplication.shared
        let delegate = AppDelegate()
        let menu = NSMenu(title: "Quality UI test")
        let selection = RenderQualityManager.shared.selection
        let defaultsBefore = UserDefaults.standard.dictionaryRepresentation() as NSDictionary
        delegate.menuNeedsUpdate(menu)
        let quality = try XCTUnwrap(menu.items.first { $0.title.hasPrefix("Render Quality") }?.submenu)
        XCTAssertEqual(quality.items.count, 5)
        XCTAssertEqual(quality.items.map(\.title), RenderQuality.allCases.map(\.title))
        XCTAssertEqual(quality.items.compactMap { $0.representedObject as? String }, RenderQuality.allCases.map(\.rawValue))
        for (item, choice) in zip(quality.items, RenderQuality.allCases) {
            XCTAssertTrue(item.target === delegate)
            XCTAssertEqual(item.action, NSSelectorFromString("selectQuality:"))
            XCTAssertTrue(delegate.responds(to: try XCTUnwrap(item.action)))
            XCTAssertEqual(item.state, selection == choice ? .on : .off)
        }
        let studio = try XCTUnwrap(menu.item(withTitle: "Animation Studio…"))
        XCTAssertTrue(studio.target === delegate)
        XCTAssertEqual(studio.action, NSSelectorFromString("showStudio"))
        XCTAssertTrue(delegate.responds(to: try XCTUnwrap(studio.action)))
        let library = try XCTUnwrap(menu.item(withTitle: "Effects Library…"))
        XCTAssertEqual(library.action, NSSelectorFromString("showEffects"))
        XCTAssertTrue(delegate.responds(to: try XCTUnwrap(library.action)))
        XCTAssertNotNil(menu.item(withTitle: "Settings…"))
        XCTAssertEqual(RenderQualityManager.shared.selection, selection)
        XCTAssertEqual(UserDefaults.standard.dictionaryRepresentation() as NSDictionary, defaultsBefore)
        XCTAssertFalse(CatalogRuntime.shared.isPlaying)
    }

    @MainActor
    func testNativeNavigationOrderAnd66EffectsInSixLibraryCategories() async {
        XCTAssertEqual(ManagementPage.allCases.map(\.title), [
            "Overview", "Effects", "Animation Studio", "Physics", "Layouts", "Rules",
            "Screen Saver", "Performance", "Windows", "Diagnostics", "Settings"
        ])
        XCTAssertEqual(ManagementPage.primary + ManagementPage.system, ManagementPage.allCases)
        XCTAssertEqual(StudioInspectorTab.allCases.map(\.rawValue), ["Edit", "Keyframes", "Advanced"])
        XCTAssertEqual(EffectTrigger.librarySections, [.drag, .open, .close, .minimize, .overview])
        XCTAssertEqual(EffectCategory.allCases.count, 6)
        XCTAssertEqual(EffectCatalog.effects.count, 19)
        XCTAssertEqual(EffectCategory.allCases.map { category in
            EffectCatalog.effects.filter { $0.category == category }.count
        }, [2, 4, 4, 4, 2, 3])
        XCTAssertEqual(LibraryEffect.all.count, 66)
        XCTAssertEqual(EffectCategory.allCases.map { category in
            LibraryEffect.all.filter { $0.category == category }.count
        }, [5, 31, 15, 10, 2, 3])
    }

    @MainActor
    func testEveryLayerEditIsUndoableAndRedoable() async throws {
        let initial = StudioDocument()
        let editor = StudioEditorModel(document: initial)
        let id = try XCTUnwrap(editor.addLayer(EffectCatalog.descriptor(.wobbly).defaultPreset))
        let added = editor.document
        editor.updateLayer(id) { $0.enabled = false; $0.name = "Elastic Window"; $0.start = 2.5 }
        let changed = editor.document
        XCTAssertEqual(changed.duration, 3.5)
        XCTAssertFalse(try XCTUnwrap(changed.layers.first).enabled)
        editor.undo()
        XCTAssertEqual(editor.document, added)
        editor.undo()
        XCTAssertEqual(editor.document, initial)
        editor.redo()
        editor.redo()
        XCTAssertEqual(editor.document, changed)
        editor.removeLayer(id)
        XCTAssertTrue(editor.document.layers.isEmpty)
        editor.undo()
        XCTAssertEqual(editor.document, changed)
    }

    @MainActor
    func testHistoryIsBoundedAndNewEditsDiscardRedo() async {
        let editor = StudioEditorModel(document: StudioDocument())
        for index in 0..<150 { editor.perform { $0.name = "Composition \(index)" } }
        XCTAssertEqual(editor.undoCount, StudioEditorModel.historyLimit)
        editor.undo()
        XCTAssertEqual(editor.redoCount, 1)
        editor.perform { $0.name = "New Branch" }
        XCTAssertEqual(editor.redoCount, 0)
        let current = editor.document
        editor.redo()
        XCTAssertEqual(editor.document, current)
    }

    @MainActor
    func testInvalidEditIsAtomicAndDoesNotPolluteHistory() async throws {
        let editor = StudioEditorModel(document: StudioDocument())
        let id = try XCTUnwrap(editor.addLayer(EffectPreset(effect: .genie)))
        let before = editor.document
        let count = editor.undoCount
        editor.updateLayer(id) { $0.start = 60 }
        XCTAssertEqual(editor.document, before)
        XCTAssertEqual(editor.undoCount, count)
        XCTAssertNotNil(editor.errorMessage)
        XCTAssertFalse(editor.perform { $0.duration = .nan })
        XCTAssertEqual(editor.document, before)
        XCTAssertFalse(editor.perform { $0.duration = 0.1 })
        XCTAssertEqual(editor.document, before)
    }

    @MainActor
    func testTrackEditingUsesRealOutgoingCurveAndSupportsMoveDeleteAndMute() async throws {
        let editor = StudioEditorModel(document: StudioDocument())
        let id = try XCTUnwrap(editor.addLayer(EffectPreset(effect: .wobbly)))
        editor.addTrack(layer: id, parameter: "amplitude")
        editor.updateTrack(layer: id, parameter: "amplitude") {
            $0.keyframes[0].value = 0
            $0.keyframes[0].curve = .easeIn
            $0.keyframes[1].value = 2
        }
        var preset = try XCTUnwrap(editor.document.layers.first).preset
        XCTAssertEqual(preset.value("amplitude", at: 0.5), 0.5, accuracy: 0.000001)
        editor.addKeyframe(layer: id, parameter: "amplitude", time: 0.5)
        preset = try XCTUnwrap(editor.document.layers.first).preset
        XCTAssertEqual(preset.tracks[0].keyframes.count, 3)
        XCTAssertEqual(preset.tracks[0].keyframes[1].value, 0.5, accuracy: 0.000001)
        editor.updateTrack(layer: id, parameter: "amplitude") { $0.keyframes[1].time = 0.75 }
        XCTAssertEqual(editor.document.layers[0].preset.tracks[0].keyframes[1].time, 0.75)
        let beforeCollision = editor.document
        editor.updateTrack(layer: id, parameter: "amplitude") { $0.keyframes[1].time = 1 }
        XCTAssertEqual(editor.document, beforeCollision)
        XCTAssertNotNil(editor.errorMessage)
        editor.updateTrack(layer: id, parameter: "amplitude") { $0.keyframes.remove(at: 1); $0.muted = true }
        preset = try XCTUnwrap(editor.document.layers.first).preset
        XCTAssertEqual(preset.value("amplitude", at: 0.5), preset.parameters["amplitude"])
        editor.removeTrack(layer: id, parameter: "amplitude")
        XCTAssertTrue(editor.document.layers[0].preset.tracks.isEmpty)
        editor.undo()
        XCTAssertEqual(editor.document.layers[0].preset.tracks[0].keyframes.count, 2)
    }

    @MainActor
    func testDuplicateTracksAndKeysAreRejectedWithoutLosingDocument() async throws {
        let editor = StudioEditorModel(document: StudioDocument())
        let id = try XCTUnwrap(editor.addLayer(EffectPreset(effect: .ripple)))
        editor.addTrack(layer: id, parameter: "decay")
        let before = editor.document
        editor.addTrack(layer: id, parameter: "decay")
        XCTAssertEqual(editor.document, before)
        editor.addKeyframe(layer: id, parameter: "decay", time: 0)
        XCTAssertEqual(editor.document, before)
        XCTAssertNotNil(editor.errorMessage)
    }

    @MainActor
    func testStrictParameterPasteAcceptsOnlyMatchingValidatedPreset() async throws {
        var source = EffectPreset(effect: .portal)
        source.parameters["twist"] = -90
        source.name = "Portal Twist"
        var destination = EffectPreset(effect: .portal)
        destination.name = "Keep This Name"
        destination.duration = 2
        let pasted = try PresetClipboard.applying(source.encoded(), to: destination)
        XCTAssertEqual(pasted.parameters, source.parameters)
        XCTAssertEqual(pasted.name, destination.name)
        XCTAssertEqual(pasted.duration, destination.duration)
        XCTAssertThrowsError(try PresetClipboard.applying(source.encoded(), to: EffectPreset(effect: .fold)))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: source.encoded()) as? [String: Any])
        json["unexpected"] = true
        XCTAssertThrowsError(try PresetClipboard.applying(JSONSerialization.data(withJSONObject: json), to: destination))
    }

    @MainActor
    func testDocumentImportIsUndoableAndJSONRoundTripsAllEdits() async throws {
        let editor = StudioEditorModel(document: StudioDocument())
        let id = try XCTUnwrap(editor.addLayer(EffectPreset(effect: .liquidMorph), at: 0.5))
        editor.addTrack(layer: id, parameter: "viscosity")
        editor.updateTrack(layer: id, parameter: "viscosity") { $0.keyframes[0].curve = .spring }
        let encoded = try editor.document.encoded()
        let decoded = try StudioDocument.decode(encoded)
        XCTAssertEqual(decoded, editor.document)
        let original = editor.document
        editor.perform { $0 = StudioDocument(name: "Empty Composition") }
        editor.perform { $0 = decoded }
        XCTAssertEqual(editor.document, original)
        editor.undo()
        XCTAssertTrue(editor.document.layers.isEmpty)
        editor.redo()
        XCTAssertEqual(editor.document, original)
    }
}
/// Saved compositions ("My Effects") share single trigger ownership with catalog presets.
final class CustomEffectStoreTests: XCTestCase {
    @MainActor private func store() throws -> (CatalogStore, UserDefaults) {
        let suite = "io.github.invernomut0.Kinetiq.custom.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return (CatalogStore(defaults: defaults), defaults)
    }

    private func document(_ name: String) -> StudioDocument {
        let incinerate = StudioLayer(builtin: "close:incinerate", name: "Incinerate", duration: 2, start: 0.5)
        return StudioDocument(name: name, duration: 2.5, layers: [StudioLayer(preset: EffectPreset(effect: .ripple)), incinerate])
    }

    @MainActor func testCustomEffectsPersistAndOwnTriggersExclusivelyWithPresets() async throws {
        let (store, defaults) = try store()
        var fold = EffectPreset(effect: .fold); fold.trigger = .close
        try store.save(fold)
        XCTAssertEqual(store.assigned(to: .close)?.effect, .fold)
        let custom = CustomEffect(document: document("Burn Out"), trigger: .close)
        try store.saveCustom(custom)
        XCTAssertEqual(store.assignedCustom(to: .close)?.id, custom.id)
        XCTAssertNil(store.assigned(to: .close), "A custom owner releases the catalog owner")
        XCTAssertEqual(store.preset(.fold).trigger, .manual)
        XCTAssertEqual(store.preset(.fold).effect, .fold)

        try store.save(fold)
        XCTAssertNil(store.assignedCustom(to: .close), "A catalog owner releases the custom owner")
        XCTAssertEqual(store.customEffect(custom.id)?.trigger, .manual)

        var second = CustomEffect(document: document("Fade In"), trigger: .open)
        try store.saveCustom(second)
        second.document.name = "Fade In 2"
        try store.saveCustom(second)
        XCTAssertEqual(store.customEffects.count, 2)
        let reloaded = CatalogStore(defaults: defaults)
        XCTAssertNil(reloaded.errorMessage)
        XCTAssertEqual(reloaded.customEffects, store.customEffects)
        XCTAssertEqual(reloaded.assignedCustom(to: .open)?.name, "Fade In 2")
        XCTAssertEqual(reloaded.customEffects.first?.document.layers.last?.builtin, "close:incinerate")

        try reloaded.releaseAssignment(to: .open)
        XCTAssertNil(reloaded.assignedCustom(to: .open))
        XCTAssertNotNil(reloaded.customEffect(second.id), "Releasing keeps the effect")
        reloaded.deleteCustom(custom.id)
        XCTAssertNil(CatalogStore(defaults: defaults).customEffect(custom.id))

        let settings = Settings(defaults: defaults)
        try reloaded.saveCustom(CustomEffect(id: second.id, document: second.document, trigger: .minimize))
        XCTAssertEqual(TriggerAssignment.current(.minimize, settings: settings, store: reloaded), .custom(second.id, "Fade In 2"))
    }

    @MainActor func testInvalidCustomEffectsAreRejectedAtomically() async throws {
        let (store, _) = try store()
        XCTAssertThrowsError(try store.saveCustom(CustomEffect(document: StudioDocument(name: "Empty"))))
        XCTAssertThrowsError(try store.saveCustom(CustomEffect(document: document("Drag"), trigger: .drag)))
        var bad = document("Unknown")
        bad.layers[1].builtin = "close:"
        XCTAssertThrowsError(try store.saveCustom(CustomEffect(document: bad)))
        XCTAssertTrue(store.customEffects.isEmpty)
    }

    @MainActor func testMenuTokensRoundTripAndBuiltinLayersResolve() {
        for builtin in BuiltinLayer.all {
            XCTAssertEqual(BuiltinLayer(builtin.effect.id), builtin)
            let layer = builtin.makeLayer(start: 1)
            XCTAssertEqual(layer.builtin, builtin.effect.id)
            XCTAssertEqual(layer.name, builtin.effect.title)
            XCTAssertEqual(layer.start, 1)
            XCTAssertNoThrow(try StudioDocument(duration: layer.end, layers: [layer]).validated())
        }
        XCTAssertEqual(BuiltinLayer.all.count, 45)
        XCTAssertNil(BuiltinLayer("liquid"))
        XCTAssertNil(BuiltinLayer("catalog:fold"))
        XCTAssertTrue(LayerCompositor.needsCompositor(StudioDocument(duration: 2, layers: [BuiltinLayer.close(.fire).makeLayer()])))
        XCTAssertFalse(LayerCompositor.needsCompositor(StudioDocument(duration: 1, layers: [StudioLayer(preset: EffectPreset(effect: .fold))])))
    }
}

/// Overview geometry is pure: the desktop and the preview share it, and hit-testing reads it.
final class OverviewLayoutTests: XCTestCase {
    private let stage = CGRect(x: 60, y: 70, width: 1320, height: 760)
    private var homes: [CGRect] { OverviewLayout.sampleHomes(in: CGRect(x: 0, y: 0, width: 1440, height: 900), count: 5) }

    func testWindowsStartAtTheirRealFramesAndArriveInsideTheStage() {
        for effect in Settings.overviewLayouts {
            let preset = EffectPreset(effect: effect)
            var state = OverviewState(amount: 0, hover: Array(repeating: 0, count: homes.count))
            let start = OverviewLayout.place(effect: effect, preset: preset, homes: homes, stage: stage, state: state)
            XCTAssertEqual(start.placements.map(\.rect), homes, "\(effect)")
            XCTAssertTrue(start.placements.allSatisfy { $0.preset.value("amplitude", at: 0) == 0 }, "Flat while at home")
            state.amount = 1
            let arranged = OverviewLayout.place(effect: effect, preset: preset, homes: homes, stage: stage, state: state)
            XCTAssertEqual(Set(arranged.order), Set(homes.indices), "\(effect)")
            XCTAssertEqual(arranged.order.count, homes.count)
            for placement in arranged.placements {
                XCTAssertTrue(stage.insetBy(dx: -stage.width * 0.2, dy: -stage.height * 0.2).contains(placement.rect), "\(effect)")
                XCTAssertGreaterThan(placement.preset.value("amplitude", at: 0), 0)
            }
        }
    }

    func testHighlightedWindowIsDrawnLastAndLifted() {
        for effect in Settings.overviewLayouts {
            var state = OverviewState(amount: 1, focus: 2, hover: [0, 0, 1, 0, 0])
            let lifted = OverviewLayout.place(effect: effect, preset: EffectPreset(effect: effect), homes: homes, stage: stage, state: state)
            XCTAssertEqual(lifted.order.last, 2, "\(effect)")
            state.hover = Array(repeating: 0, count: 5)
            let plain = OverviewLayout.place(effect: effect, preset: EffectPreset(effect: effect), homes: homes, stage: stage, state: state)
            XCTAssertGreaterThan(lifted.placements[2].rect.width, plain.placements[2].rect.width, "\(effect)")
        }
        // Exposé straightens the highlighted window.
        let expose = OverviewLayout.place(effect: .expose3D, preset: EffectPreset(effect: .expose3D), homes: homes, stage: stage,
                                          state: OverviewState(amount: 1, hover: [1, 0, 0, 0, 0]))
        XCTAssertEqual(expose.placements[0].preset.value("angle", at: 0), 0, accuracy: 1e-9)
        XCTAssertGreaterThan(expose.placements[1].preset.value("angle", at: 0), 0)
    }

    func testCarouselTurnsSideWindowsAndOrbitSpinMovesWindows() {
        let cube = OverviewLayout.place(effect: .workspaceCube, preset: EffectPreset(effect: .workspaceCube), homes: homes,
                                        stage: stage, state: OverviewState(amount: 1, focus: 2, hover: []))
        XCTAssertEqual(cube.placements[2].preset.value("angle", at: 0), 0, accuracy: 1e-9)
        XCTAssertLessThan(cube.placements[0].rect.midX, cube.placements[2].rect.midX)
        XCTAssertGreaterThan(cube.placements[4].rect.midX, cube.placements[2].rect.midX)
        XCTAssertEqual(cube.order.last, 2)
        let a = OverviewLayout.place(effect: .orbit, preset: EffectPreset(effect: .orbit), homes: homes, stage: stage,
                                     state: OverviewState(amount: 1, spin: 0, hover: []))
        let b = OverviewLayout.place(effect: .orbit, preset: EffectPreset(effect: .orbit), homes: homes, stage: stage,
                                     state: OverviewState(amount: 1, spin: 1, hover: []))
        XCTAssertNotEqual(a.placements[0].rect, b.placements[0].rect)
        XCTAssertEqual(OverviewLayout.enter(0), 0, accuracy: 1e-9)
        XCTAssertEqual(OverviewLayout.enter(1), 1, accuracy: 1e-9)
        XCTAssertGreaterThan((0...20).map { OverviewLayout.enter(Double($0) / 20) }.max()!, 1, "Entering overshoots like a spring")
        XCTAssertEqual(OverviewLayout.leave(1), 1, accuracy: 1e-9)
    }
}
