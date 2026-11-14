extends SceneTree
const Map = preload("res://scripts/city_map.gd")
const C = preload("res://scripts/three_d/world_coordinates.gd")
var app: Node
func _initialize() -> void: run.call_deferred()
func capture(filename: String, point: Vector2, size: float) -> void:
	var rig: Node3D=app.map_view.camera_rig
	rig.focus_at(C.to_world(point)); rig.target_distance=size; rig.snap()
	for i in range(12): await process_frame
	var started := Time.get_ticks_usec()
	for i in range(30): await process_frame
	print("Phase 2 %s: mean frame %.2f ms, draw calls %d"%[filename,(Time.get_ticks_usec()-started)/30000.0,Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	await RenderingServer.frame_post_draw
	app.map_view.world_viewport.get_texture().get_image().save_png("res://outputs/phase2/"+filename+".png")
func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://outputs/phase2")
	root.size=Vector2i(1440,1000)
	app=preload("res://scenes/main.tscn").instantiate(); root.add_child(app)
	app.set_process(false); app.manager.set_process(false); app.manager.ai_bridge.set_process(false)
	app.manager.ai_config.enabled=false; app.manager.social.close(); app.manager.social.next_send=INF
	app.intro_panel.hide(); app.map_view.blast_zones.hide(); Map.interior_cutaway=false
	await capture("district",Map.lots[Map.lots.size()/2].get_center(),95)
	await capture("city",Map.MAP_SIZE*.5,Map.MAP_SIZE.x*.065)
	await capture("outskirts",Vector2(Map.MAP_SIZE.x*.5,0),200)
	for shelter in app.map_view.shelter_nodes:
		await capture(str(shelter.record.id),shelter.record.position,42)
	app.queue_free(); await process_frame; await process_frame
	quit()
