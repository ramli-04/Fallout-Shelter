extends SceneTree
const Sprites=preload("res://scripts/three_d/building_sprites.gd")
const Art=preload("res://scripts/three_d/reference_sprite_catalog.gd")
func _initialize() -> void:
	var checks:=0
	for kind in Sprites.GROUND_DEPTH:
		var result:=Sprites.registration(kind,Art.REGIONS[kind],Vector2(16,12))
		assert(result.width<(16+12)*.70710678)
		# The calibrated contact centre projects onto parcel centre at 30 degrees.
		var contact_y: float=result.height*.47-result.ground_depth*.5
		assert(absf(result.anchor*cos(deg_to_rad(30))-contact_y)<.0001)
		assert(result.height>0 and result.ground_depth>0); checks+=3
	var roads=preload("res://scripts/three_d/reference_road_tiles.gd")
	assert(roads.material(2).get_shader_parameter("sheet")!=null)
	assert(roads.material(4).get_shader_parameter("sheet")!=null)
	print("Sprite registration: %d checks, road axes passed"%checks); quit()
