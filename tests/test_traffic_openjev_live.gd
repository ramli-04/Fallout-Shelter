extends SceneTree
const Map=preload("res://scripts/city_map.gd")
const Rules=preload("res://scripts/traffic_rules.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var manager:=preload("res://scripts/simulation_manager.gd").new(); root.add_child(manager); manager.set_process(false)
	if not manager.load_settings(): quit(1); return
	manager.social_config.llm_agents=0; manager.initialize_run(); manager.ai_bridge.set_process(false); manager.social.close()
	manager.phase="LIVING"; manager.ai_config.enabled=true; manager.social.next_send=INF
	var social: RefCounted=manager.social; var rules: RefCounted=social.driving
	var edge: Dictionary={}
	for road in Map.roads:
		if int(road.lanes)>=4 and not road.get("elevated",false) and road.a.distance_to(road.b)>650: edge=road; break
	if edge.is_empty(): printerr("No suitable test boulevard"); manager.queue_free(); await process_frame; quit(1); return
	var index: int=int(edge.points.size()/2.0)
	var tangent: Vector2=(edge.points[index+1]-edge.points[index]).normalized()
	var a: Dictionary=social.vehicles[0].duplicate(true); var b: Dictionary=social.vehicles[1].duplicate(true)
	a.position=edge.points[index]; a.heading=tangent.angle(); a.lane_offset=Rules.lane_offset(edge)
	a.body_position=a.position+tangent.orthogonal()*a.lane_offset; a.status="MOVING"; a.speed=65.0; a.height=0.0
	a.slow_wait=10.0; a.lead_gap=100.0; a.lead_speed=18.0; a.speed_limit=100.0; a.driving_mode="KEEP_LANE"
	a.rules_edge=edge; a.rules_edge_due=INF; a.traffic_light="NONE"; a.next_driving_ai=0.0
	b.position=a.position+tangent*150; b.body_position=b.position+tangent.orthogonal()*a.lane_offset; b.heading=a.heading; b.height=0.0; b.speed=18; b.status="MOVING"
	social.vehicles=[a,b]
	for agent in manager.agents: agent.indoor_id="TEST_ROOM"
	if not rules.can_pass(a,edge,tangent): printerr("Test passing corridor is not clear"); manager.queue_free(); await process_frame; quit(1); return
	rules.request_advice(a,true)
	for step in range(1100):
		await create_timer(.02).timeout
		if rules.pending.is_empty(): break
	var success: bool=rules.completed==1 and a.get("driving_provider","")=="OPENJEV"
	var before: int=social.history.size()
	a.next_driving_ai=0; rules.request_advice(a,true); rules.close(); await create_timer(.5).timeout
	success=success and rules.pending.is_empty() and social.history.size()==before
	print("Driving OpenJev live: %s / %s / %s / %s"%[rules.status,a.get("last_driving_action","none"),a.get("driving_provider","none"),"PASS" if success else "FAIL"])
	social.close(); manager.queue_free(); await process_frame; await process_frame; quit(0 if success else 1)
