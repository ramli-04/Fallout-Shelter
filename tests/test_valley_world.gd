extends SceneTree
const Map = preload("res://scripts/city_map.gd")
const Manager = preload("res://scripts/simulation_manager.gd")
const Admission = preload("res://scripts/shelter_admission.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: "+label)
func run() -> void:
	for seed_value in [42,43,91]:
		Map.generate(seed_value)
		check(Map.graph.get_point_count() == 65,"connected junction and shelter network")
		for id in Map.graph.get_point_ids(): check(not Map.graph.get_id_path(0,id).is_empty(),"all junctions connected")
		var slots := Map.spawn_slots()
		check(slots.size() >= 400,"120 agents and extra population fit")
		for i in range(0,slots.size(),maxi(1,int(slots.size()/15))):
			for destination in Map.sites.values():
				var path := Map.free_route(slots[i],destination)
				check(path.size() >= 2,"all five shelter approaches reachable")
				for j in range(1,path.size()): check(Map.clear_segment(path[j-1],path[j]),"routes avoid buildings, lake and vault rock")
		for edge in Map.roads:
			var pts: PackedVector2Array = edge["points"]
			for point in pts:
				for rect in Map.lots:
					if rect.grow(20).has_point(point): check(false,"street crosses building")
		check(Map.lot_angles.any(func(a): return absf(sin(a*2)) > 0.3),"diagonal building orientations")
	var sim := Manager.new()
	root.add_child(sim)
	sim.set_process(false)
	check(sim.load_settings(),"expanded configuration accepted")
	sim.ai_config["enabled"] = false
	sim.new_run(42)
	for agent in sim.agents:
		for site in Map.sites.values(): check(not Map.free_route(agent["position"],site).is_empty(),"actual seeded agent can reach each shelter")
	var city = preload("res://scenes/three_d/city.tscn").instantiate()
	root.add_child(city)
	var visuals := []
	for record in sim.shelters:
		if not record["exists"]: continue
		var shelter = preload("res://scenes/three_d/shelter.tscn").instantiate()
		shelter.configure(record)
		root.add_child(shelter)
		visuals.append(shelter)
		check(shelter.vault.name == "FloorVault" if record["id"] in ["S1","S2","S3"] else shelter.vault.name != "FloorVault","correct entrance type")
		shelter.vault.door.set_state("CLOSED")
		check(shelter.vault.door.blocker.collision_layer == 1,"closed door blocks physics")
		var agent: Dictionary = sim.agents[0].duplicate(true)
		agent["position"] = record["position"]
		var closed: Dictionary = record.duplicate(true)
		closed["door_status"] = "CLOSED"
		check(not Admission.try_admit(agent,closed,true).is_empty(),"closed door denies admission")
	await create_timer(1.25).timeout
	for shelter in visuals:
		check(absf(shelter.vault.door.plate.position.x) < 0.01,"closing animation completes")
		shelter.vault.door.set_state("OPEN")
	await create_timer(1.25).timeout
	for shelter in visuals:
		check(shelter.vault.door.plate.position.x > 4,"open plate clears access")
		check(shelter.vault.door.blocker.collision_layer == 0,"open physics threshold")
	sim.start()
	sim.launch_nuke()
	sim._trigger_impact()
	check(sim.phase == "IMPACT" and sim.summary.has("survivors"),"impact and survival resolve")
	city.devastate(sim.structures,sim.nuclear)
	for shelter in visuals:
		shelter.configure(sim.shelter_by_id[shelter.record["id"]])
		check(shelter.vault.door.target_state == "DESTROYED" if shelter.record["structural_state"] == "DESTROYED" else true,"destruction feeds both door types")
	var count: int = city.buildings.size()
	sim.new_run(42)
	check(Map.lots.size() == count and sim.phase == "PREPARATION","reset reproduces geography")
	check(sim.shelter_by_id["S5"]["existence_probability"] == 0.5,"secret shelter probability preserved")
	var view = preload("res://scripts/map_view_3d.gd").new()
	view.manager = sim
	root.add_child(view)
	var scenario: Array[Dictionary] = sim.shelters.duplicate(true)
	for record in scenario:
		if record["id"] == "S5": record["exists"] = false
	view.display_run(sim.agents,scenario)
	check(view.shelter_nodes.size() == 4 and view.shelter_nodes.all(func(n): return n.record["id"] != "S5"),"absent S5 creates no entrance")
	var original_city: Node3D = view.city
	view.select_agent(sim.agents[0])
	check(view.city == original_city,"selection does not rebuild or resurrect city")
	view.focus_landmark("School")
	check(view.camera_rig.target_distance == 65,"public building focus")
	view.select_shelter(sim.shelters[0])
	view.focus_selected()
	check(not view.follow_agent,"shelter focus does not follow an agent")
	view.camera_rig.pan(Vector2(1,1),1000)
	check(view.camera_rig.target_focus.x <= Map.MAP_SIZE.x*0.1 and view.camera_rig.target_focus.z <= Map.MAP_SIZE.y*0.1,"camera remains in useful bounds")
	view.queue_free()
	for shelter in visuals: shelter.queue_free()
	city.queue_free()
	sim.queue_free()
	await process_frame
	print("Valley world: %d checks / %d failures"%[checks,failures])
	quit(1 if failures else 0)

