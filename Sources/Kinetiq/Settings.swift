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
    static let defaultCloseEffect = CloseEffectChoice.effect(.fire)
    /// Kinetiq's own windows (the Setup window) start excluded, like before exclusions were configurable.
    static let defaultExcludedApps = ["io.github.invernomut0.Kinetiq"]

    private static let defaultTilesX = 16
    private static let defaultTilesY = 14

    private let defaults = UserDefaults.standard

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

    /// Effect played when a window is closed (a Burn-My-Windows shader), a random one, or none.
    var closeEffect: CloseEffectChoice {
        get { CloseEffectChoice(rawValue: defaults.string(forKey: "closeEffect")) }
        set { defaults.set(newValue.rawValue, forKey: "closeEffect") }
    }

    /// Effect played when a window opens (the same shaders, reversed); off by default.
    var openEffect: CloseEffectChoice {
        get { defaults.string(forKey: "openEffect").map { CloseEffectChoice(rawValue: $0) } ?? .off }
        set { defaults.set(newValue.rawValue, forKey: "openEffect") }
    }

    /// Effect played when a window is minimized with its yellow button (the close shaders); off by default.
    var minimizeEffect: CloseEffectChoice {
        get { defaults.string(forKey: "minimizeEffect").map { CloseEffectChoice(rawValue: $0) } ?? .off }
        set { defaults.set(newValue.rawValue, forKey: "minimizeEffect") }
    }

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
        get { defaults.stringArray(forKey: "excludedApps") ?? Self.defaultExcludedApps }
        set { defaults.set(newValue, forKey: "excludedApps") }
    }

    func resetToDefaults() {
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
    }

    private func float(_ key: String) -> Float? {
        (defaults.object(forKey: key) as? Double).map(Float.init)
    }
}

/// Whether the app owning a window is on the exclusion list; read straight from the defaults so it is cheap in the event tap.
enum AppExclusions {
    static func contains(pid: pid_t) -> Bool {
        guard let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return false }
        return (UserDefaults.standard.stringArray(forKey: "excludedApps") ?? Settings.defaultExcludedApps).contains(id)
    }
}
