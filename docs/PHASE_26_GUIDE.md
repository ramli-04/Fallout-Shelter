# ESSAIM Phase 2.6: 3D city and Director camera

Open the **existing** `project.godot` in Godot 4 and press **F5**. No new project,
manual scene wiring, navigation baking, plugins or downloaded assets are needed.
The entry scene is still `scenes/main.tscn`. Tested with the installed
**Godot 4.7.2 stable**, using its OpenGL Compatibility renderer.

## Start and inspect

1. Click **Start simulation** to run the city without an alarm.
2. Click **Launch nuke** to sound the siren and begin evacuation. The Director
   sees the real/false alarm state and countdown. Agents continue to use their
   own incomplete beliefs and independent urgency estimates.
3. Click a visible bean to select it. A ground ring and ID identify the selection,
   and the right-hand inspector shows its role, personality, traits, objective,
   beliefs, memories, rumors and decision explanation. Scroll for the full record.
4. Click a shelter structure or its sidebar card for capacity, occupancy, stock,
   maintenance, door state and recent incidents. Each existing entrance has an ID
   and status indicator. S2 has a metro entrance; S3 has communications equipment.
5. Admitted agents disappear outdoors. Their simulation records remain active;
   use the inspector's **agent picker** to inspect them inside their shelters.
6. Choose **10x** to accelerate evacuation. Pause freezes the simulation while
   the camera remains available. Real impact produces the existing outcome summary,
   a short 3D shockwave/flash and a screen flash. False alarm produces **ALL CLEAR**
   without an impact. Nuclear effects do not remove buildings or navigation.

The latest prompt makes **Director the only viewing mode**. The previous Observer
selector is intentionally removed. Inspection, focusing and camera controls do not
control agent movement or give agents Director knowledge.

## Camera controls

Move the pointer into the city view. Click it to give keyboard focus.

| Input | Action |
| --- | --- |
| WASD / arrow keys | Pan horizontally relative to the camera's direction |
| Mouse wheel | Smooth zoom toward/away from the camera focus |
| Middle mouse drag | Pan the focus across the ground |
| Right mouse drag horizontally | Orbit around the focus |
| Right mouse drag vertically | Adjust the downward tilt within limits |
| Double-click a visible agent | Center on that agent |
| F, with city keyboard focus | Center on the selected agent, including an indoor agent |
| Home / Home-overview button | Restore the initial elevated diagonal overview |

The default perspective view has **45° yaw and 45° downward tilt**. Camera
movement, orbit and zoom interpolate smoothly. The focus stays within the city;
the camera can orbit outside the footprint to see its edges. Focusing is a
one-time centering action, not continuous following. Buildings can occlude agents:
orbit to see them or use the agent picker. Clicking an opaque building does not
select an agent through it. Empty-space clicks clear selection.

Keyboard motion is gated by city hover and UI focus; typing in the seed field or
scrolling the inspector does not move/zoom the camera. Leaving the viewport or
losing window focus cancels a drag.

## Preserved Phase 2.5 systems

The controller, rule-based decisions, beliefs, personalities, rumor system,
environmental event scheduler, shelter state/admission, fixed clock and seeded
configuration were **not rewritten**. Existing Start/Launch, Pause/Resume, speeds,
Reset same scenario, New random simulation, chosen seeds, forced False alarm,
event logs, population totals and JSON trace export remain available.

S5 still has one seeded 50% existence draw at scenario initialization. If absent,
there is **no 3D shelter, selection area, doorway or entrance destination node**
at its location. Its record remains inspectable in the Director sidebar, and
agents can still travel to the rumored location and discover absence locally.
On the tested engine, **seed 2** is a convenient absent-S5 example; **seed 42**
has S5 present. World state never comes from visual nodes.

All fifteen archetypes, numeric traits, bounded memories, local messages, S3's
deposited-observation relay, temporary shelter/door/road incidents, crowd reactions
and rat consequences remain governed by the same simulation modules. Event
markers now appear in 3D; their creation does not create or clear actual events.
Real and false alarms preserve the original clock and admission rules.

## Coordinates and navigation

`world_coordinates.gd` defines one reversible mapping:

```text
simulation Vector2(x, y) -> world Vector3(x × 0.1, 0.18, y × 0.1)
```

The second simulation coordinate becomes world **Z**; world **Y** is height.
The preserved 1800×1080 layout becomes a 180×108 3D footprint. Existing speeds,
distances, beliefs, ETAs and decisions remain in simulation units. This scale is
a visual convention, not a calibrated real-world evacuation speed model.

The city derives all 57 building footprints, 18 streets and three parks from the
existing `city_map.gd` layout. Roads have connected intersections and sidewalks.
West residences, the civic gardens and the east district differ in material and
building height. Buildings and tree trunks have static collision shapes.

A `NavigationRegion3D` owns an authored, connected `NavigationMesh` generated from
the same road grid. Its non-overlapping polygons cover road/sidewalk center paths
and exclude building blocks with bean clearance. No runtime bake or editor Bake
button is required. Each 3D agent has a `NavigationAgent3D` maintaining a reachable
path to its current authoritative road waypoint.

**Movement deliberately keeps the existing deterministic road planner and fixed
clock.** Avatars render its positions on XZ, rotate toward motion and bob lightly
while moving. Godot navigation queries validate reachability and maintain the
3D path representation; they do not advance an agent a second time, replace the
chosen road route, change ETA scoring or feed physics timing into cognition.
This prevents the visualization migration from changing academic experiment
results. Crowd collision/RVO and physical pushing are not introduced.

Navigation and collision are separate in Godot; static collision shapes alone
do not remove walkable polygons. Here, building exclusion is explicit in the
navigation geometry. See the official [navigation mesh documentation](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationmeshes.html)
and [NavigationAgent3D reference](https://docs.godotengine.org/en/stable/classes/class_navigationagent3d.html).

Shelter structures keep the road junction open. Their colored threshold at the
model's destination is the designated admission point; the canopy and metro steps
are an illustrative entrance behind it. No walkable shelter interiors are modeled.
Only the existing admission function changes occupancy or sheltered status.

## Files created and modified

| New files | Purpose |
| --- | --- |
| `scenes/three_d/city.tscn` | Reusable primitive city |
| `scenes/three_d/camera_rig.tscn` | CameraRig → Pivot → Camera3D hierarchy |
| `scenes/three_d/building.tscn`, `agent.tscn`, `shelter.tscn` | Reusable 3D entity scenes |
| `scripts/map_view_3d.gd` | Isolated 3D viewport, entity binding, input routing, raycasting and selection |
| `scripts/three_d/world_coordinates.gd` | Planar/XZ conversion |
| `scripts/three_d/geometry.gd` | Primitive geometry/material helpers |
| `scripts/three_d/city_3d.gd`, `building_3d.gd` | Streets, sidewalks, neighborhoods, parks, buildings and lighting |
| `scripts/three_d/road_navigation_3d.gd` | Connected navigation surface, queries and optional debug overlay |
| `scripts/three_d/director_camera.gd` | Independent bounded camera controller and config validation |
| `scripts/three_d/agent_3d.gd`, `shelter_3d.gd` | Read-only visual entities and selection/collision areas |
| `scripts/three_d/environment_markers_3d.gd`, `impact_3d.gd` | Lightweight incident and nuclear effects |
| `resources/visual_3d.json` | Adjustable camera and visual settings |
| `tests/test_phase26.gd`, `render_phase26.gd` | 3D engine tests and real viewport captures |
| `docs/PHASE_26_GUIDE.md` | This beginner guide |

Modified: `scripts/main.gd` switches the HUD to 3D/Director-only, preserves controls,
adds the indoor agent picker and warning banner, and fixes inspector scrolling.
`scripts/object_inspector.gd` formats shelter incident history readably. Phase 1
and 2.5 tests and Phase 2/2.5 capture helpers were adapted to 3D selection and the
intentional removal of the Observer selector. README and historical guide pointers
were updated. Godot-generated `.gd.uid` files accompany new scripts.

The original 2D agent/shelter scenes and visual scripts are retained for reference.
`scenes/main.tscn`, `project.godot`, simulation modules and both simulation JSON
files retain their existing responsibilities. Earlier Python scaffolding remains
unused by the Godot game.

## Configuration and laptop use

Stop the game, edit `resources/visual_3d.json`, then press F5 again. Camera defaults:
movement speed **36**, zoom sensitivity **0.12**, smoothing **9**, distance
**16–260**, overview distance **145**, tilt **30–70°**, FOV **50°**, focus bounds
**(0,0)–(180,108)**. Rotation/tilt sensitivities are also editable. Set
`shadows_enabled` to `false` if needed. Set `navigation_debug` to `true` to overlay
the connected walkable surface. Neither setting consumes simulation RNG values.

Geometry uses low-detail capsules/boxes/cylinders, one directional light,
MultiMesh facade windows and crosswalk stripes, and simple bounded effects.
No particles, destruction physics, external artwork or character animation rigs
are required. Population starts at 20; the existing spawn/configuration limits
still apply. Increasing population substantially needs more spawn slots and
communication/physics/render profiling. This delivery does not promise a target
frame rate on other hardware.

Shelter positions/capacities, probabilities and cognitive assumptions remain in
`phase1.json` and `living_world.json`; the historical Phase 2.5 guide documents
them. Moving building footprints or adding arbitrary obstacles requires updating
the shared city layout and navigation geometry, rather than only adding a mesh.

## Executed validation

```powershell
Set-Location 'C:\Users\Moham\OneDrive\Desktop\ESSAIM'
$GodotExe = 'C:\Users\Moham\Downloads\godot\Godot_v4.7.2-stable_win64_console.exe'
& $GodotExe --headless --path . --editor --quit
& $GodotExe --headless --path . --script res://tests/test_phase1.gd
& $GodotExe --headless --path . --script res://tests/test_phase2.gd
& $GodotExe --headless --path . --script res://tests/test_phase25.gd
& $GodotExe --headless --path . --script res://tests/test_phase26.gd
& $GodotExe --path . --script res://tests/render_phase26.gd
```

Actual Godot test results: Phase 1 **1436 checks**, Phase 2 **253**, Phase 2.5
**1093**, Phase 2.6 **427**, each with **zero failures**. The 3D suite checks:

- Perspective camera, smooth input, zoom/tilt/focus bounds, mouse drags, F/Home,
  actual raycast selection and UI input isolation.
- Connected Godot paths from every spawn to every existing entrance, sampled
  building clearance, and compatibility of all preserved routes with the 3D mesh.
- Identical seeded initialization and full evacuation state/event histories when
  compared with an independent headless controller, despite camera and selection.
- Admission/hiding, continued indoor inspection, reset, false alarms, impact
  effects, retained navigation and absent-S5 behavior/partial agent knowledge.

All **41 GDScript files** passed Godot `--check-only`. Headless editor import,
scene references and the normal project launch also passed without logged errors.

Graphical QA ran on the laptop's **NVIDIA GeForce RTX 5070 Ti** through OpenGL.
Actual captures in ignored `outputs/` cover overview, close-up bean selection,
evacuation, orbit, a naturally scheduled incident, impact, all-clear, absent S5,
the connected navigation debug overlay
and a 1024×720 window. No other platform/Godot version or large-population benchmark
has been tested. Check console output as well as exit codes: import commands may
exit zero after a logged script error.

During development, an unsupported navigation debug property, missing collider
metadata lookup, an outdated 2D test expectation, inspector scroll timing,
debug-overlay face culling and overbright lighting were corrected. Navigation
registration is asynchronous: the new test waits for a real entrance path before
checking all routes, so concurrent test execution does not race map registration.
Seed 0 was found unsuitable for the absent-S5
example and replaced with the verified seed 2. Final checks found no outstanding
GDScript/runtime errors.

## Manual checks

1. F5: verify raised buildings, roads, trees, colored beans and the diagonal view.
2. Pan, zoom and drag to orbit/tilt. Double-click a bean, press F, then Home.
   Type a seed or scroll the inspector and verify the camera stays put.
3. Start, Launch, select 10x, and inspect a moving agent's beliefs and memories.
   Pause; move the camera; verify agents and the countdown remain frozen.
4. Watch admission: the avatar disappears, occupancy rises, and the agent picker
   still displays its sheltered record. Reset and replay with the same launch time.
5. Choose seed **2** and Use seed. S5's sidebar record says absent and there is no
   physical S5 entrance, while initial agent beliefs remain uncertain.
6. Press **False alarm** after reset: siren and evacuation occur, followed by
   all-clear without nuclear effects. Reset, Launch normally and inspect impact.
7. For a reliable incident demonstration, temporarily set one probability to
   **1.0** in `living_world.json`, restart with F5, then Start/Launch/10x. It begins
   at its scheduled time, not immediately. Restore the original probability.

No additional manual steps in Godot are required. This phase provides a genuine
3D foundation while preserving the intelligence architecture. Ten-day survival,
LLMs/Ollama/free APIs, Python decision services and Kafka remain future work.
**Phase 3 has not started.**
