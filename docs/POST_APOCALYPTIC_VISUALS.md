# Phase 2 — post-apocalyptic isometric presentation

Implemented on the existing Godot renderer, 2026-11-11. Simulation managers, population generation, road geometry, decision rules, AI, shelter admissions, and save/replay formats are unchanged in this phase. The active population remains 100 people (65 civilians / 35 authorities).

## Visual components

- Existing orthographic camera retains 45° yaw and 35.264° elevation. Focus now preserves the selected object's elevation; manual panning follows terrain height.
- `building_weathering.gd` adds deterministic stains, timber and rooftop debris to rectangular perimeter buildings. Its private RNG never consumes simulation RNG. Three MultiMesh groups replace per-piece nodes.
- `building_3d.gd` uses an earth/oxidized-metal palette, irregular dark upper windows and boarded panes. Ground-floor entrances stay open. Cornices and floor bands are batched; redundant underlying window geometry is omitted for street-facade buildings. Weathering follows interior cutaway visibility.
- `ruin_landmark.tscn` / `ruin_landmark.gd` supplies reusable abandoned shells, rubble, exposed reinforcement and old industrial stacks. Nine instances sit outside the playable boundary; they have no actors or collision bodies. Scenic decay does not mark occupied simulation buildings as abandoned or destroyed. Impact destruction remains driven by the existing blast model.
- Existing irregular streets, lane widths, junction surfaces, highway/ramp profiles, streetlights, signs, signal controllers, trees and distant hills are retained. Lighting, earth, pavement and curb colors are adjusted for a dusty, desaturated setting.
- `social_world.gd` adds emergency stripes, medical markings and civilian body wear to existing vehicles. Hidden debug captions no longer rebuild their text each frame. No display-only cars or pedestrians are spawned.

No GLB, GLTF or OBJ assets were present in the workspace. This implementation uses reusable procedural components and existing scenes, without downloading external assets.

## Shelters

S1–S5 keep their records, positions, capacities, availability and admission rules. Existing separate door scenes and state-driven animations remain in use.

| Shelter | Visual identity |
|---|---|
| S1 | Public refuge, paired approach signs |
| S2 | Metro access canopy and transit sign |
| S3 | Communications mast with dish |
| S4 | Rock-cut vault and civil-defense side booth |
| S5 | Experimental rock-cut vault with ventilation towers |

Mountain vaults and rock shoulders are arranged behind their existing admission threshold, facing the positive-Z foreground of the fixed camera. Urban floor entrances retain their ground-level approaches. Identity fixtures are placed to the sides rather than at the admission point. No missing shelter is made visible merely for presentation.

## Visibility and animation

`isometric_visibility.gd` projects each visible agent or shelter into the camera viewport, then casts from `project_ray_origin()` to its world position. This fixes off-center orthographic sightlines. Up to eight collider layers are checked per target, every 0.3 seconds. Offscreen targets are skipped. Queries use the rendered SubViewport's own world.

Buildings cache all nested facade materials and change transparency only when obstruction state changes. Roofs, facade batches and weathering fade together and restore full opacity when the sightline clears. Collision layers are unaffected by transparency.

The existing agent animation code continues to observe authoritative walking/running, conversation, helping, emergency, shelter-activity and death states. A public `animation_state` exposes the current presentation state. Enter/exit poses last 0.45 simulation seconds after a real `riding` transition, then passengers hide. First display of an already seated passenger does not invent a boarding event. No pose changes movement, passenger membership or decision state.

Controls remain: WASD/arrows or right/middle drag to pan, wheel zoom, F to follow, I for existing interior cutaway, F8 for road debugging.

## Validation

Godot 4.7.2, GL Compatibility, Windows, NVIDIA GeForce RTX 5070 Ti Laptop GPU.

| Check | Result |
|---|---|
| `tests/test_phase2_visuals.gd` | 21 checks passed: off-center parallel rays, two overlapping nested buildings, viewport isolation, fade restoration, batches, population, passenger transitions, elevated focus, shelter fixtures |
| `tests/test_isometric_camera.gd` | Passed: projection, fixed angle, zoom and pan |
| `tests/test_phase5_ui.gd` | 6 startup/UI checks passed |
| `tests/test_city_navigation.gd` | 97 checks passed, including shelter reachability and closure updates |
| `tests/test_phase62.gd` | 1,415 vehicle checks passed |
| `tests/test_phase62_world.gd` | Completed full scene with 53 vehicles; 0.05-second step CPU p50 3.51 ms / p95 83.88 ms during concurrent validation |
| `tests/render_post_apocalyptic.gd` | Captured and inspected district, city, outskirts and all five shelters; outputs under `outputs/phase2/` |

Final graphical capture sampled 30 frames per view after warm-up at a 1440×1000 window (world image 1296×900), with the initialized population present and simulation paused. Mean frame intervals were 16.66–17.80 ms; district 1,037 draw calls, city overview 7,269, shelter views 323–969. These are short, vsync-influenced presentation samples, not sustained live-AI or low-end hardware benchmarks. The full-scene simulation's p95 spikes remain a separate optimization concern.

Existing ObjectDB/resource teardown warnings remain. The audit's separate issue in `vehicle_runtime.physics_query()`—root-world queries while rendered colliders live in an independent viewport—is not redesigned here. The new isolation test makes that separation explicit; passing planar vehicle and navigation tests does not establish parity between those two worlds. Resolve that simulation boundary with dedicated tests before relying on rendered scenery as authoritative vehicle collision geometry.

## Reproduction

Use your Godot executable in place of `godot`:

```powershell
godot --headless --path . --script tests/test_phase2_visuals.gd
godot --headless --path . --script tests/test_isometric_camera.gd
godot --headless --path . --script tests/test_city_navigation.gd
godot --headless --path . --script tests/test_phase62.gd
godot --path . --script tests/render_post_apocalyptic.gd --resolution 1440x1000
./tools/graphify.ps1 build
```

The older `tests/render_phase2.gd` preparation/evacuation/impact capture remains intact. New screenshots are ignored outputs, not committed source assets.
