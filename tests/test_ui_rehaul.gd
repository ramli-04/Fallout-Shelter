extends SceneTree
const MAIN = preload("res://scenes/main.tscn")
var failures := 0
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func settle() -> void:
	for i in range(8):
		await process_frame

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/ui_" + name + ".png")

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://outputs")
	var app: Control = MAIN.instantiate()
	root.add_child(app)
	await settle()
	check(app.intro_panel.visible and not app.drawer.visible, "initial welcome and collapsed panels")
	app.start_button.pressed.emit()
	await settle()
	check(app.manager.running and not app.intro_panel.visible, "Start enters map and starts simulation")
	check(app.map_view.position.is_equal_approx(Vector2.ZERO) and app.map_view.size.is_equal_approx(app.size), "map fills entire interface")
	check(app.start_button.global_position.y > app.size.y - 180, "controls at bottom")
	for button in [app.start_button, app.pause_button, app.reset_button, app.launch_button, app.false_alarm_button, app.fullscreen_button, app.export_button, app.new_run_button, app.random_button, app.drawer_buttons["agents"], app.drawer_buttons["shelters"], app.drawer_buttons["logs"], app.drawer_buttons["settings"]]:
		check(button.icon != null and button.text.is_empty() and not button.tooltip_text.is_empty(), "action uses an icon with a descriptive tooltip")
	var dock_style: StyleBoxFlat = app.controls_dock.get_theme_stylebox("panel")
	check(is_equal_approx(dock_style.bg_color.a, 0.5), "control bar background is exactly fifty percent transparent")
	check(app.controls_dock.modulate.a == 1.0, "controls remain fully opaque")
	await capture("map")
	app.drawer_buttons["agents"].pressed.emit()
	await settle()
	check(app.active_drawer == "agents" and app.drawer.visible and app.agent_picker.visible and not app.shelter_group.visible, "agent drawer")
	app.map_view.select_agent(app.manager.agents[0])
	await settle()
	check(app.details.visible and app.details.text.contains("A001"), "agent selection opens own information")
	var distance: float = app.map_view.camera_rig.target_distance
	var pointer := InputEventMouseMotion.new()
	pointer.position = app.details.global_position + Vector2(20, 20)
	root.push_input(pointer, true)
	var wheel := InputEventMouseButton.new()
	wheel.position = pointer.position
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	root.push_input(wheel, true)
	await settle()
	check(app.map_view.camera_rig.target_distance == distance, "scrolling a drawer does not zoom the map")
	await capture("agents")
	app.drawer_buttons["agents"].pressed.emit()
	check(not app.drawer.visible, "repeated button collapses drawer")
	app.drawer_buttons["shelters"].pressed.emit()
	await settle()
	check(app.shelter_group.visible and not app.agent_picker.visible, "shelter drawer")
	app.map_view.select_shelter(app.manager.shelters[0])
	await settle()
	check(app.details.visible and app.details.text.contains("Capacity: 125"), "shelter selection opens shelter info")
	await capture("shelters")
	app.drawer_buttons["logs"].pressed.emit()
	await settle()
	check(app.logs_panel.visible and not app.inspector_panel.visible, "logs replace inspector")
	check(not app.event_feed.get_parsed_text().is_empty(), "journal still receives events")
	await capture("logs")
	app.pause_button.pressed.emit()
	check(not app.manager.running, "pause control preserved")
	app.drawer_buttons["settings"].pressed.emit()
	await settle()
	check(app.settings_panel.visible and not app.logs_panel.visible and not app.inspector_panel.visible, "settings menu replaces other drawers")
	check(app.settings_panel.is_ancestor_of(app.seed_picker), "seed input lives inside settings")
	await capture("settings")
	app.seed_picker.value = 123
	app.new_run_button.pressed.emit()
	await settle()
	check(app.manager.seed_value == 123 and app.manager.agents.size() == 150, "settings apply seed without changing population")
	app.drawer_buttons["settings"].pressed.emit()
	app.random_button.pressed.emit()
	await settle()
	check(app.manager.seed_value != 123 and app.seed_picker.value == app.manager.seed_value, "random scenario synchronizes settings seed")
	app.start_button.pressed.emit()
	app.drawer_buttons["logs"].pressed.emit()
	if DisplayServer.get_name() != "headless":
		app.fullscreen_button.pressed.emit()
		await settle()
		check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "fullscreen button expands native window")
		app.fullscreen_button.pressed.emit()
		await settle()
		check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "fullscreen button restores windowed mode")
		DisplayServer.window_set_size(Vector2i(1024, 720))
		await settle()
		await capture("small_window")
		for control in [app.start_button, app.fullscreen_button, app.speed_label, app.drawer_buttons["logs"]]:
			check(control.get_global_rect().end.x <= app.size.x + 1 and control.get_global_rect().end.y <= app.size.y + 1, "controls inside smaller window")
	app.reset_button.pressed.emit()
	await settle()
	check(not app.manager.running and app.intro_panel.visible and not app.drawer.visible, "reset restores welcome and collapsed drawers")
	app.queue_free()
	await settle()
	print("UI overhaul: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
