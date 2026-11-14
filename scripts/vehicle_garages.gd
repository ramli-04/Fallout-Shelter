extends RefCounted
## Hidden civilian vehicle storage. A garage owns at most twelve vehicles and
## serializes physical departures through its existing entrance, without new art.
const CAPACITY:=12
const MAX_GARAGES:=3
const SAT=preload("res://scripts/vehicle_collisions.gd")

static func configure(map: Script) -> void:
	map.garage_sites.clear()
	var candidates: Array=[]
	for i in range(map.building_data.size()):
		var b: Dictionary=map.building_data[i]
		b.erase("garage_id")
		if b.district!="INDUSTRIAL" or not b.has("access_path"): continue
		if map.pois.any(func(p):return p.footprint==map.lots[i]): continue
		candidates.append(i)
	candidates.sort_custom(func(a,b):return a<b if is_equal_approx(map.lots[a].get_area(),map.lots[b].get_area()) else map.lots[a].get_area()>map.lots[b].get_area())
	for index in candidates:
		if map.garage_sites.size()>=MAX_GARAGES: break
		var b: Dictionary=map.building_data[index]
		var center: Vector2=map.lots[index].get_center()
		if map.garage_sites.any(func(g):return g.center.distance_to(center)<450): continue
		var entry: Vector2=map._v2(b.road_entry); var door: Vector2=map._v2(b.entrance)
		var out: Vector2=(entry-door).normalized()
		var portal: Vector2=door+out*55
		var probe: Dictionary={"length":80.0,"width":28.0,"heading":out.angle(),"height":0.0,"body_height":3.0}
		if map.lots.any(func(rect):return not SAT.contact(probe,portal,entry,{"position":rect.get_center(),"length":rect.size.x,"width":rect.size.y,"heading":0.0,"height":0.0,"body_height":20.0},rect.get_center(),rect.get_center()).is_empty()): continue
		var id: String="GARAGE%d"%(map.garage_sites.size()+1)
		b.garage_id=id
		map.garage_sites.append({"id":id,"index":index,"center":center,"position":portal,"waiting_point":portal+out.orthogonal()*25,"road_entry":entry,"heading":out.angle(),"capacity":CAPACITY,"exit":PackedVector2Array([portal,entry])})

static func allocate(v: Dictionary,vehicles: Array,map: Script,near: Vector2) -> Dictionary:
	var choices: Array=map.garage_sites.duplicate()
	choices.sort_custom(func(a,b):return a.position.distance_squared_to(near)<b.position.distance_squared_to(near))
	for garage in choices:
		if vehicles.filter(func(other):return other.get("garage_id","")==garage.id).size()>=CAPACITY: continue
		v.merge({"garage_id":garage.id,"stored_in":garage.id,"position":garage.position,"body_position":garage.position,"heading":garage.heading,"parking_heading":garage.heading,"parking_bay":"","parking_exit":garage.exit.duplicate()},true)
		return garage
	return {}

static func site(v: Dictionary,map: Script) -> Dictionary:
	for garage in map.garage_sites:
		if garage.id==v.get("garage_id",""): return garage
	return {}

static func release(v: Dictionary,sim: RefCounted) -> bool:
	if v.get("stored_in","")=="": return true
	var map: Script=load("res://scripts/city_map.gd")
	var garage:=site(v,map)
	if garage.is_empty(): return false
	# One car clears the entrance and merge before the next one materializes.
	for other in sim.vehicles:
		if other.id==v.id or other.get("stored_in","")!="" or other.status=="REMOVED": continue
		if other.position.distance_to(garage.position)<maxf(v.length,other.length)+35: return false
		if other.get("departure_garage","")==garage.id and (int(other.get("parking_exit_end",0))>0 and int(other.get("route_index",0))<=int(other.parking_exit_end)): return false
	var probe: Dictionary=v.duplicate(); probe.stored_in=""; probe.position=garage.position; probe.body_position=garage.position; probe.heading=garage.heading
	probe.curb_clearance=.32
	for other in sim.vehicles:
		if other.id!=v.id and not SAT.contact(probe,garage.position,garage.road_entry,other,SAT.body_position(other),SAT.body_position(other)).is_empty(): return false
	if not sim.traffic.physics_query(probe,garage.position,garage.road_entry).is_empty(): return false
	for agent in sim.manager.agents:
		if agent.id==v.driver or agent.get("indoor_id","")!="" or agent.get("riding","")!="" or agent.get("boarding_vehicle","")==v.id: continue
		if agent.position.distance_to(Geometry2D.get_closest_point_to_segment(agent.position,garage.position,garage.road_entry))<float(v.width)*.5+5: return false
	v.stored_in=""; v.departure_garage=garage.id; v.parking_exit=garage.exit.duplicate()
	v.position=garage.position; v.body_position=garage.position; v.heading=garage.heading; v.lane_offset=0.0
	sim.emit_event("garage.vehicle_spawned",v.id,{"garage":garage.id,"manual":false})
	return true

static func destination(v: Dictionary,sim: RefCounted) -> Dictionary:
	var garage:=site(v,load("res://scripts/city_map.gd"))
	if garage.is_empty(): return {}
	for other in sim.daily.parking_destinations.values():
		if other.get("garage_id","")==garage.id: return {}
	var approach: PackedVector2Array=garage.exit.duplicate(); approach.reverse()
	return {"id":garage.id+":"+v.id,"garage_id":garage.id,"position":garage.position,"heading":garage.heading,"approach":approach,"occupied_by":"DEST:"+v.id}

static func store(v: Dictionary,sim: RefCounted) -> void:
	var garage:=site(v,load("res://scripts/city_map.gd"))
	if garage.is_empty(): return
	v.stored_in=garage.id; v.parking_bay=""; v.speed=0; v.lane_offset=0
	v.position=garage.position; v.body_position=garage.position; v.parking_exit=garage.exit.duplicate(); v.parking_exit_end=0
	sim.emit_event("garage.vehicle_stored",v.id,{"garage":garage.id})
