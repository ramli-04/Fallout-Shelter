extends RefCounted
## Three layers: immediate local safety, bounded utility, existing asynchronous AI.
const Perception = preload("res://scripts/agent_perception.gd")
const Map = preload("res://scripts/city_map.gd")
const Routes = preload("res://scripts/road_routes.gd")
const Actions = preload("res://scripts/llm_actions.gd")
var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/agent_cognition.json"))
var owner: WeakRef
var sim: RefCounted:
	get: return owner.get_ref() if owner!=null else null

func initialize(value: RefCounted) -> void:
	owner=weakref(value)
	config.perception_interval=maxf(.1,float(config.perception_interval))
	config.decision_interval=maxf(.5,float(config.decision_interval))
	config.context_interval=maxf(5,float(config.context_interval))
	for a in sim.manager.agents: ensure(a)

func ensure(a: Dictionary) -> void:
	if a.has("cognition"): return
	a.cognition={"observations":[],"memory":[],"history":[],"action":"CONTINUE","layer":"UTILITY","reason":"Continue current goal","scores":{},"next_observe":0.0,"next_decide":0.0,"next_context":0.0,"until":0.0,"route":PackedVector2Array(),"index":1,"progress_position":a.position,"progress_time":0.0,"replans":0,"navigation":"IDLE"}
	a.cognitive_traits={"fear":float(a.get("panic_level",50)),"courage":float(a.get("courage",50)),"aggression":80.0 if a.get("primary_personality","")=="AGGRESSIVE" else 25.0,"altruism":float(a.get("empathy",50)),"risk_tolerance":float(a.get("risk_tolerance",50)),"curiosity":float(a.get("adaptability",50)),"sociability":float(a.get("sociability",50)),"trust":float(a.get("authority_trust",50)),"self_preservation":float(a.get("self_preservation",50)),"family_attachment":90.0 if a.get("primary_personality","")=="FAMILY-ORIENTED" else 65.0 if not a.get("relationships",{}).is_empty() else 30.0}
	a.cognition.help_radius=float(sim.manager.living.help_radius)
	a.cognition.communication_radius=float(sim.manager.living.communication_radius)
	a.cognition.next_observe=(int(a.get("population_index",0))%100)/100.0*float(config.perception_interval)
	a.cognition.next_decide=(int(a.get("population_index",0))%100)/100.0*float(config.decision_interval)

func tick(_seconds: float) -> void:
	if not config.enabled or sim==null or sim.replaying: return
	var now: float=sim.manager.elapsed_seconds
	for a in sim.manager.agents:
		ensure(a)
		if a.health<=0 or a.state in ["SHELTERED","SAFE","EXPOSED"]: continue
		var c: Dictionary=a.cognition
		c.now=now
		a.cognitive_traits.fear=float(a.panic_level)
		if now>=c.next_observe:
			c.next_observe=now+float(config.perception_interval)
			c.observations=Perception.observe(sim,a,config)
			var signature := ""
			for item in c.observations:
				if item.severity>=.4: signature+=str(item.kind)+":"+str(item.id)+";"
			if signature!=c.get("observation_signature",""):
				c.observation_signature=signature; c.next_decide=now; c.erase("context_signature")
			_remember(a,now)
		var threat := immediate_threat(a)
		if not threat.is_empty() and a.get("indoor_id","")!="" and not a.get("emergency_evacuating",false):
			a["emergency_evacuating"]=true; a.alarm_confidence=maxf(a.alarm_confidence,.9); a.social_target=""
			_request_indoor_exit(a)
		c.threats=c.observations.filter(func(item):return item.kind in ["accident","roadblock","fire","smoke","explosion","obstacle"])
		if not threat.is_empty() and threat not in c.threats: c.threats.append(threat)
		if not threat.is_empty() and a.get("riding","")=="" and a.get("indoor_id","")=="":
			if c.layer!="REFLEX" or now>=c.until: _escape(a,threat,now)
			continue
		_driver_recovery(a,now)
		if a.get("police_unit_busy",false): continue
		if now<c.until or now<c.next_decide: continue
		c.next_decide=now+float(config.decision_interval)
		if sim.manager.phase=="LIVING" and c.action in ["FLEE","DETOUR","SUPPORT"]:
			a.state="ROUTINE"
		if c.action in ["FLEE","DETOUR"]:
			c.route=PackedVector2Array()
			if sim.manager.phase in ["EVACUATION","BOMB_FALL"]: sim.manager.choose_rule_destination(a)
		var choice := evaluate(a)
		if not a.get("responding_to","").is_empty() or (a.get("role","")=="Authority" and not sim.authorities.assignment_for(a.id).is_empty()):
			if choice.action in ["FOLLOW_POLICE","JOIN_GROUP","RETURN_HOME","DETOUR"]:
				choice.action="CONTINUE"; choice.reason="Continue assigned duty; immediate reflex remains available"
		c.scores=choice.scores
		_record(a,choice.action,"UTILITY",choice.reason,now)
		_apply(a,choice,now)
		# Complex conflict context uses the established bridge, run IDs, validators and cache.
		var complex_context: bool=choice.action in ["WARN_FAMILY","HELP","ASK_HELP","DETOUR"] and c.observations.size()>2
		var signature := str(choice.action)+":"+str(choice.target)
		if now>=c.next_context and complex_context and signature!=c.get("context_signature",""):
			c.next_context=now+float(config.context_interval)
			if sim.manager.phase in ["EVACUATION","BOMB_FALL"] and sim.manager.ai_config.enabled and a.get("configured_provider","")=="LOCAL_LLM":
				if sim.manager.ai_bridge.request_decision(a): c.context_signature=signature

func _remember(a: Dictionary, now: float) -> void:
	var c: Dictionary=a.cognition
	c.memory=c.memory.filter(func(m):return now-float(m.timestamp)<float(config.memory_seconds))
	for item in c.observations:
		var found := -1
		for i in range(c.memory.size()):
			if c.memory[i].id==item.id and c.memory[i].kind==item.kind: found=i; break
		if found>=0: c.memory.remove_at(found)
		c.memory.append(item.duplicate(true))
		if item.kind in ["fire","smoke","explosion","accident","roadblock","danger_zone","increasing_threat"]:
			var hazard := {"position":item.position,"until":now+float(config.memory_seconds)}
			var found_hazard := false
			for existing in a.avoided_locations:
				if existing.position.distance_to(item.position)<10: existing.until=hazard.until; found_hazard=true; break
			if not found_hazard: a.avoided_locations.append(hazard)
	while c.memory.size()>int(config.memory_limit): c.memory.pop_front()

func immediate_threat(a: Dictionary) -> Dictionary:
	for item in a.cognition.observations:
		if item.kind in ["fire","explosion","danger_zone","increasing_threat"] and item.severity>.35 and a.position.distance_to(item.position)<maxf(float(config.reflex_radius),float(item.get("radius",0))): return item
		if item.kind in ["vehicle","emergency_vehicle"] and item.speed>5 and a.get("riding","")=="":
			var forward := Vector2.from_angle(float(item.heading))
			var delta: Vector2=a.position-item.position
			if delta.dot(forward)>0 and delta.dot(forward)<item.speed*1.5+item.length*.5 and absf(delta.dot(forward.orthogonal()))<item.width*.5+10: return item
	return {}

static func evaluate(a: Dictionary) -> Dictionary:
	var t: Dictionary=a.cognitive_traits
	var scores := {"CONTINUE":35.0}
	var targets := {}
	var evidence: Array=a.cognition.observations.duplicate()
	for memory in a.cognition.memory:
		if float(a.cognition.get("now",0))-float(memory.timestamp)>120: continue
		if memory.kind in ["fire","accident","roadblock","route_failure"] and not evidence.any(func(item):return item.id==memory.id and item.kind==memory.kind):
			if a.position.distance_to(memory.position)<100: evidence.append(memory)
	for item in evidence:
		if item.kind=="injured":
			if item.distance>float(a.cognition.help_radius): continue
			if float(a.cognition.get("helped",{}).get(item.id,-100))>float(a.cognition.get("now",0))-30: continue
			var utility: float=float(t.altruism)*.8+float(t.courage)*.2-float(t.fear)*.3-float(t.self_preservation)*.1-float(item.distance)*.03
			if utility>float(scores.get("HELP",-INF)):
				scores["HELP"]=utility; targets["HELP"]=item.id
		if item.kind in ["fire","smoke","explosion","accident","roadblock","obstacle","road","route_failure","danger_zone","increasing_threat"]:
			if a.position.distance_to(item.position)>120: continue
			var utility: float=30+float(item.severity)*40+(100-float(t.risk_tolerance))*.2+float(t.fear)*.15-float(t.courage)*.1-float(t.aggression)*.08
			if utility>float(scores.get("DETOUR",-INF)):
				scores["DETOUR"]=utility; targets["DETOUR"]=item.position
			scores["WARN_FAMILY"]=float(t.family_attachment)*.65+float(t.sociability)*.15
			if a.relationships.is_empty(): scores.erase("WARN_FAMILY")
		if item.kind=="police":
			if item.distance>float(a.cognition.communication_radius): continue
			scores["FOLLOW_POLICE"]=float(t.trust)*.55+float(t.fear)*.2-float(t.aggression)*.2
			targets["FOLLOW_POLICE"]=item.id
		if item.kind=="person" and not a.get("objective","").is_empty():
			if item.distance>float(a.cognition.communication_radius): continue
			scores["JOIN_GROUP"]=float(t.sociability)*.4+float(t.trust)*.2
			targets["JOIN_GROUP"]=item.id
	if a.health<45: scores["ASK_HELP"]=80.0
	if a.get("age",30)>=18 and a.get("alarm_confidence",0)>.5 and a.get("objective","").is_empty(): scores["FIND_SHELTER"]=60.0+float(t.self_preservation)*.2
	if a.get("fatigue",0)>85 and a.get("alarm_confidence",0)==0: scores["RETURN_HOME"]=65.0
	if float(a.get("hunger",0))>65: scores["SEARCH_RESOURCES"]=70.0
	if not a.cognition.observations.is_empty(): scores["OBSERVE"]=float(t.curiosity)*.4-float(t.fear)*.1
	# Prior choices suppress repeated broadcasts and curiosity pauses.
	for previous in a.cognition.history:
		if previous.action in ["WARN_FAMILY","OBSERVE"] and float(a.cognition.get("now",0))-float(previous.timestamp)<20:
			scores[previous.action]=0.0
	var best := "CONTINUE"
	for action in scores:
		if float(scores[action])>float(scores[best]): best=action
	return {"action":best,"target":targets.get(best,""),"scores":scores,"reason":"Highest private utility: "+best}

func _record(a: Dictionary, action: String, layer: String, reason: String, now: float) -> void:
	if layer!="LLM": a["rule_decision_count"]=int(a.get("rule_decision_count",0))+1
	var c: Dictionary=a.cognition
	c.action=action; c.layer=layer; c.reason=reason
	c.history.append({"timestamp":now,"action":action,"layer":layer,"reason":reason})
	while c.history.size()>32: c.history.pop_front()

func _escape(a: Dictionary, threat: Dictionary, now: float) -> void:
	var direction: Vector2=(a.position-threat.position).normalized()
	var distance: float=maxf(90,float(threat.get("radius",0))*1.5+30)
	if not Map.clear_point(a.position,0):
		var cell: Vector2i=Map._free_cell(a.position)
		if cell.x>=0:
			var safe_point: Vector2=Map.free_grid.get_point_position(cell)
			direction=(safe_point-a.position).normalized(); distance=maxf(distance,a.position.distance_to(safe_point)+30)
	if threat.kind in ["vehicle","emergency_vehicle"]: direction=Vector2.from_angle(float(threat.heading)).orthogonal()*(-1 if int(a.get("population_index",0))%2 else 1)
	if direction.is_zero_approx(): direction=Vector2.RIGHT
	_plan_away(a,threat.position,direction,"FLEE",now,distance)

func _request_indoor_exit(a: Dictionary) -> void:
	if sim.manager.emergency.owner!=null: sim.manager.emergency.reconsider(a,"Danger sensed indoors; use physical exit")

func _plan_away(a: Dictionary, hazard: Vector2, direction: Vector2, action: String, now: float, distance: float = 90.0) -> void:
	var c: Dictionary=a.cognition
	for turn in [0.0,.7,-.7,1.4,-1.4]:
		var point: Vector2=a.position+direction.rotated(turn)*distance
		var route := Routes.plan(a.position,point)
		if route.size()<2 or route[-1].distance_to(hazard)<a.position.distance_to(hazard)+15: continue
		var safe := true
		for i in range(1,route.size()):
			if Geometry2D.get_closest_point_to_segment(hazard,route[i-1],route[i]).distance_to(hazard)<minf(25,a.position.distance_to(hazard)-1): safe=false
		if not safe: continue
		c.route=route; c.index=1; c.until=now+4; c.navigation="ESCAPE_ROUTE"
		_record(a,action,"REFLEX" if action=="FLEE" else "UTILITY","Move clear of observed danger",now)
		return
	c.route=PackedVector2Array(); c.until=now+.5; c.navigation="NO_SAFE_ROUTE"
	_experience(a,"route_failure",hazard,now)
	_record(a,"OBSERVE","REFLEX","No safe escape; stop and reassess",now)

func _apply(a: Dictionary, choice: Dictionary, now: float) -> void:
	if a.get("evacuation_group","")!="": return # Consent and group pacing own routine movement; reflexes above remain active.
	var c: Dictionary=a.cognition
	if a.get("riding","")!="": return
	if choice.action=="DETOUR" and a.get("indoor_id","")=="" and a.get("responding_to","")=="":
		_plan_away(a,choice.target,(a.position-choice.target).normalized(),"DETOUR",now)
	elif choice.action in ["HELP","FOLLOW_POLICE","JOIN_GROUP","ASK_HELP","WARN_FAMILY"]:
		var action: String={"HELP":"HELP_AGENT","FOLLOW_POLICE":"FOLLOW_AGENT","JOIN_GROUP":"FOLLOW_AGENT","ASK_HELP":"COMMUNICATE","WARN_FAMILY":"COMMUNICATE"}[choice.action]
		var target: String=str(choice.target)
		var message := "I need assistance" if choice.action=="ASK_HELP" else "Danger observed nearby; seek verified safety"
		if choice.action=="WARN_FAMILY":
			for id in a.relationships: sim.send_phone(a,id,{"subject":"local_danger","value":message,"position":a.position})
		elif choice.action=="HELP":
			var other: Dictionary=sim.by_id.get(target,{})
			if not other.is_empty() and sim.manager.can_observe(a,other) and other.health>0 and a.position.distance_to(other.position)<=float(c.help_radius):
				other.panic_level=maxf(0,other.panic_level-float(sim.manager.living.help_panic_reduction))
				if not c.has("helped"): c.helped={}
				c.helped[target]=now; c.until=now+float(sim.manager.living.help_seconds)
				c.action="SUPPORT"; a.current_goal="Support injured person "+target
				a.state="HELPING"; a.wait_until=c.until
				# First aid is performed only by existing dispatched medical/fire responders.
				sim.emit_event("agent.supported",a.id,{"recipient":target,"kind":"emotional_support"})
		elif choice.action=="FOLLOW_POLICE" and sim.by_id.get(target,{}).get("police_unit_busy",false):
			sim.manager.emergency.reconsider(a,"Observe police traffic instructions and avoid restricted road")
		elif sim.manager.phase in ["EVACUATION","BOMB_FALL"]:
			Actions.apply(sim.manager,a,{"action":action,"target":target,"message":message,"reason":choice.reason,"confidence":.8},"LOCAL_UTILITY")
	elif choice.action=="OBSERVE": c.until=now+1
	elif choice.action=="RETURN_HOME" and sim.manager.phase=="LIVING": sim.daily.schedule(a,"HOME",a.home_building)
	elif choice.action=="SEARCH_RESOURCES":
		if sim.manager.phase=="LIVING": sim.daily.schedule(a,"SHOP",a.shop_building)
		else: sim.manager.choose_rule_destination(a)
	elif choice.action=="FIND_SHELTER" and sim.manager.phase in ["EVACUATION","BOMB_FALL"]: sim.manager.choose_rule_destination(a)

func move(a: Dictionary, seconds: float) -> bool:
	if not config.enabled or not a.has("cognition") or a.get("riding","")!="" or a.get("indoor_id","")!="": return false
	var c: Dictionary=a.cognition
	if sim.manager.elapsed_seconds>=c.until: return false
	if c.action in ["OBSERVE","SUPPORT"]: return true
	if c.action not in ["FLEE","DETOUR"]: return false
	if c.index<c.route.size() and not Map.clear_segment(a.position,c.route[c.index]):
		_experience(a,"route_failure",c.route[c.index],sim.manager.elapsed_seconds)
		c.navigation="ROUTE_INVALIDATED"; c.until=sim.manager.elapsed_seconds
		c.next_observe=sim.manager.elapsed_seconds; c.next_decide=sim.manager.elapsed_seconds
		return true
	var speed: float=a.run_speed if c.action=="FLEE" else a.walk_speed
	var proxy := {"position":a.position,"route":c.route,"route_index":c.index,"movement_speed":speed}
	a.previous_position=a.position
	var result := Routes.move(proxy,seconds)
	a.position=proxy.position; c.index=proxy.route_index
	a.state="SCRAMBLING" if c.action=="FLEE" else "MOVING"
	a.current_goal=c.reason
	if result.arrived:
		c.until=sim.manager.elapsed_seconds; c.navigation="REACHED"
		_experience(a,"route_success",a.position,sim.manager.elapsed_seconds)
	return true

func _experience(a: Dictionary, kind: String, point: Vector2, now: float) -> void:
	if kind=="route_success":
		a.cognition.memory=a.cognition.memory.filter(func(m):return m.kind!="route_failure" or m.position.distance_to(point)>35)
	var item := Perception.entry(kind,"route:%d:%d"%[int(point.x/20),int(point.y/20)],point,a,now,.6 if kind=="route_failure" else 0)
	a.cognition.memory.append(item)
	while a.cognition.memory.size()>int(config.memory_limit): a.cognition.memory.pop_front()

func _driver_recovery(a: Dictionary, now: float) -> void:
	if a.get("police_unit_busy",false): return
	var riding: String=a.get("riding","")
	if riding.is_empty(): return
	for v in sim.vehicles:
		if v.id!=riding or v.driver!=a.id: continue
		var c: Dictionary=a.cognition
		var since_last: float=maxf(0,now-float(c.get("driver_last_time",now)))
		c.driver_last_time=now
		if c.get("vehicle_id","")!=v.id or (a.position-c.progress_position).dot(Vector2.from_angle(float(v.heading)))>10 or v.speed>2 or v.status=="PARKED":
			c.vehicle_id=v.id; c.progress_position=a.position; c.progress_time=now; c.replans=0; return
		if v.get("traffic_light","")=="RED":
			c.progress_time+=since_last
			return
		var hazard: bool=v.status in ["BLOCKED","CONGESTED"] and v.route.is_empty()
		for item in c.observations:
			if item.kind in ["accident","roadblock"] and (item.position-v.position).dot(Vector2.from_angle(float(v.heading)))>=-float(v.length): hazard=true
			if item.kind in ["vehicle","emergency_vehicle"] and float(item.get("speed",0))<2 and item.distance<140 and (item.position-v.position).dot(Vector2.from_angle(float(v.heading)))>0: hazard=true
		if not hazard: c.progress_time=now; return
		var waited: float=now-float(c.progress_time)
		if waited>=float(config.stuck_seconds) and c.replans==0:
			c.replans=1
			var destination: Vector2=v.route[-1] if not v.route.is_empty() else a.position
			var target: String=a.social_target if not a.social_target.is_empty() else a.objective
			if v.route.is_empty() and a.known_locations.has(target): destination=a.known_locations[target].position
			elif v.route.is_empty() and a.beliefs.has(target): destination=a.beliefs[target].position
			var path: PackedVector2Array=sim._vehicle_route(v.position,destination,v.kind!="Civilian",v.height,a.get("known_traffic",{}))
			if path.size()>1 and (path[1]-v.position).normalized().dot(Vector2.from_angle(float(v.heading)))>-.2:
				v.route=path; v.route_index=1
			elif sim.driving.begin_reverse(v): c.navigation="REVERSING"
			_record(a,"REROUTE","UTILITY","Observed obstruction prevents progress",now)
		if waited>=float(config.abandon_seconds) and v.speed<=1 and float(v.height)<3 and a.get("responding_to","")=="":
			if sim.driving.safe_disembark(v,a):
				_record(a,"ABANDON_VEHICLE","UTILITY","Reached safe right-side footway after bounded recovery",now)
				if sim.manager.phase in ["EVACUATION","BOMB_FALL"]: sim.manager.choose_rule_destination(a)
			elif v.get("recovery_mode","")!="PULLING_OVER" and now>=float(c.get("next_assistance",0)):
				c.next_assistance=now+15; c.replans=0
				_record(a,"ASK_HELP","UTILITY","No safe parking or exit; request assistance and reassess",now)
				sim.emit_event("vehicle.assistance_requested",a.id,{"vehicle":v.id,"position":v.position,"reason":"no safe recovery space"})
		return
