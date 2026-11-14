extends RefCounted
const Convention=preload("res://scripts/traffic_conventions.gd")
## Routines use physical room/door/vehicle transitions. Only initialization assigns spawn positions.
const Map=preload("res://scripts/city_map.gd")
const SAT=preload("res://scripts/vehicle_collisions.gd")
var _social_ref: WeakRef
var social: RefCounted:
	get: return _social_ref.get_ref() if _social_ref!=null else null
	set(value): _social_ref=weakref(value) if value!=null else null
var interiors=preload("res://scripts/building_interiors.gd").new()
var spontaneous=preload("res://scripts/spontaneous_actions.gd").new()
var rng:=RandomNumberGenerator.new()
var settings: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/daily_life.json"))
var outdoor_slots: Array=[]
var parking_destinations: Dictionary={}

func room_for(kind: String) -> String:
	for room in interiors.rooms.values():
		if room.kind==kind: return room.id
	return ""

func initialize(owner_social: RefCounted) -> void:
	social=owner_social; rng.seed=social.manager.seed_for("population")+71071
	interiors.initialize(social); outdoor_slots.clear(); parking_destinations.clear()
	var homes: Array=interiors.rooms.values().filter(func(room):return room.kind=="Home" and Map.lot_districts[room.index] in ["RESIDENTIAL","GROVE"])
	var workplaces: Array=interiors.rooms.values().filter(func(room):return room.kind=="Home" and Map.lot_districts[room.index] in ["DOWNTOWN","INDUSTRIAL","SERVICES"])
	var shops: Array=workplaces.filter(func(room):return Map.lot_districts[room.index]=="DOWNTOWN")
	if workplaces.is_empty(): workplaces=homes.duplicate()
	if shops.is_empty(): shops=workplaces.duplicate()
	for room in homes:
		if Map.lot_districts[room.index]!="GROVE" and room.size.x*room.size.y>5000: room.kind="Apartment"
	var home_by_family: Dictionary={}
	for a in social.manager.agents:
		a.indoor_id=""; a.interior_transition=""; a.interior_transition_room=""; a.location_mode="OUTDOOR"
		a.routine="HOME"; a.routine_target=""; a.routine_until=0.0; a.routine_use_vehicle=false; a.routine_dwell_started=0.0
		a.needs={"safety":1.0,"fatigue":0.0,"stress":0.0,"family":0.0,"health":a.health/100.0,"social_attachment":a.sociability/100.0}
		a.safety=1.0; a.social_attachment=a.sociability/100.0; a.family_plans={}
		a.boarding_vehicle=""; a.travel_group=""; a.group_leader=""; a.pickup_target=""; a.pickup_walk=false; a.group_on_foot=false
		var household: String=a.family_id if not a.family_id.is_empty() else a.id
		if not home_by_family.has(household):
			var near: Vector2=Vector2(a.home_uv[0],a.home_uv[1])*Map.MAP_SIZE
			homes.sort_custom(func(first,second):return near.distance_squared_to(first.center)<near.distance_squared_to(second.center))
			if homes.is_empty(): social.manager._fail("No accessible homes available"); return
			var household_size:=1
			for family in social.families:
				if family.id==a.family_id: household_size=family.members.size(); break
			var available: Array=homes.filter(func(room):return int(room.get("home_capacity_used",0))+household_size<=range(12,int(room.size.x)-8,12).size()*range(12,int(room.size.y)-8,12).size())
			if available.is_empty(): social.manager._fail("No accessible home capacity for household "+household); return
			var chosen: Dictionary=available[int(home_by_family.size())%mini(3,available.size())]
			chosen.home_capacity_used=int(chosen.get("home_capacity_used",0))+household_size
			home_by_family[household]=chosen.id
		a.home_building=home_by_family[household]; a.home_location=interiors.rooms[a.home_building].center
		var workplace: String={"Police":"Police Station","Fire":"Fire Station","Medical":"Medical Station","Civil protection":"Fire Station","Crisis commander":"Police Station"}.get(a.occupation,"")
		if a.school in ["SCHOOL","SCHOOL_STAFF"]: workplace="School"
		a.work_building=room_for(workplace)
		if a.work_building.is_empty(): a.work_building=workplaces[(int(a.get("population_index",0))+7)%workplaces.size()].id
		if a.work_building!=a.home_building and interiors.rooms[a.work_building].kind in ["Home","Apartment"]: interiors.rooms[a.work_building].kind="Workplace"
		a.shop_building=shops[int(a.get("population_index",0))%mini(3,shops.size())].id
		interiors.rooms[a.shop_building].kind="Shop"
		a.school_building=room_for("School")
		for id in [a.home_building,a.work_building,a.shop_building,a.school_building]:
			if interiors.rooms.has(id): interiors.rooms[id].active=true
		for id in a.relationships:
			a.known_locations[id]={"position":social.school_position if a.relationships[id]=="child" else a.home_location,"source":"remembered plan","timestamp":0.0,"confidence":.45}
	var school_room: String=room_for("School")
	if not school_room.is_empty(): social.school_position=interiors.rooms[school_room].door_outside
	var adults: Array=social.manager.agents.filter(func(a):return a.age>=18)
	for i in range(social.manager.agents.size()):
		var a: Dictionary=social.manager.agents[i]
		a.friend_home=a.home_building
		if adults.size()>1:
			var friend: Dictionary=adults[(i+5)%adults.size()]
			a.friend_home=friend.home_building
			if friend.id!=a.id and friend.id not in a.phone.contacts: a.phone.contacts.append(friend.id)
		var location: String=a.home_building
		var draw: float=rng.randf()
		if a.school in ["SCHOOL","SCHOOL_STAFF"] and not school_room.is_empty(): location=school_room; a.routine="SCHOOL"
		elif a.occupation in ["Fire","Medical","Civil protection","Crisis commander"]: location=a.work_building; a.routine="DUTY"
		elif a.occupation=="Police": location=a.work_building; a.routine="PATROL" if draw<.6 else "DUTY"
		elif draw<.35: a.routine="HOME"
		elif draw<.57: location=a.work_building; a.routine="WORK"
		elif draw<.70: location=a.shop_building; a.routine="SHOP"
		elif draw<.81: location=a.friend_home; a.routine="VISIT_FRIEND"
		elif draw<.87 and a.age>=66: location=room_for("Medical Station"); a.routine="HOSPITAL"
		else: a.routine="WALK"
		if a.age<18 and a.school.is_empty(): location=a.home_building; a.routine="HOME"
		if a.routine in ["WALK","PATROL"]:
			var point: Vector2=sidewalk_spawn()
			if point.is_finite(): a.position=point; a.previous_position=point
			else: a.routine="HOME"; location=a.home_building
		if a.routine not in ["WALK","PATROL"]:
			if not interiors.spawn(a,location) and (a.school in ["SCHOOL","SCHOOL_STAFF"] or not interiors.spawn(a,a.home_building)):
				social.manager._fail("No valid interior spawn for "+a.id); return
		a.initial_location=a.routine; a.routine_target=location
		a.routine_until=rng.randf_range(15,45); a.current_goal="Daily routine: "+a.routine.to_lower()
		a.state="ROUTINE"
		for child in a.relationships:
			if a.relationships[child]=="child": a.known_locations[child]={"position":social.school_position,"source":"remembered school schedule","timestamp":0.0,"confidence":.5}
	for v in social.vehicles:
		var driver: Dictionary=social.by_id[v.driver]
		if driver.school!="" or driver.age<18 or rng.randf()>social.config.vehicles_in_use_rate: continue
		if rng.randf()<.55 and driving_spawn(v):
			put_in_vehicle(driver,v,"DRIVING")
			schedule(driver,"DRIVE",driver.work_building,true)
		else:
			put_in_vehicle(driver,v,"PARKED_CAR"); driver.routine="REST_IN_CAR"; driver.routine_until=rng.randf_range(8,25)
	for a in social.manager.agents:
		if not valid_spawn(a): social.manager._fail("Invalid daily spawn for "+a.id); return
	spontaneous.initialize(social,self)
	rng.seed=social.manager.seed_for("behavior")+71071

func sidewalk_spawn() -> Vector2:
	for _attempt in range(256):
		var road: Dictionary=Map.roads[rng.randi_range(0,Map.roads.size()-1)]
		if road.get("elevated",false) or road.get("ramp",false): continue
		var points: PackedVector2Array=road.points
		var index: int=rng.randi_range(0,points.size()-2)
		var direction: Vector2=(points[index+1]-points[index]).normalized()
		var point: Vector2=points[index].lerp(points[index+1],rng.randf())+direction.orthogonal()*(road.width*.5+float(road.get("sidewalk",20))*.5)*(1 if rng.randf()<.5 else -1)
		if Map.clear_point(point,4) and not outdoor_slots.any(func(other):return point.distance_to(other)<10):
			outdoor_slots.append(point); return point
	return Vector2.INF

func put_in_vehicle(a: Dictionary, v: Dictionary, mode: String) -> void:
	if not a.indoor_id.is_empty(): interiors.rooms[a.indoor_id].occupants.erase(a.id)
	a.indoor_id=""; a.interior_transition=""; a.position=v.position; a.previous_position=v.position
	a.riding=v.id; a.location_mode=mode
	if a.id not in v.passengers: v.passengers.append(a.id)

func driving_spawn(v: Dictionary) -> bool:
	for _attempt in range(64):
		var road: Dictionary=Map.roads[rng.randi_range(0,Map.roads.size()-1)]
		if road.get("elevated",false) or road.get("ramp",false): continue
		var points: PackedVector2Array=road.points
		if points.size()<4: continue
		var index: int=rng.randi_range(1,points.size()-2)
		var direction: Vector2=(points[index+1]-points[index]).normalized()
		var point: Vector2=points[index]
		var lane_center: float=preload("res://scripts/traffic_rules.gd").lane_offset(road)
		var body: Vector2=point+Convention.right(direction)*lane_center
		var probe: Dictionary=v.duplicate(); probe.heading=direction.angle(); probe.position=point; probe.body_position=body
		var clear:=true
		for other in social.vehicles:
			if other.id!=v.id and not SAT.contact(probe,body,body,other,SAT.body_position(other),SAT.body_position(other)).is_empty(): clear=false; break
		for rect in Map.lots+Map.rock_obstacles:
			if not social.traffic.static_contact(probe,body,body,rect).is_empty(): clear=false; break
		if not clear or not social.traffic.physics_query(probe,body,body).is_empty(): continue
		Map.release_parking(v.id); social.traffic.reservations.erase(v.id)
		v.position=point; v.body_position=body; v.heading=direction.angle(); v.lane_offset=lane_center; v.target_lane_offset=lane_center
		v.speed=20.0; v.status="MOVING"; v.parking_exit=PackedVector2Array(); v.parking_bay=""
		return true
	return false

func schedule(a: Dictionary, action: String, room_id: String, drive: bool=false) -> void:
	if not interiors.rooms.has(room_id): return
	a.routine=action; a.routine_target=room_id; a.routine_use_vehicle=drive and not a.vehicle_id.is_empty()
	a.routine_until=social.manager.elapsed_seconds+rng.randf_range(25,55); a.routine_dwell_started=-1.0
	a.current_goal="Daily routine: "+action.to_lower(); a.state="ROUTINE"
	if a.routine_use_vehicle:
		var key: String="routine:"+a.id
		a.known_locations[key]={"position":interiors.rooms[room_id].door_outside,"source":"own schedule","timestamp":social.manager.elapsed_seconds,"confidence":1.0}
		a.social_target=key
	social.emit_event("routine.changed",a.id,{"routine":action,"building":room_id})

func valid_spawn(a: Dictionary) -> bool:
	if not a.position.is_finite(): return false
	if a.get("riding","")!="":
		return social.vehicles.any(func(v):return v.id==a.riding and a.id in v.passengers and v.position.distance_to(a.position)<.01)
	if a.get("indoor_id","")!="": return interiors.contains(a.indoor_id,a.position)
	return Map.clear_point(a.position,3)

func tick(seconds: float) -> void:
	for room in interiors.rooms.values(): room.door_is_open=social.manager.elapsed_seconds<float(room.door_open_until)
	for a in social.manager.agents:
		if a.health<=0 or a.state in ["SHELTERED","EXPOSED","SAFE"]: continue
		var moving: bool=a.position.distance_to(a.get("previous_position",a.position))>.1
		if social.manager.phase=="LIVING" and a.family_id!="":
			var oldest:=0.0
			for id in a.relationships:
				if a.known_locations.has(id): oldest=maxf(oldest,social.manager.elapsed_seconds-float(a.known_locations[id].get("timestamp",0)))
			a.family_concern=clampf(oldest/300.0*social.config.family_priority,.05,.85)
		a.fatigue=clampf(a.fatigue+(seconds*.08 if moving else -seconds*.1),0,100)
		a.safety=clampf(1-a.panic_level/100,0,1)
		a.social_attachment=clampf(a.sociability/100+(.1 if a.family_id!="" else 0),0,1)
		a.needs={"safety":a.safety,"fatigue":a.fatigue/100,"stress":a.panic_level/100,"family":a.family_concern,"health":a.health/100,"social_attachment":a.social_attachment}
		if social.manager.phase!="LIVING": continue
		if a.get("police_unit_busy",false): continue
		if a.get("emergency_evacuating",false): continue
		if social.cognition.move(a,seconds): continue
		a.previous_position=a.position; a.movement_speed=a.walk_speed
		if a.get("riding","")!="":
			if a.routine=="REST_IN_CAR" and social.manager.elapsed_seconds>=a.routine_until: schedule(a,"DRIVE",a.work_building,true)
			continue
		if a.routine_use_vehicle:
			if a.indoor_id!="": interiors.exit_building(a,seconds)
			continue
		if a.routine in ["WALK","PATROL"]:
			if a.indoor_id!="": interiors.exit_building(a,seconds); continue
			if not a.has("routine_walk") or a.position.distance_to(a.routine_walk)<5:
				a.routine_walk=sidewalk_spawn()
			if a.routine_walk.is_finite(): social._walk_toward(a,a.routine_walk,a.walk_speed,seconds)
		elif a.routine!="REST_OUTDOOR":
			if interiors.go_to(a,a.routine_target,seconds) and a.routine_dwell_started<0:
				a.routine_dwell_started=social.manager.elapsed_seconds
				a.routine_until=maxf(a.routine_until,social.manager.elapsed_seconds+20)
		if social.manager.elapsed_seconds>=a.routine_until and a.age>=18 and (a.routine in ["WALK","PATROL","REST_OUTDOOR"] or a.indoor_id==a.routine_target):
			var hour: float=fmod(social.config.day_start_hour+social.manager.elapsed_seconds*social.config.routine_clock_rate/3600,24)
			if a.school!="" or a.occupation in ["Fire","Medical","Civil protection","Crisis commander"]: schedule(a,"DUTY",a.work_building)
			elif a.occupation=="Police": schedule(a,"PATROL",a.work_building)
			elif hour>=8 and hour<17 and (a.occupation in ["Family member","Technician","Student"] or "child" in a.relationships.values()): schedule(a,"WORK",a.work_building,not a.vehicle_id.is_empty() and rng.randf()<.35)
			else: schedule(a,["HOME","SHOP","VISIT_FRIEND"][rng.randi_range(0,2)],[a.home_building,a.shop_building,a.friend_home][rng.randi_range(0,2)])
	if social.manager.phase=="LIVING" and social.config.spontaneous_actions: spontaneous.tick()

func reserve_destination(v: Dictionary, target: Vector2) -> Dictionary:
	if parking_destinations.has(v.id): return parking_destinations[v.id]
	var candidates: Array=[]
	for lot in Map.parking_lots:
		if not preload("res://scripts/station_parking.gd").allows(lot,v): continue
		for bay in lot.bays:
			if bay.occupied_by.is_empty(): candidates.append(bay)
	candidates.sort_custom(func(a,b):return target.distance_squared_to(a.position)<target.distance_squared_to(b.position))
	for bay in candidates:
		var probe: Dictionary=v.duplicate(); probe.heading=bay.heading
		var clear:=true
		for other in social.vehicles:
			if other.id!=v.id and not SAT.contact(probe,bay.position,bay.position,other,SAT.body_position(other),SAT.body_position(other)).is_empty(): clear=false; break
		for other in parking_destinations.values():
			if bay.position.distance_to(other.position)<maxf(v.length,v.width)+8: clear=false; break
		if not clear: continue
		bay.occupied_by="DEST:"+v.id; parking_destinations[v.id]=bay
		return bay
	return {}

func driving_route(v: Dictionary, start: Vector2, destination: Vector2, emergency: bool, height: float, knowledge: Dictionary) -> PackedVector2Array:
	var bay: Dictionary=reserve_destination(v,destination)
	if bay.is_empty(): return PackedVector2Array()
	var route: PackedVector2Array=social._vehicle_route(start,bay.approach[0],emergency,height,knowledge)
	if route.is_empty(): return route
	route.append_array(bay.approach)
	return route

func vehicle_arrived(v: Dictionary, driver: Dictionary) -> void:
	if parking_destinations.has(v.id):
		var bay: Dictionary=parking_destinations[v.id]
		bay.occupied_by=v.id; v.parking_bay=bay.id; v.heading=bay.heading; v.parking_heading=bay.heading
		v.parking_exit=bay.approach.duplicate(); v.parking_exit.reverse()
		parking_destinations.erase(v.id)
	driver.social_target=""; driver.routine_use_vehicle=false; driver.location_mode="OUTDOOR"
	driver.routine="WORK"; driver.routine_until=social.manager.elapsed_seconds+45

func warning() -> void:
	spontaneous.close()
	for a in social.manager.agents:
		a.routine_use_vehicle=false
		if a.social_target.begins_with("routine:"): a.social_target=""
		if a.interior_transition=="ENTER" and interiors.rooms.has(a.get("interior_transition_room","")):
			a.indoor_id=a.interior_transition_room; a.indoor_exit=interiors.rooms[a.indoor_id].door_outside
			if a.id not in interiors.rooms[a.indoor_id].occupants: interiors.rooms[a.indoor_id].occupants.append(a.id)
		a.interior_transition=""
	for v in social.vehicles:
		v.destination=""; v.route=PackedVector2Array(); v.route_index=0
		if v.id in parking_destinations:
			parking_destinations[v.id].occupied_by=""; parking_destinations.erase(v.id)

func close() -> void:
	spontaneous.close()

func summary_text() -> String:
	var indoor: int=social.manager.agents.filter(func(a):return a.get("indoor_id","")!="").size()
	var riders: int=social.manager.agents.filter(func(a):return a.get("riding","")!="").size()
	var hour: float=fmod(social.config.day_start_hour+social.manager.elapsed_seconds*social.config.routine_clock_rate/3600,24)
	return "\nDaily city: %02d:%02d | %d indoors / %d in vehicles\nOpenJev %s / %s: %d decisions, %d fallbacks"%[int(hour),int(fmod(hour,1)*60),indoor,riders,spontaneous.config.model,spontaneous.status,spontaneous.completed,spontaneous.fallbacks]

func release_destination(v: Dictionary) -> void:
	if parking_destinations.has(v.id):
		var bay: Dictionary=parking_destinations[v.id]
		if bay.occupied_by=="DEST:"+v.id: bay.occupied_by=""
		parking_destinations.erase(v.id)
