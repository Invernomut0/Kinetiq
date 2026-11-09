// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import CoreGraphics
import Foundation
import KinetiqCore
import KinetiqEffects

enum DragModifier: String, CaseIterable {
    case controlCommand
    case optionCommand
    case controlOption
    case option

    static let relevantFlags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

    var flags: CGEventFlags {
        switch self {
        case .controlCommand: return [.maskControl, .maskCommand]
        case .optionCommand: return [.maskAlternate, .maskCommand]
        case .controlOption: return [.maskControl, .maskAlternate]
        case .option: return [.maskAlternate]
        }
    }

    var title: String {
        switch self {
        case .controlCommand: return "⌃⌘ + Drag"
        case .optionCommand: return "⌥⌘ + Drag"
        case .controlOption: return "⌃⌥ + Drag"
        case .option: return "⌥ + Drag"
        }
    }

    func matches(_ flags: CGEventFlags) -> Bool {
        flags.intersection(Self.relevantFlags) == self.flags
    }
}

/// What plays when a window opens: one of the jelly entrances, a random one or nothing.
enum OpenEffectChoice: Equatable {
    case off
    case random
    case wobble(WobbleEntrance)

    init(rawValue: String?) {
        switch rawValue {
        case nil, "off": self = .off
        case "random": self = .random
        case let id? where id.hasPrefix("wobble:"):
            self = WobbleEntrance(rawValue: String(id.dropFirst("wobble:".count))).map(OpenEffectChoice.wobble) ?? .wobble(.wobblePop)
        // Older versions stored a shader here: the effect was on, so keep it on.
        default: self = .wobble(.wobblePop)
        }
    }

    var rawValue: String {
        switch self {
        case .off: return "off"
        case .random: return "random"
        case .wobble(let entrance): return "wobble:" + entrance.rawValue
        }
    }
}

/// A Dock morph or desktop-space liquid, triggered by the yellow minimize button.
enum MinimizeEffectChoice: Equatable {
    case off
    case random
    case liquid
    case morph(DockMorphStyle)

    init(rawValue: String?) {
        switch rawValue {
        case nil, "off": self = .off
        case "random": self = .random
        case "liquid": self = .liquid
        case let id? where id.hasPrefix("morph:"):
            self = DockMorphStyle(rawValue: String(id.dropFirst("morph:".count))).map(MinimizeEffectChoice.morph) ?? .morph(.genie)
        // Older versions stored a close shader here: the effect was on, so keep it on.
        default: self = .morph(.genie)
        }
    }

    var rawValue: String {
        switch self {
        case .off: return "off"
        case .random: return "random"
        case .liquid: return "liquid"
        case .morph(let style): return "morph:" + style.rawValue
        }
    }
}

enum WobblePreset: String, CaseIterable {
    case subtle, realistic, exaggerated, extreme, custom

    var settings: KinetiqSettings? {
        switch self {
        case .subtle: return .subtle
        case .realistic: return .realistic
        case .exaggerated: return .exaggerated
        case .extreme: return .extreme
        case .custom: return nil
        }
    }

    var title: String {
        switch self {
        case .subtle: return "Subtle"
        case .realistic: return "Realistic"
        case .exaggerated: return "Exaggerated"
        case .extreme: return "Extreme"
        case .custom: return "Custom"
        }
    }
}

/// The same settings as the GNOME extension "Compiz windows effect", with the same ranges.
final class Settings {
    static let frictionRange: ClosedRange<Double> = 1...10
    static let springRange: ClosedRange<Double> = 1...10
    static let speedupRange: ClosedRange<Double> = 2...40
    static let massRange: ClosedRange<Double> = 20...80
    static let tilesRange: ClosedRange<Double> = 3...20
    /// Multiplies the default animation time of the close effects.
    static let closeSpeedRange: ClosedRange<Double> = 0.25...3
    static let chaosIdleRange = 1...60
    static let defaultCloseEffect = CloseEffectChoice.effect(.fire)
    /// Keep the management window usable even while other windows are animated.
    static let protectedExclusionID = "io.github.invernomut0.Kinetiq"
    static let defaultExcludedApps = [protectedExclusionID]

    private static let defaultTilesX = 16
    private static let defaultTilesY = 14

    private let defaults: UserDefaults

    /// A separate defaults suite supports isolated tests without touching the user's preferences.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var enabled: Bool {
        get { defaults.object(forKey: "enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "enabled") }
    }

    /// Drag from the title bar without holding any shortcut.
    var titleBarDrag: Bool {
        get { defaults.object(forKey: "titleBarDrag") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "titleBarDrag") }
    }

    var modifier: DragModifier {
        get { defaults.string(forKey: "modifier").flatMap(DragModifier.init(rawValue:)) ?? .controlCommand }
        set { defaults.set(newValue.rawValue, forKey: "modifier") }
    }

    var shadow: Bool {
        get { defaults.object(forKey: "shadow") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "shadow") }
    }

    var preset: WobblePreset {
        get { defaults.string(forKey: "wobblyPreset").flatMap(WobblePreset.init(rawValue:)) ?? .realistic }
        set {
            defaults.set(newValue.rawValue, forKey: "wobblyPreset")
            if let values = newValue.settings { physics = values }
        }
    }

    var physics: KinetiqSettings {
        get {
            let fallback = KinetiqSettings.realistic
            return KinetiqSettings(
                friction: float("friction") ?? fallback.friction,
                spring: float("spring") ?? fallback.spring,
                speedup: float("speedup") ?? fallback.speedup,
                mass: float("mass") ?? fallback.mass)
        }
        set {
            defaults.set(Double(newValue.friction), forKey: "friction")
            defaults.set(Double(newValue.spring), forKey: "spring")
            defaults.set(Double(newValue.speedup), forKey: "speedup")
            defaults.set(Double(newValue.mass), forKey: "mass")
        }
    }

    var tilesX: Int {
        get { defaults.object(forKey: "tilesX") as? Int ?? Self.defaultTilesX }
        set { defaults.set(newValue, forKey: "tilesX") }
    }

    var tilesY: Int {
        get { defaults.object(forKey: "tilesY") as? Int ?? Self.defaultTilesY }
        set { defaults.set(newValue, forKey: "tilesY") }
    }

    var maximizeEffect: Bool {
        get { defaults.object(forKey: "maximizeEffect") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "maximizeEffect") }
    }

    var resizeEffect: Bool {
        get { defaults.object(forKey: "resizeEffect") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "resizeEffect") }
    }

    /// A window let go while moving fast keeps gliding and bounces off the edges of the screen.
    var glideOnFlick: Bool {
        get { defaults.object(forKey: "glideOnFlick") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "glideOnFlick") }
    }

    /// A circular ripple spreads over the window from the point where it was dropped.
    var rippleOnDrop: Bool {
        get { defaults.object(forKey: "rippleOnDrop") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "rippleOnDrop") }
    }

    /// A glow flashes around the window that takes the focus.
    var focusPulse: Bool {
        get { defaults.object(forKey: "focusPulse") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "focusPulse") }
    }

    /// The window leans in perspective into its movement while it is dragged.
    var tiltOnDrag: Bool {
        get { defaults.object(forKey: "tiltOnDrag") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "tiltOnDrag") }
    }

    /// Liquid, Window Destruction, a Burn-My-Windows shader, a random shader, or none.
    var closeEffect: CloseEffectChoice {
        get { CloseEffectChoice(rawValue: defaults.string(forKey: "closeEffect")) }
        set { defaults.set(newValue.rawValue, forKey: "closeEffect") }
    }

    /// Effect played when a window opens: a jelly entrance or a shader (the close effects in reverse); off by default.
    var openEffect: OpenEffectChoice {
        get { OpenEffectChoice(rawValue: defaults.string(forKey: "openEffect")) }
        set { defaults.set(newValue.rawValue, forKey: "openEffect") }
    }

    /// Liquid or a morph into the Dock icon, on the yellow button; off by default.
    var minimizeEffect: MinimizeEffectChoice {
        get { MinimizeEffectChoice(rawValue: defaults.string(forKey: "minimizeEffect")) }
        set { defaults.set(newValue.rawValue, forKey: "minimizeEffect") }
    }

    /// ⌃⌥↑ anywhere opens the window overview.
    var overviewShortcut: Bool {
        get { defaults.object(forKey: "overviewShortcut") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "overviewShortcut") }
    }

    /// Which arrangement the shortcut and the menu open: Exposé 3D, Orbit or Cube.
    var overviewLayout: EffectID {
        get {
            let id = defaults.string(forKey: "overviewLayout").flatMap(EffectID.init(rawValue:)) ?? .expose3D
            return Self.overviewLayouts.contains(id) ? id : .expose3D
        }
        set { defaults.set(newValue.rawValue, forKey: "overviewLayout") }
    }

    static let overviewLayouts: [EffectID] = [.expose3D, .orbit, .workspaceCube]

    /// Animation time of the close effects relative to the default of each effect.
    var closeDuration: Double {
        get { min(max(defaults.object(forKey: "closeDuration") as? Double ?? 1, Self.closeSpeedRange.lowerBound), Self.closeSpeedRange.upperBound) }
        set { defaults.set(newValue, forKey: "closeDuration") }
    }

    /// Close effect per app (bundle identifier -> choice), overriding `closeEffect`.
    var appCloseEffects: [String: String] {
        get { defaults.dictionary(forKey: "appCloseEffects") as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: "appCloseEffects") }
    }

    /// The close effect for windows of the app with this bundle identifier.
    func closeEffect(forBundleID id: String?) -> CloseEffectChoice {
        if let id, let raw = appCloseEffects[id] { return CloseEffectChoice(rawValue: raw) }
        return closeEffect
    }

    /// Bundle identifiers of the apps whose windows get no effect at all.
    var excludedApps: [String] {
        get { Self.protectingOwnWindows(defaults.stringArray(forKey: "excludedApps") ?? Self.defaultExcludedApps) }
        set { defaults.set(Self.protectingOwnWindows(newValue), forKey: "excludedApps") }
    }

    /// Also repairs legacy lists whose user-removable Kinetiq rule was deleted.
    private static func protectingOwnWindows(_ apps: [String]) -> [String] {
        apps.contains(protectedExclusionID) ? apps : defaultExcludedApps + apps
    }

    /// The screen saver that makes the desktop fall apart starts after `chaosIdleMinutes` without input.
    var chaosEnabled: Bool {
        get { defaults.object(forKey: "chaosEnabled") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "chaosEnabled") }
    }

    /// Inactivity delay to restore when Kinetiq relinquishes the system screen saver.
    var chaosPreviousIdleSeconds: Int? {
        get { defaults.object(forKey: "chaosPreviousIdleSeconds") as? Int }
        set { defaults.set(newValue, forKey: "chaosPreviousIdleSeconds") }
    }

    var chaosIdleMinutes: Int {
        get { min(max(defaults.object(forKey: "chaosIdleMinutes") as? Int ?? 5, Self.chaosIdleRange.lowerBound), Self.chaosIdleRange.upperBound) }
        set { defaults.set(newValue, forKey: "chaosIdleMinutes") }
    }

    /// Milliseconds between two things breaking.
    var chaosEventInterval: Double {
        get { defaults.object(forKey: "chaosEventInterval") as? Double ?? 1500 }
        set { defaults.set(newValue, forKey: "chaosEventInterval") }
    }

    /// Seconds a fallen piece stays before it fades away.
    var chaosLifetime: Double {
        get { defaults.object(forKey: "chaosLifetime") as? Double ?? 15 }
        set { defaults.set(newValue, forKey: "chaosLifetime") }
    }

    var chaosIntensity: Double {
        get { defaults.object(forKey: "chaosIntensity") as? Double ?? 1 }
        set { defaults.set(newValue, forKey: "chaosIntensity") }
    }

    var chaosSettings: ChaosSettings {
        ChaosSettings(eventInterval: chaosEventInterval, lifetime: chaosLifetime, intensity: chaosIntensity, speed: chaosSpeed)
    }

    /// 1 = real time; lower values make everything fall in slow motion.
    var chaosSpeed: Double {
        get { defaults.object(forKey: "chaosSpeed") as? Double ?? 0.55 }
        set { defaults.set(newValue, forKey: "chaosSpeed") }
    }

    func resetToDefaults() {
        chaosEnabled = false
        chaosIdleMinutes = 5
        chaosEventInterval = 1500
        chaosLifetime = 15
        chaosIntensity = 1
        chaosSpeed = 0.55
        preset = .realistic
        excludedApps = Self.defaultExcludedApps
        tilesX = Self.defaultTilesX
        tilesY = Self.defaultTilesY
        maximizeEffect = true
        resizeEffect = false
        glideOnFlick = true
        tiltOnDrag = true
        focusPulse = false
        rippleOnDrop = false
        closeEffect = Self.defaultCloseEffect
        openEffect = .off
        minimizeEffect = .off
        appCloseEffects = [:]
        closeDuration = 1
        overviewShortcut = true
        overviewLayout = .expose3D
    }

    private func float(_ key: String) -> Float? {
        (defaults.object(forKey: key) as? Double).map(Float.init)
    }
}

/// Whether the app owning a window is on the exclusion list; read straight from the defaults so it is cheap in the event tap.
enum AppExclusions {
    static func contains(pid: pid_t) -> Bool {
        if pid == ProcessInfo.processInfo.processIdentifier { return true }
        return contains(bundleID: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier)
    }

    /// The mandatory rule applies even to externally edited or legacy preferences.
    static func contains(bundleID: String?, defaults: UserDefaults = .standard) -> Bool {
        guard let bundleID else { return false }
        return bundleID == Settings.protectedExclusionID
            || (defaults.stringArray(forKey: "excludedApps") ?? Settings.defaultExcludedApps).contains(bundleID)
    }
}
