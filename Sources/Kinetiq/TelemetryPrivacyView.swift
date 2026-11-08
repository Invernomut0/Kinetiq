// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// A nonblocking native sheet; the default button declines rather than granting consent.
@MainActor
enum TelemetryConsentPrompt {
    static func makeAlert() -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Help improve Kinetiq?"
        alert.informativeText = "Allow optional Google Firebase Analytics? Firebase collects its own app-instance identifier, app/device/OS information and automatic usage/session events. Kinetiq adds only opening Settings; no window titles, screenshots or documents. Advertising storage, personalization and advertising identifiers are disabled. Firebase uses app-private Keychain storage on macOS. This is a new choice, separate from any previous provider. Analytics stays off unless you enable it; withdraw consent in Settings → Privacy & Analytics."
        alert.addButton(withTitle: "Don't Share")
        alert.addButton(withTitle: "Enable Analytics")
        alert.buttons[1].keyEquivalent = ""
        return alert
    }

    @discardableResult
    static func present(for telemetry: KinetiqTelemetry, on window: NSWindow) -> Bool {
        guard window.isVisible, window.attachedSheet == nil,
              telemetry.claimStartupConsentPrompt() else { return false }
        makeAlert().beginSheetModal(for: window) { response in
            Task { @MainActor in
                await telemetry.setAnalyticsConsent(response == .alertSecondButtonReturn)
            }
        }
        return true
    }
}

/// Only telemetry controls are gated. Effects, permissions and other settings remain usable.
struct TelemetryPrivacyView: View {
    @ObservedObject var telemetry: KinetiqTelemetry

    var body: some View {
        Section("Privacy & Analytics") {
            Toggle("Share categorical usage analytics", isOn: Binding(
                get: { telemetry.analyticsConsent },
                set: { value in Task { await telemetry.setAnalyticsConsent(value) } }))
                .toggleStyle(.checkbox)
                .disabled(!telemetry.canChangeConsent)
                .accessibilityHint("Optional; off by default. You can withdraw consent here.")
            if telemetry.busy { ProgressView("Applying analytics preference") }
            Text(telemetry.status).font(.caption).foregroundStyle(.secondary)
            Text("Optional Google Firebase Analytics includes its app-instance identifier, app/device/OS information and automatic usage/session events. Kinetiq adds only opening these settings, never window titles, images or documents. Advertising identifiers, ad storage and personalization are disabled. No crash reporting. Firebase requires app-private Keychain access on macOS; previous provider consent and identifiers are not transferred.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Withdrawal stops new submissions and attempts to remove the local queue. It cannot recall in-flight data or erase server records. The service sees your connection IP; this is not network anonymity.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task { await telemetry.privacySettingsOpened() }
    }
}