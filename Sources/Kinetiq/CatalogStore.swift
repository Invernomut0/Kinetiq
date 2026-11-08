// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import Combine
import Foundation
import KinetiqCore

/// A Studio composition the user saved under a name. It can own Open, Close or Minimize
/// like a catalog preset; `trigger` is `.manual` while it is not used by any event.
struct CustomEffect: Codable, Equatable, Identifiable, Sendable {
    static let maximumCount = 64
    static let assignableTriggers: [EffectTrigger] = [.open, .close, .minimize]

    var id: UUID
    var document: StudioDocument
    var trigger: EffectTrigger

    var name: String { document.name }

    init(id: UUID = UUID(), document: StudioDocument, trigger: EffectTrigger = .manual) {
        self.id = id
        self.document = document
        self.trigger = trigger
    }

    func validated() throws -> CustomEffect {
        _ = try document.validated()
        guard trigger == .manual || Self.assignableTriggers.contains(trigger) else {
            throw AnimationValidationError.invalidValue(path: "customEffect.trigger", reason: "must be manual, open, close or minimize")
        }
        guard !document.layers.filter(\.enabled).isEmpty else {
            throw AnimationValidationError.invalidValue(path: "customEffect.layers", reason: "needs at least one enabled layer")
        }
        return self
    }
}

/// Validated, versioned user documents. A trigger has at most one explicit owner, a catalog
/// preset or a custom effect; built-in defaults are manual and never silently replace legacy preferences.
@MainActor
final class CatalogStore: ObservableObject {
    static let shared = CatalogStore()
    @Published private(set) var presets: [String: EffectPreset] = [:]
    @Published private(set) var customEffects: [CustomEffect] = []
    @Published var document = StudioDocument()
    @Published private(set) var errorMessage: String?
    private let defaults: UserDefaults
    private static let presetKey = "catalogPresets.v1"
    private static let documentKey = "studioDocument.v1"
    private static let customKey = "customEffects.v1"

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
            if let data = defaults.data(forKey: Self.customKey) {
                guard data.count <= 32 * 1024 * 1024 else { throw AnimationValidationError.limitExceeded(path: "customEffects", maximum: 32 * 1024 * 1024) }
                let values = try JSONDecoder().decode([CustomEffect].self, from: data).map { try $0.validated() }
                guard values.count <= CustomEffect.maximumCount, Set(values.map(\.id)).count == values.count else {
                    throw AnimationValidationError.invalidValue(path: "customEffects", reason: "duplicate or excessive effects")
                }
                let owned = values.filter { $0.trigger != .manual }.map(\.trigger)
                    + presets.values.filter { $0.trigger != .manual }.map(\.trigger)
                guard Set(owned).count == owned.count else {
                    throw AnimationValidationError.invalidValue(path: "triggers", reason: "multiple owners")
                }
                customEffects = values
            }
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
        var customs = customEffects
        if preset.trigger != .manual {
            for key in Array(next.keys) where next[key]?.trigger == preset.trigger {
                next[key]?.trigger = .manual
            }
            for index in customs.indices where customs[index].trigger == preset.trigger { customs[index].trigger = .manual }
        }
        next[preset.effect.rawValue] = preset
        if customs != customEffects { try persistCustom(customs) }
        try persist(next)
    }

    // MARK: - Custom effects (saved Studio compositions)

    func customEffect(_ id: UUID) -> CustomEffect? { customEffects.first { $0.id == id } }

    func assignedCustom(to trigger: EffectTrigger) -> CustomEffect? {
        guard trigger != .manual else { return nil }
        return customEffects.first { $0.trigger == trigger }
    }

    /// Inserts or replaces by ID. An automatic trigger releases its previous owner, preset or custom.
    func saveCustom(_ effect: CustomEffect) throws {
        let effect = try effect.validated()
        var customs = customEffects
        var next = presets
        if effect.trigger != .manual {
            for index in customs.indices where customs[index].trigger == effect.trigger && customs[index].id != effect.id {
                customs[index].trigger = .manual
            }
            for key in Array(next.keys) where next[key]?.trigger == effect.trigger { next[key]?.trigger = .manual }
        }
        if let index = customs.firstIndex(where: { $0.id == effect.id }) { customs[index] = effect }
        else {
            guard customs.count < CustomEffect.maximumCount else {
                throw AnimationValidationError.limitExceeded(path: "customEffects", maximum: CustomEffect.maximumCount)
            }
            customs.append(effect)
        }
        if next != presets { try persist(next) }
        try persistCustom(customs)
    }

    func deleteCustom(_ id: UUID) {
        do { try persistCustom(customEffects.filter { $0.id != id }) }
        catch { errorMessage = error.localizedDescription }
    }

    private func persistCustom(_ next: [CustomEffect]) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(next)
        defaults.set(data, forKey: Self.customKey)
        customEffects = next; errorMessage = nil
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
        if var custom = assignedCustom(to: trigger) {
            custom.trigger = .manual
            try saveCustom(custom)
        }
        guard var owner = assigned(to: trigger) else { return }
        owner.trigger = .manual
        try save(owner)
    }

    func resetAll() {
        defaults.removeObject(forKey: Self.presetKey)
        defaults.removeObject(forKey: Self.documentKey)
        defaults.removeObject(forKey: Self.customKey)
        presets = [:]; customEffects = []; document = StudioDocument(); errorMessage = nil
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