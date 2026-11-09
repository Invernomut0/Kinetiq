# Original (built-in) effects — v0.4.0 (build 40)

Every prior effect is discoverable by the window event it reacts to: the menu bar's **Open**, **Close** and **Minimize** submenus and the matching Effects sections list each built-in next to the compatible Studio presets, with a live preview and a **Use when…** button. The six legacy categories below remain as metadata (they group the **Try an Effect** menu and the Studio's Add Layer menu). Nothing here replaces the original engines or migrates preferences. Since v0.4.0 the 45 non-Liquid built-ins can also be **Animation Studio layers** (schema 2 `builtin` field), forwards or in reverse, and combined into My Effects; **Try an Effect** in the menu bar plays any of them, Liquid and Window Destruction included, once on the front window without closing it.

`Sources/Kinetiq/LibraryEffect.swift` is the shared discovery and classification source: **66 entries = 19 Studio + 30 original close shaders + 6 original entrances + 9 original minimize morphs + Liquid + Window Destruction**. Liquid is one entry supporting two triggers, not two effects; Window Destruction supports Close only. The 19 Studio entries remain unchanged; see the [README catalog table](../README.md#effects-library-66-effects-organized-by-what-you-do) and [Studio guide](animation-studio.md).

| Permanent category | Studio | Originals | Combined |
|---|---:|---:|---:|
| Window Motion | 2 | 3 | 5 |
| Transitions | 4 | 27 | 31 |
| Destruction | 4 | 11 | 15 |
| Spatial Effects | 4 | 6 | 10 |
| Physics | 2 | 0 | 2 |
| Workspace & Overview | 3 | 0 | 3 |
| **Total** | **19** | **47** | **66** |

**Off** and **Random** live in each event's section header and menu bar submenu; the shared close/minimize duration is under **Adjust** on any built-in's page. Existing spring/mesh, glide, tilt, focus glow, drop ripple, maximize and resize controls remain on **Physics** unchanged.

## Complete original-effects list

The following tables enumerate all **47 originals**, with the exact category/submenu placement in `LibraryEffect.swift`. Preference values are `Settings` raw IDs, not Studio JSON effect IDs. Discovery IDs use `close:<CloseEffect.rawValue>`, `open:<WobbleEntrance.rawValue>`, `minimize:<DockMorphStyle.rawValue>`, `liquid` and `destruction`; those discovery prefixes do not replace the preference formats below.

### Original Close — Window Destruction

| Effect | Category | Submenu | Supported triggers | Preference / discovery value |
|---|---|---|---|---|
| Window Destruction | Destruction | Fragmentation | Close only | `destruction` |

`LibraryEffect.destruction` is a distinct built-in; `CloseEffectChoice.destruction` stores the raw value `destruction` in the global close choice or a per-app close rule. It is not a 31st shader, a Studio JSON layer, an entrance or a minimize morph. Select it from the menu bar's **Close** submenu, the library's **When a window closes** section with **Use when a window closes**, or **Per-App Close Effects** in Rules. **Off** is unchanged; **Random** still selects only among the 30 shaders, and **Fire** remains the default. Studio Close ownership keeps its existing precedence.

Window Destruction shares `UIObjectExtractor`, `ChaosScene`, `ChaosWorld.destroyWindow()` and `ChaosRenderer` with the screen saver, but uses transparent `oneShot` rendering: **no wallpaper, no restoring/rebuilding scene loop**. Glyphs and icons release over **0.02–0.22 normalized seconds**, shards over **0.4–1.15**. Gravity, bouncing and piling lead into fading with a **three-normalized-second piece lifetime**. The complete preview timeline is **six seconds at 1×**; release, simulation lifetime and timeline scale with the shared **0.25×–3×** duration multiplier.

Native playback has a floor at each display's full bottom edge, behind the Dock, and click-through overlays. Admission allows at most **two source captures including pending work**, each capped at **32,000,000 pixels / 16384 per dimension**; per-display extraction is bounded to **1200 glyphs, 160 other objects and 256 target tiles**. It keeps captures in memory, writes no images to disk, does not activate the screen saver and leaves the existing saver behavior/settings unchanged. Preview uses a local floor, makes no AX changes and leaves the real window untouched. The expensive-effects gate refuses playback instead of substituting an animation.

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

## Preview and use a built-in effect

Since v0.3.2, Liquid's final pool stays opaque and drains physically off the bottom edges. Outlets open gradually from the lower corners towards the center over six normalized seconds after the existing linger; completed material stops simulating only after its full rendering support has left the display. Melting, exposed-window collisions and behind-Dock layering are unchanged.

1. In **Effects**, open the section for the event (*When a window opens*, *When a window closes*, *When you minimize*) and select the effect, or pick it straight from the matching menu bar submenu (which applies it immediately).
2. The preview loops at once on the sample window; switch the source menu to a real eligible window to see it on your own content. Screen Recording and an enabled engine are required for real captures. The panel reports capture, permission, Metal and budget errors rather than displaying a fabricated demo.
3. Press **Use when a window closes**, **Use when a window opens** or **Use when you minimize**. Window Destruction offers Close only. Liquid has independent Close and Minimize buttons; activating one does not assign the other. The active one reads **Active when…** and offers **Turn off**.

Selecting, previewing or scrubbing never changes assignments. Under **Adjust**, close and minimize effects share the 0.25×–3× duration multiplier; entrances link to Physics. **More** links to Rules (per-app overrides, exclusions) and Performance.

## Real preview engines and safety boundaries

`OriginalEffectPreview` / `OriginalPreviewRenderer` render actual ScreenCaptureKit frames through the original paths:

| Original family | Preview path | Deliberate panel boundary |
|---|---|---|
| Close shaders | `CloseEffectRenderer` with the selected `CloseEffect` / `EffectScene` | No actual close; the capture is rendered offscreen. |
| Open entrances | `WobbleEntrance.apply` on `KinetiqModel`, stepped at 120 Hz | Original spring/mesh motion, not Studio Ripple/Wobbly substitution; no AX movement. |
| Minimize morphs | `DockMorphDeformer` | Local preview destination, **not the actual Dock**; no native minimize or Dock preference change from previewing. |
| Liquid | `LiquidWorld` with `LiquidEffectRenderer` | Retained local floor stage, **no actual desktop obstacles**; scrubbing covers the full geometry-dependent melt/pool/drain lifecycle, scaled by shared duration. |
| Window Destruction | `UIObjectExtractor` → `ChaosScene` → `ChaosWorld.destroyWindow()` → transparent `ChaosRenderer` in `oneShot` mode | Local floor and complete six-second timeline at 1×; no wallpaper, AX movement, actual close or screen saver activation. |

Previews never move, park, close or minimize a live window. Liquid's local stage is retained so falling/pooling fluid is not cropped to the now-empty source rectangle. It does not capture or simulate other desktop windows as obstacles. These panel boundaries do not change native playback: actual minimize still uses the real Dock path, and native Liquid still uses live window-top obstacles and per-display floors as described in the [README](../README.md#liquid-close-and-minimize-v0131).

### Bounded resources and cancellation

- Offscreen targets follow the current texture-scale budget and are capped at **8,000,000 pixels and 8192 pixels per dimension**.
- Each source capture is capped at **32,000,000 pixels and 16384 pixels per dimension**, including capture/shadow allocation checks. Real target eligibility and unchanged frame are checked around capture/render completion.
- At most **two preview requests are in flight** per renderer. New work invalidates stale generations; cancellation, hidden/closed detail panels and disabled effects prevent stale results from being displayed. Bounded simulation loops yield and check cancellation.
- The captured pixel buffer, IOSurface/CoreVideo mapping and `CVMetalTexture` backing remain retained through committed GPU command completion, even if the requesting task disappears or is superseded. Captures stay in memory, not Studio JSON or a new disk cache.
- Mesh/particle/texture budgets still apply. When `allowsExpensive` is false, **original close shader, Liquid and Window Destruction previews refuse playback**; there is no fallback to Glide or another misleading substitute. This preview rule does not redefine native engine lifecycle behavior.

## Native trigger lifecycle remains unchanged

Close observes actual window disappearance/fade after pre-capture; refused closes, tab closes, hiding and Space changes are not window-close animations. Original Open keeps the jelly entrance lifecycle after a new standard window stabilizes. Minimize intercepts the yellow button only; capture/setup failure replays the native click, and **⌘M / Dock minimization remain native**. Explicitly enabling native minimize continues to synchronize the Dock animation preference as before; merely opening or previewing an original does not.

## Verification status

**Current v0.3.3 / build 38:** final release suite passed **304 tests: 122 app + 36 Effects + 146 Core; 0 failures, 0 skips** (`/tmp/kinetiq-v033-acceptance.log`), with both UI and Destruction opt-in dumps. The real README capture-to-Metal contact sheet was visually inspected: text releases before shards, pieces pile up, the stage clears at six seconds at 1× and initial border clipping is correct. Real test-window snapshots are under `/tmp/kinetiq-v033-ui` and `/tmp/kinetiq-v033-destruction`, not sample-window illustrations or distributed artifacts. Normal playback remains memory-only; these disk images require test opt-in.

Final build exit 0 (`/tmp/kinetiq-v033-final-build.log`); app and embedded saver each verified universal x86_64/arm64 with `lipo` and `codesign --verify --deep --strict`. Packaged 0.3.3/build 38 launched from `build/Kinetiq.app` (PID 56054 at verification); Quick Look cache and Finder refreshed. [TODO 19](../TODO.md) is **Done**.

LLVM release **line** coverage (`/tmp/kinetiq-v033-coverage.txt`, not Regions): `DestructionEffectPlayer.swift` **95.95%**, `OriginalEffectPreview.swift` **92.49%**, `LibraryEffect.swift` **98.49%**, `ChaosWorld.swift` **99.20%**, `ChaosRenderer.swift` **88.86%**. This is not 100% coverage or Metal shader branch coverage, nor proof of every native failure path/display configuration. Local-floor preview remains capture-only; only native Close observes actual closure. Window Destruction adds no Studio layer/schema change or screen saver behavior change.

**Historical v0.3.2 / build 37:** **287 release tests: 146 Core + 36 Effects + 105 app; 0 failures, 0 skips**, including real-capture bottom-edge drainage and a completely empty final preview. Actual material remains opaque during partial drainage, and final particles have moved below the complete kernel-support margin. Universal app/saver signatures and launch were verified; Quick Look/Finder refreshed. Log: `/tmp/kinetiq-v032-acceptance-direct.log`; build: `/tmp/kinetiq-v032-final-build.log`. See the [README](../README.md#building) for historical line coverage and the preserved optical/runtime regression coverage.

**Historical v0.2.1 / build 34:** the final release suite passed **277 tests: 144 Core + 36 Effects + 97 app; 0 failures, 0 skips**. The app suite includes **11 Management + 7 OriginalEffectLibrary + 8 OriginalEffectPreview + 10 StudioUI + 61 other existing tests**. All 30 original shaders, six entrances, nine minimize morphs and Liquid passed genuine real-capture tests, including the README Liquid regression. All 65 effect navigation requests are routed and consumed, including repeated navigation, after fixing `@Published` reentrancy with `onChange(initial: true)`. Final log: `/tmp/kinetiq-v021-suite.log`; opt-in UI captures: `/tmp/kinetiq-v021-ui`.

Build script completed (`/tmp/kinetiq-v021-build.log`); both app and embedded `.saver` passed direct arm64/x86_64 `lipo` and strict signature checks. Actual packaged version **0.2.1 / build 34** was confirmed, the app launched and Quick Look/Finder refreshed. Native **Destruction → Dissolution → Fire — Original Close…** opened the exact original Fire detail; Accessibility inspection confirmed 65 effects and `/tmp/kinetiq-v021-fire.png` was visually inspected. This inspection did not activate an effect or change user assignments. [TODO R2](../TODO.md) and task 9 are **Done**.

Historical v0.2.1 merged release line coverage (`/tmp/kinetiq-v021-coverage.txt`): `LibraryEffect.swift` **100%**, `CatalogStore.swift` **100%**, `OriginalEffectPreview.swift` **85.32%**, `OriginalEffectDetailView.swift` **40.80%**. This is not Metal shader branch coverage. Historical v0.2.0 verification remains separately recorded in the [changelog](../CHANGELOG.md#020--build-33).