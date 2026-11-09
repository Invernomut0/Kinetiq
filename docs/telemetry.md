# Kinetiq telemetry integration

## Current: configured country for GA4 — v0.5.1 / build 44 (2026-11-09)

**Task 24 Done — Copilot, implementation and verified local acceptance only.**
The owner's explicit request to use the macOS configured region for GA4 Country
supersedes the earlier no-`user_location`/no-Locale-inference restriction **only for
configured country**, not physical position, citizenship or City.

### Country-only payload and consent lifecycle

- Read only `Locale.current.region?.identifier`, inside consented `provider.start`
  after `configuration.enabled && privacy.analyticsEnabled`; not at construction,
  prompt presentation, denied startup or in the static payload builder.
- Typed optional `GA4ConfiguredCountry` accepts only the **249 assigned ISO 3166-1
  alpha-2** country/territory codes, not merely arbitrary two letters. Foundation's
  larger regional catalog includes macroregions and reserved/user-assigned codes;
  `EU`, `001`, `UK`, `XK` and `ZZ` are omitted, without alias invention. The provider snapshots it
  only in memory until stop/withdrawal, clears it there, and refreshes it on the next
  consented start. No persistence or per-event Locale lookup is authorized.
- Pass that optional country explicitly to the static builder, whose country argument
  defaults to `nil`. A valid country yields only top-level JSON
  `user_location: {country_id: <ISO 3166-1 alpha-2>}`. Nil/invalid input omits the whole
  object, without language/time-zone fallback or lookup.
- Use standard **Country**, **no custom country event parameter, user property or
  custom definition**. Existing six events/five custom keys are unchanged. No GPS,
  IP lookup, external geolocation service, new network permission, `ip_override`,
  fabricated city or `region_id` is introduced.
- Google's [Measurement Protocol reference](https://developers.google.com/analytics/devguides/collection/protocol/ga4/reference#payload_geo_info)
  marks geographic fields optional: `country_id` alone is valid. Its recommendation
  to provide `country_id` and `region_id` is not a requirement or permission to invent
  a subdivision. Property-level granular-location settings still apply.
- Configured region is **not citizenship or physical geolocation**. This explicit
  country can override GA4's country attribution and distort reports/maps. No real
  City/position or ingestion is claimed. If omitted, Google's documented tagging-
  history derivation may leave this MP-only identity's geography `(not set)`;
  connection IP alone is not promised to populate reports. Native geography remains
  conditional on actual enablement behind its unchanged gates.

GA4 requires **consent revision 3** at `kinetiq.telemetry.ga4.usageConsentRevision`,
disclosing configured country. A prior revision-2 grant stays runtime **off** until
a new explicit prompt/Settings choice; **Don't Share** remains default. Native
Firebase stays at **revision 2** at `kinetiq.telemetry.firebase.usageConsentRevision`.
Preserve existing consent/decision/identity namespaces and UUID retention, without
migration or cross-mode grants. Configuration/kill switch never grants consent.
Stop/revocation clears country memory, not transmitted bytes or server records.

The host `PrivacyInfo.xcprivacy` conservatively declares **CoarseLocation**, analytics,
non-tracking and linked to the stable pseudonymous client identifier for this Country
field. This is a declaration of transmitted country data, not permission to measure
physical location. No precise-location type or new required-reason API is added.
The source is still a regional preference, not GPS. App Store labels, Google processing
and distribution privacy remain owner review, not a compliance certification.

### Local acceptance — task 24

| Local gate | Verified result | Evidence |
|---|---|---|
| Complete final Release | **414 = 230 app + 36 Effects + 148 Core; zero failures/skips, exit 0** | `/tmp/kinetiq-country-final-release.log` |
| Analytics included above | **89 = 34 GA4 + 50 owner/native + 5 taxonomy**; seven new Country/manifest contracts | Same complete suite |
| ISO and consent | All 249 assigned codes; unsupported/missing omitted; event properties cannot spoof geography; consent-only read/snapshot/clear/refresh; revision-2 off, revision-3 relaunch identity retained, native revision 2 unchanged | Same complete suite, public ISO/Locale data and isolated storage only |
| Universal packaging | Actual **0.5.1 / 44**, app and saver each **x86_64 + arm64**, build exit 0 | `/tmp/kinetiq-country-build.log`; direct version/architecture checks |
| Strict signatures / bundle / disabled smoke | Both signatures passed; `KINETIQ_TELEMETRY_BUNDLE_CHECK_SUCCESS`, `KINETIQ_TELEMETRY_DISABLED_SMOKE_SUCCESS` | Direct fixed-success checks |

Actual matching LLVM **Lines**, not Regions:

| Component | Total lines | Missed lines | Line coverage |
|---|---:|---:|---:|
| `GA4ConfiguredCountry.swift` | 7 | 1 | **85.71%** |
| `GA4MeasurementProtocolProvider.swift` | 282 | 64 | **77.30%** |
| `KinetiqTelemetry.swift` | 290 | 8 | **97.24%** |
| `TelemetryPrivacyView.swift` | 97 | 10 | **89.69%** |
| `KinetiqUsageEvent.swift` | 54 | 0 | **100.00%** |
| `FirebaseAnalyticsProvider.swift` | 60 | 48 | **20.00%** |

Report `/tmp/kinetiq-country-coverage.txt`; profile
`/tmp/kinetiq-country-final-release.profdata`; matching binary
`/tmp/kinetiq-country-final-KinetiqTests`, preserved before the post-doc run.
The actual `Locale.current` getter/default closures are intentionally unexecuted in
tests, which must not read the user's configured region. Live requests/responses,
30-minute session boundary and native Firebase startup/delivery/reset remain unverified.
No ingestion, exhaustive integration, Debug suite or Metal branch coverage claim.

The owner subsequently requested a GitHub release and installation/first-launch
instructions (task 25). Final post-edit captured-README optics and release asset
verification are tracked there, not inferred from this suite. The earlier focused
compile had two negative test events missing mandatory properties; corrected before
the 88-test focused pass and the final 414-test suite. The first complete 413-test
suite passed before adding the seventh manifest test; final acceptance is 414.

### Release preparation — task 25

**Doing — Copilot, remote publication pending.** The owner explicitly requested
GitHub release/tag/DMG publication, superseding the earlier no-release scope for
publication only. No live analytics, real preferences, normal user-app lifecycle,
billing settings or branch protections are changed.

- Final post-documentation **90 passed = 89 analytics + 1 actual captured-README
  optics**, zero failures/skips, exit 0 (`/tmp/kinetiq-country-postdocs.log`). The
  actual optics Test Case passed in **2.672 seconds**, with unchanged assertions.
- `Kinetiq-0.5.1.dmg` created from the verified app, checked by `hdiutil verify`,
  mounted read-only and compared byte-for-byte with the packaged app. Both app/saver
  signatures, actual version/build **0.5.1/44** and both **x86_64 + arm64** slices
  passed. Image detached afterward (`/tmp/kinetiq-country-dmg.log`). No app launch.
- `SHA256SUMS.txt` matches the actual image; `shasum -a 256 -c` reports **OK**.
  Source and private owner files are not release assets. The authorized bundled
  GA4 ingestion secret remains extractable; no server-only secrecy is claimed.
- README installation explains DMG versus source archives, required permissions,
  menu-bar lifecycle and non-notarized/ad-hoc limitations. Prefer **Open Anyway**;
  targeted `xattr -dr com.apple.quarantine` removes only quarantine within the trusted
  app, unlike `xattr -cr` which clears all extended attributes. No global Gatekeeper
  disabling, elevation or malicious/damaged-app warning bypass is recommended.
- Normal branch/PR merge, annotated tag and remote release/asset digest verification
  remain publication steps, not inferred from the local DMG. Hosted CI remains
  separately verified/reported; historical PR #6 billing failure is not a new pass.

No normal app start, real consent/preferences change, live probe or console automation
is authorized here. **G2/F2 Review — Lorenzo** retain live ingestion, privacy/distribution
and native signing review. **PR #6 is merged**; its hosted job was **not started**
because of account billing/spending limits. Owner Billing & plans review and Actions
rerun remain open, not hosted CI success or evidence for a new PR.

## Historical scope and local acceptance: product usage — v0.5.0 / build 43 (2026-11-09)

The revision-2 consent and no-country-override policy below describe task 23, not
build 44. Its six-event/five-key taxonomy and ownership/transport bounds remain the
current baseline; task 24 changes only the authorized country field and GA4 consent
revision. All task-23 tests, coverage and packaging evidence remain historical.

**Task 23 Done — Copilot, implementation and local acceptance only.** The owner explicitly
authorized broader categorical product analytics, superseding the earlier
privacy-settings-only scope, **not** its consent, transport or native-signing gates.
The production implementation uses `KinetiqUsageEvent.swift`; the generic TelemetrySDK
core is unchanged. Earlier acceptance sections below are historical records only.

### Historical consent revision 2, separate modes and retained ownership

The existing Boolean consent/decision keys remain separate for GA4 and Firebase.
Revision **2** is required at `kinetiq.telemetry.ga4.usageConsentRevision` or
`kinetiq.telemetry.firebase.usageConsentRevision`, respectively. An older true grant
without revision 2 leaves runtime analytics **off** and requires an updated disclosed
prompt or explicit Settings choice. **Don't Share** remains default; no old grant is
silently extended. Legacy decisions and identities are preserved, not transferred
between modes. Merely presenting the prompt, configuration or the runtime kill
switch does not grant consent. Withdrawal retains the existing suppression/cleanup
semantics; it is not a remote deletion guarantee.

The single AppDelegate-owned `KinetiqTelemetry` remains the only client owner.
Product hooks use its **weak static** emission reference; they never create a second
owner or enable analytics. At most **four immediate product-event tasks** are
admitted, without queue or replay; busy/denied/overflow actions are dropped. GA4 retains the
existing **four in-flight network requests** cap, ephemeral transport, no disk queue
or retries and withdrawal cancellation. These are separate bounds, not a delivery
guarantee. Best-effort accepted/submitted counters and drops are **not an exact usage
census**, even with consent. The core pin and native fallback signing/Keychain gates
are unchanged. No SDK, analytics owner or telemetry configuration is added to the
screen saver host.

### Retained current event taxonomy (introduced in v0.5.0)

Both provider boundaries validate the same typed, closed allowlist. The only custom
property keys are `feature`, `effect_id`, `trigger`, `action` and `quality`; only the
relevant keys below are emitted per event. Unknown event names/values are rejected
and extra properties are not forwarded.

| Event name | Custom properties and allowed values | When it counts |
|---|---|---|
| `feature_used` | `feature`: `privacy_settings`, `animation_studio`, `effects_library`, `layouts`, `performance`, `rules`, `screen_saver` | Actual feature visits, including the Studio/Lab; no automatic startup/Overview event. |
| `effect_played` | `effect_id`, `trigger` | Only an actual successful playback **start**, not an attempted or completed playback. |
| `effect_selected` | `effect_id`, `trigger` | Explicit selection/assignment, separate from playback. |
| `studio_action` | `action`: `layer_added`, `layer_removed`, `keyframe_added`, `saved`, `imported`, `exported` | Validated edits and successful save/import/export actions; no document payload. |
| `screensaver_action` | `action`: `enabled`, `disabled`, `preview_started` | Actual app-side enable/disable and in-app preview starts, **not** macOS saver-host runs. |
| `quality_changed` | `quality`: `auto`, `low`, `balanced`, `high`, `ultra` | Explicit quality choice, **not** automatic budget/thermal adaptation. |

Effect IDs are the stable IDs of all **66 actual `LibraryEffect.all` entries**,
plus `custom` (one sentinel for every user composition) and `wobbly_classic`.
`off` and `random` are allowed **only for `effect_selected`**, never as played IDs.
Triggers are `drag`, `open`, `close`, `minimize`, `manual`, `layout`, `maximize` and
`resize`. Manual try/run actions stay distinct from native triggers; explicit
layouts use `layout`. Automatically looping library/Studio/layout previews do not
generate playback counts. A selection does not prove a later play; a successful
start does not prove completion or ingestion.

No custom names, composition IDs/content, application IDs, window titles/IDs/geometry,
documents, images, paths, precise location, hardware metadata or free-form properties
enter this custom event schema. GA4 mode still omits automatic native/core lifecycle
and OS/device metadata, denies advertising user data/personalization and uses only
actual session/positive consented foreground timing, not fabricated engagement.
Native Firebase's possible automatic metadata, **if actually enabled** after its
existing gates, remains separately disclosed; this scope does not enable that fallback.

### Historical geography policy — v0.5.0/build 43 only

At task 23, the owner was unavailable when asked about an external geolocation service; the
least-collection option was chosen. **No new external geolocation service**, GPS,
IP lookup, `ip_override` or `user_location` is used. Locale and time zone are not
location evidence and are not substituted for City/Country.

Google still receives connection IP/network metadata. However, the official
[Measurement Protocol reference](https://developers.google.com/analytics/devguides/collection/protocol/ga4/reference)
documents geography derived from **tagging history** when `user_location` and
`ip_override` are absent. The separate MP-only Web client identity may have no such
history: **City and Country may remain `(not set)`**. Do not promise that the
connection IP alone populates these reports. Native Firebase may derive geography
**if actually enabled**, not because this release enabled it. Property-level
granular-location restrictions, reporting thresholds and VPN/proxy routing can also
limit, suppress or distort geographic results. No precise or reliable city is promised.

## Practical GA4 report setup

These are **manual owner steps**, not performed console changes. No administrator
credentials, console automation, new collection service or fabricated charts are
required or supplied by this task.

1. Select the intended GA4 property. With Editor/Administrator access, open
  **Admin → Data display → Custom definitions → Custom dimensions → Create custom
  dimension**. For each row below, select scope **Event** and enter the exact event
  parameter; the display name can be the readable label.

  | Dimension label | Event parameter | Scope |
  |---|---|---|
  | Effect ID | `effect_id` | Event |
  | Trigger | `trigger` | Event |
  | Feature | `feature` | Event |
  | Action | `action` | Event |
  | Quality | `quality` | Event |

2. Save each definition. Google documents **24–48 hours after custom data is sent
  and the definition is created** before report use. Do not promise retroactive
  availability for events predating creation, immediate data or Realtime coverage.
  Official steps: [Create event-scoped custom dimensions](https://support.google.com/analytics/answer/14239696).
3. In **Explore → Free form**, import Event name, Effect ID and Trigger plus the
  **Event count** metric. Set rows to Effect ID, columns/breakdown to Trigger,
  values to Event count, and filter **Event name exactly matches `effect_played`**.
  Sort descending by Event count. Exclude **Trigger exactly matches `manual`** to
  rank non-manual usage; to rank native automatic window usage alone, also separate
  or exclude `layout`. A separate `trigger=manual` view answers manual try/run usage.
4. For assignments, use **`effect_selected`**, not the playback report. Off/Random
  belong here. Selection count is **not play count**. For feature visits use
  **`feature_used`**, rows Feature; for Studio edits/save/import/export use
  **`studio_action`**, rows Action. Filter **`screensaver_action`** by Action for
  app-side enable/disable/preview, never as a system saver-run count. Use
  **`quality_changed`**, rows Quality for explicit quality choices only.
5. **Country is built-in**, not a custom definition: use standard **Country** with
  Event count to inspect the consented configured-country field. Do not add a custom
  country event parameter/definition. It can override GA4 attribution and distort
  maps; it is not citizenship or physical position. **City is also built-in but is
  not supplied or promised by this change.** Retain `(not set)` and check date range,
  granular-location settings, thresholds and attribution limits. Do not enable more
  collection to fill empty charts by
  default. HTTP **2xx/204 only acknowledges HTTP receipt, not GA4 ingestion**;
  submitted counts and debug validation are not proof of report availability.

## Local acceptance — task 23

**Historical v0.5.0/build 43 only; not task-24/build-44 acceptance.**

| Local gate | Verified result | Evidence |
|---|---|---|
| Complete final Release | **407 = 223 app + 36 Effects + 148 Core; zero failures/skips, exit 0** | `/tmp/kinetiq-usage-final-acceptance.log` |
| Analytics contracts included above | **82 = 50 owner/native-boundary + 27 GA4 + 5 taxonomy**; both same-turn save/assignment and layer/import actions retained | Same complete suite |
| Post-documentation recheck | **83 passed = 82 analytics + 1 actual captured-README optics; zero failures/skips, exit 0** | `/tmp/kinetiq-usage-postdocs.log` |
| Isolated native capture recheck | All **15 CatalogRuntime tests passed**, unchanged assertions | `/tmp/kinetiq-usage-catalog-isolated.log` |
| Universal packaging | **0.5.0/build 43**, app and embedded saver each **x86_64 + arm64**, build exit 0 | `/tmp/kinetiq-usage-build.log`; direct version/architecture verification |
| Deep/strict signatures | App and embedded saver both passed | Direct `codesign --verify --deep --strict` checks |
| Bundle / signed disabled smoke | `KINETIQ_TELEMETRY_BUNDLE_CHECK_SUCCESS` and `KINETIQ_TELEMETRY_DISABLED_SMOKE_SUCCESS` | Direct fixed-success output; no saved check log claimed |

Earlier focused/full runs encountered existing native capture/window-origin failures,
including `InvalidTransition { phase: idle, targetPhase: failed(deinit) }` from the
native capture path and helper origins changing during an overview that does not move
windows. Logs remain `/tmp/kinetiq-usage-focused.log`,
`/tmp/kinetiq-usage-final-release.log` and `/tmp/kinetiq-usage-acceptance.log`.
The isolated runtime recheck and final complete suite passed without runtime fixes,
test changes, weaker assertions, stopping the user's app or exclusion bypasses.
This records observed instability, not a claim that its external cause was proven.

Actual matching Release LLVM **Lines**, not Regions:

| Component | Total lines | Missed lines | Line coverage |
|---|---:|---:|---:|
| `KinetiqUsageEvent.swift` | 54 | 0 | **100.00%** |
| `KinetiqTelemetry.swift` | 287 | 7 | **97.56%** |
| `GA4MeasurementProtocolProvider.swift` | 275 | 63 | **77.09%** |
| `FirebaseAnalyticsProvider.swift` | 60 | 48 | **20.00%** |
| `TelemetryPrivacyView.swift` | 97 | 10 | **89.69%** |

Report: `/tmp/kinetiq-usage-coverage.txt`; profile:
`/tmp/kinetiq-usage-final-acceptance.profdata`; matching binary:
`.build/out/Products/Release/KinetiqTests.xctest/Contents/MacOS/KinetiqTests`.
The real core and recording provider boundary establish consent, filtering and
cancellation contracts, not server delivery. Live network tasks/responses/cancellation,
the 30-minute session boundary and native Firebase startup/delivery/reset remain
unexecuted at runtime. Taxonomy 100% Lines does not imply exhaustive integration,
native lifecycle or Metal shader branch coverage. No new complete Debug claim is made.

No normal user-app restart, real consent/preferences change, live event/probe or
console automation was performed. The task-23 instruction to reopen build 43 is
historical, not an instruction to launch the current app. G2/F2 live-ingestion/privacy/distribution
gates remain owner Review; no native fallback enablement, report ingestion, hosted CI
success, new DMG or release publication is implied by these local checks.

**Hosted CI — blocked before execution (merged PR #6):** GitHub's `host` annotation says
the job was not started because recent account payments failed or the spending limit
must be increased. This is not a test result: no hosted build/test pass is claimed.
Owner Lorenzo must review **Billing & plans** and rerun Actions after resolving the
account restriction. No billing settings, workflow checks or branch protections are
changed or bypassed by this task; local acceptance above remains separate evidence.

## Historical: privacy-settings-only GA4 Web transport — v0.3.4 / build 39 (2026-11-08)

Everything in this section through its acceptance table and coverage records
describes the **earlier scope and verification**, not v0.5.1/build 44 acceptance. References
to “current”, the lone Privacy & Analytics action, dates, configuration checks and
owner instructions below are historical statements. The current mode-specific consent scope,
geography limits and remaining owner gates above take precedence; no old grant is extended.

**VERIFIED LOCAL — G1 Done, owner Copilot, for implementation and offline/local
acceptance only; G2 Review, owner Lorenzo.** Current complete Release and Debug each
passed **361 tests, 0 failures, 0 skips, exit 0**; focused contracts, Python and final
local package checks are verified below. Historical native Firebase F1/F2 evidence
is not GA4 acceptance. No live ingestion,
authentication, realtime availability or distribution approval is claimed.

### Actual provider selection, consent and identity

`TelemetryHostConfiguration.load()` selects a valid main-bundle
`KinetiqGA4Configuration.plist` before parsing native Firebase metadata. Present
invalid/unreadable/oversized GA4 configuration throws and fails closed, without native
fallback. Absence retains the native fallback and its actual Apple private signing
gate. FirebaseCore + FirebaseAnalyticsCore remain linked, but the native singleton is
not configured or started when GA4 is selected. This is a **Web stream**, not the
native Firebase app stream or a replacement native Firebase installation identifier.

The existing `AppDelegate` retains **one** `KinetiqTelemetry` and one generic
TelemetrySDK `TelemetryClient`; the approved unmodified core pin remains
`c5e275421fa03c242c9c53b5431d919fdd18547a`. No SDK adapter, second owner or per-window
client is added. The GA4 provider and owner are main-actor serialized.

Fresh Boolean-only consent keys are `kinetiq.telemetry.ga4.analytics` and
`kinetiq.telemetry.ga4.analyticsDecision`, default off. Previous Firebase/PostHog
decisions and identifiers are untouched and not transferred. The existing native
sheet discloses GA4; **Don't Share** is default, and only explicit **Enable Analytics**
or the Settings control grants consent. Configuration is not a grant. A remembered
decline is not repeatedly prompted; unanswered exits can prompt on next launch.

The host injects `TelemetryPreferenceIdentityStore` with product namespace
`kinetiq.ga4`. The separate UUID at `kinetiq.ga4.telemetry.installationID` is created
only when consented analytics starts. Two 32-bit portions are mapped to the stable
numeric `number.number` Web `client_id`; the raw hyphenated UUID is not transmitted.
It persists
across launches and withdrawal; malformed identity fails closed. There is **no
Keychain access**, old-item read/migration/deletion, user ID or identity aliasing in
GA4 mode. App-local preferences are not credential-grade storage or secure erasure.

### Actual collection and transport limits

Only an actual visit to the mounted Privacy & Analytics Settings section during
consent is forwarded: `feature_used` with exactly `feature=privacy_settings`.
The reported “no data arrives” bug was an actual SwiftUI one-shot `.task` that ran
before consent was granted and did not rerun afterward. The task is now keyed by
readiness, runtime enablement and consent, **not busy state**. It waits 100 ms for
the actual visible visit and is cancellable on disappearance or eligibility changes;
it does not manufacture a visit on startup or Overview.
`FirebaseAnalyticsPolicy.parameters(for:)` is shared as a pure allowlist; its name
does not start Firebase. The builder drops other event properties and checks the
event identity against the provider's installation UUID. Core/native lifecycle is
disabled; no automatic installation, app/session/window events, crash reporting,
OS/hardware metadata, window titles, screenshots, documents or arbitrary errors
are sent. Payload advertising user data and personalization are explicitly **DENIED**;
no advertising identifier is sent. Native Firebase automatic collection is dormant.

Requests use HTTPS `www.google-analytics.com/mp/collect`, with the Web measurement
ID and ingestion secret in the query and the separate `client_id` in the body.
Google sees the connection **IP and network metadata** and may derive location:
this is not network anonymity or a legal-compliance certification. A positive
`session_id` is derived from the actual `Date` and refreshed after 30 minutes without
approved actions. Actual foreground time is measured with `ContinuousClock` only
after consent, using NSApp activation/deactivation notifications.
`engagement_time_msec` is attached to the approved action only when positive; zero is
omitted. This is not synthetic time, a heartbeat, an automatic session event or
instrumentation of unapproved actions. No automatic startup/Overview events or fake
engagement are added to fill graphs. Reports may remain partial; no realtime or
session-metric availability is promised.

Starting creates local ephemeral URLSession state only, not a request. Cookies,
credential storage and URL cache are disabled; redirects are rejected, with at most
four in-flight requests, request/resource timeouts of 8/10 seconds, no disk queue,
retry or ingestion acknowledgement. Raw responses, URLs, errors, identifiers and
credentials are never logged. Settings exposes sanitized `transportStatus`: ready,
number submitted, in-flight count, HTTP accepted and categorical failure. An HTTP
accepted result is **not ingestion confirmed**. Filtered core installation events
are not failures. `submittedRequests` is not a delivery receipt; `flush()` is a no-op.

Withdrawal persists false before cleanup, suppresses later submissions, cancels
pending tasks and clears local transport memory. Generation checks isolate old
completions from new starts. The independent kill switch never grants consent.
Shutdown uses the existing serialized owner and bounded app quit; cancellation
cannot recall received bytes or erase server records. Local UUID retention is disclosed.

### Owner configuration and explicit deployment risk

The owner explicitly authorized bundling a direct GA4 **ingestion secret**. It is
extractable from the distributed app and can enable forged/spam events. This
desktop placement is contrary to the recommended **server-only secret deployment**;
it is not a secret-authentication boundary. No administrator/service-account JSON,
private key or admin SDK belongs in the app. Console Analytics is active **per owner**;
neither that statement nor the native client plist establishes Web-stream ingestion.
`IS_ANALYTICS_ENABLED` in native metadata is not authoritative console state.

Local root `.env` is ignored and consumed only by the build/test process, never
returned to tools/model/chat or committed. Do not inspect/dump `.env`, native
GoogleService values, preferences or private identifiers. `scripts/configure-ga4.py`
recognizes only `KINETIQ_GA4_MEASUREMENT_ID` and `KINETIQ_GA4_API_SECRET`; it reads
bounded UTF-8 data (65,536 bytes), without sourcing, evaluation or expansion.
Unrelated lines are ignored, including malformed unrelated assignments. Duplicates,
partial input and recognized keys without `=` reject. Optional matching outer quotes
are literal. Accepted ID syntax is `G-` plus uppercase ASCII letters/digits; secret
syntax is 1–256 ASCII letters/digits/underscore/hyphen, **not a fixed 22-character rule**.
Placeholders, invalid types and unsafe syntax reject; no arbitrary valid credentials
are invented for tests.

Packaging writes only exact `measurement_id` / `api_secret` keys to
`Kinetiq.app/Contents/Resources/KinetiqGA4Configuration.plist` (0600), before signing.
Only `.app` with `io.github.invernomut0.Kinetiq` is accepted. No dotenv file, unrelated
key or administrator field is copied, and the saver is rejected. Absence removes stale
GA4 resources; invalid presence rejects packaging. Runtime reads the main bundle
resource, **not runtime `.env`**. Python and Swift both bound reads and require a
closed two-field schema; the runtime also rejects common sentinel secret words.

Offline standalone command:
`python3 -m unittest discover -s scripts -p test_ga4_config.py -v`.
Positive cases consume only the real owner configuration via `module.load_env` inside
the test process; they skip when absent and fail categorically if invalid. Temporary
app metadata is copied from actual `Resources/Info.plist`. Comparisons of real
credentials are Boolean assertions, never credential-bearing `assertEqual` output.
The suite uses no network mocks, patches or live requests. The telemetry and release
workflows include this offline suite; ignored owner credentials are not uploaded to CI.

The actual local **`build/Kinetiq.app` contains the owner's bundled GA4 configuration**.
The two ignored root `.env` keys remain local only; GitHub CI credentials have **not
been uploaded or provisioned**. Workflow packaging without the owner's `.env` removes
GA4 configuration and uses the safe native fallback, currently
`KINETIQ_FIREBASE_SIGNING_BLOCKED_OFF`. It does **not** produce a configured GA4
release app. Hosted CI execution is unverified, and local packaging does not
establish publication of a new DMG.

Optional explicit owner command: `python3 scripts/configure-ga4.py --validate`.
It contacts only Google's **debug** Measurement Protocol endpoint with a separate
validation identity encoded in the same numeric Web format and a structure-check payload.
The current validation-only payload uses an actual positive session value and, only
when positive, elapsed probe-preparation timing; that metric is **not app engagement**.
Fixed statuses/counts only;
the debug endpoint does **not authenticate the secret or prove report ingestion**.
This is not an automatic CI test. The explicitly requested local probe initially returned
`VALUE_INVALID` for the raw hyphenated UUID `client_id`. The numeric Web mapping above
corrects that response in both Swift and Python. The current explicitly requested
**session-aware** Google debug probe returned **0 validation messages and exit 0**.
Its real positive Web session ID and optional measured preparation timing validate
the payload structure only; preparation timing is **not app engagement**. The debug
endpoint does not collect this probe into reports, authenticate the measurement
ID/secret or establish property ingestion. Ordinary tests and the disabled signed
smoke remain offline.

### Owner check and troubleshooting FAQ

- **Which stream is configured?** The reported categorical runtime check matched
  root/bundle configuration to the Web stream's public measurement ID
  **`G-NWQ84487HV`**, with same configuration `true` and GA4 consent typed `TRUE`.
  No app process was running at the reported process check. Configuration matching
  and consent alone do not prove requests, launch of the current fix or ingestion.
  Reopen the actual **`build/Kinetiq.app`**, not an older installed copy: its bundled
  GA4 resource is present. Native fallback `KINETIQ_FIREBASE_SIGNING_BLOCKED_OFF`
  is **not GA4 unavailability**; GA4 needs fresh default-off consent, not Keychain.
- **Where should I look for today's event?** The supplied Home screenshot covers
  **November 1–7**, while the current date is **November 8**; it excludes Today.
  Open **Reports → Realtime**, then visit the app's actual **Settings → Privacy &
  Analytics** section with explicit owner consent and inspect sanitized transport
  status. No test grants consent automatically or changes owner preferences.
- **Does HTTP 204 prove the secret is correct?** No. A successful HTTP transport
  response, including 204, does not authenticate the secret or confirm GA4 ingestion.
  Debug validation checks format only; actual console ingestion remains owner review.
- **Which ID belongs in the configuration?** Use the Web measurement ID beginning
  **`G-`**, not the numeric stream ID or native Firebase app ID. The ingestion secret
  must belong to that same Web stream; do not expose it while checking the console.
- **Does a website-tagging banner prove Measurement Protocol is broken?** No.
  That banner concerns website tagging and is not standalone proof of MP failure.
  Check the actual stream, date range, approved visit and categorical transport state;
  never add fake events or engagement just to populate graphs.

### Current acceptance gates

- **G1 Done — Copilot:** implementation and verified offline/local acceptance only.
  Version **0.3.4 / build 39**; exact current results follow. Historical native F1
  counts below remain unchanged and are not substituted for current GA4 evidence.
- **G2 Review — Lorenzo:** actual Web-stream credentials and console ingestion,
  owner-approved consented cold/relaunch and live offline/cancellation/revocation,
  IP/location/retention/access/erasure/privacy, extractable-secret spam risk, applicable
  terms, notarization and release provisioning remain open. Hosted CI execution is
  unverified; debug structure validation and HTTP acceptance are no substitute.
- **Native F2 remains open:** the fallback still requires a real Apple signature/private
  Keychain scope; GA4 bypasses this transport requirement, not the native gate. Do not
  request or invent unavailable Apple certificates/profiles or automate Keychain prompts.

| Current local gate | Verified result | Evidence |
|---|---|---|
| Complete Release | **361 = 179 app + 36 Effects + 146 Core; 0 failures, 0 skips, exit 0** | `/tmp/kinetiq-ga4-fix-release.log` |
| Complete Debug | **361 = 179 app + 36 Effects + 146 Core; 0 failures, 0 skips, `DEBUG_EXIT=0`**; app suite completed in approximately **1928 seconds**, not hung | `/tmp/kinetiq-ga4-fix-debug.log` |
| Focused Release | **55 = 21 GA4 Swift + 34 native contracts; 0 failures** | `/tmp/kinetiq-ga4-fix-focused.log` |
| Python GA4 | **26 passed; 0 failures/errors/skips, exit 0**, including the validation-only payload test | Current completed local suite |
| Native parser | **19 passed, 0 skips** | Current completed local suite |
| Signing | **5 ran: 4 passed, 1 skipped**; real-Team positive unavailable because no real Apple Team exists locally | Current completed local suite |
| Explicit session-aware Google debug probe | **0 validation messages, exit 0**; event structure only, not authentication/ingestion | Current explicitly requested local debug validation |
| Universal build | **`BUILD_EXIT=0`**; app and saver each **arm64 + x86_64** | `/tmp/kinetiq-ga4-fix-build.log` |
| Deep/strict signatures | Actual app and embedded saver both verified, **exit 0** | Direct terminal verification; no saved log claimed |
| Resource verifier | **Exit 0**, `KINETIQ_TELEMETRY_BUNDLE_CHECK_SUCCESS`; bundled GA4 configuration present in local app | Direct terminal verification; no saved log claimed |
| Signed disabled smoke | **Exit 0**, `KINETIQ_TELEMETRY_DISABLED_SMOKE_SUCCESS`; offline, no consent/events/vendor startup/Keychain UI | Direct terminal verification; no saved log claimed |

The actual native Settings regression uses the retained application owner and a
recording provider boundary: **mount while denied, grant while still visible without
navigation, exactly one approved event, then revoke**. GA4 disclosure was tested.
This is real native UI/owner acceptance, **not** a normal consented app GUI launch or
automated live GA4 collection. The complete suites include the actual README
capture-to-Metal optics regression. The focused post-documentation rerun using
`swift test -c release --filter 'LiquidIntegrationTests/testCapturedREADMEOpticsPreserveNativeTextContrast'`
passed the actual Test Case in **2.618 seconds: 1 test, 0 failures, 0 skips, exit 0**
(`/tmp/kinetiq-ga4-fix-postdocs.log`). The initial dot-filter attempt selected
0 tests and is not a successful regression run.

Actual Release LLVM **Lines**, verified using the report header, **not Regions**:

| Component | Total lines | Missed lines | Line coverage |
|---|---:|---:|---:|
| `GA4MeasurementProtocolProvider.swift` | 275 | 63 | **77.09%** |
| `KinetiqTelemetry.swift` owner | 240 | 7 | **97.08%** |
| `TelemetryPrivacyView.swift` | 97 | 10 | **89.69%** |
| `TelemetryPreferenceIdentityStore.swift` | 20 | 0 | **100%** |
| `FirebaseAnalyticsProvider.swift` native adapter | 61 | 48 | **21.31%** |

Matching binary:
`.build/out/Products/Release/KinetiqTests.xctest/Contents/MacOS/KinetiqTests`;
profile: `/tmp/kinetiq-ga4-fix-release.profdata`;
report: `/tmp/kinetiq-ga4-fix-coverage.txt`.
Approved exclusions are **not runtime-tested**: live URLSession data tasks, response
handling, cancellation and the 30-minute session boundary. Native live startup,
delivery and reset remain unverified. Local boundary contracts do not establish those
runtime paths, ingestion or exhaustive coverage; 100% store Lines is not 100%
integration or Metal branch coverage.

**Workflow:** Owner-requested publication uses commits/push on firebase, reviewed PR and normal merge into main. Git history and PR are publication evidence; local packaging is not new DMG release.

## Historical: PostHog → Google Firebase Analytics (2026-11-08)

**Migration acceptance: VERIFIED LOCAL — F1 Done, owner Copilot, for implementation
and offline/local acceptance only; F2 Review, owner Lorenzo.**
This section describes the earlier native Firebase migration, not current GA4 mode.
It superseded the older PostHog guidance below. Counts, logs and coverage are retained,
not recertified; native fallback signing and live gates remain open.
The complete final Debug and serialized restored-core Release suites each passed
**339 tests**, including **33 telemetry contracts**, with **0 failures, 0 skips**.
The verified local evidence and its limitations are recorded below; no pending owner
gate is marked complete.

### Ownership and selected products

- Keep the existing single `AppDelegate` → `KinetiqTelemetry` owner and injected
  Settings model; do not add a second facade, client or delegate. `FirebaseAnalyticsProvider`
  is `@MainActor` and owns access to the official Firebase singleton, configuring it
  **only after consented start**, not at app launch or consent-sheet presentation.
- Retain only TelemetrySDK 0.1.1 generic core `Invernomut0Telemetry`, pinned at
  `c5e275421fa03c242c9c53b5431d919fdd18547a`. The external SDK source stays unmodified.
  Remove the nested PostHog adapter and PostHog dependency from the host graph.
- Official Firebase Apple SDK **12.6.0** is a verified published version. Its official
  manifest selects GoogleAppMeasurement **12.5.0** binaries. Official Analytics supports
  **native macOS starting with SDK 8.9**; no Measurement Protocol workaround, API secret,
  admin SDK or external SDK adapter is needed.
- Select **FirebaseCore + FirebaseAnalyticsCore**, without AdSupport/IdentitySupport.
  No Auth, FCM, Crashlytics or Sentry; no Firebase dependency in Core, Effects, saver
  or preview targets. Disable TelemetrySDK native lifecycle to avoid duplicating
  Firebase's automatic app/session events; no custom per-window lifecycle forwarding.
- The copied `Documentation/COPILOT_INTEGRATION.md` and SDK-derived guidance remain
  **historical source copies**. Their previous PostHog instructions do not override
  this task or the current `.github/instructions/telemetry-integration.instructions.md`.
  Preserve the original core MIT notice and privacy bundle.

### Fresh consent and collection disclosure

Only actual Boolean values in `kinetiq.telemetry.firebase.analytics` and
`kinetiq.telemetry.firebase.analyticsDecision` represent the new consent and decision.
Default is **Don't Share**. Old `kinetiq.telemetry.analytics`,
`kinetiq.telemetry.analyticsDecision` and the PostHog installation UUID are untouched,
but neither consent nor identity carries over to Firebase. A remembered decline does
not cause repeated prompting; unavailable configuration is not a user decision.
The startup sheet must disclose the actual Firebase provider and collection.

The adapter forwards **only** `feature_used` with the allowlisted
`feature=privacy_settings`, after the actual Settings page mounts during consent.
Never forward core installation/lifecycle/reserved events, a core/private UUID,
identify/alias/user ID, arbitrary error text or custom window/document/image/path,
clipboard, account or payment content.

**Firebase automatic device/OS, app-instance and session data may be collected after
consent.** Do not reuse the previous provider's promise of no OS/hardware collection.
Connection IP, derived/proxy location and network metadata may be processed: a
pseudonymous app instance and lack of custom content do not imply network anonymity.
Console changes to Analytics linking, advertising or the project/environment require
owner review of the disclosure and policy; no legal-compliance certification is made.

All ten main Info.plist defaults are false: Firebase Analytics collection, Firebase
data collection, analytics storage, ad storage, ad user data, ad personalization,
IDFV collection, ad-network registration, automatic screen reporting and AppDelegate
proxying. These are startup/privacy defaults, not a claim that the consented official
SDK never emits automatic events or processes network metadata.

### Private runtime scope and signing

The application factory `.forApplication` creates an uninitialized owner; only
initialization sets readiness and checks the **actual Apple signature's private Keychain access group**
before enabling analytics controls. It must be exactly
`TeamID + ".io.github.invernomut0.Kinetiq"`, with the Team ID obtained from the real
signature, not guessed from a certificate name or configuration. Missing scope gives
categorical status and disabled analytics controls; normal product controls work.

`scripts/configure-firebase-signing.py` adds **only that own private group** using the
real Apple Team signature of the existing selected signing identity. It must not
invent Team IDs, add ad-hoc entitlements or use a blanket/shared Keychain group.
Ad-hoc builds stay safely **`blocked_off`**. A cryptographically valid ad-hoc signature
is not evidence of the required Firebase capability.

This addresses the prior no-Keychain-prompt requirement through Data Protection
Keychain access scoped to this app, not by reading the old identity store. Do not read,
migrate or delete the old Keychain item, preference UUID or alias; do not set a Firebase
user ID. No Keychain password, authorization-dialog or access-UI automation is allowed.
Check the signature first through the safe categorical capability path; no credentials,
private UUIDs, raw entitlement/certificate dumps or admin files enter diagnostics.
Actual consented signed restart behavior still requires owner-approved verification.

### Root client configuration, not admin authentication

The owner supplied root `GoogleService-Info.plist` is real, non-secret **client metadata**,
matching project **`kinetiq-75593`** and bundle **`io.github.invernomut0.Kinetiq`**.
Do not open/dump its raw contents or API key, edit the root client file, or read `.env`,
user preferences, private UUIDs or certificates into troubleshooting/model context.

The build parses at most **65,536 bytes** with typed, allowlisted client keys and
packages the approved configuration only for the main app. The original file stays
unchanged; missing/invalid configuration means unavailable analytics. Sibling `.env`
ingestion is removed; old configuration is ignored, not deleted. Client metadata is
extractable from a distributed app and is not a server/admin secret. A service-account
email is **not authentication configuration**; never package admin/service-account JSON.

**Console Analytics is active per Lorenzo; `IS_ANALYTICS_ENABLED` in the client
plist does not establish that console state or backend delivery.**
A matching client file, selected SDK, successful local initialization, accepted event
counter or signed disabled smoke does not prove backend ingestion. No console link,
project/environment change or live provider probe is authorized by this documentation.

### Serialization, revocation and quit

Keep existing serial awaited initialization, consent/control gates and independent
runtime kill switch. The kill switch never grants consent; transitions disable telemetry
controls, not effects. Persist grants only after successful startup and persist local
false **before cleanup**. Revocation suppresses later custom submissions, disables
Firebase Analytics collection, sets all consent categories denied and invokes
`resetAnalyticsData()` best-effort. There is no reset completion callback to await.

Do not force a flush on withdrawal. The official SDK has no public awaited flush or
delivery acknowledgement; an adapter completion is not an ingestion receipt. Local
reset cannot recall in-flight bytes, establish secure erasure or guarantee remote
deletion. Preserve the existing bounded graceful quit and main-run-loop deadline;
do not manufacture synchronous network shutdown or exactly-once delivery guarantees.

### Bundles, privacy resources and license boundaries

Build/sign the private app and embedded saver separately. The saver must contain
**no Firebase product, client configuration or Firebase Keychain entitlement**.
Remove PostHog, prefixed PLCrashReporter, libwebp and derived Sentry symbols/resources
and vendor licenses from app/saver bundles. This is not permission to remove independent
core privacy/MIT resources or rewrite the archived SDK guide.

The selected official Analytics ZIPs' **macos-arm64_x86_64** slices contain no privacy
resource bundle or binary license/terms file. Do not invent such resources or describe
Analytics binaries as Apache-licensed/open source. Preserve Firebase SDK source
Apache material and googleappmeasurement source **LICENSE + README** under
`ThirdPartyLicenses/`; preserve official **FirebaseAnalytics.podspec, Copyright 2022
Google**, binary-distribution metadata under `ThirdPartyLicenses/binary/`. Source
licenses and podspec copyright metadata do not relicense the downloaded binaries or
replace applicable Google terms. `NOTICE` distinguishes them; owner distribution
review remains open. Preserve actual host/core and selected dependency privacy
resources without inventing an absent Analytics resource bundle.

### Current acceptance and owner gates

- **F1 — Done, Copilot: implementation and offline/local acceptance only.** The
  following are actual final main-task results, not intended counts or historical
  PostHog acceptance.
- **F2 — Review, Lorenzo:** actual Apple signing identity and exact private
  `TeamID.bundleID` scope, native backend ingestion (console Analytics active per owner),
  project/environment and applicable terms,
  consented signed cold/relaunch behavior,
  native activation/background/sleep/wake/multi-window/timeout/quit deduplication,
  offline/retry/queued/in-flight revocation and denied cold relaunch, backend ingestion,
  retention/IP/location/access/erasure policy, hosted CI/distribution privacy and
  notarization are **not verified**. Local contracts and disabled smoke are not substitutes.

| Local gate | Verified result | Evidence |
|---|---|---|
| Complete final Debug | **339 = 157 app + 36 Effects + 146 Core; 0 failures, 0 skips**, including 33 telemetry contracts | `/tmp/kinetiq-firebase-final-debug.log` |
| Complete serialized restored-core Release | **339 = 157 app + 36 Effects + 146 Core; 0 failures, 0 skips**, including 33 telemetry contracts | `/tmp/kinetiq-firebase-restored-release.log` |
| Python parser/artifacts | **19 passed, 0 skips**; includes the real linked Google `ParamsEntry`/`sEntry` substring-collision regression with correct vendor symbol boundaries | `/tmp/kinetiq-firebase-final-parser.log` |
| Signing tests | **5 ran: 4 passed, 1 skipped**; actual app is ad-hoc with no valid Apple Team, so the real-Team positive case skipped | `/tmp/kinetiq-firebase-final-signing.log` |
| Universal build | **Exit 0**; actual app and embedded saver are **arm64 + x86_64** and both pass deep/strict signature verification | `/tmp/kinetiq-firebase-final-build.log` |
| Actual signing capability | **`KINETIQ_FIREBASE_SIGNING_BLOCKED_OFF`**, not `PRIVATE_GROUP_READY`; no real Apple identity available, analytics controls safely unavailable until actual private scope exists | Actual packaged app/build signing state |
| Bundle verifier | **Exit 0**, `KINETIQ_TELEMETRY_BUNDLE_CHECK_SUCCESS`; sanitized client configuration only in the main app, core privacy/MIT intact, no old providers in the actual new distribution | Actual new bundle verification |
| Signed disabled smoke | **Exit 0**, `KINETIQ_TELEMETRY_DISABLED_SMOKE_SUCCESS`; no Firebase configure, consent, events or Keychain UI | `/tmp/kinetiq-firebase-signed-smoke.log` |

The original broad Sentry filter falsely detected the real linked Google `ParamsEntry`
symbol. Correct vendor symbol boundaries fixed that false positive and are regression
tested; the verifier does **not** ignore real vendor symbols.

Actual Release LLVM **Lines**, not Regions or Metal branch coverage:

| Component | Lines | Total lines | Missed lines |
|---|---:|---:|---:|
| `KinetiqTelemetry.swift` owner | **96.63%** | 208 | 7 |
| `FirebaseAnalyticsProvider.swift` adapter | **21.31%** | 61 | 48 |
| `TelemetryPrivacyView.swift` | **96.83%** | 63 | 2 |
| `TelemetryPreferenceIdentityStore.swift` | **100%** | 20 | 0 |

Report: `/tmp/kinetiq-firebase-coverage.txt`; profile:
`/tmp/kinetiq-firebase-release.profdata`; matching binary:
`.build/out/Products/Release/KinetiqTests.xctest/Contents/MacOS/KinetiqTests`.
The low adapter coverage is intentional: live start/lifecycle, offline delivery and
reset were **not tested**. Local contracts do not establish live Firebase behavior,
backend ingestion or exhaustive lifecycle/revocation coverage.

An earlier Release rerun overlapped an earlier Debug run and failed
helper-frontmost/`windowNotShareable` checks. The final serialized run passed with
unchanged assertions; the earlier failure is not concealed. A separate compilation
failed when sibling `TelemetrySDK` disappeared from disk. A clean clone reprovisioned
the same approved pin `c5e275421fa03c242c9c53b5431d919fdd18547a`, with no SDK source edits.

Historical version **0.3.3 / build 38** was preserved in that task (current: **0.3.4 / build 39**). Commit/push for each completed task and
the `firebase` → reviewed PR → `main` workflow are **owner-requested**.
The local root client plist is ignored/excluded;
user `.vscode/launch.json`, `.serena/`, effects and documents are preserved.
The real post-documentation README capture-to-Metal optics regression passed:
**1 test, 0 failures**, `/tmp/kinetiq-firebase-postdocs.log`.

Owner-metadata Swift/Python tests use the actual root client file read-only. In CI
without this ignored owner file, those specific tests explicitly skip; no valid fake
Firebase configuration is generated. Missing-configuration and default-off contracts
still execute. Supplying the real file enables the metadata-only tests without
configuring Firebase or transmitting events. Both parsers reject administrator
fields inside nested metadata, including case/separator variants.

## Historical PostHog implementation and evidence (not current Firebase guidance)

Everything below retains the earlier implementation narrative and original counts,
logs and limitations. Statements such as "now", "current", "supersedes" and remaining
review refer to those earlier PostHog tasks only. In particular, their preference
identity, preserved consent, dotenv provisioning and no-OS/hardware statements are
**not** Firebase behavior. The current section above takes precedence.

## Scope and ownership

This is a **host-only**, PostHog-only integration. SDK sources and Git checkout are
unchanged. AppKit's existing `AppDelegate` retains one `KinetiqTelemetry` owner and
passes it through `SetupWindowController` → `SetupModel` → the actual Settings form.
There is no facade/vendor singleton added, per-window lifecycle forwarding, manual
reserved event or telemetry dependency in Core, Effects, saver or preview targets.
Existing test constructors default to `telemetry: nil`.

Core: `../TelemetrySDK`; adapter: `../TelemetrySDK/Integrations/PostHog`.
Verified published SHA: **c5e275421fa03c242c9c53b5431d919fdd18547a** (SDK 0.1.1).
Official vendor: **PostHog 3.93.6**, resolved revision
`4e9850f767988f394e8584b0bf61ce85674775eb`. One local core graph; no Sentry package
or SDK example product. `Documentation/telemetry-sdk-revision.txt`, the SwiftPM manifest,
packaging and CI enforce the SHA/clean checkout, including non-ignored untracked files.
Ignored local config does not make the pin dirty.
CI checks out `Kinetiq` and `TelemetrySDK` as siblings, preserving the release workflow.
`bash scripts/verify-telemetry-sdk.sh` also provides a standalone provisioning check.

**Version discrepancy for owner review:** supplied task context said 0.3.2/build37,
but inspected `Resources/Info.plist` and current repository documentation already
contain **0.3.3/build38**. No version/build field was changed or downgraded; historical
Liquid/Studio/Destruction documentation remains intact. No commit or push was made.
The pin is verified but owner approval of that selection remains Review.

## Consent, events and quit

`kinetiq.telemetry.analytics` accepts only an actual plist Boolean, default false.
No token, Debug flag or app feature switch grants consent. The owner serializes
initialization, consent, categorical action and shutdown. Grant is persisted after
provider startup succeeds; withdrawal is persisted before awaiting purge. Missing
config and invalid config/startup/purge errors deny consent. Purge failure prevents
restart in this process; only fixed status messages appear. No flush on withdrawal.
The independent runtime kill switch preserves the consent preference but does not
grant a denied preference when resumed. An existing grant remains withdrawable while
paused; a new grant is blocked until resumed. Product controls remain available.

The checkbox is in **Settings → Privacy & Analytics**, with observable status and
progress; active consent remains withdrawable. Startup opens Overview. The only
custom capture is `feature_used` with `feature=privacy_settings`, sent after the real
Settings section is mounted and only during consent. `feature` is the only custom
property allowlist. Timer single-stop/revocation semantics are tested on the real core;
no unused product timing instrumentation or arbitrary effect/user strings are sent.

On the first configured launch, after the retained owner initializes, the existing
management window presents a nonblocking native **Help improve Kinetiq?** sheet.
**Don't Share** is the default; **Enable Analytics** alone grants consent through the
same awaited owner API. No provider starts merely because the sheet appears.
`kinetiq.telemetry.analyticsDecision` records an actual answer (or a Settings change),
independently of automatic fail-closed/configuration errors. Declining is remembered;
unanswered exits may ask again next launch. Missing configuration does not mark an
answer, and a pre-existing grant is not re-prompted. Claims are guarded per process
and a hidden window/existing sheet cannot consume the claim. The sheet is not used
by disabled smoke and is never automatically accepted during verification.

The SDK alone observes native app/session lifecycle. No OS/hardware collection,
identify/alias, account correlation, document/path/window/image/clipboard/payment
data or arbitrary errors. The product ID is `kinetiq`, not the bundle identifier.
Consented analytics creates a product-scoped UUID in app-local UserDefaults through
`TelemetryPreferenceIdentityStore`, not the SDK's default Keychain store. The owner
always injects this store unless an explicit test store is supplied, so neither
startup nor consent grant reads/writes the old Keychain item. The key is
`kinetiq.telemetry.installationID`; it is a pseudonymous identifier, not a credential.
It is created only when consented analytics actually starts, persists across launches,
and is retained on withdrawal just as the previous identity was. SDK identity
reset/delete acts only on the new preference key. Malformed stored values fail closed.
The former Keychain identity is **not migrated or deleted** (either operation could
request authorization); the first consented start after this change uses a new UUID.
Removing app preferences resets this identifier; preferences can themselves remain
after uninstall. This is deliberately not credential-grade or tamper-proof storage.
The service sees IP and pseudonymous metadata; this is not
anonymity, secure erasure, exactly-once delivery or a legal compliance certification.

`applicationShouldTerminate` first restores windows/stops tap, chaos and system
saver watching, then returns `.terminateLater` and awaits telemetry shutdown.
Reentrant quit and replies are guarded. An independent **3-second main-run-loop
deadline** permits exit even if cleanup stalls. No main-thread blocking, delivery
promise or unbounded process wait; force kill/crash/power loss are not graceful quit.

## Safe configuration and packaging

Runtime reads only named process keys, falling back to the **main** Info.plist:

- `TELEMETRY_POSTHOG_TOKEN`: client ingestion token, strictly `phc_` + ASCII
  letters/digits/underscore/hyphen, maximum 200 bytes. Management/personal tokens
  are rejected. A compiled ingestion token is extractable, not a server secret.
- `TELEMETRY_POSTHOG_HOST`: HTTPS ingest root; default EU. No credentials, query,
  fragment, non-root path or non-443 explicit port. No localhost HTTP in the host.
- `TELEMETRY_ENVIRONMENT`: development/staging/production. Runtime defaults to
  development in Debug, production in Release; Debug production is always rejected.

`scripts/configure-telemetry.py` reads the approved `../TelemetrySDK/.env` only inside
the local build subprocess as bounded UTF-8 **data**. It recognizes those three keys,
literal optional quotes/comments, rejects duplicates/interpolation/escape/executable
syntax for recognized assignments, and ignores all other keys (including Sentry).
It does not source/eval dotenv, print values, return content to the assistant, copy
dotenv into host/bundle or touch admin credentials. Named environment overrides
include explicit empty values. The sibling token defaults to **development even in
Release**, staging may be declared; **any nonempty production token is blocked by
packaging** until owner-reviewed production provisioning is designed. A production
override/smoke bypass is not provided. There is no automatic consent.

The parser substitutes only the generated main app plist, before signing; source
plist/version/signing settings are preserved. Missing config works with consent off.
`.env`, `.env.*` (except an empty `.env.example`) and `*.local.xcconfig` are ignored.
The existing sibling config is wired, so no redundant host `.env` is created.
Never dump plist/environment/build settings in troubleshooting.

Packaging copies the host `PrivacyInfo.xcprivacy`, core and official PostHog privacy
resource bundles, plus its transitive prefixed crash-reporter manifest. Host reasons:
UserDefaults **CA92.1** (own settings/consent/analytics UUID), SystemBootTime **35F9.1** (local elapsed
animation intervals). Vendor manifest includes its file-timestamp reason C617.1;
host code does not add that accessed API for telemetry. DeviceID, interaction and
session performance data are non-tracking analytics and consent-scoped. Vendor
manifests are preserved, not rewritten to claim unused collection is active.
MIT SDK/PostHog notices and transitive PLCrashReporter/libwebp licenses accompany
the app. PostHog contains attributed derived Sentry code but **no Sentry provider**.

Kinetiq remains **unsandboxed**, as before: enabling sandbox globally would break
the app's AX/capture behavior. No blanket Keychain sharing entitlement is added.
If a future distribution sandbox is designed, consented outgoing traffic requires
`com.apple.security.network.client` and local preference persistence must be reverified.
This task does not certify notarization or an App Store archive privacy report.

## Executed evidence (local)

### No-Keychain identity acceptance (2026-11-08)

This section supersedes the earlier identity-storage implementation, not the remaining
owner-gated live-delivery checks. The reported Keychain authorization prompt came from
the SDK's default identity store. The host now passes a nonoptional preference store
to every owned client; explicit injected test stores still work. No SDK/signing scope
change, legacy Keychain lookup/migration/deletion or automatic consent was used.

- Focused VS Code Debug telemetry run passed; the complete Release run confirms all
  **28 telemetry contracts** pass, including four new local-store contracts.
- `KINETIQ_UI_TEST_DUMP=/tmp/kinetiq-no-keychain-ui swift test -c release --enable-code-coverage`:
  exit 0; **334 tests = 152 app + 36 Effects + 146 Core; 0 failures, 0 skips**.
  Log: `/tmp/kinetiq-no-keychain-release.log`.
- Local contracts use real isolated UserDefaults and the actual core with a recording
  provider boundary (never PostHog startup). They verify no UUID before consent,
  consented creation, same UUID after a fresh owner starts, retention on withdrawal,
  product-scoped deletion preserving consent/other identities, malformed UUID fail-closed,
  and real core reset/delete with no recreation after deletion.
- LLVM **Lines**: store **100%** (20 lines/0 missed), owner **97.58%** (207/5 missed),
  privacy UI **96.83%** (63/2 missed). Matching Release `KinetiqTests` binary and
  `codecov/*.profraw` merged to `/tmp/kinetiq-no-keychain-release.profdata`;
  report `/tmp/kinetiq-no-keychain-coverage.txt`. Not a live-provider or branch-coverage claim.
- `bash scripts/build-app.sh`: exit 0, log `/tmp/kinetiq-no-keychain-build.log`.
  App and embedded saver: **x86_64 + arm64**, strict signatures verified. Bundle verifier
  and disabled signed smoke both exit 0; version/build stay **0.3.3/38**.
- SDK pin/cleanliness and `git diff --check` pass; modified Swift files have no diagnostics.
  The old local process was stopped, but no normal app launch, real provider probe,
  user consent response, Keychain password entry, SDK edit, commit or push was automated.
  Reopen `build/Kinetiq.app` to run the new binary. Deny any dialog from an older copy;
  authorization is not necessary for this analytics identity.

### Startup-consent acceptance (2026-11-07, historical)

These results supersede only the earlier integration runs below. Both full suites include
the actual native consent sheet and opt-in Management UI screenshot test; no real
provider/consent or user preference was used. No assertions were weakened.

| Gate | Exact command | Result | Log |
|---|---|---|---|
| Focused final Debug | `swift test --filter KinetiqTelemetryTests --enable-code-coverage` | exit 0; 24 tests, 0 failures/skips | `/tmp/kinetiq-startup-consent-debug.log` |
| Complete final Debug | `KINETIQ_UI_TEST_DUMP=/tmp/kinetiq-startup-consent-ui swift test --enable-code-coverage` | exit 0; **328 = 146 app + 36 Effects + 146 Core; 0 failures/skips** | `/tmp/kinetiq-startup-consent-final-debug.log` |
| Complete final Release | `KINETIQ_UI_TEST_DUMP=/tmp/kinetiq-startup-consent-ui swift test -c release --enable-code-coverage` | exit 0; **328 tests, 0 failures/skips**, including 24 telemetry contracts | `/tmp/kinetiq-startup-consent-release.log` |
| Final universal packaging | `bash scripts/build-app.sh` | exit 0; x86_64 + arm64; source version/build preserved | `/tmp/kinetiq-startup-consent-build.log` |
| Final strict signatures | `codesign --verify --deep --strict build/Kinetiq.app` and embedded `Kinetiq.saver` | both exit 0 | direct terminal verification |
| Final bundle check | `python3 scripts/verify-telemetry-bundle.py` | exit 0; configuration present, values withheld; privacy/notices present and dotenv absent | direct fixed success output |
| Final signed disabled smoke | `build/Kinetiq.app/Contents/MacOS/Kinetiq --telemetry-smoke-test` | exit 0; `KINETIQ_TELEMETRY_DISABLED_SMOKE_SUCCESS` | direct fixed success output |
| Post-documentation optics | `swift test -c release --filter LiquidIntegrationTests.testCapturedREADMEOpticsPreserveNativeTextContrast` | exit 0; actual README capture-to-Metal regression passed | `/tmp/kinetiq-startup-consent-postdocs.log` |

Release LLVM **Lines**: `KinetiqTelemetry.swift` **97.09%** (206 lines, 6 missed),
`TelemetryPrivacyView.swift` **96.83%** (63 lines, 2 missed). Matching binary:
`.build/out/Products/Release/KinetiqTests.xctest/Contents/MacOS/KinetiqTests`;
profiles: `.build/out/Products/Release/codecov/*.profraw`; merged profile/report:
`/tmp/kinetiq-startup-consent-release.profdata` and
`/tmp/kinetiq-startup-consent-coverage.txt`. The active Xcode build system uses this
Products path, not the legacy architecture-specific coverage path.

The new six tests cover configuration-gated/default-off prompting, zero provider or
identity access on presentation, single claims, persistent denial/grant/withdrawal,
unanswered restart, malformed decision values and a real AppKit sheet response.
The earlier full Debug Liquid failures are resolved by the unchanged assertions in
the final full Debug/Release runs. macOS TextKit emits system `contactsd` connection
diagnostics during native document tests; these are not telemetry captures or XCTest
failures and are not used to infer delivery. Test log summaries exclude their payload.

### Earlier integration runs (historical)

All logs below are temporary local artifacts, not shipped resources. No env/token
values or real-provider smoke are used in tests. Core/adapter tests are those at
the verified pin; host contract doubles prove ordering, **not server delivery**.

| Gate | Exact command | Result | Log |
|---|---|---|---|
| SDK core build | `swift build --package-path ../TelemetrySDK` | exit 0 | `/tmp/kinetiq-sdk-core-build.log` |
| SDK core tests | `swift test --package-path ../TelemetrySDK --enable-code-coverage` | exit 0; 62 tests, 0 failures | `/tmp/kinetiq-sdk-core-tests.log` |
| PostHog build | `swift build --package-path ../TelemetrySDK/Integrations/PostHog` | exit 0 | `/tmp/kinetiq-sdk-posthog-build.log` |
| PostHog tests | `swift test --package-path ../TelemetrySDK/Integrations/PostHog --enable-code-coverage` | exit 0; 10 tests, 0 failures | `/tmp/kinetiq-sdk-posthog-tests.log` |
| Manifest pin/sandbox | `swift package dump-package` | exit 0; local pin and tracked-state guard evaluated | `/tmp/kinetiq-telemetry-manifest-check.log` |
| Parser | `python3 -m unittest discover -s scripts -p test_telemetry_config.py -v` | exit 0; 11 tests | `/tmp/kinetiq-telemetry-parser-tests.log` |
| Host Debug focused | `swift test --filter KinetiqTelemetryTests --enable-code-coverage` | exit 0; 18 tests, 0 failures, 0 skips | `/tmp/kinetiq-telemetry-final-debug-focused.log` |
| Host Release focused | `swift test -c release --filter KinetiqTelemetryTests --enable-code-coverage` | exit 0; 18 tests, 0 failures, 0 skips | `/tmp/kinetiq-telemetry-final-release-focused.log` |
| Host Debug build | `swift build` | exit 0 | `/tmp/kinetiq-telemetry-debug-build.log` |
| Host Release build | `swift build -c release` | exit 0 | `/tmp/kinetiq-telemetry-release-build.log` |
| Complete Debug suite (before final kill-switch regression) | `swift test --enable-code-coverage` | **Failed**: 321 tests; 4 failures (2 unexpected) in 2 Liquid cases, 1 opt-in screenshot skip | `/tmp/kinetiq-telemetry-debug-suite.log` |
| Debug Liquid isolated retry | `swift test --filter 'LiquidIntegrationTests.testCloseTriggerCancelled(ImmediatelyAfterActualCloseDoesNotRestart\|WhileWatchingDoesNotPlayAfterActualClose)' --enable-code-coverage` | exit 0; both cases passed unchanged; **not** a full Debug pass | `/tmp/kinetiq-telemetry-debug-liquid-retry.log` |
| Complete final Release suite | `swift test -c release --enable-code-coverage` | exit 0; **322 tests = 140 app + 36 Effects + 146 Core; 0 failures, 1 opt-in screenshot skip** | `/tmp/kinetiq-telemetry-final-release-suite.log` |
| Signed universal packaging | `bash scripts/build-app.sh` | exit 0; app and saver x86_64 + arm64 | `/tmp/kinetiq-telemetry-final-universal-build.log` |
| Strict app signature | `codesign --verify --deep --strict build/Kinetiq.app` | exit 0 | `/tmp/kinetiq-telemetry-app-signature.log` |
| Strict saver signature | `codesign --verify --deep --strict build/Kinetiq.app/Contents/Resources/Kinetiq.saver` | exit 0 | `/tmp/kinetiq-telemetry-saver-signature.log` |
| Main configuration/resources | `python3 scripts/verify-telemetry-bundle.py` | exit 0; ingestion configuration present (values withheld); version preserved, manifests/notices present, dotenv absent | `/tmp/kinetiq-telemetry-bundle-check.log` |
| Signed disabled launch | `build/Kinetiq.app/Contents/MacOS/Kinetiq --telemetry-smoke-test` | exit 0; `KINETIQ_TELEMETRY_DISABLED_SMOKE_SUCCESS` | `/tmp/kinetiq-telemetry-signed-smoke.log` |
| Post-documentation real README optics | `swift test -c release --filter LiquidIntegrationTests.testCapturedREADMEOpticsPreserveNativeTextContrast --enable-code-coverage` | exit 0; actual capture-to-Metal regression passed | `/tmp/kinetiq-telemetry-postdocs-readme.log` |

Final local gate exit markers are retained in `/tmp/kinetiq-telemetry-final-status.log`
(three completed runs; the second includes the manifest/kill-switch correction and
the third the documentation/patent-notice check). Post-documentation gates also
have fixed exits in `/tmp/kinetiq-telemetry-postdocs-status.log` and
`/tmp/kinetiq-telemetry-postdocs-gates.log`; suite exits are in
`/tmp/kinetiq-telemetry-final-suites-status.log`. Raw/merged LLVM profiles are ignored
build artifacts, never packaged or treated as analytics evidence. No production token
override was needed. Only the parser consumed sibling dotenv locally; tests and smoke
did not read it. The generated bundle's ingestion **presence**, not its values, was reported.

The failed Debug cases are
`testCloseTriggerCancelledImmediatelyAfterActualCloseDoesNotRestart` and
`testCloseTriggerCancelledWhileWatchingDoesNotPlayAfterActualClose` in
`LiquidIntegrationTests`: helper-frontmost/capture failures. Both passed unchanged
in isolated Debug retry and the complete final Release run. This does **not** erase
the original full Debug failure; the final startup-consent suites above supply the
clean complete rerun. The sole earlier Release skip was
`ManagementTests.testOptInScreenshotsOfOwnEffectsStudioAndPerformanceWindow`;
the telemetry native Settings test did run, rather than skip.

Earlier LLVM **Lines**, before the startup prompt, from merged Release `codecov/*.profraw` against the matching
`KinetiqTests.xctest/Contents/MacOS/KinetiqTests` binary:
`KinetiqTelemetry.swift` **96.89%** (193 lines, 6 missed),
`TelemetryPrivacyView.swift` **94.29%** (35 lines, 2 missed).
Report: `/tmp/kinetiq-telemetry-release-coverage.txt`; merged profile:
`/tmp/kinetiq-telemetry-release.profdata`. Not Regions, Metal branch coverage,
live-provider coverage or evidence of service delivery.

Focused tests use isolated preferences, a unique core product namespace and injected
memory identity/actor recording boundaries. They cover Boolean-only/default-off
consent, no startup/provider/identity/capture before consent, concurrent startup,
grant ordering/start failure, identity failure, withdrawal before purge/no flush,
purge fail-closed, kill switch and withdrawal while paused, serialized/repeated quit, invalid no-secret config,
fixed categorical metadata, timer once/revoke suppression, constructor isolation
and a real native Settings/Overview window using the retained owner. The native
test does not start a real provider or alter user effects/documents/saver selection.

Disabled signed smoke branches **before AppDelegate/Settings construction**, keys,
AX/Screen Recording prompts or user preference effects. It uses the real core with
`enabled=false`, no providers, native lifecycle disabled and a throwing identity
store to detect unexpected access. Success requires initialized diagnostics, both
channels denied/unavailable and zero accepted events; shutdown is awaited. Fixed
output: `KINETIQ_TELEMETRY_DISABLED_SMOKE_SUCCESS`; failure is fixed and exits 1.
No normal packaged-app launch is performed automatically in this task.

## Remaining owner review / not claimed complete

- The copied prompt/instruction files are byte-identical to the pinned SDK (`cmp` exit 0).
  `Documentation/COPILOT_INTEGRATION.md` preserves the full source text and required path;
  its one additional EOF newline is a nonsemantic editor normalization (`cmp` exit 1),
  not a missing integration instruction.
- Confirm pin selection and existing version/build discrepancy.
- Signed **consented** analytics persistence after native restart and delivery remain
  subject to approval. Keychain access/migration is intentionally removed at the
  owner's request; the old item is left alone. Preference-store persistence, isolation,
  malformed data and reset/delete are covered by isolated local contracts, not by a
  live provider probe.
- Consented native activation/background/sleep/wake/multi-window/timeout/quit
  exactly-once capture boundary, real offline/queued/in-flight revocation and
  denied cold relaunch are deferred. Core tests do not replace host-native evidence.
- Real development/staging project delivery and dashboard ingestion, retry/overflow,
  retention/IP processing/access/erasure policy require explicit approval. Accepted
  counters/flush/shutdown are not delivery receipts. **No live events were sent.**
- Hosted CI execution, distribution privacy report and notarization remain Review.
  The editor reports context warnings for the release workflow's existing signing-secret
  references, which were not changed; secret availability was not inspected or exposed.
  Swift/Python and the new telemetry workflow have no reported diagnostics.
- No user `.vscode/launch.json`, `.serena/`, effect assignments or documents changed;
  no SDK source/checkout changes, no commit/push. Full production acceptance is not
  declared complete merely because local contracts and disabled smoke pass.