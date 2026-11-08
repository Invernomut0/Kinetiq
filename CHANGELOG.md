# Changelog

All notable changes to Kinetiq are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] — Build 36

### Added

- **Built-in effects in the Animation Studio.** Add Layer now offers all 30 original close shaders (Incinerate, Fire, Broken Glass…), the 6 spring entrances and the 9 Dock morphs next to the 19 Studio effects. A new `LayerCompositor` plays them in document order on one capture, each layer reading the previous one's output, in a stage with room around the window, for both previews and desktop playback. Built-in layers have timing, speed curve and direction; their look stays the original. Liquid is not a layer (it is a desktop-wide simulation) but can be tried from the menu.
- **Play in reverse** for any layer: a close shader becomes an entrance (the shaders' own opening direction), a minimize morph becomes a restore.
- **My Effects.** Studio compositions are saved by name (`CustomEffect`, `customEffects.v1`) and can own Open, Close or Minimize exactly like a preset: one owner per event across presets and custom effects. The Studio toolbar has **My Effects**, **Save** (⌘S) and **Use when…**, plus a status line saying whether and where the effect is used. The Effects library lists My Effects first with a looping preview, **Use when…** buttons, Run, Edit in Studio and Delete; the menu bar's Open, Close and Minimize submenus list them too.
- **Try an Effect** now covers every effect: My Effects, the 30 close shaders, 6 entrances, 9 minimize morphs, Liquid and the 19 Studio effects, each played once on the front window and put back.
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
- New tests: schema-1 upgrade and schema-2 built-in/reversed round trip; My Effects persistence, single ownership with presets, release and invalid input; every one of the 45 built-in layers animating and reversing on the sample window; Ripple feeding Incinerate; overview geometry (home → arranged, highlight on top, carousel and orbit); the five-window overview demo returning every window home; the Try menu covering all 65 effects.
- `scripts/build-app.sh`: universal arm64/x86_64 app and saver, `codesign --verify --deep --strict` OK, Info.plist 0.4.0 / 36. Preview frames of the three layouts and the Ripple → Incinerate composition were inspected.

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
