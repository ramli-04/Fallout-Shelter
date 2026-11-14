extends RefCounted
## Map XY maps to world XZ. Eastbound right is +map Y, not Vector2.orthogonal().
static func right(forward: Vector2) -> Vector2:
	return Vector2(-forward.y,forward.x).normalized()

static func permitted(edge: Dictionary, forward: bool) -> bool:
	if edge.get("closed",false): return false
	var direction: String=str(edge.get("direction","forward" if edge.get("one_way",false) else "both"))
	return direction=="both" or (direction=="forward" and forward) or (direction=="reverse" and not forward)

static func signal_yaw(tangent: Vector2) -> float:
	# A head's local +Z lamp face looks back toward the approaching driver.
	return -tangent.angle()-PI*.5

static func edge_tangent(edge: Dictionary, point: Vector2) -> Vector2:
	var points: PackedVector2Array=edge.points
	var nearest:=INF
	var tangent:=Vector2.RIGHT
	for i in range(1,points.size()):
		var distance: float=Geometry2D.get_closest_point_to_segment(point,points[i-1],points[i]).distance_squared_to(point)
		if distance<nearest:
			nearest=distance; tangent=(points[i]-points[i-1]).normalized()
	return tangent
