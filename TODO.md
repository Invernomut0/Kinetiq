# TODO

Statuses: To Do, Doing, Review, Done. Owner: Lorenzo (requests) / Copilot (implementation).

| # | Task | Status | Notes |
|---|------|--------|-------|
| 1 | Open effects (close shaders reversed when a window appears) | Review | v0.1.9. Window is parked, captured once painted, effect plays, window restored near the end. Not yet verified on screen. |
| 2 | Inertia and bounce off the screen edges after releasing a drag | Review | v0.1.10. `KinetiqModel.fling`, unit-tested physics; release velocity from the last 0.1 s of cursor samples. Not yet verified on screen. |
| 3 | 3D tilt while dragging | To Do | Perspective projection in the mesh renderer, driven by drag velocity. |
| 4 | Minimize effect | To Do | Detect minimize before macOS animates it. |
| 5 | Per-app close effects | To Do | Reuse the exclusion list infrastructure in Setup. |
| 6 | Focus highlight (pulse / glow on the window that gets focus) | To Do | |
| 7 | Ripple at the drop point | To Do | |

## Done

- Rename to Kinetiq, Setup window, app exclusions (v0.1.4 - v0.1.8).
