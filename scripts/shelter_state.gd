extends RefCounted
## Admission truth. Resources are person-days; Phase 2.5 does not consume daily rations.

static func initialize(shelter: Dictionary, rng: RandomNumberGenerator, config: Dictionary) -> void:
	shelter["manual_door_state"] = ""
	shelter["nominal_capacity"] = shelter["capacity"]
	if not shelter["exists"]:
		shelter["capacity"] = 0
	shelter["shelter_id"] = shelter["id"]
	shelter["world_position"] = shelter["position"]
	shelter["maximum_capacity"] = shelter["capacity"]
	shelter["current_occupancy"] = 0
	shelter["base_operational"] = shelter["operational"]
	shelter["maintenance_condition"] = 100.0
	shelter["door_status"] = "OPEN" if shelter["exists"] else "ABSENT"
	shelter["operational_status"] = "OPERATIONAL" if shelter["operational"] else "ABSENT"
	shelter["supply_level"] = 0.0
	if shelter["exists"]:
		if shelter["supplies_person_days"] != null:
			shelter["supply_level"] = float(shelter["supplies_person_days"])
		elif shelter["resources"] == "Unknown":
			shelter["supply_level"] = rng.randf_range(config["unknown_supply_range"][0], config["unknown_supply_range"][1])
		else:
			shelter["supply_level"] = shelter["capacity"] * config["abundant_supply_days"]
	shelter["known_information"] = {"size": config["size_descriptions"][shelter["id"]], "resources": shelter["resources"]}
	shelter["hidden_information"] = {"exists": shelter["exists"], "capacity": shelter["capacity"], "initial_supply": shelter["supply_level"]}
	shelter["event_history"] = []
	shelter["infested"] = false
	shelter["relay_messages"] = []

static func refresh(shelter: Dictionary, active_events: Array) -> void:
	if shelter.get("structural_state", "INTACT") == "DESTROYED":
		shelter["operational"] = false
		shelter["accepting"] = false
		shelter["door_status"] = "DESTROYED"
		return
	if shelter.get("structural_state", "INTACT") == "DAMAGED":
		shelter["door_status"] = "JAMMED"
		shelter["operational_status"] = "DAMAGED"
		return
	var failure := false
	var blocked := false
	var rats := false
	for event in active_events:
		if not event["active_status"] or event["target_id"] != shelter["id"]:
			continue
		failure = failure or event["event_type"] == "maintenance"
		blocked = blocked or event["event_type"] == "door"
		rats = rats or event["event_type"] == "rats"
	shelter["operational"] = shelter["base_operational"] and not failure
	shelter["operational_status"] = "ABSENT" if not shelter["exists"] else "MAINTENANCE FAILURE" if failure else "OPERATIONAL" if shelter["operational"] else "UNAVAILABLE"
	shelter["door_status"] = "ABSENT" if not shelter["exists"] else "BLOCKED" if blocked else shelter["manual_door_state"] if not shelter.get("manual_door_state", "").is_empty() else "CLOSED" if not shelter["accepting"] else "OPEN"
	shelter["maintenance_condition"] = 30.0 if failure else 100.0
	shelter["infested"] = rats
	shelter["current_occupancy"] = shelter["occupancy"]

static func set_door_state(shelter: Dictionary, state: String) -> bool:
	if not shelter["exists"] or state not in ["OPEN","CLOSING","CLOSED","OPENING","JAMMED","DESTROYED"]: return false
	if shelter.get("structural_state", "INTACT") == "DESTROYED" and state != "DESTROYED": return false
	shelter["manual_door_state"] = state
	shelter["door_status"] = state
	return true
