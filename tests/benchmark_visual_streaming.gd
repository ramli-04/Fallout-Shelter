extends SceneTree
const Map=preload("res://scripts/city_map.gd")
const C=preload("res://scripts/three_d/world_coordinates.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var manager=preload("res://scripts/simulation_manager.gd").new(); root.add_child(manager)
	manager.set_process(false); manager.load_settings(); manager.ai_bridge.set_process(false)
	manager.social_config.llm_agents=0; manager.social_config.automatic_warning=false; manager.social_config.spontaneous_actions=false
	if not OS.get_cmdline_user_args().is_empty() and OS.get_cmdline_user_args()[0]!="baseline": manager.world.load_world("res://outputs/streaming/baseline-world.json")
	else: manager.generate_world(42,{"preset":"large","district_density":1.5})
	await manager.world.completed
	var view=preload("res://scripts/map_view_3d.gd").new(); view.manager=manager
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var started:=Time.get_ticks_usec(); root.add_child(view)
	view.display_run(manager.agents,manager.shelters,true,manager.social.companions)
	view.camera_rig.focus_at(C.to_world(Map.MAP_SIZE*.5)); view.camera_rig.target_distance=180; view.camera_rig.snap()
	var startup_ms:=float(Time.get_ticks_usec()-started)/1000
	if view.city.get("streamer")!=null:
		view.city.streamer.refresh()
		while not view.city.streamer.queue.is_empty(): await process_frame
	var first_view_ready_ms:=float(Time.get_ticks_usec()-started)/1000
	for i in range(120): await process_frame
	var samples:=[]; var cpu:=[]
	manager.start()
	for i in range(180):
		var begin:=Time.get_ticks_usec(); manager.advance_clock(1.0/30)
		view.sync_run(manager.agents,manager.shelters,1,true,manager.elapsed_seconds,manager.social.companions)
		cpu.append(float(Time.get_ticks_usec()-begin)/1000)
		await process_frame
		samples.append(float(Time.get_ticks_usec()-begin)/1000)
	samples.sort(); cpu.sort()
	var total_frame_ms:=0.0
	for value in samples: total_frame_ms+=float(value)
	var result: Dictionary={"world_id":manager.world.current.world_id,"buildings_in_map":Map.lots.size(),"agents":manager.agents.size(),"startup_ms":startup_ms,
		"frame_p50_ms":samples[90],"frame_p95_ms":samples[171],"simulation_visual_cpu_p50_ms":cpu[90],"simulation_visual_cpu_p95_ms":cpu[171],
		"fps":Performance.get_monitor(Performance.TIME_FPS),"nodes":root.find_children("*","",true,false).size(),"objects":Performance.get_monitor(Performance.OBJECT_COUNT),
		"static_memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"render_objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),"video_memory_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		"active_buildings":view.city.buildings.size(),"active_agents":view.agent_nodes.size(),"renderer":RenderingServer.get_video_adapter_name()}
	result.first_view_ready_ms=first_view_ready_ms; result.measured_fps=1000*samples.size()/maxf(.001,total_frame_ms)
	if view.city.get("streamer")!=null: result.streaming=view.city.streamer.metrics()
	var label: String=OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "baseline"
	DirAccess.make_dir_recursive_absolute("res://outputs/streaming")
	var file:=FileAccess.open("res://outputs/streaming/"+label+".json",FileAccess.WRITE); file.store_string(JSON.stringify(result,"  ")); file.close()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/streaming/"+label+".png")
	print(JSON.stringify(result)); view.queue_free(); manager.queue_free(); await process_frame; quit()
