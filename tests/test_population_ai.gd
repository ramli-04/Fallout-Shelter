extends SceneTree
## Large-population scheduling through a scripted transport provider, not real inference.
const Manager = preload("res://scripts/simulation_manager.gd")
const MAIN = preload("res://scenes/main.tscn")
var failures := 0
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

func run() -> void:
	var app: Control = MAIN.instantiate()
	root.add_child(app)
	var manager: Node = app.manager
	manager.ai_config["max_concurrent_requests"] = 1 # explicit serial transport regression
	if not OS.get_environment("ESSAIM_TEST_POPULATION").is_empty():
		manager.ai_config["experiment_preset"] = OS.get_environment("ESSAIM_TEST_POPULATION")
		manager.ai_config["enable_120"] = true
		preload("res://scripts/llm_experiments.gd").apply(manager.settings, manager.ai_config)
	manager.ai_config["service_url"] = OS.get_environment("ESSAIM_TEST_URL")
	manager.ai_config["health_interval_seconds"] = 0.2
	manager.ai_config["decision_interval_seconds"] = 120
	manager.settings["evacuation"]["decision_interval_seconds"] = 120
	manager.initialize_run()
	var population: int = manager.settings["agent_count"]
	check(manager.agents.size() == population, "preset agents")
	check(app.map_view.agent_nodes.size() == population, "preset 3D avatars")
	check(app.agent_picker.item_count == population+1, "all agents selectable")
	var ids := {}
	var positions := {}
	for agent in manager.agents:
		ids[agent["id"]] = true
		positions[agent["position"]] = true
		check(agent["configured_provider"] == "LOCAL_LLM", "AI configured for " + agent["id"])
		for building in Manager.CityMap.building_rects():
			check(not building.has_point(agent["position"]), "spawn outside building")
	check(ids.size() == population and positions.size() == population, "unique IDs and clear distinct spawn points")
	var capacities := []
	for shelter in manager.shelters:
		capacities.append(shelter["capacity"])
	check(capacities == [125, 37, 90, 175, 250], "capacities divided by twenty, rounded down")
	await create_timer(0.5).timeout
	check(manager.ai_bridge.status == "CONNECTED", "transport service connected")
	manager.launch_nuke()
	for agent in manager.agents:
		agent["state"] = "DECIDING"
		agent["wait_until"] = 0
		manager.choose_destination(agent)
	check(manager.ai_bridge.pending.size() == 1, "only one inference in flight")
	check(manager.ai_bridge.decision_queue.size() == population-1, "remaining agents fairly queued")
	for agent in manager.agents:
		manager.choose_destination(agent)
	check(manager.ai_bridge.decision_queue.size() == population-1, "duplicate scheduling does not duplicate requests")
	var started: float = manager.elapsed_seconds
	var deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline:
		check(manager.ai_bridge.pending.size() <= 1, "concurrency stays bounded")
		if manager.agents.all(func(a): return a.has("latest_llm_action")):
			break
		await process_frame
	check(manager.agents.all(func(a): return a.has("latest_llm_action")), "every agent receives and applies an AI decision")
	check(manager.elapsed_seconds > started, "simulation remains active while servicing the queue")
	check(manager.ai_bridge.decision_queue.is_empty(), "first fair round drains")
	for shelter in manager.shelters:
		check(shelter["occupancy"] <= shelter["capacity"], "shelter admission still enforces capacity")
	for agent in manager.agents:
		agent["next_llm_seconds"] = 0
		manager.choose_destination(agent)
	manager.initialize_run()
	check(manager.ai_bridge.pending.is_empty() and manager.ai_bridge.decision_queue.is_empty() and manager.ai_bridge.queued.is_empty(), "reset clears in-flight and queued work")
	await create_timer(0.3).timeout
	check(manager.agents.all(func(a): return not a.has("latest_llm_action")), "old queue cannot affect new agents")
	app.queue_free()
	await process_frame
	print("Population AI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
