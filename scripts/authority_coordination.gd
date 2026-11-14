extends RefCounted
## Authority decisions use local observations, addressed reports and explicit duty records.
const Map = preload("res://scripts/city_map.gd")
const Blast = preload("res://scripts/blast_model.gd")
const Coordinates = preload("res://scripts/three_d/world_coordinates.gd")
const RADIO_RANGE := 900.0

var _sim_ref: WeakRef
var sim: RefCounted:
	get: return _sim_ref.get_ref() if _sim_ref!=null else null
	set(value): _sim_ref=weakref(value) if value!=null else null
var assignments: Array = []
var reports: Array = []
var orders: Array = []
var desertion_events: Array = []
var family_emergencies: Array = []
var decisions: Array = []
var decision_cooldowns: Dictionary = {}
var next_tick := 0.0
var reported_scenes: Dictionary = {}
var last_family_contact: Dictionary = {}
var assignment_sequence := 0
var report_sequence := 0
var order_sequence := 0

func initialize(owner_sim: RefCounted) -> void:
	sim = owner_sim
	assignments.clear(); reports.clear(); orders.clear(); desertion_events.clear()
	family_emergencies.clear(); decisions.clear(); decision_cooldowns.clear(); reported_scenes.clear(); last_family_contact.clear()
	next_tick = 0.0; assignment_sequence = 0; report_sequence = 0; order_sequence = 0
	for agent in sim.manager.agents:
		if agent.role != "Authority": continue
		agent.duty_commitment = _commitment(agent)
		agent.duty_status = "ON_DUTY"
		agent.family_emergency = false
		agent.authority_action = "remain_at_post"
		_add_assignment(agent, _task_for(agent), "INITIAL")

func close() -> void:
	# Replay finalization still reads the completed authority metrics. A fresh run
	# calls initialize(), which clears all run-scoped records and references.
	return

func _task_for(agent: Dictionary) -> String:
	return {
		"Police":"traffic patrol and scene security",
		"Fire":"fire response and rescue readiness",
		"Medical":"medical triage and evacuation readiness",
		"Civil protection":"evacuation guidance and hazard checks",
		"Crisis commander":"coordinate reports and allocate response"
	}.get(agent.occupation, "authority duty")

func _commitment(agent: Dictionary) -> float:
	if agent.has("duty_commitment"): return clampf(float(agent.duty_commitment), 0, 100)
	return clampf(float(agent.get("leadership", 50))*0.30 + float(agent.get("cooperation", 50))*0.30 + float(agent.get("courage", 50))*0.20 + float(agent.get("authority_trust", 50))*0.20, 0, 100)

func _add_assignment(agent: Dictionary, task: String, origin: String, source_task: String = "") -> Dictionary:
	assignment_sequence += 1
	var record := {"id":"AS%03d"%assignment_sequence,"agent":agent.id,"role":agent.occupation,"task":task,"status":"ACTIVE","origin":origin,"created":sim.manager.elapsed_seconds,"source_task":source_task,"rationale":""}
	assignments.append(record)
	agent.assignment_id = record.id
	agent.duty_task = task
	return record

func assignment_for(agent_id: String) -> Dictionary:
	for record in assignments:
		if record.agent == agent_id and record.status == "ACTIVE": return record
	return {}

func report(sender: Dictionary, subject: String, value: Variant, position: Vector2, uncertainty: float, evidence: String, recipients: Array = []) -> Dictionary:
	if sim == null or sender.get("role", "") != "Authority": return {}
	var role: String = sender.occupation
	var channel := _channel_for(role)
	var targets: Array = recipients.duplicate()
	if targets.is_empty():
		for receiver in sim.manager.agents:
			if receiver.role != "Authority" or receiver.id == sender.id: continue
			var same_service: bool = receiver.occupation == role
			var commander: bool = receiver.occupation == "Crisis commander"
			var subordinate: bool = receiver.get("commander", "") == sender.id
			if (same_service or commander or subordinate) and sender.position.distance_to(receiver.position) <= RADIO_RANGE:
				targets.append(receiver.id)
	report_sequence += 1
	var confidence := clampf(1.0-clampf(uncertainty,0,1),0.05,0.99)
	var record := {"id":"R%04d"%report_sequence,"subject":subject,"value":value,"position":position,"timestamp":sim.manager.elapsed_seconds,"source":sender.id,"source_role":role,"channel":channel,"uncertainty":clampf(uncertainty,0,1),"confidence":confidence,"evidence":evidence,"recipients":[]}
	for target_id in targets:
		if not sim.by_id.has(target_id) or target_id in record.recipients or sim.by_id[target_id].role!="Authority": continue
		record.recipients.append(target_id)
	for target_id in record.recipients:
		var receiver: Dictionary = sim.by_id[target_id]
		receiver.authority_reports.append(record.duplicate(true))
		if receiver.authority_reports.size() > 40: receiver.authority_reports.pop_front()
		if subject == "accident":
			receiver.known_locations["accident:"+str(value)] = {"position":position,"source":"radio:"+sender.id,"timestamp":record.timestamp,"confidence":confidence,"uncertainty":uncertainty}
		elif subject == "nuclear_hazard":
			receiver.known_locations["nuclear_hazard"] = {"position":position,"source":"radio:"+sender.id,"timestamp":record.timestamp,"confidence":confidence,"uncertainty":uncertainty,"danger_radius":float(sim.manager.nuclear.radius)/Coordinates.SCALE,"uncertainty_radius":float(sim.manager.nuclear.radius)*uncertainty/Coordinates.SCALE}
			sim.acquire(receiver,"nuclear","official hazard estimate",sender.id,confidence,"command-radio")
		sim.emit_event("authority.report_received",receiver.id,record)
	reports.append(record)
	if reports.size() > 500: reports.pop_front()
	sim.emit_event("authority.report_sent",sender.id,record)
	return record

func issue_order(issuer: Dictionary, target: Dictionary, task: String, rationale: String) -> Dictionary:
	if issuer.occupation != "Crisis commander" or target.role != "Authority": return {}
	order_sequence += 1
	var trust := clampf(float(target.get("authority_trust",50))/100,0,1)
	var compliance_chance := clampf(trust*0.55+float(target.get("duty_commitment",50))/100*0.45,0,1)
	var complied: bool = compliance_chance >= 0.42 and target.duty_status not in ["DESERTED","RESCUING_FAMILY"]
	var order := {"id":"O%04d"%order_sequence,"issuer":issuer.id,"recipient":target.id,"task":task,"rationale":rationale,"timestamp":sim.manager.elapsed_seconds,"channel":"command","compliance_score":compliance_chance,"complied":complied}
	orders.append(order)
	target.authority_orders.append(order.duplicate(true))
	if target.authority_orders.size()>30: target.authority_orders.pop_front()
	if orders.size() > 300: orders.pop_front()
	if complied:
		target.current_goal = "Order: "+task
		target.order_status = "COMPLIED"
		sim.counters.compliance += 1
	else:
		target.order_status = "DECLINED"
	sim.counters.orders += 1
	sim.emit_event("authority.order_issued",issuer.id,order)
	sim.emit_event("authority.order_response",target.id,{"order_id":order.id,"status":"COMPLIED" if complied else "DECLINED","score":compliance_chance})
	return order

func nuclear_warning() -> void:
	if sim == null: return
	var center := Vector2(float(sim.manager.nuclear.impact_position[0]),float(sim.manager.nuclear.impact_position[1]))
	for agent in sim.manager.agents:
		if agent.occupation != "Crisis commander": continue
		agent.known_locations["nuclear_hazard"] = {"position":center,"source":"command briefing","timestamp":sim.manager.elapsed_seconds,"confidence":0.82,"uncertainty":0.18,"danger_radius":float(sim.manager.nuclear.radius)/Coordinates.SCALE,"uncertainty_radius":float(sim.manager.nuclear.radius)*0.18/Coordinates.SCALE}
		var recipients: Array=[]
		for receiver in sim.manager.agents:
			if receiver.role=="Authority" and receiver.occupation in ["Police","Civil protection","Crisis commander"] and agent.position.distance_to(receiver.position)<=RADIO_RANGE: recipients.append(receiver.id)
		report(agent,"nuclear_hazard",{"estimated_center":center,"estimated_radius":float(sim.manager.nuclear.radius)/Coordinates.SCALE},center,0.18,"command briefing",recipients)

func tick(_seconds: float) -> void:
	if sim == null or sim.replaying or sim.manager.elapsed_seconds < next_tick: return
	next_tick = sim.manager.elapsed_seconds + 1.0
	_report_new_scenes()
	_refresh_family_emergencies()
	_evaluate_desertion()
	_manage_roadblocks()
	_consider_roadblocks()
	_fill_unfinished_assignments()

func _report_new_scenes() -> void:
	for scene in sim.traffic.scenes:
		var key: String = str(scene.vehicle)
		if reported_scenes.has(key): continue
		reported_scenes[key] = true
		var responders: Array = scene.get("responders",[])
		var senders: Array=[]
		for responder_id in responders:
			if sim.by_id.has(responder_id): senders.append(sim.by_id[responder_id])
		if senders.is_empty():
			for agent in sim.manager.agents:
				if agent.role == "Authority" and agent.occupation == "Crisis commander": senders.append(agent); break
		if senders.is_empty(): continue
		var targets: Array = responders.duplicate()
		for agent in sim.manager.agents:
			if agent.role == "Authority" and agent.occupation == "Crisis commander" and agent.id not in targets: targets.append(agent.id)
		for sender in senders:
			var role_targets: Array=targets.duplicate()
			for agent in sim.manager.agents:
				if agent.role=="Authority" and agent.occupation==sender.occupation and agent.id not in role_targets and sender.position.distance_to(agent.position)<=RADIO_RANGE: role_targets.append(agent.id)
			report(sender,"accident",key,scene.position,0.08,"emergency dispatch",role_targets)
		scene.report_ids=reports.slice(maxi(0,reports.size()-senders.size())).map(func(item):return item.id)
		scene.report_id=reports[-1].id if not reports.is_empty() else ""

func _channel_for(role: String) -> String:
	return {"Police":"police-radio","Fire":"fire-radio","Medical":"medical-radio","Civil protection":"civil-protection-radio","Crisis commander":"command-radio"}.get(role,"emergency-radio")

func _refresh_family_emergencies() -> void:
	var previous: Dictionary={}
	for item in family_emergencies: previous[item.authority+":"+item.relative]=item
	family_emergencies.clear()
	for agent in sim.manager.agents:
		if agent.role != "Authority" or agent.health <= 0: continue
		var best := {}
		for relative_id in agent.relationships:
			if not agent.known_locations.has(relative_id): continue
			var known: Dictionary = agent.known_locations[relative_id]
			var risk := _known_family_risk(agent, known)
			if risk <= 0.35: continue
			if best.is_empty() or risk > float(best.risk):
				best = {"authority":agent.id,"relative":relative_id,"relationship":agent.relationships[relative_id],"position":known.position,"source":known.get("source","remembered schedule"),"timestamp":known.get("timestamp",0.0),"confidence":known.get("confidence",0.0),"risk":risk}
		agent.family_emergency = not best.is_empty()
		if not best.is_empty():
			family_emergencies.append(best)
			var key: String=best.authority+":"+best.relative
			if not previous.has(key) or absf(float(previous[key].risk)-float(best.risk))>.15: sim.emit_event("authority.family_emergency",agent.id,best)
			if agent.get("family_emergency_relative","") != best.relative:
				agent.family_emergency_relative = best.relative
				agent.family_emergency_timestamp = sim.manager.elapsed_seconds
		else:
			agent.family_emergency_relative = ""

func _known_family_risk(agent: Dictionary, known: Dictionary) -> float:
	var age: float=maxf(0,sim.manager.elapsed_seconds-float(known.get("timestamp",0)))
	var confidence := float(known.get("confidence",0.0))*maxf(.2,1.0-age/1800.0)
	if str(known.get("source","")).begins_with("remembered schedule"): confidence=minf(confidence,.48)
	var personal_danger := maxf(float(agent.get("perceived_danger",0.0)),float(agent.get("panic_level",0.0))/100.0)
	var nuclear_belief: Dictionary = agent.social_beliefs.get("nuclear",{})
	if not nuclear_belief.is_empty(): personal_danger = maxf(personal_danger,float(nuclear_belief.get("confidence",0.0))*0.72)
	var nuclear: Dictionary=agent.known_locations.get("nuclear_hazard",{})
	if not nuclear.is_empty():
		var radius := float(nuclear.get("danger_radius",0))+float(nuclear.get("uncertainty_radius",0))
		var distance: float = known.position.distance_to(nuclear.position)
		var location_risk := clampf((radius+300.0-distance)/maxf(1,radius*.45),0,1)
		return clampf(location_risk*confidence*float(nuclear.get("confidence",0.7)),0,1)
	return clampf(personal_danger*confidence*0.65,0,1)

func _evaluate_desertion() -> void:
	for agent in sim.manager.agents:
		if agent.role != "Authority" or agent.health <= 0: continue
		if agent.duty_status in ["DESERTED","RESCUING_FAMILY","RETURNING"]:
			_update_return(agent)
			continue
		if not agent.has("personal_warning_known_at") and (agent.alarm_confidence>0 or float(agent.get("perceived_danger",0))>=0.18):
			agent.personal_warning_known_at=sim.manager.elapsed_seconds
		var assessment: Dictionary=desertion_assessment(agent)
		var danger: float=assessment.danger
		if danger < 0.18: continue
		var family_risk: float=assessment.family_risk
		var relative_id: String=assessment.relative
		var duty: float=assessment.duty_commitment/100
		var time_left: float=assessment.time_left
		var time_pressure: float=assessment.time_pressure
		var score: float=assessment.score
		agent.desertion_score = score
		if family_risk > 0.35: _contact_family(agent,relative_id)
		if score >= 0.48 and score < 0.63 and family_risk > 0.35 and agent.get("reassignment_requested",false) == false:
			agent.reassignment_requested = true
			agent.duty_status = "REQUESTED_REASSIGNMENT"
			desertion_events.append({"agent":agent.id,"timestamp":sim.manager.elapsed_seconds,"action":"request_reassignment","score":score,"danger":danger,"family_risk":family_risk,"duty_commitment":duty,"leadership_trust":assessment.leadership_trust,"time_pressure":time_pressure})
			sim.emit_event("authority.reassignment_requested",agent.id,desertion_events[-1])
			var covered: bool=_request_cover(agent,"Family safety request")
			if covered and not relative_id.is_empty() and agent.known_locations.has(relative_id):
				agent.social_target=relative_id; agent.current_goal="Rescue family after post coverage was approved"
				agent.duty_status="RESCUING_FAMILY"; agent.authority_action="leave_to_rescue_family"
				sim.emit_event("authority.reassignment_approved",agent.id,{"relative":relative_id,"requested_assignment":desertion_events[-1].get("assignment_id","")})
			continue
		if score < 0.63: continue
		if family_risk >= 0.42 and not relative_id.is_empty() and time_left > 20:
			var known: Dictionary = agent.known_locations.get(relative_id,{})
			if not known.is_empty():
				agent.authority_action = "leave_to_rescue_family"
				agent.social_target = relative_id
				agent.current_goal = "Leave assigned post to reach family using last known location"
				agent.duty_status = "RESCUING_FAMILY"
				_leave_post(agent,"leave_to_rescue_family",score,danger,family_risk,time_pressure)
				continue
		if danger >= 0.68 or time_left <= 30:
			agent.authority_action = "abandon_duty_and_evacuate"
			agent.duty_status = "DESERTED"
			agent.current_goal = "Abandon duty and seek immediate shelter"
			sim.manager.choose_rule_destination(agent)
			_leave_post(agent,"abandon_duty_and_evacuate",score,danger,family_risk,time_pressure)

func desertion_assessment(agent: Dictionary) -> Dictionary:
	var nuclear_belief: Dictionary=agent.social_beliefs.get("nuclear",{})
	var danger := maxf(float(agent.get("perceived_danger",0)),float(agent.get("panic_level",0))/100.0)
	if not nuclear_belief.is_empty(): danger=maxf(danger,float(nuclear_belief.get("confidence",0))*0.72)
	var family_risk := 0.0
	var relative_id: String=str(agent.get("family_emergency_relative",""))
	if not relative_id.is_empty():
		for emergency in family_emergencies:
			if emergency.authority==agent.id: family_risk=float(emergency.risk); break
	var stress := clampf(float(agent.get("stress",0))/100,0,1)
	var duty := float(agent.get("duty_commitment",50))
	var trust := clampf(float(agent.get("authority_trust",50)),0,100)
	var first_known_at: float=float(agent.get("personal_warning_known_at",nuclear_belief.get("acquired_at",sim.manager.elapsed_seconds)))
	var personal_warning: float=maxf(0,float(agent.get("perceived_warning_seconds",180)))
	var time_left := maxf(0,personal_warning-maxf(0,sim.manager.elapsed_seconds-first_known_at))
	var time_pressure := clampf((180.0-time_left)/180.0,0,1)
	var score := clampf(danger*0.29+family_risk*0.27+stress*0.15+(1.0-duty/100)*0.13+(1.0-trust/100)*0.08+time_pressure*0.08,0,1)
	return {"score":score,"danger":danger,"family_risk":family_risk,"relative":relative_id,"stress":stress,"duty_commitment":duty,"leadership_trust":trust,"time_left":time_left,"time_pressure":time_pressure}

func _contact_family(agent: Dictionary, relative_id: String) -> void:
	if relative_id.is_empty() or not sim.by_id.has(relative_id): return
	if sim.manager.elapsed_seconds-float(last_family_contact.get(agent.id,-1000)) < 30: return
	last_family_contact[agent.id] = sim.manager.elapsed_seconds
	var known: Dictionary = agent.known_locations.get(relative_id,{})
	var sent: bool = sim.send_phone(agent,relative_id,{"subject":"authority_family_checkin","value":"Need your status. Reply with your current location.","position":agent.position,"known_location":known.get("position",Vector2.INF)},"call")
	if sent: sim.emit_event("authority.family_contact",agent.id,{"recipient":relative_id,"known_source":known.get("source","unknown"),"known_timestamp":known.get("timestamp",-1.0)})

func _leave_post(agent: Dictionary, action: String, score: float, danger: float, family_risk: float, time_pressure: float) -> void:
	var assignment: Dictionary = assignment_for(agent.id)
	var event := {"agent":agent.id,"action":action,"timestamp":sim.manager.elapsed_seconds,"assignment_id":assignment.get("id",""),"assignment_task":assignment.get("task",""),"status":"UNFINISHED","score":score,"perceived_danger":danger,"family_risk":family_risk,"stress":float(agent.get("stress",0)),"duty_commitment":float(agent.get("duty_commitment",50)),"leadership_trust":float(agent.get("authority_trust",50)),"time_pressure":time_pressure,"family_relative":agent.get("family_emergency_relative","")}
	if not assignment.is_empty(): assignment.status = "UNFINISHED"; assignment.rationale = action
	desertion_events.append(event)
	sim.emit_event("authority.deserted",agent.id,event)
	for civilian in sim.manager.agents:
		if civilian.role != "Civilian" or not sim.daily.interiors.can_see(civilian,agent) or civilian.position.distance_to(agent.position)>sim.manager.living.observation_radius: continue
		civilian.trust_relationships[agent.id] = maxf(0,float(civilian.trust_relationships.get(agent.id,0.5))-0.15)
		sim.counters.trust_changes += 1
		sim.counters.public_trust_changes = int(sim.counters.get("public_trust_changes",0))+1
	_notify_nearby_authorities(agent)
	for block in sim.blocks:
		if block.active and str(block.get("managed_by","")) == agent.id:
			block.unmanaged = true
			block.unmanaged_at = sim.manager.elapsed_seconds
			sim.emit_event("roadblock.unmanaged",agent.id,{"block":block.id,"reason":"assigned officer left duty"})
	_reassign_assignment(agent,assignment)

func _request_cover(agent: Dictionary, rationale: String) -> bool:
	var assignment: Dictionary = assignment_for(agent.id)
	if assignment.is_empty(): return false
	var commander := _commander()
	if commander.is_empty(): return false
	return _request_replacement(commander,agent,assignment,rationale)

func _reassign_assignment(agent: Dictionary, assignment: Dictionary) -> void:
	if assignment.is_empty(): return
	var commander := _commander()
	if commander.is_empty():
		assignment.status = "UNFILLED"
		return
	_request_replacement(commander,agent,assignment,"Cover for authority leaving post")

func _request_replacement(commander: Dictionary, outgoing: Dictionary, assignment: Dictionary, rationale: String) -> bool:
	if assignment.get("status","")=="UNFILLED" and sim.manager.elapsed_seconds<float(assignment.get("retry_at",0)): return false
	var candidates: Array=[]
	for other in sim.manager.agents:
		if other.role != "Authority" or other.id == outgoing.id or other.occupation != assignment.get("role",outgoing.occupation): continue
		if other.health <= 0 or other.duty_status not in ["ON_DUTY","REQUESTED_REASSIGNMENT"]: continue
		candidates.append(other)
	candidates.sort_custom(func(a,b):return a.position.distance_squared_to(outgoing.position)<b.position.distance_squared_to(outgoing.position))
	for candidate in candidates:
		var order := issue_order(commander,candidate,str(assignment.task),rationale)
		if order.is_empty() or not order.complied: continue
		assignment.status = "REASSIGNED"
		assignment.reassigned_to = candidate.id
		assignment.reassigned_at = sim.manager.elapsed_seconds
		assignment.erase("retry_at")
		var replacement := _add_assignment(candidate,str(assignment.task),"REASSIGNED",str(assignment.id))
		replacement.rationale = rationale
		candidate.duty_status = "ON_DUTY"
		candidate.reassignment_requested = false
		if str(assignment.get("managed_block","")) != "" and sim.blocks.any(func(block):return block.id==assignment.managed_block and block.active):
			for block in sim.blocks:
				if block.id==assignment.managed_block: block.managed_by=candidate.id; block.unmanaged=false
		return true
	assignment.status = "UNFILLED"
	assignment.rationale = "No available same-service authority complied with coverage order"
	assignment.retry_at = sim.manager.elapsed_seconds+15.0
	sim.emit_event("authority.assignment_unfilled",commander.id,{"assignment_id":assignment.id,"role":assignment.role,"task":assignment.task,"rationale":assignment.rationale})
	return false

func _fill_unfinished_assignments() -> void:
	for assignment in assignments:
		if assignment.status != "UNFILLED": continue
		var commander := _commander()
		if commander.is_empty(): continue
		var outgoing: Dictionary = sim.by_id.get(assignment.get("agent",""),{})
		if outgoing.is_empty(): continue
		_request_replacement(commander,outgoing,assignment,"Commander coverage review")

func _commander() -> Dictionary:
	for agent in sim.manager.agents:
		if agent.role == "Authority" and agent.occupation == "Crisis commander" and agent.health > 0 and agent.duty_status not in ["DESERTED","RESCUING_FAMILY"]: return agent
	return {}

func _notify_nearby_authorities(departing: Dictionary) -> void:
	for witness in sim.manager.agents:
		if witness.role!="Authority" or witness.id==departing.id or witness.health<=0: continue
		if witness.position.distance_to(departing.position)>sim.manager.living.observation_radius or not sim.daily.interiors.can_see(witness,departing): continue
		witness.social_beliefs["authority_absent:"+departing.id]={"claimed_value":"left post","source":witness.id,"acquired_at":sim.manager.elapsed_seconds,"confidence":1.0,"evidence":"direct observation","status":"KNOWN"}
		var recipients: Array=[departing.id]
		var commander: Dictionary=_commander()
		if not commander.is_empty() and commander.id not in recipients: recipients.append(commander.id)
		report(witness,"authority_absence",{"agent":departing.id,"assignment":departing.get("assignment_id","")},departing.position,0.02,"direct observation",recipients)

func _update_return(agent: Dictionary) -> void:
	if agent.duty_status == "RESCUING_FAMILY":
		var relative_id: String = str(agent.get("family_emergency_relative",""))
		if relative_id.is_empty() or not sim.by_id.has(relative_id): return
		var relative: Dictionary = sim.by_id[relative_id]
		if sim.daily.interiors.can_see(agent,relative) and agent.position.distance_to(relative.position)<45:
			agent.duty_status = "RETURNING"
			agent.authority_action = "return_after_family_contact"
			agent.social_target = ""
			agent.current_goal = "Family contact made; request return to duty"
			sim.emit_event("authority.family_reached",agent.id,{"relative":relative_id,"assignment_id":_last_assignment(agent.id).get("id","")})
	elif agent.duty_status == "DESERTED":
		if agent.state == "SHELTERED" and agent.get("family_emergency",false): return
		if agent.state == "SHELTERED" and not agent.get("family_emergency",false):
			agent.duty_status = "RETURNING"
			agent.authority_action = "return_after_family_contact"
			sim.emit_event("authority.return_requested",agent.id,{"reason":"family reported safe"})
	if agent.duty_status == "RETURNING":
		var commander := _commander()
		if commander.is_empty(): return
		var record := _last_assignment(agent.id)
		if record.is_empty(): return
		var order := issue_order(commander,agent,str(record.get("task",_task_for(agent))),"Family reported safe; return to service")
		if order.complied:
			agent.duty_status = "ON_DUTY"
			agent.authority_action = "remain_at_post"
			sim.emit_event("authority.returned_to_duty",agent.id,{"assignment_id":record.get("id","")})

func _last_assignment(agent_id: String) -> Dictionary:
	for i in range(assignments.size()-1,-1,-1):
		if assignments[i].agent == agent_id: return assignments[i]
	return {}

func _report_hazards_for(agent: Dictionary) -> Array:
	var found: Array=[]
	for scene in sim.traffic.scenes:
		if scene.recovered: continue
		var subject := "accident:"+str(scene.vehicle)
		var belief: Dictionary = agent.social_beliefs.get(subject,{})
		var known: Dictionary=agent.known_locations.get(subject,{})
		var visible: bool=scene.position.distance_to(agent.position) <= sim.manager.living.observation_radius
		if not belief.is_empty() or not known.is_empty() or visible:
			found.append({"kind":"accident","id":str(scene.vehicle),"position":scene.position,"confidence":float(belief.get("confidence",known.get("confidence",1.0 if visible else 0.0))),"scene":scene})
	var nuclear: Dictionary = agent.known_locations.get("nuclear_hazard",{})
	for shelter in sim.manager.shelters:
		if shelter.get("available_capacity",1)==0 and shelter.exists and agent.beliefs[shelter.id].estimated_occupancy>=agent.beliefs[shelter.id].capacity:
			found.append({"kind":"full_shelter","id":shelter.id,"position":agent.beliefs[shelter.id].position,"confidence":float(agent.beliefs[shelter.id].confidence),"location":{"danger_radius":100.0}})
	for event in sim.manager.environment_events:
		var key: String="emergency:"+event.event_id
		if event.event_type=="POLICE_SHELTER_EVACUATION": continue
		if event.active_status and agent.known_locations.has(key):
			var location: Dictionary=agent.known_locations[key]
			found.append({"kind":event.event_type,"id":event.event_id,"position":location.position,"confidence":float(location.confidence),"location":location})
	if not nuclear.is_empty() and agent.social_beliefs.has("nuclear"):
		found.append({"kind":"nuclear","id":"nuclear_hazard","position":nuclear.position,"confidence":float(nuclear.get("confidence",0.7)),"location":nuclear})
	return found

func request_roadblock(officer: Dictionary) -> bool:
	if officer.role!="Authority" or officer.occupation!="Police" or officer.health<=0: return false
	var previous: int=sim.police.requests.size()
	_consider_roadblocks(officer.id)
	return sim.police.requests.size()>previous

func request_block_removal(officer: Dictionary, block_id: String) -> bool:
	if officer.role!="Authority" or officer.occupation not in ["Police","Crisis commander"]: return false
	for block in sim.blocks:
		if block.id!=block_id or not block.active or not block.get("managed_by_policy",false): continue
		if officer.occupation!="Crisis commander" and block.get("managed_by","")!=officer.id: return false
		var reason: String=_release_reason(block)
		if reason.is_empty(): return false
		if block.has("deployment_id"): return sim.police.request_removal(block.deployment_id,reason)
		_remove_managed_block(block,reason)
		return true
	return false

func _consider_roadblocks(only_officer_id: String = "") -> void:
	var active_managed: Array=sim.police.requests.filter(func(r):return r.state!="REMOVED")
	var limit := mini(3,sim.manager.agents.filter(func(a):return a.role=="Authority" and a.occupation=="Police" and a.health>0).size())
	if active_managed.size() >= limit: return
	for officer in sim.manager.agents:
		if officer.role != "Authority" or officer.occupation != "Police" or officer.health <= 0: continue
		if not only_officer_id.is_empty() and officer.id!=only_officer_id: continue
		if officer.duty_status not in ["ON_DUTY","ROADBLOCK_DUTY"]: continue
		if sim.blocks.any(func(block):return block.active and block.get("managed_by_policy",false) and block.get("managed_by","")==officer.id): continue
		var hazards := _report_hazards_for(officer)
		if hazards.is_empty(): continue
		for hazard in hazards:
			var candidates: Array=[]
			if hazard.kind=="nuclear":
				candidates=_nuclear_entry_edges(hazard,officer)
			else:
				var incident_edge: Dictionary = Map.nearest_edge(hazard.position,true).get("edge",{})
				var incident_index: int = Map.roads.find(incident_edge)
				if incident_index < 0: continue
				candidates=_adjacent_edges(incident_index)
			candidates.sort_custom(func(a,b):return _edge_priority(a,hazard,officer)>_edge_priority(b,hazard,officer))
			for candidate_index in candidates:
				if active_managed.size() >= limit: return
				if _edge_has_active_block(candidate_index): continue
				var candidate: Dictionary=Map.roads[candidate_index]
				var center: Vector2=_edge_center(candidate)
				var officer_reach: float=320.0 if hazard.kind=="accident" else 600.0
				var hazard_reach: float=440.0 if hazard.kind=="accident" else float(hazard.get("location",{}).get("danger_radius",0))+float(hazard.get("location",{}).get("uncertainty_radius",0))+260.0
				if center.distance_to(hazard.position)>hazard_reach: continue
				var metrics := _edge_metrics(candidate_index)
				if hazard.kind=="accident" and metrics.vehicle_count<1: continue
				var available_personnel := _available_police_count()

				var safe := _shelter_access_preserved(candidate_index)
				var emergency_access: bool=_emergency_access_preserved(candidate_index,hazard.position)
				var evidence := {"hazard_kind":hazard.kind,"hazard_id":hazard.id,"hazard_confidence":hazard.confidence,"hazard_position":hazard.position,"vehicle_count":metrics.vehicle_count,"mean_speed":metrics.mean_speed,"congestion":metrics.congestion,"traffic_flow":metrics.flow,"evacuation_demand":metrics.evacuation_demand,"road_capacity":metrics.road_capacity,"capacity_utilization":metrics.capacity_utilization,"lane_count":metrics.lane_count,"available_personnel":available_personnel,"shelter_access_preserved":safe,"emergency_vehicle_access_preserved":emergency_access,"edge":candidate_index,"timestamp":sim.manager.elapsed_seconds}
				var decision: Dictionary=evaluate_roadblock(evidence)
				if decision.action == "hold":
					if decision.reason != "No observed hazard": _record_roadblock_rejection(officer,decision,evidence)
					continue
				var point: Vector2=_edge_center(candidate)
				var block_kind: String="emergency_lane" if decision.action=="reserve_emergency_lane" else "police"
				if block_kind=="emergency_lane":
					var tangent: Vector2=(candidate.points[-1]-candidate.points[0]).normalized()
					point+=preload("res://scripts/traffic_conventions.gd").right(tangent)*float(candidate.width)*0.23
				var request: Dictionary=sim.police.request_deployment(block_kind,int(candidate_index),point,decision.reason,evidence)
				if request.is_empty(): continue
				active_managed.append(request)
				decision.request_id=request.id; decision.officer=officer.id
				decisions.append(decision)
				sim.emit_event("authority.roadblock_decision",officer.id,decision)
				break

func evaluate_roadblock(evidence: Dictionary) -> Dictionary:
	var result := {"action":"hold","reason":"No observed hazard","score":0.0}
	var hazard: String = str(evidence.get("hazard_kind",""))
	if hazard not in ["accident","nuclear","full_shelter","fire","explosion","road_closure","danger_zone","infrastructure_failure","increasing_threat"]: return result
	var hazard_confidence := clampf(float(evidence.get("hazard_confidence",0)),0,1)
	var flow := clampf(float(evidence.get("traffic_flow",0)),0,1)
	var congestion := clampf(float(evidence.get("congestion",0)),0,1)
	var demand := clampf(float(evidence.get("evacuation_demand",0)),0,1)
	var capacity_utilization := clampf(float(evidence.get("capacity_utilization",0)),0,1)
	var personnel := int(evidence.get("available_personnel",0))
	result["available_personnel"]=personnel
	result["deployment_pending"]=personnel<2
	if hazard_confidence < 0.55: result.reason="Hazard report is too uncertain"; return result
	if not bool(evidence.get("shelter_access_preserved",false)):
		result.reason="Rejected: would isolate civilians from an accessible shelter"; return result
	if not bool(evidence.get("emergency_vehicle_access_preserved",true)):
		result.reason="Rejected: would cut emergency vehicle access to the hazard"; return result
	if hazard == "accident" and int(evidence.get("vehicle_count",0)) < 1:
		result.reason="No approaching traffic to redirect"; return result
	var hazard_weight := 1.0 if hazard == "nuclear" else 0.82
	var score := hazard_weight*0.52+flow*0.15+congestion*0.12+demand*0.09+capacity_utilization*0.07+0.05
	result.score=score
	var initiative: float=clampf(float(sim.config.get("roadblock_frequency",0.3)),0,1)
	var threshold: float=0.55 if hazard=="nuclear" else 0.62-initiative*0.13
	if score < threshold: result.reason="Observed hazard does not justify the traffic cost"; return result
	var reserve_lane: bool=hazard=="accident" and int(evidence.get("lane_count",0))>=4 and capacity_utilization>=0.75
	result.action="close_unsafe_road" if hazard=="nuclear" else "reserve_emergency_lane" if reserve_lane else "redirect_traffic"
	result.reason="%s; flow %.2f, congestion %.2f, demand %.2f, capacity %.0f%%; shelters and emergency routes remain connected"%["Close entry to reported nuclear danger zone" if hazard=="nuclear" else "Reserve lane for responders" if reserve_lane else "Redirect traffic around "+hazard,flow,congestion,demand,capacity_utilization*100]
	return result

func _record_roadblock_rejection(officer: Dictionary, decision: Dictionary, evidence: Dictionary) -> void:
	var key: String="%s:%s:%s:%s"%[evidence.get("hazard_kind",""),evidence.get("hazard_id",""),evidence.get("edge",-1),decision.get("reason","")]
	if sim.manager.elapsed_seconds-float(decision_cooldowns.get(key,-1000))<15.0: return
	decision_cooldowns[key]=sim.manager.elapsed_seconds
	var record: Dictionary=decision.duplicate(true); record.merge(evidence,true); record.officer=officer.id
	decisions.append(record)
	if decisions.size()>500: decisions.pop_front()
	sim.emit_event("authority.roadblock_rejected",officer.id,record)

func _edge_priority(edge_index: int, hazard: Dictionary, officer: Dictionary) -> float:
	var edge: Dictionary=Map.roads[edge_index]
	var center: Vector2=_edge_center(edge)
	var m := _edge_metrics(edge_index)
	return float(m.flow)*2.0+float(m.congestion)+float(m.evacuation_demand)*0.5-center.distance_to(hazard.position)/maxf(1,Map.MAP_SIZE.length())-officer.position.distance_to(center)/maxf(1,Map.MAP_SIZE.length())

func _adjacent_edges(edge_index: int) -> Array:
	var incident: Dictionary=Map.roads[edge_index]
	var result: Array=[]
	for index in range(Map.roads.size()):
		if index==edge_index: continue
		var edge: Dictionary=Map.roads[index]
		if edge.get("elevated",false) or edge.get("ramp",false): continue
		if edge.from==incident.from or edge.from==incident.to or edge.to==incident.from or edge.to==incident.to: result.append(index)
	return result

func _nuclear_entry_edges(hazard: Dictionary, officer: Dictionary) -> Array:
	var location: Dictionary=hazard.get("location",{})
	var radius := float(location.get("danger_radius",0))+float(location.get("uncertainty_radius",0))
	if radius<=0: return []
	var result: Array=[]
	for index in range(Map.roads.size()):
		var edge: Dictionary=Map.roads[index]
		if edge.get("elevated",false) or edge.get("ramp",false) or edge.points.size()<2: continue
		var minimum_distance:=INF; var maximum_distance:=0.0
		for point in edge.points:
			var distance: float=point.distance_to(hazard.position)
			minimum_distance=minf(minimum_distance,distance); maximum_distance=maxf(maximum_distance,distance)
		if minimum_distance<=radius+250 and maximum_distance>=radius-250 and officer.position.distance_to(_edge_center(edge))<=600:
			result.append(index)
	return result

func _edge_center(edge: Dictionary) -> Vector2:
	var points: PackedVector2Array=edge.points
	return points[int(points.size()/2)] if not points.is_empty() else Vector2.ZERO

func _distance_to_edge(point: Vector2, edge: Dictionary) -> float:
	var best := INF
	var points: PackedVector2Array=edge.points
	for i in range(1,points.size()): best=minf(best,point.distance_to(Geometry2D.get_closest_point_to_segment(point,points[i-1],points[i])))
	return best

func _edge_metrics(edge_index: int) -> Dictionary:
	var edge: Dictionary=Map.roads[edge_index]
	var center: Vector2=_edge_center(edge)
	var volume := 0
	var speed_total := 0.0
	var civilians := 0
	for vehicle in sim.vehicles:
		if vehicle.status in ["PARKED","ACCIDENT","REMOVED","DESTROYED"] or absf(float(vehicle.get("height",0)))>2: continue
		if vehicle.position.distance_to(center)<=280 and (int(vehicle.get("edge",-1))==edge_index or _distance_to_edge(vehicle.position,edge)<=float(edge.width)*0.5+32):
			volume+=1; speed_total+=maxf(0,float(vehicle.speed))
	for agent in sim.manager.agents:
		if agent.role!="Civilian" or agent.health<=0 or agent.state in ["SHELTERED","SAFE","EXPOSED"] or agent.get("indoor_id","")!="": continue
		if agent.position.distance_to(center)<=260 and _distance_to_edge(agent.position,edge)<=float(edge.width)*0.5+float(edge.get("sidewalk",0))+36: civilians+=1
	var mean_speed := speed_total/volume if volume>0 else 0.0
	var flow := clampf(float(volume)/4,0,1)
	var congestion := clampf(1.0-mean_speed/60.0,0,1) if volume>0 else 0.0
	var lanes:=maxi(1,int(edge.get("lanes",2)))
	var capacity:=lanes*4
	return {"vehicle_count":volume,"mean_speed":mean_speed,"flow":flow,"congestion":congestion,"evacuation_demand":clampf(float(civilians)/8,0,1),"civilian_count":civilians,"lane_count":lanes,"road_capacity":capacity,"capacity_utilization":clampf(float(volume)/capacity,0,1)}

func _available_police_count() -> int:
	return sim.manager.agents.filter(func(a):return a.role=="Authority" and a.occupation=="Police" and a.health>0 and a.duty_status=="ON_DUTY").size()

func _edge_has_active_block(edge_index: int) -> bool:
	return sim.blocks.any(func(block):return block.active and block.edge==edge_index and block.kind in ["police","checkpoint","evacuation_checkpoint","restricted","damaged_road","accident"])

func _components(excluded_edge: int) -> Dictionary:
	var adjacency: Dictionary={}
	for edge_id in Map.graph.get_point_ids(): adjacency[int(edge_id)]=[]
	for index in range(Map.roads.size()):
		if index==excluded_edge or not Map.graph.has_point(Map.roads[index].from) or not Map.graph.has_point(Map.roads[index].to): continue
		var edge: Dictionary=Map.roads[index]
		if not Map.graph.are_points_connected(edge.from,edge.to): continue
		adjacency[edge.from].append(edge.to); adjacency[edge.to].append(edge.from)
	var component: Dictionary={}; var next_id:=0
	for root_id in adjacency:
		if component.has(root_id): continue
		next_id+=1; component[root_id]=next_id
		var queue: Array=[root_id]; var cursor:=0
		while cursor<queue.size():
			var current: int=queue[cursor]; cursor+=1
			for neighbor in adjacency[current]:
				if component.has(neighbor): continue
				component[neighbor]=next_id; queue.append(neighbor)
	return component

func _shelter_access_preserved(candidate_edge: int) -> bool:
	var before := _components(-1)
	var after := _components(candidate_edge)
	var open_shelters: Array=[]
	for shelter in sim.manager.shelters:
		if shelter.get("admission_open",shelter.get("accepting",false)) and shelter.get("operational",true):
			var point_id: int=Map.graph.get_closest_point(Map.nearest_lane_point(shelter.position))
			if before.has(point_id): open_shelters.append(point_id)
	if open_shelters.is_empty(): return false
	var before_shelter_components: Dictionary={}; var after_shelter_components: Dictionary={}
	for point_id in open_shelters:
		before_shelter_components[before[point_id]]=true
		if after.has(point_id): after_shelter_components[after[point_id]]=true
	if after_shelter_components.is_empty(): return false
	for agent in sim.manager.agents:
		if agent.role!="Civilian" or agent.health<=0 or agent.state in ["SHELTERED","SAFE","EXPOSED"]: continue
		var node_id: int=Map.graph.get_closest_point(Map.nearest_lane_point(agent.position))
		if not before.has(node_id) or before_shelter_components.get(before[node_id],false)==false: continue
		if not after.has(node_id) or not after_shelter_components.has(after[node_id]): return false
	var group_component_after: Dictionary={}
	for agent in sim.manager.agents:
		if agent.role!="Civilian" or agent.health<=0 or agent.state in ["SHELTERED","SAFE","EXPOSED"]: continue
		var node_id: int=Map.graph.get_closest_point(Map.nearest_lane_point(agent.position))
		if not before.has(node_id) or not after.has(node_id): continue
		var old_component: int=before[node_id]; var new_component: int=after[node_id]
		if group_component_after.has(old_component) and group_component_after[old_component]!=new_component: return false
		group_component_after[old_component]=new_component
	return true

func _emergency_access_preserved(candidate_edge: int, hazard_position: Vector2) -> bool:
	var before := _components(-1)
	var after := _components(candidate_edge)
	var incident: Dictionary=Map.nearest_edge(hazard_position,true).get("edge",{})
	if incident.is_empty(): return true
	var targets: Array=[incident.from,incident.to]
	for agent in sim.manager.agents:
		if agent.role!="Authority" or agent.occupation not in ["Police","Fire","Medical","Civil protection"] or agent.health<=0: continue
		if agent.duty_status in ["DESERTED","RESCUING_FAMILY"]: continue
		var source_id: int=Map.graph.get_closest_point(Map.nearest_lane_point(agent.position))
		var was_connected:=false; var remains_connected:=false
		for target_id in targets:
			if before.has(source_id) and before.has(target_id) and before[source_id]==before[target_id]: was_connected=true
			if after.has(source_id) and after.has(target_id) and after[source_id]==after[target_id]: remains_connected=true
		if was_connected and not remains_connected: return false
	return true

func _manage_roadblocks() -> void:
	for block in sim.blocks:
		if not block.active or not block.get("managed_by_policy",false): continue
		if block.has("deployment_id"):
			var release: String=_release_reason(block)
			if not release.is_empty(): sim.police.request_removal(block.deployment_id,release)
			continue
		var owner: Dictionary=sim.by_id.get(str(block.get("managed_by","")),{})
		if owner.is_empty() or owner.get("duty_status","") in ["DESERTED","RESCUING_FAMILY"]:
			block.unmanaged=true
		if sim.manager.phase=="ALL_CLEAR":
			sim.remove_block(block.id); continue
		var edge: Dictionary=Map.roads[int(block.edge)]
		if block.kind!="emergency_lane" and not sim.blocks.any(func(other):return other.active and other.id!=block.id and other.edge==block.edge and other.kind!="emergency_lane"):
			Map.graph.connect_points(edge.from,edge.to)
			var access_ok: bool=_shelter_access_preserved(int(block.edge))
			Map.graph.disconnect_points(edge.from,edge.to)
			if not access_ok:
				_remove_managed_block(block,"Changed shelter or road access would strand civilians")
				continue
		var reason: String=_release_reason(block)
		if not reason.is_empty(): _remove_managed_block(block,reason)

func _release_reason(block: Dictionary) -> String:
	if sim.manager.phase=="ALL_CLEAR": return "All-clear released managed road restrictions"
	for event in sim.manager.environment_events:
		if event.event_id==block.get("hazard_id","") and event.ended: return "Emergency event cleared"
	for scene in sim.traffic.scenes:
		if str(scene.vehicle)==str(block.get("hazard_id","")) and scene.recovered: return "Incident recovery completed"
	if block.get("hazard_kind","")!="accident": return ""
	var original: float=float(block.get("created_metrics",{}).get("congestion",0))
	if _nearby_scene_secured(block) and _area_congestion(block.position)>original+0.40:
		return "Congestion became worse after the scene was secured"
	return ""

func _nearby_scene_secured(block: Dictionary) -> bool:
	for scene in sim.traffic.scenes:
		if scene.position.distance_to(block.position)<500 and scene.secured: return true
	return false

func _area_congestion(position: Vector2) -> float:
	var count:=0; var speed:=0.0
	for vehicle in sim.vehicles:
		if vehicle.status in ["PARKED","ACCIDENT","REMOVED","DESTROYED"] or vehicle.position.distance_to(position)>420: continue
		count+=1; speed+=maxf(0,float(vehicle.speed))
	return clampf(1.0-speed/maxf(1,count*60),0,1) if count>0 else 0.0

func _remove_managed_block(block: Dictionary, reason: String) -> void:
	var id: String=block.id
	sim.remove_block(id)
	sim.emit_event("authority.roadblock_released",str(block.get("managed_by","")),{"block":id,"rationale":reason})
	for assignment in assignments:
		if assignment.get("managed_block","")==id and assignment.status=="ACTIVE":
			assignment.task=_task_for(sim.by_id[assignment.agent]); assignment.erase("managed_block")
			if sim.by_id[assignment.agent].duty_status=="ROADBLOCK_DUTY": sim.by_id[assignment.agent].duty_status="ON_DUTY"

func director_text() -> String:
	if sim == null: return "Authorities: not initialized"
	var role_counts: Dictionary={}
	for agent in sim.manager.agents:
		if agent.role=="Authority": role_counts[agent.occupation]=int(role_counts.get(agent.occupation,0))+1
	var active := assignments.filter(func(item):return item.status=="ACTIVE")
	var unfinished := assignments.filter(func(item):return item.status in ["UNFINISHED","UNFILLED"])
	var blocks_active: Array=sim.blocks.filter(func(block):return block.active and block.kind in ["police","checkpoint","evacuation_checkpoint","restricted","damaged_road","emergency_lane"])
	var deserted := desertion_events.filter(func(item):return item.action in ["leave_to_rescue_family","abandon_duty_and_evacuate"])
	var text := "AUTHORITY COORDINATION / Police %d · Fire %d · Medical %d · Civil protection %d · Commanders %d\n%d active tasks / %d unfinished / %d radio reports / %d orders (%d compliance)\nPolice roadblocks %d / policy decisions %d / desertion events %d / family emergencies %d / observed public trust changes %d\n"%[role_counts.get("Police",0),role_counts.get("Fire",0),role_counts.get("Medical",0),role_counts.get("Civil protection",0),role_counts.get("Crisis commander",0),active.size(),unfinished.size(),reports.size(),sim.counters.get("orders",0),sim.counters.get("compliance",0),blocks_active.size(),decisions.size(),deserted.size(),family_emergencies.size(),sim.counters.get("public_trust_changes",0)]
	for assignment in active:
		var agent: Dictionary=sim.by_id.get(assignment.agent,{})
		text+="%s %s → %s [%s / %s]\n"%[assignment.id,assignment.agent,assignment.role,agent.get("duty_status","UNKNOWN"),assignment.task]
	for block in blocks_active.slice(maxi(0,blocks_active.size()-3)):
		text+="%s edge %d by %s · %s%s\n"%[block.id,block.edge,block.get("managed_by",block.issuer),block.get("rationale","manual closure")," · UNMANAGED" if block.get("unmanaged",false) else ""]
	for order in orders.slice(maxi(0,orders.size()-3)):
		text+="ORDER %s → %s · %s · %s\n"%[order.issuer,order.recipient,order.task,"COMPLIED" if order.complied else "DECLINED"]
	for item in deserted.slice(maxi(0,deserted.size()-3)):
		text+="DESERTION %s · %s · danger %.2f / family %.2f / duty %.0f / trust %.0f\n"%[item.agent,item.action,item.perceived_danger,item.family_risk,item.duty_commitment,item.leadership_trust]
	for item in family_emergencies.slice(0,3):
		text+="FAMILY %s seeks %s · risk %.2f · source %s @ %.0fs ± uncertainty\n"%[item.authority,item.relative,item.risk,item.source,item.timestamp]
	if not reports.is_empty():
		var latest: Dictionary=reports[-1]
		text+="Latest %s via %s · source %s · %.0fs · uncertainty %.0f%% · recipients %d"%[latest.subject,latest.channel,latest.source,latest.timestamp,latest.uncertainty*100,latest.recipients.size()]
	return text+sim.police.director_text()

func export_state() -> Dictionary:
	return {"assignments":assignments,"reports":reports,"orders":orders,"desertion_events":desertion_events,"family_emergencies":family_emergencies,"decisions":decisions}

func metrics() -> Dictionary:
	var role_counts: Dictionary={}
	for agent in sim.manager.agents:
		if agent.role=="Authority": role_counts[agent.occupation]=int(role_counts.get(agent.occupation,0))+1
	return {"role_counts":role_counts,"active_assignments":assignments.filter(func(item):return item.status=="ACTIVE").size(),"unfinished_assignments":assignments.filter(func(item):return item.status in ["UNFINISHED","UNFILLED"]).size(),"reports":reports.size(),"orders":orders.size(),"complied_orders":orders.filter(func(item):return item.complied).size(),"roadblock_decisions":decisions.size(),"active_managed_roadblocks":sim.blocks.filter(func(block):return block.active and block.get("managed_by_policy",false)).size(),"desertion_events":desertion_events.size(),"family_emergencies":family_emergencies.size()}
