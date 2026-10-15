extends SceneTree
const MAIN = preload("res://scenes/main.tscn")
const Blast = preload("res://scripts/blast_model.gd")
const Observation = preload("res://scripts/agent_observation.gd")
const Admission = preload("res://scripts/shelter_admission.gd")
const State = preload("res://scripts/shelter_state.gd")
var checks := 0
var failures := 0
func check(value: bool, name: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: "+name)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var app = MAIN.instantiate()
	root.add_child(app)
	var sim = app.manager
	var view = app.map_view
	sim.set_process(false)
	# Keep the historical 150-person/POI regression scenario explicit.
	sim.ai_config["experiment_preset"] = "legacy"
	sim.settings["agent_count"] = 150
	sim.ai_config["enabled"] = false
	sim.initialize_run()
	for i in range(120):
		await physics_frame
		await process_frame
		var warmup: PackedVector3Array = view.city.navigation_region.path_between(view.agent_nodes[0].position,view.shelter_nodes[0].position)
		if warmup.size() >= 2: break
	check(Blast.validate(sim.nuclear).is_empty(),"nuclear configuration validates")
	var invalid: Dictionary = sim.nuclear.duplicate(true)
	invalid["zone_fractions"] = [0.8,0.2,1.0]
	check(not Blast.validate(invalid).is_empty(),"invalid zones rejected")
	check(sim.CityMap.MAP_SIZE == Vector2(4500,2700),"2.5x dimensions")
	check(sim.shelters.size() == 5,"five definitions")
	check(sim.points_of_interest.size() == 5,"five POIs")
	check(sim.agents.any(func(a): return a["initial_location"].begins_with("POI")),"POI population")
	check(view.city.buildings.size() == sim.structures.size(),"visual and gameplay building registry")
	for poi in sim.points_of_interest:
		check(view.city.buildings.any(func(b): return b.footprint == poi["footprint"]),"physical POI footprint "+poi["kind"])
	var nav = view.city.navigation_region
	var path: PackedVector3Array = nav.path_between(view.agent_nodes[0].position,view.shelter_nodes[0].position)
	check(path.size() >= 2,"real navigation connected")
	var footprints = sim.CityMap.building_rects()
	for agent in sim.agents:
		for shelter in sim.shelters:
			var route = sim.Routes.plan(agent["position"],shelter["position"])
			var clear := true
			for i in range(1,route.size()):
				for t in [0.0,0.25,0.5,0.75,1.0]:
					var point: Vector2 = route[i-1].lerp(route[i],t)
					for rect in footprints:
						clear = clear and not rect.grow(5).has_point(point)
			check(clear,"route avoids building footprints")
	var before: Array = sim.shelters.duplicate(true)
	var agents_before: Array = sim.agents.duplicate(true)
	sim.preview_damage()
	view.preview_nuclear()
	check(before == sim.shelters and agents_before == sim.agents,"preview never mutates model")
	view.impact_selection_enabled = true
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	var target := Vector2(1260,720)
	click.position = view.camera.unproject_position(preload("res://scripts/three_d/world_coordinates.gd").to_world(target))
	view._gui_input(click)
	check(Vector2(sim.nuclear["impact_position"][0],sim.nuclear["impact_position"][1]).distance_to(target) < 0.01,"click ray selects impact coordinates")
	view.impact_selection_enabled = false
	check(sim.set_impact(sim.shelter_by_id["S1"]["position"]),"impact selectable in preparation")
	sim.nuclear["radius"] = 80.0
	var prediction = sim.preview_damage()
	check(prediction[0]["structural_state"] == "DESTROYED","near shelter destroyed")
	check(prediction[3]["structural_state"] == "INTACT","remote shelter survives")
	var payload := JSON.stringify(Observation.generate(sim,sim.agents[0]))
	check(not payload.contains("impact_position") and not payload.contains("blast_resistance") and not payload.contains("structural_state"),"LLM hidden-state isolation")
	sim.nuclear["random_impact"] = true
	sim.initialize_run()
	var location: Array = sim.nuclear["impact_position"].duplicate()
	sim.initialize_run()
	check(location == sim.nuclear["impact_position"],"seeded random impact reproducible")
	sim.nuclear["random_impact"] = false
	sim.set_impact(sim.shelter_by_id["S1"]["position"])
	sim.agents[0]["state"] = "SHELTERED"
	sim.agents[0]["shelter_id"] = "S1"
	sim.shelter_by_id["S1"]["occupant_ids"].append(sim.agents[0]["id"])
	sim.shelter_by_id["S1"]["occupancy"] = 1
	sim.launch_nuke()
	sim.alarm_is_real = true
	check(not sim.set_impact(Vector2.ZERO),"impact frozen after start")
	sim.advance_clock(sim.countdown_seconds-0.1)
	check(sim.phase == "EVACUATION","no early impact")
	sim.advance_clock(0.2)
	check(sim.phase == "IMPACT" and is_equal_approx(sim.elapsed_seconds,sim.countdown_seconds),"impact clock exact")
	check(sim.shelter_by_id["S1"]["structural_state"] == "DESTROYED","actual shelter damage")
	check(sim.agents[0]["survival_status"] == "DEAD","destroyed shelter occupants unsafe")
	check(sim.agents.size() == 150 and not sim.events.is_empty(),"records and event history retained")
	sim.finish_archives()
	var archived: Variant = JSON.parse_string(FileAccess.get_file_as_string(sim.last_archive_path))
	check(archived is Dictionary and archived["agents"].size() == 150 and archived["summary"]["dead"] > 0,"automatic full experiment archive")
	check(sim.summary["destroyed_shelters"] > 0 and sim.summary["dead"] > 0,"metrics include damage and death")
	State.refresh(sim.shelter_by_id["S1"],[])
	check(sim.shelter_by_id["S1"]["door_status"] == "DESTROYED","refresh cannot reopen ruins")
	check(Admission.try_admit(sim.agents[1],sim.shelter_by_id["S1"],true) != "","destroyed admission rejected")
	check(is_instance_valid(view.impact_3d),"real visual sequence created")
	check(view.city.buildings.any(func(b): return b.destruction_state == "DESTROYED"),"visual destruction connected")
	for b in view.city.buildings:
		if b.destruction_state == "DESTROYED":
			check(b.get_children().filter(func(c): return c is StaticBody3D).all(func(c): return c.collision_layer == 0),"ruins no invisible wall")
	view.select_shelter(sim.shelter_by_id["S1"])
	check(app.details.text.contains("DESTROYED") and app.details.text.contains("Blast distance"),"accurate director inspection")
	app._export_trace()
	var trace: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://essaim_trace_%d.json" % sim.seed_value))
	check(trace is Dictionary and trace.has("nuclear") and trace.has("structures") and trace["summary"]["dead"] > 0,"JSON export experimental state")
	sim.initialize_run()
	check(not is_instance_valid(view.impact_3d) and view.city.buildings.all(func(b): return b.destruction_state == "INTACT"),"reset rebuilds city")
	sim.launch_nuke(true)
	sim.advance_clock(1000)
	check(sim.phase == "ALL_CLEAR" and not is_instance_valid(view.impact_3d),"second run and false alarm")
	for seed in range(12):
		sim.new_run(seed)
		check(view.shelter_nodes.size() == sim.shelters.filter(func(sh): return sh["exists"]).size(),"S5 physical existence")
	check(view.shelter_nodes.all(func(sh): return sh.vault.door.STATES.size() == 6),"six reusable door states")
	var door = view.shelter_nodes[0].vault.door
	door.set_state("CLOSED")
	check(door.state == "CLOSING","door closing transition")
	await create_timer(1.0).timeout
	check(door.state == "CLOSED" and absf(door.plate.position.x) < 0.01,"door closes independently")
	door.set_state("OPEN")
	check(door.state == "OPENING","door opening transition")
	await create_timer(1.0).timeout
	check(door.state == "OPEN" and door.plate.position.x > 4,"door reopens independently")
	var config: Dictionary = sim.nuclear.duplicate(true)
	var shelter: Dictionary = sim.shelter_by_id["S2"].duplicate(true)
	config["impact_position"] = [shelter["position"].x,shelter["position"].y]
	config["severity"] = 0.4
	Blast.apply(shelter,config)
	check(shelter["structural_state"] == "DAMAGED" and shelter["capacity"] < shelter["nominal_capacity"] and shelter["door_status"] == "JAMMED","damage reduces capacity and jams door")
	for map_scale in [2.0,2.5,3.0]:
		sim.nuclear["map_scale"] = map_scale
		sim.initialize_run()
		check(sim.CityMap.MAP_SIZE == Vector2(1800,1080)*map_scale,"map preset dimensions")
		check(sim.points_of_interest.size() == 5 and view.city.buildings.size() == sim.structures.size(),"preset preserves POI registry and city")
	sim.nuclear["map_scale"] = 2.5
	sim.initialize_run()
	var access: Dictionary = sim.shelter_by_id["S1"].duplicate(true)
	var applicant: Dictionary = sim.agents[0].duplicate(true)
	applicant["state"] = "DECIDING"
	applicant["shelter_id"] = ""
	applicant["position"] = access["position"]
	for door_state in ["CLOSING","CLOSED","OPENING","JAMMED","DESTROYED"]:
		check(State.set_door_state(access,door_state),"logical door command accepted")
		State.refresh(access,[])
		check(Admission.try_admit(applicant,access,true) != "","non-open door denies real admission")
	var same_seed: int = sim.seed_value
	sim.nuclear["severity"] = 1.0
	sim.nuclear["radius"] = 200
	sim.nuclear["random_impact"] = true
	sim.new_run(same_seed)
	sim.launch_nuke()
	sim.alarm_is_real = true
	sim.advance_clock(1000)
	var first_summary: Dictionary = sim.summary.duplicate(true)
	var first_states: Array = sim.shelters.duplicate(true)
	sim.new_run(same_seed)
	sim.launch_nuke()
	sim.alarm_is_real = true
	sim.advance_clock(1000)
	check(sim.summary == first_summary and sim.shelters == first_states,"same-seed full destruction replay")
	app.queue_free()
	await process_frame
	print("Phase 3.5: %d checks / %d failures" % [checks,failures])
	quit(1 if failures else 0)
