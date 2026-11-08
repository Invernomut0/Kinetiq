# Kinetiq telemetry integration

## Current: PostHog → Google Firebase Analytics (2026-11-08)

**Migration acceptance: VERIFIED LOCAL — F1 Done, owner Copilot, for implementation
and offline/local acceptance only; F2 Review, owner Lorenzo.**
This section supersedes the historical provider, configuration, identity and live-gate
guidance below. Historical counts, logs and coverage are retained, not recertified.
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

**`IS_ANALYTICS_ENABLED=false` requires Lorenzo's console Analytics-link review.**
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
  `TeamID.bundleID` scope, real console Analytics link (actual root
  `IS_ANALYTICS_ENABLED=false`), project/environment and applicable terms,
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

Version **0.3.3 / build 38** remains preserved. Commit/push for each completed task and
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