extends RefCounted
## Routes are planned only at decision time, using the existing orthogonal roads.

const CityMap = preload("res://scripts/city_map.gd")


static func intersection(point: Vector2) -> Vector2:
	return (point / CityMap.ROAD_SPACING).round() * CityMap.ROAD_SPACING


static func plan(start: Vector2, destination: Vector2) -> PackedVector2Array:
	var start_junction := intersection(start)
	var end_junction := intersection(destination)
	var candidates := [start, Vector2(start_junction.x, start.y), start_junction,
		Vector2(end_junction.x, start_junction.y), end_junction,
		Vector2(destination.x, end_junction.y), destination]
	var route := PackedVector2Array()
	for point in candidates:
		if route.is_empty() or not route[-1].is_equal_approx(point):
			route.append(point)
	return route


static func length(route: PackedVector2Array) -> float:
	var distance := 0.0
	for index in range(1, route.size()):
		distance += route[index - 1].distance_to(route[index])
	return distance


static func remaining_distance(agent: Dictionary) -> float:
	var route: PackedVector2Array = agent["route"]
	var index: int = agent["route_index"]
	if index >= route.size():
		return 0
	var distance: float = agent["position"].distance_to(route[index])
	for next_index in range(index + 1, route.size()):
		distance += route[next_index - 1].distance_to(route[next_index])
	return distance


static func move(agent: Dictionary, seconds: float) -> Dictionary:
	# Spend the time budget across waypoints; never snap past the allowed distance.
	var budget: float = agent["movement_speed"] * seconds
	var initial_budget := budget
	var route: PackedVector2Array = agent["route"]
	var index: int = agent["route_index"]
	while index < route.size():
		var location: Vector2 = agent["position"]
		var distance := location.distance_to(route[index])
		if distance > budget + 0.00001:
			agent["position"] = location.move_toward(route[index], budget)
			budget = 0
			break
		agent["position"] = route[index]
		budget = maxf(0, budget - distance)
		index += 1
	agent["route_index"] = index
	return {"arrived": index >= route.size(), "travel_seconds": (initial_budget - budget) / agent["movement_speed"]}
