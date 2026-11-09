// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import Invernomut0Telemetry

/// Owner-supplied Web stream ingestion credentials, never administrator credentials.
/// Bundling the ingestion secret makes it extractable; it is not an authentication boundary.
struct GA4MeasurementProtocolConfiguration: Sendable {
    let measurementID: String
    let apiSecret: String

    enum Invalid: Error { case configuration }

    static var defaultBundleURL: URL? {
        Bundle.main.url(forResource: "KinetiqGA4Configuration", withExtension: "plist")
    }

    init(data: Data) throws {
        guard data.count <= 65_536,
              let metadata = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let values = metadata as? [String: Any],
              Set(values.keys) == ["measurement_id", "api_secret"],
              let measurementID = values["measurement_id"] as? String,
              let apiSecret = values["api_secret"] as? String,
              measurementID.utf8.count <= 256,
              measurementID.range(of: "^G-[A-Z0-9]+\\z", options: .regularExpression) != nil,
              (1...256).contains(apiSecret.utf8.count),
              apiSecret.range(of: "^[A-Za-z0-9_-]+\\z", options: .regularExpression) != nil,
              !Self.isPlaceholder(measurementID),
              !Self.isPlaceholder(apiSecret) else { throw Invalid.configuration }
        self.measurementID = measurementID
        self.apiSecret = apiSecret
    }

    /// Absence is optional; a present unreadable, oversized or invalid resource fails closed.
    static func load(file: URL? = defaultBundleURL) throws -> Self? {
        guard let file else { return nil }
        do {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            guard let data = try handle.read(upToCount: 65_537) else { throw Invalid.configuration }
            return try Self(data: data)
        } catch { throw Invalid.configuration }
    }

    private static func isPlaceholder(_ value: String) -> Bool {
        let normalized = value.uppercased()
        return normalized.contains("REPLACE") || normalized.contains("PLACEHOLDER") ||
            ["CHANGEME", "CHANGE_ME", "YOUR_API_SECRET", "API_SECRET", "SECRET", "TODO"].contains(normalized)
    }
}

/// Reject redirects even to another HTTPS URL: the query contains an extractable ingestion secret.
private final class GA4NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Locally measured Web timing, not a Firebase app session or an automatic session event.
struct GA4EventTiming: Sendable, Equatable {
    let sessionID: Int64
    let engagementTimeMilliseconds: Int64?
}

/// Actual monotonic foreground intervals; no clock injection, persisted state or automatic events.
/// The host supplies AppKit activation boundaries only after consented startup.
@MainActor
struct GA4ForegroundMeasurement {
    private let clock = ContinuousClock()
    private var lastApprovedAction: ContinuousClock.Instant?
    private var foregroundStart: ContinuousClock.Instant?
    private var elapsed: Duration = .zero
    private(set) var sessionID: Int64?
    var isMeasuringForeground: Bool { foregroundStart != nil }

    mutating func start(isForeground: Bool) {
        stop()
        sessionID = Self.currentSessionID()
        lastApprovedAction = clock.now
        if isForeground { foregroundStart = clock.now }
    }

    mutating func setForeground(_ active: Bool) {
        guard lastApprovedAction != nil else { return }
        if active {
            if foregroundStart == nil { foregroundStart = clock.now }
        } else if let start = foregroundStart {
            elapsed += start.duration(to: clock.now)
            foregroundStart = nil
        }
    }

    /// Consumes only time since consented start or the previous approved capture.
    /// Thirty minutes without an approved action begins a fresh, actual wall-clock Web session.
    mutating func takeApprovedActionTiming() -> GA4EventTiming? {
        guard let previous = lastApprovedAction else { return nil }
        let now = clock.now
        if previous.duration(to: now) >= .seconds(30 * 60) { sessionID = Self.currentSessionID() }
        if let start = foregroundStart {
            elapsed += start.duration(to: now)
            foregroundStart = now
        }
        lastApprovedAction = now
        let components = elapsed.components
        elapsed = .zero
        let (seconds, overflow) = components.seconds.multipliedReportingOverflow(by: 1_000)
        let (milliseconds, additionOverflow) = seconds.addingReportingOverflow(components.attoseconds / 1_000_000_000_000_000)
        guard let sessionID else { return nil }
        let measured = !overflow && !additionOverflow && milliseconds > 0 ? milliseconds : nil
        return GA4EventTiming(sessionID: sessionID, engagementTimeMilliseconds: measured)
    }

    mutating func stop() {
        lastApprovedAction = nil
        foregroundStart = nil
        elapsed = .zero
        sessionID = nil
    }

    private static func currentSessionID() -> Int64? {
        let timestamp = Date().timeIntervalSince1970.rounded(.down)
        guard timestamp.isFinite, timestamp >= 1, timestamp < Double(Int64.max) else { return nil }
        return Int64(timestamp)
    }
}

/// Direct, best-effort Web Measurement Protocol; no native Firebase, Keychain, queue or retries.
@MainActor
final class GA4MeasurementProtocolProvider: AnalyticsProvider {
    /// Sanitized diagnostics only: acceptance is not confirmation of GA4 ingestion.
    enum TransportStatus: Equatable, Sendable {
        case stopped
        case ready
        case submitting(submitted: Int, inFlight: Int)
        case requestAccepted(statusCode: Int)
        case httpRejected(statusCode: Int)
        case networkFailed
        case invalidResponse
        case droppedAtCapacity(inFlight: Int)
        case droppedInvalidEvent

        var message: String {
            switch self {
            case .stopped: return "GA4 transport stopped"
            case .ready: return "GA4 transport ready; no request submitted"
            case .submitting(let submitted, let inFlight):
                return "GA4 requests submitted: \(submitted); in flight: \(inFlight)"
            case .requestAccepted(let code):
                return "GA4 HTTP \(code): request accepted; ingestion not confirmed"
            case .httpRejected(let code): return "GA4 HTTP \(code): request not accepted"
            case .networkFailed: return "GA4 network request failed; no retry"
            case .invalidResponse: return "GA4 response unavailable or invalid"
            case .droppedAtCapacity(let count): return "GA4 request dropped: capacity reached (\(count) in flight)"
            case .droppedInvalidEvent: return "GA4 request dropped: invalid or unapproved event"
            }
        }
    }

    nonisolated let name = "Google Analytics 4 Measurement Protocol"
    private let configuration: GA4MeasurementProtocolConfiguration
    private let statusChanged: (@MainActor (TransportStatus) -> Void)?
    private let countrySource: @MainActor () -> GA4ConfiguredCountry?
    private(set) var configuredCountry: GA4ConfiguredCountry?
    private(set) var transportStatus: TransportStatus = .stopped
    private var foregroundMeasurement = GA4ForegroundMeasurement()
    private var foregroundObservers: [NSObjectProtocol] = []
    var foregroundObserverCount: Int { foregroundObservers.count }
    private var started = false
    private var clientID: UUID?
    private var generation = UUID()
    private var session: URLSession?
    private var tasks: [UUID: URLSessionDataTask] = [:]
    private(set) var submittedRequests = 0
    var inFlightRequests: Int { tasks.count }

    init(configuration: GA4MeasurementProtocolConfiguration,
         statusChanged: (@MainActor (TransportStatus) -> Void)? = nil,
         countrySource: @escaping @MainActor () -> GA4ConfiguredCountry? = { GA4ConfiguredCountry.current() }) {
        self.configuration = configuration
        self.statusChanged = statusChanged
        self.countrySource = countrySource
    }

    /// Starting creates only local ephemeral state, never a request or a native SDK instance.
    func start(configuration: TelemetryConfiguration, installationID: UUID) async throws {
        stopLocally()
        guard configuration.enabled, configuration.privacy.analyticsEnabled else {
            throw GA4MeasurementProtocolConfiguration.Invalid.configuration
        }
        let transport = URLSessionConfiguration.ephemeral
        transport.httpCookieStorage = nil
        transport.httpShouldSetCookies = false
        transport.urlCache = nil
        transport.urlCredentialStorage = nil
        transport.requestCachePolicy = .reloadIgnoringLocalCacheData
        transport.timeoutIntervalForRequest = 8
        transport.timeoutIntervalForResource = 10
        transport.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: transport, delegate: GA4NoRedirectDelegate(), delegateQueue: nil)
        clientID = installationID
        started = true
        configuredCountry = countrySource()
        foregroundMeasurement.start(isForeground: NSApplication.shared.isActive)
        observeForeground()
        updateStatus(.ready)
    }

    /// No asynchronous submission is scheduled: the generation check and resume share one actor turn.
    func capture(_ event: TelemetryEvent) async {
        guard started, let clientID, let session else { return }
        // Core installation/lifecycle events are intentionally filtered, not transport failures.
        guard FirebaseAnalyticsPolicy.parameters(for: event) != nil else { return }
        guard event.installationID == clientID else {
            updateStatus(.droppedInvalidEvent)
            return
        }
        foregroundMeasurement.setForeground(NSApplication.shared.isActive)
        let timing = foregroundMeasurement.takeApprovedActionTiming()
        guard tasks.count < 4 else {
            updateStatus(.droppedAtCapacity(inFlight: tasks.count))
            return
        }
        guard let request = try? Self.makeRequest(configuration: configuration, clientID: clientID,
                                                 event: event, timing: timing, country: configuredCountry) else {
            updateStatus(.droppedInvalidEvent)
            return
        }
        let currentGeneration = generation
        let taskID = UUID()
        let task = session.dataTask(with: request) { [weak self] _, response, error in
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let failed = error != nil
            // Never log responses, raw errors, URLs or identifiers. Old completions cannot touch new tasks.
            Task { @MainActor [weak self] in
                guard let self, self.generation == currentGeneration else { return }
                self.tasks.removeValue(forKey: taskID)
                self.updateStatus(failed ? .networkFailed : statusCode.map(Self.makeStatusHTTP) ?? .invalidResponse)
            }
        }
        guard started, generation == currentGeneration else { task.cancel(); return }
        tasks[taskID] = task
        submittedRequests += 1
        task.resume()
        updateStatus(.submitting(submitted: submittedRequests, inFlight: tasks.count))
    }

    /// There is no retained queue or delivery acknowledgement; this bounded operation does nothing.
    func flush() async {}

    /// Cancels local work for both shutdown and revocation; cannot recall received server data.
    func stop(purge: Bool) async { stopLocally() }

    private func stopLocally() {
        started = false
        generation = UUID()
        clientID = nil
        configuredCountry = nil
        for observer in foregroundObservers { NotificationCenter.default.removeObserver(observer) }
        foregroundObservers.removeAll()
        foregroundMeasurement.stop()
        let pending = tasks.values
        tasks.removeAll()
        for task in pending { task.cancel() }
        session?.invalidateAndCancel()
        session = nil
        updateStatus(.stopped)
    }

    private func updateStatus(_ status: TransportStatus) {
        transportStatus = status
        statusChanged?(status)
    }

    /// Main-queue AppKit notifications are measured synchronously, not after a deferred task.
    private func observeForeground() {
        let currentGeneration = generation
        for (name, active) in [(NSApplication.didBecomeActiveNotification, true),
                               (NSApplication.willResignActiveNotification, false)] {
            let observer = NotificationCenter.default.addObserver(forName: name, object: NSApplication.shared,
                                                                  queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.started, self.generation == currentGeneration else { return }
                    self.foregroundMeasurement.setForeground(active)
                }
            }
            foregroundObservers.append(observer)
        }
    }

    /// Pure HTTP categorization: status codes alone cannot establish server-side ingestion.
    nonisolated static func makeStatusHTTP(_ statusCode: Int) -> TransportStatus {
        guard (100...599).contains(statusCode) else { return .invalidResponse }
        return (200...299).contains(statusCode) ? .requestAccepted(statusCode: statusCode) : .httpRejected(statusCode: statusCode)
    }

    /// Stable numeric Web client ID from two 32-bit portions of the separate GA4 UUID.
    /// Google's validator rejects the raw hyphenated UUID; this is not a Firebase app-instance ID.
    nonisolated static func webClientID(for installationID: UUID) -> String {
        let bytes = installationID.uuid
        let first = UInt32(bytes.0) << 24 | UInt32(bytes.1) << 16 | UInt32(bytes.2) << 8 | UInt32(bytes.3)
        let last = UInt32(bytes.12) << 24 | UInt32(bytes.13) << 16 | UInt32(bytes.14) << 8 | UInt32(bytes.15)
        return "\(first).\(last)"
    }

    /// Pure local builder. Only the actual approved action is represented; all other fields are dropped.
    /// Optional timing comes only from local measurement, never from private event properties.
    nonisolated static func makeRequest(configuration: GA4MeasurementProtocolConfiguration,
                                        clientID: UUID, event: TelemetryEvent,
                                        timing: GA4EventTiming? = nil,
                                        country: GA4ConfiguredCountry? = nil) throws -> URLRequest? {
        guard event.installationID == clientID,
              let approved = FirebaseAnalyticsPolicy.parameters(for: event) else { return nil }
        var parameters: [String: Any] = approved
        if let timing {
            guard timing.sessionID > 0,
                  timing.engagementTimeMilliseconds.map({ $0 > 0 }) ?? true else { return nil }
            parameters["session_id"] = timing.sessionID
            if let milliseconds = timing.engagementTimeMilliseconds {
                parameters["engagement_time_msec"] = milliseconds
            }
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.google-analytics.com"
        components.path = "/mp/collect"
        components.queryItems = [URLQueryItem(name: "measurement_id", value: configuration.measurementID),
                                 URLQueryItem(name: "api_secret", value: configuration.apiSecret)]
        guard let url = components.url else { throw GA4MeasurementProtocolConfiguration.Invalid.configuration }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = [
            "client_id": webClientID(for: clientID),
            "consent": ["ad_user_data": "DENIED", "ad_personalization": "DENIED"],
            "events": [["name": event.name, "params": parameters]]
        ]
        // Standard GA4 geography, never an event parameter or inferred city/subdivision.
        if let country { payload["user_location"] = ["country_id": country.code] }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }
}