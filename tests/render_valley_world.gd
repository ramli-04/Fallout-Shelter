extends SceneTree
var app: Node
var results := {}
func _initialize() -> void: run.call_deferred()
func settle() -> void:
	for i in range(24): await process_frame
func capture(name: String) -> void:
	await settle()
	await RenderingServer.frame_post_draw
	app.map_view.world_viewport.get_texture().get_image().save_png("res://outputs/valley-"+name+".png")
func measure(label: String) -> void:
	assert(app.manager.agents.size() == (120 if label.begins_with("120") else 30))
	var frames := []
	await settle()
	for i in range(180):
		var start := Time.get_ticks_usec()
		app.manager.advance_clock(1.0/60)
		await process_frame
		frames.append(float(Time.get_ticks_usec()-start)/1000)
	frames.sort()
	var total := 0.0
	for value in frames: total += value
	results[label] = {"population":app.manager.agents.size(),"frames":180,"mean_frame_ms":total/frames.size(),"p95_frame_ms":frames[int(frames.size()*0.95)],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),"vram_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)}
	print(label+": "+JSON.stringify(results[label]))
func run() -> void:
	var started := Time.get_ticks_usec()
	app = preload("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	app.manager.set_process(false)
	app.manager.ai_config["enabled"] = false
	app.intro_panel.hide()
	app.map_view.show_zones = false
	app.map_view.blast_zones.hide()
	results["startup_ms"] = (Time.get_ticks_usec()-started)/1000.0
	var city: Node3D = app.map_view.city
	results["buildings"] = city.buildings.size()
	results["viewport"] = str(app.map_view.world_viewport.size)
	await capture("overview")
	var rig: Node3D = app.map_view.camera_rig
	rig.target_yaw = 0
	rig.target_pitch = 34
	rig.target_distance = 650
	rig.focus_at(Vector3(337,0,240))
	rig.snap()
	await capture("valley")
	for key in ["S1","S4"]:
		var point: Vector2 = app.manager.shelter_by_id[key]["position"]
		rig.focus_at(preload("res://scripts/three_d/world_coordinates.gd").to_world(point+Vector2(0,35)))
		rig.target_yaw = 155 if key == "S4" else 25
		rig.target_pitch = 36 if key == "S4" else 55
		rig.target_distance = 40
		rig.snap()
		await capture(key+"-open")
		for node in app.map_view.shelter_nodes:
			if node.record["id"] == key:
				node.record["door_status"] = "CLOSED"
				node._update_status()
		await create_timer(1.3).timeout
		await capture(key+"-closed")
	rig.reset_overview()
	app.manager.start()
	await measure("30_roaming_overview")
	app.manager.settings["agent_count"] = 120
	app.manager.new_run(42)
	app.manager.start()
	await measure("120_roaming_overview")
	app.manager.launch_nuke()
	await measure("120_evacuating_overview")
	var file := FileAccess.open("res://outputs/valley-performance.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"  "))
	app.queue_free()
	await process_frame
	quit()
