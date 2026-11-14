extends SceneTree
const Map=preload("res://scripts/city_map.gd")
const Architecture=preload("res://scripts/three_d/reference_architecture.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/building_sprites"))
	var viewport:=SubViewport.new(); viewport.size=Vector2i(512,512); viewport.transparent_bg=true; viewport.own_world_3d=true; viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var world:=Node3D.new(); viewport.add_child(world)
	var environment:=WorldEnvironment.new(); var env:=Environment.new(); env.background_mode=Environment.BG_CLEAR_COLOR; env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color=Color.WHITE; env.ambient_light_energy=.65; environment.environment=env; world.add_child(environment)
	var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-55,-30,0); sun.light_energy=.65; world.add_child(sun)
	var camera:=Camera3D.new(); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; world.add_child(camera); camera.current=true
	var manifest: Dictionary={}
	for kind in ["house","house_small","house_large","townhouse","motel","apartment_low","apartment","office","industrial","fire","police","medical","school"]:
		var size:=Vector2(12,10); var height:=15.0
		if kind.begins_with("house") or kind=="townhouse": size=Vector2(9,8); height=5.5
		if kind=="house_small": height=4.3
		if kind=="house_large": size=Vector2(12,10); height=8
		if kind=="townhouse": size=Vector2(18,9); height=8
		if kind=="motel": size=Vector2(24,10); height=6
		if kind=="apartment_low": height=9
		if kind=="industrial": size=Vector2(20,14); height=6
		if kind in ["fire","police","school"]: size=Vector2(23,14.5); height=7
		if kind=="medical": size=Vector2(23,22); height=22
		Map.lots.assign([Rect2(-size*5,size*10),Rect2(-size*5,size*10),Rect2(-size*5,size*10)]); Map.lot_districts.assign(["GROVE" if kind.begins_with("house") or kind=="townhouse" else "DOWNTOWN" if kind=="office" else "RESIDENTIAL"]); Map.lot_districts.assign([Map.lot_districts[0],Map.lot_districts[0],Map.lot_districts[0]]); Map.pois.clear()
		if kind in ["fire","police","medical","school"]: Map.pois.append({"footprint":Map.lots[0],"kind":{"fire":"Fire Station","police":"Police Station","medical":"Medical Station","school":"School"}[kind]})
		var recipe={"size":size,"height":height,"color":Color("865744"),"roof":kind.begins_with("house") or kind=="townhouse","chimneys":kind=="industrial","interior":{},"wings":[[Vector3(size.x,height,size.y),Vector3.ZERO,Color("865744")]]}
		if kind.begins_with("house"):
			recipe.wings=[[Vector3(size.x*.70,height,size.y*.82),Vector3(-size.x*.15,0,-size.y*.09),recipe.color],[Vector3(size.x*.30,height*.65,size.y*.72),Vector3(size.x*.35,0,size.y*.14),recipe.color]]
		if kind=="townhouse":
			recipe.wings=[]
			for unit in range(3): recipe.wings.append([Vector3(size.x/3,height,size.y),Vector3((unit-1)*size.x/3,0,0),recipe.color])
		if kind=="fire":
			recipe.wings=[[Vector3(19,6,14.5),Vector3(-2,0,0),recipe.color],[Vector3(4,11,10),Vector3(9.5,0,-2.25),recipe.color]]
		if kind=="police":
			recipe.wings=[[Vector3(17,8,14.5),Vector3(-3,0,0),recipe.color],[Vector3(6,4,11),Vector3(8.5,0,1.75),recipe.color]]
		if kind=="medical":
			recipe.wings=[[Vector3(14,22,14),Vector3(0,0,-4),recipe.color],[Vector3(23,7,8),Vector3(0,0,7),recipe.color]]
		var model:=Node3D.new(); world.add_child(model); Architecture.new().build(model,recipe,1 if kind=="house_small" else 2 if kind=="house_large" else 0)
		var G=preload("res://scripts/three_d/geometry.gd")
		if kind.begins_with("house"):
			G.box(model,Vector3(size.x*.45,.15,1.4),Vector3(-size.x*.17,2.6,size.y*.40),Color("b8b2a3"))
			for x in [-size.x*.36,size.x*.04]: G.box(model,Vector3(.14,2.6,.14),Vector3(x,1.3,size.y*.44),Color("b8b2a3"))
			G.box(model,Vector3(size.x*.26,2,.06),Vector3(size.x*.35,1,size.y*.505),Color("b4b7ae"))
		if kind=="motel":
			for level in [0,1]:
				G.box(model,Vector3(size.x,.12,1),Vector3(0,level*3+.15,size.y*.5),Color("aaa692"))
				for door in range(8): G.box(model,Vector3(.9,2,.08),Vector3((door-3.5)*2.8,level*3+1,size.y*.51),Color("794f3e"))
		if kind=="medical":
			G.box(model,Vector3(7,.3,4),Vector3(0,3.5,10),Color("b7b4a5"))
			for x in [-3,3]: G.box(model,Vector3(.3,3.5,.3),Vector3(x,1.75,11),Color("a7a493"))
			G.box(model,Vector3(8,.1,7),Vector3(0,22.5,-4),Color("454e51"))
			var label=G.label(model,"H",Vector3(0,22.58,-4),Color.WHITE,80,.045); label.billboard=BaseMaterial3D.BILLBOARD_DISABLED; label.rotation.x=-PI*.5
			var entrance=G.label(model,"EMERGENCY",Vector3(0,3.5,12.1),Color("b13f35"),40,.012); entrance.billboard=BaseMaterial3D.BILLBOARD_DISABLED

		var extent:=maxf((size.x+size.y)*.7072,height*.82+(size.x+size.y)*.41)*1.15
		manifest[kind]={"size":[size.x,size.y],"height":height,"extent":extent,"anchor":height*.4,"facings":72}
		for facing in range(72):
			model.rotation.y=facing*TAU/72
			camera.size=extent; var target:=Vector3(0,height*.4,0); camera.position=target+Vector3(50,50,50); camera.look_at(target)
			for i in range(3): await process_frame
			await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png("res://assets/building_sprites/%s_%d.png"%[kind,facing])
		model.free()
	var file:=FileAccess.open("res://assets/building_sprites/catalog.json",FileAccess.WRITE); file.store_string(JSON.stringify(manifest,"	")); file.close()
	viewport.queue_free(); await process_frame; print("Baked building sprite library"); quit()
