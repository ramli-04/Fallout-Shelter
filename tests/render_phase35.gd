extends SceneTree
func _initialize() -> void:
	run.call_deferred()
func capture(name: String) -> void:
	for i in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/phase35-"+name+".png")
func run() -> void:
	var app = preload("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.manager.set_process(false)
	app.map_view.set_process(false)
	app.map_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	app.manager.ai_config["enabled"] = false
	app.manager.initialize_run()
	app.intro_panel.hide()
	await capture("city")
	app._show_drawer("settings")
	await capture("controller")
	app._show_drawer("")
	var model_before: Array = app.manager.shelters.duplicate(true)
	app.map_view.preview_nuclear()
	await create_timer(4.0).timeout
	await capture("preview")
	assert(model_before == app.manager.shelters)
	app.map_view.clear_preview()
	app._show_drawer("")
	app.map_view.camera_rig.focus_at(Vector3(75,0.18,62))
	app.map_view.camera_rig.target_distance = 60
	app.map_view.camera_rig.snap()
	await capture("services")
	app.map_view.camera_rig.focus_at(app.map_view.shelter_nodes[0].position)
	app.map_view.camera_rig.target_distance = 27
	app.map_view.camera_rig.snap()
	await capture("vault")
	app.map_view.shelter_nodes[0].vault.door.set_state("CLOSED")
	await create_timer(1.0).timeout
	await capture("vault-closed")
	app.map_view.shelter_nodes[0].vault.door.set_state("OPEN")
	app.map_view.fit_camera()
	app.manager.nuclear["radius"] = 500
	app.manager.set_impact(app.manager.shelter_by_id["S1"]["position"])
	app.map_view.update_impact_marker()
	app.manager.launch_nuke()
	app.manager.alarm_is_real = true
	app.manager.advance_clock(1000)
	await create_timer(0.2).timeout
	await capture("blast")
	await create_timer(8.5).timeout
	await capture("devastation")
	app.map_view.select_shelter(app.manager.shelter_by_id["S1"])
	await capture("ruins-inspector")
	app.manager.initialize_run()
	app.intro_panel.hide()
	await capture("reset")
	print("Phase35 rendered captures complete")
	app.queue_free()
	await process_frame
	quit()
