extends RefCounted
## Command planning is separate from consent, physical motion and atomic admission.
const Map=preload("res://scripts/city_map.gd")
const Routes=preload("res://scripts/road_routes.gd")
const Perception=preload("res://scripts/agent_perception.gd")
const Beliefs=preload("res://scripts/agent_beliefs.gd")
const EVENT="POLICE_SHELTER_EVACUATION"
var owner: WeakRef
var sim: RefCounted:
	get: return owner.get_ref() if owner!=null else null
var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/police_evacuation.json"))
var operations: Array=[]
var groups: Array=[]
var sequence:=0
var next_plan:=0.0
var next_auto_request:=0.0

func initialize(value: RefCounted) -> void:
	owner=weakref(value); operations.clear(); groups.clear(); sequence=0; next_plan=0; next_auto_request=0
	for a in sim.manager.agents: a["evacuation_group"]=""; a["evacuation_member_status"]=""

func operation(id: String) -> Dictionary:
	for op in operations:
		if op.id==id: return op
	return {}

func group(id: String) -> Dictionary:
	for g in groups:
		if g.id==id: return g
	return {}

func _event(id: String) -> Dictionary:
	for e in sim.manager.environment_events:
		if e.event_id==id: return e
	return {}

func _log(op: Dictionary, action: String, detail: String) -> void:
	var entry: Dictionary={"time":sim.manager.elapsed_seconds,"action":action,"detail":detail}
	op.history.append(entry)
	while op.history.size()>100: op.history.pop_front()
	sim.emit_event("police.evacuation_"+action.to_lower(),op.id,entry)

func _eligible(a: Dictionary) -> bool:
	return a.role=="Civilian" and a.health>0 and a.state not in ["SHELTERED","SAFE","EXPOSED"] and not a.get("medical_evacuated",false)

func _safe(point: Vector2) -> bool:
	if not Map.clear_point(point,5): return false
	for e in sim.manager.environment_events:
		if e.active_status and e.event_type in ["fire","explosion","danger_zone","increasing_threat"] and point.distance_to(e.target_location)<float(e.radius)+15: return false
	return true

func _safe_point(center: Vector2) -> Vector2:
	if _safe(center): return center
	for radius in [40.0,100.0,200.0,400.0,650.0]:
		for angle in range(12):
			var p: Vector2=center+Vector2.from_angle(angle*TAU/12)*radius
			if Rect2(Vector2.ZERO,Map.MAP_SIZE).has_point(p) and _safe(p): return p
	return Vector2.INF

func start(event: Dictionary) -> Dictionary:
	var existing:=operation(event.event_id)
	if not existing.is_empty(): return existing
	if operations.filter(func(o):return o.state!="COMPLETE").size()>=int(config.max_operations): return {}
	var census: Array=sim.manager.agents.filter(func(a):return _eligible(a) and a.position.distance_to(event.target_location)<=float(event.radius)).map(func(a):return a.id)
	var nearest: Dictionary=Map.nearest_edge(event.target_location,true,0)
	var origin: Vector2=event.target_location
	if not nearest.is_empty():
		var tangent: Vector2=preload("res://scripts/traffic_conventions.gd").edge_tangent(nearest.edge,nearest.point)
		origin=nearest.point+preload("res://scripts/traffic_conventions.gd").right(tangent)*(float(nearest.edge.width)*.5+40)
	var gathering:=_safe_point(origin)
	var op: Dictionary={"id":event.event_id,"state":"PLANNING","center":event.target_location,"radius":event.radius,"gathering":gathering,"estimated_count":census.size(),"area_estimate_ids":census,"destination":"","tasks":{},"refusals":{},"contacted":[],"history":[],"search_index":0,"recruit_started":-1.0,"created":sim.manager.elapsed_seconds,"pending_reason":"","revision":0,"source_severity":event.severity}
	operations.append(op); op.destination=_initial_destination(op); _log(op,"PLANNED","Dispatch area estimate: %d; civilians still require local contact"%census.size())
	_plan_tasks(op)
	return op

func _plan_tasks(op: Dictionary) -> void:
	if not op.gathering.is_finite():
		op.gathering=_safe_point(op.center)
		if not op.gathering.is_finite(): op.pending_reason="No safe gathering location"; return
	var roles: Array=["gather","escort"]
	if int(op.estimated_count)>int(config.group_size): roles.append("secure_intersection")
	if int(op.estimated_count)>=int(config.large_operation_size): roles.append("emergency_access")
	for role in roles:
		if op.tasks.has(role): continue
		var point: Vector2=op.gathering
		if role in ["secure_intersection","emergency_access"]:
			var nearest: Dictionary=Map.nearest_edge(op.gathering,true,0)
			if nearest.is_empty(): continue
			var edge: Dictionary=nearest.edge
			var tangent: Vector2=preload("res://scripts/traffic_conventions.gd").edge_tangent(edge,nearest.point)
			point=_safe_point(nearest.point+preload("res://scripts/traffic_conventions.gd").right(tangent)*(float(edge.width)*.5+65)+tangent*(55 if role=="emergency_access" else -55))
		if not point.is_finite(): continue
		var r: Dictionary=sim.police.request_task(op.id,role,point)
		if not r.is_empty(): op.tasks[role]=r.id
	op.state="ORGANIZING" if _task(op,"gather").get("state","")=="ACTIVE" else "DISPATCHING"
	op.pending_reason="" if op.state=="ORGANIZING" else "Awaiting physical police arrival"

func _task(op: Dictionary, role: String) -> Dictionary:
	return sim.police.request_for(str(op.tasks.get(role,"")))

func _crew(request: Dictionary) -> Array:
	var unit: Dictionary=sim.police.unit_for(str(request.get("unit","")))
	return unit.get("officers",[])

func cooperation(a: Dictionary, op: Dictionary) -> float:
	var t: Dictionary=a.get("cognitive_traits",{})
	return clampf(float(a.authority_trust)*.45+float(a.get("cooperation",50))*.2+float(t.get("altruism",a.get("empathy",50)))*.1+float(a.panic_level)*.15+float(op.source_severity)*15-float(t.get("aggression",25))*.12-float(a.get("skepticism",50))*.08,0,100)

func offer(officer: Dictionary, a: Dictionary, op: Dictionary) -> bool:
	if officer.get("occupation","")!="Police" or officer.health<40 or officer.get("duty_status","") in ["DESERTED","RESCUING_FAMILY"] or op.state in ["RETURNING","COMPLETE"]: return false
	if not _eligible(a) or a.get("evacuation_group","")!="" or not Perception.visible(officer,a.position,float(config.communication_radius),float(a.get("transport_height",0))): return false
	if sim.manager.elapsed_seconds-float(a.get("evacuation_last_offer",-1000))<float(config.instruction_interval): return false
	a["evacuation_last_offer"]=sim.manager.elapsed_seconds
	var score:=cooperation(a,op)
	var family_group: Dictionary={}
	for relative in a.relationships:
		var other: Dictionary=sim.by_id.get(relative,{})
		var g:=group(str(other.get("evacuation_group","")))
		if not g.is_empty() and g.operation==op.id:
			family_group=g
			if a.age<18 and Perception.visible(a,other.position,float(config.communication_radius),float(other.get("transport_height",0))): score=maxf(score,float(config.cooperation_threshold)+1)
	a["police_instruction"]={"officer":officer.id,"operation":op.id,"message":"Join the gathering point; shelter route will be explained by the guide","position":op.gathering,"timestamp":sim.manager.elapsed_seconds,"confidence":float(a.authority_trust)/100,"utility":score}
	if a.id not in op.contacted: op.contacted.append(a.id)
	Beliefs.remember(a,sim.manager.elapsed_seconds,"Police evacuation instruction from "+officer.id,sim.manager.living)
	if score<float(config.cooperation_threshold):
		op.refusals[a.id]={"time":sim.manager.elapsed_seconds,"score":score}; a["evacuation_member_status"]="REFUSED"
		_log(op,"REFUSED",a.id+" retains independent decision (utility %.1f)"%score); return false
	var g: Dictionary=family_group if not family_group.is_empty() and family_group.state in ["GATHERING","WAITING_GUIDE","HOLDING","MOVING"] else {}
	if g.is_empty():
		for candidate in groups:
			if candidate.operation==op.id and candidate.state in ["GATHERING","WAITING_GUIDE","HOLDING"] and _pending(candidate).size()<int(config.group_size): g=candidate; break
	if g.is_empty(): g=_new_group(op,op.gathering)
	g.members.append(a.id); g.size=_pending(g).size()
	a["evacuation_saved"]={"emergency_evacuating":a.get("emergency_evacuating",false),"group_on_foot":a.get("group_on_foot",false),"social_target":a.social_target}
	a.evacuation_group=g.id; a.evacuation_member_status="REGROUPING"; a.emergency_evacuating=true; a.group_on_foot=true; a.social_target=""
	a["evacuation_order"]={"officer":officer.id,"gathering":g.regrouping_position,"last_guide":g.regrouping_position,"destination":"","version":-1,"timestamp":sim.manager.elapsed_seconds}
	a["evacuation_family_wait"]=sim.manager.elapsed_seconds+float(config.family_wait_seconds)
	if g.state=="MOVING":
		_announce(g,a,officer); a.evacuation_order.last_guide=g.position
	op.refusals.erase(a.id); _log(op,"JOINED",a.id+" consented to "+g.id)
	return true

func _new_group(op: Dictionary, position: Vector2) -> Dictionary:
	sequence+=1
	var g: Dictionary={"id":"EVG%04d"%sequence,"operation":op.id,"members":[],"arrived":[],"size":0,"destination":"","route":PackedVector2Array(),"route_index":1,"state":"GATHERING","leader":"","guide_unit":"","position":position,"regrouping_position":position,"created":sim.manager.elapsed_seconds,"version":0,"revision":-1,"pending_reason":"","lag_since":-1.0}
	groups.append(g); return g

func _pending(g: Dictionary) -> Array:
	return g.members.filter(func(id):return sim.by_id[id].get("evacuation_group","")==g.id and _eligible(sim.by_id[id]))

func _committed(shelter: String, except_group: String = "") -> int:
	var count:=0
	for g in groups:
		if g.id!=except_group and g.destination==shelter and g.state not in ["COMPLETE","MERGED"]: count+=_pending(g).size()
	return count

func _shelter_known(s: Dictionary) -> bool:
	return s.id!="S5" or sim.manager.agents.any(func(a):return a.role=="Authority" and float(a.beliefs.S5.existence_probability)>=1.0)

func _path_safe(path: PackedVector2Array) -> bool:
	if path.is_empty(): return false
	for i in range(1,path.size()):
		if not Map.clear_segment(path[i-1],path[i]): return false
	return true

func _allocate(g: Dictionary) -> void:
	var needed:=_pending(g).size()
	if needed==0: return
	var best: Dictionary={}; var route:=PackedVector2Array(); var best_score:=INF
	var op:=operation(g.operation)
	var preferred: String=_event(op.id).get("target_id","")
	for s in sim.manager.shelters:
		if not s.exists or not s.operational or not s.get("admission_open",false) or s.get("safety_status","")!="SAFE" or not _shelter_known(s): continue
		if int(s.available_capacity)-_committed(s.id,g.id)<needed: continue
		var path: PackedVector2Array=Routes.plan(g.position,s.position)
		if not _path_safe(path): continue
		var score: float=Routes.length(path)*(0.8 if s.id==preferred else 1.0)
		if score<best_score: best=s; route=path; best_score=score
	if best.is_empty():
		g.destination=""; g.route=PackedVector2Array(); g.state="HOLDING"; g.pending_reason="No safe reachable shelter can accommodate this group and other incoming groups"
		_split_for_capacity(g)
		return
	var changed: bool=g.destination!=best.id or g.revision!=Map.navigation_revision or not _path_safe(g.route)
	if changed:
		g.destination=best.id; g.route=route; g.route_index=1; g.revision=Map.navigation_revision; g.version+=1; op.revision+=1
		_log(op,"ROUTE_UPDATED",g.id+" to "+best.id+"; incoming estimates include other groups")
	g.pending_reason=""; op.destination=best.id
	if g.state=="HOLDING": g.state="WAITING_GUIDE"

func _split_for_capacity(g: Dictionary) -> void:
	var members:=_pending(g)
	var bundles: Dictionary={}
	for id in members:
		var a: Dictionary=sim.by_id[id]; var key: String=a.family_id if a.family_id!="" else id
		if not bundles.has(key): bundles[key]=[]
		bundles[key].append(id)
	if bundles.size()<2: return # A family is kept intact when no safe option fits it.
	var largest:=0
	for s in sim.manager.shelters:
		if s.get("admission_open",false) and s.get("safety_status","")=="SAFE" and _shelter_known(s): largest=maxi(largest,int(s.available_capacity)-_committed(s.id,g.id))
	if largest<=0 or largest>=members.size(): return
	var subset: Array=[]
	for bundle in bundles.values():
		if subset.size()+bundle.size()<=largest: subset.append_array(bundle)
	if not subset.is_empty() and subset.size()<members.size(): split_group(g.id,subset,"Shelter capacity requires family-preserving split")

func split_group(id: String, member_ids: Array, reason: String) -> Dictionary:
	var g:=group(id)
	if g.is_empty() or member_ids.is_empty() or member_ids.size()>=_pending(g).size(): return {}
	if not member_ids.all(func(member):return member in _pending(g)): return {}
	var other:=_new_group(operation(g.operation),g.position)
	other.state="WAITING_GUIDE"
	for member in member_ids:
		g.members.erase(member); other.members.append(member); sim.by_id[member].evacuation_group=other.id
	g.size=_pending(g).size(); other.size=_pending(other).size(); g.revision=-1
	_log(operation(g.operation),"SPLIT",g.id+" / "+other.id+": "+reason)
	return other

func merge_groups(first: String, second: String) -> bool:
	var a:=group(first); var b:=group(second)
	if a.is_empty() or b.is_empty() or a==b or a.operation!=b.operation: return false
	if a.state not in ["GATHERING","WAITING_GUIDE","HOLDING"] or b.state not in ["GATHERING","WAITING_GUIDE","HOLDING"]: return false
	if a.position.distance_to(b.position)>float(config.regroup_radius) or _pending(a).size()+_pending(b).size()>int(config.group_size): return false
	if a.destination!="" and b.destination!="" and a.destination!=b.destination: return false
	for id in b.members: a.members.append(id); sim.by_id[id].evacuation_group=a.id
	b.members=[]; b.size=0; b.state="MERGED"; a.size=_pending(a).size(); a.revision=-1
	_log(operation(a.operation),"MERGED",b.id+" into "+a.id); return true

func _brief(op: Dictionary) -> void:
	for request_id in op.tasks.values():
		var r: Dictionary=sim.police.request_for(request_id)
		for id in _crew(r):
			sim.by_id[id]["police_operation_briefing"]={"operation":op.id,"revision":op.revision,"destination":op.destination,"gathering":op.gathering,"estimated_civilians":op.estimated_count,"task":r.task,"source":"POLICE_COMMAND","timestamp":sim.manager.elapsed_seconds,"groups":groups.filter(func(g):return g.operation==op.id).map(func(g):return {"id":g.id,"position":g.position,"destination":g.destination,"size":g.size})}

func _recruit(op: Dictionary, seconds: float) -> void:
	var r:=_task(op,"gather")
	if r.get("state","")!="ACTIVE": return
	if op.recruit_started<0: op.recruit_started=sim.manager.elapsed_seconds
	if sim.manager.elapsed_seconds-float(op.recruit_started)>float(config.recruitment_seconds) and not groups.any(func(g):return g.operation==op.id and not _pending(g).is_empty()): return
	var ids:=_crew(r)
	for id in ids:
		var officer: Dictionary=sim.by_id[id]
		var separated: Array=sim.manager.agents.filter(func(a):return _eligible(a) and a.get("evacuation_member_status","")=="SEPARATED" and group(str(a.get("evacuation_group",""))).get("operation","")==op.id and Perception.visible(officer,a.position,float(sim.cognition.config.observation_radius),float(a.get("transport_height",0))))
		if not separated.is_empty():
			var member: Dictionary=separated[0]; var g:=group(member.evacuation_group)
			if officer.position.distance_to(member.position)>float(config.communication_radius): sim.police._walk(officer,member.position,seconds)
			else:
				_announce(g,member,officer); member.evacuation_order.last_guide=g.position; member.evacuation_member_status="REJOINING"; officer.police_animation="helping"
			continue
		var visible: Array=sim.manager.agents.filter(func(a):return _eligible(a) and a.get("evacuation_group","")=="" and a.position.distance_to(op.center)<=float(op.radius) and Perception.visible(officer,a.position,float(sim.cognition.config.observation_radius),float(a.get("transport_height",0))) and sim.manager.elapsed_seconds-float(a.get("evacuation_last_offer",-1000))>=float(config.instruction_interval))
		visible.sort_custom(func(a,b):return a.position.distance_squared_to(officer.position)<b.position.distance_squared_to(officer.position))
		if not visible.is_empty():
			var a: Dictionary=visible[0]
			if officer.position.distance_to(a.position)>float(config.communication_radius): sim.police._walk(officer,a.position,seconds)
			else:
				officer.police_animation="communicating"; offer(officer,a,op)
		else:
			# Patrol a bounded deterministic search pattern; unknown people are not tracked.
			var index: int=int(op.search_index)+ids.find(id)*3
			var radius: float=minf(float(op.radius)*.85,float(config.search_stride)*(1+index/12))
			var point:=_safe_point(op.center+Vector2.from_angle(index*TAU/12)*radius)
			if point.is_finite() and sim.police._walk(officer,point,seconds): op.search_index+=1

func _active_guide(op: Dictionary, g: Dictionary) -> Dictionary:
	var r:=_task(op,"escort")
	if r.get("state","")!="ACTIVE": return {}
	var assigned: Dictionary=group(str(r.get("assigned_group","")))
	if not assigned.is_empty() and assigned.id!=g.id and not _pending(assigned).is_empty(): return {}
	if groups.any(func(other):return other.id!=g.id and other.guide_unit==r.unit and other.state=="MOVING"): return {}
	r["assigned_group"]=g.id
	return r

func _announce(g: Dictionary, a: Dictionary, officer: Dictionary) -> void:
	if not Perception.visible(officer,a.position,float(config.communication_radius),float(a.get("transport_height",0))): return
	var old: Dictionary=a.get("evacuation_order",{})
	if old.get("version",-1)==g.version and sim.manager.elapsed_seconds-float(old.get("timestamp",-1000))<float(config.instruction_interval): return
	if a.age>=18 and cooperation(a,operation(g.operation))<float(config.cooperation_threshold): leave_group(a,"Reassessed police instruction and declined"); return
	if a.panic_level>75: a.panic_level=maxf(0,a.panic_level-2)
	a.evacuation_order={"officer":officer.id,"gathering":g.regrouping_position,"last_guide":officer.position,"destination":g.destination,"shelter_position":sim.manager.shelter_by_id[g.destination].position if g.destination!="" else g.regrouping_position,"version":g.version,"timestamp":sim.manager.elapsed_seconds}
	if g.destination!="":
		var b: Dictionary=a.beliefs[g.destination]
		b.position=sim.manager.shelter_by_id[g.destination].position; b.source="Police guide "+officer.id; b.confidence=.95; b.existence_probability=1.0
		a.objective=g.destination

func _guide(g: Dictionary, seconds: float) -> void:
	var members:=_pending(g)
	if members.is_empty(): g.state="COMPLETE"; g.size=0; return
	var op:=operation(g.operation)
	if g.destination=="": return
	var r:=_active_guide(op,g)
	if r.is_empty(): g.state="WAITING_GUIDE"; g.pending_reason="Awaiting a physically arrived escort crew"; return
	var crew:=_crew(r)
	if crew.is_empty(): return
	var lead: Dictionary=sim.by_id[crew[0]]
	if g.leader=="" and lead.position.distance_to(g.regrouping_position)>float(config.communication_radius):
		for id in crew: sim.police._walk(sim.by_id[id],g.regrouping_position,seconds)
		g.pending_reason="Escort physically approaching group"; return
	var gathered: Array=members.filter(func(id):return sim.by_id[id].position.distance_to(g.regrouping_position)<=float(config.regroup_radius))
	if g.state!="MOVING" and (gathered.is_empty() or (gathered.size()<members.size() and sim.manager.elapsed_seconds-float(g.created)<float(config.regroup_seconds))):
		for id in members: _announce(g,sim.by_id[id],lead)
		return
	g.leader=lead.id; g.guide_unit=r.unit; g.state="MOVING"; g.pending_reason=""
	var speed: float=lead.walk_speed
	var lagging:=false
	for id in members:
		var a: Dictionary=sim.by_id[id]; speed=minf(speed,_speed(a))
		if a.position.distance_to(lead.position)>float(config.leash_distance): lagging=true
		_announce(g,a,lead)
	if lagging and g.lag_since<0: g.lag_since=sim.manager.elapsed_seconds
	if not lagging: g.lag_since=-1.0
	if lagging and sim.manager.elapsed_seconds-float(g.lag_since)<float(config.family_wait_seconds): lead.police_animation="communicating"; return
	if g.route_index<g.route.size():
		var target: Vector2=g.route[g.route_index]
		for i in range(crew.size()):
			var officer: Dictionary=sim.by_id[crew[i]]; var original: float=officer.walk_speed
			officer.walk_speed=speed; sim.police._walk(officer,target if i==0 else lead.position+Vector2(10,0),seconds); officer.walk_speed=original
		if lead.position.distance_to(target)<=5: g.route_index+=1
	g.position=lead.position

func _speed(a: Dictionary) -> float:
	return float(a.walk_speed)*clampf(float(a.health)/70,.25,1)*clampf(1-float(a.get("fatigue",0))/250,.6,1)

func _walk_member(a: Dictionary, target: Vector2, seconds: float) -> void:
	if not a.has("evacuation_walk") or a.get("evacuation_walk_target",Vector2.INF).distance_to(target)>8 or a.get("evacuation_walk_revision",-1)!=Map.navigation_revision:
		a.evacuation_walk=Routes.plan(a.position,target); a.evacuation_walk_target=target; a.evacuation_walk_index=1; a.evacuation_walk_revision=Map.navigation_revision
	var proxy: Dictionary={"position":a.position,"route":a.evacuation_walk,"route_index":a.evacuation_walk_index,"movement_speed":_speed(a)}
	a.previous_position=a.position; Routes.move(proxy,seconds); a.position=proxy.position; a.evacuation_walk_index=proxy.route_index
	sim.manager._set_state(a,"MOVING")

func _move_member(a: Dictionary, g: Dictionary, seconds: float) -> void:
	if not _eligible(a) or a.get("evacuation_group","")!=g.id: return
	if a.get("riding","")!="":
		for v in sim.vehicles:
			if v.id!=a.riding: continue
			v.boarding_stop=true
			if v.speed<=1:
				if v.status=="PARKED": sim.leave(v,a)
				else: sim.driving.safe_disembark(v,sim.by_id[v.driver])
		return
	if a.get("indoor_id","")!="": sim.daily.interiors.exit_building(a,seconds); return
	if sim.cognition.move(a,seconds): a.evacuation_member_status="SEPARATED"; return
	if a.state in ["DELAYED","DANCING","HELPING","STAGGERED","FROZEN","STAYING_HOME"] and sim.manager.elapsed_seconds<float(a.get("wait_until",0)):
		a.evacuation_member_status="PAUSED_BY_CHOICE"; return
	var order: Dictionary=a.evacuation_order
	var lead: Dictionary=sim.by_id.get(g.leader,{})
	var target: Vector2=order.gathering
	if g.state=="MOVING" and not lead.is_empty():
		var visible: bool=Perception.visible(a,lead.position,float(sim.cognition.config.observation_radius),float(lead.get("transport_height",0)))
		if visible:
			_announce(g,a,lead)
			if a.get("evacuation_group","")!=g.id: return
			order=a.evacuation_order; order.last_guide=lead.position
			if order.destination!="" and lead.position.distance_to(order.shelter_position)<float(config.follow_distance): target=order.shelter_position
			else:
				var offset: Vector2=Vector2.from_angle(float(a.get("population_index",0))*2.4)*(8+int(a.get("population_index",0))%3*4)
				target=lead.position+offset if _safe(lead.position+offset) else lead.position
				if a.position.distance_to(target)<=float(config.follow_distance): a.evacuation_member_status="FOLLOWING"; return
		else: target=order.last_guide; a.evacuation_member_status="SEPARATED"
	else: a.evacuation_member_status="REGROUPING"
	# Short family waits use only visible relatives or their shared group membership.
	for id in a.relationships:
		var relative: Dictionary=sim.by_id.get(id,{})
		if relative.get("evacuation_group","")!=g.id or relative.health<=0: continue
		if relative.get("evacuation_member_status","")=="SEPARATED":
			if a.get("evacuation_waiting_for","")!=id:
				a["evacuation_waiting_for"]=id; a.evacuation_family_wait=sim.manager.elapsed_seconds+float(config.family_wait_seconds)
			if sim.manager.elapsed_seconds<float(a.evacuation_family_wait): a.current_goal="Wait for separated family member "+id; return
		elif a.get("evacuation_waiting_for","")==id: a.erase("evacuation_waiting_for")
	if a.health<50 and not a.get("evacuation_assistance_reported",false):
		a["evacuation_assistance_reported"]=true
		_log(operation(g.operation),"ASSISTANCE_REQUESTED",a.id+" needs medical help; group pace reduced")
		if not lead.is_empty() and Perception.visible(lead,a.position,float(config.communication_radius),float(a.get("transport_height",0))): sim.authorities.report(lead,"evacuation_medical_assistance",{"agent":a.id},a.position,.05,"direct observation",sim.manager.agents.filter(func(p):return p.occupation=="Medical").map(func(p):return p.id))
	_walk_member(a,target,seconds)
	a.current_goal="Police evacuation "+g.id+" / "+a.evacuation_member_status
	if order.get("destination","")!="" and a.position.distance_to(order.shelter_position)<.01:
		a.objective=order.destination
		var result: String=sim.manager.admit_arrival(a)
		if result=="":
			g.arrived.append(a.id); a.evacuation_member_status="ARRIVED"; a.evacuation_group=""
			_log(operation(g.operation),"ADMITTED",a.id+" physically entered "+order.destination)
		else: g.revision=-1; a.evacuation_member_status="AWAITING_REDIRECTION"

func leave_group(a: Dictionary, reason: String) -> void:
	var g:=group(str(a.get("evacuation_group","")))
	if g.is_empty(): return
	_log(operation(g.operation),"LEFT_GROUP",a.id+": "+reason)
	a.evacuation_group=""; a.evacuation_member_status="INDEPENDENT"
	var saved: Dictionary=a.get("evacuation_saved",{})
	a.emergency_evacuating=saved.get("emergency_evacuating",false); a.group_on_foot=saved.get("group_on_foot",false); a.social_target=saved.get("social_target","")
	a.next_rule_decision=sim.manager.elapsed_seconds

func _finish(op: Dictionary, reason: String) -> void:
	if op.state=="RETURNING" or op.state=="COMPLETE": return
	for g in groups:
		if g.operation!=op.id: continue
		for id in _pending(g): leave_group(sim.by_id[id],reason)
		if g.state!="MERGED": g.state="COMPLETE"
		g.size=0
	for request_id in op.tasks.values(): sim.police.request_removal(request_id,reason)
	op["outcomes"]={"admitted":0,"refused":op.refusals.size(),"uncontacted":op.area_estimate_ids.filter(func(id):return id not in op.contacted and _eligible(sim.by_id[id])).size()}
	for g in groups:
		if g.operation==op.id: op.outcomes.admitted+=g.arrived.size()
	op.state="RETURNING"; op.pending_reason=reason; _log(op,"RETURNING",reason)

func tick(seconds: float) -> void:
	if sim==null or sim.replaying or sim.manager.phase not in ["LIVING","EVACUATION","BOMB_FALL"]: return
	var now: float=sim.manager.elapsed_seconds
	var planning: bool=now>=next_plan
	if planning: next_plan=now+float(config.planning_interval)
	if bool(config.automatic_requests) and now>=next_auto_request:
		next_auto_request=now+float(config.automatic_request_interval); consider_authority_requests()
	for op in operations:
		if op.state=="COMPLETE": continue
		for g in groups:
			if g.operation!=op.id: continue
			for id in g.members:
				var a: Dictionary=sim.by_id[id]
				if a.state=="SHELTERED" and a.get("evacuation_group","")==g.id:
					if id not in g.arrived: g.arrived.append(id)
					a.evacuation_group=""; a.evacuation_member_status="ARRIVED"
		var e:=_event(op.id)
		if e.is_empty() or not e.active_status: _finish(op,"Operation event ended; release civilians and return crews")
		if op.state=="RETURNING":
			var returning: bool=sim.police.units.any(func(u):return u.request in op.tasks.values())
			if not returning:
				op.state="COMPLETE"; op["completed_at"]=now; _log(op,"COMPLETE","Assigned crews released; outcomes remain in history")
				sim.manager.emergency.clear_event(op.id)
			continue
		if planning:
			_plan_tasks(op); _brief(op); _merge_waiting(op)
			if not _safe(op.gathering):
				var safe:=_safe_point(op.gathering)
				if safe.is_finite():
					op.gathering=safe; op.revision+=1
					for g in groups:
						if g.operation==op.id and g.state in ["GATHERING","WAITING_GUIDE","HOLDING"]: g.regrouping_position=safe; g.position=safe; g.version+=1
					var gathering_task:=_task(op,"gather")
					if not gathering_task.is_empty(): gathering_task.position=safe
					_log(op,"GATHERING_MOVED","Danger requires a new safe gathering point; local instructions follow")
			for g in groups.duplicate():
				if g.operation==op.id and not _pending(g).is_empty():
					_allocate(g)
					for task_id in op.tasks.values():
						var task: Dictionary=sim.police.request_for(task_id)
						if task.get("state","")!="ACTIVE": continue
						for officer_id in _crew(task):
							for member_id in _pending(g): _announce(g,sim.by_id[member_id],sim.by_id[officer_id])
		_recruit(op,seconds)
		for g in groups.duplicate():
			if g.operation!=op.id or g.state in ["COMPLETE","MERGED"]: continue
			_guide(g,seconds)
			for id in _pending(g): _move_member(sim.by_id[id],g,seconds)
			g.size=_pending(g).size()
		if op.recruit_started>=0 and not groups.any(func(g):return g.operation==op.id and not _pending(g).is_empty()):
			var resolved: bool=op.area_estimate_ids.all(func(id):return not _eligible(sim.by_id[id]) or op.refusals.has(id))
			if resolved or now-float(op.recruit_started)>float(config.recruitment_seconds): _finish(op,"Recruitment complete; admitted, refused and uncontacted outcomes retained")

func snapshot() -> Dictionary:
	return {"operations":operations,"groups":groups,"sequence":sequence}

func inspection(id: String = "") -> String:
	var text: String="\nORGANIZED EVACUATION\n"
	for op in operations:
		if id!="" and op.id!=id: continue
		text+="%s / %s / estimated %d / destination %s\nGathering %s / tasks %s\n%s\n"%[op.id,op.state,op.estimated_count,op.destination,str(op.gathering),str(op.tasks),op.pending_reason+" / outcomes "+str(op.get("outcomes",{}))]
		for g in groups:
			if g.operation==op.id: text+="%s / %s / size %d / guide %s / destination %s / admitted %d\nMembers %s\n%s\n"%[g.id,g.state,g.size,g.leader,g.destination,g.arrived.size(),str(g.members),g.pending_reason]
		for h in op.history.slice(-8): text+="%.1fs %s: %s\n"%[h.time,h.action,h.detail]
	return text

func _initial_destination(op: Dictionary) -> String:
	var best: String=""; var cost:=INF
	if not op.gathering.is_finite(): return best
	for s in sim.manager.shelters:
		if not s.exists or not s.operational or not s.get("admission_open",false) or s.get("safety_status","")!="SAFE" or not _shelter_known(s) or int(s.available_capacity)<=0: continue
		var route: PackedVector2Array=Routes.plan(op.gathering,s.position)
		if _path_safe(route) and Routes.length(route)<cost: best=s.id; cost=Routes.length(route)
	return best

func consider_authority_requests() -> void:
	for a in sim.manager.agents:
		if a.occupation!="Police" or a.health<40 or a.get("police_unit_busy",false) or a.get("duty_status","")!="ON_DUTY": continue
		var observations: Array=a.get("cognition",{}).get("observations",[])
		var people: Array=observations.filter(func(item):return item.kind in ["person","injured"] and sim.by_id.has(item.id) and _eligible(sim.by_id[item.id]) and sim.manager.elapsed_seconds-float(item.timestamp)<=float(sim.cognition.config.perception_interval)*2)
		if people.size()<int(config.minimum_observed_civilians): continue
		var danger: bool=observations.any(func(item):return item.kind in ["fire","explosion","danger_zone","increasing_threat"] and sim.manager.elapsed_seconds-float(item.timestamp)<=float(sim.cognition.config.perception_interval)*2)
		var stranded: bool=people.filter(func(item):return sim.by_id[item.id].state in ["WAITING_ROAD","REJECTED"]).size()>=int(config.minimum_observed_civilians)
		if danger or stranded: request_by_authority(a,"Observed danger with scattered civilians" if danger else "Observed stranded civilians")

func request_by_authority(a: Dictionary, reason: String) -> String:
	if a.role!="Authority" or a.occupation not in ["Police","Crisis commander"] or a.health<40 or a.get("duty_status","") in ["DESERTED","RESCUING_FAMILY"]: return ""
	if operations.any(func(op):return (op.state!="COMPLETE" or sim.manager.elapsed_seconds-float(op.get("completed_at",0))<60) and op.center.distance_to(a.position)<=float(op.radius)): return ""
	if sim.manager.environment_events.any(func(e):return e.event_type==EVENT and not e.ended and e.target_location.distance_to(a.position)<=float(e.radius)): return ""
	var id: String=sim.manager.add_emergency(EVENT,a.position,{"radius":250,"duration":1200})
	if id!="": sim.emit_event("police.evacuation_requested",a.id,{"event":id,"reason":reason,"position":a.position})
	return id

func _merge_waiting(op: Dictionary) -> void:
	var waiting: Array=groups.filter(func(g):return g.operation==op.id and g.state in ["GATHERING","WAITING_GUIDE","HOLDING"] and g.destination!="" and not _pending(g).is_empty())
	for i in range(waiting.size()):
		for j in range(i+1,waiting.size()):
			var a: Dictionary=waiting[i]; var b: Dictionary=waiting[j]
			if a.state=="MERGED" or b.state=="MERGED" or a.destination!=b.destination: continue
			var s: Dictionary=sim.manager.shelter_by_id[a.destination]
			if _committed(s.id)<=int(s.available_capacity): merge_groups(a.id,b.id)
