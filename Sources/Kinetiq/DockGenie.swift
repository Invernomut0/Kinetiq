// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import KinetiqCore

/// Turns the system's genie minimize animation off while Kinetiq's minimize effect is on, and puts it back after.
/// The Dock only reads the setting when it starts, so it is restarted (it relaunches by itself).
enum DockGenie {
    private static let domain = "com.apple.dock" as CFString
    private static let key = "mineffect" as CFString
    private static let backupKey = "dockMinimizeEffectBackup"

    static func sync(enabled: Bool, defaults: UserDefaults = .standard) {
        let current = CFPreferencesCopyValue(key, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? String
        let change = DockMinimizeAnimation.plan(wantsDisabled: enabled, current: current, backup: defaults.string(forKey: backupKey))
        switch change {
        case .none:
            return
        case .disable(let backup):
            if let backup { defaults.set(backup, forKey: backupKey) }
            write(DockMinimizeAnimation.replacement)
        case .restore(let value):
            defaults.removeObject(forKey: backupKey)
            write(value)
        case .forgetBackup:
            defaults.removeObject(forKey: backupKey)
            return
        }
        restartDock()
    }

    private static func write(_ value: String?) {
        CFPreferencesSetValue(key, value as CFString?, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    private static func restartDock() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        try? process.run()
    }
}
