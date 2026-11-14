extends RefCounted
## Pure policy: takes private beliefs and subjective urgency, never world shelters or deadline.
const Routes = preload("res://scripts/road_routes.gd")

static func initialize_beliefs(definitions: Array, rng: RandomNumberGenerator, _uncertainty: float) -> Dictionary:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/living_world.json"))
	return preload("res://scripts/agent_beliefs.gd").initialize(definitions, rng, config)

static func evaluate(agent: Dictionary, remaining: float, weights: Dictionary) -> Dictionary:
	var scores := {}
	var best_id := ""
	var best_score := -INF
	var best_route := PackedVector2Array()
	var best_eta := INF
	var caution := 1.0 - float(agent["risk_tolerance"])/100.0
	var type: String = agent["primary_personality"]
	var risk_factor := 1.5 if type == "CAUTIOUS" else 0.6 if type in ["OPTIMISTIC", "AGGRESSIVE"] else 1.0
	var social_factor := 1.6 if type == "FOLLOWER" else 1.0
	var travel_factor := 2.5 if agent["panic_level"] > 75 else 1.4 if type == "SURVIVALIST" else 1.0
	travel_factor *= 0.7 + agent["self_preservation"]/166.7
	for shelter_id in agent["beliefs"]:
		var belief: Dictionary = agent["beliefs"][shelter_id]
		var origin: Vector2=agent.get("indoor_exit",agent.position) if agent.get("indoor_id","")!="" else agent.position
		var route := Routes.plan(origin, belief["position"])
		if route.is_empty():
			scores[shelter_id] = {"eligible": false, "reason": "No clear route"}
			continue
		var distance: float=Routes.length(route)+agent.position.distance_to(origin)
		if not agent.get("force_route_replan",false) and agent["objective"] == shelter_id and not agent["route"].is_empty():
			distance = Routes.remaining_distance(agent)
		var eta: float = distance / agent["movement_speed"]
		# Synthetic IQ changes only subjective travel-time estimation by a bounded small amount.
		eta *= 1.0 + clampf((100-float(agent.get("iq",100)))/45,-1,1)*minf(.1,float(agent.get("iq_influence",0)))
		var verified: bool=not agent.get("evacuation_requires_verified",false) or (float(belief.existence_probability)>=1.0 and float(belief.confidence)>=.7 and belief.get("safety_status","")=="SAFE")
		var eligible: bool = verified and shelter_id not in agent.get("evacuation_excluded_shelters",[]) and not belief["unavailable"] and belief.get("accessible",true) and belief.get("safety_status","SAFE") not in ["UNSAFE","DESTROYED"] and belief["existence_probability"] > 0 and belief["estimated_occupancy"] < belief["capacity"] and eta <= remaining + 0.00001
		if not eligible:
			scores[shelter_id] = {"eligible": false, "score": null, "eta": eta, "reason": "Unavailable, believed full, or beyond own warning estimate"}
			continue
		var capacity_fraction: float = maxf(0, belief["capacity"] - belief["estimated_occupancy"]) / weights["capacity_normalizer"]
		var score: float = weights["resources"] * belief["resource_score"]
		score += weights["capacity"] * capacity_fraction
		score += weights["popularity"] * agent["sociability"]/100.0 * social_factor * belief["popularity"]
		score += weights["authority"] * agent["authority_trust"]/100.0 * belief["official_support"]
		score -= weights["travel"] * travel_factor * eta / maxf(remaining, 0.001)
		score -= weights["risk"] * caution * risk_factor * belief["risk"]
		score -= weights["existence"] * caution * (1.0 - belief["existence_probability"])
		score -= weights["uncertainty"] * (caution + agent["skepticism"]/200.0) * (1.0 - belief["confidence"])
		score += float(agent.get("recommendations", {}).get(shelter_id, 0)) * (1.5 if type in ["FOLLOWER", "FAMILY-ORIENTED"] else 0.3)
		score += float(agent.get("observed_crowds", {}).get(shelter_id, 0)) * agent["sociability"]/300.0
		var family_support:=0.0
		for member in agent.get("relationships",{}):
			var remembered: Dictionary=agent.get("known_locations",{}).get(member,{})
			if not remembered.is_empty() and remembered.position.distance_to(belief.position)<65:
				family_support+=float(remembered.get("confidence",.5))*float(agent.get("cognitive_traits",{}).get("family_attachment",50))/100.0
		score+=minf(2,family_support)
		for hazard in agent.get("avoided_locations", []):
			for i in range(1, route.size()):
				if Geometry2D.get_closest_point_to_segment(hazard["position"], route[i-1], route[i]).distance_to(hazard["position"]) < 65:
					score -= 2*caution + agent["panic_level"]/100.0
					break
		scores[shelter_id] = {"eligible": true, "score": score, "eta": eta, "distance": distance}
		if score > best_score:
			best_id = shelter_id
			best_score = score
			best_route = route
			best_eta = eta
	var explanation := "No known option fits my warning estimate; wait for information and reconsider."
	if not best_id.is_empty():
		var belief: Dictionary = agent["beliefs"][best_id]
		explanation = "%s leads (%.2f); ETA %.1fs, own urgency estimate %.1fs. Existence belief %.0f%%; %s, panic %.0f. %s." % [best_id, best_score, best_eta, remaining, belief["existence_probability"]*100, type, agent["panic_level"], belief["source"]]
	return {"shelter_id": best_id, "score": best_score, "scores": scores, "route": best_route, "eta": best_eta, "explanation": explanation}
