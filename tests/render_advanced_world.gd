extends SceneTree
const Map=preload("res://scripts/city_map.gd")
const C=preload("res://scripts/three_d/world_coordinates.gd")
func _initialize() -> void: run.call_deferred()
func capture(app: Node,label: String) -> void:
	for i in range(160): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/streaming/"+label+".png")
func run() -> void:
	root.gui_embed_subwindows=true
	var app=preload("res://scenes/main.tscn").instantiate(); root.add_child(app)
	app.manager.set_process(false); app.manager.ai_bridge.set_process(false)
	app.manager.social_config.llm_agents=0; app.manager.social_config.spontaneous_actions=false
	app.manager.generate_world(42,{"preset":"small"}); await app.manager.world.completed
	app.intro_panel.hide(); app.map_view.show_zones=false; app.map_view.blast_zones.hide()
	var rig: Node3D=app.map_view.camera_rig
	rig.focus_at(C.to_world(Map.pois[1].footprint.get_center())); rig.target_distance=65; rig.snap()
	await capture(app,"advanced-street")
	rig.reset_overview(); await capture(app,"advanced-overview")
	print("Captured procedural world ",app.manager.world.current.world_id)
	app.queue_free(); await process_frame; quit()
