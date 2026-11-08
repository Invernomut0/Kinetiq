// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Invernomut0Telemetry

/// Disabled real-core smoke, bypassing runtime keys, preferences, vendor setup and Keychain.
@MainActor
enum TelemetrySmoke {
    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task {
            let config = TelemetryConfiguration(productID: "kinetiq_disabled_smoke",
                productName: "Kinetiq", environment: .development, enabled: false,
                privacy: PrivacySettings(collectOSVersion: false, collectHardwareInfo: false),
                lifecycleTrackingEnabled: false)
            let client = TelemetryClient(configuration: config, identityStore: NoSmokeIdentity())
            do {
                try await client.initialize()
                let health = await client.diagnostics()
                guard health.initialized, !health.analyticsEnabled, !health.analyticsAvailable,
                      !health.crashReportingEnabled, !health.crashReportingAvailable,
                      health.acceptedEvents == 0 else { throw SmokeFailure.invalid }
                await client.shutdown()
                print("KINETIQ_TELEMETRY_DISABLED_SMOKE_SUCCESS")
                exit(0)
            } catch {
                await client.shutdown()
                print("KINETIQ_TELEMETRY_DISABLED_SMOKE_FAILURE")
                exit(1)
            }
        }
        app.run()
    }
}

private enum SmokeFailure: Error { case invalid }
private actor NoSmokeIdentity: InstallationIdentityStore {
    func load() throws -> UUID? { throw SmokeFailure.invalid }
    func save(_ identity: UUID) throws { throw SmokeFailure.invalid }
    func delete() throws { throw SmokeFailure.invalid }
}