extends RefCounted
## Event lifecycle and shelter operations. Occupancy changes only at physical thresholds.
const Map=preload("res://scripts/city_map.gd")
const State=preload("res://scripts/shelter_state.gd")
const Admission=preload("res://scripts/shelter_admission.gd")
const Beliefs=preload("res://scripts/agent_beliefs.gd")
const Perception=preload("res://scripts/agent_perception.gd")
const Routes=preload("res://scripts/road_routes.gd")
const TYPES=["explosion","fire","accident","road_closure","danger_zone","infrastructure_failure","increasing_threat","shelter_closure","shelter_unsafe","evacuation_order","POLICE_SHELTER_EVACUATION"]
var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/emergency_management.json"))
var owner: WeakRef
var manager: Node:
	get: return owner.get_ref() if owner!=null else null
var signatures: Dictionary={}
var history: Array=[]
var rng:=RandomNumberGenerator.new()
var sequence:=0
var last_revision:=-1
var accident_events: Dictionary={}

func initialize(value: Node) -> void:
	owner=weakref(value); sequence=0; signatures.clear(); history.clear()
	accident_events.clear()
	rng.seed=manager.seed_for("events")+78131
	last_revision=Map.navigation_revision
	for shelter in manager.shelters:
		State.refresh(shelter,manager.environment_events)
		signatures[shelter.id]=_signature(shelter)

func add_event(kind: String, point: Vector2, options: Dictionary = {}) -> String:
	if kind=="police_shelter_evacuation": kind="POLICE_SHELTER_EVACUATION"
	if kind=="POLICE_SHELTER_EVACUATION" and (manager==null or manager.social==null or manager.phase not in ["PREPARATION","LIVING","EVACUATION","BOMB_FALL"]): return ""
	if manager==null or kind not in TYPES or not point.is_finite() or not Rect2(Vector2.ZERO,Map.MAP_SIZE).has_point(point): return ""
	if manager.environment_events.filter(func(e):return e.get("dynamic",false) and not e.ended).size()>=int(config.max_dynamic_events): return ""
	var target: String=str(options.get("shelter_id",""))
	if not target.is_empty() and not manager.shelter_by_id.has(target): return ""
	var severity: float=float(options.get("severity",.7))
	var duration: float=float(options.get("duration",60.0))
	var radius: float=float(options.get("radius",config.default_event_radius))
	var growth: float=float(options.get("growth_per_second",0.0))
	if not is_finite(severity) or not is_finite(duration) or not is_finite(radius) or not is_finite(growth) or duration<=0 or radius<=0 or radius>Map.MAP_SIZE.length() or severity<0 or severity>1 or growth<0: return ""
	if kind=="accident" and not options.get("vehicle_id","") in _vehicle_ids(): return ""
	if kind=="accident":
		var vehicle_id: String=str(options.vehicle_id)
		if accident_events.has(vehicle_id): return accident_events[vehicle_id]
		for vehicle in manager.social.vehicles:
			if vehicle.id==vehicle_id: point=vehicle.position; break
	sequence+=1
	var id: String="DYN%04d"%sequence
	manager.environment_events.append({"event_id":id,"event_type":kind,"target_id":target,"target_location":point,"scheduled_time":0.0,"start_at":manager.elapsed_seconds,"duration":duration,"radius":radius,"severity":severity,"initial_severity":severity,"growth_per_second":growth,"dynamic":true,"active_status":false,"started":false,"ended":false,"visibility_to_agents":[],"event_log_message":kind+" at "+str(point),"actual_effect":"dynamic emergency","block_ids":[],"vehicle_id":str(options.get("vehicle_id","")),"apply_vehicle_impact":bool(options.get("apply_vehicle_impact",kind=="accident"))})
	if kind=="accident": accident_events[str(options.vehicle_id)]=id
	return id

func _vehicle_ids() -> Array:
	return [] if manager.social==null else manager.social.vehicles.map(func(v):return v.id)

func clear_event(id: String) -> bool:
	for event in manager.environment_events:
		if event.event_id==id and event.get("dynamic",false) and not event.ended:
			event.ended=true; event.active_status=false
			_remove_closures(event); _emit("emergency.cleared",event)
			refresh_shelters()
			return true
	return false

func set_shelter_condition(id: String, safety: String, accessible: bool = true) -> bool:
	if not manager.shelter_by_id.has(id) or safety not in ["SAFE","WARNING","UNSAFE"]: return false
	var shelter: Dictionary=manager.shelter_by_id[id]
	shelter.manual_safety_status=safety; shelter.manual_accessible=accessible
	refresh_shelters()
	return true

func set_admissions(id: String, open: bool) -> bool:
	if not manager.shelter_by_id.has(id): return false
	var s: Dictionary=manager.shelter_by_id[id]
	if open and (not s.exists or not s.operational or s.safety_status in ["UNSAFE","DESTROYED"] or not s.manual_accessible): return false
	if not State.set_door_state(s,"OPEN" if open else "CLOSED"): return false
	s.accepting=open
	refresh_shelters()
	return true

func open_exit(id: String) -> bool:
	if not manager.shelter_by_id.has(id): return false
	var s: Dictionary=manager.shelter_by_id[id]
	if not s.exists or not s.manual_accessible or s.get("structural_state","INTACT")!="INTACT": return false
	var opened: bool=State.set_door_state(s,"OPEN")
	refresh_shelters()
	return opened

func tick(seconds: float) -> void:
	if manager==null or (manager.social!=null and manager.social.replaying): return
	for event in manager.environment_events.duplicate():
		if event.get("scope","")=="shelter": continue
		if event.get("dynamic",false):
			if event.ended: continue
			if not event.started:
				event.started=true; event.active_status=true
				_install_closures(event); _dispatch(event); _affect(event,0,true); _emit("emergency.started",event)
			var age: float=manager.elapsed_seconds-float(event.start_at)
			event.severity=clampf(float(event.initial_severity)+age*float(event.growth_per_second),0,1)
			if age>=float(event.duration): clear_event(event.event_id); continue
			if event.event_type=="fire":
				event["damage_elapsed"]=float(event.get("damage_elapsed",0))+seconds
				if float(event.damage_elapsed)>=1.0: _affect(event,float(event.damage_elapsed),false); event.damage_elapsed=0.0
		elif event.active_status and event.event_type=="road" and not event.get("route_integrated",false):
			_install_closures(event); event.route_integrated=true
		elif not event.active_status and event.get("route_integrated",false):
			_remove_closures(event); event.route_integrated=false
	refresh_shelters()
	if Map.navigation_revision!=last_revision:
		last_revision=Map.navigation_revision
		for a in manager.agents:
			if a.state not in ["SHELTERED","SAFE","EXPOSED"]:
				reconsider(a,"Navigation changed")
		if manager.social!=null:
			for vehicle in manager.social.vehicles: vehicle.next_route=manager.elapsed_seconds
	_egress(seconds)
	_move_ordered_evacuees(seconds)

func record_accident(vehicle: String, payload: Dictionary) -> void:
	if accident_events.has(vehicle): return
	var id:=add_event("accident",payload.get("position",Vector2.ZERO),{"vehicle_id":vehicle,"apply_vehicle_impact":false,"duration":3600.0})
	if not id.is_empty(): accident_events[vehicle]=id

func record_recovery(vehicle: String) -> void:
	if accident_events.has(vehicle): clear_event(accident_events[vehicle]); accident_events.erase(vehicle)

func _emit(kind: String, event: Dictionary) -> void:
	if manager.social!=null: manager.social.emit_event(kind,event.event_id,{"kind":event.event_type,"position":event.target_location,"severity":event.severity,"shelter":event.target_id})
	manager.log_event("EMERGENCY",event.event_id+" / "+event.event_type+" / "+kind,"director")
	if manager.social!=null: manager.social.authorities.next_tick=manager.elapsed_seconds

func _dispatch(event: Dictionary) -> void:
	if event.event_type=="POLICE_SHELTER_EVACUATION":
		if manager.social!=null: manager.social.evacuation.start(event)
		return
	if event.event_type not in ["fire","explosion","accident","road_closure","danger_zone","infrastructure_failure","increasing_threat"]: return
	for a in manager.agents:
		if a.role!="Authority" or a.health<=0: continue
		a.known_locations["emergency:"+event.event_id]={"position":event.target_location,"confidence":.95,"source":"emergency dispatch","timestamp":manager.elapsed_seconds,"danger_radius":event.radius,"uncertainty_radius":0.0}

func _install_closures(event: Dictionary) -> void:
	if manager.social==null or event.event_type not in ["road","road_closure","fire","explosion","danger_zone","increasing_threat","infrastructure_failure"]: return
	if event.event_type=="infrastructure_failure" and event.target_id!="": return
	event["block_ids"]=[]
	var radius: float=float(event.get("radius",config.default_event_radius))
	var zone_id: String="EMZONE:"+event.event_id
	Map.set_closure(zone_id,event.target_location,true,radius)
	event.block_ids.append(zone_id)
	for index in range(Map.roads.size()):
		var edge: Dictionary=Map.roads[index]
		var nearest:=INF
		var road_point: Vector2=event.target_location
		for i in range(1,edge.points.size()):
			var projected: Vector2=Geometry2D.get_closest_point_to_segment(event.target_location,edge.points[i-1],edge.points[i])
			var distance: float=projected.distance_to(event.target_location)
			if distance<nearest: nearest=distance; road_point=projected
		if nearest>radius+float(edge.width)*.5 or edge.get("elevated",false): continue
		var id: String="EM:"+event.event_id+":"+str(index)
		var block: Dictionary={"id":id,"edge":index,"position":road_point,"height":0.0,"kind":"damaged_road","issuer":"EMERGENCY_SYSTEM","active":true,"expires":INF,"managed_by_policy":false,"rationale":event.event_type,"source_event":event.event_id}
		manager.social.blocks.append(block); Map.roadblock_data[id]=block
		Map.graph.disconnect_points(edge.from,edge.to)
		Map.set_closure(id,road_point,true)
		event.block_ids.append(id)

func _remove_closures(event: Dictionary) -> void:
	for id in event.get("block_ids",[]):
		if str(id).begins_with("EMZONE:"): Map.set_closure(id,event.target_location,false)
		elif manager.social!=null: manager.social.remove_block(id)
	event["block_ids"]=[]

func _affect(event: Dictionary, seconds: float, initial: bool) -> void:
	if event.event_type=="POLICE_SHELTER_EVACUATION": return # Instructions require real officer contact.
	var radius: float=float(event.radius)
	for a in manager.agents:
		if a.health<=0 or a.state in ["SAFE","EXPOSED"] or a.position.distance_to(event.target_location)>radius: continue
		if initial and Perception.visible(a,event.target_location,radius):
			a.panic_level=minf(100,a.panic_level+float(event.severity)*30)
			Beliefs.remember(a,manager.elapsed_seconds,"Observed "+event.event_type,manager.living)
			if a.has("cognition"): a.cognition.next_observe=manager.elapsed_seconds; a.cognition.next_decide=manager.elapsed_seconds
		if initial and event.event_type=="evacuation_order":
			a.alarm_confidence=maxf(a.alarm_confidence,.9)
			a["emergency_evacuating"]=true; a.social_target=""
			if a.state=="SHELTERED": a["evacuating_shelter"]=a.shelter_id
			elif a.get("riding","")=="": a.group_on_foot=true
			Beliefs.remember(a,manager.elapsed_seconds,"Local civil-defense evacuation order received",manager.living)
			reconsider(a,"Local evacuation order")
			continue
		if a.state=="SHELTERED" and event.target_id!=a.shelter_id: continue
		var damage: float=float(config.explosion_damage)*float(event.severity)*(1-a.position.distance_to(event.target_location)/radius) if initial and event.event_type=="explosion" else float(config.fire_damage_per_second)*float(event.severity)*seconds if event.event_type=="fire" else 0.0
		if damage>0 and manager.social!=null: manager.social.traffic.injure(manager.social,a,damage)
	if initial and manager.social!=null:
		for v in manager.social.vehicles.duplicate():
			if event.event_type=="accident" and event.apply_vehicle_impact and v.id==event.vehicle_id:
				manager.social.traffic.impact(manager.social,v,{},maxf(1,float(event.severity)*5),"emergency_event")
			elif event.event_type=="explosion" and v.position.distance_to(event.target_location)<radius and v.status not in ["ACCIDENT","REMOVED","DESTROYED"]:
				manager.social.traffic.impact(manager.social,v,{},maxf(1,float(event.severity)*3),"explosion")

func _signature(s: Dictionary) -> String:
	return str([s.get("safety_status","SAFE"),s.operational,s.get("accessible",true),s.get("admission_open",true),s.get("available_capacity",0)==0,s.door_status])

func refresh_shelters() -> void:
	for s in manager.shelters:
		var effects: Array=manager.environment_events.duplicate()
		for event in manager.environment_events:
			if event.active_status and event.target_id=="" and event.event_type in ["fire","explosion","danger_zone","infrastructure_failure","increasing_threat"] and s.position.distance_to(event.target_location)<=float(event.get("radius",config.default_event_radius)):
				var local_event: Dictionary=event.duplicate(); local_event.target_id=s.id; effects.append(local_event)
		State.refresh(s,effects)
		if manager.social!=null and manager.social.shelter_life.shelters.has(s.id):
			var refuge: Dictionary=manager.social.shelter_life.shelters[s.id]
			refuge.emergency=s.safety_status in ["UNSAFE","DESTROYED"] or not s.operational
			refuge.fire=effects.any(func(e):return e.active_status and e.target_id==s.id and e.event_type=="fire")
			if not manager.social.shelter_life.storyteller.config.is_empty(): manager.social.shelter_life.storyteller.project(s.id)
		var signature:=_signature(s)
		if signatures.get(s.id,"")==signature: continue
		signatures[s.id]=signature
		_publish_status(s)

func _publish_status(s: Dictionary) -> void:
	var status: Dictionary={"shelter_id":s.id,"timestamp":manager.elapsed_seconds,"available":s.admission_open,"safety":s.safety_status,"accessible":s.accessible}
	history.append(status)
	while history.size()>int(config.status_history_limit): history.pop_front()
	if manager.social!=null: manager.social.emit_event("shelter.status_changed",s.id,status)
	for a in manager.agents:
		if a.health<=0: continue
		var local: bool=a.shelter_id==s.id or Perception.visible(a,s.position,float(manager.living.observation_radius))
		var known_public: bool=s.id!="S5" or float(a.beliefs[s.id].get("existence_probability",0))>=1.0
		var radio: bool=a.role=="Authority" and known_public
		var phone: bool=manager.social!=null and known_public and manager.social.connected(a) and rng.randf()<float(config.status_message_reach)
		if not local and not radio and not phone: continue
		var b: Dictionary=a.beliefs[s.id]
		if local and a.position.distance_to(s.position)<=float(manager.living.observation_radius): Beliefs.observe(a,s,manager.elapsed_seconds,manager.living)
		else:
			b.unavailable=not s.admission_open; b["accessible"]=s.accessible; b["safety_status"]=s.safety_status
			b.last_update_time=manager.elapsed_seconds; b.source="Civil defense shelter-status message"; b.evidence_type="official_status"; b.confidence=.9
			b.risk=1.0 if s.safety_status in ["UNSAFE","DESTROYED"] else maxf(.65,float(s.known_risk)) if s.safety_status=="WARNING" else float(s.known_risk)
			if s.available_capacity==0: b.estimated_occupancy=b.capacity
			elif int(b.estimated_occupancy)>=int(b.capacity): b.estimated_occupancy=maxi(0,int(b.capacity)-1)
		if radio:
			if not a.has("authority_reports"): a.authority_reports=[]
			a.authority_reports.append({"subject":"shelter_status","value":status.duplicate(),"source":"SHELTER_CONTROL","timestamp":manager.elapsed_seconds})
			while a.authority_reports.size()>40: a.authority_reports.pop_front()
		Beliefs.remember(a,manager.elapsed_seconds,"Shelter status "+s.id+": "+str(status),manager.living)
		if a.objective==s.id and not s.admission_open: reconsider(a,"Destination shelter unavailable")
		elif s.admission_open and a.state in ["REJECTED","DECIDING","CHANGING_DESTINATION"]: reconsider(a,"Shelter availability restored")
		if a.shelter_id==s.id and s.safety_status in ["UNSAFE","DESTROYED"]:
			a["evacuating_shelter"]=s.id
			if manager.social!=null and a.get("shelter_life_active",false): manager.social.shelter_life.shelters.get(s.id,{})["emergency"]=true
	if manager.social!=null: manager.social.authorities.next_tick=manager.elapsed_seconds

func reconsider(a: Dictionary, reason: String) -> void:
	a["force_route_replan"]=true; a.next_rule_decision=manager.elapsed_seconds
	if a.has("cognition"): a.cognition.next_decide=manager.elapsed_seconds; a.cognition.next_observe=manager.elapsed_seconds
	if (manager.phase in ["EVACUATION","BOMB_FALL"] or (manager.phase in ["LIVING","IMPACT"] and a.get("emergency_evacuating",false))) and a.state not in ["SHELTERED","SAFE","EXPOSED"] and a.get("age",30)>=18:
		manager.choose_rule_destination(a)
		a["replan_reason"]=reason

func _egress(seconds: float) -> void:
	if manager.phase not in ["LIVING","EVACUATION","BOMB_FALL","IMPACT"]: return
	for a in manager.agents:
		var id: String=a.get("evacuating_shelter","")
		if id.is_empty() or a.health<=0 or not manager.shelter_by_id.has(id): continue
		var s: Dictionary=manager.shelter_by_id[id]
		if manager.phase=="IMPACT": a["evacuation_requires_verified"]=true
		if not a.has("evacuation_excluded_shelters"): a.evacuation_excluded_shelters=[]
		if id not in a.evacuation_excluded_shelters: a.evacuation_excluded_shelters.append(id)
		if manager.phase=="IMPACT" and a.get("shelter_life_active",false):
			var plan: Dictionary=a.duplicate(true)
			plan.position=s.exit_position; plan.indoor_id=""; plan.force_route_replan=true
			var alternative: Dictionary=preload("res://scripts/evacuation_decisions.gd").evaluate(plan,1800,manager.settings.evacuation.weights)
			if alternative.shelter_id.is_empty(): a.current_goal="Await verified alternative before leaving "+id; continue
			a["planned_transfer_shelter"]=alternative.shelter_id
		if s.door_status!="OPEN": a.current_goal="Await accessible exit from "+id; continue
		if manager.phase=="IMPACT" and a.get("shelter_life_active",false):
			a["egress_moved_at"]=manager.elapsed_seconds
			if not manager.social.shelter_life.advance_emergency_exit(a,seconds): continue
		var exit: Vector2=s.exit_position
		if a.position.distance_to(exit)>.01:
			a["egress_moved_at"]=manager.elapsed_seconds
			var path:=Routes.plan(a.position,exit)
			var proxy: Dictionary={"position":a.position,"route":path,"route_index":1,"movement_speed":float(a.walk_speed)}
			a.previous_position=a.position; Routes.move(proxy,seconds); a.position=proxy.position
		if Admission.try_exit(a,s):
			a.erase("evacuating_shelter"); a.group_on_foot=true
			a["emergency_evacuating"]=true
			manager._set_state(a,"DECIDING"); reconsider(a,"Unsafe shelter evacuation")
			if manager.social!=null: manager.social.emit_event("shelter.departed",a.id,{"shelter":id,"position":a.position})
	refresh_shelters()

func _move_ordered_evacuees(seconds: float) -> void:
	if manager.phase not in ["LIVING","IMPACT"]: return
	var arrivals: Array=[]
	for a in manager.agents:
		if not a.get("emergency_evacuating",false) or a.health<=0 or a.state in ["SHELTERED","EXPOSED","SAFE"]: continue
		if is_equal_approx(float(a.get("egress_moved_at",-1)),manager.elapsed_seconds): continue
		if manager.social!=null:
			if a.get("riding","")!="": continue
			if a.get("indoor_id","")!="": manager.social.daily.interiors.exit_building(a,seconds); continue
			if manager.social.move_social(a,seconds): continue
		if a.get("force_route_replan",false) or manager.elapsed_seconds>=float(a.get("emergency_next_replan",0)):
			a.emergency_next_replan=manager.elapsed_seconds+3
			reconsider(a,"Emergency evacuation progression")
		if a.objective.is_empty() or a.route.is_empty(): continue
		a.previous_position=a.position
		var result:=Routes.move(a,seconds)
		if result.arrived: arrivals.append({"agent":a,"offset":result.travel_seconds})
	arrivals.sort_custom(func(a,b):return a.agent.admission_priority<b.agent.admission_priority if is_equal_approx(a.offset,b.offset) else a.offset<b.offset)
	for arrival in arrivals: manager.admit_arrival(arrival.agent)
