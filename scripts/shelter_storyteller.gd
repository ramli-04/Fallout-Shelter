extends RefCounted
## Pacing and simplified hazards for the existing environment-event stream.
## Truth stays private; only observation or an in-shelter report informs a responder.
var owner: WeakRef
var life: RefCounted:
	get: return owner.get_ref() if owner!=null else null
var config: Dictionary={}
var events: Array[Dictionary]=[]
var history: Array[Dictionary]=[]
var conditions: Dictionary={}
var rngs: Dictionary={}
var cooldowns: Dictionary={}
var pacing: Dictionary={}
var door_blocks: Dictionary={}
var counts: Dictionary={}
var elapsed_hours:=0.0
var accumulator:=0.0
var sequence:=0
var generation_paused:=false
var replaying:=false
var last_error:=""

func reset() -> void:
	events.clear(); history.clear(); conditions.clear(); rngs.clear(); cooldowns.clear(); pacing.clear(); door_blocks.clear(); counts.clear()
	elapsed_hours=0; accumulator=0; sequence=0; generation_paused=false; replaying=false; last_error=""

func initialize(value: RefCounted) -> void:
	owner=weakref(value); reset()
	for index in range(life.manager.environment_events.size()-1,-1,-1):
		if life.manager.environment_events[index].get("scope","")=="shelter": life.manager.environment_events.remove_at(index)
	config=JSON.parse_string(FileAccess.get_file_as_string("res://resources/shelter_storyteller.json"))
	for key in ["automatic","manual","resolved","escalations","responses","evacuation_orders","rejected_responses"]: counts[key]=0
	for id in life.shelters:
		var refuge: Dictionary=life.shelters[id]
		var random:=RandomNumberGenerator.new(); random.seed=life.manager.seed_for("events")+675031+int(str(id).substr(1))*1097; rngs[id]=random
		conditions[id]={}
		door_blocks[id]=[]
		for definition in config.events.values():
			if not str(definition.system).is_empty(): conditions[id][definition.system]=clampf(float(refuge.truth.get("infrastructure_condition",{}).get(definition.system,refuge.truth.get("maintenance_condition",100))),0,100)
		pacing[id]={"last_event":-100.0,"last_critical":-100.0,"day":-1,"today":0,"maintenance_hours":0.0}
		refuge["medical_supplies"]=float(refuge.get("medical_supplies",3.0+life.dynamics.residents(id).size()*.5))
		refuge["medical_reserve"]=float(refuge.get("medical_reserve",2.0))
		refuge["spare_parts"]=float(refuge.get("spare_parts",6.0))
		refuge["storyteller_base"]={"power":refuge.power,"air":refuge.air,"water":refuge.water}
		refuge["communications"]=true
		refuge["water_quality"]=1.0; refuge["temperature_c"]=20.0

func catalog() -> Array:
	var result: Array=config.get("events",{}).keys(); result.sort(); return result

func active(id: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for event in events:
		if event.active_status and (id.is_empty() or event.target_id==id): result.append(event)
	return result

func find(id: String) -> Dictionary:
	for event in events:
		if event.event_id==id: return event
	return {}

func profile(id: String) -> Dictionary:
	var result: Dictionary=config.shelter_profiles.get(id,config.shelter_profiles.S1).duplicate(true)
	result.merge(life.shelters[id].truth.get("storyteller_profile",{}),true)
	return result

func risk(id: String,kind: String) -> float:
	if not life.shelters.has(id) or not config.events.has(kind): return 0.0
	var members: Array[Dictionary]=life.dynamics.residents(id)
	if members.is_empty(): return 0.0
	var refuge: Dictionary=life.shelters[id]; var definition: Dictionary=config.events[kind]; var traits:=profile(id)
	var occupancy:=float(members.size())/maxf(1,float(refuge.truth.capacity))
	var wear:=1.0-float(conditions[id].get(definition.system,100))/100.0
	var pressure:=1.0+wear*3+(1-float(traits.reliability))*2+minf(2,occupancy)*.7
	if kind in ["flooding","broken_pipes","rat_infestation","pest_contamination","water_contamination"]: pressure+=float(traits.dampness)*2
	if kind in ["respiratory_problems","infection"]: pressure+=occupancy*2+(2 if not refuge.air else 0)
	if kind=="infection" and active(id).any(func(e):return e.event_type in ["rat_infestation","pest_contamination","water_contamination"]): pressure*=1.8
	if kind=="injury" and members.any(func(a):return a.get("current_activity_code","") in ["REPAIR_EQUIPMENT","MAINTAIN_GENERATOR","SECURITY"] or float(a.get("fatigue",0))>75): pressure*=1.5
	if kind=="dehydration" and not members.any(func(a):return float(a.get("thirst",0))>65): return 0.0
	if kind=="exhaustion" and not members.any(func(a):return float(a.get("fatigue",0))>75): return 0.0
	if kind=="medical_supply_shortage" and float(refuge.medical_supplies)>1.0: return 0.0
	if definition.category=="social":
		if _pair(id,kind).is_empty(): return 0.0
		var stress:=0.0
		for a in members: stress+=float(a.get("stress",0))
		if stress/members.size()<45: return 0.0
		pressure+=stress/members.size()/40
	if kind=="food_theft" and (refuge.person_days>members.size() or not members.any(func(a):return float(a.get("hunger",0))>65 and float(a.get("cooperation",50))<30)): return 0.0
	if kind=="group_panic" and not members.any(func(a):return float(a.get("fear",0))>60): return 0.0
	if kind=="refusal_to_work" and not members.any(func(a):return not str(a.get("shelter_social_task","")).is_empty()): return 0.0
	if kind in ["electrical_short","fire"] and not refuge.power: pressure*=.35
	if kind=="flooding" and active(id).any(func(e):return e.event_type=="broken_pipes"): pressure*=2.5
	if kind=="respiratory_problems" and active(id).any(func(e):return e.event_type in ["air_filtration_failure","ventilation_blockage","fire"]): pressure*=2
	pressure*=1.0-float(traits.redundancy)*.45
	pressure/=1.0+float(pacing[id].maintenance_hours)*.08
	return maxf(0,float(definition.rate_per_hour)*pressure*float(life.social.config.get("event_frequency",1.0)))

func _pair(id: String,kind: String) -> Array:
	var members: Array[Dictionary]=life.dynamics.residents(id)
	for a in members:
		for b in members:
			if not life.dynamics.together(a,b): continue
			if kind in ["refusal_to_work","leadership_dispute"] and int(a.get("age",0))<18: continue
			if kind=="family_disagreement" and (str(a.get("family_id","")).is_empty() or a.get("family_id","")!=b.get("family_id","")): continue
			if kind=="authority_civilian_conflict" and (a.get("role","")==b.get("role","") or "Authority" not in [a.get("role",""),b.get("role","")]): continue
			if kind=="food_theft" and (int(a.get("age",30))<18 or float(a.get("cooperation",50))>=30 or float(a.get("hunger",0))<65 or float(b.get("hunger",0))<65): continue
			return [a,b]
	return []

func trigger(kind: String,id: String,severity: float = .3,manual: bool = true, room_id: String = "") -> String:
	last_error=""
	if life==null or replaying or not life.active or life.completed: last_error="An active shelter phase is required"; return ""
	if not config.events.has(kind) or not life.shelters.has(id) or not is_finite(severity) or severity<=0 or severity>1: last_error="Invalid event, shelter or severity"; return ""
	if life.dynamics.residents(id).is_empty(): last_error="No living residents in this shelter"; return ""
	if active(id).any(func(e):return e.event_type==kind): last_error="This event is already active"; return ""
	var key:=id+":"+kind
	if elapsed_hours<float(cooldowns.get(key,-1)): last_error="Event cooldown is active"; return ""
	if active(id).size()>=int(config.max_active_per_shelter): last_error="Shelter event budget is full"; return ""
	var definition: Dictionary=config.events[kind]; var pair: Array=[]; var patient: Dictionary={}
	if definition.category=="social":
		pair=_pair(id,kind)
		if pair.is_empty(): last_error="This social event requires a matching co-present pair"; return ""
		room_id=str(pair[0].shelter_room_id)
	if definition.category=="health" and kind!="medical_supply_shortage":
		var members: Array[Dictionary]=life.dynamics.residents(id)
		members.sort_custom(func(a,b):return float(a.get("thirst",0))>float(b.get("thirst",0)) if kind=="dehydration" else float(a.get("fatigue",0))>float(b.get("fatigue",0)) if kind=="exhaustion" else float(a.health)<float(b.health))
		patient=members[0]; room_id=str(patient.get("shelter_room_id",""))
	if room_id.is_empty(): room_id=life._room_of_type(id,definition.rooms)
	if room_id.is_empty(): room_id=life.rooms_by_shelter[id][0]
	if not life.rooms.has(room_id) or life.rooms[room_id].shelter_id!=id: last_error="Room is not in the target shelter"; return ""
	if kind=="food_theft":
		var saved_code: String=pair[0].get("current_activity_code","")
		pair[0].current_activity_code="EAT"
		var taken: bool=life.dynamics.take_extra_ration(pair[0],pair[1]); pair[0].current_activity_code=saved_code
		if not taken: last_error="No actual ration theft was possible under these conditions"; return ""
	sequence+=1
	var event: Dictionary={"event_id":"ST%05d"%sequence,"event_type":kind,"category":definition.category,"scope":"shelter","target_id":id,"room_id":room_id,"target_location":life.rooms[room_id].position,"severity":severity,"initial_severity":severity,"origin":"MANUAL TEST" if manual else "STORYTELLER","manual":manual,"scheduled_time":0.0,"start_at":life.manager.elapsed_seconds if manual else life.started_at+elapsed_hours*3600.0/life.routine_clock_rate(),"started_hour":elapsed_hours,"duration":0.0,"active_status":true,"started":true,"ended":false,"dynamic":false,"visibility_to_agents":[],"status":"ACTIVE","progress":0.0,"work_required":float(definition.work_hours)*(.5+severity),"responders":[],"patient":patient.get("id",""),"members":pair.map(func(a):return a.id),"linked_conflict":"","last_escalation_hour":elapsed_hours,"event_log_message":("[MANUAL TEST] " if manual else "")+kind+" in "+id,"actual_effect":"shelter "+str(definition.category)}
	events.append(event); life.manager.environment_events.append(event)
	cooldowns[key]=elapsed_hours+float(definition.cooldown_hours)
	pacing[id].last_event=elapsed_hours; pacing[id].today+=1
	if severity>=.65: pacing[id].last_critical=elapsed_hours
	counts["manual" if manual else "automatic"]+=1
	if not str(definition.system).is_empty(): conditions[id][definition.system]=minf(float(conditions[id][definition.system]),100*(1-severity))
	if not pair.is_empty():
		var cause: String={"argument":"personal_disagreement","leadership_dispute":"leadership","food_theft":"resource_theft","refusal_to_work":"rule_violation","group_panic":"security","family_disagreement":"personal_disagreement","authority_civilian_conflict":"leadership"}[kind]
		var dispute: Dictionary=life.dynamics.open_conflict(pair[0],pair[1],cause)
		event.linked_conflict=dispute.get("id","")
		if kind=="refusal_to_work": pair[0]["refusing_work_event"]=event.event_id
	if not patient.is_empty():
		if kind in ["injury","infection","respiratory_problems"]: patient.health=maxf(0,float(patient.health)-severity*8)
		if kind=="dehydration": patient.thirst=maxf(float(patient.get("thirst",0)),65+severity*20)
		if kind=="exhaustion": patient.fatigue=maxf(float(patient.get("fatigue",0)),75+severity*20)
	if kind in ["rat_infestation","pest_contamination"]:
		life.shelters[id].person_days=maxf(0,float(life.shelters[id].person_days)*(1-severity*.08))
	if kind=="medical_supply_shortage": life.shelters[id].medical_supplies*=.5
	project(id); observe(); _audit("started",event)
	return event.event_id

func tick(seconds: float) -> void:
	if life==null or replaying or seconds<=0 or not is_finite(seconds): return
	accumulator+=seconds*life.routine_clock_rate()/3600
	var interval:=float(config.step_minutes)/60
	while accumulator+.00000001>=interval:
		accumulator-=interval; elapsed_hours+=interval; step(interval)

func step(hours: float) -> void:
	observe()
	for event in active():
		var definition: Dictionary=config.events[event.event_type]
		var old: float=event.severity
		event.severity=maxf(old,minf(.95,old+float(definition.escalation_per_hour)*hours*(1-float(profile(event.target_id).redundancy)*.5)))
		if old<.65 and event.severity>=.65: pacing[event.target_id].last_critical=elapsed_hours
		if elapsed_hours-float(event.last_escalation_hour)>=1.0 and event.severity>old:
			event.last_escalation_hour=elapsed_hours; counts.escalations+=1; _audit("escalated",event)
		consequences(event,hours)
		for a in life.dynamics.residents(event.target_id):
			if str(a.get("shelter_event_assignment",""))==event.event_id:
				if can_respond(event,a,true): respond(event.event_id,a,hours)
			elif str(a.get("shelter_event_assignment","")).is_empty() and can_respond(event,a,false) and not life._critical_need(a): request_response(event.event_id,a)
		project(event.target_id)
	if generation_paused: return
	for id in pacing:
		var pace: Dictionary=pacing[id]
		var day:=int(floor(elapsed_hours/24))
		if int(pace.day)!=day: pace.day=day; pace.today=0
		if elapsed_hours<float(config.warmup_hours) or elapsed_hours-float(pace.last_event)<float(config.minimum_gap_hours) or pace.today>=int(config.max_events_per_day) or active(id).size()>=int(config.max_active_per_shelter): continue
		var choices: Array=[]; var total:=0.0
		for kind in catalog():
			if elapsed_hours<float(cooldowns.get(id+":"+kind,-1)) or active(id).any(func(e):return e.event_type==kind): continue
			var weight:=risk(id,kind)
			if weight>0: choices.append([kind,weight]); total+=weight
		if total<=0: continue
		var random: RandomNumberGenerator=rngs[id]
		if random.randf()>=1-exp(-total*hours): continue
		var draw:=random.randf()*total
		for choice in choices:
			draw-=float(choice[1])
			if draw>0: continue
			var severity:=random.randf_range(config.automatic_severity_range[0],config.automatic_severity_range[1])
			# A critical incident imposes a long recovery window, even after repair.
			if elapsed_hours-float(pace.last_critical)<float(config.critical_event_gap_hours): severity=minf(severity,.3)
			trigger(choice[0],id,severity,false); break

func knows(a: Dictionary,id: String) -> bool:
	return a.get("shelter_event_knowledge",{}).has(id)

func known_failure(a: Dictionary,activities: Array) -> bool:
	var relevant: Array[Dictionary]=[]
	for event in active(str(a.get("shelter_id",""))):
		if config.events[event.event_type].activity in activities: relevant.append(event)
	return relevant.is_empty() or relevant.any(func(e):return knows(a,e.event_id))

func observe() -> void:
	for event in active():
		var witnesses: Array=[]
		for a in life.dynamics.residents(event.target_id):
			if a.get("shelter_room_id","")==event.room_id and a.get("shelter_activity_state","")!="MOVING":
				learn(a,event,"direct observation",a.id); witnesses.append(a.id)
		if witnesses.is_empty() or not life.shelters[event.target_id].get("communications",true): continue
		for a in life.dynamics.residents(event.target_id):
			if a.get("role","")=="Authority" or life._has_skill(a,"technical") or life._has_skill(a,"medical"):
				learn(a,event,"in-shelter report",witnesses[0])

func learn(a: Dictionary,event: Dictionary,evidence: String,source: String) -> void:
	if not a.has("shelter_event_knowledge"): a.shelter_event_knowledge={}
	if knows(a,event.event_id) and a.shelter_event_knowledge[event.event_id].evidence=="direct observation": return
	a.shelter_event_knowledge[event.event_id]={"kind":event.event_type,"room_id":event.room_id,"source":source,"evidence":evidence,"at_hour":elapsed_hours,"confidence":1.0 if evidence=="direct observation" else .85}
	if a.id not in event.visibility_to_agents: event.visibility_to_agents.append(a.id)

func can_respond(event: Dictionary,a: Dictionary,at_location: bool) -> bool:
	if event.is_empty() or not event.active_status or a.get("health",0)<35 or int(a.get("age",0))<18 or a.get("state","")!="SHELTERED" or not a.get("shelter_life_active",false) or a.get("emergency_exit_active",false) or a.get("shelter_id","")!=event.target_id or not knows(a,event.event_id) or float(a.get("stress",0))>90: return false
	if not str(a.get("refusing_work_event","")).is_empty(): return false
	var definition: Dictionary=config.events[event.event_type]
	var skill: String=definition.skill
	if skill=="social":
		if float(a.get("empathy",50))<45 or float(a.get("cooperation",50))<45: return false
	elif skill=="care":
		if float(a.get("empathy",50))<45: return false
	elif skill!="any" and not life._has_skill(a,skill): return false
	var target:=response_room(event,a)
	if at_location and (a.get("shelter_room_id","")!=target or a.get("shelter_activity_state","")=="MOVING" or a.get("current_activity_code","")!=definition.activity): return false
	return life._reachable(str(a.get("shelter_room_id","")),target)

func response_room(event: Dictionary,a: Dictionary) -> String:
	if event.event_type=="door_malfunction":
		for neighbor in life.rooms[event.room_id].navigation_connections:
			if life._reachable(str(a.get("shelter_room_id","")),neighbor): return neighbor
	return str(event.room_id)

func request_response(id: String,a: Dictionary) -> bool:
	var event:=find(id)
	if replaying or not can_respond(event,a,false) or life._critical_need(a): counts.rejected_responses=int(counts.get("rejected_responses",0))+1; return false
	if a.get("current_activity_code","") in ["EAT","DRINK","SLEEP","TREATMENT","CHILDCARE"] and not (event.event_type in ["fire","flooding","structural_damage"] and float(event.severity)>=.65): return false
	if not str(a.get("shelter_event_assignment","")).is_empty() and a.shelter_event_assignment!=id: return false
	# Mutual trust matters to willingness to help an injured resident.
	var patient: Dictionary=life.social.by_id.get(event.patient,{})
	if not patient.is_empty() and patient.id!=a.id and float(life.dynamics.relationship(a,patient).conflict)>75 and float(a.get("cooperation",50))<65: return false
	a["shelter_event_assignment"]=id
	life._start_activity(a,config.events[event.event_type].activity)
	if a.get("current_activity_code","")!=config.events[event.event_type].activity: a.shelter_event_assignment=""; return false
	if a.id not in event.responders: event.responders.append(a.id); _audit("response_assigned",event,{"agent":a.id})
	return true

func respond(id: String,a: Dictionary,hours: float) -> bool:
	var event:=find(id)
	if replaying or not is_finite(hours) or hours<=0 or hours>8 or not can_respond(event,a,true): counts.rejected_responses=int(counts.get("rejected_responses",0))+1; return false
	var ability:=clampf(.5+float(a.get("cooperation",50))*.005-float(a.get("stress",0))*.003,.2,1.0)
	if event.progress>=event.work_required: return resolve(id,a)
	event.progress=minf(float(event.work_required),float(event.progress)+hours*ability); counts.responses+=1
	if config.events[event.event_type].skill=="technical": pacing[event.target_id].maintenance_hours+=hours
	if event.progress>=event.work_required: return resolve(id,a)
	return true

func resolve(id: String,a: Dictionary) -> bool:
	var event:=find(id)
	if replaying or event.is_empty() or not can_respond(event,a,true) or float(event.progress)+.000001<float(event.work_required): return false
	var refuge: Dictionary=life.shelters[event.target_id]; var definition: Dictionary=config.events[event.event_type]
	var patient: Dictionary=life.social.by_id.get(event.patient,{})
	if definition.skill=="technical" and refuge.spare_parts<1.0: event.status="AWAITING_RESOURCES"; event["resolution_blocked"]="spare parts"; return false
	if definition.skill=="medical" and refuge.medical_supplies<.25: event.status="AWAITING_RESOURCES"; event["resolution_blocked"]="medical supplies"; return false
	if event.event_type=="medical_supply_shortage":
		if refuge.medical_reserve<=0: event.status="AWAITING_RESOURCES"; event["resolution_blocked"]="no medical reserve to recover"; return false
		var recovered:=minf(2.0,float(refuge.medical_reserve)); refuge.medical_reserve-=recovered; refuge.medical_supplies+=recovered
	if event.event_type=="dehydration" and (not refuge.water or float(refuge.get("water_liters",.5))<.5): event.status="AWAITING_RESOURCES"; event["resolution_blocked"]="potable water"; return false
	if not str(event.linked_conflict).is_empty():
		var settled:=false
		for dispute in life.dynamics.conflicts:
			if dispute.id==event.linked_conflict and dispute.status=="RESOLVED": settled=true
		if not settled and not life.dynamics.resolve(event.linked_conflict,a): event.status="AWAITING_AGREEMENT"; event["resolution_blocked"]="underlying dispute"; return false
	if definition.skill=="technical": refuge.spare_parts-=1.0
	if definition.skill=="medical": refuge.medical_supplies-=.25
	if not patient.is_empty() and patient.get("health",0)>0:
		if definition.skill=="medical": patient.health=minf(100,float(patient.health)+12); life.dynamics.interact(a,patient,"help")
		if event.event_type=="dehydration":
			if refuge.has("water_liters"): refuge.water_liters=maxf(0,float(refuge.water_liters)-.5)
			patient.thirst=maxf(0,float(patient.thirst)-35)
		if event.event_type=="exhaustion": patient.fatigue=maxf(0,float(patient.fatigue)-30)
	if not str(definition.system).is_empty(): conditions[event.target_id][definition.system]=maxf(85,float(conditions[event.target_id][definition.system]))
	event.active_status=false; event.ended=true; event.status="RESOLVED"; event["resolved_hour"]=elapsed_hours; event["resolved_by"]=a.id
	event.erase("resolution_blocked")
	cooldowns[event.target_id+":"+event.event_type]=elapsed_hours+float(definition.cooldown_hours)
	for member in life.dynamics.residents(event.target_id):
		if member.get("shelter_event_assignment","")==id: member.shelter_event_assignment=""
		if member.get("refusing_work_event","")==id: member.refusing_work_event=""
	counts.resolved+=1; project(event.target_id); _audit("resolved",event)
	return true

func consequences(event: Dictionary,hours: float) -> void:
	var refuge: Dictionary=life.shelters[event.target_id]
	var severity: float=event.severity
	if event.event_type=="water_contamination": refuge.water_quality=maxf(0,1-severity)
	if event.event_type=="temperature_change": refuge.temperature_c=20+severity*15
	for a in life.dynamics.residents(event.target_id):
		var local: bool=a.get("shelter_room_id","")==event.room_id
		if event.event_type in ["air_filtration_failure","ventilation_blockage"]:
			# Shared air is a shelter-wide exposure; this is a small abstract health cost.
			a.health=maxf(0,float(a.health)-severity*hours*.35)
		if local and event.event_type in ["fire","flooding","structural_damage"]: a.health=maxf(0,float(a.health)-severity*hours*(1.5 if event.event_type=="fire" else .4))
		if a.id==event.patient and event.event_type in ["infection","respiratory_problems"]: a.health=maxf(0,float(a.health)-severity*hours*.4)
		if local and event.event_type in ["underground_noises","group_panic","temperature_change"]: life.dynamics.feel(a,{"fear":severity*hours*2,"anxiety":severity*hours,"stress":severity*hours})
		if a.health<=0: a.shelter_life_active=false; a.survival_status="DEAD"; a.current_activity="Deceased"; a.activity_animation="lying"

func project(id: String) -> void:
	var refuge: Dictionary=life.shelters[id]
	var pending:=active(id)
	refuge.power=refuge.storyteller_base.power and not pending.any(func(e):return e.event_type=="generator_failure" or (e.event_type=="electrical_short" and e.severity>=.5))
	refuge.air=refuge.storyteller_base.air and not pending.any(func(e):return e.event_type in ["air_filtration_failure","ventilation_blockage"])
	refuge.water=float(refuge.get("water_liters",1))>0 and refuge.storyteller_base.water and not pending.any(func(e):return e.event_type in ["water_pump_failure","broken_pipes","water_contamination"])
	refuge.communications=not pending.any(func(e):return e.event_type=="communication_failure")
	refuge.fire=pending.any(func(e):return e.event_type=="fire") or life.manager.environment_events.any(func(e):return e.get("scope","")!="shelter" and e.active_status and e.target_id==id and e.event_type=="fire")
	if not pending.any(func(e):return e.event_type=="water_contamination"): refuge.water_quality=1.0
	if not pending.any(func(e):return e.event_type=="temperature_change"): refuge.temperature_c=20.0
	refuge.truth.power_available=refuge.power; refuge.truth.air_available=refuge.air; refuge.truth.water_available=refuge.water
	refuge.truth.supply_level=refuge.person_days; refuge.truth["storyteller_conditions"]=conditions[id].duplicate(true)
	preload("res://scripts/shelter_state.gd").refresh(refuge.truth,life.manager.environment_events)
	refuge.emergency=refuge.fire or pending.any(func(e):return e.severity>=.65 or e.event_type in ["flooding","air_filtration_failure","ventilation_blockage"]) or refuge.truth.get("safety_status","SAFE") in ["UNSAFE","DESTROYED"] or not refuge.truth.operational
	# Repair must clear only our door restriction; existing closures retain ownership.
	var door_event: bool=pending.any(func(e):return e.event_type=="door_malfunction")
	if not door_blocks.has(id): door_blocks[id]=[]
	if not door_event:
		for key in door_blocks[id]: life.blocked_doors.erase(key)
		door_blocks[id]=[]
	for rid in life.rooms_by_shelter[id]:
		if life.rooms[rid].room_type not in ["Entrance","Secure entrance"]: continue
		for neighbor in life.rooms[rid].navigation_connections:
			var key: String=life._door_key(rid,neighbor)
			if door_event and not life.blocked_doors.has(key): life.blocked_doors[key]=INF; door_blocks[id].append(key)

func adjust_severity(id: String,value: float) -> bool:
	var event:=find(id)
	if replaying or event.is_empty() or not event.active_status or not is_finite(value) or value<=0 or value>1: return false
	event.severity=value
	if value>=.65: pacing[event.target_id].last_critical=elapsed_hours
	event.work_required=float(config.events[event.event_type].work_hours)*(.5+value)
	event["manually_adjusted"]=true; project(event.target_id); _audit("manual_severity",event); return true

func pause_generation(value: bool) -> void:
	if replaying: return
	generation_paused=value
	_audit("generation_paused" if value else "generation_resumed",{})

func order_transfer(id: String,commander: Dictionary) -> bool:
	var event:=find(id)
	if replaying or event.is_empty() or not event.active_status or not knows(commander,id) or not life._has_skill(commander,"leadership") or commander.get("shelter_id","")!=event.target_id or commander.get("health",0)<=0 or commander.get("shelter_activity_state","")=="MOVING": return false
	if int(commander.get("age",0))<18 or float(commander.get("stress",0))>90: return false
	var source: Dictionary=life.shelters[event.target_id].truth
	if source.door_status!="OPEN": return false
	var ordered:=0
	for a in life.dynamics.residents(event.target_id):
		if not life.dynamics.together(commander,a): continue
		var plan: Dictionary=a.duplicate(true); plan.position=source.exit_position; plan.indoor_id=""; plan.evacuation_requires_verified=true
		plan.evacuation_excluded_shelters=[event.target_id]
		var alternative: Dictionary=preload("res://scripts/evacuation_decisions.gd").evaluate(plan,1800,life.manager.settings.evacuation.weights)
		if alternative.shelter_id.is_empty(): continue
		a["evacuating_shelter"]=event.target_id; a["planned_transfer_shelter"]=alternative.shelter_id; a["evacuation_requires_verified"]=true; ordered+=1
	if ordered==0: return false
	counts.evacuation_orders+=1; _audit("transfer_order",event,{"commander":commander.id,"residents":ordered})
	return true

func _audit(action: String,event: Dictionary,extra: Dictionary = {}) -> void:
	var item: Dictionary={"action":action,"hour":elapsed_hours,"event_id":event.get("event_id",""),"kind":event.get("event_type",""),"shelter":event.get("target_id",""),"severity":event.get("severity",0),"origin":event.get("origin","DIRECTOR CONTROL"),"manual":event.get("manual",true)}
	item.merge(extra); history.append(item)
	if life!=null: life.social.emit_event("shelter.storyteller_"+action,item.event_id,item)

func metrics() -> Dictionary:
	var result: Dictionary=counts.duplicate(true)
	result.merge({"hours":elapsed_hours,"active":active().size(),"generation_paused":generation_paused,"replaying":replaying,"by_type":{}})
	for event in events: result.by_type[event.event_type]=int(result.by_type.get(event.event_type,0))+1
	return result

func snapshot() -> Dictionary:
	var states: Dictionary={}; var supplies: Dictionary={}
	for id in rngs: states[id]={"seed":str(rngs[id].seed),"state":str(rngs[id].state)}
	if life!=null:
		for id in life.shelters:
			var refuge: Dictionary=life.shelters[id]; supplies[id]={}
			for key in ["person_days","water_liters","maintenance_actions","medical_supplies","medical_reserve","spare_parts","storyteller_base","water_quality","temperature_c"]:
				if refuge.has(key): supplies[id][key]=refuge[key].duplicate(true) if refuge[key] is Dictionary else refuge[key]
	var clock: Dictionary={"day":float(life.day),"active":life.active,"completed":life.completed,"elapsed":life.elapsed} if life!=null else {}
	return {"schema_version":1,"life_clock":clock,"events":events.duplicate(true),"history":history.duplicate(true),"conditions":conditions.duplicate(true),"cooldowns":cooldowns.duplicate(true),"pacing":pacing.duplicate(true),"door_blocks":door_blocks.duplicate(true),"counts":counts.duplicate(true),"hours":elapsed_hours,"accumulator":accumulator,"sequence":sequence,"paused":generation_paused,"rngs":states,"supplies":supplies}

func restore(value: Dictionary,owner_life: RefCounted) -> bool:
	if int(value.get("schema_version",0))!=1 or not value.get("events") is Array or not value.get("conditions") is Dictionary: return false
	for key in ["history","cooldowns","pacing","counts","hours","accumulator","sequence","paused","rngs","supplies"]:
		if not value.has(key): return false
	for key in ["conditions","cooldowns","pacing","counts","rngs","supplies"]:
		if not value[key] is Dictionary: return false
	if not value.history is Array or not is_finite(float(value.hours)) or not is_finite(float(value.accumulator)): return false
	var definitions: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/shelter_storyteller.json"))
	for event in value.events:
		if not event is Dictionary or not definitions.events.has(event.get("event_type","")) or not owner_life.manager.shelter_by_id.has(event.get("target_id","")): return false
		for key in ["event_id","room_id","severity","active_status","progress","work_required"]:
			if not event.has(key): return false
	for id in value.supplies:
		if not owner_life.manager.shelter_by_id.has(id) or not value.conditions.has(id): return false
	owner=weakref(owner_life); reset(); replaying=true
	config=JSON.parse_string(FileAccess.get_file_as_string("res://resources/shelter_storyteller.json"))
	events.assign(value.events.duplicate(true)); history.assign(value.history.duplicate(true)); conditions=value.conditions.duplicate(true)
	cooldowns=value.cooldowns.duplicate(true); pacing=value.pacing.duplicate(true); counts=value.counts.duplicate(true)
	door_blocks=value.get("door_blocks",{}).duplicate(true)
	elapsed_hours=value.hours; accumulator=value.accumulator; sequence=int(value.sequence); generation_paused=value.paused
	for key in value.get("life_clock",{}): life[key]=value.life_clock[key]
	for id in value.rngs:
		var random:=RandomNumberGenerator.new(); random.seed=int(value.rngs[id].seed); random.state=int(value.rngs[id].state); rngs[id]=random
	for id in value.supplies:
		if not life.shelters.has(id): life._create_shelter(life.manager.shelter_by_id[id])
		life.shelters[id].merge(value.supplies[id].duplicate(true),true)
		project(id)
	for index in range(life.manager.environment_events.size()-1,-1,-1):
		if life.manager.environment_events[index].get("scope","")=="shelter": life.manager.environment_events.remove_at(index)
	for event in events: life.manager.environment_events.append(event)
	return true
