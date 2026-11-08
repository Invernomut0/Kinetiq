---
description: "Use when modifying Kinetiq Swift telemetry: generic TelemetrySDK core, official Firebase Analytics, explicit consent, private signing scope and acceptance gates."
applyTo: "**/*.swift"
---

# Kinetiq Firebase Analytics host integration

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
  kinetiq-75593 / io.github.invernomut0.Kinetiq; `IS_ANALYTICS_ENABLED=false` requires
  owner console Analytics-link review, **not backend validation**. Service-account
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