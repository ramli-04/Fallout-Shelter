extends Node3D
const STATES := ["OPEN","CLOSING","CLOSED","OPENING","JAMMED","DESTROYED"]
const G = preload("res://scripts/three_d/geometry.gd")
var state := "OPEN"
var target_state := "OPEN"
var plate: Node3D
var animation: Tween
var blocker: StaticBody3D

func _ready() -> void:
	plate = Node3D.new()
	add_child(plate)
	var disk := G.cylinder(plate,3.45,0.42,Vector3.ZERO,Color("738487"))
	disk.material_override.metallic = 0.8
	for radius in [0.8,1.65,2.6,3.3]:
		var ring := G.ring(plate,radius,Color("b1b6a5"))
		ring.position.y = 0.24
	for i in range(10):
		var angle := i*TAU/10
		var brace := G.box(plate,Vector3(0.15,0.12,1.8),Vector3(sin(angle)*2.0,0.26,cos(angle)*2.0),Color("657473"))
		brace.rotation.y = angle
		G.cylinder(plate,0.13,0.12,Vector3(sin(angle)*3.0,0.28,cos(angle)*3.0),Color("d1ba73"))
	G.cylinder(plate,0.6,0.32,Vector3(0,0.32,0),Color("b6aa82"))
	plate.position = Vector3(5.9,0.9,0)
	blocker = G.collider(self,Vector3(6.8,0.7,6.8),Vector3(0,0.65,0))
	blocker.collision_layer = 0

func set_state(value: String) -> void:
	if value == "BLOCKED": value = "JAMMED"
	if value not in STATES or value == target_state: return
	if animation: animation.kill()
	target_state = value
	state = "CLOSING" if value == "CLOSED" else "OPENING" if value == "OPEN" else value
	var open := value in ["OPEN","OPENING"]
	blocker.collision_layer = 0 if open else 1
	animation = create_tween()
	# Hydraulic lift, then lateral translation: never sweep a plate through the stairs.
	animation.tween_property(plate,"position:y",1.15,0.25)
	animation.tween_property(plate,"position:x",5.9 if open else 0.0,0.6)
	animation.tween_property(plate,"position:y",0.9 if open else 0.67,0.25)
	if value == "DESTROYED": animation.parallel().tween_property(plate,"rotation:z",0.2,0.4)

	animation.finished.connect(func(): state = target_state)
