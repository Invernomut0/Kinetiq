// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import KinetiqCore
import KinetiqEffects

/// Discovery combines the original engines with the Studio catalog without changing
/// their persisted identifiers, renderer implementations or preset schemas.
enum LibraryEffect: Hashable, Identifiable {
    case catalog(EffectID)
    case close(CloseEffect)
    case entrance(WobbleEntrance)
    case minimize(DockMorphStyle)
    case liquid

    static let all: [LibraryEffect] = EffectID.allCases.map(Self.catalog)
        + CloseEffect.allCases.map(Self.close) + WobbleEntrance.allCases.map(Self.entrance)
        + DockMorphStyle.allCases.map(Self.minimize) + [.liquid]

    var id: String {
        switch self {
        case .catalog(let effect): return "catalog:" + effect.rawValue
        case .close(let effect): return "close:" + effect.rawValue
        case .entrance(let effect): return "open:" + effect.rawValue
        case .minimize(let effect): return "minimize:" + effect.rawValue
        case .liquid: return "liquid"
        }
    }

    static func find(_ id: String) -> LibraryEffect? { all.first { $0.id == id } }

    var title: String {
        switch self {
        case .catalog(let effect): return EffectCatalog.descriptor(effect).title
        case .close(let effect): return effect.title
        case .entrance(let effect): return effect.title
        case .minimize(let effect): return effect.title
        case .liquid: return "Liquid"
        }
    }

    var badge: String {
        switch self {
        case .catalog: return "Studio"
        case .close: return "Original Close"
        case .entrance: return "Original Open"
        case .minimize: return "Original Minimize"
        case .liquid: return "Original Close / Minimize"
        }
    }

    /// Menu originals configure their native trigger; catalog actions keep their manual Run behavior.
    var menuTitle: String {
        if case .catalog = self { return title }
        return "\(title) — \(badge)…"
    }

    var category: EffectCategory { placement.0 }
    var submenu: String { placement.1 }

    var triggers: [EffectTrigger] {
        switch self {
        case .catalog(let effect): return EffectCatalog.descriptor(effect).triggers
        case .close: return [.close]
        case .entrance: return [.open]
        case .minimize: return [.minimize]
        case .liquid: return [.close, .minimize]
        }
    }

    private var placement: (EffectCategory, String) {
        switch self {
        case .catalog(let effect):
            let descriptor = EffectCatalog.descriptor(effect)
            return (descriptor.category, descriptor.submenu)
        case .liquid: return (.transitions, "Fluid")
        case .minimize: return (.transitions, "Minimize / Restore")
        case .entrance(let entrance):
            switch entrance {
            case .wobblePop, .jellySquash, .quake: return (.windowMotion, "Elastic Entrances")
            case .ripple, .stoneInWater, .shockwave: return (.transitions, "Distortion")
            }
        case .close(let effect):
            switch effect {
            case .brokenGlass, .mushroom, .tRexAttack: return (.destruction, "Fragmentation")
            case .doom, .energizeA, .energizeB, .fire, .incinerate, .snapOfDisintegration, .wisps:
                return (.destruction, "Dissolution")
            case .auraGlow, .focus: return (.spatial, "Depth & Lighting")
            case .aperturePanels, .teamRocket: return (.spatial, "3D Transform")
            case .portal, .wormhole: return (.spatial, "Distortion")
            case .apparition, .glide, .materialize, .morph, .tvEffect: return (.transitions, "Transform")
            case .glitch, .rgbWarp, .tvGlitch: return (.transitions, "Distortion")
            case .hexagon, .matrix, .paintBrush, .pixelate, .pixelWheel, .pixelWipe:
                return (.transitions, "Pixel Transitions")
            }
        }
    }
}

/// Selecting an original reuses its real preferences. No duplicate legacy store or
/// automatic migration can overwrite an existing user's selection.
@MainActor
enum OriginalEffectAssignment {
    static func apply(_ effect: LibraryEffect, trigger: EffectTrigger,
                      settings: Settings, store: CatalogStore) throws {
        if case .catalog = effect {
            throw StudioUIError.message("Use Save & Apply for a Studio preset.")
        }
        guard effect.triggers.contains(trigger) else {
            throw StudioUIError.message("This original effect does not support \(trigger.title).")
        }
        try store.releaseAssignment(to: trigger)
        switch effect {
        case .close(let value): settings.closeEffect = .effect(value)
        case .entrance(let value): settings.openEffect = .wobble(value)
        case .minimize(let value): settings.minimizeEffect = .morph(value)
        case .liquid:
            if trigger == .close { settings.closeEffect = .liquid }
            else { settings.minimizeEffect = .liquid }
        case .catalog: break
        }
    }

    static func isSelected(_ effect: LibraryEffect, trigger: EffectTrigger,
                           settings: Settings, store: CatalogStore) -> Bool {
        guard store.assigned(to: trigger) == nil, effect.triggers.contains(trigger) else { return false }
        switch effect {
        case .close(let value): return settings.closeEffect == .effect(value)
        case .entrance(let value): return settings.openEffect == .wobble(value)
        case .minimize(let value): return settings.minimizeEffect == .morph(value)
        case .liquid: return trigger == .close ? settings.closeEffect == .liquid : settings.minimizeEffect == .liquid
        case .catalog: return false
        }
    }
}