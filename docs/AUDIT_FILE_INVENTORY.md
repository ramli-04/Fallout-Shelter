# ESSAIM audit file inventory

Audit date: 2026-11-11. Structural inventory of project-owned files; caches, dependencies, generated outputs, secrets, `.uid` and `.import` sidecars are excluded from the main tables. This is not a visual or audio quality certification.

All listed text files were read for structural indexing. Main runtime paths and findings were additionally inspected manually in the audit. Binary assets were inventoried by path and size.

## Counts

| Extension | Files |
|---|---:|
| .gd | 126 |
| .gdshader | 1 |
| .json | 20 |
| .md | 31 |
| .mp3 | 1 |
| .ps1 | 3 |
| .py | 49 |
| .svg | 17 |
| .tscn | 14 |
| .txt | 1 |
| .wav | 4 |

## Scenes

| Scene | Root | Nodes | Script/scene references |
|---|---|---:|---|
| `scenes/agent.tscn` | Node2D | 1 | `res://scripts/agent.gd` |
| `scenes/main.tscn` | Control | 1 | `res://scripts/main.gd` |
| `scenes/shelter.tscn` | Node2D | 1 | `res://scripts/shelter.gd` |
| `scenes/three_d/agent.tscn` | Node3D | 2 | `res://scripts/three_d/agent_3d.gd` |
| `scenes/three_d/building.tscn` | Node3D | 1 | `res://scripts/three_d/building_3d.gd` |
| `scenes/three_d/camera_rig.tscn` | Node3D | 3 | `res://scripts/three_d/director_camera.gd` |
| `scenes/three_d/city.tscn` | Node3D | 1 | `res://scripts/three_d/city_3d.gd` |
| `scenes/three_d/FloorVault.tscn` | Node3D | 1 | `res://scripts/three_d/floor_vault.gd` |
| `scenes/three_d/FloorVaultDoor.tscn` | Node3D | 1 | `res://scripts/three_d/floor_vault_door.gd` |
| `scenes/three_d/shelter.tscn` | Node3D | 1 | `res://scripts/three_d/shelter_3d.gd` |
| `scenes/three_d/valley_environment.tscn` | Node3D | 1 | `res://scripts/three_d/valley_environment.gd` |
| `scenes/three_d/VaultDoor.tscn` | Node3D | 1 | `res://scripts/three_d/vault_door.gd` |
| `scenes/three_d/VaultEntrance.tscn` | Node3D | 1 | `res://scripts/three_d/vault_entrance.gd` |
| `scenes/three_d/WarningSiren.tscn` | Node3D | 1 | `res://scripts/three_d/warning_siren.gd` |

## Scripts, service, models and tools

| File | Lines | Declared functions | Summary |
|---|---:|---:|---|
| `ai_service/__init__.py` | 1 | 0 | Python module |
| `ai_service/async_providers.py` | 179 | 9 | Python module |
| `ai_service/benchmark.py` | 85 | 4 | Python module |
| `ai_service/city_generator.py` | 417 | 15 | Python module |
| `ai_service/cognitive_retrieval.py` | 155 | 4 | Python module |
| `ai_service/cognitive_tools.py` | 144 | 7 | Python module |
| `ai_service/contracts.py` | 118 | 4 | Python module |
| `ai_service/engine.py` | 235 | 6 | Python module |
| `ai_service/events.py` | 188 | 11 | Python module |
| `ai_service/inspector.py` | 20 | 0 | Python module |
| `ai_service/langgraph_decisions.py` | 603 | 32 | Python module |
| `ai_service/main.py` | 174 | 13 | Python module |
| `ai_service/pool.py` | 230 | 8 | Python module |
| `ai_service/provider.py` | 56 | 8 | Python module |
| `ai_service/road_geometry.py` | 61 | 2 | Python module |
| `ai_service/runtime.py` | 380 | 12 | Python module |
| `ai_service/schemas.py` | 10 | 0 | Python module |
| `ai_service/server.py` | 69 | 6 | Python module |
| `ai_service/social_events.py` | 65 | 7 | Python module |
| `ai_service/social_population.py` | 198 | 5 | Python module |
| `ai_service/traces.py` | 58 | 4 | Python module |
| `config/__init__.py` | 1 | 0 | Python module |
| `config/settings.py` | 192 | 12 | Python module |
| `models/__init__.py` | 1 | 0 | Python module |
| `models/agent.py` | 81 | 2 | Python module |
| `models/shelter.py` | 35 | 2 | Python module |
| `scripts/agent.gd` | 52 | 4 | A reusable character: read-only run data, drawing, and selection. |
| `scripts/agent_beliefs.gd` | 50 | 3 | Only this boundary converts locally observable world state into an agent's knowledge. |
| `scripts/agent_observation.gd` | 50 | 3 | Reads a private mind plus locally visible people; never shelter/director truth. |
| `scripts/agent_personality.gd` | 50 | 1 | Tendencies blended with individual trait variation; no archetype guarantees an outcome. |
| `scripts/agent_reactions.gd` | 83 | 3 | Local perception and social actions. The controller, not a decision policy, supplies observations. |
| `scripts/animal_companion_runtime.gd` | 343 | 23 | Companion movement is simulation-clock driven; it never snaps to the owner. |
| `scripts/authority_coordination.gd` | 756 | 51 | Authority decisions use local observations, addressed reports and explicit duty records. |
| `scripts/blast_model.gd` | 59 | 5 | Fictional experimental damage, never a physical nuclear-effects prediction. |
| `scripts/building_interiors.gd` | 144 | 11 | Lightweight rooms share the exterior coordinates; every transition follows a door corridor. |
| `scripts/city_controls.gd` | 63 | 5 | Generation controls are locked once the run starts; overlays remain available. |
| `scripts/city_map.gd` | 651 | 48 | Seeded shared geography. Simulation, rendering, spawns and routes use this source. |
| `scripts/civilian_activity.gd` | 134 | 8 | Seeded physical/social behavior. No hidden deadline or world secrets enter choices. |
| `scripts/daily_life.gd` | 272 | 15 | Routines use physical room/door/vehicle transitions. Only initialization assigns spawn positions. |
| `scripts/dashboard.gd` | 179 | 11 | Small UI factory: styles and layout stay separate from simulation state. |
| `scripts/environment_events.gd` | 80 | 3 | Independent seeded per-scenario Bernoulli draws; event schedules are world-private. |
| `scripts/environment_visuals.gd` | 15 | 2 | Pure presentation of incidents visible in the current display mode. |
| `scripts/evacuation_decisions.gd` | 64 | 2 | Pure policy: takes private beliefs and subjective urgency, never world shelters or deadline. |
| `scripts/evacuation_effects.gd` | 13 | 4 | Compatibility facade: the spatial network owns playback. No second global siren loop. |
| `scripts/experiment_log.gd` | 31 | 3 | Immutable run snapshots are serialized/written off the scene thread. |
| `scripts/household_travel.gd` | 218 | 10 | Agreements and observed/communicated positions drive behavior; Director metrics may inspect truth. |
| `scripts/impact_effect.gd` | 24 | 3 | A brief local map flash and expanding ring. Outcomes stay in the manager. |
| `scripts/llm_actions.gd` | 100 | 1 | Validate intentions against current state; physical admission remains Godot-owned. |
| `scripts/llm_bridge.gd` | 316 | 17 | HTTPRequest polls asynchronously; inference never blocks the render/fixed loop. |
| `scripts/llm_experiments.gd` | 55 | 4 | Independent seeded streams keep model assignment unrelated to role. |
| `scripts/main.gd` | 753 | 30 | Compose the dashboard and connect signals. All run state is in the manager. |
| `scripts/map_view.gd` | 172 | 12 | Local map viewport: GUI panels never move with the camera or steal map clicks. |
| `scripts/map_view_3d.gd` | 415 | 25 | View boundary. All entity movement comes from the existing simulation records. |
| `scripts/nuclear_controls.gd` | 124 | 5 | Director configuration is preparation-only; preview reads truth without applying it. |
| `scripts/object_inspector.gd` | 62 | 3 | Inspector displays the selected person's mind; director shelter inspection is separate. |
| `scripts/parking_layout.gd` | 45 | 1 | Parking is zoned before buildings, sharing the seeded road geometry. |
| `scripts/population_histogram.gd` | 13 | 2 | See source |
| `scripts/road_graph.gd` | 5 | 1 | Physical spline lengths are the edge costs; closures disconnect actual edges. |
| `scripts/road_routes.gd` | 49 | 5 | Free-space routes can cross open ground while avoiding buildings and water. |
| `scripts/rumor_system.gd` | 150 | 5 | Bounded local messages. A recipient interprets claims rather than copying another mind. |
| `scripts/scenario_config.gd` | 124 | 3 | Configuration checks are separate from the runtime clock and agent loop. |
| `scripts/shelter.gd` | 50 | 3 | The absent S5 record has no map node; it stays inspectable in the sidebar. |
| `scripts/shelter_admission.gd` | 27 | 1 | Admission is the only place where arrival discovers actual shelter availability. |
| `scripts/shelter_life.gd` | 732 | 54 | Event-driven routines and physical room-to-room movement during the ten-day shelter phase. |
| `scripts/shelter_state.gd` | 62 | 3 | Admission truth. Resources are person-days; Phase 2.5 does not consume daily rations. |
| `scripts/simulation_manager.gd` | 842 | 30 | Owns run state and the fixed simulation clock. Rendering only observes signals. |
| `scripts/siren_controls.gd` | 100 | 5 | See source |
| `scripts/social_alert_widget.gd` | 27 | 2 | See source |
| `scripts/social_config.gd` | 76 | 5 | Versioned pre-run settings. NumPy sampling is performed before the clock starts. |
| `scripts/social_dashboard.gd` | 223 | 12 | See source |
| `scripts/social_recorder.gd` | 45 | 5 | Serialize snapshots and write the append-only audit off the render thread. |
| `scripts/social_simulation.gd` | 883 | 42 | Director world state stays here; decisions read only each agent's acquired evidence. |
| `scripts/spontaneous_actions.gd` | 104 | 7 | OpenJev chooses from a bounded menu. Physical feasibility remains authoritative in Godot. |
| `scripts/three_d/agent_3d.gd` | 218 | 9 | Read-only avatar. Fixed-clock simulation positions own motion, never render/physics timing. |
| `scripts/three_d/animal_companion_3d.gd` | 148 | 7 | Low-cost stylized companion avatar. Simulation records own all movement and state. |
| `scripts/three_d/bomb_drop.gd` | 48 | 2 | Authoritative eight-second descent; animation and audio follow the simulation clock. |
| `scripts/three_d/building_3d.gd` | 264 | 9 | Reusable static obstruction; color/height are deterministic visual choices, not RNG draws. |
| `scripts/three_d/city_3d.gd` | 204 | 7 | The shared seeded geography drives terrain, streets, paths and building footprints. |
| `scripts/three_d/city_details.gd` | 118 | 4 | Original neighbourhood props and an optional district overlay; no simulation. |
| `scripts/three_d/director_camera.gd` | 122 | 12 | Reusable orbit/pan rig. Receives camera intent only; has no simulation or RNG reference. |
| `scripts/three_d/environment_markers_3d.gd` | 29 | 1 | Director-only visual markers; event consequences remain in environment_events.gd. |
| `scripts/three_d/floor_vault.gd` | 28 | 1 | Horizontal city vault. Logical admission remains at the safe approach threshold. |
| `scripts/three_d/floor_vault_door.gd` | 43 | 2 | See source |
| `scripts/three_d/geometry.gd` | 79 | 6 | Small primitive factory, shared by buildings, shelters and environmental markers. |
| `scripts/three_d/impact_3d.gd` | 50 | 2 | Brief geometric flash/shockwave, driven by presentation time. Never touches nav or state. |
| `scripts/three_d/road_navigation_3d.gd` | 72 | 7 | Obstacle-aware raster surface matching free-space simulation movement. |
| `scripts/three_d/shelter_3d.gd` | 107 | 7 | Physical entrance is created only for an existing shelter. Threshold is the model destination. |
| `scripts/three_d/shelter_interior_3d.gd` | 112 | 10 | Lightweight, presentation-only cutaway generated from a shelter-specific room plan. |
| `scripts/three_d/social_world.gd` | 101 | 3 | Lightweight visual observers. No vehicle physics or decisions run in rendering. |
| `scripts/three_d/terrain.gdshader` | 76 | 0 | See source |
| `scripts/three_d/valley_environment.gd` | 308 | 13 | Batched road ribbons and a purely scenic mountain horizon. No distant simulation. |
| `scripts/three_d/vault_door.gd` | 42 | 2 | See source |
| `scripts/three_d/vault_entrance.gd` | 14 | 1 | See source |
| `scripts/three_d/warning_network_3d.gd` | 172 | 7 | Bounded camera mix observes authoritative warning records; it never drives agent perception. |
| `scripts/three_d/warning_siren.gd` | 109 | 5 | See source |
| `scripts/three_d/world_coordinates.gd` | 11 | 2 | One explicit, reversible conversion. The simulation retains its planar units and speed. |
| `scripts/traffic_rules.gd` | 315 | 14 | Local driving perception and bounded tactical AI. All distances use simulation units. |
| `scripts/vehicle_catalog.gd` | 26 | 1 | Dimensions are simulation units (10 units = one rendered metre). |
| `scripts/vehicle_collisions.gd` | 69 | 6 | Continuous SAT for translating oriented boxes. Includes parked cars and wrecks. |
| `scripts/vehicle_runtime.gd` | 271 | 19 | Deterministic planar dynamics; 10 simulation units = 1 m. No suspension solver. |
| `scripts/warning_audio.gd` | 28 | 2 | Shared local assets. Generated files are explicitly temporary, never licensed-recording claims. |
| `scripts/warning_system.gd` | 148 | 11 | Authoritative acoustic perception uses ground-plane world units, never Director audio gain. |
| `scripts/world_projection.gd` | 31 | 2 | A read-only UI projection. Observer geometry cannot reveal the S5 existence draw. |
| `tools/benchmark_llm_scaling.py` | 125 | 2 | Python module |
| `tools/benchmark_phase4_http.py` | 41 | 1 | Python module |
| `tools/check_llm_parallel.py` | 49 | 2 | Python module |
| `tools/download_openjev_model.py` | 110 | 2 | Python module |
| `tools/generate_warning_audio.py` | 55 | 2 | Python module |
| `tools/generate_warning_voice.ps1` | 15 | 0 | Offline temporary announcement. No network/TTS service is contacted. |
| `tools/graphify.ps1` | 92 | 0 | See source |
| `tools/graphify_essaim.py` | 261 | 15 | Python module |
| `tools/openjev.ps1` | 70 | 0 | See source |
| `tools/run_openjev.py` | 29 | 0 | Python module |
| `tools/summarize_llm_benchmarks.py` | 96 | 1 | Python module |
| `tools/summarize_phase4.py` | 65 | 1 | Python module |

## Configuration/resources

| File | Structure |
|---|---|
| `config/agents.json` | spawn_x_m, spawn_y_m, speed_m_per_second, authority_fraction, communication_probability, risk_tolerance, trust_in_authorities, sociability, crowd_following, initial_health, initial_belief_confidence, personalities |
| `config/graphify.json` | repository, revision, version, language_pack_version, output |
| `config/llm_groups.json` | A, B, C |
| `config/openjev.json` | repository, revision, version, model, backend, endpoint, timeout_seconds, max_pending, interval_seconds, checkpoint, checkpoint_revision |
| `config/shelters.json` | list: 5 entries |
| `config/simulation.json` | seed, population, countdown_min_seconds, countdown_max_seconds, tick_seconds, arrival_radius_m |
| `resources/agent_activity.json` | bomb_fall_seconds, walking_speed_fraction, roam_distance_range, panic_scramble_threshold, push_radius, push_distance, door_close_seconds, nihilist_dance_probability, despairing_dance_probability |
| `resources/ai_config.json` | enabled, experiment_preset, enable_120, model_weights, llm_agent_count, max_concurrent_requests, per_model_concurrency, queue_limit, queue_timeout_seconds, service_url, request_timeout_seconds, decision_interval_seconds, health_interval_seconds, max_response_age_seconds |
| `resources/city_generation.json` | area_multiplier, road_width_multiplier, terrain_cell |
| `resources/daily_life.json` | family_follow_distance, family_separation_distance, boarding_timeout_seconds, missing_member_wait_seconds, fatigue_rest_threshold |
| `resources/living_world.json` | event_probabilities, event_duration_range, event_window_fraction, event_spacing_seconds, event_radius, road_radius, observation_radius, communication_radius, communication_interval, rumor_ttl_seconds, rumor_max_hops, rumor_history_limit, memory_limit, relay_radius, false_alarm_probability, public_warning_estimate_range, capacity_estimates, capacity_estimate_variation, size_descriptions, abundant_supply_days, unknown_supply_range, rat_supply_loss_fraction, secondary_personality_probability, trait_jitter, denial_delay_range, freeze_threshold, freeze_seconds, freeze_cooldown_seconds, panic_decay_per_second, help_radius, help_seconds, help_panic_reduction |
| `resources/nuclear.json` | map_scale, impact_position, random_impact, radius, severity, zone_fractions, zone_damage, damaged_capacity_fraction, damaged_supply_fraction, damaged_occupant_damage, destroyed_occupant_damage, outside_damage_multiplier, building_resistance |
| `resources/phase1.json` | seed, agent_count, authority_count, speed_range, trait_range, simulation_speed, shelters, evacuation |
| `resources/shelter_life.json` | duration_days, decision_interval_seconds, critical_decision_interval_seconds, day_start_hour, reflection_allowed, daily_windows, need_rates_per_hour, activity_effects, activity_durations_minutes, maximum_cognitive_requests, cognitive_cooldown_seconds |
| `resources/social_config.json` | schema_version, total, civilians, authorities, family_rate, children, school_students, seed, iq_mean, iq_std, iq_influence, stress_tolerance, cooperation, authority_trust, skepticism, risk_tolerance, sociability, vehicle_rate, police_vehicles, ambulances, fire_trucks, civil_protection_vehicles, traffic_density, vehicles_in_use_rate, vehicle_collisions, accident_probability, roadblock_frequency, phone_rate, social_adoption, rumor_probability, credibility_sensitivity, network_availability, alert_reach, warning_min, warning_max, simulation_speed, random_impact, shelter_availability, event_frequency, llm_agents, inference_interval, concurrency, execution_mode, group_a, group_b, group_c, family_priority, provider_concurrency, provider_a, provider_b, provider_c, model_a, model_b, model_c, pre_disaster_seconds, automatic_warning, day_start_hour, routine_clock_rate, spontaneous_actions, named_agents_enabled, zack_age, legend_age, dog_shelter_access_restricted |
| `resources/social_population.json` | schema_version, numpy_version, rng_algorithm, config, config_hash, agents, families, school, iq_stats |
| `resources/traffic_rules.json` | green_seconds, amber_seconds, all_red_seconds, headway_seconds, minimum_gap, passing_patience_seconds, lane_change_units_per_second, emergency_escape_enabled, pavement_max_speed, ai_enabled, ai_interval_seconds, urban_speed_limit, residential_speed_limit, highway_speed_limit |
| `resources/vehicle_physics.json` | spawn_attempts, spawn_clearance, minimum_impact_mps, vehicle_damage_per_mps, occupant_damage_per_mps, pedestrian_damage_per_mps, treatment_per_second, recovery_enabled, recovery_seconds, injury_model |
| `resources/visual_3d.json` | camera, shadows_enabled, agent_bob_height, navigation_debug |
| `resources/warnings.json` | sound_radius_world, tower_volume_db, tower_pitch, master_volume_db, max_audible_sirens, network_mode, announcements_enabled, announcement_interval_seconds, announcement_duration_seconds, first_announcement_seconds, final_warning_seconds, start_offset_seconds, hearing_threshold, comprehension_threshold, indoor_gain, environmental_muffling, director_mix, survivor_tail_seconds, siren_resistance, announcement_text, announcement_comprehensible, audio_paths, siren_overrides |

## Assets

| File | Bytes |
|---|---:|
| `assets/audio/warnings/bomb_dropping_cc0.mp3` | 121968 |
| `assets/audio/warnings/BOMB_SOUND_LICENSE.md` | 672 |
| `assets/audio/warnings/README.md` | 2549 |
| `assets/audio/warnings/temporary_civil_defense_wail.wav` | 1058444 |
| `assets/audio/warnings/temporary_emergency_broadcast.wav` | 504896 |
| `assets/audio/warnings/temporary_explosion.wav` | 176444 |
| `assets/audio/warnings/temporary_final_warning.wav` | 352844 |

## UI icon assets

| File | Bytes |
|---|---:|
| `resources/icons/agents.svg` | 283 |
| `resources/icons/alert.svg` | 224 |
| `resources/icons/apply.svg` | 208 |
| `resources/icons/close.svg` | 214 |
| `resources/icons/export.svg` | 228 |
| `resources/icons/false_alarm.svg` | 242 |
| `resources/icons/fullscreen.svg` | 232 |
| `resources/icons/logs.svg` | 263 |
| `resources/icons/overview.svg` | 263 |
| `resources/icons/pause.svg` | 226 |
| `resources/icons/play.svg` | 248 |
| `resources/icons/random.svg` | 258 |
| `resources/icons/reset.svg` | 218 |
| `resources/icons/settings.svg` | 279 |
| `resources/icons/shelters.svg` | 233 |
| `resources/icons/sirens.svg` | 252 |
| `resources/icons/windowed.svg` | 232 |

## Tests and render harnesses

| File | Bytes |
|---|---:|
| `tests/__init__.py` | 80 |
| `tests/benchmark_llm_scaling.gd` | 4528 |
| `tests/render_city61.gd` | 3485 |
| `tests/render_civilian_activity.gd` | 3002 |
| `tests/render_daily_life.gd` | 1804 |
| `tests/render_phase1.gd` | 682 |
| `tests/render_phase2.gd` | 1544 |
| `tests/render_phase25.gd` | 2117 |
| `tests/render_phase26.gd` | 3028 |
| `tests/render_phase35.gd` | 2167 |
| `tests/render_phase5.gd` | 2733 |
| `tests/render_procedural_map.gd` | 1158 |
| `tests/render_streetscape.gd` | 2176 |
| `tests/render_valley_world.gd` | 3023 |
| `tests/run_phase3_http.py` | 2530 |
| `tests/test_ai_service.py` | 8074 |
| `tests/test_city_61.gd` | 6073 |
| `tests/test_city_generator.py` | 7938 |
| `tests/test_city_navigation.gd` | 3218 |
| `tests/test_civilian_activity.gd` | 5183 |
| `tests/test_daily_life.gd` | 14016 |
| `tests/test_daily_life_world.gd` | 2562 |
| `tests/test_daily_shelters.gd` | 3463 |
| `tests/test_daily_spawn_seeds.gd` | 1644 |
| `tests/test_graphify_integration.py` | 4704 |
| `tests/test_isometric_camera.gd` | 1352 |
| `tests/test_langgraph_cognition.py` | 11749 |
| `tests/test_llm_parallel.gd` | 2026 |
| `tests/test_llm_scaling.gd` | 2668 |
| `tests/test_model_pool.py` | 6734 |
| `tests/test_models.py` | 3931 |
| `tests/test_openjev_live.gd` | 1837 |
| `tests/test_phase1.gd` | 9763 |
| `tests/test_phase2.gd` | 14446 |
| `tests/test_phase25.gd` | 18212 |
| `tests/test_phase26.gd` | 15456 |
| `tests/test_phase3.gd` | 3326 |
| `tests/test_phase31_real.gd` | 1191 |
| `tests/test_phase35.gd` | 9683 |
| `tests/test_phase3_http.gd` | 3022 |
| `tests/test_phase4.gd` | 2105 |
| `tests/test_phase4.py` | 12865 |
| `tests/test_phase5.gd` | 7669 |
| `tests/test_phase5_transport.gd` | 3127 |
| `tests/test_phase5_ui.gd` | 1384 |
| `tests/test_phase62.gd` | 10468 |
| `tests/test_phase62_world.gd` | 1171 |
| `tests/test_phase64.gd` | 13233 |
| `tests/test_phase65.gd` | 12322 |
| `tests/test_population_ai.gd` | 4129 |
| `tests/test_procedural_map.gd` | 3696 |
| `tests/test_project.py` | 491 |
| `tests/test_road_geometry.py` | 1302 |
| `tests/test_road_surface.gd` | 1602 |
| `tests/test_shelter_life.gd` | 4987 |
| `tests/test_social_events.py` | 2572 |
| `tests/test_social_population.py` | 5499 |
| `tests/test_traces.py` | 3751 |
| `tests/test_traffic_openjev_live.gd` | 2641 |
| `tests/test_traffic_rules.gd` | 10323 |
| `tests/test_ui_rehaul.gd` | 5597 |
| `tests/test_valley_world.gd` | 5096 |
| `tests/test_warning_audio.gd` | 3979 |
| `tests/test_warnings.gd` | 9575 |

## Existing documentation

| File | Bytes |
|---|---:|
| `docs/BEGINNER_GUIDE.md` | 8674 |
| `docs/CIVILIAN_ACTIVITY.md` | 4521 |
| `docs/DOCKER.md` | 3513 |
| `docs/GRAPHIFY.md` | 4817 |
| `docs/ISOMETRIC_RENDERING.md` | 2111 |
| `docs/LIVING_CITY.md` | 12189 |
| `docs/LLM_INSPECTOR.md` | 4728 |
| `docs/MULTI_LLM.md` | 8465 |
| `docs/MULTI_LLM_PERFORMANCE.md` | 5148 |
| `docs/PHASE1_NOTES.md` | 6007 |
| `docs/PHASE_25_GUIDE.md` | 14684 |
| `docs/PHASE_26_GUIDE.md` | 14268 |
| `docs/PHASE_2_GUIDE.md` | 15581 |
| `docs/PHASE_31_REPORT.md` | 3341 |
| `docs/PHASE_35_ARCHITECTURE.md` | 1243 |
| `docs/PHASE_35_GUIDE.md` | 9712 |
| `docs/PHASE_35_REPORT.md` | 4562 |
| `docs/PHASE_3_GUIDE.md` | 10499 |
| `docs/PHASE_4.md` | 13263 |
| `docs/PHASE_45_WORLD.md` | 12520 |
| `docs/PHASE_4_MEASUREMENTS.md` | 3820 |
| `docs/PHASE_5.md` | 15891 |
| `docs/PHASE_61_CITY.md` | 14001 |
| `docs/PHASE_62_VEHICLES.md` | 7071 |
| `docs/POPULATION_AI.md` | 3472 |
| `docs/PROCEDURAL_MAP.md` | 926 |
| `docs/TRAFFIC_STREETSCAPE.md` | 8398 |
| `docs/WARNING_SIRENS.md` | 11017 |

## Literal resource reference check

No missing literal `preload("res://...")` / `load("res://...")` targets found in indexed source.

Dynamic paths, plugin availability and exported builds need separate runtime checks. Root project settings, Docker/Compose configuration and entrypoints were reviewed separately in PROJECT_AUDIT.md.
