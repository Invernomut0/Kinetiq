---
description: "Integrate TelemetrySDK 0.1.1 into an existing SwiftUI or AppKit macOS host app with explicit consent and verified package dependencies."
agent: agent
argument-hint: "App ID/name, SwiftUI or AppKit lifecycle, SDK checkout and verified commit, requested providers"
---

# Integrate telemetry in the host app only

Read the [integration guide](../../Documentation/COPILOT_INTEGRATION.md) and
[Swift integration rules](../instructions/telemetry-integration.instructions.md) first.
These files must be copied into the host repository with their paths preserved.
Use the user's appended app ID/name, lifecycle, SDK checkout/pin and requested providers.
If critical inputs are missing, inspect the host first and ask only for unresolved choices.

1. Confirm this workspace is the **host app**, not TelemetrySDK. Inspect its app target,
   package/Xcode configuration, entry point/delegate, current telemetry owner, consent
   persistence/UI, signing and entitlements. Reuse existing architecture; do not add
   app-specific functionality to the SDK or a second singleton/client/vendor initializer.
2. Verify the actual SDK sources at the reviewed revision: client/facade, configuration,
   provider contracts, privacy, timers, native lifecycle, Keychain identity, requested
   adapters and examples. Source wins over historical planned-API docs. Stop on a missing
   API/build blocker; do not implement a substitute SDK or invent API names.
3. Add only requested packages from `https://github.com/Invernomut0/TelemetrySDK`.
   Core is the root package. Nested adapters cannot be selected by a Git URL directory:
   use a complete locally cloned/pinned repository named `TelemetrySDK` and
   `.package(path: ".../TelemetrySDK/Integrations/PostHog")` or Xcode Add Local.
   Adapter core is transitive; never resolve a second remote core. Verify remote SHA/tag
   availability, record local revision/changes and reproduce paths in CI. Version 0.1.1
   does not guarantee a published tag. Do not invent standalone adapter repositories.
4. Implement one retained owner and host-owned, explicit Boolean consent, default false.
   Serialize and await initialization before any consent operation or event. Gate telemetry
   controls during transitions; persist withdrawal first, grants only after successful
   startup, fail closed on startup/purge failure, and await graceful shutdown. Keep real
   app features working when telemetry is disabled. Do not add Sentry unless requested;
   requested crash reporting needs a separate default-false choice and global owner review.
5. Use reviewed stable IDs `kinetiq`, `tempo`, `omnipreview` for their corresponding apps;
   bundle IDs are not product IDs. Use host bundle version/build, Debug development and
   a deliberate Release/staging policy, never automatic Debug consent or production override.
   Supply `TELEMETRY_POSTHOG_TOKEN` / `TELEMETRY_POSTHOG_HOST` through named process env
   or main Info.plist substitutions; `TELEMETRY_SENTRY_DSN` only if requested. Follow the
   SDK's Examples/Configuration templates without replacing host signing/plist settings.
   Check secret ignore rules before the owner supplies values. Never open/read `.env`,
   secret xcconfigs or credentials into model context, dump env/plist/build settings,
   put credentials in source, or embed management tokens.
6. Instrument only actual, reviewed categorical host actions with restrictive property
   keys. Await actor `track`; timer creation is nonisolated/synchronous and `stop` async,
   returning milliseconds once. Let the SDK own native lifecycle when enabled; no
   per-window scene forwarding or manually tracked reserved lifecycle events. Never
   collect document/path/window/clipboard/payment contents or arbitrary error messages.
7. Complete the guide's acceptance checks: SDK/adapter and host builds/tests, disabled
   smoke first, injectable contract tests (doubles allowed), signed app restart with real
   Keychain persistence, consent revoke/denied relaunch, native lifecycle capture exactly
   once, and graceful quit. Do not send real events without explicit approval for a
   controlled development/staging smoke. Verify server ingestion separately; counters
   and flush are not receipts. Do not claim live delivery, absent host migrations or
   signed-app validation without actual evidence.

Keep changes in the host app. Update its existing task list/docs as appropriate and
report files changed, recorded SDK pin, actual checks/results and blockers/skipped checks.
Do not commit or push unless the user subsequently asks.