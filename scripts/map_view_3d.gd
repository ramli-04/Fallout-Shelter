extends SubViewportContainer
## View boundary. All entity movement comes from the existing simulation records.
signal object_selected(kind: String, record: Dictionary)
const Coordinates = preload("res://scripts/three_d/world_coordinates.gd")
const CITY = preload("res://scenes/three_d/city.tscn")
const CAMERA_RIG = preload("res://scenes/three_d/camera_rig.tscn")
const AGENT = preload("res://scenes/three_d/agent.tscn")
const SHELTER = preload("res://scenes/three_d/shelter.tscn")
var world_viewport: SubViewport
var world: Node3D
var city: Node3D
var camera_rig: Node3D
var camera: Camera3D
var agent_nodes: Array[Node3D] = []
var shelter_nodes: Array[Node3D] = []
var selected_node: Node3D
var event_visuals: Node3D
var impact_effect: Control
var impact_3d: Node3D
var dragging_pan := false
var dragging_rotate := false
var mouse_over := false
var window_active := true

func _ready() -> void:
	stretch = true
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	world_viewport = SubViewport.new()
	world_viewport.name = "WorldViewport"
	world_viewport.size = Vector2i(800,600)
	world_viewport.own_world_3d = true
	world_viewport.handle_input_locally = false
	world_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(world_viewport)
	world = Node3D.new()
	world.name = "World3D"
	world_viewport.add_child(world)
	city = CITY.instantiate()
	world.add_child(city)
	event_visuals = preload("res://scripts/three_d/environment_markers_3d.gd").new()
	world.add_child(event_visuals)
	camera_rig = CAMERA_RIG.instantiate()
	world.add_child(camera_rig)
	camera = camera_rig.camera
	mouse_exited.connect(_cancel_drag)
	get_window().focus_exited.connect(_cancel_drag)
	get_window().focus_exited.connect(func(): window_active = false)
	get_window().focus_entered.connect(func(): window_active = true)
	mouse_entered.connect(func(): mouse_over = true)
	mouse_exited.connect(func(): mouse_over = false)

func display_run(agents: Array[Dictionary], shelters: Array[Dictionary], reset_camera: bool = true) -> void:
	clear_selection()
	for node in agent_nodes + shelter_nodes:
		world.remove_child(node)
		node.queue_free()
	agent_nodes.clear()
	shelter_nodes.clear()
	for record in shelters:
		if not record["exists"]: continue
		var node: Node3D = SHELTER.instantiate()
		node.configure(record)
		world.add_child(node)
		shelter_nodes.append(node)
	for record in agents:
		var node: Node3D = AGENT.instantiate()
		node.configure(record)
		world.add_child(node)
		agent_nodes.append(node)
	reset_emergency_visuals()
	if reset_camera: fit_camera()

func sync_run(agents: Array[Dictionary], shelters: Array[Dictionary], alpha: float, running: bool, time: float = 0) -> void:
	for index in range(agent_nodes.size()):
		agent_nodes[index].update_visual(agents[index],alpha,running,time)
	for node in shelter_nodes:
		for record in shelters:
			if node.record["id"] == record["id"]:
				node.configure(record)
				break

func show_warning() -> void:
	city.set_warning(true)

func show_impact() -> void:
	if is_instance_valid(impact_3d): return
	impact_3d = preload("res://scripts/three_d/impact_3d.gd").new()
	world.add_child(impact_3d)
	impact_effect = preload("res://scripts/impact_effect.gd").new()
	add_child(impact_effect)
	city.set_warning(true)

func reset_emergency_visuals() -> void:
	if is_instance_valid(impact_3d):
		world.remove_child(impact_3d)
		impact_3d.queue_free()
	impact_3d = null
	if is_instance_valid(impact_effect):
		remove_child(impact_effect)
		impact_effect.queue_free()
	impact_effect = null
	city.set_warning(false)
	event_visuals.sync([])
	_cancel_drag()

func fit_camera() -> void:
	camera_rig.reset_overview()

func pan_camera(direction: Vector2, delta: float) -> void:
	camera_rig.pan(direction,delta)

func focus_selected() -> void:
	if is_instance_valid(selected_node) and selected_node in agent_nodes:
		camera_rig.focus_at(Coordinates.to_world(selected_node.record["position"]))

func _cancel_drag() -> void:
	dragging_pan = false
	dragging_rotate = false

func _can_navigate() -> bool:
	var owner := get_viewport().gui_get_focus_owner()
	return window_active and mouse_over and (owner == null or owner == self)

func _process(delta: float) -> void:
	if camera_rig == null: return
	if _can_navigate():
		var direction := Vector2.ZERO
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): direction.x -= 1
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): direction.x += 1
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): direction.y -= 1
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): direction.y += 1
		camera_rig.pan(direction,delta)
	camera_rig.advance(delta)

func _gui_input(event: InputEvent) -> void:
	if camera == null: return
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_MIDDLE:
				dragging_pan = event.pressed
				if event.pressed: grab_focus()
			MOUSE_BUTTON_RIGHT:
				dragging_rotate = event.pressed
				if event.pressed: grab_focus()
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed: camera_rig.zoom_steps(1)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed: camera_rig.zoom_steps(-1)
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					grab_focus()
					select_at(event.position)
					if event.double_click: focus_selected()
			_:
				return
		accept_event()
	elif event is InputEventMouseMotion:
		if dragging_pan:
			camera_rig.drag_pan(event.relative,size.y)
			accept_event()
		elif dragging_rotate:
			camera_rig.rotate_drag(event.relative)
			accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F or event.keycode == KEY_F:
			focus_selected()
			accept_event()
		elif event.physical_keycode == KEY_HOME or event.keycode == KEY_HOME:
			fit_camera()
			accept_event()

func pick_entity(local_point: Vector2) -> Node3D:
	var origin := camera.project_ray_origin(local_point)
	var direction := camera.project_ray_normal(local_point)
	var query := PhysicsRayQueryParameters3D.create(origin,origin+direction*camera.far,1|2|4)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return null
	var collider: Object = hit["collider"]
	# Prefer a bean inside the gate's generous selection area, while opaque buildings
	# still block the ray. A selection volume is not a solid wall.
	if collider is Area3D and int(collider.collision_layer) == 2:
		query.collision_mask = 1|4
		var agent_hit := world.get_world_3d().direct_space_state.intersect_ray(query)
		if not agent_hit.is_empty() and agent_hit["collider"].has_meta("entity_owner"):
			var candidate: Node3D = agent_hit["collider"].get_meta("entity_owner")
			if candidate in agent_nodes: return candidate
	return collider.get_meta("entity_owner") if collider.has_meta("entity_owner") else null

func select_at(local_point: Vector2) -> void:
	clear_selection()
	var node := pick_entity(local_point)
	if node == null:
		object_selected.emit("none",{})
		return
	selected_node = node
	node.set_selected(true)
	object_selected.emit("agent" if node in agent_nodes else "shelter",node.record)

func clear_selection() -> void:
	if is_instance_valid(selected_node): selected_node.set_selected(false)
	selected_node = null

func select_shelter(record: Dictionary) -> void:
	clear_selection()
	for node in shelter_nodes:
		if node.record["id"] == record["id"]:
			selected_node = node
			node.set_selected(true)
			break
	object_selected.emit("shelter",record)

func select_agent(record: Dictionary) -> void:
	clear_selection()
	for node in agent_nodes:
		if node.record["id"] == record["id"]:
			selected_node = node
			node.set_selected(true)
			break
	object_selected.emit("agent",record)

func screen_point(node: Node3D, offset: Vector3 = Vector3(0,1.2,0)) -> Vector2:
	return camera.unproject_position(node.global_position+offset)
