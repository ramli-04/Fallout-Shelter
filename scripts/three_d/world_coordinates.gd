extends RefCounted
## One explicit, reversible conversion. The simulation retains its planar units and speed.
const SCALE := 0.1
const FLOOR_Y := 0.18
const CITY_SIZE := Vector2(180, 108)

static func to_world(point: Vector2, height: float = FLOOR_Y) -> Vector3:
	return Vector3(point.x * SCALE, height, point.y * SCALE)

static func to_simulation(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z) / SCALE
