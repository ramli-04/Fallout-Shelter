extends RefCounted
## Authoritative post-impact reporting. Hazard values are fictional scenario indices.
var manager: Node
var started := false
var replaying := false
var start_seconds := 0.0
var started_wall := ""
var reports: Array = []
var samples: Array = []
var result: Dictionary = {}
var initial: Dictionary = {}
var arrivals: Dictionary = {}
var baselines: Dictionary = {}
var uptime: Dictionary = {}
var initial_social: Dictionary = {}
var opening: Dictionary = {"minimum_day":10,"outside_verified":false,"outside_hazard":1.0,"maximum_hazard":0.25,"route_clear":false,"allow_damaged":false,"require_power":false,"require_child_supervision":true}
var overrides: Dictionary = {}
var fast_forward := false
var fast_target := 0.0
var fast_signature := ""
var export_path := ""

func reset(owner: Node) -> void:
	manager=owner; started=false; replaying=false; start_seconds=0; started_wall=""
	reports.clear(); samples.clear(); result.clear(); initial.clear(); arrivals.clear(); baselines.clear(); uptime.clear(); initial_social.clear()
	fast_forward=false; fast_target=0; export_path=""

func begin(owner: Node) -> void:
	reset(owner); started=true; start_seconds=manager.elapsed_seconds; started_wall=Time.get_datetime_string_from_system(true)
	var life=manager.social.shelter_life
	for a in manager.agents:
		initial[a.id]={"id":a.id,"family_id":a.get("family_id",""),"age":a.get("age",30)}
		if a.get("state","")=="SHELTERED": arrivals[a.id]=a.get("shelter_id","")
	for id in life.shelters:
		var s: Dictionary=life.shelters[id]
		var count:=0
		for sid in arrivals.values(): count+=int(sid==id)
		s["water_liters"]=maxf(0,float(s.truth.get("water_liters",count*20.0)))
		baselines[id]={"food_person_days":s.person_days,"water_liters":s.water_liters}
		uptime[id]={"hours":0.0,"available_hours":0.0}
	initial_social=life.dynamics.metrics().duplicate(true)
	samples.append(measure(0))

func day_seconds() -> float:
	return manager.social.shelter_life.day_duration_seconds()

func elapsed_days() -> float:
	return clampf((manager.elapsed_seconds-start_seconds)/day_seconds(),0,10) if started else 0.0

func next_boundary() -> float:
	return start_seconds+(reports.size()+1)*day_seconds()

func configure(id: String, values: Dictionary) -> bool:
	if replaying or not result.is_empty(): return false
	for key in values:
		if not opening.has(key): return false
		if opening[key] is bool:
			if not values[key] is bool: return false
		elif not (values[key] is float or values[key] is int) or not is_finite(float(values[key])): return false
		elif float(values[key])<0 or float(values[key])>(30 if key=="minimum_day" else 1): return false
	if id.is_empty(): opening.merge(values,true)
	else:
		if not manager.shelter_by_id.has(id): return false
		var policy: Dictionary=overrides.get(id,{}); policy.merge(values,true); overrides[id]=policy
	return true

func signature() -> String:
	var transitions: Array=[]
	for event in manager.environment_events: transitions.append([event.get("event_id",""),event.get("status",""),int(float(event.get("severity",0))*4)])
	return str(transitions)+str(manager.agents.filter(func(a):return float(a.get("health",0))<=0).size())+str(reports.size())

func forward() -> void:
	if not started or replaying or not result.is_empty(): return
	fast_forward=true; fast_target=next_boundary(); fast_signature=signature()
	manager.start()

func tick(seconds: float) -> void:
	if not started or replaying or not result.is_empty(): return
	var life=manager.social.shelter_life
	for a in manager.agents:
		if a.get("state","")=="SHELTERED" and not arrivals.has(a.id): arrivals[a.id]=a.get("shelter_id","")
	for id in uptime:
		var s: Dictionary=life.shelters[id]
		uptime[id].hours+=seconds/day_seconds()*24
		var available:=int(s.get("power",false))+int(s.get("water",false))+int(s.get("air",false))
		uptime[id].available_hours+=seconds/day_seconds()*24*available/3.0
	var days:=elapsed_days()
	if samples.is_empty() or days-float(samples.back().day)>=1.0/24.0-0.000001: samples.append(measure(days))
	while reports.size()<10 and days+0.000001>=reports.size()+1:
		var report:=measure(reports.size()+1)
		report["wall_clock_utc"]=Time.get_datetime_string_from_system(true)
		report["social"]=life.dynamics.metrics().duplicate(true)
		var previous_families: Dictionary=(samples[0] if reports.is_empty() else reports.back()).family.groups
		var reunifications: Array=[]
		for id in report.family.groups:
			if report.family.groups[id].reunited and not previous_families.get(id,{}).get("reunited",false): reunifications.append(id)
		report["family_reunifications"]=reunifications
		report["major_events"]=life.storyteller.history.filter(func(e):return float(e.get("hour",0))>reports.size()*24 and float(e.get("hour",0))<=(reports.size()+1)*24).duplicate(true)
		reports.append(report)
		manager.log_event("DAILY REPORT","Shelter Day %d complete: %d survivors, %d deaths."%[reports.size(),report.population.survivors,report.population.deaths],"director")
	if fast_forward and (manager.elapsed_seconds>=fast_target or signature()!=fast_signature):
		fast_forward=false; manager.accumulator=0; manager.pause()

func families() -> Dictionary:
	var groups: Dictionary={}
	var live: Dictionary={}
	for a in manager.agents: live[a.id]=a
	for id in initial:
		var fid:=str(initial[id].family_id)
		if fid.is_empty(): continue
		if not groups.has(fid): groups[fid]={"members":[],"alive":[],"dead":[],"missing":[],"locations":[],"surviving_children":0}
		var g: Dictionary=groups[fid]; g.members.append(id)
		var a: Dictionary=live.get(id,{})
		if a.is_empty() or a.get("state","")=="MISSING": g.missing.append(id)
		elif float(a.get("health",0))<=0: g.dead.append(id)
		else:
			g.alive.append(id); g.surviving_children+=int(int(initial[id].age)<18)
			var location: String=str(a.get("shelter_id","")) if a.get("state","")=="SHELTERED" else "outside:"+str(id)
			if location not in g.locations: g.locations.append(location)
	var reunited:=0; var separated:=0; var children:=0; var missing:=0
	for g in groups.values():
		g["reunited"]=g.alive.size()>1 and g.locations.size()==1 and g.missing.is_empty()
		reunited+=int(g.reunited); separated+=int(g.locations.size()>1 or not g.missing.is_empty()); children+=g.surviving_children; missing+=g.missing.size()
	children=0
	for a in manager.agents:
		if int(a.get("age",30))<18 and float(a.get("health",0))>0 and a.get("state","")!="MISSING": children+=1
	return {"groups":groups,"reunited_families":reunited,"separated_families":separated,"surviving_children":children,"missing_relatives":missing}

func measure(day_value: float) -> Dictionary:
	var pop: Dictionary={"initial_population":initial.size(),"shelter_arrival_population":arrivals.size(),"survivors":0,"deaths":0,"injuries":0,"missing":0}
	var present: Dictionary={}
	var rows: Dictionary={}
	var life=manager.social.shelter_life
	for id in ["S1","S2","S3","S4","S5"]:
		var s: Dictionary=life.shelters.get(id,{})
		rows[id]={"exists":not s.is_empty(),"occupancy":0,"arrival_population":0,"arrival_survivors":0,"food_person_days":s.get("person_days",null),"water_liters":s.get("water_liters",null),"electricity":s.get("power",false),"air":s.get("air",false),"water_system":s.get("water",false),"infrastructure":s.get("truth",{}).get("storyteller_conditions",{}).duplicate(true),"stress":[],"morale":[],"family_survivors":0,"infrastructure_reliability":null}
		for sid in arrivals.values(): rows[id].arrival_population+=int(sid==id)
		if uptime.has(id) and uptime[id].hours>0: rows[id].infrastructure_reliability=uptime[id].available_hours/uptime[id].hours
		rows[id]["maintenance_actions"]=s.get("maintenance_actions",0)
		var incidents: Array=life.storyteller.events.filter(func(e):return e.get("target_id","")==id)
		rows[id]["infrastructure_failures"]=incidents.filter(func(e):return not str(life.storyteller.config.events.get(e.event_type,{}).get("system","")).is_empty()).size()
		rows[id]["resolved_events"]=incidents.filter(func(e):return e.get("status","")=="RESOLVED").size()
		rows[id]["event_count"]=incidents.size()
		rows[id]["maintenance_condition"]=s.get("truth",{}).get("maintenance_condition",null)
	for a in manager.agents:
		if not initial.has(a.id): continue
		present[a.id]=true
		if a.get("state","")=="MISSING": pop.missing+=1; continue
		if float(a.get("health",0))<=0: pop.deaths+=1; continue
		pop.survivors+=1; pop.injuries+=int(float(a.get("health",100))<100)
		var arrival:=str(arrivals.get(a.id,""))
		if rows.has(arrival): rows[arrival].arrival_survivors+=1
		var sid:=str(a.get("shelter_id",""))
		if a.get("state","")=="SHELTERED" and rows.has(sid):
			rows[sid].occupancy+=1; rows[sid].stress.append(float(a.get("stress",0))); rows[sid].morale.append(float(a.get("morale",0)))
			rows[sid].family_survivors+=int(not str(a.get("family_id","")).is_empty())
	pop.missing+=initial.size()-present.size()
	for row in rows.values(): row["survival_rate"]=float(row.arrival_survivors)/row.arrival_population if row.arrival_population>0 else null
	return {"day":day_value,"simulation_seconds":day_value*86400,"engine_seconds":manager.elapsed_seconds,"population":pop,"shelters":rows,"family":families()}

func opening_result(id: String) -> Dictionary:
	var policy:=opening.duplicate(true); policy.merge(overrides.get(id,{}),true)
	var s: Dictionary=manager.social.shelter_life.shelters.get(id,{})
	var truth: Dictionary=manager.shelter_by_id.get(id,{})
	var reasons: Array=[]
	if s.is_empty(): reasons.append("Shelter unavailable")
	if elapsed_days()<float(policy.minimum_day): reasons.append("Minimum shelter period not reached")
	if not policy.outside_verified: reasons.append("Outside conditions unverified")
	if float(policy.outside_hazard)>float(policy.maximum_hazard): reasons.append("Outside hazard exceeds configured threshold")
	if not policy.route_clear: reasons.append("Exit route unverified or blocked")
	if not truth.get("manual_accessible",true): reasons.append("Physical access blocked")
	if truth.get("manual_safety_status","SAFE") in ["UNSAFE","DESTROYED"]: reasons.append("Director safety restriction")
	if s.get("fire",false): reasons.append("Active shelter fire")
	if truth.get("structural_state","")=="DESTROYED": reasons.append("Structure destroyed")
	if truth.get("structural_state","")=="DAMAGED" and not policy.allow_damaged: reasons.append("Damaged structure requires clearance")
	if truth.get("door_status","") in ["BLOCKED","JAMMED","DESTROYED"]: reasons.append("Exit door unusable")
	if policy.require_power and not s.get("power",false): reasons.append("Required electrical supply unavailable")
	for e in manager.environment_events:
		if e.get("scope","")=="shelter" and e.get("target_id","")==id and e.get("active_status",false) and e.get("event_type","") in ["fire","flooding","structural_damage","door_malfunction"]: reasons.append("Unresolved "+str(e.event_type))
	return {"can_open":reasons.is_empty(),"status":"CLEARED_TO_OPEN" if reasons.is_empty() else "REMAIN_CLOSED","reasons":reasons,"conditions":policy}

func finish() -> void:
	if not started or replaying or not result.is_empty() or elapsed_days()<10: return
	result=measure(10)
	result.merge({"schema_version":1,"seed":manager.seed_value,"started_wall_clock_utc":started_wall,"finished_wall_clock_utc":Time.get_datetime_string_from_system(true),"daily_reports":reports.duplicate(true),"samples":samples.duplicate(true),"social":manager.social.shelter_life.dynamics.metrics(),"initial_social":initial_social,"storyteller":manager.social.shelter_life.storyteller.metrics(),"ai":manager.ai_bridge.metrics.duplicate(true) if manager.ai_bridge!=null else {},"survivor_outcomes":{}})
	var rules:=0
	for id in result.shelters:
		result.shelters[id]["opening"]=opening_result(id)
		if result.shelters[id].opening.can_open:
			preload("res://scripts/shelter_state.gd").set_door_state(manager.shelter_by_id[id],"OPEN")
		if baselines.has(id):
			result.shelters[id]["food_depletion_person_days"]=maxf(0,float(baselines[id].food_person_days)-float(result.shelters[id].food_person_days))
			result.shelters[id]["water_consumption_liters"]=maxf(0,float(baselines[id].water_liters)-float(result.shelters[id].water_liters))
	for id in initial: result.survivor_outcomes[id]={"outcome":"MISSING","can_leave":false}
	for a in manager.agents:
		rules+=int(a.get("rule_decision_count",0))
		var outcome:="MISSING" if a.get("state","")=="MISSING" else "DEAD" if float(a.get("health",0))<=0 else "SURVIVED_OUTSIDE"
		var can_leave:=false
		if float(a.get("health",0))>0 and a.get("state","")=="SHELTERED":
			var clearance: Dictionary=result.shelters.get(a.get("shelter_id",""),{}).get("opening",{})
			can_leave=clearance.get("can_open",false); outcome="CAN_LEAVE" if can_leave else "REMAIN_SHELTERED"
			if can_leave and int(a.get("age",30))<18 and clearance.conditions.require_child_supervision:
				var caregiver: Dictionary=manager.social.by_id.get(a.get("shelter_caregiver",""),{})
				if caregiver.is_empty() or float(caregiver.get("health",0))<=0 or int(caregiver.get("age",0))<18 or caregiver.get("shelter_id","")!=a.get("shelter_id","") or caregiver.get("state","")!="SHELTERED": can_leave=false; outcome="AWAITING_GUARDIAN"
		result.survivor_outcomes[a.id]={"outcome":outcome,"can_leave":can_leave,"health":a.get("health",0),"shelter_id":a.get("shelter_id",""),"family_id":a.get("family_id","")}
	result.ai["rule_based_decisions"]=rules
	result.ai["llm_decisions"]=int(result.ai.get("successful",0))
	result.ai["failed_decisions"]=maxi(0,int(result.ai.get("calls",0))-int(result.ai.get("successful",0)))
	result.ai["token_consumption"]=int(result.ai.get("input_tokens",0))+int(result.ai.get("output_tokens",0))
	result.ai["pending_requests_at_end"]=manager.ai_bridge.pending.size()+manager.ai_bridge.shelter_pending.size() if manager.ai_bridge!=null else 0
	var old_trust: Variant=initial_social.get("mean_relationships",{}).get("trust",null)
	var new_trust: Variant=result.social.get("mean_relationships",{}).get("trust",null)
	result.social["mean_trust_change"]=float(new_trust)-float(old_trust) if old_trust!=null and new_trust!=null else null
	result.social["major_conflicts"]=manager.social.shelter_life.dynamics.conflicts.duplicate(true)
	manager.summary.merge(result.population,true)
	manager.summary["dead"]=result.population.deaths; manager.summary["injured"]=result.population.injuries
	result.population["final_survivors"]=result.population.survivors
	fast_forward=false

func snapshot() -> Dictionary:
	return {"schema_version":1,"started":started,"start_seconds":start_seconds,"started_wall":started_wall,"reports":reports.duplicate(true),"samples":samples.duplicate(true),"result":result.duplicate(true),"initial":initial.duplicate(true),"arrivals":arrivals.duplicate(true),"baselines":baselines.duplicate(true),"uptime":uptime.duplicate(true),"initial_social":initial_social.duplicate(true),"opening":opening.duplicate(true),"overrides":overrides.duplicate(true)}

func restore(data: Dictionary, owner: Node) -> void:
	reset(owner); replaying=true
	if int(data.get("schema_version",0))!=1: return
	for key in ["started","start_seconds","started_wall","reports","samples","result","initial","arrivals","baselines","uptime","initial_social","opening","overrides"]:
		if data.has(key): set(key,data[key].duplicate(true) if data[key] is Dictionary or data[key] is Array else data[key])
	manager.post_impact_started_seconds=start_seconds
	manager.post_impact_complete=not result.is_empty()
	if started: manager.post_impact_end_seconds=start_seconds+day_seconds()*10

func export_report() -> String:
	if result.is_empty(): return ""
	var folder:="res://outputs/survival-%s-%s"%[manager.seed_value,started_wall.replace(":","-")]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var ignore:=FileAccess.open(folder+"/.gdignore",FileAccess.WRITE)
	if ignore: ignore.close()
	var file:=FileAccess.open(folder+"/results.json",FileAccess.WRITE)
	if file==null: return ""
	file.store_string(JSON.stringify(result,"\t")); file.close(); export_path=ProjectSettings.globalize_path(folder+"/results.json")
	var python:=ProjectSettings.globalize_path("res://.venv/Scripts/python.exe")
	if FileAccess.file_exists(python): OS.create_process(python,[ProjectSettings.globalize_path("res://tools/survival_report.py"),export_path],false)
	return export_path
