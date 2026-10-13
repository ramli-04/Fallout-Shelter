extends Node3D
## Brief geometric flash/shockwave, driven by presentation time. Never touches nav or state.
const Geometry = preload("res://scripts/three_d/geometry.gd")
var origin := Vector3(90,0.4,54)
var radius := 300.0
var smoke: Array[MeshInstance3D] = []
var dust: MeshInstance3D
var age := 0.0
var wave: MeshInstance3D
var flash: MeshInstance3D

func _ready() -> void:
	position = origin
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
	dust = Geometry.cylinder(self,1.0,1.0,Vector3(0,2,0),Color(0.45,0.4,0.33,0.18))
	dust.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in range(5):
		var cloud := MeshInstance3D.new()
		cloud.mesh = sphere
		cloud.material_override = Geometry.material(Color(0.38,0.34,0.3,0.35),true)
		cloud.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cloud.position = Vector3(sin(i*TAU/5)*7,20,cos(i*TAU/5)*7)
		add_child(cloud)
		smoke.append(cloud)

func _process(delta: float) -> void:
	age += delta
	wave.scale = Vector3.ONE*(1+minf(radius,age*90))
	flash.scale = Vector3.ONE*(1+age*25)
	flash.visible = age < 0.45
	dust.scale = Vector3(minf(radius,age*45),minf(35,age*5),minf(radius,age*45))
	dust.material_override.albedo_color.a = 0.18*maxf(0,1-age/8)
	for cloud in smoke:
		cloud.position.y = 20+age*8
		cloud.scale = Vector3.ONE*(4+age*5)
		cloud.material_override.albedo_color.a = 0.35*maxf(0,1-age/8)
	if age >= 8.0:
		visible = false
		set_process(false)
