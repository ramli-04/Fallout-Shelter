extends RefCounted
## Authoritative status. Derived availability never changes actual occupancy.

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
	shelter["entrance_position"] = shelter.position
	shelter["exit_position"] = shelter.position
	shelter["manual_accessible"] = true
	shelter["manual_safety_status"] = "SAFE"
	shelter["admission_rules"] = {"requires_operational":true,"requires_safe":true,"requires_open_door":true,"allows_overcapacity":false}
	project(shelter)

static func refresh(shelter: Dictionary, active_events: Array) -> void:
	shelter.safety_status=shelter.get("manual_safety_status","SAFE")
	if shelter.get("structural_state", "INTACT") == "DESTROYED":
		shelter["operational"] = false
		shelter["accepting"] = false
		shelter["door_status"] = "DESTROYED"
		shelter.safety_status="DESTROYED"
		project(shelter)
		return
	if shelter.get("structural_state", "INTACT") == "DAMAGED":
		shelter["door_status"] = "JAMMED"
		shelter["operational_status"] = "DAMAGED"
		shelter.safety_status="UNSAFE"
		project(shelter)
		return
	var failure := false
	var blocked := not bool(shelter.get("manual_accessible",true))
	var rats := false
	for event in active_events:
		if not event["active_status"] or event["target_id"] != shelter["id"]:
			continue
		if event.get("scope","")=="shelter":
			blocked=blocked or event.event_type=="door_malfunction"
			if event.event_type in ["fire","flooding","structural_damage","air_filtration_failure","ventilation_blockage"]:
				if float(event.severity)>=.65: shelter.safety_status="UNSAFE"
				elif shelter.safety_status=="SAFE": shelter.safety_status="WARNING"
			rats=rats or event.event_type=="rat_infestation"
			continue
		failure = failure or event["event_type"] == "maintenance"
		blocked = blocked or event["event_type"] == "door"
		rats = rats or event["event_type"] == "rats"
		failure = failure or event.event_type=="infrastructure_failure"
		blocked = blocked or event.event_type=="shelter_closure"
		if event.event_type in ["fire","explosion","danger_zone","increasing_threat","shelter_unsafe"]:
			if float(event.severity)>=.6 or event.event_type=="shelter_unsafe": shelter.safety_status="UNSAFE"
			elif shelter.safety_status=="SAFE": shelter.safety_status="WARNING"
	shelter["operational"] = shelter["base_operational"] and not failure
	shelter["operational_status"] = "ABSENT" if not shelter["exists"] else "MAINTENANCE FAILURE" if failure else "OPERATIONAL" if shelter["operational"] else "UNAVAILABLE"
	shelter["door_status"] = "ABSENT" if not shelter["exists"] else "BLOCKED" if blocked else shelter["manual_door_state"] if not shelter.get("manual_door_state", "").is_empty() else "CLOSED" if not shelter["accepting"] else "OPEN"
	shelter["maintenance_condition"] = 30.0 if failure else 100.0
	if shelter.has("storyteller_conditions"):
		for condition in shelter.storyteller_conditions.values(): shelter.maintenance_condition=minf(float(shelter.maintenance_condition),float(condition))
	shelter["infested"] = rats
	shelter["current_occupancy"] = shelter["occupancy"]
	project(shelter)

static func project(shelter: Dictionary) -> void:
	shelter.maximum_capacity=int(shelter.capacity)
	shelter.current_occupancy=int(shelter.occupancy)
	shelter.available_capacity=maxi(0,int(shelter.capacity)-int(shelter.occupancy))
	shelter.safety_status=shelter.get("safety_status",shelter.get("manual_safety_status","SAFE"))
	shelter.accessible=bool(shelter.exists) and bool(shelter.get("manual_accessible",true)) and shelter.get("door_status","OPEN")=="OPEN"
	shelter.admission_open=bool(shelter.accepting) and bool(shelter.operational) and shelter.accessible and shelter.safety_status not in ["UNSAFE","DESTROYED"] and shelter.available_capacity>0
	if shelter.available_capacity==0 and shelter.exists and shelter.operational: shelter.operational_status="FULL"

static func set_door_state(shelter: Dictionary, state: String) -> bool:
	if not shelter["exists"] or state not in ["OPEN","CLOSING","CLOSED","OPENING","JAMMED","DESTROYED"]: return false
	if shelter.get("structural_state", "INTACT") == "DESTROYED" and state != "DESTROYED": return false
	shelter["manual_door_state"] = state
	shelter["door_status"] = state
	project(shelter)
	return true
