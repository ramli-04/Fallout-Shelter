extends RefCounted
## Directed routing snapshot. Never reconnects or changes the shared pedestrian graph.
const Map=preload("res://scripts/city_map.gd")
const Convention=preload("res://scripts/traffic_conventions.gd")

static func route(sim: RefCounted, start: Vector2, destination: Vector2, emergency: bool, height: float, knowledge: Dictionary) -> PackedVector2Array:
	var first: Dictionary=Map.nearest_edge(start,true,height)
	var last: Dictionary=Map.nearest_edge(destination,true,0)
	if first.is_empty() or last.is_empty(): return PackedVector2Array()
	var graph:=preload("res://scripts/road_graph.gd").new()
	for id in Map.graph.get_point_ids(): graph.add_point(id,Map.graph.get_point_position(id))
	var eligible: Dictionary={}
	for index in range(Map.roads.size()):
		var edge: Dictionary=Map.roads[index]
		if edge.get("trail",false) or edge.get("vehicle_access",true)==false: continue
		var blocked: bool=bool(edge.get("closed",false))
		for block in sim.blocks:
			if block.active and block.edge==index and block.kind!="emergency_lane" and not (emergency and block.kind in sim.EMERGENCY_PASS): blocked=true
		if blocked: continue
		eligible[index]=true
		var cost: float=Map._path_length(edge.points)
		if sim.manager.elapsed_seconds-float(knowledge.get(index,knowledge.get(str(index),-1000)))<30: cost*=2.5
		for forward in [true,false]:
			if not Convention.permitted(edge,forward): continue
			var a: int=edge.from if forward else edge.to
			var b: int=edge.to if forward else edge.from
			graph.connect_points(a,b,false); graph.costs[Vector2i(a,b)]=cost
	var first_index: int=Map.roads.find(first.edge)
	var last_index: int=Map.roads.find(last.edge)
	var best:=PackedVector2Array()
	var best_cost:=INF
	if first_index==last_index and eligible.has(first_index):
		var path: PackedVector2Array=Map._between(first,last)
		var forward: bool=int(first.segment)<int(last.segment) or (int(first.segment)==int(last.segment) and first.point.distance_to(first.edge.points[first.segment])<=last.point.distance_to(last.edge.points[last.segment]))
		if Convention.permitted(first.edge,forward) and connector_clear(sim,path,first.edge,emergency):
			best=PackedVector2Array([start]); best.append_array(path); best.append(destination)
			best_cost=Map._path_length(best)*traffic_factor(sim,knowledge,first_index)
	for a in [first.edge.from,first.edge.to]:
		if not Convention.permitted(first.edge,a==first.edge.to): continue
		for b in [last.edge.from,last.edge.to]:
			if not Convention.permitted(last.edge,b==last.edge.from): continue
			var ids: PackedInt64Array=graph.get_id_path(a,b)
			if ids.is_empty(): continue
			var head: PackedVector2Array=Map._toward_node(first,a)
			var tail: PackedVector2Array=Map._toward_node(last,b); tail.reverse()
			if not connector_clear(sim,head,first.edge,emergency) or not connector_clear(sim,tail,last.edge,emergency): continue
			var path:=PackedVector2Array([start]); path.append_array(head)
			var cost: float=start.distance_to(first.point)+Map._path_length(head)*traffic_factor(sim,knowledge,first_index)+Map._path_length(tail)*traffic_factor(sim,knowledge,last_index)+last.point.distance_to(destination)
			for i in range(1,ids.size()):
				path.append_array(Map._edge_path(ids[i-1],ids[i])); cost+=float(graph.costs[Vector2i(ids[i-1],ids[i])])
			path.append_array(tail); path.append(destination)
			if cost<best_cost: best_cost=cost; best=path
	return Map._simplify(best)

static func traffic_factor(sim: RefCounted, knowledge: Dictionary, index: int) -> float:
	return 2.5 if sim.manager.elapsed_seconds-float(knowledge.get(index,knowledge.get(str(index),-1000)))<30 else 1.0

static func connector_clear(sim: RefCounted, path: PackedVector2Array, edge: Dictionary, emergency: bool) -> bool:
	if edge.get("closed",false): return false
	for block in sim.blocks:
		if not block.active or Map.roads[block.edge]!=edge or block.kind=="emergency_lane" or (emergency and block.kind in sim.EMERGENCY_PASS): continue
		for i in range(1,path.size()):
			if Geometry2D.get_closest_point_to_segment(block.position,path[i-1],path[i]).distance_to(block.position)<35:
				if path[i-1].distance_to(block.position)<45 and path[i].distance_to(block.position)>path[i-1].distance_to(block.position): continue
				return false
	return true
