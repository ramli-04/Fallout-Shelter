extends SceneTree
## Real elapsed-time benchmark: simulation advances through its normal clock.
const Manager = preload("res://scripts/simulation_manager.gd")
const Experiments = preload("res://scripts/llm_experiments.gd")

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var app: Control
	var manager: Node
	var render := OS.get_environment("ESSAIM_BENCH_RENDER") == "true"
	if render:
		app = preload("res://scenes/main.tscn").instantiate()
		root.add_child(app)
		manager = app.manager
		app.intro_panel.hide()
		app._show_drawer("settings")
	else:
		manager = Manager.new()
		root.add_child(manager)
		if not manager.load_settings(): quit(1); return
	var preset := OS.get_environment("ESSAIM_BENCH_PRESET")
	manager.ai_config["experiment_preset"] = preset
	manager.ai_config["enable_120"] = true # runner gates this after a measured 30-agent run
	Experiments.apply(manager.settings, manager.ai_config)
	manager.ai_config["service_url"] = OS.get_environment("ESSAIM_TEST_URL")
	manager.ai_config["health_interval_seconds"] = 1
	manager.new_run(int(OS.get_environment("ESSAIM_BENCH_SEED")))
	if render:
		app.intro_panel.hide()
		app._show_drawer("settings")
	var deadline := Time.get_ticks_msec() + 15000
	while manager.ai_config["enabled"] and manager.ai_bridge.status not in ["CONNECTED", "DEGRADED"] and Time.get_ticks_msec() < deadline:
		await process_frame
	if manager.ai_config["enabled"] and manager.ai_bridge.status not in ["CONNECTED", "DEGRADED"]:
		printerr("Benchmark requires all pool models installed and service connected")
		quit(1); return
	manager.launch_nuke()
	manager.alarm_is_real = true
	manager.countdown_seconds = float(OS.get_environment("ESSAIM_BENCH_DURATION"))
	manager.remaining_seconds = manager.countdown_seconds
	manager.simulation_speed = float(OS.get_environment("ESSAIM_BENCH_SPEED"))
	var started := Time.get_ticks_msec()
	var frames := 0
	var max_frame_seconds := 0.0
	var previous_frame := Time.get_ticks_usec()
	var captured := false
	while manager.phase == "EVACUATION":
		await process_frame
		max_frame_seconds = maxf(max_frame_seconds, (Time.get_ticks_usec()-previous_frame)/1e6)
		previous_frame = Time.get_ticks_usec()
		frames += 1
		if render and not captured and Time.get_ticks_msec()-started > 10000:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OS.get_environment("ESSAIM_BENCH_OUTPUT") + ".png")
			captured = true
	var wall_seconds := (Time.get_ticks_msec()-started)/1000.0
	manager.ai_bridge.save_logs()
	var timely := {}
	var choices := {}
	var communications := 0
	for event in manager.events:
		if event["category"] in ["RUMOR", "RELAY"]: communications += 1
	var by_model := {}
	for entry in manager.ai_bridge.records:
		if entry.get("success", false):
			timely[entry["agent_id"]] = true
	for agent in manager.agents:
		var destination: String = agent["objective"]
		if not destination.is_empty(): choices[destination] = int(choices.get(destination, 0)) + 1
		var tier: String = agent["model_tier"]
		if not by_model.has(tier): by_model[tier] = {"assigned": 0, "timely_agents": 0}
		by_model[tier]["assigned"] += 1
		by_model[tier]["timely_agents"] += 1 if timely.has(agent["id"]) else 0
	var result := {"preset": preset, "seed": manager.seed_value, "headless": not render,
		"average_process_fps": frames/maxf(wall_seconds, 0.001),
		"maximum_process_frame_seconds": max_frame_seconds,
		"shelter_selection": choices, "communication_receipts": communications,
		"consensus_largest_destination_fraction": float(choices.values().max())/manager.agents.size() if not choices.is_empty() else 0.0,
		"simulation_speed": manager.simulation_speed, "impact_seconds": manager.countdown_seconds,
		"wall_seconds": wall_seconds, "population": manager.agents.size(),
		"timely_agents": timely.size(), "per_model": by_model,
		"metrics": manager.ai_bridge.metrics, "client_per_model": manager.ai_bridge.model_metrics,
		"backend": manager.ai_bridge.backend_health, "summary": manager.summary,
		"trace_run_id": manager.ai_bridge.run_id, "pending_at_impact": manager.ai_bridge.pending.size(),
		"queued_at_impact": manager.ai_bridge.decision_queue.size()}
	var file := FileAccess.open(OS.get_environment("ESSAIM_BENCH_OUTPUT"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	print("REAL LLM benchmark: %s, timely %d/%d, %.2fs wall" % [preset, timely.size(), manager.agents.size(), wall_seconds])
	if render: app.queue_free()
	else: manager.queue_free()
	await process_frame
	quit()
