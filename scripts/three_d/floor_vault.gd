extends Node3D
## Horizontal city vault. Logical admission remains at the safe approach threshold.
const G = preload("res://scripts/three_d/geometry.gd")
var door: Node3D

func _ready() -> void:
	name = "FloorVault"
	# Raised retaining apron contains a recessed stairwell; the approach ramp is level.
	G.cylinder(self,5.6,0.55,Vector3(0,0.15,0),Color("929789"))
	var pit := G.cylinder(self,3.5,0.08,Vector3(0,0.45,0),Color("1d2a2d"))
	pit.material_override.roughness = 1
	for radius in [3.65,4.0,4.8]:
		var ring := G.ring(self,radius,Color("b4b29a"))
		ring.position.y = 0.53
	for i in range(12):
		var angle := i*TAU/12
		var mark := G.box(self,Vector3(0.45,0.025,0.8),Vector3(sin(angle)*4.35,0.55,cos(angle)*4.35),Color("d1af59"))
		mark.rotation.y = angle
	# A guarded access bridge reaches stairs under the offset open plate.
	for i in range(7):
		G.box(self,Vector3(1.8,0.10,0.42),Vector3(0,0.83-i*0.055,-3.8+i*0.42),Color("7f8b85"))
	for side in [-1,1]:
		G.box(self,Vector3(0.08,0.08,3.8),Vector3(side*1.05,1.35,-2.4),Color("c0c4b3"))
		G.box(self,Vector3(0.08,1.0,0.08),Vector3(side*1.05,0.95,-4),Color("b1b7ab"))
	var ramp := G.box(self,Vector3(2.5,0.22,3.0),Vector3(0,0.32,-5.0),Color("8b978d"))
	ramp.rotation.x = -0.15
	door = preload("res://scenes/three_d/FloorVaultDoor.tscn").instantiate()
	add_child(door)
