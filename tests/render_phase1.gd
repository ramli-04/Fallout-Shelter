extends SceneTree
## Optional visual QA. Requires a graphical display; saves outputs/phase1.png.

const MAIN_SCENE = preload("res://scenes/main.tscn")


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	root.add_child(MAIN_SCENE.instantiate())
	for frame in range(10):
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://outputs")
	var filename := "phase1.png"
	if not OS.get_cmdline_user_args().is_empty():
		filename = OS.get_cmdline_user_args()[0].get_file()
	var result := root.get_texture().get_image().save_png("res://outputs/" + filename)
	print("Visual capture: ", result)
	quit(result)
