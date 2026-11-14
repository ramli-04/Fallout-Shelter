extends SceneTree
const Manager = preload("res://scripts/simulation_manager.gd")
const Observation = preload("res://scripts/agent_observation.gd")
const Config = preload("res://scripts/social_config.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures+=1; printerr("FAIL: "+label)
func run() -> void:
	var sim:=Manager.new(); root.add_child(sim)
	check(sim.load_settings(),"valid project settings")
	sim.initialize_run(); sim.ai_bridge.status="DISCONNECTED"
	check(sim.agents.size()==100,"100 agents")
	check(sim.agents.filter(func(a):return a.role=="Authority").size()==35,"35 authorities")
	check(sim.agents.filter(func(a):return a.age<18).size()==10,"10 children")
	check(sim.social.school.students.size()==10,"school assignments")
	for id in sim.social.school.students:
		check(sim.social.by_id[id].indoor_id==sim.social.daily.room_for("School") and sim.social.daily.interiors.contains(sim.social.by_id[id].indoor_id,sim.social.by_id[id].position),"students physically inside school")
	var first: Dictionary=sim.agents[0]
	var second: Dictionary=sim.agents[1]
	first.personal_memory.append({"time":0,"text":"FIRST_PRIVATE"})
	second.personal_memory.append({"time":0,"text":"SECOND_SECRET"})
	second.hidden_secret="HIDDEN_COORDINATES"
	var observation: Dictionary=Observation.generate(sim,first)
	check(not str(observation).contains("SECOND_SECRET"),"other memory isolated")
	check(not str(observation).contains("HIDDEN_COORDINATES"),"unlisted fields isolated")
	check(not observation.has("nuclear") and not observation.has("vehicles") and not observation.has("families"),"no omniscient fields")
	sim.social.acquire(first,"test","wrong","someone",.3,"social media")
	check(not second.social_beliefs.has("test"),"independent beliefs")
	sim.social.acquire(first,"test","true",first.id,1,"direct observation")
	sim.social.acquire(first,"test","wrong","someone",.9,"text")
	check(first.social_beliefs.test.claimed_value=="true","observation resists contradictory rumor")
	first.has_phone=true; second.has_phone=true; first.phone.connected=true; second.phone.connected=true
	first.phone.contacts.append(second.id); sim.social.config.network_availability=1
	check(sim.social.send_phone(first,second.id,{"subject":"test_call","value":"hello"},"call"),"targeted phone send")
	var message: Dictionary=sim.social.deliveries[-1]
	sim.social._deliver(message)
	check(second.social_beliefs.has("test_call"),"recipient receives call")
	check(not sim.agents[2].social_beliefs.has("test_call"),"phone audience isolation")
	first.phone.connected=false
	check(not sim.social.send_phone(first,second.id,{},"text"),"disconnected device cannot send")
	first.phone.connected=true
	var authority: Dictionary={}
	var police: Dictionary={}
	for a in sim.agents:
		if a.role=="Authority": authority=a
		if a.occupation=="Police": police=a
	var alert: Dictionary=sim.social.issue_alert(authority,"evacuate","test","seek protection",first.position,1)
	for pending in sim.social.deliveries:
		if pending.channel=="alert": check(sim.social.by_id[pending.recipient].position.distance_to(first.position)<=1,"geographic alert audience")
	var Map=preload("res://scripts/city_map.gd")
	var edge: Dictionary=Map.roads[0]
	check(sim.social.create_block(police,"police",edge).is_empty(),"unstaffed police closure rejected")
	var block: Dictionary=sim.social.create_block(police,"accident",edge,edge.points[edge.points.size()/2])
	check(not Map.graph.are_points_connected(edge.from,edge.to),"closure updates route graph")
	check(not Map.free_route(block.position,Map.spawn_slots()[0]).is_empty(),"person enclosed by a new temporary barrier can leave")
	sim.social.remove_block(block.id)
	check(Map.graph.are_points_connected(edge.from,edge.to),"closure removal restores graph")
	var vehicle: Dictionary=sim.social.vehicles[0]
	# Boarding fixtures stand outside the vehicle, not inside their initial building.
	for passenger in [first,second]:
		if passenger.indoor_id!="": sim.social.daily.interiors.rooms[passenger.indoor_id].occupants.erase(passenger.id)
		passenger.indoor_id=""; passenger.riding=""
		for other in sim.social.vehicles: other.passengers.erase(passenger.id)
	first.position=vehicle.position; vehicle.speed=0
	check(sim.social.board(vehicle,first),"vehicle boarding")
	vehicle.capacity=vehicle.passengers.size()
	second.position=vehicle.position
	check(not sim.social.board(vehicle,second),"capacity enforced")
	check(sim.social.leave(vehicle,first),"vehicle disembarking")
	# A road closure requires a wreck on the road, rather than in its parking bay.
	vehicle.position=Map.nearest_edge(vehicle.position,true,0).point
	vehicle.body_position=vehicle.position
	sim.social.accident(vehicle)
	check(vehicle.status=="ACCIDENT" and sim.social.blocks[-1].kind=="accident","accident creates physical closure")
	check(Config.save_preset(sim.social_config,"user://test_phase5_preset.json")==OK,"save versioned config")
	var saved: Variant=JSON.parse_string(FileAccess.get_file_as_string("user://test_phase5_preset.json"))
	check(Config.validate(saved).is_empty() and saved.total==sim.social_config.total and saved.seed==sim.social_config.seed,"preset roundtrip")
	var pending:=HTTPRequest.new(); sim.ai_bridge.add_child(pending)
	sim.start(); sim.launch_nuke()
	sim.ai_config.execution_mode="sync"
	sim.ai_bridge.pending["mock"]=pending
	var before_barrier: float=sim.elapsed_seconds
	sim.advance_clock(1)
	check(sim.elapsed_seconds==before_barrier,"synchronous inference barrier freezes simulation clock")
	sim.ai_config.execution_mode="async"
	sim.advance_clock(1)
	check(sim.elapsed_seconds>before_barrier,"asynchronous mode continues with pending inference")
	sim.ai_bridge.pending.erase("mock"); pending.queue_free()
	check(sim.social.create_block(first,"police",edge).is_empty(),"police roadblocks require dispatched officers and operational evidence")

	for i in range(60): sim.advance_clock(.25)
	check(sim.elapsed_seconds>=15,"clock progresses")
	check(sim.ai_bridge.decision_queue.is_empty(),"no central inference backlog")
	check(sim.social.history.any(func(e):return e.event_type=="authority.alert_issued"),"emergency alert emitted")
	for e in sim.social.history:
		check(e.has("event_id") and e.schema_version==1 and e.has("simulation_timestamp") and e.has("source_entity"),"versioned social event")
	var replay_path: String="res://outputs/phase5/"+sim.ai_bridge.run_id+".jsonl"
	check(sim.social.load_replay(replay_path),"recorded replay loads")
	check(not sim.running and sim.social.replaying,"replay disables simulation")
	sim.social.apply_replay_frame(sim.social.replay_frames.size()-1)
	check(sim.ai_bridge.pending.is_empty(),"replay issues no inference")
	sim.social.replaying=false
	sim.alarm_is_real=true; sim._trigger_impact()
	check(sim.phase=="IMPACT","nuclear impact compatible")
	check(sim.shelters.size()==5,"five shelters preserved")
	var iq: float=sim.agents[0].iq
	sim.initialize_run()
	check(absf(sim.agents[0].iq-iq)<.000001 and sim.agents.size()==100,"same-seed reset reproducibility")
	sim.phase5_enabled=false
	sim.ai_config.experiment_preset="30"
	preload("res://scripts/llm_experiments.gd").apply(sim.settings,sim.ai_config)
	sim.initialize_run()
	check(sim.agents.size()==30 and sim.social==null,"legacy preset remains available after social run")
	sim.phase5_enabled=true; sim.initialize_run()
	check(sim.agents.size()==100 and sim.social!=null,"social runtime can be restored")
	sim.queue_free(); await process_frame
	print("Phase 5: %d checks / %d failures"%[checks,failures]); quit(1 if failures else 0)
