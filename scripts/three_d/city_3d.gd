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
var streamer: Node3D
var collision: Node3D
var landscape_trees: Array=[]
var sun: DirectionalLight3D

func _ready() -> void:
	CityMap.ensure()
	if CityMap.graph==null or not CityMap.validation.get("valid",false): return
	Geometry.begin_world(str(CityMap.generated_world.get("world_content_hash",str([CityMap.map_seed,CityMap.generation_settings]))))
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/visual_3d.json"))
	add_child(preload("res://scripts/generation/parcel_debug.gd").new())
	_prepare_landscape_data()
	collision=preload("res://scripts/three_d/static_world_collision.gd").new()
	collision.trees=landscape_trees; add_child(collision)
	navigation_region=preload("res://scripts/three_d/road_navigation_3d.gd").new()
	navigation_region.name="RoadNavigation"; add_child(navigation_region)
	if settings["navigation_debug"]: navigation_region.show_debug_surface()
	var valley=preload("res://scenes/three_d/valley_environment.tscn").instantiate()
	valley.streaming_enabled=true
	valley.chunk_size=CityMap.tile_grid.chunk_world_size() if CityMap.tile_grid!=null else float(preload("res://scripts/three_d/render_options.gd").load_options().chunk_size)
	add_child(valley)
	var overlay=preload("res://scripts/three_d/city_details.gd").new(); overlay.overlay_only=true; add_child(overlay)
	streamer=preload("res://scripts/three_d/visual_chunk_manager.gd").new(); streamer.city=self; add_child(streamer)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-32,0)
	sun.light_color = Color("fff1df")
	sun.light_energy = 0.48
	sun.shadow_enabled = settings["shadows_enabled"]
	sun.directional_shadow_max_distance = 450
	add_child(sun)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("adb9bc")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("bac8d0")
	environment.ambient_light_energy = 0.30
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("adb9bc")
	environment.fog_density = 0.00012
	environment.fog_sun_scatter = 0.0
	environment.fog_light_energy = 0.25
	environment.fog_sky_affect = 0.7
	environment_node.environment = environment
	add_child(environment_node)

func _prepare_landscape_data() -> void:
	landscape_trees=CityMap.vegetation_data.duplicate(true)
	if not CityMap.terrain_definition.is_empty(): return
	var rng:=RandomNumberGenerator.new(); rng.seed=CityMap.map_seed+61909
	for i in range(7000):
		var point:=Vector2(rng.randf()*CityMap.MAP_SIZE.x,rng.randf()*CityMap.MAP_SIZE.y)
		if not CityMap.park.has_point(point) and not CityMap.green_zone.has_point(point) and rng.randf()>.35: continue
		if CityMap.lake.grow(30).has_point(point) or not CityMap.clear_point(point,30): continue
		var road: Dictionary=CityMap.nearest_edge(point)
		if road.point.distance_to(point)<float(road.edge.width)*.5+float(road.edge.sidewalk)+25: continue
		if CityMap.parking_lots.any(func(lot):return lot.bounds.grow(30).has_point(point)): continue
		if CityMap.sites.values().any(func(site):return point.distance_to(site)<190): continue
		landscape_trees.append({"position":[point.x,point.y],"scale":1.0,"variant":i%3})
	if CityMap.tile_grid!=null and not CityMap.tile_grid.chunks.is_empty():
		var accepted: Array=[]
		for i in range(landscape_trees.size()):
			var tree: Dictionary=landscape_trees[i]
			if CityMap.tile_grid.place_decoration(CityMap._v2(tree.position),Vector2i.ONE,"tree-runtime:%d"%i): accepted.append(tree)
		landscape_trees=accepted
	for tree in landscape_trees: tree.scale=rng.randf_range(.7,1.65)

func building_for_index(index: int) -> Node3D:
	return streamer.building_nodes.get(index) if streamer!=null else null

func _ground(point: Vector2, offset: float = 0.0) -> Vector3:
	return Coordinates.to_world(point,offset)

func _terrain_color(point: Vector2) -> Color:
	var tint := CityMap.noise.get_noise_2d(point.x*2.7,point.y*2.7)*0.045
	var color := Color("294b30")
	if CityMap.park.has_point(point): color = Color("244a2c")
	if CityMap.green_zone.has_point(point): color = Color("28472e").lerp(Color("3e5740"),clampf((CityMap.elevation(point)-11)/14,0,0.6))
	if CityMap.lake.grow(35).has_point(point): color = Color("355b38")
	return color.lightened(tint) if tint > 0 else color.darkened(-tint)

func set_warning(active: bool) -> void:
	if sun != null: sun.light_color = Color("ffd0b5") if active else Color("fff1df")

func devastate(records: Array, config: Dictionary) -> void:
	var valley := get_node_or_null("ValleyEnvironment")
	if valley: valley.devastate(config)
	var blast = preload("res://scripts/blast_model.gd")
	var center := Vector2(config["impact_position"][0],config["impact_position"][1])*0.1
	if collision!=null: collision.apply_damage(records)
	if streamer!=null: streamer.apply_damage(records,config)
	for building in buildings:
		var index: int=building.source_index
		if index<records.size(): building.destroy_to(records[index]["destruction_state"],Vector2(building.position.x,building.position.z).distance_to(center)/90.0)
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
