extends SceneTree
const Map=preload("res://scripts/city_map.gd")
const C=preload("res://scripts/three_d/world_coordinates.gd")
const G=preload("res://scripts/three_d/geometry.gd")
const Visibility=preload("res://scripts/three_d/isometric_visibility.gd")
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1; printerr("FAIL: "+label)
func settle(view: Node) -> void:
	view.city.streamer.refresh(); view._refresh_agent_visuals()
	for i in range(500):
		await process_frame
		if view.city.streamer.queue.is_empty(): break
func run() -> void:
	var options: Dictionary=preload("res://scripts/three_d/render_options.gd").normalize({"chunk_size":650,"unload_distance":0,"fade_seconds":-1})
	check(options.chunk_size==600 and options.unload_distance>options.preload_distance and options.fade_seconds>0,"configuration keeps chunk grids and hysteresis valid")
	var manager=preload("res://scripts/simulation_manager.gd").new(); root.add_child(manager); manager.set_process(false)
	check(manager.load_settings(),"existing simulation settings")
	manager.social_config.llm_agents=0; manager.social_config.spontaneous_actions=false; manager.social_config.automatic_warning=false
	manager.ai_bridge.set_process(false); manager.generate_world(42,{"preset":"large"})
	check(await manager.world.completed,"shelter-first world initializes existing agents")
	var view=preload("res://scripts/map_view_3d.gd").new(); view.manager=manager; view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.add_child(view)
	view.display_run(manager.agents,manager.shelters,true,manager.social.companions)
	var metric_key:=InputEventKey.new(); metric_key.keycode=KEY_F10; metric_key.pressed=true
	view._gui_input(metric_key)
	check(view.performance_label.visible and view.performance_label.mouse_filter==Control.MOUSE_FILTER_IGNORE,"F10 metrics do not intercept map interaction")
	view._gui_input(metric_key)
	check(view.city.buildings.is_empty() and view.agent_nodes.is_empty(),"startup overview does not instantiate detailed buildings or every avatar")
	var source: Dictionary=manager.agents.filter(func(a):return a.role=="Civilian")[0]
	var original: Array=manager.agents.map(func(a):return [a.id,a.position,a.health,a.state,a.personal_memory.duplicate(true)])
	view.camera_rig.focus_at(C.to_world(source.position)); view.camera_rig.target_distance=65; view.camera_rig.snap()
	await settle(view)
	check(view.city.streamer.building_nodes.size()>0 and view.city.buildings.size()<Map.lots.size(),"only visible/near detailed buildings are resident")
	check(view.agent_nodes.any(func(node):return node.record.id==source.id),"visible agent avatar reconstructs from actual record")
	check(view.city.collision.buildings.size()==Map.lots.size(),"collision structures persist for every building")
	var physics_ids: Array=view.city.collision.buildings.values().map(func(node):return node.get_instance_id())
	var first_keys: Array=view.city.streamer.building_nodes.keys()
	await physics_frame; await process_frame
	for i in range(12):
		var xy: Vector2=Map.MAP_SIZE*Vector2(.15+float(i%4)*.22,.2+float(i/4)*.23)
		var query:=PhysicsRayQueryParameters3D.create(Vector3(xy.x*.1,200,xy.y*.1),Vector3(xy.x*.1,-100,xy.y*.1),8)
		var hit: Dictionary=view.world.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty() and absf(hit.position.y-Map.elevation(xy))<.01,"persistent terrain matches authoritative heights and triangle diagonals")
	for index in view.city.streamer.building_nodes:
		var node: Node=view.city.streamer.building_nodes[index]
		check(node.get_children().all(func(child):return not child is StaticBody3D),"streamed facade does not duplicate collision bodies")
	for point in [Map.MAP_SIZE*Vector2(.9,.1),Map.MAP_SIZE*Vector2(.1,.9),source.position,Map.MAP_SIZE*.5,source.position]:
		view.camera_rig.focus_at(C.to_world(point)); view.camera_rig.snap(); await settle(view)
		check(manager.agents.map(func(a):return [a.id,a.position,a.health,a.state,a.personal_memory.duplicate(true)])==original,"camera loading does not mutate simulation state")
		check(view.city.buildings.size()==view.city.streamer.building_nodes.size(),"no duplicated active building identities")
		check(view.city.collision.buildings.values().map(func(node):return node.get_instance_id())==physics_ids,"camera unloading preserves physical geometry")
		check(view.city.streamer.pool.size()<=int(view.render_config.pooled_chunks) and view.agent_pool.size()<=int(view.render_config.pooled_agents),"pool memory is bounded")
	check(view.city.streamer.unloads>0,"distant visual chunks release resources")
	check(view.agent_nodes.any(func(node):return node.record.id==source.id),"agent returns after repeated visibility transitions")
	var records_before: Array=manager.agents.map(func(a):return a.position)
	manager.start()
	for i in range(30): manager.advance_clock(.1)
	view.sync_run(manager.agents,manager.shelters,1,true,manager.elapsed_seconds,manager.social.companions)
	check(manager.elapsed_seconds>2.9 and manager.agents.size()==100,"all 100 simulation entities continue on fixed clock")
	check(manager.agents.any(func(a):return a.position!=records_before[manager.agents.find(a)] and not view.agent_nodes.any(func(node):return node.record.id==a.id)),"off-screen agent moves without an avatar")
	check(view.social_world.vehicle_bodies.size()==manager.social.vehicles.size(),"vehicle collision representations persist across visual boundaries")
	for vehicle in manager.social.vehicles:
		check(vehicle.position.is_finite(),"vehicles remain simulated across chunk boundaries")
	var emergency: String=manager.add_emergency("POLICE_SHELTER_EVACUATION",source.position,{"radius":300,"duration":1200})
	manager.advance_clock(.1)
	check(not manager.social.evacuation.operation(emergency).is_empty(),"real police/shelter evacuation remains integrated")
	manager.pause(); await occlusion_fixture()
	var damaged_index: int=view.city.buildings[0].source_index
	var damage_records: Array=manager.structures.duplicate(true); damage_records[damaged_index].destruction_state="DESTROYED"
	view.city.devastate(damage_records,manager.nuclear)
	view.camera_rig.focus_at(C.to_world(Map.MAP_SIZE*Vector2(.9,.05))); view.camera_rig.snap(); await settle(view)
	view.camera_rig.focus_at(C.to_world(Map.lots[damaged_index].get_center())); view.camera_rig.snap(); await settle(view)
	var restored: Node3D=view.city.building_for_index(damaged_index)
	check(restored!=null and restored.destruction_state=="DESTROYED" and is_equal_approx(restored.scale.y,.08),"damage reconstructs from persistent records after visual unloading")
	check(view.city.collision.buildings[damaged_index].get_children().all(func(body):return not body is StaticBody3D or body.collision_layer==0),"damage applies consistently to persistent collision bodies")
	view.queue_free(); manager.queue_free(); await process_frame
	print("Visual streaming: %d checks / %d failures"%[checks,failures]); quit(1 if failures else 0)

func occlusion_fixture() -> void:
	var viewport:=SubViewport.new(); viewport.size=Vector2i(800,600); viewport.own_world_3d=true; root.add_child(viewport)
	var world:=Node3D.new(); viewport.add_child(world)
	var camera:=Camera3D.new(); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=30; world.add_child(camera)
	camera.position=Vector3(12,12,12); camera.look_at(Vector3.ZERO)
	var building=preload("res://scripts/three_d/building_3d.gd").new(); building.source_index=999; building.set_meta("building_index",999); world.add_child(building)
	var mesh:=G.box(building,Vector3(6,8,6),Vector3(0,4,0),Color("8a795f")); mesh.material_override.roughness=.31
	var original_material: StandardMaterial3D=mesh.material_override
	var shared_mesh:=BoxMesh.new(); shared_mesh.material=G.material(Color("a39070"))
	var imported:=MeshInstance3D.new(); imported.mesh=shared_mesh; building.add_child(imported)
	var neighbor:=MeshInstance3D.new(); neighbor.mesh=shared_mesh; world.add_child(neighbor); neighbor.position.x=20
	var body:=G.collider(world,Vector3(6,8,6),Vector3(0,4,0)); body.set_meta("building_index",999)
	var rid: RID=body.get_rid(); var layer: int=body.collision_layer
	var a:=Node3D.new(); a.position=Vector3(-5,0,-5); world.add_child(a)
	var b:=Node3D.new(); b.position=Vector3(-6,0,-5); world.add_child(b)
	await physics_frame; await process_frame
	var space: PhysicsDirectSpaceState3D=world.get_world_3d().direct_space_state
	check(Visibility.obscured_buildings(camera,space,[a,b],[building]).has(building),"orthographic camera rays detect multiple agents behind a building")
	check(Visibility.obscured_buildings(camera,space,[b],[building]).has(building),"one remaining conflict keeps building obstructed")
	building.set_obscured(true)
	building.fader.tween.pause(); building.fader.tween.custom_step(.10)
	check(mesh.material_override.albedo_color.a<1 and mesh.material_override.albedo_color.a>.18,"fade transitions smoothly")
	building.fader.tween.play()
	await create_timer(.25).timeout
	check(is_equal_approx(mesh.material_override.albedo_color.a,float(building.fade_settings.occlusion_alpha)),"configurable transparent target reached")
	check(imported.get_surface_override_material(0)!=null and is_equal_approx(shared_mesh.material.albedo_color.a,1),"surface materials fade locally without modifying shared mesh materials")
	building.set_obscured(false); await create_timer(.08).timeout
	var partial: float=mesh.material_override.albedo_color.a
	building.set_obscured(true)
	check(is_equal_approx(mesh.material_override.albedo_color.a,partial),"interrupted transition does not reset opacity or flicker")
	building.set_obscured(false); await create_timer(.35).timeout
	check(mesh.material_override==original_material and original_material.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED and is_equal_approx(original_material.roughness,.31),"exact original material restored")
	check(imported.get_surface_override_material(0)==null and neighbor.mesh.material==shared_mesh.material,"original per-surface override state restored")
	check(body.get_rid()==rid and body.collision_layer==layer,"fading never changes physical collision geometry")
	camera.position=Vector3(-12,12,-12); camera.look_at(Vector3.ZERO)
	check(Visibility.obscured_buildings(camera,space,[a,b],[building]).is_empty(),"changing camera viewpoint removes conflict without world-axis rules")
	viewport.queue_free(); await process_frame
