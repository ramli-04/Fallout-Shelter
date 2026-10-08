extends Node3D
## Primitive city matches the preserved road grid and every original building footprint.
const CityMap = preload("res://scripts/city_map.gd")
const Coordinates = preload("res://scripts/three_d/world_coordinates.gd")
const Geometry = preload("res://scripts/three_d/geometry.gd")
const BUILDING = preload("res://scenes/three_d/building.tscn")
var buildings: Array[Node3D] = []
var navigation_region: NavigationRegion3D
var sun: DirectionalLight3D

func _ready() -> void:
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/visual_3d.json"))
	Geometry.box(self, Vector3(194,0.35,122), Vector3(90,-0.20,54), Color("8ca49c"))
	Geometry.collider(self, Vector3(194,0.35,122), Vector3(90,-0.20,54), 8)
	for x in range(11):
		Geometry.box(self, Vector3(7.6,0.12,115.6), Vector3(x*18,0.04,54), Color("c3ccc5"))
		Geometry.box(self, Vector3(3.6,0.05,115.6), Vector3(x*18,0.12,54), Color("435961"))
	for z in range(7):
		Geometry.box(self, Vector3(187.6,0.12,7.6), Vector3(90,0.04,z*18), Color("c3ccc5"))
		Geometry.box(self, Vector3(187.6,0.05,3.6), Vector3(90,0.13,z*18), Color("435961"))
	# Crosswalks beside intersections, with repeated stripes in one MultiMesh draw.
	var crossings := MultiMeshInstance3D.new()
	var stripes := MultiMesh.new()
	stripes.transform_format = MultiMesh.TRANSFORM_3D
	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(0.34,0.012,2.8)
	stripes.mesh = stripe_mesh
	stripes.instance_count = 9*5*5
	var stripe_index := 0
	for x in range(1,10):
		for z in range(1,6):
			for offset in range(5):
				stripes.set_instance_transform(stripe_index, Transform3D(Basis(), Vector3(x*18-1.3+offset*0.65,0.17,z*18+3.3)))
				stripe_index += 1
	crossings.multimesh = stripes
	crossings.material_override = Geometry.material(Color("e4e9d8"))
	add_child(crossings)
	var index := 0
	for rect in CityMap.building_rects():
		var building: Node3D = BUILDING.instantiate()
		building.configure(rect, index)
		add_child(building)
		buildings.append(building)
		index += 1
	for cell in CityMap.PARK_CELLS:
		var center := Vector3(cell.x*18+9,0.19,cell.y*18+9)
		Geometry.box(self, Vector3(11,0.12,11), center, Color("5b937b"))
		for offset in [Vector3(-3,0,-3), Vector3(3,0,0), Vector3(-1,0,3)]:
			Geometry.cylinder(self,0.25,1.9,center+offset+Vector3(0,0.95,0),Color("836b50"))
			Geometry.collider(self,Vector3(0.5,1.9,0.5),center+offset+Vector3(0,0.95,0))
			var crown := Geometry.cylinder(self,1.25,2.2,center+offset+Vector3(0,2.6,0),Color("387967"))
			crown.mesh.top_radius = 0.6
		Geometry.box(self,Vector3(2,0.45,0.55),center+Vector3(2,0.35,3),Color("b78d65"))
	Geometry.label(self,"ORCHARD QUARTER",Vector3(31,10,78),Color("ffe3b8"),32,0.04)
	Geometry.label(self,"CIVIC GARDENS",Vector3(90,7,47),Color("d4f4dc"),32,0.035)
	Geometry.label(self,"EAST WORKS",Vector3(151,13,29),Color("d6ebf7"),32,0.04)
	navigation_region = preload("res://scripts/three_d/road_navigation_3d.gd").new()
	navigation_region.name = "RoadNavigation"
	add_child(navigation_region)
	if settings["navigation_debug"]:
		navigation_region.show_debug_surface()
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55,-30,0)
	sun.light_color = Color("fff3dd")
	sun.light_energy = 0.65
	sun.shadow_enabled = settings["shadows_enabled"]
	sun.directional_shadow_max_distance = 220
	add_child(sun)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("a7c3ce")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d2e3ec")
	environment.ambient_light_energy = 0.24
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment_node.environment = environment
	add_child(environment_node)

func set_warning(active: bool) -> void:
	sun.light_color = Color("ffd0b5") if active else Color("fff3dd")
