// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import Combine
import Foundation
import KinetiqCore

/// Validated, versioned user documents. A trigger has at most one explicit owner;
/// built-in defaults are manual and never silently replace legacy preferences.
@MainActor
final class CatalogStore: ObservableObject {
    static let shared = CatalogStore()
    @Published private(set) var presets: [String: EffectPreset] = [:]
    @Published var document = StudioDocument()
    @Published private(set) var errorMessage: String?
    private let defaults: UserDefaults
    private static let presetKey = "catalogPresets.v1"
    private static let documentKey = "studioDocument.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        do {
            if let data = defaults.data(forKey: Self.presetKey) {
                guard data.count <= 32 * 1024 * 1024 else { throw AnimationValidationError.limitExceeded(path: "presets", maximum: 32 * 1024 * 1024) }
                let values = try JSONDecoder().decode([EffectPreset].self, from: data)
                guard values.count <= EffectID.allCases.count,
                      Set(values.map(\.effect)).count == values.count else {
                    throw AnimationValidationError.invalidValue(path: "presets", reason: "duplicate or excessive effects")
                }
                let automatic = values.filter { $0.trigger != .manual }
                guard Set(automatic.map(\.trigger)).count == automatic.count else {
                    throw AnimationValidationError.invalidValue(path: "triggers", reason: "multiple owners")
                }
                presets = Dictionary(uniqueKeysWithValues: values.map { ($0.effect.rawValue, $0) })
            }
            if let data = defaults.data(forKey: Self.documentKey) { document = try StudioDocument.decode(data) }
        } catch { errorMessage = error.localizedDescription }
    }

    func preset(_ id: EffectID) -> EffectPreset { presets[id.rawValue] ?? EffectPreset(effect: id) }

    /// Only persisted assignments participate in engine routing, never catalog defaults.
    func assigned(to trigger: EffectTrigger) -> EffectPreset? {
        guard trigger != .manual else { return nil }
        return EffectID.allCases.compactMap { presets[$0.rawValue] }.first { $0.trigger == trigger }
    }

    func save(_ preset: EffectPreset) throws {
        let preset = try preset.validated()
        var next = presets
        if preset.trigger != .manual {
            for key in Array(next.keys) where next[key]?.trigger == preset.trigger {
                next[key]?.trigger = .manual
            }
        }
        next[preset.effect.rawValue] = preset
        try persist(next)
    }

    func reset(_ id: EffectID) {
        do {
            var next = presets
            next[id.rawValue] = nil
            try persist(next)
        } catch { errorMessage = error.localizedDescription }
    }

    /// Releases only this action, retaining its preset, tracks and all other owners.
    func releaseAssignment(to trigger: EffectTrigger) throws {
        guard var owner = assigned(to: trigger) else { return }
        owner.trigger = .manual
        try save(owner)
    }

    func resetAll() {
        defaults.removeObject(forKey: Self.presetKey)
        defaults.removeObject(forKey: Self.documentKey)
        presets = [:]; document = StudioDocument(); errorMessage = nil
    }

    func saveDocument() throws {
        let data = try document.encoded()
        defaults.set(data, forKey: Self.documentKey)
        errorMessage = nil
    }

    func importPreset(_ data: Data) throws { try save(EffectPreset.decode(data)) }
    func exportPreset(_ id: EffectID) throws -> Data { try preset(id).encoded() }

    private func persist(_ next: [String: EffectPreset]) throws {
        let ordered = EffectID.allCases.compactMap { next[$0.rawValue] }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(ordered)
        defaults.set(data, forKey: Self.presetKey)
        presets = next; errorMessage = nil
    }
}