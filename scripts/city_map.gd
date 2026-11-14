extends Node2D
## Seeded shared geography. Simulation, rendering, spawns and routes use this source.
static var MAP_SIZE := Vector2(6750, 4050)
const ROAD_SPACING := 180 # Legacy unit used by incident radii and historical fixtures.
static var map_seed := 42
static var tile_grid: RefCounted
static var x_cuts: Array[float] = []
static var y_cuts: Array[float] = []
static var roads: Array[Dictionary] = []
static var edge_lookup := {}
static var lots: Array[Rect2] = []
static var sites := {}
static var shelter_parcels: Dictionary = {}
static var park := Rect2()
static var green_zone := Rect2()
static var lake := Rect2()
static var hill := Vector2.ZERO
static var noise: FastNoiseLite
static var graph: AStar2D
static var pois: Array[Dictionary] = []
static var free_grid: AStarGrid2D
const FREE_CELL := 30.0
const ROAD_CELL_SIZE := 192.0
static var road_segment_cells: Dictionary = {}
static var road_segments: Array[Vector2i] = []
static var road_index_road_count := -1
static var road_index_segment_count := -1
const FREE_PATH_CACHE_LIMIT := 2048
static var free_path_cache: Dictionary={}
static var free_path_cache_order: Array[String]=[]
static var free_path_cache_revision := -1
static var lot_angles: Array[float] = []
static var lot_districts: Array[String] = []
static var rock_obstacles: Array[Rect2] = []
const OBSTACLE_CELL_SIZE := 128.0
static var obstacle_cells: Dictionary = {}
static var obstacle_records: Array[Rect2] = []
static var obstacle_index_count := -1
static var closures: Dictionary = {}
static var roadblock_data := {}
static var interior_cutaway := false
static var interior_data: Dictionary = {}
static var parking_lots: Array[Dictionary] = []
static var ramps: Array[PackedVector2Array] = []
static var highways: Array[PackedVector2Array] = []

static var generation_settings: Dictionary = {}
static var validation: Dictionary = {}
static var districts: Array = []
static var grove: Dictionary = {}
static var building_data: Array = []
static var generation_ms := 0.0
static var terrain_cell := 40.0
static var terrain_heights := PackedFloat32Array()
static var terrain_columns := 0
static var terrain_rows := 0
static var foundation_index := {}
static var foundation_pads: Array = []
static var generation_error := ""
static var navigation_revision := 0
static var traffic_signals: Dictionary = {}
static var traffic_time := 0.0
static var signal_settings: Dictionary = {}
static var layout_version := 0
static var terrain_definition: Dictionary = {}
static var vegetation_data: Array = []
static var prop_data: Array = []
static var infrastructure_data: Array = []
static var roundabout_data: Array = []
static var generated_world: Dictionary = {}

static func default_settings() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://resources/city_generation.json"))

static func generate(seed_value: int, parking_count: int = 12, options: Dictionary = {}) -> bool:
	var started := Time.get_ticks_usec()
	free_path_cache.clear(); free_path_cache_order.clear(); free_path_cache_revision=-1
	closures.clear(); roadblock_data.clear(); validation.clear(); generation_error=""
	generation_settings=default_settings()
	generation_settings.merge(options,true)
	for key in ["area_multiplier","road_width_multiplier","terrain_cell"]:
		if not (generation_settings[key] is int or generation_settings[key] is float) or not is_finite(float(generation_settings[key])):
			generation_error="Invalid city setting: "+key; return false
	if generation_settings.area_multiplier<1 or generation_settings.area_multiplier>3 or generation_settings.terrain_cell<20 or generation_settings.terrain_cell>40:
		generation_error="City area must be 1-3 and terrain cells 20-40"; return false
	var base: Vector2=Vector2(6750,4050)*sqrt(float(generation_settings.area_multiplier))
	var dimensions: Array=options.get("size",[base.x,base.y])
	MAP_SIZE=Vector2(dimensions[0],dimensions[1])
	map_seed=seed_value
	noise=FastNoiseLite.new(); noise.seed=seed_value; noise.frequency=.0018; noise.fractal_octaves=3
	var request: Dictionary={"seed":seed_value,"size":[MAP_SIZE.x,MAP_SIZE.y],"road_width_multiplier":generation_settings.road_width_multiplier,"parking_count":parking_count}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://city_cache"))
	var digest:=JSON.stringify(request,"",true,true).sha256_text().substr(0,20)
	var input:=ProjectSettings.globalize_path("user://city_cache/request_%d_%s.json"%[OS.get_process_id(),digest])
	var output:=ProjectSettings.globalize_path("user://city_cache/layout_%s.json"%digest)
	var file:=FileAccess.open(input,FileAccess.WRITE)
	if file==null: generation_error="Cannot write city generation request"; return false
	file.store_string(JSON.stringify(request)); file.close()
	var python:=ProjectSettings.globalize_path("res://.venv/Scripts/python.exe")
	if not FileAccess.file_exists(python): python="python3"
	var logs:=[]
	if OS.execute(python,["-m","ai_service.city_generator",input,output],logs,true)!=0:
		generation_error="City generation/validation failed: "+str(logs); push_error(generation_error); return false
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(output))
	if not data is Dictionary or not data.get("validation",{}).get("valid",false):
		generation_error="Invalid generated city"; return false
	return load_layout(data,generation_settings,started)

static func load_layout(data: Dictionary, options: Dictionary = {}, started: int = 0) -> bool:
	# Immutable JSON is hydrated into the same runtime API as historical maps.
	if not data.get("validation",{}).get("valid",false): generation_error="Unvalidated world"; return false
	var logical_report: Dictionary=preload("res://scripts/generation/building_validator.gd").validate(data)
	if not logical_report.valid:
		generation_error="Godot placement validation rejected layout: "+str(logical_report.errors)
		push_error(generation_error); return false
	print("City generation report: ",logical_report)
	var next_grid=preload("res://scripts/generation/chunk_grid.gd").new()
	if data.has("tile_world") and not next_grid.load_manifest(data.tile_world):
		generation_error="Tile placement rejected: "+next_grid.error; return false
	if data.has("tile_world") and not next_grid.validate_buildings(data.buildings):
		generation_error="Tile placement rejected: "+next_grid.error; return false
	tile_grid=next_grid
	print("Tile grid: ",tile_grid.chunks.size()," chunks, ",tile_grid.entities.size()," assets; tile=",tile_grid.tile_size," chunk=",tile_grid.chunk_tiles,"x",tile_grid.chunk_tiles)
	data=data.duplicate(true)
	data.validation["godot"]=logical_report
	generated_world.clear()
	free_path_cache.clear(); free_path_cache_order.clear(); free_path_cache_revision=-1
	closures.clear(); roadblock_data.clear(); generation_error=""
	generation_settings=default_settings(); generation_settings.merge(options,true)
	MAP_SIZE=_v2(data.size); map_seed=int(data.seed)
	terrain_definition=data.get("terrain",{}).duplicate(true)
	vegetation_data=data.get("vegetation",[]).duplicate(true)
	prop_data=data.get("environment_props",[]).duplicate(true)
	infrastructure_data=data.get("infrastructure",[]).duplicate(true)
	roundabout_data=data.get("roundabouts",[]).duplicate(true)
	noise=FastNoiseLite.new(); noise.seed=int(terrain_definition.get("noise_seed",map_seed)); noise.frequency=.0018; noise.fractal_octaves=3
	validation=data.validation
	layout_version=int(data.version)
	graph=preload("res://scripts/road_graph.gd").new()
	interior_data.clear(); roads.clear(); edge_lookup.clear(); sites.clear(); lots.clear(); lot_angles.clear(); lot_districts.clear(); pois.clear(); parking_lots.clear(); ramps.clear(); highways.clear(); rock_obstacles.clear()
	for i in range(data.nodes.size()): graph.add_point(i,_v2(data.nodes[i]))
	for record in data.roads:
		var edge: Dictionary=record.duplicate(true)
		edge.from=int(edge.from); edge.to=int(edge.to); edge.points=_points(edge.points)
		edge.a=edge.points[0]; edge.b=edge.points[-1]
		graph.connect_points(edge.from,edge.to); edge_lookup[Vector2i(edge.from,edge.to)]=edge.points; _store_cost(edge.from,edge.to,edge.points)
		roads.append(edge)
	_rebuild_road_index()
	shelter_parcels.clear()
	for key in data.sites:
		var access: Dictionary=data.get("shelter_access",{}).get(key,{"position":data.sites[key],"road_entry":data.sites[key]})
		sites[key]=_v2(access.position)
		shelter_parcels[key]={"position":sites[key],"road_entry":_v2(access.road_entry),"bounds":_rect(access.get("bounds",[sites[key].x-80,sites[key].y-80,160,160]))}
	park=_rect(data.park); lake=_rect(data.lake); hill=sites.S5
	green_zone=Rect2(MAP_SIZE*Vector2(.73,0),MAP_SIZE*Vector2(.27,.64))
	x_cuts=[0.0,MAP_SIZE.x]; y_cuts=[0.0,MAP_SIZE.y]
	building_data=data.buildings
	for building in building_data:
		lots.append(_rect(building.rect)); lot_angles.append(float(building.angle)); lot_districts.append(building.district)
	for record in data.pois:
		var poi: Dictionary=record.duplicate(true)
		poi.position=_v2(poi.position); poi.roof_position=_v2(poi.roof_position); poi.footprint=_rect(poi.footprint)
		pois.append(poi)
	for record in data.parking_lots:
		var lot: Dictionary=record.duplicate(true)
		for key in ["position","road_entry","tangent","normal"]: lot[key]=_v2(lot[key])
		lot.bounds=_rect(lot.bounds); lot.polygon=_points(lot.polygon)
		for bay in lot.bays: bay.position=_v2(bay.position); bay.approach=_points(bay.approach)
		parking_lots.append(lot)
	for points in data.highways: highways.append(_points(points))
	for points in data.ramps: ramps.append(_points(points))
	districts=data.districts
	for d in districts: d.polygon=_points(d.polygon); d.center=_v2(d.center)
	grove=data.grove; grove.center=_v2(grove.center); grove.entrance=_v2(grove.entrance); grove.gathering=_v2(grove.gathering); grove.bounds=_rect(grove.bounds); grove.bulb=_points(grove.bulb); grove.alley=_points(grove.alley)
	for item in vegetation_data+prop_data:
		var p:=_v2(item.position)
		rock_obstacles.append(Rect2(p-Vector2.ONE*4,Vector2.ONE*8))
	_build_foundations()
	_build_terrain_heights()
	_build_walk_grid()
	_rebuild_obstacle_index()
	# Runtime connectivity and obstacle-aware shelter access are checked as well.
	for site in sites.values():
		if graph.get_id_path(0,graph.get_closest_point(site)).is_empty() or free_route(nearest_lane_point(MAP_SIZE*.5),site).is_empty():
			generation_error="Critical shelter is unreachable"; validation.valid=false; return false
	generation_ms=float(Time.get_ticks_usec()-started)/1000 if started>0 else 0.0
	navigation_revision+=1
	return true

static func _v2(value: Array) -> Vector2: return Vector2(value[0],value[1])
static func _rect(value: Array) -> Rect2: return Rect2(value[0],value[1],value[2],value[3])
static func _points(value: Array) -> PackedVector2Array:
	var result:=PackedVector2Array()
	for p in value: result.append(_v2(p))
	return result

static func _build_walk_grid() -> void:
	free_grid=AStarGrid2D.new()
	free_grid.region=Rect2i(0,0,ceili(MAP_SIZE.x/FREE_CELL),ceili(MAP_SIZE.y/FREE_CELL))
	free_grid.cell_size=Vector2.ONE*FREE_CELL; free_grid.offset=Vector2.ONE*FREE_CELL*.5
	free_grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	free_grid.default_compute_heuristic=AStarGrid2D.HEURISTIC_OCTILE; free_grid.default_estimate_heuristic=AStarGrid2D.HEURISTIC_OCTILE
	free_grid.update()
	for rect in lots+[lake]+rock_obstacles:
		var bounds: Rect2=rect.grow(12)
		var first:=Vector2i((bounds.position/FREE_CELL).floor()); var last:=Vector2i((bounds.end/FREE_CELL).ceil())
		for x in range(maxi(0,first.x),mini(free_grid.region.end.x,last.x+1)):
			for y in range(maxi(0,first.y),mini(free_grid.region.end.y,last.y+1)):
				if bounds.has_point(Vector2(x,y)*FREE_CELL+Vector2.ONE*FREE_CELL*.5): free_grid.set_point_solid(Vector2i(x,y))

static func district_at(point: Vector2) -> String:
	if not grove.is_empty() and grove.bounds.has_point(point): return "GROVE"
	for district in districts:
		if Geometry2D.is_point_in_polygon(point,district.polygon): return district.name
	return "MOUNTAINS"

static func claim_parking(vehicle_id: String, near: Vector2) -> Dictionary:
	if vehicle_id.is_empty(): return {}
	for lot in parking_lots:
		for bay in lot.bays:
			if bay.occupied_by==vehicle_id: return bay
	var best: Dictionary={}; var distance:=INF
	for lot in parking_lots:
		for bay in lot.bays:
			var d: float=near.distance_squared_to(bay.position)
			if bay.occupied_by.is_empty() and d<distance: best=bay; distance=d
	if not best.is_empty(): best.occupied_by=vehicle_id
	return best

static func release_parking(vehicle_id: String) -> void:
	for lot in parking_lots:
		for bay in lot.bays:
			if bay.occupied_by==vehicle_id: bay.occupied_by=""

static func restore_parking(vehicles: Array) -> void:
	for lot in parking_lots:
		for bay in lot.bays:
			bay.occupied_by=""
			for vehicle in vehicles:
				if vehicle.get("parking_bay","")==bay.id and vehicle.status=="PARKED" and vehicle.position.distance_to(bay.position)<1:
					bay.occupied_by=vehicle.id; break

static func travel_estimates(start: Vector2) -> Dictionary:
	var result: Dictionary={}
	for id in sites:
		var walking:=_path_length(free_route(start,sites[id]))
		var driving:=_path_length(route(start,sites[id]))
		result[id]={"walk_metres":walking*.1,"walk_seconds":walking/14.0,"drive_metres":driving*.1,"drive_seconds":driving/95.0}
	return result

static func ensure() -> void:
	if graph == null and generation_error.is_empty(): generate(map_seed)

static func building_rects() -> Array[Rect2]:
	ensure()
	return lots

static func points_of_interest() -> Array[Dictionary]:
	ensure()
	return pois

static func park_cells() -> Array[Vector2i]:
	ensure()
	var result: Array[Vector2i] = []
	for x in range(int(MAP_SIZE.x/180)):
		for y in range(int(MAP_SIZE.y/180)):
			if is_park(Vector2i(x,y)): result.append(Vector2i(x,y))
	return result

static func is_park(cell: Vector2i) -> bool:
	var point := Vector2(cell)*180+Vector2(90,90)
	return park.has_point(point) or green_zone.has_point(point)

static func _raw_elevation(point: Vector2) -> float:
	var uv:=point/MAP_SIZE
	var mountain: Vector2=_v2(terrain_definition.get("mountain_center",[MAP_SIZE.x*.89,MAP_SIZE.y*.15]))/MAP_SIZE
	var height:=noise.get_noise_2d(point.x,point.y)*1.1+55*exp(-pow((uv.x-mountain.x)/.16,2)-pow((uv.y-mountain.y)/.30,2))
	var relative: Vector2=(point-lake.get_center())/(lake.size*.5)
	return lerpf(height,-1.4,1-smoothstep(.8,1.35,relative.length()))

static func _build_foundations() -> void:
	foundation_index.clear(); foundation_pads.clear()
	var pads: Array=lots.duplicate()
	for lot in parking_lots: pads.append(lot.bounds)
	for parcel in shelter_parcels.values(): pads.append(parcel.bounds)
	# Nearby pads share a grade when their terrain support cells overlap. This
	# prevents one foundation's blend from lifting a neighbouring house corner.
	var parent:=[]
	for i in range(pads.size()): parent.append(i)
	for i in range(pads.size()):
		for j in range(i):
			if not pads[i].grow(40).intersects(pads[j].grow(40)): continue
			var a: int=i; var b: int=j
			while parent[a]!=a: a=parent[a]
			while parent[b]!=b: b=parent[b]
			parent[a]=b
	var grades: Dictionary={}
	for i in range(pads.size()):
		var root: int=i
		while parent[root]!=root: root=parent[root]
		parent[i]=root
		if not grades.has(root): grades[root]=[]
		grades[root].append(_raw_elevation(pads[i].get_center()))
	for rect in pads:
		var index:=foundation_pads.size()
		var samples: Array=grades[parent[index]]; var grade:=0.0
		for value in samples: grade+=float(value)/samples.size()
		foundation_pads.append({"rect":rect,"height":grade})
		var first:=Vector2i((rect.grow(105).position/200).floor()); var last:=Vector2i((rect.grow(105).end/200).floor())
		for x in range(first.x,last.x+1):
			for y in range(first.y,last.y+1):
				var key:=Vector2i(x,y)
				if not foundation_index.has(key): foundation_index[key]=[]
				foundation_index[key].append(index)

static func _terrain_height(point: Vector2) -> float:
	var height:=_raw_elevation(point)
	for index in foundation_index.get(Vector2i((point/200).floor()),[]):
		var pad: Dictionary=foundation_pads[index]
		if pad.rect.grow(40).has_point(point): return float(pad.height)
	for index in foundation_index.get(Vector2i((point/200).floor()),[]):
		var pad: Dictionary=foundation_pads[index]; var rect: Rect2=pad.rect
		var flat: Rect2=rect.grow(40)
		var outside:=maxf(maxf(flat.position.x-point.x,point.x-flat.end.x),maxf(flat.position.y-point.y,point.y-flat.end.y))
		if outside<65: height=lerpf(float(pad.height),height,smoothstep(0,65,outside))
	return height

static func _build_terrain_heights() -> void:
	terrain_cell=float(generation_settings.get("terrain_cell",40))
	terrain_columns=ceili(MAP_SIZE.x/terrain_cell); terrain_rows=ceili(MAP_SIZE.y/terrain_cell)
	terrain_heights.resize((terrain_columns+1)*(terrain_rows+1))
	for y in range(terrain_rows+1):
		for x in range(terrain_columns+1):
			terrain_heights[y*(terrain_columns+1)+x]=_terrain_height(Vector2(x,y)*terrain_cell)

static func elevation(point: Vector2) -> float:
	if noise==null: return 0.0
	if terrain_heights.is_empty() or point.x<0 or point.y<0 or point.x>MAP_SIZE.x or point.y>MAP_SIZE.y: return _terrain_height(point)
	var cell:=Vector2i((point/terrain_cell).floor())
	cell=cell.clamp(Vector2i.ZERO,Vector2i(terrain_columns-1,terrain_rows-1))
	var uv:=point/terrain_cell-Vector2(cell)
	var i:=cell.y*(terrain_columns+1)+cell.x
	var a:=terrain_heights[i]; var b:=terrain_heights[i+terrain_columns+1]
	var c:=terrain_heights[i+terrain_columns+2]; var d:=terrain_heights[i+1]
	# Matches terrain triangles a,c,b and a,d,c exactly, including road vertices.
	return a+(d-a)*uv.x+(c-d)*uv.y if uv.x>=uv.y else a+(c-b)*uv.x+(b-a)*uv.y

static func _path_length(points: PackedVector2Array) -> float:
	var distance:=0.0
	for i in range(1,points.size()): distance+=points[i-1].distance_to(points[i])
	return distance

static func nearest_edge(point: Vector2, include_elevated: bool = false, height: float = -1) -> Dictionary:
	ensure()
	_ensure_road_index()
	var best := {}
	var distance := INF
	var origin:=Vector2i((point/ROAD_CELL_SIZE).floor())
	var seen: Dictionary={}
	var max_ring:=ceili(maxf(MAP_SIZE.x,MAP_SIZE.y)/ROAD_CELL_SIZE)+2
	for ring in range(max_ring+1):
		for x in range(origin.x-ring,origin.x+ring+1):
			for y in range(origin.y-ring,origin.y+ring+1):
				if ring>0 and x!=origin.x-ring and x!=origin.x+ring and y!=origin.y-ring and y!=origin.y+ring: continue
				for segment_id in road_segment_cells.get(Vector2i(x,y),[]):
					if seen.has(segment_id): continue
					seen[segment_id]=true
					var segment: Vector2i=road_segments[segment_id]
					var edge: Dictionary=roads[segment.x]
					if not include_elevated and (edge.get("elevated",false) or edge.get("ramp",false)): continue
					var i: int=segment.y
					var points: PackedVector2Array=edge.points
					var projected:=Geometry2D.get_closest_point_to_segment(point,points[i-1],points[i])
					var delta:=point.distance_squared_to(projected)
					if height>=0:
						var road_height: float=10 if edge.get("elevated",false) else 0
						if edge.get("ramp",false): road_height=10*(1-float(i)/points.size())
						delta+=pow(road_height-height,2)*100
					if delta<distance:
						distance=delta; best={"point":projected,"edge":edge,"segment":i-1}
		if distance<INF:
			var left: float=origin.x*ROAD_CELL_SIZE-ring*ROAD_CELL_SIZE
			var right: float=(origin.x+ring+1)*ROAD_CELL_SIZE
			var top: float=origin.y*ROAD_CELL_SIZE-ring*ROAD_CELL_SIZE
			var bottom: float=(origin.y+ring+1)*ROAD_CELL_SIZE
			var boundary_distance:=minf(minf(point.x-left,right-point.x),minf(point.y-top,bottom-point.y))
			if boundary_distance*boundary_distance>distance: break
	return best

static func _ensure_road_index() -> void:
	if road_index_road_count!=roads.size(): _rebuild_road_index()

static func _rebuild_road_index() -> void:
	road_segment_cells.clear(); road_segments.clear()
	for edge_index in range(roads.size()):
		var points: PackedVector2Array=roads[edge_index].points
		for segment in range(1,points.size()):
			var segment_id:=road_segments.size()
			road_segments.append(Vector2i(edge_index,segment))
			var first:=Vector2i((Vector2(minf(points[segment-1].x,points[segment].x),minf(points[segment-1].y,points[segment].y))/ROAD_CELL_SIZE).floor())
			var last:=Vector2i((Vector2(maxf(points[segment-1].x,points[segment].x),maxf(points[segment-1].y,points[segment].y))/ROAD_CELL_SIZE).floor())
			for x in range(first.x,last.x+1):
				for y in range(first.y,last.y+1):
					var cell:=Vector2i(x,y)
					if not road_segment_cells.has(cell): road_segment_cells[cell]=[]
					road_segment_cells[cell].append(segment_id)
	road_index_road_count=roads.size(); road_index_segment_count=road_segments.size()

static func nearby_road_segments(point: Vector2, radius: float) -> Array[Vector2i]:
	_ensure_road_index()
	var result: Array[Vector2i]=[]
	var seen: Dictionary={}
	var first:=Vector2i(((point-Vector2.ONE*radius)/ROAD_CELL_SIZE).floor())
	var last:=Vector2i(((point+Vector2.ONE*radius)/ROAD_CELL_SIZE).floor())
	for x in range(first.x,last.x+1):
		for y in range(first.y,last.y+1):
			for segment_id in road_segment_cells.get(Vector2i(x,y),[]):
				if seen.has(segment_id): continue
				seen[segment_id]=true; result.append(road_segments[segment_id])
	return result

static func nearest_lane_point(point: Vector2) -> Vector2:
	return nearest_edge(point)["point"]

static func route(start: Vector2, destination: Vector2, start_height: float = 0) -> PackedVector2Array:
	var first := nearest_edge(start,true,start_height)
	var last := nearest_edge(destination)
	var best := PackedVector2Array()
	var shortest := INF
	if first["edge"] == last["edge"] and graph.are_points_connected(first["edge"]["from"],first["edge"]["to"]):
		best = PackedVector2Array([start])
		best.append_array(_between(first,last))
		best.append(destination)
		return _simplify(best)
	for a in [first["edge"]["from"], first["edge"]["to"]]:
		for b in [last["edge"]["from"], last["edge"]["to"]]:
			var path := PackedVector2Array([start])
			var head:=_toward_node(first,a)
			if _entry_blocked(head,first.edge): continue
			path.append_array(head)
			var ids := graph.get_id_path(a,b)
			if ids.is_empty(): continue
			for i in range(1,ids.size()):
				path.append_array(_edge_path(ids[i-1],ids[i]))
			var tail := _toward_node(last,b)
			if _entry_blocked(tail,last.edge): continue
			tail.reverse()
			path.append_array(tail)
			path.append(destination)
			var distance := 0.0
			for i in range(1,path.size()): distance += path[i-1].distance_to(path[i])
			if distance < shortest:
				shortest = distance
				best = path
	return _simplify(best)

static func _edge_path(a: int, b: int) -> PackedVector2Array:
	if edge_lookup.has(Vector2i(a,b)): return edge_lookup[Vector2i(a,b)]
	if edge_lookup.has(Vector2i(b,a)):
		var reverse: PackedVector2Array = edge_lookup[Vector2i(b,a)].duplicate()
		reverse.reverse()
		return reverse
	return PackedVector2Array()

static func _toward_node(entry: Dictionary, id: int) -> PackedVector2Array:
	var result := PackedVector2Array([entry["point"]])
	var points: PackedVector2Array = entry["edge"]["points"]
	if id == entry["edge"]["from"]:
		for i in range(int(entry["segment"]),-1,-1): result.append(points[i])
	else:
		for i in range(int(entry["segment"])+1,points.size()): result.append(points[i])
	return result

static func _between(first: Dictionary, last: Dictionary) -> PackedVector2Array:
	var points: PackedVector2Array = first["edge"]["points"]
	var reverse: bool = first["segment"] > last["segment"] or (first["segment"] == last["segment"] and first["point"].distance_to(points[first["segment"]]) > last["point"].distance_to(points[last["segment"]]))
	if reverse:
		var result := _between(last,first)
		result.reverse()
		return result
	var result := PackedVector2Array([first["point"]])
	for i in range(int(first["segment"])+1,int(last["segment"])+1): result.append(points[i])
	result.append(last["point"])
	return result

static func _simplify(path: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in path:
		if result.is_empty() or not point.is_equal_approx(result[-1]): result.append(point)
	return result

static func spawn_slots() -> Array[Vector2]:
	ensure()
	var result: Array[Vector2] = []
	for edge in roads:
		if edge["trail"] or edge.get("elevated",false) or edge.get("ramp",false): continue
		var points: PackedVector2Array = edge["points"]
		for i in range(1,points.size()-1,2):
			var direction := (points[i+1]-points[i-1]).normalized()
			var normal := Vector2(-direction.y,direction.x)
			for side in [-1,1]:
				var point: Vector2 = points[i]+normal*side*(float(edge.width)*.5+float(edge.sidewalk)*.55)
				if clear_point(point,15): result.append(point)
	return result

static func clear_point(point: Vector2, clearance: float = 8.0) -> bool:
	if not Rect2(Vector2.ONE*12,MAP_SIZE-Vector2.ONE*24).has_point(point): return false
	for rect in obstacles_near(Rect2(point-Vector2.ONE*clearance,Vector2.ONE*clearance*2),true)+closures.values():
		if rect.grow(clearance).has_point(point): return false
	return true

static func clear_segment(a: Vector2, b: Vector2, include_closures: bool = true) -> bool:
	var segment_bounds:=Rect2(a,Vector2.ZERO).expand(b).grow(.001)
	_ensure_obstacle_index()
	var search_bounds:=segment_bounds.grow(9)
	var first:=Vector2i((search_bounds.position/OBSTACLE_CELL_SIZE).floor())
	var last:=Vector2i((search_bounds.end/OBSTACLE_CELL_SIZE).floor())
	var queried_cells: int=(last.x-first.x+1)*(last.y-first.y+1)
	var candidates: Array[Rect2]=obstacle_records if queried_cells>maxi(16,obstacle_records.size()*2) else obstacles_near(search_bounds,true)
	for original in candidates+(closures.values() if include_closures else []):
		var rect: Rect2 = original.grow(9)
		if not segment_bounds.intersects(rect): continue
		# A temporary barrier erected around a person must permit stepping out.
		if original in closures.values() and rect.has_point(a) and b.distance_to(rect.get_center())>a.distance_to(rect.get_center()): continue
		if rect.has_point(a) or rect.has_point(b): return false
		var corners := [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
		for i in range(4):
			if Geometry2D.segment_intersects_segment(a,b,corners[i],corners[(i+1)%4]) != null: return false
	return true

static func _ensure_obstacle_index() -> void:
	if obstacle_index_count != lots.size()+rock_obstacles.size()+1:
		_rebuild_obstacle_index()

static func _rebuild_obstacle_index() -> void:
	obstacle_cells.clear(); obstacle_records.clear()
	obstacle_records.append_array(lots)
	obstacle_records.append_array(rock_obstacles)
	obstacle_records.append(lake)
	for index in range(obstacle_records.size()):
		var rect: Rect2=obstacle_records[index]
		if rect.size.x<=0 or rect.size.y<=0: continue
		var first:=Vector2i((rect.position/OBSTACLE_CELL_SIZE).floor())
		var last:=Vector2i(((rect.end-Vector2.ONE*.001)/OBSTACLE_CELL_SIZE).floor())
		for x in range(first.x,last.x+1):
			for y in range(first.y,last.y+1):
				var cell:=Vector2i(x,y)
				if not obstacle_cells.has(cell): obstacle_cells[cell]=[]
				obstacle_cells[cell].append(index)
	obstacle_index_count=lots.size()+rock_obstacles.size()+1

static func obstacles_near(bounds: Rect2, include_lake: bool = false) -> Array[Rect2]:
	_ensure_obstacle_index()
	var result: Array[Rect2]=[]
	var seen: Dictionary={}
	var first:=Vector2i((bounds.position/OBSTACLE_CELL_SIZE).floor())
	var last:=Vector2i((bounds.end/OBSTACLE_CELL_SIZE).floor())
	for x in range(first.x,last.x+1):
		for y in range(first.y,last.y+1):
			for index in obstacle_cells.get(Vector2i(x,y),[]):
				if seen.has(index): continue
				seen[index]=true
				if not include_lake and index==obstacle_records.size()-1: continue
				result.append(obstacle_records[index])
	return result

static func static_obstacles_near(bounds: Rect2) -> Array[Rect2]:
	return obstacles_near(bounds,false)

static func free_route(start: Vector2, destination: Vector2) -> PackedVector2Array:
	ensure()
	if not Rect2(Vector2.ZERO,MAP_SIZE).has_point(start) or not Rect2(Vector2.ZERO,MAP_SIZE).has_point(destination): return PackedVector2Array()
	if clear_segment(start,destination): return _simplify(PackedVector2Array([start,destination]))
	var first := _free_cell(start)
	var last := _free_cell(destination)
	if first.x < 0 or last.x < 0: return PackedVector2Array()
	if free_path_cache_revision!=navigation_revision:
		free_path_cache.clear(); free_path_cache_order.clear(); free_path_cache_revision=navigation_revision
	var key: String="%d:%d>%d:%d"%[first.x,first.y,last.x,last.y]
	var grid_path: PackedVector2Array
	if free_path_cache.has(key): grid_path=free_path_cache[key]
	else:
		grid_path=free_grid.get_point_path(first,last)
		if free_path_cache.size()>=FREE_PATH_CACHE_LIMIT:
			free_path_cache.erase(free_path_cache_order.pop_front())
		free_path_cache[key]=grid_path; free_path_cache_order.append(key)
	if grid_path.is_empty(): return PackedVector2Array()
	var points := PackedVector2Array([start])
	points.append_array(grid_path)
	points.append(destination)
	var result := PackedVector2Array([start])
	var cursor := 0
	while cursor < points.size()-1:
		var next := points.size()-1
		# Coarse-to-fine line-of-sight checks avoid testing every intermediate cell
		# on long evacuation routes. The chosen segment is still validated below.
		while next > cursor+4 and not clear_segment(points[cursor],points[next]): next -= 4
		while next > cursor+1 and not clear_segment(points[cursor],points[next]): next -= 1
		if not clear_segment(points[cursor],points[next]):
			# An invalid approach never becomes a route through an obstacle.
			return PackedVector2Array()
		result.append(points[next])
		cursor = next
	return _simplify(result)

static func _free_cell(point: Vector2) -> Vector2i:
	var cell := Vector2i((point/FREE_CELL).floor())
	if free_grid.is_in_boundsv(cell) and not free_grid.is_point_solid(cell): return cell
	var search_radius:=4
	for bounds in closures.values():
		if bounds.grow(12).has_point(point): search_radius=maxi(search_radius,mini(64,int(ceil(maxf(bounds.size.x,bounds.size.y)/FREE_CELL))+2))
	for radius in range(1,search_radius+1):
		for x in range(-radius,radius+1):
			for y in range(-radius,radius+1):
				var candidate := cell+Vector2i(x,y)
				if free_grid.is_in_boundsv(candidate) and not free_grid.is_point_solid(candidate) and clear_segment(point,free_grid.get_point_position(candidate)): return candidate
	return Vector2i(-1,-1)

func _draw() -> void:
	ensure()
	draw_rect(Rect2(Vector2.ZERO,MAP_SIZE),Color("849987"))
	draw_rect(park,Color("547c53"))
	draw_rect(green_zone,Color("3e6746"))
	for edge in roads:
		draw_polyline(edge["points"],Color("baa780") if edge["trail"] else Color("485463"),12 if edge["trail"] else 36)
	for rect in lots: draw_rect(rect,Color("a29889"))

static func set_closure(id: String, point: Vector2, active: bool, radius: float = 42.0) -> void:
	navigation_revision+=1
	var bounds: Rect2=Rect2(point-Vector2.ONE*radius,Vector2.ONE*radius*2) if active else closures.get(id,Rect2(point-Vector2.ONE*radius,Vector2.ONE*radius*2))
	if active: closures[id]=bounds
	else: closures.erase(id)
	var first := Vector2i((bounds.position/FREE_CELL).floor())-Vector2i.ONE
	var last := Vector2i((bounds.end/FREE_CELL).ceil())+Vector2i.ONE
	for x in range(maxi(0,first.x),mini(free_grid.region.end.x,last.x+1)):
		for y in range(maxi(0,first.y),mini(free_grid.region.end.y,last.y+1)):
			free_grid.set_point_solid(Vector2i(x,y),not clear_point(Vector2(x,y)*FREE_CELL+Vector2.ONE*FREE_CELL*.5,12))

static func _store_cost(a: int, b: int, points: PackedVector2Array) -> void:
	var distance:=0.0
	for i in range(1,points.size()): distance+=points[i-1].distance_to(points[i])
	graph.costs[Vector2i(a,b)]=distance; graph.costs[Vector2i(b,a)]=distance

static func route_height(point: Vector2, tangent: Vector2, previous: float) -> float:
	var best:=INF
	var height:=previous
	for segment in nearby_road_segments(point,10):
		var edge: Dictionary=roads[segment.x]
		var i: int=segment.y
		var points: PackedVector2Array=edge.points
		var projected:=Geometry2D.get_closest_point_to_segment(point,points[i-1],points[i])
		var d: float=point.distance_squared_to(projected)
		if d>100: continue
		var value: float=10 if edge.get("elevated",false) else 0
		if edge.get("ramp",false): value=10*(1-(float(i-1)+points[i-1].distance_to(projected)/maxf(.001,points[i-1].distance_to(points[i])))/(points.size()-1))
		var alignment: float=absf(tangent.dot((points[i]-points[i-1]).normalized()))
		var score: float=d+absf(value-previous)*.1+(1-alignment)*.1
		if score<best: best=score; height=value
	return height

static func _entry_blocked(path: PackedVector2Array, edge: Dictionary) -> bool:
	if graph.are_points_connected(edge.from,edge.to): return false
	for record in roadblock_data.values():
		if record.edge!=roads.find(edge): continue
		for i in range(1,path.size()):
			if Geometry2D.get_closest_point_to_segment(record.position,path[i-1],path[i]).distance_to(record.position)<35:
				if path[i-1].distance_to(record.position)<45 and path[i].distance_to(record.position)>path[i-1].distance_to(record.position): continue
				return true
	return false

# Buildings/props must remain outside EVERY carriageway, including junctions and decks.
static func roadway_clear(point: Vector2, radius: float = 0.0) -> bool:
	for edge in roads:
		for i in range(1,edge.points.size()):
			if Geometry2D.get_closest_point_to_segment(point,edge.points[i-1],edge.points[i]).distance_to(point)<float(edge.width)*.5+radius: return false
		if not edge.get("elevated",false) and not edge.get("ramp",false):
			for node in [edge.from,edge.to]:
				if graph.get_point_connections(node).size()>2 and graph.get_point_position(node).distance_to(point)<float(edge.width)*.5+5+radius: return false
	if Geometry2D.is_point_in_polygon(point,grove.bulb): return false
	for i in range(grove.bulb.size()):
		if Geometry2D.get_closest_point_to_segment(point,grove.bulb[i],grove.bulb[(i+1)%grove.bulb.size()]).distance_to(point)<radius: return false
	return true

static func roadside_position(near: Vector2, radius: float = 6.0) -> Vector2:
	var nearest: Dictionary=nearest_edge(near)
	var edge: Dictionary=nearest.edge
	var tangent: Vector2=(edge.points[nearest.segment+1]-edge.points[nearest.segment]).normalized()
	for along in [0.0,45.0,-45.0,100.0,-100.0,180.0,-180.0]:
		for side in [1.0,-1.0]:
			for margin in [12.0,24.0,36.0]:
				var point: Vector2=nearest.point+tangent*along+tangent.orthogonal()*side*(float(edge.width)*.5+radius+margin)
				if not Rect2(Vector2.ONE*20,MAP_SIZE-Vector2.ONE*40).has_point(point) or not roadway_clear(point,radius) or not clear_point(point,radius): continue
				if parking_lots.any(func(lot):return lot.bounds.grow(radius).has_point(point)): continue
				return point
	return Vector2.INF
