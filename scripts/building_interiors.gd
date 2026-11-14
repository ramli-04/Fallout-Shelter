extends RefCounted
## Lightweight rooms share the exterior coordinates; every transition follows a door corridor.
const Map=preload("res://scripts/city_map.gd")
var rooms: Dictionary={}
var slots: Dictionary={}
var _social_ref: WeakRef
var social: RefCounted:
	get: return _social_ref.get_ref() if _social_ref!=null else null
	set(value): _social_ref=weakref(value) if value!=null else null

func initialize(owner_social: RefCounted) -> void:
	social=owner_social; rooms.clear(); slots.clear(); Map.interior_data.clear()
	for index in range(Map.lots.size()):
		var rect: Rect2=Map.lots[index]
		if minf(rect.size.x,rect.size.y)<32: continue
		var room_size: Vector2=Map._v2(Map.building_data[index].get("local_size",[rect.size.x,rect.size.y]))
		var angle: float=-Map.lot_angles[index]
		var center: Vector2=rect.get_center()
		var best: Dictionary={}; var distance:=INF
		for normal in [Vector2.RIGHT,Vector2.LEFT,Vector2.DOWN,Vector2.UP]:
			var extent: float=(room_size.x if normal.x else room_size.y)*.5
			var boundary: Vector2=center+(normal*extent).rotated(angle)
			for clearance in [20.0,40.0,70.0,110.0,160.0]:
				var anchor: Vector2=boundary+(normal*clearance).rotated(angle)
				if not Map.clear_point(anchor,12) or not corridor_clear(boundary,anchor,index): continue
				var road: Dictionary=Map.nearest_edge(anchor)
				if Map.free_route(anchor,road.point).is_empty(): continue
				var d: float=anchor.distance_to(road.point)+clearance
				if d<distance:
					distance=d; best={"door":boundary,"door_inside":boundary-(normal*10).rotated(angle),"door_outside":anchor,"door_normal":normal}
				break
		if best.is_empty(): continue
		var id: String="I%04d"%index
		best.merge({"id":id,"index":index,"center":center,"size":room_size,"angle":angle,"kind":"Home","active":false,"occupants":[],"door_open_until":0.0})
		for poi in Map.pois:
			if poi.footprint==rect: best.kind=poi.kind
		rooms[id]=best
		Map.interior_data[id]=best

func corridor_clear(start: Vector2, finish: Vector2, own_index: int) -> bool:
	var obstacles: Array=Map.rock_obstacles.duplicate(); obstacles.append(Map.lake)
	for index in range(Map.lots.size()):
		if index!=own_index: obstacles.append(Map.lots[index])
	for rect in obstacles:
		var bounds: Rect2=rect.grow(4)
		if bounds.has_point(start) or bounds.has_point(finish): return false
		var corners: Array=[bounds.position,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)]
		for i in range(4):
			if Geometry2D.segment_intersects_segment(start,finish,corners[i],corners[(i+1)%4])!=null: return false
	return true

func local_point(room: Dictionary, point: Vector2) -> Vector2:
	return (point-room.center).rotated(-float(room.angle))

func contains(room_id: String, point: Vector2) -> bool:
	if not rooms.has(room_id): return false
	var room: Dictionary=rooms[room_id]
	return Rect2(-room.size*.5+Vector2.ONE*5,room.size-Vector2.ONE*10).has_point(local_point(room,point))

func reserve_slot(room_id: String, agent_id: String) -> Vector2:
	if slots.has(agent_id): return slots[agent_id]
	if not rooms.has(room_id): return Vector2.INF
	var room: Dictionary=rooms[room_id]
	for y in range(12,int(room.size.y)-8,12):
		for x in range(12,int(room.size.x)-8,12):
			var point: Vector2=room.center+(Vector2(x,y)-room.size*.5).rotated(room.angle)
			if not contains(room_id,point): continue
			if slots.values().any(func(other):return point.distance_to(other)<9): continue
			slots[agent_id]=point
			return point
	return Vector2.INF

func spawn(agent: Dictionary, room_id: String) -> bool:
	var point: Vector2=reserve_slot(room_id,agent.id)
	if not point.is_finite(): return false
	rooms[room_id].active=true
	agent.position=point; agent.previous_position=point; agent.indoor_id=room_id; agent.indoor_exit=rooms[room_id].door_outside
	agent.location_mode="INDOOR"; agent.transport_height=0.0
	if agent.id not in rooms[room_id].occupants: rooms[room_id].occupants.append(agent.id)
	return true

func move_path(agent: Dictionary, seconds: float) -> bool:
	var points: PackedVector2Array=agent.interior_path
	var budget: float=maxf(0,agent.movement_speed)*seconds
	while int(agent.interior_index)<points.size() and budget>0:
		var target: Vector2=points[agent.interior_index]
		var distance: float=agent.position.distance_to(target)
		var used: float=minf(distance,budget)
		agent.position=agent.position.move_toward(target,used); budget-=used
		if distance<=used+.001: agent.interior_index+=1
		else: break
	return int(agent.interior_index)>=points.size()

func exit_building(agent: Dictionary, seconds: float) -> bool:
	var id: String=agent.get("indoor_id","")
	if id.is_empty(): return true
	var room: Dictionary=rooms[id]
	if Map.closures.values().any(func(bounds):return bounds.has_point(room.door_outside)): return false
	room.door_open_until=social.manager.elapsed_seconds+2
	if agent.get("interior_transition","")!="EXIT":
		agent.interior_transition="EXIT"; agent.interior_transition_room=id; agent.interior_index=1
		agent.interior_path=PackedVector2Array([agent.position,room.door_inside,room.door,room.door_outside])
	agent.location_mode="EXITING"
	if not move_path(agent,seconds): return false
	room.occupants.erase(agent.id); agent.indoor_id=""; agent.interior_transition=""
	agent.location_mode="OUTDOOR"; agent.route=PackedVector2Array(); agent.route_index=0
	social.emit_event("building.exited",agent.id,{"building":id,"door":room.door})
	if social.manager.phase in ["EVACUATION","BOMB_FALL"] and agent.age>=18:
		if not agent.objective.is_empty() and agent.beliefs.has(agent.objective):
			agent.route=preload("res://scripts/road_routes.gd").plan(agent.position,agent.beliefs[agent.objective].position)
			agent.route_index=1
			social.manager._set_state(agent,"MOVING")
		else: social.manager.choose_destination(agent)
	return true

func go_to(agent: Dictionary, room_id: String, seconds: float) -> bool:
	if not rooms.has(room_id): return false
	if agent.get("indoor_id","")==room_id: return true
	if not agent.get("indoor_id","").is_empty(): exit_building(agent,seconds); return false
	var room: Dictionary=rooms[room_id]
	if Map.closures.values().any(func(bounds):return bounds.has_point(room.door_outside)): return false
	if agent.get("interior_transition","")!="ENTER":
		if agent.position.distance_to(room.door_outside)>2:
			social._walk_toward(agent,room.door_outside,agent.movement_speed,seconds); return false
		agent.interior_transition="ENTER"; agent.interior_transition_room=room_id; agent.interior_index=1
		var destination: Vector2=slots.get(agent.id,room.center)
		if not contains(room_id,destination): destination=room.center
		agent.interior_path=PackedVector2Array([agent.position,room.door,room.door_inside,destination])
	room.door_open_until=social.manager.elapsed_seconds+2; agent.location_mode="ENTERING"
	if not move_path(agent,seconds): return false
	agent.indoor_id=room_id; agent.indoor_exit=room.door_outside; agent.interior_transition=""; agent.location_mode="INDOOR"
	if agent.id not in room.occupants: room.occupants.append(agent.id)
	social.emit_event("building.entered",agent.id,{"building":room_id,"door":room.door})
	return true

func can_see(a: Dictionary, b: Dictionary) -> bool:
	if b.get("state","")=="SHELTERED" and (a.get("state","")!="SHELTERED" or a.get("shelter_id","")!=b.get("shelter_id","")): return false
	if a.get("indoor_id","")!=b.get("indoor_id",""): return false
	if a.get("riding","")!=b.get("riding","") and (a.get("riding","")!="" or b.get("riding","")!=""): return false
	if a.position.distance_to(b.position)>social.manager.living.observation_radius: return false
	return a.get("indoor_id","")!="" or Map.clear_segment(a.position,b.position)

func clear() -> void:
	rooms.clear(); slots.clear(); Map.interior_data.clear()
