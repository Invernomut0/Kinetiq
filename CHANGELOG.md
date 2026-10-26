# Changelog

All notable changes to Kinetiq are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
