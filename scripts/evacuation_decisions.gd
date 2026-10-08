extends RefCounted
## Receives agent beliefs only. Runtime shelter truth is deliberately unavailable.

const Routes = preload("res://scripts/road_routes.gd")


static func initialize_beliefs(definitions: Array, rng: RandomNumberGenerator, uncertainty: float) -> Dictionary:
	var beliefs := {}
	for definition in definitions:
		var location: Array = definition["position"]
		var resource_value: float = definition["resource_score"]
		if definition["resources"] == "Unknown":
			resource_value = clampf(resource_value + rng.randf_range(-uncertainty, uncertainty), 0, 1)
		beliefs[definition["id"]] = {
			"position": Vector2(location[0], location[1]), "capacity": int(definition["capacity"]),
			"estimated_occupancy": 0, "resource_score": resource_value,
			"risk": definition["known_risk"], "popularity": definition["popularity"],
			"official_support": definition["official_support"],
			"existence_probability": definition["public_existence_probability"],
			"confidence": definition["information_confidence"],
			"unavailable": false, "source": "Published map / personal estimate",
		}
	return beliefs


static func evaluate(agent: Dictionary, remaining: float, weights: Dictionary) -> Dictionary:
	var scores := {}
	var best_id := ""
	var best_score := -INF
	var best_route := PackedVector2Array()
	var best_eta := INF
	var caution := 1.0 - float(agent["risk_tolerance"])
	var risk_factor := 1.5 if agent["personality"] == "Cautious" else 0.6 if agent["personality"] == "Bold" else 1.0
	var social_factor := 1.6 if agent["personality"] == "Social" else 1.0
	var travel_factor := 1.4 if agent["personality"] == "Pragmatic" else 1.0
	for shelter_id in agent["beliefs"]:
		var belief: Dictionary = agent["beliefs"][shelter_id]
		var route := Routes.plan(agent["position"], belief["position"])
		var distance := Routes.length(route)
		if agent["objective"] == shelter_id and not agent["route"].is_empty():
			distance = Routes.remaining_distance(agent)
		var eta: float = distance / agent["movement_speed"]
		var eligible: bool = not belief["unavailable"] and belief["existence_probability"] > 0 and belief["estimated_occupancy"] < belief["capacity"] and eta <= remaining + 0.00001
		if not eligible:
			scores[shelter_id] = {"eligible": false, "score": null, "eta": eta,
				"reason": "Unavailable, believed full, or not reachable before impact"}
			continue
		var capacity_fraction: float = maxf(0, belief["capacity"] - belief["estimated_occupancy"]) / weights["capacity_normalizer"]
		var score: float = weights["resources"] * belief["resource_score"]
		score += weights["capacity"] * capacity_fraction
		score += weights["popularity"] * agent["sociability"] * social_factor * belief["popularity"]
		score += weights["authority"] * agent["trust_in_authority"] * belief["official_support"]
		score -= weights["travel"] * travel_factor * eta / maxf(remaining, 0.001)
		score -= weights["risk"] * caution * risk_factor * belief["risk"]
		score -= weights["existence"] * caution * (1.0 - belief["existence_probability"])
		score -= weights["uncertainty"] * caution * (1.0 - belief["confidence"])
		scores[shelter_id] = {"eligible": true, "score": score, "eta": eta, "distance": distance}
		if score > best_score:
			best_id = shelter_id
			best_score = score
			best_route = route
			best_eta = eta
	var explanation := "No known shelter is reachable with remaining time; waiting to reconsider."
	if not best_id.is_empty():
		var belief: Dictionary = agent["beliefs"][best_id]
		explanation = "%s leads with score %.2f; road ETA %.1fs / %.1fs left. Resources %.2f, risk %.2f, existence belief %.0f%%; %s personality, sociability %.2f, authority trust %.2f." % [best_id, best_score, best_eta, remaining, belief["resource_score"], belief["risk"], belief["existence_probability"] * 100, agent["personality"], agent["sociability"], agent["trust_in_authority"]]
	return {"shelter_id": best_id, "score": best_score, "scores": scores,
		"route": best_route, "eta": best_eta, "explanation": explanation}
