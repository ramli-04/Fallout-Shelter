extends SceneTree
const Manager = preload("res://scripts/simulation_manager.gd")
const Experiments = preload("res://scripts/llm_experiments.gd")
var failures := 0
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func run() -> void:
	var manager := Manager.new()
	root.add_child(manager)
	check(manager.load_settings(), "settings load")
	check(Experiments.apply({}, {"experiment_preset": "120", "enable_120": false}) != "", "120 gated")
	var disabled := {"experiment_preset": "30", "enabled": false}
	Experiments.apply({}, disabled)
	check(not disabled["enabled"] and disabled["llm_agent_count"] == 0, "explicit disabled flag preserved")
	for population in [30, 120]:
		manager.ai_config["experiment_preset"] = str(population)
		manager.ai_config["enable_120"] = true
		manager.ai_config["enabled"] = true
		check(Experiments.apply(manager.settings, manager.ai_config).is_empty(), "preset valid")
		manager.new_run(42)
		var original := manager.agents.duplicate(true)
		check(manager.agents.all(func(a): return a["configured_provider"] == "LOCAL_LLM"), "normal preset powers all agents with LLM")
		var counts := [0, 0, 0]
		var roles := 0
		for agent in manager.agents:
			counts[Experiments.MODELS.find(agent["model_tier"])] += 1
			roles += 1 if agent["role"] == "Authority" else 0
			for building in Manager.CityMap.building_rects():
				check(not building.has_point(agent["position"]), "clear seeded spawn")
		check(counts == Experiments.PRESETS[str(population)], "exact model quotas")
		check(roles == 4, "seeded authority quota")
		manager.new_run(42)
		check(manager.agents == original, "same seed preserves entire initial mind")
		manager.new_run(43)
		check(manager.agents != original, "new seed changes experiment")
		check(Experiments.assignments(population, 42, manager.ai_config) == Experiments.assignments(population, 42, manager.ai_config), "assignment deterministic")
		manager.ai_config["experiment_preset"] = "rules_" + str(population)
		Experiments.apply(manager.settings, manager.ai_config)
		manager.new_run(42)
		check(manager.agents.all(func(a): return a["configured_provider"] == "RULE_BASED"), "rule baseline")
		for i in range(population):
			check(manager.agents[i]["beliefs"] == original[i]["beliefs"] and manager.agents[i]["position"] == original[i]["position"] and manager.agents[i]["model_tier"] == original[i]["model_tier"], "baseline same initial scenario")
	manager.queue_free()
	await process_frame
	print("LLM scaling: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
