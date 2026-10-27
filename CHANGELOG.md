# Changelog

All notable changes to Kinetiq are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
