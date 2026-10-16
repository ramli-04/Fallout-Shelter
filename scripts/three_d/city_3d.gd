extends Node3D
## The shared seeded geography drives terrain, streets, paths and building footprints.
const CityMap = preload("res://scripts/city_map.gd")
const Coordinates = preload("res://scripts/three_d/world_coordinates.gd")
const Geometry = preload("res://scripts/three_d/geometry.gd")
const BUILDING = preload("res://scenes/three_d/building.tscn")
var buildings: Array[Node3D] = []
var navigation_region: NavigationRegion3D
var scenery: Array[Node3D] = []
var vegetation: Array[MultiMeshInstance3D] = []
var sun: DirectionalLight3D

func _ready() -> void:
	CityMap.ensure()
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/visual_3d.json"))
	_build_terrain()
	for index in range(CityMap.lots.size()):
		var rect: Rect2 = CityMap.lots[index]
		var building: Node3D = BUILDING.instantiate()
		building.configure(rect,index)
		for poi in CityMap.points_of_interest():
			if poi["footprint"] == rect: building.add_poi(poi["kind"])
		add_child(building)
		buildings.append(building)
	_build_landscape()
	navigation_region = preload("res://scripts/three_d/road_navigation_3d.gd").new()
	navigation_region.name = "RoadNavigation"
	add_child(navigation_region)
	if settings["navigation_debug"]: navigation_region.show_debug_surface()
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-32,0)
	sun.light_color = Color("fff0d5")
	sun.light_energy = 0.65
	sun.shadow_enabled = settings["shadows_enabled"]
	sun.directional_shadow_max_distance = 450
	add_child(sun)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("a9c5d0")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d9e5e8")
	environment.ambient_light_energy = 0.30
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	add_child(environment_node)

func _ground(point: Vector2, offset: float = 0.0) -> Vector3:
	return Coordinates.to_world(point,offset)

func _terrain_color(point: Vector2) -> Color:
	var tint := CityMap.noise.get_noise_2d(point.x*2.7,point.y*2.7)*0.13
	var color := Color("8b967a")
	if CityMap.park.has_point(point): color = Color("709454")
	if CityMap.green_zone.has_point(point): color = Color("64824d").lerp(Color("a39e79"),clampf((CityMap.elevation(point)-11)/14,0,0.6))
	if CityMap.lake.grow(35).has_point(point): color = Color("82926b")
	return color.lightened(tint) if tint > 0 else color.darkened(-tint)

func _build_terrain() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var columns := 120
	var rows := 80
	for x in range(columns):
		for y in range(rows):
			var a := Vector2(float(x)/columns,float(y)/rows)*CityMap.MAP_SIZE
			var b := Vector2(float(x)/columns,float(y+1)/rows)*CityMap.MAP_SIZE
			var c := Vector2(float(x+1)/columns,float(y+1)/rows)*CityMap.MAP_SIZE
			var d := Vector2(float(x+1)/columns,float(y)/rows)*CityMap.MAP_SIZE
			for point in [a,c,b,a,d,c]:
				surface.set_uv(point/CityMap.MAP_SIZE)
				surface.set_color(_terrain_color(point))
				surface.add_vertex(_ground(point))
	surface.generate_normals()
	var terrain := MeshInstance3D.new()
	terrain.name = "SculptedTerrain"
	terrain.mesh = surface.commit()
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/three_d/terrain.gdshader")
	material.set_shader_parameter("map_size",CityMap.MAP_SIZE)
	material.set_shader_parameter("map_seed",CityMap.map_seed)
	material.set_shader_parameter("x_count",CityMap.x_cuts.size())
	material.set_shader_parameter("y_count",CityMap.y_cuts.size())
	var xs := PackedFloat32Array(CityMap.x_cuts)
	var ys := PackedFloat32Array(CityMap.y_cuts)
	xs.resize(32)
	ys.resize(32)
	material.set_shader_parameter("x_cuts",xs)
	material.set_shader_parameter("y_cuts",ys)
	material.set_shader_parameter("park_bounds",Vector4(CityMap.park.position.x,CityMap.park.position.y,CityMap.park.end.x,CityMap.park.end.y))
	material.set_shader_parameter("reserve_bounds",Vector4(CityMap.green_zone.position.x,CityMap.green_zone.position.y,CityMap.green_zone.end.x,CityMap.green_zone.end.y))
	terrain.material_override = material
	add_child(terrain)
	var body := StaticBody3D.new()
	body.collision_layer = 8
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	collider.shape = terrain.mesh.create_trimesh_shape()
	body.add_child(collider)
	add_child(body)

func _build_landscape() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = CityMap.map_seed+61909
	var positions: Array[Vector2] = []
	for _i in range(1600):
		var point := Vector2(rng.randf()*CityMap.MAP_SIZE.x,rng.randf()*CityMap.MAP_SIZE.y)
		if not CityMap.park.has_point(point) and not CityMap.green_zone.has_point(point): continue
		if CityMap.lake.grow(30).has_point(point): continue
		if CityMap.nearest_lane_point(point).distance_to(point) < 40: continue
		var reserved := false
		for site in CityMap.sites.values():
			if point.distance_to(site) < 90: reserved = true
		if not reserved: positions.append(point)
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.16
	trunk_mesh.bottom_radius = 0.25
	trunk_mesh.height = 2.8
	trunk_mesh.radial_segments = 6
	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = 1.8
	crown_mesh.height = 4.2
	crown_mesh.radial_segments = 10
	crown_mesh.rings = 5
	var sizes: Array[float] = []
	for _point in positions: sizes.append(rng.randf_range(0.7,1.65))
	for crown in [false,true]:
		var batch := MultiMeshInstance3D.new()
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.use_colors = true
		instances.mesh = crown_mesh if crown else trunk_mesh
		instances.instance_count = positions.size()
		for i in range(positions.size()):
			var size: float = sizes[i]
			var point := _ground(positions[i]) + Vector3(0,(3.7 if crown else 1.4)*size,0)
			instances.set_instance_transform(i,Transform3D(Basis().scaled(Vector3(size,size,size)),point))
			instances.set_instance_color(i,Color("427153").lightened(rng.randf_range(-0.12,0.13)) if crown else Color("77604a"))
		batch.multimesh = instances
		var material := Geometry.material(Color.WHITE)
		material.vertex_color_use_as_albedo = true
		batch.material_override = material
		batch.visibility_range_end = 950
		add_child(batch)
		vegetation.append(batch)
	# An inset reservoir gives the park a shoreline and visibly depressed terrain.
	var water := SurfaceTool.new()
	water.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := CityMap.lake.get_center()*0.1
	var radius := CityMap.lake.size*0.05
	for i in range(64):
		for angle in [-1.0,float(i+1)/64*TAU,float(i)/64*TAU]:
			water.add_vertex(Vector3(center.x,-0.28,center.y) if angle < 0 else Vector3(center.x+cos(angle)*radius.x,-0.28,center.y+sin(angle)*radius.y))
	water.generate_normals()
	var pond := MeshInstance3D.new()
	pond.mesh = water.commit()
	var water_material := Geometry.material(Color("508a93"))
	water_material.roughness = 0.22
	water_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	pond.material_override = water_material
	add_child(pond)
	for _i in range(42):
		var point := CityMap.hill+Vector2(rng.randf_range(-450,450),rng.randf_range(-350,350))
		if point.distance_to(CityMap.hill) < 100 or CityMap.nearest_lane_point(point).distance_to(point) < 35: continue
		var rock := Geometry.cylinder(self,rng.randf_range(1.1,3.0),rng.randf_range(1.5,4.0),_ground(point,0.0),Color("8d9181"))
		rock.mesh.radial_segments = 5
		rock.mesh.top_radius = 0.7
		rock.rotation.y = rng.randf()*TAU
		scenery.append(rock)
	for site in [CityMap.park.get_center(),CityMap.hill]:
		var point := _ground(site,0.02)
		Geometry.cylinder(self,7,0.14,point,Color("b8b498"))
	# District names do not reveal whether the rumored fifth shelter actually exists.
	Geometry.label(self,"CENTRAL PARK",_ground(CityMap.park.get_center()+Vector2(0,300),5),Color("e0efd0"),46,0.09)
	Geometry.label(self,"HIGHLAND RESERVE",_ground(CityMap.hill+Vector2(0,-300),8),Color("e0efd0"),40,0.09)
	Geometry.label(self,"DOWNTOWN",_ground(CityMap.MAP_SIZE*Vector2(0.73,0.75),12),Color("f3e0ba"),40,0.08)
	for child in get_children():
		if child is Label3D:
			child.visibility_range_begin = 60.0

func set_warning(active: bool) -> void:
	if sun != null: sun.light_color = Color("ffd0b5") if active else Color("fff0d5")

func devastate(records: Array, config: Dictionary) -> void:
	var blast = preload("res://scripts/blast_model.gd")
	var center := Vector2(config["impact_position"][0],config["impact_position"][1])*0.1
	for i in range(mini(buildings.size(),records.size())):
		buildings[i].destroy_to(records[i]["destruction_state"],Vector2(buildings[i].position.x,buildings[i].position.z).distance_to(center)/90.0)
	for building in buildings:
		for object in building.exposed_objects:
			if blast.intensity(Coordinates.to_simulation(building.position+object.position),config) > 0: object.hide()
	for node in scenery:
		if blast.intensity(Coordinates.to_simulation(node.position),config) > 0: node.hide()
	for batch in vegetation:
		for i in range(batch.multimesh.instance_count):
			var transform := batch.multimesh.get_instance_transform(i)
			if blast.intensity(Coordinates.to_simulation(transform.origin),config) > 0:
				transform.basis = Basis().scaled(Vector3.ZERO)
				batch.multimesh.set_instance_transform(i,transform)
