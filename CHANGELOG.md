# Changelog

All notable changes to Kinetiq are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.1] — Build 44

### Changed

- Owner-authorized macOS configured country for GA4's standard **Country** dimension: only top-level JSON `user_location: {country_id: <ISO 3166-1 alpha-2>}`, not a custom country parameter/definition. Google's fields are optional; country alone is valid and its subdivision recommendation does not authorize an invented `region_id` or city.
- GA4 requires fresh **consent revision 3**, default **Don't Share**; prior revision-2 grants stay off until a new disclosed choice. Native Firebase remains revision **2** with unchanged signing gates; existing mode-specific consent/identity namespaces are preserved.
- Main-task source contract: typed optional `GA4ConfiguredCountry`, reading only `Locale.current.region?.identifier` inside consented provider start after `configuration.enabled && privacy.analyticsEnabled`. Snapshot only in memory until stop/revocation, then clear; refresh on next consented start. Static builder receives explicit country, default `nil`; nil/invalid country omits `user_location`.
- Configured country is not citizenship or physical location and can override GA4 attribution/distort maps. No language/time-zone fallback, GPS, IP lookup, external geolocation service, new network permission, `ip_override`, fabricated city or subdivision. Existing six events/five custom keys, owner/core/transport bounds and saver isolation remain unchanged.
- The closed catalog accepts only 249 assigned ISO country/territory codes, excluding macroregions/reserved/user-assigned values. Host privacy metadata conservatively declares non-tracking coarse-country analytics linked to the pseudonymous client ID, not physical location or a new permission.

### Verification status

- **Task 24 Done — Copilot**, implementation/local acceptance only. Final Release **414 = 230 app + 36 Effects + 148 Core**, zero failures/skips, includes **89 analytics contracts** and seven Country/manifest regressions (`/tmp/kinetiq-country-final-release.log`). Earlier 413-test full suite also passed; the initial focused compile's two incomplete negative test events were corrected before acceptance.
- Matching LLVM **Lines**: country validator 85.71%, GA4 77.30%, owner 97.24%, privacy UI 89.69%, taxonomy 100%, native adapter 20% (`/tmp/kinetiq-country-coverage.txt`, `/tmp/kinetiq-country-final-release.profdata`). Actual user-region getter/default closures and live delivery remain unexecuted; not exhaustive, Debug or Metal coverage.
- Actual universal app/saver **0.5.1/44**, x86_64 + arm64, strict signatures, bundle and signed disabled smoke passed (`/tmp/kinetiq-country-build.log`; direct checks). No normal app restart, real consent/preferences change or live event.
- Owner-requested **task 25 Done — Copilot**: [GitHub v0.5.1 Latest release](https://github.com/Invernomut0/Kinetiq/releases/tag/v0.5.1) published from verified local DMG, with uploaded DMG/checksum states, sizes and server SHA-256 digests matching local bytes. PR #7 merged normally at `2a8d3f4d937111f5602d1a50424cec53a37a4d30`; annotated tag targets that exact commit. Repository remains private and requires authorized login. Installation docs explain source archives, permissions, menu-bar launch/quit, non-notarized/ad-hoc signatures, preferred Open Anyway and targeted `xattr -dr com.apple.quarantine` versus broad `xattr -cr`; no global Gatekeeper disablement. G2/F2 owner review remains open.
- Final post-documentation **90 passed = 89 analytics + 1 actual captured-README optics**, zero failures/skips (`/tmp/kinetiq-country-postdocs.log`, actual optics 2.672 seconds). DMG integrity/read-only byte comparison, app/saver signatures and universal 0.5.1/44 metadata passed; checksum reports OK (`/tmp/kinetiq-country-dmg.log`). Exact tag/asset digests are recorded in `docs/telemetry.md`; publication-record documentation does not move the tag or change assets.
- Hosted tag `Release` and `Telemetry host gates` workflows report failure, not a hosted pass. Local verified artifacts were published independently; no billing settings/checks/protections were changed.
- Final private-download/publication README clarification rechecked with actual capture-to-Metal optics: **1 test, zero failures/skips, exit 0, 2.867 seconds** (`/tmp/kinetiq-country-publication-readme.log`), unchanged assertions.
- Current PR **#7** hosted `host` job did not start because of GitHub account billing/spending limits; no hosted tests/build ran. Owner Billing & plans review/rerun remains open. Local acceptance is separate; no account settings or branch protections were changed.

## [0.5.0] — Build 43

### Added

- Owner-authorized product-usage scope with a fresh **revision-2**, default-off opt-in in each transport mode. Older grants do not silently extend: an updated disclosed choice is required, with **Don't Share** default and legacy mode-specific consent/identity preserved.
- Typed closed custom events `feature_used`, `effect_played`, `effect_selected`, `studio_action`, `screensaver_action` and `quality_changed`; only `feature`, `effect_id`, `trigger`, `action`, `quality`. IDs use the real 66-entry library plus `custom`/`wobbly_classic`; `off`/`random` are selection-only. No user content, custom names, app IDs, window metadata, precise location, hardware metadata or free-form properties.
- Successful playback starts separated from selections and manual/native/layout triggers; automatic preview loops excluded. Actual Studio/Lab visits and validated edits/save/import/export, app-side saver enable/disable/preview (not OS host runs), and explicit quality choices (not automatic adaptation).
- Practical manual GA4 custom-definition/Explore instructions, reporting latency and geography limitations. No external geolocation service, GPS/IP lookup or location overrides; MP-only City/Country may remain `(not set)`. Native fallback may derive geography only if actually enabled behind unchanged gates.

### Boundaries and verification

- Reuse the single AppDelegate owner through a weak static hook and unchanged generic SDK core. At most four immediate product-event tasks, no disk queue/retry/replay; existing four-request GA4 cap retained. Best-effort/drop-prone counters are not an exact usage census. Native signing gates unchanged; no saver SDK.
- Complete final Release: **407 passed = 223 app + 36 Effects + 148 Core, zero failures/skips**, including **82 analytics contracts** and same-turn save/assignment and layer/import regressions (`/tmp/kinetiq-usage-final-acceptance.log`). Earlier native capture/window-origin failures remain documented; all 15 runtime tests passed in isolation, then the full suite passed unchanged assertions. No runtime fix or exclusion bypass was made to obtain the rerun.
- After the final README update, **83 passed = 82 analytics + 1 actual captured-README optics**, zero failures/skips, exit 0 (`/tmp/kinetiq-usage-postdocs.log`).
- Hosted PR #6 `host` CI was blocked before job startup by GitHub account billing/spending limits. No hosted tests ran; owner review/rerun is required. No account settings or branch protections were changed.
- LLVM **Lines**: taxonomy **100.00%**, owner **97.56%**, GA4 provider **77.09%**, native adapter **20.00%**, privacy UI **89.69%** (`/tmp/kinetiq-usage-coverage.txt`, matching `/tmp/kinetiq-usage-final-acceptance.profdata`). Not exhaustive, live-delivery or Metal branch coverage.
- Universal app/saver **0.5.0/build 43**, each x86_64 + arm64, strict signatures, bundle verifier and signed disabled smoke passed (`/tmp/kinetiq-usage-build.log`; direct artifact checks). No normal user-app restart, real consent/preferences change, live probe or console automation. HTTP 2xx is not ingestion proof; G2/F2 remain owner Review. No new DMG/tag/release or hosted CI success is claimed. Historical acceptance below is retained, not recertified for the broader scope.

## [0.4.2] — Build 42

### Fixed

- Layouts capture admission now includes ScreenCaptureKit's 100-point shadow room on every side. Previously an additional capture could pass the opaque-window estimate, exceed the total 32 MP after allocation, and abort the entire overview even at Low/Auto and nominal thermal pressure. Extra windows that do not fit are skipped, retaining already prepared captures; the primary window still fails explicitly if too large. Native pixels, the 32 MP total and eight-window maximum are preserved.
- Separate capture-memory, texture-allocation, renderer-busy, invalid-resource and critical-thermal errors instead of claiming every failure is a quality-disabled effect. Layouts displays the admitted window count.
- Clear previous operation errors when stopping, retrying, editing a Studio document or opening another effect page. A quality update that reopens the thermal gate clears only the thermal refusal; unrelated failures remain visible until a new operation.

### Verification

- A native regression with four real, test-owned README windows reproduced the exact former message in both Low and Auto before the fix: one test, six assertion failures (`/tmp/kinetiq-layout-red.log`). The test restricts selection to its helper PID, never capturing user windows.
- Complete Release: **380 passed — 196 app + 36 Effects + 148 Core; zero failures/skips** (`/tmp/kinetiq-layout-final-release.log`). Actual desktop Ripple → Incinerate runs at Low/Auto, clears the previous failure, renders overlapping layers, restores the exact helper-window origin and retains a specific critical-thermal refusal. Real captures also verify shadow estimation, bounded overview admission and selective thermal-error recovery. Initial focused suites: 55 passed (`/tmp/kinetiq-layout-focused.log`).
- Universal app/saver **0.4.2 / 42**, both x86_64 + arm64 and strict signatures passed; bundle verifier and signed disabled smoke passed (`/tmp/kinetiq-layout-build.log`). No normal app restart, consent change or live analytics was automated.
- LLVM **Lines**: runtime **75.74%**, capture **75.00%**, compositor **96.47%**, Studio UI **59.15%**, library UI **67.31%** (`/tmp/kinetiq-layout-final-coverage.txt`, profile `/tmp/kinetiq-layout-final-release.profdata`). Not exhaustive integration, all display configurations or Metal shader branch coverage.
- After the README update, all 15 runtime tests and the real captured-README optics regression passed again: **16 tests, zero failures/skips, exit 0** (`/tmp/kinetiq-layout-postdocs.log`).

## [0.4.1] — Build 41

### Fixed

- Low quality and the entire Auto ladder now reduce resource use without disabling expensive effects. The former final Auto gate could prevent further GPU work and thus the samples needed to recover, leaving effects unavailable. Adaptation now has 12 resource-only steps; the existing GPU thresholds and memory/capture limits are unchanged.
- Serious thermal pressure still caps quality at Low but permits effects. Critical thermal pressure retains the expensive-effects block and 15 Hz secondary ceiling, including for manual Ultra; cooling below critical reopens the gate without needing a GPU sample.
- Kinetiq's own Settings/management windows are permanently excluded. The Rules entry is locked, model removal is rejected, settings reads/writes preserve the mandatory rule, and runtime checks protect Kinetiq even with legacy or externally edited exclusion lists. Other app rules and internal previews remain available.

### Verification

- Complete Release suite: **376 passed — 192 app + 36 Effects + 148 Core; zero failures/skips**, with real capture/Metal playback, Low-quality heavy-effect previews, critical thermal refusals, recovery and isolated persisted exclusion tests. Log: `/tmp/kinetiq-budget-release.log`.
- Universal app and embedded saver: **x86_64 + arm64**, version **0.4.1 / 41**, both deep/strict signatures passed. Bundle verification and signed disabled smoke passed; no normal consented app launch or live analytics probe. Build log: `/tmp/kinetiq-budget-build.log`.
- LLVM **Lines**: quality policy **98.75%**, Settings **94.09%**, SetupWindow **78.61%**, PerformanceView **96.46%** (`/tmp/kinetiq-budget-coverage.txt`). Not exhaustive integration or Metal shader branch coverage.

## [0.4.0] — Build 40

### Added

- **Built-in effects in the Animation Studio.** Add Layer now offers all 30 original close shaders (Incinerate, Fire, Broken Glass…), the 6 spring entrances and the 9 Dock morphs next to the 19 Studio effects. A new `LayerCompositor` plays them in document order on one capture, each layer reading the previous one's output, in a stage with room around the window, for both previews and desktop playback. Built-in layers have timing, speed curve and direction; their look stays the original. Liquid and Window Destruction are not layers (they are desktop-wide simulations) but can be tried from the menu.
- **Play in reverse** for any layer: a close shader becomes an entrance (the shaders' own opening direction), a minimize morph becomes a restore.
- **My Effects.** Studio compositions are saved by name (`CustomEffect`, `customEffects.v1`) and can own Open, Close or Minimize exactly like a preset: one owner per event across presets and custom effects. The Studio toolbar has **My Effects**, **Save** (⌘S) and **Use when…**, plus a status line saying whether and where the effect is used. The Effects library lists My Effects first with a looping preview, **Use when…** buttons, Run, Edit in Studio and Delete; the menu bar's Open, Close and Minimize submenus list them too.
- **Try an Effect** now covers every effect: My Effects, the 30 close shaders, 6 entrances, 9 minimize morphs, Liquid, Window Destruction and the 19 Studio effects, each played once on the front window and put back.
- **Interactive, animated Layouts.** Windows fly from their real positions into Exposé 3D, Orbit or Cube with a spring and fly back on exit; the dimmed backdrop fades with them. Pointing at a window lifts it (Exposé straightens it to face you) and shows its app and title; click brings it forward with a return animation; arrow keys, Tab and Return navigate; scroll spins the orbit or the cube carousel; Escape or right-click puts everything back. Cube is now a carousel with one window facing you. Geometry lives in the pure `OverviewLayout`, shared by the desktop and the preview so hit-testing matches what is drawn.
- **⌃⌥↑ anywhere** opens the chosen layout (and closes it again), through Carbon `RegisterEventHotKey`: only that combination reaches Kinetiq, no other keystroke is observed. Toggle and layout choice on the Layouts page; the menu has **Arrange Windows**.
- The Layouts page shows each layout as a looping demo with five windows (rest, fly in, browse, fly back), sliders that change it live, Start, Use for Shortcut and Defaults.

### Changed

- The Studio preview loops with its own Play button and follows edits while playing; the separate transport is gone. Clicking the ruler moves the playhead. New layers start where the previous ones end. The example document is a Studio Ripple followed by the built-in Incinerate. Inspector tabs are Edit, Keyframes and Advanced.
- Studio documents are schema 2 (adds `builtin` and `reversed` per layer). Schema 1 documents still import and are upgraded; a schema 1 file cannot contain built-in layers.
- Manual runs started from Kinetiq's own window (Layouts Start, Run on Window with the sample source) target the topmost eligible window instead of failing; an explicit window ID still never falls back.

### Fixed

- The preview player rendered the subject it started with: parameter edits made while playing did not appear until it was paused.
- "Stop using" a Studio owner now releases the event so the built-in choice underneath plays again, instead of switching that event off.

### Verification

- `swift test` (debug): **Core 145 passed, Effects 36 passed, app 112 run with 28 skipped and 1 failing test.** The failure is `LiquidIntegrationTests.testLiquidPickersInRealNativeHostingViews`; it fails identically on the unmodified v0.3.0 commit in the same session, because SwiftUI exposed only 1–3 accessibility elements to the test process there (an environment condition, not a regression). The 28 skips need Screen Recording in the test host.
- New tests: schema-1 upgrade and schema-2 built-in/reversed round trip; My Effects persistence, single ownership with presets, release and invalid input; every one of the 45 built-in layers animating and reversing on the sample window; Ripple feeding Incinerate; overview geometry (home → arranged, highlight on top, carousel and orbit); the five-window overview demo returning every window home; the Try menu covering all 66 library effects.
- `scripts/build-app.sh`: universal arm64/x86_64 app and saver, `codesign --verify --deep --strict` OK, Info.plist 0.4.0 / 40. Preview frames of the three layouts and the Ripple → Incinerate composition were inspected.
## [0.3.4] — Build 39

### Added

- Owner-authorized direct **GA4 Web Measurement Protocol** provider using the existing single application owner and unchanged generic TelemetrySDK core. Valid GA4 bundle configuration takes precedence over the still-linked, dormant native Firebase SDK; invalid presence fails closed. Native fallback signing/Keychain gates remain unchanged.
- Fresh default-off GA4 Boolean consent and separate app-local pseudonymous identity without Keychain access or transfer of previous consent/UUIDs. Only the actual `feature_used` / `privacy_settings` action is sent; no native automatic, OS/hardware, lifecycle or synthetic session/engagement events. Approved actions carry a positive actual-Date session ID, refreshed after 30 minutes without approved actions, and only positive actual consented foreground engagement measured with ContinuousClock and NSApp notifications. Zero engagement is omitted; no automatic startup/Overview events or fake timing fill graphs. Advertising user data/personalization are denied; connection IP/network processing remains disclosed, with no report/realtime guarantee.
- Sanitized GA4 Settings `transportStatus`: readiness, submitted count, in-flight count, HTTP acceptance and categorical failure without URLs/secrets. HTTP acceptance is not confirmed ingestion; filtered core installation events are not transport failures.
- Bounded root-local ignored `.env` packaging through `scripts/configure-ga4.py`, recognizing only `KINETIQ_GA4_MEASUREMENT_ID` and `KINETIQ_GA4_API_SECRET`, writing exact `measurement_id` / `api_secret` fields only to the main app resource. Runtime never reads `.env`; saver/wrong-ID destinations, invalid/admin extras and stale absent configuration are handled locally.
- Standalone offline `scripts/test_ga4_config.py`: genuine owner-only positive cases (skip absent), invalid-input contracts and categorical assertions, with no fabricated valid credentials, network mocks or live requests. Explicit `--validate` is debug event-structure validation only, not secret authentication/ingestion proof and not automatic CI.

### Fixed

- The actual SwiftUI one-shot Settings `.task` could run before analytics consent was granted and never submit the visit. Key it by readiness, runtime enablement and consent (not busy state), wait 100 ms, and cancel when the actual visible visit becomes ineligible or disappears.
- Correct telemetry documentation's obsolete no-session/no-engagement claims, stale pending acceptance and confusion between LLVM Regions and **Lines**. Current Python GA4 acceptance is **26 passed**. Owner troubleshooting: reopen actual `build/Kinetiq.app`, use Reports → Realtime and an actual consented Privacy & Analytics visit; Home November 1–7 excludes Today November 8. HTTP 204 does not authenticate the secret or prove ingestion, Web measurement IDs start with G- (not numeric stream/native app IDs), and website-tagging banners alone do not prove MP failure.

### Privacy and acceptance

- The owner explicitly authorizes an **extractable bundled ingestion secret**, enabling forged/spam events and contrary to recommended server-only secret deployment. No administrator/service-account credentials are packaged. Web-stream credentials differ from the native Firebase app stream; console Analytics is active per owner, not proven ingestion.
- Ephemeral bounded transport, rejected redirects, no disk queue/retries/delivery acknowledgement; withdrawal suppresses new requests and cancels pending work but cannot erase received server data. Local identity remains in preferences.
- Current complete **Release and Debug each passed 361 tests = 179 app + 36 Effects + 146 Core; 0 failures, 0 skips, exit 0**, `/tmp/kinetiq-ga4-fix-release.log` and `/tmp/kinetiq-ga4-fix-debug.log` (`DEBUG_EXIT=0`). Debug app suite completed in approximately **1928 seconds**, not hung. Focused Release: **55 = 21 GA4 Swift + 34 native contracts, 0 failures**, `/tmp/kinetiq-ga4-fix-focused.log`. Actual native Settings mounted denied, granted while visible without navigation, recorded exactly one event and revoked using the retained owner and recording boundary. GA4 disclosure was tested; no normal consented app GUI launch or live collection request was automated. Full suites include real README capture-to-Metal optics. The focused post-documentation rerun using `swift test -c release --filter 'LiquidIntegrationTests/testCapturedREADMEOpticsPreserveNativeTextContrast'` passed the actual Test Case in **2.618 seconds: 1 test, 0 failures, 0 skips, exit 0** (`/tmp/kinetiq-ga4-fix-postdocs.log`). The initial dot-filter attempt selected 0 tests and is not a successful regression run.
- Current Python GA4: **26 passed, 0 failures/errors/skips, exit 0**; native parser: **19 passed, 0 skips**; signing: **5 ran, 4 passed, 1 skipped**, because the real Apple Team is unavailable. Current explicit session-aware Google debug probe: **0 validation messages, exit 0**, structure validation only, not authentication/ingestion. It uses a real Web session ID and optional measured preparation timing, **not app engagement**; ordinary tests and smoke are offline.
- Universal build **`BUILD_EXIT=0`**, `/tmp/kinetiq-ga4-fix-build.log`; actual app and embedded saver each **arm64 + x86_64**, both deep/strict signatures verified **0**. Direct terminal resource verifier **0**, `KINETIQ_TELEMETRY_BUNDLE_CHECK_SUCCESS`; signed disabled smoke **0**, `KINETIQ_TELEMETRY_DISABLED_SMOKE_SUCCESS`; no saved logs claimed for direct checks. Local `build/Kinetiq.app` contains owner GA4 configuration and works without Keychain after fresh default-off consent. Native fallback status **`KINETIQ_FIREBASE_SIGNING_BLOCKED_OFF` is not GA4 unavailability**.
- Actual Release LLVM **Lines**, verified from the report header, not Regions: GA4 provider **77.09% (275 lines/63 missed)**, owner **97.08% (240/7)**, privacy UI **89.69% (97/10)**, store **100% (20/0)**, native adapter **21.31% (61/48)**. Matching binary `.build/out/Products/Release/KinetiqTests.xctest/Contents/MacOS/KinetiqTests`; profile `/tmp/kinetiq-ga4-fix-release.profdata`; report `/tmp/kinetiq-ga4-fix-coverage.txt`. Approved live data-task/response/cancellation and 30-minute session-boundary exclusions are **not runtime-tested**; no ingestion, exhaustive integration coverage or Metal branch-coverage claim.
- Reported categorical runtime check: root/bundle configuration matches the Web stream public ID **G-NWQ84487HV**, same configuration `true`, typed GA4 consent `TRUE`; no app process at the reported process check. This is not request or ingestion evidence. No live production configuration or owner preferences were touched.
- **G1 Done — Copilot**, implementation and verified offline/local acceptance only; **G2 Review — Lorenzo**, actual Web-stream credentials/console ingestion, consented cold/relaunch/live offline/cancellation/revocation, IP/location/retention/access/erasure/privacy, extractable-secret spam risk, terms, notarization and release provisioning. Hosted CI execution is unverified. Native F1 evidence stays historical; native blocked-off signing is unchanged and dormant in configured GA4 mode.
- Two root `.env` keys remain ignored and local only; credentials are **not uploaded or provisioned in GitHub CI**. Workflow builds without owner `.env` fall back safely to native blocked off and **do not produce a configured GA4 release app**. Version **0.3.4 / build 39**.
- **Workflow:** Owner-requested publication uses commits/push on firebase, reviewed PR and normal merge into main. Git history and PR are publication evidence; local packaging is not new DMG release.

## [0.3.3] — Build 38

### Added

- **Window Destruction**, a Close-only built-in available in the global Close menu, per-app close rules and the Effects library with **Use when a window closes**. `LibraryEffect.destruction` and `CloseEffectChoice.destruction` use raw ID `destruction`, with Destruction / Fragmentation metadata.
- A shared **66-entry** manifest: 19 unchanged Studio effects + 47 originals (30 close shaders, 6 entrances, 9 minimize morphs, Liquid and Window Destruction). Combined category totals are **5 / 31 / 15 / 10 / 2 / 3**. Off and the 30-shader close Random pool are unchanged; Fire remains the default. Studio schema 1 and its layer model are unchanged.
- Captured-window destruction through shared `UIObjectExtractor`, `ChaosScene`, `ChaosWorld.destroyWindow()` and transparent `ChaosRenderer` `oneShot` rendering, without wallpaper or a restoring/rebuilding scene loop. Glyphs/icons release over 0.02–0.22 normalized seconds, shards over 0.4–1.15; gravity, bounce and piling end in a fade with a three-normalized-second lifetime. The complete preview timeline is six seconds at 1×, scaled by the shared 0.25×–3× duration multiplier.
- Per-display desktop floors behind the Dock and click-through overlays; at most two source captures including pending work, each at most 32 megapixels / 16384 per dimension, with 1200 glyphs, 160 other objects and 256 target tiles per display. Sample/real-window previews use a local floor without AX movement or touching the live window; the expensive-effects gate refuses playback rather than substituting another effect.
- Memory-only Window Destruction captures: no disk images, screen saver activation or changes to the existing saver behavior/settings. Updated English guides and completed TODO 19 release acceptance.

### Verification

- Final release suite: **304 tests — 122 app + 36 Effects + 146 Core; 0 failures, 0 skips** (`/tmp/kinetiq-v033-acceptance.log`), with both native UI and Destruction opt-in dumps. Real README capture-to-Metal contact sheet visually inspected: text before shards, piling, clear at six seconds at 1× and correct initial border clipping. Real test-window snapshots are under `/tmp/kinetiq-v033-ui` and `/tmp/kinetiq-v033-destruction`, not fabricated sample images or distributed artifacts; normal playback remains memory-only.
- Final build exit 0 (`/tmp/kinetiq-v033-final-build.log`); app and embedded saver each verified universal x86_64/arm64 with `lipo` and `codesign --verify --deep --strict`. Packaged 0.3.3/build 38 launched from `build/Kinetiq.app` (PID 56054 at verification); Quick Look cache and Finder refreshed.
- LLVM release **line** coverage (`/tmp/kinetiq-v033-coverage.txt`, not Regions): DestructionEffectPlayer 95.95%, OriginalEffectPreview 92.49%, LibraryEffect 98.49%, ChaosWorld 99.20%, ChaosRenderer Swift 88.86%. Not 100%, not Metal shader branch coverage, and not proof of every native failure path/display configuration. Local-floor previews do not mutate windows; actual Close retains its native lifecycle. Studio schema/layers and screen saver behavior are unchanged. Prior release results below remain historical evidence.

## [0.3.2] — Build 37

### Changed

- Replace original Liquid's final global fade with slow physical drainage through bottom outlets opening from both corners towards the center over six normalized seconds. Gentle outward floor flow preserves the initial melt, real-window shelf collisions and behind-Dock pool.
- Keep material opaque until every particle's full kernel is below the display. Retain particle indices/UVs while retiring drained samples from physics, bounding their final positions just below the screen.
- Replay the complete Liquid ending in sample/real-window previews, sharing geometry-dependent timing with the desktop safety deadline. Update library and settings descriptions without changing assignments, preferences or Studio Liquid Morph.
- Cover progressive physical exit, no early leakage from thin bottom-aligned sources, negative display origins, duration scaling, deterministic stepping and real capture-to-Metal opacity/clear completion.

### Verification

- Final direct release suite with coverage: **287 tests — 146 Core + 36 Effects + 105 app; 0 failures, 0 skips**, including opt-in native UI captures and genuine captured-document drainage/preview regressions. Initial native helper-frontmost failure passed on isolated retry and the complete final suite, without weakening assertions.
- Actual drainage contact sheet visually inspected; universal arm64/x86_64 app and embedded saver passed strict signature checks. Packaged 0.3.2/build 37 launched; Quick Look/Finder refreshed. Current line coverage: LiquidWorld 98.70%, Liquid renderer Swift 100%, player 95.89%, original preview 92.16% (not Metal shader branch coverage).

## [0.3.1] — Build 36

### Fixed

- Bound each `NavigationSplitView` column to its actual viewport. Native ideal-size propagation previously laid out a roughly 4,146-point split inside a 768-point window, leaving the sidebar, page header, Studio toolbar, inspector and timeline outside the visible area. Bounding the outer split alone was insufficient.
- Keep the Studio introduction inline only for empty documents. A persistent **?** button opens it in a popover, so it no longer overlaps the preview/inspector after adding a layer at compact window sizes.
- Preserve the 960 × 700-point minimum content area, all 65 library effects, the 19 Studio effects, saved documents and event assignments.

### Verification

- Release suite with coverage: **284 tests — 144 Core + 36 Effects + 104 app; 0 failures, 0 skips**. The new native geometry regression failed against the original layout and passes with empty/populated documents at three window sizes in light/dark appearances. Existing shader, real-capture, runtime restoration and editor tests remain in the suite.
- Final app and embedded saver verified universal arm64/x86_64 with strict signatures; packaged version 0.3.1/build 36 launched. Native Studio checked empty and after Add Layer, including inspector tabs and keyframe-track creation at minimum size, without saving a user document. Quick Look/Finder refreshed.

## [0.3.0] — Build 35

### Changed

- **Menu bar organized by window event.** Drag, Open, Close and Minimize are top-level submenus whose titles show the current choice (“Close: Fire”). Each lists Off, Random, every compatible built-in effect and the compatible Studio presets; choosing an item applies it immediately through the same `SetupModel.assign` path as the library. The six abstract categories, the three-level effect menus and the “Title — Original Close…” labels are gone; categories remain as metadata and group **Try an Effect on the Front Window** (19 Studio effects, run once and restored). Title-bar drag and the shortcut modifier moved to Settings. Added **Effects Library…** (⌘E); **Setup…** is now **Settings…**.
- **Effects library rebuilt around what you do.** Sidebar sections “When you drag a window”, “When a window opens”, “When a window closes”, “When you minimize” and “Overview & layouts” list every compatible effect with a one-line description and a checkmark on the active one; headers show the current choice and offer Off/Random; search covers all 65. The detail page is preview first, then one **Use when…** button per supported event, then collapsible **Customize** and **More**. The five-tab detail, the separate original detail view and the Window Trigger Assignments footer were removed.
- **Previews need no window.** A drawn sample window (`SampleWindow`) is packaged like a ScreenCaptureKit capture, so every effect — including all 46 originals — previews immediately and loops; the source menu switches to a real window (captured only). The shared `PreviewSourceStore` keeps the choice across effects and the Studio. Playback self-paces: a frame starts only after the previous one finished, with a short hold on the last frame before looping.
- **Wobbly preview uses the real spring mesh.** `OriginalPreviewRenderer` replays `KinetiqModel` under a scripted title-bar drag (1.8 s move, release, settle to 3 s) with the preset's stiffness, friction, speed and amplitude. Catalog previews now render through the preview renderer's own `CatalogEffectRenderer` into a stage with room around the window, so Genie's funnel and falling fragments are not cropped and the desktop runtime is never compiled by navigation.
- **Animation Studio explains itself.** A dismissable how-it-works card, an empty state with **Add Layer** and **Load an Example** (Ripple then a keyframed Fold), labelled Undo/Redo, a **File** menu, a Save button that reads “Saved” when nothing changed, and inspector tabs **Edit**, **Keyframes**, **Use It** and **Advanced**. **Use It** saves the layer as the effect's preset and assigns it to a window event in one step. **Open in Animation Studio** in the library adds the current preset as a layer. The Studio previews on the sample window too; Run on Window targets the preview source.
- **Dashboard: 11 pages.** Layouts and Workspaces merged into **Layouts** (Exposé 3D, Orbit, Cube, each with a preview and a Start button). Sidebar groups everyday pages and a System group. Overview gained a **What plays right now** card.
- **Studio Wobbly shader** now reads as a spring sheet let go after a drag (lagging far edge, overshoot, damped ring-out driven by stiffness and friction) instead of a generic membrane. Endpoints are still exact.
- `LibraryEffect` gained `blurb`, `kindLabel`, `isStudio`, `automaticTriggers` and `supporting(_:)`; `EffectTrigger` gained user-facing `eventTitle`, `shortTitle`, `symbol`, `explanation` and `librarySections`; `TriggerAssignment` resolves what an event currently plays across the catalog store and original settings. Persisted identifiers, preferences, the 19-effect catalog and JSON schema 1 are unchanged.

### Fixed

- Per-call `CatalogRuntime` instances (and a Metal library compile) are no longer created for every catalog preview frame.
- Importing a preset for a different effect from an effect's page now reports which effect it belongs to instead of silently switching pages.

### Verification

- `swift test` (debug): **283 tests — 144 Core + 36 Effects + 103 app; 0 failures.** 28 app tests were skipped because the test host had no Screen Recording grant (real-capture, Liquid integration and runtime restoration tests); they are unchanged. New `SampleWindowPreviewTests` render all 65 effects, the scripted Wobbly replay, multi-layer documents and budget refusals on the sample window without any permission, and can dump PNGs (`KINETIQ_PREVIEW_DUMP`) for inspection.
- `StudioUITests` now verify the event-based menu: every compatible effect per trigger, correct tokens, exactly one checked choice per event, and the 19-effect Try menu.

## [0.2.1] — Build 34

### Fixed

- Restored all prior effects directly to the six shared native-menu/library categories through `LibraryEffect`: 65 entries (19 Studio, 30 original close shaders, 6 original entrances, 9 original minimize morphs and Liquid counted once). Combined category counts are Window Motion 5, Transitions 31, Destruction 14, Spatial Effects 10, Physics 2 and Workspace & Overview 3.
- Original menu actions identify their engine with “Title — Original Close/Open/Minimize…” labels (Liquid: “Original Close / Minimize…”) and open the exact detail instead of silently assigning a trigger or running a Studio namesake.
- Original details provide Preview, Parameters, Triggers, Performance and Reset tabs. Explicit Use for Close/Open/Minimize writes the existing Settings/raw IDs and releases only the corresponding catalog owner, preserving its parameters/tracks and all other owners. Opening a detail or preview makes no assignment changes. Per-app close overrides and exclusions remain unchanged; per-app choices can still override the global original close selection.
- Real captured-window original previews reuse `CloseEffectRenderer`, `KinetiqModel` entrances, `DockMorphDeformer` and `LiquidWorld` / `LiquidEffectRenderer`. Playback stays inside the panel: no real movement, close or minimize; minimize has a local destination, and Liquid retains a local floor without desktop obstacles. Native trigger playback is unchanged.
- Original previews enforce 8-megapixel / 8192-per-dimension targets, 32-megapixel source captures, at most two in-flight requests, cancellation and capture-backing retention through GPU completion. Original shader and Liquid previews refuse playback when expensive effects are disallowed.
- Fixed `@Published` navigation reentrancy using `onChange(initial: true)`; all 65 effect requests are routed and consumed, including repeated navigation.
- Stabilized the `CatalogRuntimeTests` window helper by waiting until WindowServer reports both opacity and the same origin as the child window's actual AppKit frame before testing restoration. macOS can slide a native Core Graphics window in from negative X even after it becomes opaque; restoration assertions were not weakened.

### Changed

- Renamed the former Legacy Window Triggers footer to Window Trigger Assignments, retaining all global choices, Off and Random; originals no longer depend on that footer for discovery.
- Kept the shared original close/minimize duration at 0.25×–3×, default 1×. Original entrances still use Physics; older spring/mesh, glide, tilt, focus, ripple, maximize and resize controls remain there. Original shader uniforms keep compiled defaults, not new per-effect JSON controls.
- The 19-effect Studio catalog, schema-1 presets/documents and layer model are unchanged. Originals are not Studio JSON layers; similarly named effects remain distinct.
- Updated English README, Studio guide and TODO, and added a complete original-effects guide. This is a v0.2.1 / build 34 correction, not a v0.3.0 schema expansion.

### Verification

- Final release suite: **277 passed — 144 Core + 36 Effects + 97 app; 0 failures, 0 skips** (`/tmp/kinetiq-v021-suite.log`). App tests comprise 11 Management, 7 OriginalEffectLibrary, 8 OriginalEffectPreview, 10 StudioUI and 61 other existing tests. All 30 original shaders, six entrances, nine minimize morphs and Liquid passed genuine real-capture tests, including the README regression.
- Build script completed (`/tmp/kinetiq-v021-build.log`); app and embedded `.saver` both verified directly as universal arm64/x86_64 with strict signatures. Packaged version 0.2.1 / build 34 confirmed, app launched, Quick Look/Finder refreshed.
- Native NSMenu selection Destruction → Dissolution → Fire — Original Close… opened the exact original Fire detail. Accessibility inspection confirmed 65 effects and `/tmp/kinetiq-v021-fire.png` was visually inspected; no effect was activated and no user assignment changed.
- Merged release line coverage (`/tmp/kinetiq-v021-coverage.txt`): `LibraryEffect.swift` 100%, `CatalogStore.swift` 100%, `OriginalEffectPreview.swift` 85.32%, `OriginalEffectDetailView.swift` 40.80%. These are not Metal shader branch-coverage figures. TODO R2 and task 9 are Done.

## [0.2.0] — Build 33

### Added

- Shared 19-effect catalog with stable raw IDs, bounded parameters and Default/Subtle/Dramatic presets. Six permanent categories in the native menu and Effects library: Window Motion (2), Transitions (4), Destruction (4), Spatial Effects (4), Physics (2), Workspace & Overview (3).
- Effects library with Preview, Parameters, Triggers, Performance and Reset tabs; real-window selection, captured previews, saved presets, strict JSON import/export and same-effect parameter copy/paste.
- Functional Animation Studio motion editor: transport/scrubbing, layer timeline, parameter tracks, editable keyframes, evaluated curve display and explicit Undo/Redo buttons with 100 snapshots. Outgoing segment curves are linear, easeIn, easeOut, easeInOut and spring; no cubic-Bézier tangent editor is claimed.
- Strict schema-1 preset/document serialization: unknown fields/versions/parameters fail validation; bounded values, unique IDs, ordered key times and layer containment are enforced. Limits: 32 layers/document, 64 tracks/preset, 128 keys/track, 0.1–12-second presets and up to 60-second documents.
- Auto/Low/Balanced/High/Ultra quality selection, actual completed Metal GPU timings and independent texture, particle, blur-sampling, mesh and secondary-rate budgets. Auto starts at High, degrades one resource at a time across 13 steps and recovers with hysteresis; thermal/Low Power safety caps apply to manual settings too.
- Twelve-page management dashboard: Animation Studio, Layouts, Workspaces and Performance join the previous eight destinations; App Rules is now Rules.
- Real desktop catalog adapters: restoring manual playback, explicit single-owner native trigger routing, snapshotted drag policies and AX Magnet/Gravity. Cube, Orbit and Exposé 3D compose frozen current-Space captures (up to eight windows / 32 megapixels), with Escape dismissal and projected-window activation.
- Budget-scaled Studio ping-pong intermediates, bounded to 8 megapixels / 8192 pixels per dimension per texture and two in-flight compositions. Captures and desktop destinations remain native resolution.
- English Studio usage/schema/API guide and documented runtime boundaries, resource budgets and native fallback behavior.

### Changed

- Menu effect actions run the saved preset on an eligible frontmost-app window; they do not assign triggers. Explicitly saving/importing an automatic assignment replaces only that action's previous catalog owner. Legacy preferences remain until assigned and resume when the assignment is removed.
- The original 30 close shaders, Liquid simulation, jelly entrances, Dock morphs, permissions and native screen saver remain available; Liquid Morph is a separate catalog transition.
- Unavailable or budget-refused effects report errors/refuse playback and preserve native behavior instead of showing substitute demos. Physics/interactive overview desktop playback requires one enabled layer; panel composition does not imply native physics composition.
- Workspace names describe captured current-Space overviews, not private-API native Space switching, permanent layouts or a full workspace compositor. DOF affects the captured target only, not a global desktop depth buffer. “Blur passes” denotes shader sampling rings, not full-screen multipass blur.

### Verification (historical v0.2.0 evidence)

- Final release suite: 260 passed (144 Core, 36 Effects, 80 app), zero failures and zero skips, including real-capture Liquid regressions, compiled catalog shaders and 19 management/Studio tests.
- Build 33 app and embedded native saver: universal arm64/x86_64, strict signatures verified; packaged app launched and inspected. Quick Look/Finder refreshed.
- Dashboard titles identify the current page; supported minimum content area is 960 × 700 points. UI tests mount a production-equivalent hosting controller and respect native toolbar sizing.

## [0.1.31]

### Changed

- Liquid transports precise material UV coordinates instead of averaging RGB in the low-resolution field. Text and images are sampled directly from the original capture at output resolution, preserving Retina detail during flow.
- Water-like Snell refraction, Schlick Fresnel reflectance and procedural softbox reflections replace the blurred color-field bend. Refraction is bounded to keep fine glyphs legible; no extra desktop capture is needed.
- Cropped geometry fields and surface quads, a polynomial kernel without per-fragment exponentials, and one shared destination pass reduce shader work. Bucketed texture sizes and a bounded LRU prevent allocation churn between sources.
- Added real-capture native-resolution contrast regression, optional GPU timings, hardware/manual float32 filtering comparison and independent reflection/refraction checks.

## [0.1.30]

### Added

- **Liquid** close and yellow-button minimize effect: top-right liquefaction, captured window colors, connected glossy flow, real-window edge collisions and bottom pooling behind the Dock with delayed fade.
- Deterministic bounded particle fluid, spatial neighbors, density relaxation, viscosity and cohesion; live exposed-window geometry and per-display floors.
- Persistent Liquid choices in Effects and per-app close rules, without changing existing defaults or Random catalogs.
- Real-display physics tests and capture-to-Metal, native picker, actual close and AX minimize/position-restoration integration tests using disposable README windows.

### Fixed

- Cancelled asynchronous close/minimize captures cannot restart effects or park a window after controller cancellation.

## [0.1.29]

### Added

- Signed native ScreenSaver.framework module, installed per user and selected as the macOS default on explicit enable.
- PaperSaverKit 0.4.3 integration, real system selection/error feedback and macOS inactivity delay controls.
- Selective previous-saver restoration without replacing wallpaper or later user choices, including reset handling.
- Private local scene archive with explicit lock-screen privacy consent; app-side capture preparation and shared Metal rendering in the system host.
- Native-module, live wallpaper-store, private archive and real desktop rendering tests.

### Changed

- Automatic screen saver activation is owned by macOS, not an app overlay timer. Start Now is renamed Preview Now.
- Universal app packaging embeds and signs the native module and includes dependency notices. Old app-only inactivity preferences require explicit system opt-in.

## [0.1.28]

### Added

- Native management dashboard with a collapsible sidebar, Overview status cards, quick actions and eight working destinations.
- Read-only on-screen window inventory from Core Graphics and diagnostics for the actual Metal renderer, event tap and permissions.
- General enable and drag controls in Settings, plus confirmation before resetting effect settings.
- Isolated preference, app-rule, system-metadata and SwiftUI hosting tests, included in the existing `swift test` CI step.

### Changed

- Setup opens at launch and when the app is reopened, remembers its window size and adapts to macOS light/dark appearance.
- Existing settings are organized into Effects, Physics, Screen Saver, App Rules and Settings; changes still apply immediately.
- Screen Saver's Start Now is disabled until Screen Recording is granted. Physics sliders do not re-enumerate desktop windows.

## [0.1.27]

### Changed

- The screen saver logs why it does not start (missing Screen Recording permission, start already in progress, no screen).

## [0.1.26]

### Added

- **Screen saver: the edges that stay burn.** The edges of the window pieces around a hole are charred, glow with a
  flickering ember light, give off small flames, smoke and embers, and are eaten away very slowly, so their sharp
  cut becomes ragged and rounded. Window borders do not burn. `ChaosWorld` finds the neighbour of every edge
  (`edgeNeighbor`, `edgeBurnAge`).
- Debug aid: `KINETIQ_CHAOS_OFFSCREEN=1` runs the simulation and writes the pictures of `KINETIQ_CHAOS_DUMP_TIMES`
  without covering the screen.

## [0.1.25]

### Added

- **Screen saver: burnt edges, cracks, sparks and dust.** The broken edges of pieces are charred and glow until they
  cool. Blasts and cracking windows draw jagged cracks (with branches and arcs) on the pieces around them that hold.
  Explosions throw cooling sparks and fine dust, and hard landings raise dust.
- **Dock icon explosions** are far stronger than the others (about three times the radius, a flash, a shake, a ring of
  dust). **A nuclear blast** with a mushroom cloud happens once per session, now and then. It is contained: limited
  reach and number of pieces, a soft flash and little shake.

## [0.1.24]

### Changed

- **Screen saver: windows break like glass.** The pieces are no longer rectangles or triangles: a window is divided into
  irregular convex Voronoi chunks, and a chunk hit by a blast cracks again along rings of seeds around the impact
  (small radial fragments near the hit, bigger ones away from it). Fallen pieces have anti-aliased edges and a faint
  pale rim. `ChaosPolygon` and `ChaosGeometry` in `KinetiqCore`.

## [0.1.23]

### Added

- **Screen saver** (Setup › Screen Saver): after a number of minutes without input (or with *Start Now*) the desktop
  falls apart in slow motion. Letters come loose and drop, buttons blink and explode, blasts break windows into
  irregular triangular pieces, cracks run through windows. Everything piles up at the bottom of the screen and
  fades after a configurable time. Settings: start after, event interval, vanish time, speed, intensity.
- `KinetiqCore`: `UIObjectExtractor` (letters, buttons and icons cut out of window pictures), `ChaosTiling`,
  `ChaosScene` and `ChaosWorld` (circle physics at 120 Hz with stacking, sleeping and fading), all unit-tested.

## [0.1.22]

### Added

- **Six more Minimize styles**: Whirlpool, Tornado, Rubber Band, Pancake, Accordion and Hop, next to Dock Morph, Genie
  and Jelly Suck.

### Changed

- **Open only offers the jelly entrances.** The shader effects (the close effects in reverse) are gone from the Open
  picker, together with the code that hid and revealed the window; a shader saved by an earlier version becomes Wobble
  Pop. The glow on focus now flashes once an entrance has finished.

## [0.1.21]

### Added

- **Jelly entrances for opening windows**, in the **Open** picker: Wobble Pop, Ripple, Stone in Water, Shockwave,
  Jelly Squash and Quake. The window is never hidden: it is captured when its pop-in animation ends and the jelly model
  plays the entrance, so there is no flash and no gap. *Random* picks among these and the shaders.
- **Dock morphs for minimizing**, in the **Minimize** picker: Dock Morph, Genie and Jelly Suck. The window is
  deformed towards its Dock icon (found through Accessibility) and fades out as it arrives, over the frozen screen
  picture that hides the system animation. A minimize effect saved by an older version is migrated to Genie.
- The jelly model gained configurable and chained ripples, squeeze and shear impulses, and its settling now also waits
  for nodes thrown by an impulse to stop moving.

### Changed

- **The Open Trick picker is gone** (added in 0.1.20): Wobble Pop is now an Open effect and keeps the window
  visible by itself. Minimize no longer offers the close shaders.

## [0.1.20]

### Added

- **Open tricks** (new **Open Trick** picker in Setup) to deal with apps showing a new window before Kinetiq can hide it:
  - *Hide Immediately* (default): as before.
  - *Skip the Start of the Effect*: the Open effect starts a quarter of the way in, so the empty moment before the
    window appears is shorter.
  - *Keep Visible (Wobble Pop)*: the window is never hidden. Once its pop-in animation is over it is captured as it
    is and the overlay takes over with a jelly pop (the unmaximize kick), so there is no flash and no gap. This
    replaces the Open effect and works even when it is Off.

## [0.1.19]

### Fixed

- **Flash at the end of the open effect.** The real window used to come back at 90 % of the effect, while the effect
  had not finished revealing it (the whole window popped in early), and its shadow was drawn twice until the overlay
  went away. The overlay now keeps drawing the finished window until the real one is back on screen (the shadow
  is handed over at that moment), and only then goes away.

## [0.1.18]

### Changed

- **No focus glow while a window opens.** With an Open effect, the glow around the new window is held back (and
  cancelled if it had already started) and flashes once the effect has finished.

## [0.1.17]

### Fixed

- **Open effects used the wrong size and position.** A new window pops in with an animation, so its frame was still
  changing when the app announced it; the capture was cropped and the window came back at a stale position. Kinetiq
  now waits for the size to hold still and puts the window back at its final position (the animation keeps its
  center). Moves of the new window no longer wait behind the app's other Accessibility calls.
- **Glide and bounce went the wrong way and ended in the wrong place.** The mesh was no longer tied to the window's
  position once released, so it could drift away from where the real window was put back, and a window that already
  stuck out of the screen was thrown back at the first frame. The mesh is now pulled to its rest position while it
  glides, and a window that sticks out keeps its own position as the limit on that side.
- **The minimize animation was visible below the Dock.** The system shrinks the real window towards the Dock, and the
  effect only covered the place where the window was. A frozen picture of the screen without the window (and without
  the menu bar and Dock, which stay live) now covers the animation; the window is put back at its position once it
  has left the screen.

## [0.1.16]

### Changed

- **Open effects hide the new window sooner.** The window is moved off-screen first and checked afterwards (it is put
  back if it turns out to be a full-screen or tiny window), so it is on screen for as short a time as possible before
  the effect starts.
- **Minimize effects turn the genie animation off.** Choosing a Minimize effect sets the Dock's minimize animation to
  *scale* (so ⌘M and the Dock don't play the genie either) and restarts the Dock; choosing **Off** puts your original
  animation back.

## [0.1.15]

### Added

- **Ripple on drop.** A circular wave spreads over the window from the point where it was dropped (about 1.2 s, up to
  7 pt of displacement). Off by default; toggle **Ripple on Drop** in Setup.

## [0.1.14]

### Added

- **Glow on focus.** An accent-colored glow flashes around the window that takes the focus, when its app is activated
  or moves the focus to another of its windows. Off by default; toggle **Glow on Focus** in Setup. It is a
  click-through Core Animation overlay: nothing is captured or moved.

## [0.1.13]

### Added

- **Per-app close effects.** A new **Per-App Close Effects** list in Setup gives an app its own close effect (a shader,
  Random or Off), overriding the global one, even when the global one is Off.

## [0.1.12]

### Added

- **Minimize effects.** Minimizing a window with its yellow button can play one of the close effects instead of the
  system animation (new **Minimize** picker in Setup, off by default). The click is held back; if it ends on the
  button and the window was captured, the window is parked, minimized off-screen and the effect plays where it was,
  then the minimized window is put back at its position. Otherwise the click is replayed untouched. ⌘M and
  minimizing from the Dock keep the system animation.

## [0.1.11]

### Added

- **3D tilt while dragging.** The window leans in perspective into its movement (up to about 22° at high speed) and
  flattens again at rest; it also follows the glide after a flick. Toggle **3D Tilt while Dragging** in Setup.

## [0.1.10]

### Added

- **Glide and bounce on flick.** Releasing a window while moving it fast (900 pt/s or more) makes it keep travelling,
  slow down and bounce off the edges of the usable screen area, squashing like jelly. Toggle **Glide and Bounce on
  Flick** in Setup.

## [0.1.9]

### Added

- **Open effects.** The close shaders also play in reverse when a window appears (new **Open** picker in Setup, off by
  default; **Duration** applies to both). The new window is parked off-screen as soon as its app announces it, captured
  once painted, and moved back under the last frames of the effect. Only standard windows of the frontmost app are
  affected; dialogs, sheets and popovers are not.

## [0.1.8]

### Added

- **Exclusions in Setup.** A list of apps (by bundle identifier) whose windows get no wobble, resize, maximize or close
  effect. Add a running app or choose one from disk, remove with the minus button. Kinetiq's own windows are in the
  list by default, which was previously hard-coded; removing it lets the Setup window wobble too.

## [0.1.7]

### Fixed

- **Permissions requested again after every build.** Ad-hoc builds were bound to the binary hash, so macOS dropped the
  Accessibility and Screen Recording grants on each rebuild. `build-app.sh` now pins the ad-hoc signature to the
  bundle identifier, so a grant survives rebuilds (grant once after updating to this version).

## [0.1.6]

### Fixed

- **Setup window showing only the title bar.** The window collapsed to zero height because its form has no intrinsic
  height; it now opens at a fixed size and is resizable.

## [0.1.5]

### Changed

- **Setup moved to a detached window.** Presets, sliders, effect toggles, close effect, permissions and reset are now
  in a SwiftUI window opened by **Setup…** (⌘,) instead of a menu, which stays with Kinetiq Enabled, Drag from
  Title Bar and the shortcut modifier.

## [0.1.4]

### Changed

- **Project renamed from Wobbly to Kinetiq.** Swift targets (`Kinetiq`, `KinetiqCore`, `KinetiqEffects`),
  `kinetiq-effects-preview`, the app bundle (`Kinetiq.app`) and its identifier (`io.github.invernomut0.Kinetiq`) were
  renamed. macOS treats it as a new app: grant Accessibility and Screen Recording again.

## [0.1.3]

### Added

- **Close effects.** Closing a window plays one of the 30 window-close effects of
  [Burn-My-Windows](https://github.com/Schneegans/Burn-My-Windows), ported from GLSL to Metal shaders and drawn on
  the GPU: Aperture Panels, Apparition, Aura Glow, Broken Glass, Doom, Energize A and B, Fire, Focus, Glide, Glitch,
  Hexagon, Incinerate, Materialize, Matrix, Morph, Mushroom, Paint Brush, Pixelate, Pixel Wheel, Pixel Wipe, Portal,
  RGB Warp, Snap of Disintegration, Team Rocket, T-Rex Attack, TV Effect, TV Glitch, Wisps and Wormhole.
  - New **Close Effect** section in the Setup menu (an effect, Random or Off; Fire by default) and a **Duration** slider.
  - It plays when closing with the close button or with ⌘W / ⌘Q. The window is captured beforehand, when a click lands
    near the close button or ⌘ is pressed, and the effect starts as soon as macOS fades the window out or removes it.
    Minimizing, hiding and switching Spaces are ignored.
  - Aperture Panels, Morph and Wormhole animate only the window: the real desktop shows through.
- `kinetiq-effects-preview`, a command-line tool that renders the effects headlessly, checks every shader, texture
  and seed, and writes a contact sheet per effect (`swift run kinetiq-effects-preview --check`).

## [0.1.2]

### Changed

- **Menu bar menu reorganized.** The top level only keeps Kinetiq Enabled, Drag from Title Bar and the
  shortcut modifier. Presets, sliders, effect toggles, reset and permissions moved to a new **Setup** submenu.

## [0.1.1]

### Fixed

- **Windows vanishing when dragged on some Spaces.** The dragged window was matched to its Accessibility
  element by frame, but an app's window list also includes its windows on other Spaces. Two windows with
  the same frame (maximized or tiled, for example) could be confused, so the wrong one was hidden and the
  one being dragged seemed to disappear. Windows are now matched by their exact window ID.
- **Dragging a window switching to another Space.** Activating the window's app could make macOS jump to a
  Space holding another of its windows. The dragged window is now made the app's main window before the
  app is activated.
- **Shadow jumping on release.** The overlay drew an approximated shadow that was smaller and darker than
  the native one, so it visibly changed when the real window took over. The overlay now draws the
  window's own native shadow, captured along with it, so the handover is seamless.
- **Title bar and shadow changing on release for background windows.** A window grabbed from the
  background was captured with its inactive look. It is now captured again once it becomes active.
- **Shadow flicker when grabbing and releasing a window.** For a frame or two, both the native and the
  overlay shadows were drawn, or neither. The overlay now switches shadows in the same frame the real
  window is hidden or put back.

### Changed

- **Faster start of the effect.** The window no longer moves rigidly for a moment before it starts to
  wobble, especially when switching between windows, apps or Spaces:
  - The list of capturable windows is kept up to date in the background and covers every Space.
  - Screen capture is warmed up at launch, so the first drag is as fast as the rest.
  - A slow app no longer delays dragging windows of other apps.
  - Mouse clicks do less work before being passed on.

## [0.1.0]

- Initial release: Compiz-style wobbly windows for macOS, with maximize and resize effects.

[0.1.1]: https://github.com/jsgrrchg/Wobbly/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/jsgrrchg/Wobbly/releases/tag/v0.1.0
