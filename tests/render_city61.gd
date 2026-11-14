extends SceneTree
const Map=preload("res://scripts/city_map.gd")
const C=preload("res://scripts/three_d/world_coordinates.gd")
var app: Node
var results: Dictionary={}
func _initialize() -> void: run.call_deferred()
func capture(name: String) -> void:
	for _i in range(15): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/city61-"+name+".png")
func focus(point: Vector2, distance: float) -> void:
	var rig: Node3D=app.map_view.camera_rig
	rig.focus_at(C.to_world(point)); rig.target_distance=distance; rig.target_pitch=60; rig.target_yaw=0; rig.snap()
func run() -> void:
	root.gui_embed_subwindows=true
	var started:=Time.get_ticks_usec()
	app=preload("res://scenes/main.tscn").instantiate(); root.add_child(app)
	results.startup_ms=float(Time.get_ticks_usec()-started)/1000
	app.manager.set_process(false); app.set_process(false); app.manager.ai_bridge.set_process(false)
	app.manager.ai_config.enabled=false
	for a in app.manager.agents: a.configured_provider="RULE_BASED"
	app.intro_panel.hide(); app.map_view.show_zones=false; app.map_view.blast_zones.hide()
	await capture("overview")
	var rig: Node3D=app.map_view.camera_rig
	rig.focus_at(C.to_world(Map.MAP_SIZE*Vector2(.9,.12)))
	rig.target_distance=rig.settings.max_distance; rig.target_pitch=30; rig.target_yaw=135; rig.snap()
	await capture("horizon")
	focus(Map.grove.center+Vector2(-150,0),165)
	await capture("alder-court")
	var parking: Dictionary=Map.parking_lots[2]
	focus(parking.position,85)
	await capture("parking")
	var node: int=Map.graph.get_point_ids()[0]
	for id in Map.graph.get_point_ids():
		if Map.graph.get_point_connections(id).size()>=4: node=id; break
	focus(Map.graph.get_point_position(node),110)
	await capture("intersection")
	Map.generation_settings.show_districts=true; app.map_view.fit_camera()
	await capture("districts")
	Map.generation_settings.show_districts=false
	app._toggle_drawer("settings")
	await capture("director")
	app._toggle_drawer("")
	var valley: Node=app.map_view.city.get_node("ValleyEnvironment")
	results.road_vertices=valley.road_vertices; results.buildings=Map.lots.size(); results.roads=Map.roads.size()
	results.map_metres=[Map.MAP_SIZE.x*.1,Map.MAP_SIZE.y*.1]
	results.validation=Map.validation
	var fixture:=FileAccess.open("res://outputs/city61-road-fixture.json",FileAccess.WRITE)
	fixture.store_string(JSON.stringify(valley.geometry_definition)); fixture.close()
	var samples:=[]
	app.manager.start()
	for _i in range(120):
		var before:=Time.get_ticks_usec()
		app.manager.advance_clock(1.0/30)
		await process_frame
		samples.append(float(Time.get_ticks_usec()-before)/1000)
	samples.sort(); results.frame_p50_ms=samples[60]; results.frame_p95_ms=samples[114]
	app.manager.launch_nuke()
	samples.clear()
	for _i in range(120):
		var before:=Time.get_ticks_usec()
		app.manager.advance_clock(1.0/30)
		await process_frame
		samples.append(float(Time.get_ticks_usec()-before)/1000)
	samples.sort(); results.evacuation_p50_ms=samples[60]; results.evacuation_p95_ms=samples[114]
	results.draw_calls=Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	results.renderer_video_memory_bytes=Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
	var file:=FileAccess.open("res://outputs/city61-render-benchmark.json",FileAccess.WRITE); file.store_string(JSON.stringify(results,"  ")); file.close()
	print(JSON.stringify(results))
	app.queue_free(); await process_frame; quit()
