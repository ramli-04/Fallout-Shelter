extends Node3D
## Physical entrance is created only for an existing shelter. Threshold is the model destination.
const Coordinates = preload("res://scripts/three_d/world_coordinates.gd")
const Geometry = preload("res://scripts/three_d/geometry.gd")
var record: Dictionary = {}
var is_selected := false
var entrance_position := Vector3.ZERO
var selection_ring: MeshInstance3D
var status_lamp: MeshInstance3D
var status_label: Label3D
var selection_area: Area3D

func configure(data: Dictionary) -> void:
	record = data
	position = Coordinates.to_world(record["position"])
	entrance_position = position
	if status_lamp != null: _update_status()

func _ready() -> void:
	assert(record.get("exists", false),"An absent shelter must not have a physical entrance.")
	var color := Color(record["color"])
	# Columns occupy the unused corners between sidewalks and original building footprints.
	# The admission threshold at local (0,0,0) and both crossing roads stay unobstructed.
	for side in [-1,1]:
		Geometry.box(self,Vector3(0.55,3.3,0.55),Vector3(side*4.1,1.65,4.1),Color("cbd1c8"))
		var collider := Geometry.collider(self,Vector3(0.55,3.3,0.55),Vector3(side*4.1,1.65,4.1),1|2)
		collider.set_meta("entity_owner",self)
	Geometry.box(self,Vector3(8.75,0.5,2.2),Vector3(0,3.3,4.1),color)
	Geometry.box(self,Vector3(5.5,0.035,5.5),Vector3(0,0.015,2.2),Color("576d70"))
	Geometry.box(self,Vector3(4.8,0.025,0.35),Vector3(0,0.045,0),color)
	if record["id"] == "S2":
		for step in range(5):
			Geometry.box(self,Vector3(3.5,0.08,0.55),Vector3(0,0.28-step*0.045,1.0+step*0.55),Color("829597"))
		Geometry.label(self,"METRO",Vector3(0,4.65,4.1),color,32,0.025)
	elif record["id"] == "S3":
		Geometry.cylinder(self,0.10,4.5,Vector3(2.8,5.4,4.1),Color("d8e3e0"))
		Geometry.cylinder(self,0.9,0.15,Vector3(2.8,7.2,4.1),color)
	else:
		Geometry.box(self,Vector3(1.7,0.45,1.4),Vector3(2.2,3.9,4.1),Color("829b99"))
	Geometry.label(self,record["id"],Vector3(0,4.0,3.2),color,54,0.032)
	status_label = Geometry.label(self,"OPEN",Vector3(0,2.8,2.8),Color.WHITE,24,0.02)
	status_lamp = Geometry.cylinder(self,0.28,0.35,Vector3(-3.0,3.8,4.1),Color("66d9bb"))
	selection_ring = Geometry.ring(self,3.1,Color("ffe8a3"))
	selection_ring.position.y = 0.06
	selection_ring.visible = false
	selection_area = Area3D.new()
	selection_area.collision_layer = 2
	selection_area.collision_mask = 0
	selection_area.set_meta("entity_owner",self)
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(8.8,4.0,5.5)
	shape_node.shape = shape
	shape_node.position = Vector3(0,2.0,2.2)
	selection_area.add_child(shape_node)
	add_child(selection_area)
	_update_status()

func _update_status() -> void:
	var open: bool = record["operational"] and record["accepting"] and record["door_status"] == "OPEN" and record["occupancy"] < record["capacity"]
	status_lamp.material_override.albedo_color = Color("66d9bb") if open else Color("ed7587")
	status_label.text = "OPEN" if open else "BLOCKED" if record["door_status"] == "BLOCKED" else "UNAVAILABLE"

func set_selected(value: bool) -> void:
	is_selected = value
	selection_ring.visible = value
