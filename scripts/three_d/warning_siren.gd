extends Node3D
const Geometry = preload("res://scripts/three_d/geometry.gd")
const Coordinates = preload("res://scripts/three_d/world_coordinates.gd")
@export_enum("POLE","ROOFTOP") var mounting := "POLE"
@export var sound_radius := 120.0
@export_range(-60,0,1) var volume_db := -16.0
@export_range(0.5,2.0,0.05) var pitch := 1.0
@export var mechanical_rotation := true
@export_enum("INACTIVE","ACTIVE","DAMAGED","DESTROYED") var initial_state := "INACTIVE"
var record: Dictionary = {}
var player: AudioStreamPlayer3D
var assembly: Node3D
var beacon: Node3D
var lamp: MeshInstance3D
var ring: MeshInstance3D
var coverage: MeshInstance3D
var original_radius := 120.0
var roof_building: Node3D
var selection_area: Area3D
var destruction_shown := false
var playback_mode := ""
var is_selected := false
func configure(data: Dictionary) -> void:
	record = data
	position = Coordinates.to_world(record["position"])
func _ready() -> void:
	if record.is_empty():
		record = {"id":"SIREN","position":Vector2.ZERO,"state":initial_state,"mount":mounting,"radius_world":sound_radius,"volume_db":volume_db,"pitch":pitch,"mechanical_rotation":mechanical_rotation}
	var rooftop: bool = record.get("mount","POLE") == "ROOFTOP"
	var height := 3.0 if rooftop else 10.0
	var base: float = record.get("base_height",0.0)
	Geometry.cylinder(self,0.22,height,Vector3(0,base+height/2,0),Color("687879"))
	Geometry.box(self,Vector3(1.3,0.3,1.3),Vector3(0,base+0.15,0),Color("9a9f93"))
	assembly = Node3D.new()
	assembly.position.y = base+height
	add_child(assembly)
	Geometry.box(assembly,Vector3(1.2,0.9,1.2),Vector3.ZERO,Color("b6b99e"))
	for i in range(4):
		var angle := i*TAU/4
		var speaker := Geometry.cylinder(assembly,0.75,1.2,Vector3(sin(angle),0,cos(angle)),Color("adb59b"))
		speaker.mesh.top_radius = 0.8
		speaker.mesh.bottom_radius = 0.25
		speaker.mesh.radial_segments = 8
		speaker.rotation = Vector3(PI/2,angle,0)
		var mouth := Geometry.cylinder(assembly,0.64,0.04,Vector3(sin(angle)*1.62,0,cos(angle)*1.62),Color("424f52"))
		mouth.rotation = Vector3(PI/2,angle,0)
	beacon = Node3D.new()
	beacon.position.y = 1.0
	assembly.add_child(beacon)
	lamp = Geometry.box(beacon,Vector3(0.65,0.3,0.3),Vector3(0.3,0,0),Color("cd693e"))
	lamp.material_override.emission_enabled = true
	lamp.material_override.emission = Color("dd5732")
	Geometry.label(self,record.get("id","SIREN"),Vector3(0,base+height+2,0),Color("f3d5a4"),20,0.035)
	ring = Geometry.ring(self,1.5,Color("ffe3a0"))
	ring.visible = false
	original_radius = record.get("radius_world",120.0)
	coverage = Geometry.ring(self,record.get("radius_world",120.0),Color("ddae5e"))
	coverage.visible = false
	player = AudioStreamPlayer3D.new()
	player.name = "SpatialWarningAudio"
	player.position.y = base+height
	player.bus = "ESSAIMWarnings"
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	player.unit_size = 18.0
	player.max_distance = record.get("radius_world",120.0)
	player.volume_db = record.get("volume_db",volume_db)
	player.pitch_scale = record.get("pitch",pitch)
	player.max_db = -6
	player.panning_strength = 1.0
	add_child(player)
	var area := Area3D.new()
	selection_area = area
	area.collision_layer = 16
	area.collision_mask = 0
	area.set_meta("entity_owner",self)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3,3,3)
	shape.shape = box
	shape.position.y = base+height
	area.add_child(shape)
	add_child(area)
	visual(0,record["state"] == "ACTIVE")
func visual(time: float, active: bool) -> void:
	player.max_distance = record["radius_world"]
	coverage.scale = Vector3.ONE*record["radius_world"]/original_radius
	var ruined: bool = record["state"] == "DESTROYED"
	if ruined and not destruction_shown:
		destruction_shown = true
		assembly.position.y = 0.9
		for child in get_children():
			if child is MeshInstance3D and child not in [coverage,ring]:
				child.position.y = maxf(0.12,child.position.y*0.04)
				child.scale.y = 0.15
			elif child is Label3D: child.position.y = 1.8
		selection_area.get_child(0).position.y = 1.0
	assembly.scale = Vector3(1,0.4,1) if ruined else Vector3.ONE
	assembly.rotation.z = 0.6 if ruined else 0.15 if record["state"] == "DAMAGED" else 0.0
	if active:
		beacon.rotation.y = time*5
		if record.get("mechanical_rotation",true): assembly.rotation.y = time*0.25
	lamp.material_override.emission_energy_multiplier = 1.0 if active else 0.0
	lamp.material_override.albedo_color = Color("ffb663") if active else Color("5d6764")
func stop_audio() -> void:
	player.stop()
	playback_mode = ""
func set_selected(value: bool) -> void:
	is_selected = value
	ring.visible = value
