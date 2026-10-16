extends RefCounted
## Independent seeded streams keep model assignment unrelated to role.
const MODELS := ["A", "B", "C"]
const PRESETS := {"30": [10, 10, 10], "120": [40, 40, 40]}

static func apply(settings: Dictionary, config: Dictionary) -> String:
	var preset: String = str(config.get("experiment_preset", "legacy"))
	if preset == "legacy": return ""
	var population: String = "30" if preset in ["A", "B", "C", "D"] else preset.trim_prefix("rules_")
	if not PRESETS.has(population): return "Unknown experiment preset"
	if population == "120" and not config.get("enable_120", false):
		return "120-agent preset requires enable_120 after reviewing the 30-agent benchmark"
	settings["agent_count"] = int(population)
	settings["authority_count"] = 4
	config["enabled"] = bool(config.get("enabled", true)) and not preset.begins_with("rules_") and preset != "A"
	config["llm_agent_count"] = 0 if not config["enabled"] else int(population)
	return ""

static func shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for i in range(values.size()-1, 0, -1):
		var j := rng.randi_range(0, i)
		var value: Variant = values[i]
		values[i] = values[j]
		values[j] = value

static func assignments(count: int, seed_value: int, config: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 19001
	var result: Array = []
	var weights: Array = config.get("model_weights", [])
	if weights.size() == 3:
		var total := float(weights[0]) + float(weights[1]) + float(weights[2])
		for _i in range(count):
			var draw := rng.randf()*total
			var tier := 0
			while tier < 2 and draw >= float(weights[tier]):
				draw -= float(weights[tier])
				tier += 1
			result.append(MODELS[tier])
	else:
		var quotas: Array = PRESETS.get(str(count), [count, 0, 0])
		for tier in range(3):
			for _i in range(int(quotas[tier])): result.append(MODELS[tier])
		shuffle(result, rng)
	if config.get("experiment_preset", "") == "B":
		result.fill("B")
	return result

static func roles(count: int, authorities: int, seed_value: int) -> Array:
	var result: Array = []
	for i in range(count): result.append("Authority" if i < authorities else "Civilian")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 23003
	shuffle(result, rng)
	return result
