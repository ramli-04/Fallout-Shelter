extends Node3D
## Batched road ribbons and a purely scenic mountain horizon. No distant simulation.
const Map = preload("res://scripts/city_map.gd")
const Coordinates = preload("res://scripts/three_d/world_coordinates.gd")
const G = preload("res://scripts/three_d/geometry.gd")
var batches := {}
var road_vertices := 0
var background_vertices := 0

func _ready() -> void:
	name = "ValleyEnvironment"
	_build_background()
	for edge in Map.roads:
		var points: PackedVector2Array = edge["points"]
		if edge["trail"]:
			_ribbon(points,1.6,0.27,"trail",Color("b29c70"))
		else:
			_ribbon(points,7.8,0.25,"sidewalk",Color("999b8a"))
			_ribbon(points,5.0,0.30,"asphalt",Color("424c4d"))
			_marks(points,false)
	for points in Map.highways:
		_ribbon(points,12.5,0,"highway",Color("4f5856"),true)
		_ribbon(points,0.15,0.13,"median",Color("d7c491"),true)
		_marks(points,true)
		_highway_details(points)
	# Ramps connect actual highway points to the nearest urban junction.
	for uv in [Vector2(0.25,0.20),Vector2(0.67,0.16)]:
		var highway: PackedVector2Array = Map.highways[0]
		var index := clampi(int((uv.x+0.12)/1.26*100),0,100)
		var start := highway[index]
		var end := Map.graph.get_point_position(Map.graph.get_closest_point(start))
		var points := PackedVector2Array()
		for i in range(25):
			var t := float(i)/24
			points.append(start.lerp(end,t)+Vector2(sin(t*PI)*180,0))
		# Elevated ramp eases down to the street.
		_ramp(points)
	# A roundabout at a shared junction; street connections remain visible.
	var center: Vector2 = Map.graph.get_point_position(27)
	var ring := PackedVector2Array()
	for i in range(49): ring.append(center+Vector2(cos(i*TAU/48),sin(i*TAU/48))*65)
	_ribbon(ring,6.5,0.32,"asphalt",Color("424c4d"))
	G.cylinder(self,3.0,0.22,Coordinates.to_world(center,0.13),Color("728257"))
	for key in batches:
		var entry: Dictionary = batches[key]
		var surface: SurfaceTool = entry["surface"]
		surface.generate_normals()
		var node := MeshInstance3D.new()
		node.name = key.capitalize()
		node.mesh = surface.commit()
		node.material_override = G.material(entry["color"])
		node.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
		add_child(node)

func _surface(key: String, color: Color) -> SurfaceTool:
	if not batches.has(key):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		batches[key] = {"surface":surface,"color":color}
	return batches[key]["surface"]

func _height(point: Vector2, highway: bool) -> float:
	return Map.elevation(point)+(10.0 if highway else 0.0)

func _ribbon(points: PackedVector2Array, width: float, offset: float, key: String, color: Color, highway: bool = false) -> void:
	var surface := _surface(key,color)
	for i in range(1,points.size()):
		var normal := (points[i]-points[i-1]).normalized().orthogonal()*width*5
		var corners := [points[i-1]+normal,points[i-1]-normal,points[i]-normal,points[i]+normal]
		for j in [0,2,1,0,3,2]:
			var point: Vector2 = corners[j]
			surface.add_vertex(Vector3(point.x*0.1,_height(point,highway)+offset,point.y*0.1))
			road_vertices += 1

func _marks(points: PackedVector2Array, highway: bool) -> void:
	var distance := 0.0
	for i in range(1,points.size()):
		var length := points[i].distance_to(points[i-1])
		var tangent := (points[i]-points[i-1]).normalized()
		var normal := tangent.orthogonal()
		for cursor in range(int(length/12)+1):
			var along := minf(cursor*12,length)
			if fmod(distance+along,65) > 27: continue
			var point := points[i-1]+tangent*along
			for lane in [-1,1] if highway else [0]:
				var mid: Vector2 = point+normal*lane*31
				_ribbon(PackedVector2Array([mid,mid+tangent*9]),0.12,0.38,"markings",Color("d9cfad"),highway)
		distance += length

func _ramp(points: PackedVector2Array) -> void:
	var surface := _surface("ramps",Color("515957"))
	for i in range(1,points.size()):
		var normal := (points[i]-points[i-1]).normalized().orthogonal()*24
		for j in [0,2,1,0,3,2]:
			var ends := [points[i-1]+normal,points[i-1]-normal,points[i]-normal,points[i]+normal]
			var point: Vector2 = ends[j]
			var t := float(i-1 if j < 2 else i)/(points.size()-1)
			surface.add_vertex(Vector3(point.x*0.1,Map.elevation(point)+10*(1-t)+0.12,point.y*0.1))

func _highway_details(points: PackedVector2Array) -> void:
	for side in [-1,1]:
		var rail := PackedVector2Array()
		for i in range(points.size()):
			var direction := (points[mini(i+1,points.size()-1)]-points[maxi(0,i-1)]).normalized()
			rail.append(points[i]+direction.orthogonal()*side*62)
		_ribbon(rail,0.32,1.0,"guardrails",Color("b5b9ac"),true)
	for i in range(4,points.size()-3,5):
		var point := Coordinates.to_world(points[i],0)
		G.box(self,Vector3(1.5,10,3.5),point+Vector3.UP*5,Color("92988c"))
	for index in [15,55,88]:
		var point := Coordinates.to_world(points[index],11)
		G.box(self,Vector3(0.22,5,0.22),point+Vector3(7,2.5,0),Color("a3aaa0"))
		G.box(self,Vector3(7,2,0.22),point+Vector3(4,4,0),Color("375d54"))
		G.label(self,"VALLEY / A7",point+Vector3(4,4,0.2),Color("e5e6d3"),25,0.025)
	for index in [4,96]:
		var point := Coordinates.to_world(points[index],10)
		var tunnel := Node3D.new()
		tunnel.position = point
		tunnel.rotation.y = -(points[mini(index+1,100)]-points[index-1]).angle()+PI/2
		add_child(tunnel)
		# Arch geometry wraps around an open black tunnel mouth.
		for i in range(13):
			var angle := i*PI/12
			var block := G.box(tunnel,Vector3(1.5,2.2,4),Vector3(cos(angle)*7,sin(angle)*7,0),Color("8e938a"))
			block.rotation.z = angle-PI/2
		G.box(tunnel,Vector3(12,8,0.2),Vector3(0,3,2),Color("252f30"))
		for side in [-1,1]:
			var rock := G.cylinder(tunnel,15,26,Vector3(side*17,0,7),Color("777e70"))
			rock.mesh.radial_segments = 5
			rock.mesh.top_radius = 4

func _background_height(point: Vector2) -> float:
	var uv := point/Map.MAP_SIZE
	var outside := maxf(maxf(-uv.x,uv.x-1),maxf(-uv.y,uv.y-1))
	var blend := smoothstep(0.04,0.55,outside)
	var peaks := 65+absf(Map.noise.get_noise_2d(point.x*0.12,point.y*0.12))*180
	return lerpf(Map.elevation(point),peaks,blend)

func _build_background() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# A circular horizon extending far beyond all permitted camera positions.
	var center := Map.MAP_SIZE*0.5
	var rings := 60
	var segments := 144
	for ring in range(rings):
		for segment in range(segments):
			var points := []
			for pair in [Vector2(ring,segment),Vector2(ring+1,segment),Vector2(ring+1,segment+1),Vector2(ring,segment+1)]:
				var angle: float = pair.y/segments*TAU
				var direction := Vector2(cos(angle),sin(angle))
				# Begin at exact rectangular playable perimeter, then extend radially.
				var boundary := minf(Map.MAP_SIZE.x*0.5/maxf(absf(direction.x),0.001),Map.MAP_SIZE.y*0.5/maxf(absf(direction.y),0.001))
				points.append(center+direction*(boundary+pair.x/rings*Map.MAP_SIZE.x*3.0))
			for index in [0,2,1,0,3,2]:
				var point: Vector2 = points[index]
				var height := _background_height(point)
				var outside := maxf(maxf(-point.x/Map.MAP_SIZE.x,point.x/Map.MAP_SIZE.x-1),maxf(-point.y/Map.MAP_SIZE.y,point.y/Map.MAP_SIZE.y-1))
				var edge_color: Color = get_parent()._terrain_color(point.clamp(Vector2.ZERO,Map.MAP_SIZE-Vector2.ONE))
				var color := edge_color.lerp(Color("7d8576").lerp(Color("a4a79b"),clampf(height/200,0,1)),smoothstep(0.03,0.45,outside))
				surface.set_color(color)
				surface.add_vertex(Vector3(point.x*0.1,height,point.y*0.1))
				background_vertices += 1
	surface.index()
	surface.generate_normals()
	var terrain := MeshInstance3D.new()
	terrain.name = "BackgroundMountains"
	terrain.mesh = surface.commit()
	terrain.material_override = G.material(Color.WHITE)
	terrain.material_override.vertex_color_use_as_albedo = true
	terrain.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	add_child(terrain)
	# Instanced conifers on outskirts, outside playable terrain only.
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0
	mesh.bottom_radius = 2.7
	mesh.height = 9
	mesh.radial_segments = 5
	instances.mesh = mesh
	instances.instance_count = 1600
	var rng := RandomNumberGenerator.new()
	rng.seed = Map.map_seed+105
	for i in range(1600):
		var angle := rng.randf()*TAU
		var direction := Vector2(cos(angle),sin(angle))
		var boundary := minf(Map.MAP_SIZE.x*0.5/maxf(absf(direction.x),0.001),Map.MAP_SIZE.y*0.5/maxf(absf(direction.y),0.001))
		var point := center+direction*(boundary+rng.randf_range(50,3500))
		var scale_value := rng.randf_range(0.7,1.8)
		instances.set_instance_transform(i,Transform3D(Basis().scaled(Vector3.ONE*scale_value),Vector3(point.x*0.1,_background_height(point)+4*scale_value,point.y*0.1)))
	var forest := MultiMeshInstance3D.new()
	forest.name = "DistantForest"
	forest.multimesh = instances
	forest.material_override = G.material(Color("435c46"))
	add_child(forest)


func devastate(config: Dictionary) -> void:
	var blast = preload("res://scripts/blast_model.gd")
	for child in get_children():
		if child is MeshInstance3D and not child.position.is_zero_approx():
			if blast.intensity(Coordinates.to_simulation(child.position),config) > 0: child.hide()
	# Local road damage overlays preserve the authoritative movement graph and damage model.
	for edge in Map.roads:
		var points: PackedVector2Array = edge["points"]
		for i in range(0,points.size(),4):
			if blast.intensity(points[i],config) > 0:
				var scorch := G.cylinder(self,3.3,0.025,Coordinates.to_world(points[i],0.42),Color("393b34"))
				scorch.name = "ScorchedRoad"
