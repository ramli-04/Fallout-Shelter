# Phase 4.5 — valley world redesign

The inline concept supplied in the conversation guided the composition: a lower urban valley, suburbs and public services, an industrial western edge, a forested northeast reserve, a raised cross-valley highway and mountain refuges. This is original procedural low-poly geometry, substantially simpler than the painted reference. No GLB models or standalone reference bitmap were present in `assets/models` or `assets/references`; no third-party model assets were imported.

## World and configuration

The default `resources/nuclear.json` map scale is now **3.75**, producing **6750 × 4050 simulation units / 675 × 405 world metres**. This is 1.5 times each previous dimension and **2.25 times the playable area**. The Director map-size menu retains 2, 2.5 and 3, and adds Valley (3.75). Damage formulas, damage radii, shelter capacities, supplies, maintenance and existence probabilities were not changed to compensate for the larger world.

`CityMap` owns the seeded shared geography: 65 connected junctions including the five shelter approaches, sine-sampled curved street segments, diagonal connections, roadside building reservations, conservative obstacle footprints, public-service sites and highway centerlines. The same seed reproduces roads, buildings, terrain and spawns. Public buildings reserve the closest available lot to their district target. Buildings face the adjacent street and fit entirely inside conservative navigation footprints. The representative seed 42 produces 134 buildings; the count varies with seed.

S1 remains in the residential park; S2 is the urban metro refuge; S3 is on the residential/communications edge. S4 and S5 are northeast mountain sites. S5 retains its original 50% existence probability. A missing S5 produces no entrance, label or selection area. Natural hill scenery exists regardless of that private fact.

The terrain is a continuous height field with blended building foundations and a collision mesh. Background mountains begin at the playable perimeter, extend into a larger circular landscape, and have no agent simulation or physics bodies. Batched distant conifers, local instanced vegetation, warm daylight and light distance fog continue the scenery beyond the city. The background shares the perimeter terrain colors to avoid a sharp border.

Roads are batched mesh ribbons with separate sidewalks, asphalt, dirt paths and arc-length dashed markings. There is a junction roundabout, a multilane elevated highway, median markings, guardrails, concrete supports, signs, descending access ramps and scenic tunnel mouths. Narrow street and path approaches connect both mountain destinations to the city.

## Entrances and navigation

The existing `shelter.tscn` selects the entrance by shelter ID:

- S1–S3: new `FloorVault.tscn`, horizontal reinforced hatch, concrete apron, concentric rings, radial braces, central hub, warning marks, stair landing, railings and approach ramp. `FloorVaultDoor.tscn` performs hydraulic lift, lateral slide, then lowering.
- S4–S5: existing `VaultEntrance.tscn` / `VaultDoor.tscn`, recessed vertical gear door, rock shoulders, overhead rock canopy, concrete frame, approach platform and status light.

Each door provides open, opening, closing, closed, jammed and destroyed states. Closed plates enable static collision. The original authoritative admission check still rejects any non-open, unavailable, full, failed or absent shelter. Agent destination coordinates are on the safe approach; admission removes the admitted agent from the surface. The stair/shaft is a staged entrance, not a fully navigable underground interior. An agent does not need to cross a closed plate or fall through a hole to enter.

Free-space movement remains supported as requested in the preceding civilian update. Agents can cross clear ground instead of being forced onto roads. Buildings, reservoir and mountain-vault rock shoulders are excluded from fine-grid A* and line-of-sight shortcuts. The Godot pedestrian region uses conservative obstacle-aware raster polygons; `path_between()` uses the same finer authoritative route planner so narrow approaches remain usable. Distant mountains are outside the playable map. Decorative trees are not hard obstacles.

## Camera and destruction

The existing pan, zoom, orbit, tilt, agent follow and city overview controls remain. Camera bounds and far clip scale with the enlarged city. Focusing a selected shelter works; the Nuclear Impact Controller now has a **Focus landmark** menu for all five public buildings and the impact point. Building transparency remains available when following selected agents. Selecting an agent no longer rebuilds the city, which previously could restore destroyed visual buildings.

Nuclear calculations and survivor resolution remain in the existing manager and blast model. Building records still match rendered building order. The existing destruction hooks affect buildings, service vehicles, local vegetation and props. The valley environment adds local scorched-road overlays and hides exposed highway props in the damage zone. Both entrance types receive the actual logical damage state. Reset rebuilds visual geometry and restores authoritative state without retaining scorches or destroyed plates.

## Scene hierarchy and reusable scenes

```text
World3D
  City
    SculptedTerrain + terrain collider
    Building instances
    local vegetation MultiMeshes
    ValleyEnvironment [new reusable scene]
      BackgroundMountains
      DistantForest MultiMesh
      Sidewalk / Asphalt / Trail / Markings batches
      Highway / Guardrails / Ramps batches
      supports / signs / tunnel mouths
    PedestrianNavigation
    Sun + WorldEnvironment
  Shelter instances (only existing shelters)
    FloorVault -> FloorVaultDoor [two new reusable scenes]
    OR VaultEntrance -> VaultDoor
  Agent instances (small details culled beyond 120 m)
  CameraRig / warning network / impact and bomb effects
```

## Files

Created:

- `scenes/three_d/valley_environment.tscn`
- `scenes/three_d/FloorVault.tscn`
- `scenes/three_d/FloorVaultDoor.tscn`
- `scripts/three_d/valley_environment.gd`
- `scripts/three_d/floor_vault.gd`
- `scripts/three_d/floor_vault_door.gd`
- `tests/test_valley_world.gd`
- `tests/render_valley_world.gd`
- this guide (plus Godot-generated script UID files).

Modified:

- `resources/nuclear.json`: default expanded dimensions and centered initial impact.
- `scripts/city_map.gd`: shared organic layout, building districts and orientations, foundation heights, highway centerline, obstacle and spawn planning.
- `scripts/blast_model.gd`: accepts the extra map-size preset; damage formulas unchanged.
- `scripts/nuclear_controls.gd`: extra size preset, dynamic coordinate limits, landmark focus.
- `scripts/map_view_3d.gd`: shelter/landmark focus and selection no longer rebuilding the city.
- `scripts/three_d/city_3d.gd`: terrain, fog, vegetation clearances, valley scene and destruction hook.
- `scripts/three_d/building_3d.gd`: road-facing, bounded geometry, medium-rise skyline, houses, warehouses and factories.
- `scripts/three_d/agent_3d.gd`: distance culling for small character details.
- `scripts/three_d/director_camera.gd`: larger zoom range and far clip.
- `scripts/three_d/road_navigation_3d.gd`: obstacle-aware pedestrian surface and shared route authority.
- `scripts/three_d/shelter_3d.gd`: entrance type selection, rock integration, antennas and damage display.
- `scripts/three_d/vault_door.gd`: closed-state physical blocker.
- `tests/test_warnings.gd`: expanded-map siren-count expectation, with reset assertions comparing current node and record counts.
- `README.md` and `docs/PROCEDURAL_MAP.md`: current world guide links.

## Checkpoints

Local ignored artifacts, without `.env` or credentials:

- `outputs/checkpoints/pre-phase45-world.zip`
- `outputs/checkpoints/phase45-layout-entrances.zip`
- `outputs/checkpoints/phase45-verified-world.zip`

## Executed verification

- `test_valley_world.gd`: **1437 checks, zero failures**. Three layout seeds; graph connectivity; road/building separation; five shelter routes from sampled spawns and actual seeded agents; both door types and timed opening/closing; physical blockers; closed admission rejection; actual impact/survival resolution; damage display; reset; absent S5; landmark focus and camera bounds; selection retaining the city.
- `test_procedural_map.gd`: **8281 checks, zero failures** after fixing three reserved-nature footprint overlaps found in the first run. Includes terrain ray collision and seeded layout checks.
- `test_civilian_activity.gd`: **56 checks, zero failures** with the larger layout.
- `test_phase4.gd`: **12 checks, zero failures** (model quotas and integration contracts).
- `test_warnings.gd`: **93 checks, zero failures** after updating the old 18-tower expectation to the expanded map's 43 towers. Initial run failed only three fixed-count assertions.
- Python `unittest discover`: **40 tests pass**. Existing dependency deprecation and SQLite teardown warnings remain. `pytest` is not installed; the suite was executed through unittest.
- `render_valley_world.gd`: actual NVIDIA renderer, captured overview, valley angle, S1 and S4 open/closed views; images visually inspected. Frame measurements saved to `outputs/valley-performance.json`.
- Real rendered local-model run through `benchmark_llm_scaling.gd`: three local model groups, 10 agents each; 20-second warning plus eight-second fall. **15/30 agents** had timely decisions, **18 successful responses**, **55.67 average process FPS**, **422 ms maximum process frame**, **28.98 s wall time**. Godot kept running while local requests completed. Kafka and all three local groups reported CONNECTED. No cloud test was performed.
- An exploratory legacy `test_phase35.gd` run was stopped after encountering its obsolete 4500×2700 dimension assertion and strict click-coordinate assertion. That historical suite also assumes instant impact and one-second door completion; it is **not reported as passing**. Targeted tests above cover the replacement behavior. Full historical-suite migration remains separate work.

## Performance and limits

Measured on this laptop's RTX 5070 Ti Laptop GPU, Godot 4.7.2, OpenGL Compatibility, a 1440×900 3D viewport, normal shadow configuration. Render-only measurements keep the AI/Kafka/Ollama containers running but disable new inference; the separate live run above measures actual concurrent inference. Samples are 180 frames per condition, with 24 warm-up frames and VSync active. These are short scenario measurements, not a sustained stress-test guarantee. See the JSON for current mean and p95 times, draw calls, object count, approximate renderer VRAM and startup time.

| Scenario | Mean frame | p95 frame | Draw calls |
|---|---:|---:|---:|
| 30 roaming | 16.67 ms | 16.80 ms | 2063 |
| 120 roaming | 16.76 ms | 17.05 ms | 2651 |
| 120 evacuating | 21.47 ms | 68.52 ms | 2698 |

Startup measured 3.09 seconds. Renderer-reported video memory was approximately 44?67 MiB in these samples; this excludes other applications and model allocations.

The important remaining limitations are visual asset fidelity, CPU route-planning spikes during evacuation, and entrance staging. The highway is scenic infrastructure: pedestrian ground routes pass beneath raised decks, and there is no vehicle traffic or elevated highway pedestrian simulation. Tunnel mouths create a visual continuation, not navigable tunnel interiors. The underground shaft is staged with a dark inset and stairs rather than a cut-through terrain tunnel. Distant mountains and forest use simple geometry; no terrain deformation or full distant destruction is simulated. This pass adds a roundabout and organic street branches, but does not model traffic lanes, traffic signals or vehicle junction behavior.

Recommended follow-ups: replace procedural facades/rocks with a small licensed modular asset kit; add a true underground shelter entrance interior and explicit animated entry link; amortize path planning across frames; consolidate more avatar/building draw calls; add highway traffic only if it serves the simulation; migrate the historical instant-impact tests to the current timing contract. Preserve the shared seeded geography and authoritative admission/damage logic through those changes.

