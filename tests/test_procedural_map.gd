extends SceneTree
const Map = preload("res://scripts/city_map.gd")
const Routes = preload("res://scripts/road_routes.gd")
const Coordinates = preload("res://scripts/three_d/world_coordinates.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func run() -> void:
	Map.generate(42)
	var original := Map.lots.duplicate()
	var roads := Map.roads.duplicate(true)
	var sites := Map.sites.duplicate()
	check(is_equal_approx(Map.green_zone.get_area()/Map.MAP_SIZE.x/Map.MAP_SIZE.y,0.25), "quarter-map reserve")
	check(Map.park.has_point(Map.sites["S1"]), "central park shelter")
	check(Map.green_zone.has_point(Map.sites["S5"]), "S5 on reserve hill")
	check(Map.elevation(Map.sites["S5"]) > 15, "raised S5 hill")
	check(Map.elevation(Map.lake.get_center()) < -1, "recessed reservoir")
	var sizes := {}
	for rect in Map.lots:
		sizes[rect.size] = true
		check(not Map.park.intersects(rect) and not Map.green_zone.intersects(rect), "nature protected from buildings")
		for site in Map.sites.values(): check(not rect.grow(60).has_point(site), "shelter approach clear")
	check(sizes.size() > 15, "varied large footprints")
	check(Map.spawn_slots().size() >= 120, "population scaling has clear slots")
	var slots := Map.spawn_slots()
	for i in range(0,slots.size(),maxi(1,int(slots.size()/35))):
		var start: Vector2 = slots[i]
		for rect in Map.lots: check(not rect.has_point(start), "spawn outside footprint")
		for site in Map.sites.values():
			var route := Routes.plan(start,site)
			check(route[0] == start and route[-1] == site, "route reaches shelter")
			for segment in range(1,route.size()):
				var steps := maxi(1,int(route[segment-1].distance_to(route[segment])/20))
				for step in range(steps+1):
					var point := route[segment-1].lerp(route[segment],float(step)/steps)
					for rect in Map.lots:
						if rect.has_point(point):
							check(false,"route crosses building")
		check(is_equal_approx(Coordinates.to_world(start).y,Map.elevation(start)+Coordinates.FLOOR_Y),"avatar follows terrain")
	Map.generate(42)
	check(Map.lots == original and Map.roads == roads and Map.sites == sites,"same seed reproduces entire geography")
	Map.generate(43)
	check(Map.lots != original and Map.roads != roads,"different seed changes geography")
	for seed_value in range(12):
		Map.generate(seed_value)
		for cuts in [Map.x_cuts,Map.y_cuts]:
			for i in range(1,cuts.size()): check(cuts[i]-cuts[i-1] >= 99.9,"non-overlapping navigation corridors")
		check(Map.green_zone.has_point(Map.sites["S5"]),"seeded hill remains in reserve")
		check(Map.spawn_slots().size() >= 120,"seeded maps have sufficient population spawns")
	Map.generate(42)
	var city = preload("res://scenes/three_d/city.tscn").instantiate()
	root.add_child(city)
	await physics_frame
	await physics_frame
	var point := Coordinates.to_world(Map.hill)
	var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*80,point-Vector3.UP*80,8)
	var hit: Dictionary = city.get_world_3d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty(),"terrain has a physical surface for picking")
	if not hit.is_empty(): check(absf(hit["position"].y-Map.elevation(Map.hill)) < 0.25,"terrain collider matches elevation")
	check(city.buildings.size() == Map.lots.size(),"visual buildings match authoritative footprints")
	for rect in city.navigation_region.walkable_rects: check(rect.size.x > 0 and rect.size.y > 0,"valid navigation polygons")
	city.queue_free()
	await process_frame
	print("Procedural map: %d checks / %d failures" % [checks,failures])
	quit(1 if failures else 0)
