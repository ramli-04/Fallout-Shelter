extends RefCounted
## Bounded local messages. A recipient interprets claims rather than copying another mind.

const Beliefs = preload("res://scripts/agent_beliefs.gd")
const CLAIMS := ["Shelter 5 is real.", "Shelter 2 is broken.", "Shelter 1 is already full.", "Shelter 4 has plenty of supplies.", "The alarm might be false."]

static func initialize(agents: Array) -> void:
	for i in range(mini(CLAIMS.size(), agents.size())):
		var rumor := {"rumor_id": "R%d" % i, "claim": CLAIMS[i], "original_source": agents[i]["id"], "current_speaker": agents[i]["id"], "timestamp": 0.0, "perceived_credibility": 0.65, "hops": 0, "kind": "rumor"}
		agents[i]["messages"].append(rumor)
		agents[i]["heard_ids"][rumor["rumor_id"]] = true

static func receive(agent: Dictionary, message: Dictionary, speaker: Dictionary, time: float, config: Dictionary) -> String:
	var id: String = message["rumor_id"]
	if agent["heard_ids"].has(id):
		return "duplicate"
	agent["heard_ids"][id] = true
	while agent["heard_ids"].size() > int(config["rumor_history_limit"])*8:
		agent["heard_ids"].erase(agent["heard_ids"].keys()[0])
	var own := message.duplicate(true)
	own["current_speaker"] = speaker["id"]
	own["hops"] = int(message["hops"]) + 1
	var authority_bonus := float(agent["authority_trust"]) / 400.0 if speaker["role"] == "Authority" else 0.0
	var memory_modifier := 0.0
	for prior in agent["rumors_heard"]:
		if prior["original_source"] == message["original_source"]:
			memory_modifier = (float(prior["perceived_credibility"])-0.5)*0.1
	var credibility := clampf(float(message["perceived_credibility"]) * 0.45 + float(agent["trust_level"])/150.0 - float(agent["skepticism"])/200.0 + authority_bonus + memory_modifier - own["hops"]*0.04, 0, 1)
	var reaction := "believe" if credibility >= 0.60 else "reject" if credibility <= 0.25 else "investigate" if agent["skepticism"] >= 60 else "doubt"
	if own.get("kind", "rumor") == "observation":
		var shelter_id: String = own["shelter_id"]
		var belief: Dictionary = agent["beliefs"][shelter_id]
		# Fresh first-hand evidence outranks second-hand reports, even trusted reports.
		if float(belief["observed_at"]) < float(message["timestamp"]) and credibility > 0.25:
			var evidence: Dictionary = own["evidence"]
			for key in ["capacity", "capacity_exact", "estimated_occupancy", "existence_probability", "unavailable", "risk"]:
				belief[key] = evidence[key]
			belief["confidence"] = credibility
			belief["source"] = "Report via %s; observed by %s" % [speaker["id"], message["original_source"]]
			reaction = "believe report"
	elif reaction == "believe":
		_apply_claim(agent, own["claim"], time)
	elif reaction == "investigate":
		agent["current_goal"] = "Investigate: " + own["claim"]
		if own["claim"] == CLAIMS[0]:
			agent["recommendations"]["S5"] = 0.25
	if own.get("kind", "rumor") == "recommendation" and credibility > 0.4:
		agent["recommendations"][own["shelter_id"]] = credibility
	own["perceived_credibility"] = credibility
	own["reaction"] = reaction
	agent["rumors_heard"].append(own)
	while agent["rumors_heard"].size() > int(config["rumor_history_limit"]):
		agent["rumors_heard"].pop_front()
	if reaction != "reject" and agent["cooperation"] + agent["sociability"] > 85:
		agent["messages"].append(own)
		while agent["messages"].size() > int(config["rumor_history_limit"]):
			agent["messages"].pop_front()
	Beliefs.remember(agent, time, "%s from %s: %s (credibility %.0f%%)" % [reaction, speaker["id"], own["claim"], credibility*100], config)
	return reaction

static func _apply_claim(agent: Dictionary, claim: String, time: float) -> void:
	var id := "S5" if claim == CLAIMS[0] else "S2" if claim == CLAIMS[1] else "S1" if claim == CLAIMS[2] else "S4"
	if claim == CLAIMS[4]:
		agent["alarm_confidence"] = maxf(0.15, agent["alarm_confidence"]-0.3)
		return
	var belief: Dictionary = agent["beliefs"][id]
	if float(belief["observed_at"]) >= 0:
		return
	if claim == CLAIMS[0]:
		belief["existence_probability"] = 0.85
	elif claim == CLAIMS[1]:
		belief["unavailable"] = true
	elif claim == CLAIMS[2]:
		belief["estimated_occupancy"] = belief["capacity"]
	elif claim == CLAIMS[3]:
		belief["resource_score"] = 1.0
	belief["source"] = "Unverified rumor at %.1fs" % time

static func observation_message(agent: Dictionary, shelter_id: String, time: float) -> Dictionary:
	return {"rumor_id": "OBS:%s:%s:%.1f" % [agent["id"], shelter_id, time], "claim": "%s entrance observed" % shelter_id,
		"original_source": agent["id"], "current_speaker": agent["id"], "timestamp": time, "perceived_credibility": 0.95,
		"hops": 0, "kind": "observation", "shelter_id": shelter_id, "evidence": agent["beliefs"][shelter_id].duplicate(true)}

static func exchange(manager: Node) -> void:
	var config: Dictionary = manager.living
	var time: float = manager.elapsed_seconds
	# A snapshot prevents a message propagating arbitrarily far within one contact tick.
	var snapshots := {}
	for agent in manager.agents:
		snapshots[agent["id"]] = agent["messages"].duplicate(true)
	for speaker in manager.agents:
		var chosen := {}
		for message in snapshots[speaker["id"]]:
			if time-message["timestamp"] <= config["rumor_ttl_seconds"] and int(message["hops"]) < int(config["rumor_max_hops"]) and not speaker["shared_ids"].has(message["rumor_id"]):
				chosen = message
				break
		if chosen.is_empty():
			continue
		var contacted := false
		for recipient in manager.agents:
			if recipient == speaker or recipient["position"].distance_to(speaker["position"]) > config["communication_radius"]:
				continue
			var reaction := receive(recipient, chosen, speaker, time, config)
			if reaction != "duplicate":
				contacted = true
				manager.log_event("RUMOR", "%s %s '%s' from %s." % [recipient["id"], reaction, chosen["claim"], speaker["id"]])
		if contacted:
			speaker["shared_ids"][chosen["rumor_id"]] = true
		# Expired packets and bookkeeping are pruned; memories stay bounded separately.
		speaker["messages"] = speaker["messages"].filter(func(m: Dictionary): return time-m["timestamp"] <= config["rumor_ttl_seconds"])
		var live_ids := {}
		for message in speaker["messages"]:
			live_ids[message["rumor_id"]] = true
		for id in speaker["shared_ids"].keys():
			if not live_ids.has(id):
				speaker["shared_ids"].erase(id)
	# S3 repeats only deposited observations, never queries other shelters' truth.
	var relay: Dictionary = manager.shelter_by_id["S3"]
	if not relay["operational"]:
		return
	for agent in manager.agents:
		if agent["position"].distance_to(relay["position"]) <= config["observation_radius"]:
			for message in snapshots[agent["id"]]:
				if message["kind"] == "observation" and time-message["timestamp"] <= config["rumor_ttl_seconds"] and not relay["relay_messages"].any(func(m: Dictionary): return m["rumor_id"] == message["rumor_id"]):
					relay["relay_messages"].append(message)
					if relay["relay_messages"].size() > 8:
						relay["relay_messages"].pop_front()
		if agent["position"].distance_to(relay["position"]) <= config["relay_radius"]:
			for message in relay["relay_messages"]:
				if time-message["timestamp"] > config["rumor_ttl_seconds"] or int(message["hops"]) >= int(config["rumor_max_hops"]):
					continue
				var reaction := receive(agent, message, {"id": "S3 relay", "role": "Authority"}, time, config)
				if reaction != "duplicate":
					manager.log_event("RELAY", "%s received an observation through S3: %s." % [agent["id"], reaction])
