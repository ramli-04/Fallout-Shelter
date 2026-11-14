# Rendering Architecture and Asset Integration

Godot renders the city while the existing simulation remains authoritative for agent positions, traffic, routes, vehicle state, collisions, and world geography. Rendering nodes observe those records; they do not move simulation actors or add a second vehicle-physics system.

## Character rig and animation

`scenes/three_d/agent.tscn` uses `scripts/three_d/agent_3d.gd`. Each visible person gets the same named `Skeleton3D` pivot layout (`Root`, `Torso`, `Head`, `ArmLeft`, `ArmRight`, `LegLeft`, `LegRight`) and bone attachments for the procedural low-poly parts. `character_animations.gd` builds one shared `AnimationLibrary` and state-machine graph. Every character owns its `AnimationTree` playback state, so playing an animation for one NPC cannot change another's state.

The shared clip set includes idle, walk, run, sprint, limp, injured, panic, look around, fight, fall, get up, interaction, and shelter entry/exit. The existing agent state is mapped into this presentation layer; it does not change decisions or navigation. Role, clothing, hair, and skin variations remain visual-only.

Animation processing is manual and distance-based. `resources/render_streaming.json` controls the full-rate distance (42 m), medium distance (125 m), medium interval (0.10 s), and distant interval (0.30 s). Hidden/pooled avatars do not advance their animation tree. The F10 metrics overlay shows full, medium, and distant avatar counts.

## Vehicles

`scripts/three_d/vehicle_3d.gd` builds sedan, SUV, pickup, van, truck, minibus, police, ambulance, and fire/rescue silhouettes from shared primitive meshes. Four tires and four hubs are grouped into two per-vehicle `MultiMesh` submissions; wheel transforms still rotate from simulation speed and steer the front pair from the simulation value. Headlights, brake/reverse lamps, response sirens, damage tinting, and wreck smoke/fire read fields from the vehicle record.

The vehicle's `Node3D` is visual only. `vehicle_runtime.gd`, `vehicle_collisions.gd`, and the traffic layer still determine movement, collision, wreck state, and road obstruction. No collision is disabled or repositioned to make visual vehicles fit.

Emergency light bars are present on responder models. They flash only when the vehicle record sets `siren_active` or `emergency_response`; a police or ambulance vehicle does not claim an active response by default. Wreck particles are instantiated lazily for a crashed vehicle with health below 78, and fire is shown below 18 health or after destruction.

## Geometry, materials, and environment

`scripts/three_d/geometry.gd` caches generated box/cylinder/sphere/ring meshes and immutable primitive materials. `Geometry.shared_material()` is read-only by convention. For a material that changes over time, use `Geometry.material()` or call `Geometry.make_material_unique()` before editing a shared material. Mutable cone/roof meshes call `make_mesh_unique()` before changing their dimensions.

Buildings keep real 3D footprints, facades, roofs, windows, interior cutaways, and collision. A generated 128×128 repeating stone tile adds a small mipmapped facade texture, while batched windows and streamed chunks keep static geometry bounded. The asset audit documents that the repository contains no imported building/road model or texture pack to preserve or optimize.

## Importing optional authored models

1. Put source assets in a category folder under `assets/models/` and keep the editable source beside exported `.glb` files.
2. Use meter-scale authoring. The simulation stores planar map positions in tenths of a meter; render conversion remains in `world_coordinates.gd`.
3. Vehicle local length points along local `+Z` in the procedural renderer. Rotate imported models in their wrapper scene if their authored forward axis differs.
4. Prefer one shared skeleton and compatible bone names for human variants. Import shared idle/locomotion clips once and add them to the character animation library; keep per-agent playback parameters local.
5. Reuse material resources. Use mipmaps on world textures and VRAM compression only when the selected GL Compatibility target supports the chosen format. Keep icon SVG imports at their small native dimensions.
6. Keep physical collision shapes and navigation out of decorative imported meshes. Do not replace road graph data, building footprints, doors, or shelter access with model bounds.
7. Check the remote-visibility and animation LOD in the benchmark scene before increasing texture size, mesh detail, or animation rate.

## Verification

Run the presentation regression suite with:

```powershell
& 'C:\Users\Moham\Downloads\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/test_rendering_architecture.gd
& 'C:\Users\Moham\Downloads\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/test_visual_streaming.gd
```

Use `tests/benchmark_visual_streaming.gd` with a label other than `baseline` to load `outputs/streaming/baseline-world.json` and capture a renderer-specific sample. Headless runs cannot report desktop GPU draw/video-memory counters and should not be compared to desktop runs.

Use `tests/benchmark_render_population.gd -- <count>` for a rendering-only population sample from 1 to 1,000. The count scales synthetic display records around the same city; it leaves the authoritative simulation population at 100 and does not benchmark AI or traffic simulation. See `docs/RENDERING_PERFORMANCE.md` for the recorded population matrix and its limits.
