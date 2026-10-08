extends RefCounted
## Only this boundary converts locally observable world state into an agent's knowledge.

static func remember(agent: Dictionary, time: float, text: String, config: Dictionary) -> void:
	agent["personal_memory"].append({"time": time, "text": text})
	while agent["personal_memory"].size() > int(config["memory_limit"]):
		agent["personal_memory"].pop_front()

static func initialize(definitions: Array, rng: RandomNumberGenerator, config: Dictionary) -> Dictionary:
	var result := {}
	for definition in definitions:
		var size: String = config["size_descriptions"][definition["id"]]
		var estimate := int(float(config["capacity_estimates"][size]) * rng.randf_range(1-config["capacity_estimate_variation"], 1+config["capacity_estimate_variation"]))
		result[definition["id"]] = {"position": Vector2(definition["position"][0], definition["position"][1]),
			"capacity": estimate, "capacity_exact": false, "size_description": size,
			"estimated_occupancy": 0, "resource_score": definition["resource_score"],
			"risk": definition["known_risk"], "popularity": definition["popularity"],
			"official_support": definition["official_support"], "existence_probability": definition["public_existence_probability"],
			"confidence": definition["information_confidence"], "unavailable": false,
			"observed_at": -1.0, "source": "Rumored location" if definition["id"] == "S5" else "Public map; approximate size"}
	return result

static func observe(agent: Dictionary, shelter: Dictionary, time: float, config: Dictionary) -> bool:
	if agent["position"].distance_to(shelter["position"]) > float(config["observation_radius"]):
		return false
	var belief: Dictionary = agent["beliefs"][shelter["id"]]
	var signature := "%s:%s:%s:%s:%d" % [shelter["exists"], shelter["operational"], shelter["door_status"], shelter["infested"], shelter["occupancy"]]
	if belief.get("observation_signature", "") == signature:
		return false
	belief["observation_signature"] = signature
	belief["existence_probability"] = 1.0 if shelter["exists"] else 0.0
	belief["capacity"] = shelter["capacity"]
	belief["capacity_exact"] = true
	belief["estimated_occupancy"] = shelter["occupancy"]
	belief["unavailable"] = not shelter["operational"] or shelter["door_status"] != "OPEN" or shelter["occupancy"] >= shelter["capacity"]
	belief["confidence"] = 1.0
	belief["observed_at"] = time
	belief["source"] = "Direct observation at %.1fs" % time
	belief["risk"] = maxf(belief["risk"], 0.65) if shelter["infested"] else float(shelter["known_risk"])
	var text := "%s: %s; entrance %s; occupancy %d/%d%s" % [shelter["id"], "present" if shelter["exists"] else "ABSENT", shelter["door_status"], shelter["occupancy"], shelter["capacity"], "; rats observed" if shelter["infested"] else ""]
	remember(agent, time, text, config)
	return true
