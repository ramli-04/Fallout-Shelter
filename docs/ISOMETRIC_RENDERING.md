# Isometric rendering, phase 1 and 2

The completed visual redesign and current validation are documented in
[Post-apocalyptic visuals](POST_APOCALYPTIC_VISUALS.md). The notes below describe
the earlier camera conversion.

## Existing architecture

The simulation remains authoritative in continuous 2D map coordinates. `city_map.gd`
owns the seeded geography, routes and collision/pathfinding inputs. The visual adapter
in `three_d/world_coordinates.gd` maps simulation XY to the XZ ground plane and
preserves the simulation's elevation. `map_view_3d.gd` creates the 3D city and entity
views from simulation records; its raycasts handle selection and impact placement.
`three_d/director_camera.gd` is the camera-only boundary for focus, panning, zoom and
follow. The simulation and navigation do not read camera transforms.

## Camera transformation

The director camera now uses orthographic projection at a fixed 45 degree yaw and
35.264 degree elevation. The existing smoothed focus/pan behavior and selected-agent
follow remain in place. Wheel zoom changes orthographic view size, and pointer-drag
pan uses the orthographic world-units-per-pixel scale. Right and middle drag pan;
camera rotation is disabled so roads and buildings keep a stable isometric basis.
Camera raycasts remain the picking interface, so impact selection and entity
selection retain their world-coordinate conversions.

## Files changed for this rendering phase

- `resources/visual_3d.json` defines the fixed isometric yaw and pitch.
- `scenes/three_d/camera_rig.tscn` declares the orthographic camera projection.
- `scripts/three_d/director_camera.gd` configures orthographic projection and size-based zoom/pan.
- `scripts/map_view_3d.gd` maps right-drag input to pan.
- `scripts/main.gd` updates the camera control hint.
- `tests/test_isometric_camera.gd` covers the projection, fixed angle, zoom and pan.

## Validation limits

`visual_3d.json` parses, `git diff --check` passes, and the project Graphify build
completes. Godot 4.7.2 was located in the user's Downloads/godot directory.
The headless isometric camera test passes, and the Phase 5 UI test passes all six
checks, including starting the simulation. The UI test reports resource cleanup
warnings at exit. Interactive visual inspection remains pending.
