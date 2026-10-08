extends Control
## A brief local map flash and expanding ring. Outcomes stay in the manager.

var age := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	age += delta
	if age < 2.5:
		queue_redraw()


func _draw() -> void:
	var flash := maxf(0, 0.6 * (1 - age / 0.6))
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 0.85, 0.66, flash))
	var opacity := maxf(0, 0.7 * (1 - age / 2.5))
	if opacity > 0:
		draw_arc(size / 2, age * size.length() / 2.5, 0, TAU, 96, Color(1, 0.65, 0.4, opacity), 5, true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.8, 0.15, 0.12, 0.06))
