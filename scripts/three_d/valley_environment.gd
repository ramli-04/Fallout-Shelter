extends Node3D
## Batched road ribbons and a purely scenic mountain horizon. No distant simulation.
const Map = preload("res://scripts/city_map.gd")
const Coordinates = preload("res://scripts/three_d/world_coordinates.gd")
const G = preload("res://scripts/three_d/geometry.gd")
var batches := {}
var road_vertices := 0
var background_vertices := 0
var road_surfaces := {}
var ribbons := {}
var geometry_definition: Dictionary={}
var streaming_enabled:=false
var chunk_size:=1800.0
var road_chunks: Dictionary={}
var art_chunks: Dictionary={}
var damage_config: Dictionary={}

func _ready() -> void:
	name="ValleyEnvironment"
	_build_background()
	for edge in Map.roads:
		if edge.get("elevated",false) or edge.get("ramp",false): continue
		var points: PackedVector2Array=edge.points
		var width: float=edge.width*.1
		_ribbon(points,width+float(edge.sidewalk)*.2,.24,"sidewalk",Color("92958d"))
		_ribbon(points,width+.4,.28,"curb",Color("9b9d99"))
		_ribbon(points,width,.12,"asphalt",Color("414344"))
		_marks_road(edge)
	var junctions: Dictionary={}
	var pavement_widths: Dictionary={}
	for edge in Map.roads:
		if edge.get("elevated",false) or edge.get("ramp",false): continue
		for id in [edge.from,edge.to]:
			junctions[id]=maxf(float(junctions.get(id,0)),float(edge.width)*.5+5)
			pavement_widths[id]=maxf(float(pavement_widths.get(id,0)),float(edge.sidewalk))
	for id in junctions:
		var connections: PackedInt64Array=Map.graph.get_point_connections(id)
		if connections.size()<2: continue
		if connections.size()==2:
			var center: Vector2=Map.graph.get_point_position(id)
			var a: Vector2=(Map.graph.get_point_position(connections[0])-center).normalized()
			var b: Vector2=(Map.graph.get_point_position(connections[1])-center).normalized()
			if a.dot(b)<-.85: continue
			var radius: float=float(junctions[id])*1.5
			var distance:=0.0
			for step in range(48):
				var t: float=float(step)/48; var u: float=float(step+1)/48
				var start: Vector2=center+a*radius*(1-t)*(1-t)+b*radius*t*t
				var finish: Vector2=center+a*radius*(1-u)*(1-u)+b*radius*u*u
				if fmod(distance,55)<25: _ribbon(PackedVector2Array([start,finish]),.12,.17,"markings",Color("d6d4ca"))
				distance+=start.distance_to(finish)
		for layer in ["asphalt","curb","sidewalk"]:
			var radius: float=junctions[id]+({"asphalt":0,"curb":2,"sidewalk":pavement_widths[id]}[layer])
			var polygon:=PackedVector2Array()
			for i in range(20): polygon.append(Map.graph.get_point_position(id)+Vector2.from_angle(i*TAU/20)*radius)
			_polygon(polygon,float({"asphalt":.12,"curb":.28,"sidewalk":.24}[layer]),layer,Color({"asphalt":"414344","curb":"9b9d99","sidewalk":"92958d"}[layer]))
	_polygon(Map.grove.bulb,.12,"asphalt",Color("414344"))
	var bulb_ring:=Geometry2D.offset_polygon(Map.grove.bulb,24)
	if not bulb_ring.is_empty(): _polygon(bulb_ring[0],.24,"sidewalk",Color("92958d"))
	var bulb_curb:=Geometry2D.offset_polygon(Map.grove.bulb,2)
	if not bulb_curb.is_empty(): _polygon(bulb_curb[0],.28,"curb",Color("9b9d99"))
	for parcel in Map.shelter_parcels.values():
		_ribbon(PackedVector2Array([parcel.road_entry,parcel.position]),2.5,.10,"alley",Color("b6ad97"))
	for lot in Map.parking_lots:
		if lot.get("integrated_station",false): continue
		_polygon(lot.polygon,.12,"asphalt",Color("414344"))
		_ribbon(PackedVector2Array([lot.road_entry,lot.position]),3.2,.12,"asphalt",Color("414344"))
		for bay in lot.bays:
			var forward:=Vector2.from_angle(bay.heading); var side:=forward.orthogonal()
			var outline:=PackedVector2Array([bay.position+forward*33-side*15,bay.position-forward*33-side*15,bay.position-forward*33+side*15,bay.position+forward*33+side*15])
			_ribbon(outline,.10,.17,"parking_markings",Color("d7c18b"))
	for building_index in range(Map.building_data.size()):
		var building: Dictionary=Map.building_data[building_index]
		if building.has("access_path") or building.has("driveway"):
			var source_path=building.get("access_path",building.get("driveway",[]))
			var entry:=Map._v2(source_path[0])
			if not building.has("road_entry"): entry=Map.nearest_edge(entry).point
			var recipe: Dictionary=preload("res://scripts/three_d/building_shape.gd").plan(building_index)
			var door: Vector2=preload("res://scripts/three_d/building_sprites.gd").visual_door(recipe,building_index)
			_ribbon(PackedVector2Array([entry,door]),1.8,.24,"sidewalk",Color("92958d"))
		if not building.has("driveway"): continue
		var path:=Map._points(building.driveway)
		_ribbon(path,3.2,.24,"sidewalk",Color("92958d"))
		_ribbon(path,2.8,.12,"asphalt",Color("414344"))
	_ribbon(Map.grove.alley,2.0,.07,"alley",Color("a69579"))
	for points in Map.highways:
		_ribbon(points,21*float(Map.generation_settings.road_width_multiplier),.3,"highway",Color("4f5856"),true)
		_ribbon(points,.2,.34,"median",Color("d7c491"),true)
		_marks(points,true); _highway_details(points)
	for i in range(Map.ramps.size()):
		var key: String="ramp%d"%i
		_ribbon(Map.ramps[i],7.5*float(Map.generation_settings.road_width_multiplier),.3,key,Color("515957"))
		ribbons[key].profile=Map.ramps[i]
	_commit_ribbons()
	for key in batches:
		if key=="asphalt" and not art_chunks.is_empty():
			for records in art_chunks.values(): _make_art_mesh(self,records)
			continue
		var entry: Dictionary=batches[key]
		var surface: SurfaceTool=entry.surface
		if road_surfaces.get(key,{}).get("triangles",0)==0: continue
		surface.generate_normals()
		var node:=MeshInstance3D.new(); node.name=key.capitalize(); node.mesh=surface.commit()
		node.material_override=preload("res://scripts/three_d/reference_sprite_catalog.gd").road_material(key,entry.color)
		if node.material_override is StandardMaterial3D: node.material_override.cull_mode=BaseMaterial3D.CULL_DISABLED
		add_child(node)
		if key in ["curb","sidewalk"]:
			var body:=StaticBody3D.new(); body.collision_layer=64; body.collision_mask=32
			var collision:=CollisionShape3D.new(); collision.shape=node.mesh.create_trimesh_shape()
			collision.shape.backface_collision=true; body.add_child(collision); add_child(body)
	if not streaming_enabled:
		var details:=preload("res://scripts/three_d/city_details.gd").new()
		add_child(details)

func _polygon(points: PackedVector2Array, offset: float, key: String, color: Color) -> void:
	if not ribbons.has(key): ribbons[key]={"paths":[],"polygons":[],"offset":offset,"color":color,"highway":false}
	var coordinates:=[]
	for p in points: coordinates.append([p.x,p.y])
	ribbons[key].polygons.append(coordinates)

func _build_ruins() -> void:
	# Beyond the navigable boundary, separated from the highway corridor.
	for i in range(9):
		var point := Vector2(Map.MAP_SIZE.x*(.12+i*.09),-Map.MAP_SIZE.y*.16)
		var ruin := preload("res://scenes/three_d/ruin_landmark.tscn").instantiate()
		ruin.variant = i
		ruin.position = Vector3(point.x*.1,_background_height(point),point.y*.1)
		ruin.rotation.y = i*.71
		add_child(ruin)

func _marks_road(edge: Dictionary) -> void:
	var points: PackedVector2Array=edge.points
	var distance:=0.0
	for i in range(1,points.size()):
		var length: float=points[i].distance_to(points[i-1])
		var tangent: Vector2=(points[i]-points[i-1]).normalized()
		var normal:=tangent.orthogonal()
		for cursor in range(0):
			var p: Vector2=points[i-1]+tangent*cursor
			var node: int=Map.graph.get_closest_point(p)
			if Map.graph.get_point_connections(node).size()>2 and p.distance_to(Map.graph.get_point_position(node))<95: continue
			if fmod(distance+cursor,65)>28: continue
			var offsets: Array=[0.0]
			if edge.lanes==4: offsets=[-float(edge.width)*.25,0.0,float(edge.width)*.25]
			for offset in offsets:
				_ribbon(PackedVector2Array([p+normal*offset,p+normal*offset+tangent*9]),.12,.16,"markings",Color("d6d4ca"))
		distance+=length
	# Zebra stripes outside the intersection mouth, aligned to each approach.
	for end in [0,1]:
		var id: int=edge.from if end==0 else edge.to
		if Map.graph.get_point_connections(id).size()<3: continue
		var p: Vector2=points[0] if end==0 else points[-1]
		var tangent: Vector2=(points[1]-p).normalized() if end==0 else (points[-2]-p).normalized()
		var normal:=tangent.orthogonal()
		p+=tangent*(float(edge.width)*.5+70)
		var stop_point: Vector2=(points[0] if end==0 else points[-1])+tangent*(float(edge.width)*.5+102)
		_ribbon(PackedVector2Array([stop_point-normal*float(edge.width)*.5,stop_point]),.3,.17,"markings",Color("f0e8cd"))
		for stripe in range(-int(edge.width*.5)+8,int(edge.width*.5)-7,10):
			_ribbon(PackedVector2Array([p+normal*stripe,p+normal*stripe+tangent*24]),.45,.16,"markings",Color("d6d4ca"))

func _surface(key: String, color: Color) -> SurfaceTool:
	if not batches.has(key):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		batches[key] = {"surface":surface,"color":color}
	return batches[key]["surface"]

func _height(point: Vector2, highway: bool) -> float:
	return Map.elevation(point)+(10.0 if highway else 0.0)

func _ribbon(points: PackedVector2Array, width: float, offset: float, key: String, color: Color, highway: bool = false) -> void:
	if points.size()<2: return
	var group: String=key+("_elevated" if highway else "")
	if not ribbons.has(group): ribbons[group]={"paths":[],"polygons":[],"offset":offset,"color":color,"highway":highway}
	var coordinates:=[]
	for p in points: coordinates.append([p.x,p.y])
	ribbons[group].paths.append({"points":coordinates,"width":width*5})

func _commit_ribbons() -> void:
	var groups: Dictionary={}
	for key in ribbons:
		groups[key]={"paths":ribbons[key].paths,"polygons":ribbons[key].polygons,"terrain_cell":Map.terrain_cell}
	groups.sidewalk.subtract=["curb","asphalt"]
	groups.curb.subtract=["asphalt"]
	groups.asphalt.art_roads=Map.roads
	groups.asphalt.art_revision=(FileAccess.get_file_as_string("res://ai_service/road_art_layout.py")+FileAccess.get_file_as_string("res://ai_service/road_geometry.py")).sha256_text()
	groups.asphalt.art_nodes=[]
	for id in Map.graph.get_point_ids():
		var point: Vector2=Map.graph.get_point_position(id)
		groups.asphalt.art_nodes.append([point.x,point.y])
	groups.asphalt.art_parking=[]
	for lot in Map.parking_lots:
		if lot.get("integrated_station",false): continue
		var polygon:=[]
		for point in lot.polygon: polygon.append([point.x,point.y])
		groups.asphalt.art_parking.append({"polygon":polygon,"position":[lot.position.x,lot.position.y]})
	geometry_definition=groups
	var encoded:=JSON.stringify(_json_vectors(groups),"",true,true)
	var digest:=encoded.sha256_text().substr(0,20)
	var input:=ProjectSettings.globalize_path("user://city_cache/roads_%d_%s.input.json"%[OS.get_process_id(),digest])
	var output:=ProjectSettings.globalize_path("user://city_cache/roads_%s.json"%digest)
	var file:=FileAccess.open(input,FileAccess.WRITE)
	file.store_string(encoded); file.close()
	var python:=ProjectSettings.globalize_path("res://.venv/Scripts/python.exe")
	if not FileAccess.file_exists(python): python="python3"
	var logs:=[]
	if not FileAccess.file_exists(output) and OS.execute(python,["-m","ai_service.road_geometry",input,output],logs,true)!=0:
		push_error("Road triangulation failed: "+str(logs)); return
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(output))
	_partition_art(data.get("art",[]))
	if streaming_enabled:
		_partition_roads(data.groups)
		return
	for key in ribbons:
		var definition: Dictionary=ribbons[key]
		var surface:=_surface(key,definition.color)
		var geometry: Dictionary={"triangles":0,"polygons":[],"degenerate":0}
		road_surfaces[key]=geometry
		for triangle in data.groups[key]:
			var a:=Vector2(triangle[0][0],triangle[0][1])
			var b:=Vector2(triangle[1][0],triangle[1][1])
			var c:=Vector2(triangle[2][0],triangle[2][1])
			if not Rect2(Vector2.ZERO,Map.MAP_SIZE).has_point((a+b+c)/3): continue
			_emit_triangle(surface,a,b,c,definition.offset,definition.highway,0,definition.get("profile",PackedVector2Array()))
			geometry.triangles+=1

func _road_vertex(point: Vector2, definition: Dictionary) -> Vector3:
	var height:=_height(point,definition.highway)+float(definition.offset)
	var profile: PackedVector2Array=definition.get("profile",PackedVector2Array())
	if not profile.is_empty():
		var closest:=INF; var along:=0.0; var cursor:=0.0; var total:=Map._path_length(profile)
		for i in range(1,profile.size()):
			var projected:=Geometry2D.get_closest_point_to_segment(point,profile[i-1],profile[i])
			var distance:=projected.distance_squared_to(point)
			if distance<closest: closest=distance; along=cursor+profile[i-1].distance_to(projected)
			cursor+=profile[i-1].distance_to(profile[i])
		height+=10*(1-along/maxf(.001,total))
	return Vector3(point.x*.1,height,point.y*.1)

func _json_vectors(value: Variant) -> Variant:
	if value is Vector2: return [value.x,value.y]
	if value is PackedVector2Array or value is Array:
		var result:=[]
		for item in value: result.append(_json_vectors(item))
		return result
	if value is Dictionary:
		var result: Dictionary={}
		for key in value: result[key]=_json_vectors(value[key])
		return result
	return value

func _partition_art(records: Array) -> void:
	art_chunks.clear()
	for record in records:
		var a:=Map._v2(record.vertices[0]); var b:=Map._v2(record.vertices[1]); var c:=Map._v2(record.vertices[2])
		var center: Vector2=(a+b+c)/3
		if not Rect2(Vector2.ZERO,Map.MAP_SIZE).has_point(center): continue
		var cell:=Vector2i((center/chunk_size).floor())
		if not art_chunks.has(cell): art_chunks[cell]=[]
		art_chunks[cell].append(record)

func _make_art_mesh(parent: Node3D,records: Array) -> void:
	var groups: Dictionary={}
	for record in records:
		var lanes: int=-1 if int(record.tile)==-1 else 4 if int(record.tile)==-4 else 2
		if not groups.has(lanes):
			var surface:=SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES); groups[lanes]=surface
		for index in [0,2,1]:
			var vertex: Array=record.vertices[index]
			groups[lanes].set_uv(Vector2(vertex[2],vertex[3]))
			groups[lanes].set_uv2(Vector2(maxi(0,int(record.tile)),0))
			groups[lanes].add_vertex(Coordinates.to_world(Vector2(vertex[0],vertex[1]),.12))
	for lanes in groups:
		var mesh:=MeshInstance3D.new(); mesh.name="ConnectedRoadArtwork"; mesh.mesh=groups[lanes].commit()
		mesh.material_override=preload("res://scripts/three_d/reference_road_tiles.gd").material(lanes)
		mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; parent.add_child(mesh)

func _partition_roads(groups: Dictionary) -> void:
	for key in groups:
		var definition: Dictionary=ribbons[key]
		var physical:=PackedVector3Array()
		road_surfaces[key]={"triangles":groups[key].size(),"degenerate":0}
		for triangle in groups[key]:
			var a:=Map._v2(triangle[0]); var b:=Map._v2(triangle[1]); var c:=Map._v2(triangle[2])
			if not Rect2(Vector2.ZERO,Map.MAP_SIZE).has_point((a+b+c)/3): continue
			var cell:=Vector2i(((a+b+c)/3/chunk_size).floor())
			if not road_chunks.has(cell): road_chunks[cell]={}
			if not road_chunks[cell].has(key): road_chunks[cell][key]=PackedVector3Array()
			var vertices:=PackedVector3Array([_road_vertex(a,definition),_road_vertex(c,definition),_road_vertex(b,definition)])
			road_chunks[cell][key].append_array(vertices)
			if key in ["curb","sidewalk"]: physical.append_array(vertices)
		if not physical.is_empty():
			var body:=StaticBody3D.new(); body.collision_layer=64; body.collision_mask=32
			var shape:=CollisionShape3D.new(); var mesh:=ConcavePolygonShape3D.new(); mesh.set_faces(physical); mesh.backface_collision=true
			shape.shape=mesh; body.add_child(shape); add_child(body)

func make_chunk(cell: Vector2i) -> Node3D:
	var root:=Node3D.new(); root.name="RoadSurfaces"
	for key in road_chunks.get(cell,{}):
		if key=="sidewalk":
			preload("res://scripts/three_d/reference_road_tiles.gd").paving_surface(root,road_chunks[cell][key]); continue
		if key=="asphalt":
			if not art_chunks.is_empty():
				_make_art_mesh(root,art_chunks.get(cell,[])); continue
			preload("res://scripts/three_d/reference_road_tiles.gd").conforming_surface(root,road_chunks[cell][key]); continue
		var surface:=SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for point in road_chunks[cell][key]: surface.add_vertex(point)
		surface.generate_normals()
		var mesh:=MeshInstance3D.new(); mesh.mesh=surface.commit(); mesh.material_override=preload("res://scripts/three_d/reference_sprite_catalog.gd").road_material(key,ribbons[key].color)
		if mesh.material_override is StandardMaterial3D: mesh.material_override.cull_mode=BaseMaterial3D.CULL_DISABLED
		root.add_child(mesh)
	var bounds:=Rect2(Vector2(cell)*chunk_size,Vector2.ONE*chunk_size)
	for lot in Map.parking_lots:
		if lot.get("integrated_station",false): continue
		if not bounds.has_point(lot.position) or lot.bays.is_empty(): continue
		var bay: Dictionary=lot.bays[0]
		preload("res://scripts/three_d/reference_sprite_catalog.gd").ground_decal(root,"accessible_paving",Vector2(6.2,2.8),Coordinates.to_world(bay.position,.15),bay.heading)
		if lot.category in ["hospital","police","offices","motel"]:
			var service_bay: Dictionary=lot.bays[-1]
			preload("res://scripts/three_d/reference_sprite_catalog.gd").ground_decal(root,"loading_paving",Vector2(6.2,2.8),Coordinates.to_world(service_bay.position,.15),service_bay.heading)
	decorate_damage(root,bounds)
	return root

func decorate_damage(root: Node3D,bounds: Rect2) -> void:
	if damage_config.is_empty() or root.has_meta("road_damage"): return
	root.set_meta("road_damage",true)
	var blast=preload("res://scripts/blast_model.gd")
	for edge in Map.roads:
		for i in range(0,edge.points.size(),4):
			var point: Vector2=edge.points[i]
			if bounds.has_point(point) and blast.intensity(point,damage_config)>0:
				preload("res://scripts/three_d/reference_sprite_catalog.gd").ground_decal(root,"road_damaged" if i%8==0 else "road_pothole",Vector2(6.5,6.5),Coordinates.to_world(point,.42))

func _emit_triangle(surface: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, offset: float, highway: bool, depth: int, profile: PackedVector2Array = PackedVector2Array()) -> void:
	for point in [a,c,b]:
		var height:=_height(point,highway)+offset
		if not profile.is_empty():
			var closest:=INF; var along:=0.0; var cursor:=0.0; var total:=Map._path_length(profile)
			for i in range(1,profile.size()):
				var projected:=Geometry2D.get_closest_point_to_segment(point,profile[i-1],profile[i])
				var d:=projected.distance_squared_to(point)
				if d<closest: closest=d; along=cursor+profile[i-1].distance_to(projected)
				cursor+=profile[i-1].distance_to(profile[i])
			height+=10*(1-along/maxf(.001,total))
		surface.add_vertex(Vector3(point.x*.1,height,point.y*.1)); road_vertices+=1

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
			if not Rect2(Vector2.ZERO,Map.MAP_SIZE).has_point(point): continue
			for lane in [-2,-1,1,2] if highway else [0]:
				var mid: Vector2 = point+normal*lane*35*float(Map.generation_settings.road_width_multiplier)
				_ribbon(PackedVector2Array([mid,mid+tangent*9]),0.12,0.38,"markings",Color("d9cfad"),highway)
		distance += length

func _highway_details(points: PackedVector2Array) -> void:
	for side in [-1,1]:
		var rail := PackedVector2Array()
		for i in range(points.size()):
			var direction := (points[mini(i+1,points.size()-1)]-points[maxi(0,i-1)]).normalized()
			rail.append(points[i]+direction.orthogonal()*side*104*float(Map.generation_settings.road_width_multiplier))
		_ribbon(rail,0.32,1.0,"guardrails",Color("b5b9ac"),true)
	for i in range(4,points.size()-3,5):
		if not Rect2(Vector2.ZERO,Map.MAP_SIZE).has_point(points[i]): continue
		var ground: Dictionary=Map.nearest_edge(points[i])
		if ground.point.distance_to(points[i])<float(ground.edge.width)*.5+25: continue
		var point := Coordinates.to_world(points[i],0)
		G.box(self,Vector3(1.5,10,3.5),point+Vector3.UP*5,Color("92988c"))
	for index in [15,55,88]:
		if not Rect2(Vector2.ZERO,Map.MAP_SIZE).has_point(points[index]): continue
		var point := Coordinates.to_world(points[index],11)
		G.box(self,Vector3(0.22,5,0.22),point+Vector3(7,2.5,0),Color("a3aaa0"))
		G.box(self,Vector3(7,2,0.22),point+Vector3(4,4,0),Color("375d54"))
		G.label(self,"VALLEY / A7",point+Vector3(4,4,0.2),Color("e5e6d3"),25,0.025)

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
	var rings := 30
	# Match every playable terrain edge vertex, including the four corners.
	var perimeter:=PackedVector2Array()
	var nx:=ceili(Map.MAP_SIZE.x/Map.terrain_cell); var ny:=ceili(Map.MAP_SIZE.y/Map.terrain_cell)
	for x in range(nx): perimeter.append(Vector2(minf(x*Map.terrain_cell,Map.MAP_SIZE.x),0))
	for y in range(ny): perimeter.append(Vector2(Map.MAP_SIZE.x,minf(y*Map.terrain_cell,Map.MAP_SIZE.y)))
	for x in range(nx,0,-1): perimeter.append(Vector2(minf(x*Map.terrain_cell,Map.MAP_SIZE.x),Map.MAP_SIZE.y))
	for y in range(ny,0,-1): perimeter.append(Vector2(0,minf(y*Map.terrain_cell,Map.MAP_SIZE.y)))
	var segments := perimeter.size()
	for ring in range(rings):
		for segment in range(segments):
			var points := []
			for pair in [Vector2(ring,segment),Vector2(ring+1,segment),Vector2(ring+1,segment+1),Vector2(ring,segment+1)]:
				var edge: Vector2=perimeter[int(pair.y)%segments]
				var direction: Vector2=(edge-center).normalized()
				points.append(edge+direction*pow(pair.x/rings,1.7)*Map.MAP_SIZE.x*14.0)
			for index in [0,2,1,0,3,2]:
				var point: Vector2 = points[index]
				var height := _background_height(point)-.02

				surface.add_vertex(Vector3(point.x*0.1,height,point.y*0.1))
				background_vertices += 1
	surface.index()
	surface.generate_normals()
	var terrain := MeshInstance3D.new()
	terrain.name = "BackgroundMountains"
	terrain.mesh = surface.commit()
	terrain.material_override = preload("res://scripts/three_d/grass_material.gd").material()
	add_child(terrain)
	# The horizon uses the same flat conifer artwork as the playable chunks.
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	var mesh := QuadMesh.new(); mesh.size=Vector2(5.8,9); mesh.center_offset=Vector3(0,4.5,0)
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
		instances.set_instance_transform(i,Transform3D(Basis().scaled(Vector3.ONE*scale_value),Vector3(point.x*0.1,_background_height(point),point.y*0.1)))
	var forest := MultiMeshInstance3D.new()
	forest.name = "DistantForest"
	forest.multimesh = instances
	forest.material_override = preload("res://scripts/three_d/reference_sprite_catalog.gd").material("new_tree0")
	forest.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	forest.extra_cull_margin=20
	add_child(forest)


func devastate(config: Dictionary) -> void:
	if streaming_enabled:
		damage_config=config.duplicate(true)
		for chunk in get_parent().streamer.chunks.values():
			if is_instance_valid(chunk.node):
				var roads: Node3D=chunk.node.get_node_or_null("RoadSurfaces")
				if roads!=null: decorate_damage(roads,chunk.bounds)
		return
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
