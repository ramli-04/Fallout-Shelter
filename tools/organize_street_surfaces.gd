extends SceneTree
func _initialize() -> void:
	preload("res://scripts/three_d/street_surface_art.gd").export_resources()
	print("Current street surface atlas: 15 resources exported"); quit()
