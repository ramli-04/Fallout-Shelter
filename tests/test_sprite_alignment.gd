extends SceneTree
const Art=preload("res://scripts/three_d/building_sprites.gd")
const Map=preload("res://scripts/city_map.gd")
func _initialize() -> void:
	Map.lots.assign([Rect2(-45,-40,90,80)]); Map.lot_districts.assign(["GROVE"]); Map.lot_angles.assign([0.0]); Map.pois.clear()
	var recipe={"roof":true,"height":5.5,"size":Vector2(9,8),"chimneys":false}
	var checks:=0
	for angle in [0,90,180,270]:
		Map.lot_angles[0]=deg_to_rad(angle)
		var info:=Art.info(recipe,0)
		assert(info.key=="sheet:new_house0:%d"%(angle/90)); checks+=1
		var material:=Art.material(info.key)
		assert(material.get_shader_parameter("mirror")== (angle in [90,180])); checks+=1
	print("Reference sheet frontage alignment: %d checks passed"%checks); quit()
