extends RefCounted
## Inspector displays the selected person's mind; director shelter inspection is separate.
const Routes = preload("res://scripts/road_routes.gd")
const Personality = preload("res://scripts/agent_personality.gd")

static func agent_text(agent: Dictionary, _remaining: float = 0) -> String:
	var text := "[b]%s / %s[/b]\n%s%s\nState: %s\nGoal: %s\nPreferred shelter: %s\nCompanion: %s\nSpeed: %.2f units/s\n" % [agent["id"], agent["role"], agent["primary_personality"], " + " + agent["secondary_personality"] if not agent["secondary_personality"].is_empty() else "", agent["state"], agent["current_goal"], agent["objective"], agent["companion_id"], agent["movement_speed"]]
	for trait_name in Personality.TRAITS:
		text += "%s: %.0f / 100\n" % [trait_name.capitalize(), agent[trait_name]]
	text += "Health: %.0f / 100\nStrike status: %s\n" % [agent["health"], agent["survival_status"]]
	text += "\n[b]Private beliefs[/b]\n"
	for id in agent["beliefs"]:
		var b: Dictionary = agent["beliefs"][id]
		text += "%s: %s; %s %d; existence %.0f%%\n%s\n" % [id, "unavailable" if b["unavailable"] else "possibly accessible", "observed capacity" if b["capacity_exact"] else b["size_description"] + " estimate", b["capacity"], b["existence_probability"]*100, b["source"]]
	text += "\n[b]Decision explanation[/b]\n" + agent["decision_explanation"]
	text += "\n\n[b]Rumors / reports heard[/b]\n"
	for i in range(maxi(0, agent["rumors_heard"].size()-6), agent["rumors_heard"].size()):
		var r: Dictionary = agent["rumors_heard"][i]
		text += "%s: %s (%.0f%%)\n" % [r["reaction"], r["claim"], r["perceived_credibility"]*100]
	text += "\n[b]Recent memories[/b]\n"
	for i in range(maxi(0, agent["personal_memory"].size()-8), agent["personal_memory"].size()):
		var m: Dictionary = agent["personal_memory"][i]
		text += "%.1fs: %s\n" % [m["time"], m["text"]]
	text += "\n[b]Decision history[/b]\n"
	for i in range(maxi(0, agent["decision_history"].size()-8), agent["decision_history"].size()):
		var d: Dictionary = agent["decision_history"][i]
		text += "%.1fs: %s\n" % [d["time"], d["shelter_id"]]
	return text

static func shelter_text(record: Dictionary) -> String:
	if record.get("observer_masked", false):
		return "[b]%s / %s[/b]\nPublic size: %s\nSupplies: %s\nDistance: %s\n%s\n\nExistence, exact capacity, occupancy, maintenance and stocks are unverified here. Inspect agents for their own evidence. S5 ? marks a rumored site." % [record["id"], record["name"], record["known_information"]["size"], record["resources"], record["distance"], record["special"]]
	return "[b]%s / %s / DIRECTOR[/b]\nExists: %s\nStatus: %s\nCapacity: %d\nOccupancy: %d\nDoor: %s\nMaintenance: %.0f / 100\nSupply: %.0f person-days\nResources: %s\nDistance: %s\n%s\n\nEvent history: %s\nStocks are not consumed until Phase 3." % [record["id"], record["name"], record["exists"], record["operational_status"], record["capacity"], record["occupancy"], record["door_status"], record["maintenance_condition"], record["supply_level"], record["resources"], record["distance"], record["special"], str(record["event_history"])]
