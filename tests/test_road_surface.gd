extends SceneTree
const Map=preload("res://scripts/city_map.gd")
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(v: bool, label: String) -> void:
	checks+=1
	if not v: failures+=1; printerr("FAIL: "+label)
func area(p: PackedVector2Array) -> float:
	var sum:=0.0
	for i in range(p.size()): sum+=(p[i]-p[0]).cross(p[(i+1)%p.size()]-p[0])
	return absf(sum)*.5
func run() -> void:
	Map.generate(42)
	var paths:=[]
	for road in Map.roads:
		var points:=[]
		for p in road.points: points.append([p.x,p.y])
		paths.append({"points":points,"width":25})
	var file:=FileAccess.open("res://outputs/phase5-road-fixture.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"roads":paths},"",true,true)); file.close()
	var route:=Map.route(Map.roads[0].points[2],Map.sites.S3)
	check(not route.is_empty(),"road graph shelter connection")
	for i in range(1,route.size()): check(route[i].distance_to(route[i-1])<200,"continuous curved vehicle route")
	check(Map.ramps.size()==2,"two connected highway ramps")
	for road in Map.roads:
		if road.get("elevated",false) or road.get("ramp",false):
			check(Map.graph.are_points_connected(road.from,road.to),"elevated geometry has real graph edge")
	var elevated: Dictionary=Map.roads.filter(func(e):return e.get("elevated",false))[10]
	var middle: Vector2=(elevated.a+elevated.b)*.5
	check(absf(Map.route_height(middle,(elevated.b-elevated.a).normalized(),10)-10)<.01,"highway vehicle elevation")
	print("Road navigation: %d checks / %d failures"%[checks,failures]); quit(1 if failures else 0)
