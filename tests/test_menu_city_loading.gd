extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var scene=load(ProjectSettings.get_setting("application/run/main_scene")).instantiate(); root.add_child(scene)
	for i in range(3): await process_frame
	scene.manager.social_config.llm_agents=0; scene.manager.ai_bridge.set_process(false)
	var progress: Array=[]; scene.manager.world.progress_changed.connect(func(value,stage): progress.append([value,stage]))
	scene._start_map_view.call_deferred()
	var started:=Time.get_ticks_msec(); var captured:=false
	while scene.launch_menu.visible or scene.manager.agents.is_empty():
		await process_frame
		if scene.launch_menu.busy and scene.launch_menu.bar.value>=10 and not captured:
			await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png("res://outputs/loading-screen.png"); captured=true
		if Time.get_ticks_msec()-started>120000: printerr("Loading timed out"); quit(1); return
	assert(scene.launch_menu.bar.value==100)
	assert(not scene.manager.world.busy and scene.manager.agents.size()>0)
	assert(progress.size()>=2)
	scene.manager.pause(); scene.manager.social.close()
	await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png("res://outputs/menu-loaded-city.png")
	print("Menu to city: real worker progress, scenario and presentation ready, ",progress.size()," progress updates")
	scene.queue_free(); await process_frame; await process_frame; quit()
