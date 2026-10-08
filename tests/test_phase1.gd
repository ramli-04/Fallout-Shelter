extends SceneTree
## Run without third-party test plugins: godot --headless --path . --script res://tests/test_phase1.gd

const MAIN_SCENE = preload("res://scenes/main.tscn")
const Manager = preload("res://scripts/simulation_manager.gd")
const CityMap = preload("res://scripts/city_map.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + description)


func click(control: Control, local_point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = control.global_position + local_point
	motion.global_position = motion.position
	root.push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = control.global_position + local_point
	event.global_position = event.position
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)


func _run() -> void:
	var app: Control = MAIN_SCENE.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	await physics_frame
	await process_frame
	var manager: Node = app.manager
	manager.set_process(false)
	check(manager.agents.size() == 20, "20 agents initialized")
	check(manager.shelters.size() == 5, "all five shelter records initialized")
	check(app.map_view.agent_nodes.size() == 20, "20 reusable agent scenes instantiated")
	var existing := 0
	var capacities: Array[int] = []
	for shelter in manager.shelters:
		capacities.append(int(shelter["capacity"]))
		if shelter["exists"]:
			existing += 1
	check(capacities == [2500, 750, 1800, 3500, 5000], "specified capacities")
	check(app.map_view.shelter_nodes.size() == existing, "only existing shelters drawn")
	check(app.shelter_list.get_child_count() == 5, "absent shelter still has a sidebar record")
	check(manager.shelters[2]["resources"] == "Unknown", "S3 supplies described as unknown")
	check(manager.shelters[2]["supplies_person_days"] == null, "unknown quantity is null, never zero")
	var ids: Array[String] = []
	var positions: Array[Vector2] = []
	var authorities := 0
	for agent in manager.agents:
		check(agent["id"] not in ids, "agent has unique ID")
		check(agent["position"] not in positions, "agent has distinct position")
		ids.append(agent["id"])
		positions.append(agent["position"])
		if agent["role"] == "Authority":
			authorities += 1
		check(agent["state"] == "IDLE", "agent starts idle")
		check(agent["movement_speed"] >= 1.2 and agent["movement_speed"] <= 4.8, "speed range respected")
		for property in ["risk_tolerance", "trust_in_authority", "sociability"]:
			check(agent[property] >= 0 and agent[property] <= 100, "trait range respected")
		for building in CityMap.building_rects():
			check(not building.grow(12).has_point(agent["position"]), "agent spawns clear of buildings")
		for shelter in manager.shelters:
			check(agent["position"].distance_to(shelter["position"]) >= 65, "spawn clears shelter plaza")
	check(authorities == 4, "heterogeneous roles: four authorities")
	var original_agents: Array = manager.agents.duplicate(true)
	var original_shelters: Array = manager.shelters.duplicate(true)
	var initial_events: Array = manager.events.duplicate(true)
	check(initial_events.size() == 28, "system, five shelter and 20 agent events recorded")
	check(app.start_button.disabled == false and app.pause_button.disabled, "initial control state")
	# Dispatch real GUI events through the viewport, exercising connected signals.
	click(app.start_button, app.start_button.size / 2)
	await process_frame
	check(manager.running, "Start button starts evacuation clock")
	manager.advance_clock(2.5)
	check(is_equal_approx(manager.elapsed_seconds, 2.5), "clock advances at 1x")
	manager.simulation_speed = 2
	manager.advance_clock(1)
	check(is_equal_approx(manager.elapsed_seconds, 4.5), "configured clock speed applies")
	click(app.pause_button, app.pause_button.size / 2)
	await process_frame
	check(not manager.running, "Pause button stops preparation clock")
	manager.advance_clock(100)
	check(is_equal_approx(manager.elapsed_seconds, 4.5), "paused time does not advance")
	var paused_agents: Array = manager.agents.duplicate(true)
	manager.advance_clock(10)
	check(manager.agents == paused_agents, "Pause freezes agent movement and decisions")
	check(manager.shelters == original_shelters, "clock does not resample S5")
	manager.simulation_speed = 1
	var view: SubViewportContainer = app.map_view
	# A building may occlude an agent in a perspective view. Click a genuinely visible bean.
	var selected_agent: Dictionary = {}
	var target := Vector2.ZERO
	for node in view.agent_nodes:
		var projected: Vector2 = view.screen_point(node)
		if Rect2(Vector2.ZERO,view.size).has_point(projected) and view.pick_entity(projected) == node:
			selected_agent = node.record
			target = projected
			break
	check(not selected_agent.is_empty(), "at least one agent selectable from initial perspective")
	click(view, target)
	await process_frame
	check(is_instance_valid(view.selected_node) and view.selected_node.record["id"] == selected_agent.get("id", "missing"), "map agent click selects agent")
	check(app.details.text.contains(selected_agent.get("id", "missing")), "agent inspector updates")
	check(is_instance_valid(view.selected_node) and view.selected_node.is_selected, "selection highlight is enabled")
	target = view.screen_point(view.shelter_nodes[0], Vector3(0,3.3,4.1))
	click(view, target)
	await process_frame
	check(is_instance_valid(view.selected_node) and view.selected_node.record["id"] == "S1", "map shelter click selects shelter")
	check(app.details.text.contains("Capacity: 2500"), "director inspector shows actual capacity")
	var s3_card: Control = app.shelter_list.get_child(2)
	app.sidebar_scroll.ensure_control_visible(s3_card)
	await process_frame
	click(s3_card, s3_card.size / 2)
	await process_frame
	check(app.details.text.contains("Unknown"), "sidebar shelter selection shows unknown supplies")
	var zoom_before: float = view.camera_rig.target_distance
	var wheel := InputEventMouseButton.new()
	wheel.pressed = true
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.position = view.global_position + view.size / 2
	root.push_input(wheel, true)
	await process_frame
	check(view.camera_rig.target_distance < zoom_before, "mouse-wheel input zooms camera")
	wheel = wheel.duplicate()
	wheel.pressed = false
	root.push_input(wheel, true)
	click(view, Vector2(10, 10))
	await process_frame
	var keyboard_before: Vector3 = view.camera_rig.position
	var key := InputEventKey.new()
	key.physical_keycode = KEY_D
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	view._process(0.1)
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	check(view.camera_rig.position.x > keyboard_before.x, "D key pans camera when map is focused")
	view.camera_rig.zoom_steps(-1000)
	check(is_equal_approx(view.camera_rig.target_distance, 260), "maximum zoom clamp")
	view.camera_rig.zoom_steps(1000)
	check(is_equal_approx(view.camera_rig.target_distance, 16), "minimum zoom clamp")
	var camera_before: Vector3 = view.camera_rig.target_focus
	view.pan_camera(Vector2.RIGHT, 0.2)
	check(view.camera_rig.target_focus.x > camera_before.x, "camera pan changes position")
	await process_frame
	click(app.reset_button, app.reset_button.size / 2)
	await process_frame
	await process_frame
	check(manager.elapsed_seconds == 0 and not manager.running, "Reset clears clock and pauses")
	check(manager.agents == original_agents, "Reset reproduces every agent property")
	check(manager.shelters == original_shelters, "Reset reproduces S5 and shelter data")
	check(manager.events == initial_events, "Reset reproduces initialization event journal")
	check(not is_instance_valid(view.selected_node), "Reset clears selection")
	check(view.agent_nodes.size() == 20, "Reset does not duplicate rendered agents")
	check(app.shelter_list.get_child_count() == 5, "Reset does not duplicate sidebar entries")
	# Cover both possible S5 outcomes and independence from profile count.
	var seen: Array[bool] = []
	for run_seed in range(12):
		manager.seed_value = run_seed
		manager.initialize_run()
		var exists: bool = manager.shelters[4]["exists"]
		if exists not in seen:
			seen.append(exists)
		manager.settings["agent_count"] = 5
		manager.initialize_run()
		check(manager.shelters[4]["exists"] == exists, "S5 independent of agent count")
		manager.settings["agent_count"] = 20
	check(seen.size() == 2, "seeded runs cover present and absent S5")
	check(Manager.validate_settings(manager.settings).is_empty(), "default configuration validates")
	for bad_value in [0, -1, "fast"]:
		var bad: Dictionary = manager.settings.duplicate(true)
		bad["simulation_speed"] = bad_value
		check(not Manager.validate_settings(bad).is_empty(), "invalid clock speed rejected")
	var invalid: Dictionary = manager.settings.duplicate(true)
	invalid["shelters"][0]["position"] = ["bad", 100]
	check(not Manager.validate_settings(invalid).is_empty(), "invalid position rejected")
	invalid = manager.settings.duplicate(true)
	invalid["shelters"][4]["existence_probability"] = 1.5
	check(not Manager.validate_settings(invalid).is_empty(), "invalid probability rejected")
	print("Phase 1: %d checks, %d failures" % [checks, failures])
	app.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
