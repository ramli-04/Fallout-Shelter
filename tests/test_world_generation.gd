extends SceneTree
const Manager=preload("res://scripts/simulation_manager.gd")
const Map=preload("res://scripts/city_map.gd")
const Navigation=preload("res://scripts/vehicle_navigation.gd")
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures+=1; printerr("FAIL: "+label)
func run() -> void:
	var manager:=Manager.new(); root.add_child(manager); manager.set_process(false)
	check(manager.load_settings(),"existing settings load")
	manager.social_config.llm_agents=0; manager.social_config.automatic_warning=false
	manager.ai_bridge.set_process(false)
	check(manager.generate_world(42,{"preset":"small","vegetation_density":.5}),"generation starts asynchronously")
	check(manager.world.busy and manager.agents.is_empty(),"worker does not mutate live simulation")
	var frames:=0
	while manager.world.busy: frames+=1; await process_frame
	check(frames>1 and manager.last_setup_error.is_empty(),"UI remains responsive until validated world handoff")
	check(manager.agents.size()==100 and manager.agents.filter(func(a):return a.role=="Authority").size()==35,"preserve 65 civilians / 35 authorities")
	check(Map.map_seed==42 and Map.validation.valid and not manager.world.current.is_empty(),"accepted world feeds authoritative map")
	check(manager.shelter_by_id.S5.observer_masked and not manager.shelter_by_id.S5.discovered,"S5 truth stays masked until local discovery")
	var original: String=JSON.stringify(manager.world.current,"",true,true)
	for shelter in manager.shelters:
		check(shelter.nominal_capacity==manager.world.current.shelters[shelter.id].capacity,"scenario shelter capacity "+shelter.id)
		check(shelter.exists==manager.world.current.shelters[shelter.id].exists,"world-specific existence "+shelter.id)
		var start: Vector2=Map.nearest_lane_point(Map.MAP_SIZE*.5)
		check(not Map.free_route(start,shelter.position).is_empty(),"pedestrian reaches entrance "+shelter.id)
		var road_entry: Vector2=Map.shelter_parcels[shelter.id].road_entry
		check(not Navigation.route(manager.social,start,road_entry,true,0,{}).is_empty(),"directed right-hand vehicle access "+shelter.id)
	check(manager.social.police.units.size()==6,"existing paired police roster survives generated layout")
	var controls:=preload("res://scripts/city_controls.gd").new(); root.add_child(controls); controls.configure(manager,Node.new()); controls.sync()
	check(controls.size_picker.item_count==4 and controls.seed_input.value==42,"Director preset and world seed controls")
	var generation_count: int=manager.world.generation_count
	controls.vegetation_input.value=1.8
	await process_frame
	check(manager.world.generation_count==generation_count and not manager.world.busy,"editing draft settings does not regenerate")
	manager.experiment_seeds.population=718; manager.experiment_seeds.behavior=919
	manager.initialize_run()
	check(JSON.stringify(manager.world.current,"",true,true)==original,"population and behavior changes preserve immutable world")
	check(manager.social.config.seed==718 and manager.seed_for("behavior")==919,"independent experiment seeds reach population and behavior")
	var population: Array=manager.agents.map(func(a):return [a.id,a.age,a.position,a.primary_personality])
	manager.experiment_seeds.behavior=920; manager.initialize_run()
	check(population==manager.agents.map(func(a):return [a.id,a.age,a.position,a.primary_personality]),"behavior seed does not change initial population placements")
	check(manager.world.save_world("user://worlds/test_world_roundtrip.json"),"save complete generated world")
	var id: String=manager.world.current.world_id
	check(manager.world.load_world("user://worlds/test_world_roundtrip.json"),"load validates saved configuration on worker")
	check(await manager.world.completed,"saved world passes external geometry/checksum validation")
	check(manager.world.current.world_id==id and JSON.stringify(manager.world.current,"",true,true)==original,"exact world survives Godot/Python save/load")
	manager.start(); manager.advance_clock(3)
	check(manager.running and manager.agents.all(func(a):return a.position.is_finite()),"ordinary agents and vehicles advance on generated map")
	check(manager.events[-1].world_seed==42 and manager.events[-1].experiment_seeds.population==718,"simulation logs carry world and independent seed metadata")
	manager.social.emit_event("world.generation_test","director",{})
	check(manager.social.history[-1].world_id==id,"Kafka-bound event retains world identity")
	var source: String=manager.add_emergency("POLICE_SHELTER_EVACUATION",manager.agents[-1].position,{"radius":300,"duration":1200})
	manager.advance_clock(.2)
	check(not manager.social.evacuation.operation(source).is_empty(),"organized emergency integrates with generated world")
	check(manager.social.experiment_metrics().world.world_id==id,"scientific report identifies exact world")
	var hidden: bool=manager.agents.filter(func(a):return a.role=="Civilian").all(func(a):return a.beliefs.S5.status=="RUMORED" and a.beliefs.S5.existence_probability==.5 and not a.beliefs.S5.capacity_exact)
	check(hidden,"generation does not grant civilians verified S5 discovery")
	manager.pause()
	for preset in ["medium","large","very_large"]:
		manager.generate_world(43,{"preset":preset})
		check(await manager.world.completed,"runtime accepts size preset "+preset)
		check(manager.last_setup_error.is_empty() and manager.agents.size()==100,"actual population initializes on "+preset)
		var center: Vector2=Map.nearest_lane_point(Map.MAP_SIZE*.5)
		for shelter in manager.shelters:
			check(not Map.free_route(center,shelter.position).is_empty(),"walk navigation on "+preset+" / "+shelter.id)
			check(not Navigation.route(manager.social,center,Map.shelter_parcels[shelter.id].road_entry,true,0,{}).is_empty(),"vehicle navigation on "+preset+" / "+shelter.id)
	controls.queue_free(); manager.queue_free(); await process_frame
	print("World generation integration: %d checks / %d failures"%[checks,failures]); quit(1 if failures else 0)
