extends SubViewportContainer
## Local map viewport: GUI panels never move with the camera or steal map clicks.

signal object_selected(kind: String, record: Dictionary)

const CityMap = preload("res://scripts/city_map.gd")
const AGENT_SCENE = preload("res://scenes/agent.tscn")
const SHELTER_SCENE = preload("res://scenes/shelter.tscn")
const ImpactEffect = preload("res://scripts/impact_effect.gd")
const MIN_ZOOM := 0.3
const MAX_ZOOM := 2.5

var world_viewport: SubViewport
var world: Node2D
var camera: Camera2D
var agent_nodes: Array[Node2D] = []
var shelter_nodes: Array[Node2D] = []
var selected_node: Node2D
var impact_effect: Control


func _ready() -> void:
	stretch = true
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	world_viewport = SubViewport.new()
	world_viewport.size = Vector2i(800, 600)
	world_viewport.handle_input_locally = false
	world_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(world_viewport)
	world = Node2D.new()
	world_viewport.add_child(world)
	world.add_child(CityMap.new())
	camera = Camera2D.new()
	world.add_child(camera)
	resized.connect(fit_camera)
	fit_camera.call_deferred()


func display_run(agents: Array[Dictionary], shelters: Array[Dictionary]) -> void:
	clear_selection()
	if is_instance_valid(impact_effect):
		remove_child(impact_effect)
		impact_effect.queue_free()
	impact_effect = null
	for node in agent_nodes + shelter_nodes:
		world.remove_child(node)
		node.queue_free()
	agent_nodes.clear()
	shelter_nodes.clear()
	for record in shelters:
		if not record["exists"]:
			continue
		var node: Node2D = SHELTER_SCENE.instantiate()
		node.configure(record)
		world.add_child(node)
		shelter_nodes.append(node)
	for record in agents:
		var node: Node2D = AGENT_SCENE.instantiate()
		node.configure(record)
		world.add_child(node)
		agent_nodes.append(node)
	fit_camera.call_deferred()


func sync_run(agents: Array[Dictionary], shelters: Array[Dictionary], alpha: float, active: bool) -> void:
	for index in range(agent_nodes.size()):
		agent_nodes[index].update_visual(agents[index], alpha, active)
	for node in shelter_nodes:
		for record in shelters:
			if node.record["id"] == record["id"]:
				node.configure(record)
				break


func show_impact() -> void:
	if is_instance_valid(impact_effect):
		return
	impact_effect = ImpactEffect.new()
	add_child(impact_effect)


func fit_camera() -> void:
	if camera == null or size.x < 1 or size.y < 1:
		return
	camera.position = CityMap.MAP_SIZE / 2
	var fit := minf((size.x - 70) / CityMap.MAP_SIZE.x, (size.y - 60) / CityMap.MAP_SIZE.y)
	camera.zoom = Vector2.ONE * clampf(fit, MIN_ZOOM, MAX_ZOOM)
	camera.force_update_scroll()


func _process(delta: float) -> void:
	if camera == null or (not has_focus() and not get_global_rect().has_point(get_global_mouse_position())):
		return
	var direction := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		direction.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		direction.x += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		direction.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		direction.y += 1
	pan_camera(direction, delta)


func pan_camera(direction: Vector2, delta: float) -> void:
	camera.position += direction.normalized() * 500 * delta / camera.zoom.x
	camera.position = camera.position.clamp(Vector2(-150, -150), CityMap.MAP_SIZE + Vector2(150, 150))
	camera.force_update_scroll()


func _gui_input(event: InputEvent) -> void:
	if camera == null or not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		zoom_at(event.position, 1.12)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		zoom_at(event.position, 1.0 / 1.12)
	elif event.button_index == MOUSE_BUTTON_LEFT:
		grab_focus()
		select_at(world_viewport.canvas_transform.affine_inverse() * event.position)
	else:
		return
	accept_event()


func zoom_at(local_point: Vector2, multiplier: float) -> void:
	var before := world_viewport.canvas_transform.affine_inverse() * local_point
	camera.zoom = Vector2.ONE * clampf(camera.zoom.x * multiplier, MIN_ZOOM, MAX_ZOOM)
	camera.force_update_scroll()
	var after := world_viewport.canvas_transform.affine_inverse() * local_point
	camera.position += before - after
	camera.force_update_scroll()


func clear_selection() -> void:
	if is_instance_valid(selected_node):
		selected_node.set_selected(false)
	selected_node = null


func select_at(world_point: Vector2) -> void:
	clear_selection()
	var closest: Node2D = null
	var distance := INF
	for node in agent_nodes + shelter_nodes:
		var candidate_distance: float = node.position.distance_to(world_point)
		var hit_radius := maxf(14 / camera.zoom.x, 14) if node in agent_nodes else 47.0
		if candidate_distance <= hit_radius and candidate_distance < distance:
			closest = node
			distance = candidate_distance
	if closest != null:
		selected_node = closest
		closest.set_selected(true)
		object_selected.emit("agent" if closest in agent_nodes else "shelter", closest.record)
	else:
		object_selected.emit("none", {})


func select_shelter(record: Dictionary) -> void:
	clear_selection()
	for node in shelter_nodes:
		if node.record["id"] == record["id"]:
			selected_node = node
			node.set_selected(true)
	object_selected.emit("shelter", record)
