extends SceneTree
## Actual viewport captures, including small-window and hidden-state presentations.
const MAIN = preload("res://scenes/main.tscn")

func _initialize() -> void:
	_capture.call_deferred()

func save_capture(name: String) -> void:
	for i in range(5): await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png("res://outputs/" + name + ".png")
	if error != OK:
		printerr("Capture failed: ", error_string(error))
		quit(1)

func _capture() -> void:
	DirAccess.make_dir_recursive_absolute("res://outputs")
	var app: Control = MAIN.instantiate()
	root.add_child(app)
	app.manager.set_process(false)
	await save_capture("phase25-director-ready")
	app.manager.start()
	app.manager.advance_clock(5)
	app.manager.launch_nuke()
	app.manager.advance_clock(25)
	app.map_view.select_at(app.map_view.screen_point(app.map_view.agent_nodes[0]))
	app._refresh_live_ui()
	await save_capture("phase25-director-agent")
	app.manager.environment_events.assign([{"event_id":"QA", "event_type":"maintenance", "target_id":"S2", "target_location":app.manager.shelter_by_id["S2"]["position"], "scheduled_time":30.0, "duration":60.0, "severity":1.0, "active_status":false, "started":false, "ended":false, "actual_effect":"Stops admissions", "visibility_to_agents":[], "event_log_message":"S2 maintenance failure"}])
	app.manager.advance_clock(15)
	app.map_view.select_shelter(app.manager.shelter_by_id["S2"])
	app._refresh_live_ui()
	await save_capture("phase25-director-incident")
	app.manager.advance_clock(1000)
	app._refresh_live_ui()
	for i in range(30): await process_frame
	await save_capture("phase25-impact")
	app.manager.initialize_run()
	app.manager.launch_nuke(true)
	app.manager.advance_clock(1000)
	app._refresh_live_ui()
	await save_capture("phase25-all-clear")
	root.get_window().size = Vector2i(1024,720)
	app.manager.initialize_run()
	await save_capture("phase25-small-window")
	app.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("Phase 2.5 graphical capture complete")
	quit()
