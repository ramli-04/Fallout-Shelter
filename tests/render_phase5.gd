extends SceneTree
var app: Node
var results := {}
func _initialize() -> void: run.call_deferred()
func settle() -> void:
	for _i in range(12): await process_frame
func screenshot(path: String) -> void:
	await settle(); await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func run() -> void:
	root.gui_embed_subwindows=true
	var start:=Time.get_ticks_usec()
	app=preload("res://scenes/main.tscn").instantiate(); root.add_child(app)
	app.manager.set_process(false); app.set_process(false)
	app.manager.ai_config.enabled=false
	app.manager.ai_bridge.set_process(false)
	for a in app.manager.agents: a.configured_provider="RULE_BASED"
	app.manager.ai_bridge.status="DISCONNECTED"
	results.startup_ms=(Time.get_ticks_usec()-start)/1000.0
	app.intro_panel.hide(); app.map_view.show_zones=false; app.map_view.blast_zones.hide()
	await screenshot("res://outputs/phase5-overview.png")
	app.social_window.popup_centered()
	await screenshot("res://outputs/phase5-configuration.png")
	app.social_window.get_child(1).get_child(0).current_tab=1
	await create_timer(1.1).timeout
	await screenshot("res://outputs/phase5-director.png")
	app.social_window.hide()
	var rig: Node3D=app.map_view.camera_rig
	rig.focus_at(preload("res://scripts/three_d/world_coordinates.gd").to_world(app.manager.social.school_position))
	rig.target_distance=110; rig.target_pitch=55; rig.snap()
	await screenshot("res://outputs/phase5-school.png")
	app.manager.start(); app.manager.launch_nuke()
	var samples:=[]
	for _i in range(120):
		var before:=Time.get_ticks_usec()
		app.manager.advance_clock(1.0/30)
		await process_frame
		samples.append(float(Time.get_ticks_usec()-before)/1000)
	samples.sort()
	results.population=app.manager.agents.size(); results.frame_p50_ms=samples[60]; results.frame_p95_ms=samples[114]
	results.draw_calls=Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	results.video_memory_bytes=Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
	results.vehicles=app.manager.social.vehicles.size()
	var valley: Node=app.map_view.city.get_node("ValleyEnvironment")
	results.road_vertices=valley.road_vertices
	results.road_surfaces={}
	for key in valley.road_surfaces:
		var surface: Dictionary=valley.road_surfaces[key]
		results.road_surfaces[key]={"polygons":surface.polygons.size(),"triangles":surface.triangles,"degenerate":surface.degenerate}
	await screenshot("res://outputs/phase5-evacuation.png")
	var file:=FileAccess.open("res://outputs/phase5-performance.json",FileAccess.WRITE); file.store_string(JSON.stringify(results,"  ")); file.close()
	print(JSON.stringify(results))
	app.queue_free(); await process_frame; quit()
