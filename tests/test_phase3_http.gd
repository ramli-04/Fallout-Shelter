extends SceneTree
## Run through tests/run_phase3_http.py with a deliberately labeled test provider.
const Manager = preload("res://scripts/simulation_manager.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func wait_seconds(seconds: float) -> void:
	await create_timer(seconds).timeout

func run() -> void:
	var manager := Manager.new()
	root.add_child(manager)
	manager.load_settings()
	manager.ai_config["service_url"] = OS.get_environment("ESSAIM_TEST_URL")
	manager.ai_config["health_interval_seconds"] = 0.2
	manager.ai_config["decision_interval_seconds"] = 0.2
	manager.initialize_run()
	await wait_seconds(0.5)
	check(manager.ai_bridge.status == "CONNECTED", "HTTP health connected")
	manager.launch_nuke()
	var agent: Dictionary = manager.agents.filter(func(a): return a["configured_provider"] == "LOCAL_LLM")[0]
	agent["wait_until"] = 0
	manager.choose_destination(agent)
	check(manager.ai_bridge.pending.has(agent["id"]), "async request queued")
	var start_time: float = manager.elapsed_seconds
	await wait_seconds(0.15)
	check(manager.elapsed_seconds > start_time, "clock advances during inference")
	await wait_seconds(2.0)
	check(agent["decision_history"].any(func(d): return d.get("provider") == "LOCAL_LLM"), "real HTTP result applied")
	check(agent["objective"] == "S1", "model-selected target moves through Godot")
	# Pause invalidates a late intention without changing physical state.
	agent["next_llm_seconds"] = 0
	manager.choose_destination(agent)
	manager.pause()
	var position: Vector2 = agent["position"]
	await wait_seconds(2)
	check(agent["position"] == position, "paused simulation cannot move from response")
	check(manager.ai_bridge.pending.is_empty(), "paused completion releases request")
	manager.start()
	agent["next_llm_seconds"] = 0
	manager.choose_destination(agent)
	var old_run: String = manager.ai_bridge.run_id
	manager.initialize_run()
	check(manager.ai_bridge.run_id != old_run, "reset switches request epoch")
	await wait_seconds(1.5)
	check(manager.agents[0]["decision_history"].is_empty(), "old reply cannot affect reset agent")
	manager.ai_config["request_timeout_seconds"] = 0.1
	manager.ai_config["decision_interval_seconds"] = 12
	manager.ai_bridge.status = "CONNECTED"
	manager.launch_nuke()
	var timeout_agent: Dictionary = manager.agents.filter(func(a): return a["configured_provider"] == "LOCAL_LLM")[0]
	timeout_agent["wait_until"] = 0
	manager.choose_destination(timeout_agent)
	await wait_seconds(0.25)
	check(timeout_agent["decision_provider"] == "FALLBACK_RULE_BASED", "HTTP timeout uses rules")
	check(not timeout_agent.get("fallback_reason", "").is_empty(), "timeout reason recorded")
	manager.queue_free()
	await process_frame
	print("Phase 3 HTTP: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
