extends SceneTree
func _initialize() -> void:
	var buildings=preload("res://scripts/three_d/building_sprites.gd")
	var art=preload("res://scripts/three_d/reference_sprite_catalog.gd")
	var vehicles=preload("res://scripts/three_d/runtime_model_catalog.gd")
	var checks:=0
	for kind in buildings.scale_definition.width_metres:
		var first:=buildings.registration(kind,art.REGIONS[kind],Vector2(8,7))
		var second:=buildings.registration(kind,art.REGIONS[kind],Vector2(36,40))
		assert(first==second); checks+=1
	var paths: Dictionary={}
	for model in preload("res://scripts/vehicle_catalog.gd").TYPES:
		var path: String=vehicles.vehicle_path(model,"Civilian")
		var dimensions: Vector3=vehicles.vehicle_dimensions(model)
		if not path.is_empty():
			if paths.has(path): assert(paths[path]==dimensions)
			paths[path]=dimensions
		var small=preload("res://scripts/three_d/vehicle_3d.gd").new()
		var large=preload("res://scripts/three_d/vehicle_3d.gd").new()
		small.configure({"model":model,"length":10,"width":8,"body_height":.5})
		large.configure({"model":model,"length":100,"width":40,"body_height":6})
		assert(Vector3(small.width,small.height,small.length)==Vector3(large.width,large.height,large.length)); checks+=1
		small.free(); large.free()
	assert(preload("res://scripts/three_d/grass_material.gd").TILE_METRES==1.0); checks+=1
	print("Fixed artwork dimensions: %d checks passed"%checks); quit()
