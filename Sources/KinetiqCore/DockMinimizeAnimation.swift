// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

/// Decides how to change the Dock's minimize animation (`mineffect`: genie, scale or suck) so that the system one
/// doesn't compete with Kinetiq's minimize effect, and how to put the user's choice back afterwards.
public enum DockMinimizeAnimation {
    public static let replacement = "scale"
    public static let systemDefault = "genie"

    public enum Change: Equatable {
        case none
        /// Switch the Dock to `replacement`. `backup` is the user's original value to remember (nil: one is already kept).
        case disable(backup: String?)
        /// Put `value` back (nil removes the setting, which means the system default).
        case restore(value: String?)
        /// The user changed the setting meanwhile: leave it alone and drop the remembered value.
        case forgetBackup
    }

    /// - Parameters:
    ///   - wantsDisabled: Kinetiq's minimize effect is on.
    ///   - current: the Dock's current `mineffect` (nil: not set).
    ///   - backup: the value remembered when the animation was last replaced.
    public static func plan(wantsDisabled: Bool, current: String?, backup: String?) -> Change {
        let effective = current ?? systemDefault
        if wantsDisabled {
            guard effective != replacement else { return .none }
            return .disable(backup: backup == nil ? effective : nil)
        }
        guard let backup else { return .none }
        guard effective == replacement else { return .forgetBackup }
        return .restore(value: backup == systemDefault ? nil : backup)
    }
}
