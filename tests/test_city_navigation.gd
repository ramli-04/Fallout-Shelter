extends SceneTree
const Map=preload("res://scripts/city_map.gd")
const C=preload("res://scripts/three_d/world_coordinates.gd")
const Nav=preload("res://scripts/three_d/road_navigation_3d.gd")
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1; printerr("FAIL: "+label)
func synchronize(region: Node, previous: int = 0, previous_region: int = 0) -> void:
	var navigation_map: RID=region.get_navigation_map()
	# Iteration one is the empty world map; region upload and map synchronization
	# are separate asynchronous stages. Wait for the populated map snapshot.
	for _i in range(300):
		await physics_frame
		if NavigationServer3D.map_get_iteration_id(navigation_map)>maxi(1,previous) and NavigationServer3D.region_get_iteration_id(region.get_rid())>previous_region and NavigationServer3D.get_process_info(NavigationServer3D.INFO_POLYGON_COUNT)==region.navigation_mesh.get_polygon_count(): return
	check(false,"navigation synchronization timed out")
func run() -> void:
	check(Map.generate(42),"valid city")
	var region:=Nav.new(); root.add_child(region)
	var navigation_map:=region.get_world_3d().navigation_map
	await synchronize(region)
	check(NavigationServer3D.map_get_regions(navigation_map).size()>0,"real Godot navigation map synchronized")
	check(region.navigation_mesh.get_polygon_count()>10000,"pedestrian surface rebuilt at street scale")
	var slots:=Map.spawn_slots()
	for i in range(0,slots.size(),maxi(1,slots.size()/8)):
		for site in Map.sites.values():
			var path: PackedVector3Array=region.server_path_between(C.to_world(slots[i]),C.to_world(site))
			check(not path.is_empty(),"Godot navigation reaches every shelter")
			if not path.is_empty():
				var distance:=C.to_simulation(path[-1]).distance_to(site)
				check(distance<35,"Godot path reaches actual approach")
	var point: Vector2=Map.roads[0].points[Map.roads[0].points.size()/2]
	var revision:=Map.navigation_revision
	var iteration:=NavigationServer3D.map_get_iteration_id(navigation_map)
	var region_iteration:=NavigationServer3D.region_get_iteration_id(region.get_rid())
	Map.set_closure("nav-test",point,true)
	await create_timer(.4).timeout
	await synchronize(region,iteration,region_iteration)
	check(region.revision>revision,"navigation updates after road closure")
	var closest:=NavigationServer3D.map_get_closest_point(navigation_map,C.to_world(point))
	check(C.to_simulation(closest).distance_to(point)>35,"closed area excluded from real navigation mesh")
	iteration=NavigationServer3D.map_get_iteration_id(navigation_map)
	region_iteration=NavigationServer3D.region_get_iteration_id(region.get_rid())
	Map.set_closure("nav-test",point,false)
	await create_timer(.4).timeout
	await synchronize(region,iteration,region_iteration)
	check(region.revision==Map.navigation_revision,"reopened navigation synchronized")
	closest=NavigationServer3D.map_get_closest_point(navigation_map,C.to_world(point))
	check(C.to_simulation(closest).distance_to(point)<1,"reopened ground reachable")
	region.queue_free(); await process_frame
	print("City navigation: %d checks / %d failures"%[checks,failures]); quit(1 if failures else 0)
