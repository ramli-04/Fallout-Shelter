extends VBoxContainer
const Dashboard = preload("res://scripts/dashboard.gd")
var refresh_age := 0.0
var activate_button: Button
var test_button: Button
var volume_label: Label
var manager: Node
var view: Node
var picker: OptionButton
var inspection: Label
var mode_picker: OptionButton
var volume: HSlider
var announcements: CheckBox
func configure(sim: Node, map: Node) -> void:
	manager = sim
	view = map
	var heading := Label.new()
	heading.text = "SIREN CONTROL PANEL"
	add_child(heading)
	var hint := Label.new()
	hint.text = "Network activation and individual tests never launch the countdown. Temporary local audio is included."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	for active in [true,false]:
		var button := Dashboard.button("",active)
		if active: activate_button = button
		button.text = "Activate all sirens" if active else "Deactivate all sirens"
		button.pressed.connect(func():
			manager.Warning.activate(manager,active,true)
			view.siren_network.sync_mix())
		add_child(button)
	mode_picker = OptionButton.new()
	for mode in manager.Warning.MODES: mode_picker.add_item(mode)
	mode_picker.item_selected.connect(func(i):
		manager.warning_config["network_mode"] = manager.Warning.MODES[i]
		view.siren_network.sync_mix())
	add_child(mode_picker)
	var label := Label.new()
	volume_label = label
	label.text = "Master warning volume (-60 to 0 dB)"
	add_child(label)
	volume = HSlider.new()
	volume.min_value = -60
	volume.max_value = 0
	volume.value = -10
	volume.value_changed.connect(func(value):
		volume_label.text = "Master warning volume: %.0f dB" % value
		manager.warning_config["master_volume_db"] = value
		view.siren_network.sync_mix())
	add_child(volume)
	announcements = _toggle("Enable announcements",true,func(value): manager.warning_config["announcements_enabled"] = value)
	_toggle("Show siren coverage",false,func(value):
		view.siren_network.show_coverage = value
		for node in view.siren_network.nodes: node.coverage.visible = value)
	_toggle("Camera-relative Director mix",true,func(value): manager.warning_config["director_mix"] = value)
	_toggle("Environmental muffling",true,func(value): manager.warning_config["environmental_muffling"] = value)
	_toggle("Listener indoors (Director only)",false,func(value): view.listener_indoors = value)
	picker = OptionButton.new()
	picker.item_selected.connect(func(_index): inspect())
	add_child(picker)
	var test := Dashboard.button("Test selected siren (6 seconds)")
	test_button = test
	test.text = "Test selected siren (6 seconds)"
	test.pressed.connect(func():
		if picker.selected >= 0: view.siren_network.test_siren(manager.sirens[picker.selected]["id"]))
	add_child(test)
	inspection = Label.new()
	inspection.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(inspection)
	manager.run_initialized.connect(sync)
func _toggle(text: String, initial: bool, callback: Callable) -> CheckBox:
	var button := CheckBox.new()
	button.text = text
	button.button_pressed = initial
	button.toggled.connect(callback)
	add_child(button)
	return button
func sync() -> void:
	picker.clear()
	for record in manager.sirens: picker.add_item(record["id"]+" / "+record["site"])
	mode_picker.select(manager.Warning.MODES.find(manager.warning_config["network_mode"]))
	volume.set_value_no_signal(manager.warning_config["master_volume_db"])
	volume_label.text = "Master warning volume: %.0f dB" % volume.value
	announcements.set_pressed_no_signal(manager.warning_config["announcements_enabled"])
	inspect()
func inspect(id: String = "") -> void:
	if not id.is_empty():
		for i in range(manager.sirens.size()):
			if manager.sirens[i]["id"] == id: picker.select(i)
	if picker.selected < 0: return
	var record: Dictionary = manager.sirens[picker.selected]
	test_button.disabled = record["state"] in ["DAMAGED","DESTROYED"]
	inspection.text = "%s / %s\nState: %s / Survived impact: %s\nMount: %s / Radius: %.0f world units\nTower: %.0f dB / Pitch: %.2f\nSpatial channels: %d / %d" % [record["id"],record["site"],record["state"],record["survived"] if manager.phase == "IMPACT" else "N/A",record["mount"],record["radius_world"],record["volume_db"],record["pitch"],view.siren_network.audible_ids.size(),manager.warning_config["max_audible_sirens"]]
func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	refresh_age += delta
	if refresh_age < 0.25: return
	refresh_age = 0
	activate_button.disabled = manager.phase == "IMPACT"
	if inspection and not manager.sirens.is_empty(): inspect()
