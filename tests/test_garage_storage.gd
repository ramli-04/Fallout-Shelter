extends SceneTree
const Map=preload("res://scripts/city_map.gd")
const Garages=preload("res://scripts/vehicle_garages.gd")
const SAT=preload("res://scripts/vehicle_collisions.gd")
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; printerr("FAIL: "+label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var manager=preload("res://scripts/simulation_manager.gd").new(); root.add_child(manager); manager.set_process(false)
	manager.load_settings(); manager.social_config.llm_agents=0; manager.initialize_run(); manager.ai_bridge.set_process(false); manager.social.close()
	var sim=manager.social
	var city: Node3D
	if OS.get_cmdline_user_args().has("physics"):
		city=preload("res://scripts/three_d/city_3d.gd").new(); root.add_child(city); sim.traffic.bind_world(city)
		await physics_frame; await process_frame
	check(Map.garage_sites.size()==3,"three garage buildings")
	var count:=0
	for i in range(Map.lots.size()):
		var art:=preload("res://scripts/three_d/building_sprites.gd").info(preload("res://scripts/three_d/building_shape.gd").plan(i),i)
		if art.key.split(":")[1]=="new_parking": count+=1
	check(count==3,"only three garage artworks in active map")
	var civilian: Array=sim.vehicles.filter(func(v):return v.kind=="Civilian")
	check(not civilian.is_empty() and civilian.all(func(v):return v.get("stored_in","")!=""),"owned civilian vehicles initially stored")
	for garage in Map.garage_sites:
		check(civilian.filter(func(v):return v.garage_id==garage.id).size()<=12,"twelve vehicles per garage maximum")
	var pool: Array=[]
	for i in range(36):
		var record: Dictionary={"id":"CAP%d"%i}
		check(not Garages.allocate(record,pool,Map,Map.garage_sites[0].position).is_empty(),"storage capacity %d"%i); pool.append(record)
	check(Garages.allocate({"id":"OVERFLOW"},pool,Map,Vector2.ZERO).is_empty(),"no 37th vehicle")
	for agent in manager.agents: agent.indoor_id="GARAGE_TEST"; agent.social_target=""; agent.objective=""
	var selected: Array=[]; var garage: Dictionary={}
	for candidate in Map.garage_sites:
		var cars: Array=civilian.filter(func(v):return v.garage_id==candidate.id)
		if cars.size()>=2: selected=cars.slice(0,2); garage=candidate; break
	check(selected.size()==2,"two owners share storage")
	if selected.size()!=2: manager.queue_free(); quit(1); return
	check(SAT.contact(selected[0],selected[0].position,selected[0].position,selected[1],selected[1].position,selected[1].position).is_empty(),"stored vehicles have no collision footprint")
	manager.phase="EVACUATION"; manager.running=true
	for v in selected:
		var driver: Dictionary=sim.by_id[v.driver]
		driver.indoor_id=""; driver.position=garage.waiting_point; driver.health=100; driver.state="MOVING"; driver.social_target="garage_test"; driver.family_id=""; driver.relationships={}; driver.pickup_target=""; driver.pickup_walk=false; driver.group_on_foot=false; driver.evacuation_group=""
		driver.known_locations.garage_test={"position":garage.road_entry+Vector2.from_angle(garage.heading).orthogonal()*350}
	for step in range(2000):
		sim.traffic.capture(sim.vehicles); sim._move_vehicles(.05); sim.traffic.resolve(sim,.05); manager.elapsed_seconds+=.05
		if step==5: check(selected.filter(func(v):return v.stored_in=="").size()==1,"one car spawns through portal at a time")
		if selected.all(func(v):return v.stored_in=="" and not sim.traffic.parking_maneuver(v)): break
	for v in selected:
		check(v.stored_in=="" and not sim.traffic.parking_maneuver(v),"car leaves garage")
		check(v.status!="ACCIDENT","garage departure without crash")
		if v.status=="ACCIDENT": print("Garage diagnostic: ",v.position," ",v.collision_state)
	Garages.store(selected[0],sim)
	check(selected[0].stored_in==garage.id,"return to hidden storage")
	var replay: Dictionary=sim.decode(sim.encode(selected[0]))
	check(replay.stored_in==garage.id and replay.garage_id==garage.id and replay.position==selected[0].position,"storage survives recorded replay encoding")
	if city!=null: city.queue_free()
	manager.queue_free(); await process_frame
	print("Garage storage: %d checks / %d failures"%[checks,failures]); quit(1 if failures else 0)
