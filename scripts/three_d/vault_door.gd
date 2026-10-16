extends Node3D
const Geometry = preload("res://scripts/three_d/geometry.gd")
const STATES := ["OPEN","CLOSING","CLOSED","OPENING","JAMMED","DESTROYED"]
var state := "OPEN"
var target_state := "OPEN"
var plate: Node3D
var animation: Tween
var blocker: StaticBody3D
func _ready() -> void:
	plate = Node3D.new()
	add_child(plate)
	var disk := Geometry.cylinder(plate,2.0,0.55,Vector3.ZERO,Color("79858a"))
	disk.rotation.x = PI/2
	disk.material_override.metallic = 0.8
	disk.material_override.roughness = 0.7
	for i in range(8):
		var angle := i*TAU/8
		var brace := Geometry.box(plate,Vector3(0.13,1.25,0.12),Vector3(sin(angle)*1.15,cos(angle)*1.15,-0.34),Color("929b96") if i%2 == 0 else Color("657275"))
		brace.rotation.z = -angle
	for i in range(12):
		var angle := i*TAU/12
		var tooth := Geometry.box(plate,Vector3(0.65,0.65,0.7),Vector3(sin(angle)*2,cos(angle)*2,0),Color("4e5c62"))
		tooth.rotation.z = -angle
	var hub := Geometry.cylinder(plate,0.7,0.85,Vector3(0,0,-0.2),Color("bac0b4"))
	hub.rotation.x = PI/2
	plate.position.x = 4.4
	blocker = Geometry.collider(self,Vector3(4.4,4.4,0.7),Vector3.ZERO)
	blocker.collision_layer = 0
func set_state(value: String) -> void:
	if value == "BLOCKED": value = "JAMMED"
	if value not in STATES or value == target_state: return
	if animation: animation.kill()
	target_state = value
	if blocker: blocker.collision_layer = 0 if value in ["OPEN","OPENING"] else 1
	state = "CLOSING" if value == "CLOSED" else "OPENING" if value == "OPEN" else value
	if not is_instance_valid(plate): return
	animation = create_tween()
	animation.tween_property(plate,"position:x",4.4 if value in ["OPEN","OPENING"] else 0.0,0.8)
	if value == "DESTROYED":
		animation.parallel().tween_property(plate,"rotation:z",1.0,0.8)

	animation.finished.connect(func(): state = target_state)
