extends RefCounted
## Operational requests do not become barriers until the assigned crew physically deploys.
const Map=preload("res://scripts/city_map.gd")
const Routes=preload("res://scripts/road_routes.gd")
const Convention=preload("res://scripts/traffic_conventions.gd")
var owner: WeakRef
var sim: RefCounted:
	get: return owner.get_ref() if owner!=null else null
var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/police_response.json"))
var units: Array=[]
var requests: Array=[]
var stations: Array=[]
var sequence:=0

func initialize(value: RefCounted) -> void:
	owner=weakref(value); units.clear(); requests.clear(); stations.clear(); sequence=0
	for room in sim.daily.interiors.rooms.values():
		if room.kind=="Police Station": stations.append({"id":room.id,"position":room.center})
	var officers: Array=sim.manager.agents.filter(func(a):return a.role=="Authority" and a.occupation=="Police")
	var assigned: Array=[]
	var drivers: Array=sim.vehicles.filter(func(v):return v.kind=="Police").map(func(v):return v.driver)
	for v in sim.vehicles:
		if v.kind!="Police" or v.driver in assigned or sim.by_id[v.driver].occupation!="Police": continue
		var driver: Dictionary=sim.by_id[v.driver]
		var partner: Dictionary={}
		for a in officers:
			if a.id!=driver.id and a.id not in assigned:
				if partner.is_empty() or (partner.id in drivers and a.id not in drivers) or ((partner.id in drivers)==(a.id in drivers) and a.position.distance_to(driver.position)<partner.position.distance_to(driver.position)): partner=a
		if partner.is_empty(): continue
		var id: String="PU%02d"%(units.size()+1)
		var station: Dictionary={}
		for site in stations:
			if station.is_empty() or site.position.distance_to(v.position)<station.position.distance_to(v.position): station=site
		units.append({"id":id,"vehicle":v.id,"officers":[driver.id,partner.id],"station":station.get("id",""),"state":"AVAILABLE","request":"","eta":0.0,"patrol_assignment":"traffic patrol and emergency readiness","position":v.position})
		for a in [driver,partner]:
			assigned.append(a.id); a["police_unit_id"]=id; a["police_unit_busy"]=false; a["police_animation"]=""

func vehicle(unit: Dictionary) -> Dictionary:
	for v in sim.vehicles:
		if v.id==unit.vehicle: return v
	return {}

func unit_for(id: String) -> Dictionary:
	for unit in units:
		if unit.id==id: return unit
	return {}

func request_for(id: String) -> Dictionary:
	for request in requests:
		if request.id==id: return request
	return {}

func crew_available(unit: Dictionary, hazard: String = "") -> bool:
	if unit.officers.size()!=int(config.required_officers): return false
	var v:=vehicle(unit)
	if v.is_empty() or v.health<=0 or v.status in ["ACCIDENT","REMOVED","DESTROYED"]: return false
	for passenger in v.passengers:
		if passenger not in unit.officers: return false
	for id in unit.officers:
		var a: Dictionary=sim.by_id[id]
		if a.health<40 or a.state in ["SHELTERED","SAFE","EXPOSED"] or a.get("duty_status","") in ["DESERTED","RESCUING_FAMILY"]: return false
		if a.get("responding_to","") not in ["",hazard]: return false
	return true

func reason_active(request: Dictionary) -> bool:
	var kind: String=request.evidence.get("hazard_kind","")
	var id: String=request.evidence.get("hazard_id","")
	if kind=="POLICE_SHELTER_EVACUATION" and sim.evacuation.operation(id).get("state","COMPLETE") in ["RETURNING","COMPLETE"]: return false
	if kind=="nuclear": return sim.manager.phase in ["EVACUATION","BOMB_FALL"]
	if kind=="full_shelter": return sim.manager.shelter_by_id.has(id) and sim.manager.shelter_by_id[id].available_capacity==0
	for scene in sim.traffic.scenes:
		if scene.vehicle==id and not scene.recovered: return true
	for event in sim.manager.environment_events:
		if event.event_id==id and event.active_status: return true
	return false

func request_deployment(kind: String, edge: int, point: Vector2, rationale: String, evidence: Dictionary) -> Dictionary:
	if edge<0 or edge>=Map.roads.size() or rationale.is_empty() or not point.is_finite(): return {}
	if kind not in ["police","checkpoint","evacuation_checkpoint","restricted","emergency_lane","damaged_road"]: return {}
	var road: Dictionary=Map.roads[edge]
	var distance:=INF
	for i in range(1,road.points.size()): distance=minf(distance,Geometry2D.get_closest_point_to_segment(point,road.points[i-1],road.points[i]).distance_to(point))
	if distance>float(road.width)*.5+float(road.sidewalk): return {}
	for r in requests:
		if r.state!="REMOVED" and r.edge==edge: return r
	if requests.filter(func(r):return r.state!="REMOVED").size()>=int(config.max_requests): return {}
	var probe: Dictionary={"evidence":evidence}
	if not reason_active(probe): return {}
	var decision: Dictionary=sim.authorities.evaluate_roadblock(evidence)
	if decision.action=="hold": return {}
	sequence+=1
	var request: Dictionary={"id":"RBQ%04d"%sequence,"kind":kind,"edge":edge,"position":point,"rationale":rationale,"evidence":evidence.duplicate(true),"state":"REQUESTED","unit":"","block":"","created":sim.manager.elapsed_seconds,"changed":sim.manager.elapsed_seconds,"history":[],"pending_reason":"","eta":0.0,"next_instruction":0.0,"work_started":-1.0,"removal_reason":""}
	requests.append(request); _transition(request,"REQUESTED","Operational request received")
	_transition(request,"EVALUATED",decision.reason)
	return request

func _transition(request: Dictionary, state: String, reason: String) -> void:
	request.state=state; request.changed=sim.manager.elapsed_seconds
	request.history.append({"state":state,"time":request.changed,"reason":reason})
	sim.emit_event("police.task_state" if request.kind=="evacuation_task" else "police.roadblock_state",request.id,{"state":state,"reason":reason,"unit":request.unit,"edge":request.edge})

func _candidate(unit: Dictionary, request: Dictionary) -> Dictionary:
	if unit.state!="AVAILABLE" or not crew_available(unit,str(request.evidence.get("hazard_id",""))): return {}
	var v:=vehicle(unit)
	var best: Dictionary={}
	for lot in Map.parking_lots:
		for bay in lot.bays:
			if bay.occupied_by not in ["",v.id] or not _parking_access_clear(v,bay): continue
			if not best.is_empty() and bay.position.distance_to(request.position)/maxf(1,float(sim.by_id[unit.officers[1]].walk_speed))>float(best.eta): continue
			var foot: PackedVector2Array=Routes.plan(bay.position,officer_position(request,1))
			if foot.is_empty(): continue
			var start: Vector2=v.parking_exit[-1] if not v.get("parking_exit",PackedVector2Array()).is_empty() else v.position
			var path: PackedVector2Array=sim._vehicle_route(start,bay.approach[0],true,float(v.height),sim.by_id[v.driver].get("known_traffic",{}))
			if path.is_empty(): continue
			var distance: float=Routes.length(path)+Routes.length(bay.approach)+Routes.length(v.get("parking_exit",PackedVector2Array()))
			var assembly:=0.0
			for id in unit.officers:
				var a: Dictionary=sim.by_id[id]
				var origin: Vector2=a.get("indoor_exit",a.position) if a.get("indoor_id","")!="" else a.position
				var walk: PackedVector2Array=Routes.plan(origin,v.position)
				if walk.is_empty(): assembly=INF; break
				assembly=maxf(assembly,(Routes.length(walk)+a.position.distance_to(origin))/maxf(1,float(a.walk_speed)))
			var eta: float=assembly+distance/maxf(10,minf(float(v.max_speed),float(sim.driving.settings.urban_speed_limit))*.65)+Routes.length(foot)/maxf(1,float(sim.by_id[unit.officers[1]].walk_speed))+float(config.deployment_seconds)
			if is_finite(eta) and (best.is_empty() or eta<float(best.eta)): best={"unit":unit.id,"bay":bay,"eta":eta,"road_distance":distance,"foot_distance":Routes.length(foot)}
	return best

func _assign(request: Dictionary) -> void:
	if request.kind!="evacuation_task" and requests.filter(func(r):return r.kind!="evacuation_task" and r.state in ["ASSIGNED","DISPATCHED","ARRIVED","DEPLOYING","ACTIVE","REMOVING"]).size()>=int(config.max_active_deployments):
		request.pending_reason="Deployment capacity in use; request remains queued"; return
	var best: Dictionary={}
	for unit in units:
		var candidate:=_candidate(unit,request)
		if not candidate.is_empty() and (best.is_empty() or candidate.eta<best.eta): best=candidate
	if best.is_empty(): request.pending_reason="No available two-officer unit with a reachable parking/deployment route"; return
	var unit:=unit_for(best.unit)
	unit.state="ASSEMBLING"; unit.request=request.id; unit.eta=best.eta
	request.unit=unit.id; request.eta=best.eta; request["road_distance"]=best.road_distance; request["foot_distance"]=best.foot_distance; request["parking_bay"]=best.bay; request.pending_reason=""
	best.bay.occupied_by="POLICE:"+unit.id
	for id in unit.officers:
		var a: Dictionary=sim.by_id[id]
		a.police_unit_busy=true; a.police_animation="coordinating"; a.duty_task=("Evacuation "+str(request.get("task","")) if request.kind=="evacuation_task" else "Roadblock request "+request.id)
		a["police_saved_group_on_foot"]=a.get("group_on_foot",false); a["police_saved_vehicle_routine"]=a.get("routine_use_vehicle",false)
		a["police_saved_target"]=a.social_target; a.social_target=""; a.current_goal=a.duty_task
	_transition(request,"ASSIGNED","Selected reachable unit by road and crew-assembly ETA")

func _walk(a: Dictionary, target: Vector2, seconds: float) -> bool:
	if a.health<=0 or a.state in ["SHELTERED","SAFE","EXPOSED"]: return false
	if a.get("cognition",{}).get("action","") in ["FLEE","DETOUR"] and sim.cognition.move(a,seconds): return false
	if a.get("riding","")!="":
		for v in sim.vehicles:
			if v.id==a.riding:
				if v.speed>1: v.boarding_stop=true; return false
				sim.leave(v,a)
	if a.get("indoor_id","")!="": sim.daily.interiors.exit_building(a,seconds); a.police_animation="walking"; return false
	if a.position.distance_to(target)<=5: a.police_animation="coordinating"; return true
	if a.get("police_walk_target",Vector2.INF).distance_to(target)>1 or a.get("police_walk_revision",-1)!=Map.navigation_revision or not a.has("police_walk_route"):
		a.police_walk_target=target; a.police_walk_route=Routes.plan(a.position,target); a.police_walk_index=1; a.police_walk_revision=Map.navigation_revision
	var proxy: Dictionary={"position":a.position,"route":a.police_walk_route,"route_index":a.police_walk_index,"movement_speed":float(a.walk_speed)}
	a.previous_position=a.position; Routes.move(proxy,seconds); a.position=proxy.position; a.police_walk_index=proxy.route_index
	sim.manager._set_state(a,"MOVING"); a.police_animation="walking"
	return a.position.distance_to(target)<=5

func tick(seconds: float) -> void:
	if sim==null or sim.replaying: return
	var now: float=sim.manager.elapsed_seconds
	for unit in units:
		var patrol:=vehicle(unit)
		unit.position=patrol.get("position",Vector2.ZERO); unit["available"]=unit.state=="AVAILABLE" and crew_available(unit)
	for request in requests:
		if request.state=="REMOVED": continue
		if not reason_active(request) or (request.state=="ARRIVED" and request.get("remove_after_arrival",false)): request_removal(request.id,"Operational reason cleared or assignment complete")
		if request.state=="EVALUATED":
			if now>=float(request.get("next_dispatch",0)): request.next_dispatch=now+float(config.dispatch_interval); _assign(request)
			continue
		var unit:=unit_for(request.unit)
		if unit.is_empty(): continue
		var v:=vehicle(unit)
		unit.position=v.position if not v.is_empty() else Vector2.ZERO
		if not crew_available(unit,str(request.evidence.get("hazard_id",""))):
			request.pending_reason="Assigned crew or vehicle unavailable; reassessment required"
			if request.block!="":
				for b in sim.blocks:
					if b.id==request.block: b.unmanaged=true
			_release(unit); request.unit=""; _transition(request,"EVALUATED",request.pending_reason)
			continue
		if request.state=="ASSIGNED":
			var ready:=true
			v.boarding_stop=true if v.speed>1 else false
			for id in unit.officers:
				var a: Dictionary=sim.by_id[id]
				if a.get("riding","")==v.id: continue
				if _walk(a,v.position,seconds) and v.speed<=1: sim.board(v,a)
				if a.get("riding","")!=v.id: ready=false
			if ready:
				var bay: Dictionary=request.parking_bay
				var key: String="police_dispatch:"+request.id
				var driver: Dictionary=sim.by_id[v.driver]
				driver.known_locations[key]={"position":bay.approach[0],"source":"dispatch","timestamp":now,"confidence":1.0}
				driver.social_target=key; driver.group_on_foot=false; v.boarding_stop=false
				request["progress_position"]=v.position; request["progress_time"]=now; request["progress_remaining"]=INF; request["progress_revision"]=Map.navigation_revision; request["recovery_attempted"]=false
				unit.state="EN_ROUTE"; _transition(request,"DISPATCHED","Both officers boarded; physical travel begins")
		elif request.state=="DISPATCHED":
			request.eta=maxf(0,float(request.eta)-seconds); unit.eta=request.eta
			if request.get("progress_revision",-1)!=Map.navigation_revision:
				request.progress_remaining=INF; request.progress_revision=Map.navigation_revision; request.progress_time=now
			if v.route.size()>1:
				var remaining: float=Routes.remaining_distance({"position":v.position,"route":v.route,"route_index":v.route_index})
				if remaining<float(request.get("progress_remaining",INF))-10:
					request.progress_remaining=remaining; request.progress_time=now
			if v.get("traffic_light","")=="RED": request.progress_time=now

			var stalled: float=now-float(request.get("progress_time",now))
			if stalled>float(sim.cognition.config.stuck_seconds) and not request.get("recovery_attempted",false):
				request.recovery_attempted=true; v.next_route=0; v.destination=""
				request.pending_reason="Road obstruction: recalculating or reversing where safe"
				if v.speed<=1: sim.driving.begin_reverse(v)
			if stalled>float(sim.cognition.config.abandon_seconds) and v.speed<=1:
				if not sim.driving.safe_disembark(v,sim.by_id[v.driver]): request.pending_reason="Awaiting safe pull-over or access clearance"

			if v.get("driving_mode","")=="ON_FOOT" or sim.by_id[v.driver].get("group_on_foot",false):
				request.pending_reason="Patrol route obstructed; officers continuing on foot"
				v.boarding_stop=true
				if v.speed<=1:
					for id in unit.officers: sim.leave(v,sim.by_id[id])
					unit.state="ON_FOOT"; _transition(request,"ARRIVED","Vehicle safely stopped; crew continues via pedestrian route")
		elif request.state in ["ARRIVED","DEPLOYING","REMOVING"]:
			var at_site:=true
			for id in unit.officers:
				var a: Dictionary=sim.by_id[id]
				if not _walk(a,officer_position(request,unit.officers.find(id)),seconds): at_site=false
			if not at_site: continue
			if request.state=="ARRIVED":
				if request.kind=="evacuation_task":
					unit.state="ON_SCENE"; _transition(request,"ACTIVE","Both officers physically reached evacuation task position"); continue
				request.work_started=now
				if request.block!="" and reason_active(request):
					for b in sim.blocks:
						if b.id==request.block: b.unmanaged=false; b.managed_by=unit.officers[0]; b.officer_ids=unit.officers.duplicate(); b.unit_id=unit.id
					unit.state="ON_SCENE"; _transition(request,"ACTIVE","Replacement crew physically took over existing barrier"); continue
				_transition(request,"DEPLOYING","Both officers reached deployment positions")
			var removing: bool=request.state=="REMOVING"
			for i in range(unit.officers.size()): sim.by_id[unit.officers[i]].police_animation="removing_barrier" if removing else "placing_barrier" if i==0 else "deploying_cones"
			if request.work_started<0: request.work_started=now
			if now-float(request.work_started)<float(config.removal_seconds if removing else config.deployment_seconds): continue
			if removing:
				if request.block!="": sim.remove_block(request.block,request.id)
				_transition(request,"REMOVED",request.removal_reason); unit.state="RETURNING"
			else:
				if not sim.authorities._shelter_access_preserved(request.edge) or not sim.authorities._emergency_access_preserved(request.edge,request.evidence.get("hazard_position",request.position)):
					request_removal(request.id,"Access no longer safe for deployment"); continue
				var block: Dictionary=sim.create_block(sim.by_id[unit.officers[0]],request.kind,Map.roads[request.edge],request.position,0,request.rationale,request.evidence,true,request.id)
				if block.is_empty(): continue
				block.unit_id=unit.id; block.officer_ids=unit.officers.duplicate(); block.hazard_id=request.evidence.get("hazard_id",""); block.hazard_kind=request.evidence.get("hazard_kind","")
				request.block=block.id; unit.state="ON_SCENE"; _transition(request,"ACTIVE","Barriers deployed by arrived officers")
		elif request.state=="ACTIVE" and (request.kind!="evacuation_task" or request.get("task","") in ["secure_intersection","emergency_access"]): _instruct(request,unit)
	for unit in units:
		if unit.state!="RETURNING": continue
		var v:=vehicle(unit); var ready:=true
		if not crew_available(unit,str(request_for(unit.request).get("evidence",{}).get("hazard_id",""))):
			var task:=request_for(unit.request)
			if not task.is_empty(): task.pending_reason="Return crew/vehicle unavailable; release to normal emergency response without moving missing crew"
			_release(unit); continue
		for id in unit.officers:
			var a: Dictionary=sim.by_id[id]
			if a.get("riding","")==v.id: continue
			if _walk(a,v.position,seconds): sim.board(v,a)
			if a.get("riding","")!=v.id: ready=false
		if ready: _release(unit)

func vehicle_arrived(v: Dictionary, target: String) -> bool:
	if not target.begins_with("police_dispatch:"): return false
	var request:=request_for(target.trim_prefix("police_dispatch:"))
	if request.is_empty(): return false
	var unit:=unit_for(request.unit)
	if unit.is_empty() or unit.vehicle!=v.id or request.state!="DISPATCHED": return false
	var bay: Dictionary=request.parking_bay
	if v.position.distance_to(bay.position)>5: return false
	bay.occupied_by=v.id; v.parking_bay=bay.id; v.parking_heading=bay.heading
	v.parking_exit=bay.approach.duplicate(); v.parking_exit.reverse()
	v.speed=0; v.status="PARKED"; v.destination=""
	sim.by_id[v.driver].social_target=""
	for id in unit.officers: sim.leave(v,sim.by_id[id])
	unit.state="ON_FOOT"; _transition(request,"ARRIVED","Patrol physically reached its reserved parking bay")
	return true

func authorizes(request_id: String, issuer: Dictionary, edge: int) -> bool:
	var request:=request_for(request_id)
	if request.is_empty() or request.state!="DEPLOYING" or request.edge!=edge or not reason_active(request): return false
	var unit:=unit_for(request.unit)
	if unit.is_empty() or issuer.id!=unit.officers[0] or not crew_available(unit,str(request.evidence.get("hazard_id",""))): return false
	if vehicle(unit).speed>1 or sim.manager.elapsed_seconds-float(request.work_started)<float(config.deployment_seconds): return false
	for id in unit.officers:
		var a: Dictionary=sim.by_id[id]
		if a.get("riding","")!="" or a.position.distance_to(officer_position(request,unit.officers.find(id)))>float(config.arrival_radius): return false
	return true

func request_removal(id: String, reason: String) -> bool:
	var request:=request_for(id)
	if request.is_empty() or request.state=="REMOVED": return false
	request.removal_reason=reason
	if request.state in ["REQUESTED","EVALUATED"]:
		if request.block!="": return true
		_transition(request,"REMOVED",reason); return true
	if request.state=="ASSIGNED":
		if request.block!="": return true
		var unit:=unit_for(request.unit)
		if not unit.is_empty(): _release(unit)
		_transition(request,"REMOVED",reason); return true
	if request.state=="DISPATCHED": request["remove_after_arrival"]=true; return true
	if request.kind=="evacuation_task":
		var unit:=unit_for(request.unit)
		if not unit.is_empty(): unit.state="RETURNING"
		_transition(request,"REMOVED",reason); return true
	if request.state!="REMOVING": request.work_started=-1.0; _transition(request,"REMOVING",reason)
	return true

func _release(unit: Dictionary) -> void:
	for id in unit.officers:
		var a: Dictionary=sim.by_id[id]
		a.police_unit_busy=false; a.police_animation=""
		a.erase("police_walk_route"); a.erase("police_walk_target")
		if a.duty_status not in ["DESERTED","RESCUING_FAMILY"]:
			a.duty_status="ON_DUTY"; a.duty_task="traffic patrol and emergency readiness"; a.social_target=a.get("police_saved_target","")
			a.group_on_foot=a.get("police_saved_group_on_foot",false); a.routine_use_vehicle=a.get("police_saved_vehicle_routine",false)
			if unit.state=="RETURNING" and a.get("riding","")==unit.vehicle:
				a.group_on_foot=false
				if sim.manager.phase=="LIVING": a.routine="REST_IN_CAR"; a.routine_until=sim.manager.elapsed_seconds+2; a.social_target=""
		a.next_rule_decision=sim.manager.elapsed_seconds
	var request:=request_for(unit.request)
	if not request.is_empty() and request.has("parking_bay") and request.parking_bay.occupied_by=="POLICE:"+unit.id: request.parking_bay.occupied_by=""
	unit.state="AVAILABLE"; unit.request=""; unit.eta=0

func _instruct(request: Dictionary, unit: Dictionary) -> void:
	if sim.manager.elapsed_seconds<float(request.next_instruction): return
	request.next_instruction=sim.manager.elapsed_seconds+float(config.instruction_interval)
	var alternative: int=-1
	for edge in sim.authorities._adjacent_edges(int(request.edge)):
		if not Map.roads[edge].get("closed",false) and not sim.authorities._edge_has_active_block(edge): alternative=edge; break
	request["alternative_edge"]=alternative
	for i in range(unit.officers.size()): sim.by_id[unit.officers[i]].police_animation="directing_traffic" if i==0 else "pointing_route" if alternative>=0 else "communicating"
	var officer: Dictionary=sim.by_id[unit.officers[0]]
	for a in sim.manager.agents:
		if a.role!="Civilian" or a.health<=0 or a.state in ["SHELTERED","SAFE","EXPOSED"] or a.get("indoor_id","")!="" or absf(float(a.get("transport_height",0))-float(officer.get("transport_height",0)))>3: continue
		if not preload("res://scripts/agent_perception.gd").visible(officer,a.position,float(config.instruction_radius),float(a.get("transport_height",0))): continue
		if a.position.distance_to(request.position)>float(config.instruction_radius): continue
		a["police_instruction"]={"officer":officer.id,"request":request.id,"message":"Road %d restricted; use open road %d"%[request.edge,alternative] if alternative>=0 else "Restricted road; wait for an accessible alternative","alternative_edge":alternative,"timestamp":sim.manager.elapsed_seconds,"confidence":float(a.authority_trust)/100}
		if float(a.authority_trust)>=30:
			if not a.has("known_traffic"): a.known_traffic={}
			a.known_traffic[str(request.edge)]=sim.manager.elapsed_seconds
			a.force_route_replan=true
			if a.get("riding","")!="":
				for v in sim.vehicles:
					if v.driver==a.id: v.next_route=0; v.destination=""
			sim.manager.emergency.reconsider(a,"Police traffic redirection")

func snapshot() -> Dictionary:
	return {"units":units,"requests":requests,"stations":stations}

func director_text() -> String:
	var text: String="\nPOLICE UNITS: %d / REQUESTS: %d\nStations: %s\n"%[units.size(),requests.size(),str(stations)]
	for unit in units: text+="%s / %s / crew %s / vehicle %s / request %s / ETA %.0fs / %s\n"%[unit.id,unit.state,str(unit.officers),unit.vehicle,unit.request,float(unit.eta),str(unit.position)+" / station "+str(unit.station)+" / available "+str(unit.get("available",false))]
	for r in requests.slice(-8): text+="%s / %s / edge %d / unit %s / %.0fs\n%s\n%s\n"%[r.id,r.state,r.edge,r.unit,float(r.eta),r.rationale,r.pending_reason]
	return text

func controls_vehicle(v: Dictionary) -> bool:
	if v.kind!="Civilian": return false # Registered emergency services retain access.
	var nearest: Dictionary=Map.nearest_edge(v.position,true,float(v.get("height",0)))
	if nearest.is_empty(): return false
	var segment: int=Map.roads.find(nearest.edge)
	for r in requests:
		if r.kind=="evacuation_task" and r.get("task","") not in ["secure_intersection","emergency_access"]: continue
		if r.edge!=segment: continue
		if r.state not in ["ARRIVED","DEPLOYING","ACTIVE","REMOVING"]: continue
		var unit:=unit_for(r.unit)
		if unit.is_empty(): continue
		var officer: Dictionary=sim.by_id[unit.officers[0]]
		if officer.get("riding","")!="" or officer.position.distance_to(r.position)>float(config.instruction_radius): continue
		var control_point: Vector2=r.position
		if r.kind=="evacuation_task":
			var road: Dictionary=Map.roads[r.edge]; var best:=INF
			for i in range(1,road.points.size()):
				var projected: Vector2=Geometry2D.get_closest_point_to_segment(r.position,road.points[i-1],road.points[i])
				if projected.distance_to(r.position)<best: best=projected.distance_to(r.position); control_point=projected
		var delta: Vector2=control_point-v.position
		if delta.dot(Vector2.from_angle(float(v.heading)))>0 and delta.length()<v.speed*v.speed/(2*v.braking)+65:
			officer.police_animation="stopping_vehicle"
			return true
	return false

func inspection(id: String) -> String:
	var r:=request_for(id)
	if r.is_empty(): return director_text()
	var text: String="%s / %s\nReason: %s\nRoad: %d / position: %s\nUnit: %s / ETA: %.0fs\nRoad distance: %.0f / foot distance: %.0f\nBarrier: %s\nPending: %s\nEvidence: %s\n"%[r.id,r.state,r.rationale,r.edge,str(r.position),r.unit,float(r.eta),float(r.get("road_distance",0)),float(r.get("foot_distance",0)),r.block,r.pending_reason,str(r.evidence)]
	for item in r.history: text+="%.1fs %s: %s\n"%[item.time,item.state,item.reason]
	return text

func officer_position(request: Dictionary, index: int) -> Vector2:
	if request.kind=="evacuation_task": return request.position+Vector2(index*12,0)
	var edge: Dictionary=Map.roads[request.edge]
	var tangent: Vector2=Convention.edge_tangent(edge,request.position)
	return request.position+Convention.right(tangent)*maxf(float(edge.width)*.5+12,60)+tangent*(index*18-9)

func authorizes_removal(id: String) -> bool:
	var r:=request_for(id)
	if r.is_empty() or r.state!="REMOVING" or float(r.work_started)<0 or sim.manager.elapsed_seconds-float(r.work_started)<float(config.removal_seconds): return false
	var unit:=unit_for(r.unit)
	if unit.is_empty() or not crew_available(unit,str(r.evidence.get("hazard_id",""))): return false
	for i in range(unit.officers.size()):
		var a: Dictionary=sim.by_id[unit.officers[i]]
		if a.get("riding","")!="" or a.position.distance_to(officer_position(r,i))>float(config.arrival_radius): return false
	return true

func request_task(operation: String, task: String, position: Vector2) -> Dictionary:
	var key: String=operation+":"+task
	for r in requests:
		if r.get("task_key","")==key and r.state!="REMOVED": return r
	if requests.filter(func(r):return r.state!="REMOVED").size()>=int(config.max_requests): return {}
	var evidence: Dictionary={"hazard_kind":"POLICE_SHELTER_EVACUATION","hazard_id":operation}
	if not reason_active({"evidence":evidence}) or not Map.clear_point(position,4): return {}
	sequence+=1
	var nearest: Dictionary=Map.nearest_edge(position,true,0)
	if nearest.is_empty(): return {}
	var r: Dictionary={"id":"EVT%04d"%sequence,"kind":"evacuation_task","task":task,"task_key":key,"operation":operation,"edge":Map.roads.find(nearest.edge),"position":position,"rationale":"Organized evacuation: "+task,"evidence":evidence,"state":"REQUESTED","unit":"","block":"","created":sim.manager.elapsed_seconds,"changed":sim.manager.elapsed_seconds,"history":[],"pending_reason":"","eta":0.0,"next_instruction":0.0,"work_started":-1.0,"removal_reason":""}
	requests.append(r); _transition(r,"REQUESTED","Evacuation command task received"); _transition(r,"EVALUATED","Awaiting reachable two-officer patrol")
	return r

func _parking_access_clear(v: Dictionary, bay: Dictionary) -> bool:
	var collision=preload("res://scripts/vehicle_collisions.gd")
	var probe: Dictionary=v.duplicate()
	for i in range(1,bay.approach.size()):
		var a: Vector2=bay.approach[i-1]; var b: Vector2=bay.approach[i]
		if a.is_equal_approx(b): continue
		probe.heading=(b-a).angle()
		for other in sim.vehicles:
			if other.id==v.id or other.status=="REMOVED" or other.speed>1: continue
			var p: Vector2=collision.body_position(other)
			if not collision.contact(probe,a,b,other,p,p).is_empty(): return false
	return true
