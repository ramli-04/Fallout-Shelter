extends AStar2D
## Physical spline lengths are the edge costs; closures disconnect actual edges.
var costs := {}
func _compute_cost(from_id: int, to_id: int) -> float:
	return float(costs.get(Vector2i(from_id,to_id),get_point_position(from_id).distance_to(get_point_position(to_id))))
