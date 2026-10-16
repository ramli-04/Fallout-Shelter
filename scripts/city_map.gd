extends Node2D
## Seeded shared geography. Simulation, rendering, spawns and routes use this source.
static var MAP_SIZE := Vector2(6750, 4050)
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
static var free_grid: AStarGrid2D
const FREE_CELL := 30.0
static var lot_angles: Array[float] = []
static var lot_districts: Array[String] = []
static var rock_obstacles: Array[Rect2] = []
static var highways: Array[PackedVector2Array] = []

static func generate(seed_value: int) -> void:
	map_seed = seed_value
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 41031
	noise = FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.0018
	noise.fractal_octaves = 3
	green_zone = Rect2(MAP_SIZE*Vector2(0.50,0),MAP_SIZE*0.5)
	park = Rect2(MAP_SIZE*Vector2(0.13,0.55),MAP_SIZE*Vector2(0.17,0.25))
	hill = MAP_SIZE*Vector2(0.86,0.13)
	lake = Rect2(MAP_SIZE*Vector2(0.15,0.59),MAP_SIZE*Vector2(0.045,0.055))
	sites = {"S1":park.get_center(),"S2":MAP_SIZE*Vector2(0.48,0.78),"S3":MAP_SIZE*Vector2(0.80,0.70),"S4":MAP_SIZE*Vector2(0.90,0.33),"S5":hill}
	graph = AStar2D.new()
	roads.clear()
	edge_lookup.clear()
	# Warped, staggered junctions; each edge is a sampled spline, not a painted grid.
	x_cuts = [0.0,MAP_SIZE.x]
	y_cuts = [0.0,MAP_SIZE.y]
	var columns := 10
	var rows := 6
	for x in range(columns):
		for y in range(rows):
			var uv := Vector2(0.06+x*0.091,0.19+y*0.145)
			uv += Vector2(rng.randf_range(-0.023,0.023),rng.randf_range(-0.035,0.035))
			uv.x += sin(y*1.3)*0.024
			graph.add_point(x*rows+y,uv*MAP_SIZE)
	for x in range(columns):
		for y in range(rows):
			var id := x*rows+y
			if x+1 < columns: _organic_connect(id,(x+1)*rows+y,rng)
			if y+1 < rows and (x+y)%4 != 1: _organic_connect(id,id+1,rng)
			if x+1 < columns and y+1 < rows and (x+y)%4 == 0: _organic_connect(id,(x+1)*rows+y+1,rng)
	# Shelter approaches join the same network, including remote winding roads.
	for key in sites:
		var point: Vector2 = sites[key]
		var near := graph.get_closest_point(point)
		var id := graph.get_available_point_id()
		graph.add_point(id,point)
		_organic_connect(near,id,rng)
	rock_obstacles.clear()
	for key in ["S4","S5"]:
		for side in [-1,1]:
			rock_obstacles.append(Rect2(sites[key]+Vector2(10 if side > 0 else -175,20),Vector2(165,220)))
	highways.clear()
	var highway := PackedVector2Array()
	for i in range(101):
		var t := float(i)/100
		highway.append(Vector2(lerpf(-0.12,1.14,t),0.19+sin(t*TAU+0.4)*0.055)*MAP_SIZE)
	highways.append(highway)
	lots.clear()
	lot_angles.clear()
	lot_districts.clear()
	for edge in roads:
		if edge["trail"]: continue
		var points: PackedVector2Array = edge["points"]
		for i in range(2,points.size()-2,2):
			var tangent := (points[i+1]-points[i-1]).normalized()
			var normal := Vector2(-tangent.y,tangent.x)
			for side in [-1,1]:
				var center: Vector2 = points[i]+normal*side*rng.randf_range(125,165)
				if not Rect2(MAP_SIZE*0.03,MAP_SIZE*0.94).has_point(center): continue
				if park.grow(30).has_point(center) or green_zone.has_point(center): continue
				var district := district_at(center)
				var size := rng.randf_range(95,165) if district == "RESIDENTIAL" else rng.randf_range(150,225)
				var rect := Rect2(center-Vector2.ONE*size*0.5,Vector2.ONE*size)
				var clear := not lake.grow(30).intersects(rect) and not park.intersects(rect) and not green_zone.intersects(rect)
				for site in sites.values():
					if rect.grow(125).has_point(site): clear = false
				for other in lots:
					if rect.grow(18).intersects(other): clear = false
				for road in roads:
					for point in road["points"]:
						if rect.grow(45).has_point(point): clear = false
				if clear:
					lots.append(rect)
					lot_angles.append(-tangent.angle()+(PI if side == 1 else 0.0))
					lot_districts.append(district)
	pois.clear()
	var kinds := ["Bank","Police Station","Medical Station","Fire Station","School"]
	var targets := [Vector2(0.45,0.45),Vector2(0.55,0.51),Vector2(0.64,0.58),Vector2(0.65,0.64),Vector2(0.73,0.78)]
	var used := []
	for i in range(kinds.size()):
		var best := -1
		var distance := INF
		for j in range(lots.size()):
			var d := lots[j].get_center().distance_squared_to(targets[i]*MAP_SIZE)
			if j not in used and d < distance:
				distance = d
				best = j
		if best >= 0:
			used.append(best)
			var rect: Rect2 = lots[best]
			pois.append({"id":"POI%d"%i,"kind":kinds[i],"position":nearest_lane_point(rect.get_center()),"footprint":rect,"roof_position":rect.get_center()})
	free_grid = AStarGrid2D.new()
	free_grid.region = Rect2i(0,0,ceili(MAP_SIZE.x/FREE_CELL),ceili(MAP_SIZE.y/FREE_CELL))
	free_grid.cell_size = Vector2.ONE*FREE_CELL
	free_grid.offset = Vector2.ONE*FREE_CELL*0.5
	free_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	free_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	free_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	free_grid.update()
	for rect in lots+[lake]+rock_obstacles:
		var bounds: Rect2 = rect.grow(12)
		var first := Vector2i((bounds.position/FREE_CELL).floor())
		var last := Vector2i((bounds.end/FREE_CELL).ceil())
		for x in range(maxi(0,first.x),mini(free_grid.region.end.x,last.x+1)):
			for y in range(maxi(0,first.y),mini(free_grid.region.end.y,last.y+1)):
				if bounds.has_point(Vector2(x,y)*FREE_CELL+Vector2.ONE*FREE_CELL*0.5): free_grid.set_point_solid(Vector2i(x,y))

static func district_at(point: Vector2) -> String:
	var uv := point/MAP_SIZE
	if uv.x < 0.25 and uv.y < 0.52: return "INDUSTRIAL"
	if uv.x > 0.52 and uv.y < 0.5: return "MOUNTAINS"
	if uv.distance_to(Vector2(0.46,0.48)) < 0.22: return "CENTER"
	if uv.x > 0.55 and uv.y < 0.73: return "SERVICES"
	return "RESIDENTIAL"

static func _organic_connect(a: int, b: int, rng: RandomNumberGenerator) -> void:
	graph.connect_points(a,b)
	var start := graph.get_point_position(a)
	var finish := graph.get_point_position(b)
	var delta := finish-start
	var normal := Vector2(-delta.y,delta.x).normalized()
	var bend := rng.randf_range(-0.19,0.19)*delta.length()
	var points := PackedVector2Array()
	for i in range(maxi(8,int(delta.length()/35))+1):
		var t := float(i)/maxi(8,int(delta.length()/35))
		points.append(start.lerp(finish,t)+normal*sin(t*PI)*bend)
	var trail := green_zone.has_point((start+finish)*0.5) or park.has_point((start+finish)*0.5)
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
	var uv := point/MAP_SIZE
	var ridges := 55.0*exp(-pow((uv.x-0.89)/0.16,2)-pow((uv.y-0.15)/0.30,2))
	var height := noise.get_noise_2d(point.x,point.y)*1.1+ridges
	if lake.size.x > 0:
		var relative := (point-lake.get_center())/(lake.size*0.5)
		height = lerpf(height,-1.4,1.0-smoothstep(0.8,1.35,relative.length()))
	# Foundation pads blend into natural terrain instead of leaving floating corners.
	for rect in lots:
		if rect.grow(32).has_point(point):
			var center := rect.get_center()
			var local_uv := center/MAP_SIZE
			var base := noise.get_noise_2d(center.x,center.y)*1.1+55.0*exp(-pow((local_uv.x-0.89)/0.16,2)-pow((local_uv.y-0.15)/0.30,2))
			var outside := maxf(maxf(rect.position.x-point.x,point.x-rect.end.x),maxf(rect.position.y-point.y,point.y-rect.end.y))
			height = lerpf(base,height,smoothstep(0,32,outside))
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
		var points: PackedVector2Array = edge["points"]
		for i in range(1,points.size()-1,2):
			var direction := (points[i+1]-points[i-1]).normalized()
			var normal := Vector2(-direction.y,direction.x)
			for side in [-1,1]:
				var point: Vector2 = points[i]+normal*side*29
				if clear_point(point,15): result.append(point)
	return result

static func clear_point(point: Vector2, clearance: float = 8.0) -> bool:
	if not Rect2(Vector2.ONE*12,MAP_SIZE-Vector2.ONE*24).has_point(point): return false
	if lake.grow(clearance).has_point(point): return false
	for rect in lots+rock_obstacles:
		if rect.grow(clearance).has_point(point): return false
	return true

static func clear_segment(a: Vector2, b: Vector2) -> bool:
	for original in lots+[lake]+rock_obstacles:
		var rect: Rect2 = original.grow(9)
		if rect.has_point(a) or rect.has_point(b): return false
		var corners := [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
		for i in range(4):
			if Geometry2D.segment_intersects_segment(a,b,corners[i],corners[(i+1)%4]) != null: return false
	return true

static func free_route(start: Vector2, destination: Vector2) -> PackedVector2Array:
	ensure()
	if not Rect2(Vector2.ZERO,MAP_SIZE).has_point(start) or not Rect2(Vector2.ZERO,MAP_SIZE).has_point(destination): return PackedVector2Array()
	if clear_segment(start,destination): return _simplify(PackedVector2Array([start,destination]))
	var first := _free_cell(start)
	var last := _free_cell(destination)
	if first.x < 0 or last.x < 0: return PackedVector2Array()
	var grid_path := free_grid.get_point_path(first,last)
	if grid_path.is_empty(): return PackedVector2Array()
	var points := PackedVector2Array([start])
	points.append_array(grid_path)
	points.append(destination)
	var result := PackedVector2Array([start])
	var cursor := 0
	while cursor < points.size()-1:
		var next := points.size()-1
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
	for radius in range(1,5):
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
