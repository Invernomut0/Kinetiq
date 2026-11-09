// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import FirebaseAnalytics
import FirebaseCore
import Invernomut0Telemetry
import Security

/// One application owner controls the official singleton; no Firebase configuration before consent.
@MainActor
final class FirebaseAnalyticsProvider: AnalyticsProvider {
    nonisolated let name = "Google Firebase Analytics"
    private let options: FirebaseOptions
    private var configured = false
    private var started = false

    init(options: FirebaseOptions) { self.options = options }

    /// Inspect signing metadata only. Never query a Keychain item or request authorization.
    static var hasPrivateKeychainAccess: Bool {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(rawValue: 0), &code) == errSecSuccess, let code else { return false }
                var staticCode: SecStaticCode?
                guard SecCodeCopyStaticCode(code, SecCSFlags(rawValue: 0), &staticCode) == errSecSuccess,
              let staticCode else { return false }
        var information: CFDictionary?
                guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let info = information as? [String: Any],
              let team = info[kSecCodeInfoTeamIdentifier as String] as? String,
              let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
              let groups = entitlements["keychain-access-groups"] as? [String] else { return false }
        return groups == [team + ".io.github.invernomut0.Kinetiq"]
    }

    func start(configuration: TelemetryConfiguration, installationID: UUID) throws {
                guard configuration.enabled, configuration.privacy.analyticsEnabled,
              hasSafeDefaults, Self.hasPrivateKeychainAccess else { throw TelemetryHostConfiguration.Invalid.configuration }
        if !configured {
            guard FirebaseApp.app() == nil else { throw TelemetryHostConfiguration.Invalid.configuration }
            FirebaseApp.configure(options: options)
            configured = true
        }
        // Only analytics is granted. Never link the previous local UUID using setUserID.
        Analytics.setConsent([.analyticsStorage: .granted, .adStorage: .denied,
                              .adUserData: .denied, .adPersonalization: .denied])
        Analytics.setAnalyticsCollectionEnabled(true)
        started = true
    }

    private var hasSafeDefaults: Bool {
        FirebaseAnalyticsPolicy.safetyKeys.allSatisfy { key in
            guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? NSNumber,
                  CFGetTypeID(value) == CFBooleanGetTypeID() else { return false }
            return !value.boolValue
        }
    }

    func capture(_ event: TelemetryEvent) {
        guard started, let parameters = FirebaseAnalyticsPolicy.parameters(for: event) else { return }
        Analytics.logEvent(event.name, parameters: parameters)
    }

    /// Firebase has no public awaited flush API. Never invent a delivery acknowledgement.
    func flush() {}

    func stop(purge: Bool) {
        guard started else { return }
        Analytics.setAnalyticsCollectionEnabled(false)
        Analytics.setConsent([.analyticsStorage: .denied, .adStorage: .denied,
                              .adUserData: .denied, .adPersonalization: .denied])
        if purge { Analytics.resetAnalyticsData() }
        started = false
    }
}

/// Restrict custom events independently of the SDK core's lifecycle/metadata vocabulary.
enum FirebaseAnalyticsPolicy {
    static let safetyKeys = ["FIREBASE_ANALYTICS_COLLECTION_ENABLED", "FIREBASE_DATA_COLLECTION_DEFAULT_ENABLED",
        "GOOGLE_ANALYTICS_DEFAULT_ALLOW_ANALYTICS_STORAGE", "GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_STORAGE",
        "GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_USER_DATA", "GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS",
        "GOOGLE_ANALYTICS_IDFV_COLLECTION_ENABLED", "GOOGLE_ANALYTICS_REGISTRATION_WITH_AD_NETWORK_ENABLED",
        "FirebaseAutomaticScreenReportingEnabled", "FirebaseAppDelegateProxyEnabled"]

    static func parameters(for event: TelemetryEvent) -> [String: String]? {
        KinetiqUsageEvent.approvedParameters(name: event.name, properties: event.properties)
    }
}