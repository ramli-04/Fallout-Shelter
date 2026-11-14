class_name AgentObservationBuilder
extends RefCounted
## Reads a private mind plus locally visible people; never shelter/director truth.
const PROFILE := ["id", "role", "primary_personality", "secondary_personality", "panic_level", "trust_level", "skepticism", "cooperation", "risk_tolerance", "self_preservation", "empathy", "authority_trust", "sociability", "companion_id", "courage", "leadership", "name", "age", "occupation", "iq", "stress_tolerance", "adaptability", "family_id", "fatigue", "health", "family_concern", "home_location", "workplace", "school", "has_phone", "social_user", "vehicle_id", "safety", "social_attachment", "stress", "routine", "location_mode", "police_unit_id", "police_unit_busy", "police_animation", "duty_task", "police_instruction", "evacuation_group", "evacuation_member_status", "evacuation_order", "police_operation_briefing"]
const BELIEF := ["accessible","safety_status","subject","claimed_value","acquired_at","status","position", "capacity", "capacity_exact", "size_description", "estimated_occupancy", "resource_score", "risk", "popularity", "official_support", "existence_probability", "confidence", "unavailable", "observed_at", "source", "last_update_time", "evidence_type", "original_source"]
const MESSAGE := ["rumor_id", "claim", "original_source", "current_speaker", "timestamp", "perceived_credibility", "hops", "kind", "shelter_id", "reaction"]

static func pick(record: Dictionary, fields: Array) -> Dictionary:
	var result := {}
	for key in fields:
		if record.has(key):
			var value: Variant = record[key]
			result[key] = json_value(value)
	return result

static func generate(manager: Node, agent: Dictionary) -> Dictionary:
	var beliefs := {}
	for id in agent["beliefs"]:
		beliefs[id] = pick(agent["beliefs"][id], BELIEF)
	var memories := []
	for entry in agent["personal_memory"].slice(-12):
		memories.append(pick(entry, ["time", "text"]))
	var messages := []
	var known_messages: Array = agent["rumors_heard"].duplicate()
	for entry in agent["messages"]:
		if not known_messages.any(func(m): return m["rumor_id"] == entry["rumor_id"]):
			known_messages.append(entry)
	for entry in known_messages.slice(-8):
		messages.append(pick(entry, MESSAGE))
	var nearby := []
	for other in manager.agents:
		if manager.can_observe(agent,other) and other["id"] != agent["id"] and other["state"] not in ["SHELTERED", "EXPOSED", "SAFE"] and other["position"].distance_to(agent["position"]) <= manager.living["communication_radius"]:
			nearby.append(pick(other, ["id", "role", "position", "state"]))
	return {"profile": pick(agent, PROFILE), "beliefs": beliefs, "memories": memories,
		"messages": messages, "nearby_agents": nearby,
		"perceptions": cognitive_records(agent,"observations"),
		"experience": cognitive_records(agent,"memory"),
		"cognitive_traits": agent.get("cognitive_traits",{}).duplicate(),
		"excluded_shelters": agent.get("evacuation_excluded_shelters",[]).duplicate(),
		"requires_verified_shelter": bool(agent.get("evacuation_requires_verified",false)),
		"position": [agent["position"].x, agent["position"].y],
		"destination": agent["objective"], "goal": agent["current_goal"],
		"trust_relationships": agent.get("trust_relationships", {}).duplicate(),
		"family_relationships": agent.get("relationships", {}).duplicate(true),
		"social_beliefs": agent.get("social_beliefs", {}).duplicate(true),
		"known_family_locations": family_locations(agent),
		"received_phone_messages": agent.get("inbox", []).duplicate(true),
		"simulation_time": manager.elapsed_seconds,
		"estimated_time_remaining": maxf(30, agent["perceived_warning_seconds"] - (manager.elapsed_seconds-manager.alarm_started_seconds))}

static func family_locations(agent: Dictionary) -> Dictionary:
	var result := {}
	for id in agent.get("known_locations", {}):
		result[id]=pick(agent.known_locations[id],["position","source","timestamp","confidence"])
	return result

static func cognitive_records(agent: Dictionary, key: String) -> Array:
	var result: Array=[]
	for item in agent.get("cognition",{}).get(key,[]).slice(-24):
		result.append(pick(item,["kind","id","position","distance","severity","confidence","timestamp","speed","heading","state"]))
	return result

static func json_value(value: Variant) -> Variant:
	if value is Vector2: return [value.x,value.y]
	if value is Dictionary:
		var out: Dictionary={}
		for key in value: out[key]=json_value(value[key])
		return out
	if value is Array:
		var out: Array=[]
		for item in value: out.append(json_value(item))
		return out
	return value
