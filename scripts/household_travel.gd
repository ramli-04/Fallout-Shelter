extends RefCounted
## Agreements and observed/communicated positions drive behavior; Director metrics may inspect truth.
var _social_ref: WeakRef
var social: RefCounted:
	get: return _social_ref.get_ref() if _social_ref!=null else null
	set(value): _social_ref=weakref(value) if value!=null else null
var groups: Dictionary={}
var next_plan:=0.0

func initialize(owner_social: RefCounted) -> void:
	social=owner_social; groups.clear(); next_plan=0
	for family in social.families:
		var adults: Array=family.members.filter(func(id):return social.by_id[id].age>=18)
		if adults.is_empty(): continue
		adults.sort_custom(func(a,b):return social.by_id[a].leadership>social.by_id[b].leadership)
		family.leader_id=adults[0]; family.vehicle_id=""; family.destination=""; family.last_offer=""
		family.walk_speed=INF
		for id in family.members: family.walk_speed=minf(family.walk_speed,social.by_id[id].walk_speed)
		for v in social.vehicles:
			if v.kind!="Civilian" or v.owner not in family.members: continue
			v.household_id=family.id
			if family.vehicle_id.is_empty() and v.capacity>=family.members.size(): family.vehicle_id=v.id; family.leader_id=v.driver
		family.home_building=social.by_id[family.leader_id].home_building
		groups[family.id]=family

func vehicle(id: String) -> Dictionary:
	for v in social.vehicles:
		if v.id==id: return v
	return {}

func offer(leader: Dictionary, destination: String) -> void:
	if not groups.has(leader.family_id) or not leader.beliefs.has(destination): return
	var group: Dictionary=groups[leader.family_id]
	if group.leader_id!=leader.id: return
	group.destination=destination; group.last_offer=destination
	leader.travel_group=group.id; leader.group_leader=leader.id
	leader.group_destination=destination; leader.expected_boarders=group.members.duplicate()
	var car: Dictionary=vehicle(group.vehicle_id)
	var meeting: Vector2=car.position if not car.is_empty() else leader.position
	leader.group_on_foot=group.vehicle_id.is_empty()
	leader.family_meeting=meeting; leader.boarding_vehicle=group.vehicle_id
	if not car.is_empty():
		car.boarding_started=social.manager.elapsed_seconds
		if car.status=="MOVING": car.boarding_stop=true
	var plan: Dictionary={"destination":destination,"vehicle":group.vehicle_id,"leader":leader.id,"meeting":meeting}
	for id in group.members:
		if id==leader.id: continue
		var member: Dictionary=social.by_id[id]
		if social.daily.interiors.can_see(leader,member): receive(member,leader,{"subject":"family_plan","value":plan},true)
		else: social.send_phone(leader,id,{"subject":"family_plan","value":plan})
	social.emit_event("family.travel_planned",group.id,{"leader":leader.id,"destination":destination,"vehicle":group.vehicle_id})

func receive(a: Dictionary, sender: Dictionary, body: Dictionary, direct: bool=false) -> void:
	if a.get("police_unit_busy",false) or a.get("evacuation_group","")!="": return
	if a.family_id.is_empty() or a.family_id!=sender.family_id: return
	if body.get("subject","")=="family_accept":
		if not body.get("value",false) and a.has("expected_boarders"): a.expected_boarders.erase(sender.id)
		return
	if body.get("subject","")!="family_plan" or not body.get("value") is Dictionary: return
	var plan: Dictionary=body.value
	if not plan.get("meeting") is Vector2 or not plan.get("destination") is String: return
	a.family_plans[sender.id]=plan.duplicate(true)
	var accepted: bool=a.age<18 or a.objective.is_empty() or a.objective==plan.destination or social.config.family_priority+a.cooperation/200.0>=.75
	if a.age>=18 and a.get("riding","")!="" and a.riding!=plan.get("vehicle",""): accepted=false
	if not a.beliefs.has(plan.destination) or a.beliefs[plan.destination].get("unavailable",false): accepted=false
	# Children can follow a guardian's reported shelter without gaining its hidden state.
	if a.age<18: accepted=true
	a.family_disagreement=not accepted
	if accepted:
		a.travel_group=a.family_id; a.group_leader=sender.id; a.group_destination=plan.destination
		a.group_on_foot=plan.get("vehicle","")==""
		a.family_meeting=plan.meeting; a.boarding_vehicle=plan.get("vehicle","")
		if a.boarding_vehicle=="": a.known_locations[sender.id]={"position":plan.meeting,"source":"family meeting instruction","timestamp":social.manager.elapsed_seconds,"confidence":.9}
		a.known_locations["meeting:"+a.family_id]={"position":plan.meeting,"source":"conversation" if direct else "family message","timestamp":social.manager.elapsed_seconds,"confidence":.9}
		if a.age>=18 and a.beliefs.has(plan.destination) and a.objective!=plan.destination:
			a.objective=plan.destination; social.manager._set_state(a,"MOVING")
	if direct:
		if not accepted and sender.has("expected_boarders"): sender.expected_boarders.erase(a.id)
	else: social.send_phone(a,sender.id,{"subject":"family_accept","value":accepted})
	if not accepted:
		a.travel_group=""; a.group_leader=""; a.boarding_vehicle=""; a.group_on_foot=false
	social.emit_event("family.negotiated",a.id,{"leader":sender.id,"destination":plan.destination,"accepted":accepted})

func tick(_seconds: float) -> void:
	if social.manager.phase not in ["EVACUATION","BOMB_FALL"] or social.manager.elapsed_seconds<next_plan: return
	next_plan=social.manager.elapsed_seconds+1
	for group in groups.values():
		var leader: Dictionary=social.by_id[group.leader_id]
		if leader.get("police_unit_busy",false) or leader.get("evacuation_group","")!="" or leader.health<=0 or leader.state in ["SHELTERED","EXPOSED","SAFE"]: continue
		if not leader.objective.is_empty() and group.last_offer!=leader.objective: offer(leader,leader.objective)

func prepare_departure(v: Dictionary, driver: Dictionary) -> bool:
	if not driver.has("expected_boarders") or driver.pickup_target!="": return true
	var expected: Array=driver.expected_boarders
	var missing: Array=[]
	for id in expected:
		if id not in v.passengers: missing.append(id)
	if missing.is_empty(): return true
	var elapsed: float=social.manager.elapsed_seconds-float(v.get("boarding_started",social.manager.elapsed_seconds))
	if not v.has("boarding_started"): v.boarding_started=social.manager.elapsed_seconds
	if elapsed<float(social.daily.settings.boarding_timeout_seconds):
		driver.current_goal="Wait for household boarding: "+str(missing.size())
		return false
	if social.config.family_priority<.35 or priority(driver)<.35 or driver.get("allow_leave_behind",false):
		v.deliberately_left_behind=missing.duplicate(); driver.expected_boarders=v.passengers.duplicate()
		social.emit_event("family.left_behind",driver.id,{"vehicle":v.id,"missing":missing,"reason":"explicit priority decision after boarding timeout","family_priority":priority(driver)})
		return true
	for id in missing:
		var known: Dictionary=driver.known_locations.get(id,{})
		if not known.is_empty() and driver.position.distance_to(known.position)>social.manager.living.observation_radius:
			driver.pickup_target=id; driver.social_target=id
			social.emit_event("school.pickup_started",driver.id,{"member":id,"source":known.source})
			return true
	driver.current_goal="Wait for missing family; no reliable pickup location"
	return false

func move_member(a: Dictionary, seconds: float) -> bool:
	if a.health<=0 or a.state in ["SHELTERED","EXPOSED","SAFE"]: return false
	if a.get("pickup_walk",false): return pickup_walk(a,seconds)
	if a.get("travel_group","")=="" or not groups.has(a.travel_group): return false
	var group: Dictionary=groups[a.travel_group]
	if a.age<18 and a.get("supervisor","") in social.school.staff:
		var guardian: Dictionary=social.by_id[group.leader_id]
		if not social.daily.interiors.can_see(a,guardian): return false
	if a.get("boarding_vehicle","")!="":
		var car: Dictionary=vehicle(a.boarding_vehicle)
		if car.is_empty():
			a.boarding_vehicle=""; a.group_on_foot=true; return false
		var visible_car: bool=a.get("indoor_id","")=="" and a.position.distance_to(car.position)<=social.manager.living.observation_radius and social.daily.interiors.corridor_clear(a.position,car.position,-1)
		if visible_car and car.status in ["ACCIDENT","REMOVED","DESTROYED"]:
			a.boarding_vehicle=""; a.group_on_foot=true; return false
		if a.id==car.driver: return false
		if a.get("indoor_id","")!="": social.daily.interiors.exit_building(a,seconds); return true
		var meeting: Vector2=a.family_meeting
		if visible_car: meeting=car.position
		a.current_goal="Join household vehicle "+car.id
		if a.position.distance_to(meeting)>25: social._walk_toward(a,meeting,minf(a.walk_speed,group.walk_speed),seconds)
		elif social.board(car,a): social.emit_event("family.boarded",a.id,{"vehicle":car.id})
		return true
	if a.get("indoor_id","")!="": social.daily.interiors.exit_building(a,seconds); return true
	if a.id==group.leader_id:
		if priority(a)>=.5:
			for id in group.members:
				var member: Dictionary=social.by_id[id]
				if member.get("travel_group","")!=group.id: continue
				if not social.daily.interiors.can_see(a,member):
					var remembered: Dictionary=a.known_locations.get(id,{})
					if not remembered.is_empty() and social.manager.elapsed_seconds-float(remembered.get("timestamp",0))<float(social.daily.settings.missing_member_wait_seconds):
						a.current_goal="Wait after losing sight of family "+id; return true
					if priority(a)>.85 and not remembered.is_empty():
						social._walk_toward(a,remembered.position,group.walk_speed,seconds); return true
					continue
				if a.position.distance_to(member.position)>minf(float(social.daily.settings.family_separation_distance),social.manager.living.observation_radius*.75):
					a.current_goal="Wait for visible family member "+id
					social.manager._set_state(a,"WAITING_GROUP"); return true
		a.movement_speed=minf(a.run_speed,group.walk_speed)
		if a.state=="WAITING_GROUP": social.manager._set_state(a,"MOVING")
		return false
	if a.beliefs.has(a.get("group_destination","")):
		var target: Vector2=a.beliefs[a.group_destination].position
		if a.position.distance_to(target)<65:
			a.objective=a.group_destination
			social._walk_toward(a,target,minf(a.run_speed,group.walk_speed),seconds)
			if a.position.distance_to(target)<.01: social.manager.admit_arrival(a)
			return true
	var leader: Dictionary=social.by_id[group.leader_id]
	var seen: bool=social.daily.interiors.can_see(a,leader)
	var known: Dictionary=a.known_locations.get(group.leader_id,{})
	if not seen and known.is_empty(): a.current_goal="Wait for family information"; return true
	var point: Vector2=leader.position if seen else known.position
	a.movement_speed=minf(a.run_speed,group.walk_speed)
	if a.position.distance_to(point)>float(social.daily.settings.family_follow_distance): social._walk_toward(a,point,a.movement_speed,seconds)
	elif seen and leader.state=="SHELTERED": a.objective=leader.shelter_id; social.manager.admit_arrival(a)
	return true

func pickup_walk(a: Dictionary, seconds: float) -> bool:
	a.movement_speed=a.walk_speed
	var id: String=a.pickup_target
	if id.is_empty(): a.pickup_walk=false; return false
	var known: Dictionary=a.known_locations.get(id,{})
	if known.is_empty(): a.current_goal="Await pickup location update"; return true
	var child: Dictionary=social.by_id[id]
	if a.id not in child.guardians: a.pickup_target=""; a.pickup_walk=false; return false
	if social.daily.interiors.can_see(a,child) and a.position.distance_to(child.position)<45:
		child.supervisor=a.id
		child.known_locations[a.id]={"position":a.position,"source":"direct observation","timestamp":social.manager.elapsed_seconds,"confidence":1.0}
		var car: Dictionary=vehicle(a.vehicle_id)
		if not car.is_empty():
			child.family_meeting=car.position; child.boarding_vehicle=car.id; child.travel_group=a.family_id; child.group_leader=a.id
			child.known_locations["meeting:"+a.family_id]={"position":car.position,"source":"guardian instruction","timestamp":social.manager.elapsed_seconds,"confidence":1.0}
			a.expected_boarders=[a.id,child.id]; car.boarding_started=social.manager.elapsed_seconds
		a.pickup_walk=false; a.pickup_target=""; a.social_target=""
		social.emit_event("school.pickup_completed",a.id,{"child":id,"position":a.position})
		return true
	if a.get("indoor_id","")!="":
		if a.indoor_id==child.get("indoor_id","") and social.daily.interiors.can_see(a,child):
			a.position=a.position.move_toward(child.position,a.walk_speed*seconds); return true
		if a.indoor_id==a.school_building:
			a.current_goal="Search school room and ask staff for last known child location"
			var room: Dictionary=social.daily.interiors.rooms[a.indoor_id]
			var search_points: Array=[room.center]
			for y in range(15,int(room.size.y)-10,30):
				for x in range(15,int(room.size.x)-10,30): search_points.append(room.center+(Vector2(x,y)-room.size*.5).rotated(room.angle))
			var index: int=int(a.get("pickup_search_index",0))%search_points.size()
			var point: Vector2=search_points[index]
			a.position=a.position.move_toward(point,a.walk_speed*seconds)
			if a.position.distance_to(point)<.01: a.pickup_search_index=index+1
			return true
		social.daily.interiors.exit_building(a,seconds); return true
	if a.school_building!="" and known.position.distance_to(social.school_position)<150:
		social.daily.interiors.go_to(a,a.school_building,seconds)
	else: social._walk_toward(a,known.position,a.walk_speed,seconds)
	return true

func vehicle_arrived(driver: Dictionary, target: String) -> void:
	if driver.pickup_target!="" and target==driver.pickup_target: driver.pickup_walk=true

func priority(a: Dictionary) -> float:
	return clampf(social.config.family_priority+(float(a.empathy)-float(a.self_preservation))/400.0+float(a.family_concern)*.1,0,1)
