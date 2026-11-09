// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// A nonblocking native sheet; the default button declines rather than granting consent.
@MainActor
enum TelemetryConsentPrompt {
    private static let usageDisclosure = "Kinetiq sends known effect identifiers and their drag/open/close/minimize/manual/layout use, effect selections, visits to the Lab/Animation Studio and other product pages, successful Studio editing/save/import/export actions, screen saver enable/disable and app previews, and selected render quality. Custom effects are reported only as 'custom', never by name or identifier. No window titles, app identities, screenshots, document contents, paths, precise location or crash reports. Screen saver activation in the macOS host is not measured."

    static func disclosure(mode: KinetiqTelemetry.Mode) -> String {
        if mode == .ga4 {
            return "Optional Google Analytics 4 Web Measurement Protocol uses a separate local pseudonymous identifier, a local Web session identifier and measured foreground time after consent. " + usageDisclosure + " No automatic native Firebase, device/OS or session events. No Keychain access. Advertising user data and personalization are denied. Google sees your connection IP and network metadata. After consent, Kinetiq reads the country configured in macOS Language & Region and sends its ISO code as GA4 user_location.country_id for the standard Country dimension. This regional preference can override the reported country; it is not your physical location or citizenship. No city, subdivision, GPS or IP lookup is added; no external location service is contacted. Missing or unsupported country codes are omitted. Usage/session reports are partial; HTTP acceptance does not confirm report ingestion. The bundled ingestion secret is extractable. Previously granted settings-only consent or revision-2 product-usage consent does not authorize this country collection; please choose again."
        }
        return "Allow optional Google Firebase Analytics? Firebase collects its own app-instance identifier, app/device/OS information and automatic usage/session events; Google may derive approximate city/country from the connection IP. " + usageDisclosure + " Advertising storage, personalization and advertising identifiers are disabled. Firebase uses app-private Keychain storage on macOS. Previously granted settings-only consent does not authorize expanded collection; please choose again."
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