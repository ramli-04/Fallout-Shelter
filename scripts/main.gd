extends Control
## Compose the dashboard and connect signals. All run state is in the manager.

const Dashboard = preload("res://scripts/dashboard.gd")
const Manager = preload("res://scripts/simulation_manager.gd")
const MapView = preload("res://scripts/map_view_3d.gd")
const Inspector = preload("res://scripts/object_inspector.gd")
const Effects = preload("res://scripts/evacuation_effects.gd")
const director_mode := true

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
var launch_button: Button
var false_alarm_button: Button
var random_button: Button
var export_button: Button
var environment_feed: RichTextLabel
var warning_label: Label
var inspector_scroll_generation := 0
var agent_picker: OptionButton
var inspector_header: Label
var settings_panel: PanelContainer
var controls_dock: PanelContainer
var fullscreen_button: Button
var drawer: VBoxContainer
var inspector_panel: PanelContainer
var logs_panel: PanelContainer
var shelter_group: VBoxContainer
var drawer_title: Label
var drawer_buttons := {}
var active_drawer := ""
var intro_panel: PanelContainer
var windowed_size := Vector2i(1440, 900)
var windowed_position := Vector2i.ZERO
var ai_status_label: Label


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
	manager.siren_activated.connect(_on_siren_visual)
	manager.clock_changed.connect(effects.set_clock_active)
	manager.impact_occurred.connect(_on_impact)
	manager.all_clear.connect(_on_all_clear)
	map_view.object_selected.connect(_on_object_selected)
	agent_picker.item_selected.connect(func(index: int):
		if index > 0: map_view.select_agent(manager.agents[index-1]))
	start_button.pressed.connect(_start_map_view)
	launch_button.pressed.connect(manager.launch_nuke)
	false_alarm_button.pressed.connect(manager.launch_nuke.bind(true))
	random_button.pressed.connect(_on_random_run)
	export_button.pressed.connect(_export_trace)
	pause_button.pressed.connect(manager.pause)
	reset_button.pressed.connect(manager.initialize_run)
	new_run_button.pressed.connect(_on_new_run)
	speed_picker.item_selected.connect(func(index: int): manager.set_speed(speed_picker.get_item_id(index)))
	if manager.load_settings():
		manager.initialize_run()


func _build_dashboard() -> void:
	theme = Dashboard.light_theme()
	map_view = MapView.new()
	map_view.name = "CityViewport"
	map_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(map_view)
	var hud := Dashboard.column(6)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hud.offset_left = 16
	hud.offset_top = 16
	hud.offset_right = -16
	_build_top_bar(hud)
	summary_panel = Dashboard.panel()
	summary_panel.visible = false
	summary_label = Dashboard.label("", 14, Color("a05b22"))
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_panel.add_child(summary_label)
	hud.add_child(summary_panel)
	var rail := Dashboard.column(8)
	add_child(rail)
	rail.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	rail.offset_left = -64
	rail.offset_right = -16
	rail.offset_top = 112
	for entry in [["agents", "Agents"], ["shelters", "Shelters"], ["logs", "Logs"]]:
		var button := Dashboard.icon_button(entry[0], entry[1])
		button.toggle_mode = true
		button.tooltip_text = "Open or collapse " + entry[1].to_lower() + " panel"
		rail.add_child(button)
		drawer_buttons[entry[0]] = button
		button.pressed.connect(_toggle_drawer.bind(entry[0]))
	drawer = Dashboard.column(8)
	drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(drawer)
	drawer.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	drawer.offset_left = -472
	drawer.offset_right = -88
	drawer.offset_top = 112
	drawer.offset_bottom = -112
	var heading := Dashboard.panel()
	drawer.add_child(heading)
	var heading_row := Dashboard.row(8)
	heading.add_child(heading_row)
	drawer_title = Dashboard.label("AGENT INFO", 16, Dashboard.ACCENT)
	heading_row.add_child(drawer_title)
	heading_row.add_child(Dashboard.spacer())
	var close := Dashboard.icon_button("close", "Close panel")
	heading_row.add_child(close)
	close.pressed.connect(_toggle_drawer.bind(""))
	_build_sidebar(drawer)
	_build_event_panel(drawer)
	drawer.hide()
	var dock := Dashboard.panel()
	controls_dock = dock
	dock.add_theme_stylebox_override("panel", Dashboard.style(Color(0.98, 0.985, 0.96, 0.5)))
	add_child(dock)
	dock.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	dock.offset_left = 16
	dock.offset_right = -16
	dock.offset_top = -96
	dock.offset_bottom = -16
	var controls := Dashboard.column(8)
	dock.add_child(controls)
	_build_controls(controls)
	_build_settings(drawer)
	intro_panel = Dashboard.panel()
	add_child(intro_panel)
	intro_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	intro_panel.offset_left = -260
	intro_panel.offset_right = 260
	intro_panel.offset_top = -90
	intro_panel.offset_bottom = 90
	var intro := Dashboard.column(10)
	intro_panel.add_child(intro)
	intro.add_child(Dashboard.label("ESSAIM / DIRECTOR VIEW", 24, Dashboard.ACCENT))
	var hint := Dashboard.label("Press the play icon below to enter the city.\nAgents, shelters and logs open from the right.\nWASD: pan / Wheel: zoom / Right drag: orbit", 16)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_child(hint)


func _build_top_bar(layout: VBoxContainer) -> void:
	var panel := Dashboard.panel()
	layout.add_child(panel)
	var column := Dashboard.column(4)
	panel.add_child(column)
	var row := Dashboard.row(14)
	column.add_child(row)
	row.add_child(Dashboard.label("ESSAIM", 20, Dashboard.ACCENT))
	status_label = Dashboard.label("Preparation / Ready", 14)
	row.add_child(status_label)
	row.add_child(Dashboard.spacer())
	countdown_label = Dashboard.label("--:--", 20)
	row.add_child(countdown_label)
	count_label = Dashboard.label("150", 16)
	row.add_child(Dashboard.label("AGENTS", 11, Dashboard.MUTED))
	row.add_child(count_label)
	totals_label = Dashboard.label("0 / 0", 16)
	row.add_child(Dashboard.label("SAFE / EXPOSED", 11, Dashboard.MUTED))
	row.add_child(totals_label)
	top_speed_label = Dashboard.label("1x", 16, Dashboard.ACCENT)
	row.add_child(top_speed_label)
	var info := Dashboard.row(14)
	column.add_child(info)
	ai_status_label = Dashboard.label("AI / DISCONNECTED", 12, Dashboard.MUTED)
	info.add_child(ai_status_label)
	info.add_child(Dashboard.spacer())
	warning_label = Dashboard.label("NUCLEAR ALERT / EVACUATE", 13, Color("a05b22"))
	warning_label.hide()
	info.add_child(warning_label)


func _build_sidebar(body: VBoxContainer) -> void:
	var panel := Dashboard.panel()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector_panel = panel
	body.add_child(panel)
	var scroll := ScrollContainer.new()
	sidebar_scroll = scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var column := Dashboard.column(10)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	shelter_group = Dashboard.column(8)
	column.add_child(shelter_group)
	shelter_group.add_child(Dashboard.label("SHELTER NETWORK", 16))
	shelter_group.add_child(Dashboard.label("Five records â€¢ click a card to inspect", 13, Dashboard.MUTED))
	shelter_list = Dashboard.column(7)
	shelter_group.add_child(shelter_list)
	shelter_group.add_child(HSeparator.new())
	inspector_header = Dashboard.label("OBJECT INSPECTOR", 16, Dashboard.ACCENT)
	column.add_child(inspector_header)
	agent_picker = OptionButton.new()
	agent_picker.fit_to_longest_item = false
	agent_picker.clip_text = true
	agent_picker.custom_minimum_size = Vector2(275,34)
	agent_picker.tooltip_text = "Inspect agents outdoors or inside a shelter."
	column.add_child(agent_picker)
	details = RichTextLabel.new()
	details.bbcode_enabled = true
	details.fit_content = true
	details.scroll_active = false
	details.custom_minimum_size = Vector2(275, 170)
	details.add_theme_font_size_override("normal_font_size", 15)
	column.add_child(details)


func _build_event_panel(layout: VBoxContainer) -> void:
	var panel := Dashboard.panel()
	logs_panel = panel
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(panel)
	var column := Dashboard.column(5)
	panel.add_child(column)
	var heading := Dashboard.row()
	heading.add_child(Dashboard.label("EVENT JOURNAL", 14))
	heading.add_child(Dashboard.spacer())
	seed_label = Dashboard.label("SEED 42", 12, Dashboard.MUTED)
	seed_label.tooltip_text = "The same seed recreates the same scenario. Change it in Settings."
	heading.add_child(seed_label)
	column.add_child(heading)
	event_feed = RichTextLabel.new()
	event_feed.bbcode_enabled = false
	event_feed.custom_minimum_size.y = 72
	event_feed.scroll_following = true
	event_feed.add_theme_font_size_override("normal_font_size", 13)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(tabs)
	event_feed.name = "Journal"
	tabs.add_child(event_feed)
	environment_feed = RichTextLabel.new()
	environment_feed.name = "Environment"
	environment_feed.custom_minimum_size.y = 72
	environment_feed.scroll_following = true
	environment_feed.add_theme_font_size_override("normal_font_size", 13)
	tabs.add_child(environment_feed)


func _build_controls(layout: VBoxContainer) -> void:
	var row := Dashboard.row(10)
	layout.add_child(row)
	start_button = Dashboard.icon_button("play", "Start / resume simulation", true)
	pause_button = Dashboard.icon_button("pause", "Pause simulation")
	reset_button = Dashboard.icon_button("reset", "Reset the current scenario")
	launch_button = Dashboard.icon_button("alert", "Launch nuclear alert", true)
	false_alarm_button = Dashboard.icon_button("false_alarm", "Launch a false alarm")
	for control in [start_button, pause_button, launch_button, false_alarm_button, reset_button]:
		row.add_child(control)
	var home := Dashboard.icon_button("overview", "Fit the city overview")
	row.add_child(home)
	home.pressed.connect(map_view.fit_camera)
	speed_picker = OptionButton.new()
	speed_picker.tooltip_text = "Simulation speed"
	speed_picker.custom_minimum_size = Vector2(75, 48)
	for speed in [1, 2, 5, 10]:
		speed_picker.add_item("%dx" % speed, speed)
	row.add_child(speed_picker)
	export_button = Dashboard.icon_button("export", "Export simulation trace")
	row.add_child(export_button)
	fullscreen_button = Dashboard.icon_button("fullscreen", "Enter fullscreen / F11")
	row.add_child(fullscreen_button)
	fullscreen_button.pressed.connect(_toggle_fullscreen)
	var settings_button := Dashboard.icon_button("settings", "Scenario settings")
	settings_button.toggle_mode = true
	drawer_buttons["settings"] = settings_button
	row.add_child(settings_button)
	settings_button.pressed.connect(_toggle_drawer.bind("settings"))
	row.add_child(Dashboard.spacer())
	clock_label = Dashboard.label("Elapsed  00:00", 14)
	row.add_child(clock_label)
	speed_label = Dashboard.label("SPEED  1x", 14, Dashboard.ACCENT)
	row.add_child(speed_label)

func _build_settings(parent: VBoxContainer) -> void:
	settings_panel = Dashboard.panel()
	settings_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(settings_panel)
	var column := Dashboard.column(16)
	settings_panel.add_child(column)
	column.add_child(Dashboard.label("SCENARIO SEED", 16, Dashboard.ACCENT))
	var hint := Dashboard.label("The same seed recreates the same scenario. Applying a seed resets the simulation.", 14, Dashboard.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	seed_picker = SpinBox.new()
	seed_picker.min_value = 0
	seed_picker.max_value = 2147483646
	seed_picker.step = 1
	seed_picker.custom_minimum_size = Vector2(0, 44)
	seed_picker.tooltip_text = "Scenario seed (0 to 2147483646)"
	column.add_child(seed_picker)
	var actions := Dashboard.row(12)
	column.add_child(actions)
	new_run_button = Dashboard.icon_button("apply", "Apply seed and create a new scenario", true)
	actions.add_child(new_run_button)
	actions.add_child(Dashboard.label("Apply seed", 14))
	random_button = Dashboard.icon_button("random", "Create a random scenario")
	actions.add_child(random_button)
	actions.add_child(Dashboard.label("Random", 14))
	column.add_child(Dashboard.label("SEED RANGE / 0 - 2147483646", 12, Dashboard.MUTED))
	settings_panel.hide()


func _on_run_initialized() -> void:
	effects.stop_siren()
	intro_panel.show()
	_toggle_drawer("")
	warning_label.visible = false
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
	agent_picker.clear()
	agent_picker.add_item("Inspect any agent / indoors too")
	agent_picker.set_item_disabled(0,true)
	for agent in manager.agents:
		agent_picker.add_item("%s / %s" % [agent["id"],agent["state"]])
	agent_picker.select(0)
	seed_label.text = "SEED %d" % manager.seed_value
	speed_label.text = "SPEED  %dx" % int(manager.simulation_speed) if is_equal_approx(manager.simulation_speed, round(manager.simulation_speed)) else "SPEED  %.1fx" % manager.simulation_speed
	event_feed.clear()
	environment_feed.clear()
	for entry in manager.events:
		_on_event_logged(entry)
	_on_object_selected("none", {})
	seed_picker.value = manager.seed_value
	speed_picker.select(speed_picker.get_item_index(int(manager.simulation_speed)))
	_refresh_live_ui()


func _on_clock_changed(elapsed: float, active: bool) -> void:
	if not active and not manager.agents.is_empty():
		map_view.sync_run(manager.agents,manager.shelters,1,false,manager.elapsed_seconds)
	clock_label.text = "Elapsed  %s" % _format_time(elapsed)
	countdown_label.text = _format_time(ceil(manager.remaining_seconds)) if manager.phase == "EVACUATION" else "--:--"
	status_label.text = manager.phase.capitalize() + (" / Running" if active else " / Paused")
	if manager.phase == "EVACUATION":
		status_label.text += " / " + ("Real" if manager.alarm_is_real else "False")
	start_button.tooltip_text = "Start simulation" if manager.phase == "PREPARATION" else "Resume simulation"
	start_button.disabled = active or manager.phase in ["IMPACT", "ALL_CLEAR"]
	launch_button.disabled = manager.phase not in ["PREPARATION", "LIVING"]
	false_alarm_button.disabled = launch_button.disabled
	pause_button.disabled = not active
	speed_label.text = "SPEED  %dx" % int(manager.simulation_speed)
	top_speed_label.text = "%dx" % int(manager.simulation_speed)


func _on_event_logged(entry: Dictionary) -> void:
	event_feed.add_text("[%s]  %-8s  %s\n" % [_format_time(entry["time"]), entry["category"], entry["message"]])
	if entry["category"] in ["ENVIRONMENT", "OBSERVED", "RELAY"]:
		environment_feed.add_text("[%s] %s\n" % [_format_time(entry["time"]), entry["message"]])


func _on_object_selected(kind: String, record: Dictionary) -> void:
	selected_kind = kind
	selected_id = record.get("id", "")
	agent_picker.select(0)
	if kind == "agent":
		for index in range(manager.agents.size()):
			if manager.agents[index]["id"] == selected_id:
				agent_picker.select(index+1)
				break
	if kind in ["agent", "shelter"]:
		_show_drawer("agents" if kind == "agent" else "shelters")
	_refresh_inspector()
	inspector_scroll_generation += 1
	if kind != "none":
		_scroll_to_inspector(inspector_scroll_generation)
	else:
		sidebar_scroll.set_deferred("scroll_vertical", 0)


func _scroll_to_inspector(generation: int) -> void:
	# RichTextLabel fit-content changes settle after layout. Avoid scrolling beyond a
	# newly shortened inspector when switching from a long agent record to a shelter.
	await get_tree().process_frame
	await get_tree().process_frame
	if generation != inspector_scroll_generation: return
	var scrollbar := sidebar_scroll.get_v_scroll_bar()
	var limit := maxi(0,int(scrollbar.max_value-scrollbar.page))
	sidebar_scroll.scroll_vertical = mini(limit,maxi(0,int(inspector_header.position.y)-4))


func _refresh_inspector() -> void:
	details.visible = (active_drawer == "agents" and selected_kind == "agent") or (active_drawer == "shelters" and selected_kind == "shelter") or selected_kind == "none"
	if selected_kind == "agent":
		for agent in manager.agents:
			if agent["id"] == selected_id:
				details.text = Inspector.agent_text(agent)
				return
	elif selected_kind == "shelter":
		details.text = Inspector.shelter_text(manager.shelter_by_id[selected_id])
		return
	details.text = "[color=#62736b]Click a 3D agent or shelter to inspect. Start simulation activates the city; Launch nuke sounds the siren.\n\nDirector sees world truth. Agents continue to use their own partial knowledge. Scroll this panel for beliefs and memories.[/color]"


func _on_simulation_updated() -> void:
	var alpha: float = manager.accumulator / float(manager.settings["evacuation"]["fixed_step_seconds"])
	map_view.sync_run(manager.agents, manager.shelters, alpha, manager.running, manager.elapsed_seconds)
	map_view.event_visuals.sync(manager.environment_events, director_mode)
	ui_dirty = true


func _process(delta: float) -> void:
	if manager != null and manager.ai_bridge != null and ai_status_label != null:
		ai_status_label.text = "AI / %s / %d agents / queue %d / active %d" % [manager.ai_bridge.status, int(manager.ai_config.get("llm_agent_count", 0)), manager.ai_bridge.decision_queue.size(), manager.ai_bridge.pending.size()]
	ui_refresh_time += delta
	if ui_dirty and ui_refresh_time >= 0.1:
		ui_refresh_time = 0
		ui_dirty = false
		_refresh_live_ui()


func _refresh_live_ui() -> void:
	var totals: Dictionary = manager.get_totals()
	totals_label.text = "%d / %d" % [totals["sheltered"], totals["exposed"]]
	for index in range(manager.agents.size()):
		var agent: Dictionary = manager.agents[index]
		var text := "%s / %s" % [agent["id"],agent["state"]]
		if agent_picker.get_item_text(index+1) != text:
			agent_picker.set_item_text(index+1,text)
	for index in range(manager.shelters.size()):
		Dashboard.update_shelter_card(shelter_list.get_child(index), manager.shelters[index])
	_refresh_inspector()


func _on_impact(result: Dictionary) -> void:
	effects.stop_siren()
	warning_label.text = "IMPACT / EVACUATION STOPPED"
	warning_label.visible = true
	map_view.show_impact()
	summary_panel.visible = true
	summary_label.text = "IMPACT  â€¢  %d sheltered / %d exposed / %d total. Evacuation and admissions stopped. Final survival outcomes are not modeled." % [result["sheltered"], result["exposed"], result["population"]]
	_refresh_live_ui()


func _on_new_run() -> void:
	var chosen_seed := int(seed_picker.value)
	manager.new_run(chosen_seed)


func _on_random_run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var chosen := rng.randi_range(0, 2147483646)
	if chosen == manager.seed_value:
		chosen = (chosen+1) % 2147483647
	manager.new_run(chosen)


func _on_all_clear() -> void:
	effects.stop_siren()
	warning_label.text = "ALL CLEAR"
	warning_label.visible = true
	map_view.city.set_warning(false)
	summary_panel.visible = true
	summary_label.text = "ALL CLEAR / False alarm. No nuclear impact occurred."
	_refresh_live_ui()


func _on_siren_visual() -> void:
	warning_label.text = "NUCLEAR ALERT / EVACUATE"
	warning_label.visible = true
	map_view.show_warning()


func _export_trace() -> void:
	var path := "user://essaim_trace_%d.json" % manager.seed_value
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		manager.log_event("ERROR", "Cannot write trace: " + error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(_json_value({"seed": manager.seed_value, "settings": manager.settings, "living": manager.living, "alarm_is_real": manager.alarm_is_real, "countdown": manager.countdown_seconds, "events": manager.events, "environment": manager.environment_events, "agents": manager.agents, "shelters": manager.shelters}), "\t"))
	file.close()
	manager.log_event("EXPORT", "Trace saved: " + ProjectSettings.globalize_path(path), "director")


static func _json_value(value: Variant) -> Variant:
	if value is Vector2:
		return [value.x, value.y]
	if value is Dictionary:
		var result := {}
		for key in value:
			result[key] = _json_value(value[key])
		return result
	if value is Array or value is PackedVector2Array:
		var result := []
		for item in value:
			result.append(_json_value(item))
		return result
	return value


func _on_setup_failed(message: String) -> void:
	details.text = "Configuration error:\n" + message
	status_label.text = "Preparation â€¢ Error"
	start_button.disabled = true
	pause_button.disabled = true
	reset_button.disabled = true
	event_feed.add_text("[ERROR] " + message)


static func _format_time(seconds: float) -> String:
	var whole := int(seconds)
	return "%02d:%02d" % [whole / 60, whole % 60]

func _start_map_view() -> void:
	intro_panel.hide()
	_toggle_drawer("")
	manager.start()
	map_view.grab_focus()

func _toggle_drawer(kind: String) -> void:
	_show_drawer("" if kind == active_drawer else kind)

func _show_drawer(kind: String) -> void:
	active_drawer = kind
	drawer.visible = not kind.is_empty()
	inspector_panel.visible = kind in ["agents", "shelters"]
	logs_panel.visible = kind == "logs"
	settings_panel.visible = kind == "settings"
	shelter_group.visible = kind == "shelters"
	agent_picker.visible = kind == "agents"
	inspector_header.text = "AGENT INFO" if kind == "agents" else "SHELTER INFO"
	drawer_title.text = "SETTINGS" if kind == "settings" else "EVENT LOGS" if kind == "logs" else inspector_header.text
	for key in drawer_buttons:
		drawer_buttons[key].set_pressed_no_signal(key == kind)
	_refresh_inspector()
	sidebar_scroll.scroll_vertical = 0

func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(windowed_size)
		DisplayServer.window_set_position(windowed_position)
		fullscreen_button.icon = load("res://resources/icons/fullscreen.svg")
		fullscreen_button.tooltip_text = "Enter fullscreen / F11"
	else:
		windowed_size = DisplayServer.window_get_size()
		windowed_position = DisplayServer.window_get_position()
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		fullscreen_button.icon = load("res://resources/icons/windowed.svg")
		fullscreen_button.tooltip_text = "Restore windowed mode / F11"

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11:
			_toggle_fullscreen()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and not active_drawer.is_empty():
			_toggle_drawer("")
			get_viewport().set_input_as_handled()
