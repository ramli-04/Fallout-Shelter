extends NavigationRegion3D
## Obstacle-aware raster surface matching free-space simulation movement.
const Coordinates = preload("res://scripts/three_d/world_coordinates.gd")
const Map = preload("res://scripts/city_map.gd")
const CELL := 30.0
var walkable_rects: Array[Rect2] = []
var revision := -1
var rebuild_age := 0.0

func _ready() -> void:
	name = "PedestrianNavigation"
	navigation_mesh = create_mesh()
	revision=Map.navigation_revision

func _process(delta: float) -> void:
	if revision==Map.navigation_revision: return
	rebuild_age+=delta
	if rebuild_age<.25: return
	navigation_mesh=create_mesh(); revision=Map.navigation_revision; rebuild_age=0

func create_mesh() -> NavigationMesh:
	var vertices := PackedVector3Array()
	var polygons: Array[PackedInt32Array] = []
	var ids := {}
	walkable_rects.clear()
	for x in range(int(Map.MAP_SIZE.x/CELL)):
		for y in range(int(Map.MAP_SIZE.y/CELL)):
			var rect := Rect2(Vector2(x,y)*CELL,Vector2.ONE*CELL)
			var valid := true
			for obstacle in Map.obstacles_near(rect.grow(14),true)+Map.closures.values():
				if rect.intersects(obstacle.grow(14)): valid = false; break
			if not valid: continue
			var polygon := PackedInt32Array()
			for corner in [Vector2i(x,y),Vector2i(x,y+1),Vector2i(x+1,y+1),Vector2i(x+1,y)]:
				if not ids.has(corner):
					ids[corner] = vertices.size()
					vertices.append(Coordinates.to_world(Vector2(corner)*CELL))
				polygon.append(ids[corner])
			polygons.append(polygon)
			walkable_rects.append(Rect2(rect.position*0.1,rect.size*0.1))
	var mesh := NavigationMesh.new()
	mesh.agent_radius = 0.45
	mesh.agent_height = 1.8
	mesh.vertices = vertices
	for polygon in polygons: mesh.add_polygon(polygon)
	return mesh

func contains(point: Vector3) -> bool:
	return Map.clear_point(Coordinates.to_simulation(point))

func path_between(start: Vector3, destination: Vector3) -> PackedVector3Array:
	# Use the same obstacle-aware authority as fixed-clock movement, including narrow approaches.
	var result := PackedVector3Array()
	for point in Map.free_route(Coordinates.to_simulation(start),Coordinates.to_simulation(destination)):
		result.append(Coordinates.to_world(point))
	return result

func server_path_between(start: Vector3, destination: Vector3) -> PackedVector3Array:
	# Godot's default 4096-polygon query budget truncates cross-city paths on a
	# street-scale raster. Bound the search by this generated mesh's size.
	var parameters:=NavigationPathQueryParameters3D.new()
	parameters.map=get_navigation_map(); parameters.start_position=start; parameters.target_position=destination
	parameters.path_search_max_polygons=navigation_mesh.get_polygon_count()+1
	var result:=NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(parameters,result)
	return result.path

func show_debug_surface() -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = navigation_mesh.get_debug_mesh()
	mesh.material_override = preload("res://scripts/three_d/geometry.gd").material(Color("5bd7e0"),true)
	add_child(mesh)
