extends SceneTree
const Visibility = preload("res://scripts/three_d/isometric_visibility.gd")
const G = preload("res://scripts/three_d/geometry.gd")
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: "+label)
func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800,600)
	viewport.own_world_3d = true
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 30
	world.add_child(camera)
	camera.position = Vector3(20,20,20)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var agent := Node3D.new()
	world.add_child(agent)
	agent.position = Vector3(7,0,-3)
	var target := agent.position+Vector3.UP
	var ray: PhysicsRayQueryParameters3D = Visibility.sightline(camera,target)
	check((target-ray.from).normalized().dot(-camera.global_basis.z)>.9999,"off-center sightline is parallel to camera forward")
	var buildings: Array = []
	for distance in [4.0,8.0]:
		var building := preload("res://scripts/three_d/building_3d.gd").new()
		world.add_child(building)
		building.position = target+camera.global_basis.z*distance
		var nested := Node3D.new()
		building.add_child(nested)
		G.box(nested,Vector3(2,2,2),Vector3.ZERO,Color.WHITE)
		G.collider(nested,Vector3(2,2,2),Vector3.ZERO)
		buildings.append(building)
	await physics_frame; await physics_frame
	var hits := Visibility.obscured_buildings(camera,world.get_world_3d().direct_space_state,[agent],buildings)
	check(hits.size()==2,"both overlapping buildings detected in independent viewport")
	for building in buildings:
		building.set_obscured(true)
		check(building.fade_materials.size()==1 and building.fade_materials[0].albedo_color.a<.2,"nested facade fades")
		building.set_obscured(false)
		check(building.fade_materials[0].albedo_color.a==1,"facade opacity restores")
	check(Visibility.obscured_buildings(camera,root.world_3d.direct_space_state,[agent],buildings).is_empty(),"view colliders do not leak into root world")
	var weathering := preload("res://scripts/three_d/building_weathering.gd").new()
	weathering.configure(Vector2(12,10),8,42)
	check(weathering.instance_total>10 and weathering.get_child_count()==3,"weathering batches geometry into three draw groups")
	weathering.free()
	viewport.queue_free(); await process_frame
	var app: Node = preload("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false); app.manager.set_process(false); app.manager.ai_bridge.set_process(false)
	app.manager.ai_config.enabled=false; app.manager.social.close(); app.manager.social.next_send=INF
	check(app.manager.agents.size()==100,"population preserved")
	var avatar: Node3D = app.map_view.agent_nodes[0]
	var record: Dictionary = avatar.record.duplicate(true)
	record.riding=""; record.state="CHATTING"; record.shelter_life_active=false
	avatar.update_visual(record,1,true,10); avatar._process(.02)
	check(avatar.animation_state=="talking","talk pose follows real state")
	record.riding="test-car"
	avatar.update_visual(record,1,true,11); avatar._process(.02)
	check(avatar.animation_state=="entering_vehicle" and avatar.visible,"board transition pose")
	avatar.update_visual(record,1,true,12)
	check(not avatar.visible,"rider hides after transition")
	record.riding=""
	avatar.update_visual(record,1,true,13); avatar._process(.02)
	check(avatar.animation_state=="exiting_vehicle" and avatar.visible,"disembark transition pose")
	var rig: Node3D=app.map_view.camera_rig
	rig.focus_at(Vector3(20,18,20))
	check(is_equal_approx(rig.target_focus.y,18),"follow preserves elevated interior height")
	for shelter in app.map_view.shelter_nodes:
		check(shelter.has_node("IdentityDetails"),"shelter has identity fixtures")
		if shelter.record.id in ["S4","S5"]: check(shelter.vault.position.z<0,"hill vault approach faces visible foreground")
	app.queue_free(); await process_frame; await process_frame
	print("Phase 2 visuals: %d checks / %d failures"%[checks,failures])
	quit(1 if failures else 0)
