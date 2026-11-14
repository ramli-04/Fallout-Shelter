extends RefCounted
## Inspector displays the selected person's mind; director shelter inspection is separate.
const Routes = preload("res://scripts/road_routes.gd")
const Personality = preload("res://scripts/agent_personality.gd")

static func agent_text(agent: Dictionary, _remaining: float = 0) -> String:
	var text := "[b]%s / %s / %s[/b]\n%s%s\nState: %s\nGoal: %s\nPreferred shelter: %s\nCompanion: %s\nSpeed: %.2f units/s\n" % [agent.get("display_name",agent["name"]), agent["id"], agent["role"], agent["primary_personality"], " + " + agent["secondary_personality"] if not agent["secondary_personality"].is_empty() else "", agent["state"], agent["current_goal"], agent["objective"], agent["companion_id"], agent["movement_speed"]]
	for trait_name in Personality.TRAITS:
		text += "%s: %.0f / 100\n" % [trait_name.capitalize(), agent[trait_name]]
	text += "Provider: %s (configured %s)\n" % [agent.get("decision_provider", "RULE_BASED"), agent.get("configured_provider", "RULE_BASED")]
	text += "Latest LLM: %s / confidence %s\n%s\nFallback: %s\n" % [agent.get("latest_llm_action", "Pending"), agent.get("latest_llm_confidence", "Pending"), agent.get("latest_llm_explanation", ""), agent.get("fallback_reason", "None")]
	text += "Actual provider/model: %s / %s\n" % [agent.get("actual_llm_provider", "pending"), agent.get("actual_llm_model", "pending")]
	text += "AI model group: %s\nAI queue: %s\n" % [agent.get("model_tier", "llama3.2:1b"), agent.get("ai_queue_status", "IDLE")]
	text += "LLM metrics: %s\n" % str(agent.get("llm_metrics", {}))
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
	if agent.has("iq"):
		text += "\n[b]SOCIAL / selected agent private knowledge[/b]\n%s / age %d / %s / synthetic IQ %.1f\nPersonality: %s\nVisual skin tone: %s\nFamily %s / links %s\nGoal: %s\nPhone messages: %s\nAcquired beliefs (source, confidence, evidence):\n%s\nKnown member locations (may be stale):\n%s\n" % [agent.get("display_name",agent.name),agent.age,agent.occupation,agent.iq,agent.get("personality_description",agent.get("primary_personality","individual")),agent.get("visual_skin_tone","unspecified"),agent.family_id,str(agent.relationships),agent.current_goal,str(agent.inbox.slice(-5)),str(agent.social_beliefs),str(agent.known_locations)]
	if agent.has("needs"):
		text+="\n[b]Routine and personal needs[/b]\n%s / %s / room %s\nHome %s / workplace %s\nSafety %.0f%% / fatigue %.0f%% / stress %.0f%%\nFamily concern %.0f%% / health %.0f%% / social attachment %.0f%%\nGroup %s / leader %s / boarding %s\nSpontaneous: %s via %s\n"%[agent.routine,agent.location_mode,agent.indoor_id,agent.home_building,agent.work_building,float(agent.needs.get("safety",1.0))*100,float(agent.needs.get("fatigue",0.0))*100,float(agent.needs.get("stress",0.0))*100,float(agent.needs.get("family",0.0))*100,float(agent.needs.get("health",1.0))*100,float(agent.needs.get("social_attachment",0.0))*100,agent.travel_group,agent.group_leader,agent.boarding_vehicle,agent.get("last_spontaneous_action","none"),agent.get("spontaneous_provider","not queried")]
	if agent.get("shelter_life_active",false) or agent.has("current_activity"):
		var activity_duration: float=float(agent.get("activity_duration_seconds",0))
		var activity_elapsed: float=maxf(0,float(agent.get("activity_remaining_seconds",0)))
		var routine_rate: float=float(agent.get("shelter_clock_rate",60.0))
		var relationships: Dictionary=agent.get("shelter_relationships",agent.get("shelter_relationship_scores",{}))
		if relationships.is_empty(): relationships=agent.get("relationships",{})
		text+="\n[b]Shelter social dynamics[/b]\nFear %.0f / Anxiety %.0f / Morale %.0f / Loneliness %.0f\nHope %.0f / Frustration %.0f / Safety %.0f\nCaregiver: %s / family separated: %d / organized task: %s\nLeadership choice: %s\nRecent conversations: %s\n"%[float(agent.get("fear",0)),float(agent.get("anxiety",0)),float(agent.get("morale",0)),float(agent.get("loneliness",0)),float(agent.get("hope",0)),float(agent.get("frustration",0)),float(agent.get("sense_of_safety",0)),agent.get("shelter_caregiver",""),int(agent.get("separated_family_count",0)),agent.get("shelter_social_task",""),agent.get("leadership_choice",""),str(agent.get("shelter_conversations",[]).slice(-3))]
		text+="\n[b]Shelter life[/b]\nActivity: %s / previous: %s / next: %s\nShelter %s / room %s / movement %s\nNeeds: hunger %.0f%% / thirst %.0f%% / fatigue %.0f%% / sanitation %.0f%%\nStress %.0f%% / health %.0f%%\nActivity duration: %.1f min / remaining %.1f min / interruptions %d\nRelationships: %s\n"%[agent.get("current_activity","none"),agent.get("previous_activity","none"),agent.get("next_planned_activity","none"),agent.get("shelter_id",""),agent.get("shelter_room_id","in transit"),agent.get("shelter_activity_state","inactive"),float(agent.get("hunger",0)),float(agent.get("thirst",0)),float(agent.get("fatigue",0)),float(agent.get("sanitation_need",0)),float(agent.get("stress",0)),float(agent.get("health",0)),activity_duration*routine_rate/60,activity_elapsed*routine_rate/60,int(agent.get("activity_interruptions",0)),str(relationships)]
		if agent.has("last_complex_decision"): text+="Last LangGraph shelter choice: %s / %s\n"%[agent.last_complex_decision.get("action",""),agent.last_complex_decision.get("reason","")]
	if agent.has("driving_state"):
		var driving: Dictionary=agent.driving_state
		text+="\n[b]Driving[/b]\n%.1f / %.1f m/s | %s\n%s / signal %s\nLast choice: %s via %s\n"%[driving.speed_mps,driving.speed_limit_mps,driving.mode,driving.reason,driving.signal,driving.action,driving.provider]
	if agent.has("cognition"):
		var mind: Dictionary=agent.cognition
		text+="\n[b]Autonomous cognition[/b]\n%s / %s: %s\nTraits: %s\nUtility: %s\nNavigation: %s / tactical waypoint %d / goal waypoint %d of %d\nThreats: %s\nObservations: %s\nExperience: %s\nDecision history: %s\n"%[mind.layer,mind.action,mind.reason,str(agent.cognitive_traits),str(mind.scores),mind.navigation,mind.index,int(agent.get("route_index",0)),agent.get("route",[]).size(),str(mind.get("threats",[])),str(mind.observations),str(mind.memory.slice(-8)),str(mind.history.slice(-8))]
	if agent.has("police_unit_id"):
		text+="\n[b]Police assignment[/b]\nUnit: %s / busy: %s / action: %s\n%s\n"%[agent.police_unit_id,str(agent.get("police_unit_busy",false)),agent.get("police_animation",""),str(agent.get("police_instruction",{}))]
	if agent.get("evacuation_group","")!="" or agent.has("evacuation_order"):
		text+="\n[b]Organized evacuation[/b]\nGroup: %s / %s\nOrder: %s\n"%[agent.get("evacuation_group",""),agent.get("evacuation_member_status",""),str(agent.get("evacuation_order",{}))]
	return text

static func shelter_text(record: Dictionary) -> String:
	if record.get("observer_masked", false):
		return "[b]%s / %s[/b]\nPublic size: %s\nSupplies: %s\nDistance: %s\n%s\n\nExistence, exact capacity, occupancy, maintenance and stocks are unverified here. Inspect agents for their own evidence. S5 ? marks a rumored site." % [record["id"], record["name"], record["known_information"]["size"], record["resources"], record["distance"], record["special"]]
	var history := "No incidents recorded.\n"
	var operation: String="\nAvailable: %d / safety: %s / accessible: %s / admissions: %s\nEntrance: %s / exit: %s\n"%[int(record.get("available_capacity",maxi(0,int(record.capacity)-int(record.occupancy)))),str(record.get("safety_status","SAFE")),str(record.get("accessible",true)),str(record.get("admission_open",false)),str(record.get("entrance_position",record.position)),str(record.get("exit_position",record.position))]
	if not record["event_history"].is_empty():
		history = ""
		for entry in record["event_history"].slice(-6):
			var seconds := int(entry["time"])
			history += "%02d:%02d / %s %s\n" % [seconds/60,seconds%60,entry["event_id"],entry["action"]]
	return "[b]%s / %s / DIRECTOR[/b]\nExists: %s\nStatus: %s\nCapacity: %d\nOccupancy: %d\nDoor: %s\nMaintenance: %.0f / 100\nSupply: %.0f person-days\nResources: %s\nDistance: %s\n%s\n\nRecent incidents:\n%s\n" % [record["id"], record["name"], record["exists"], record["operational_status"], record["capacity"], record["occupancy"], record["door_status"], record["maintenance_condition"], record["supply_level"], record["resources"], record["distance"], record["special"], history]+operation

static func companion_text(runtime: RefCounted, companion_id: String) -> String:
	return runtime.text(companion_id)
