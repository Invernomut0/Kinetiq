# Animation Studio and catalog — v0.4.0 (build 40)

Kinetiq's compact motion editor composes effects on a window capture. Previews play on a built-in **sample window** (a drawn macOS-style document packaged like a ScreenCaptureKit capture) or on any real window you pick as preview source; real windows are only captured for previews, never moved. The [README library](../README.md#effects-library-66-effects-organized-by-what-you-do) describes the shared **66-entry** `LibraryEffect` manifest (**19 Studio + 47 originals: 30 close shaders + 6 entrances + 9 minimize morphs + Liquid + Window Destruction**) that the menu bar and the Effects library organize by window event. The [original-effects guide](original-effects.md) lists every built-in effect.

The **19 Studio effect IDs are unchanged** since v0.2.0. Documents are **schema 2** since v0.4.0: a layer may play a built-in engine (`builtin`) and play in reverse (`reversed`). Schema 1 documents still import and are upgraded on save. Originals are not Studio JSON layers and cannot be added as such. Catalog Liquid Morph remains separate from original Liquid; shared titles such as Morph, Portal, Ripple and Genie do not identify interchangeable engines.

## Quick start

1. Enable Kinetiq and grant Screen Recording for real-window captures. Desktop movement/restoration also requires Accessibility; previews make no AX changes.
2. Open **Effects**. The sidebar is grouped by event: *When you drag a window*, *When a window opens*, *When a window closes*, *When you minimize*, *Overview & layouts*. Select any effect: its preview starts looping on the sample window right away. Use the source menu under the preview to switch to one of your real windows.
3. Press **Use when a window closes** (or the button for the event you selected). The checkmark in the sidebar and the menu bar title (“Close: Fire”) update. **Off** and **Random** are in the section header and in the menu bar.
4. Studio presets have **Customize parameters**: edits show in the preview immediately; **Save** keeps them (using the effect also saves pending edits). Variants Default/Subtle/Dramatic are one click. Built-ins share a duration multiplier; entrances follow Physics.
5. **More › Run on Window** plays a Studio preset once on the preview-source window (or the frontmost app's window) and restores it; it never closes or minimizes anything. **Open in Animation Studio** adds the preset as a layer.

The 11 dashboard pages are Overview, Effects, Animation Studio, Physics, Layouts, Rules, Screen Saver and, under System, Performance, Windows, Diagnostics and Settings. Layouts starts Exposé 3D, Orbit or Cube on the current Space; it is not a native Spaces manager.

### Built-in effects are not Studio presets

- **Use when…** for a built-in writes only the corresponding `Settings` choice/raw ID and releases only that event's `CatalogStore` owner. The former owner's parameters/tracks and all other owners survive. Liquid offers both Close and Minimize buttons; Window Destruction offers **Use when a window closes** only and is also selectable globally in the Close menu or in per-app close rules. Per-app close overrides and exclusions remain unchanged; a per-app choice can still override the global built-in close effect. Off is unchanged, close Random still selects only among the 30 shaders, and Fire remains the default.
- Built-in close/minimize share the existing **0.25×–3× duration multiplier, default 1×**, applied immediately (**Adjust** on the effect page). Shader-specific uniforms keep compiled defaults.
- Entrances reuse Physics spring/mesh settings. Glide, tilt, focus glow, drop ripple, maximize and resize controls stay on Physics.
- Previews use `CloseEffectRenderer`, a `KinetiqModel` entrance, `DockMorphDeformer`, `LiquidWorld` with `LiquidEffectRenderer`, or the shared Chaos extraction/scene/physics/renderer path for Window Destruction. Minimize has a local destination, not the actual Dock; Liquid and Window Destruction keep local floor stages. These previews make no AX changes and leave the real window untouched.
- Preview targets are bounded to **8,000,000 pixels / 8192 per dimension**; source captures to **32,000,000 pixels / 16384 per dimension**. At most **two in-flight requests**, cancellation/generation checks and backing retention through GPU completion bound work and lifetime. A closed expensive-effects gate refuses GPU-heavy previews instead of substituting a cheaper animation.

### Window Destruction is a Close-only built-in

`LibraryEffect.destruction` and `CloseEffectChoice.destruction` use raw ID `destruction`, with **Destruction / Fragmentation** metadata. It adds no Studio effect ID, schema field or layer type. Its captured-window path reuses `UIObjectExtractor`, `ChaosScene`, `ChaosWorld.destroyWindow()` and `ChaosRenderer` in transparent `oneShot` mode: no wallpaper and no restoring/rebuilding scene loop. Glyphs/icons release over **0.02–0.22 normalized seconds**, shards over **0.4–1.15**; gravity, bouncing and piling end in a fade with a **three-normalized-second lifetime**. The complete preview timeline is **six seconds at 1×**, scaled along with the simulation by the shared **0.25×–3×** duration multiplier.

Desktop playback uses a per-display floor at the full display bottom behind the Dock and click-through overlays. At most **two source captures including pending work**, **32,000,000 pixels / 16384 per dimension** per capture, and **1200 glyphs / 160 other objects / 256 target tiles per display** bound the work. Preview instead uses a local floor without AX movement. The expensive-effects gate refuses playback; there is no substitute animation. Captures are memory-only: no disk images, saver activation or changes to the existing screen saver. See the [original-effects contract](original-effects.md#original-close--window-destruction).

### The Wobbly preview is the real spring model

Selecting **Wobbly** (or scrubbing a single-layer Wobbly document) replays `KinetiqModel` deterministically at 120 Hz under a scripted drag: the title bar is grabbed at 0 s, swept right and back for 1.8 s, released, and the mesh settles until 3 s. Stiffness, friction and speed come from the preset (or its tracks) and amplitude scales the displacement, exactly like the live drag adapter. Multi-layer compositions keep the shader membrane, which v0.3.0 reshaped to resemble a released spring sheet.

## Make your own effect

1. Open **Animation Studio** (menu bar or dashboard). The guide card explains the three steps; ✕ hides it and ? brings it back. **Load an Example** gives a Studio Ripple followed by the built-in Incinerate.
2. **Add Layer** offers two groups. *Studio effects* (19) have parameters and keyframes. *Built-in effects* are the original engines: 30 close shaders, 6 spring entrances and 9 Dock morphs. A new layer starts where the last one ends; drag its start in **Edit** to overlap layers. Overlapping layers chain: each one transforms the previous one's result, so a Ripple can feed Incinerate.
3. Select a layer. **Edit** has name, enabled, **Play in reverse**, start and, for built-ins, duration, speed curve and *Natural duration*. Reverse turns a close shader into an entrance (using the shader's own opening direction) and a Dock morph into a restore. Studio layers also show variants and parameters; **Keyframes** animates one parameter over the layer.
4. The preview loops on the sample window with its own Play button; it follows every edit while playing. Click the timeline ruler to move the playhead; the source menu switches to a real window, which is only captured. **Run on Window** plays the document once on the preview-source window (or the topmost window) and puts it back.
5. **Save** (⌘S) stores it in **My Effects** under its name. **Use when… → When a window closes** (or opens, or minimize) makes it the owner of that event; the status line confirms it, and the menu bar title reads e.g. “Close: Burn Out”. **Stop using it automatically** releases the event. **My Effects** in the toolbar opens, creates or deletes saved effects.

Close and Minimize play the composition on the window's last image after it has gone, so end with a layer that makes the window disappear; otherwise the image simply ends. Open plays it on the new window before handing the real window back. Drag cannot be owned by a composition: it is a live physics policy.

Saved effects also appear in **Effects › My Effects** (preview, Use when…, Run, Edit in Studio, Delete), in the menu bar's Open/Close/Minimize submenus and in **Try an Effect**. Each event has one owner across catalog presets and My Effects; assigning one releases the other without deleting it.

## Edit a motion document

Each layer has a name, enabled state, direction, start offset in document seconds and either a catalog preset or a built-in engine. Layers process the captured image sequentially in document order; this is not a general-purpose video editor. The inspector has three tabs: **Edit**, **Keyframes** and **Advanced** (rendering class, saving a Studio layer as its effect's library preset, copy/paste, reset).

The guide appears inline only for empty documents; **?** opens it as a popover so it cannot push the populated editor out of view.

The management sidebar and editor use the actual native column viewport, including at the 960 × 700-point minimum content size. v0.3.1 fixes oversized native ideal heights that previously placed sidebar rows, toolbar and timeline outside the window. Parameters and tracks scroll inside the inspector; the timeline remains a separate editing area.

- The preview's Play/Pause loops the document on the sample window or the chosen real window; frames self-pace behind the renderer and hold the last frame briefly before looping. Seek-to-start and the scrub slider move the playhead; playback ends at the document duration rather than looping forever.
- Select a layer and use **Edit** for its start, duration and static controls. In **Keyframes**, choose a parameter and **Add Keyframe Track** to create endpoint keys. Add another at the playhead, edit time/value, move keys with their sliders, delete keys or mute/remove the track. Timeline diamonds show active keys; the curve plot samples the actual Core evaluator.
- Key time is normalized within its preset: `0` is its start and `1` its end. Document time equals layer start plus key time × preset duration. Values use the descriptor's units/bounds, not arbitrary normalized values.
- Each key's **Outgoing Curve** controls the segment leading to the next key. The last key's curve is unused. Choices are `linear`, `easeIn`, `easeOut`, `easeInOut`, `spring`; spring is bounded. There are **no editable cubic-Bézier tangents**. Values hold before the first/after the last key; muted or empty tracks use static values/defaults.
- **Playback curve** controls effect progress; the pure `EffectPreset.value(_:at:)` evaluator samples local seconds and outgoing segment curves without applying a second preset time warp. The native drag adapter applies its preset clock curve once before sampling tracks.
- Explicit **Undo/Redo** toolbar buttons maintain up to **100 document snapshots**. Invalid edits are atomic, produce an error and do not enter history; a new edit clears redo. Document import is undoable.
- The working document is kept automatically. **Save** adds or updates it in My Effects; **Use when…** saves it and makes it the owner of a window event in one step. **Advanced → Save Layer as … Preset** instead stores a single Studio layer as that effect's library preset. Loading a built-in variant replaces the layer's preset, including tracks/trigger.
- **Copy/Paste Parameters** validates preset JSON and requires the same effect ID. Paste replaces only static parameters, preserving the destination name, duration, trigger and tracks. It does not copy an entire timeline.
- **Advanced → Reset Layer Preset** resets the selected layer's preset and is undoable; name/start remain. The library's **Reset to Defaults** instead removes that effect's saved preset/assignment, without resetting other effects.

### Hard limits

| Value | Limit |
|---|---|
| Document duration | 0.1–60 seconds |
| Layers | 32 per document |
| Preset duration | 0.1–12 seconds |
| Parameter tracks | 64 per preset, at most one per parameter (including muted tracks) |
| Keyframes | 128 per track; unique IDs and strictly increasing times |
| Key time/value | Time 0–1; finite value within that parameter's descriptor bounds |
| Names | Nonempty, no control characters, at most 256 UTF-8 bytes |
| Imported JSON | At most 32 MiB |

Even disabled layers must fit entirely inside the document. Studio sorts edited key times before validation; strict JSON import does not silently sort, discard or repair invalid data. The track ceiling is a schema bound, not a promise of 64 distinct controls for every effect.

## JSON schema 1

**File → Import Effect Preset as Layer…** and **Advanced → Copy / Paste / Export → Export Layer Preset…** exchange a preset. **File → Import Document JSON… / Export Document JSON…** exchanges the composition. Importing an effect preset also saves its trigger assignment; importing a document changes the editor until Save Document. Exports contain real mathematical animation data, not captured pixels.

All listed fields are required; unknown fields at every model level, unsupported schema versions, unknown enum/raw IDs, unsupported triggers, unknown parameter keys, nonfinite/out-of-bounds values, duplicate IDs/tracks or unordered key times fail explicitly.

| Object | Required fields |
|---|---|
| EffectPreset | `schemaVersion`, `effect`, `name`, `duration`, `curve`, `trigger`, `parameters`, `tracks` |
| AnimationTrack | `id` (UUID), `parameter`, `keyframes`, `muted` |
| AnimationKeyframe | `id` (UUID), `time`, `value`, `curve` |
| StudioDocument | `schemaVersion`, `name`, `duration`, `layers` |
| StudioLayer | `id` (UUID), `name`, `preset`, `start`, `enabled`; schema 2 adds optional `builtin` (`close:…`, `open:…` or `minimize:…` discovery ID) and `reversed` |

Documents use `schemaVersion: 2` (1 is still read); nested presets use `schemaVersion: 1`. For a built-in layer the nested preset only carries `duration` and `curve`. Raw trigger IDs are `manual`, `drag`, `close`, `minimize`, `open`, `overview`; only the effect's supported subset is accepted. Raw effect IDs are the README table's identifiers, including `depth-of-field`, `liquid-morph`, `workspace-cube` and `expose-3d`. Parameter dictionaries may be sparse: omitted known parameters use descriptor defaults, but unknown keys are errors. Every effect has `amplitude` (0–2, default 1) and `speed` (0.1–4, default 1), plus its effect-specific controls.

This complete, valid default Wobbly preset needs no UUIDs because it has no tracks. It can be imported directly; export from the UI when you need actual layer/track/key UUIDs.

```json
{
  "schemaVersion": 1,
  "effect": "wobbly",
  "name": "Default",
  "duration": 1,
  "curve": "easeInOut",
  "trigger": "manual",
  "parameters": {
    "amplitude": 1,
    "speed": 1,
    "stiffness": 3.8,
    "friction": 3.5
  },
  "tracks": []
}
```

## Trigger ownership and native behavior

There is **one explicit catalog owner per non-manual action**, not a chain of effects. Saving/importing a new owner changes the old owner's trigger to Manual while retaining its preset/track data. Built-in defaults are Manual, so existing original settings are not silently replaced. Removing/resetting the assignment lets the existing original action resume. Explicitly choosing a built-in through **Use when…** (library or menu bar) or picking Off/Random releases only that action's owner, retaining its parameters/tracks. A catalog Close assignment overrides original global/per-app close choices until released; after release, per-app choices still override the global original close choice. Exclusions remain unchanged and still apply.

- **Close:** the app genuinely closes its window; Kinetiq uses a pre-capture and watches WindowServer disappearance/fade. Manual Run is not a close. A refused close, a tab close, hide or Space change is not an actual window close.
- **Minimize:** only the yellow button is intercepted. Capture/setup failure replays the native click safely. Successful native minimize restores the original window origin while leaving it minimized; **⌘M and Dock minimization remain native**.
- **Open:** capture follows a painted/stable new standard window, then a reversible AX lease handles playback. Legacy jelly entrances remain available when no catalog Open owner is assigned.
- **Drag:** a gesture snapshots its saved preset and physics settings; later edits do not change it mid-drag. Wobbly maps stiffness/friction and simulation speed into the real mesh; Float continues ambient oscillation while held, beyond the parameter timeline, then fades its release offset within 0.5 s. Ripple runs on release. Magnet attracts/snaps against real visible geometry; Gravity runs bounded post-release physics. Parameters hold their final values after preset duration rather than wrapping keyframes; release work is duration-bounded, not an endless animation loop.
- **Overview:** supported metadata is saved like other triggers; interactive overview activation is explicit via the menu/Run controls, not automatic native Mission Control interception or a new global shortcut.

## Runtime contracts and explicit boundaries

**Capture and restoration.** Panel preview only renders actual capture pixels; it does not park, raise, close or minimize windows. Manual desktop playback checks the exact window ID/frame, completes initial GPU work before mutation, and restores leased origins on stop/cancellation. Disable, Space/display changes, sleep and termination invalidate work. Missing/invalid explicit targets never fall back to an unrelated window. Captures remain in memory; JSON stores animation values, not screenshots. The separate screen saver cache/privacy policy in the README is unchanged.

**Physics.** Manual Magnet/Gravity use real AX movement for the preset's bounded duration and restore the origin afterward. Native drag uses its own mesh/AX session and final drop/settling position, not a second preview overlay. Shader-only physics previews illustrate local surface deformation; they do not execute native forces.

**DOF / Spatial Effects.** DOF is a single-captured-target defocus material, with focal position along the local surface and bounded blur sampling. Manual playback parks only that target; it does not hide other windows or calculate a global desktop depth buffer. Perspective/lighting are local captured-surface rendering, not a full desktop 3D scene.

**Workspace & Overview.** Cube, Orbit and Exposé 3D use frozen actual captures from the **current Space**, up to **eight windows** with **32,000,000 total capture pixels**. Eligibility, exact AX validation and exclusions may reduce that count. Escape dismisses; clicking a projected captured window activates the real one. Live application content is not continuously recaptured during the overview. Cube is a cube-like projection, not a cube of native Spaces or a full workspace compositor. Orbit is an overview arrangement, not a permanent AX layout. No private Spaces APIs are used and no native Space is switched.

**Composition.** Ordinary enabled layers compose sequentially using bounded ping-pong targets. A desktop document containing dynamics (Magnet/Gravity) or a multiwindow overview must have **one enabled layer**; otherwise Run fails with an explicit composition error. The panel can visually compose these shader styles, but that is not multi-layer native physics or interactive-overview composition. DOF is a single-target material, not a multiwindow overview adapter.

**Failure handling.** Unavailable permissions, capture, exact AX ownership, Metal/GPU resources or a forbidden expensive mode cause explicit errors/refusal and native fallback/restoration—not a fake cheap demo. Expensive catalog modes are Shatter, Explode, Burn, DOF, Liquid Morph, Cube, Orbit and Exposé 3D. A rejected native Close simply leaves the real close unchanged; a failed intercepted Minimize falls back to its native action. Built-in Liquid and Window Destruction also refuse new playback when expensive effects are disallowed.

## Quality and resource budget

The [README quality table](../README.md#render-quality-and-real-gpu-timings) gives `RenderBudget.forQuality` values: Low/Balanced/High/Ultra mesh ceilings **16/32/48/64** and secondary rate ceilings **30/60/90/120 Hz**. Auto starts at High, never automatically enters Ultra and changes one resource per step.

The **13-step reduction order** is texture scale (0.75, 0.5), particles (1000, 700, 400), blur rings (1, 0), mesh (32, 24, 16), secondary rate (60, 30), then expensive modes off. Recovery reverses this order. The smoothed GPU duration uses EWMA alpha 0.15; >12 ms needs 0.5 s and 8 samples to reduce, with 3 s cooldown; <6 ms needs 5 s and 30 samples to recover, with 8 s cooldown. Gaps over one second reset sustained evidence. Only successful completed GPU durations from 10 µs to 1 s are accepted; unsupported/failed timestamps are not replaced with CPU time.

Fair thermal pressure or Low Power Mode applies a Balanced ceiling; serious/critical thermal pressure applies Low, with critical secondary rate capped at 15 Hz. Even manual Ultra obeys these limits without changing the saved selection. Performance shows the actual budget and last smoothed completed GPU duration, **not GPU utilization, measured FPS or a fabricated idle sample**.

Native captures and desktop output remain full-resolution. Studio intermediates obey `textureScale`, preserve aspect ratio and are capped at **8,000,000 pixels and 8192 per dimension per texture**; two ping-pong textures and at most **two in-flight compositions** bound work. Allocation retries reduce intermediate scale before failing. Liquid's independent cropped float32 geometry field has a **1280-pixel longest-edge cap** before quality scaling and 32-pixel buckets; it samples original capture detail at native destination resolution. Liquid retains its original **1500-particle source/display cap** (Balanced 1000, Low budget 400; Low refuses new expensive playback), not an increased unbounded particle count.

The Performance label **“Blur passes”** is a budget field name: catalog DOF implements **concentric eight-tap sampling rings in one fragment shader**, not repeated full-screen blur passes. Zero rings samples the sharp capture once. Particle limits also bound actual transported fragment quads; descriptor fragment counts can be lower than the budget.

## API and source reference

- `KinetiqCore/EffectCatalog.swift`: `EffectID`, `EffectCategory`, descriptors, units/bounds, supported triggers and variants. Use raw IDs for persistence, not titles or declaration indices.
- `KinetiqCore/AnimationPreset.swift`: `validated()`, `encoded()`, `EffectPreset.decode(_:)`, `StudioDocument.decode(_:)`, and `EffectPreset.value(_:at:)` for local-second sampling. Encoding and decoding validate; malformed input is never silently downgraded to another effect.
- `KinetiqEffects/CatalogEffectRenderer.swift`: `encode(effect:texture:uvRect:frame:screenRect:progress:amplitude:speed:meshLimit:particleLimit:blurPasses:parameters:into:)`. The optional `parameters: [String: Float] = [:]` consumes evaluated values; recognized entries override legacy amplitude/speed arguments. Missing custom entries use descriptor defaults; nonfinite entries use defaults; finite entries clamp; unknown dictionary keys are ignored. This permissive low-level dictionary is **not** the strict JSON schema. Invalid legacy scalars/rectangles/UVs/textures skip drawing without clearing the caller's pass.
- Renderer inputs are a compatible 2D capture texture, crop `(offset.x, offset.y, scale.x, scale.y)`, global Y-down screen-point rectangles and bounded progress. Output is premultiplied BGRA8; the caller owns clear/presentation, capture lifetime, ordering, native physics/layout and restoration. No global depth attachment is required.
- `Kinetiq/CatalogRuntime.swift`: real capture preview, restoring playback, exact-window leases, sequential composition and current-Space overview adapters. `CatalogStore.swift` stores validated presets/assignments and the saved document locally. `RenderQuality.swift` / `RenderQualityManager.swift` separate pure policy from ProcessInfo/Metal completion evidence.
- `Kinetiq/LibraryEffect.swift`: shared discovery (`all`, `supporting(_:)`, `blurb`, `kindLabel`, `automaticTriggers`), legacy category placement, `OriginalEffectAssignment` and `TriggerAssignment.current(_:settings:store:)`, which resolves what an event plays (Studio owner first, then the original setting). `EffectTrigger.eventTitle/shortTitle/symbol/explanation` are the user-facing words. `SetupModel.assign(_:to:)` and `setTrigger(_:random:)` are the single assignment path for the library, the menu bar and the Studio.
- `Kinetiq/OriginalEffectPreview.swift`: `OriginalPreviewRenderer` renders every library effect offscreen — original engines, catalog documents through its own `CatalogEffectRenderer`, and the scripted-drag `KinetiqModel` for Wobbly — from `PreviewSource.sample` (`SampleWindow.frame()`) or `.window(id)`. `EffectPreviewPlayer.swift` is the looping, self-pacing SwiftUI player shared by the library, Layouts and the Studio; `PreviewSourceStore` keeps the chosen source. `CatalogStore.releaseAssignment(to:)` retains the released owner's preset/track data.

## Validation and release status

From the repository root, use `swift test -c release` for the whole suite, `swift test -c release --filter Catalog` for catalog coverage, `swift test -c release --filter Studio` for editor coverage and `swift test -c release --filter Liquid` for real-capture fluid regressions. Use `swift test --enable-code-coverage` for coverage. Build/package instructions and screen saver prerequisites remain in the README; graphical tests require a real session and applicable permissions, not mock data.

**Current v0.3.3 / build 38:** final release suite passed **304 tests — 122 app + 36 Effects + 146 Core; 0 failures, 0 skips** (`/tmp/kinetiq-v033-acceptance.log`), with both UI and Destruction opt-in dumps. Real test-window UI snapshots are under `/tmp/kinetiq-v033-ui`; the real README capture-to-Metal frames/contact sheet are under `/tmp/kinetiq-v033-destruction`, not fabricated sample images or distributed artifacts. The contact sheet was visually inspected: text before shards, piling, clear at six seconds at 1× and correct initial border clipping. Normal playback remains memory-only.

Final build exit 0 (`/tmp/kinetiq-v033-final-build.log`); app and embedded saver verified universal x86_64/arm64 with `lipo` and `codesign --verify --deep --strict`. Packaged 0.3.3/build 38 launched from `build/Kinetiq.app` (PID 56054 at verification); Quick Look cache and Finder refreshed. [TODO 19](../TODO.md) is **Done**.

LLVM release **line** coverage (`/tmp/kinetiq-v033-coverage.txt`, not Regions): DestructionEffectPlayer **95.95%**, OriginalEffectPreview **92.49%**, LibraryEffect **98.49%**, ChaosWorld **99.20%**, ChaosRenderer Swift **88.86%**. Not 100%, not Metal shader branch coverage, and not proof of every native failure path/display configuration. Window Destruction remains a Close-only built-in with a local-floor, non-mutating preview; Studio's 19 effects, schema 1 and layer model and the existing screen saver behavior are unchanged.

**Historical v0.3.2 / build 37:** Liquid drainage acceptance is recorded in the [README](../README.md#building) and [original-effects guide](original-effects.md#verification-status); it is not v0.3.3 acceptance.

**Historical v0.3.1 / build 36:** the release suite passed **284 tests — 144 Core + 36 Effects + 104 app; 0 failures, 0 skips** (`/tmp/kinetiq-v031-final-suite.log`). Native regression coverage checks actual split/sidebar geometry for empty/populated documents at three window sizes in light/dark appearances. The test changes only in-memory documents and restores them; it never saves over the user's composition. The signed universal packaged app and saver were verified, and Studio was inspected empty and after Add Layer, including creating a keyframe track at minimum window size. The guide no longer overlaps the editor.

**Historical v0.2.1 / build 34:** the final release suite passed **277 tests — 144 Core + 36 Effects + 97 app; 0 failures, 0 skips** (`/tmp/kinetiq-v021-suite.log`). App tests include **11 Management + 7 OriginalEffectLibrary + 8 OriginalEffectPreview + 10 StudioUI + 61 other existing tests**. All 30 original shaders, six entrances, nine minimize morphs and Liquid passed genuine real-capture tests, including the README Liquid regression. All 65 navigation requests are routed and consumed, including repeated navigation; `onChange(initial: true)` fixes `@Published` reentrancy.

The `CatalogRuntimeTests` helper waits for WindowServer opacity and an origin matching the child window's actual AppKit frame before testing restoration. macOS can slide a native window in from negative X while it is already opaque; no restoration assertions were weakened.

The build script completed (`/tmp/kinetiq-v021-build.log`); app and embedded `.saver` were each verified directly as arm64/x86_64 with strict signatures and packaged version **0.2.1 / build 34**. The app was launched and Quick Look/Finder refreshed. Clicking native **Destruction → Dissolution → Fire — Original Close…** opened the exact original Fire detail; Accessibility inspection confirmed 65 effects and `/tmp/kinetiq-v021-fire.png` was visually inspected. No effect was activated or user assignment changed. [TODO R2](../TODO.md) is **Done**.

Historical v0.2.1 merged release line coverage (`/tmp/kinetiq-v021-coverage.txt`): `LibraryEffect.swift` **100%**, `CatalogStore.swift` **100%**, `OriginalEffectPreview.swift` **85.32%**, `OriginalEffectDetailView.swift` **40.80%**. These figures do not measure Metal shader branch coverage. Historical v0.2.0 evidence remains in the [changelog](../CHANGELOG.md#020--build-33), separate from current acceptance. Local logs and opt-in own-window screenshots remain under `/tmp`, not in exported presets or the repository.