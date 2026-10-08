extends SceneTree
## Engine-backed 3D navigation, raycasts, input and lifecycle regression checks.
const MAIN = preload("res://scenes/main.tscn")
const Manager = preload("res://scripts/simulation_manager.gd")
const Coordinates = preload("res://scripts/three_d/world_coordinates.gd")
const CameraRig = preload("res://scripts/three_d/director_camera.gd")
const Routes = preload("res://scripts/road_routes.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + description)

func button_input(control: Control, position: Vector2, button: int, pressed: bool, double_click: bool = false) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = control.global_position+position
	motion.global_position = motion.position
	root.push_input(motion,true)
	var event := InputEventMouseButton.new()
	event.position = motion.position
	event.global_position = event.position
	event.button_index = button
	event.pressed = pressed
	event.double_click = double_click
	root.push_input(event,true)

func drag(control: Control, button: int, movement: Vector2) -> void:
	var point := control.size/2
	button_input(control,point,button,true)
	var motion := InputEventMouseMotion.new()
	motion.position = control.global_position+point+movement
	motion.global_position = motion.position
	motion.relative = movement
	motion.button_mask = MOUSE_BUTTON_MASK_MIDDLE if button == MOUSE_BUTTON_MIDDLE else MOUSE_BUTTON_MASK_RIGHT
	root.push_input(motion,true)
	button_input(control,point+movement,button,false)

func key_input(code: int) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = code
	key.keycode = code
	key.pressed = true
	root.push_input(key,true)
	key = key.duplicate()
	key.pressed = false
	root.push_input(key,true)

func settle_physics() -> void:
	await physics_frame
	await process_frame
	await physics_frame
	await process_frame

func _run() -> void:
	var app: Control = MAIN.instantiate()
	root.add_child(app)
	app.manager.set_process(false)
	await settle_physics()
	var view: SubViewportContainer = app.map_view
	var rig: Node3D = view.camera_rig
	# Navigation map updates are asynchronous. A nonzero iteration can still
	# represent the empty map before this region's mesh joins it under CPU load.
	# Wait for a real entrance path, with a bounded timeout rather than two frames.
	for frame in range(120):
		var warmup: PackedVector3Array = view.city.navigation_region.path_between(view.agent_nodes[0].position,view.shelter_nodes[0].entrance_position)
		if warmup.size() >= 2 and warmup[-1].distance_to(view.shelter_nodes[0].entrance_position) < 0.05:
			break
		await physics_frame
		await process_frame
	var baseline := Manager.new()
	root.add_child(baseline)
	baseline.set_process(false)
	check(baseline.load_settings(), "headless baseline configuration loads")
	baseline.initialize_run()
	check(app.manager.agents == baseline.agents and app.manager.shelters == baseline.shelters and app.manager.environment_events == baseline.environment_events, "3D initialization consumes no simulation randomness")
	check(view.world is Node3D and view.camera is Camera3D and view.world_viewport.own_world_3d, "genuine isolated 3D world and camera")
	check(view.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "camera uses perspective projection")
	check(is_equal_approx(rig.pitch,45) and is_equal_approx(rig.yaw,45) and view.camera.global_position.y > 50, "elevated 45-degree diagonal overview")
	check(view.city.buildings.size() == Manager.CityMap.building_rects().size(), "all original building footprints represented")
	check(view.agent_nodes.size() == 20, "twenty reusable 3D avatars")
	check(app.director_mode and app.false_alarm_button.visible and app.export_button.visible, "Director-only controls preserved")
	check(not app.get_property_list().any(func(p: Dictionary): return p["name"] == "mode_picker"), "no Observer mode selector")
	check(CameraRig.validate(rig.settings).is_empty(), "camera config validates")
	var invalid: Dictionary = rig.settings.duplicate(true)
	invalid["min_distance"] = invalid["max_distance"]+1
	check(not CameraRig.validate(invalid).is_empty(), "invalid camera zoom bounds rejected")
	for point in [Vector2.ZERO,Vector2(1800,1080),Vector2(540,388)]:
		check(Coordinates.to_simulation(Coordinates.to_world(point)).is_equal_approx(point), "coordinate conversion round trip")
	var nav: NavigationRegion3D = view.city.navigation_region
	var map: RID = view.world.get_world_3d().navigation_map
	check(NavigationServer3D.map_get_iteration_id(map) > 0 and nav.navigation_mesh.get_polygon_count() > 0, "navigation map synchronized and populated")
	var colors := {}
	for index in range(view.agent_nodes.size()):
		var node: Node3D = view.agent_nodes[index]
		check(node.bean.mesh is CapsuleMesh and node.selection_area is Area3D and node.navigator is NavigationAgent3D, "capsule avatar, selection area and navigation agent")
		check(node.position.is_equal_approx(Coordinates.to_world(app.manager.agents[index]["position"])), "avatar XZ matches simulation position")
		colors[node.unique_color.to_html()] = true
		for shelter in view.shelter_nodes:
			var path: PackedVector3Array = nav.path_between(node.position,shelter.entrance_position)
			check(path.size() >= 2 and path[-1].distance_to(shelter.entrance_position) < 0.05, "connected Godot path from every spawn to every existing entrance")
			var clear := true
			for i in range(1,path.size()):
				for fraction in [0.0,0.25,0.5,0.75,1.0]:
					var point := Coordinates.to_simulation(path[i-1].lerp(path[i],fraction))
					for building in Manager.CityMap.building_rects():
						clear = clear and not building.grow(5.2).has_point(point)
			check(clear, "3D nav query avoids building volumes with bean clearance")
	check(colors.size() == 20, "distinct deterministic avatar colors")
	# The preserved fixed-clock routes also fit the same walkable 3D corridors.
	for profile in app.manager.agents:
		for belief in profile["beliefs"].values():
			var route := Routes.plan(profile["position"],belief["position"])
			var valid := true
			for i in range(1,route.size()):
				for fraction in [0.0,0.25,0.5,0.75,1.0]:
					valid = valid and nav.contains(Coordinates.to_world(route[i-1].lerp(route[i],fraction)))
			check(valid, "authoritative road routes lie on 3D navigation surface")
	# Raycasting respects real occlusion; select an initially visible entity.
	var selected: Node3D = null
	var selected_point := Vector2.ZERO
	for node in view.agent_nodes:
		var point: Vector2 = view.screen_point(node)
		if Rect2(Vector2.ZERO,view.size).has_point(point) and view.pick_entity(point) == node:
			selected = node
			selected_point = point
			break
	check(selected != null, "visible agent selectable in overview")
	if selected != null:
		var before: Array = app.manager.agents.duplicate(true)
		button_input(view,selected_point,MOUSE_BUTTON_LEFT,true)
		button_input(view,selected_point,MOUSE_BUTTON_LEFT,false)
		check(view.selected_node == selected and selected.is_selected and selected.selection_ring.visible and app.details.text.contains(selected.record["id"]), "real mouse raycast highlights agent and updates inspector")
		check(app.manager.agents == before, "selection never changes autonomy")
		button_input(view,selected_point,MOUSE_BUTTON_LEFT,true,true)
		button_input(view,selected_point,MOUSE_BUTTON_LEFT,false)
		check(rig.target_focus.is_equal_approx(Coordinates.to_world(selected.record["position"])), "double-click focuses selected agent")
		rig.snap()
		rig.pan(Vector2.RIGHT,0.5)
		key_input(KEY_F)
		check(rig.target_focus.is_equal_approx(Coordinates.to_world(selected.record["position"])), "F key focuses current agent")
	key_input(KEY_HOME)
	check(rig.target_focus == Vector3(90,0.18,54) and rig.target_distance == 145, "Home restores initial overview")
	var focus_before: Vector3 = rig.target_focus
	drag(view,MOUSE_BUTTON_MIDDLE,Vector2(24,8))
	check(rig.target_focus != focus_before and not view.dragging_pan, "middle drag pans and releases cleanly")
	var yaw_before: float = rig.target_yaw
	drag(view,MOUSE_BUTTON_RIGHT,Vector2(35,12))
	check(rig.target_yaw != yaw_before and not view.dragging_rotate, "right drag orbits and releases cleanly")
	var distance_before: float = rig.target_distance
	button_input(view,view.size/2,MOUSE_BUTTON_WHEEL_UP,true)
	button_input(view,view.size/2,MOUSE_BUTTON_WHEEL_UP,false)
	check(rig.target_distance < distance_before, "mouse wheel zooms in")
	var start_position: Vector3 = rig.position
	rig.pan(Vector2.RIGHT,1)
	rig.advance(0.01)
	check(rig.position != start_position and rig.position != rig.target_focus, "camera motion interpolates smoothly")
	rig.zoom_steps(10000)
	check(rig.target_distance == rig.settings["min_distance"], "minimum zoom distance clamped")
	rig.zoom_steps(-10000)
	check(rig.target_distance == rig.settings["max_distance"], "maximum zoom distance clamped")
	rig.rotate_drag(Vector2(0,10000))
	check(rig.target_pitch == 70, "upper pitch bounded")
	rig.rotate_drag(Vector2(0,-10000))
	check(rig.target_pitch == 30, "lower pitch bounded")
	rig.pan(Vector2(1,1),100000)
	check(rig.target_focus.x >= 0 and rig.target_focus.x <= 180 and rig.target_focus.z >= 0 and rig.target_focus.z <= 108, "camera focus stays inside city bounds")
	# UI input must not initiate camera movement, zoom or rotation.
	rig.reset_overview()
	app.seed_picker.get_line_edit().grab_focus()
	var ui_focus: Vector3 = rig.target_focus
	var key := InputEventKey.new()
	key.physical_keycode = KEY_D
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	view._process(0.2)
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	check(rig.target_focus == ui_focus, "typing in UI never pans camera")
	var ui_distance: float = rig.target_distance
	button_input(app.details,Vector2(20,20),MOUSE_BUTTON_WHEEL_UP,true)
	button_input(app.details,Vector2(20,20),MOUSE_BUTTON_WHEEL_UP,false)
	check(rig.target_distance == ui_distance, "scrolling inspector never zooms city")
	# Camera and selection activity cannot influence complete seeded evacuation traces.
	app.manager.start()
	baseline.start()
	app.manager.launch_nuke()
	baseline.launch_nuke()
	app.manager.advance_clock(30)
	baseline.advance_clock(30)
	await settle_physics()
	var active_paths := 0
	for node in view.agent_nodes:
		if node.record["state"] == "MOVING" and node.navigation_reachable: active_paths += 1
	check(active_paths > 0, "moving 3D avatars maintain reachable NavigationAgent waypoint paths")
	check(app.manager.agents == baseline.agents and app.manager.events == baseline.events, "3D camera, selection and physics preserve exact 30-second cognition trace")
	for node in view.agent_nodes:
		check(node.position.distance_to(Coordinates.to_world(node.record["previous_position"])) < 0.06, "rendered movement stays consistent with authoritative route interpolation")
	app.manager.pause()
	check(view.agent_nodes.all(func(a: Node3D): return not a.active and a.position.is_equal_approx(Coordinates.to_world(a.record["position"]))), "Pause snaps render interpolation to frozen authoritative positions")
	var paused_agents: Array = app.manager.agents.duplicate(true)
	rig.pan(Vector2.LEFT,1)
	rig.advance(0.2)
	app.manager.advance_clock(40)
	check(app.manager.agents == paused_agents, "camera remains free while simulation stays paused")
	app.manager.start()
	# Align baseline pause/resume journal with UI controller before comparing final traces.
	baseline.pause()
	baseline.start()
	app.manager.advance_clock(1000)
	baseline.advance_clock(1000)
	check(app.manager.agents == baseline.agents and app.manager.shelters == baseline.shelters and app.manager.events == baseline.events, "full 3D evacuation identical to independent headless baseline")
	check(app.manager.phase == "IMPACT" and app.summary_panel.visible and is_instance_valid(view.impact_3d), "siren/impact lifecycle reaches 3D effect and summary")
	for node in view.agent_nodes:
		if node.record["state"] == "SHELTERED":
			check(not node.visible and node.selection_area.collision_layer == 0, "admitted avatars disappear without phantom outdoor selection")
		else:
			check(node.visible and node.record["state"] == "EXPOSED", "outside agents stay represented as exposed")
	check(app.agent_picker.item_count == 21, "Director can inspect every agent including sheltered agents")
	app.agent_picker.item_selected.emit(1)
	check(app.details.text.contains(app.manager.agents[0]["id"]) and app.selected_kind == "agent", "agent picker retains indoor cognitive inspection")
	check(nav.navigation_mesh.get_polygon_count() > 0 and nav.path_between(Vector3(54,0.18,36),Vector3(90,0.18,72)).size() >= 2, "impact leaves navigation intact")
	app.reset_button.pressed.emit()
	await settle_physics()
	check(not is_instance_valid(view.impact_3d) and view.agent_nodes.size() == 20 and view.agent_nodes.all(func(a: Node3D): return a.visible), "reset clears effects and restores twenty visible beans")
	app.false_alarm_button.pressed.emit()
	app.manager.advance_clock(1000)
	check(app.manager.phase == "ALL_CLEAR" and not is_instance_valid(view.impact_3d), "false alarms preserve all-clear without 3D impact")
	var absent_seed := -1
	for seed_number in range(32):
		app.manager.new_run(seed_number)
		if not app.manager.shelter_by_id["S5"]["exists"]:
			absent_seed = seed_number
			break
	print("Absent S5 demonstration seed: ",absent_seed)
	await settle_physics()
	check(not app.manager.shelter_by_id["S5"]["exists"] and not view.shelter_nodes.any(func(s: Node3D): return s.record["id"] == "S5"), "absent S5 creates no 3D structure or accessible entrance")
	check(app.manager.agents.all(func(a: Dictionary): return a["beliefs"]["S5"]["existence_probability"] == 0.5), "Director knowledge never reveals S5 truth to agents")
	view.select_shelter(app.manager.shelter_by_id["S5"])
	check(app.details.text.contains("Exists: false"), "absent shelter remains inspectable in Director sidebar")
	baseline.queue_free()
	app.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("Phase 2.6: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
