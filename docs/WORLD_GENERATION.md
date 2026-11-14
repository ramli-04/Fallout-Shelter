# Seed-based procedural worlds

For the current dependency scheduler, shelter-first reservations, incremental artifacts and visual streaming, see [Advanced map generation and rendering](ADVANCED_MAP_RENDERING.md). The verification figures below describe the original implementation pass; that report contains the newer results.

The new `WorldGenerationManager` builds validated, versioned worlds through the existing city generator. Godot, pedestrian routing, directed right-hand vehicle routing, police dispatch, shelter admissions, interiors and emergency events all consume the same `city_map.gd` geography. The Python `Main.py` prototype is unchanged; these controls belong to the current Godot simulation.

## Use it

1. Open `scenes/main.tscn` in Godot. Before starting, open **Settings → WORLD GENERATION / SEEDS**.
2. Enter a world seed or press **Random world seed**. Choose **small**, **medium**, **large** or **very_large**, district/road density, vegetation density and road width. Editing these fields only changes the draft.
3. Press **Generate map**. Generation and validation run on a background worker. The existing preview remains visible until the accepted world is applied. Read the validation status and inspect the real road overview. **Regenerate same world** reuses the current world seed and the selected settings.
4. Leave the population at 100: 65 civilians and 35 authorities. Starting through the Social Director automatically creates a random world if none has been explicitly generated. The initial preparation view retains the historical city for compatibility; starting a new world is explicit and observable. The HUD shows **WORLD** and **RUN** seeds separately.
5. The **population**, **scenario**, **events** and **behavior** seed fields accept independent values. `-1` inherits the existing run/scenario seed. **Apply experiment seeds / keep this world** rebuilds the initial simulation against the same stored geography. Changing AI provider, population or event seed does not rebuild the procedural road network.
6. Set a world JSON path and press **Save / export world configuration**. The default is `user://worlds/exported_world.json`; an absolute filesystem path is also accepted. **Load saved world configuration** validates and restores its geometry without calling the generator. **Copy current world seed** and export remain available during a run; generation/loading controls are locked after starting. Reset to preparation before loading another world.
7. The existing random-new-scenario control chooses a new run seed and, once using procedural worlds, generates a new world with that seed. Reset keeps the current generated world.

A seed identifies the world together with its generator version and generation settings. For an exact archival handoff, export the configuration; a seed alone does not specify a city size or density.

## Pipeline and constraints

`ai_service/world_generation.py` orchestrates dedicated deterministic streams for terrain, roads, districts, buildings, vegetation, vehicles, props and shelters. It never draws from Python's global random state. Godot uses cryptographic entropy only to choose a new displayed seed. Generation attempts derive their streams from the original seed, stream name, generator version and attempt number.

Terrain dimensions and protected lake/park land precede road placement. Seeded district centers define clipped Voronoi zones. Road patterns include warped organic networks, radial neighborhoods and mixed urban/suburban connections. Irregular intersections are noded before the road graph is built. A real one-way roundabout joins the street network; Alder Court remains a connected cul-de-sac with homes and driveways. The elevated highway connects through explicit ramps. Street widths, sidewalks, off-road parking and reserved public/shelter parcels precede buildings. Existing foundation grading handles building terrain support.

The public district types required by existing systems remain available. Larger presets add residential districts, more road segments and larger building/prop/parking budgets. The medium preset targets the existing 100-person simulation. The approximate base dimensions in simulation units are 6,750 × 4,250; 9,500 × 5,900; 12,200 × 7,900; and 15,000 × 11,000. Seeded dimensions vary between 96.5% and 102.5% of those bases. Ten simulation units equal one metre.

All five identities have seeded off-road entrances with clear connectors. Their existing supply descriptions, popularity, maintenance risks and communications behavior are retained:

| Shelter | Nominal capacity | Geographical role |
| --- | ---: | --- |
| S1 | 2,500 | Near the urban center; popular, limited supplies. |
| S2 | 750 | Near its generated, labeled metro access; good supplies, maintenance risk. |
| S3 | 1,800 | Intermediate journey, road/pedestrian access and communications. |
| S4 | 3,500 | Beyond the dense center, requiring a longer journey. |
| S5 | 5,000 | Remote mountain zone; independent 50% existence draw in the world shelter stream. |

S5's absence is stored once in the world and applied to actual simulation state: an absent S5 has zero usable capacity and no physical shelter node. Population/scenario/behavior changes cannot resample its existence. Generated-world S5 truth stays masked in the normal shelter card/inspector, its entrance remains hidden until local observation, and the overview omits it. Private agent beliefs begin with the existing rumor rather than verified world truth. Saved world files contain ground truth for scientific reconstruction.

Generated vegetation and small environmental objects are stored placements, rendered through existing reusable geometry/MultiMesh resources and included in pedestrian obstacles. They reserve streets, sidewalks, parking and shelter connectors. Building facade variation and weathering are stored cosmetic choices. Vehicle spawn inventory consists of real, unique parking bays; actual vehicles still come from the configured population and emergency services. No decorative population or shelter occupancy is fabricated.

Permanent geography is separate from initial population/scenario state and dynamic emergencies. Initial accidents or closures continue to use the existing event systems rather than being baked into road geometry.

## Validation, caching and persistence

The existing planar generator physically repairs disconnected street components before final noding. The world validator checks connectivity in both directed travel directions, same-level crossings, road/building/parking overlaps, shelter entrance connectors, public access, building envelopes, vehicle bays/spawns and environmental clearance. If generation fails, up to four whole-world attempts use deterministic derived streams. Exhausted attempts reject the request and expose the reason. A stored `validation.valid` flag is never sufficient to load a world.

`resources/world_generation.json` configures preset budgets and retry limits. Generation requests are version-keyed and cached under `user://worlds/cache`. Heavy Python geometry and save validation run outside the scene thread; changing draft settings never triggers a job. Runtime hydration uses existing terrain, obstacle indexes and navigation caches. The accepted world is handed to Godot on the main thread, and existing scene construction remains there.

The world JSON includes format version `1`, generator version `essaim-world-3` (with exact `essaim-world-1` and `essaim-world-2` snapshot loading retained), seed, deterministic attempt, stream seeds, settings, generation dependencies/priorities, dimensions, road graph, districts, infrastructure, terrain inputs/formula version, shelters/existence, buildings, asset variations, parking/vehicle spawns, vegetation, props and validation results. Its content hash supplies the generated world ID. New layouts default to 70% straight street links and denser building infill between existing roads. Unsupported world/terrain versions and checksum mismatches are rejected; migration must be explicit. Loading uses saved placements instead of rerunning the current generator.

Godot retains the original canonical JSON text when exporting and recording worlds. This avoids changing the checksum through differences between Python and Godot floating-point JSON formatting. Runtime hydration deep-copies the stored layout before converting arrays to vectors or changing bay occupancy.

Simulation log entries, Kafka-bound events, AI logs, social experiment reports and experiment archives carry the world ID/version/hash and resolved experiment seeds. Recording headers and full experiment/trace exports also retain the canonical world configuration. Replay validates that snapshot before rebuilding the scene and keeps simulation/inference disabled while scrubbing. The replay reader accepts initialization events preceding its complete header.

## Files

| Component | Files |
| --- | --- |
| World pipeline, presets and persistence | `ai_service/world_generation.py`, `resources/world_generation.json`, `scripts/world_generation_manager.gd` |
| Shared city generator and runtime hydration | `ai_service/city_generator.py`, `scripts/city_map.gd` |
| Director controls/preview and start flow | `scripts/city_controls.gd`, `world_preview.gd`, `main.gd`, `social_dashboard.gd` |
| Independent seeds, logs and recordings | `scripts/simulation_manager.gd`, `social_simulation.gd`, `daily_life.gd`, `civilian_activity.gd`, `emergency_management.gd`, `shelter_life.gd`, `llm_bridge.gd` |
| Existing visual components and S5 discovery | `scripts/three_d/city_3d.gd`, `city_details.gd`, `building_3d.gd`, `scripts/map_view_3d.gd`, `agent_beliefs.gd` |
| Acceptance tests | `tests/test_world_generation.py`, `tests/test_world_generation.gd`, `tests/test_world_ui.gd` |
| Existing shelter regression compatibility | `tests/test_shelter_life.gd` (explicit return type for an existing test variable) |

## Verification

```powershell
.venv\Scripts\python.exe -m unittest discover -s tests -p test_world_generation.py
$godot = "C:\Users\Moham\Downloads\godot\Godot_v4.7.2-stable_win64_console.exe"
& $godot --headless --path . --script tests/test_world_generation.gd
& $godot --headless --path . --script tests/test_world_ui.gd
```

The Python suite checks cross-process reproducibility, actual road-pattern differences, independent vegetation, all presets/shelter constraints, full save/load, rejected tampering/versions/settings and bounded retry behavior. Godot integration checks actual 100-person initialization, all four presets, pedestrian and right-hand vehicle shelter access, independent seed effects, immutable geography, export/import, police/emergency integration, logging and S5 masking. The main-scene suite checks controls, actual rendered inventory, HUD settings, running-state locks, S5 visibility and replay of a generated-world recording.

An inspected schematic of actual generated road/building records is available at `outputs/world_generation/seed-comparison.png` (seed 42 organic versus seed 2 radial). These are map overviews, not screenshots of 3D art.

Results on 2026-11-11:

| Suite | Passed |
| --- | ---: |
| Python world generation/persistence | 9 tests |
| Godot generated-world integration, all four sizes | 79 checks |
| Godot main-scene world controls/replay | 12 checks |
| Existing city/navigation/foundations | 4,107 checks |
| Organized police evacuation | 43 checks |
| Daily life | 1,881 checks |
| Daily shelter regression | 13 checks |
| Phase 5 UI | 11 checks |
| Phase 7 UI | 11 checks |
| Moroccan traffic | 40 checks |
| Dynamic emergencies | 59 checks |
| Shelter activities and ten-day progression | 357 checks |

All 11 Godot suites pass, totaling 6,613 checks. The Python cache test also verifies deterministic rebuilding after cache corruption. Explicit saved-world loads reject corruption rather than replacing the user's file. Editor import and whitespace checks pass; shutdown/replay warnings below remain. Graphify was rebuilt using the project wrapper.

## Limits

- Lake water features and existing elevated highways/ramps are supported. This phase does not implement navigable river crossings or underground vehicle tunnels; existing distant tunnel landmarks remain scenery.
- Buildings use existing foundation grading, AABB obstacle envelopes and visual components. This is not a geological erosion or detailed civil-engineering terrain solver.
- Python generation is asynchronous, but Godot terrain/navigation hydration and scene/road-mesh construction still run on the main thread. A visible handoff pause is possible, especially for very large maps; no claim of a measured frame-time target is made. Existing instancing, mesh/resource reuse, visibility ranges and caches remain in use.
- Generation caches dependency artifacts as well as complete worlds and runtime navigation results. Vegetation edits reuse the layout artifact; there is still no live editor for selectively rebuilding individual districts.
- Presets bound the number of vehicle bays. Populations exceeding the stored parking budget are rejected with an instruction to choose a larger world, rather than silently changing geography.
- The historical city path remains available for existing scripts/tests. Its original scenario capacities are retained; the explicit capacities above apply to generated worlds. Historical recordings still require their compatible city-generator version.
- Existing headless shutdown resource/ObjectDB notices and replay float warnings remain visible. Passing assertions do not establish warning-free shutdown or final GPU performance.
