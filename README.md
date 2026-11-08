# Kinetiq

Compiz-style wobbly windows for macOS. Drag a window and it wobbles like jelly, then settles where you drop it. Optional effects also play when a window is maximized or resized. Closing offers 30 GPU shaders plus a desktop-space **Liquid** simulation, also available for minimizing.

Kinetiq is a native menu bar app, forked from [Wobbly](https://github.com/jsgrrchg/Wobbly) by José Gurruchaga. Window effects use public macOS APIs. Optional system screen saver selection uses PaperSaverKit 0.4.3 and macOS's undocumented wallpaper preference store; Apple provides no public API for selecting the default screen saver.

https://github.com/user-attachments/assets/40bc5530-d253-4d47-bc57-3eccdac83d70

**v0.4.0 · build 36** makes the Animation Studio a real effect maker and Layouts a real feature. Studio layers can now be any of the **45 built-in effects** (close shaders like Incinerate, spring entrances, Dock morphs) next to the 19 Studio effects, played forwards or in reverse; a composition saved to **My Effects** can be used when a window opens, closes or is minimized, from the Studio, the Effects library or the menu bar. **Try an Effect** covers every effect. **Layouts** (Exposé 3D, Orbit, Cube) now animate windows in and out, react to hover, clicks, arrows and scrolling, and open anywhere with **⌃⌥↑**. See the [Studio guide](docs/animation-studio.md) and the [original-effects guide](docs/original-effects.md).

## Installing

Requires macOS 14 or later, on Apple Silicon or Intel.

Download the DMG from Releases and drag Kinetiq to `/Applications`. The app is not notarized, so the first time you open it macOS will block it: go to **System Settings → Privacy & Security** and click **Open Anyway**.

## Usage

- **Drag from the title bar** as usual, or
- **Hold the shortcut** (⌃⌘ by default) and drag a window from anywhere.

The menu bar is organized by window event. **Drag**, **Open**, **Close** and **Minimize** each show their current choice in the title (for example “Close: Fire”) and open a submenu with **Off**, **Random**, every compatible built-in effect and the compatible **Studio presets**; choosing an item applies it immediately and the checkmark moves. The Drag submenu also holds the wobble preset (Subtle…Extreme) and a **Wobbly (classic)** entry that releases any Studio drag preset. **Try an Effect on the Front Window** plays any effect — My Effects, every built-in close shader, entrance and Dock morph, Liquid, and the Studio effects — once on the frontmost window and puts it back; **Arrange Windows** (⌃⌥↑ anywhere) opens the chosen layout; **Stop & Restore Windows** cancels any playback. **Render Quality**, **Effects Library…** (⌘E), **Animation Studio…**, **Settings…** (⌘,) and **Quit** complete the menu. Title-bar drag and the shortcut modifier live on the Settings page. The management window opens on launch and can be reopened from the menu or by opening the app again; closing it leaves the engine running but stops active library/Studio playback.

### Management dashboard

There are **11 pages**, grouped into everyday pages (Overview, Effects, Animation Studio, Physics, Layouts, Rules, Screen Saver) and a **System** group (Performance, Windows, Diagnostics, Settings).

The dashboard supports a minimum content area of **960 × 700 points**, excluding native window chrome.

| Page | Controls and information |
|---|---|
| **Overview** | Engine and permission status, enable/pause switch, a **What plays right now** card listing the current Drag/Open/Close/Minimize choice with a Change button, permission requests and refresh. |
| **Effects** | **My Effects** (your Studio compositions) first, then sidebar sections **When you drag a window**, **When a window opens**, **When a window closes**, **When you minimize** and **Overview & layouts**, each listing every compatible effect with a one-line description and a checkmark on the active one; the section header shows the current choice and offers Off/Random. Search covers all 65 effects. The detail page shows a looping preview (sample window or a real one), a **Use when…** button per supported event, a collapsible **Customize** area (Studio parameters with live preview and Save, or the shared duration for built-ins) and **More** (Run on Window, Open in Animation Studio, import/export, reset). |
| **Animation Studio** | Build your own effect: layers from the 19 Studio effects and the 45 built-in ones, timing, reverse, parameters and keyframes, a looping preview, **Save** to My Effects and **Use when…** to play it on open, close or minimize. Inspector tabs **Edit**, **Keyframes** and **Advanced**; undo/redo; document JSON (schema 2). |
| **Physics** | Preset, friction, spring, speedup, mass, mesh density, maximize/resize effects, shadow, glide, tilt, focus glow and drop ripple. These springs drive the classic wobble, the entrances and the Wobbly preview. |
| **Layouts** | Exposé 3D, Orbit and Cube with a looping five-window demo, live sliders and Start. Windows fly in and out, lift on hover, come forward on click; arrows, Tab, Return, scroll and Escape work. **⌃⌥↑** anywhere opens the chosen layout. No native Space switching. |
| **Rules** | Per-app close-effect overrides and exclusions. Add running apps or choose installed apps from disk. |
| **Screen Saver** | Install/select Kinetiq as the macOS default, system inactivity delay, actual selection status, event interval, fragment lifetime, speed, intensity and Preview Now (requires Screen Recording). |
| **Performance** | Five quality choices, completed Metal GPU timings and actual resource budgets; no inferred GPU utilization. |
| **Windows** | Read-only snapshot of normal-level on-screen windows: owning app, title when available, and dimensions. This page never moves or captures a window. |
| **Diagnostics** | Actual Metal renderer and event-tap state, permission grants, physics preset, mesh, rule counts, OS and app version. |
| **Settings** | Enable state, title-bar drag, shortcut modifier, permissions and confirmed reset of effect settings. Reset preserves the enable state and drag controls. |

The **Exclusions** list under Rules holds apps whose windows get no effects. Kinetiq's own management window is excluded by default; remove that exclusion to let it wobble. Catalog targets always exclude Kinetiq itself. Window titles may be unavailable without Screen Recording. Permission checks refresh when the app becomes active or when you press Refresh; macOS may require restarting the app after a grant. The existing launch-time permission prompts are unchanged. Navigation does not start or stop the engine.

### Effects library: 65 effects, organized by what you do

Both the native menu and the Effects library use `LibraryEffect.all`: **19 Studio effects + 30 original close shaders + 6 original entrances + 9 original minimize morphs + Liquid = 65 entries**. Liquid counts once, although it supports Close and Minimize. Each entry carries a plain-language description (`blurb`), the events it can react to and a kind: **Studio preset** (editable parameters, timeline-capable) or **Built-in** (original engine with compiled defaults). The six legacy categories remain as metadata and group the **Try an Effect** menu and the Studio's Add Layer menu.

| Event | Effects |
|---|---|
| When you drag a window | Wobbly, Float, Ripple, Magnet, Gravity (Studio). The classic spring wobble is always available. |
| When a window opens | Wobble Pop, Ripple, Stone in Water, Shockwave, Jelly Squash, Quake (built-in) · Genie, Morph, Fold, Flip, Float, Dissolve, Portal, Ripple, Liquid Morph (Studio) |
| When a window closes | 30 built-in shaders and Liquid · Fold, Flip, Shatter, Explode, Dissolve, Burn, Portal, Liquid Morph (Studio) |
| When you minimize | Dock Morph, Genie, Jelly Suck, Whirlpool, Tornado, Rubber Band, Pancake, Accordion, Hop and Liquid (built-in) · Genie, Morph (Studio) |
| Overview & layouts | DOF, Cube, Orbit, Exposé 3D (Studio, started explicitly) |

The Studio catalog's raw IDs are stable JSON identifiers, not display names:

| Effect | Raw ID | Events |
|---|---|---|
| Wobbly | `wobbly` | Drag |
| Float | `float` | Drag, Open |
| Genie | `genie` | Minimize, Open |
| Morph | `morph` | Open, Minimize |
| Ripple | `ripple` | Drag, Open |
| Liquid Morph | `liquid-morph` | Open, Close |
| Shatter | `shatter` | Close |
| Explode | `explode` | Close |
| Dissolve | `dissolve` | Close, Open |
| Burn | `burn` | Close |
| Fold | `fold` | Close, Open |
| Flip | `flip` | Open, Close |
| Portal | `portal` | Open, Close |
| DOF | `depth-of-field` | Overview |
| Magnet | `magnet` | Drag |
| Gravity | `gravity` | Drag |
| Cube | `workspace-cube` | Overview |
| Orbit | `orbit` | Overview |
| Exposé 3D | `expose-3d` | Overview |

**Previews.** Every effect previews immediately on a drawn **sample window** that is packaged like a real ScreenCaptureKit capture (window plus shadow); the source menu under the preview switches to any eligible real window, which is only captured, never moved. Previews loop automatically, pause when you scrub, and self-pace so slow simulations drop frames instead of queueing. The preview of **Wobbly** replays the actual `KinetiqModel` spring mesh under a scripted title-bar drag and release, using the preset's stiffness, friction and speed; Studio timeline compositions still use the shader membrane. Catalog previews render with their own `CatalogEffectRenderer` into a stage with room below the window, so Genie's funnel and falling fragments are not cropped. Original previews use `CloseEffectRenderer`, `KinetiqModel` entrances, `DockMorphDeformer` or `LiquidWorld`; minimize uses a local destination, not the actual Dock, and Liquid a local floor. Preview targets are capped at **8,000,000 pixels / 8192 per dimension**, source captures at **32,000,000 pixels / 16384 per dimension**, with at most **two in-flight requests**. When the expensive-effects gate is closed, GPU-heavy previews refuse playback rather than substitute an animation.

**Using an effect.** Select it in the section for the event you care about and press **Use when a window closes** (or opens, or when you minimize, or when you drag). Studio presets are saved with that trigger as their owner; built-ins write their existing `Settings` choice and release only that event's Studio owner, preserving its parameters and tracks. Each event has at most one Studio owner; assigning a new one makes the previous owner's preset Manual without discarding its tracks. A Studio Close owner takes precedence over per-app close rules until released; per-app rules then override the global built-in choice again. **Off** and **Random** sit in each section header and in the menu bar. Nothing is assigned by merely selecting or previewing an effect.

**Customizing.** Studio presets expose their bounded parameters, duration and playback curve under **Customize parameters**; edits show in the preview immediately and persist with **Save** (using the effect also saves pending edits). Default, Subtle and Dramatic variants are one click away. Built-in close and minimize effects share the **0.25×–3× duration multiplier**; entrances follow the Physics springs. **More** offers **Run on Window** (restoring, never closes or minimizes), **Open in Animation Studio** (adds the preset as a layer), JSON import/export, parameter copy/paste and a per-effect reset.

**Animation Studio** adds a timeline, enabled layers, start offsets, parameter tracks and editable key times/values with outgoing `linear`, `easeIn`, `easeOut`, `easeInOut` or `spring` curves. Limits: 32 layers/document, 64 tracks/preset, 128 keys/track; normalized key time 0–1, preset duration 0.1–12 seconds and document duration up to 60 seconds. Explicit Undo/Redo buttons retain 100 edit snapshots. See the [guide and API reference](docs/animation-studio.md).

These are real runtime adapters, not synthetic demo windows on the desktop. Manual Run restores the window rather than closing/minimizing it; actual Close and yellow-button Minimize triggers retain their native lifecycle (⌘M remains native). Magnet and Gravity use real AX movement; drag assignments are snapshotted for the gesture. DOF processes the single captured target, not a global desktop depth buffer. Cube is a cube-like current-Space projection, not a native Spaces cube. Cube, Orbit and Exposé 3D use frozen captures of up to eight eligible windows, within a total 32-megapixel capture budget; Escape dismisses, and clicking a projected window activates it. No private Spaces APIs are used.

Desktop compositions cannot mix a Physics adapter or interactive overview with other enabled layers: the runtime reports an error. Permission, capture, Metal and budget failures preserve/restore native windows; expensive modes are refused rather than replaced with a misleading cheap animation.

### Render quality and real GPU timings

Choose **Auto**, **Low**, **Balanced**, **High** or **Ultra** in the menu or Performance page. Only the choice is persisted. These are resource ceilings, not promised frame rates:

| Quality | Intermediate scale | Particle cap | Blur sampling rings | Mesh cap/axis | Secondary rate ceiling | Expensive effects |
|---|---:|---:|---:|---:|---:|---|
| Low | 0.50× | 400 | 0 | 16 | 30 Hz | Refused |
| Balanced | 0.75× | 1000 | 1 | 32 | 60 Hz | Allowed |
| High / Auto start | 1.00× | 1500 | 2 | 48 | 90 Hz | Allowed |
| Ultra | 1.00× | 1500 | 3 | 64 | 120 Hz | Allowed |

Auto starts at High and reduces one resource at a time across **13 steps**: texture scale 0.75→0.5; particles 1000→700→400; blur rings 1→0; mesh 32→24→16; secondary rate 60→30; then expensive effects off. Recovery reverses the ladder, at most back to High; Ultra is manual opt-in. Smoothed successful GPU command-buffer durations above 12 ms for at least 0.5 s/8 samples reduce quality (3 s cooldown); below 6 ms for 5 s/30 samples recover it (8 s cooldown). Idle gaps break evidence streaks. These are actual completed GPU timings, **not GPU utilization or inferred FPS**; the last sample remains visible while idle.

Thermal/power safety caps also apply to manual choices: fair thermal pressure or Low Power Mode caps at Balanced, serious/critical at Low, with a 15 Hz secondary ceiling at critical. Budget fields, not the summary quality label, are authoritative. Original captures and desktop output remain native resolution. Studio preview/composition intermediates follow `textureScale`, with at most 8,000,000 pixels and 8192 pixels per dimension per target texture, two ping-pong targets and at most two in-flight compositions. Liquid's separate cropped geometry field is capped at 1280 pixels on its longest edge before quality scaling. Its original particle cap remains 1500 per source/display (Balanced 1000, Low budget 400); Low refuses new expensive Liquid playback. The UI label “Blur passes” means concentric eight-tap shader sampling rings for catalog DOF, **not multiple full-screen render passes**.

### Glide and bounce

Let go of a window while moving it fast and it keeps travelling, slows down and bounces off the edges of the usable screen area, squashing like jelly. Grab it again at any time to stop it. Turn it off with **Glide and Bounce on Flick** in **Setup → Physics**.

### 3D tilt

While you drag, the window leans in perspective into its movement and flattens again when you stop. Turn it off with **3D Tilt while Dragging** in **Setup → Physics**.

### Glow on focus

Optional (**Glow on Focus** in **Setup → Physics**, off by default): an accent-colored glow flashes around the window that takes the focus. A window that opens with an Open effect gets its glow after the effect has finished.

### Ripple on drop

Optional (**Ripple on Drop** in **Setup → Physics**, off by default): a circular wave spreads over the window from the point where you dropped it. Existing maximize, resize, shadow, spring/mesh, glide, tilt, focus and ripple controls remain on Physics; the discovery correction does not move or replace them.

### Close effects

When a window closes, it is replaced by an animation drawn on the GPU. Pick one under **Effects › When a window closes** (or in the menu bar's **Close** submenu): **Liquid**, one of the 30 shaders below, **Random** (a different shader every time) or **Off**. The existing **Duration** multiplier is shared by original close and minimize effects: **0.25×–3×, default 1×**. Shader-specific uniforms retain their compiled defaults; they are not new per-effect JSON controls. Fire remains the default. Original entrances continue to use Physics settings, not this duration multiplier.

**Effects › When a window opens** (off by default), or an entrance's **Use when a window opens** button, plays a jelly entrance when a window opens: Wobble Pop, Ripple, Stone in Water, Shockwave, Jelly Squash or Quake (or Random). The window stays visible: once its own pop-in animation is over it is captured as it is and the jelly model shakes it, so there is no flash and no gap. *Stone in Water* drops a stone at a random point and sends rings across the window, *Ripple* spreads a wave from the center, *Shockwave* combines a pop with a fast wave, *Jelly Squash* squeezes it vertically and lets it bounce back, *Quake* shakes it sideways. Dialogs, sheets and popovers are not affected.

Pick a Dock morph or Liquid under **Effects › When you minimize** (off by default). **Random** continues to choose among the nine morphs. The click is held briefly for capture; a frozen desktop without the source window hides the native animation, then disappears as soon as the real window is minimized and its original position restored. Failed capture or setup replays the original click. ⌘M and minimizing from the Dock use the system animation. Choosing a Minimize effect sets the Dock's animation to *scale* (restarting the Dock); choosing **Off** restores the original animation.

The **Per-App Close Effects** list in **Setup › Rules** gives an app its own close effect (Liquid, a shader, Random or Off) in place of the global original choice. Selecting an original does not clear these rules or exclusions; an explicit Studio Close owner takes precedence until released.

Aperture Panels, Apparition, Aura Glow, Broken Glass, Doom, Energize A, Energize B, Fire, Focus, Glide, Glitch, Hexagon, Incinerate, Materialize, Matrix, Morph, Mushroom, Paint Brush, Pixelate, Pixel Wheel, Pixel Wipe, Portal, RGB Warp, Snap of Disintegration, Team Rocket, T-Rex Attack, TV Effect, TV Glitch, Wisps and Wormhole.

The effect plays when you close a window with:

- the close button (the red one), or
- **⌘W** (and **⌘Q**, for the focused window).

Minimizing, hiding, switching Spaces, closing a tab with ⌘W, or a close that the app refuses (an unsaved-changes sheet) don't play it. Effects that start at the pointer (Incinerate, Pixel Wipe) use the position of the mouse when the window closes. The effects that need the desktop behind the window (Aperture Panels, Morph, Wormhole) only animate the window: the real desktop shows through instead of being warped.

### Liquid close and minimize (v0.1.31)

Select **Liquid** under **When a window closes** or **When you minimize**, then press **Use when a window closes** and/or **Use when you minimize**. This original particle-fluid simulation is separate from the catalog's **Liquid Morph** refractive transition; neither replaces the other. During native playback, the captured window liquefies progressively from the **top-right** towards the bottom-left, retaining its actual colors and content. Gravity pulls the connected, glossy surface down. It lands on exposed upper edges of other real windows, spreads sideways and spills off their ends. Geometry refreshes approximately every 150 ms, so moving or removing a window releases supported liquid. Already-overlapping background windows do not teleport liquid onto their tops. The panel preview instead has a local floor and no desktop obstacles.

The liquid collects at the **full display bottom**, not the usable desktop boundary, and stays **behind the Dock** (including a side Dock), before slowly fading. Each display has its own floor; source windows spanning displays are split into per-display fluid domains. Duration scales melting, falling, the roughly three-second linger and three-second fade. This is a bounded visual particle-fluid approximation with viscosity, cohesion and density constraints, not a full hydrodynamics solver: collisions use visible rectangular window tops, not arbitrary content shapes or physical side walls. No real obstacle window is moved or modified.

At most two source captures are retained, with at most 1500 particles per source/display, fixed 120 Hz physics and bounded catch-up work. Metal blends their density into continuous surfaces, rather than drawing disconnected shards. Overlays never receive clicks. Disable, display changes, Space changes or sleep clear the liquid; a wall-clock deadline also prevents stranded effects. Liquid captures remain in memory only and are not written to the screen saver cache or disk.

**Sharp material and water optics:** the low-resolution geometry field transports float32 texture coordinates, not averaged colors. The final shader samples the original window capture at output resolution, so letters deform with the fluid instead of becoming blurred blobs. Water-index Snell refraction adds a restrained lens effect; Schlick Fresnel and procedural studio lights provide glancing highlights and soft reflections. These are local optical approximations, not ray-traced reflections of other desktop windows; no additional desktop image is captured. Strongly compressed or folded fluid can still distort text naturally.

Shader work is restricted to the fluid's cropped bounds. A compact polynomial replaces the exponential kernel, intact content and fluid share one destination load/store, and geometry fields stay independent of Retina output resolution. Texture dimensions use 32-pixel buckets; up to four recently used fields are cached within 32 MiB (or a single maximum-size field). GPUs without float32 hardware filtering use explicit bilinear reconstruction of the same precise UV field.

### Screen saver

In **Setup › Screen Saver**, turn on **Use as macOS Screen Saver** and confirm the privacy notice. Kinetiq installs its signed native `Kinetiq.saver` in `~/Library/Screen Savers`, selects it for every display and Space, and applies the inactivity delay to macOS. WallpaperAgent restarts briefly. The control reports the actual system selection and any error, not just an app preference. Previous versions' in-app inactivity setting is not silently migrated into a system selection: opt in again.

macOS owns automatic activation, dismissal and authentication; Kinetiq does not change your password or lock policy. **Preview Now** remains an in-app visual preview, not a lock screen. Disabling restores the previously selected screen saver only in slots still using Kinetiq, preserves newer wallpaper/other-saver choices, restores the old inactivity delay if it is still the Kinetiq-applied value, and deletes the saved scene. Reset Effect Settings performs the same restoration first. A different screen saver chosen later in System Settings is never automatically replaced.

**Privacy:** the module runs in Apple's sandboxed screen saver host and does not inherit Kinetiq's Screen Recording grant. Kinetiq prepares a real desktop snapshot on enable and shortly before the system inactivity deadline while the app runs. It is stored locally in `~/Library/Caches/io.github.invernomut0.Kinetiq/SystemSaver/desktop.plist` (directory mode 0700, file mode 0600), never uploaded. The saved windows can contain private content and can appear on the lock screen; enable only if this is acceptable. When the app is closed, the module keeps using the last saved scene; if the cache is purged, it asks you to open Kinetiq again. Open Kinetiq to refresh the scene after changing displays. The previous selection is backed up in `~/Library/Application Support/Kinetiq/PreviousScreenSaver.plist` until disabled. Deleting the app does not uninstall the system module: disable it first, or select another saver in macOS and remove `~/Library/Screen Savers/Kinetiq.saver` and its cache manually.

The desktop falls apart slowly: every so often (*Event every*, 100–5000 ms) a blast breaks the windows like glass and throws letters and icons around, letters come loose and drop, a button or icon blinks red and explodes (neighbouring buttons chain-react), or a crack runs through a window. Everything that comes loose falls, bounces, piles up and fades after *Pieces vanish after* seconds. *Speed* slows the simulation down (0.55 by default), and *Intensity* sets blast size. When most of the desktop is gone it fades out and rebuilds. No real window is changed.

Blasts leave marks and debris. The broken edges of the pieces are charred (dark and ragged) and glow like embers until they cool. The edges that stay behind, those of the pieces around a hole, are left bare when their neighbour breaks away: they char, glow with a flickering ember light, give off small flames, a little smoke and now and then an ember, and are eaten away very slowly, so a sharp cut turns into a ragged, rounded, burnt edge (about 0.2 pixels per second, up to 9). The border of a window does not burn. Jagged cracks with side branches and a few arcs spread from every blast across the pieces of window around it that stay in place, and a piece that comes loose later takes its cracks along. Explosions throw sparks that cool from white-yellow to red and fall back as embers, flames, smoke, and fine dust that hangs in the air; pieces landing hard raise dust. An explosion of an icon of the Dock is much stronger than the others: a blast radius about three times larger, a flash of light, a shaking screen, a ring of dust and many more sparks. Once per session, after at least 25 seconds and then at random (at the latest after two minutes), a nuclear blast goes off at ground level: a short flash, a shock wave that reaches a limited part of the screen and breaks and throws the pieces in its way (up to a fixed number, fewer and fewer the farther away), a fireball and a mushroom cloud. It is deliberately contained, so the screen stays smooth.

The objects are found in the pictures of the windows without any extra permission: the background of every tile is its most common colour, what differs is foreground, and connected regions are classified by size and shape into letters, window buttons, buttons and icons. What remains is cut like glass. A window is first divided into irregular convex chunks (the Voronoi cells of a jittered grid: four to seven sides of different lengths and angles, none alike, the same window always along the same lines). When a blast hits a chunk it breaks again: crack seeds are placed on rings around the impact point, close together near it and farther apart away from it, and the fragments are the Voronoi cells of those seeds clipped to the chunk, so they are small, sharp and radial near the hit and larger away from it. The pieces keep exactly the part of the picture they covered, with a faint pale rim along their edges. Pieces hidden behind another window are not touched until the window in front has broken away. It needs the Screen Recording permission.

## Permissions

| Permission | Why |
|---|---|
| **Accessibility** | Watch mouse events and move windows. |
| **Screen Recording** | Capture the dragged or closing window so it can be drawn deformed or animated. Without it, windows move rigidly and close without an effect. |

## How it works

When a window is grabbed it is captured with ScreenCaptureKit, drawn on a deformed mesh by Metal in a transparent overlay, and the real window is moved off-screen through the Accessibility API. Once the animation settles, the real window is put back at its final position.

An app closes its windows by itself, so Kinetiq can't intercept a close: it captures the window beforehand and watches it. A click near the top-left corner of a window captures it, and so does holding ⌘ (the capture is refreshed while ⌘ is held; keystrokes are never read). When macOS starts to fade the window out, or removes it, the capture is drawn by the effect's Metal shader in a transparent overlay, over the desktop that the closed window left. The shaders are in `Sources/KinetiqEffects/Resources/Shaders`: each effect is one Metal file, ported from the GLSL of Burn-My-Windows.

## Building

Requires macOS 14 or later and Xcode 26 or later (Swift 6 for PaperSaverKit). SwiftPM resolves the pinned MIT-licensed PaperSaver 0.4.3 dependency; its ArgumentParser dependency is for PaperSaver's CLI, not bundled in Kinetiq.

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

`build-app.sh` signs with your "Apple Development" identity if you have one, or with `SIGN_IDENTITY` if set. Otherwise it uses ad-hoc signing with stable bundle-identifier requirements to preserve permission grants across rebuilds. Both the app and embedded screen saver are signed.

**Current v0.2.1 / build 34 verification:** the final release suite passed **277 tests: 144 Core + 36 Effects + 97 app**, with **0 failures and 0 skips**. The app suite includes **11 Management + 7 OriginalEffectLibrary + 8 OriginalEffectPreview + 10 StudioUI + 61 other existing tests**. All 30 original shaders, six entrances, nine minimize morphs and Liquid passed genuine real-capture tests, including the README Liquid regression. Management tests verify all 65 navigation requests are routed and consumed, including repeated navigation. Local evidence: `/tmp/kinetiq-v021-suite.log`.

The completed build (`/tmp/kinetiq-v021-build.log`) produced **arm64 + x86_64** binaries for both the app and embedded `.saver`, verified directly with `lipo` and strict `codesign` checks. The actual packaged version is **0.2.1 / build 34**; the app was launched and Quick Look/Finder refreshed. Clicking native **Destruction → Dissolution → Fire — Original Close…** opened the exact original Fire detail; Accessibility inspection confirmed the 65-effect library, and `/tmp/kinetiq-v021-fire.png` was visually inspected. This inspection neither activated an effect nor changed user assignments. [TODO R2](TODO.md) is Done.

Current merged release **line coverage** (`/tmp/kinetiq-v021-coverage.txt`): `LibraryEffect.swift` **100%**, `CatalogStore.swift` **100%**, `OriginalEffectPreview.swift` **85.32%**, `OriginalEffectDetailView.swift` **40.80%**. These figures do not measure Metal shader branch coverage.

**Historical v0.2.0 / build 33 verification (not current acceptance):** the final release suite passed **260 tests: 144 Core + 36 Effects + 80 app**, with **0 failures and 0 skips**, including that version's README real-capture Liquid regression and 19 management/Studio tests. Build 33's app and embedded saver were built for arm64/x86_64, passed strict signature verification, and the app was launched and inspected. Local evidence: `/tmp/kinetiq-v02-final-suite.log`; temporary logs are not distributed artifacts.

Historical v0.2.0 merged release coverage reports 98.97% lines for preset/document validation, 98.74% for the quality policy, 100% for catalog storage, 79.33% for the native runtime and 99.26% for the catalog renderer's Swift encoding path. These are not current v0.2.1 coverage figures, do not measure Metal shader branch coverage and do not promise coverage of every native failure. Optional `KINETIQ_UI_TEST_DUMP` under `/tmp` saves only the tests' own real Effects/Studio/Performance window screenshots, requiring Screen Recording.

The `KinetiqSaverSupport` target shares the Metal renderer and private scene archive between the app and `KinetiqScreenSaver`. Packaging embeds the universal `.saver` in `Kinetiq.app/Contents/Resources`; running a bare `swift run Kinetiq` cannot install the module. Native integration tests read the real wallpaper store and write only temporary copies. Desktop capture tests use real windows and skip when Screen Recording or a graphical session is unavailable; they never change the user's default screen saver. Run `swift test --enable-code-coverage` for coverage. Future macOS changes to the undocumented selection store may require a PaperSaver update; failures are surfaced in the Screen Saver page, with a shortcut to System Settings.

Liquid physics lives in `Sources/KinetiqCore/LiquidWorld.swift`; `KinetiqEffects/LiquidEffectRenderer.swift` implements the density/surface Metal passes, and `Kinetiq/LiquidEffectPlayer.swift` owns desktop overlays and live geometry. `swift test -c release --filter Liquid` exercises real display geometry, capture-to-Metal output, native picker selection, close detection and actual AX minimization/restoration of disposable README document windows. Graphical/permission-dependent tests skip only when those capabilities are absent; no user document is closed or moved. To inspect an opt-in contact sheet of the captured test document, set `KINETIQ_LIQUID_TEST_DUMP` to a directory under `/tmp` when running these tests; without it no image is persisted. The tests do not alter Dock preferences.

Native-resolution optical tests compare transported text edges against the actual captured pixels, isolate refraction/reflection without changing coverage, and compare the manual float32 filter to hardware filtering when supported. Set `KINETIQ_LIQUID_BENCHMARK=1` to print GPU timings for 40 warmed frames at three fluid states (simulation and readback excluded). With the temporary dump directory above, `KINETIQ_LIQUID_TEST_DUMP_FRAMES=1` also saves individual native-resolution test-document PNGs. Timings depend on GPU, display and current load; they are diagnostics, not fixed CI performance thresholds.

The graphical Liquid test displays this actual README in a disposable native text window; it requires more than 32 coherent edge samples at 1.5 s, a contrast ratio above 0.65 and material RGB error below 0.18. Text/layout changes can affect this real-capture regression and should be rechecked, not worked around with a fabricated image.

### Source map and API reference

- `KinetiqCore`: catalog descriptors, strict schema-1 presets/documents, keyframe sampling, drag/dynamics policy and quality budgets.
- `KinetiqEffects`: original close shaders, Liquid renderer and `CatalogEffectRenderer.encode`, whose optional evaluated `parameters: [String: Float] = [:]` preserves existing callers. Missing custom values use descriptor defaults; finite values clamp to bounds, nonfinite values use defaults and unknown renderer dictionary keys are ignored. Strict preset JSON, unlike this low-level renderer dictionary, rejects unknown keys.
- `Kinetiq`: `LibraryEffect` combines Studio and original discovery; `OriginalEffectAssignment` reuses Settings and releases the corresponding catalog owner; `OriginalEffectDetailView` / `OriginalEffectPreview` provide original controls and captured previews. `CatalogStore` handles Studio persistence/trigger ownership; `CatalogRuntime` handles Studio capture/AX restoration/composition, alongside the library/Studio and performance UI.
- `KinetiqSaverSupport` / `KinetiqScreenSaver`: shared scene archive/renderer and native saver host integration.
- `Tests`: Core validation/physics, actual Metal asset rendering and real capture/AX/native UI integration. [Studio guide](docs/animation-studio.md) covers editing, schema and adapter contracts.

## Credits

- The wobbly model comes from the Compiz wobbly plugin by David Reveman (Novell), with the spring model by Kristian Høgsberg.
- The physics, presets and resize effect are ported from the GNOME Shell extension [Compiz windows effect](https://github.com/hermes83/compiz-windows-effect) by Mauro Pepe.
- The trick for hiding the real window comes from [AeroSpace](https://github.com/nikitabobko/AeroSpace).
- The close effects, their settings and their textures come from [Burn-My-Windows](https://github.com/Schneegans/Burn-My-Windows) by Simon Schneegans: the GLSL shaders were ported to Metal. The brush, claws, dust, matrix font and shard textures are licensed CC-BY-4.0.
- Native screen saver selection uses [PaperSaverKit](https://github.com/AerialScreensaver/PaperSaver) 0.4.3 (MIT); the full notice is included in `NOTICE` and in the packaged app.

## License

Kinetiq is licensed under the [GNU General Public License v3.0 or later](LICENSE). The resize effect is ported from Compiz windows effect, and the close effects from Burn-My-Windows, which are GPL-3.0-or-later, so Kinetiq is a derivative work under the same license. Third-party notices are in [NOTICE](NOTICE).
