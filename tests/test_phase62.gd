extends SceneTree
const Runtime=preload("res://scripts/vehicle_runtime.gd")
const SAT=preload("res://scripts/vehicle_collisions.gd")
const Map=preload("res://scripts/city_map.gd")
const Manager=preload("res://scripts/simulation_manager.gd")
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures+=1; printerr("FAIL: "+label)
func car(id: String, point: Vector2) -> Dictionary:
	return {"id":id,"position":point,"body_position":point,"heading":0.0,"length":43.0,"width":18.0,"body_height":1.5,"height":0.0,"speed":100.0,"status":"MOVING"}
func run() -> void:
	var a:=car("A",Vector2.ZERO); var b:=car("B",Vector2(100,0))
	var hit:=SAT.contact(a,a.position,Vector2(200,0),b,b.position,b.position)
	check(not hit.is_empty() and hit.time<.5,"high-speed vehicle sweep prevents tunneling")
	check(not Runtime.static_contact(a,Vector2.ZERO,Vector2(200,0),Rect2(100,-30,40,60)).is_empty(),"building collision")
	check(not Runtime.static_contact(a,Vector2.ZERO,Vector2(200,0),Rect2(100,-30,2,60)).is_empty(),"thin barrier collision")
	check(not Runtime.static_contact(a,Vector2.ZERO,Vector2(200,0),Rect2(100,-3,6,6)).is_empty(),"pedestrian sweep")
	b.height=10
	check(SAT.contact(a,a.position,Vector2(200,0),b,b.position,b.position).is_empty(),"bridge traffic separated")
	var sim:=Manager.new(); root.add_child(sim); sim.set_process(false)
	check(sim.load_settings(),"settings")
	sim.social_config.llm_agents=0; sim.initialize_run(); sim.ai_bridge.set_process(false); sim.social.close()
	var social: RefCounted=sim.social
	for i in range(social.vehicles.size()):
		for j in range(i):
			var first: Dictionary=social.vehicles[i]; var second: Dictionary=social.vehicles[j]
			check(SAT.contact(first,first.position,first.position,second,second.position,second.position).is_empty(),"no overlapping fleet spawn")
	var runtime:=Runtime.new()
	var saved: Array=Map.parking_lots
	Map.parking_lots=[{"bays":[{"id":"TEST","position":Vector2(-1000,-1000),"heading":0.0,"occupied_by":"","approach":PackedVector2Array()}]}]
	var test:=car("TEST",Vector2.ZERO)
	check(not runtime.reserve_spawn(test,[],Vector2.ZERO).is_empty(),"spawn reservation succeeds")
	check(runtime.reserve_spawn(car("TEST2",Vector2.ZERO),[],Vector2.ZERO).is_empty(),"full parking rejects spawn")
	runtime.reset(); check(runtime.reservations.is_empty(),"reset clears reservations")
	Map.parking_lots=saved
	var v: Dictionary=social.vehicles[0]
	var driver: Dictionary=social.by_id[v.driver]
	v.position=Map.nearest_edge(v.position,true,0).point; v.body_position=v.position
	driver.position=v.position; driver.health=100; v.passengers=[driver.id]; driver.riding=v.id
	var edge: Dictionary=Map.nearest_edge(v.position,true,0).edge
	var distant: Dictionary=sim.agents.filter(func(agent):return agent.role=="Civilian" and agent.position.distance_to(v.position)>sim.living.observation_radius*2)[0]
	social.traffic.impact(social,v,{},25.0,"building")
	check(not distant.social_beliefs.has("accident:"+v.id),"distant civilian gets no automatic accident knowledge")
	check(v.status=="ACCIDENT" and v.speed==0 and v.health==0,"severe collision creates persistent wreck")
	check(driver.health==0 and driver.survival_status=="DEAD","configurable severe occupant fatality")
	check(not Map.graph.are_points_connected(edge.from,edge.to),"wreck disconnects road graph")
	check(social.history.any(func(e):return e.event_type=="emergency.dispatched"),"emergency dispatch event")
	check(social.history.any(func(e):return e.event_type=="traffic.casualty"),"casualty event")
	var accidents: int=social.counters.accidents
	social.traffic.impact(social,v,{},25.0,"building")
	check(social.counters.accidents==accidents,"persistent contact does not repeat accident")
	var alternate: PackedVector2Array=social._vehicle_route(edge.a,edge.b)
	check(alternate.is_empty() or alternate.size()>2,"closed edge reroutes or safely has no route")
	var scene: Dictionary=social.traffic.scenes[-1]
	for id in scene.responders:
		social.by_id[id].position=scene.position; social.by_id[id].health=100
	sim.elapsed_seconds=scene.created+125
	social.traffic.respond(social,1)
	check(scene.secured,"police secure scene")
	check(scene.recovered and v.status=="REMOVED","configured recovery removes wreck")
	check(Map.graph.are_points_connected(edge.from,edge.to),"recovery restores graph")
	var parked_wreck: Dictionary=social.vehicles[1]
	parked_wreck.position=Vector2(-2000,-2000); parked_wreck.body_position=parked_wreck.position
	parked_wreck.passengers=[]; parked_wreck.status="PARKED"
	social.traffic.impact(social,parked_wreck,{},3.0,"building")
	var offroad: Dictionary=social.traffic.scenes[-1]
	check(offroad.block.is_empty(),"off-road wreck does not close a remote road")
	social.traffic.settings.recovery_enabled=false; offroad.secured=true
	sim.elapsed_seconds+=1000; social.traffic.respond(social,1)
	check(parked_wreck.status=="ACCIDENT","disabled recovery preserves wreck")
	social.traffic.settings.recovery_enabled=true
	var officer: Dictionary=sim.agents.filter(func(agent):return agent.occupation=="Police")[0]
	check(social.create_block(officer,"police",edge,edge.a).is_empty(),"police barriers require dispatched crew")
	var checkpoint: Dictionary=social.create_block(officer,"accident",edge,edge.a)
	var obstruction: Dictionary=social.create_block(officer,"accident",edge,edge.b)
	social.remove_block(checkpoint.id)
	check(not Map.graph.are_points_connected(edge.from,edge.to),"removing checkpoint cannot reopen accident closure")
	social.remove_block(obstruction.id)
	check(Map.graph.are_points_connected(edge.from,edge.to),"last closure reopens road")
	social.traffic.reset(); check(social.traffic.scenes.is_empty(),"reset cleans accident scenes")
	# Run actual movement resolution against each supported planar collision category.
	var saved_lots: Array[Rect2]=Map.lots.duplicate()
	var saved_blocks: Array=social.blocks.duplicate()
	var saved_fleet: Array=social.vehicles.duplicate()
	for agent in sim.agents: agent.position=Vector2(-9000,-9000); agent.riding=""
	var origin: Vector2=Map.roads[0].points[2]
	for category in ["vehicle","building","barrier","pedestrian"]:
		Map.lots.clear(); social.blocks=[]; social.traffic.reset()
		var mover: Dictionary=saved_fleet[1].duplicate(true)
		mover.position=origin; mover.body_position=origin+Vector2(0,11); mover.heading=0.0
		mover.status="MOVING"; mover.health=100.0; mover.speed=100.0; mover.height=0.0; mover.passengers=[]
		social.vehicles=[mover]
		if category=="vehicle":
			var parked: Dictionary=saved_fleet[2].duplicate(true)
			parked.position=origin+Vector2(80,11); parked.body_position=parked.position; parked.heading=0.0; parked.height=0.0; parked.status="PARKED"; parked.speed=0.0
			social.vehicles.append(parked)
		elif category=="building": Map.lots.append(Rect2(origin+Vector2(60,-30),Vector2(20,60)))
		elif category=="barrier": social.blocks.append({"id":"TEST-BARRIER","position":origin+Vector2(70,11),"height":0.0,"kind":"damaged_road","active":true,"edge":0})
		else:
			var pedestrian: Dictionary=sim.agents[-1]
			pedestrian.position=origin+Vector2(70,11); pedestrian.health=100; pedestrian.state="MOVING"; pedestrian.indoor_id=""; pedestrian.transport_height=0.0
		social.traffic.capture(social.vehicles)
		mover.position=origin+Vector2(150,0)
		social.traffic.resolve(social,.25)
		check(mover.status=="ACCIDENT" and mover.position.x<origin.x+100,"resolved "+category+" impact stops vehicle")
		if category=="pedestrian": check(sim.agents[-1].health<100,"resolved pedestrian casualty")
		for closure in social.blocks.duplicate():
			if closure.id!="TEST-BARRIER": social.remove_block(closure.id)
		for agent in sim.agents: agent.position=Vector2(-9000,-9000)
	Map.lots.assign(saved_lots); social.blocks=saved_blocks; social.vehicles=saved_fleet
	# Actual Godot occupancy query, using the same layer as street furniture.
	var obstacle:=StaticBody3D.new(); obstacle.collision_layer=64
	var collision:=CollisionShape3D.new(); var box:=BoxShape3D.new(); box.size=Vector3(2,3,2); collision.shape=box
	obstacle.add_child(collision); root.add_child(obstacle)
	var coord=preload("res://scripts/three_d/world_coordinates.gd")
	obstacle.position=coord.to_world(Vector2(-500,-500),1.5)
	await physics_frame; await physics_frame
	var probe:=car("PROBE",Vector2(-500,-500))
	check(not runtime.physics_query(probe,probe.position,probe.position).is_empty(),"Godot physics occupancy rejects obstacle")
	obstacle.queue_free()
	var ambulance: Dictionary=social.vehicles.filter(func(vehicle):return vehicle.kind=="Medical")[0]
	var medic: Dictionary=social.by_id[ambulance.driver]
	var patient: Dictionary=sim.agents[-1]
	medic.indoor_id=""; medic.interior_transition=""; medic.health=100; medic.state="MOVING"; medic.position=ambulance.position; medic.riding=""
	patient.indoor_id=""; patient.interior_transition=""; patient.health=50; patient.state="MOVING"; patient.position=ambulance.position; patient.riding=""
	ambulance.status="PARKED"; ambulance.speed=0; ambulance.passengers=[]
	social.traffic.scenes=[{"vehicle":"TEST-MEDICAL","position":ambulance.position,"block":"NONE","created":sim.elapsed_seconds,"responders":[medic.id],"secured":false,"treated":true,"recovered":false,"evacuated":[]}]
	social.traffic.respond(social,.1)
	check(patient.get("riding","")==ambulance.id,"ambulance boards living injured patient")
	check(social.history.any(func(event):return event.event_type=="emergency.evacuation_started"),"medical transport event")
	sim.phase="EVACUATION"
	ambulance.route=PackedVector2Array([ambulance.position,ambulance.position+Vector2.from_angle(ambulance.heading)*2])
	ambulance.route_index=1; ambulance.destination=medic.social_target; ambulance.next_route=sim.elapsed_seconds+100
	social._move_vehicles(.5)
	social._finish_vehicle_arrivals()
	check(patient.get("medical_evacuated",false),"medical arrival leaves patient under care")
	patient.health=0
	check(not social.board(ambulance,patient),"fatal casualty cannot board")
	sim.initialize_run(); sim.ai_bridge.set_process(false); sim.social.close()
	check(sim.social.traffic.scenes.is_empty() and sim.social.junction_reservations.is_empty(),"full scenario reset clears traffic incidents and junctions")
	check(sim.agents.all(func(agent):return agent.health>0),"reset restores casualties")
	sim.queue_free(); await process_frame
	print("Phase 6.2: %d checks / %d failures"%[checks,failures]); quit(1 if failures else 0)
