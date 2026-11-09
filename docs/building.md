# Building Kinetiq from source

Toolchain, dependencies, packaging, analytics configuration, verification commands and the source map.

## Building

Requires macOS 14 or later and Xcode 26 or later (Swift 6 for PaperSaverKit and
TelemetrySDK; Kinetiq keeps its existing Swift 5 language mode). SwiftPM resolves
PaperSaver 0.4.3 and official Firebase Apple SDK **12.6.0** (published version verified;
its official manifest selects GoogleAppMeasurement **12.5.0** binaries). Official
Analytics supports native macOS starting with SDK 8.9. PaperSaver's ArgumentParser is for its
CLI, not bundled in Kinetiq. Provision the complete sibling `../TelemetrySDK` checkout
at `c5e275421fa03c242c9c53b5431d919fdd18547a`; only the generic core is retained,
unchanged. The PostHog adapter/dependency is removed. FirebaseCore and
FirebaseAnalyticsCore (without AdSupport/IdentitySupport) link only to the main app;
no Auth, FCM, Crashlytics or Sentry is selected. The SwiftPM manifest, packaging
and CI enforce the SHA and clean checkout (including non-ignored untracked files) without rejecting ignored local
`.env`. `bash scripts/verify-telemetry-sdk.sh` is the standalone provisioning check.

For GA4, `scripts/build-app.sh` runs `scripts/configure-ga4.py` (Python 3 standard
library only). It reads **root `.env` only inside the local build process**, as bounded
UTF-8 data (65,536 bytes), never sources/evaluates it. The local ignored keys are
`KINETIQ_GA4_MEASUREMENT_ID` (a Web stream `G-…` ID) and `KINETIQ_GA4_API_SECRET`
(that Web stream's Measurement Protocol ingestion secret). These are **not** the
native Firebase app ID/client API key; the Web stream is a different stream, even if
it belongs to the same Analytics property. Do not put admin/service-account JSON here.
Only exact `measurement_id` / `api_secret` fields enter
`Kinetiq.app/Contents/Resources/KinetiqGA4Configuration.plist`, before signing;
no unrelated dotenv data or `.env` file is copied. Runtime reads this bundle resource,
**never runtime `.env`**. Absence removes stale GA4 configuration; invalid presence
rejects packaging. The saver cannot receive this configuration.

The verified local **`build/Kinetiq.app` contains the owner's GA4 configuration**.
The two root `.env` keys are ignored and local only: credentials have **not been
uploaded or provisioned in GitHub CI**. A workflow build without the owner's `.env`
uses the safe native fallback, currently `KINETIQ_FIREBASE_SIGNING_BLOCKED_OFF`; it
does **not** produce a configured GA4 release app. Hosted CI execution is unverified.
The owner-requested v0.5.1 DMG was instead published from the verified local package;
tag and uploaded SHA-256 digests are recorded in [task 25](telemetry.md#release-publication--task-25).

**Deployment risk, explicitly authorized by the owner:** bundling the ingestion
secret makes it extractable and enables forged/spam events. This direct desktop
deployment is contrary to the recommended server-only secret placement; it provides
no secret-authentication boundary. Never bundle administrator credentials. The owner
confirms console Analytics is active; this is not proof of Web-stream ingestion.

Standalone offline tests: `python3 -m unittest discover -s scripts -p test_ga4_config.py -v`.
Current verified local run (2026-11-08): **26 passed, 0 failures/errors, 0 skips, exit 0**,
including the pure validation-only payload contract.
Positive cases use only actual owner configuration inside the test process and skip
when absent; failures/statuses never display credentials. No fabricated valid keys,
network mocks, patches or live requests are used. Optional owner command
`python3 scripts/configure-ga4.py --validate` calls only Google's **debug** endpoint
for event-structure validation, not secret authentication or report ingestion proof.
It is **not an automatic CI test**. The current explicitly requested session-aware
Google debug probe returned **0 validation messages, exit 0**. It uses a real positive
Web session ID and optionally measured probe-preparation time, **not app engagement**.
Ordinary tests and the disabled smoke remain offline.

**Historical privacy-settings-only GA4 acceptance — v0.3.4/build 39, VERIFIED LOCAL,
G1 Done (Copilot), G2 Review (Lorenzo); not v0.5.0 acceptance:**

- Complete **Release and Debug each passed 361 tests = 179 app + 36 Effects +
	146 Core; 0 failures, 0 skips, exit 0**. Logs:
	`/tmp/kinetiq-ga4-fix-release.log` and `/tmp/kinetiq-ga4-fix-debug.log`
	(verified `DEBUG_EXIT=0`). The Debug app suite completed in approximately
	**1928 seconds**; it did not hang.
- Focused Release: **55 = 21 GA4 Swift + 34 native contracts, 0 failures**,
	`/tmp/kinetiq-ga4-fix-focused.log`. Actual native Settings mounted while denied,
	then granted consent **while visible, without navigation**, recorded exactly one
	approved event and revoked through the retained owner and recording boundary.
	GA4 disclosure was tested; no normal consented app GUI launch or live collection
	request was automated. The full suites include the real README capture-to-Metal
	optics regression. The focused post-documentation rerun using
	`swift test -c release --filter 'LiquidIntegrationTests/testCapturedREADMEOpticsPreserveNativeTextContrast'`
	passed the actual Test Case in **2.618 seconds: 1 test, 0 failures, 0 skips, exit 0**
	(`/tmp/kinetiq-ga4-fix-postdocs.log`). The initial dot-filter attempt selected
	0 tests and is not a successful regression run.
- Python GA4: **26 passed, 0 failures/errors/skips**; native parser: **19 passed,
	0 skips**. Signing: **5 ran, 4 passed, 1 skipped**, because a real Apple Team is
	unavailable; no Team identity is invented.
- Universal build: **exit 0** (`BUILD_EXIT=0`, `/tmp/kinetiq-ga4-fix-build.log`).
	App and embedded saver are each **arm64 + x86_64**; both deep/strict signature
	checks returned **0**. Direct terminal resource verification returned **0**,
	`KINETIQ_TELEMETRY_BUNDLE_CHECK_SUCCESS`; signed disabled smoke returned **0**,
	`KINETIQ_TELEMETRY_DISABLED_SMOKE_SUCCESS`. These direct checks have no claimed
	saved log. Native fallback status is **`KINETIQ_FIREBASE_SIGNING_BLOCKED_OFF`**,
	not GA4 unavailability: bundled GA4 is present and works without Keychain after
	its own fresh default-off consent.

Actual Release LLVM **Lines**, verified against the report header (not Regions):

| Component | Total lines | Missed lines | Line coverage |
|---|---:|---:|---:|
| GA4 provider | 275 | 63 | **77.09%** |
| Telemetry owner | 240 | 7 | **97.08%** |
| Privacy UI | 97 | 10 | **89.69%** |
| Preference identity store | 20 | 0 | **100%** |
| Native Firebase adapter | 61 | 48 | **21.31%** |

Report: `/tmp/kinetiq-ga4-fix-coverage.txt`; profile:
`/tmp/kinetiq-ga4-fix-release.profdata`; matching binary:
`.build/out/Products/Release/KinetiqTests.xctest/Contents/MacOS/KinetiqTests`.
Approved exclusions remain **unexecuted at runtime**: live data tasks, response
handling, cancellation and the 30-minute session boundary. Native live-provider
paths are not certified. Coverage is not exhaustive, Metal branch coverage or
ingestion evidence; the store's 100% does not imply 100% integration coverage.

**Workflow:** Owner-requested publication uses commits/push on firebase, reviewed PR and normal merge into main. Git history and PR are publication evidence; local packaging is not new DMG release.

G2 retains actual Web-stream credentials/console ingestion,
IP/location/retention/access/erasure/privacy, extractable-secret spam risk, terms,
notarization and release provisioning review; hosted CI remains unverified.

The still-supported native fallback uses Python 3 to parse the owner-supplied
root `GoogleService-Info.plist` as bounded (65,536 bytes), typed, allowlisted client
metadata for the main app. The source file is not modified; missing configuration
leaves analytics unavailable. The supplied project/bundle match is `kinetiq-75593` /
`io.github.invernomut0.Kinetiq`. **The owner confirms console Analytics is active;
the plist's `IS_ANALYTICS_ENABLED` is not authoritative console state. A client match
is not backend validation.** Client
metadata is extractable, not an admin credential. No service-account JSON belongs in
the app; a service-account email is not authentication configuration. Sibling `.env`
ingestion is removed and old configuration is ignored, not deleted. Do not dump client
keys, `.env`, preferences, private UUIDs or certificates during troubleshooting.

`scripts/configure-firebase-signing.py` derives only the app's own private Keychain
group from the real Apple Team signature of the existing selected identity. It invents
neither a Team ID nor ad-hoc entitlements. Both app and saver are signed; the saver has
no Firebase products, client configuration or Firebase Keychain entitlement. Packaging
removes PostHog/PLCrashReporter/libwebp/Sentry symbols, resources and vendor licenses.
Ten main-plist defaults disable collection/data collection, analytics/ad storage,
ad user data/personalization, IDFV, ad-network registration, screen reporting and
delegate proxying. See [the precise scope and license distinctions](telemetry.md).

Parser tests: `python3 -m unittest discover -s scripts -p test_telemetry_config.py -v`.
Host contracts: `swift test --filter KinetiqTelemetryTests --enable-code-coverage`.
Safe signed launch: `build/Kinetiq.app/Contents/MacOS/Kinetiq --telemetry-smoke-test`.
The smoke bypasses all runtime keys, app preferences, permissions, vendor startup and
Keychain; it initializes the real disabled core, verifies denied/unavailable channels
and zero accepted events, then shuts down with a fixed success/failure line.

**Historical native Firebase migration acceptance (v0.3.3/build 38): VERIFIED LOCAL — F1 Done for implementation and
offline/local acceptance only; F2 Review, owner Lorenzo.** Actual complete final
**Debug and serialized restored-core Release: 339 tests each = 157 app + 36 Effects
+ 146 Core; 0 failures, 0 skips**, including **33 telemetry contracts**. Logs:
`/tmp/kinetiq-firebase-final-debug.log` and
`/tmp/kinetiq-firebase-restored-release.log`. Python parser/artifact tests:
**19 passed, 0 skips** (`/tmp/kinetiq-firebase-final-parser.log`), including the real
linked Google `ParamsEntry`/`sEntry` substring-collision regression with correct vendor
symbol boundaries. Signing tests ran **5: 4 passed, 1 skipped**
(`/tmp/kinetiq-firebase-final-signing.log`): the real-Team positive case skipped because
the actual ad-hoc app has no valid Apple Team.

Universal build exit **0** (`/tmp/kinetiq-firebase-final-build.log`); actual app and
embedded saver are **arm64 + x86_64** and pass deep/strict signature verification.
Actual status is **`KINETIQ_FIREBASE_SIGNING_BLOCKED_OFF`**, **not
`PRIVATE_GROUP_READY`**: no real Apple signing identity is available; analytics controls
remain safely unavailable until the actual private `TeamID.bundleID` scope exists.
Bundle verifier exit **0**, `KINETIQ_TELEMETRY_BUNDLE_CHECK_SUCCESS`: sanitized client
configuration is present only in the main app, core privacy/MIT resources are intact,
and old providers are absent from the actual new distribution. The original broad
Sentry filter falsely matched real Google `ParamsEntry`; it was fixed and regression
tested, not changed to ignore real vendor symbols. Signed disabled smoke exit **0**,
`KINETIQ_TELEMETRY_DISABLED_SMOKE_SUCCESS`
(`/tmp/kinetiq-firebase-signed-smoke.log`), with no Firebase configuration, consent,
events or Keychain UI.

Actual LLVM **Lines** (`/tmp/kinetiq-firebase-coverage.txt`): owner **96.63%**
(208 lines/7 missed), Firebase adapter **21.31%** (61/48 missed), privacy UI **96.83%**
(63/2 missed), local store **100%** (20/0 missed). Matching profile:
`/tmp/kinetiq-firebase-release.profdata`; binary:
`.build/out/Products/Release/KinetiqTests.xctest/Contents/MacOS/KinetiqTests`.
Low adapter coverage is intentional: live startup/lifecycle, offline delivery and reset
are not tested. This is neither live-provider nor exhaustive coverage evidence.
An earlier overlapping Release rerun failed helper-frontmost/`windowNotShareable`
checks; the final serial run passed unchanged assertions. A separate compilation failed
when the sibling TelemetrySDK disappeared from disk; a clean clone restored the same
approved `c5e275421fa03c242c9c53b5431d919fdd18547a` pin, without SDK source edits.

Historical version **0.3.3 / build 38** was preserved in that migration; the later
GA4 follow-up was **0.3.4 / build 39**. F2 still requires actual Apple identity/private
scope, native backend ingestion review (console Analytics active per owner), live/native,
offline/revocation, terms/retention, notarization and hosted CI verification. The owner
requires commit/push for completed tasks on `firebase`, then a reviewed PR merge into `main`.
The local root client plist is ignored/excluded; `.vscode/launch.json` and `.serena/`
are preserved. The real post-documentation README capture-to-Metal optics regression
passed: **1 test, 0 failures** (`/tmp/kinetiq-firebase-postdocs.log`). Historical evidence below is unchanged.

**Historical PostHog telemetry acceptance before the coffee CTA:** SDK core 62/PostHog 10 tests, parser 11 and host contracts 24
pass. Final complete **Debug and Release: 328 tests each, 0 failures, 0 skips**, with
the native startup consent sheet and optional UI screenshots executed. Universal
app/saver signatures, configuration-presence checks and disabled signed smoke pass.
Release line coverage: owner **97.09%**, privacy UI/dialog **96.83%**.
Consented/live/distribution acceptance requires separate approval; see
[the detailed evidence](telemetry.md).

**Historical native coffee CTA acceptance (2026-11-08, pre-Firebase):** complete Release **330 tests
(148 app + 36 Effects + 146 Core), 0 failures, 0 skips**; Debug Management
**14 tests, 0 failures**, including the real sidebar CTA across three pages, two
sizes and light/dark appearances. Five owned UI screenshots were saved privately
under `/tmp/kinetiq-coffee-ui`; Overview and Studio were visually inspected.
Release log: `/tmp/kinetiq-coffee-release-suite.log`; Debug UI log:
`/tmp/kinetiq-coffee-management-debug.log`. LLVM **Lines** for `SupportCoffeeView`
are **97.92%** (`/tmp/kinetiq-coffee-coverage.txt`); hover dispatch is not fully covered.
Universal app/saver strict signatures, bundle checks and disabled signed smoke pass
(`/tmp/kinetiq-coffee-build.log`). Version/build remain 0.3.3/38. No automatic browser
open, checkout, analytics consent change, live event, commit or push was performed.

**Historical PostHog no-Keychain identity acceptance (2026-11-08):** complete Release **334 tests
(152 app + 36 Effects + 146 Core), 0 failures, 0 skips**, including **28 telemetry
contracts**; the focused Debug run also passes. Four new contracts use real isolated
preferences and the real SDK core to check consent-gated creation, relaunch persistence,
product isolation, malformed UUID fail-closed and identity reset/delete. LLVM Lines:
local store **100%** (20 lines), owner **97.58%**, privacy UI **96.83%**; these are
not live-delivery or exhaustive native-lifecycle claims. Logs/report:
`/tmp/kinetiq-no-keychain-release.log`, `/tmp/kinetiq-no-keychain-coverage.txt`.
Universal app/saver strict signatures, bundle checks and disabled signed smoke pass
(`/tmp/kinetiq-no-keychain-build.log`). Reopen **`build/Kinetiq.app`**, not an older
installed copy, to use the fix. Existing consent, version/build 0.3.3/38 and old
Keychain item are untouched; no normal consented launch or live probe was automated.

```sh
swift build                # build
swift test                 # physics, effects, management and native screen saver tests
swift test -c release      # complete release test suite
scripts/build-app.sh       # universal signed app, including its signed native .saver

# Render the close effects headlessly: checks every shader, texture and seed,
# and writes one contact sheet (PNG) per effect.
swift run kinetiq-effects-preview --check --out /tmp/wobbly-effects
swift run kinetiq-effects-preview --effect fire --out /tmp/wobbly-effects
```

`build-app.sh` signs with your "Apple Development" identity if you have one, or with `SIGN_IDENTITY` if set. Otherwise it uses ad-hoc signing with stable bundle-identifier requirements to preserve permission grants across rebuilds. Both the app and embedded screen saver are signed. Ad-hoc signing does not authorize native Firebase: that fallback stays `blocked_off` without the exact real Apple Team private group. Configured GA4 does not use this Keychain scope and still requires its own fresh consent.

**Historical pre-telemetry v0.3.3 / build 38 verification:** **304 release tests: 122 app + 36 Effects + 146 Core; 0 failures, 0 skips**, with both native UI and Destruction opt-in dumps enabled (`/tmp/kinetiq-v033-acceptance.log`). The real README capture-to-Metal contact sheet was visually inspected: text releases before shards, pieces pile up, the stage is clear at six seconds at 1×, and initial border clipping is correct. Native UI snapshots are in `/tmp/kinetiq-v033-ui` (Effects, Animation Studio and Performance); six native-resolution destruction frames and their contact sheet are under `/tmp/kinetiq-v033-destruction`. These are real test-window captures, not sample-window illustrations; temporary evidence is not a distributed artifact. Normal Window Destruction playback still writes no images to disk. Current GA4 acceptance and deferred owner checks are recorded in [docs/telemetry.md](telemetry.md); earlier failed Debug evidence is retained separately in its historical sections.

Final build completed with exit 0 (`/tmp/kinetiq-v033-final-build.log`). App and embedded saver were each verified with `lipo` as universal **x86_64 + arm64** and with `codesign --verify --deep --strict`. Packaged **0.3.3 / build 38** was launched from `build/Kinetiq.app` (PID 56054 at verification); Quick Look cache and Finder were refreshed. [TODO 19](../TODO.md) is **Done**.

Historical pre-telemetry LLVM release **line coverage** (`/tmp/kinetiq-v033-coverage.txt`, **Lines**, not Regions): `DestructionEffectPlayer.swift` **95.95%**, `OriginalEffectPreview.swift` **92.49%**, `LibraryEffect.swift` **98.49%**, `ChaosWorld.swift` **99.20%**, `ChaosRenderer.swift` **88.86%**. Coverage is not 100%; these Swift line figures neither measure Metal shader branch coverage nor establish every native failure path or display configuration. Preview uses a local floor without AX changes; native Close uses per-display floors and observes actual closure. Studio's 19 effects/schema 1 and screen saver behavior remain unchanged.

**Historical v0.3.2 / build 37 verification:** **287 release tests: 146 Core + 36 Effects + 105 app; 0 failures, 0 skips**, including optional native UI capture, real README capture-to-Metal drainage, native close/minimize and complete Liquid previews. Final direct log: `/tmp/kinetiq-v032-acceptance-direct.log`. New tests verify gradual bottom-edge exit without opacity loss, no early leakage for thin bottom-aligned windows, bounded retired particles, negative origins, duration scaling and deterministic stepping. The real rendered contact sheet was visually inspected. Universal arm64/x86_64 app and embedded saver passed strict signature verification; packaged version 0.3.2/build 37 was launched and Quick Look/Finder refreshed. Build: `/tmp/kinetiq-v032-final-build.log`. Merged release **line** coverage: `LiquidWorld.swift` **98.70%**, `LiquidEffectRenderer.swift` **100%**, `LiquidEffectPlayer.swift` **95.89%**, `OriginalEffectPreview.swift` **92.16%** (`/tmp/kinetiq-v032-coverage.txt`); these figures do not measure Metal shader branch coverage.

**Historical v0.3.1 / build 36 verification:** the release suite passed **284 tests: 144 Core + 36 Effects + 104 app**, with **0 failures and 0 skips** (`/tmp/kinetiq-v031-final-suite.log`). A new native geometry regression reproduces the former 4,000-point split overflow and bounds empty/populated Studio documents at minimum, reported and default window sizes, in light and dark appearances. Tests use actual catalog documents, native hosting windows and real Metal/capture paths; no user composition is saved or replaced. The final universal app and embedded saver passed strict signature checks; the packaged Studio was inspected empty, after Add Layer and while creating a keyframe track at minimum size. Quick Look/Finder were refreshed. Build log: `/tmp/kinetiq-v031-final-build.log`; merged line coverage: `/tmp/kinetiq-v031-coverage.txt` (not Metal shader branch coverage).

**Historical v0.2.1 / build 34 verification:** the final release suite passed **277 tests: 144 Core + 36 Effects + 97 app**, with **0 failures and 0 skips**. The app suite includes **11 Management + 7 OriginalEffectLibrary + 8 OriginalEffectPreview + 10 StudioUI + 61 other existing tests**. All 30 original shaders, six entrances, nine minimize morphs and Liquid passed genuine real-capture tests, including the README Liquid regression. Management tests verify all 65 navigation requests are routed and consumed, including repeated navigation. Local evidence: `/tmp/kinetiq-v021-suite.log`.

The completed build (`/tmp/kinetiq-v021-build.log`) produced **arm64 + x86_64** binaries for both the app and embedded `.saver`, verified directly with `lipo` and strict `codesign` checks. The actual packaged version is **0.2.1 / build 34**; the app was launched and Quick Look/Finder refreshed. Clicking native **Destruction → Dissolution → Fire — Original Close…** opened the exact original Fire detail; Accessibility inspection confirmed the 65-effect library, and `/tmp/kinetiq-v021-fire.png` was visually inspected. This inspection neither activated an effect nor changed user assignments. [TODO R2](../TODO.md) is Done.

Historical v0.2.1 merged release **line coverage** (`/tmp/kinetiq-v021-coverage.txt`): `LibraryEffect.swift` **100%**, `CatalogStore.swift` **100%**, `OriginalEffectPreview.swift` **85.32%**, `OriginalEffectDetailView.swift` **40.80%**. These figures do not measure Metal shader branch coverage.

**Historical v0.2.0 / build 33 verification (not current acceptance):** the final release suite passed **260 tests: 144 Core + 36 Effects + 80 app**, with **0 failures and 0 skips**, including that version's README real-capture Liquid regression and 19 management/Studio tests. Build 33's app and embedded saver were built for arm64/x86_64, passed strict signature verification, and the app was launched and inspected. Local evidence: `/tmp/kinetiq-v02-final-suite.log`; temporary logs are not distributed artifacts.

Historical v0.2.0 merged release coverage reports 98.97% lines for preset/document validation, 98.74% for the quality policy, 100% for catalog storage, 79.33% for the native runtime and 99.26% for the catalog renderer's Swift encoding path. These are not current v0.2.1 coverage figures, do not measure Metal shader branch coverage and do not promise coverage of every native failure. Optional `KINETIQ_UI_TEST_DUMP` under `/tmp` saves only the tests' own real Effects/Studio/Performance window screenshots, requiring Screen Recording.

The `KinetiqSaverSupport` target shares the Metal renderer and private scene archive between the app and `KinetiqScreenSaver`. Packaging embeds the universal `.saver` in `Kinetiq.app/Contents/Resources`; running a bare `swift run Kinetiq` cannot install the module. Native integration tests read the real wallpaper store and write only temporary copies. Desktop capture tests use real windows and skip when Screen Recording or a graphical session is unavailable; they never change the user's default screen saver. Run `swift test --enable-code-coverage` for coverage. Future macOS changes to the undocumented selection store may require a PaperSaver update; failures are surfaced in the Screen Saver page, with a shortcut to System Settings.

Liquid physics lives in `Sources/KinetiqCore/LiquidWorld.swift`; `KinetiqEffects/LiquidEffectRenderer.swift` implements the density/surface Metal passes, and `Kinetiq/LiquidEffectPlayer.swift` owns desktop overlays and live geometry. `swift test -c release --filter Liquid` exercises real display geometry, capture-to-Metal output, native picker selection, close detection and actual AX minimization/restoration of disposable README document windows. Graphical/permission-dependent tests skip only when those capabilities are absent; no user document is closed or moved. To inspect an opt-in contact sheet of the captured test document, set `KINETIQ_LIQUID_TEST_DUMP` to a directory under `/tmp` when running these tests; without it no image is persisted. The tests do not alter Dock preferences.

Native-resolution optical tests compare transported text edges against the actual captured pixels, isolate refraction/reflection without changing coverage, and compare the manual float32 filter to hardware filtering when supported. Set `KINETIQ_LIQUID_BENCHMARK=1` to print GPU timings for 40 warmed frames at three fluid states (simulation and readback excluded). With the temporary dump directory above, `KINETIQ_LIQUID_TEST_DUMP_FRAMES=1` also saves individual native-resolution test-document PNGs. Timings depend on GPU, display and current load; they are diagnostics, not fixed CI performance thresholds.

The graphical Liquid test displays this actual README in a disposable native text window; it requires more than 32 coherent edge samples at 1.5 s, a contrast ratio above 0.65 and material RGB error below 0.18. Text/layout changes can affect this real-capture regression and must be rechecked after documentation changes, not worked around with a fabricated image. The post-edit release-preparation recheck is recorded in `docs/telemetry.md`, separately from historical results.

### Source map and API reference

- `KinetiqCore`: catalog descriptors, strict schema-1 presets/documents, keyframe sampling, drag/dynamics policy and quality budgets.
- `KinetiqEffects`: original close shaders, Liquid renderer and `CatalogEffectRenderer.encode`, whose optional evaluated `parameters: [String: Float] = [:]` preserves existing callers. Missing custom values use descriptor defaults; finite values clamp to bounds, nonfinite values use defaults and unknown renderer dictionary keys are ignored. Strict preset JSON, unlike this low-level renderer dictionary, rejects unknown keys.
- `Kinetiq`: `LibraryEffect` combines Studio and original discovery; `OriginalEffectAssignment` reuses Settings and releases the corresponding catalog owner; `OriginalEffectDetailView` / `OriginalEffectPreview` provide original controls and captured previews. `CatalogStore` handles Studio persistence/trigger ownership; `CatalogRuntime` handles Studio capture/AX restoration/composition, alongside the library/Studio and performance UI.
- `KinetiqSaverSupport` / `KinetiqScreenSaver`: shared scene archive/renderer and native saver host integration.
- `Tests`: Core validation/physics, actual Metal asset rendering and real capture/AX/native UI integration. [Studio guide](animation-studio.md) covers editing, schema and adapter contracts.
