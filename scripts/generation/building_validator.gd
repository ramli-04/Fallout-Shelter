extends RefCounted
## Logical map validation before runtime scene/collision instantiation.
const CELL:=256.0
static func point(v) -> Vector2: return Vector2(v[0],v[1])
static func polygon(values) -> PackedVector2Array:
	var result:=PackedVector2Array()
	for v in values: result.append(point(v))
	return result
static func rectangle(values) -> PackedVector2Array:
	var p:=point(values); var s:=Vector2(values[2],values[3])
	# Integer envelope is useful for broad-phase grid queries; polygons are authoritative.
	var cells:=Rect2i(Vector2i(floor(p.x),floor(p.y)),Vector2i(ceil(s.x),ceil(s.y)))
	assert(cells.size.x>=0 and cells.size.y>=0)
	return PackedVector2Array([p,p+Vector2(s.x,0),p+s,p+Vector2(0,s.y)])
static func bounds(poly: PackedVector2Array) -> Rect2:
	var r:=Rect2(poly[0],Vector2.ZERO)
	for p in poly: r=r.expand(p)
	return r
static func keys(poly: PackedVector2Array) -> Array[Vector2i]:
	var r:=bounds(poly); var result: Array[Vector2i]=[]
	for x in range(floori(r.position.x/CELL),floori(r.end.x/CELL)+1):
		for y in range(floori(r.position.y/CELL),floori(r.end.y/CELL)+1): result.append(Vector2i(x,y))
	return result
static func insert(grid: Dictionary,poly: PackedVector2Array,index: int) -> void:
	for key in keys(poly):
		if not grid.has(key): grid[key]=[]
		grid[key].append(index)
static func query(grid: Dictionary,poly: PackedVector2Array) -> Dictionary:
	var result: Dictionary={}
	for key in keys(poly):
		for index in grid.get(key,[]): result[index]=true
	return result
static func overlaps(a: PackedVector2Array,b: PackedVector2Array) -> bool:
	for part in Geometry2D.intersect_polygons(a,b):
		var area:=0.0
		for i in range(part.size()): area+=part[i].cross(part[(i+1)%part.size()])
		if absf(area)>.1: return true
	return false
static func strip(a: Vector2,b: Vector2,width: float) -> PackedVector2Array:
	var n: Vector2=(b-a).normalized().orthogonal()*width
	return PackedVector2Array([a+n,b+n,b-n,a-n])
static func validate(data: Dictionary) -> Dictionary:
	var footprints: Array[PackedVector2Array]=[]; var grid: Dictionary={}
	var road_shapes: Array[PackedVector2Array]=[]; var road_grid: Dictionary={}
	var invalid: Dictionary={}; var inaccessible: Dictionary={}; var errors: Array[String]=[]
	var adjacency: Dictionary={}
	for road in data.roads:
		var a:=int(road.from); var b:=int(road.to)
		if not adjacency.has(a): adjacency[a]=[]
		if not adjacency.has(b): adjacency[b]=[]
		adjacency[a].append(b); adjacency[b].append(a)
		for j in range(1,road.points.size()):
			var shape:=strip(point(road.points[j-1]),point(road.points[j]),float(road.width)*.5+float(road.sidewalk))
			insert(road_grid,shape,road_shapes.size()); road_shapes.append(shape)
	for record in data.buildings:
		var poly:=rectangle(record.rect)
		insert(grid,poly,footprints.size()); footprints.append(poly)
	var overlap_count:=0; var service_count:=0
	for i in range(footprints.size()):
		var poly:=footprints[i]; var record: Dictionary=data.buildings[i]
		for j in query(grid,poly):
			if j>i and overlaps(poly,footprints[j]):
				overlap_count+=1; invalid[i]=true; invalid[j]=true
		for j in query(road_grid,poly):
			if overlaps(poly,road_shapes[j]): invalid[i]=true
		if record.has("parcel"):
			var parcel:=polygon(record.parcel)
			if not Geometry2D.clip_polygons(poly,parcel).is_empty(): invalid[i]=true
		if record.has("access_path"):
			var entry:=point(record.road_entry); var entry_valid:=false
			var probe:=PackedVector2Array([entry-Vector2.ONE,entry+Vector2(1,-1),entry+Vector2.ONE,entry+Vector2(-1,1)])
			for j in query(road_grid,probe):
				if Geometry2D.is_point_in_polygon(entry,road_shapes[j]): entry_valid=true
			if not entry_valid: inaccessible[i]=true
			var path=record.access_path
			for k in range(1,path.size()):
				var route:=strip(point(path[k-1]),point(path[k]),6)
				for j in query(grid,route):
					if j!=i and overlaps(route,footprints[j]): inaccessible[i]=true
		elif not record.has("driveway"):
			# Legacy layouts are accepted only if a nearby clear frontage exists.
			var center:=bounds(poly).get_center(); var nearest:=Vector2.INF; var distance:=INF
			for road in data.roads:
				if road.get("elevated",false) or road.get("ramp",false): continue
				for k in range(1,road.points.size()):
					var p:=Geometry2D.get_closest_point_to_segment(center,point(road.points[k-1]),point(road.points[k]))
					if center.distance_to(p)<distance: nearest=p; distance=center.distance_to(p)
			if distance>600: inaccessible[i]=true
			else:
				var route:=strip(center,nearest,6)
				for j in query(grid,route):
					if j!=i and overlaps(route,footprints[j]): inaccessible[i]=true
		if record.has("municipal_block"):
			service_count+=0 if record.get("asset_type","")=="motel" else 1
			var block:=polygon(record.municipal_block)
			for j in query(grid,block):
				if j!=i and overlaps(block,footprints[j]): invalid[j]=true
	var visited: Dictionary={}; var components:=0
	for start in range(data.nodes.size()):
		if visited.has(start): continue
		components+=1; var queue: Array=[start]
		while not queue.is_empty():
			var id=int(queue.pop_back())
			if visited.has(id): continue
			visited[id]=true
			queue.append_array(adjacency.get(id,[]))
	if not invalid.is_empty(): errors.append("Invalid building footprints: %d"%invalid.size())
	if not inaccessible.is_empty(): errors.append("Inaccessible entrances: %d"%inaccessible.size())
	if components!=1: errors.append("Disconnected road components: %d"%components)
	return {"valid":errors.is_empty(),"errors":errors,"buildings":footprints.size(),"overlapping_buildings":overlap_count,"inaccessible_entrances":inaccessible.size(),"road_components":components,"emergency_service_sites":service_count,"invalid_indices":invalid.keys(),"inaccessible_indices":inaccessible.keys()}
