extends Node3D
## Scenic abandoned shell, placed outside the simulated map. Never spawns actors.
const G = preload("res://scripts/three_d/geometry.gd")
@export var variant := 0

func _ready() -> void:
	var concrete := Color("777264")
	G.box(self,Vector3(14,.5,10),Vector3.ZERO,concrete)
	for i in range(5):
		var h := 3.0+float((i*7+variant)%5)
		G.box(self,Vector3(2.6,h,.65),Vector3(i*2.8-5.6,h*.5,-4),concrete)
		var rebar := G.box(self,Vector3(.09,1.6,.09),Vector3(i*2.8-5.6,h+.5,-4),Color("5f4938"))
		rebar.rotation.z = .2 if i%2 else -.15
	for i in range(7):
		var debris := G.box(self,Vector3(1.8,.6,1.1),Vector3((i%4)*2.4-4,.4,(i/4)*3),Color("958773"))
		debris.rotation.y = i*1.7
	G.box(self,Vector3(.6,3.5,7),Vector3(-6.5,1.75,-.5),concrete)
	if variant%2 == 0:
		G.cylinder(self,.65,12,Vector3(5,6,-3),Color("80644e"))
		G.box(self,Vector3(6,1.1,.15),Vector3(0,2.7,-3.5),Color("574d3e"))
