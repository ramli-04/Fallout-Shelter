extends Node2D
## A reusable character: read-only run data, drawing, and selection.

var record: Dictionary = {}
var is_selected := false
var last_drawn_state := ""


func configure(data: Dictionary) -> void:
	record = data
	position = record["position"]
	queue_redraw()


func set_selected(value: bool) -> void:
	is_selected = value
	queue_redraw()


func _draw() -> void:
	if record.is_empty():
		return
	last_drawn_state = record["state"]
	var authority: bool = record["role"] == "Authority"
	var color := Color("f0b76a") if authority else Color("a9d9ec")
	match record["state"]:
		"MOVING": color = Color("81aafa")
		"SHELTERED": color = Color("66d9bb")
		"REJECTED": color = Color("f0b76a")
		"EXPOSED": color = Color("ed7587")
		"FROZEN", "DELAYED", "STAYING_HOME", "WAITING_ROAD": color = Color("c2a0f3")
		"HELPING": color = Color("e8e09a")
		"SAFE": color = Color("66d9bb")
	if is_selected:
		draw_circle(Vector2.ZERO, 22, Color(0.4, 0.9, 1.0, 0.15))
		draw_arc(Vector2.ZERO, 21, 0, TAU, 48, Color("ffffff"), 2.5, true)
	draw_circle(Vector2(2, 4), 12, Color("08131f"))
	draw_circle(Vector2.ZERO, 11, color)
	draw_arc(Vector2.ZERO, 11, 0, TAU, 32, Color("132238"), 2, true)
	if authority:
		draw_line(Vector2(-5, 0), Vector2(5, 0), Color("172331"), 2)
		draw_line(Vector2(0, -5), Vector2(0, 5), Color("172331"), 2)
	if is_selected:
		draw_string(ThemeDB.fallback_font, Vector2(-20, -30), record["id"], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)


func update_visual(data: Dictionary, alpha: float, active: bool) -> void:
	record = data
	var previous: Vector2 = data.get("previous_position", data["position"])
	position = previous.lerp(data["position"], alpha) if active else data["position"]
	if last_drawn_state != data["state"] or is_selected:
		queue_redraw()
