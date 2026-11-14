extends Node3D
var record: Dictionary={}
var selection_area: Area3D

func _init() -> void: set_meta("roadblock",true)

func set_selected(value: bool) -> void:
	for child in get_children():
		if child is Label3D: child.modulate=Color.WHITE if value else Color("eddbb1")
