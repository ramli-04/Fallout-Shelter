extends SceneTree

func _initialize() -> void: run.call_deferred()

func capture(app: Node, name: String) -> void:
	for _i in range(12): await process_frame
	await RenderingServer.frame_post_draw
	app.map_view.world_viewport.get_texture().get_image().save_png("res://outputs/map-"+name+".png")

func run() -> void:
	var app = preload("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.manager.set_process(false)
	app.manager.ai_config["enabled"] = false
	app.intro_panel.hide()
	app.map_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	await capture(app,"overview")
	var map = preload("res://scripts/city_map.gd")
	app.map_view.camera_rig.focus_at(preload("res://scripts/three_d/world_coordinates.gd").to_world(map.park.get_center()))
	app.map_view.camera_rig.target_distance = 200
	app.map_view.camera_rig.target_yaw = 25
	app.map_view.camera_rig.snap()
	await capture(app,"park")
	app.map_view.camera_rig.focus_at(preload("res://scripts/three_d/world_coordinates.gd").to_world(map.hill))
	app.map_view.camera_rig.target_distance = 170
	app.map_view.camera_rig.snap()
	await capture(app,"hill")
	app.queue_free()
	await process_frame
	quit()
