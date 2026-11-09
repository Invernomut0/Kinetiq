// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import Combine
import Foundation
import Invernomut0Telemetry
import FirebaseCore

/// Optional host metadata. Explicit native loading remains independent of GA4 selection.
struct TelemetryHostConfiguration {
    let options: FirebaseOptions?
    let environment: TelemetryEnvironment
    let ga4: GA4MeasurementProtocolConfiguration?

    init(options: FirebaseOptions?, environment: TelemetryEnvironment,
         ga4: GA4MeasurementProtocolConfiguration? = nil) {
        self.options = options
        self.environment = environment
        self.ga4 = ga4
    }

    enum Invalid: Error { case configuration }

    /// A present invalid GA4 resource throws; native credentials are never parsed when GA4 is selected.
    static func load(ga4File: URL? = GA4MeasurementProtocolConfiguration.defaultBundleURL) throws -> Self {
        if let ga4 = try GA4MeasurementProtocolConfiguration.load(file: ga4File) {
            return Self(options: nil, environment: buildEnvironment, ga4: ga4)
        }
        return try load(file: Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"))
    }

    private static var buildEnvironment: TelemetryEnvironment {
        #if DEBUG
        return .development
        #else
        return .production
        #endif
    }

    static func load(file: URL?) throws -> Self {
        let environment = buildEnvironment
        guard let file else { return Self(options: nil, environment: environment) }
        do {
            let stream = try FileHandle(forReadingFrom: file)
            defer { try? stream.close() }
            guard let data = try stream.read(upToCount: 65_537), data.count <= 65_536,
                  let metadata = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let appID = metadata["GOOGLE_APP_ID"] as? String,
                  let sender = metadata["GCM_SENDER_ID"] as? String,
                  let apiKey = metadata["API_KEY"] as? String,
                  appID.range(of: "^1:[0-9]+:ios:[0-9a-fA-F]+\\z", options: .regularExpression) != nil,
                  appID.split(separator: ":")[1] == sender,
                  apiKey.range(of: "^AIza[A-Za-z0-9_-]{35}\\z", options: .regularExpression) != nil,
                  metadata["PROJECT_ID"] as? String == "kinetiq-75593",
                  metadata["BUNDLE_ID"] as? String == "io.github.invernomut0.Kinetiq",
                  !containsAdministratorMetadata(metadata),
                  let options = FirebaseOptions(contentsOfFile: file.path) else { throw Invalid.configuration }
            return Self(options: options, environment: environment)
        } catch { throw Invalid.configuration }
    }

    /// Inspect nested metadata iteratively, without logging values or risking recursive traversal.
    private static func containsAdministratorMetadata(_ metadata: [String: Any]) -> Bool {
        var pending: [Any] = [metadata]
        while let value = pending.popLast() {
            if let dictionary = value as? [String: Any] {
                for (key, child) in dictionary {
                    let normalized = key.lowercased().replacingOccurrences(of: "-", with: "_")
                    if normalized.contains("private") || normalized.contains("service") ||
                        ["client_email", "client_x509_cert_url", "token_uri"].contains(normalized) ||
                        (normalized == "type" && child as? String == "service_account") { return true }
                    pending.append(child)
                }
            } else if let array = value as? [Any] {
                pending.append(contentsOf: array)
            }
        }
        return false
    }
}

/// One retained application owner; only approved categorical product actions cross this boundary.
/// Test constructors inject real core clients' storage/provider contracts, never a vendor singleton.
@MainActor
final class KinetiqTelemetry: ObservableObject {
    static weak var application: KinetiqTelemetry?
    nonisolated static let maximumPendingUsageTasks = 4
    nonisolated static let usageConsentRevision = 2
    nonisolated static let usageConsentRevisionKey = "kinetiq.telemetry.firebase.usageConsentRevision"
    nonisolated static let ga4UsageConsentRevisionKey = "kinetiq.telemetry.ga4.usageConsentRevision"
    nonisolated static let consentKey = "kinetiq.telemetry.firebase.analytics"
    nonisolated static let consentDecisionKey = "kinetiq.telemetry.firebase.analyticsDecision"
    nonisolated static let ga4ConsentKey = "kinetiq.telemetry.ga4.analytics"
    nonisolated static let ga4ConsentDecisionKey = "kinetiq.telemetry.ga4.analyticsDecision"
    enum Mode { case native, ga4 }
    let mode: Mode
    private var activeConsentKey: String { mode == .ga4 ? Self.ga4ConsentKey : Self.consentKey }
    private var activeDecisionKey: String { mode == .ga4 ? Self.ga4ConsentDecisionKey : Self.consentDecisionKey }
    private var activeRevisionKey: String { mode == .ga4 ? Self.ga4UsageConsentRevisionKey : Self.usageConsentRevisionKey }
    @Published private(set) var ready = false
    @Published private(set) var busy = false
    @Published private(set) var analyticsConsent = false
    @Published private(set) var enabled = true
    @Published private(set) var status = "Analytics not initialized"
    @Published private(set) var transportStatus = GA4MeasurementProtocolProvider.TransportStatus.stopped.message

    private let defaults: UserDefaults
    private let productID: String
    private let configuration: Result<TelemetryHostConfiguration, Error>
    private let injectedProvider: (any AnalyticsProvider)?
    private let identityStore: any InstallationIdentityStore
    private let purgeFailed: @Sendable () async -> Bool
    private var provider: (any AnalyticsProvider)?
    private var client: TelemetryClient?
    private var attemptedInitialization = false
    private var closing = false
    private var cleanedUp = false
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private var shutdownTask: Task<Void, Never>?
    private var startupPromptPresented = false
    private var needsUpdatedConsent = false
    private var usageTasks: [UUID: Task<Void, Never>] = [:]
    private var usageGeneration = UUID()

    var canChangeConsent: Bool { ready && !busy && !closing && (enabled || analyticsConsent) && provider != nil }

    /// Configuration failures are not a user decision; prompt once when analytics becomes available.
    var shouldRequestConsentAtStartup: Bool {
        guard canChangeConsent, enabled, !analyticsConsent, !startupPromptPresented else { return false }
        if needsUpdatedConsent { return true }
        guard let decision = defaults.object(forKey: activeDecisionKey) as? NSNumber,
              CFGetTypeID(decision) == CFBooleanGetTypeID() else { return true }
        return !decision.boolValue
    }

    /// Claim only when a real window can present the sheet; unanswered quits retry next launch.
    func claimStartupConsentPrompt() -> Bool {
        guard shouldRequestConsentAtStartup else { return false }
        startupPromptPresented = true
        return true
    }

    init(defaults: UserDefaults,
         configuration: Result<TelemetryHostConfiguration, Error>,
            productID: String = "kinetiq",
         provider: (any AnalyticsProvider)? = nil,
         identityStore: (any InstallationIdentityStore)? = nil,
         purgeFailed: @escaping @Sendable () async -> Bool = { false }) {
        self.defaults = defaults
        self.productID = productID
        self.configuration = configuration
        injectedProvider = provider
        let usesGA4: Bool
        switch configuration {
        case .success(let host): usesGA4 = host.ga4 != nil
        case .failure(let error): usesGA4 = error is GA4MeasurementProtocolConfiguration.Invalid
        }
        mode = usesGA4 ? .ga4 : .native
        self.identityStore = identityStore ?? TelemetryPreferenceIdentityStore(
            defaults: defaults, productID: usesGA4 ? productID + ".ga4" : productID)
        self.purgeFailed = purgeFailed
        // UserDefaults.bool accepts strings/numbers. Consent must be an actual plist Boolean.
        if let stored = defaults.object(forKey: activeConsentKey) as? NSNumber,
           CFGetTypeID(stored) == CFBooleanGetTypeID() {
            needsUpdatedConsent = stored.boolValue && (defaults.object(forKey: activeRevisionKey) as? Int) != Self.usageConsentRevision
            analyticsConsent = stored.boolValue && !needsUpdatedConsent
        }
    }

    static func forApplication() -> KinetiqTelemetry {
        let owner = KinetiqTelemetry(defaults: .standard,
                                    configuration: Result { try TelemetryHostConfiguration.load() })
        application = owner
        return owner
    }

    /// Product hooks never construct a client or enable analytics as a side effect.
    static func emit(_ event: KinetiqUsageEvent) { application?.record(event) }

    /// At most four immediate core submissions; denied/busy/overflow actions are never queued or replayed.
    func record(_ event: KinetiqUsageEvent) {
        guard ready, !busy, !closing, enabled, analyticsConsent,
              usageTasks.count < Self.maximumPendingUsageTasks, let client else { return }
        let properties: EventProperties = event.parameters.mapValues { .string($0) }
        guard KinetiqUsageEvent.approvedParameters(name: event.name, properties: properties) != nil else { return }
        let generation = usageGeneration
        let taskID = UUID()
        // MainActor isolation registers the task before its body can execute.
        usageTasks[taskID] = Task { [weak self] in
            guard let self else { return }
            defer { if self.usageGeneration == generation { self.usageTasks.removeValue(forKey: taskID) } }
            guard !Task.isCancelled, self.usageGeneration == generation,
                  !self.closing, self.enabled, self.analyticsConsent else { return }
            await client.track(event.name, properties: properties)
        }
    }

    private func cancelPendingUsage() {
        usageGeneration = UUID()
        for task in usageTasks.values { task.cancel() }
        usageTasks.removeAll()
    }

    /// Reserve initialization before suspension; repeated callers wait without making another client.
    func initialize() async {
        guard !closing else { return }
        if attemptedInitialization { await waitUntilIdle(); return }
        attemptedInitialization = true
        busy = true
        defer { finish() }
        do {
            let host = try configuration.get()
            provider = injectedProvider
            if provider == nil, let ga4 = host.ga4 {
                provider = GA4MeasurementProtocolProvider(configuration: ga4, statusChanged: { [weak self] status in
                    self?.transportStatus = status.message
                })
            } else if provider == nil, let options = host.options {
                guard FirebaseAnalyticsProvider.hasPrivateKeychainAccess else {
                    denyConsent()
                    ready = true
                    status = "Firebase unavailable: app-private Keychain signing required"
                    return
                }
                provider = FirebaseAnalyticsProvider(options: options)
            }
            if provider == nil { denyConsent() }
            let config = TelemetryConfiguration(productID: productID, productName: "Kinetiq",
                environment: host.environment, enabled: enabled,
                privacy: PrivacySettings(analyticsEnabled: analyticsConsent && provider != nil,
                    crashReportingEnabled: false, collectOSVersion: false, collectHardwareInfo: false,
                    allowedPropertyKeys: KinetiqUsageEvent.propertyKeys),
                lifecycleTrackingEnabled: false, allowProductionInDebugBuild: false)
            let owned = TelemetryClient(configuration: config, analyticsProvider: provider,
                                        identityStore: identityStore)
            client = owned
            try await owned.initialize()
            let diagnostics = await owned.diagnostics()
            guard !analyticsConsent || diagnostics.analyticsAvailable else { throw TelemetryHostConfiguration.Invalid.configuration }
            ready = true
            status = provider == nil ? "Analytics unavailable: configuration required" :
                (analyticsConsent ? "Analytics consent granted" :
                    needsUpdatedConsent ? "Analytics off: updated product-usage consent required" : "Analytics off: consent required")
        } catch { await failClosed() }
    }

    /// Persist withdrawal before vendor cleanup, grants only after successful provider startup.
    func setAnalyticsConsent(_ granted: Bool) async {
        guard canChangeConsent, !granted || enabled, let client else { return }
        cancelPendingUsage()
        defaults.set(true, forKey: activeDecisionKey)
        busy = true
        defer { finish() }
        if !granted { denyConsent() }
        do {
            try await client.setAnalyticsEnabled(granted)
            if !granted, await hasPurgeFailure() { await failClosed(); return }
            let diagnostics = await client.diagnostics()
            guard !granted || diagnostics.analyticsAvailable else { throw TelemetryHostConfiguration.Invalid.configuration }
            defaults.set(Self.usageConsentRevision, forKey: activeRevisionKey)
            needsUpdatedConsent = false
            analyticsConsent = granted
            defaults.set(granted, forKey: activeConsentKey)
            status = granted ? "Analytics consent granted" : "Analytics consent withdrawn"
        } catch { await failClosed() }
    }

    /// Called by the displayed Settings section, never startup/Overview or per-window lifecycle.
    func privacySettingsOpened() async {
        guard ready, !busy, !closing, enabled, analyticsConsent, let client else { return }
        busy = true
        defer { finish() }
        await client.track("feature_used", properties: ["feature": "privacy_settings"])
    }

    /// Independent runtime kill switch; re-enabling never invents persisted consent.
    func setEnabled(_ value: Bool) async {
        guard ready, !busy, !closing, let client else { return }
        cancelPendingUsage()
        busy = true
        defer { finish() }
        enabled = value
        do {
            try await client.setEnabled(value)
            if !value, await hasPurgeFailure() { await failClosed(); return }
            status = value ? (analyticsConsent ? "Analytics consent granted" : "Analytics off: consent required") : "Analytics paused"
        } catch { await failClosed() }
    }

    private func hasPurgeFailure() async -> Bool {
        return await purgeFailed()
    }

    private func denyConsent() {
        analyticsConsent = false
        defaults.set(false, forKey: activeConsentKey)
    }

    private func failClosed() async {
        cancelPendingUsage()
        denyConsent()
        closing = true
        ready = false
        enabled = false
        if let client { try? await client.setEnabled(false); await client.shutdown() }
        // No provider is constructed on invalid configuration; cleanup is restricted to our owner.
        await provider?.stop(purge: true)
        cleanedUp = true
        status = "Analytics stopped; product features remain available"
    }

    private func waitUntilIdle() async {
        if busy { await withCheckedContinuation { idleWaiters.append($0) } }
    }

    private func finish() {
        busy = false
        let waiters = idleWaiters
        idleWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    /// Single serialized shutdown. The AppKit delegate supplies a best-effort external deadline.
    func shutdown() async {
        if let shutdownTask { await shutdownTask.value; return }
        cancelPendingUsage()
        closing = true
        let task = Task { @MainActor in
            await waitUntilIdle()
            if !cleanedUp { await client?.shutdown(); cleanedUp = true }
            ready = false
            status = "Analytics stopped"
        }
        shutdownTask = task
        await task.value
    }
}