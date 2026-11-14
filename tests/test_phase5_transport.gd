extends SceneTree
const Manager=preload("res://scripts/simulation_manager.gd")
const Map=preload("res://scripts/city_map.gd")
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(v: bool, label: String) -> void:
	checks+=1
	if not v: failures+=1; printerr("FAIL: "+label)
func run() -> void:
	var sim:=Manager.new(); root.add_child(sim); sim.set_process(false)
	check(sim.load_settings(),"configuration loads")
	sim.social_config.llm_agents=0; sim.social_config.phone_rate=1; sim.social_config.network_availability=1
	sim.social_config.alert_reach=1; sim.social_config.accident_probability=0
	sim.initialize_run(); sim.ai_bridge.set_process(false)
	sim.social.close() # Behavior test does not need frame recordings.
	var starts: Dictionary={}
	for v in sim.social.vehicles: starts[v.id]=v.position
	sim.start(); sim.launch_nuke()
	for step in range(160):
		var previous: Dictionary={}
		for v in sim.social.vehicles: previous[v.id]=v.position
		sim.advance_clock(.25)
		for v in sim.social.vehicles: check(v.position.distance_to(previous[v.id])<=115*.25+.01,"bounded continuous vehicle movement")
	check(sim.social.vehicles.any(func(v):return v.position.distance_to(starts[v.id])>20),"vehicles actually travel")
	if sim.social.school_status=="NORMAL":
		for id in sim.social.school.staff:
			var staff: Dictionary=sim.social.by_id[id]
			print("SCHOOL_DIAGNOSTIC "+str({"id":id,"state":staff.state,"position":staff.position,"objective":staff.objective,"beliefs":staff.social_beliefs,"decision":staff.decision_scores,"phase":sim.phase}))
	check(sim.social.school_status in ["EVACUATING","COMPLETED"],"school organizes evacuation")
	check(sim.social.history.any(func(e):return e.event_type=="phone.message_sent"),"phones used during live scenario")
	check(sim.social.history.any(func(e):return e.event_type=="school.evacuation_started"),"school event emitted")
	var police: Dictionary=sim.agents.filter(func(a):return a.occupation=="Police")[0]
	var v: Dictionary=sim.social.vehicles.filter(func(car):return car.kind=="Civilian")[0]
	var driver: Dictionary=sim.social.by_id[v.driver]
	var edge: Dictionary=Map.roads[0]
	var point: Vector2=edge.points[3]
	var direction: Vector2=(edge.points[4]-edge.points[3]).normalized()
	check(sim.social.create_block(police,"police",edge,point).is_empty(),"police barrier needs deployment lifecycle")
	var block: Dictionary=sim.social.create_block(police,"accident",edge,point)
	v.position=point-direction*40; v.route=PackedVector2Array([v.position,point+direction*80]); v.route_index=1
	v.speed=20; v.status="MOVING"; v.destination="S1"; v.height=0; v.next_route=sim.elapsed_seconds+30
	driver.objective="S1"; driver.social_target=""; driver.state="MOVING"; driver.position=v.position
	for _i in range(4): sim.social._move_vehicles(.1)
	check((v.position-point).dot(direction)<0,"civilian car does not pass active barrier")
	sim.social.remove_block(block.id)
	check(Map.graph.are_points_connected(edge.from,edge.to),"road reopens after obstruction removal")
	print("Transport behavior: %d checks / %d failures | %s"%[checks,failures,sim.social.snapshot_text()])
	sim.queue_free(); await process_frame; quit(1 if failures else 0)
