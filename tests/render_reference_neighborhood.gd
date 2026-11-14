extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var manager=preload("res://scripts/simulation_manager.gd").new(); root.add_child(manager); manager.set_process(false)
	manager.load_settings(); manager.social_config.llm_agents=0; manager.initialize_run(); manager.ai_bridge.set_process(false); manager.social.close()
	var view=preload("res://scripts/map_view_3d.gd").new(); view.manager=manager; root.add_child(view); view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.display_run(manager.agents,manager.shelters,true,manager.social.companions)
	var map=preload("res://scripts/city_map.gd")
	var target: Vector2=map.lots[map.lots.size()/2].get_center()
	view.camera_rig.focus_at(preload("res://scripts/three_d/world_coordinates.gd").to_world(target)); view.camera_rig.target_distance=110; view.camera_rig.snap()
	view.city.streamer.refresh()
	for i in range(360):
		await process_frame
		if i>40 and view.city.streamer.queue.is_empty(): break
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/reference-neighborhood.png")
	print("Reference neighborhood: ",view.city.streamer.building_nodes.size()," detailed buildings")
	view.queue_free(); manager.queue_free(); await process_frame; await process_frame; quit()
