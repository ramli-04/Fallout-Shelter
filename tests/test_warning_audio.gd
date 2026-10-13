extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, text: String) -> void:
	print("AUDIO ","PASS " if value else "FAIL ",text)
	if not value: failures += 1
func capture_energy(capture: AudioEffectCapture) -> Vector2:
	capture.clear_buffer()
	await create_timer(0.5).timeout
	var frames := capture.get_buffer(capture.get_frames_available())
	var energy := Vector2.ZERO
	for frame in frames: energy += Vector2(frame.x*frame.x,frame.y*frame.y)
	return energy/maxi(1,frames.size())
func save_image(name: String) -> void:
	for i in range(5): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/warning-"+name+".png")
func run() -> void:
	var app = preload("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.manager.set_process(false)
	app.manager.ai_config["enabled"] = false
	app.manager.initialize_run()
	app.intro_panel.hide()
	app.map_view.set_process(false)
	app.map_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var net: Node3D = app.map_view.siren_network
	net.set_process(false)
	app.manager.warning_config["director_mix"] = true
	app.manager.warning_config["environmental_muffling"] = false
	app.manager.warning_config["master_volume_db"] = -6.0
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	var bus := AudioServer.get_bus_index("ESSAIMWarningMaster")
	AudioServer.add_bus_effect(bus,capture)
	var original_master_mute := AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0,true)
	var node: Node3D = net.nodes[0]
	var location: Vector3 = node.position
	app.map_view.camera_rig.yaw = 0
	app.map_view.camera_rig.target_focus = location+Vector3(-10,0,0)
	net.test_siren(node.record["id"])
	net.sync_mix()
	var right: Vector2 = await capture_energy(capture)
	app.map_view.camera_rig.target_focus = location+Vector3(10,0,0)
	net.sync_mix()
	var left: Vector2 = await capture_energy(capture)
	app.map_view.camera_rig.target_focus = location+Vector3(0,0,90)
	net.sync_mix()
	var far: Vector2 = await capture_energy(capture)
	print("Measured channel energies: right ",right," / left ",left," / distant ",far)
	check(right.x+right.y > 0.00000001,"actual warning PCM reaches capture bus")
	check(right.y > right.x and left.x > left.y,"3D stereo pan reverses with listener position")
	check(right.x+right.y > (far.x+far.y)*4,"distance attenuates measured audio energy")
	net.test_id = ""
	net.sync_mix()
	app.map_view.fit_camera()
	app._show_drawer("sirens")
	await save_image("panel")
	app.map_view.camera_rig.focus_at(location)
	app.map_view.camera_rig.target_distance = 30
	app.map_view.camera_rig.snap()
	await save_image("tower")
	app.manager.launch_nuke()
	net.sync_mix()
	app.manager.pause()
	net.sync_mix()
	for i in range(4):
		await physics_frame
		net.sync_mix()
	await create_timer(0.3).timeout
	var paused: Vector2 = await capture_energy(capture)
	print("Paused channel energy: ",paused)
	check(paused.x+paused.y < 0.000000001,"paused warning produces silent measured PCM")
	app.manager.nuclear["impact_position"] = [node.record["position"].x,node.record["position"].y]
	app.manager.nuclear["radius"] = 20.0
	app.manager.alarm_is_real = true
	app.manager._trigger_impact()
	net._process(0.1)
	app.manager.clock_changed.emit(app.manager.elapsed_seconds,false)
	app.siren_controls.inspect(node.record["id"])
	await create_timer(8.5).timeout
	net._process(8.5)
	app.siren_panel.get_child(0).set_deferred("scroll_vertical",10000)
	await save_image("destroyed-tower")
	AudioServer.remove_bus_effect(bus,AudioServer.get_bus_effect_count(bus)-1)
	AudioServer.set_bus_mute(0,original_master_mute)
	net.stop_all()
	capture = null
	await create_timer(0.3).timeout
	app.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("Warning audio: 4 checks / %d failures" % failures)
	quit(1 if failures else 0)
