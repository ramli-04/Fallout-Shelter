extends SubViewportContainer
## View boundary. All entity movement comes from the existing simulation records.
signal impact_selected(point: Vector2)
var follow_agent := false
var preview_city: Node3D
var preview_visibility: Array[Dictionary] = []
var preview_effect: Node3D
var visual_quality := 1
var impact_selection_enabled := false
var listener_indoors := false
var siren_network: Node3D
var social_world: Node3D
var manager: Node
var marker: Node3D
var blast_zones: Node3D
var show_zones := false
var occlusion_age := 0.0
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
var companion_nodes: Array[Node3D] = []
var shelter_nodes: Array[Node3D] = []
var selected_node: Node3D
var event_visuals: Node3D
var impact_effect: Control
var impact_3d: Node3D
var falling_bomb: Node3D
var dragging_pan := false
var mouse_over := false
var window_active := true
var agent_records: Array[Dictionary]=[]
var agent_pool: Dictionary={}
var visual_age:=0.0
var metrics_age:=0.0
var last_occluded: Dictionary={}
var render_config: Dictionary=preload("res://scripts/three_d/render_options.gd").load_options()
var performance_label: Label

func _ready() -> void:
	stretch = true
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	world_viewport = SubViewport.new()
	world_viewport.name = "WorldViewport"
	world_viewport.size = Vector2i(800,600)
	world_viewport.own_world_3d = true
	world_viewport.msaa_3d = Viewport.MSAA_4X
	world_viewport.audio_listener_enable_3d = true
	world_viewport.handle_input_locally = false
	world_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(world_viewport)
	world = Node3D.new()
	world.name = "World3D"
	world_viewport.add_child(world)
	social_world=preload("res://scripts/three_d/social_world.gd").new()
	social_world.manager=manager
	social_world.view=self
	world.add_child(social_world)
	event_visuals = preload("res://scripts/three_d/environment_markers_3d.gd").new()
	world.add_child(event_visuals)
	camera_rig = CAMERA_RIG.instantiate()
	world.add_child(camera_rig)
	camera = camera_rig.camera
	performance_label=Label.new(); performance_label.position=Vector2(16,130); performance_label.z_index=100; performance_label.add_theme_color_override("font_color",Color.WHITE); performance_label.add_theme_color_override("font_outline_color",Color.BLACK); performance_label.add_theme_constant_override("outline_size",4); performance_label.visible=render_config.show_metrics; performance_label.mouse_filter=Control.MOUSE_FILTER_IGNORE; add_child(performance_label)
	siren_network = preload("res://scripts/three_d/warning_network_3d.gd").new()
	siren_network.manager = manager
	siren_network.view = self
	world.add_child(siren_network)
	mouse_exited.connect(_cancel_drag)
	get_window().focus_exited.connect(_cancel_drag)
	get_window().focus_exited.connect(func(): window_active = false)
	get_window().focus_entered.connect(func(): window_active = true)
	mouse_entered.connect(func(): mouse_over = true)
	mouse_exited.connect(func(): mouse_over = false)

func display_run(agents: Array[Dictionary], shelters: Array[Dictionary], reset_camera: bool = true, companions: Array[Dictionary] = []) -> void:
	if manager!=null and manager.social!=null: manager.social.traffic.bind_world(world)
	clear_selection()
	if is_instance_valid(city):
		world.remove_child(city)
		city.queue_free()
	city = CITY.instantiate()
	world.add_child(city)
	city.sun.shadow_enabled = visual_quality == 1
	agent_records=agents; last_occluded.clear()
	for pooled in agent_pool.values(): pooled.queue_free()
	agent_pool.clear()
	for node in agent_nodes + companion_nodes + shelter_nodes:
		world.remove_child(node)
		node.queue_free()
	agent_nodes.clear()
	companion_nodes.clear()
	shelter_nodes.clear()
	for record in shelters:
		if not record["exists"]: continue
		var node: Node3D = SHELTER.instantiate()
		node.configure(record)
		world.add_child(node)
		node.visible=not record.get("hidden_until_discovered",false) or record.get("discovered",false)
		shelter_nodes.append(node)
	for record in companions:
		var node: Node3D = preload("res://scripts/three_d/animal_companion_3d.gd").new()
		node.configure(record)
		world.add_child(node)
		companion_nodes.append(node)
	reset_emergency_visuals()
	if reset_camera: fit_camera()
	city.streamer.configure(camera)
	_refresh_agent_visuals()
	update_impact_marker()
	siren_network.rebuild()
	if social_world!=null: social_world.rebuild()

func sync_run(agents: Array[Dictionary], shelters: Array[Dictionary], alpha: float, running: bool, time: float = 0, companions: Array[Dictionary] = []) -> void:
	if manager != null and manager.phase == "BOMB_FALL" and not is_instance_valid(falling_bomb):
		falling_bomb = preload("res://scripts/three_d/bomb_drop.gd").new()
		falling_bomb.manager = manager
		world.add_child(falling_bomb)
	for node in agent_nodes:
		node.update_visual(node.record,alpha,running,time)
	for index in range(mini(companion_nodes.size(),companions.size())):
		companion_nodes[index].update_visual(companions[index],alpha,running,time)
	for node in shelter_nodes:
		for record in shelters:
			if node.record["id"] == record["id"]:
				node.configure(record)
				node.visible=not record.get("hidden_until_discovered",false) or record.get("discovered",false)
				node.set_interior_power(bool(record.get("power_available",record.get("operational",true))))
				break

func show_warning() -> void:
	clear_preview()
	city.set_warning(true)

func show_impact() -> void:
	if is_instance_valid(falling_bomb): falling_bomb.queue_free()
	falling_bomb = null
	siren_network.impact_audio()
	clear_preview()
	if is_instance_valid(impact_3d): return
	impact_3d = preload("res://scripts/three_d/impact_3d.gd").new()
	if manager != null:
		impact_3d.origin = Coordinates.to_world(Vector2(manager.nuclear["impact_position"][0],manager.nuclear["impact_position"][1]))
		impact_3d.radius = manager.nuclear["radius"]
		city.devastate(manager.structures,manager.nuclear)
	world.add_child(impact_3d)
	impact_effect = preload("res://scripts/impact_effect.gd").new()
	add_child(impact_effect)
	city.set_warning(true)

func reset_emergency_visuals() -> void:
	if is_instance_valid(falling_bomb): falling_bomb.queue_free()
	falling_bomb = null
	clear_preview()
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
	follow_agent = false
	camera_rig.reset_overview()

func pan_camera(direction: Vector2, delta: float) -> void:
	camera_rig.pan(direction,delta)

func focus_selected() -> void:
	if is_instance_valid(selected_node) and selected_node in agent_nodes:
		follow_agent = true
		camera_rig.focus_at(Coordinates.to_world(selected_node.record["position"]))
	elif is_instance_valid(selected_node):
		follow_agent = false
		camera_rig.focus_at(Coordinates.to_world(selected_node.record["position"]))

func focus_landmark(kind: String) -> void:
	follow_agent = false
	if kind == "Nuclear impact":
		camera_rig.focus_at(Coordinates.to_world(Vector2(manager.nuclear["impact_position"][0],manager.nuclear["impact_position"][1])))
	else:
		for poi in manager.points_of_interest:
			if poi["kind"] == kind: camera_rig.focus_at(Coordinates.to_world(poi["footprint"].get_center()))
	camera_rig.target_distance = 65.0

func _cancel_drag() -> void:
	dragging_pan = false

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
		if not direction.is_zero_approx(): follow_agent = false
		camera_rig.pan(direction,delta)
	if follow_agent and is_instance_valid(selected_node):
		camera_rig.focus_at(selected_node.global_position)
	camera_rig.advance(delta)
	if city==null: return
	visual_age+=delta; occlusion_age+=delta; metrics_age+=delta
	if visual_age>=float(render_config.update_interval): visual_age=0; _refresh_agent_visuals()
	if occlusion_age>=float(render_config.occlusion_interval):
		occlusion_age=0
		var targets: Array=[]; targets.append_array(agent_nodes); targets.append_array(shelter_nodes)
		var structures: Array=[]; structures.append_array(city.buildings); structures.append_array(shelter_nodes)
		var obscured: Array=preload("res://scripts/three_d/isometric_visibility.gd").obscured_buildings(camera,world.get_world_3d().direct_space_state,targets,structures,int(render_config.max_occlusion_layers))
		var now:=Time.get_ticks_msec()/1000.0
		for building in obscured: last_occluded[building.get_instance_id()]=now
		var active_ids: Dictionary={}
		for building in structures:
			active_ids[building.get_instance_id()]=true
			building.set_obscured(now-float(last_occluded.get(building.get_instance_id(),-100))<float(render_config.restore_delay))
		for id in last_occluded.keys():
			if not active_ids.has(id): last_occluded.erase(id)
		for shelter in shelter_nodes:
			if shelter.interior_visible: shelter.interior.update_cutaway(camera.global_position)
	if metrics_age>=1:
		metrics_age=0
		var stats: Dictionary=city.streamer.metrics()
		var animation_lod: Dictionary={"full":0,"medium":0,"far":0}
		for avatar in agent_nodes: animation_lod[avatar.animation_lod_tier]=int(animation_lod.get(avatar.animation_lod_tier,0))+1
		performance_label.text="FPS %.0f / CPU process %.2f ms\nAvatars %d / pooled %d / vehicles %d\nAnimation LOD full %d / medium %d / far %d\nChunks %d / pending %d / pooled %d\nDraws %.0f / VRAM %.1f MB\nLoad max %.2f ms / unload max %.2f ms\nObjects %.0f / static memory %.1f MB"%[Performance.get_monitor(Performance.TIME_FPS),Performance.get_monitor(Performance.TIME_PROCESS)*1000,agent_nodes.size(),agent_pool.size(),social_world.cars.size(),animation_lod.full,animation_lod.medium,animation_lod.far,stats.loaded_chunks,stats.pending_chunks,stats.pooled_chunks,Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576,stats.max_load_frame_ms,stats.max_unload_ms,Performance.get_monitor(Performance.OBJECT_COUNT),Performance.get_monitor(Performance.MEMORY_STATIC)/1048576]


func _refresh_agent_visuals() -> void:
	if city==null or city.streamer==null: return
	var active: Dictionary={}
	for node in agent_nodes: active[node.record.id]=node
	var wanted: Dictionary={}
	for record in agent_records:
		if not render_config.enabled or city.streamer.wants_point(record.position) or (is_instance_valid(selected_node) and selected_node.get("record") is Dictionary and selected_node.record.get("id","")==record.id):
			wanted[record.id]=true
			if not active.has(record.id): _ensure_agent(record)
	for node in agent_nodes.duplicate():
		if wanted.has(node.record.id): continue
		agent_nodes.erase(node); node.hide(); node.process_mode=Node.PROCESS_MODE_DISABLED; node.selection_area.collision_layer=0
		agent_pool[node.record.id]=node
	while agent_pool.size()>int(render_config.pooled_agents):
		var id: String=agent_pool.keys()[0]; agent_pool[id].queue_free(); agent_pool.erase(id)

func _ensure_agent(record: Dictionary) -> Node3D:
	for node in agent_nodes:
		if node.record.id==record.id: return node
	var node: Node3D
	if agent_pool.has(record.id):
		node=agent_pool[record.id]; agent_pool.erase(record.id); node.process_mode=Node.PROCESS_MODE_INHERIT
		# Events that happened while absent are current state, not a fresh boarding animation.
		node.visual_initialized=false; node.vehicle_transition=""; node.transition_until=-1
		node.update_visual(record,1,false,manager.elapsed_seconds if manager!=null else 0)
	else:
		node=AGENT.instantiate(); node.configure(record); world.add_child(node)
	agent_nodes.append(node); return node

func _gui_input(event: InputEvent) -> void:
	if camera == null: return
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_MIDDLE:
				dragging_pan = event.pressed
				if event.pressed: grab_focus()
			MOUSE_BUTTON_RIGHT:
				dragging_pan = event.pressed
				if event.pressed: grab_focus()
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed: camera_rig.zoom_steps(1)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed: camera_rig.zoom_steps(-1)
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					grab_focus()
					if impact_selection_enabled and manager != null and manager.phase == "PREPARATION":
						var origin := camera.project_ray_origin(event.position)
						var direction := camera.project_ray_normal(event.position)
						var query := PhysicsRayQueryParameters3D.create(origin,origin+direction*4000,8)
						var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
						if not hit.is_empty(): impact_selected.emit(Coordinates.to_simulation(hit["position"]))
					else:
						select_at(event.position)
					if event.double_click: focus_selected()
			_:
				return
		accept_event()
	elif event is InputEventMouseMotion:
		if dragging_pan:
			follow_agent = false
			camera_rig.drag_pan(event.relative,size.y)
			accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F or event.keycode == KEY_F:
			focus_selected()
			accept_event()
		elif event.physical_keycode == KEY_F10 or event.keycode == KEY_F10:
			performance_label.visible=not performance_label.visible; accept_event()
		elif event.physical_keycode == KEY_HOME or event.keycode == KEY_HOME:
			fit_camera()
			accept_event()
		elif event.physical_keycode == KEY_I or event.keycode == KEY_I:
			_toggle_selected_shelter_interior()
			accept_event()

func _toggle_selected_shelter_interior() -> void:
	if manager==null or manager.phase!="IMPACT" or not is_instance_valid(selected_node) or selected_node not in shelter_nodes: return
	selected_node.toggle_interior()
	if selected_node.interior_visible:
		follow_agent=false
		camera_rig.focus_at(selected_node.global_position+selected_node.interior.position+Vector3(16,1,3))
		camera_rig.target_distance=43.0
	else: camera_rig.focus_at(selected_node.global_position)

func pick_entity(local_point: Vector2) -> Node3D:
	if city==null: return null
	var origin := camera.project_ray_origin(local_point)
	var direction := camera.project_ray_normal(local_point)
	var query := PhysicsRayQueryParameters3D.create(origin,origin+direction*camera.far,1|2|4|16|128)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	for pass_index in range(8):
		if hit.is_empty(): return null
		var obstruction: Node=hit["collider"].get_parent()
		if hit["collider"].has_meta("building_index"): obstruction=city.building_for_index(int(hit["collider"].get_meta("building_index")))
		if obstruction not in city.buildings: break
		if obstruction.fade_amount>.5 and not preload("res://scripts/city_map.gd").interior_cutaway: break
		var exclusions: Array[RID] = query.exclude
		exclusions.append(hit["collider"].get_rid())
		query.exclude = exclusions
		hit = world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return null
	var collider: Object = hit["collider"]
	if collider is Area3D and collider.has_meta("room_id"): return collider
	# Prefer a person inside the gate's generous selection area, while opaque buildings
	# still block the ray. A selection volume is not a solid wall.
	if collider is Area3D and int(collider.collision_layer) == 2:
		query.collision_mask = 1|4
		var agent_hit := world.get_world_3d().direct_space_state.intersect_ray(query)
		if not agent_hit.is_empty() and agent_hit["collider"].has_meta("entity_owner"):
			var candidate: Node3D = agent_hit["collider"].get_meta("entity_owner")
			if candidate in agent_nodes or candidate in companion_nodes: return candidate
	return collider.get_meta("entity_owner") if collider.has_meta("entity_owner") else null

func select_at(local_point: Vector2) -> void:
	clear_selection()
	var node := pick_entity(local_point)
	if node in shelter_nodes and not node.visible: node=null
	if node == null:
		object_selected.emit("none",{})
		return
	if node is Area3D and node.has_meta("room_id"):
		var interior: Node3D=node.get_meta("room_owner")
		var room: Dictionary=interior.select_room(str(node.get_meta("room_id")))
		object_selected.emit("room",room)
		return
	selected_node = node
	follow_agent = node in agent_nodes
	node.set_selected(true)
	object_selected.emit("agent" if node in agent_nodes else "companion" if node in companion_nodes else "siren" if node in siren_network.nodes else "roadblock" if node.has_meta("roadblock") else "shelter",node.record)

func clear_selection() -> void:
	follow_agent = false
	if is_instance_valid(selected_node): selected_node.set_selected(false)
	selected_node = null

func select_shelter(record: Dictionary) -> void:
	clear_selection()
	if record.get("hidden_until_discovered",false) and not record.get("discovered",false):
		object_selected.emit("shelter",record); return
	for node in shelter_nodes:
		if node.record["id"] == record["id"]:
			selected_node = node
			node.set_selected(true)
			break
	object_selected.emit("shelter",record)

func select_agent(record: Dictionary) -> void:
	_ensure_agent(record)
	clear_selection()
	for node in agent_nodes:
		if node.record["id"] == record["id"]:
			selected_node = node
			node.set_selected(true)
			break
	follow_agent=is_instance_valid(selected_node)
	object_selected.emit("agent",record)

func select_companion(record: Dictionary) -> void:
	clear_selection()
	for node in companion_nodes:
		if node.record["id"] == record["id"]:
			selected_node = node
			node.set_selected(true)
			break
	object_selected.emit("companion",record)

func screen_point(node: Node3D, offset: Vector3 = Vector3(0,1.2,0)) -> Vector2:
	return camera.unproject_position(node.global_position+offset)

func update_impact_marker() -> void:
	if manager == null: return
	if is_instance_valid(marker):
		world.remove_child(marker)
		marker.queue_free()
	if is_instance_valid(blast_zones):
		world.remove_child(blast_zones)
		blast_zones.queue_free()
	marker = Node3D.new()
	marker.position = Coordinates.to_world(Vector2(manager.nuclear["impact_position"][0],manager.nuclear["impact_position"][1]))
	world.add_child(marker)
	var geometry = preload("res://scripts/three_d/geometry.gd")
	geometry.ring(marker,3.0,Color("ff694b"))
	geometry.cylinder(marker,0.3,12,Vector3(0,6,0),Color("ffdd91"))
	geometry.label(marker,"IMPACT",Vector3(0,18,0),Color("ffdd91"),64,0.09)
	blast_zones = Node3D.new()
	blast_zones.position = marker.position
	world.add_child(blast_zones)
	for fraction in manager.nuclear["zone_fractions"]:
		geometry.ring(blast_zones,manager.nuclear["radius"]*fraction,Color("ec9e68"))
	blast_zones.visible = show_zones

func clear_preview() -> void:
	for snapshot in preview_visibility:
		if is_instance_valid(snapshot["node"]): snapshot["node"].visible = snapshot["visible"]
	preview_visibility.clear()
	if is_instance_valid(preview_city): preview_city.queue_free()
	preview_city = null
	if is_instance_valid(preview_effect): preview_effect.queue_free()
	preview_effect = null
func preview_nuclear() -> void:
	clear_preview()
	var preview := preload("res://scripts/three_d/impact_3d.gd").new()
	preview.origin = marker.position
	preview.radius = manager.nuclear["radius"]
	world.add_child(preview)
	preview_effect = preview
	# Presentation-only copies. Original collision and navigation remain untouched.
	if manager.phase == "PREPARATION":
		preview_city = Node3D.new()
		world.add_child(preview_city)
		var blast = preload("res://scripts/blast_model.gd")
		for i in range(city.buildings.size()):
			var original: Node3D = city.buildings[i]
			preview_visibility.append({"node": original,"visible": original.visible})
			original.hide()
			var copy: Node3D = preload("res://scenes/three_d/building.tscn").instantiate()
			copy.visual_only=true
			copy.configure(preload("res://scripts/city_map.gd").lots[original.source_index],original.source_index)
			preview_city.add_child(copy)
			for child in copy.get_children():
				if child is StaticBody3D: child.collision_layer = 0
			copy.destroy_to(blast.structure_state(manager.structures[original.source_index]["position"],manager.nuclear),original.position.distance_to(marker.position)/90)
		for object in city.scenery:
			if object is GeometryInstance3D and blast.intensity(Coordinates.to_simulation(object.position),manager.nuclear) > 0:
				preview_visibility.append({"node": object,"visible": object.visible})
				object.hide()
	var preview_id := preview.get_instance_id()
	get_tree().create_timer(8.5).timeout.connect(func():
		if is_instance_valid(preview_effect) and preview_effect.get_instance_id() == preview_id: clear_preview())
