extends VBoxContainer
## Director configuration is preparation-only; preview reads truth without applying it.
var manager: Node
var view: Node
var readout: Label
var fields: Array[Control] = []
var x_input: SpinBox
var y_input: SpinBox
var radius_input: SpinBox
var severity_input: SpinBox
var map_size_picker: OptionButton
var random_toggle: CheckBox
func configure(sim: Node, map: Node) -> void:
	manager = sim
	view = map
	add_child(_label("NUCLEAR IMPACT CONTROLLER"))
	var size_picker := OptionButton.new()
	map_size_picker = size_picker
	for name in ["Compact (2x)","Large (2.5x)","Extended (3x)","Valley (3.75x)"]: size_picker.add_item(name)
	size_picker.select(1)
	add_child(size_picker)
	fields.append(size_picker)
	size_picker.item_selected.connect(func(i):
		if manager.phase != "PREPARATION": return
		manager.nuclear["map_scale"] = [2.0,2.5,3.0,3.75][i]
		manager.initialize_run())
	x_input = _number("Impact X (simulation units)",0,5400,2250)
	y_input = _number("Impact Y (simulation units)",0,3240,1350)
	for input in [x_input,y_input]:
		input.value_changed.connect(func(_value):
			if manager.set_impact(Vector2(x_input.value,y_input.value)):
				random_toggle.set_pressed_no_signal(false)
				view.update_impact_marker())
	var select := CheckBox.new()
	select.text = "Click map to select impact"
	add_child(select)
	fields.append(select)
	select.toggled.connect(func(value): view.impact_selection_enabled = value)
	view.impact_selected.connect(func(point):
		if manager.set_impact(point):
			sync()
			view.update_impact_marker())
	random_toggle = CheckBox.new()
	random_toggle.text = "Seeded random impact"
	add_child(random_toggle)
	fields.append(random_toggle)
	random_toggle.toggled.connect(func(value):
		if manager.phase != "PREPARATION": return
		manager.nuclear["random_impact"] = value
		if value: manager.randomize_impact()
		sync()
		view.update_impact_marker())
	var radius := _number("Blast radius (3D world units)",10,700,300)
	radius_input = radius
	radius.value_changed.connect(func(value):
		if manager.phase != "PREPARATION": return
		manager.nuclear["radius"] = value
		view.update_impact_marker())
	var severity := _number("Fictional severity",0,4,1,0.05)
	severity_input = severity
	severity.value_changed.connect(func(value):
		if manager.phase == "PREPARATION": manager.nuclear["severity"] = value)
	var zones := CheckBox.new()
	zones.text = "Show blast zones"
	zones.button_pressed = true
	add_child(zones)
	zones.toggled.connect(func(value):
		view.show_zones = value
		view.update_impact_marker())
	var quality := OptionButton.new()
	quality.add_item("Visual quality: low / no shadows")
	quality.add_item("Visual quality: standard")
	quality.select(1)
	add_child(quality)
	quality.item_selected.connect(func(i):
		view.visual_quality = i
		view.city.sun.shadow_enabled = i == 1)
	var preview := Button.new()
	preview.text = "Preview event / shelter damage"
	add_child(preview)
	preview.pressed.connect(func():
		view.preview_nuclear()
		readout.text = "PREVIEW ONLY\n"
		for prediction in manager.preview_damage():
			readout.text += "%s: %s (%.1f units)\n" % [prediction["id"],prediction["structural_state"],prediction["distance_world"]])
	var reset := Button.new()
	reset.text = "Reset impact to city center"
	add_child(reset)
	fields.append(reset)
	reset.pressed.connect(func():
		if manager.phase != "PREPARATION": return
		manager.nuclear["random_impact"] = false
		random_toggle.set_pressed_no_signal(false)
		manager.set_impact(preload("res://scripts/city_map.gd").MAP_SIZE/2)
		sync()
		view.update_impact_marker())
	var landmark_picker := OptionButton.new()
	for title in ["Focus landmark?","Bank","Police Station","Medical Station","Fire Station","School","Nuclear impact"]: landmark_picker.add_item(title)
	landmark_picker.item_selected.connect(func(index):
		if index > 0: view.focus_landmark(landmark_picker.get_item_text(index)))
	add_child(landmark_picker)
	readout = _label("Select a shelter for actual state. Preview leaves simulation unchanged.")
	add_child(readout)
	manager.run_initialized.connect(sync)
func sync() -> void:
	var bounds: Vector2 = preload("res://scripts/city_map.gd").MAP_SIZE
	x_input.max_value = bounds.x
	y_input.max_value = bounds.y
	radius_input.set_value_no_signal(manager.nuclear["radius"])
	severity_input.set_value_no_signal(manager.nuclear["severity"])
	map_size_picker.select([2.0,2.5,3.0,3.75].find(float(manager.nuclear["map_scale"])))
	random_toggle.set_pressed_no_signal(manager.nuclear["random_impact"])
	x_input.set_value_no_signal(manager.nuclear["impact_position"][0])
	y_input.set_value_no_signal(manager.nuclear["impact_position"][1])
	if readout: readout.text = "Preparation: configure impact before starting."
func _process(_delta: float) -> void:
	if manager == null: return
	for control in fields:
		if control is SpinBox: control.editable = manager.phase == "PREPARATION"
		elif control is BaseButton: control.disabled = manager.phase != "PREPARATION"
func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
func _number(title: String, low: float, high: float, value: float, step: float = 1) -> SpinBox:
	add_child(_label(title))
	var input := SpinBox.new()
	input.min_value = low
	input.max_value = high
	input.step = step
	input.value = value
	add_child(input)
	fields.append(input)
	return input
