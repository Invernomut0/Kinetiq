# TODO

Statuses: To Do, Doing, Review, Done. Owner: Lorenzo (requests) / Copilot (implementation).

**Layouts capture admission — v0.4.2 / build 42:** task 22 Done (Copilot, implementation/local acceptance).
Reproduced the exact quality-budget error at nominal thermal pressure with four
real helper-owned README windows, in both Low and Auto (six pre-fix assertion
failures, `/tmp/kinetiq-layout-red.log`). Include shadow buffers in admission,
skip extra captures rather than cancel the overview, distinguish failure causes
and clear stale errors. The 32 MP total/eight-window maximum remain unchanged.
Complete Release: **380 passed** (196 app + 36 Effects + 148 Core), zero failures/skips,
including actual Low/Auto desktop Ripple → Incinerate playback and exact restoration.
Universal app/saver, strict signatures, bundle verification and disabled smoke passed.
Logs: `/tmp/kinetiq-layout-final-release.log`, `/tmp/kinetiq-layout-build.log`.
LLVM Lines: runtime 75.74%, capture 75.00%, compositor 96.47%, Studio UI 59.15%,
library UI 67.31% (`/tmp/kinetiq-layout-final-coverage.txt`), not exhaustive/Metal coverage.
Publication is tracked separately in Git/PR history; no new DMG or normal app restart.

**Budget and protected Settings — v0.4.1 / build 41:** task 21 Done (Copilot).
Low/Auto keep expensive effects available with bounded reduced resources; only
critical thermal pressure closes the gate. Kinetiq's exclusion is mandatory in
UI, settings and runtime, including legacy lists. Focused policy/exclusion tests:
20 passed; rendering/window suites: 55 executed, zero failures, one optional
screenshot skip. Complete Release: **376 passed** (192 app + 36 Effects + 148 Core),
zero failures/skips with native UI captures enabled. Universal app/saver both
x86_64 + arm64, deep/strict signatures, bundle verification and signed disabled
smoke passed. Logs: `/tmp/kinetiq-budget-release.log`, `/tmp/kinetiq-budget-build.log`.
LLVM Lines: quality 98.75%, Settings 94.09%, SetupWindow 78.61%, Performance 96.46%
(`/tmp/kinetiq-budget-coverage.txt`), not exhaustive integration/Metal coverage.

**Current GA4 Web transport — v0.3.4 / build 39:** **G1 Done (Copilot)** for verified
implementation and offline/local acceptance only; **G2 Review (Lorenzo)** for actual
Web-stream ingestion and distribution/privacy.
GA4 takes precedence with fresh default-off consent and separate app-local identity;
the native SDK remains linked but dormant in this mode. No Keychain access, automatic
native/OS/session events or realtime guarantee. Approved actual visits carry a positive
Date-based session ID and only positive consented ContinuousClock foreground engagement;
no automatic startup/Overview events or fake timing. The owner authorizes an extractable
ingestion secret; server-only secret deployment remains recommended. No admin JSON.
Complete current **Release and Debug each passed 361 = 179 app + 36 Effects + 146 Core;
0 failures, 0 skips, exit 0**, `/tmp/kinetiq-ga4-fix-release.log` and
`/tmp/kinetiq-ga4-fix-debug.log` (`DEBUG_EXIT=0`). Debug app duration approximately
**1928 seconds**, completed, not hung. Focused Release: **55 = 21 GA4 Swift + 34 native
contracts, 0 failures**, `/tmp/kinetiq-ga4-fix-focused.log`; actual denied Settings
mount → grant while visible without navigation → exactly one event → revoke uses
the retained owner and recording boundary. GA4 disclosure is tested; no normal
consented app GUI launch or live GA4 collection was automated.

Python GA4: **26 passed, 0 failures/errors/skips, exit 0**; native parser: **19 passed,
0 skips**; signing: **5 ran, 4 passed, 1 skipped**, real Apple Team unavailable.
Current explicit session-aware Google debug probe: **0 validation messages, exit 0**,
structure only, not authentication/ingestion. Its real Web session ID and optional
measured probe-preparation timing are not app engagement; ordinary tests/smoke are offline.
Universal build: **`BUILD_EXIT=0`**, `/tmp/kinetiq-ga4-fix-build.log`, app+saver each
**arm64 + x86_64**, both deep/strict signatures verified **0**. Direct terminal
resource verifier **0**, `KINETIQ_TELEMETRY_BUNDLE_CHECK_SUCCESS`; signed disabled smoke
**0**, `KINETIQ_TELEMETRY_DISABLED_SMOKE_SUCCESS`; no saved logs invented for these checks.
Native fallback is `KINETIQ_FIREBASE_SIGNING_BLOCKED_OFF`, **not GA4 unavailable**:
the local `build/Kinetiq.app` contains owner GA4 configuration and works without
Keychain after fresh default-off consent.

Actual Release LLVM **Lines**, not Regions: provider **77.09% (275/63 missed)**,
owner **97.08% (240/7)**, privacy UI **89.69% (97/10)**, store **100% (20/0)**,
native adapter **21.31% (61/48)**. Matching binary:
`.build/out/Products/Release/KinetiqTests.xctest/Contents/MacOS/KinetiqTests`;
profile `/tmp/kinetiq-ga4-fix-release.profdata`; report `/tmp/kinetiq-ga4-fix-coverage.txt`.
Approved live data-task/response/cancellation and 30-minute session-boundary exclusions
are **not runtime-tested**; no ingestion or exhaustive/100% integration coverage claim.
Full suites include real README optics. The focused post-documentation rerun using
`swift test -c release --filter 'LiquidIntegrationTests/testCapturedREADMEOpticsPreserveNativeTextContrast'`
passed the actual Test Case in **2.618 seconds: 1 test, 0 failures, 0 skips, exit 0**
(`/tmp/kinetiq-ga4-fix-postdocs.log`). The initial dot-filter attempt selected
0 tests and is not a successful regression run.

**Workflow:** Owner-requested publication uses commits/push on firebase, reviewed PR and normal merge into main. Git history and PR are publication evidence; local packaging is not new DMG release.

Two root `.env` keys remain ignored/local only, **not uploaded or provisioned in
GitHub CI**. Workflow builds without owner `.env` fall back safely to native blocked
off and **do not produce a configured GA4 release app**. Hosted CI is unverified.

**Historical native Firebase migration:** F1/F2 record native-only acceptance. T1–T5 and
the 328/330/334-test evidence are historical PostHog/pre-Firebase records; their Done
statuses do not certify this migration. Old consent/UUID are untouched but not reused.
F1 is Done for implementation and verified offline/local acceptance only: complete
final Debug and serialized restored-core Release each passed 339 tests (157 app +
36 Effects + 146 Core), including 33 telemetry contracts, with zero failures/skips.
Actual signing remains `KINETIQ_FIREBASE_SIGNING_BLOCKED_OFF`, not
`PRIVATE_GROUP_READY`. F2 remains Review; no owner gate is closed.

**Historical native follow-up:** the owner requests commit/push for each completed task on
`firebase`, then a reviewed PR merge into `main`. The local root client plist is ignored/excluded;
`.vscode/launch.json` and `.serena/` are preserved. The real post-documentation
README optics gate passed: 1 test, zero failures (`/tmp/kinetiq-firebase-postdocs.log`). An earlier overlapping
Release rerun failed helper-frontmost/`windowNotShareable`; the final serial suite
passed unchanged assertions. A separate missing-sibling-SDK compile failure was
resolved by a clean clone at the same approved `c5e275421fa03c242c9c53b5431d919fdd18547a`
pin, without SDK source edits.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 22 | Fix false quality blocks caused by capture accounting and stale errors | Done | Owner: Copilot, implementation/local acceptance. v0.4.2/build 42; real four-window pre-fix regression reproduces failure at Low/Auto. Include shadow allocation, skip over-budget additional windows, retain hard memory limits and mandatory own exclusions; separate error causes and clear stale messages. Complete Release 380 passed (196 app + 36 Effects + 148 Core), zero failures/skips, including actual desktop Ripple/Incinerate and restoration. Universal app/saver, signatures, bundle and disabled smoke passed; exact logs/coverage above. |
| 21 | Relax effect quality gate and protect Settings exclusion | Done | Owner: Copilot. 12-step resource-only Auto ladder, expensive effects allowed at Low/serious thermal pressure, critical thermal and memory/capture safety retained; protected Kinetiq rule enforced in UI, settings and runtime. Complete Release 376 passed (192 app + 36 Effects + 148 Core), zero failures/skips, including actual captured-README rendering and protected rule persistence. Universal app/saver, strict signatures, bundle and disabled smoke passed. Exact logs/Lines coverage above. |
| 20 | v0.4.0 Studio built-ins, My Effects, complete Try menu, interactive Layouts | Done | Owner: Copilot. Built-in close/open/minimize engines as Studio layers through `LayerCompositor`, reverse playback, saved compositions owning Open/Close/Minimize, Try menu with every effect, animated hover/keyboard/scroll overview with ⌃⌥↑ and five-window demos. See CHANGELOG 0.4.0 for verification. |
| G1 | Owner-authorized GA4 Web transport and current offline/local acceptance | Done | Owner: Copilot. Implementation and offline/local acceptance only, 0.3.4/build 39. Single retained owner/core, fresh consent/identity, GA4 precedence, native fallback unchanged. Ready/enabled/consent-keyed cancellable 100 ms actual Settings task, not busy state; real denied mount/grant while visible without navigation/exactly one event/revoke exercised with retained owner and recording boundary. GA4 disclosure tested, no normal consented app GUI launch/live collection automated. Complete Release/Debug each 361 (179 app + 36 Effects + 146 Core), 0 failures/skips, exit 0; Debug app completed in ~1928 seconds. Focused 55 (21 GA4 Swift + 34 native), 0 failures. Python GA4 26 passed/0 failures/errors/skips; parser 19 passed/0 skips; signing 5 ran/4 passed/1 real-Team skip. Current session-aware debug probe 0 messages/exit 0, structure only; probe timing is not app engagement. Universal app+saver arm64+x86_64 build exit 0; both deep/strict signatures, resource verifier and signed disabled smoke verified 0 directly. Lines and exact artifacts above; live data tasks/response/cancellation/30-minute session boundary unexecuted at runtime, not ingestion/exhaustive coverage. Full suites include README optics; focused post-doc slash-filter rerun verified 1 test, 0 failures/skips, exit 0, actual Test Case passed in 2.618 seconds (/tmp/kinetiq-ga4-fix-postdocs.log). |
| G2 | GA4 Web ingestion, consented transport and distribution/privacy review | Review | Owner: Lorenzo. Actual Web-stream credentials/console ingestion, IP/location/retention/access/erasure/privacy, extractable-secret spam risk, terms, notarization and release provisioning remain open; hosted CI unverified. Root .env two ignored keys are local only, not uploaded/provisioned in GitHub CI; builds without owner .env use safe native blocked-off fallback, not a configured GA4 release app. Reopen actual build/Kinetiq.app containing owner configuration, then manually visit Settings → Privacy & Analytics with explicit consent and check Reports → Realtime. Home November 1–7 excludes Today November 8. HTTP acceptance/204 and debug validation do not prove authentication/ingestion. Use Web G- measurement ID and its own ingestion secret, not numeric/native app IDs; tagging banner alone is not MP failure. Consented cold/relaunch/live cancellation/offline/revocation remain owner review; no fake engagement/realtime guarantee. KINETIQ_FIREBASE_SIGNING_BLOCKED_OFF is native fallback status, not GA4 unavailability; no Keychain in configured GA4. Publication follows the standing workflow above. |
| F1 | PostHog → official Google Firebase Analytics implementation and local acceptance | Done | Owner: Copilot. Implementation + offline/local acceptance only. Firebase Apple SDK 12.6.0 / GoogleAppMeasurement 12.5.0, unchanged approved generic core pin, consent-only singleton startup, fresh consent keys, no old identity reuse. Complete final Debug and serialized restored-core Release each 339 (157 app + 36 Effects + 146 Core), including 33 telemetry contracts, zero failures/skips. Python parser/artifacts 19 passed/0 skipped, including real linked Google ParamsEntry/sEntry collision regression with correct vendor boundaries. Signing 5 ran: 4 passed/1 skipped (real-Team positive unavailable for actual ad-hoc app). Universal build exit 0, actual app+saver arm64+x86_64, deep/strict signatures pass. Actual KINETIQ_FIREBASE_SIGNING_BLOCKED_OFF, NOT PRIVATE_GROUP_READY; controls safely unavailable without actual Apple private scope. Bundle verifier exit 0 KINETIQ_TELEMETRY_BUNDLE_CHECK_SUCCESS: broad Sentry false positive fixed/tested, not ignoring vendor symbols; sanitized client only in app, core privacy/MIT intact, old providers absent. Saver has no Firebase product/configuration/entitlement. Disabled signed smoke exit 0 KINETIQ_TELEMETRY_DISABLED_SMOKE_SUCCESS; no Firebase configure/consent/events/Keychain UI. LLVM Lines: owner 96.63% (208/7 missed), adapter 21.31% (61/48), privacy 96.83% (63/2), store 100% (20/0); live start/lifecycle/offline/reset untested. Exact logs/profile/binary in README/docs. Version/build 0.3.3/38 preserved. |
| F2 | Historical native Firebase consented/offline delivery and distribution review | Review | Owner: Lorenzo. Native fallback still requires actual Apple signing identity/private Team.bundle scope, unavailable and unverified; GA4 does not remove that native gate. Console Analytics active per owner; client IS_ANALYTICS_ENABLED is not authoritative console state or ingestion proof. Actual signed restart/cold launch, live/native lifecycle deduplication, offline/retry/queued/in-flight revocation and denied relaunch, ingestion, IP/location/retention/erasure policy, project/environment/advertising changes, applicable binary terms, hosted CI/privacy report and notarization remain unverified. Explicit approval before real provider/event verification; no pending gate is claimed complete. |
| T5 | Analytics identity without Keychain prompts | Done | Owner: Copilot. Default host store uses product-scoped app-local preferences; old Keychain item never read/migrated/deleted. Existing consent preserved; UUID creation consent-gated. Four real-preference/core contracts added, 28 telemetry contracts pass. Full Release 334 (152 app + 36 Effects + 146 Core), zero failures/skips; focused Debug passes. Store Lines 100%, owner 97.58%, privacy UI 96.83%. Universal app+saver strict signatures, bundle check and disabled smoke pass; reopen build/Kinetiq.app. Version/build 0.3.3/38 preserved; no SDK edit, normal consented launch, live probe, commit or push. Exact evidence in README/docs. |
| C1 | Native Buy Me a Coffee CTA | Done | Owner: Copilot. Persistent yellow/black/coffee SwiftUI sidebar link to the verified Invernomut0 HTTPS profile; opens browser only on click, no scripts/fonts/checkout or analytics changes. Debug Management 14 pass; full Release 330 (148 app + 36 Effects + 146 Core), zero failures/skips. CTA pixels verified across 3 pages × 2 sizes × light/dark; Overview/Studio real screenshots inspected. CTA Lines 97.92%; universal app+saver signatures, bundle check and disabled smoke pass. Version/build 0.3.3/38 and user changes preserved; no commit/push. Logs and coverage in README. |
| T4 | Explicit startup analytics permission | Done | Owner: Copilot. First configured launch asks through the existing management window; Don't Share is default. Answers persist independently of configuration failures. Six new host/native regressions pass, including the actual sheet response. Final Debug/Release each 328 tests, zero failures/skips; universal app rebuilt and signed, disabled smoke passes. No automatic consent or live events. |
| T1 | Host-owned PostHog integration and offline acceptance gates | Done | Owner: Copilot. SDK core 62/PostHog 10, parser 11, host contracts 24 pass. Final complete Debug/Release each 328 tests (146 app + 36 Effects + 146 Core), zero failures/skips; initial Liquid failures resolved unchanged. Universal app+saver signatures, bundle/configuration-presence checks and disabled signed smoke exit 0. Owner/privacy UI Lines 97.09%/96.83%. Pin enforces clean checkout while allowing ignored dotenv. Copied guide text/path preserved (nonsemantic extra EOF newline). No SDK edits, live events, commit/push or version change; owner-gated acceptance stays T2/T3 Review. See docs/telemetry.md. |
| T2 | SDK pin/configuration and distribution privacy review | Review | Owner: Lorenzo. Confirm verified pin, project/environment separation, disclosure/retention/IP policy and signed access scope. Actual checkout is already 0.3.3/build38, unlike supplied 0.3.2/build37; preserved existing values pending review. CI execution and notarization not certified locally. |
| T3 | Consented signed native identity/lifecycle/staging delivery | Review | Owner: Lorenzo. Explicit approval required before any verification starts a real provider/event. Identity now uses app-local preferences, not Keychain (T5); consented signed restart, native lifecycle deduplication, offline/retry/queued revocation and backend ingestion remain unexecuted. Disabled smoke and recording boundaries are not live evidence. |
| 19 | v0.3.3 build 38 Window Destruction | Done | Owner: Copilot. Close-only built-in (`destruction`), global/per-app/library selection and transparent one-shot Chaos preview/playback documented. Current manifest: 66 entries = 19 Studio + 47 originals; category totals 5/31/15/10/2/3. Final release: 304 tests (122 app + 36 Effects + 146 Core), zero failures/skips, both UI/Destruction opt-in dumps. Real README contact sheet inspected, initial clipping correct and clear at six seconds. Universal app+saver strict signatures verified; packaged 0.3.3/build 38 launched, Quick Look/Finder refreshed. |
| 18 | v0.3.2 Liquid bottom-edge drainage | Done | Owner: Copilot. Slow corner-to-center floor outlets replace the final fade; material stays opaque until fully offscreen. Complete preview/deadline timing shared. Final direct release: 287 tests (146 Core + 36 Effects + 105 app), zero failures/skips. Actual captured drainage visually inspected; universal app+saver strict signatures verified, version 0.3.2/build 37 launched and Quick Look/Finder refreshed. |
| 17 | v0.3.1 Studio/sidebar viewport correction | Done | Owner: Copilot. Reproduced a 4,146-point native split inside a 768-point window; bound both native columns, not just the outer split. Empty/populated Studio regression passes at minimum, reported and default sizes in light/dark appearances. Guide becomes a popover while editing. Final release: 284 tests (144 Core + 36 Effects + 104 app), zero failures/skips; universal app+saver strict signatures verified. Packaged Studio inspected empty, after Add Layer and while creating a keyframe track at minimum size; no user document saved. Quick Look/Finder refreshed. |
| 16 | v0.3.0 UI restructure: event-based menu and library, sample-window previews, real Wobbly preview, Studio guidance | Done | Owner: Copilot. Menu bar and Effects library organized by Drag/Open/Close/Minimize with the current choice visible and one-click assignment; every effect previews immediately on a built-in sample window (real windows optional); Wobbly preview replays `KinetiqModel` under a scripted drag; Studio has a guide, example document and “Use It” step; dashboard reduced to 11 pages. Debug suite: 283 tests — 144 Core + 36 Effects + 103 app — 0 failures; 28 app tests skipped only because the xctest host lacked Screen Recording. New `SampleWindowPreviewTests` cover all 65 effects without that permission. |
| R2 | v0.2.1 build 34 original-effects recovery final verification | Done | Owner: Copilot. 277 release tests passed (144 Core, 36 Effects, 97 app), zero failures/skips, including genuine original-engine captures and the README Liquid regression. Historical v0.2.1 line coverage recorded; app and embedded saver verified universal arm64/x86_64 with strict signatures and actual version 0.2.1 / build 34. Packaged app launched, exact native Fire detail inspected without activation/assignment changes, Quick Look/Finder refreshed. |
| R1 | v0.2.0 build 33 final release verification | Done | Owner: Copilot. Historical evidence only: 260 release tests, zero failures/skips; universal app and embedded saver built, strict signatures verified, packaged app launched and visually inspected. Quick Look and Finder refreshed. Does not verify build 34. |
| 1 | Open effects | Done | Owner: Copilot. The v0.1.9 reversed-shader path was superseded by v0.1.22 jelly entrances; v0.2.0 also supports explicitly assigned captured catalog entrances. Code/test verification is complete; final release acceptance is R1. |
| 2 | Inertia and bounce off the screen edges after releasing a drag | Done | Owner: Copilot. `KinetiqModel.fling`, bounded real-screen physics and settling covered by the release suite. |
| 3 | 3D tilt while dragging | Done | Owner: Copilot. Unit-tested `Tilt`, perspective mesh projection and quality safety gating. |
| 4 | Minimize effect | Done | Owner: Copilot. Yellow-button native minimize, exact-window AX parking/restoration and real capture tests pass. ⌘M and Dock actions remain native. |
| 5 | Per-app close effects | Done | Owner: Copilot. Legacy overrides persist and are tested; an explicit catalog Close owner takes precedence until removed. |
| 6 | Focus highlight | Done | Owner: Copilot. Optional accent glow on focus; deferred after entrances and quality-gated. Global dimming of other windows is not implemented or claimed. |
| 7 | Ripple at the drop point | Done | Owner: Copilot. Bounded radial wave, settling and explicit catalog Drag policy are tested. |
| 8 | Native screen saver and desktop destruction | Done | Owner: Copilot. Voronoi fragments, letters/buttons, Metal renderer, real archive, native module and selective system selection/restoration tested. Final packaged build verification is R1. |
| 9 | Shared 65-effect library and permanent category mapping | Done | Owner: Copilot. Historical v0.2.1 LibraryEffect / NSMenu / library totals: 5 Window Motion, 31 Transitions, 14 Destruction, 10 Spatial, 2 Physics, 3 Workspace. Includes 19 unchanged Studio entries and 46 originals (30 close, 6 entrances, 9 minimize, Liquid once). All 65 routing requests consumed, repeated navigation tested, five-tab details and explicit per-trigger assignments verified; exact native Fire menu/detail inspection completed under R2. |
| 10 | Adaptive quality and truthful performance diagnostics | Done | Owner: Copilot. Five choices, 13-step Auto ladder/recovery, actual completed GPU timings, thermal/power caps and bounded native/intermediate resource handling. |
| 11 | Animation Studio and validated preset/document storage | Done | Owner: Copilot. Timeline/layers/tracks/keys, five outgoing curves, 100-snapshot undo/redo, guarded copy/paste and strict schema-1 JSON. No tangent editor claimed. |
| 12 | Twelve-page dashboard and five-tab Effects library | Done | Owner: Copilot. Original eight pages plus Studio, Layouts, Workspaces and Performance; real-window previews and explicit save/run/reset controls. |
| 13 | Real runtime adapters, trigger ownership and safe fallbacks | Done | Owner: Copilot. Native Close/Minimize/Open routing, snapshotted Drag, real AX physics and bounded interactive current-Space overviews. Unsupported mixed physics/overview compositions fail explicitly. |
| 14 | v0.2.0 English documentation | Done | Owner: Copilot. README, changelog and Studio guide reflect actual schema, catalog, budgets, runtime limits and final verification evidence. |
| 15 | v0.2.1 original-effects English documentation | Done | Owner: Copilot. README, changelog, TODO, Studio guide and original-effects guide describe exact categories/full original list, existing IDs, explicit assignment ownership, panel-only previews and unchanged Studio schema/Physics controls. Final build-34 verification and its line coverage are retained as historical evidence. |

## Historical pre-telemetry v0.3.3 / build 38 status

The evidence below belongs to task 19, before telemetry changes. It does not certify
the current worktree; current GA4 gates are G1/G2, historical native gates are F1/F2
and `docs/telemetry.md`.

- **Done — Owner: Copilot (task 19).** Final release acceptance: **304 tests — 122 app + 36 Effects + 146 Core; 0 failures, 0 skips** (`/tmp/kinetiq-v033-acceptance.log`), with both UI and Destruction opt-in dumps. Real README capture-to-Metal contact sheet inspected: text before shards, piling, clear at six seconds at 1× and correct initial clipping. Real test-window snapshots remain under `/tmp/kinetiq-v033-ui` and `/tmp/kinetiq-v033-destruction`, not fabricated sample images or distributed artifacts.
- Final build exit 0 (`/tmp/kinetiq-v033-final-build.log`); app and embedded saver verified universal x86_64/arm64 with `lipo` and `codesign --verify --deep --strict`. Packaged 0.3.3/build 38 launched from `build/Kinetiq.app` (PID 56054 at verification); Quick Look cache and Finder refreshed.
- LLVM release **line** coverage (`/tmp/kinetiq-v033-coverage.txt`, not Regions): DestructionEffectPlayer 95.95%, OriginalEffectPreview 92.49%, LibraryEffect 98.49%, ChaosWorld 99.20%, ChaosRenderer Swift 88.86%. Not 100% or Metal shader branch coverage; no claim that every native failure path/display configuration is covered.
- Documented scope: Close only, `LibraryEffect.destruction` / `CloseEffectChoice.destruction` raw `destruction`, Destruction / Fragmentation, global/per-app/library assignment with **Use when a window closes**. Off/Random remain unchanged (30 close shaders); Fire stays the default. Studio's 19 effects/schema 1 and the existing saver are unchanged.
- Shared `UIObjectExtractor` / `ChaosScene` / `ChaosWorld.destroyWindow()` / `ChaosRenderer` in transparent `oneShot` mode: no wallpaper or restoring/rebuilding loop. Glyphs/icons release at 0.02–0.22 normalized seconds, shards at 0.4–1.15; gravity, bounce and piles fade with a three-normalized-second lifetime. Full six-second preview at 1× scales with shared 0.25×–3× duration.
- Per-display floors behind the Dock, click-through overlays, at most two source captures including pending work, 32 MP / 16384 per dimension per source, and 1200 glyphs / 160 other objects / 256 target tiles per display. Local-floor previews make no AX changes or live-window mutations; expensive-gate refusal, memory-only captures, no disk images or saver activation.
- Historical completed tasks and verification below retain their original release counts; they do not establish v0.3.3 acceptance.

## Historical v0.3.2 / build 37 verification

- **287 release tests passed: 146 Core + 36 Effects + 105 app; 0 failures, 0 skips.** Final direct log: `/tmp/kinetiq-v032-acceptance-direct.log`; build: `/tmp/kinetiq-v032-final-build.log`. The earlier helper-frontmost failure passed on isolated retry and in the final complete suite; no native assertions were weakened.
- Tests cover progressive physical exit, stable opacity/UV identity, no predrain leakage for thin bottom-aligned sources, negative origins, duration scaling, deterministic stepping and a clear final real-capture preview. Initial melting, real-window shelf collisions and water optics retain their regressions. Real rendered drainage contact sheet inspected.
- Merged release line coverage (`/tmp/kinetiq-v032-coverage.txt`): LiquidWorld 98.70%, LiquidEffectRenderer Swift 100%, LiquidEffectPlayer 95.89%, OriginalEffectPreview 92.16%; not Metal shader branch coverage.
- Universal arm64/x86_64 app and embedded saver passed strict signature checks; actual packaged 0.3.2/build 37 launched, Quick Look/Finder refreshed. User effect assignments/documents and unrelated `.vscode/launch.json` / `.serena/` were preserved.

## Historical v0.3.1 / build 36 verification

- **284 release tests passed: 144 Core + 36 Effects + 104 app; 0 failures, 0 skips.** Final log: `/tmp/kinetiq-v031-final-suite.log`; build: `/tmp/kinetiq-v031-final-build.log`; merged line coverage: `/tmp/kinetiq-v031-coverage.txt`. The new native geometry test fails on the original oversized layout and passes for empty/populated documents, three sizes and light/dark appearances.
- Signed universal arm64/x86_64 app and embedded saver verified directly. Packaged app version 0.3.1/build 36 launched; sidebar, Add Layer, inspector tabs, timeline and actual keyframe-track creation inspected at minimum size without saving the document or changing event assignments. Guide no longer overlaps the populated editor. Quick Look/Finder refreshed.

## Historical v0.2.1 / build 34 verification

- **277 release tests passed: 144 Core + 36 Effects + 97 app; 0 failures, 0 skips.** The app suite includes 11 Management + 7 OriginalEffectLibrary + 8 OriginalEffectPreview + 10 StudioUI + 61 other existing tests. Final log: `/tmp/kinetiq-v021-suite.log`; opt-in UI captures: `/tmp/kinetiq-v021-ui`.
- **R2 and task 9 are Done.** All 65 navigation requests are routed and consumed, including repeated navigation; `onChange(initial: true)` fixes `@Published` reentrancy. Original assignment tests verify release of only the selected owner, preserving its parameters/tracks, other owners, per-app rules and exclusions.
- All 30 original shaders, six entrances, nine minimize morphs and Liquid passed genuine real-capture tests, including the README Liquid regression. Preview safety checks cover no native move/close/minimize, local minimize destination, retained Liquid floor/no desktop obstacles, 8 MP / 8192 target bounds, 32 MP source capture bound, two-request limit, cancellation/backing lifetime and explicit expensive-mode refusal.
- `CatalogRuntimeTests` waits for WindowServer opacity **and** an origin matching the child window's actual AppKit frame before testing restoration: macOS can slide an already opaque native window in from negative X. No restoration assertions were weakened.
- Build script completed (`/tmp/kinetiq-v021-build.log`). App and embedded `.saver` each passed direct arm64/x86_64 `lipo` and strict signature checks; actual packaged version is 0.2.1 / build 34. App launched and Quick Look/Finder refreshed.
- Native **Destruction → Dissolution → Fire — Original Close…** opened the exact original Fire detail. Accessibility inspection confirmed the 65-effect library; `/tmp/kinetiq-v021-fire.png` was visually inspected. No effect was activated and user assignments were unchanged.
- Historical v0.2.1 merged release line coverage (`/tmp/kinetiq-v021-coverage.txt`): `LibraryEffect.swift` 100%, `CatalogStore.swift` 100%, `OriginalEffectPreview.swift` 85.32%, `OriginalEffectDetailView.swift` 40.80%. This is not Metal shader branch coverage.
- Studio remains 19 effects/schema 1; originals are not JSON layers. Shared original close/minimize duration stays 0.25×–3× (default 1×); entrances and older glide/tilt/focus/ripple/maximize/resize controls stay on Physics.

## Historical v0.2.0 / build 33 evidence and scope

- Historical final `/tmp/kinetiq-v02-final-suite.log`: **260 release tests passed — 144 Core + 36 Effects + 80 app; 0 failures, 0 skips**. Includes 19 management/Studio tests, all compiled catalog effects and that version's real-capture Liquid regressions. Not current build-34 verification.
- Build-33 app and native saver both contain arm64/x86_64 and passed `codesign --verify --deep --strict`; the actual packaged app was launched and visually inspected. Historical v0.2.0 coverage is recorded in `/tmp/kinetiq-v02-final-coverage.txt`; it is not current coverage, and shader encoding-path coverage is not Metal branch coverage.
- Product boundaries: no native Spaces switching/private Spaces APIs, no permanent Orbit layout, no global desktop DOF/depth buffer, no Bézier tangent editor, and no desktop mixing of physics/overview with other enabled layers. These are explicit limits, not substitute demos.

## Done

- Sharper, more realistic and optimized Liquid optics — Owner: Copilot. Done in v0.1.31: 140 tests passed (3 new optical regressions, no skips). Native-resolution float32 UV transport, bounded water refraction and Fresnel/studio reflections; cropped fields, polynomial kernels, shared destination pass and bounded texture reuse. Real Retina capture retained 94% of measured coherent-edge contrast versus 13% previously; Apple M3 Pro GPU means 0.15–0.29 ms versus 0.50–0.57 ms in the three sampled states (diagnostic measurements, not universal guarantees).
- Liquid close and yellow-button minimize effect — Owner: Copilot. Done in v0.1.30: 137 tests passed (27 new, no skips), universal signed app built and launched. Top-right melting, live window-edge collisions, per-display bottom pooling behind the Dock and slow fade; real capture/Metal output, native controls and actual close/AX minimize restoration verified. New fluid line coverage: Core 96.50%, renderer 100%, player 95.52%.
- Native macOS default screen saver — Owner: Copilot. Done in v0.1.29: 110 tests passed (12 new, no skips), universal signed native module loaded successfully by macOS legacyScreenSaver, real selection/restore verified, wallpaper preserved and snapshot deleted on disable. Includes explicit privacy consent and dependency notices.
- Native management dashboard with eight sidebar destinations, real window inventory, permission and engine diagnostics, and isolated UI/settings tests — Owner: Copilot. Done in v0.1.28: all 98 tests passed (7 new management tests); universal app built, signed and launched; dashboard inspected on screen.
- Rename to Kinetiq, Setup window, app exclusions (v0.1.4 - v0.1.8).
