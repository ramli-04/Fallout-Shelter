extends SceneTree
func _initialize() -> void:
	var art=preload("res://scripts/three_d/road_ground_art.gd")
	var count: int=art.export_resources()
	assert(ResourceSaver.save(preload("res://scripts/three_d/grass_material.gd").material(),"res://assets/Nature/Grass/patchy_grass.tres")==OK)
	print("Road/ground collection: ",count," categorized atlas resources"); quit()
