---
description: "Use when modifying Kinetiq Swift telemetry: consented direct GA4 Web transport, native Firebase signing fallback, generic core and acceptance gates."
applyTo: "**/*.swift"
---

# Kinetiq Firebase Analytics host integration

## Current owner-authorized GA4 follow-up (0.3.4)

- Owner explicitly requests direct Web GA4 Measurement Protocol with the ingestion
  secret embedded in the app; the extractable secret allows event spam. This is not
  native Firebase Analytics or the recommended server-only MP deployment. Never
  embed service-account/admin credentials, print secrets, or claim secret secrecy.
- Build reads only root `.env` keys `KINETIQ_GA4_MEASUREMENT_ID` and
  `KINETIQ_GA4_API_SECRET` as bounded data, never shell execution/expansion. This
  supersedes the historical no-root-dotenv ingestion rule below for these two keys
  only. Never read their values into chat/tools output. Bundle only the closed
  `KinetiqGA4Configuration.plist` schema `measurement_id` / `api_secret`, main app only.
- A valid GA4 configuration takes precedence over native Firebase and does not
  initialize the Firebase singleton or use its signing/Keychain gate. Invalid present
  GA4 configuration fails closed; missing configuration allows historical native fallback.
- Keep single owner and generic pinned core. GA4 has fresh consent/decision keys
  `kinetiq.telemetry.ga4.analytics` / `analyticsDecision` and separate local identity;
  no transfer of previous Firebase/PostHog consent or UUID. Default Don't Share.
- Use Web `measurement_id` / `client_id`; never invent a Firebase `app_instance_id`.
  Only actual `feature_used` / `feature=privacy_settings`. Deny ads consent, omit
  automatic native events/device metadata and invented engagement time. Web session
  ID uses actual Date; measure real foreground intervals with ContinuousClock only
  after consent, omit zero engagement, stop observers on withdrawal. Disclose actual
  timing, partial session/realtime reporting and connection IP/network visibility.
- Settings' cancellable task is keyed by readiness/enabled/consent, never busy:
  granting while already mounted records one actual visible visit, not Overview/startup.
  Show only sanitized transport categories/counts/HTTP codes, never URLs or errors.
  Filtering core installation events is expected, not a failed transport request.
- Ephemeral HTTPS transport: no cookies/cache/credentials/redirect/retry, bounded
  requests/timeouts, cancel on withdrawal; no recall or remote-erasure guarantee.
- Owner requested a validation probe: explicit `configure-ga4.py --validate` may
  call only `/debug/mp/collect` without manipulating app consent. It does not collect
  report events or authenticate credentials. Ordinary tests/smoke remain offline.
  Production receipt/ingestion requires an actual owner-consented Settings visit and
  console verification; HTTP 2xx alone is not evidence of ingestion.

## Historical native Firebase rules (still apply to native fallback)

Apply only to telemetry-related Swift work. [Current guide](../../docs/telemetry.md)
supersedes provider/configuration/identity guidance in the historical copied
`Documentation/COPILOT_INTEGRATION.md`; preserve that source copy and its MIT notice.

- Keep TelemetrySDK 0.1.1 **generic core only**, product `Invernomut0Telemetry`, pinned
  sibling SHA `c5e275421fa03c242c9c53b5431d919fdd18547a`; do not edit the external SDK.
  Remove the PostHog adapter/dependency, not core privacy/MIT resources. Product ID
  remains `kinetiq`; preserve bundle release/build values.
- Official Firebase Apple SDK **12.6.0**, official-manifest GoogleAppMeasurement
  **12.5.0**; native macOS Analytics supported since SDK 8.9. Select FirebaseCore and
  FirebaseAnalyticsCore **without AdSupport/IdentitySupport**, no Auth/FCM/Crashlytics/Sentry.
  No Firebase products/configuration/entitlements in saver or preview targets.
- Reuse the single AppDelegate-owned `KinetiqTelemetry` and Settings injection, no
  second facade/client/delegate. `@MainActor FirebaseAnalyticsProvider` controls the
  official singleton; configure **only after consented start**. Disable core native
  lifecycle; never forward core installation/lifecycle/reserved events or window events.
- New Boolean consent/decision keys: `kinetiq.telemetry.firebase.analytics` and
  `kinetiq.telemetry.firebase.analyticsDecision`; default Don't Share with actual
  Firebase disclosure. Old PostHog consent/UUID remain untouched and are not reused.
  No old Keychain store, UUID alias, Firebase user ID or admin credentials.
- Check the actual Apple signature's private Keychain group first: exactly real
  `TeamID + ".io.github.invernomut0.Kinetiq"`. Application-factory default readiness
  does not bypass this check. Missing group disables analytics controls with categorical
  status; ad-hoc stays `blocked_off`, product features work. Signing helper derives
  only the own private Data Protection scope from the existing real Apple Team identity;
  no invented team, ad-hoc entitlement, broad sharing or Keychain password/access-UI automation.
- Root `GoogleService-Info.plist` is owner-supplied client metadata, parsed with a
  65,536-byte bound and typed allowlist; never edit/dump it, its API key, `.env`,
  preferences/private UUIDs or certificates. Missing config means unavailable. No
  sibling dotenv ingestion; old config ignored, not deleted. Client match is
  kinetiq-75593 / io.github.invernomut0.Kinetiq; the owner confirms console Analytics
  is active, and `IS_ANALYTICS_ENABLED` is not authoritative console state or backend
  validation. Service-account
  email is not auth configuration; never embed admin JSON.
- Keep ten plist defaults false: Analytics/data collection, analytics/ad storage,
  ad user data/personalization, IDFV, ad-network registration, automatic screen reporting,
  delegate proxy. After consent, Firebase may collect device/OS, app-instance/session
  and IP/location/network metadata. Never promise no OS/hardware or network anonymity.
  Forward only actual `feature_used` / `feature=privacy_settings`, no custom content.
- Serialize and await existing initialization/control gates; kill switch is not consent.
  Persist grant after successful startup and local false before cleanup. Revoke with
  collection false, all consent denied and best-effort `resetAnalyticsData()` (no callback).
  No forced/awaited public flush, delivery acknowledgement or remote-erasure claim;
  preserve bounded native quit. Later submissions must remain suppressed.
- Preserve SDK source Apache and googleappmeasurement LICENSE/README plus official
  FirebaseAnalytics.podspec Copyright 2022 Google metadata under ThirdPartyLicenses/binary.
  The macOS Analytics ZIP has no privacy bundle/terms file: invent neither and do not
  call Analytics binaries Apache/open source. Remove old PostHog/PLCrashReporter/libwebp/
  Sentry symbols/resources/vendor licenses from bundles, preserving core notices.
- Record actual tests/build/signing-state logs/coverage only when proven; F1 remains
  Doing and F2 owner Review until evidence/approval. Historical 328/330/334 results
  and intended 33 contracts are not Firebase pass counts. Real console, consented
  lifecycle/offline/in-flight delivery and notarization require owner review; disabled
  smoke/counters are not ingestion receipts. Never automate consent or live probes.