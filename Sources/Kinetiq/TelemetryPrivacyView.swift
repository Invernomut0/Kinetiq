// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// A nonblocking native sheet; the default button declines rather than granting consent.
@MainActor
enum TelemetryConsentPrompt {
    static func disclosure(mode: KinetiqTelemetry.Mode) -> String {
        if mode == .ga4 {
            return "Optional Google Analytics 4 Web Measurement Protocol sends a separate local pseudonymous identifier and only the action of opening Privacy & Analytics settings, with a local Web session identifier and measured time in the foreground after consent. No automatic native Firebase, device/OS or session events, window titles, screenshots, documents or crash reports. No Keychain access. Advertising user data and personalization are denied. Google sees your connection IP and network metadata. Usage/session reports are partial and cover only this action; HTTP acceptance does not confirm report ingestion. The bundled ingestion secret is extractable. Previous Firebase and other provider consent and identifiers are not transferred."
        }
        return "Allow optional Google Firebase Analytics? Firebase collects its own app-instance identifier, app/device/OS information and automatic usage/session events. Kinetiq adds only opening Settings; no window titles, screenshots or documents. Advertising storage, personalization and advertising identifiers are disabled. Firebase uses app-private Keychain storage on macOS. This is a new choice, separate from any previous provider."
    }

    static func withdrawalDisclosure(mode: KinetiqTelemetry.Mode) -> String {
        if mode == .ga4 {
            return "Withdrawal stops new submissions, cancels pending requests and clears local transport memory. The local identifier remains in preferences. There is no disk queue or retry. Cancellation cannot recall in-flight data or erase server records; this is not network anonymity."
        }
        return "Withdrawal stops new submissions and attempts to remove the local queue. It cannot recall in-flight data or erase server records. The service sees your connection IP; this is not network anonymity."
    }

    static func makeAlert(mode: KinetiqTelemetry.Mode = .native) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Help improve Kinetiq?"
        alert.informativeText = disclosure(mode: mode) + " Analytics stays off unless you enable it; withdraw consent in Settings → Privacy & Analytics."
        alert.addButton(withTitle: "Don't Share")
        alert.addButton(withTitle: "Enable Analytics")
        alert.buttons[1].keyEquivalent = ""
        return alert
    }

    @discardableResult
    static func present(for telemetry: KinetiqTelemetry, on window: NSWindow) -> Bool {
        guard window.isVisible, window.attachedSheet == nil,
              telemetry.claimStartupConsentPrompt() else { return false }
        makeAlert(mode: telemetry.mode).beginSheetModal(for: window) { response in
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
            if telemetry.mode == .ga4 {
                Text(telemetry.transportStatus).font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel("Google Analytics transport status")
            }
            Text(TelemetryConsentPrompt.disclosure(mode: telemetry.mode))
                .font(.caption).foregroundStyle(.secondary)
            Text(TelemetryConsentPrompt.withdrawalDisclosure(mode: telemetry.mode))
                .font(.caption).foregroundStyle(.secondary)
        }
        // Granting while this page is mounted must record the actual visible visit once.
        // Busy is deliberately not part of the key: tracking itself changes that state.
        .task(id: telemetry.ready && telemetry.enabled && telemetry.analyticsConsent) {
            guard telemetry.ready, telemetry.enabled, telemetry.analyticsConsent else { return }
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            guard !Task.isCancelled else { return }
            await telemetry.privacySettingsOpened()
        }
    }
}