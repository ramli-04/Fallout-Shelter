extends SceneTree
const Manager = preload("res://scripts/simulation_manager.gd")
const Actions = preload("res://scripts/llm_actions.gd")
var failures := 0
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func run() -> void:
	var sim := Manager.new()
	root.add_child(sim)
	check(sim.load_settings(), "settings valid")
	sim.new_run(42)
	check(sim.agents.size() == 30, "30 seeded agents")
	for group in ["A", "B", "C"]:
		check(sim.agents.filter(func(a): return a["model_tier"] == group).size() == 10, "exact group quota")
	var agent: Dictionary = sim.agents[0]
	agent["personal_memory"].append({"time": 0, "text": "PRIVATE_TEST"})
	check(not str(sim.agents[1]["personal_memory"]).contains("PRIVATE_TEST"), "memories isolated")
	sim.ai_bridge.status = "DISCONNECTED"
	sim.start()
	sim.launch_nuke()
	agent["state"] = "DECIDING"
	sim.choose_rule_destination(agent)
	var initial: Vector2 = agent["position"]
	var fake_request := HTTPRequest.new()
	sim.ai_bridge.add_child(fake_request)
	sim.ai_bridge.pending[agent["id"]] = fake_request
	sim.advance_clock(1)
	check(agent["position"] != initial or agent["state"] in ["FROZEN", "HELPING", "SHELTERED", "WAITING_ROAD"], "movement continues with pending inference")
	check(sim.ai_bridge.decision_queue.is_empty(), "no central backlog")
	var old_run: String = sim.ai_bridge.run_id
	sim.new_run(42)
	check(sim.ai_bridge.run_id != old_run and sim.ai_bridge.pending.is_empty(), "reset cancels old requests")
	sim.start()
	sim.launch_nuke()
	sim.alarm_is_real = true
	sim._trigger_impact()
	check(sim.phase == "IMPACT" and not sim.running, "impact mechanics preserved")
	check(not Actions.apply(sim, sim.agents[0], {"action":"WAIT", "target":"", "message":"", "reason":"late", "confidence":0.5}), "late action rejected after impact")
	check(sim.shelters.size() == 5, "five shelters preserved")
	sim.queue_free()
	await process_frame
	print("Phase 4: %d checks / %d failures" % [checks, failures])
	quit(1 if failures else 0)


