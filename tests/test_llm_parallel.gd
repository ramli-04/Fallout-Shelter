extends SceneTree
const Manager = preload("res://scripts/simulation_manager.gd")
var failures := 0
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func run() -> void:
	var manager := Manager.new()
	root.add_child(manager)
	manager.load_settings()
	manager.set_process(false)
	manager.ai_config["service_url"] = OS.get_environment("ESSAIM_TEST_URL")
	manager.ai_config["health_interval_seconds"] = 0.1
	manager.initialize_run()
	await create_timer(0.5).timeout
	check(manager.ai_bridge.status == "CONNECTED", "pool connected")
	manager.launch_nuke()
	for agent in manager.agents:
		agent["state"] = "DECIDING"
		agent["wait_until"] = 0
		manager.choose_destination(agent)
	check(manager.ai_bridge.pending.size() == 3, "three requests dispatched")
	var models := {}
	for request in manager.ai_bridge.pending.values(): models[request.get_meta("model")] = true
	check(models.size() == 3, "each model receives its own simultaneous request")
	var queued: int = manager.ai_bridge.decision_queue.size()
	for agent in manager.agents: manager.choose_destination(agent)
	check(manager.ai_bridge.decision_queue.size() == queued, "no duplicated agent requests")
	var deadline := Time.get_ticks_msec()+15000
	while Time.get_ticks_msec() < deadline and not manager.agents.all(func(a): return a.has("latest_llm_action")):
		check(manager.ai_bridge.pending.size() <= 3, "global limit")
		models.clear()
		for request in manager.ai_bridge.pending.values():
			var model: String = request.get_meta("model")
			check(not models.has(model), "one active request per model")
			models[model] = true
		await process_frame
	check(manager.agents.all(func(a): return a.has("latest_llm_action")), "parallel pool serves every test agent")
	manager.queue_free()
	await process_frame
	print("Parallel model transport: %d checks, %d failures (TEST_ONLY provider)" % [checks, failures])
	quit(1 if failures else 0)
