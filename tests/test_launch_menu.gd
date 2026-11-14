extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var scene=load(ProjectSettings.get_setting("application/run/main_scene")).instantiate(); root.add_child(scene)
	for i in range(4): await process_frame
	assert(scene.launch_menu!=null and scene.launch_menu.visible)
	assert(not scene.manager.world.busy and scene.manager.agents.is_empty())
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/main-menu.png")
	scene.launch_menu.begin(); scene.launch_menu.report(40,"Terrain ready"); assert(scene.launch_menu.bar.value==40)
	scene.launch_menu.report(20,"Another stage"); assert(scene.launch_menu.bar.value==40)
	scene.launch_menu.fail("Test error"); assert(not scene.launch_menu.busy and scene.launch_menu.menu.visible)
	scene.queue_free(); await process_frame; print("Launch menu: initial menu, no automatic generation, progress and retry passed"); quit()
