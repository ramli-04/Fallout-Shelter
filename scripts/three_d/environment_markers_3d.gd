extends Node3D
## Director-only visual markers; event consequences remain in environment_events.gd.
const Coordinates = preload("res://scripts/three_d/world_coordinates.gd")
const Geometry = preload("res://scripts/three_d/geometry.gd")
var markers := {}

func sync(events: Array, _director: bool = true) -> void:
	var active_ids := {}
	for event in events:
		if not event["active_status"]: continue
		var id: String = event["event_id"]
		active_ids[id] = true
		if markers.has(id): continue
		var marker := Node3D.new()
		marker.position = Coordinates.to_world(event["target_location"])
		add_child(marker)
		var color := Color("f3b456") if event["event_type"] != "crowd" else Color("ee7568")
		var ring := Geometry.ring(marker,3.2,color)
		ring.position.y = 0.05
		Geometry.label(marker,event["event_type"].to_upper(),Vector3(0,5.5,0),color,30,0.025)
		if event["event_type"] == "road":
			Geometry.box(marker,Vector3(3.0,0.65,0.3),Vector3(0,0.65,0),color)
			for side in [-1,1]: Geometry.box(marker,Vector3(0.25,1.0,0.4),Vector3(side*1.2,0.5,0),Color("48565a"))
		markers[id] = marker
	for id in markers.keys():
		if not active_ids.has(id):
			remove_child(markers[id])
			markers[id].queue_free()
			markers.erase(id)
