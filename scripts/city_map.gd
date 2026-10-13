extends Node2D
## Static map geometry in world units. No simulation behavior lives in this file.

static var MAP_SIZE := Vector2(4500, 2700)
const ROAD_SPACING := 180
const PARK_CELLS := [Vector2i(4, 2), Vector2i(5, 2), Vector2i(2, 4)]


static func spawn_slots() -> Array[Vector2]:
	# Sidewalk corners near the population center: outside every building rectangle.
	var slots: Array[Vector2] = []
	for x in [540, 720, 900, 1080, 1260]:
		for y in [360, 540, 720]:
			for side in [-1, 1]:
				slots.append(Vector2(x + side * 28, y + 28))
	# Additional clear sidewalk positions along the existing vertical streets.
	for x in range(180, int(MAP_SIZE.x), ROAD_SPACING):
		for y in range(0, int(MAP_SIZE.y)-179, ROAD_SPACING):
			for side in [-1, 1]:
				for offset in [28, 60, 100, 140]:
					var point := Vector2(x + side * 28, y + offset)
					if not slots.has(point):
						slots.append(point)
	return slots


static func building_rects() -> Array[Rect2]:
	var buildings: Array[Rect2] = []
	for column in range(int(MAP_SIZE.x / ROAD_SPACING)):
		for row in range(int(MAP_SIZE.y / ROAD_SPACING)):
			if not is_park(Vector2i(column,row)) and not (column > 14 and (column+row)%5 == 0):
				buildings.append(Rect2(column * 180 + 44, row * 180 + 44, 92, 92))
	return buildings


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), Color("101d2b"))
	for x in range(0, int(MAP_SIZE.x)+1, ROAD_SPACING):
		draw_line(Vector2(x, 0), Vector2(x, MAP_SIZE.y), Color("253549"), 36)
		draw_dashed_line(Vector2(x, 0), Vector2(x, MAP_SIZE.y), Color("415269"), 1, 12)
	for y in range(0, int(MAP_SIZE.y)+1, ROAD_SPACING):
		draw_line(Vector2(0, y), Vector2(MAP_SIZE.x, y), Color("253549"), 36)
		draw_dashed_line(Vector2(0, y), Vector2(MAP_SIZE.x, y), Color("415269"), 1, 12)
	for cell in park_cells():
		var park := Rect2(Vector2(cell) * 180 + Vector2(35, 35), Vector2(110, 110))
		draw_rect(park, Color("193730"))
		for offset in [Vector2(25, 25), Vector2(75, 45), Vector2(40, 80)]:
			draw_circle(park.position + offset, 11, Color("2d5448"))
	for building in building_rects():
		draw_rect(Rect2(building.position + Vector2(5, 6), building.size), Color("0b1520"))
		draw_rect(building, Color("2b3d52"))
		draw_rect(building.grow(-8), Color("30465c"), false, 1.5)
		for offset in [Vector2(18, 20), Vector2(48, 20), Vector2(18, 52), Vector2(48, 52)]:
			draw_rect(Rect2(building.position + offset, Vector2(16, 9)), Color("526476"))
	draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), Color("4b6178"), false, 3)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(790, 477), "CIVIC GARDENS", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("83b4a3"))
	draw_string(font, Vector2(630, 1018), "ESSAIM  /  CITY OBSERVATION GRID", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("7a8fa5"))

static func points_of_interest() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var kinds := ["Police Station", "Fire Station", "Medical Station", "Bank", "School"]
	for i in range(5):
		result.append({"id": "POI%d" % i, "kind": kinds[i], "position": Vector2(540+i*360, 568), "footprint": Rect2(540+i*360+44,584,92,92)})
	return result

static func is_park(cell: Vector2i) -> bool:
	return cell in PARK_CELLS or (cell.x+cell.y*3)%17 == 0
static func park_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in range(int(MAP_SIZE.x/180)):
		for y in range(int(MAP_SIZE.y/180)):
			if is_park(Vector2i(x,y)): result.append(Vector2i(x,y))
	return result
