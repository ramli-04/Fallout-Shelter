extends SceneTree
const Art=preload("res://scripts/three_d/building_sprites.gd")
const Map=preload("res://scripts/city_map.gd")
func _initialize() -> void: run.call_deferred()
func capture(view: SubViewport) -> Image:
	for i in range(3): await process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()
func run() -> void:
	var view:=SubViewport.new(); view.size=Vector2i(400,400); view.transparent_bg=true; view.own_world_3d=true; view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(view)
	var world:=Node3D.new(); view.add_child(world)
	var camera:=Camera3D.new(); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=22; world.add_child(camera); camera.position=Vector3(20,20,20); camera.look_at(Vector3(0,2,0)); camera.current=true
	var ground:=MeshInstance3D.new(); var box:=BoxMesh.new(); box.size=Vector3(100,.1,100); ground.mesh=box; ground.position.y=-.05
	var material:=StandardMaterial3D.new(); material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; material.albedo_color=Color.GREEN; ground.material_override=material; world.add_child(ground)
	Map.lots.assign([Rect2(-45,-40,90,80)]); Map.lot_angles.assign([0.0]); Map.lot_districts.assign(["GROVE"]); Map.pois.clear()
	var recipe={"roof":true,"height":5.5,"size":Vector2(9,8),"chimneys":false}
	var failed:=0
	for distant in [false,true]:
		var sprite: Node3D
		if not distant: sprite=Art.build(world,recipe,0)
		else:
			var info:=Art.info(recipe,0); var batch:=MultiMeshInstance3D.new(); var multi:=MultiMesh.new(); multi.transform_format=MultiMesh.TRANSFORM_3D; var quad:=QuadMesh.new(); quad.size=Vector2.ONE; multi.mesh=quad; multi.instance_count=1; multi.set_instance_transform(0,Transform3D(Basis.from_scale(Vector3(info.width,info.height,1)),Vector3(0,info.anchor,0))); batch.multimesh=multi; batch.material_override=Art.material(info.key); world.add_child(batch); sprite=batch
		ground.hide(); var reference: Image=await capture(view)
		ground.show(); var actual: Image=await capture(view)
		var erased:=0; var pixels:=0
		for x in range(400):
			for y in range(200,400):
				var expected:=reference.get_pixel(x,y)
				if expected.a<.95: continue
				pixels+=1
				var color:=actual.get_pixel(x,y)
				if absf(expected.r-color.r)+absf(expected.g-color.g)+absf(expected.b-color.b)>.15: erased+=1
		if pixels<100 or erased>pixels*.01: failed+=1; printerr("Sprite base erased: ",erased,"/",pixels," overview=",distant)
		sprite.free()
	view.queue_free(); await process_frame; print("Sprite ground depth: close and overview, %d failures"%failed); quit(1 if failed else 0)
