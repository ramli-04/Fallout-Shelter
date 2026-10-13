extends Node3D
## Reusable static obstruction; color/height are deterministic visual choices, not RNG draws.
const Geometry = preload("res://scripts/three_d/geometry.gd")
var exposed_objects: Array[Node3D] = []
var destruction_state := "INTACT"
var collapse_tween: Tween
var footprint := Rect2()
var height := 0.0

func configure(rect: Rect2, index: int) -> void:
	footprint = rect
	var scale_value := preload("res://scripts/three_d/world_coordinates.gd").SCALE
	var center: Vector2 = rect.get_center() * scale_value
	position = Vector3(center.x, 0.18, center.y)
	var district := int(center.x / (preload("res://scripts/city_map.gd").MAP_SIZE.x*0.1/3))
	var palettes := [Color("d99c77"), Color("a5c3c3"), Color("839aaa")]
	var color: Color = palettes[mini(district, 2)].lightened((index%3)*0.055)
	height = 3.0 + (index%4)*1.35 if district == 0 else 4.2 + (index%5)*1.6 if district == 1 else 3.0 + (index%3)*1.0
	for poi in preload("res://scripts/city_map.gd").points_of_interest():
		if poi["footprint"] == rect:
			height = 3.5 if poi["kind"] == "School" else 4.5
			var service_colors := {"Police Station":"9cbdcd","Fire Station":"c66e60","Medical Station":"e6ecda","Bank":"b1bda6","School":"d9b578"}
			color = Color(service_colors[poi["kind"]])
	var size := Vector3(rect.size.x*scale_value, height, rect.size.y*scale_value)
	Geometry.box(self, size, Vector3(0, height/2, 0), color)
	Geometry.box(self, Vector3(size.x+0.3, 0.22, size.z+0.3), Vector3(0, height+0.08, 0), Color("465b63"))
	Geometry.box(self, Vector3(size.x+0.2, 0.25, size.z+0.2), Vector3(0, 0.12, 0), Color("718784"))
	Geometry.collider(self, size, Vector3(0, height/2, 0))
	# One instanced draw per building for all repeated facade windows.
	var windows := MultiMeshInstance3D.new()
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.25, 0.8, 0.06)
	multimesh.mesh = mesh
	var floors := maxi(1, int(height/2))
	multimesh.instance_count = floors*12
	var window_index := 0
	for floor_index in range(floors):
		for side in range(4):
			for offset in [-2.8, 0.0, 2.8]:
				var basis := Basis(Vector3.UP, side*PI/2)
				var point := basis * Vector3(offset, 1.1 + floor_index*1.8, size.z/2+0.04)
				multimesh.set_instance_transform(window_index, Transform3D(basis, point))
				window_index += 1
	windows.visibility_range_end = 170.0
	windows.multimesh = multimesh
	windows.material_override = Geometry.material(Color("e1edda"))
	add_child(windows)

func add_poi(kind: String) -> void:
	var color := Color("618eae") if kind == "Police Station" else Color("b95450") if kind == "Fire Station" else Color("e4eadc") if kind == "Medical Station" else Color("b4b891")
	Geometry.box(self,Vector3(9.3,1.0,0.2),Vector3(0,2.6,4.75),color)
	Geometry.label(self,kind.to_upper(),Vector3(0,height+1.2,0),color,24,0.025)
	Geometry.box(self,Vector3(2.5,2.1,0.1),Vector3(0,1.1,4.78),Color("88c9d5"))
	if kind in ["Police Station","Fire Station","Medical Station"]:
		if kind == "Medical Station":
			Geometry.box(self,Vector3(0.25,1.2,0.15),Vector3(3,2.6,4.9),Color("bd4c47"))
			Geometry.box(self,Vector3(1.2,0.25,0.15),Vector3(3,2.6,4.9),Color("bd4c47"))
		var vehicle_color := Color("c74f49") if kind == "Fire Station" else Color("e8e9de")
		for x in [-2.0,2.0]:
			if kind == "Fire Station":
				Geometry.box(self,Vector3(2.7,2.5,0.2),Vector3(x,1.25,4.78),Color("545e60"))
			exposed_objects.append(Geometry.box(self,Vector3(1.4,0.8,2.5),Vector3(x,0.55,5.8),vehicle_color))
			exposed_objects.append(Geometry.box(self,Vector3(0.8,0.25,0.35),Vector3(x,1.05,5.8),Color("548dda")))
	elif kind == "Bank":
		for x in [-3.0,3.0]:
			Geometry.cylinder(self,0.4,3,Vector3(x,1.5,4.6),Color("d2d8c6"))
		Geometry.box(self,Vector3(0.3,0.3,0.5),Vector3(1.8,2.9,4.85),Color("414b4c"))
	elif kind == "School":
		Geometry.box(self,Vector3(7,0.12,2.0),Vector3(0,0.15,6),Color("d8b879"))
		for side in [-1,1]:
			Geometry.box(self,Vector3(0.15,1.8,0.15),Vector3(side*1.2,0.95,6),Color("bb7550"))
		Geometry.box(self,Vector3(2.7,0.15,0.15),Vector3(0,1.9,6),Color("bb7550"))
		Geometry.box(self,Vector3(0.6,0.15,0.6),Vector3(0,0.65,6),Color("52889e"))
func destroy_to(state: String, delay: float) -> void:
	destruction_state = state
	if state == "INTACT": return
	for object in exposed_objects: object.hide()
	for child in get_children():
		if child is StaticBody3D: child.collision_layer = 0
	collapse_tween = create_tween()
	collapse_tween.tween_interval(delay)
	collapse_tween.tween_property(self,"scale:y",0.08 if state == "DESTROYED" else 0.55,1.0)
	collapse_tween.parallel().tween_property(self,"rotation:z",0.12,0.8)
	for child in get_children():
		if child is GeometryInstance3D and child.material_override is StandardMaterial3D:
			child.material_override.albedo_color = Color("706b60")
func set_obscured(value: bool) -> void:
	for child in get_children():
		if child is GeometryInstance3D and child.material_override is StandardMaterial3D:
			child.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if value else BaseMaterial3D.TRANSPARENCY_DISABLED
			child.material_override.albedo_color.a = 0.22 if value else 1.0
