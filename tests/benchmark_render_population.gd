extends SceneTree
## Rendering-only avatar scale benchmark. Cloned visual records never enter simulation state.
const Map = preload("res://scripts/city_map.gd")
const Coordinates = preload("res://scripts/three_d/world_coordinates.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var arguments := OS.get_cmdline_user_args()
	var target_agents := 100
	if not arguments.is_empty() and str(arguments[0]).is_valid_int(): target_agents = int(arguments[0])
	if target_agents < 1 or target_agents > 1000:
		push_error("Rendering population benchmark accepts 1-1000 visual agents.")
		quit(2)
		return
	var manager = preload("res://scripts/simulation_manager.gd").new()
	root.add_child(manager)
	manager.set_process(false)
	manager.load_settings()
	manager.ai_bridge.set_process(false)
	manager.social_config.llm_agents = 0
	manager.social_config.automatic_warning = false
	manager.social_config.spontaneous_actions = false
	manager.world.load_world("res://outputs/streaming/baseline-world.json")
	await manager.world.completed
	if not manager.last_setup_error.is_empty():
		push_error("Could not initialize benchmark city: " + manager.last_setup_error)
		quit(1)
		return
	var records := _visual_records(manager.agents, target_agents)
	var view = preload("res://scripts/map_view_3d.gd").new()
	view.manager = manager
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(view)
	view.display_run(records, manager.shelters, true, manager.social.companions)
	var center: Vector2 = Map.MAP_SIZE * .5
	view.camera_rig.focus_at(Coordinates.to_world(center))
	view.camera_rig.target_distance = 180
	view.camera_rig.snap()
	view._refresh_agent_visuals()
	if view.city.get("streamer") != null:
		view.city.streamer.refresh()
		while not view.city.streamer.queue.is_empty(): await process_frame
	for _i in range(60):
		view.sync_run(records, manager.shelters, 1.0, true, 0.0, manager.social.companions)
		await process_frame
	var frame_samples: Array[float] = []
	var cpu_samples: Array[float] = []
	for index in range(120):
		var started := Time.get_ticks_usec()
		view.sync_run(records, manager.shelters, 1.0, true, float(index) / 30.0, manager.social.companions)
		cpu_samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
		await process_frame
		frame_samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
	frame_samples.sort()
	cpu_samples.sort()
	var total_ms := 0.0
	for sample in frame_samples: total_ms += sample
	var lod := {"full": 0, "medium": 0, "far": 0}
	for avatar in view.agent_nodes:
		lod[avatar.animation_lod_tier] = int(lod.get(avatar.animation_lod_tier, 0)) + 1
	var result := {
		"benchmark": "rendering_only_synthetic_population",
		"visual_agents_requested": target_agents,
		"visible_avatar_nodes": view.agent_nodes.size(),
		"authoritative_simulation_agents": manager.agents.size(),
		"animation_lod": lod,
		"frame_p50_ms": frame_samples[60],
		"frame_p95_ms": frame_samples[114],
		"simulation_visual_cpu_p50_ms": cpu_samples[60],
		"simulation_visual_cpu_p95_ms": cpu_samples[114],
		"measured_fps": 1000.0 * frame_samples.size() / maxf(.001, total_ms),
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"render_objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"nodes": root.find_children("*", "", true, false).size(),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"static_memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC),
		"video_memory_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		"renderer": RenderingServer.get_video_adapter_name(),
		"world_id": manager.world.current.world_id,
		"note": "Synthetic cloned records are used only by the renderer; the configured simulation population and authoritative agent array remain unchanged."
	}
	var output_path := "res://outputs/streaming/render-population-%d.json" % target_agents
	var all_visuals_loaded: bool = view.agent_nodes.size() == target_agents
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print(JSON.stringify(result))
	view.queue_free()
	manager.queue_free()
	await process_frame
	quit(0 if all_visuals_loaded else 1)

func _visual_records(source: Array[Dictionary], count: int) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var columns := ceili(sqrt(float(count)))
	var spacing := 35.0
	var center: Vector2 = Map.MAP_SIZE * .5
	for index in range(count):
		var row := floori(float(index) / float(columns))
		var col := index % columns
		var point := center + Vector2((float(col) - float(columns - 1) * .5) * spacing, (float(row) - float(columns - 1) * .5) * spacing)
		var record: Dictionary = source[index % source.size()].duplicate(true)
		record.id = "RENDER-%04d" % index
		record.display_name = "Render Agent %d" % index
		record.population_index = index
		record.position = point
		record.previous_position = point - Vector2(5, 0)
		record.state = "ROAMING"
		record.riding = ""
		record.survival_status = "ALIVE"
		record.route = PackedVector2Array()
		record.route_index = 0
		record.personal_memory = {}
		records.append(record)
	return records
