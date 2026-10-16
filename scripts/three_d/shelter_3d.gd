extends Node3D
## Physical entrance is created only for an existing shelter. Threshold is the model destination.
const Coordinates = preload("res://scripts/three_d/world_coordinates.gd")
const Geometry = preload("res://scripts/three_d/geometry.gd")
var vault: Node3D
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
	var mountain: bool = record["id"] in ["S4","S5"]
	vault = preload("res://scenes/three_d/VaultEntrance.tscn").instantiate() if mountain else preload("res://scenes/three_d/FloorVault.tscn").instantiate()
	vault.position.z = 4.5
	vault.rotation.y = PI if mountain else 0.0
	add_child(vault)
	Geometry.box(self,Vector3(5.5,0.035,5.5),Vector3(0,0.015,2.2),Color("576d70"))
	Geometry.box(self,Vector3(4.8,0.025,0.35),Vector3(0,0.045,0),color)
	if mountain:
		# Deep rock shoulders and a recessed canopy integrate the vertical entrance.
		for side in [-1,1]:
			for layer in range(3):
				var rock := MeshInstance3D.new()
				var mesh := SphereMesh.new()
				mesh.radius = 5.5
				mesh.height = 12+layer*2
				mesh.radial_segments = 7
				mesh.rings = 4
				rock.mesh = mesh
				rock.material_override = Geometry.material(Color("7b8174"))
				rock.position = Vector3(side*(6.5+layer*2),2.5,8+layer*3)
				rock.rotation = Vector3(0.1*side,layer*0.5,0.1*side)
				add_child(rock)
				Geometry.collider(self,Vector3(5,8,8),rock.position)
		var canopy := Geometry.cylinder(self,7,5,Vector3(0,6.2,11),Color("7e8577"))
		canopy.mesh.radial_segments = 7
		canopy.mesh.top_radius = 3.0
	elif record["id"] == "S3":
		Geometry.cylinder(self,0.12,7,Vector3(-8,3.5,6),Color("d8e3e0"))
		Geometry.cylinder(self,1.1,0.15,Vector3(-8,6.8,6),color)
		Geometry.box(self,Vector3(2,0.4,2),Vector3(-8,0.2,6),Color("87958d"))
	var purposes := {"S1":"PUBLIC REFUGE","S2":"METRO VAULT","S3":"COMMUNICATIONS","S4":"MOUNTAIN OUTPOST","S5":"EXPERIMENTAL"}
	Geometry.label(self,purposes[record["id"]],Vector3(0,7.8 if mountain else 5.5,4.5),color,25,0.03)
	Geometry.label(self,record["id"],Vector3(0,6.5 if mountain else 4.1,3.2),color,54,0.032)
	status_label = Geometry.label(self,"OPEN",Vector3(0,5.5 if mountain else 3.0,2.8),Color.WHITE,24,0.02)
	status_lamp = Geometry.cylinder(self,0.28,0.35,Vector3(-4,1.2,0.5),Color("66d9bb"))
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
	if vault != null:
		vault.door.set_state(record["door_status"])
		var structural: String = record.get("structural_state", "INTACT")
		if structural == "DESTROYED": vault.door.set_state("DESTROYED")
		vault.scale.y = 0.4 if structural == "DESTROYED" else 1.0
	var open: bool = record["operational"] and record["accepting"] and record["door_status"] == "OPEN" and record["occupancy"] < record["capacity"]
	status_lamp.material_override.albedo_color = Color("66d9bb") if open else Color("ed7587")
	status_label.text = "DESTROYED" if record.get("structural_state", "INTACT") == "DESTROYED" else "OPEN" if open else "BLOCKED" if record["door_status"] == "BLOCKED" else "UNAVAILABLE"

func set_selected(value: bool) -> void:
	is_selected = value
	selection_ring.visible = value
