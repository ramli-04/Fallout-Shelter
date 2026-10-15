# Phase 3.5 ? city and impact overhaul

## Implemented

The existing Godot project was extended in place. The default city is 4500 ? 2700 simulation units (450 ? 270 Godot XZ units), 2.5 times the former dimensions. The Director offers 2?, 2.5? and 3? presets. Roads, sidewalks, parks, sparse outskirts and low-rise district palettes use procedural geometry, reused box meshes and MultiMesh facade/crosswalk batches. Police, fire, medical, bank and school buildings have recognizable colors/signs and service details. Their POI records drive initial location assignments; authority specializations retain the existing Authority role and individual personalities. Service and home spawns avoid buildings and reserved shelter plazas. S4 is relocated to [3240,1980], beside a rocky remote entrance; its other academic properties remain intact.

NavigationRegion3D and each NavigationAgent3D still support the authoritative fixed-clock road planner. The larger road mesh excludes building interiors. Camera bounds and overview scale with the map; pan, zoom, rotation, tilt, focus and following remain available. F/double-click follows a selected agent; pan or Home cancels following. Obstructing buildings become transparent, and selection rays can pass through their transparent facades. Windows have a distance cutoff and small geometry does not cast shadows. Director quality switches directional shadows.

VaultEntrance.tscn and VaultDoor.tscn are original procedural assets: a circular segmented metal door with gear teeth, hub and braces, recessed concrete frame and hydraulic columns. The separate plate rolls aside with a Tween. Six states are supported: OPEN, CLOSING, CLOSED, OPENING, JAMMED and DESTROYED. Existing BLOCKED incidents map to the JAMMED visual. Logical non-open states reject admission; ShelterState.set_door_state supports persistent explicit commands. Structural destruction cannot reopen through refresh. Public, metro, relay, mountain and experimental entrances retain distinct identification/features. An absent S5 creates no physical entrance.

The fictional blast model uses world-unit distance, configurable zone fractions and damage, severity, building resistance and shelter resistance/protection. Civilian structures are deliberately less resistant than bunkers. The default strike can flatten the city while bunkers generally survive; putting the center directly on a shelter can destroy it. Structure states are INTACT/DAMAGED/DESTROYED, independent of door states. Damaged shelters lose configurable capacity and supplies, jam their doors and inflict configured occupant injury. Destroyed shelters lose capacity/supplies, close admission, retain identifiable ruins and can kill occupants. Outside agents receive radial damage. Health, survival_status and evacuation_failed distinguish deaths, injuries and failed evacuation without discarding IDs, memories, histories or occupant records.

At the exact existing 300?600 second warning deadline, the manager applies gameplay damage once and signals presentation. A flash, expanding wave, five simple smoke meshes, dust, delayed building collapse, vegetation/street-furniture/vehicle removal and scorched ground create devastation. Terrain, shelter records/ruins, Director controls and surviving agents persist. Destroyed building/tree collisions are disabled. The connected road navigation mesh remains valid; no full-map bake or physics-fragment storm happens during the strike.

Preview animates temporary copies of buildings and the blast effect, restores original visibility, and never applies damage to real simulation records, collisions or navigation. Only one preview is retained. Starting the alarm, reset or a replacement preview safely clears it.

All five shelter definitions and S5's original dedicated 50% existence RNG remain. Existing rule policy, Llama bridge, memories, communication, incident system and AI metrics remain. Impact configuration and structural truth are absent from the allowlisted agent observation payload. Agents learn unavailable destinations only through existing observation/report pathways; Director preview does not change beliefs. Export trace now includes nuclear settings, POIs, structures, exposed objects and summary damage/death metrics. Each real impact also archives a deep snapshot of the complete experiment automatically under outputs/experiment_runs; JSON serialization and file writing run on a worker thread, and reset cannot mutate the archived snapshot. Worker failures are reported, completed workers are reaped on reset, and exit waits for outstanding writes.

## Try it

1. Open project.godot in Godot 4.7.2 and press F5. Open the bottom Settings gear while still in Preparation; scroll to NUCLEAR IMPACT CONTROLLER.
2. Select a map preset. Enter impact X/Y or enable Click map to select impact and click the city. Coordinates are simulation units; divide by 10 for Godot X/Z. The vertical IMPACT marker and optional concentric rings show the selection.
3. Set blast radius in **Godot world units**, and severity. Seeded random impact uses a dedicated seed + 3501 RNG stream. Reset impact returns to the current city's center. Manual coordinates/map selection turn off random impact.
4. Preview event / shelter damage plays the temporary visual and lists predicted shelter outcomes. Inspect a real shelter for its current state, resistance, door, occupancy, living occupants and remaining capacity. Configuration locks when simulation starts.
5. For a close-impact example: X=720, Y=360, radius=80, severity=1. Preview predicts S1 destruction and distant S4 survival. Start/resume the city, then use Launch nuclear alert. Use 10? speed if desired. The existing chance of a false alarm remains; false alarms produce no destruction.
6. Inspect S1 after the real impact and export the trace. Summary lists deaths/injuries and destroyed shelters separately from sheltered/exposed evacuation counts.
7. Reset the scenario with the bottom reset icon. Geometry, collisions, agents, supplies and shelter states are rebuilt. The current seed and impact configuration remain. Change the impact before the next start to compare locations against the same initial seed.
8. For broad city devastation, reset to center with the default radius=300, severity=1. The graphical capture test uses a radius=500 close to S1 to demonstrate widespread ruins.

resources/nuclear.json controls zone thresholds, damage, map scale, building resistance and health/supply/capacity consequences. resources/phase1.json controls each shelter's blast_resistance and terrain_protection. All values validate on load; preset changes use the same scenario seed.

## Validation commands

```powershell
$GodotExe = 'C:/Users/Moham/Downloads/godot/Godot_v4.7.2-stable_win64_console.exe'
& $GodotExe --headless --path . --script res://tests/test_phase35.gd
& $GodotExe --path . --script res://tests/render_phase35.gd
& $GodotExe --headless --path . --script res://tests/test_phase3.gd
.venv/Scripts/python.exe -m tests.run_phase3_http --godot $GodotExe
.venv/Scripts/python.exe -m tests.run_phase3_http --godot $GodotExe --script res://tests/test_population_ai.gd --inference-delay 0.01
.venv/Scripts/python.exe -m unittest discover -s tests -p 'test_*.py'
```

For live inference, start the services using [Docker Compose](DOCKER.md), then run tests/test_phase31_real.gd. A real llama3.2:1b inference was executed successfully during this work: A001 returned MOVE_TO_SHELTER targeting S4, and Godot applied MOVING. Transport fixtures are explicitly TEST_ONLY and do not replace the production provider.

## Limits

The city is a stylized procedural grid with simple placeholders; assets/models was absent. There is no automatic GLB discovery or imported art in this change. School/playground, emergency vehicles and service roles are simplified, with no traffic, dispatch, school schedules or medical-treatment subsystem. POIs supply actual initial assignments and exported identities; the existing LLM action contract still targets shelters rather than general POI destinations. Ordinary home locations are clear neighborhood sidewalk slots, not simulated interiors.

The blast model is fictional, piecewise and deterministic, not a real nuclear-effects predictor. Damage is resolved atomically at impact; the visuals then spread outward. Rubble is flattened/tilted geometry rather than fractured meshes; there is no detailed terrain deformation, fire propagation or thousands of fragments. Protected shelter structures do not automatically survive close strikes. Occupant risks use configurable deterministic health deductions, not newly sampled casualty probabilities.

The simulation still ends at impact/all-clear. Ten-day rationing, door reopening at day ten, post-impact roaming and post-impact S3 broadcast scheduling are not implemented. Damage, supplies, doors and occupant records are retained for that future phase. The connected road corridors remain navigable after destruction; former building interiors are not newly baked as walkable terrain. NavigationAgent3D supports/validates the fixed-clock routes rather than replacing authoritative simulation motion with physics/RVO.

Rendered captures were visually inspected on the RTX 5070 Ti Laptop GPU; the graphical harness exercised actual scenes and UI. No separate human interactive walkthrough, sustained FPS benchmark or simultaneous 150-agent real-inference throughput benchmark is claimed. Real inference is serialized by the existing service/bridge, and tiny-model output remains nondeterministic even when the physical scenario is seeded. Exact replay checks use the rule policy.
