extends Node2D
## Pure presentation of incidents visible in the current display mode.
var visible_events: Array = []

func sync(events: Array, director: bool) -> void:
	visible_events = events.filter(func(e: Dictionary): return e["active_status"] and (director or not e["visibility_to_agents"].is_empty()))
	queue_redraw()

func _draw() -> void:
	for event in visible_events:
		var color := Color("eeb568") if event["event_type"] != "crowd" else Color("f27b72")
		var point: Vector2 = event["target_location"]
		draw_circle(point, 32, Color(color, 0.15))
		draw_arc(point, 32, 0, TAU, 32, color, 3, true)
		draw_string(ThemeDB.fallback_font, point + Vector2(-40,-40), event["event_type"].to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)
