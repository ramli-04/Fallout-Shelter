extends Node2D
## Static map geometry in world units. No simulation behavior lives in this file.

const MAP_SIZE := Vector2(1800, 1080)
const ROAD_SPACING := 180
const PARK_CELLS := [Vector2i(4, 2), Vector2i(5, 2), Vector2i(2, 4)]


static func spawn_slots() -> Array[Vector2]:
	# Sidewalk corners near the population center: outside every building rectangle.
	var slots: Array[Vector2] = []
	for x in [540, 720, 900, 1080, 1260]:
		for y in [360, 540, 720]:
			for side in [-1, 1]:
				slots.append(Vector2(x + side * 28, y + 28))
	return slots


static func building_rects() -> Array[Rect2]:
	var buildings: Array[Rect2] = []
	for column in range(10):
		for row in range(6):
			if Vector2i(column, row) not in PARK_CELLS:
				buildings.append(Rect2(column * 180 + 44, row * 180 + 44, 92, 92))
	return buildings


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), Color("101d2b"))
	for x in range(0, 1801, ROAD_SPACING):
		draw_line(Vector2(x, 0), Vector2(x, 1080), Color("253549"), 36)
		draw_dashed_line(Vector2(x, 0), Vector2(x, 1080), Color("415269"), 1, 12)
	for y in range(0, 1081, ROAD_SPACING):
		draw_line(Vector2(0, y), Vector2(1800, y), Color("253549"), 36)
		draw_dashed_line(Vector2(0, y), Vector2(1800, y), Color("415269"), 1, 12)
	for cell in PARK_CELLS:
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
