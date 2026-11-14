extends SceneTree
const Art=preload("res://scripts/three_d/reference_sprite_catalog.gd")
const Buildings=preload("res://scripts/three_d/building_sprites.gd")
const Map=preload("res://scripts/city_map.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var checks:=0
	for kind in Art.REGIONS:
		var texture: Texture2D=Art.atlas(kind); var rect: Rect2=Art.REGIONS[kind]
		assert(texture!=null and Rect2(Vector2.ZERO,texture.get_size()).encloses(rect)); checks+=1
	Map.lots.assign([Rect2(-45,-40,90,80)]); Map.lot_districts.assign(["GROVE"]); Map.lot_angles.assign([0.0]); Map.pois.clear()
	var data:=Buildings.info({"size":Vector2(9,8),"roof":true,"height":5.5,"chimneys":false},0)
	assert(data.key.begins_with("sheet:new_house0:")); checks+=1
	var material:=Buildings.material(data.key)
	assert(material.get_shader_parameter("artwork")==Art.atlas("new_house0")); checks+=1
	assert(material.get_shader_parameter("uv_region").z<1); checks+=1
	for lanes in [2,4,-1]:
		assert(preload("res://scripts/three_d/reference_road_tiles.gd").material(lanes).get_shader_parameter("sheet")==preload("res://scripts/three_d/road_ground_art.gd").texture()); checks+=1
	print("Reference artwork integration: %d checks passed"%checks); quit()
