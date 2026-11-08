// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import FirebaseCore
import Foundation
import Invernomut0Telemetry
import XCTest
@testable import Kinetiq

/// Offline contracts only. Owner credentials stay in memory and never appear in assertions.
/// No test grants owner consent, submits an approved event or contacts a GA4 endpoint.
@MainActor
final class GA4MeasurementProtocolTests: XCTestCase {
    private func ownerResource() throws -> URL {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let candidates = [GA4MeasurementProtocolConfiguration.defaultBundleURL,
            root.appendingPathComponent("build/Kinetiq.app/Contents/Resources/KinetiqGA4Configuration.plist"),
            root.appendingPathComponent("KinetiqGA4Configuration.plist")].compactMap { $0 }
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw XCTSkip("Owner-supplied bundled GA4 Web configuration is unavailable; no credentials are fabricated")
        }
        return url
    }

    private func realConfiguration() throws -> GA4MeasurementProtocolConfiguration {
        try XCTUnwrap(GA4MeasurementProtocolConfiguration.load(file: ownerResource()))
    }

    private func preferences() throws -> UserDefaults {
        let suite = "kinetiq.ga4.contract." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func temporaryFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("invalid.plist")
    }

    private func approvedAction(clientID: UUID) -> TelemetryEvent {
        // Newly generated Web test identity, not a fabricated Firebase app-instance identifier.
        TelemetryEvent(name: "feature_used", installationID: clientID,
                       properties: ["feature": "privacy_settings"])
    }

    /// Real CPU work and monotonic elapsed time, never a sleep, injected clock or invented duration.
    private func performRealCPUWork() {
        let clock = ContinuousClock()
        let start = clock.now
        var hasher = Hasher()
        var iterations = 0
        repeat {
            iterations += 1
            hasher.combine(iterations)
        } while start.duration(to: clock.now) < .milliseconds(2)
        _ = hasher.finalize()
        XCTAssertGreaterThan(iterations, 0)
    }

    /// Exercises the interval helper at actual execution boundaries, without activating another app.
    private func measuredForegroundTiming() throws -> GA4EventTiming {
        var measurement = GA4ForegroundMeasurement()
        measurement.start(isForeground: false)
        measurement.setForeground(true)
        performRealCPUWork()
        measurement.setForeground(false)
        return try XCTUnwrap(measurement.takeApprovedActionTiming())
    }

    func testForegroundMeasurementRequiresConsentedStartAndClearsOnStop() throws {
        var measurement = GA4ForegroundMeasurement()
        measurement.setForeground(true)
        performRealCPUWork()
        XCTAssertFalse(measurement.isMeasuringForeground)
        XCTAssertNil(measurement.sessionID)
        XCTAssertNil(measurement.takeApprovedActionTiming())

        measurement.start(isForeground: false)
        performRealCPUWork()
        XCTAssertNil(try XCTUnwrap(measurement.takeApprovedActionTiming()).engagementTimeMilliseconds)
        measurement.setForeground(true)
        XCTAssertTrue(measurement.isMeasuringForeground)
        performRealCPUWork()
        measurement.setForeground(false)
        let timing = try XCTUnwrap(measurement.takeApprovedActionTiming())
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(timing.engagementTimeMilliseconds), 2)
        performRealCPUWork()
        XCTAssertNil(try XCTUnwrap(measurement.takeApprovedActionTiming()).engagementTimeMilliseconds,
                     "Background time and already-consumed foreground time must not be reported")
        measurement.setForeground(true)
        performRealCPUWork()
        measurement.stop()
        XCTAssertNil(measurement.sessionID)
        XCTAssertFalse(measurement.isMeasuringForeground)
        XCTAssertNil(measurement.takeApprovedActionTiming())
        measurement.setForeground(true)
        XCTAssertFalse(measurement.isMeasuringForeground)
        measurement.start(isForeground: false)
        XCTAssertNil(try XCTUnwrap(measurement.takeApprovedActionTiming()).engagementTimeMilliseconds)
        measurement.stop()
    }

    func testSessionUsesActualDateAndForegroundIntervalsStayWithinActualElapsedTime() throws {
        let before = Int64(Date().timeIntervalSince1970.rounded(.down))
        let clock = ContinuousClock()
        let start = clock.now
        var measurement = GA4ForegroundMeasurement()
        measurement.start(isForeground: true)
        performRealCPUWork()
        // Repeated active boundaries must not discard or restart the existing interval.
        measurement.setForeground(true)
        performRealCPUWork()
        measurement.setForeground(false)
        let first = try XCTUnwrap(measurement.takeApprovedActionTiming())
        let elapsed = start.duration(to: clock.now).components
        let actualMilliseconds = elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000
        let after = Int64(Date().timeIntervalSince1970.rounded(.down))
        XCTAssertGreaterThanOrEqual(first.sessionID, before)
        XCTAssertLessThanOrEqual(first.sessionID, after)
        XCTAssertGreaterThan(first.sessionID, 0)
        let foreground = try XCTUnwrap(first.engagementTimeMilliseconds)
        XCTAssertGreaterThanOrEqual(foreground, 4)
        XCTAssertLessThanOrEqual(foreground, actualMilliseconds)
        measurement.setForeground(true)
        performRealCPUWork()
        let second = try XCTUnwrap(measurement.takeApprovedActionTiming())
        XCTAssertEqual(second.sessionID, first.sessionID)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(second.engagementTimeMilliseconds), 2)
        measurement.stop()
    }

    func testPureRequestAddsOnlyActualMeasuredWebTimingAndStillDropsPrivateProperties() throws {
        let configuration = try realConfiguration()
        let timing = try measuredForegroundTiming()
        let clientID = UUID()
        let action = approvedAction(clientID: clientID)
        var properties = action.properties
        properties["session_id"] = .string(String(timing.sessionID))
        properties["engagement_time_msec"] = .string(String(try XCTUnwrap(timing.engagementTimeMilliseconds)))
        properties["path"] = .string(#filePath)
        properties["os_version"] = .string(ProcessInfo.processInfo.operatingSystemVersionString)
        let enriched = TelemetryEvent(id: action.id, name: action.name, installationID: clientID,
                                      timestamp: action.timestamp, properties: properties)
        let request = try XCTUnwrap(GA4MeasurementProtocolProvider.makeRequest(
            configuration: configuration, clientID: clientID, event: enriched, timing: timing))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(Set(payload.keys), ["client_id", "consent", "events"])
        XCTAssertTrue(payload["client_id"] as? String == GA4MeasurementProtocolProvider.webClientID(for: clientID))
        XCTAssertEqual(payload["consent"] as? [String: String],
                       ["ad_user_data": "DENIED", "ad_personalization": "DENIED"])
        let events = try XCTUnwrap(payload["events"] as? [[String: Any]])
        XCTAssertEqual(events.count, 1)
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(Set(event.keys), ["name", "params"])
        XCTAssertEqual(event["name"] as? String, "feature_used")
        let parameters = try XCTUnwrap(event["params"] as? [String: Any])
        XCTAssertEqual(Set(parameters.keys), ["feature", "session_id", "engagement_time_msec"])
        XCTAssertEqual(parameters["feature"] as? String, "privacy_settings")
        XCTAssertEqual((parameters["session_id"] as? NSNumber)?.int64Value, timing.sessionID)
        XCTAssertEqual((parameters["engagement_time_msec"] as? NSNumber)?.int64Value, timing.engagementTimeMilliseconds)
        let withoutTiming = try XCTUnwrap(GA4MeasurementProtocolProvider.makeRequest(
            configuration: configuration, clientID: clientID, event: enriched))
        let plain = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(withoutTiming.httpBody)) as? [String: Any])
        let plainEvents = try XCTUnwrap(plain["events"] as? [[String: Any]])
        XCTAssertEqual(plainEvents.first?["params"] as? [String: String], ["feature": "privacy_settings"])
    }

    func testPureBuilderOmitsUnmeasuredEngagementAndRejectsInvalidTiming() throws {
        let configuration = try realConfiguration()
        var measurement = GA4ForegroundMeasurement()
        measurement.start(isForeground: false)
        let timing = try XCTUnwrap(measurement.takeApprovedActionTiming())
        XCTAssertNil(timing.engagementTimeMilliseconds)
        let clientID = UUID()
        let action = approvedAction(clientID: clientID)
        let request = try XCTUnwrap(GA4MeasurementProtocolProvider.makeRequest(
            configuration: configuration, clientID: clientID, event: action, timing: timing))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        let events = try XCTUnwrap(payload["events"] as? [[String: Any]])
        let parameters = try XCTUnwrap(events.first?["params"] as? [String: Any])
        XCTAssertEqual(Set(parameters.keys), ["feature", "session_id"])
        XCTAssertEqual((parameters["session_id"] as? NSNumber)?.int64Value, timing.sessionID)
        for invalid in [GA4EventTiming(sessionID: 0, engagementTimeMilliseconds: nil),
                        GA4EventTiming(sessionID: -1, engagementTimeMilliseconds: nil),
                        GA4EventTiming(sessionID: timing.sessionID, engagementTimeMilliseconds: 0),
                        GA4EventTiming(sessionID: timing.sessionID, engagementTimeMilliseconds: -1)] {
            XCTAssertTrue(try GA4MeasurementProtocolProvider.makeRequest(configuration: configuration,
                clientID: clientID, event: action, timing: invalid) == nil)
        }
        measurement.stop()
    }

    func testPureHTTPStatusMeansRequestAcceptedNotIngestionConfirmed() {
        for code in 200...299 {
            let status = GA4MeasurementProtocolProvider.makeStatusHTTP(code)
            XCTAssertEqual(status, .requestAccepted(statusCode: code))
            XCTAssertTrue(status.message.contains("request accepted"))
            XCTAssertTrue(status.message.contains("ingestion not confirmed"))
        }
        for code in [100, 199, 300, 302, 400, 401, 403, 429, 500, 599] {
            XCTAssertEqual(GA4MeasurementProtocolProvider.makeStatusHTTP(code), .httpRejected(statusCode: code))
        }
        for code in [Int.min, -1, 0, 99, 600, Int.max] {
            XCTAssertEqual(GA4MeasurementProtocolProvider.makeStatusHTTP(code), .invalidResponse)
        }
    }

    func testTransportStatusMessagesExposeOnlyCategoriesCountsAndHTTPCode() {
        let statuses: [GA4MeasurementProtocolProvider.TransportStatus] = [
            .stopped, .ready, .submitting(submitted: 1, inFlight: 1), .requestAccepted(statusCode: 204),
            .httpRejected(statusCode: 403), .networkFailed, .invalidResponse,
            .droppedAtCapacity(inFlight: 4), .droppedInvalidEvent
        ]
        for status in statuses {
            XCTAssertTrue(status.message.hasPrefix("GA4 "))
            for forbidden in ["https:", "http:", "?", "api_secret", "measurement_id", "client_id", "UUID", #filePath] {
                XCTAssertFalse(status.message.contains(forbidden))
            }
        }
        XCTAssertEqual(GA4MeasurementProtocolProvider.TransportStatus.networkFailed.message,
                       "GA4 network request failed; no retry")
    }

    func testProviderRegistersObserversOnlyAfterConsentAndReportsLocalStartStop() async throws {
        var changes: [GA4MeasurementProtocolProvider.TransportStatus] = []
        let provider = GA4MeasurementProtocolProvider(configuration: try realConfiguration(),
                                                      statusChanged: { changes.append($0) })
        XCTAssertEqual(provider.foregroundObserverCount, 0)
        XCTAssertEqual(provider.transportStatus, .stopped)
        XCTAssertTrue(changes.isEmpty)
        let clientID = UUID()
        let configuration = TelemetryConfiguration(productID: "kinetiq_ga4_observers_" + UUID().uuidString.lowercased(),
            productName: "Kinetiq", privacy: PrivacySettings(analyticsEnabled: true,
                collectOSVersion: false, collectHardwareInfo: false), lifecycleTrackingEnabled: false)
        try await provider.start(configuration: configuration, installationID: clientID)
        XCTAssertEqual(provider.foregroundObserverCount, 2)
        XCTAssertEqual(provider.transportStatus, .ready)
        XCTAssertEqual(changes, [.stopped, .ready])
        await provider.flush()
        performRealCPUWork()
        XCTAssertEqual(provider.submittedRequests, 0)
        XCTAssertEqual(provider.inFlightRequests, 0)
        XCTAssertEqual(provider.transportStatus, .ready)
        await provider.stop(purge: true)
        XCTAssertEqual(provider.foregroundObserverCount, 0)
        XCTAssertEqual(provider.transportStatus, .stopped)
        XCTAssertEqual(changes, [.stopped, .ready, .stopped])
        try await provider.start(configuration: configuration, installationID: clientID)
        XCTAssertEqual(provider.foregroundObserverCount, 2)
        await provider.stop(purge: false)
        XCTAssertEqual(provider.foregroundObserverCount, 0)
        XCTAssertEqual(provider.submittedRequests, 0)
        XCTAssertEqual(provider.inFlightRequests, 0)
        XCTAssertEqual(changes, [.stopped, .ready, .stopped, .stopped, .ready, .stopped])
    }

    func testAbsentResourceIsOptionalAndExistingNativeInitializerIsPreserved() throws {
        XCTAssertTrue(try GA4MeasurementProtocolConfiguration.load(file: nil) == nil)
        let native = try TelemetryHostConfiguration.load(file: nil)
        XCTAssertTrue(native.options == nil)
        XCTAssertTrue(native.ga4 == nil)
        let constructed = TelemetryHostConfiguration(options: nil, environment: .development)
        XCTAssertTrue(constructed.ga4 == nil)
    }

    func testInvalidPresentResourceNeverFallsBackToFirebase() throws {
        let file = try temporaryFile()
        try Data().write(to: file)
        XCTAssertThrowsError(try TelemetryHostConfiguration.load(ga4File: file)) { error in
            XCTAssertTrue(error is GA4MeasurementProtocolConfiguration.Invalid)
        }
        try Data(repeating: 0, count: 65_537).write(to: file)
        XCTAssertThrowsError(try GA4MeasurementProtocolConfiguration.load(file: file)) { error in
            XCTAssertTrue(error is GA4MeasurementProtocolConfiguration.Invalid)
        }
        try FileManager.default.removeItem(at: file)
        XCTAssertThrowsError(try TelemetryHostConfiguration.load(ga4File: file))
    }

    func testTypedAllowlistAndInvalidFormatsUsingOwnerMetadata() throws {
        let real = try realConfiguration()
        let original: [String: Any] = ["measurement_id": real.measurementID, "api_secret": real.apiSecret]
        func reject(_ values: [String: Any]) throws {
            let data = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
            XCTAssertThrowsError(try GA4MeasurementProtocolConfiguration(data: data)) { error in
                XCTAssertTrue(error is GA4MeasurementProtocolConfiguration.Invalid)
            }
        }
        for value: Any in [true, 1, "", "g-invalid", "G-", "G-INVALID\n", "G-INVALID/", "G-é",
                  "G-REPLACE", "G-PLACEHOLDER", "G-" + String(repeating: "A", count: 255)] {
            var invalid = original
            invalid["measurement_id"] = value
            try reject(invalid)
        }
        for value: Any in [true, 1, "", "REPLACE_WITH_API_SECRET", "placeholder", "CHANGE_ME",
                           "YOUR_API_SECRET", "invalid secret", "invalid/secret", "invalid+secret",
                           "invalid\n", "é", String(repeating: "x", count: 257)] {
            var invalid = original
            invalid["api_secret"] = value
            try reject(invalid)
        }
        for key in ["measurement_id", "api_secret"] {
            var invalid = original
            invalid.removeValue(forKey: key)
            try reject(invalid)
        }
        var administrator = original
        administrator["private_key"] = "invalid"
        try reject(administrator)
        try reject(["configuration": original])
        XCTAssertThrowsError(try GA4MeasurementProtocolConfiguration(data: Data(repeating: 0, count: 65_537)))
    }

    func testOwnerResourceSelectsGA4WithoutNativeOptionsOrSingleton() throws {
        XCTAssertNil(FirebaseApp.app())
        let host = try TelemetryHostConfiguration.load(ga4File: ownerResource())
        XCTAssertTrue(host.ga4 != nil)
        XCTAssertTrue(host.options == nil)
        XCTAssertNil(FirebaseApp.app())
    }

    func testPureWebRequestContainsOnlyApprovedActionAndDeniedAdvertisingConsent() throws {
        let configuration = try realConfiguration()
        let clientID = UUID()
        let request = try XCTUnwrap(GA4MeasurementProtocolProvider.makeRequest(
            configuration: configuration, clientID: clientID, event: approvedAction(clientID: clientID)))
        let components = try XCTUnwrap(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "www.google-analytics.com")
        XCTAssertEqual(components.path, "/mp/collect")
        XCTAssertNil(components.user)
        XCTAssertNil(components.password)
        let query = components.queryItems ?? []
        XCTAssertEqual(Set(query.map(\.name)), ["measurement_id", "api_secret"])
        XCTAssertEqual(query.count, 2)
        // Boolean comparisons intentionally prevent XCTest from printing ingestion credentials.
        XCTAssertTrue(query.first { $0.name == "measurement_id" }?.value == configuration.measurementID)
        XCTAssertTrue(query.first { $0.name == "api_secret" }?.value == configuration.apiSecret)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.timeoutInterval, 8)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        let body = try XCTUnwrap(request.httpBody)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(Set(payload.keys), ["client_id", "consent", "events"])
        XCTAssertTrue(payload["client_id"] as? String == GA4MeasurementProtocolProvider.webClientID(for: clientID))
        XCTAssertTrue(payload["client_id"] as? String != clientID.uuidString)
        XCTAssertEqual(payload["consent"] as? [String: String],
                       ["ad_user_data": "DENIED", "ad_personalization": "DENIED"])
        let events = try XCTUnwrap(payload["events"] as? [[String: Any]])
        XCTAssertEqual(events.count, 1)
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(Set(event.keys), ["name", "params"])
        XCTAssertEqual(event["name"] as? String, "feature_used")
        XCTAssertEqual(event["params"] as? [String: String], ["feature": "privacy_settings"])
    }

    func testPureFilterDropsAdditionalPropertiesAndUnapprovedEvents() throws {
        let configuration = try realConfiguration()
        let action = approvedAction(clientID: UUID())
        var properties = action.properties
        // Actual core metadata is never part of the outgoing payload.
        properties["product_id"] = "kinetiq"
        properties["platform"] = "macOS"
        properties["path"] = .string(#filePath)
        properties["os_version"] = .string(ProcessInfo.processInfo.operatingSystemVersionString)
        let enriched = TelemetryEvent(id: action.id, name: action.name, installationID: action.installationID,
                                      timestamp: action.timestamp, properties: properties)
        let plain = try GA4MeasurementProtocolProvider.makeRequest(configuration: configuration,
            clientID: action.installationID, event: action)
        let filtered = try GA4MeasurementProtocolProvider.makeRequest(configuration: configuration,
            clientID: action.installationID, event: enriched)
        let plainJSON = try JSONSerialization.jsonObject(with: XCTUnwrap(plain?.httpBody)) as? NSDictionary
        let filteredJSON = try JSONSerialization.jsonObject(with: XCTUnwrap(filtered?.httpBody)) as? NSDictionary
        XCTAssertTrue(plainJSON == filteredJSON)
        for name in ["installation_started", "app_launched", "session_started", "screen_viewed", "ga_feature"] {
            let event = TelemetryEvent(id: action.id, name: name, installationID: action.installationID,
                                      timestamp: action.timestamp, properties: action.properties)
            XCTAssertTrue(try GA4MeasurementProtocolProvider.makeRequest(configuration: configuration,
                clientID: action.installationID, event: event) == nil)
        }
        for properties: EventProperties in [[:], ["feature": true], ["feature": "overview"]] {
            let event = TelemetryEvent(name: "feature_used", installationID: action.installationID, properties: properties)
            XCTAssertTrue(try GA4MeasurementProtocolProvider.makeRequest(configuration: configuration,
                clientID: action.installationID, event: event) == nil)
        }
        XCTAssertTrue(try GA4MeasurementProtocolProvider.makeRequest(configuration: configuration,
            clientID: UUID(), event: action) == nil)
    }

    func testWebClientIdentityUsesStableNumericFormatInsteadOfHyphenatedUUID() {
        let identity = UUID()
        let encoded = GA4MeasurementProtocolProvider.webClientID(for: identity)
        XCTAssertTrue(encoded.range(of: "^[0-9]{1,10}\\.[0-9]{1,10}\\z", options: .regularExpression) != nil)
        XCTAssertTrue(encoded == GA4MeasurementProtocolProvider.webClientID(for: identity))
        XCTAssertTrue(encoded != identity.uuidString)
    }

    func testProviderStartFlushAndStoppedCapturesNeverSubmit() async throws {
        XCTAssertNil(FirebaseApp.app())
        let provider = GA4MeasurementProtocolProvider(configuration: try realConfiguration())
        let clientID = UUID()
        let action = approvedAction(clientID: clientID)
        await provider.capture(action)
        XCTAssertEqual(provider.submittedRequests, 0)
        let configuration = TelemetryConfiguration(productID: "kinetiq_ga4_test_" + UUID().uuidString.lowercased(),
            productName: "Kinetiq", privacy: PrivacySettings(analyticsEnabled: true,
                collectOSVersion: false, collectHardwareInfo: false), lifecycleTrackingEnabled: false)
        try await provider.start(configuration: configuration, installationID: clientID)
        await provider.flush()
        XCTAssertEqual(provider.submittedRequests, 0)
        XCTAssertEqual(provider.inFlightRequests, 0)
        await provider.stop(purge: true)
        await provider.capture(action)
        await provider.flush()
        XCTAssertEqual(provider.submittedRequests, 0)
        XCTAssertEqual(provider.inFlightRequests, 0)
        try await provider.start(configuration: configuration, installationID: clientID)
        await provider.stop(purge: false)
        await provider.stop(purge: true)
        await provider.capture(action)
        XCTAssertEqual(provider.submittedRequests, 0)
        XCTAssertNil(FirebaseApp.app())
    }

    func testProviderRequiresBothEnabledAndAnalyticsConsent() async throws {
        let provider = GA4MeasurementProtocolProvider(configuration: try realConfiguration())
        for (enabled, consent) in [(false, false), (false, true), (true, false)] {
            let configuration = TelemetryConfiguration(productID: "kinetiq_ga4_gate", productName: "Kinetiq",
                enabled: enabled, privacy: PrivacySettings(analyticsEnabled: consent), lifecycleTrackingEnabled: false)
            do {
                try await provider.start(configuration: configuration, installationID: UUID())
                XCTFail("Disabled or unconsented startup must fail closed")
            } catch { XCTAssertTrue(error is GA4MeasurementProtocolConfiguration.Invalid) }
            XCTAssertEqual(provider.foregroundObserverCount, 0)
            XCTAssertEqual(provider.transportStatus, .stopped)
        }
        XCTAssertEqual(provider.submittedRequests, 0)
        XCTAssertEqual(provider.inFlightRequests, 0)
    }

    func testOwnerDefaultOffIgnoresPreviousConsentDecisionAndIdentity() async throws {
        let host = try TelemetryHostConfiguration.load(ga4File: ownerResource())
        let defaults = try preferences()
        let productID = "kinetiq_ga4_owner_" + UUID().uuidString.lowercased()
        defaults.set(true, forKey: KinetiqTelemetry.consentKey)
        defaults.set(true, forKey: KinetiqTelemetry.consentDecisionKey)
        defaults.set(true, forKey: "kinetiq.telemetry.analytics")
        defaults.set(true, forKey: "kinetiq.telemetry.analyticsDecision")
        let nativeKey = TelemetryPreferenceIdentityStore.preferenceKey(productID: productID)
        let ga4Key = TelemetryPreferenceIdentityStore.preferenceKey(productID: productID + ".ga4")
        let previousID = UUID().uuidString
        defaults.set(previousID, forKey: nativeKey)
        let telemetry = KinetiqTelemetry(defaults: defaults, configuration: .success(host), productID: productID)
        XCTAssertTrue(telemetry.mode == .ga4)
        XCTAssertFalse(telemetry.analyticsConsent)
        await telemetry.initialize()
        XCTAssertTrue(telemetry.ready)
        XCTAssertTrue(telemetry.canChangeConsent, "GA4 must not require the native Keychain signing gate")
        XCTAssertTrue(telemetry.shouldRequestConsentAtStartup)
        await telemetry.privacySettingsOpened()
        XCTAssertNil(defaults.object(forKey: ga4Key))
        XCTAssertNil(defaults.object(forKey: KinetiqTelemetry.ga4ConsentKey))
        XCTAssertNil(defaults.object(forKey: KinetiqTelemetry.ga4ConsentDecisionKey))
        XCTAssertTrue(defaults.string(forKey: nativeKey) == previousID)
        XCTAssertTrue(defaults.bool(forKey: KinetiqTelemetry.consentKey))
        XCTAssertTrue(defaults.bool(forKey: "kinetiq.telemetry.analytics"))
        await telemetry.shutdown()
        XCTAssertNil(FirebaseApp.app())
    }

    func testInvalidGA4OwnerRevokesOnlyGA4Consent() async throws {
        let defaults = try preferences()
        defaults.set(true, forKey: KinetiqTelemetry.ga4ConsentKey)
        defaults.set(true, forKey: KinetiqTelemetry.consentKey)
        let telemetry = KinetiqTelemetry(defaults: defaults,
            configuration: .failure(GA4MeasurementProtocolConfiguration.Invalid.configuration))
        await telemetry.initialize()
        XCTAssertTrue(telemetry.mode == .ga4)
        XCTAssertFalse(telemetry.ready)
        XCTAssertFalse(telemetry.analyticsConsent)
        XCTAssertFalse(defaults.bool(forKey: KinetiqTelemetry.ga4ConsentKey))
        XCTAssertTrue(defaults.bool(forKey: KinetiqTelemetry.consentKey))
        await telemetry.shutdown()
        XCTAssertNil(FirebaseApp.app())
    }

    func testGA4GrantCreatesSeparateIdentityAndRevocationPreservesNativePreferences() async throws {
        let host = try TelemetryHostConfiguration.load(ga4File: ownerResource())
        let defaults = try preferences()
        let productID = "kinetiq_ga4_grant_" + UUID().uuidString.lowercased()
        let nativeKey = TelemetryPreferenceIdentityStore.preferenceKey(productID: productID)
        let ga4Key = TelemetryPreferenceIdentityStore.preferenceKey(productID: productID + ".ga4")
        let previousID = UUID().uuidString
        defaults.set(previousID, forKey: nativeKey)
        defaults.set(true, forKey: KinetiqTelemetry.consentKey)
        let telemetry = KinetiqTelemetry(defaults: defaults, configuration: .success(host), productID: productID)
        await telemetry.initialize()
        XCTAssertEqual(telemetry.transportStatus, GA4MeasurementProtocolProvider.TransportStatus.stopped.message)
        // Only isolated test preferences are granted. Startup emits no approved feature action.
        await telemetry.setAnalyticsConsent(true)
        XCTAssertEqual(telemetry.transportStatus, GA4MeasurementProtocolProvider.TransportStatus.ready.message)
        XCTAssertTrue(telemetry.analyticsConsent)
        XCTAssertTrue(defaults.bool(forKey: KinetiqTelemetry.ga4ConsentKey))
        XCTAssertTrue(defaults.bool(forKey: KinetiqTelemetry.ga4ConsentDecisionKey))
        XCTAssertTrue(defaults.string(forKey: ga4Key) != nil)
        XCTAssertTrue(defaults.string(forKey: ga4Key) != previousID)
        await telemetry.setAnalyticsConsent(false)
        XCTAssertEqual(telemetry.transportStatus, GA4MeasurementProtocolProvider.TransportStatus.stopped.message)
        XCTAssertFalse(telemetry.analyticsConsent)
        XCTAssertFalse(defaults.bool(forKey: KinetiqTelemetry.ga4ConsentKey))
        XCTAssertTrue(defaults.bool(forKey: KinetiqTelemetry.consentKey))
        XCTAssertTrue(defaults.string(forKey: nativeKey) == previousID)
        await telemetry.privacySettingsOpened()
        await telemetry.shutdown()
        XCTAssertNil(FirebaseApp.app())
    }

    func testGA4BooleanOnlyConsentAndIndependentDecision() async throws {
        let host = try TelemetryHostConfiguration.load(ga4File: ownerResource())
        for value: Any in ["true", "YES", 1, 0] {
            let defaults = try preferences()
            defaults.set(value, forKey: KinetiqTelemetry.ga4ConsentKey)
            defaults.set(value, forKey: KinetiqTelemetry.ga4ConsentDecisionKey)
            let telemetry = KinetiqTelemetry(defaults: defaults, configuration: .success(host),
                productID: "kinetiq_ga4_boolean_" + UUID().uuidString.lowercased())
            XCTAssertFalse(telemetry.analyticsConsent)
            await telemetry.initialize()
            XCTAssertTrue(telemetry.shouldRequestConsentAtStartup)
            await telemetry.shutdown()
        }
        let defaults = try preferences()
        defaults.set(true, forKey: KinetiqTelemetry.ga4ConsentDecisionKey)
        let telemetry = KinetiqTelemetry(defaults: defaults, configuration: .success(host),
            productID: "kinetiq_ga4_decision_" + UUID().uuidString.lowercased())
        await telemetry.initialize()
        XCTAssertFalse(telemetry.analyticsConsent)
        XCTAssertFalse(telemetry.shouldRequestConsentAtStartup)
        XCTAssertNil(defaults.object(forKey: KinetiqTelemetry.consentDecisionKey))
        await telemetry.shutdown()
        XCTAssertNil(FirebaseApp.app())
    }

    func testModeAwareDisclosureAndDefaultNativeAlert() {
        let native = TelemetryConsentPrompt.makeAlert()
        let ga4 = TelemetryConsentPrompt.makeAlert(mode: .ga4)
        XCTAssertEqual(native.buttons.map(\.title), ["Don't Share", "Enable Analytics"])
        XCTAssertEqual(ga4.buttons.map(\.title), ["Don't Share", "Enable Analytics"])
        XCTAssertEqual(ga4.buttons[1].keyEquivalent, "")
        XCTAssertTrue(native.informativeText.contains("app-private Keychain"))
        XCTAssertTrue(ga4.informativeText.contains("No Keychain access"))
        XCTAssertTrue(ga4.informativeText.contains("connection IP"))
        XCTAssertTrue(ga4.informativeText.contains("partial"))
        XCTAssertTrue(TelemetryConsentPrompt.withdrawalDisclosure(mode: .ga4).contains("cannot recall"))
    }
}