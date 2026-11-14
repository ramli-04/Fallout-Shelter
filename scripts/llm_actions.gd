extends RefCounted
## Validate intentions against current state; physical admission remains Godot-owned.
const Routes = preload("res://scripts/road_routes.gd")
const Beliefs = preload("res://scripts/agent_beliefs.gd")
const Rumors = preload("res://scripts/rumor_system.gd")
const ACTIONS := ["MOVE_TO_SHELTER", "WAIT", "OBSERVE", "COMMUNICATE", "DANCE", "FLEE_RANDOMLY", "HELP_AGENT", "FOLLOW_AGENT", "CALL", "TEXT", "POST", "FIND_FAMILY", "DRIVE_TO_SHELTER", "CREATE_ROADBLOCK", "REMOVE_ROADBLOCK", "ISSUE_ALERT"]

static func apply(manager: Node, agent: Dictionary, decision: Dictionary, provider: String = "LOCAL_LLM") -> bool:
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
	if agent.get("police_unit_busy",false) and action not in ["CALL","TEXT","POST","COMMUNICATE","CREATE_ROADBLOCK","REMOVE_ROADBLOCK","ISSUE_ALERT"]: return false
	if action not in ACTIONS or decision["reason"].length() > 240 or decision["message"].length() > 160 or target.length() > 64:
		return false
	if manager.phase not in ["EVACUATION", "BOMB_FALL"] or agent.get("health", 0) <= 0 or agent["state"] in ["SHELTERED", "EXPOSED", "SAFE"]:
		return false
	if agent.get("cognition",{}).get("layer","")=="REFLEX" and manager.elapsed_seconds<float(agent.cognition.get("until",0)):
		return false
	if agent["state"] in ["FROZEN", "HELPING", "DANCING", "STAGGERED"] and manager.elapsed_seconds < agent["wait_until"]:
		return false
	if action in ["CALL","TEXT","POST","FIND_FAMILY","DRIVE_TO_SHELTER","CREATE_ROADBLOCK","REMOVE_ROADBLOCK","ISSUE_ALERT"]:
		if action=="DRIVE_TO_SHELTER" and not shelter_allowed(agent,target): return false
		return manager.social != null and manager.social.perform_action(agent,decision)
	var other := {}
	if action in ["HELP_AGENT", "FOLLOW_AGENT"] or (action == "COMMUNICATE" and not target.is_empty()):
		for candidate in manager.agents:
			if manager.can_observe(agent,candidate) and candidate["id"] == target and target != agent["id"] and candidate["state"] not in ["SHELTERED", "EXPOSED", "SAFE"] and candidate["position"].distance_to(agent["position"]) <= manager.living["communication_radius"]:
				other = candidate
		if other.is_empty():
			return false
	if action == "FOLLOW_AGENT":
		target = other["objective"]
	if action in ["MOVE_TO_SHELTER", "CHANGE_DESTINATION", "FOLLOW_AGENT"]:
		if not shelter_allowed(agent,target):
			return false
		# Only the private believed location is used, including a possibly absent S5.
		var origin: Vector2=agent.get("indoor_exit",agent.position) if agent.get("indoor_id","")!="" else agent.position
		var planned := Routes.plan(origin, agent["beliefs"][target]["position"])
		if planned.is_empty(): return false
		if agent.get("evacuation_group","")!="": manager.social.evacuation.leave_group(agent,"Independent intention from "+provider)
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
			if not manager.can_observe(agent,recipient) or recipient["id"] == agent["id"] or (not target.is_empty() and recipient["id"] != target) or recipient["state"] in ["SHELTERED", "EXPOSED", "SAFE"]:
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
		if agent.get("evacuation_group","")!="": manager.social.evacuation.leave_group(agent,"Independent intention from "+provider)
		preload("res://scripts/civilian_activity.gd").scramble(manager,agent,3.0)
	else:
		if action == "OBSERVE":
			for shelter in manager.shelters:
				Beliefs.observe(agent, shelter, manager.elapsed_seconds, manager.living)
		agent["wait_until"] = manager.elapsed_seconds + manager.ai_config["decision_interval_seconds"]
		agent["current_goal"] = action.capitalize()
		manager._set_state(agent, "STAYING_HOME" if action == "STAY_HOME" else "DELAYED")
	if provider == "LOCAL_LLM":
		agent["latest_llm_action"] = action
		agent["latest_llm_explanation"] = decision["reason"]
		agent["latest_llm_confidence"] = decision.get("confidence", 0.0)
	agent["fallback_reason"] = ""
	agent["decision_provider"] = provider
	agent["decision_explanation"] = decision["reason"]
	agent["decision_history"].append({"time": manager.elapsed_seconds, "shelter_id": agent["objective"],
		"action": action, "target": decision["target"], "provider": provider, "explanation": decision["reason"]})
	while agent["decision_history"].size() > 100:
		agent["decision_history"].pop_front()
	Beliefs.remember(agent, manager.elapsed_seconds, action + ": " + decision["reason"], manager.living)
	manager.log_event(provider, "%s %s %s: %s" % [agent["id"], action, target, decision["reason"]])
	return true

static func shelter_allowed(agent: Dictionary, target: String) -> bool:
	if target in agent.get("evacuation_excluded_shelters",[]) or not agent.beliefs.has(target): return false
	var belief: Dictionary=agent.beliefs[target]
	if belief.unavailable or not belief.get("accessible",true) or belief.get("safety_status","SAFE") in ["UNSAFE","DESTROYED"]: return false
	return not agent.get("evacuation_requires_verified",false) or (float(belief.existence_probability)>=1.0 and float(belief.confidence)>=.7 and belief.get("safety_status","")=="SAFE")
