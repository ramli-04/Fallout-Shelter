extends RefCounted
## Independent seeded per-scenario Bernoulli draws; event schedules are world-private.

const EFFECTS := {"maintenance": "Temporarily refuses admission", "door": "Entrance temporarily blocked", "road": "Affected travelers must wait", "crowd": "Local panic and route avoidance", "rats": "Supply contamination and perceived risk"}

static func schedule(seed_value: int, shelters: Array, delay: float, config: Dictionary) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 5051
	var result: Array[Dictionary] = []
	var eligible: Array = shelters.filter(func(s: Dictionary): return s["exists"] and s["base_operational"])
	for type in ["maintenance", "door", "road", "crowd", "rats"]:
		if rng.randf() >= float(config["event_probabilities"][type]):
			continue
		var target_id := "S2" if type in ["maintenance", "rats"] else ""
		var location := Vector2(900, 540)
		if type == "door":
			if eligible.is_empty():
				continue
			target_id = eligible[rng.randi_range(0, eligible.size()-1)]["id"]
		if not target_id.is_empty():
			for shelter in shelters:
				if shelter["id"] == target_id:
					location = shelter["position"]
		else:
			location = Vector2(rng.randi_range(3,7)*180, rng.randi_range(2,4)*180)
		result.append({"event_id": "E%02d" % (result.size()+1), "event_type": type,
			"target_id": target_id, "target_location": location,
			"scheduled_time": rng.randf_range(delay*config["event_window_fraction"][0], delay*config["event_window_fraction"][1]),
			"duration": rng.randf_range(config["event_duration_range"][0], config["event_duration_range"][1]),
			"severity": rng.randf_range(0.3,1), "active_status": false, "started": false, "ended": false,
			"actual_effect": EFFECTS[type], "visibility_to_agents": [],
			"event_log_message": "%s near %s" % [type.capitalize(), target_id if not target_id.is_empty() else str(location)]})
	result.sort_custom(func(a: Dictionary, b: Dictionary): return a["scheduled_time"] < b["scheduled_time"])
	var previous := -INF
	for event in result:
		event["scheduled_time"] = maxf(event["scheduled_time"], previous + config["event_spacing_seconds"])
		previous = event["scheduled_time"]
	# Project backward into the configured window after resolving clustered draws.
	var latest: float = delay*config["event_window_fraction"][1]
	for index in range(result.size()-1, -1, -1):
		result[index]["scheduled_time"] = minf(result[index]["scheduled_time"], latest)
		latest = result[index]["scheduled_time"] - config["event_spacing_seconds"]
	return result

static func update(manager: Node) -> void:
	var time: float = manager.elapsed_seconds - manager.alarm_started_seconds
	var changed := false
	for event in manager.environment_events:
		if not event["started"] and time + 0.000001 >= event["scheduled_time"]:
			event["started"] = true
			event["active_status"] = true
			changed = true
			manager.log_event("ENVIRONMENT", event["event_log_message"] + " started: " + event["actual_effect"], "director")
			if not event["target_id"].is_empty():
				var shelter: Dictionary = manager.shelter_by_id[event["target_id"]]
				shelter["event_history"].append({"time": manager.elapsed_seconds, "event_id": event["event_id"], "action": "started"})
				if event["event_type"] == "rats":
					shelter["supply_level"] *= 1.0 - manager.living["rat_supply_loss_fraction"] * event["severity"]
		if event["active_status"] and time + 0.000001 >= event["scheduled_time"] + event["duration"]:
			event["active_status"] = false
			event["ended"] = true
			changed = true
			manager.log_event("ENVIRONMENT", event["event_log_message"] + " cleared.", "director")
			if not event["target_id"].is_empty():
				manager.shelter_by_id[event["target_id"]]["event_history"].append({"time": manager.elapsed_seconds, "event_id": event["event_id"], "action": "ended"})
	if changed:
		for shelter in manager.shelters:
			preload("res://scripts/shelter_state.gd").refresh(shelter, manager.environment_events)

static func road_blocks(agent: Dictionary, events: Array, radius: float) -> bool:
	if agent["route"].is_empty():
		return false
	var index := mini(int(agent["route_index"]), agent["route"].size()-1)
	for event in events:
		if event["active_status"] and event["event_type"] == "road":
			var nearest := Geometry2D.get_closest_point_to_segment(event["target_location"], agent["position"], agent["route"][index])
			# Stop only when approaching the physical obstruction, not anywhere on the street.
			if nearest.distance_to(event["target_location"]) <= radius and agent["position"].distance_to(nearest) <= radius:
				return true
	return false
