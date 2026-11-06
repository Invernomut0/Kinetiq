# Original effects — v0.2.1 (build 34)

This correction restores direct discovery of every prior effect in the same six permanent categories used by the native NSMenu and Effects library. It does not replace the original engines, migrate preferences or expand Studio's JSON schema.

`Sources/Kinetiq/LibraryEffect.swift` is the shared discovery and classification source: **65 entries = 19 Studio + 30 original close shaders + 6 original entrances + 9 original minimize morphs + Liquid**. Liquid is one entry supporting two triggers, not two effects. The 19 Studio entries remain unchanged; see the [README catalog table](../README.md#effects-library-65-effects-six-permanent-categories) and [Studio guide](animation-studio.md).

| Permanent category | Studio | Originals | Combined |
|---|---:|---:|---:|
| Window Motion | 2 | 3 | 5 |
| Transitions | 4 | 27 | 31 |
| Destruction | 4 | 10 | 14 |
| Spatial Effects | 4 | 6 | 10 |
| Physics | 2 | 0 | 2 |
| Workspace & Overview | 3 | 0 | 3 |
| **Total** | **19** | **46** | **65** |

Originals appear directly in those categories, not hidden in the former Legacy Window Triggers disclosure. Its replacement, **Window Trigger Assignments**, retains the global Close/Open/Minimize pickers, **Off**, **Random** and shared duration. Existing spring/mesh, glide, tilt, focus glow, drop ripple, maximize and resize controls remain on **Physics** unchanged.

## Complete original-effects list

The following tables enumerate all **46 originals**, with the exact category/submenu placement in `LibraryEffect.swift`. Preference values are the existing `Settings` raw IDs, not Studio JSON effect IDs. Discovery IDs use `close:<CloseEffect.rawValue>`, `open:<WobbleEntrance.rawValue>`, `minimize:<DockMorphStyle.rawValue>` and `liquid`; those discovery prefixes do not replace the preference formats below.

### Original Close — 30 shaders

All rows support **Close**. The preference value is stored in `Settings.closeEffect`; the same values remain valid for per-app close rules.

| Effect | Category | Submenu | Existing preference value |
|---|---|---|---|
| Aperture Panels | Spatial Effects | 3D Transform | `aperturePanels` |
| Apparition | Transitions | Transform | `apparition` |
| Aura Glow | Spatial Effects | Depth & Lighting | `auraGlow` |
| Broken Glass | Destruction | Fragmentation | `brokenGlass` |
| Doom | Destruction | Dissolution | `doom` |
| Energize A | Destruction | Dissolution | `energizeA` |
| Energize B | Destruction | Dissolution | `energizeB` |
| Fire | Destruction | Dissolution | `fire` |
| Focus | Spatial Effects | Depth & Lighting | `focus` |
| Glide | Transitions | Transform | `glide` |
| Glitch | Transitions | Distortion | `glitch` |
| Hexagon | Transitions | Pixel Transitions | `hexagon` |
| Incinerate | Destruction | Dissolution | `incinerate` |
| Materialize | Transitions | Transform | `materialize` |
| Matrix | Transitions | Pixel Transitions | `matrix` |
| Morph | Transitions | Transform | `morph` |
| Mushroom | Destruction | Fragmentation | `mushroom` |
| Paint Brush | Transitions | Pixel Transitions | `paintBrush` |
| Pixelate | Transitions | Pixel Transitions | `pixelate` |
| Pixel Wheel | Transitions | Pixel Transitions | `pixelWheel` |
| Pixel Wipe | Transitions | Pixel Transitions | `pixelWipe` |
| Portal | Spatial Effects | Distortion | `portal` |
| RGB Warp | Transitions | Distortion | `rgbWarp` |
| Snap of Disintegration | Destruction | Dissolution | `snapOfDisintegration` |
| Team Rocket | Spatial Effects | 3D Transform | `teamRocket` |
| T-Rex Attack | Destruction | Fragmentation | `tRexAttack` |
| TV Effect | Transitions | Transform | `tvEffect` |
| TV Glitch | Transitions | Distortion | `tvGlitch` |
| Wisps | Destruction | Dissolution | `wisps` |
| Wormhole | Spatial Effects | Distortion | `wormhole` |

### Original Open — 6 entrances

All rows support **Open**, using the original jelly model. Values are stored in `Settings.openEffect` with the existing `wobble:` prefix.

| Effect | Category | Submenu | Existing preference value |
|---|---|---|---|
| Wobble Pop | Window Motion | Elastic Entrances | `wobble:wobblePop` |
| Ripple | Transitions | Distortion | `wobble:ripple` |
| Stone in Water | Transitions | Distortion | `wobble:stoneInWater` |
| Shockwave | Transitions | Distortion | `wobble:shockwave` |
| Jelly Squash | Window Motion | Elastic Entrances | `wobble:jellySquash` |
| Quake | Window Motion | Elastic Entrances | `wobble:quake` |

### Original Minimize — 9 Dock morphs

All rows support **Minimize**, using the original deformer. Values are stored in `Settings.minimizeEffect` with the existing `morph:` prefix.

| Effect | Category | Submenu | Existing preference value |
|---|---|---|---|
| Dock Morph | Transitions | Minimize / Restore | `morph:morph` |
| Genie | Transitions | Minimize / Restore | `morph:genie` |
| Jelly Suck | Transitions | Minimize / Restore | `morph:jellySuck` |
| Whirlpool | Transitions | Minimize / Restore | `morph:whirlpool` |
| Tornado | Transitions | Minimize / Restore | `morph:tornado` |
| Rubber Band | Transitions | Minimize / Restore | `morph:rubberBand` |
| Pancake | Transitions | Minimize / Restore | `morph:pancake` |
| Accordion | Transitions | Minimize / Restore | `morph:accordion` |
| Hop | Transitions | Minimize / Restore | `morph:hop` |

### Original Close / Minimize — Liquid

| Effect | Category | Submenu | Supported triggers | Existing preference value |
|---|---|---|---|---|
| Liquid | Transitions | Fluid | Close, Minimize | `liquid` in either corresponding Settings choice |

Liquid is distinct from Studio **Liquid Morph**. Original Morph, Portal, Ripple and Genie also remain distinct from similarly named Studio entries; badges, menu suffixes and discovery IDs identify the actual engine.

## Open, preview and explicitly assign

1. Select an Original entry directly in its Effects category, or choose its native menu item. Labels are **Title — Original Close…**, **Title — Original Open…**, **Title — Original Minimize…**, or **Liquid — Original Close / Minimize…**. The action opens that exact library detail, not a Studio namesake, and does not run or silently assign anything.
2. Choose a real eligible window in **Preview**, scrub progress and use **Recapture** as needed. Screen Recording and an enabled engine are required. The panel reports capture, permission, Metal and budget errors rather than displaying a fabricated demo.
3. Use **Use for Close**, **Use for Open** or **Use for Minimize** to activate the supported native action. Liquid has independent Close and Minimize buttons; activating one does not assign the other. An already selected action shows **Active for Close/Open/Minimize**.

Opening the detail, switching its tabs, choosing a capture or scrubbing a preview never changes assignments. The five tabs are:

| Tab | Original behavior |
|---|---|
| Preview | Real selected capture, progress scrubber and Recapture; panel-only rendering. |
| Parameters | Existing shared duration for close/minimize; entrances link to Physics settings. Shader-specific uniforms retain compiled defaults. |
| Triggers | Supported actions, current selection and any Studio owner that explicit activation will release. |
| Performance | Actual original rendering path and shared quality/resource diagnostics. |
| Reset | Reset Shared Duration to 1×; entrances also link to Physics. Does not reset assignments, per-app rules or exclusions. |

### Settings, ownership and per-app rules

Explicit activation writes the existing `Settings.closeEffect`, `Settings.openEffect` or `Settings.minimizeEffect` raw value. `OriginalEffectAssignment` first calls `CatalogStore.releaseAssignment(to:)` for **only that action**. The former Studio owner's trigger becomes Manual; its preset parameters and tracks are preserved, as are every other action's owner and the Studio document. A release failure is surfaced rather than silently replacing preferences.

No duplicate legacy preset store or automatic preference migration is introduced. Existing choices survive merely opening the app or library. The footer's global pickers also release only the corresponding catalog owner when a choice is explicitly selected. **Off** and **Random** remain available: Close Random chooses among the 30 shaders, Open among the six entrances, and Minimize among the nine morphs; Liquid is not silently added to those random pools.

Per-app close choices and exclusions stay in **Rules** and are not cleared by original activation. A per-app close choice, including Off or Liquid, can still override the newly chosen **global original** close effect. A subsequently saved explicit Studio Close owner takes precedence over global/per-app original close choices until released; exclusions still apply.

### Existing controls, not new JSON parameters

Original close and minimize effects share `Settings.closeDuration`: **0.25×–3×, default 1×**. Editing it takes effect immediately across those originals; **Reset Shared Duration to 1×** changes only that shared value. It is not a per-effect preset duration. Original shader-specific material uniforms retain their compiled defaults and existing runtime context; this correction does not expose them as new editable per-effect JSON controls.

Original entrances keep the existing Physics spring, friction, speedup, mass and mesh settings. Existing maximize, resize, shadow, glide/bounce, 3D tilt, focus glow and drop ripple settings remain on Physics unchanged. The **19 Studio IDs, schema-1 preset/document validation and layer model are unchanged**. Originals cannot be inserted as Studio JSON layers, imported as new Studio effect IDs or given Studio parameter tracks by this discovery wrapper.

## Real preview engines and safety boundaries

`OriginalEffectPreview` / `OriginalPreviewRenderer` render actual ScreenCaptureKit frames through the original paths:

| Original family | Preview path | Deliberate panel boundary |
|---|---|---|
| Close shaders | `CloseEffectRenderer` with the selected `CloseEffect` / `EffectScene` | No actual close; the capture is rendered offscreen. |
| Open entrances | `WobbleEntrance.apply` on `KinetiqModel`, stepped at 120 Hz | Original spring/mesh motion, not Studio Ripple/Wobbly substitution; no AX movement. |
| Minimize morphs | `DockMorphDeformer` | Local preview destination, **not the actual Dock**; no native minimize or Dock preference change from previewing. |
| Liquid | `LiquidWorld` with `LiquidEffectRenderer` | Retained local floor stage, **no actual desktop obstacles**; scrubbing covers 0–6 normalized seconds, scaled by shared duration. |

Previews never move, park, close or minimize a live window. Liquid's local stage is retained so falling/pooling fluid is not cropped to the now-empty source rectangle. It does not capture or simulate other desktop windows as obstacles. These panel boundaries do not change native playback: actual minimize still uses the real Dock path, and native Liquid still uses live window-top obstacles and per-display floors as described in the [README](../README.md#liquid-close-and-minimize-v0131).

### Bounded resources and cancellation

- Offscreen targets follow the current texture-scale budget and are capped at **8,000,000 pixels and 8192 pixels per dimension**.
- Each source capture is capped at **32,000,000 pixels and 16384 pixels per dimension**, including capture/shadow allocation checks. Real target eligibility and unchanged frame are checked around capture/render completion.
- At most **two preview requests are in flight** per renderer. New work invalidates stale generations; cancellation, hidden/closed detail panels and disabled effects prevent stale results from being displayed. Bounded simulation loops yield and check cancellation.
- The captured pixel buffer, IOSurface/CoreVideo mapping and `CVMetalTexture` backing remain retained through committed GPU command completion, even if the requesting task disappears or is superseded. Captures stay in memory, not Studio JSON or a new disk cache.
- Mesh/particle/texture budgets still apply. When `allowsExpensive` is false, **original close shader and Liquid previews refuse playback**; there is no fallback to Glide or another misleading substitute. This preview rule does not redefine native engine lifecycle behavior.

## Native playback remains unchanged

Close observes actual window disappearance/fade after pre-capture; refused closes, tab closes, hiding and Space changes are not window-close animations. Original Open keeps the jelly entrance lifecycle after a new standard window stabilizes. Minimize intercepts the yellow button only; capture/setup failure replays the native click, and **⌘M / Dock minimization remain native**. Explicitly enabling native minimize continues to synchronize the Dock animation preference as before; merely opening or previewing an original does not.

## Verification status

**Current v0.2.1 / build 34:** the final release suite passed **277 tests: 144 Core + 36 Effects + 97 app; 0 failures, 0 skips**. The app suite includes **11 Management + 7 OriginalEffectLibrary + 8 OriginalEffectPreview + 10 StudioUI + 61 other existing tests**. All 30 original shaders, six entrances, nine minimize morphs and Liquid passed genuine real-capture tests, including the README Liquid regression. All 65 effect navigation requests are routed and consumed, including repeated navigation, after fixing `@Published` reentrancy with `onChange(initial: true)`. Final log: `/tmp/kinetiq-v021-suite.log`; opt-in UI captures: `/tmp/kinetiq-v021-ui`.

Build script completed (`/tmp/kinetiq-v021-build.log`); both app and embedded `.saver` passed direct arm64/x86_64 `lipo` and strict signature checks. Actual packaged version **0.2.1 / build 34** was confirmed, the app launched and Quick Look/Finder refreshed. Native **Destruction → Dissolution → Fire — Original Close…** opened the exact original Fire detail; Accessibility inspection confirmed 65 effects and `/tmp/kinetiq-v021-fire.png` was visually inspected. This inspection did not activate an effect or change user assignments. [TODO R2](../TODO.md) and task 9 are **Done**.

Current merged release line coverage (`/tmp/kinetiq-v021-coverage.txt`): `LibraryEffect.swift` **100%**, `CatalogStore.swift` **100%**, `OriginalEffectPreview.swift` **85.32%**, `OriginalEffectDetailView.swift` **40.80%**. This is not Metal shader branch coverage. Historical v0.2.0 verification remains separately recorded in the [changelog](../CHANGELOG.md#020--build-33).