extends RefCounted
## Atomic admission and exit enforce current world truth at physical thresholds.


static func try_admit(agent: Dictionary, shelter: Dictionary, open_phase: bool) -> String:
	if agent["state"] == "SHELTERED" or not agent["shelter_id"].is_empty():
		return "Already admitted"
	if shelter.get("structural_state", "INTACT") == "DESTROYED":
		return "Shelter destroyed"
	if shelter.get("safety_status","SAFE") in ["UNSAFE","DESTROYED"]: return "Shelter unsafe"
	if not shelter.get("manual_accessible",true): return "Shelter entrance inaccessible"
	if not open_phase or not shelter["accepting"]:
		return "Admissions closed"
	if not shelter["exists"]:
		return "Shelter does not exist"
	if not shelter["operational"]:
		return "Shelter is not operational"
	if shelter.get("door_status", "OPEN") != "OPEN":
		return "Shelter door is blocked"
	if shelter["occupancy"] >= shelter["capacity"]:
		return "Shelter is full"
	if agent["position"].distance_to(shelter["position"]) > 0.01:
		return "Agent has not reached entrance"
	if agent["id"] in shelter["occupant_ids"]:
		return "Already admitted"
	shelter["occupant_ids"].append(agent["id"])
	shelter["occupancy"] = shelter["occupant_ids"].size()
	agent["shelter_id"] = shelter["id"]
	preload("res://scripts/shelter_state.gd").project(shelter)
	return ""

static func try_exit(agent: Dictionary, shelter: Dictionary) -> bool:
	if agent.get("shelter_id","")!=shelter.id or agent.id not in shelter.occupant_ids: return false
	if agent.position.distance_to(shelter.get("exit_position",shelter.position))>.01 or shelter.get("door_status","OPEN")!="OPEN": return false
	shelter.occupant_ids.erase(agent.id)
	shelter.occupancy=shelter.occupant_ids.size()
	agent.shelter_id=""
	preload("res://scripts/shelter_state.gd").project(shelter)
	return true
