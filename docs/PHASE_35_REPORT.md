# Phase 3.5 validation and file report

Successful executed runs (Godot 4.7.2):

| Suite | Checks/tests | Result |
|---|---:|---|
| Phase 3.5 gameplay/integration | 861 | Passed |
| Phase 1 configuration/spawn/UI | 50,006 | Passed |
| Phase 2 movement/admission/clock | 1,235 | Passed |
| Phase 2.5 knowledge/incidents | 4,083 | Passed |
| Phase 2.6 3D/navigation/camera/replay | 2,897 | Passed |
| Phase 3 LLM action/observation boundary | 17 | Passed |
| Phase 3 scripted HTTP transport | 11 | Passed |
| Population AI scripted transport | 49,519 | Passed |
| UI overhaul | 33 | Passed |
| Python unittest discovery | 18 tests | Passed |
| Real Ollama llama3.2:1b | One live decision | Passed: MOVE_TO_SHELTER/S4 applied as MOVING |

The suites were run and repaired during implementation; counts are their successful runs, not claimed human test counts. Older fixtures were updated for dynamic camera bounds, larger-map reachability, reserved service spawns, an isolated rumor newcomer, rule-only deterministic fixtures and asynchronous navigation synchronization after resets. Initial failures were investigated rather than reported as passes. Real AI was verified against the existing local Ollama model; the temporary AI HTTP service started for that test was stopped afterward. Ollama itself was left running.

The graphical harness generated and visually reviewed actual RTX 5070 Ti Laptop GPU captures in outputs/phase35-*.png: city, controller, preview, services, vault, vault-closed, blast, devastation, ruins-inspector and reset. A main-scene headless smoke run completed without script errors. git diff --check completed without whitespace errors. No sustained FPS measurement or separate interactive human walkthrough was performed.

Acceptance coverage: configurable map presets and POIs; road/building clearance and real Godot paths; all five definitions and absent-S5 physical isolation; LLM boundary plus real inference; map click coordinate conversion; seeded random location; exact impact clock; preview model isolation; real visual sequence; near destruction/distant survival; damaged capacity/supply/door consequences; actual admission denial; occupant deaths retained and automatically archived off the scene thread; Director inspection and JSON export; same-seed destruction replay; reset and second false-alarm run; six door states and timed opening/closing. Post-impact ten-day behavior remains intentionally unimplemented as described in the guide.

## Files changed or added

- `README.md`
- `resources/phase1.json`
- `scripts/city_map.gd`
- `scripts/main.gd`
- `scripts/map_view_3d.gd`
- `scripts/scenario_config.gd`
- `scripts/shelter_admission.gd`
- `scripts/shelter_state.gd`
- `scripts/simulation_manager.gd`
- `scripts/three_d/agent_3d.gd`
- `scripts/three_d/building_3d.gd`
- `scripts/three_d/city_3d.gd`
- `scripts/three_d/director_camera.gd`
- `scripts/three_d/geometry.gd`
- `scripts/three_d/impact_3d.gd`
- `scripts/three_d/road_navigation_3d.gd`
- `scripts/three_d/shelter_3d.gd`
- `tests/test_phase1.gd`
- `tests/test_phase2.gd`
- `tests/test_phase25.gd`
- `tests/test_phase26.gd`
- `docs/PHASE_35_ARCHITECTURE.md`
- `docs/PHASE_35_GUIDE.md`
- `resources/nuclear.json`
- `scenes/three_d/VaultDoor.tscn`
- `scenes/three_d/VaultEntrance.tscn`
- `scripts/experiment_log.gd`
- `scripts/blast_model.gd`
- `scripts/blast_model.gd.uid`
- `scripts/nuclear_controls.gd`
- `scripts/nuclear_controls.gd.uid`
- `scripts/three_d/vault_door.gd`
- `scripts/three_d/vault_door.gd.uid`
- `scripts/three_d/vault_entrance.gd`
- `scripts/three_d/vault_entrance.gd.uid`
- `tests/render_phase35.gd`
- `tests/test_phase35.gd`
- `docs/PHASE_35_REPORT.md` (this report)


Simulation changes are in simulation_manager, blast_model, shelter_state/admission and scenario_config. CityMap and phase1/nuclear resources own layout and scenario settings. Main, map_view_3d and nuclear_controls connect the Director, preview and enriched trace. three_d scripts/scenes implement art, camera, navigation and effects. Tests and documentation provide verification and handoff. New .uid files are Godot-generated script identities. No Python AI-service implementation, memory/communication policy, user .env or .gitignore was modified.

The clean working project was checkpointed before modifications using git archive HEAD at commit 56567d2, into the sibling ESSAIM-checkpoint-20261013-223049/project-before-phase35.zip. Changes are left in the workspace for review; no commit was created.
