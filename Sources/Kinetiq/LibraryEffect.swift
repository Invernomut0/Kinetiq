// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
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

    /// Effects that can be chosen for a trigger, in library order.
    static func supporting(_ trigger: EffectTrigger) -> [LibraryEffect] {
        all.filter { $0.triggers.contains(trigger) }
    }

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

    /// Short user-facing kind: whether the effect has an editable preset or fixed built-in behavior.
    var kindLabel: String {
        if case .catalog = self { return "Studio preset" }
        return "Built-in"
    }

    var isStudio: Bool {
        if case .catalog = self { return true }
        return false
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

    /// Triggers that fire automatically on a window event (everything except Manual).
    var automaticTriggers: [EffectTrigger] { triggers.filter { $0 != .manual } }

    /// Plain-language description of what the user will see.
    var blurb: String {
        switch self {
        case .catalog(let effect): return EffectCatalog.descriptor(effect).summary
        case .liquid:
            return "The window melts from the top-right corner, spills over its edges and pools behind the Dock before fading away."
        case .entrance(let entrance):
            switch entrance {
            case .wobblePop: return "The new window springs in with a jelly pop from its center and settles."
            case .ripple: return "A circular wave rolls out from the center of the new window."
            case .stoneInWater: return "Rings spread from where the window appears, like a stone dropped in water."
            case .shockwave: return "A pop and a fast wave sweep across the new window."
            case .jellySquash: return "The window squashes vertically and bounces back like jelly."
            case .quake: return "Alternate rows shake sideways and quickly settle."
            }
        case .minimize(let style):
            switch style {
            case .morph: return "The window shrinks and slides straight into its Dock icon."
            case .genie: return "The edge nearest the Dock leads and the rest follows, narrowing into a funnel."
            case .jellySuck: return "The Dock icon sucks the window in like jelly, rippling sideways on the way."
            case .whirlpool: return "The window spins down the drain, twisting around the icon as it shrinks."
            case .tornado: return "The whole window turns a full circle while it flies into the icon."
            case .rubberBand: return "The window stretches away from the icon like a rubber band, then snaps into it."
            case .pancake: return "The window is flattened first, then the pancake slides into the icon."
            case .accordion: return "Like Genie, but the window folds into zigzag bands on the way."
            case .hop: return "The window jumps in an arc and lands in its Dock icon."
            }
        case .close(let effect):
            switch effect {
            case .aperturePanels: return "The window splits into panels that slide apart like a camera aperture."
            case .apparition: return "The window turns to smoke and drifts away."
            case .auraGlow: return "A colored aura glows around the edges while the window fades."
            case .brokenGlass: return "The window shatters into glass shards that fall away."
            case .doom: return "The window melts downward column by column, like the classic Doom screen wipe."
            case .energizeA: return "A transporter beam dematerializes the window into sparkles."
            case .energizeB: return "Bright particles swarm the window and carry it away."
            case .fire: return "Flames burn the window away from the bottom up."
            case .focus: return "The window goes out of focus and fades."
            case .glide: return "The window glides a short distance and fades, quick and discreet."
            case .glitch: return "Digital glitch stripes tear the window apart."
            case .hexagon: return "The window dissolves through a glowing hexagonal grid."
            case .incinerate: return "A glowing ember line wanders across the window, leaving ash behind."
            case .materialize: return "The window fades through a grainy panel and vanishes."
            case .matrix: return "Green digital rain washes the window away."
            case .morph: return "The window stretches and shrinks into nothing."
            case .mushroom: return "An 8-bit power-up pop with pixel sparkles."
            case .paintBrush: return "Brush strokes paint the window out of existence."
            case .pixelate: return "The window breaks into large pixels that disappear."
            case .pixelWheel: return "Pixels vanish in a rotating wheel pattern."
            case .pixelWipe: return "A pixel wave wipes across the window from where you clicked."
            case .portal: return "The window is sucked into a swirling portal."
            case .rgbWarp: return "The color channels split and warp away."
            case .snapOfDisintegration: return "The window crumbles into dust that blows away."
            case .teamRocket: return "The window blasts off into the distance with a twinkle."
            case .tRexAttack: return "Claw marks tear the window into pieces."
            case .tvEffect: return "The picture collapses to a line, then a dot, like an old TV switching off."
            case .tvGlitch: return "Static and scanline glitches before the window vanishes."
            case .wisps: return "The window dissolves into glowing wisps that float away."
            case .wormhole: return "The window twists and stretches into a wormhole."
            }
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

/// User-facing wording for the window events an effect can react to.
extension EffectTrigger {
    /// Sidebar / menu heading, phrased as the user action.
    var eventTitle: String {
        switch self {
        case .drag: return "When you drag a window"
        case .open: return "When a window opens"
        case .close: return "When a window closes"
        case .minimize: return "When you minimize"
        case .overview: return "Overview & layouts"
        case .manual: return "Play manually"
        }
    }

    /// Short label for compact menus and buttons.
    var shortTitle: String {
        switch self {
        case .drag: return "Drag"
        case .open: return "Open"
        case .close: return "Close"
        case .minimize: return "Minimize"
        case .overview: return "Overview"
        case .manual: return "Manual"
        }
    }

    var symbol: String {
        switch self {
        case .drag: return "hand.draw"
        case .open: return "macwindow.badge.plus"
        case .close: return "xmark.circle"
        case .minimize: return "arrow.down.right.and.arrow.up.left"
        case .overview: return "rectangle.3.group"
        case .manual: return "play.circle"
        }
    }

    var explanation: String {
        switch self {
        case .drag: return "Plays while you move a window from its title bar or with the shortcut."
        case .open: return "Plays when an app shows a new standard window."
        case .close: return "Plays after a window really closes. Per-app rules can override the global choice."
        case .minimize: return "Plays when you click the yellow button. ⌘M stays native."
        case .overview: return "Arranges the windows of the current Space. Start it from the menu bar or with Run."
        case .manual: return "Not tied to any window event. Run it from the menu bar or the Effects library."
        }
    }

    /// Triggers that the Effects library lists as sections, in display order.
    static let librarySections: [EffectTrigger] = [.drag, .open, .close, .minimize, .overview]
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

/// What a trigger currently does, resolved across the catalog store and the original settings.
enum TriggerAssignment: Equatable {
    case off
    case random
    case effect(LibraryEffect)
    /// A saved Studio composition ("My Effects"), by ID and name.
    case custom(UUID, String)
    /// Drag always wobbles; the classic spring model is the default when no Studio preset owns it.
    case classicWobble

    @MainActor
    static func current(_ trigger: EffectTrigger, settings: Settings, store: CatalogStore) -> TriggerAssignment {
        if let custom = store.assignedCustom(to: trigger) { return .custom(custom.id, custom.name) }
        if let owner = store.assigned(to: trigger) { return .effect(.catalog(owner.effect)) }
        switch trigger {
        case .close:
            switch settings.closeEffect {
            case .off: return .off
            case .random: return .random
            case .liquid: return .effect(.liquid)
            case .effect(let value): return .effect(.close(value))
            }
        case .open:
            switch settings.openEffect {
            case .off: return .off
            case .random: return .random
            case .wobble(let value): return .effect(.entrance(value))
            }
        case .minimize:
            switch settings.minimizeEffect {
            case .off: return .off
            case .random: return .random
            case .liquid: return .effect(.liquid)
            case .morph(let value): return .effect(.minimize(value))
            }
        case .drag: return .classicWobble
        case .overview, .manual: return .off
        }
    }

    var title: String {
        switch self {
        case .off: return "Off"
        case .random: return "Random"
        case .effect(let effect): return effect.title
        case .custom(_, let name): return name
        case .classicWobble: return "Wobbly (classic)"
        }
    }

    var effect: LibraryEffect? {
        if case .effect(let value) = self { return value }
        return nil
    }

    var customID: UUID? {
        if case .custom(let id, _) = self { return id }
        return nil
    }
}
