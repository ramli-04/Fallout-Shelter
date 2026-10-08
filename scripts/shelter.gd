extends Node2D
## The absent S5 record has no map node; it stays inspectable in the sidebar.

var record: Dictionary = {}
var is_selected := false


func configure(data: Dictionary) -> void:
	record = data.duplicate(true)
	position = record["position"]
	queue_redraw()


func set_selected(value: bool) -> void:
	is_selected = value
	queue_redraw()


func _draw() -> void:
	if record.is_empty():
		return
	var color := Color(record["color"])
	draw_circle(Vector2.ZERO, 43, Color("122232"))
	draw_arc(Vector2.ZERO, 43, 0, TAU, 64, Color(color, 0.35), 2, true)
	if is_selected:
		draw_arc(Vector2.ZERO, 51, 0, TAU, 64, Color.WHITE, 3, true)
	var shape: String = record["shape"]
	if shape == "circle":
		draw_circle(Vector2.ZERO, 26, Color(color, 0.18))
		draw_arc(Vector2.ZERO, 26, 0, TAU, 48, color, 3, true)
	else:
		var sides := 6
		var angle := -PI / 2
		match shape:
			"square":
				sides = 4
				angle = PI / 4
			"diamond":
				sides = 4
			"triangle":
				sides = 3
		var points := PackedVector2Array()
		for index in range(sides):
			points.append(Vector2.from_angle(angle + TAU * index / sides) * 28)
		draw_colored_polygon(points, Color(color, 0.18))
		points.append(points[0])
		draw_polyline(points, color, 3, true)
	draw_line(Vector2(-7, 0), Vector2(7, 0), color, 3)
	draw_line(Vector2(0, -7), Vector2(0, 7), color, 3)
	draw_string(ThemeDB.fallback_font, Vector2(-13, 66), record["id"], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, color)
