extends RefCounted
## Sensor boundary. Policies receive only these local, time-stamped snapshots.
const Map = preload("res://scripts/city_map.gd")

static func visible(a: Dictionary, point: Vector2, radius: float, height: float = 0.0) -> bool:
	return a.get("indoor_id","")=="" and a.position.distance_to(point)<=radius and absf(float(a.get("transport_height",0))-height)<3 and Map.clear_segment(a.position,point,false)

static func entry(kind: String, id: String, point: Vector2, a: Dictionary, now: float, severity: float, confidence: float = 1.0) -> Dictionary:
	return {"kind":kind,"id":id,"position":point,"distance":a.position.distance_to(point),"severity":clampf(severity,0,1),"confidence":confidence,"timestamp":now}

static func observe(sim: RefCounted, a: Dictionary, config: Dictionary) -> Array:
	var result: Array = []
	var now: float = sim.manager.elapsed_seconds
	var radius: float = config.observation_radius
	for other in sim.manager.agents:
		if other.id==a.id: continue
		var can_see: bool=sim.manager.can_observe(a,other)
		if a.get("indoor_id","")=="" and other.get("indoor_id","")=="" and other.get("riding","")=="" and other.state not in ["SHELTERED","SAFE"]:
			can_see=visible(a,other.position,radius,float(other.get("transport_height",0)))
		if not can_see: continue
		if a.position.distance_to(other.position)>radius: continue
		var kind := "deceased" if other.health<=0 else "injured" if other.health<60 else "police" if other.get("occupation","")=="Police" else "person"
		var item := entry(kind,other.id,other.position,a,now,1-other.health/100.0)
		item["state"]=other.state
		if kind=="police" and other.get("police_unit_busy",false):
			item["instruction"]=other.get("police_animation",""); item["unit"]=other.get("police_unit_id","")
		result.append(item)
	for v in sim.vehicles:
		if v.status=="REMOVED" or not visible(a,v.position,radius,float(v.get("height",0))): continue
		var kind := "accident" if v.status in ["ACCIDENT","DESTROYED"] else "emergency_vehicle" if v.kind!="Civilian" else "vehicle"
		var item := entry(kind,v.id,v.position,a,now,.7 if kind=="accident" else .1)
		item["speed"]=float(v.speed); item["heading"]=float(v.heading)
		item["width"]=float(v.width); item["length"]=float(v.length)
		result.append(item)
	for block in sim.blocks:
		if block.active and visible(a,block.position,radius,float(block.get("height",0))):
			var item := entry("roadblock",block.id,block.position,a,now,.4)
			item["edge"]=int(block.edge); item["state"]=str(block.kind)
			result.append(item)
	for event in sim.manager.environment_events:
		var point: Vector2 = event.target_location
		var direct: bool=visible(a,point,radius)
		var local_field: bool=event.event_type in ["fire","explosion","danger_zone","increasing_threat"] and a.position.distance_to(point)<=float(event.get("radius",0))
		if event.active_status and (direct or local_field):
			var item:=entry(str(event.event_type),str(event.get("event_id","event")),point if direct else a.position,a,now,0.0 if event.event_type=="POLICE_SHELTER_EVACUATION" else float(event.severity),1.0 if direct else .7)
			item["radius"]=float(event.get("radius",0)) if direct else 0.0
			result.append(item)
	for shelter in sim.manager.shelters:
		if shelter.exists and visible(a,shelter.position,radius):
			result.append(entry("shelter",shelter.id,shelter.position,a,now,0))
	# Resources are a private estimate, not exact director stocks.
	for id in a.beliefs:
		var belief: Dictionary=a.beliefs[id]
		if belief.get("resource_score",0)>0 and not belief.get("unavailable",false) and visible(a,belief.position,radius):
			result.append(entry("resource",id,belief.position,a,now,0,float(belief.get("confidence",.5))))
	var route: PackedVector2Array=a.get("route",PackedVector2Array())
	var index: int=a.get("route_index",0)
	if a.get("indoor_id","")=="" and index<route.size() and a.position.distance_to(route[index])<radius and not Map.clear_segment(a.position,route[index]):
		result.append(entry("obstacle","route",route[index],a,now,.6))
	result.sort_custom(func(x,y): return x.distance<y.distance if is_equal_approx(x.severity,y.severity) else x.severity>y.severity)
	return result.slice(0,int(config.observation_limit))
