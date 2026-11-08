// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import FirebaseCore
import Invernomut0Telemetry
import SwiftUI
import XCTest
@testable import Kinetiq

/// Host contracts use the real core actor with recording boundary doubles, not service delivery.
@MainActor
final class KinetiqTelemetryTests: XCTestCase {
    /// Owner metadata is optional on CI; never fabricate a valid Firebase client configuration.
    private func clientConfigurationURL() throws -> URL {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("GoogleService-Info.plist")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Owner-supplied Firebase client metadata is unavailable")
        }
        return url
    }

    private func preferences() throws -> (UserDefaults, String) {
        let suite = "kinetiq.telemetry.contract.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return (defaults, suite)
    }

    private func owner(_ defaults: UserDefaults, provider: RecordingHostAnalytics? = nil,
                       store: ContractIdentity = ContractIdentity(), purgeFailure: Bool = false) -> KinetiqTelemetry {
        KinetiqTelemetry(defaults: defaults,
            configuration: .success(TelemetryHostConfiguration(options: nil, environment: .development)),
            productID: "kinetiq_contract_" + UUID().uuidString.lowercased(),
            provider: provider, identityStore: store, purgeFailed: { purgeFailure })
    }

    func testDeniedStartupNoProviderNoIdentityAndRepeatedInitialization() async throws {
        let (defaults, _) = try preferences()
        let store = ContractIdentity()
        let telemetry = owner(defaults, store: store)
        async let first: Void = telemetry.initialize()
        async let second: Void = telemetry.initialize()
        _ = await (first, second)
        await telemetry.initialize()
        XCTAssertTrue(telemetry.ready)
        XCTAssertFalse(telemetry.analyticsConsent)
        XCTAssertFalse(telemetry.canChangeConsent)
        let accesses = await store.accesses
        XCTAssertEqual(accesses, 0)
        await telemetry.shutdown()
    }

    func testDefaultIdentityUsesPreferencesOnlyAfterConsentAndPersistsAcrossRestart() async throws {
        let (defaults, _) = try preferences()
        let productID = "kinetiq_local_" + UUID().uuidString.lowercased()
        let key = TelemetryPreferenceIdentityStore.preferenceKey(productID: productID)
        func localOwner() -> KinetiqTelemetry {
            KinetiqTelemetry(defaults: defaults,
                configuration: .success(TelemetryHostConfiguration(options: nil, environment: .development)),
                productID: productID, provider: RecordingHostAnalytics())
        }
        let telemetry = localOwner()
        XCTAssertNil(defaults.object(forKey: key))
        await telemetry.initialize()
        XCTAssertTrue(telemetry.ready)
        XCTAssertNil(defaults.object(forKey: key), "Denied startup must not create an identity")
        await telemetry.setAnalyticsConsent(true)
        XCTAssertTrue(telemetry.analyticsConsent)
        let first = try XCTUnwrap(defaults.string(forKey: key))
        XCTAssertNotNil(UUID(uuidString: first))
        await telemetry.shutdown()
        let restarted = localOwner()
        await restarted.initialize()
        XCTAssertTrue(restarted.ready)
        XCTAssertTrue(restarted.analyticsConsent)
        XCTAssertEqual(defaults.string(forKey: key), first)
        await restarted.setAnalyticsConsent(false)
        await restarted.shutdown()
        let denied = localOwner()
        await denied.initialize()
        XCTAssertFalse(denied.analyticsConsent)
        XCTAssertEqual(defaults.string(forKey: key), first, "Revocation does not silently rotate attribution")
        await denied.shutdown()
    }

    func testPreferenceIdentityIsProductScopedAndDeletePreservesOtherPreferences() async throws {
        let (defaults, _) = try preferences()
        let first = TelemetryPreferenceIdentityStore(defaults: defaults, productID: "kinetiq")
        let second = TelemetryPreferenceIdentityStore(defaults: defaults, productID: "tempo")
        let a = UUID(), b = UUID()
        defaults.set(false, forKey: KinetiqTelemetry.consentKey)
        await first.save(a)
        await second.save(b)
        let loadedA = try await first.load()
        let loadedB = try await second.load()
        XCTAssertEqual(loadedA, a)
        XCTAssertEqual(loadedB, b)
        await first.delete()
        let deleted = try await first.load()
        let retained = try await second.load()
        XCTAssertNil(deleted)
        XCTAssertEqual(retained, b)
        XCTAssertNotNil(defaults.object(forKey: KinetiqTelemetry.consentKey))
        XCTAssertFalse(defaults.bool(forKey: KinetiqTelemetry.consentKey))
    }

    func testInvalidPreferenceIdentityFailsClosedWithoutProviderStart() async throws {
        let (defaults, _) = try preferences()
        let productID = "kinetiq_invalid_" + UUID().uuidString.lowercased()
        let key = TelemetryPreferenceIdentityStore.preferenceKey(productID: productID)
        defaults.set("not-a-uuid", forKey: key)
        defaults.set(true, forKey: KinetiqTelemetry.consentKey)
        let provider = RecordingHostAnalytics()
        let telemetry = KinetiqTelemetry(defaults: defaults,
            configuration: .success(TelemetryHostConfiguration(options: nil, environment: .development)),
            productID: productID, provider: provider)
        await telemetry.initialize()
        XCTAssertFalse(telemetry.ready)
        XCTAssertFalse(telemetry.analyticsConsent)
        XCTAssertFalse(defaults.bool(forKey: KinetiqTelemetry.consentKey))
        let calls = await provider.calls
        XCTAssertFalse(calls.contains("start"))
        await telemetry.shutdown()
    }

    func testRealCoreResetsAndDeletesPreferenceIdentityWithoutRecreatingAfterDelete() async throws {
        let (defaults, _) = try preferences()
        let productID = "kinetiq_reset_" + UUID().uuidString.lowercased()
        let key = TelemetryPreferenceIdentityStore.preferenceKey(productID: productID)
        let client = TelemetryClient(configuration: TelemetryConfiguration(productID: productID,
            productName: "Kinetiq", privacy: PrivacySettings(analyticsEnabled: true,
                collectOSVersion: false, collectHardwareInfo: false), lifecycleTrackingEnabled: false),
            analyticsProvider: RecordingHostAnalytics(),
            identityStore: TelemetryPreferenceIdentityStore(defaults: defaults, productID: productID))
        try await client.initialize()
        let before = try XCTUnwrap(defaults.string(forKey: key))
        try await client.resetIdentity()
        let after = try XCTUnwrap(defaults.string(forKey: key))
        XCTAssertNotEqual(before, after)
        XCTAssertNotNil(UUID(uuidString: after))
        try await client.deleteIdentity()
        XCTAssertNil(defaults.object(forKey: key))
        let diagnostics = await client.diagnostics()
        XCTAssertFalse(diagnostics.analyticsEnabled)
        XCTAssertFalse(diagnostics.analyticsAvailable)
        await client.shutdown()
        XCTAssertNil(defaults.object(forKey: key))
    }

    func testBooleanOnlyConsentRejectsCoercibleStringsAndNumbers() async throws {
        for value: Any in ["true", "YES", 1, 0, "false"] {
            let (defaults, _) = try preferences()
            defaults.set(value, forKey: KinetiqTelemetry.consentKey)
            let telemetry = owner(defaults)
            XCTAssertFalse(telemetry.analyticsConsent)
            await telemetry.initialize()
            XCTAssertFalse(telemetry.analyticsConsent)
            await telemetry.shutdown()
        }
    }

    func testNoStartOrReplayBeforeConsent() async throws {
        let (defaults, _) = try preferences()
        let provider = RecordingHostAnalytics()
        let store = ContractIdentity()
        let telemetry = owner(defaults, provider: provider, store: store)
        await telemetry.privacySettingsOpened()
        await telemetry.setAnalyticsConsent(true)
        await telemetry.initialize()
        await telemetry.privacySettingsOpened()
        let calls = await provider.calls
        let accesses = await store.accesses
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(accesses, 0)
        XCTAssertTrue(telemetry.canChangeConsent)
        await telemetry.shutdown()
    }

    func testStartupPromptRequiresConfigurationAndDoesNotGrantConsent() async throws {
        let (defaults, _) = try preferences()
        let unavailable = owner(defaults)
        await unavailable.initialize()
        XCTAssertFalse(unavailable.claimStartupConsentPrompt())
        XCTAssertNil(defaults.object(forKey: KinetiqTelemetry.consentDecisionKey))
        await unavailable.shutdown()

        let provider = RecordingHostAnalytics()
        let store = ContractIdentity()
        let telemetry = owner(defaults, provider: provider, store: store)
        XCTAssertFalse(telemetry.shouldRequestConsentAtStartup)
        await telemetry.initialize()
        XCTAssertTrue(telemetry.claimStartupConsentPrompt())
        XCTAssertFalse(telemetry.claimStartupConsentPrompt())
        XCTAssertFalse(telemetry.analyticsConsent)
        XCTAssertNil(defaults.object(forKey: KinetiqTelemetry.consentDecisionKey))
        let calls = await provider.calls
        let accesses = await store.accesses
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(accesses, 0)
        await telemetry.shutdown()
    }

    func testStartupDenialIsRememberedAcrossRestartWithoutProviderStart() async throws {
        let (defaults, _) = try preferences()
        let provider = RecordingHostAnalytics()
        let telemetry = owner(defaults, provider: provider)
        await telemetry.initialize()
        XCTAssertTrue(telemetry.claimStartupConsentPrompt())
        await telemetry.setAnalyticsConsent(false)
        XCTAssertTrue(defaults.bool(forKey: KinetiqTelemetry.consentDecisionKey))
        XCTAssertFalse(defaults.bool(forKey: KinetiqTelemetry.consentKey))
        await telemetry.shutdown()

        let restarted = owner(defaults, provider: provider)
        await restarted.initialize()
        XCTAssertFalse(restarted.claimStartupConsentPrompt())
        XCTAssertFalse(restarted.analyticsConsent)
        let calls = await provider.calls
        XCTAssertFalse(calls.contains("start"))
        XCTAssertFalse(calls.contains("flush"))
        await restarted.shutdown()
    }

    func testStartupGrantAndWithdrawalDoNotPromptAgain() async throws {
        let (defaults, _) = try preferences()
        let telemetry = owner(defaults, provider: RecordingHostAnalytics())
        await telemetry.initialize()
        XCTAssertTrue(telemetry.claimStartupConsentPrompt())
        await telemetry.setAnalyticsConsent(true)
        XCTAssertTrue(telemetry.analyticsConsent)
        XCTAssertTrue(defaults.bool(forKey: KinetiqTelemetry.consentDecisionKey))
        await telemetry.setAnalyticsConsent(false)
        await telemetry.shutdown()
        let restarted = owner(defaults, provider: RecordingHostAnalytics())
        await restarted.initialize()
        XCTAssertFalse(restarted.claimStartupConsentPrompt())
        await restarted.shutdown()
    }

    func testUnansweredStartupPromptRetriesButPersistedGrantDoesNot() async throws {
        let (defaults, _) = try preferences()
        let telemetry = owner(defaults, provider: RecordingHostAnalytics())
        await telemetry.initialize()
        XCTAssertTrue(telemetry.claimStartupConsentPrompt())
        await telemetry.shutdown()
        let restarted = owner(defaults, provider: RecordingHostAnalytics())
        await restarted.initialize()
        XCTAssertTrue(restarted.shouldRequestConsentAtStartup)
        await restarted.shutdown()
        defaults.set(true, forKey: KinetiqTelemetry.consentKey)
        let consented = owner(defaults, provider: RecordingHostAnalytics())
        await consented.initialize()
        XCTAssertFalse(consented.claimStartupConsentPrompt())
        await consented.shutdown()
    }

    func testMalformedStartupDecisionDoesNotSuppressRequest() async throws {
        for value: Any in ["true", 1] {
            let (defaults, _) = try preferences()
            defaults.set(value, forKey: KinetiqTelemetry.consentDecisionKey)
            let telemetry = owner(defaults, provider: RecordingHostAnalytics())
            await telemetry.initialize()
            XCTAssertTrue(telemetry.shouldRequestConsentAtStartup)
            await telemetry.shutdown()
        }
    }

    func testNativeStartupConsentSheetDefaultsToDenialAndPersistsResponse() async throws {
        guard CGSessionCopyCurrentDictionary() != nil, !NSScreen.screens.isEmpty else {
            throw XCTSkip("A graphical session is required for the owned consent sheet")
        }
        let alert = TelemetryConsentPrompt.makeAlert()
        XCTAssertEqual(alert.buttons.map(\.title), ["Don't Share", "Enable Analytics"])
        XCTAssertEqual(alert.buttons[1].keyEquivalent, "")
        let (defaults, _) = try preferences()
        let provider = RecordingHostAnalytics()
        let telemetry = owner(defaults, provider: provider)
        await telemetry.initialize()
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 400),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        defer { window.close() }
        XCTAssertFalse(TelemetryConsentPrompt.present(for: telemetry, on: window))
        XCTAssertTrue(telemetry.shouldRequestConsentAtStartup)
        window.orderFrontRegardless()
        XCTAssertTrue(TelemetryConsentPrompt.present(for: telemetry, on: window))
        let sheet = try XCTUnwrap(window.attachedSheet)
        XCTAssertFalse(TelemetryConsentPrompt.present(for: telemetry, on: window))
        XCTAssertFalse(telemetry.analyticsConsent)
        window.endSheet(sheet, returnCode: .alertFirstButtonReturn)
        let decision = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            defaults.bool(forKey: KinetiqTelemetry.consentDecisionKey)
        }, object: nil)
        await fulfillment(of: [decision], timeout: 3)
        XCTAssertTrue(defaults.bool(forKey: KinetiqTelemetry.consentDecisionKey))
        XCTAssertFalse(telemetry.analyticsConsent)
        let calls = await provider.calls
        XCTAssertFalse(calls.contains("start"))
        await telemetry.shutdown()
    }

    func testGrantPersistsOnlyAfterSuccessfulStartAndSingleConcurrentInitialize() async throws {
        let (defaults, _) = try preferences()
        let provider = RecordingHostAnalytics(block: .start)
        let telemetry = owner(defaults, provider: provider)
        await telemetry.initialize()
        let grant = Task { await telemetry.setAnalyticsConsent(true) }
        await provider.waitUntilBlocked()
        XCTAssertFalse(defaults.bool(forKey: KinetiqTelemetry.consentKey))
        XCTAssertFalse(telemetry.analyticsConsent)
        XCTAssertTrue(telemetry.busy)
        let repeated = Task { await telemetry.initialize() }
        await telemetry.setAnalyticsConsent(true)
        await provider.release()
        await grant.value
        await repeated.value
        XCTAssertTrue(telemetry.analyticsConsent)
        XCTAssertTrue(defaults.bool(forKey: KinetiqTelemetry.consentKey))
        let calls = await provider.calls
        XCTAssertEqual(calls.filter { $0 == "start" }.count, 1)
        await telemetry.shutdown()
    }

    func testConcurrentInitializationWithPersistedConsentStartsOnce() async throws {
        let (defaults, _) = try preferences()
        defaults.set(true, forKey: KinetiqTelemetry.consentKey)
        let provider = RecordingHostAnalytics(block: .start)
        let telemetry = owner(defaults, provider: provider)
        let first = Task { await telemetry.initialize() }
        await provider.waitUntilBlocked()
        let second = Task { await telemetry.initialize() }
        await provider.release()
        await first.value
        await second.value
        let calls = await provider.calls
        XCTAssertEqual(calls.filter { $0 == "start" }.count, 1)
        XCTAssertTrue(telemetry.ready)
        await telemetry.shutdown()
    }

    func testFailedGrantDeniesAndBlocksRestart() async throws {
        let (defaults, _) = try preferences()
        let provider = RecordingHostAnalytics(failStart: true)
        let telemetry = owner(defaults, provider: provider)
        await telemetry.initialize()
        await telemetry.setAnalyticsConsent(true)
        XCTAssertFalse(defaults.bool(forKey: KinetiqTelemetry.consentKey))
        XCTAssertFalse(telemetry.analyticsConsent)
        XCTAssertFalse(telemetry.ready)
        await telemetry.initialize()
        await telemetry.privacySettingsOpened()
        let calls = await provider.calls
        XCTAssertEqual(calls.filter { $0 == "start" }.count, 1)
        XCTAssertFalse(calls.contains("capture:feature_used"))
        await telemetry.shutdown()
    }

    func testIdentityAccessFailureFailsClosedWithoutProviderStart() async throws {
        let (defaults, _) = try preferences()
        let provider = RecordingHostAnalytics()
        let telemetry = owner(defaults, provider: provider, store: ContractIdentity(fail: true))
        await telemetry.initialize()
        await telemetry.setAnalyticsConsent(true)
        XCTAssertFalse(telemetry.ready)
        XCTAssertFalse(telemetry.analyticsConsent)
        let calls = await provider.calls
        XCTAssertFalse(calls.contains("start"))
        await telemetry.shutdown()
    }

    func testWithdrawalPersistsBeforeCleanupWithoutFlushOrFurtherCapture() async throws {
        let (defaults, suite) = try preferences()
        let provider = RecordingHostAnalytics(block: .purge, preferenceSuite: suite)
        let telemetry = owner(defaults, provider: provider)
        await telemetry.initialize()
        await telemetry.setAnalyticsConsent(true)
        await telemetry.privacySettingsOpened()
        let revoke = Task { await telemetry.setAnalyticsConsent(false) }
        await provider.waitUntilBlocked()
        XCTAssertFalse(defaults.bool(forKey: KinetiqTelemetry.consentKey))
        XCTAssertFalse(telemetry.analyticsConsent)
        await telemetry.privacySettingsOpened()
        await provider.release()
        await revoke.value
        await telemetry.privacySettingsOpened()
        let observed = await provider.consentAtPurge
        let calls = await provider.calls
        XCTAssertEqual(observed, false)
        XCTAssertEqual(calls.filter { $0 == "capture:feature_used" }.count, 1)
        XCTAssertFalse(calls.contains("flush"))
        await telemetry.shutdown()
        let restarted = owner(defaults, provider: RecordingHostAnalytics())
        XCTAssertFalse(restarted.analyticsConsent)
        await restarted.initialize()
        await restarted.shutdown()
    }

    func testPurgeFailureDeniesAndDisablesControls() async throws {
        let (defaults, _) = try preferences()
        let telemetry = owner(defaults, provider: RecordingHostAnalytics(), purgeFailure: true)
        await telemetry.initialize()
        await telemetry.setAnalyticsConsent(true)
        await telemetry.setAnalyticsConsent(false)
        XCTAssertFalse(defaults.bool(forKey: KinetiqTelemetry.consentKey))
        XCTAssertFalse(telemetry.ready)
        XCTAssertFalse(telemetry.canChangeConsent)
        XCTAssertFalse(telemetry.enabled)
        await telemetry.shutdown()
    }

    func testKillSwitchPreservesConsentAndSuppressesCaptures() async throws {
        let (defaults, _) = try preferences()
        let provider = RecordingHostAnalytics()
        let telemetry = owner(defaults, provider: provider)
        await telemetry.initialize()
        await telemetry.setEnabled(false)
        await telemetry.setEnabled(true)
        XCTAssertFalse(telemetry.analyticsConsent)
        await telemetry.setAnalyticsConsent(true)
        await telemetry.setEnabled(false)
        XCTAssertTrue(defaults.bool(forKey: KinetiqTelemetry.consentKey))
        await telemetry.privacySettingsOpened()
        let calls = await provider.calls
        XCTAssertFalse(calls.contains("capture:feature_used"))
        XCTAssertFalse(calls.contains("flush"))
        await telemetry.shutdown()
    }

    func testConsentRemainsWithdrawableWhileKillSwitchIsOff() async throws {
        let (defaults, _) = try preferences()
        let provider = RecordingHostAnalytics()
        let telemetry = owner(defaults, provider: provider)
        await telemetry.initialize()
        await telemetry.setAnalyticsConsent(true)
        await telemetry.setEnabled(false)
        XCTAssertTrue(telemetry.canChangeConsent)
        await telemetry.setAnalyticsConsent(false)
        XCTAssertFalse(telemetry.analyticsConsent)
        XCTAssertFalse(defaults.bool(forKey: KinetiqTelemetry.consentKey))
        XCTAssertFalse(telemetry.canChangeConsent)
        await telemetry.setAnalyticsConsent(true)
        await telemetry.setEnabled(true)
        XCTAssertFalse(telemetry.analyticsConsent)
        let calls = await provider.calls
        XCTAssertEqual(calls.filter { $0 == "start" }.count, 1)
        XCTAssertFalse(calls.contains("flush"))
        await telemetry.shutdown()
    }

    func testQuitWaitsForGrantAndRepeatedShutdownStopsOnce() async throws {
        let (defaults, _) = try preferences()
        let provider = RecordingHostAnalytics(block: .start)
        let telemetry = owner(defaults, provider: provider)
        await telemetry.initialize()
        let grant = Task { await telemetry.setAnalyticsConsent(true) }
        await provider.waitUntilBlocked()
        let quit = Task { await telemetry.shutdown() }
        await Task.yield()
        await telemetry.privacySettingsOpened()
        await provider.release()
        await grant.value
        await quit.value
        await telemetry.shutdown()
        let calls = await provider.calls
        XCTAssertEqual(calls.filter { $0 == "stop:keep" }.count, 1)
        XCTAssertFalse(calls.contains("capture:feature_used"))
        XCTAssertFalse(telemetry.ready)
        XCTAssertFalse(telemetry.canChangeConsent)
    }

    func testInvalidHostConfigurationDeniesPersistedConsent() async throws {
        let (defaults, _) = try preferences()
        defaults.set(true, forKey: KinetiqTelemetry.consentKey)
        let provider = RecordingHostAnalytics()
        let telemetry = KinetiqTelemetry(defaults: defaults,
            configuration: .failure(TelemetryHostConfiguration.Invalid.configuration), provider: provider)
        await telemetry.initialize()
        XCTAssertFalse(telemetry.analyticsConsent)
        XCTAssertFalse(defaults.bool(forKey: KinetiqTelemetry.consentKey))
        let calls = await provider.calls
        XCTAssertTrue(calls.isEmpty)
        await telemetry.shutdown()
    }

    /// Validate the supplied client metadata without configuring or exposing Firebase options.
    func testFirebaseConfigurationLoadsRealMetadataWithoutConfiguringSingleton() throws {
        XCTAssertNil(FirebaseApp.app())
        let missing = try TelemetryHostConfiguration.load(file: nil)
        XCTAssertTrue(missing.options == nil)
        let url = try clientConfigurationURL()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let loaded = try TelemetryHostConfiguration.load(file: url)
        XCTAssertTrue(loaded.options != nil, "The supplied Firebase client metadata must validate")
        #if DEBUG
        XCTAssertEqual(missing.environment, .development)
        XCTAssertEqual(loaded.environment, .development)
        #else
        XCTAssertEqual(missing.environment, .production)
        XCTAssertEqual(loaded.environment, .production)
        #endif
        XCTAssertNil(FirebaseApp.app())
        let original = try Data(contentsOf: url)
        let metadata = try XCTUnwrap(PropertyListSerialization.propertyList(from: original, format: nil) as? [String: Any])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let invalid = directory.appendingPathComponent("GoogleService-Info.plist")
        for key in ["private_key", "ServiceAccount", "CLIENT_EMAIL", "client-x509-cert-url", "TOKEN_URI", "type"] {
            var modified = metadata
            modified["unknown"] = [[key: key == "type" ? "service_account" : "invalid"]]
            try PropertyListSerialization.data(fromPropertyList: modified, format: .xml, options: 0).write(to: invalid)
            XCTAssertThrowsError(try TelemetryHostConfiguration.load(file: invalid)) { error in
                XCTAssertTrue(error is TelemetryHostConfiguration.Invalid)
            }
            XCTAssertNil(FirebaseApp.app())
        }
        XCTAssertTrue(try Data(contentsOf: url) == original)
    }

    func testPreviousPostHogConsentDoesNotEnableFirebaseOrSuppressNewPrompt() async throws {
        let (defaults, _) = try preferences()
        let legacyConsent = "kinetiq.telemetry.analytics"
        let legacyDecision = "kinetiq.telemetry.analyticsDecision"
        defaults.set(true, forKey: legacyConsent)
        defaults.set(true, forKey: legacyDecision)
        XCTAssertEqual(KinetiqTelemetry.consentKey, "kinetiq.telemetry.firebase.analytics")
        XCTAssertEqual(KinetiqTelemetry.consentDecisionKey, "kinetiq.telemetry.firebase.analyticsDecision")
        let provider = RecordingHostAnalytics()
        let store = ContractIdentity()
        let telemetry = owner(defaults, provider: provider, store: store)
        XCTAssertFalse(telemetry.analyticsConsent)
        XCTAssertNil(defaults.object(forKey: KinetiqTelemetry.consentKey))
        await telemetry.initialize()
        XCTAssertTrue(telemetry.ready)
        XCTAssertTrue(telemetry.canChangeConsent)
        XCTAssertFalse(telemetry.analyticsConsent)
        XCTAssertFalse(defaults.bool(forKey: KinetiqTelemetry.consentKey))
        XCTAssertNil(defaults.object(forKey: KinetiqTelemetry.consentKey))
        XCTAssertNil(defaults.object(forKey: KinetiqTelemetry.consentDecisionKey))
        XCTAssertTrue(telemetry.shouldRequestConsentAtStartup)
        XCTAssertTrue(telemetry.claimStartupConsentPrompt())
        await telemetry.privacySettingsOpened()
        let calls = await provider.calls
        let accesses = await store.accesses
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(accesses, 0)
        await telemetry.shutdown()
        XCTAssertEqual(defaults.object(forKey: legacyConsent) as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: legacyDecision) as? Bool, true)
        XCTAssertNil(defaults.object(forKey: KinetiqTelemetry.consentKey))
        XCTAssertNil(defaults.object(forKey: KinetiqTelemetry.consentDecisionKey))
        XCTAssertNil(FirebaseApp.app())
    }

    func testNewFirebaseConsentDecisionPreservesPreviousPostHogKeysAcrossRestart() async throws {
        let (defaults, _) = try preferences()
        let legacyConsent = "kinetiq.telemetry.analytics"
        let legacyDecision = "kinetiq.telemetry.analyticsDecision"
        defaults.set(true, forKey: legacyConsent)
        defaults.set(true, forKey: legacyDecision)
        let provider = RecordingHostAnalytics()
        let telemetry = owner(defaults, provider: provider)
        await telemetry.initialize()
        XCTAssertTrue(telemetry.claimStartupConsentPrompt())
        await telemetry.setAnalyticsConsent(false)
        XCTAssertEqual(defaults.object(forKey: KinetiqTelemetry.consentKey) as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: KinetiqTelemetry.consentDecisionKey) as? Bool, true)
        await telemetry.shutdown()
        let restarted = owner(defaults, provider: provider)
        await restarted.initialize()
        XCTAssertFalse(restarted.analyticsConsent)
        XCTAssertFalse(restarted.claimStartupConsentPrompt())
        let calls = await provider.calls
        XCTAssertFalse(calls.contains("start"))
        XCTAssertFalse(calls.contains("flush"))
        await restarted.shutdown()
        XCTAssertEqual(defaults.object(forKey: legacyConsent) as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: legacyDecision) as? Bool, true)
        XCTAssertNil(FirebaseApp.app())
    }

    func testFirebaseOptionsOnlyProviderConstructionAndDisabledCoreDoNotConfigureSingleton() async throws {
        XCTAssertNil(FirebaseApp.app())
        let url = try clientConfigurationURL()
        let host = try TelemetryHostConfiguration.load(file: url)
        let options = try XCTUnwrap(host.options)
        let provider = FirebaseAnalyticsProvider(options: options)
        XCTAssertEqual(provider.name, "Google Firebase Analytics")
        XCTAssertNil(FirebaseApp.app())
        let store = ContractIdentity()
        let client = TelemetryClient(configuration: TelemetryConfiguration(
            productID: "kinetiq_disabled_" + UUID().uuidString.lowercased(), productName: "Kinetiq",
            enabled: false, privacy: PrivacySettings(analyticsEnabled: false,
                crashReportingEnabled: false, collectOSVersion: false, collectHardwareInfo: false),
            lifecycleTrackingEnabled: false), analyticsProvider: provider, identityStore: store)
        try await client.initialize()
        await client.track("feature_used", properties: ["feature": "privacy_settings"])
        await client.flush()
        let diagnostics = await client.diagnostics()
        let accesses = await store.accesses
        XCTAssertTrue(diagnostics.initialized)
        XCTAssertFalse(diagnostics.analyticsEnabled)
        XCTAssertFalse(diagnostics.analyticsAvailable)
        XCTAssertFalse(diagnostics.crashReportingEnabled)
        XCTAssertFalse(diagnostics.crashReportingAvailable)
        XCTAssertEqual(diagnostics.acceptedEvents, 0)
        XCTAssertEqual(accesses, 0)
        XCTAssertNil(FirebaseApp.app())
        await client.shutdown()
        XCTAssertNil(FirebaseApp.app())
    }

    /// The test executable is not the signed, safety-configured app. Never exercise a live grant.
    func testFirebaseProviderStartFailsSafetyGateBeforeConfiguringSingleton() throws {
        XCTAssertNil(FirebaseApp.app())
        let safeDefaults = FirebaseAnalyticsPolicy.safetyKeys.allSatisfy { key in
            guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? NSNumber,
                  CFGetTypeID(value) == CFBooleanGetTypeID() else { return false }
            return !value.boolValue
        }
        guard !safeDefaults else {
            XCTFail("This gate test must run in the unconfigured test executable, never the app bundle")
            return
        }
        let url = try clientConfigurationURL()
        let host = try TelemetryHostConfiguration.load(file: url)
        let provider = FirebaseAnalyticsProvider(options: try XCTUnwrap(host.options))
        let configuration = TelemetryConfiguration(productID: "kinetiq_gate", productName: "Kinetiq",
            enabled: false, privacy: PrivacySettings(analyticsEnabled: false), lifecycleTrackingEnabled: false)
        XCTAssertThrowsError(try provider.start(configuration: configuration, installationID: UUID())) { error in
            XCTAssertTrue(error is TelemetryHostConfiguration.Invalid)
        }
        XCTAssertNil(FirebaseApp.app())
    }

    func testFirebaseEventPolicyFiltersActualCoreEventsAndRejectsReservedOrUnapprovedEvents() async throws {
        XCTAssertNil(FirebaseApp.app())
        let provider = RecordingHostAnalytics()
        let client = TelemetryClient(configuration: TelemetryConfiguration(
            productID: "kinetiq_policy_" + UUID().uuidString.lowercased(), productName: "Kinetiq",
            privacy: PrivacySettings(analyticsEnabled: true, collectOSVersion: false,
                collectHardwareInfo: false, allowedPropertyKeys: ["feature"]),
            lifecycleTrackingEnabled: false), analyticsProvider: provider, identityStore: ContractIdentity())
        try await client.initialize()
        await client.track("feature_used", properties: ["feature": "privacy_settings"])
        await client.track("feature_used", properties: ["feature": "overview"])
        await client.track("feature_used", properties: ["feature": true])
        await client.track("feature_used")
        let unapproved = ["screen_viewed", "error_occurred", "firebase_feature", "google_feature", "ga_feature"]
        for name in unapproved {
            await client.track(name, properties: ["feature": "privacy_settings"])
        }
        let reserved = ["app_launched", "app_became_active", "app_entered_background", "app_terminated",
            "session_started", "session_ended", "installation_started", "previous_session_interrupted"]
        let before = await provider.events
        for name in reserved {
            await client.track(name, properties: ["feature": "privacy_settings"])
        }
        let events = await provider.events
        XCTAssertEqual(events, before, "Manual reserved events must not reach the recording boundary")
        XCTAssertEqual(events.count, 10)
        let installation = try XCTUnwrap(events.first)
        XCTAssertEqual(installation.name, "installation_started")
        XCTAssertNil(FirebaseAnalyticsPolicy.parameters(for: installation))
        let approved = try XCTUnwrap(events.first { $0.name == "feature_used" && $0.properties["feature"] == .string("privacy_settings") })
        XCTAssertNotNil(approved.properties["product_id"])
        XCTAssertEqual(approved.properties["platform"], .string("macOS"))
        XCTAssertGreaterThan(approved.properties.count, 1)
        XCTAssertEqual(FirebaseAnalyticsPolicy.parameters(for: approved), ["feature": "privacy_settings"])
        XCTAssertEqual(events.compactMap { FirebaseAnalyticsPolicy.parameters(for: $0) }, [["feature": "privacy_settings"]])
        for event in events where event != approved {
            XCTAssertNil(FirebaseAnalyticsPolicy.parameters(for: event))
        }
        // Reuse a real captured event's metadata/identity to test the independent adapter policy.
        for name in reserved + unapproved {
            let event = TelemetryEvent(id: approved.id, name: name, installationID: approved.installationID,
                timestamp: approved.timestamp, properties: approved.properties)
            XCTAssertNil(FirebaseAnalyticsPolicy.parameters(for: event))
        }
        let diagnostics = await client.diagnostics()
        XCTAssertEqual(diagnostics.acceptedEvents, events.count)
        XCTAssertEqual(diagnostics.droppedEvents, reserved.count)
        await client.shutdown()
        XCTAssertNil(FirebaseApp.app())
    }

    /// These are custom core parameters; Firebase automatic metadata is collected separately.
    func testApprovedCategoricalActionOnlyAndNoHardwareMetadata() async throws {
        let (defaults, _) = try preferences()
        let provider = RecordingHostAnalytics()
        let telemetry = owner(defaults, provider: provider)
        await telemetry.initialize()
        await telemetry.setAnalyticsConsent(true)
        await telemetry.privacySettingsOpened()
        let properties = await provider.featureProperties
        XCTAssertEqual(properties?["feature"], .string("privacy_settings"))
        for key in ["os_version", "macos_version", "hardware_model", "hardware_architecture", "window_title", "path"] {
            XCTAssertNil(properties?[key])
        }
        await telemetry.shutdown()
    }

    func testSingleTimerStopAndRevocationSuppressesPendingMeasurement() async throws {
        let provider = RecordingHostAnalytics()
        let client = TelemetryClient(configuration: TelemetryConfiguration(
            productID: "kinetiq_timer_" + UUID().uuidString.lowercased(), productName: "Kinetiq",
            privacy: PrivacySettings(analyticsEnabled: true, collectOSVersion: false,
                collectHardwareInfo: false, allowedPropertyKeys: ["operation", "duration_ms"]),
            lifecycleTrackingEnabled: false), analyticsProvider: provider, identityStore: ContractIdentity())
        try await client.initialize()
        let timer = client.startTimer("privacy_control")
        let first = await timer.stop()
        let second = await timer.stop()
        XCTAssertNotNil(first)
        XCTAssertNil(second)
        let pending = client.startTimer("privacy_control")
        try await client.setAnalyticsEnabled(false)
        await pending.stop()
        let calls = await provider.calls
        XCTAssertEqual(calls.filter { $0 == "capture:operation_measured" }.count, 1)
        XCTAssertFalse(calls.contains("flush"))
        await client.shutdown()
    }

    func testExistingSetupConstructorsDoNotCreateTelemetry() throws {
        let (defaults, _) = try preferences()
        let model = SetupModel(settings: Settings(defaults: defaults), closeEffectChanged: {}, startChaos: {},
            enabledChanged: {}, runtimeStatus: { ManagementRuntimeStatus(metalAvailable: false, eventTapRunning: false) })
        XCTAssertNil(model.telemetry)
        let controller = SetupWindowController(settings: Settings(defaults: defaults), closeEffectChanged: {},
            startChaos: {}, enabledChanged: {}, runtimeStatus: { ManagementRuntimeStatus(metalAvailable: false, eventTapRunning: false) })
        XCTAssertNil(controller.model.telemetry)
    }

    /// Mount the actual management shell: Overview must not emit the Settings action.
    func testNativeSettingsPageUsesRetainedOwnerAndDefaultOffConsent() async throws {
        guard CGSessionCopyCurrentDictionary() != nil, !NSScreen.screens.isEmpty else {
            throw XCTSkip("A graphical session is required for the owned Settings window")
        }
        let (defaults, _) = try preferences()
        let provider = RecordingHostAnalytics()
        let telemetry = owner(defaults, provider: provider)
        await telemetry.initialize()
        let settings = Settings(defaults: defaults)
        let controller = SetupWindowController(settings: settings, closeEffectChanged: {}, startChaos: {},
            enabledChanged: {}, runtimeStatus: { ManagementRuntimeStatus(metalAvailable: false, eventTapRunning: false) },
            telemetry: telemetry)
        XCTAssertTrue(controller.model.telemetry === telemetry)
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.finishLaunching()
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1180, height: 780),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        let hosting = NSHostingController(rootView: SetupView(model: controller.model))
        window.contentViewController = hosting
        window.orderFrontRegardless()
        defer { window.close() }
        func settle() async {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    hosting.view.layoutSubtreeIfNeeded()
                    window.displayIfNeeded()
                    continuation.resume()
                }
            }
        }
        await settle()
        XCTAssertFalse(telemetry.analyticsConsent)
        XCTAssertTrue(telemetry.canChangeConsent)
        await telemetry.setAnalyticsConsent(true)
        let before = await provider.calls
        XCTAssertFalse(before.contains("capture:feature_used"), "Startup displays Overview, not privacy settings")
        controller.model.requestedPage = .settings
        await settle()
        XCTAssertEqual(window.title, "Kinetiq — Settings")
        let opened = await provider.calls
        XCTAssertEqual(opened.filter { $0 == "capture:feature_used" }.count, 1)
        XCTAssertTrue(telemetry.canChangeConsent, "Active consent must remain withdrawable")
        await telemetry.setAnalyticsConsent(false)
        XCTAssertFalse(telemetry.analyticsConsent)
        XCTAssertEqual(settings.enabled, Settings(defaults: defaults).enabled)
        await telemetry.shutdown()
    }
}

private enum ContractFailure: Error { case unavailable }
private actor ContractIdentity: InstallationIdentityStore {
    private var identity: UUID?
    private let fail: Bool
    private(set) var accesses = 0
    init(fail: Bool = false) { self.fail = fail }
    func load() throws -> UUID? { accesses += 1; if fail { throw ContractFailure.unavailable }; return identity }
    func save(_ value: UUID) { accesses += 1; identity = value }
    func delete() { accesses += 1; identity = nil }
}

private actor RecordingHostAnalytics: AnalyticsProvider {
    enum Stage { case start, purge }
    nonisolated let name = "Host contract recording boundary"
    private let block: Stage?
    private let failStart: Bool
    private let preferenceSuite: String?
    private var didBlock = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var calls: [String] = []
    private(set) var consentAtPurge: Bool?
    private(set) var featureProperties: EventProperties?
    private(set) var events: [TelemetryEvent] = []
    init(block: Stage? = nil, failStart: Bool = false, preferenceSuite: String? = nil) {
        self.block = block; self.failStart = failStart; self.preferenceSuite = preferenceSuite
    }
    func start(configuration: TelemetryConfiguration, installationID: UUID) async throws {
        calls.append("start")
        await pause(.start)
        if failStart { throw ContractFailure.unavailable }
    }
    func capture(_ event: TelemetryEvent) {
        events.append(event)
        calls.append("capture:" + event.name)
        if event.name == "feature_used" { featureProperties = event.properties }
    }
    func flush() { calls.append("flush") }
    func stop(purge: Bool) async {
        calls.append(purge ? "stop:purge" : "stop:keep")
        if purge {
            if let preferenceSuite { consentAtPurge = UserDefaults(suiteName: preferenceSuite)?.bool(forKey: KinetiqTelemetry.consentKey) }
            await pause(.purge)
        }
    }
    private func pause(_ stage: Stage) async {
        guard block == stage, !didBlock else { return }
        didBlock = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let pending = waiters; waiters.removeAll(); pending.forEach { $0.resume() }
        }
    }
    func waitUntilBlocked() async {
        if didBlock { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() { continuation?.resume(); continuation = nil }
}