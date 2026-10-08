extends RefCounted
## Format operator information without choosing destinations or mutating agents.

const Routes = preload("res://scripts/road_routes.gd")


static func agent_text(agent: Dictionary, remaining: float) -> String:
	var eta := "—"
	if agent["state"] == "MOVING":
		eta = "%.1f simulated seconds" % (Routes.remaining_distance(agent) / agent["movement_speed"])
	var text := "[b]%s • %s[/b]\nPersonality: %s\nState: %s\nSpeed: %.2f units/s\nRisk tolerance: %.0f%%\nTrust in authority: %.0f%%\nSociability: %.0f%%\nPosition: (%.1f, %.1f)\nSelected shelter: %s\nRemaining travel: %s\nTime until impact: %.1fs\n\n[b]Decision explanation[/b]\n%s\n\n[b]Decision history[/b]\n" % [agent["id"], agent["role"], agent["personality"], agent["state"], agent["movement_speed"], agent["risk_tolerance"] * 100, agent["trust_in_authority"] * 100, agent["sociability"] * 100, agent["position"].x, agent["position"].y, agent["objective"] if not agent["objective"].is_empty() else "None", eta, remaining, agent["decision_explanation"]]
	var history: Array = agent["decision_history"]
	if history.is_empty():
		text += "Awaiting siren."
	for index in range(maxi(0, history.size() - 8), history.size()):
		var entry: Dictionary = history[index]
		text += "%.1fs → %s\n" % [entry["time"], entry["shelter_id"] if not entry["shelter_id"].is_empty() else "No reachable destination"]
	if not agent["decision_scores"].is_empty():
		text += "\n[b]Latest shelter scores[/b]\n"
		for id in agent["decision_scores"]:
			var score: Dictionary = agent["decision_scores"][id]
			text += "%s: %.2f / ETA %.1fs\n" % [id, score["score"], score["eta"]] if score["eligible"] else "%s: ineligible / ETA %.1fs\n" % [id, score["eta"]]
	return text


static func shelter_text(record: Dictionary) -> String:
	var status := "Absent" if not record["exists"] else "Not operational" if not record["operational"] else "Admissions closed" if not record["accepting"] else "Open"
	var quantity := "Not specified" if record["supplies_person_days"] == null else "%s person-days" % str(record["supplies_person_days"])
	return "[b]%s • %s[/b]\nStatus: %s\nCapacity: %d\nOccupancy: %d (%.1f%%)\nRemaining places: %d\nResources: %s\nQuantity: %s\nDistance: %s\n\n%s\n\nOperator view of actual availability. Agents only discover unavailable entrances locally." % [record["id"], record["name"], status, record["capacity"], record["occupancy"], 100.0 * record["occupancy"] / record["capacity"], record["capacity"] - record["occupancy"], record["resources"], quantity, record["distance"], record["special"]]
