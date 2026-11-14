extends SceneTree
const Geometry=preload("res://scripts/three_d/geometry.gd")
var checks:=0
var failures:=0

func _initialize() -> void: run.call_deferred()

func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1; printerr("FAIL: "+label)

func run() -> void:
	var world:=Node3D.new(); root.add_child(world)
	Geometry.begin_world("rendering-test")
	var box_a:=Geometry.box(world,Vector3(1,1,1),Vector3.ZERO,Color("aa8866"))
	var box_b:=Geometry.box(world,Vector3(1,1,1),Vector3(2,0,0),Color("aa8866"))
	check(box_a.mesh==box_b.mesh,"matching procedural boxes reuse the same mesh")
	check(box_a.material_override==box_b.material_override,"matching geometry shares immutable materials")
	Geometry.make_material_unique(box_a)
	box_a.material_override.albedo_color=Color.RED
	check(box_b.material_override.albedo_color==Color("aa8866"),"runtime material changes stay local after copy-on-write")
	var cylinder_a:=Geometry.cylinder(world,.3,.5,Vector3.ZERO,Color("303030"))
	var cylinder_b:=Geometry.cylinder(world,.3,.5,Vector3(2,0,0),Color("303030"))
	check(cylinder_a.mesh==cylinder_b.mesh,"matching cylinders reuse their mesh resource")
	var facade=preload("res://scripts/three_d/environment_textures.gd").facade_material(Color("938875"))
	check(facade.albedo_texture!=null and facade.albedo_texture.get_image().has_mipmaps(),"procedural stone facade textures include a shared mip chain")
	var masonry=preload("res://scripts/three_d/reference_architecture.gd").brick_material(Color("865744"))
	var brick_wall:=Geometry.box(world,Vector3(2,3,1),Vector3(20,1.5,0),Color.WHITE); brick_wall.material_override=masonry
	var fade=preload("res://scripts/three_d/material_fader.gd").new(); fade.configure(world,{"occlusion_alpha":.2,"fade_seconds":.01}); fade.set_obscured(true)
	await fade.tween.finished
	check(is_equal_approx(brick_wall.material_override.get_shader_parameter("opacity"),.2),"reference masonry fades to reveal hidden agents")
	fade.reset()
	check(brick_wall.material_override==masonry and is_equal_approx(masonry.get_shader_parameter("opacity"),1),"masonry restores without modifying shared material")

	var record:=_agent_record("render-agent-a",Vector2(20,20))
	var first=preload("res://scenes/three_d/agent.tscn").instantiate()
	first.configure(record); world.add_child(first)
	var second_record:=_agent_record("render-agent-b",Vector2(40,20))
	var second=preload("res://scenes/three_d/agent.tscn").instantiate()
	second.configure(second_record); world.add_child(second)
	await process_frame
	check(first.body.get_node_or_null("Skeleton") is Skeleton3D,"characters use a reusable Skeleton3D pivot rig")
	var rig: Skeleton3D=first.body.get_node("Skeleton")
	check(rig.get_bone_global_pose(rig.find_bone("Head")).origin.y>1.9,"head pose sits above torso rather than at the root")
	check(rig.get_bone_global_pose(rig.find_bone("ArmLeft")).origin.x<-.4 and rig.get_bone_global_pose(rig.find_bone("ArmRight")).origin.x>.4,"arm poses retain shoulder separation")
	check(first.animation_tree.active and first.animation_tree.tree_root is AnimationNodeStateMachine,"each character has an active AnimationTree")
	check(first.animation_player.get_animation_library("character")==second.animation_player.get_animation_library("character"),"character clips are shared while playback remains per-agent")
	first_record_move(first,record)
	for i in range(15): await process_frame
	var playback: AnimationNodeStateMachinePlayback=first.animation_tree.get("parameters/playback")
	check(playback!=null and playback.get_current_node()=="walk","walking records select the shared walk clip")
	check(absf(first.arms[0].rotation.x)+absf(first.legs[0].rotation.x)>.05 and second.animation_tree.get("parameters/playback").get_current_node()=="idle","per-agent playback animates its rig without changing another agent")
	check(record.position==Vector2(20,20),"render animation does not move the authoritative agent record")
	var camera:=Camera3D.new(); world.add_child(camera); camera.position=Vector3(0,0,220); camera.current=true
	await process_frame
	check(first.animation_lod_tier=="far","distant avatars use the reduced animation update tier")

	var vehicle:=preload("res://scripts/three_d/vehicle_3d.gd").new()
	var car_record: Dictionary={"id":"test-fire-engine","kind":"Fire","model":"fire_engine","length":85.0,"width":25.0,"body_height":3.0,"health":100.0,"status":"MOVING","speed":24.0,"heading":0.0,"steering":.28,"siren_active":true}
	vehicle.configure(car_record); world.add_child(vehicle); await process_frame
	vehicle.sync_vehicle(car_record,.2)
	check(vehicle.imported_model_root!=null and vehicle.imported_wheels.size()==4 and vehicle.wheel_is_front.count(true)==2,"3D vehicles use the imported fire truck body and four named wheel meshes")
	check(absf(vehicle.wheel_phase)>.01,"wheel spin follows simulation speed")
	var rear_index: int=vehicle.wheel_is_front.find(false)
	var front_index: int=vehicle.wheel_is_front.find(true)
	var rear_transform: Transform3D=vehicle.imported_wheels[rear_index].transform
	var front_transform: Transform3D=vehicle.imported_wheels[front_index].transform
	check(is_equal_approx(vehicle.wheel_steering,.28) and not rear_transform.basis.is_equal_approx(front_transform.basis),"imported front wheels follow steering while rear wheels remain aligned")
	check(vehicle.lamps["siren_red"].material_override.emission_energy_multiplier>0 or vehicle.lamps["siren_blue"].material_override.emission_energy_multiplier>0,"emergency lights activate only when the vehicle record requests a siren")
	car_record.health=10.0; car_record.status="DESTROYED"; vehicle.sync_vehicle(car_record,.1)
	check(vehicle.smoke!=null and vehicle.fire!=null and vehicle.smoke.emitting and vehicle.fire.emitting,"severe wrecks add local smoke and fire effects")

	world.queue_free(); await process_frame
	print("Rendering architecture: %d checks / %d failures"%[checks,failures])
	quit(1 if failures else 0)

func _agent_record(id: String,point: Vector2) -> Dictionary:
	return {"id":id,"display_name":id,"position":point,"previous_position":point,"population_index":1,"appearance_seed":123,"role":"Civilian","state":"ROAMING","route":PackedVector2Array([point+Vector2(50,0)]),"route_index":0,"riding":"","health":100.0,"survival_status":"ALIVE","personal_memory":{},"family_id":"","free_movement":true}

func first_record_move(agent: Node,record: Dictionary) -> void:
	var moved:=record.duplicate(true)
	moved.state="ROAMING"
	moved.previous_position=record.position
	moved.position=record.position+Vector2(5,0)
	agent.update_visual(moved,1.0,true,1.0)
