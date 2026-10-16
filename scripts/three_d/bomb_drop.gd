extends Node3D
## Authoritative eight-second descent; animation and audio follow the simulation clock.
const Geometry = preload("res://scripts/three_d/geometry.gd")
var manager: Node
var bomb: Node3D
var plane: Node3D
var whistle: AudioStreamPlayer

func _ready() -> void:
	var target: Array = manager.nuclear["impact_position"]
	position = preload("res://scripts/three_d/world_coordinates.gd").to_world(Vector2(target[0],target[1]))
	plane = Node3D.new()
	add_child(plane)
	var fuselage := Geometry.cylinder(plane,0.9,18,Vector3.ZERO,Color("707c7e"))
	fuselage.rotation.z = PI/2
	Geometry.box(plane,Vector3(4,0.3,24),Vector3.ZERO,Color("899293"))
	Geometry.box(plane,Vector3(2,0.25,9),Vector3(-7,0,0),Color("899293"))
	Geometry.box(plane,Vector3(2,3.5,0.3),Vector3(-7,1.3,0),Color("737f80"))
	Geometry.box(plane,Vector3(2.4,0.65,1.4),Vector3(5.5,0.75,0),Color("3e626f"))
	for side in [-1,1]:
		var engine := Geometry.cylinder(plane,0.45,3.4,Vector3(0,-0.5,side*5.5),Color("566367"))
		engine.rotation.z = PI/2
	bomb = Node3D.new()
	add_child(bomb)
	Geometry.cylinder(bomb,0.65,3.5,Vector3.ZERO,Color("444c42"))
	var nose := Geometry.cylinder(bomb,0.65,0.9,Vector3(0,-2.1,0),Color("30382f"))
	nose.mesh.bottom_radius = 0.05
	Geometry.box(bomb,Vector3(2,0.7,0.12),Vector3(0,1.5,0),Color("686f54"))
	Geometry.box(bomb,Vector3(0.12,0.7,2),Vector3(0,1.5,0),Color("686f54"))
	whistle = AudioStreamPlayer.new()
	whistle.stream = load("res://assets/audio/warnings/bomb_dropping_cc0.mp3")
	whistle.bus = "ESSAIMWarnings"
	whistle.volume_db = -12
	whistle.pitch_scale = whistle.stream.get_length()/float(manager.activity_config["bomb_fall_seconds"])
	add_child(whistle)
	whistle.play(manager.bomb_fall_elapsed*whistle.pitch_scale)
	_process(0)

func _process(_delta: float) -> void:
	if manager.phase != "BOMB_FALL":
		whistle.stop()
		visible = false
		return
	whistle.stream_paused = not manager.running
	var t := clampf(manager.bomb_fall_elapsed/float(manager.activity_config["bomb_fall_seconds"]),0,1)
	plane.position = Vector3(-35+t*220,130+t*4,0)
	bomb.position = Vector3(-35*(1-t),130*(1-t*t),0)
	bomb.rotation.z = -0.12*(1-t)
