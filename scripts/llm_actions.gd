extends RefCounted
## Validate intentions against current state; physical admission remains Godot-owned.
const Routes = preload("res://scripts/road_routes.gd")
const Beliefs = preload("res://scripts/agent_beliefs.gd")
const Rumors = preload("res://scripts/rumor_system.gd")
const ACTIONS := ["MOVE_TO_SHELTER", "WAIT", "OBSERVE", "COMMUNICATE", "DANCE", "FLEE_RANDOMLY", "HELP_AGENT", "FOLLOW_AGENT"]

static func apply(manager: Node, agent: Dictionary, decision: Dictionary) -> bool:
	if decision.size() != 5 or not (decision.get("confidence") is float or decision.get("confidence") is int):
		return false
	var confidence: float = decision["confidence"]
	if not is_finite(confidence) or confidence < 0 or confidence > 1:
		return false
	for key in ["action", "target", "message", "reason"]:
		if not decision.get(key) is String:
			return false
	var action: String = decision["action"]
	var target: String = decision["target"]
	if action not in ACTIONS or decision["reason"].length() > 240 or decision["message"].length() > 160 or target.length() > 64:
		return false
	if manager.phase not in ["EVACUATION", "BOMB_FALL"] or agent.get("health", 0) <= 0 or agent["state"] in ["SHELTERED", "EXPOSED", "SAFE"]:
		return false
	if agent["state"] in ["FROZEN", "HELPING", "DANCING", "STAGGERED"] and manager.elapsed_seconds < agent["wait_until"]:
		return false
	var other := {}
	if action in ["HELP_AGENT", "FOLLOW_AGENT"] or (action == "COMMUNICATE" and not target.is_empty()):
		for candidate in manager.agents:
			if candidate["id"] == target and target != agent["id"] and candidate["state"] not in ["SHELTERED", "EXPOSED", "SAFE"] and candidate["position"].distance_to(agent["position"]) <= manager.living["communication_radius"]:
				other = candidate
		if other.is_empty():
			return false
	if action == "FOLLOW_AGENT":
		target = other["objective"]
	if action in ["MOVE_TO_SHELTER", "CHANGE_DESTINATION", "FOLLOW_AGENT"]:
		if not agent["beliefs"].has(target) or agent["beliefs"][target]["unavailable"]:
			return false
		# Only the private believed location is used, including a possibly absent S5.
		var planned := Routes.plan(agent["position"], agent["beliefs"][target]["position"])
		if planned.is_empty(): return false
		agent["objective"] = target
		agent["route"] = planned
		agent["route_index"] = 1
		agent["current_goal"] = "Follow " + other["id"] + " toward " + target if action == "FOLLOW_AGENT" else "Reach " + target
		manager._set_state(agent, "MOVING")
	elif action == "HELP_AGENT":
		if agent["position"].distance_to(other["position"]) > manager.living["help_radius"]:
			return false
		other["panic_level"] = maxf(0, other["panic_level"]-manager.living["help_panic_reduction"])
		if other["state"] == "DANCING": other["wait_until"] = manager.elapsed_seconds
		agent["wait_until"] = manager.elapsed_seconds + manager.living["help_seconds"]
		agent["current_goal"] = "Help " + target
		manager._set_state(agent, "HELPING")
	elif action == "COMMUNICATE":
		if decision["message"].strip_edges().is_empty():
			return false
		var packet := {"rumor_id": "LLM:%s:%s" % [agent["id"], agent["llm_request_sequence"]],
			"claim": decision["message"], "kind": "conversation", "original_source": agent["id"],
			"current_speaker": agent["id"], "timestamp": manager.elapsed_seconds,
			"perceived_credibility": 0.65, "hops": 0}
		var recipients: Array[String] = []
		for recipient in manager.agents:
			if recipient["id"] == agent["id"] or (not target.is_empty() and recipient["id"] != target) or recipient["state"] in ["SHELTERED", "EXPOSED", "SAFE"]:
				continue
			if recipient["position"].distance_to(agent["position"]) <= manager.living["communication_radius"]:
				Rumors.receive(recipient, packet, agent, manager.elapsed_seconds, manager.living)
				recipients.append(recipient["id"])
		manager.ai_bridge.publish_event("agent.communications", {"speaker": agent["id"], "recipients": recipients, "message": decision["message"]}, agent["id"])
		# Conversation becomes evidence to evaluate; it never overwrites shelter truth.
		Beliefs.remember(agent, manager.elapsed_seconds, "I said: " + decision["message"], manager.living)
		agent["current_goal"] = "Warn nearby people: " + decision["message"]
		if agent["state"] == "DECIDING":
			agent["wait_until"] = manager.elapsed_seconds + 2
			manager._set_state(agent, "DELAYED")
	elif action == "DANCE":
		preload("res://scripts/civilian_activity.gd").dance(manager,agent,6.0)
	elif action == "FLEE_RANDOMLY":
		preload("res://scripts/civilian_activity.gd").scramble(manager,agent,3.0)
	else:
		if action == "OBSERVE":
			for shelter in manager.shelters:
				Beliefs.observe(agent, shelter, manager.elapsed_seconds, manager.living)
		agent["wait_until"] = manager.elapsed_seconds + manager.ai_config["decision_interval_seconds"]
		agent["current_goal"] = action.capitalize()
		manager._set_state(agent, "STAYING_HOME" if action == "STAY_HOME" else "DELAYED")
	agent["latest_llm_action"] = action
	agent["latest_llm_explanation"] = decision["reason"]
	agent["latest_llm_confidence"] = decision.get("confidence", 0.0)
	agent["fallback_reason"] = ""
	agent["decision_provider"] = "LOCAL_LLM"
	agent["decision_explanation"] = decision["reason"]
	agent["decision_history"].append({"time": manager.elapsed_seconds, "shelter_id": agent["objective"],
		"action": action, "target": decision["target"], "provider": "LOCAL_LLM", "explanation": decision["reason"]})
	while agent["decision_history"].size() > 100:
		agent["decision_history"].pop_front()
	Beliefs.remember(agent, manager.elapsed_seconds, action + ": " + decision["reason"], manager.living)
	manager.log_event("LLM", "%s %s %s: %s" % [agent["id"], action, target, decision["reason"]])
	return true
