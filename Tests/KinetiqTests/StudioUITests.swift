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
    func testNativeCatalogMenusMatchEveryRealCategoryGroupAndEffect() async throws {
        _ = NSApplication.shared
        let delegate = AppDelegate()
        let menu = NSMenu(title: "Catalog UI test")
        let presets = CatalogStore.shared.presets
        let document = CatalogStore.shared.document
        let defaultsBefore = UserDefaults.standard.dictionaryRepresentation() as NSDictionary
        XCTAssertFalse(CatalogRuntime.shared.isPlaying)
        delegate.menuNeedsUpdate(menu)
        var identifiers: [String] = []
        let categories = menu.items.filter { item in EffectCategory.allCases.contains { $0.title == item.title } }
        XCTAssertEqual(categories.map(\.title), EffectCategory.allCases.map(\.title))
        XCTAssertEqual(categories.count, 6)
        for (category, item) in zip(EffectCategory.allCases, categories) {
            let effects = LibraryEffect.all.filter { $0.category == category }
            let groups = try XCTUnwrap(item.submenu).items
            XCTAssertEqual(groups.map(\.title), Array(Set(effects.map(\.submenu))).sorted())
            for group in groups {
                let expected = effects.filter { $0.submenu == group.title }
                let entries = try XCTUnwrap(group.submenu).items
                XCTAssertEqual(entries.map(\.title), expected.map(\.menuTitle))
                XCTAssertEqual(entries.count, expected.count)
                for (entry, effect) in zip(entries, expected) {
                    XCTAssertTrue(entry.target === delegate)
                    switch effect {
                    case .catalog(let id):
                        XCTAssertEqual(entry.action, NSSelectorFromString("runCatalogEffect:"))
                        XCTAssertEqual(entry.representedObject as? String, id.rawValue)
                    default:
                        XCTAssertEqual(entry.action, NSSelectorFromString("configureOriginalEffect:"))
                        XCTAssertEqual(entry.representedObject as? String, effect.id)
                    }
                    XCTAssertTrue(delegate.responds(to: try XCTUnwrap(entry.action)))
                    identifiers.append(effect.id)
                }
            }
        }
        XCTAssertEqual(identifiers.count, 65)
        XCTAssertEqual(Set(identifiers), Set(LibraryEffect.all.map(\.id)))
        XCTAssertEqual(CatalogStore.shared.presets, presets)
        XCTAssertEqual(CatalogStore.shared.document, document)
        XCTAssertEqual(UserDefaults.standard.dictionaryRepresentation() as NSDictionary, defaultsBefore)
        XCTAssertFalse(CatalogRuntime.shared.isPlaying)
    }

    @MainActor
    func testNativeQualityAndStudioActionsAreConnectedWithoutExecutingThem() async throws {
        _ = NSApplication.shared
        let delegate = AppDelegate()
        let menu = NSMenu(title: "Quality UI test")
        let selection = RenderQualityManager.shared.selection
        let defaultsBefore = UserDefaults.standard.dictionaryRepresentation() as NSDictionary
        delegate.menuNeedsUpdate(menu)
        let quality = try XCTUnwrap(menu.item(withTitle: "Render Quality")?.submenu)
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
        XCTAssertEqual(RenderQualityManager.shared.selection, selection)
        XCTAssertEqual(UserDefaults.standard.dictionaryRepresentation() as NSDictionary, defaultsBefore)
        XCTAssertFalse(CatalogRuntime.shared.isPlaying)
    }

    @MainActor
    func testNativeNavigationOrderAndSixLibraryCategories() async {
        XCTAssertEqual(ManagementPage.allCases.map(\.title), [
            "Overview", "Windows", "Effects", "Animation Studio", "Physics", "Layouts",
            "Workspaces", "Rules", "Performance", "Diagnostics", "Settings", "Screen Saver"
        ])
        XCTAssertEqual(EffectDetailTab.allCases.map(\.rawValue), ["Preview", "Parameters", "Triggers", "Performance", "Reset"])
        XCTAssertEqual(EffectCategory.allCases.count, 6)
        XCTAssertEqual(EffectCatalog.effects.count, 19)
        XCTAssertEqual(EffectCategory.allCases.map { category in
            EffectCatalog.effects.filter { $0.category == category }.count
        }, [2, 4, 4, 4, 2, 3])
        XCTAssertEqual(LibraryEffect.all.count, 65)
        XCTAssertEqual(EffectCategory.allCases.map { category in
            LibraryEffect.all.filter { $0.category == category }.count
        }, [5, 31, 14, 10, 2, 3])
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