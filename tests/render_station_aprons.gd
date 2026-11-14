extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var manager=preload("res://scripts/simulation_manager.gd").new(); root.add_child(manager); manager.set_process(false)
	manager.load_settings(); manager.social_config.llm_agents=0; manager.initialize_run(); manager.ai_bridge.set_process(false); manager.social.close()
	var view=preload("res://scripts/map_view_3d.gd").new(); view.manager=manager; root.add_child(view); view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.display_run(manager.agents,manager.shelters,true,manager.social.companions)
	var map=preload("res://scripts/city_map.gd")
	for kind in ["Police Station","Fire Station","corner","edge"]:
		var target:=Vector2(-100,map.MAP_SIZE.y*.5)
		if kind=="corner":
			var best:=INF
			for id in map.graph.get_point_ids():
				var links: PackedInt64Array=map.graph.get_point_connections(id)
				if links.size()!=2: continue
				var p: Vector2=map.graph.get_point_position(id)
				var a: Vector2=(map.graph.get_point_position(links[0])-p).normalized()
				var b: Vector2=(map.graph.get_point_position(links[1])-p).normalized()
				if absf(a.dot(b))>.4: continue
				var distance: float=p.distance_squared_to(map.MAP_SIZE*.5)
				if distance<best: best=distance; target=p
		elif kind!="edge":
			for poi in map.pois:
				if poi.kind==kind: target=poi.position; break
		view.camera_rig.focus_at(preload("res://scripts/three_d/world_coordinates.gd").to_world(target)); view.camera_rig.target_distance=85 if kind!="edge" else 250; view.camera_rig.snap()
		view.city.streamer.refresh()
		for i in range(360):
			await process_frame
			if i>60 and view.city.streamer.queue.is_empty(): break
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://outputs/station-"+kind.to_lower().replace(" ","-")+".png")
	view.queue_free(); manager.queue_free(); await process_frame; await process_frame; quit()
