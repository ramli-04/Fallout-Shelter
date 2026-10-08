extends Control
## Compose the dashboard and connect signals. All run state is in the manager.

const Dashboard = preload("res://scripts/dashboard.gd")
const Manager = preload("res://scripts/simulation_manager.gd")
const MapView = preload("res://scripts/map_view.gd")
const Inspector = preload("res://scripts/object_inspector.gd")
const Effects = preload("res://scripts/evacuation_effects.gd")

var manager: Node
var map_view: SubViewportContainer
var shelter_list: VBoxContainer
var sidebar_scroll: ScrollContainer
var details: RichTextLabel
var event_feed: RichTextLabel
var clock_label: Label
var status_label: Label
var count_label: Label
var seed_label: Label
var speed_label: Label
var start_button: Button
var pause_button: Button
var reset_button: Button
var new_run_button: Button
var speed_picker: OptionButton
var seed_picker: SpinBox
var countdown_label: Label
var totals_label: Label
var top_speed_label: Label
var summary_panel: PanelContainer
var summary_label: Label
var effects: Node
var selected_kind := "none"
var selected_id := ""
var ui_dirty := false
var ui_refresh_time := 0.0


func _ready() -> void:
	manager = Manager.new()
	manager.name = "SimulationManager"
	add_child(manager)
	_build_dashboard()
	effects = Effects.new()
	add_child(effects)
	manager.run_initialized.connect(_on_run_initialized)
	manager.clock_changed.connect(_on_clock_changed)
	manager.event_logged.connect(_on_event_logged)
	manager.setup_failed.connect(_on_setup_failed)
	manager.simulation_updated.connect(_on_simulation_updated)
	manager.siren_activated.connect(effects.sound_siren)
	manager.clock_changed.connect(effects.set_clock_active)
	manager.impact_occurred.connect(_on_impact)
	map_view.object_selected.connect(_on_object_selected)
	start_button.pressed.connect(manager.start)
	pause_button.pressed.connect(manager.pause)
	reset_button.pressed.connect(manager.initialize_run)
	new_run_button.pressed.connect(_on_new_run)
	speed_picker.item_selected.connect(func(index: int): manager.set_speed(speed_picker.get_item_id(index)))
	if manager.load_settings():
		manager.initialize_run()


func _build_dashboard() -> void:
	var background := ColorRect.new()
	background.color = Color("0a1421")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var layout := Dashboard.column(14)
	margin.add_child(layout)
	_build_top_bar(layout)
	summary_panel = Dashboard.panel()
	summary_panel.visible = false
	summary_label = Dashboard.label("", 16, Color("f0b76a"))
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_panel.add_child(summary_label)
	layout.add_child(summary_panel)
	var body := Dashboard.row(14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(body)
	_build_map(body)
	_build_sidebar(body)
	_build_event_panel(layout)
	_build_controls(layout)


func _build_top_bar(layout: VBoxContainer) -> void:
	var panel := Dashboard.panel()
	layout.add_child(panel)
	var row := Dashboard.row(22)
	panel.add_child(row)
	var title := Dashboard.column(3)
	title.add_child(Dashboard.label("URBAN RESILIENCE LAB   /   EVACUATION 02", 12, Dashboard.ACCENT))
	title.add_child(Dashboard.label("ESSAIM — LA DERNIÈRE CHANCE", 22))
	row.add_child(title)
	row.add_child(Dashboard.spacer())
	var phase := Dashboard.column(2)
	phase.add_child(Dashboard.label("PHASE", 12, Dashboard.MUTED))
	status_label = Dashboard.label("Preparation • Ready", 16)
	phase.add_child(status_label)
	row.add_child(phase)
	var countdown := Dashboard.column(2)
	countdown.add_child(Dashboard.label("COUNTDOWN", 12, Dashboard.MUTED))
	countdown_label = Dashboard.label("--:--", 22)
	countdown.add_child(countdown_label)
	row.add_child(countdown)
	var population := Dashboard.column(2)
	population.add_child(Dashboard.label("AGENTS", 12, Dashboard.MUTED))
	count_label = Dashboard.label("20", 22)
	population.add_child(count_label)
	row.add_child(population)
	var outcome := Dashboard.column(2)
	outcome.add_child(Dashboard.label("SHELTERED / EXPOSED", 11, Dashboard.MUTED))
	totals_label = Dashboard.label("0 / 0", 20)
	outcome.add_child(totals_label)
	row.add_child(outcome)
	var speed := Dashboard.column(2)
	speed.add_child(Dashboard.label("SPEED", 11, Dashboard.MUTED))
	top_speed_label = Dashboard.label("1x", 20, Dashboard.ACCENT)
	speed.add_child(top_speed_label)
	row.add_child(speed)


func _build_map(body: HBoxContainer) -> void:
	var panel := Dashboard.panel()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(panel)
	var content := Dashboard.column(10)
	panel.add_child(content)
	var heading := Dashboard.row()
	heading.add_child(Dashboard.label("CITY OVERVIEW", 16))
	heading.add_child(Dashboard.spacer())
	var fit_button := Dashboard.button("Fit map")
	heading.add_child(fit_button)
	content.add_child(heading)
	map_view = MapView.new()
	map_view.name = "CityViewport"
	map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_view.custom_minimum_size = Vector2(350, 240)
	content.add_child(map_view)
	fit_button.pressed.connect(map_view.fit_camera)
	var legend := Dashboard.label("Blue: moving  ·  Green: sheltered  ·  Gold: rejected  ·  Red: exposed  |  + Authority  |  WASD / arrows + wheel", 12, Dashboard.MUTED)
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(legend)


func _build_sidebar(body: HBoxContainer) -> void:
	var panel := Dashboard.panel()
	panel.custom_minimum_size.x = 330
	body.add_child(panel)
	var scroll := ScrollContainer.new()
	sidebar_scroll = scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var column := Dashboard.column(10)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	column.add_child(Dashboard.label("SHELTER NETWORK", 16))
	column.add_child(Dashboard.label("Five records • click a card to inspect", 13, Dashboard.MUTED))
	shelter_list = Dashboard.column(7)
	column.add_child(shelter_list)
	column.add_child(HSeparator.new())
	column.add_child(Dashboard.label("OBJECT INSPECTOR", 16, Dashboard.ACCENT))
	details = RichTextLabel.new()
	details.bbcode_enabled = true
	details.fit_content = true
	details.scroll_active = false
	details.custom_minimum_size = Vector2(275, 170)
	details.add_theme_font_size_override("normal_font_size", 15)
	column.add_child(details)


func _build_event_panel(layout: VBoxContainer) -> void:
	var panel := Dashboard.panel()
	layout.add_child(panel)
	var column := Dashboard.column(5)
	panel.add_child(column)
	var heading := Dashboard.row()
	heading.add_child(Dashboard.label("EVENT JOURNAL", 14))
	heading.add_child(Dashboard.spacer())
	seed_label = Dashboard.label("SEED 42  /  REPRODUCIBLE RESET", 12, Dashboard.MUTED)
	heading.add_child(seed_label)
	column.add_child(heading)
	event_feed = RichTextLabel.new()
	event_feed.bbcode_enabled = false
	event_feed.custom_minimum_size.y = 95
	event_feed.scroll_following = true
	event_feed.add_theme_font_size_override("normal_font_size", 13)
	column.add_child(event_feed)


func _build_controls(layout: VBoxContainer) -> void:
	var row := Dashboard.row(10)
	layout.add_child(row)
	start_button = Dashboard.button("Start", true)
	pause_button = Dashboard.button("Pause")
	reset_button = Dashboard.button("Reset")
	row.add_child(start_button)
	row.add_child(pause_button)
	row.add_child(reset_button)
	speed_picker = OptionButton.new()
	speed_picker.custom_minimum_size = Vector2(75, 42)
	for speed in [1, 2, 5, 10]:
		speed_picker.add_item("%dx" % speed, speed)
	row.add_child(speed_picker)
	row.add_child(Dashboard.label("Seed", 14, Dashboard.MUTED))
	seed_picker = SpinBox.new()
	seed_picker.min_value = 0
	seed_picker.max_value = 2147483646
	seed_picker.step = 1
	seed_picker.custom_minimum_size.x = 95
	row.add_child(seed_picker)
	new_run_button = Dashboard.button("New run")
	row.add_child(new_run_button)
	row.add_child(Dashboard.spacer())
	clock_label = Dashboard.label("Elapsed  00:00", 14)
	row.add_child(clock_label)
	speed_label = Dashboard.label("SPEED  1x", 15, Dashboard.ACCENT)
	row.add_child(speed_label)


func _on_run_initialized() -> void:
	effects.stop_siren()
	summary_panel.visible = false
	for child in shelter_list.get_children():
		shelter_list.remove_child(child)
		child.queue_free()
	for record in manager.shelters:
		var card := Dashboard.shelter_card(record)
		card.pressed.connect(map_view.select_shelter.bind(record))
		shelter_list.add_child(card)
	map_view.display_run(manager.agents, manager.shelters)
	count_label.text = str(manager.agents.size())
	seed_label.text = "SEED %d  /  REPRODUCIBLE RESET" % manager.seed_value
	speed_label.text = "SPEED  %dx" % int(manager.simulation_speed) if is_equal_approx(manager.simulation_speed, round(manager.simulation_speed)) else "SPEED  %.1fx" % manager.simulation_speed
	event_feed.clear()
	for entry in manager.events:
		_on_event_logged(entry)
	_on_object_selected("none", {})
	seed_picker.value = manager.seed_value
	speed_picker.select(speed_picker.get_item_index(int(manager.simulation_speed)))
	_refresh_live_ui()


func _on_clock_changed(elapsed: float, active: bool) -> void:
	clock_label.text = "Elapsed  %s" % _format_time(elapsed)
	countdown_label.text = "--:--" if manager.phase == "PREPARATION" else _format_time(ceil(manager.remaining_seconds))
	status_label.text = "Impact" if manager.phase == "IMPACT" else "Evacuation • %s" % ("Running" if active else "Paused") if manager.phase == "EVACUATION" else "Preparation • Ready"
	start_button.text = "Resume" if manager.phase == "EVACUATION" else "Start"
	start_button.disabled = active or manager.phase == "IMPACT"
	pause_button.disabled = not active
	speed_label.text = "SPEED  %dx" % int(manager.simulation_speed)
	top_speed_label.text = "%dx" % int(manager.simulation_speed)


func _on_event_logged(entry: Dictionary) -> void:
	event_feed.add_text("[%s]  %-8s  %s\n" % [_format_time(entry["time"]), entry["category"], entry["message"]])


func _on_object_selected(kind: String, record: Dictionary) -> void:
	selected_kind = kind
	selected_id = record.get("id", "")
	_refresh_inspector()
	if kind != "none":
		sidebar_scroll.ensure_control_visible.call_deferred(details)
	else:
		sidebar_scroll.set_deferred("scroll_vertical", 0)


func _refresh_inspector() -> void:
	if selected_kind == "agent":
		for agent in manager.agents:
			if agent["id"] == selected_id:
				details.text = Inspector.agent_text(agent, manager.remaining_seconds)
				return
	elif selected_kind == "shelter":
		details.text = Inspector.shelter_text(manager.shelter_by_id[selected_id])
		return
	details.text = "[color=#8da3bb]Select an agent or shelter to inspect.\n\nPress Start to trigger the siren. Operator shelter status is actual state; agent decisions use private beliefs.[/color]"


func _on_simulation_updated() -> void:
	var alpha: float = manager.accumulator / float(manager.settings["evacuation"]["fixed_step_seconds"])
	map_view.sync_run(manager.agents, manager.shelters, alpha, manager.running)
	ui_dirty = true


func _process(delta: float) -> void:
	ui_refresh_time += delta
	if ui_dirty and ui_refresh_time >= 0.1:
		ui_refresh_time = 0
		ui_dirty = false
		_refresh_live_ui()


func _refresh_live_ui() -> void:
	var totals: Dictionary = manager.get_totals()
	totals_label.text = "%d / %d" % [totals["sheltered"], totals["exposed"]]
	for index in range(manager.shelters.size()):
		Dashboard.update_shelter_card(shelter_list.get_child(index), manager.shelters[index])
	_refresh_inspector()


func _on_impact(result: Dictionary) -> void:
	effects.stop_siren()
	map_view.show_impact()
	summary_panel.visible = true
	summary_label.text = "IMPACT  •  %d sheltered / %d exposed / %d total. Evacuation and admissions stopped. Survival outcomes are reserved for Phase 3." % [result["sheltered"], result["exposed"], result["population"]]
	_refresh_live_ui()


func _on_new_run() -> void:
	var chosen_seed := int(seed_picker.value)
	if chosen_seed == manager.seed_value:
		chosen_seed = (chosen_seed + 1) % 2147483647
	manager.new_run(chosen_seed)


func _on_setup_failed(message: String) -> void:
	details.text = "Configuration error:\n" + message
	status_label.text = "Preparation • Error"
	start_button.disabled = true
	pause_button.disabled = true
	reset_button.disabled = true
	event_feed.add_text("[ERROR] " + message)


static func _format_time(seconds: float) -> String:
	var whole := int(seconds)
	return "%02d:%02d" % [whole / 60, whole % 60]
