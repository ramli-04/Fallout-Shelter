extends SceneTree
const Map=preload("res://scripts/city_map.gd")
const Coordinates=preload("res://scripts/three_d/world_coordinates.gd")
var app: Node
func _initialize() -> void: run.call_deferred()
func capture(name: String, point: Vector2, distance: float) -> void:
	var rig: Node3D=app.map_view.camera_rig
	rig.focus_at(Coordinates.to_world(point)); rig.target_distance=distance; rig.target_pitch=65; rig.target_yaw=0; rig.snap()
	for _frame in range(15): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/living_city/"+name+".png")
func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://outputs/living_city")
	root.gui_embed_subwindows=true
	app=preload("res://scenes/main.tscn").instantiate(); root.add_child(app)
	app.set_process(false); app.manager.set_process(false); app.manager.ai_bridge.set_process(false)
	app.manager.ai_config.enabled=false; app.manager.social.config.spontaneous_actions=false
	app.manager.social.close(); app.manager.social.next_send=INF
	app.intro_panel.hide(); Map.interior_cutaway=true
	var school_id: String=app.manager.social.daily.room_for("School")
	await capture("school-interior",app.manager.social.daily.interiors.rooms[school_id].center,65)
	var adult: Dictionary=app.manager.agents.filter(func(a):return a.get("indoor_id","")!="" and a.age>=18 and app.manager.social.daily.interiors.rooms[a.indoor_id].kind in ["Home","Apartment"])[0]
	await capture("home-interior",app.manager.social.daily.interiors.rooms[adult.indoor_id].center,65)
	app.manager.start()
	for _step in range(80): app.manager.advance_clock(.1); await process_frame
	await capture("living-city",Map.grove.center,155)
	app.manager.social.close(); app.queue_free(); await process_frame; quit()
