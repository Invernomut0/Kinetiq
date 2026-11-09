# Kinetiq release history (detailed notes)

Detailed per-release notes and verification evidence previously kept at the top of the README. The [CHANGELOG](../CHANGELOG.md) is the concise record.

## Current: v0.5.1 · build 44 — consented configured country for GA4

**Task 24 Done — Copilot; implementation and verified local acceptance.**
The owner explicitly authorized the macOS configured country for GA4's standard
**Country** dimension. GA4 requires fresh **consent revision 3**; a prior revision-2
grant stays off until a new disclosed choice. Native Firebase remains at **revision 2**
with unchanged signing gates. **Don't Share** remains default. Existing mode-specific
consent/identity namespaces are preserved, not transferred.

The closed vocabulary in `KinetiqUsageEvent.swift` permits only these custom events:

| Event | Approved meaning / custom properties |
|---|---|
| `feature_used` | Actual visits to Privacy & Analytics, Effects, Animation Studio, Layouts, Performance, Rules or Screen Saver; `feature`. |
| `effect_played` | Actual successful playback starts, not attempts or completion counts; `effect_id`, `trigger`. Manual runs remain distinct from native window triggers and explicit layouts. |
| `effect_selected` | Explicit assignment/selection, not playback; `effect_id`, `trigger`. |
| `studio_action` | Validated layer/keyframe edits, save, import and export; `action`. |
| `screensaver_action` | Actual app-side enable/disable or in-app preview start; `action`. Not macOS saver-host runs. |
| `quality_changed` | Explicit quality choice; `quality`. Not automatic resource-budget adaptation. |

The only custom property keys are `feature`, `effect_id`, `trigger`, `action` and
`quality`. Effect IDs come from the **66 real library entries**, plus `custom` for
all user compositions and `wobbly_classic`; `off`/`random` are selection-only values.
Automatic preview loops are not counted. No user content, application identifiers,
custom names, window metadata, precise location, hardware metadata or free-form
properties enter this custom schema. No automatic startup/Overview events are added.

The single existing AppDelegate owner exposes a weak static emission hook, retaining
the unchanged generic SDK core. At most **four immediate product-event tasks** are
retained, without a disk queue, retry or replay, and the existing GA4 **four-request** network cap remains.
Busy/denied/overflow actions can be dropped: counters are best-effort, not an exact
usage census. Native fallback signing gates are unchanged; no saver SDK is added.

The authorized GA4 contract reads only `Locale.current.region?.identifier`, inside
consented `provider.start` after `configuration.enabled && privacy.analyticsEnabled`.
A country from the closed **249 assigned ISO 3166-1 alpha-2** codes is snapshotted in memory until stop/withdrawal,
then cleared and refreshed on the next consented start. It enters JSON only as
top-level `user_location: {country_id: <ISO 3166-1 alpha-2>}`, never an event parameter
or custom definition. Missing/invalid country omits `user_location`; no language/
time-zone fallback, GPS, IP lookup, external geolocation service or new network
permission. No `ip_override`, fabricated city or `region_id` is sent. Google's fields
are optional: country alone is valid; its region recommendation does not authorize
invention. This is a **configured country, not citizenship or physical location**:
it can override GA4's country and distort maps. City is not supplied or promised;
without the override, MP-only geography can remain `(not set)`. Native geography
remains conditional on actual gated enablement, not enabled by this change. The six
events/five custom keys above are unchanged.

The host privacy manifest conservatively declares non-tracking coarse-country
analytics linked to the pseudonymous client identifier; this does not add physical
location measurement, a location permission or an App Store compliance guarantee.

For usable reports, manually create **Event-scoped** custom definitions for the five
keys above in **GA4 Admin → Custom definitions**, then use Explore with
`event_name=effect_played`, rows `effect_id`, breakdown `trigger` and Event count.
Exclude `trigger=manual` to rank non-manual usage, and separate `layout` from native
window triggers when needed. Selection counts are not play counts. Allow **24–48 h**
after definitions are created and data is sent; no retroactive reporting guarantee.
City/Country are built-in dimensions, not custom definitions. See the
[complete report setup and geography limitations](telemetry.md#practical-ga4-report-setup).
HTTP 2xx is receipt of the request, **not proof of ingestion**.

**v0.5.1/build 44 local acceptance:** **414 Release tests passed = 230 app +
36 Effects + 148 Core**, zero failures/skips, including **89 analytics contracts**
(`/tmp/kinetiq-country-final-release.log`). Universal app/saver, strict signatures,
bundle verification and signed disabled smoke passed (`/tmp/kinetiq-country-build.log`).
LLVM **Lines**: country validator **85.71%**, provider **77.30%**, owner **97.24%**,
privacy UI **89.69%**, taxonomy **100%**, native adapter **20%**. The actual Mac region
getter and live delivery remain unexecuted; this is not ingestion or exhaustive coverage.
No normal app restart, real consent change or live event was automated. See
[task 24 evidence](telemetry.md#local-acceptance--task-24). The published
v0.5.1 release and post-edit README optics verification are tracked as task 25.

**Historical v0.5.0/build 43 local acceptance (2026-11-09): 407 Release tests passed** — 223 app +
36 Effects + 148 Core, zero failures/skips (`/tmp/kinetiq-usage-final-acceptance.log`).
This includes **82 analytics contracts** and same-turn save/assignment and layer/import
regressions. Earlier runs encountered native capture/window-origin failures; all 15
runtime tests passed in isolation and the final full suite passed unchanged assertions.
LLVM **Lines**: event taxonomy **100%**, owner **97.56%**, GA4 provider **77.09%**,
native adapter **20.00%**, privacy UI **89.69%**; not live-delivery or exhaustive coverage.
Universal **x86_64 + arm64** app/saver **0.5.0/build 43**, strict signatures, bundle
verification and signed disabled smoke passed (`/tmp/kinetiq-usage-build.log`).
No normal user-app restart, real consent change or live probe was automated.
See [detailed evidence and remaining owner gates](telemetry.md#local-acceptance--task-23).
Those checks do not certify build 44. PR #6 is merged; its hosted job never started
because of account billing/spending limits. G2/F2 remain **Review — Lorenzo** for
live ingestion/privacy/distribution and account review/rerun, not a hosted CI pass.
All release verification below belongs to its stated historical version.

**v0.3.1 · build 36** fixes the management sidebar and Animation Studio controls disappearing outside the window. Navigation columns now use their actual viewport; after **Add Layer**, the inspector, transport and timeline stay in the editor. The startup guide remains inline for an empty document and is available from **?** without covering the populated editor. Event-based discovery and all 65 effects are unchanged.

**v0.3.2 · build 37** replaces Liquid's final fade with slow physical drainage off the bottom edges. The pooled material stays opaque while the outlets open gradually from the lower corners towards the center. The preview now includes the complete ending.

**v0.3.3 · build 38** adds **Window Destruction**, a Close-only built-in with sample/real-window previews, global selection and per-app close rules. The library now contains **66 entries: 19 Studio + 47 originals**. It reuses the screen saver's extraction, fragmentation and physics engines for a transparent one-shot effect, without activating or changing the screen saver. Its historical release-suite/package verification is retained below; it does not certify the subsequent telemetry worktree. See [verification status](#building).

**v0.3.4 · build 39** adds owner-authorized direct **GA4 Web Measurement Protocol** analytics, with a fresh default-off consent choice and separate local identity, without Keychain access. A configured GA4 resource takes precedence over the still-linked native Firebase SDK, which remains dormant in GA4 mode. The actual Privacy & Analytics visit now waits for readiness, enablement and consent; Settings shows sanitized submission/HTTP status, not a promise of report ingestion. Only real consented foreground time accompanies approved actions; startup and Overview send no events. Window effects are unchanged. **G1 Done** for implementation and verified offline/local acceptance only; **G2 Review**, owner Lorenzo, for live ingestion and distribution/privacy acceptance.

**v0.4.0 · build 40** makes the Animation Studio a real effect maker and Layouts a real feature. Studio layers can now be any of the **45 built-in effects** (close shaders like Incinerate, spring entrances, Dock morphs) next to the 19 Studio effects, played forwards or in reverse; a composition saved to **My Effects** can be used when a window opens, closes or is minimized, from the Studio, the Effects library or the menu bar. **Try an Effect** covers every effect, Liquid and Window Destruction included. **Layouts** (Exposé 3D, Orbit, Cube) now animate windows in and out, react to hover, clicks, arrows and scrolling, and open anywhere with **⌃⌥↑**. See the [Studio guide](animation-studio.md) and the [original-effects guide](original-effects.md).

**v0.4.1 · build 41** keeps expensive effects available at Low quality and throughout
Auto adaptation, reducing fidelity instead of disabling playback. Critical thermal
pressure still blocks expensive effects; allocation/capture limits are unchanged.
Kinetiq's own Settings/management windows are now permanently excluded from effects,
including when loading older exclusion lists that removed Kinetiq.

Local verification: **376 Release tests passed** (192 app + 36 Effects + 148 Core),
zero failures/skips, including real captured-README rendering at Low and critical
thermal refusals. Universal app/saver signatures, bundle checks and disabled smoke
passed. Logs: `/tmp/kinetiq-budget-release.log`, `/tmp/kinetiq-budget-build.log`.
No live analytics or user-window mutations were automated.

**v0.4.2 · build 42** fixes a separate cause of the same apparent block: Layouts
under-counted native capture memory by omitting the shadow room, then aborted the
entire overview if an additional window exceeded the total. Admission now includes
the shadow buffer and skips only additional windows that do not fit; the **32 MP
total, eight-window maximum and native capture resolution are unchanged**. Layouts
reports the number of admitted windows. Memory/allocation/busy errors are distinct
from an actual critical-thermal refusal. Stopping, retrying or changing pages clears
previous-operation errors; a recovered thermal gate clears its own refusal, without
hiding unrelated failures. No user assignments or mandatory Kinetiq exclusion change.

Local verification: **380 Release tests passed** (196 app + 36 Effects + 148 Core),
zero failures/skips. Real owned README windows verify Low/Auto overview admission,
shadow-buffer accounting, thermal recovery and desktop Ripple → Incinerate playback
with exact-origin restoration. The four-window case failed before the fix. Logs:
`/tmp/kinetiq-layout-final-release.log`, `/tmp/kinetiq-layout-red.log`.
Universal **x86_64 + arm64** app/saver, strict signatures, bundle verification and
signed disabled smoke passed (`/tmp/kinetiq-layout-build.log`). LLVM **Lines**:
runtime **75.74%**, capture **75.00%**, compositor **96.47%**, Studio UI **59.15%**,
library UI **67.31%** (`/tmp/kinetiq-layout-final-coverage.txt`); not exhaustive
integration or Metal shader branch coverage. No normal app restart or live analytics
was automated. This is historical **0.4.2/build 42** evidence, not verification of
the current source version or a request to restart the user's app.
