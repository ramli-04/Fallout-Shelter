extends RefCounted
## Admission is the only place where arrival discovers actual shelter availability.


static func try_admit(agent: Dictionary, shelter: Dictionary, open_phase: bool) -> String:
	if agent["state"] == "SHELTERED" or not agent["shelter_id"].is_empty():
		return "Already admitted"
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
	return ""
