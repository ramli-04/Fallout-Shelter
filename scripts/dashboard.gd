extends RefCounted
## Small UI factory: styles and layout stay separate from simulation state.

const TEXT := Color("e4edf7")
const MUTED := Color("8da3bb")
const ACCENT := Color("66d9bb")


static func label(text: String, font_size: int = 16, color: Color = TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


static func style(color: Color, border: Color = Color("293d53"), radius: int = 12) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	return box


static func panel() -> PanelContainer:
	var node := PanelContainer.new()
	node.add_theme_stylebox_override("panel", style(Color("111f30")))
	return node


static func column(gap: int = 8) -> VBoxContainer:
	var node := VBoxContainer.new()
	node.add_theme_constant_override("separation", gap)
	return node


static func row(gap: int = 12) -> HBoxContainer:
	var node := HBoxContainer.new()
	node.add_theme_constant_override("separation", gap)
	return node


static func button(text: String, primary: bool = false) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size = Vector2(105, 42)
	node.add_theme_font_size_override("font_size", 16)
	var base := Color("21433e") if primary else Color("1b2e43")
	node.add_theme_stylebox_override("normal", style(base))
	node.add_theme_stylebox_override("hover", style(base.lightened(0.14), ACCENT))
	node.add_theme_stylebox_override("pressed", style(base.darkened(0.15), ACCENT))
	node.add_theme_stylebox_override("focus", style(Color(0, 0, 0, 0), ACCENT))
	node.add_theme_stylebox_override("disabled", style(Color("132132")))
	node.add_theme_color_override("font_color", TEXT)
	node.add_theme_color_override("font_disabled_color", MUTED)
	return node


static func spacer() -> Control:
	var node := Control.new()
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


static func shelter_card(record: Dictionary) -> Button:
	var node := button("", false)
	node.custom_minimum_size = Vector2(0, 78)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var content := column(3)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Button is not a container, so anchor its decorative content explicitly.
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 14
	content.offset_top = 7
	content.offset_right = -14
	content.offset_bottom = -6
	node.add_child(content)
	var color := Color(record["color"]) if record["exists"] else MUTED
	content.add_child(label("%s  /  %s" % [record["id"], record["name"]], 15, color))
	var capacity_label := label("", 13, MUTED)
	var status_label := label("", 12, MUTED)
	content.add_child(capacity_label)
	content.add_child(status_label)
	node.set_meta("capacity_label", capacity_label)
	node.set_meta("status_label", status_label)
	var bar := ProgressBar.new()
	bar.custom_minimum_size.y = 4
	bar.max_value = maxi(1, record["capacity"])
	bar.value = record["occupancy"]
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color("2b3c50")
	background.set_corner_radius_all(2)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	content.add_child(bar)
	node.set_meta("occupancy_bar", bar)
	update_shelter_card(node, record)
	return node


static func update_shelter_card(card: Button, record: Dictionary) -> void:
	if record.get("observer_masked", false):
		card.get_meta("capacity_label").text = "Size: %s / occupancy unverified" % record["known_information"]["size"]
		card.get_meta("status_label").text = "Rumored site" if record["id"] == "S5" else "Status unverified / " + record["resources"]
		card.get_meta("occupancy_bar").visible = false
		return
	card.get_meta("occupancy_bar").visible = true
	card.get_meta("occupancy_bar").max_value = maxi(1, record["capacity"])
	var percentage: float = 100.0 * record["occupancy"] / maxi(1, record["capacity"])
	card.get_meta("capacity_label").text = "%d / %d  (%.1f%%) • %d places" % [record["occupancy"], record["capacity"], percentage, record["capacity"] - record["occupancy"]]
	var status := "Absent" if not record["exists"] else "Unavailable" if not record["operational"] else "Closed" if not record["accepting"] else "Full" if record["occupancy"] >= record["capacity"] else "Open"
	card.get_meta("status_label").text = "STATUS: " + status
	if record.get("door_status", "OPEN") == "BLOCKED":
		card.get_meta("status_label").text = "STATUS: Door blocked"
	card.get_meta("occupancy_bar").value = record["occupancy"]
