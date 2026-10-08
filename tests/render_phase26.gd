extends SceneTree
## Render actual 3D viewpoints and lifecycle states, never fabricated UI screenshots.
const MAIN = preload("res://scenes/main.tscn")

func _initialize() -> void:
	_capture.call_deferred()

func save_capture(name: String) -> void:
	for i in range(8): await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png("res://outputs/"+name+".png")
	if error != OK:
		printerr("Capture failed: ",error_string(error))
		quit(1)

func _capture() -> void:
	DirAccess.make_dir_recursive_absolute("res://outputs")
	var app: Control = MAIN.instantiate()
	root.add_child(app)
	app.manager.set_process(false)
	await physics_frame
	await process_frame
	await save_capture("phase26-overview")
	var selected: Node3D = null
	for node in app.map_view.agent_nodes:
		var point: Vector2 = app.map_view.screen_point(node)
		if app.map_view.pick_entity(point) == node:
			selected = node
			app.map_view.select_at(point)
			break
	if selected != null:
		app.map_view.focus_selected()
		app.map_view.camera_rig.target_distance = 28.0
		app.map_view.camera_rig.snap()
		await save_capture("phase26-agent-close")
	app.map_view.fit_camera()
	app.manager.start()
	app.manager.launch_nuke()
	app.manager.advance_clock(30)
	app._refresh_live_ui()
	await save_capture("phase26-evacuation")
	app.map_view.camera_rig.rotate_drag(Vector2(180,45))
	app.map_view.camera_rig.snap()
	await save_capture("phase26-orbit")
	if not app.manager.environment_events.is_empty():
		var incident: Dictionary = app.manager.environment_events[0]
		var until_incident: float = incident["scheduled_time"]+0.5-(app.manager.elapsed_seconds-app.manager.alarm_started_seconds)
		if until_incident > 0: app.manager.advance_clock(until_incident)
		app.map_view.camera_rig.focus_at(preload("res://scripts/three_d/world_coordinates.gd").to_world(incident["target_location"]))
		app.map_view.camera_rig.target_distance = 42.0
		app.map_view.camera_rig.snap()
		if not incident["target_id"].is_empty(): app.map_view.select_shelter(app.manager.shelter_by_id[incident["target_id"]])
		app._refresh_live_ui()
		await save_capture("phase26-scheduled-incident")
	app.map_view.fit_camera()
	app.manager.advance_clock(1000)
	app._refresh_live_ui()
	for i in range(20): await process_frame
	await save_capture("phase26-impact")
	app.manager.initialize_run()
	app.manager.launch_nuke(true)
	app.manager.advance_clock(1000)
	app._refresh_live_ui()
	await save_capture("phase26-all-clear")
	for seed_number in range(32):
		app.manager.new_run(seed_number)
		if not app.manager.shelter_by_id["S5"]["exists"]: break
	app.map_view.select_shelter(app.manager.shelter_by_id["S5"])
	await save_capture("phase26-absent-s5")
	root.get_window().size = Vector2i(1024,720)
	await save_capture("phase26-small-window")
	app.map_view.city.navigation_region.show_debug_surface()
	await save_capture("phase26-navigation")
	app.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("Phase 2.6 graphical capture complete")
	quit()
