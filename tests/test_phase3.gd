extends SceneTree
const Manager = preload("res://scripts/simulation_manager.gd")
const Observation = preload("res://scripts/agent_observation.gd")
const Actions = preload("res://scripts/llm_actions.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func choice(action: String, target: String = "", message: String = "") -> Dictionary:
	return {"action": action, "target": target, "message": message, "reason": "Test intention", "confidence": 0.8}

func run() -> void:
	var manager := Manager.new()
	root.add_child(manager)
	check(manager.load_settings(), "load configuration")
	manager.initialize_run()
	check(manager.agents.size() == 150, "150 existing-world people")
	check(manager.agents.filter(func(a): return a["configured_provider"] == "LOCAL_LLM").size() == 150, "all agents use LLM")
	manager.launch_nuke()
	var agent: Dictionary = manager.agents.filter(func(a): return a["configured_provider"] == "LOCAL_LLM")[0]
	manager.choose_destination(agent)
	check(agent["decision_provider"] == "FALLBACK_RULE_BASED", "disconnected fallback")
	var before := JSON.stringify(Observation.generate(manager, agent))
	manager.countdown_seconds = 999
	manager.shelter_by_id["S5"]["exists"] = not manager.shelter_by_id["S5"]["exists"]
	manager.shelter_by_id["S5"]["supply_level"] = 987654321
	manager.environment_events.clear()
	check(before == JSON.stringify(Observation.generate(manager, agent)), "hidden truth does not change payload")
	agent["beliefs"]["S5"]["observation_signature"] = "HIDDEN_SENTINEL"
	check(not JSON.stringify(Observation.generate(manager, agent)).contains("HIDDEN_SENTINEL"), "nested signature excluded")
	check(not Actions.apply(manager, agent, choice("MOVE_TO_SHELTER", "S9")), "unknown shelter rejected")
	check(Actions.apply(manager, agent, choice("MOVE_TO_SHELTER", "S5")), "known rumored location accepted")
	check(agent["objective"] == "S5" and agent["state"] == "MOVING", "Godot movement intention")
	check(not Actions.apply(manager, agent, choice("HELP_AGENT", "A999")), "unknown person rejected")
	var other: Dictionary = manager.agents[1]
	other["position"] = agent["position"] + Vector2(5, 0)
	check(Actions.apply(manager, agent, choice("COMMUNICATE", other["id"], "I promise to help.")), "local conversation")
	check(other["rumors_heard"].back()["original_source"] == agent["id"], "conversation provenance")
	for action in ["WAIT", "OBSERVE"]:
		check(Actions.apply(manager, agent, choice(action)), action + " supported")
	check(manager.agents.filter(func(a): return a["configured_provider"] == "RULE_BASED").size() == 0, "no configured rule agents")
	manager.phase = "IMPACT"
	check(not Actions.apply(manager, agent, choice("MOVE_TO_SHELTER", "S1")), "terminal response rejected")
	var old_run: String = manager.ai_bridge.run_id
	manager.initialize_run()
	check(manager.ai_bridge.run_id != old_run and manager.ai_bridge.pending.is_empty(), "reset invalidates old run")
	manager.queue_free()
	await process_frame
	print("Phase 3: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
