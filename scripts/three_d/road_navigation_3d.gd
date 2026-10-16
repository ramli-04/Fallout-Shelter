extends NavigationRegion3D
## Obstacle-aware raster surface matching free-space simulation movement.
const Coordinates = preload("res://scripts/three_d/world_coordinates.gd")
const Map = preload("res://scripts/city_map.gd")
const CELL := 90.0
var walkable_rects: Array[Rect2] = []

func _ready() -> void:
	name = "PedestrianNavigation"
	navigation_mesh = create_mesh()

func create_mesh() -> NavigationMesh:
	var vertices := PackedVector3Array()
	var polygons: Array[PackedInt32Array] = []
	var ids := {}
	walkable_rects.clear()
	for x in range(int(Map.MAP_SIZE.x/CELL)):
		for y in range(int(Map.MAP_SIZE.y/CELL)):
			var rect := Rect2(Vector2(x,y)*CELL,Vector2.ONE*CELL)
			var valid := true
			for obstacle in Map.lots+[Map.lake]+Map.rock_obstacles:
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

func show_debug_surface() -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = navigation_mesh.get_debug_mesh()
	mesh.material_override = preload("res://scripts/three_d/geometry.gd").material(Color("5bd7e0"),true)
	add_child(mesh)
