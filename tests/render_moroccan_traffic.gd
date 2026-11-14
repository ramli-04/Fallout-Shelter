extends SceneTree
const C=preload("res://scripts/three_d/world_coordinates.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://outputs/phase4")
	root.size=Vector2i(1440,1000)
	var app: Node=preload("res://scenes/main.tscn").instantiate(); root.add_child(app)
	app.set_process(false); app.manager.set_process(false); app.manager.ai_bridge.set_process(false)
	app.manager.ai_config.enabled=false; app.manager.social.close(); app.manager.social.next_send=INF
	app.intro_panel.hide(); app.map_view.blast_zones.hide()
	var vehicle: Dictionary={}
	for v in app.manager.social.vehicles:
		if v.status=="MOVING": vehicle=v; break
	if vehicle.is_empty(): printerr("No existing moving vehicle for visual QA"); quit(1); return
	var rig: Node3D=app.map_view.camera_rig
	rig.focus_at(C.to_world(vehicle.body_position)); rig.target_distance=75; rig.snap()
	for i in range(20): await process_frame
	await RenderingServer.frame_post_draw
	app.map_view.world_viewport.get_texture().get_image().save_png("res://outputs/phase4/right-hand-traffic.png")
	print("Traffic preview: actual vehicle %s / heading %.2f / lane offset %.2f"%[vehicle.id,vehicle.heading,vehicle.lane_offset])
	app.queue_free(); await process_frame; await process_frame; quit()
