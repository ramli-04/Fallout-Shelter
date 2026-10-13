extends Node3D
const Geometry = preload("res://scripts/three_d/geometry.gd")
var door: Node3D
func _ready() -> void:
	for side in [-1,1]:
		Geometry.box(self,Vector3(1.4,5.5,3),Vector3(side*3,2.5,1),Color("92988e"))
		Geometry.cylinder(self,0.22,3.0,Vector3(side*2.7,2.5,-0.5),Color("c3c7b6"))
	Geometry.box(self,Vector3(7.4,1.0,3.5),Vector3(0,5,1),Color("808a83"))
	var frame := Geometry.ring(self,2.45,Color("b3b19a"))
	frame.rotation.x = PI/2
	frame.position = Vector3(0,2.5,-0.4)
	door = preload("res://scenes/three_d/VaultDoor.tscn").instantiate()
	door.position = Vector3(0,2.5,0.3)
	add_child(door)
