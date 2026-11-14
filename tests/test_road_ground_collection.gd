extends SceneTree
const Art=preload("res://scripts/three_d/road_ground_art.gd")
func _initialize() -> void:
	var config:=Art.configuration(); var image:=Art.texture().get_image(); var ratio:=Vector2(image.get_size())/Art.vector(config.source_size); var checks:=0
	for group in [config.roads,config.grass]:
		for name in group:
			var record: Dictionary=group[name]
			assert(load("res://assets/"+record.category+"/"+name+".tres") is AtlasTexture); checks+=1
	for name in config.grass:
		var record: Dictionary=config.grass[name]
		for uv in [Vector2(.15,.15),Vector2(.5,.5),Vector2(.85,.85)]:
			var pixel: Vector2=(Art.vector(record.top)+Art.vector(record.cross)*uv.x+Art.vector(record.along)*uv.y)*ratio
			assert(image.get_pixel(int(pixel.x),int(pixel.y)).a>.5); checks+=1
	var grass=preload("res://scripts/three_d/grass_material.gd").material()
	assert(grass.get_shader_parameter("atlas")==Art.texture()); assert(grass.get_shader_parameter("tops").size()==13)
	for lanes in [2,4,5,-1]:
		var material=preload("res://scripts/three_d/reference_road_tiles.gd").material(lanes)
		assert(material.get_shader_parameter("sheet")==Art.texture()); assert(material.get_shader_parameter("node_top").size()==18); checks+=2
	print("Road and ground atlas: %d checks passed"%checks); quit()
