extends SceneTree
const Manager=preload("res://scripts/simulation_manager.gd")
const Map=preload("res://scripts/city_map.gd")
const Routes=preload("res://scripts/road_routes.gd")
const Admission=preload("res://scripts/shelter_admission.gd")
const State=preload("res://scripts/shelter_state.gd")
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1; printerr("FAIL: "+label)
func walk_to(a: Dictionary, shelter: Dictionary) -> void:
	a.objective=shelter.id; a.state="MOVING"; a.group_on_foot=true
	a.route=Routes.plan(a.position,shelter.position); a.route_index=1
	check(not a.route.is_empty(),"real approach route exists")
	var valid:=true
	for step in range(4000):
		var before: Vector2=a.position
		var moved:=Routes.move(a,.5)
		valid=valid and a.position.distance_to(before)<=float(a.movement_speed)*.5+.001
		if moved.arrived: break
	check(valid and a.position.distance_to(shelter.position)<.01,"entrance reached through speed-bounded movement")
func run() -> void:
	var manager:=Manager.new(); root.add_child(manager); manager.load_settings(); manager.initialize_run()
	manager.set_process(false); manager.ai_bridge.set_process(false); manager.ai_config.enabled=false; manager.ai_bridge.status="DISCONNECTED"
	manager.phase="EVACUATION"
	var sim: RefCounted=manager.social
	var emergency: RefCounted=manager.emergency
	emergency.config.status_message_reach=1.0; sim.config.network_availability=1.0
	var actors: Array=manager.agents.filter(func(a):return a.role=="Civilian" and a.age>=18 and a.indoor_id=="" and a.get("riding","")=="" and a.id!="SPECIAL_I_AM_LEGEND")
	check(actors.size()>=6,"outdoor adult fixture uses existing civilians")
	if actors.size()<6: quit(1); return
	var s1: Dictionary=manager.shelter_by_id.S1
	var s2: Dictionary=manager.shelter_by_id.S2
	for shelter in [s1,s2]: shelter.capacity=1; State.project(shelter)
	var observer: Dictionary=actors[4]
	observer.has_phone=true; observer.phone.connected=true; observer.objective="S1"
	var offline: Dictionary={}
	for a in manager.agents:
		if a.role=="Civilian" and a.position.distance_to(s1.position)>float(manager.living.observation_radius) and a.id not in actors.slice(0,5).map(func(p):return p.id): offline=a; break
	offline.has_phone=false; offline.phone.connected=false
	var private_before: bool=offline.beliefs.S1.unavailable
	# Four people physically approach two shelters before competing for the final seats.
	walk_to(actors[0],s1); walk_to(actors[1],s1)
	walk_to(actors[2],s2); walk_to(actors[3],s2)
	check(manager.admit_arrival(actors[0]).is_empty(),"first real S1 arrival admitted")
	check(manager.admit_arrival(actors[2]).is_empty(),"first real S2 arrival admitted in same clock tick")
	manager.admit_arrival(actors[1]); manager.admit_arrival(actors[3])
	check(s1.occupancy==1 and s2.occupancy==1 and s1.occupant_ids.size()==1 and s2.occupant_ids.size()==1,"simultaneous full shelters never over-admit")
	check(s1.available_capacity==0 and s2.available_capacity==0 and not s1.admission_open and not s2.admission_open,"capacity projections close admissions")
	check(actors[1].shelter_id=="" and actors[3].shelter_id=="","excess arrivals do not acquire phantom occupancy")
	check(observer.objective!="S1" and observer.beliefs.S1.unavailable,"connected incoming civilian redirects when destination fills")
	check(offline.beliefs.S1.unavailable==private_before,"distant offline civilian receives no omniscient capacity update")
	check(manager.agents.any(func(a):return a.role=="Authority" and a.authority_reports.any(func(r):return r.get("subject","")=="shelter_status")),"dispatch receives shelter-status reports")
	var before_exit: Vector2=actors[0].position
	check(emergency.set_shelter_condition("S1","UNSAFE"),"shelter can become unsafe")
	emergency.tick(.1)
	check(s1.occupancy==0 and actors[0].shelter_id=="" and actors[0].position==before_exit,"unsafe shelter releases occupant only at existing exit threshold")
	check(actors[0].objective!="S1" and actors[0].state!="SHELTERED","departing occupant selects an alternative")
	emergency.set_shelter_condition("S1","SAFE")
	check(s1.admission_open and s1.available_capacity==1,"actual departure restores capacity")
	emergency.set_shelter_condition("S2","UNSAFE",false); emergency.tick(.1)
	check(s2.occupancy==1 and actors[2].shelter_id=="S2","blocked exit preserves actual occupant membership")
	emergency.set_shelter_condition("S2","UNSAFE",true); emergency.tick(.1)
	check(s2.occupancy==0 and actors[2].shelter_id=="","opening exit permits physical departure")
	emergency.set_shelter_condition("S2","SAFE")
	for belief in observer.beliefs.values(): belief.unavailable=true
	manager.choose_rule_destination(observer)
	check(observer.objective=="" and observer.state=="DECIDING","no available shelter leaves agent eligible to reconsider")
	emergency.set_shelter_condition("S1","UNSAFE"); emergency.set_shelter_condition("S1","SAFE")
	check(observer.objective=="S1" and observer.state=="MOVING","restored availability wakes waiting evacuee")
	var closed:=manager.add_emergency("shelter_closure",manager.shelter_by_id.S3.position,{"shelter_id":"S3","duration":30})
	emergency.tick(.1)
	check(not manager.shelter_by_id.S3.accessible and not manager.shelter_by_id.S3.admission_open,"shelter closure blocks access and admissions")
	emergency.clear_event(closed)
	check(manager.shelter_by_id.S3.accessible,"clearing closure restores entrance")
	var timed:=manager.add_emergency("shelter_closure",manager.shelter_by_id.S3.position,{"shelter_id":"S3","duration":.2})
	emergency.tick(.1); manager.elapsed_seconds+=.3; emergency.tick(.1)
	check(manager.shelter_by_id.S3.accessible and manager.environment_events.any(func(e):return e.event_id==timed and e.ended),"timed closure expires using simulation clock")
	var edge: Dictionary=Map.roads.filter(func(e):return not e.get("elevated",false) and not e.get("ramp",false))[0]
	var point: Vector2=edge.points[edge.points.size()/2]
	var first:=manager.add_emergency("road_closure",point,{"radius":20,"duration":20})
	var second:=manager.add_emergency("road_closure",point,{"radius":20,"duration":20})
	var revision: int=Map.navigation_revision
	emergency.tick(.1)
	check(Map.navigation_revision>revision and not Map.graph.are_points_connected(edge.from,edge.to),"road event changes actual navigation")
	check(not Map.clear_point(point,0),"road closure blocks pedestrian space")
	emergency.clear_event(first)
	check(not Map.graph.are_points_connected(edge.from,edge.to),"overlapping closure remains after one event clears")
	emergency.clear_event(second)
	check(Map.graph.are_points_connected(edge.from,edge.to),"final closure restores road connection")
	var fire:=manager.add_emergency("fire",manager.shelter_by_id.S3.position,{"shelter_id":"S3","radius":5,"duration":30,"severity":.9})
	var failure:=manager.add_emergency("infrastructure_failure",manager.shelter_by_id.S4.position,{"shelter_id":"S4","radius":5,"duration":30})
	emergency.tick(.1)
	check(manager.shelter_by_id.S3.safety_status=="UNSAFE" and not manager.shelter_by_id.S4.operational,"simultaneous fire and infrastructure failure affect different shelters")
	var warning:=manager.add_emergency("danger_zone",manager.shelter_by_id.S3.position,{"shelter_id":"S3","radius":5,"duration":30,"severity":.2})
	emergency.tick(.1)
	check(manager.shelter_by_id.S3.safety_status=="UNSAFE","weak overlapping event cannot downgrade severe danger")
	emergency.clear_event(fire); emergency.clear_event(failure)
	check(manager.shelter_by_id.S3.safety_status=="WARNING","clearing severe event retains remaining warning")
	emergency.clear_event(warning)
	var a: Dictionary=actors[5]
	var health: float=a.health
	var explosion:=manager.add_emergency("explosion",a.position,{"radius":10,"duration":2,"severity":.7})
	emergency.tick(.1)
	check(a.health<health and a.panic_level>0,"explosion affects real nearby agent health and stress")
	check(a.cognition.next_observe<=manager.elapsed_seconds,"explosion wakes local perception")
	emergency.clear_event(explosion)
	var rising:=manager.add_emergency("increasing_threat",manager.shelter_by_id.S3.position,{"shelter_id":"S3","radius":5,"duration":20,"severity":.2,"growth_per_second":.1})
	emergency.tick(.1); manager.elapsed_seconds+=5; emergency.tick(.1)
	check(manager.shelter_by_id.S3.safety_status=="UNSAFE","increasing threat escalates shelter safety")
	emergency.clear_event(rising)
	check(manager.shelters.all(func(s):return s.occupancy==s.occupant_ids.size() and s.occupancy<=s.capacity),"occupancy always reflects real admitted identities")
	var family_agent: Dictionary=a.duplicate(true)
	family_agent.force_route_replan=true
	var policy=preload("res://scripts/evacuation_decisions.gd")
	var without_family: Dictionary=policy.evaluate(family_agent,1800,manager.settings.evacuation.weights)
	family_agent.relationships["REMEMBERED_CHILD"]="child"
	family_agent.cognitive_traits.family_attachment=100
	family_agent.known_locations["REMEMBERED_CHILD"]={"position":family_agent.beliefs.S4.position,"confidence":1.0,"timestamp":manager.elapsed_seconds}
	var with_family: Dictionary=policy.evaluate(family_agent,1800,manager.settings.evacuation.weights)
	check(with_family.scores.S4.score>without_family.scores.S4.score,"private remembered family location affects shelter utility")
	check(manager.add_emergency("unknown",point,{})=="" and manager.add_emergency("fire",point,{"severity":INF})=="","invalid events rejected")
	var vehicle: Dictionary=sim.vehicles.filter(func(v):return v.status not in ["ACCIDENT","REMOVED","DESTROYED"])[0]
	var accident:=manager.add_emergency("accident",vehicle.position,{"vehicle_id":vehicle.id,"duration":20})
	emergency.tick(.1)
	check(vehicle.status=="ACCIDENT" and sim.traffic.scenes.any(func(scene):return scene.vehicle==vehicle.id),"accident event affects an existing vehicle and response scene")
	check(manager.add_emergency("accident",vehicle.position,{"vehicle_id":vehicle.id})==accident,"repeated accident notification is idempotent")
	# Local orders work in the living city without activating a nuclear countdown.
	manager.new_run(42); manager.ai_config.enabled=false; manager.set_process(false); manager.start()
	var local: Dictionary=manager.agents.filter(func(p):return p.role=="Civilian" and p.age>=18 and p.indoor_id=="" and p.get("riding","")=="" and p.id!="SPECIAL_I_AM_LEGEND")[0]
	var order:=manager.add_emergency("evacuation_order",local.position,{"radius":5,"duration":15})
	manager.advance_clock(.1)
	check(not order.is_empty() and manager.phase=="LIVING" and local.get("emergency_evacuating",false),"non-nuclear evacuation order activates local agents")
	check(not local.objective.is_empty(),"ordered civilian selects a real reachable shelter")
	var before_order_walk: Vector2=local.position
	manager.advance_clock(.5)
	check(local.position.distance_to(before_order_walk)>0 and local.position.distance_to(before_order_walk)<=local.run_speed*.5+.001,"local evacuation order causes bounded physical walking")
	# An interior resident transfers only after the old exit and a safe alternative open.
	manager.new_run(42); manager.ai_config.enabled=false; manager.phase="EVACUATION"
	var resident: Dictionary=manager.agents.filter(func(p):return p.role=="Civilian" and p.age>=18 and p.indoor_id=="" and p.get("riding","")=="" and p.id!="SPECIAL_I_AM_LEGEND")[0]
	walk_to(resident,manager.shelter_by_id.S1)
	check(manager.admit_arrival(resident).is_empty(),"transfer fixture begins with a real admission")
	manager.phase="IMPACT"; sim=manager.social; emergency=manager.emergency
	sim.shelter_life.initialize(sim)
	for step in range(1000):
		sim.shelter_life._advance_room_route(resident,.5)
		if resident.shelter_room_id!="": break
	resident.has_phone=true; resident.phone.connected=true; resident.hunger=44
	sim.config.network_availability=1.0; emergency.config.status_message_reach=1.0
	for shelter in manager.shelters: emergency.set_admissions(shelter.id,false)
	emergency.set_shelter_condition("S1","UNSAFE")
	emergency.set_admissions("S2",true)
	var inside_position: Vector2=resident.position
	emergency.tick(.1)
	check(resident.position==inside_position and manager.shelter_by_id.S1.occupancy==1,"sealed unsafe shelter does not teleport its resident outside")
	check(not emergency.set_admissions("S1",true),"unsafe shelter cannot reopen admissions")
	check(emergency.open_exit("S1"),"director may open an exit without allowing new admissions")
	var physical_exit:=true
	for step in range(1000):
		var previous: Vector2=resident.position
		emergency.tick(.5); manager.elapsed_seconds+=.5
		physical_exit=physical_exit and resident.position.distance_to(previous)<=resident.walk_speed*.5+.001
		if resident.shelter_id=="": break
	check(physical_exit and resident.shelter_id=="" and manager.shelter_by_id.S1.occupancy==0,"room graph and portal provide bounded actual egress")
	check(resident.position.distance_to(manager.shelter_by_id.S1.exit_position)<.01 and is_zero_approx(resident.transport_height),"occupant is released at the ground exit threshold")
	walk_to(resident,manager.shelter_by_id.S2)
	var entrance_position: Vector2=resident.position
	check(manager.admit_arrival(resident).is_empty() and resident.shelter_id=="S2" and manager.shelter_by_id.S2.occupancy==1,"post-impact transfer consumes a real available place")
	check(resident.position==entrance_position and resident.shelter_life_active and is_equal_approx(resident.hunger,44),"new shelter resumes routines without teleporting or resetting needs")
	manager.add_emergency("evacuation_order",resident.position,{"shelter_id":"S2","radius":5,"duration":5})
	emergency.tick(.1)
	check(manager.shelter_by_id.S2.occupancy==1 and resident.current_goal.contains("verified alternative"),"evacuation order cannot exit and immediately readmit to the same shelter")
	manager.social.close(); manager.queue_free(); await process_frame
	print("Dynamic emergencies: %d checks / %d failures"%[checks,failures]); quit(1 if failures else 0)
