extends RefCounted
## Reads a private mind plus locally visible people; never shelter/director truth.
const PROFILE := ["id", "role", "primary_personality", "secondary_personality", "panic_level", "trust_level", "skepticism", "cooperation", "risk_tolerance", "self_preservation", "empathy", "authority_trust", "sociability", "companion_id"]
const BELIEF := ["position", "capacity", "capacity_exact", "size_description", "estimated_occupancy", "resource_score", "risk", "popularity", "official_support", "existence_probability", "confidence", "unavailable", "observed_at", "source", "last_update_time", "evidence_type", "original_source"]
const MESSAGE := ["rumor_id", "claim", "original_source", "current_speaker", "timestamp", "perceived_credibility", "hops", "kind", "shelter_id", "reaction"]

static func pick(record: Dictionary, fields: Array) -> Dictionary:
	var result := {}
	for key in fields:
		if record.has(key):
			var value: Variant = record[key]
			result[key] = [value.x, value.y] if value is Vector2 else value
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
		if other["id"] != agent["id"] and other["state"] not in ["SHELTERED", "EXPOSED", "SAFE"] and other["position"].distance_to(agent["position"]) <= manager.living["communication_radius"]:
			nearby.append(pick(other, ["id", "role", "position", "state"]))
	return {"profile": pick(agent, PROFILE), "beliefs": beliefs, "memories": memories,
		"messages": messages, "nearby_agents": nearby,
		"position": [agent["position"].x, agent["position"].y],
		"destination": agent["objective"], "goal": agent["current_goal"],
		"trust_relationships": agent.get("trust_relationships", {}).duplicate(),
		"simulation_time": manager.elapsed_seconds,
		"estimated_time_remaining": maxf(30, agent["perceived_warning_seconds"] - (manager.elapsed_seconds-manager.alarm_started_seconds))}
