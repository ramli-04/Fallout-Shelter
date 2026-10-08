extends RefCounted
## Local perception and social actions. The controller, not a decision policy, supplies observations.

const Beliefs = preload("res://scripts/agent_beliefs.gd")
const Rumors = preload("res://scripts/rumor_system.gd")

static func perceive(manager: Node) -> void:
	for agent in manager.agents:
		for shelter in manager.shelters:
			if Beliefs.observe(agent, shelter, manager.elapsed_seconds, manager.living):
				var message := Rumors.observation_message(agent, shelter["id"], manager.elapsed_seconds)
				agent["messages"].append(message)
				while agent["messages"].size() > int(manager.living["rumor_history_limit"]):
					agent["messages"].pop_front()
				manager.log_event("OBSERVED", "%s observed %s: %s." % [agent["id"], shelter["id"], agent["beliefs"][shelter["id"]]["source"]])
		for event in manager.environment_events:
			if not event["active_status"] or agent["position"].distance_to(event["target_location"]) > manager.living["event_radius"] or agent["id"] in event["visibility_to_agents"]:
				continue
			event["visibility_to_agents"].append(agent["id"])
			if event["event_type"] == "crowd":
				agent["panic_level"] = minf(100, agent["panic_level"] + 35*event["severity"])
				agent["avoided_locations"].append({"position": event["target_location"], "until": manager.alarm_started_seconds + event["scheduled_time"] + event["duration"]})
			Beliefs.remember(agent, manager.elapsed_seconds, event["event_log_message"] + " observed", manager.living)
			manager.log_event("ENVIRONMENT", "%s reported %s." % [agent["id"], event["event_log_message"]])

static func act(manager: Node, agent: Dictionary, duration: float) -> bool:
	var time: float = manager.elapsed_seconds
	agent["panic_level"] = maxf(0, agent["panic_level"] - manager.living["panic_decay_per_second"]*duration)
	agent["avoided_locations"] = agent["avoided_locations"].filter(func(a: Dictionary): return a["until"] > time)
	if agent["state"] in ["SHELTERED", "EXPOSED", "SAFE"]:
		return false
	if agent["state"] in ["DELAYED", "FROZEN", "HELPING", "STAYING_HOME"]:
		if time < agent["wait_until"]:
			return false
		manager._set_state(agent, "DECIDING")
		manager.choose_destination(agent)
	if agent["panic_level"] >= manager.living["freeze_threshold"] and agent["primary_personality"] == "OVERWHELMED" and time >= agent["freeze_cooldown_until"]:
		agent["wait_until"] = time + manager.living["freeze_seconds"]
		agent["freeze_cooldown_until"] = time + manager.living["freeze_cooldown_seconds"]
		agent["current_goal"] = "Recover from acute stress"
		manager._set_state(agent, "FROZEN")
		Beliefs.remember(agent, time, "Paused under extreme stress; will reconsider after recovering", manager.living)
		manager.log_event("REACTION", "%s froze temporarily under extreme stress." % agent["id"])
		return false
	if agent["primary_personality"] == "DENIAL" and agent["alarm_confidence"] < 0.4 and not agent.get("home_delay_used", false):
		agent["home_delay_used"] = true
		agent["wait_until"] = time + agent["reaction_delay"]
		agent["current_goal"] = "Stay home briefly; doubts alarm reliability"
		manager._set_state(agent, "STAYING_HOME")
		manager.log_event("REACTION", "%s delays leaving home while doubting the alarm." % agent["id"])
		return false
	if agent["primary_personality"] in ["COOPERATIVE", "SELF-SACRIFICING", "FAMILY-ORIENTED"] and agent["cooperation"] + agent["empathy"] >= 120:
		for other in manager.agents:
			if other == agent or other["state"] in ["SHELTERED", "EXPOSED"] or other["id"] in agent["helped_ids"]:
				continue
			if agent["primary_personality"] == "FAMILY-ORIENTED" and other["id"] != agent["companion_id"]:
				continue
			if other["panic_level"] >= 65 and agent["position"].distance_to(other["position"]) <= manager.living["help_radius"]:
				agent["helped_ids"].append(other["id"])
				other["panic_level"] = maxf(0, other["panic_level"]-manager.living["help_panic_reduction"])
				agent["wait_until"] = time + manager.living["help_seconds"]
				agent["current_goal"] = "Help " + other["id"]
				manager._set_state(agent, "HELPING")
				Beliefs.remember(agent, time, "Spent time calming " + other["id"], manager.living)
				manager.log_event("HELP", "%s helps %s, delaying their own evacuation." % [agent["id"], other["id"]])
				return false
	return agent["state"] == "MOVING"

static func social_observations(manager: Node) -> void:
	for agent in manager.agents:
		var crowds := {}
		for other in manager.agents:
			if other == agent or other["objective"].is_empty() or agent["position"].distance_to(other["position"]) > manager.living["communication_radius"]:
				continue
			var id: String = other["objective"]
			crowds[id] = int(crowds.get(id, 0)) + 1
			if other["id"] == agent["companion_id"] and agent["primary_personality"] == "FAMILY-ORIENTED":
				agent["recommendations"][id] = 1.0
		agent["observed_crowds"] = crowds
