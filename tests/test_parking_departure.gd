extends SceneTree
const Map=preload("res://scripts/city_map.gd")
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; printerr("FAIL: "+label)
func run() -> void:
	var manager=preload("res://scripts/simulation_manager.gd").new(); root.add_child(manager); manager.set_process(false)
	manager.load_settings(); manager.social_config.llm_agents=0; manager.initialize_run(); manager.ai_bridge.set_process(false); manager.social.close()
	var social=manager.social
	var city: Node3D
	if OS.get_cmdline_user_args().has("physics"):
		city=preload("res://scripts/three_d/city_3d.gd").new(); root.add_child(city); social.traffic.bind_world(city)
		await physics_frame; await process_frame
	for a in manager.agents: a.indoor_id="PARKING_TEST"; a.social_target=""; a.objective=""
	var selected: Array=[]
	var lot: Dictionary={}
	for candidate in Map.parking_lots:
		var args:=OS.get_cmdline_user_args()
		if args.has("police") and candidate.category!="police": continue
		if args.has("fire") and candidate.category!="offices": continue
		var parked: Array=social.vehicles.filter(func(v):return candidate.bounds.has_point(v.position))
		if parked.size()>=2: selected=parked if OS.get_cmdline_user_args().has("all") else parked.slice(0,2); lot=candidate; break
	check(selected.size()>=2,"parked vehicles share a generated lot")
	if selected.size()<2: manager.queue_free(); quit(1); return
	manager.phase="EVACUATION"; manager.running=true
	for v in selected:
		var driver: Dictionary=social.by_id[v.driver]
		driver.indoor_id=""; driver.state="MOVING"; driver.health=100; driver.position=v.position; driver.family_id=""; driver.relationships={}; driver.pickup_target=""; driver.pickup_walk=false; driver.group_on_foot=false; driver.evacuation_group=""; driver.social_target="exit_test"; driver.objective="exit_test"; driver.riding=v.id
		driver.known_locations.exit_test={"position":lot.road_entry+lot.tangent*350}
		v.passengers=[driver.id]; v.destination=""; v.status="PARKED"; v.speed=0; v.health=100
	var initial: Array=selected.map(func(v):return v.position)
	for i in range(5000 if OS.get_cmdline_user_args().has("all") else 1600):
		social.traffic.capture(social.vehicles); social._move_vehicles(.05); social.traffic.resolve(social,.05); manager.elapsed_seconds+=.05
		if OS.get_cmdline_user_args().has("all"):
			for v in selected:
				if v.position.distance_to(initial[selected.find(v)])>100 and not social.traffic.parking_maneuver(v) and v.status!="ACCIDENT":
					v.status="REMOVED"; social.by_id[v.driver].indoor_id="EXIT_COMPLETE"
		if i==5: check(selected.filter(func(v):return social.traffic.parking_maneuver(v)).size()==1,"only one car owns the shared exit aisle")
		if selected.all(func(v):return not social.traffic.parking_maneuver(v) and v.position.distance_to(lot.position)>80): break
	for i in range(selected.size()):
		var v: Dictionary=selected[i]
		check(v.position.distance_to(initial[i])>100,"vehicle %d physically leaves its parking bay"%i)
		check(not social.traffic.parking_maneuver(v),"vehicle %d completes its exit route"%i)
		check(v.status!="ACCIDENT","vehicle %d exits without a parking crash"%i)
		if social.traffic.parking_maneuver(v) or v.status=="ACCIDENT": print("Parking diagnostic: ",v.id," ",v.status," ",v.get("driving_reason","")," ",v.position," ",v.get("route_index",0)," ",v.get("parking_exit_end",0)," collision=",v.collision_state)
	var urgency: float=social.driving.alert_urgency(selected[0]); check(urgency==social.driving.alert_urgency(selected[0]),"alert driving personality is deterministic")
	manager.phase="LIVING"; check(social.driving.alert_urgency(selected[0])==0,"ordinary driving has no alert rule relaxation")
	if city!=null: city.queue_free()
	manager.queue_free(); await process_frame
	print("Parking departure: %d checks / %d failures"%[checks,failures]); quit(1 if failures else 0)
