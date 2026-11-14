extends SceneTree
const Map=preload("res://scripts/city_map.gd")
const Manager=preload("res://scripts/simulation_manager.gd")
const Routes=preload("res://scripts/road_routes.gd")
var checks:=0
var failures:=0
var benchmark: Array=[]
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures+=1; printerr("FAIL: "+label)
func fingerprint() -> String:
	var data:=[]
	for road in Map.roads: data.append([road.from,road.to,Array(road.points),road.width])
	return str([data,Map.lots,Map.sites,Map.districts]).sha256_text()
func run() -> void:
	for seed_value in [42,43,91]:
		check(Map.generate(seed_value),"validated generation")
		benchmark.append({"seed":seed_value,"generation_ms":Map.generation_ms,"junctions":Map.graph.get_point_count(),"roads":Map.roads.size(),"buildings":Map.lots.size()})
		check(is_equal_approx(Map.MAP_SIZE.x*Map.MAP_SIZE.y/(6750*4050.0),2),"double playable area")
		check(Map.validation.valid,"all geometry validation passes")
		for id in Map.graph.get_point_ids(): check(not Map.graph.get_id_path(0,id).is_empty(),"connected authoritative graph")
		var slots:=Map.spawn_slots()
		check(slots.size()>500,"space for population")
		for i in range(0,slots.size(),maxi(1,slots.size()/10)):
			for site in Map.sites.values():
				var path:=Map.free_route(slots[i],site)
				check(not path.is_empty(),"pedestrian shelter reachability")
				for j in range(1,path.size()): check(Map.clear_segment(path[j-1],path[j]),"pedestrians avoid physical obstacles")
		for lot in Map.lots:
			var base:=Map.elevation(lot.get_center())
			for point in [lot.position,lot.end,Vector2(lot.end.x,lot.position.y),Vector2(lot.position.x,lot.end.y)]:
				check(absf(base-Map.elevation(point))<.55,"foundation reaches ground at every corner")
		var digest:=fingerprint()
		Map.generate(seed_value)
		check(digest==fingerprint(),"same seed reproduces all shared geometry")
	Map.generate(42)
	var edge: Dictionary=Map.roads.filter(func(r): return not r.get("elevated",false) and not r.get("ramp",false) and Map._path_length(r.points)>300)[0]
	var middle: Vector2=edge.points[edge.points.size()/2]
	Map.graph.disconnect_points(edge.from,edge.to)
	Map.roadblock_data.test={"edge":Map.roads.find(edge),"position":middle}
	Map.set_closure("test",middle,true)
	var detour:=Map.route(edge.points[1],edge.points[-2])
	check(not Map.graph.are_points_connected(edge.from,edge.to),"closure disconnects physical edge")
	if not detour.is_empty():
		for i in range(1,detour.size()): check(Geometry2D.get_closest_point_to_segment(middle,detour[i-1],detour[i]).distance_to(middle)>34,"vehicle route respects closure")
	Map.graph.connect_points(edge.from,edge.to); Map.roadblock_data.erase("test"); Map.set_closure("test",middle,false)
	check(not Map.route(edge.points[1],edge.points[-2]).is_empty(),"reopening restores road access")
	var sim:=Manager.new(); root.add_child(sim); sim.set_process(false)
	check(sim.load_settings(),"manager loads city settings")
	sim.social_config.llm_agents=0; sim.ai_config.enabled=false; sim.initialize_run()
	check(sim.last_setup_error.is_empty(),"manager initializes expanded city")
	var occupied: Dictionary={}
	for v in sim.social.vehicles:
		if v.status=="PARKED":
			check(not occupied.has(v.parking_bay),"each parked car has a unique parking space")
			occupied[v.parking_bay]=true
			var found:=false
			for lot in Map.parking_lots:
				for bay in lot.bays:
					if bay.id==v.parking_bay: found=bay.occupied_by==v.id and v.position.is_equal_approx(bay.position)
			check(found,"parked car spawns in an occupied valid bay")
			check(not v.parking_exit.is_empty() and v.parking_exit[0].is_equal_approx(v.position),"parking departure begins at physical car")
		else:
			var nearest: Dictionary=Map.nearest_edge(v.position,true,v.height)
			check(v.status=="MOVING" and not nearest.is_empty() and nearest.point.distance_to(v.position)<=float(nearest.edge.width)*.5+20,"driving car spawns on a valid road")
	var free_count:=0
	var first_vehicle: Dictionary=sim.social.vehicles[0]
	check(Map.claim_parking(first_vehicle.id,Vector2.ZERO).id==first_vehicle.parking_bay,"repeated claim keeps the same bay")
	for lot in Map.parking_lots:
		for bay in lot.bays:
			if bay.occupied_by.is_empty(): free_count+=1
	for i in range(free_count): check(not Map.claim_parking("fixture%d"%i,Vector2.ZERO).is_empty(),"claim unoccupied space")
	check(Map.claim_parking("overflow",Vector2.ZERO).is_empty(),"full parking cannot spawn another car")
	Map.release_parking("fixture0")
	check(not Map.claim_parking("reused",Vector2.ZERO).is_empty(),"released space reusable")
	var estimates:=Map.travel_estimates(Map.nearest_lane_point(Map.MAP_SIZE*.5))
	check(estimates.size()==5 and estimates.S4.walk_seconds>0,"distances and travel times recalculated")
	var controls:=preload("res://scripts/city_controls.gd").new(); root.add_child(controls); controls.configure(sim,Node.new()); controls.sync()
	check(controls.seed_input.value==sim.seed_value and controls.area_input.value==2,"Director reflects generated map")
	controls.area_input.value=1.5; controls.width_input.value=1.2; controls._regenerate(77)
	check(sim.seed_value==77 and Map.map_seed==77,"Director applies new seed")
	check(absf(Map.MAP_SIZE.x*Map.MAP_SIZE.y/(6750*4050.0)-1.5)<.001,"Director applies playable area")
	check(Map.roads.any(func(r): return r.kind=="residential" and absf(r.width-84)<.01),"Director applies road widths")
	sim.start(); controls._process(0)
	check(controls.apply_button.disabled and not controls.area_input.editable,"generation locked after simulation starts")
	controls._regenerate(99)
	check(sim.seed_value==77,"running city cannot be regenerated")
	controls.view.free(); controls.queue_free(); sim.queue_free(); await process_frame
	var file:=FileAccess.open("res://outputs/city61-generation-benchmark.json",FileAccess.WRITE); file.store_string(JSON.stringify(benchmark,"  ")); file.close()
	print("City 6.1: %d checks / %d failures"%[checks,failures]); print(JSON.stringify(benchmark))
	quit(1 if failures else 0)
