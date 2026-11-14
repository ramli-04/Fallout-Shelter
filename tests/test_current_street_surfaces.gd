extends SceneTree
func _initialize() -> void:
	var art=preload("res://scripts/three_d/street_surface_art.gd")
	var texture:=art.texture(); var image:=texture.get_image()
	if image.is_compressed(): image.decompress()
	var checks:=0
	for name in art.config.tiles:
		var resource: AtlasTexture=load("res://assets/Roads/current_"+name+".tres")
		assert(resource.atlas==texture); checks+=1
		var r:=art.region(name)
		for uv in [Vector2(.15,.15),Vector2(.5,.5),Vector2(.85,.85)]:
			var pixel:=Vector2((r.x+r.z*uv.x)*image.get_width(),(r.y+r.w*uv.y)*image.get_height())
			assert(image.get_pixel(int(pixel.x),int(pixel.y)).a>.8); checks+=1
	for lanes in [2,4,-1,-2]:
		var material=preload("res://scripts/three_d/reference_road_tiles.gd").material(lanes)
		assert(material.get_shader_parameter("sheet")==texture); checks+=1
		assert(material.get_shader_parameter("parking")==(lanes==-2)); checks+=1
	assert(preload("res://scripts/three_d/road_ground_art.gd").paving_material(false).get_shader_parameter("atlas")==texture); checks+=1
	print("Current street surfaces: %d checks passed"%checks); quit()
