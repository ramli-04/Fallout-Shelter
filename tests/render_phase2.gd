extends SceneTree
## Graphical QA: captures preparation, movement/inspection, and impact states.

const MAIN_SCENE = preload("res://scenes/main.tscn")


func _initialize() -> void:
	_capture.call_deferred()


func save_capture(filename: String) -> void:
	for frame in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png("res://outputs/" + filename)
	if error != OK:
		printerr("Screenshot failed: ", error)
		quit(1)


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute("res://outputs")
	var app: Control = MAIN_SCENE.instantiate()
	root.add_child(app)
	app.manager.set_process(false)
	var prefix := "phase2"
	if "stress" in OS.get_cmdline_user_args():
		prefix = "phase2-stress"
		for shelter in app.manager.settings["shelters"]:
			shelter["capacity"] = 1
		app.manager.new_run(0)
	await save_capture(prefix + "-preparation.png")
	app.manager.start()
	app.manager.launch_nuke()
	app.manager.advance_clock(30)
	app.map_view.select_at(app.map_view.agent_nodes[0].position)
	app._refresh_live_ui()
	await save_capture(prefix + "-evacuation.png")
	# Advance using the same fixed simulation clock, not a fabricated display state.
	app.manager.advance_clock(1000)
	app._refresh_live_ui()
	for frame in range(120):
		await process_frame
	await save_capture(prefix + "-impact.png")
	print("Phase 2 graphical capture complete: ", app.manager.summary)
	app.queue_free()
	await process_frame
	quit(0)
