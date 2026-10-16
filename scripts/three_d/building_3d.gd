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
	var map = preload("res://scripts/city_map.gd")
	var coordinates = preload("res://scripts/three_d/world_coordinates.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = map.map_seed + index*173 + 701
	position = coordinates.to_world(rect.get_center())
	var palette := [Color("c8b99e"),Color("d2a483"),Color("929f9f"),Color("8a9ea8"),Color("b6b4a7"),Color("b18d78")]
	var color: Color = palette[rng.randi_range(0,palette.size()-1)]
	var downtown := 1.0-clampf(rect.get_center().distance_to(map.MAP_SIZE*Vector2(0.46,0.48))/(map.MAP_SIZE.x*0.5),0,1)
	height = rng.randf_range(5,10) + downtown*rng.randf_range(5,19)
	var district: String = map.lot_districts[index]
	rotation.y = map.lot_angles[index]
	var style := rng.randi_range(0,4)
	var civic := false
	for poi in map.points_of_interest():
		if poi["footprint"] == rect:
			civic = true
			height = 3.5 if poi["kind"] == "School" else 4.5
			style = 2
			var colors := {"Police Station":"9cbdcd","Fire Station":"c66e60","Medical Station":"e6ecda","Bank":"b1bda6","School":"d9b578"}
			color = Color(colors[poi["kind"]])
	var width := rect.size.x*0.067
	var depth := rect.size.y*0.067
	Geometry.box(self,Vector3(width,2.2,depth),Vector3(0,-0.9,0),Color("7e8175"))
	if not civic and district == "RESIDENTIAL" and rng.randf() < 0.70:
		height = rng.randf_range(3.2,6.0)
		_wing(Vector3(width,height,depth),Vector3.ZERO,color)
		var roof := Geometry.cylinder(self,width*0.72,2.4,Vector3(0,height+1.15,0),Color("995f47"))
		roof.mesh.radial_segments = 4
		roof.mesh.top_radius = 0.0
		roof.rotation.y = PI/4
		return
	if not civic and district == "INDUSTRIAL":
		height = rng.randf_range(4,7)
		_wing(Vector3(width,height,depth),Vector3.ZERO,Color("89958b"))
		for side in [-1,1]:
			Geometry.cylinder(self,0.8,height*1.8,Vector3(side*width*0.3,height*0.9,0),Color("807c72"))
		return
	match style:
		0: # L-shaped apartments with a real courtyard recess.
			_wing(Vector3(width*0.43,height,depth),Vector3(-width*0.285,0,0),color)
			_wing(Vector3(width*0.57,height*0.65,depth*0.38),Vector3(width*0.215,0,depth*0.31),color.lightened(0.06))
		1: # Tall inset tower on a broad commercial podium.
			_wing(Vector3(width,height*0.20,depth),Vector3.ZERO,color)
			_wing(Vector3(width*0.64,height*0.80,depth*0.64),Vector3(0,height*0.20,0),color.darkened(0.08))
		2: # U-shaped civic / courtyard block.
			_wing(Vector3(width,height,depth*0.32),Vector3(0,0,-depth*0.34),color)
			for side in [-1,1]:
				_wing(Vector3(width*0.27,height*0.85,depth*0.68),Vector3(side*width*0.365,0,depth*0.16),color)
		3: # Long mixed-height residential slab.
			_wing(Vector3(width*0.62,height,depth),Vector3(-width*0.19,0,0),color)
			_wing(Vector3(width*0.38,height*0.6,depth*0.78),Vector3(width*0.31,0,depth*0.11),color.lightened(0.08))
		_: # Stepped high-rise with roof terraces.
			_wing(Vector3(width,height*0.4,depth),Vector3.ZERO,color)
			_wing(Vector3(width*0.78,height*0.35,depth*0.72),Vector3(-width*0.08,height*0.4,0),color.lightened(0.04))
			_wing(Vector3(width*0.50,height*0.25,depth*0.48),Vector3(-width*0.16,height*0.75,0),color.darkened(0.08))
	Geometry.box(self,Vector3(2.2,1.2,2.8),Vector3(-width*0.2,height+0.6,0),Color("6e7d7c"))

func _wing(size: Vector3, base: Vector3, color: Color) -> void:
	var body := Geometry.box(self,size,base+Vector3(0,size.y/2,0),color)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	Geometry.box(self,Vector3(size.x+0.25,0.28,size.z+0.25),base+Vector3(0,size.y,0),Color("647471"))
	Geometry.collider(self,size,base+Vector3(0,size.y/2,0))
	var windows := MultiMeshInstance3D.new()
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.1,1.0,0.06)
	instances.mesh = mesh
	var transforms: Array[Transform3D] = []
	var floors := maxi(1,int((size.y-0.5)/2.6))
	for side in range(4):
		var frontage := size.x if side%2 == 0 else size.z
		var half_depth := (size.z if side%2 == 0 else size.x)*0.5
		var columns := maxi(1,int((frontage-1)/2.8))
		var basis := Basis(Vector3.UP,side*PI/2)
		for floor_index in range(floors):
			for column in range(columns):
				var offset := (column-(columns-1)*0.5)*2.8
				var point := base + basis*Vector3(offset,1.5+floor_index*2.6,half_depth+0.04)
				transforms.append(Transform3D(basis,point))
	instances.instance_count = transforms.size()
	for i in range(transforms.size()): instances.set_instance_transform(i,transforms[i])
	windows.multimesh = instances
	windows.material_override = Geometry.material(Color("a8c8cf"))
	windows.visibility_range_end = 700
	add_child(windows)

func add_poi(kind: String) -> void:
	var front := footprint.size.y*0.0335+0.1
	var color := Color("618eae") if kind == "Police Station" else Color("b95450") if kind == "Fire Station" else Color("e4eadc") if kind == "Medical Station" else Color("b4b891")
	Geometry.box(self,Vector3(9.3,1.0,0.2),Vector3(0,2.6,front),color)
	Geometry.label(self,kind.to_upper(),Vector3(0,height+1.2,0),color,24,0.025)
	Geometry.box(self,Vector3(2.5,2.1,0.1),Vector3(0,1.1,front),Color("88c9d5"))
	if kind in ["Police Station","Fire Station","Medical Station"]:
		if kind == "Medical Station":
			Geometry.box(self,Vector3(0.25,1.2,0.15),Vector3(3,2.6,front+0.15),Color("bd4c47"))
			Geometry.box(self,Vector3(1.2,0.25,0.15),Vector3(3,2.6,front+0.15),Color("bd4c47"))
		var vehicle_color := Color("c74f49") if kind == "Fire Station" else Color("e8e9de")
		for x in [-2.0,2.0]:
			if kind == "Fire Station":
				Geometry.box(self,Vector3(2.7,2.5,0.2),Vector3(x,1.25,front),Color("545e60"))
			exposed_objects.append(Geometry.box(self,Vector3(1.4,0.8,2.5),Vector3(x,0.55,front+1.2),vehicle_color))
			exposed_objects.append(Geometry.box(self,Vector3(0.8,0.25,0.35),Vector3(x,1.05,front+1.2),Color("548dda")))
	elif kind == "Bank":
		for x in [-3.0,3.0]:
			Geometry.cylinder(self,0.4,3,Vector3(x,1.5,front),Color("d2d8c6"))
		Geometry.box(self,Vector3(0.3,0.3,0.5),Vector3(1.8,2.9,front+0.1),Color("414b4c"))
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
