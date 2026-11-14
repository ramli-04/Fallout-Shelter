extends SceneTree
const Map=preload("res://scripts/city_map.gd")
const C=preload("res://scripts/three_d/world_coordinates.gd")
var app: Node
func _initialize() -> void: run.call_deferred()
func capture(name: String, point: Vector2, distance: float, pitch: float, yaw: float) -> void:
	var rig: Node3D=app.map_view.camera_rig
	rig.focus_at(C.to_world(point)); rig.target_distance=distance; rig.target_pitch=pitch; rig.target_yaw=yaw; rig.snap()
	for i in range(15): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/streetscape/"+name+".png")
func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://outputs/streetscape"); root.gui_embed_subwindows=true
	app=preload("res://scenes/main.tscn").instantiate(); root.add_child(app)
	app.set_process(false); app.manager.set_process(false); app.manager.ai_bridge.set_process(false); app.manager.ai_config.enabled=false
	app.manager.social.close(); app.manager.social.next_send=INF; app.intro_panel.hide(); app.map_view.blast_zones.hide(); Map.interior_cutaway=false
	var best: Dictionary={}; var count:=-1
	for road in Map.roads:
		if road.get("elevated",false) or road.get("ramp",false) or road.kind!="boulevard" or road.a.distance_to(road.b)<550: continue
		var point: Vector2=road.points[int(road.points.size()/2.0)]
		var nearby: int=Map.lots.filter(func(rect):return rect.get_center().distance_to(point)<430).size()
		if nearby>count: count=nearby; best=road
	var point: Vector2=best.points[int(best.points.size()/2.0)]
	var tangent: Vector2=(best.b-best.a).normalized()
	await capture("street-frontages",point,95,35,-rad_to_deg(tangent.angle())+70)
	await capture("block-overview",point,190,60,0)
	var node: int=best.to
	await capture("traffic-lights",Map.graph.get_point_position(node),95,55,25)
	await capture("shelter-plaza",Map.sites.S1,80,55,0)
	var details: Node=app.map_view.city.get_node("ValleyEnvironment/CityDetails")
	print("Streetscape preview: %d buildings / %d signal heads / %d junction controllers"%[Map.lots.size(),details.signals.size(),Map.traffic_signals.size()])
	app.queue_free(); await process_frame; await process_frame; quit()
