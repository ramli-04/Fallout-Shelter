extends RefCounted
## Seeded physical/social behavior. No hidden deadline or world secrets enter choices.
const Map = preload("res://scripts/city_map.gd")
const Routes = preload("res://scripts/road_routes.gd")
const Beliefs = preload("res://scripts/agent_beliefs.gd")

static func initialize(manager: Node, agent: Dictionary) -> void:
	agent["run_speed"] = agent["movement_speed"]
	agent["walk_speed"] = agent["movement_speed"]*manager.activity_config["walking_speed_fraction"]
	agent["appearance_seed"] = manager.seed_value+int(str(agent["id"]).substr(1))*917
	agent["activity_counter"] = 0
	agent["free_movement"] = true
	agent["next_push_time"] = 0.0
	agent["next_scramble_time"] = 0.0
	agent["roam_pause_until"] = 0.0
	agent["defiance_decided"] = false
	agent["sheltered_at"] = INF
	agent["fear_door_attempted"] = false

static func random(agent: Dictionary) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	agent["activity_counter"] = int(agent.get("activity_counter",0))+1
	rng.seed = int(agent.get("appearance_seed",1))+int(agent["activity_counter"])*4099
	return rng

static func random_destination(manager: Node, agent: Dictionary, low: float, high: float) -> Vector2:
	var rng := random(agent)
	for _i in range(32):
		var angle := rng.randf()*TAU
		var point: Vector2 = agent["position"]+Vector2(cos(angle),sin(angle))*rng.randf_range(low,high)
		if Map.clear_point(point) and not Routes.plan(agent["position"],point).is_empty(): return point
	return agent["position"]

static func roam(manager: Node, duration: float) -> void:
	for agent in manager.agents:
		agent["previous_position"] = agent["position"]
		if manager.elapsed_seconds < agent["roam_pause_until"]: continue
		if agent["state"] != "ROAMING" or agent["route_index"] >= agent["route"].size():
			var distances: Array = manager.activity_config["roam_distance_range"]
			var target := random_destination(manager,agent,distances[0],distances[1])
			agent["route"] = Routes.plan(agent["position"],target)
			agent["route_index"] = 1
			agent["movement_speed"] = agent["walk_speed"]
			agent["current_goal"] = "Walk around the neighborhood"
			manager._set_state(agent,"ROAMING")
		if Routes.move(agent,duration)["arrived"]:
			agent["roam_pause_until"] = manager.elapsed_seconds+random(agent).randf_range(1,4)
			agent["current_goal"] = "Look around / greet neighbors"
			manager._set_state(agent,"CHATTING")

static func dance(manager: Node, agent: Dictionary, seconds: float) -> void:
	agent["wait_until"] = manager.elapsed_seconds+seconds
	agent["current_goal"] = "Dance defiantly instead of evacuating for a while"
	manager._set_state(agent,"DANCING")
	Beliefs.remember(agent,manager.elapsed_seconds,"Chose a brief defiant dance; can still reconsider or accept help",manager.living)
	manager.log_event("REACTION","%s dances instead of immediately seeking shelter." % agent["id"])

static func scramble(manager: Node, agent: Dictionary, seconds: float = 3.0) -> void:
	var destination := random_destination(manager,agent,60,160)
	agent["route"] = Routes.plan(agent["position"],destination)
	agent["route_index"] = 1
	agent["wait_until"] = manager.elapsed_seconds+seconds
	agent["next_scramble_time"] = manager.elapsed_seconds+random(agent).randf_range(9,18)
	agent["current_goal"] = "Run in panic, then reconsider a shelter"
	manager._set_state(agent,"SCRAMBLING")

static func special(manager: Node, agent: Dictionary, duration: float) -> bool:
	var time: float = manager.elapsed_seconds
	if agent["state"] == "SHELTERED":
		if time-agent["sheltered_at"] >= 2 and not agent["fear_door_attempted"]:
			agent["fear_door_attempted"] = true
			if agent["panic_level"] >= 72 and agent["self_preservation"] >= 55 and random(agent).randf() < 0.65:
				var shelter: Dictionary = manager.shelter_by_id[agent["shelter_id"]]
				if shelter["door_status"] == "OPEN":
					shelter["accepting"] = false
					manager.ShelterState.set_door_state(shelter,"CLOSING")
					shelter["fear_close_at"] = time+manager.activity_config["door_close_seconds"]
					shelter["closed_by_agent"] = agent["id"]
					shelter["event_history"].append({"time":time,"kind":"fear_closure","agent_id":agent["id"]})
					manager.log_event("DOOR","%s starts sealing %s early out of fear; others may be shut out." % [agent["id"],shelter["id"]])
		return true
	if agent["state"] in ["DANCING","STAGGERED"]:
		if time >= agent["wait_until"]:
			agent["route"] = PackedVector2Array()
			manager._set_state(agent,"DECIDING")
			manager.choose_destination(agent)
		return true
	if not agent["defiance_decided"]:
		agent["defiance_decided"] = true
		var type: String = agent["primary_personality"]
		var chance: float = manager.activity_config["nihilist_dance_probability"] if type == "NIHILIST" else manager.activity_config["despairing_dance_probability"] if type == "DESPAIRING" else 0.0
		if random(agent).randf() < chance:
			dance(manager,agent,random(agent).randf_range(8,22))
			return true
	if agent["state"] == "SCRAMBLING":
		if time >= agent["wait_until"] or Routes.move(agent,duration)["arrived"]:
			agent["route"] = PackedVector2Array()
			manager._set_state(agent,"DECIDING")
			manager.choose_destination(agent)
		return true
	if agent["state"] == "MOVING" and agent["panic_level"] >= manager.activity_config["panic_scramble_threshold"] and time >= agent["next_scramble_time"]:
		agent["next_scramble_time"] = time+12
		if random(agent).randf() < 0.25:
			scramble(manager,agent)
			return true
	return false

static func crowd_actions(manager: Node) -> void:
	var time: float = manager.elapsed_seconds
	for shelter in manager.shelters:
		if shelter.has("fear_close_at") and time >= shelter["fear_close_at"]:
			manager.ShelterState.set_door_state(shelter,"CLOSED")
			shelter.erase("fear_close_at")
	for agent in manager.agents:
		if agent["state"] not in ["MOVING","SCRAMBLING"] or time < agent["next_push_time"]: continue
		agent["next_push_time"] = time+0.6
		if agent["cooperation"] >= 45 or (agent["panic_level"] < 70 and agent["primary_personality"] != "AGGRESSIVE"): continue
		for other in manager.agents:
			if other == agent or other["state"] not in ["MOVING","SCRAMBLING","DANCING"]: continue
			var delta: Vector2 = other["position"]-agent["position"]
			if delta.length() > manager.activity_config["push_radius"]: continue
			var direction := delta.normalized() if delta.length() > 0.01 else Vector2.RIGHT
			var pushed: Vector2 = other["position"]+direction*manager.activity_config["push_distance"]
			if not Map.clear_point(pushed) or not Map.clear_segment(other["position"],pushed): continue
			other["position"] = pushed
			other["wait_until"] = time+0.8
			other["panic_level"] = minf(100,other["panic_level"]+8)
			other["trust_relationships"][agent["id"]] = maxf(0,float(other["trust_relationships"].get(agent["id"],0.5))-0.15)
			agent["push_animation_until"] = time+0.55
			agent["next_push_time"] = time+3.0
			manager._set_state(other,"STAGGERED")
			Beliefs.remember(other,time,"Was pushed by "+agent["id"],manager.living)
			manager.log_event("PUSH","%s pushes %s in the crowd." % [agent["id"],other["id"]])
			break
