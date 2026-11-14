extends SceneTree
const Map=preload("res://scripts/city_map.gd")
const Art=preload("res://scripts/three_d/building_sprites.gd")
var failures:=0
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; printerr("FAIL: "+label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var manager=preload("res://scripts/simulation_manager.gd").new(); root.add_child(manager); manager.set_process(false)
	manager.load_settings();
	if not OS.get_cmdline_user_args().is_empty(): manager.seed_value=int(OS.get_cmdline_user_args()[0])
	manager.social_config.llm_agents=0; manager.initialize_run(); manager.ai_bridge.set_process(false);
	if manager.social==null: printerr(manager.last_setup_error); manager.queue_free(); quit(1); return
	manager.social.close()
	var policy=preload("res://scripts/station_parking.gd")
	for i in range(Map.lots.size()):
		var data:=Art.info(preload("res://scripts/three_d/building_shape.gd").plan(i),i)
		check(str(data.key).begins_with("sheet:new_"),"latest collection only")
	for lot in Map.parking_lots:
		if not lot.get("integrated_station",false): continue
		check(not policy.allows(lot,{"kind":"Civilian"}),"civilian excluded from station")
		check(policy.allows(lot,{"kind":lot.allowed_vehicle_kind}),"own fleet accepted")
		var parked: Array=manager.social.vehicles.filter(func(v):return lot.bays.any(func(b):return b.occupied_by==v.id))
		print("Station fleet: ",lot.category," ",parked.map(func(v):return v.model))
		check(parked.size()==(3 if lot.category=="offices" else 6),"station fleet has reserved capacity")
		for v in parked:
			check(v.kind==lot.allowed_vehicle_kind,"fleet restriction")
			check(Map.lots.all(func(rect):return manager.social.traffic.static_contact(v,v.position,v.position,rect).is_empty()),"bay outside building collision")
	check(manager.social.vehicles.any(func(v):return v.model=="swat"),"SWAT present")
	check(preload("res://scripts/three_d/grass_material.gd").TILE_METRES==1.0,"one metre grass parcels")
	manager.queue_free(); await process_frame
	print("Station art parking: %d checks / %d failures"%[checks,failures]); quit(1 if failures else 0)
