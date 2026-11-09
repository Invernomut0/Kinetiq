# Integrate a macOS app with Copilot — SDK 0.1.1

Use this guide **in the host application's repository**, not to add application features
to TelemetrySDK. It covers Swift 6 / macOS 13+, SwiftUI and AppKit, with an owned
`TelemetryClient` and optional PostHog analytics. Sentry is opt-in to the integration
task, not a default dependency. No Kinetiq, Tempo or OmniPreview migration is claimed here.

## 1. Give Copilot the task

Copy these three files into the host repository, preserving their paths:

- This guide: `Documentation/COPILOT_INTEGRATION.md`.
- [Reusable prompt](../.github/prompts/integrate-telemetry.prompt.md):
  `.github/prompts/integrate-telemetry.prompt.md`.
- [Swift integration instructions](../.github/instructions/telemetry-integration.instructions.md):
  `.github/instructions/telemetry-integration.instructions.md`.

Links to other SDK documents/templates below are relative to the original SDK repository.
When using this copied guide in a host, read those references from the pinned SDK checkout;
do not assume the host has `Documentation/API.md` or copy SDK example products into it.
The prompt/instruction links above remain valid with the three preserved paths.

Open the **host** workspace in VS Code, select Copilot Agent mode, and send:

```text
/integrate-telemetry Integrate SDK 0.1.1 into this host app only.
App ID: kinetiq. App name: Kinetiq. Lifecycle: SwiftUI with an AppKit delegate.
SDK checkout: ../TelemetrySDK. SDK pin: ask me for the verified full commit SHA.
Providers: PostHog only; no Sentry. Consent: explicit, persisted, default false.
First inspect existing package dependencies, telemetry ownership, consent UI,
entry points, signing and configuration. Do not read .env or print credentials.
Implement and test the host integration; do not send real events until I explicitly
approve a controlled development/staging smoke. Report evidence and blockers.
Do not commit or push.
```

Adjust the inputs, not the stable product IDs:

| App | Product ID | Product name |
| --- | --- | --- |
| Kinetiq | `kinetiq` | `Kinetiq` |
| Tempo | `tempo` | `Tempo` |
| OmniPreview | `omnipreview` | `OmniPreview` |

The product ID is **not** the reverse-DNS bundle identifier. Confirm the lifecycle,
SDK location/pin and requested providers with the host owner; do not guess app targets.

## 2. Inspect before changing the host

Copilot should find the `.xcodeproj`/workspace or `Package.swift`, actual app target,
deployment target, Swift version, `@main`/delegate, privacy UI and persisted consent.
Inventory existing `Telemetry`, PostHog and Sentry initializers and automatic collectors.
Reuse one existing owner or replace it deliberately; never add a second singleton/client
over the same vendor storage. Do not import a legacy cross-app identity or call vendor
`identify`/`alias`. Inspect source and config **key names**, never secret file contents.

Read the pinned SDK's actual `Package.swift`, `Core/TelemetryClient.swift`,
`Core/Telemetry.swift`, `Core/TelemetryConfiguration.swift`, `Integrations/Providers.swift`,
privacy, lifecycle and identity sources, requested adapter and native examples. Paths
are under `Sources/Invernomut0Telemetry` unless noted. Existing
[API](API.md), [setup](GettingStarted.md) and [migration](Migration.md) documents describe
the implemented 0.1.1 contract: **source at the chosen pin is authoritative**.
This checkout has the client/facade/timer/Keychain implementations; that does not certify
a remote release, a host build or server delivery. If the pin lacks them or fails its
gates, stop and report the blocker; do not create a substitute SDK inside the host.

## 3. Add the correct package, with a reproducible pin

The real repository is <https://github.com/Invernomut0/TelemetrySDK>.
`0.1.1` is the documentation/SDK version, **not proof that a `0.1.1` Git tag exists**.
The remote page inspected for this guide exposed no usable source; verify publication
and a full commit SHA before relying on remote resolution. A verified local checkout
can be used meanwhile, with its revision and local changes explicitly recorded.

### Core only

Once a published revision is verified, add the repository root URL in Xcode and select
the `Invernomut0Telemetry` product. In a SwiftPM host, the equivalent is:

```swift
// Dependency entry: replace the placeholder with an available, verified full SHA.
.package(url: "https://github.com/Invernomut0/TelemetrySDK", revision: "<verified-full-commit-sha>")
// Host target dependency entry:
.product(name: "Invernomut0Telemetry", package: "TelemetrySDK")
```

Core alone has no PostHog/Sentry dependency and sends nothing without a provider.

### PostHog: use the nested LOCAL package

**SwiftPM cannot select a nested `Package.swift` by appending a directory to a Git URL.**
Do not use a URL ending in `/Integrations/PostHog`, or invent a standalone adapter repo.
Clone the entire repository into a directory named `TelemetrySDK`, pin it to a reviewed
commit (or use a pinned submodule at that path), and preserve its layout. For example,
from the host repository, after replacing the SHA placeholder:

```sh
git clone https://github.com/Invernomut0/TelemetrySDK ../TelemetrySDK
git -C ../TelemetrySDK checkout --detach <verified-full-commit-sha>
git -C ../TelemetrySDK rev-parse HEAD
swift build --package-path ../TelemetrySDK
swift test --package-path ../TelemetrySDK
swift build --package-path ../TelemetrySDK/Integrations/PostHog
swift test --package-path ../TelemetrySDK/Integrations/PostHog
```

Do not clone over an existing checkout. Review local changes separately from its SHA.
An external local path is not pinned by the host's `Package.resolved`; record the SDK
revision and provision the same checkout/path in CI. Never assume adapter tests pass.

In **Xcode → Add Package Dependencies → Add Local**, select
`../TelemetrySDK/Integrations/PostHog` and link `Invernomut0TelemetryPostHog` to the app
target. Its `.package(path: "../..")` brings the root core transitively. Link the core
product from that same local graph if the app target needs an explicit product entry;
do not also add a remote copy of the core. The directory name matters to the current
adapter manifest's `package: "TelemetrySDK"` reference.

For a SwiftPM host with this sibling layout, merge these entries into its existing manifest:

```swift
// Package dependencies:
.package(path: "../TelemetrySDK"),
.package(path: "../TelemetrySDK/Integrations/PostHog")
// Existing app target dependencies:
.product(name: "Invernomut0Telemetry", package: "TelemetrySDK"),
.product(name: "Invernomut0TelemetryPostHog", package: "PostHog")
```

Both entries resolve the **same local core**. The adapter pins official PostHog to
`3.93.6`; preserve/review resolved dependencies. If Sentry is explicitly requested,
use the analogous local `Integrations/Sentry` package and
`Invernomut0TelemetrySentry` product, not a fabricated remote repository. Its current
manifest pins Sentry Cocoa `9.33.0`. Do not link example executable/support products
into the app: the shared example intentionally imports both vendors.

## 4. Supply configuration without exposing credentials

Use the actual keys from [Xcode configuration templates](../Examples/Configuration/README.md):

| Key | Use |
| --- | --- |
| `TELEMETRY_POSTHOG_TOKEN` | PostHog client ingestion project token |
| `TELEMETRY_POSTHOG_HOST` | Project's ingest host; default `https://eu.i.posthog.com` |
| `TELEMETRY_SENTRY_DSN` | Only for an explicitly requested crash integration |

For development, enter values yourself in **Xcode scheme → Run → Arguments → Environment
Variables**. Do not paste them into Copilot chat. For Finder/distribution launches, use
the host's **main Info.plist**, with `$(TELEMETRY_POSTHOG_TOKEN)` and
`$(TELEMETRY_POSTHOG_HOST)` build substitutions, or the matching
`INFOPLIST_KEY_TELEMETRY_POSTHOG_TOKEN` / `INFOPLIST_KEY_TELEMETRY_POSTHOG_HOST` settings
for a generated plist. Keep existing bundle/signing/version settings. Do not replace
the entire host plist with the template or assume a SwiftPM resource plist is `Bundle.main`.

Include an ignored `Telemetry.local.xcconfig` from your existing build config. For URLs,
use `TELEMETRY_SLASH = /` and
`TELEMETRY_POSTHOG_HOST = https:$(TELEMETRY_SLASH)$(TELEMETRY_SLASH)eu.i.posthog.com`:
literal `//` starts an xcconfig comment. See the exact
[xcconfig](../Examples/Configuration/Telemetry.xcconfig) and
[plist](../Examples/Configuration/Info.plist) templates.

Swift/Xcode do **not** automatically load `.env`; never read it into model context,
dump the environment/plist/build settings into logs, or package it as a resource.
Ensure the host ignores `.env`, `.env.*` (except an empty `.env.example`) and
`*.local.xcconfig` before supplying values. Never ship management/admin API tokens.
Client ingestion keys in a shipped binary are extractable, not confidential server secrets.
Keep development/staging projects separate from production; never enable
`allowProductionInDebugBuild` to make a smoke test pass.

## 5. Paste one host-owned controller

This complete PostHog-only starting point uses the source APIs at SDK 0.1.1.
Rename the host type if one already exists; instantiate it only once per app process.
Its product defaults illustrate Kinetiq; use the reviewed mapping above. It loads only
Boolean preferences previously granted by this host's explicit UI. Missing consent is
false. Initialization, consent, captures and shutdown cannot overlap through this owner.
Product actions remain available when telemetry fails; only telemetry controls are gated.

```swift
import Combine
import Foundation
import Invernomut0Telemetry
import Invernomut0TelemetryPostHog

@MainActor
final class HostTelemetry: ObservableObject {
    @Published private(set) var ready = false
    @Published private(set) var busy = false
    @Published private(set) var analyticsConsent = false
    @Published private(set) var status = "Telemetry not initialized"

    private let productID: String
    private let productName: String
    private let defaults: UserDefaults
    private var client: TelemetryClient?
    private var provider: PostHogAnalyticsProvider?
    private var closing = false
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private var consentKey: String { "\(productID).telemetry.analytics" }
    var canChangeConsent: Bool { ready && !busy && !closing && provider != nil }

    init(productID: String = "kinetiq", productName: String = "Kinetiq",
         defaults: UserDefaults = .standard) {
        self.productID = productID
        self.productName = productName
        self.defaults = defaults
        analyticsConsent = defaults.bool(forKey: "\(productID).telemetry.analytics")
    }

    // Read only named runtime keys; never read a .env file or log their values.
    private static func hostValue(_ key: String) -> String? {
        for candidate in [ProcessInfo.processInfo.environment[key],
                          Bundle.main.object(forInfoDictionaryKey: key) as? String] {
            guard let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty, !value.contains("$(") else { continue }
            return value
        }
        return nil
    }

    func initialize() async {
        guard client == nil, !busy, !closing else { return }
        busy = true
        defer { finish() }
        if let token = Self.hostValue("TELEMETRY_POSTHOG_TOKEN") {
            provider = PostHogAnalyticsProvider(projectToken: token,
                host: Self.hostValue("TELEMETRY_POSTHOG_HOST") ?? "https://eu.i.posthog.com")
        }
        #if DEBUG
        let environment: TelemetryEnvironment = .development
        #else
        let environment: TelemetryEnvironment = .production
        #endif
        let configuration = TelemetryConfiguration(
            productID: productID, productName: productName, environment: environment,
            privacy: PrivacySettings(
                analyticsEnabled: analyticsConsent && provider != nil,
                crashReportingEnabled: false, collectOSVersion: false,
                collectHardwareInfo: false,
                allowedPropertyKeys: ["feature", "operation", "duration_ms", "reason"]),
            lifecycleTrackingEnabled: true, allowProductionInDebugBuild: false)
        let owned = TelemetryClient(configuration: configuration, analyticsProvider: provider)
        client = owned // Reserve ownership before the first suspension.
        do {
            try await owned.initialize()
            analyticsConsent = (await owned.privacySettings()).analyticsEnabled
            ready = true
            status = provider == nil ? "Analytics unavailable: configuration required" : "Telemetry ready"
        } catch {
            await failClosed()
        }
    }

    func setAnalyticsConsent(_ enabled: Bool) async {
        guard canChangeConsent, let client else { return }
        busy = true
        defer { finish() }
        if !enabled { // Persist withdrawal BEFORE awaiting vendor cleanup.
            analyticsConsent = false
            defaults.set(false, forKey: consentKey)
        }
        do {
            try await client.setAnalyticsEnabled(enabled)
            if !enabled, await provider?.lastPurgeError != nil {
                await failClosed()
                return
            }
            analyticsConsent = enabled
            defaults.set(enabled, forKey: consentKey) // Grant only after startup succeeds.
            status = enabled ? "Analytics consent granted" : "Analytics consent withdrawn"
        } catch {
            await failClosed()
        }
    }

    // Call after the host actually opens its privacy settings, not on startup.
    func privacySettingsOpened() async {
        guard ready, !busy, !closing, analyticsConsent, let client else { return }
        busy = true
        defer { finish() }
        await client.track("feature_used", properties: ["feature": "privacy_settings"])
    }

    private func failClosed() async {
        analyticsConsent = false
        defaults.set(false, forKey: consentKey)
        closing = true // Resolve cleanup/configuration before a fresh reviewed launch.
        ready = false
        if let client { try? await client.setEnabled(false); await client.shutdown() }
        await provider?.stop(purge: true)
        status = "Telemetry stopped; product features remain available"
    }

    private func finish() {
        busy = false
        let waiters = idleWaiters
        idleWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    func shutdown() async {
        closing = true // Reject new operations while an existing one completes.
        if busy { await withCheckedContinuation { idleWaiters.append($0) } }
        if let client { await client.shutdown() }
        ready = false
    }
}
```

The SDK supplies bundle version/build defaults; do not copy the SDK's version into
the host's app version. `enabled` is an independent kill switch, **not user consent**.
For a staging build, select `.staging` explicitly and supply staging ingestion keys.
Never automatically grant consent in Debug or replay pre-consent user actions.

### SwiftUI wiring (merge into the existing App, do not add a second `@main`)

```swift
import AppKit
import SwiftUI

@main
struct HostApp: App {
    @StateObject private var telemetry = HostTelemetry()
    @NSApplicationDelegateAdaptor(TelemetryQuitDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            VStack {
                Toggle("Share categorical analytics", isOn: Binding(
                    get: { telemetry.analyticsConsent },
                    set: { value in Task { await telemetry.setAnalyticsConsent(value) } }))
                    .disabled(!telemetry.canChangeConsent)
                if telemetry.busy { ProgressView("Applying telemetry preference") }
                Text(telemetry.status)
            }
            .padding()
            .task {
                delegate.telemetry = telemetry
                await telemetry.initialize()
            }
        }
    }
}

@MainActor
final class TelemetryQuitDelegate: NSObject, NSApplicationDelegate {
    var telemetry: HostTelemetry?
    private var quitting = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !quitting else { return .terminateLater }
        quitting = true
        Task {
            await telemetry?.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
```

Place the consent control in the real privacy/settings UI, retaining product content.
The App-level `@StateObject` shares one controller across windows; repeated `.task`
calls are guarded before awaiting. Reuse the existing delegate if present. Do not also
forward per-window `scenePhase` events: with `lifecycleTrackingEnabled: true`, the SDK
owns native application notifications and session events. Do not manually `track`
`app_launched`, `session_started`, installation or other reserved lifecycle events.

### AppKit alternative

Keep `private let telemetry = HostTelemetry()` in the **existing** app delegate.
Merge these methods with its existing launch/quit behavior; do not overwrite other
cleanup or termination decisions:

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    Task { await telemetry.initialize() }
}

func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !quitting else { return .terminateLater }
    quitting = true // Add private var quitting = false to the delegate.
    Task {
        await telemetry.shutdown()
        sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
}
```

Bind the actual checkbox to `analyticsConsent`, disable telemetry controls while busy,
and await `setAnalyticsConsent` in its action. Do not disable the app's real features.
An unawaited `Task` in `applicationWillTerminate` alone cannot guarantee cleanup.
Graceful quit is best effort; process kills/crashes are not graceful termination.

### Real API quick reference

`TelemetryClient` is an actor: await `initialize`, `track`, `trackError`, consent changes,
diagnostics and shutdown. `startTimer` is **nonisolated/synchronous**; `stop` is async
and returns milliseconds once (`Double?`), then nil. A testable timing helper using
an injected, already-initialized client and a real host operation is:

```swift
import Invernomut0Telemetry

func measureRefresh(client: TelemetryClient,
                    operation: () async throws -> Void) async rethrows {
    let timer = client.startTimer("refresh_metadata")
    do {
        try await operation()
    } catch {
        await timer.stop()
        throw error
    }
    await timer.stop()
}
```

Use only a reviewed fixed operation name and call it around an actual host operation;
add `operation` and `duration_ms` to the custom-key allowlist. Do not invent duration
fields or send paths, document contents, window titles, payment data or arbitrary errors.
Revocation during an operation must suppress its later telemetry; do not keep the host
consent UI locked for the full duration of long product work.

If the host already uses the `@MainActor Telemetry` facade, reuse it **instead of** the
owned-client sample. `try await Telemetry.initialize(configuration:analyticsProvider:)`
must finish before `await Telemetry.track(...)` or consent changes. Actual convenience
names include `trackFeatureUsed`, `trackFeatureEnabled`, `trackFeatureDisabled`,
`trackSettingChanged`, `trackScreenViewed`, `trackError`; not `featureUsed`/`screenViewed`.
`Telemetry.startTimer` is synchronous on MainActor. Keep the same host serialization
and shutdown policy; do not combine facade ownership with another client.

Providers implement serial async `start`, `capture`, `stop(purge:)`; only analytics
has `flush`. The host uses client consent APIs, not direct vendor opt-in calls.
If adding Sentry by explicit request, persist a **separate**, default-false crash choice,
call `setCrashReportingEnabled`, check its adapter's `lastPurgeError` on withdrawal,
and reuse one process-global Sentry owner. Read [provider limitations](Providers.md),
including raw native crash cache and strict scrubbing/symbolication tradeoffs.

## 6. Acceptance checklist — record evidence, not assumptions

The host maintainer owns all items below. Track them as To Do / Doing / Review / Done
in the host's existing task list, with commands/results and the actual app build/pin.

- [ ] **Dependency/build:** one core graph, requested adapters only, Swift 6/macOS target
  compatibility; SDK and requested adapter build/tests pass at the recorded revision.
  Host Debug and Release build, tests/coverage and a signed archive pass. Record blockers.
- [ ] **Disabled smoke first:** isolated fresh consent preferences, no real keys/providers,
  initialize an `enabled: false` client and assert initialized diagnostics, both channels
  off/unavailable and zero accepted events. Shutdown cleanly. No network or new Keychain
  identity; absence of consent must never be replaced by a Debug auto-opt-in.
- [ ] **Host contract tests:** inject an actor test double conforming to `AnalyticsProvider`
  and an `InstallationIdentityStore` double where useful. Assert zero start/capture
  before consent, single initialization under repeated/concurrent startup, grant ordering,
  failed-start recovery, withdrawal persisted before `stop(purge: true)`, no flush on
  withdrawal, no captures after withdrawal/kill switch, serialized quit, invalid config
  and single timer stop capture. Doubles prove call ordering, **not live delivery**.
- [ ] **Signed native identity:** after explicitly approved dev/staging consent, run the
  actual signed sandboxed `.app`, quit and restart it with the same signing/access scope.
  Verify the real product-scoped Keychain UUID persists without exposing it in logs/chat;
  verify distinct product IDs do not share it. A memory double or CLI-only test is insufficient.
  Test access failure and rotation/deletion separately; Keychain can survive uninstall.
- [ ] **Consent UI/revoke:** fresh install defaults false; restart preserves reviewed host
  choices. Revoke while offline/queued and during pending work; confirm no new requests
  after completed revocation, local purge result, denied relaunch, and fail-closed handling
  of purge failure. In-flight bytes cannot be recalled; local deletion is not server erasure.
- [ ] **Lifecycle exactly once at capture boundary:** with consent off, no lifecycle
  captures; with explicit consent, verify native activation/background, sleep/wake,
  multi-window/repeated `.task`, timeout and graceful quit. One owner; no vendor automatic
  duplicates or host manual reserved events. This is not exactly-once remote delivery.
- [ ] **Controlled delivery, only after explicit approval:** use a development/staging
  project, approved ingestion keys and a real categorical host action. Review sanitized
  payload metadata and actual server ingestion in that project, including offline/retry
  behavior. `acceptedEvents`, `flush()` and shutdown are **not delivery acknowledgements**.
  Live PostHog delivery is not already proved by this guide; leave it Review until observed.
- [ ] **Distribution:** verify outgoing-network sandbox entitlement, main plist substitutions
  without revealing values, privacy resources/notices and signing/notarization. If Sentry
  was requested, separately test crash consent with analytics off, native crash/relaunch
  without debugger, purge and symbolication limitations. Test a Quick Look extension only
  if the actual host has one; do not create one or initialize shared vendor storage twice.

Do not send real events merely to validate the integration automatically. Production
rollout needs host-owner approval, privacy/retention review and independent consent.
Report changed host files, API/pin evidence, exact executed checks, skipped live checks
and remaining blockers. Do not claim absent apps are migrated or alter the SDK core.
