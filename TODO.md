# TODO

Statuses: To Do, Doing, Review, Done. Owner: Lorenzo (requests) / Copilot (implementation).

| # | Task | Status | Notes |
|---|------|--------|-------|
| 1 | Open effects (close shaders reversed when a window appears) | Review | v0.1.9. Window is parked, captured once painted, effect plays, window restored near the end. Not yet verified on screen. |
| 2 | Inertia and bounce off the screen edges after releasing a drag | Review | v0.1.10. `KinetiqModel.fling`, unit-tested physics; release velocity from the last 0.1 s of cursor samples. Not yet verified on screen. |
| 3 | 3D tilt while dragging | Review | v0.1.11. `Tilt` in KinetiqCore (unit-tested); mesh vertices are projected on the CPU around the window center. Not yet verified on screen. |
| 4 | Minimize effect | Review | v0.1.12. Yellow button only (⌘M and Dock clicks can't be intercepted without reading keystrokes): click held back, window parked + minimized, effect plays, position restored. Not yet verified on screen. |
| 5 | Per-app close effects | Review | v0.1.13. `Settings.appCloseEffects`, picker per app in Setup; overrides the global Close effect (also when that is Off). |
| 6 | Focus highlight (pulse / glow on the window that gets focus) | Review | v0.1.14. Accent-colored glow (Core Animation overlay, no capture) on app activation and focused-window changes; off by default. Dimming of the other windows not done. |
| 7 | Ripple at the drop point | Review | v0.1.15. Radial wave in `KinetiqModel` (unit-tested); settling waits for it to finish; off by default. |

| 8 | Screen saver: the desktop falls apart (letters, exploding buttons, triangular window pieces, pile at the bottom) | Review | v0.1.23. `ChaosWorld` in KinetiqCore (unit-tested), Metal renderer, Setup section. Verified on screen through frame dumps (`KINETIQ_CHAOS_DUMP`); the idle start was not waited for. |

## Done

- Native management dashboard with eight sidebar destinations, real window inventory, permission and engine diagnostics, and isolated UI/settings tests — Owner: Copilot. Done in v0.1.28: all 98 tests passed (7 new management tests); universal app built, signed and launched; dashboard inspected on screen.
- Rename to Kinetiq, Setup window, app exclusions (v0.1.4 - v0.1.8).
