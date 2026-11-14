extends Control
## Cheap overview of actual generated geometry. Hidden S5 is omitted.
const Map=preload("res://scripts/city_map.gd")
func _ready() -> void:
	custom_minimum_size=Vector2(275,170)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("252e2b"))
	if Map.graph==null: return
	var scale_value:=minf((size.x-12)/Map.MAP_SIZE.x,(size.y-12)/Map.MAP_SIZE.y)
	var offset:=(size-Map.MAP_SIZE*scale_value)*.5
	for edge in Map.roads:
		var points:=PackedVector2Array()
		for p in edge.points: points.append(p*scale_value+offset)
		draw_polyline(points,Color("a9a18c") if not edge.get("elevated",false) else Color("c2a366"),1.0)
	for id in Map.sites:
		if id=="S5": continue
		draw_circle(Map.sites[id]*scale_value+offset,3,Color("69c6a1"))
