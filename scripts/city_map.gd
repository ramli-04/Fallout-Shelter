extends Node2D
## Seeded shared geography. Simulation, rendering, spawns and routes use this source.
static var MAP_SIZE := Vector2(4500, 2700)
const ROAD_SPACING := 180 # Legacy unit used by incident radii and historical fixtures.
static var map_seed := 42
static var x_cuts: Array[float] = []
static var y_cuts: Array[float] = []
static var roads: Array[Dictionary] = []
static var edge_lookup := {}
static var lots: Array[Rect2] = []
static var sites := {}
static var park := Rect2()
static var green_zone := Rect2()
static var lake := Rect2()
static var hill := Vector2.ZERO
static var noise: FastNoiseLite
static var graph: AStar2D
static var pois: Array[Dictionary] = []

static func generate(seed_value: int) -> void:
	map_seed = seed_value
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 41031
	noise = FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.0018
	noise.fractal_octaves = 3
	green_zone = Rect2(Vector2(MAP_SIZE.x*0.5, 0), MAP_SIZE*0.5)
	park = Rect2(MAP_SIZE*Vector2(0.29,0.25), MAP_SIZE*Vector2(0.25,0.50))
	hill = MAP_SIZE*Vector2(rng.randf_range(0.75,0.84), rng.randf_range(0.19,0.28))
	x_cuts = _cuts(MAP_SIZE.x, rng, [park.position.x, park.end.x, park.get_center().x, green_zone.position.x, hill.x])
	y_cuts = _cuts(MAP_SIZE.y, rng, [park.position.y, park.end.y, park.get_center().y, green_zone.end.y, hill.y])
	hill = _nearest_junction(hill)
	# The reservoir sits inside a park block, away from all walking routes.
	var px := x_cuts.find(park.position.x)
	var py := y_cuts.find(park.position.y)
	lake = Rect2(Vector2(x_cuts[px]+65,y_cuts[py]+65), Vector2(maxf(80,x_cuts[px+1]-x_cuts[px]-130),maxf(80,y_cuts[py+1]-y_cuts[py]-130)))
	sites = {"S1": park.get_center(), "S5": hill}
	sites["S2"] = _nearest_junction(MAP_SIZE*Vector2(0.19,0.38))
	sites["S3"] = _nearest_junction(MAP_SIZE*Vector2(0.66,0.78))
	sites["S4"] = _nearest_junction(MAP_SIZE*Vector2(0.12,0.83))
	graph = AStar2D.new()
	roads.clear()
	edge_lookup.clear()
	for x in range(x_cuts.size()):
		for y in range(y_cuts.size()):
			graph.add_point(x*y_cuts.size()+y, Vector2(x_cuts[x],y_cuts[y]))
	for x in range(x_cuts.size()):
		for y in range(y_cuts.size()):
			var id := x*y_cuts.size()+y
			if x+1 < x_cuts.size(): _connect(id, (x+1)*y_cuts.size()+y)
			if y+1 < y_cuts.size(): _connect(id, id+1)
	lots.clear()
	for x in range(x_cuts.size()-1):
		for y in range(y_cuts.size()-1):
			var block := Rect2(Vector2(x_cuts[x]+52,y_cuts[y]+52),Vector2(x_cuts[x+1]-x_cuts[x]-104,y_cuts[y+1]-y_cuts[y]-104))
			if block.size.x < 110 or block.size.y < 110 or park.intersects(block) or green_zone.intersects(block): continue
			var divisions := 2 if block.size.x > 370 and rng.randf() < 0.7 else 1
			for part in range(divisions):
				var available := Rect2(block.position+Vector2(part*block.size.x/divisions,0),Vector2(block.size.x/divisions-14,block.size.y))
				var size := available.size*Vector2(rng.randf_range(0.72,0.98),rng.randf_range(0.65,0.98))
				var rect := Rect2(available.position+Vector2(rng.randf_range(0,available.size.x-size.x),rng.randf_range(0,available.size.y-size.y)),size)
				var clear := true
				for site in sites.values():
					if rect.grow(95).has_point(site): clear = false
				if clear: lots.append(rect)
	pois.clear()
	var kinds := ["Police Station", "Fire Station", "Medical Station", "Bank", "School"]
	for i in range(mini(kinds.size(), lots.size())):
		var rect: Rect2 = lots[int(float(i+1)*lots.size()/(kinds.size()+1))]
		pois.append({"id":"POI%d" % i,"kind":kinds[i],"position":nearest_lane_point(rect.get_center()),"footprint":rect,"roof_position":rect.position+rect.size*0.12})

static func _cuts(extent: float, rng: RandomNumberGenerator, anchors: Array) -> Array[float]:
	var result: Array[float] = [0.0,extent]
	for anchor in anchors:
		var separated := true
		for value in result:
			if absf(value-float(anchor)) < 100: separated = false
		if separated: result.append(float(anchor))
	var point := rng.randf_range(350,500)
	while point < extent-200:
		var clear := true
		for value in result:
			if absf(value-point) < 230: clear = false
		if clear: result.append(point)
		point += rng.randf_range(370,600)
	result.sort()
	return result

static func _nearest_junction(point: Vector2) -> Vector2:
	var result := Vector2.ZERO
	var distance := INF
	for x in x_cuts:
		for y in y_cuts:
			var candidate := Vector2(x,y)
			if candidate.distance_squared_to(point) < distance:
				result = candidate
				distance = candidate.distance_squared_to(point)
	return result

static func _connect(a: int, b: int) -> void:
	graph.connect_points(a,b)
	var start := graph.get_point_position(a)
	var finish := graph.get_point_position(b)
	var middle := (start+finish)*0.5
	var trail := park.grow(-2).has_point(middle) or green_zone.grow(-2).has_point(middle)
	var points := PackedVector2Array()
	var segments := maxi(1,int(start.distance_to(finish)/25)) if trail else 1
	var ix := x_cuts.find(start.x)
	var iy := y_cuts.find(start.y)
	var vertical := is_equal_approx(start.x,finish.x)
	var sign_value := 1.0 if (ix+iy+map_seed)%2 == 0 else -1.0
	for i in range(segments+1):
		var t := float(i)/segments
		var point := start.lerp(finish,t)
		if trail:
			point += (Vector2.RIGHT if vertical else Vector2.DOWN)*sin(t*PI)*32*sign_value
		points.append(point)
	roads.append({"a":start,"b":finish,"from":a,"to":b,"trail":trail,"points":points})
	edge_lookup[Vector2i(a,b)] = points

static func ensure() -> void:
	if graph == null: generate(map_seed)

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

static func elevation(point: Vector2) -> float:
	if noise == null: return 0.0
	var normalized := point/MAP_SIZE
	var hills := 32.0*exp(-pow((point.x-hill.x)/(MAP_SIZE.x*0.14),2)-pow((point.y-hill.y)/(MAP_SIZE.y*0.22),2))
	var western_ridge := 9.0*exp(-pow((normalized.x-0.10)/0.13,2)-pow((normalized.y-0.80)/0.24,2))
	var rolling := noise.get_noise_2d(point.x,point.y)*1.8 + sin(normalized.y*PI*3.0)*0.8
	var height := rolling + hills + western_ridge
	if lake.size.x > 0:
		var relative := (point-lake.get_center())/(lake.size*0.5)
		var blend := 1.0-smoothstep(0.8,1.35,relative.length())
		height = lerpf(height,-1.4,blend)
	return height

static func nearest_edge(point: Vector2) -> Dictionary:
	ensure()
	var best := {}
	var distance := INF
	for edge in roads:
		var points: PackedVector2Array = edge["points"]
		for i in range(1,points.size()):
			var projected := Geometry2D.get_closest_point_to_segment(point,points[i-1],points[i])
			var delta := point.distance_squared_to(projected)
			if delta < distance:
				distance = delta
				best = {"point":projected,"edge":edge,"segment":i-1}
	return best

static func nearest_lane_point(point: Vector2) -> Vector2:
	return nearest_edge(point)["point"]

static func route(start: Vector2, destination: Vector2) -> PackedVector2Array:
	var first := nearest_edge(start)
	var last := nearest_edge(destination)
	var best := PackedVector2Array()
	var shortest := INF
	if first["edge"] == last["edge"]:
		best = PackedVector2Array([start])
		best.append_array(_between(first,last))
		best.append(destination)
		return _simplify(best)
	for a in [first["edge"]["from"], first["edge"]["to"]]:
		for b in [last["edge"]["from"], last["edge"]["to"]]:
			var path := PackedVector2Array([start])
			path.append_array(_toward_node(first,a))
			var ids := graph.get_id_path(a,b)
			for i in range(1,ids.size()):
				path.append_array(_edge_path(ids[i-1],ids[i]))
			var tail := _toward_node(last,b)
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
		if edge["trail"]: continue
		var direction: Vector2 = (edge["b"]-edge["a"]).normalized()
		var normal := Vector2(-direction.y,direction.x)
		var steps := int(edge["a"].distance_to(edge["b"])/45)
		for step in range(1,steps):
			for side in [-1,1]:
				var point: Vector2 = edge["a"]+direction*step*45+normal*side*26
				if Rect2(Vector2(30,30),MAP_SIZE-Vector2(60,60)).has_point(point): result.append(point)
	return result

func _draw() -> void:
	ensure()
	draw_rect(Rect2(Vector2.ZERO,MAP_SIZE),Color("849987"))
	draw_rect(park,Color("547c53"))
	draw_rect(green_zone,Color("3e6746"))
	for edge in roads:
		draw_polyline(edge["points"],Color("baa780") if edge["trail"] else Color("485463"),12 if edge["trail"] else 36)
	for rect in lots: draw_rect(rect,Color("a29889"))
