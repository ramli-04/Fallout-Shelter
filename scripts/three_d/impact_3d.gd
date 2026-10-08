extends Node3D
## Brief geometric flash/shockwave, driven by presentation time. Never touches nav or state.
const Geometry = preload("res://scripts/three_d/geometry.gd")
var age := 0.0
var wave: MeshInstance3D
var flash: MeshInstance3D

func _ready() -> void:
	position = Vector3(90,0.4,54)
	wave = Geometry.ring(self,1.0,Color("ffbf7e"))
	flash = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1
	sphere.height = 2
	sphere.radial_segments = 16
	sphere.rings = 8
	flash.mesh = sphere
	flash.material_override = Geometry.material(Color("fff4d4"),true)
	flash.position.y = 3
	add_child(flash)

func _process(delta: float) -> void:
	age += delta
	wave.scale = Vector3.ONE*(1+age*65)
	flash.scale = Vector3.ONE*(1+age*25)
	flash.visible = age < 0.45
	if age >= 2.5:
		visible = false
		set_process(false)
