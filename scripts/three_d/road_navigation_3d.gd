extends NavigationRegion3D
## Connected non-overlapping road/sidewalk polygons, with buildings excluded geometrically.
## Existing fixed-clock routes remain authoritative: nav queries validate their 3D waypoints.
const Coordinates = preload("res://scripts/three_d/world_coordinates.gd")
const HALF_WIDTH := 3.2
var walkable_rects: Array[Rect2] = []

func _ready() -> void:
	navigation_mesh = create_mesh()

func create_mesh() -> NavigationMesh:
	var x_cuts: Array[float] = []
	var z_cuts: Array[float] = []
	for x in range(11):
		x_cuts.append(x*18.0-HALF_WIDTH)
		x_cuts.append(x*18.0+HALF_WIDTH)
	for z in range(7):
		z_cuts.append(z*18.0-HALF_WIDTH)
		z_cuts.append(z*18.0+HALF_WIDTH)
	var vertices := PackedVector3Array()
	var polygons: Array[PackedInt32Array] = []
	var vertex_ids := {}
	walkable_rects.clear()
	for i in range(x_cuts.size()-1):
		for j in range(z_cuts.size()-1):
			if i%2 != 0 and j%2 != 0:
				continue
			var rect := Rect2(Vector2(x_cuts[i], z_cuts[j]), Vector2(x_cuts[i+1]-x_cuts[i], z_cuts[j+1]-z_cuts[j]))
			walkable_rects.append(rect)
			var polygon := PackedInt32Array()
			for corner in [Vector2i(i,j), Vector2i(i,j+1), Vector2i(i+1,j+1), Vector2i(i+1,j)]:
				if not vertex_ids.has(corner):
					vertex_ids[corner] = vertices.size()
					vertices.append(Vector3(x_cuts[corner.x], Coordinates.FLOOR_Y, z_cuts[corner.y]))
				polygon.append(vertex_ids[corner])
			polygons.append(polygon)
	var mesh := NavigationMesh.new()
	mesh.agent_radius = 0.45
	mesh.agent_height = 1.8
	mesh.vertices = vertices
	for polygon in polygons:
		mesh.add_polygon(polygon)
	return mesh

func contains(point: Vector3) -> bool:
	for rect in walkable_rects:
		if rect.grow(0.001).has_point(Vector2(point.x, point.z)):
			return true
	return false

func show_debug_surface() -> void:
	# Explicit overlay also works in standalone runs; editor debug hints are not toggled.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for rect in walkable_rects:
		var a := Vector3(rect.position.x,Coordinates.FLOOR_Y+0.045,rect.position.y)
		var b := Vector3(rect.position.x,Coordinates.FLOOR_Y+0.045,rect.end.y)
		var c := Vector3(rect.end.x,Coordinates.FLOOR_Y+0.045,rect.end.y)
		var d := Vector3(rect.end.x,Coordinates.FLOOR_Y+0.045,rect.position.y)
		for vertex in [a,b,c,a,c,d]: surface.add_vertex(vertex)
	var node := MeshInstance3D.new()
	node.mesh = surface.commit()
	var material := preload("res://scripts/three_d/geometry.gd").material(Color(0.25,0.85,0.95,0.30),true)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)

func path_between(start: Vector3, destination: Vector3) -> PackedVector3Array:
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return PackedVector3Array()
	return NavigationServer3D.map_get_path(map, start, destination, true)
