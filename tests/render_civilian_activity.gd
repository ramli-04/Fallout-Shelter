extends SceneTree
func _initialize() -> void: run.call_deferred()
func capture(app: Node, name: String) -> void:
	for _i in range(15): await process_frame
	await RenderingServer.frame_post_draw
	app.map_view.world_viewport.get_texture().get_image().save_png("res://outputs/civilians-"+name+".png")

func run() -> void:
	var app = preload("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.manager.set_process(false)
	app.manager.ai_config["enabled"] = false
	app.intro_panel.hide()
	app.map_view.set_process(false)
	app.map_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for batch in app.map_view.city.vegetation: batch.hide()
	for node in app.map_view.city.get_children():
		if node is Label3D: node.hide()
	var origin: Vector2 = preload("res://scripts/city_map.gd").park.get_center()+Vector2(100,100)
	for i in range(app.manager.agents.size()):
		var agent: Dictionary = app.manager.agents[i]
		agent["position"] = origin+Vector2((i%6-2.5)*22,int(i/6)*28)
		agent["previous_position"] = agent["position"]-Vector2(0,1)
		agent["state"] = ["ROAMING","DANCING","MOVING","HELPING","FROZEN"][int(i/6)]
		app.map_view.agent_nodes[i].update_visual(agent,1,true,2)
	var rig: Node3D = app.map_view.camera_rig
	rig.focus_at(preload("res://scripts/three_d/world_coordinates.gd").to_world(origin+Vector2(0,50)))
	rig.target_distance = 29
	rig.target_yaw = 15
	rig.target_pitch = 35
	rig.snap()
	await capture(app,"skins")
	app.manager.launch_nuke()
	app.manager._begin_bomb_fall()
	app.manager.bomb_fall_elapsed = 4
	app.map_view.siren_network.set_process(false)
	app.map_view.siren_network.stop_all()
	app.effects.stop_siren()
	var capture_effect := AudioEffectCapture.new()
	capture_effect.buffer_length = 1.0
	var bus := AudioServer.get_bus_index("ESSAIMWarnings")
	AudioServer.add_bus_effect(bus,capture_effect)
	var muted := AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0,true)
	app.map_view.sync_run(app.manager.agents,app.manager.shelters,1,true,app.manager.elapsed_seconds)
	await create_timer(0.5).timeout
	var frames := capture_effect.get_buffer(capture_effect.get_frames_available())
	var energy := 0.0
	for frame in frames: energy += frame.x*frame.x+frame.y*frame.y
	energy /= maxi(1,frames.size())
	print("Falling bomb measured audio energy: ",energy)
	if energy <= 0.00000001:
		printerr("Bomb whistle did not reach audio capture")
		quit(1)
		return
	var drop: Node3D = app.map_view.falling_bomb
	for _i in range(3): await process_frame
	var middle: Vector3 = (drop.plane.global_position+drop.bomb.global_position)*0.5
	app.map_view.camera.global_position = middle+Vector3(0,45,160)
	app.map_view.camera.look_at(middle,Vector3.UP)
	await capture(app,"bomb-fall")
	app.manager.pause()
	for _i in range(3): await process_frame
	assert(drop.whistle.stream_paused)
	app.manager.initialize_run()
	for _i in range(3): await process_frame
	assert(not is_instance_valid(app.map_view.falling_bomb))
	AudioServer.set_bus_mute(0,muted)
	app.queue_free()
	await process_frame
	quit()
