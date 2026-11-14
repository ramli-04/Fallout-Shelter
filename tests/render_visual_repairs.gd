extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var world:=Node3D.new(); root.add_child(world)
	var environment:=WorldEnvironment.new(); var env:=Environment.new(); env.background_mode=Environment.BG_COLOR; env.background_color=Color("d5dfdf"); env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color=Color.WHITE; env.ambient_light_energy=.7; environment.environment=env; world.add_child(environment)
	var light:=DirectionalLight3D.new(); world.add_child(light); light.rotation_degrees=Vector3(-55,-30,0); light.light_energy=.65; light.shadow_enabled=true
	var g=preload("res://scripts/three_d/geometry.gd")
	g.box(world,Vector3(100,.2,100),Vector3(0,-.2,0),Color("a2ad98"))
	for i in range(6):
		var p:=Vector2((i-2.5)*16,0)
		var a=preload("res://scenes/three_d/agent.tscn").instantiate()
		a.configure({"id":"A%d"%i,"position":p,"previous_position":p,"population_index":i,"appearance_seed":i*72,"role":"Civilian" if i<3 else "Authority","visual_category":["civilian","civilian","civilian","police","medical","fire"][i],"state":"IDLE","route":PackedVector2Array(),"route_index":0,"riding":"","health":100.0,"age":30})
		world.add_child(a)
	var camera:=Camera3D.new(); world.add_child(camera); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=12; camera.position=Vector3(7,7,12); camera.look_at(Vector3(0,1,0)); camera.current=true
	for i in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/repaired-characters.png")
	var map=preload("res://scripts/city_map.gd")
	map.lots.assign([Rect2(-90,-90,180,180)]); map.lot_angles.assign([0.0]); map.lot_districts.assign(["RESIDENTIAL"])
	map.building_data.assign([{"asset_variant":1,"height_m":15,"style":"perimeter"}]); map.interior_data={}; map.pois.clear()
	var building=preload("res://scripts/three_d/building_3d.gd").new(); building.visual_only=true; building.configure(map.lots[0],0); world.add_child(building)
	assert(building.get_node_or_null("StreetFacade")==null)
	camera.size=30; camera.position=Vector3(27,23,30); camera.look_at(Vector3(0,7,0))
	for i in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/repaired-building.png")
	for kind in ["house","fire","police","office","medical"]:
		building.free()
		map.lot_districts[0]="GROVE" if kind=="house" else "DOWNTOWN" if kind=="office" else "SERVICES"
		map.building_data[0].height_m=25 if kind=="office" else 5.5
		map.pois.clear()
		if kind in ["fire","police","medical"]: map.pois.append({"footprint":map.lots[0],"kind":{"fire":"Fire Station","police":"Police Station","medical":"Medical Station"}[kind]})
		building=preload("res://scripts/three_d/building_3d.gd").new(); building.visual_only=true; building.configure(map.lots[0],0); world.add_child(building)
		camera.size=38 if kind in ["office","medical"] else 25; camera.position=Vector3(27,23,30); camera.look_at(Vector3(0,12 if kind in ["office","medical"] else 4,0))
		for i in range(8): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://outputs/reference-"+kind+".png")
	world.queue_free(); await process_frame; quit()
