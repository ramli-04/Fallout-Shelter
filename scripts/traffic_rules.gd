extends RefCounted
const Convention=preload("res://scripts/traffic_conventions.gd")
## Local driving perception and bounded tactical AI. All distances use simulation units.
const Map=preload("res://scripts/city_map.gd")
const SAT=preload("res://scripts/vehicle_collisions.gd")
const Runtime=preload("res://scripts/vehicle_runtime.gd")
const Choices=preload("res://scripts/spontaneous_actions.gd")
var settings: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/traffic_rules.json"))
var ai_config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://config/openjev.json"))
var _social: WeakRef
var social: RefCounted:
	get: return _social.get_ref() if _social!=null else null
var pending: Dictionary={}
var generation:=0
var status:="NOT_QUERIED"
var completed:=0
var fallbacks:=0
var next_wall_try:=0
var priority_until:=-1.0

func initialize(owner_social: RefCounted) -> void:
	close(); _social=weakref(owner_social); settings=JSON.parse_string(FileAccess.get_file_as_string("res://resources/traffic_rules.json"))
	Map.traffic_signals.clear(); Map.signal_settings=settings; Map.traffic_time=0
	completed=0; fallbacks=0; status="NOT_QUERIED"; next_wall_try=0
	settings.ai_enabled=social.manager.get_meta("driving_ai",settings.ai_enabled)
	settings.emergency_escape_enabled=social.manager.get_meta("pavement_escape",settings.emergency_escape_enabled)
	for edge in Map.roads:
		if edge.get("elevated",false) or edge.get("ramp",false): continue
		for id in [edge.from,edge.to]:
			if Map.graph.get_point_connections(id).size()<3: continue
			if not Map.traffic_signals.has(id): Map.traffic_signals[id]={"position":Map.graph.get_point_position(id),"offset":fmod(id*7.13,46.0),"approaches":[]}
			var points: PackedVector2Array=edge.points
			var outward: Vector2=(points[1]-points[0]).normalized() if id==edge.from else (points[-2]-points[-1]).normalized()
			Map.traffic_signals[id].approaches.append({"tangent":-outward,"width":edge.width,"sidewalk":edge.sidewalk})

static func light(signal_record: Dictionary, tangent: Vector2, now: float, config: Dictionary) -> String:
	if signal_record.get("enabled",true)==false: return "NONE"
	var green: float=config.get("green_seconds",18.0)
	var amber: float=config.get("amber_seconds",3.0)
	var clearance: float=config.get("all_red_seconds",2.0)
	var half_cycle: float=green+amber+clearance
	var clock: float=fposmod(now+float(signal_record.get("offset",0)),half_cycle*2)
	var axis: int=0 if absf(tangent.x)>=absf(tangent.y) else 1
	if clock>=half_cycle: clock-=half_cycle; axis=1-axis
	if axis!=0: return "RED"
	return "GREEN" if clock<green else "AMBER" if clock<green+amber else "RED"

static func lane_offset(edge: Dictionary, passing: bool = false) -> float:
	var lanes_per_direction: int=maxi(1,int(int(edge.get("lanes",2))/2.0))
	var width: float=float(edge.width)/(lanes_per_direction*2)
	return width*.5 if passing else float(edge.width)*.5-width*.5

func road_for(v: Dictionary) -> Dictionary:
	# Actual projection is refreshed per vehicle, avoiding a full network scan per substep.
	if social.manager.elapsed_seconds>=float(v.get("rules_edge_due",-1)) or not v.has("rules_edge"):
		v.rules_edge=Map.nearest_edge(v.position,true,float(v.get("height",0))).edge
		v.rules_edge_due=social.manager.elapsed_seconds+.4
	return v.rules_edge

func lane_clear(v: Dictionary, edge: Dictionary, tangent: Vector2, offset: float, forward: float, rear: float) -> bool:
	var normal:=Convention.right(tangent)
	var target: Vector2=v.position+normal*offset
	for other in social.traffic.nearby_vehicles(target,maxf(forward,rear)+100):
		if other.id==v.id or other.status=="REMOVED" or absf(float(other.height)-float(v.height))>2: continue
		var delta: Vector2=SAT.body_position(other)-target
		var along: float=delta.dot(tangent)
		var reach: float=(v.width+other.width)*.5+5
		if absf(delta.dot(normal))>reach: continue
		# Include fast vehicles approaching from behind, rather than checking only vacancies.
		var closing: float=maxf(0,float(other.speed)-float(v.speed))*2.5
		if along>-rear-closing and along<forward+(v.length+other.length)*.5: return false
	return true

func sweep_clear(v: Dictionary, start: Vector2, finish: Vector2, allow_curb: bool = false) -> bool:
	social.traffic.ensure_spatial(social)
	var probe: Dictionary=v.duplicate(); probe.width+=5; probe.length+=6
	if allow_curb: probe.curb_clearance=.32
	var search_center: Vector2=(start+finish)*.5
	var search_radius: float=start.distance_to(finish)*.5+maxf(probe.length,probe.width)+80
	for other in social.traffic.nearby_vehicles(search_center,search_radius):
		if other.id==v.id or other.status=="REMOVED": continue
		var other_start: Vector2=SAT.body_position(other)
		var other_finish: Vector2=other_start+SAT.direction(other)*float(other.speed)*.8
		if not SAT.contact(probe,start,finish,other,other_start,other_finish).is_empty(): return false
	if v.height<3:
		for rect in Map.static_obstacles_near(SAT.swept_bounds(probe,start,finish)):
			if not Runtime.static_contact(probe,start,finish,rect).is_empty(): return false
	for block in social.blocks:
		if block.kind in social.EMERGENCY_PASS and v.kind!="Civilian": continue
		if block.active and block.kind!="emergency_lane" and absf(float(block.height)-float(v.height))<3 and not Runtime.block_contact(probe,start,finish,block).is_empty(): return false
	for a in social.traffic.nearby_pedestrians(search_center,search_radius):
		if a.get("riding","")!="" or a.get("indoor_id","")!="" or a.state in ["SHELTERED","SAFE","EXPOSED"]: continue
		if absf(float(a.get("transport_height",0))-float(v.height))>3: continue
		# Protect a pedestrian's near-future movement envelope as well as their current point.
		var radius: float=9+float(a.get("movement_speed",0))*.8
		if not Runtime.static_contact(probe,start,finish,Rect2(a.position-Vector2.ONE*radius,Vector2.ONE*radius*2)).is_empty(): return false
	return social.traffic.physics_query(probe,start,finish).is_empty()

func can_pass(v: Dictionary, edge: Dictionary, tangent: Vector2) -> bool:
	social.traffic.ensure_spatial(social)
	if edge.get("no_overtaking",false): return false
	if int(edge.get("lanes",2))<4 or edge.get("ramp",false) or v.get("traffic_light","")=="RED": return false
	for id in [edge.from,edge.to]:
		if Map.traffic_signals.has(id) and v.position.distance_to(Map.graph.get_point_position(id))<260: return false
	var offset: float=lane_offset(edge,true)
	if not lane_clear(v,edge,tangent,offset,maxf(180,v.speed*3),maxf(90,v.speed*1.5)): return false
	var start: Vector2=SAT.body_position(v)
	var end: Vector2=v.position+tangent*maxf(30,v.speed*.7)+Convention.right(tangent)*offset
	return sweep_clear(v,start,end)

func escape_offset(v: Dictionary, edge: Dictionary, tangent: Vector2) -> float:
	if not settings.emergency_escape_enabled or edge.get("elevated",false) or edge.get("ramp",false) or v.height>1: return NAN
	var offset: float=float(edge.width)*.5+float(v.width)*.5+5
	if float(edge.sidewalk)<v.width+12: return NAN
	for id in [edge.from,edge.to]:
		if Map.traffic_signals.has(id) and v.position.distance_to(Map.graph.get_point_position(id))<180: return NAN
	if not lane_clear(v,edge,tangent,offset,maxf(90,v.speed*1.5),60): return NAN
	var start: Vector2=SAT.body_position(v)
	var finish: Vector2=v.position+tangent*maxf(45,v.speed*.7)+Convention.right(tangent)*offset
	if not sweep_clear(v,start,finish,true): return NAN
	# Also reserve room beyond the lane change, so the escape never ends inside a wall.
	if not sweep_clear(v,finish,finish+tangent*100,true): return NAN
	return offset

func begin_action(v: Dictionary, action: String, provider: String) -> bool:
	social.traffic.ensure_spatial(social)
	if social.replaying or social.manager.phase not in ["LIVING","EVACUATION","BOMB_FALL"] or v.status in ["PARKED","ACCIDENT","REMOVED","DESTROYED"]: return false
	var edge: Dictionary=road_for(v)
	var tangent:=SAT.direction(v)
	if action=="overtake":
		if float(v.get("slow_wait",0))<float(settings.passing_patience_seconds) or float(v.get("lead_gap",9999))>400 or not can_pass(v,edge,tangent): return false
		v.driving_mode="PASSING"; v.pass_until=social.manager.elapsed_seconds+6.0
	elif action=="evade_pavement":
		if not v.get("imminent_collision",false): return false
		var offset: float=escape_offset(v,edge,tangent)
		if not is_finite(offset): return false
		v.driving_mode="EVADING"; v.escape_offset=offset; v.escape_until=social.manager.elapsed_seconds+2.5
	elif action=="brake": v.ai_brake_until=social.manager.elapsed_seconds+1
	elif action!="keep_lane": return false
	v.driving_provider=provider; v.last_driving_action=action
	social.emit_event("vehicle.driving_decision",v.id,{"action":action,"provider":provider,"mode":v.get("driving_mode","KEEP_LANE")})
	return true

func request_advice(v: Dictionary, can_overtake: bool) -> void:
	if social==null or social.replaying or social.manager.phase not in ["LIVING","EVACUATION","BOMB_FALL"]: return
	if not settings.ai_enabled or not social.manager.ai_config.enabled or Time.get_ticks_msec()<next_wall_try: return
	if social.manager.elapsed_seconds<float(v.get("next_driving_ai",0)): return
	if can_overtake: priority_until=social.manager.elapsed_seconds+.5
	if not pending.is_empty() or not social.daily.spontaneous.pending.is_empty(): return
	priority_until=-1.0
	v.next_driving_ai=social.manager.elapsed_seconds+float(settings.ai_interval_seconds)
	var allowed: Dictionary={"keep_lane":"Follow the slow vehicle at a safe distance","brake":"Reduce speed and increase the following gap"}
	if can_overtake: allowed.overtake="Pass the slow vehicle using a clear adjacent lane travelling in the same direction"
	var req:=HTTPRequest.new(); req.timeout=float(ai_config.timeout_seconds)
	social.manager.ai_bridge.add_child(req); pending[v.id]=req
	var token: int=generation; var run_id: String=social.manager.ai_bridge.run_id
	# Only local road perception: never other agents' destinations, hidden events or world truth.
	var state: Dictionary={"country":"MA","traffic_side":"right","passing_side":"left","speed_mps":v.speed/10,"speed_limit_mps":v.get("speed_limit",70)/10,"lead_speed_mps":v.get("lead_speed",0)/10,"gap_metres":v.get("lead_gap",0)/10,"same_direction_passing_lane_clear":can_overtake,"traffic_signal":v.get("traffic_light","NONE"),"waiting_seconds":v.get("slow_wait",0)}
	var body: Dictionary={"model":ai_config.model,"state":JSON.stringify(state),"questions":{"action":{"type":"choice","instructions":"Choose a cautious tactical driving action. Pass a persistently slow vehicle when the adjacent same-direction lane is confirmed clear. Obey signals and protect pedestrians.","criteria":allowed}}}
	req.request_completed.connect(func(result,code,_headers,bytes):
		if pending.get(v.id)==req: pending.erase(v.id)
		req.queue_free()
		if token!=generation or social==null or run_id!=social.manager.ai_bridge.run_id: return
		if result==HTTPRequest.RESULT_SUCCESS and code==200:
			var choice: String=Choices.parse_choice(JSON.parse_string(bytes.get_string_from_utf8()),allowed)
			if choice!="": status="CONNECTED"; completed+=1; begin_action(v,choice,"OPENJEV"); return
		status="UNAVAILABLE"; fallbacks+=1; next_wall_try=Time.get_ticks_msec()+5000
		if can_overtake: begin_action(v,"overtake","RULE_FALLBACK"))
	var headers:=PackedStringArray(["Content-Type: application/json"])
	if OS.get_environment("OPENJEV_API_KEY")!="": headers.append("Authorization: Bearer "+OS.get_environment("OPENJEV_API_KEY"))
	if req.request(ai_config.endpoint,headers,HTTPClient.METHOD_POST,JSON.stringify(body))!=OK:
		pending.erase(v.id); req.queue_free(); status="UNAVAILABLE"; fallbacks+=1; next_wall_try=Time.get_ticks_msec()+5000

func block_requires_stop(v: Dictionary, block: Dictionary) -> bool:
	# An accident closure still disconnects the routing graph. A vehicle already
	# committed to an emergency escape can pass physically outside the carriageway.
	# Police restrictions and barriers never acquire this exception.
	if block.kind!="accident" or v.get("driving_mode","") not in ["EVADING","RETURNING"]: return true
	var edge: Dictionary=road_for(v)
	return float(v.get("lane_offset",0))-float(v.width)*.5<=float(edge.width)*.5+1

func junction_limit(v: Dictionary, edge: Dictionary, tangent: Vector2, desired: float, seconds: float) -> Dictionary:
	var result: Dictionary={"speed":desired,"travel":INF}
	v.traffic_light="NONE"
	if edge.get("elevated",false) or edge.get("ramp",false): return result
	var best:=-1; var distance:=INF
	for id in [edge.from,edge.to]:
		if not Map.traffic_signals.has(id): continue
		var delta: Vector2=Map.graph.get_point_position(id)-v.position
		var along: float=delta.dot(tangent)
		if along>0 and absf(delta.dot(tangent.orthogonal()))<80 and along<distance: best=id; distance=along
	if best<0: return result
	var stop_distance: float=float(edge.width)*.5+102+v.length*.5
	var gap: float=maxf(0,distance-stop_distance)
	var light_state: String=light(Map.traffic_signals[best],tangent,social.manager.elapsed_seconds,settings)
	v.traffic_light=light_state
	# Some alerted drivers disregard signals and priority rules. They still
	# perceive nearby vehicles/pedestrians and remain subject to physical impacts.
	if alert_urgency(v)>.58:
		v.driving_reason="ALERT_IGNORE_SIGNAL" if light_state in ["RED","AMBER"] else "ALERT_IGNORE_PRIORITY"
		return result
	if v.get("committed_junction",-1)==best: return result
	# A vehicle already beyond the stop line clears the intersection instead of freezing.
	if distance<stop_distance-3: v.committed_junction=best; return result
	var stopping: float=v.speed*v.speed/(2*maxf(1,v.braking))
	var hold: bool=light_state=="RED" or (light_state=="AMBER" and gap>stopping+4)
	if light_state=="NONE":
		var control: String=str(edge.get("junction_control","priority_right"))
		if control=="stop":
			if gap<5 and v.speed<=.1: v.stop_checked_junction=best
			if v.get("stop_checked_junction",-1)!=best: hold=true
		for other in social.traffic.nearby_vehicles(Map.graph.get_point_position(best),250):
			if other.id==v.id or other.status in ["PARKED","REMOVED","ACCIDENT"]: continue
			var relative: Vector2=SAT.body_position(other)-SAT.body_position(v)
			var approaching: bool=(Map.graph.get_point_position(best)-other.position).normalized().dot(SAT.direction(other))>.3
			if approaching and other.speed>1 and ((relative.dot(Convention.right(tangent))>5 and control!="priority") or control=="yield"): hold=true
	# Left turns yield to approaching oncoming traffic when movements conflict.
	var outgoing: Vector2=exit_direction(v,Map.graph.get_point_position(best),tangent,float(edge.width)*.5)
	if tangent.cross(outgoing)<-.2:
		for other in social.traffic.nearby_vehicles(Map.graph.get_point_position(best),220):
			if other.id!=v.id and other.status not in ["PARKED","REMOVED","ACCIDENT"] and SAT.direction(other).dot(tangent)<-.6 and other.speed>1: hold=true
	var junction_owner: String=social.junction_reservations.get(best,"")
	if not hold and gap<maxf(55,stopping+15):
		if junction_owner!="" and junction_owner!=v.id: hold=true
		else:
			# Do not enter if traffic on the far side leaves no space to clear the box.
			for other in social.traffic.nearby_vehicles(Map.graph.get_point_position(best),stop_distance+v.length+100):
				if other.id==v.id or other.status in ["REMOVED","PARKED"] or absf(float(other.height)-float(v.height))>2: continue
				var delta: Vector2=other.position-Map.graph.get_point_position(best)
				if delta.dot(tangent)>20 and delta.dot(tangent)<stop_distance+v.length and absf(delta.dot(tangent.orthogonal()))<v.width+10 and other.speed<12: hold=true; break
			if not hold: social.junction_reservations[best]=v.id
	if hold:
		result.speed=minf(desired,sqrt(maxf(0,2*v.braking*gap)))
		result.travel=gap
		v.driving_reason="RED_LIGHT" if light_state=="RED" else "AMBER_STOP" if light_state=="AMBER" else "YIELD_JUNCTION"
	elif gap<=maxf(2,v.speed*seconds): v.committed_junction=best
	return result

static func exit_direction(v: Dictionary, junction: Vector2, fallback: Vector2, radius: float) -> Vector2:
	var route: PackedVector2Array=v.route
	var closest: int=int(v.route_index)
	if closest>=route.size(): return fallback
	for i in range(closest,route.size()):
		if route[i].distance_to(junction)<route[closest].distance_to(junction): closest=i
	for i in range(closest+1,route.size()):
		if route[i].distance_to(junction)>radius: return (route[i]-junction).normalized()
	return fallback

func begin_reverse(v: Dictionary) -> bool:
	if v.speed>1 or float(v.height)>1 or v.status in ["ACCIDENT","DESTROYED","REMOVED"]: return false
	var edge: Dictionary=road_for(v)
	if edge.get("elevated",false) or edge.get("ramp",false) or edge.kind=="highway": return false
	for id in [edge.from,edge.to]:
		if v.position.distance_to(Map.graph.get_point_position(id))<float(edge.width)+90: return false
	var start: Vector2=SAT.body_position(v)
	var finish: Vector2=start-SAT.direction(v)*float(settings.get("reverse_distance",24.0))
	if not sweep_clear(v,start,finish): return false
	v.recovery_mode="REVERSING"; v.reverse_remaining=float(settings.get("reverse_distance",24.0)); v.speed=0
	v.driving_reason="REVERSE_TO_CLEAR"; v.last_driving_action="reverse"
	return true

func advance_recovery(v: Dictionary, seconds: float) -> bool:
	if v.get("recovery_mode","")=="PULLING_OVER":
		var finish: Vector2=v.position.move_toward(v.pull_over_target,float(settings.get("pull_over_speed",6.0))*seconds)
		if not sweep_clear(v,v.position,finish,true):
			v.recovery_mode="STOPPED"; v.driving_reason="NO_SAFE_PARKING"; return true
		v.position=finish; v.body_position=finish
		for id in v.passengers: social.by_id[id].position=finish
		if finish.distance_to(v.pull_over_target)<.1:
			v.recovery_mode="STOPPED"
			safe_disembark(v,social.by_id[v.driver])
		return true
	if v.get("recovery_mode","")!="REVERSING": return false
	var distance: float=minf(float(v.reverse_remaining),float(settings.get("reverse_speed",8.0))*seconds)
	var offset: Vector2=-SAT.direction(v)*distance
	if not sweep_clear(v,SAT.body_position(v),SAT.body_position(v)+offset):
		v.recovery_mode="STOPPED"; v.driving_reason="REVERSE_OBSTRUCTED"; return true
	v.position+=offset; v.body_position=SAT.body_position(v)+offset
	v.reverse_remaining-=distance; v.speed=0; v.status="BLOCKED"
	for id in v.passengers: social.by_id[id].position=v.position
	if v.reverse_remaining<=.001: v.recovery_mode="STOPPED"; v.next_route=0
	return true

func safe_disembark(v: Dictionary, driver: Dictionary) -> bool:
	if v.speed>1 or float(v.height)>1: return false
	var edge: Dictionary=road_for(v)
	if edge.get("elevated",false) or edge.get("ramp",false) or edge.kind=="highway": return false
	var nearest: Dictionary=Map.nearest_edge(v.position,true,float(v.height))
	var tangent:=SAT.direction(v)
	var exit_point: Vector2=nearest.point+Convention.right(tangent)*(float(edge.width)*.5+14)
	if not Map.clear_point(exit_point,4): return false
	var foot_point: Vector2=exit_point+Convention.right(tangent)*(float(v.width)*.5+6)
	if not Map.clear_point(foot_point,4): return false
	# Require a short unobstructed door-to-footway path; no moving-vehicle teleport.
	if SAT.body_position(v).distance_to(exit_point)>float(edge.width)+40 or not Map.clear_segment(SAT.body_position(v),exit_point): return false
	for other in social.traffic.nearby_vehicles(exit_point,80):
		if other.id!=v.id and other.status!="REMOVED" and SAT.body_position(other).distance_to(exit_point)<maxf(other.width,other.length)*.5+10: return false
	if SAT.body_position(v).distance_to(exit_point)>4:
		if v.get("recovery_mode","")=="PULLING_OVER": return false
		if not sweep_clear(v,SAT.body_position(v),exit_point,true): return false
		v.position=SAT.body_position(v); v.lane_offset=0.0; v.target_lane_offset=0.0
		v.pull_over_target=exit_point; v.recovery_mode="PULLING_OVER"; v.driving_reason="SAFE_PULL_OVER"
		return false
	for id in v.passengers.duplicate():
		var passenger: Dictionary=social.by_id[id]
		if social.leave(v,passenger):
			passenger.position=foot_point; passenger.previous_position=foot_point
			passenger.group_on_foot=true; passenger.routine_use_vehicle=false
	driver.group_on_foot=true; driver.routine_use_vehicle=false
	v.status="PARKED"; v.recovery_mode="ABANDONED"; social.daily.release_destination(v)
	social.cognition._record(driver,"ABANDON_VEHICLE","UTILITY","Parked clear of traffic and reached right-side footway",social.manager.elapsed_seconds)
	if social.manager.phase in ["EVACUATION","BOMB_FALL"]: social.manager.choose_rule_destination(driver)
	return true

func plan(v: Dictionary, tangent: Vector2, desired: float, seconds: float) -> Dictionary:
	social.traffic.ensure_spatial(social)
	Map.traffic_time=social.manager.elapsed_seconds
	var edge: Dictionary=road_for(v)
	var normal:=Convention.right(tangent)
	var in_parking: bool=Runtime.parking_maneuver(v) or Map.parking_lots.any(func(lot):return lot.bounds.grow(4).has_point(v.position))
	var nearest:=Vector2.INF
	for i in range(1,edge.points.size()):
		var projected: Vector2=Geometry2D.get_closest_point_to_segment(v.position,edge.points[i-1],edge.points[i])
		if projected.distance_squared_to(v.position)<nearest.distance_squared_to(v.position): nearest=projected
	var on_road: bool=not in_parking and nearest.distance_to(v.position)<float(edge.width)*.5+12
	v.driving_reason="CRUISE"; v.imminent_collision=false; v.traffic_light="NONE"
	var cruise_offset: float=lane_offset(edge)
	v.target_lane_offset=cruise_offset if on_road else 0.0
	var edge_index: int=Map.roads.find(edge)
	if v.get("emergency_active",false) and social.blocks.any(func(block):return block.active and block.kind=="emergency_lane" and block.edge==edge_index):
		v.target_lane_offset=lane_offset(edge,true)
		v.driving_reason="EMERGENCY_LANE"
	var speed_limit: float=float(settings.highway_speed_limit) if edge.get("elevated",false) else float(settings.residential_speed_limit) if edge.kind in ["residential","grove","mountain"] else float(settings.urban_speed_limit)
	speed_limit=minf(speed_limit,maxf(0,float(edge.get("speed_limit",speed_limit))))
	var urgency:=alert_urgency(v)
	if on_road and urgency>0:
		# Seeded, persistent preferences and slow waves avoid per-frame jitter.
		var wave:=sin(social.manager.elapsed_seconds*.13+float(posmod(str(v.id).hash(),1000)))
		speed_limit=minf(float(v.max_speed),speed_limit*(1+urgency*(.30+.12*wave)))
		v.driving_reason="ALERT_URGENT" if urgency>.5 else "ALERT_CAUTIOUS"
	if not on_road: speed_limit=minf(speed_limit,18)
	v.speed_limit=speed_limit; desired=minf(desired,speed_limit)
	var stop_travel:=INF
	if on_road:
		var junction: Dictionary=junction_limit(v,edge,tangent,desired,seconds)
		desired=junction.speed; stop_travel=junction.travel
	var lead: Dictionary={}; var lead_gap:=INF
	var start: Vector2=SAT.body_position(v)
	for other in social.traffic.nearby_vehicles(start,maxf(240,v.speed*3.5+v.length)+100):
		if other.id==v.id or other.status=="REMOVED" or absf(float(other.height)-float(v.height))>2: continue
		var delta: Vector2=SAT.body_position(other)-start
		var along: float=delta.dot(tangent)
		if along<=0 or along>maxf(240,v.speed*3.5+v.length) or absf(delta.dot(normal))>(v.width+other.width)*.5+3: continue
		var gap: float=along-(v.length+other.length)*.5
		if gap<lead_gap and Map.clear_segment(start,SAT.body_position(other)): lead=other; lead_gap=gap
	v.lead_gap=lead_gap if is_finite(lead_gap) else 9999.0; v.lead_speed=lead.get("speed",0)
	if not lead.is_empty():
		var lead_forward: float=maxf(0,float(lead.speed)*SAT.direction(lead).dot(tangent))
		var available: float=maxf(0,lead_gap-float(settings.minimum_gap)*(1-.35*urgency))
		var safe: float=minf(available/(float(settings.headway_seconds)*(1-.4*urgency)),sqrt(lead_forward*lead_forward+2*v.braking*available))
		desired=minf(desired,safe)
		stop_travel=minf(stop_travel,available+lead_forward*seconds)
		if v.driving_reason=="CRUISE": v.driving_reason="FOLLOWING"
		var closing: float=maxf(0,v.speed-lead_forward)
		v.imminent_collision=closing>15 and lead_gap<closing*closing/(2*maxf(1,v.braking))+v.speed*.35
		v.slow_wait=float(v.get("slow_wait",0))+seconds if lead_forward<v.max_speed*.6 else 0.0
	else: v.slow_wait=0.0
	for a in social.traffic.nearby_pedestrians(start,maxf(100,v.speed*v.speed/(2*v.braking)+v.speed*1.2)+100):
		if a.get("riding","")!="" or a.get("indoor_id","")!="" or a.state in ["SHELTERED","SAFE","EXPOSED"]: continue
		if absf(float(a.get("transport_height",0))-float(v.height))>3: continue
		var delta: Vector2=a.position-start
		var along: float=delta.dot(tangent)-v.length*.5-10
		if along<0 or along>maxf(100,v.speed*v.speed/(2*v.braking)+v.speed*1.2): continue
		if absf(delta.dot(normal))>v.width*.5+10+float(a.get("movement_speed",0))*.35 or not Map.clear_segment(start,a.position): continue
		desired=minf(desired,sqrt(maxf(0,2*v.braking*(along-v.speed*.35)))); stop_travel=minf(stop_travel,along)
		v.driving_reason="YIELD_PEDESTRIAN"
	for other in social.traffic.nearby_vehicles(start,250):
		if other.id==v.id or not other.get("emergency_active",false) or v.get("emergency_active",false) or absf(float(other.height)-float(v.height))>2: continue
		var delta: Vector2=SAT.body_position(other)-start
		if delta.dot(tangent)<0 and delta.length()<220 and SAT.direction(other).dot(tangent)>.6 and Map.clear_segment(start,SAT.body_position(other)):
			desired=minf(desired,35); v.driving_reason="YIELD_EMERGENCY"
	var mode: String=v.get("driving_mode","KEEP_LANE")
	if on_road and v.imminent_collision and v.driving_reason!="YIELD_PEDESTRIAN" and mode not in ["EVADING","RETURNING"]:
		if begin_action(v,"evade_pavement","COLLISION_AVOIDANCE"): mode="EVADING"
	if on_road and mode=="KEEP_LANE" and v.slow_wait>=float(settings.passing_patience_seconds):
		var pass_ok: bool=can_pass(v,edge,tangent)
		request_advice(v,pass_ok)
		if pass_ok and (not settings.ai_enabled or not social.manager.ai_config.enabled or status=="UNAVAILABLE"):
			begin_action(v,"overtake","RULE_FALLBACK" if status=="UNAVAILABLE" else "DRIVING_AI"); mode=v.get("driving_mode","KEEP_LANE")
	if mode=="PASSING":
		v.target_lane_offset=lane_offset(edge,true)
		if v.get("traffic_light","")=="RED" or social.manager.elapsed_seconds>=float(v.get("pass_until",0)) or not on_road:
			v.driving_mode="RETURNING"; mode="RETURNING"
	elif mode=="EVADING":
		v.target_lane_offset=float(v.get("escape_offset",cruise_offset))
		desired=minf(desired,float(settings.pavement_max_speed)); v.driving_reason="EMERGENCY_PAVEMENT"
		if social.manager.elapsed_seconds>=float(v.get("escape_until",0)): v.driving_mode="RETURNING"; mode="RETURNING"
	if mode=="RETURNING":
		if lane_clear(v,edge,tangent,cruise_offset,100,90) and sweep_clear(v,start,v.position+tangent*maxf(20,v.speed*.7)+normal*cruise_offset,float(v.get("lane_offset",0))>float(edge.width)*.5):
			v.target_lane_offset=cruise_offset
			if absf(float(v.get("lane_offset",0))-cruise_offset)<1: v.driving_mode="KEEP_LANE"
		else: v.target_lane_offset=float(v.get("lane_offset",cruise_offset)); desired=minf(desired,25)
	var lateral: float=move_toward(float(v.get("lane_offset",0)),float(v.target_lane_offset),seconds*float(settings.lane_change_units_per_second))
	if not is_equal_approx(lateral,float(v.get("lane_offset",0))):
		var finish: Vector2=v.position+tangent*maxf(0,v.speed*seconds)+normal*lateral
		if not sweep_clear(v,start,finish,mode in ["EVADING","RETURNING"]):
			v.target_lane_offset=float(v.get("lane_offset",0)); desired=0
			if v.driving_reason!="YIELD_PEDESTRIAN": v.driving_reason="MANOEUVRE_ABORT"
	v.lane_change_rate=settings.lane_change_units_per_second
	v.curb_clearance=.32 if in_parking or mode in ["EVADING","RETURNING"] else .15
	if social.manager.elapsed_seconds<float(v.get("ai_brake_until",0)): desired=minf(desired,maxf(0,v.speed-v.braking*seconds))
	# Sharp turns need lower entry speeds; this operates before the bounded steering step.
	var turn: float=absf(wrapf(tangent.angle()-float(v.heading),-PI,PI))
	desired=minf(desired,35.0 if turn>.45 else 60.0 if turn>.18 else speed_limit)
	var driver: Dictionary=social.by_id.get(v.driver,{})
	if not driver.is_empty(): driver.driving_state={"speed_mps":v.speed/10,"speed_limit_mps":speed_limit/10,"reason":v.driving_reason,"mode":v.get("driving_mode","KEEP_LANE"),"signal":v.traffic_light,"action":v.get("last_driving_action","keep_lane"),"provider":v.get("driving_provider","DRIVING_AI")}
	return {"speed":maxf(0,desired),"travel":stop_travel}

func alert_urgency(v: Dictionary) -> float:
	if social.manager.phase not in ["EVACUATION","BOMB_FALL"]: return 0.0
	var driver: Dictionary=social.by_id.get(v.get("driver",""),{})
	var temperament:=float(posmod((str(v.id)+":"+str(social.manager.seed_value)).hash(),1000))/999.0
	return clampf(temperament*.55+float(driver.get("stress",0))*.003+float(driver.get("risk_tolerance",50))*.002,0,1)

func close() -> void:
	priority_until=-1.0
	generation+=1
	for req in pending.values():
		if is_instance_valid(req): req.cancel_request(); req.queue_free()
	pending.clear()
