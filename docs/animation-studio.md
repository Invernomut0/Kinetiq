# Animation Studio and catalog — v0.2.1 (build 34)

Kinetiq's compact motion editor works with actual captured macOS windows: no synthetic demo window or placeholder animation replaces the desktop adapters. The [README library](../README.md#effects-library-65-effects-six-permanent-categories) describes the shared **65-entry** `LibraryEffect` manifest used by NSMenu and the Effects library: **19 Studio + 46 originals**, with combined category counts **5/31/14/10/2/3**. Originals are directly available in those categories; **Window Trigger Assignments** is the footer for global choices, Off and Random, not a hidden originals library. The [original-effects guide](original-effects.md) lists all 30 close shaders, 6 entrances, 9 minimize morphs and Liquid (counted once).

This is a discovery correction, not a Studio schema expansion. The **19 Studio effect IDs, schema 1 and layer model remain unchanged**, with Studio-only category counts **2/4/4/4/2/3**. Originals are not Studio JSON layers and cannot be added as such. Catalog Liquid Morph remains separate from original Liquid; shared titles such as Morph, Portal, Ripple and Genie do not identify interchangeable engines.

## Quick start

1. Enable Kinetiq and grant Screen Recording for captures. Desktop movement/restoration also requires Accessibility; a panel preview itself makes no AX changes.
2. Open **Setup → Effects**, select a category and a **Studio** effect, then choose a real target window. Refresh the target picker if windows have changed. Excluded apps and Kinetiq's own windows are not catalog targets. For Original entries, use the separate workflow below.
3. Use the five tabs: **Preview**, **Parameters**, **Triggers**, **Performance**, **Reset**. Scrub the capture, adjust bounded values or load Default/Subtle/Dramatic. Changes are unsaved until **Save & Apply**; **Revert** reloads the saved preset. **Export Saved Preset…** exports saved values, not pending edits.
4. **Run on Window** performs a separate restoring desktop action. **Stop & Restore** cancels it. Manual Run never closes or minimizes the target, even when the preset's trigger metadata says Close or Minimize.
5. To automate a Studio action, choose a supported trigger and **Save & Apply**. Choosing a Studio effect in the menu runs its saved preset on an eligible window of the frontmost app; it does not assign the trigger. An original menu item instead opens its exact detail without playback or assignment.

The 12 dashboard pages are Overview, Windows, Effects, Animation Studio, Physics, Layouts, Workspaces, Rules, Performance, Diagnostics, Settings and Screen Saver. Layouts exposes Orbit/Exposé 3D; Workspaces also exposes Cube. Neither is a native Spaces manager.

### Original details are not Studio presets

Native original menu labels are **Title — Original Close…**, **Title — Original Open…**, **Title — Original Minimize…** and **Liquid — Original Close / Minimize…**. Each opens the exact five-tab detail: **Preview**, **Parameters**, **Triggers**, **Performance**, **Reset**. Opening it or previewing does not change assignments.

- **Use for Close/Open/Minimize** writes only the corresponding existing `Settings` choice/raw ID and releases only that trigger's `CatalogStore` owner. The former owner's parameters/tracks and all other owners survive. Liquid provides separate Close and Minimize actions. Per-app close overrides and exclusions remain unchanged; a per-app choice can still override the new global original close effect.
- Original close/minimize share the existing **0.25×–3× duration multiplier, default 1×**, applied immediately. Reset Shared Duration to 1× changes that shared value, not assignments or rules. Original shader-specific uniforms keep compiled defaults; there are no new per-effect JSON controls.
- Original entrances reuse Physics spring/mesh settings. Existing glide, tilt, focus glow, drop ripple, maximize and resize controls stay on Physics unchanged.
- Preview renders a real selected capture using `CloseEffectRenderer`, a `KinetiqModel` entrance, `DockMorphDeformer`, or `LiquidWorld` with `LiquidEffectRenderer`. It is panel-only: no AX movement, close or minimize. Minimize has a local destination, not the actual Dock; Liquid keeps a local floor stage with no actual desktop obstacles. Native playback remains unchanged.
- Original preview targets are bounded to **8,000,000 pixels / 8192 per dimension**; source captures to **32,000,000 pixels / 16384 per dimension**. At most **two in-flight requests**, cancellation/generation checks and backing retention through GPU completion bound work and lifetime. A closed expensive-effects gate refuses original shader and Liquid previews instead of substituting a cheaper animation.

## Edit a motion document

Open **Animation Studio…** from the menu, or its dashboard page. Choose a real target, then **Add Layer** from the timeline. Each layer has a name, enabled state, start offset in document seconds and its own effect preset. Layers process the captured image sequentially in document order; this is not a general-purpose video editor.

- Play/Pause runs the **panel preview**, with at most ten preview requests per second. Seek-to-start and the scrub slider move the playhead; playback ends at the document duration rather than looping forever.
- Select a layer and use **Parameters** to edit its start, duration and static controls. Choose a parameter and **Add Parameter Track** to create endpoint keys. Add another at the playhead, edit time/value, move keys with their sliders, delete keys or mute/remove the track. Timeline diamonds show active keys; the curve plot samples the actual Core evaluator.
- Key time is normalized within its preset: `0` is its start and `1` its end. Document time equals layer start plus key time × preset duration. Values use the descriptor's units/bounds, not arbitrary normalized values.
- Each key's **Outgoing Curve** controls the segment leading to the next key. The last key's curve is unused. Choices are `linear`, `easeIn`, `easeOut`, `easeInOut`, `spring`; spring is bounded. There are **no editable cubic-Bézier tangents**. Values hold before the first/after the last key; muted or empty tracks use static values/defaults.
- **Playback curve** controls effect progress; the pure `EffectPreset.value(_:at:)` evaluator samples local seconds and outgoing segment curves without applying a second preset time warp. The native drag adapter applies its preset clock curve once before sampling tracks.
- Explicit **Undo/Redo** toolbar buttons maintain up to **100 document snapshots**. Invalid edits are atomic, produce an error and do not enter history; a new edit clears redo. Document import is undoable.
- **Save Document** persists the document locally. It does not assign layer triggers to the engine. **Presets → Save Layer as Effect Preset** saves that effect and its trigger separately. Loading a built-in variant replaces the layer's preset, including tracks/trigger.
- **Copy/Paste Parameters** validates preset JSON and requires the same effect ID. Paste replaces only static parameters, preserving the destination name, duration, trigger and tracks. It does not copy an entire timeline.
- **Reset Layer Preset** resets the selected layer's preset and is undoable; name/start remain. Library **Reset This Effect** instead removes that effect's saved preset/assignment, without resetting other effects.

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

**Presets → Import Effect Preset… / Export Layer Preset…** exchanges a preset. **Import Document JSON… / Export Document JSON…** exchanges the composition. Importing an effect preset also saves its trigger assignment; importing a document changes the editor until Save Document. Exports contain real mathematical animation data, not captured pixels.

All listed fields are required; unknown fields at every model level, unsupported schema versions, unknown enum/raw IDs, unsupported triggers, unknown parameter keys, nonfinite/out-of-bounds values, duplicate IDs/tracks or unordered key times fail explicitly.

| Object | Required fields |
|---|---|
| EffectPreset | `schemaVersion`, `effect`, `name`, `duration`, `curve`, `trigger`, `parameters`, `tracks` |
| AnimationTrack | `id` (UUID), `parameter`, `keyframes`, `muted` |
| AnimationKeyframe | `id` (UUID), `time`, `value`, `curve` |
| StudioDocument | `schemaVersion`, `name`, `duration`, `layers` |
| StudioLayer | `id` (UUID), `name`, `preset`, `start`, `enabled` |

Both document and nested presets use `schemaVersion: 1`. Raw trigger IDs are `manual`, `drag`, `close`, `minimize`, `open`, `overview`; only the effect's supported subset is accepted. Raw effect IDs are the README table's identifiers, including `depth-of-field`, `liquid-morph`, `workspace-cube` and `expose-3d`. Parameter dictionaries may be sparse: omitted known parameters use descriptor defaults, but unknown keys are errors. Every effect has `amplitude` (0–2, default 1) and `speed` (0.1–4, default 1), plus its effect-specific controls.

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

There is **one explicit catalog owner per non-manual action**, not a chain of effects. Saving/importing a new owner changes the old owner's trigger to Manual while retaining its preset/track data. Built-in defaults are Manual, so existing original settings are not silently replaced. Removing/resetting the assignment lets the existing original action resume. Explicitly choosing an original through Use for Close/Open/Minimize or the Window Trigger Assignments picker releases only that action's owner, retaining its parameters/tracks. A catalog Close assignment overrides original global/per-app close choices until released; after release, per-app choices still override the global original close choice. Exclusions remain unchanged and still apply.

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

**Failure handling.** Unavailable permissions, capture, exact AX ownership, Metal/GPU resources or a forbidden expensive mode cause explicit errors/refusal and native fallback/restoration—not a fake cheap demo. Expensive catalog modes are Shatter, Explode, Burn, DOF, Liquid Morph, Cube, Orbit and Exposé 3D. A rejected native Close simply leaves the real close unchanged; a failed intercepted Minimize falls back to its native action. Legacy Liquid also refuses new playback when expensive effects are disallowed.

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
- `Kinetiq/LibraryEffect.swift`: shared discovery/category placement and `OriginalEffectAssignment`; this wrapper does not add Studio effect IDs. `OriginalEffectDetailView.swift` / `OriginalEffectPreview.swift` reuse original Settings and engines without converting them to Studio presets. `CatalogStore.releaseAssignment(to:)` retains the released owner's preset/track data.

## Validation and release status

From the repository root, use `swift test -c release` for the whole suite, `swift test -c release --filter Catalog` for catalog coverage, `swift test -c release --filter Studio` for editor coverage and `swift test -c release --filter Liquid` for real-capture fluid regressions. Use `swift test --enable-code-coverage` for coverage. Build/package instructions and screen saver prerequisites remain in the README; graphical tests require a real session and applicable permissions, not mock data.

**Current v0.2.1 / build 34:** the final release suite passed **277 tests — 144 Core + 36 Effects + 97 app; 0 failures, 0 skips** (`/tmp/kinetiq-v021-suite.log`). App tests include **11 Management + 7 OriginalEffectLibrary + 8 OriginalEffectPreview + 10 StudioUI + 61 other existing tests**. All 30 original shaders, six entrances, nine minimize morphs and Liquid passed genuine real-capture tests, including the README Liquid regression. All 65 navigation requests are routed and consumed, including repeated navigation; `onChange(initial: true)` fixes `@Published` reentrancy.

The `CatalogRuntimeTests` helper waits for WindowServer opacity and an origin matching the child window's actual AppKit frame before testing restoration. macOS can slide a native window in from negative X while it is already opaque; no restoration assertions were weakened.

The build script completed (`/tmp/kinetiq-v021-build.log`); app and embedded `.saver` were each verified directly as arm64/x86_64 with strict signatures and packaged version **0.2.1 / build 34**. The app was launched and Quick Look/Finder refreshed. Clicking native **Destruction → Dissolution → Fire — Original Close…** opened the exact original Fire detail; Accessibility inspection confirmed 65 effects and `/tmp/kinetiq-v021-fire.png` was visually inspected. No effect was activated or user assignment changed. [TODO R2](../TODO.md) is **Done**.

Current merged release line coverage (`/tmp/kinetiq-v021-coverage.txt`): `LibraryEffect.swift` **100%**, `CatalogStore.swift` **100%**, `OriginalEffectPreview.swift` **85.32%**, `OriginalEffectDetailView.swift` **40.80%**. These figures do not measure Metal shader branch coverage. Historical v0.2.0 evidence remains in the [changelog](../CHANGELOG.md#020--build-33), separate from current acceptance. Local logs and opt-in own-window screenshots remain under `/tmp`, not in exported presets or the repository.