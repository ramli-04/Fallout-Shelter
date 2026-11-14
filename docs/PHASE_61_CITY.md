# Phase 6.1 — Procedural City 2.0

The local checkout was inspected before editing; its origin is
`https://github.com/ramli-04/Fallout-Shelter.git`. This phase replaces the world
generator and road meshes while retaining the Phase 5 social simulation,
existing shelter admission, alarms, nuclear damage, and Director camera.

## Run and configure

Install the existing local geometry dependencies if needed:

```powershell
.\.venv\Scripts\python.exe -m pip install -r ai_service/requirements.txt
```

Run `project.godot` with Godot 4.7.2, as in the main README. Local Python is used
before the simulation starts for generation and triangulation; the AI backend
does not need to be available to generate the city or use rule agents.

Open the gear **Settings → Procedural City / Phase 6.1** before starting:

- **Map seed** and **Apply settings / same seed** reproduce a layout.
- **Regenerate map / new seed** chooses a new seed and resets the scenario.
- **Area multiplier** accepts 1–3, relative to the previous 675 × 405 m city.
  Default 2 produces 954.594 × 572.756 m: 546,750 m² instead of 273,375 m².
  Each dimension grows by √2; metres and agent speeds retain their scale.
- **Road width multiplier** accepts 0.75–1.5. The default is 1.
- **Show city districts**, **Navigation graph / F8**, and **Parking occupancy**
  reveal Director overlays. **Focus Alder Court** frames the neighbourhood.
- Generation settings lock after leaving Preparation, including when paused.
  Reset the scenario to configure another map. Overlays remain available.

Defaults live in `resources/city_generation.json`. Terrain cell size is 40
simulation units / 4 m and accepts 20–40. The existing nuclear map-scale field
remains a base-dimension setting for saved configurations; the duplicate old
map-size picker was removed from the nuclear controls. The new area control is
the normal way to resize this city. Impact selection clamps to regenerated bounds.

## Generation and validation

`ai_service/city_generator.py` creates staggered, curved streets, diagonal
connections, seeded district centres, five shelter approaches, public buildings,
parking reservations, house parcels, and a raised highway with two real ramps.
It uses its own seeded RNG. Same seed, dimensions, widths, vehicle demand and
generator version produce the same layout, including parking identifiers.

Ground centreline intersections are snapped to millimetre simulation precision
and noded with Shapely **before** graph construction. Every crossing becomes a
shared endpoint. Disconnected ground components receive visible connecting
roads; there are no invisible connectivity shortcuts. The raised highway has
separate graph nodes at crossings and connects through its explicit ramps.

`CityMap` loads those edges into the existing `RoadGraph` A*. Routing costs are
recomputed from sampled planar spline lengths. Traffic, road rendering and
debug views use those same edge records. Pedestrian free-space A* and Godot's
3D navigation mesh derive their obstacles and elevations from this shared map;
pedestrians retain the existing ability to cross clear ground.

Generation is rejected before a simulation can start if validation fails. Checks
include graph connectivity, exact graph/geometry endpoints, self-intersections,
unnoded ground crossings, building and sidewalk clearance, reserved shelter
approaches, parking containment and overlap, unique bay IDs, and cul-de-sac
housing. Godot additionally verifies obstacle-aware pedestrian access to all
five shelter sites. Shelters S1–S5 retain their identities and gameplay settings,
including S5's existing 50% existence probability.

The Director displays recalculated centre-to-shelter walking and driving
distances, with reference travel times at 1.4 m/s and 9.5 m/s. These are route
estimates: individual speeds, boarding, roadblocks and congestion affect actual
arrival times. The simulation spends its existing movement-time budget along
the new paths; warning durations remain the configured 300–600 seconds.

## Road surfaces, terrain and districts

Default street cross-sections are:

| Class | Asphalt width | Traffic lanes |
|---|---:|---:|
| Residential | 7 m | 2 |
| Alder Court / mountain access | 6.5 m | 2 |
| Arterial | 10 m, including shoulders | 2 |
| Boulevard | 14 m | 4 |
| Highway | 21 m | 6 |
| Highway ramp | 7.5 m | 2 |

Urban sidewalks extend 2 m beyond each road edge, with 20 cm curb strips.
Mountain approaches have 1.2 m shoulders/sidewalks. Markings follow sampled
curves, stop inside junction mouths, and include crossing stripes. Junction
aprons and the cul-de-sac head join the asphalt union.

The renderer unions intersecting surfaces and subtracts asphalt from curbs and
both from sidewalks. These layers therefore have disjoint interiors; overlapping
ribbons cannot create coplanar intersection faces. Terrain-aware triangulation
clips each surface to the same terrain triangles used by the collision mesh.
Interpolated road heights follow the terrain plane over the entire triangle,
with deliberate surface offsets. Raised roads and ramp height profiles remain
separate. Nearby foundation pads share grades when their support cells overlap,
preventing one pad from lifting another building's corner.

Downtown, residential suburbs, industrial, school, emergency services, Alder
Court, and mountain outskirts have seeded district regions and debug colours.
The highway runs beyond the playable area into the existing distant terrain.
Continuous background hills, fog and instanced forests extend beyond camera
bounds. Vegetation respects road widths, buildings and parking reservations.

**Alder Court** uses original procedural assets: a curved approach, 23 m diameter
turning head, detached houses, yards, low fences, driveways, a pedestrian alley,
parking, a street sign, and a gathering area with benches. It is an original
suburban cul-de-sac inspired by the requested layout style. No GTA maps,
textures, signs or extracted assets are included.

## Parking and navigation

The default seed 42 has **12 parking lots / 72 spaces** and **53 simulated
vehicles**. Lots reserve land before general buildings are placed. Categories
include shopping, school, police, hospital, offices, residential, industrial,
Alder Court and appropriate shelter approaches. Public POIs retain references
to their nearby parking lots. Additional lots are requested for larger fleets.

Each bay has a stable ID, dimensions, heading, approach path and `occupied_by`
state. Allocation claims only empty bays, repeated claims are idempotent, and a
full lot cannot spawn another car. Vehicles start at their claimed bay, release
it on departure, and follow the bay's exit path to the road. Cosmetic duplicate
service cars that previously spawned outside parking were removed. Replay
restores bay occupancy and records city settings. The replay UI rejects older
generator versions rather than displaying their positions on a different map.

Godot pedestrian navigation rebuilds after generation and after closures or
reopening, using a 3 m obstacle raster. Its asynchronous region upload and map
synchronization are tested separately. Cross-city server queries and avatar
navigation use a polygon-search budget sized for the generated map; Godot's
[documented default 4096-polygon limit](https://docs.godotengine.org/en/stable/classes/class_navigationagent3d.html#class-navigationagent3d-property-path-search-max-polygons)
could truncate these longer routes. Vehicle roadblocks
still disconnect actual graph edges and prevent crossing a blocked entry segment.

Layout and mesh caches use request-content keys and atomic Python output writes;
separate game processes cannot replace one seed's geometry with another's cache.
Caches live in Godot's `user://city_cache`, outside the repository.

## Validation commands and results

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s tests -p 'test_*.py'
& $GodotExe --headless --path . --editor --quit
& $GodotExe --headless --path . --script res://tests/test_city_61.gd
& $GodotExe --headless --path . --script res://tests/test_city_navigation.gd
& $GodotExe --headless --path . --script res://tests/test_phase5.gd
& $GodotExe --headless --path . --script res://tests/test_phase5_transport.gd
& $GodotExe --headless --path . --script res://tests/test_phase5_ui.gd
& $GodotExe --headless --path . --script res://tests/test_warnings.gd
& $GodotExe --headless --path . --script res://tests/test_valley_world.gd
& $GodotExe --path . --script res://tests/render_city61.gd
```

Run the rendered test before the Python suite to include the optional actual-city
surface fixture. The Python matrix covers multiple seeds, area and width extrema,
reproducibility, parking categories, invalid data rejection, and surface topology.
The rendered test saves seven screenshots and a benchmark to ignored `outputs/`.

Executed with Godot 4.7.2 and the local Python environment:

| Check | Result |
|---|---:|
| Python discovery, including actual-city surface fixture | 60 tests passed |
| City generation, foundations, parking and Director controls | 3,596 checks, 0 failures |
| Actual Godot navigation, shelter paths and closure/reopening | 97 checks, 0 failures |
| Phase 5 social regression | 742 checks, 0 failures |
| Phase 5 transport regression | 8,487 checks, 0 failures |
| Configuration/start UI | 6 checks, 0 failures |
| Warning network | 130 checks, 0 failures |
| Valley world, entrances, impact, reset and camera | 2,219 checks, 0 failures |
| Headless editor import and rendered smoke test | No script/startup errors |

The latest generated road fixture also passed a separate triangle validity,
non-overlap and disjoint-layer check. The Python suite retains existing FastAPI
deprecation and SQLite teardown warnings. The world test was updated for the new
node count and float camera-bound precision. Its first run also exposed buildings
under highway/ramp footprints; those footprints are now excluded from parcels.

Measured on the RTX 5070 Ti Laptop GPU with the Compatibility renderer, a
1440 × 900 viewport, 100 rule agents and the local AI services idle. Each phase
contains 120 rendered frames / four simulated seconds after screenshot warm-up.
These are short samples, not a sustained-load or real-LLM benchmark.

| Sample | Median frame | p95 frame |
|---|---:|---:|
| Living city | 16.65 ms | 17.05 ms |
| Initial evacuation | 13.65 ms | 49.15 ms |

Final warm-cache startup was **7.08 s**. Standalone cached map loads for seeds
42, 43 and 91 took **396, 355 and 347 ms**, including runtime validation and
terrain/navigation preparation. Uncached generation adds Python layout and
triangulation work before startup completes. Seed 42 has **176 buildings**,
**315 road edges**, **231 junctions**, **72 parking spaces**, and **488,604 road
surface vertices**. The final frame reported 3,783 draw calls and about 62.3 MiB
of renderer video memory, excluding model/driver allocations. Evacuation still
has CPU spikes from routing and social work; the p95 above makes that visible.

Artifacts are `outputs/city61-generation-benchmark.json`,
`outputs/city61-render-benchmark.json`, `outputs/city61-road-fixture.json`,
`outputs/city61-render.log`, and `outputs/city61-*.png`. The overview, road
junction, parking, neighbourhood, district, settings and extreme-camera horizon
screenshots were visually inspected. Background terrain extends beyond the
camera far clip from every permitted focus/zoom position, with denser sampling
near the playable perimeter.

## Files changed for this phase

Created:

- `ai_service/city_generator.py`: seeded layout, noding, zoning and validation.
- `resources/city_generation.json`: map defaults.
- `scripts/city_controls.gd`: preparation controls, overlays and travel readout.
- `scripts/three_d/city_details.gd`: neighbourhood props, parking and districts.
- `tests/test_city_generator.py`, `tests/test_city_61.gd`,
  `tests/test_city_navigation.gd`, `tests/render_city61.gd` and generated Godot UIDs.
- This guide.

Modified:

- `ai_service/road_geometry.py`: disjoint surface layers, terrain tessellation,
  faster row clipping and atomic mesh cache writes.
- `scripts/city_map.gd`: shared layout loader, road costs, foundation terrain,
  walk grid, parking claims, travel estimates and validation state.
- `scripts/simulation_manager.gd`: generation settings, doubled dimensions,
  fleet parking demand, invalid-map start guards and impact bounds.
- `scripts/main.gd`, `scripts/nuclear_controls.gd`: Director controls integration.
- `scripts/three_d/valley_environment.gd`, `city_3d.gd`, `building_3d.gd`:
  road, curb, pavement, terrain and frontage rendering; scenery clearance.
- `scripts/three_d/road_navigation_3d.gd`, `agent_3d.gd`: rebuilt navigation,
  closure updates and complete long-distance path queries.
- `scripts/social_simulation.gd`, `social_dashboard.gd`,
  `scripts/three_d/social_world.gd`: parking spawns/exits, replay settings and
  occupancy, removal of the duplicate school building, elevated graph debug.
- `tests/test_valley_world.gd`, `tests/test_warnings.gd`: revised size-dependent
  assertions; the warning expiry test isolates its timer transition.
- `README.md`: current world entry point.

## Limits

Vehicle physics has not been added in this phase. Traffic retains the existing
kinematic movement and congestion rules, and lane counts describe cross-sections
rather than independent lane graphs. Procedural meshes are low-poly. Highway
tunnel mouths and distant scenery remain visual extensions. Route costs measure
planar curve length; hill-climbing speed penalties are not modeled. Previously
recorded layouts require their original generator version. Startup generation
is synchronous in Preparation and can briefly block the UI on an uncached map.
The historical Phase 1–3 suites contain older population, map-size and instant-
impact assumptions; this report does not claim those entire suites pass.
