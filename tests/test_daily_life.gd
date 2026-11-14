extends SceneTree
const Manager=preload("res://scripts/simulation_manager.gd")
const Map=preload("res://scripts/city_map.gd")
const SAT=preload("res://scripts/vehicle_collisions.gd")
const Spontaneous=preload("res://scripts/spontaneous_actions.gd")
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks+=1
	if not value: failures+=1; printerr("FAIL: "+message)
func outdoors(social: RefCounted, a: Dictionary, point: Vector2) -> void:
	if a.get("indoor_id","")!="": social.daily.interiors.rooms[a.indoor_id].occupants.erase(a.id)
	a.indoor_id=""; a.interior_transition=""; a.riding=""; a.position=point; a.previous_position=point
	a.erase("social_walk_route")
	a.health=100; a.state="MOVING"; a.pickup_target=""; a.pickup_walk=false
func run() -> void:
	var manager:=Manager.new(); root.add_child(manager); manager.set_process(false)
	check(manager.load_settings(),"configuration loads")
	manager.social_config.llm_agents=0; manager.social_config.spontaneous_actions=false
	manager.social_config.phone_rate=1; manager.social_config.network_availability=1
	manager.initialize_run(); manager.ai_bridge.set_process(false); manager.social.close(); manager.social.next_send=INF
	var social: RefCounted=manager.social
	check(manager.last_setup_error.is_empty(),"living city setup succeeds")
	var indoor: Array=manager.agents.filter(func(a):return a.get("indoor_id","")!="")
	var driving: Array=social.vehicles.filter(func(v):return v.status=="MOVING")
	check(indoor.size()>manager.agents.size()/3,"diverse indoor civilian/worker spawning")
	check(not driving.is_empty(),"driving vehicle spawning")
	check(manager.agents.any(func(a):return a.location_mode=="PARKED_CAR"),"parked-car occupants spawn")
	for a in manager.agents: check(social.daily.valid_spawn(a),"validated spawn "+a.id)
	for i in range(social.vehicles.size()):
		for j in range(i):
			var a: Dictionary=social.vehicles[i]; var b: Dictionary=social.vehicles[j]
			check(SAT.contact(a,SAT.body_position(a),SAT.body_position(a),b,SAT.body_position(b),SAT.body_position(b)).is_empty(),"driving/parked fleet has no overlapping spawns")
	for id in social.school.students: check(social.by_id[id].indoor_id==social.daily.room_for("School"),"students start inside school")
	# An indoor room joins the outdoor graph only through its door path.
	manager.phase="LIVING"
	var actor: Dictionary=indoor.filter(func(a):return a.age>=18)[0]
	var room_id: String=actor.indoor_id
	var room: Dictionary=social.daily.interiors.rooms[room_id]
	actor.movement_speed=actor.walk_speed
	var blocked_position: Vector2=actor.position
	Map.set_closure("TEST-DOOR",room.door_outside,true)
	check(not social.daily.interiors.exit_building(actor,.1) and actor.position==blocked_position,"blocked doorway cannot teleport an agent through an obstruction")
	Map.set_closure("TEST-DOOR",room.door_outside,false)
	for _step in range(800):
		var before: Vector2=actor.position
		var complete: bool=social.daily.interiors.exit_building(actor,.1)
		check(actor.position.distance_to(before)<=actor.walk_speed*.1+.001,"door exit movement is bounded")
		if complete: break
	check(actor.indoor_id=="" and actor.position.distance_to(room.door_outside)<.01,"exit uses actual outdoor doorway")
	check(Map.clear_point(actor.position,3),"door joins valid outdoor navigation")
	for _step in range(800):
		var before: Vector2=actor.position
		var complete: bool=social.daily.interiors.go_to(actor,room_id,.1)
		check(actor.position.distance_to(before)<=actor.walk_speed*.1+.001,"door entry movement is bounded")
		if complete: break
	check(actor.indoor_id==room_id and social.daily.interiors.contains(room_id,actor.position),"outdoor to indoor navigation")
	# A warning halfway through an entry cannot strand someone in a building footprint.
	for _step in range(800):
		if social.daily.interiors.exit_building(actor,.1): break
	social.daily.interiors.go_to(actor,room_id,.1)
	check(actor.interior_transition=="ENTER","entry transition starts before the warning")
	social.daily.warning()
	check(actor.indoor_id==room_id,"warning retains the interrupted entry's room identity")
	for _step in range(800):
		var before: Vector2=actor.position
		var complete: bool=social.daily.interiors.exit_building(actor,.1)
		check(actor.position.distance_to(before)<=actor.walk_speed*.1+.001,"warning interruption preserves bounded doorway movement")
		if complete: break
	check(actor.indoor_id=="" and Map.clear_point(actor.position,3),"interrupted entry can exit to valid outdoor navigation")
	for _step in range(800):
		if social.daily.interiors.go_to(actor,room_id,.1): break
	# Private family locations remain remembered until evidence reaches the agent.
	var relative_id: String=actor.relationships.keys()[0] if not actor.relationships.is_empty() else manager.agents[-1].id
	var relative: Dictionary=social.by_id[relative_id]
	actor.relationships[relative_id]="spouse"
	actor.known_locations[relative_id]={"position":Vector2(42,42),"source":"remembered plan","timestamp":0,"confidence":.4}
	outdoors(social,relative,room.door_outside)
	social._observe(actor)
	check(actor.known_locations[relative_id].position==Vector2(42,42),"walls do not reveal relatives outside")
	# Role-restricted typed spontaneous actions cannot invent movement or leak world state.
	var state: Dictionary=social.daily.spontaneous.state_for(actor)
	check(not state.has("agents") and not state.has("impact") and not state.has("family_positions"),"OpenJev receives only private needs and memories")
	check(Spontaneous.parse_choice({"answers":{"action":{"choice":"teleport","confidence":1}}},{"rest":"rest"})=="","unknown OpenJev action rejected")
	check(Spontaneous.parse_choice({"answers":{"action":{"choice":"rest","confidence":.8}}},{"rest":"rest"})=="rest","OpenJev typed choice accepted")
	var student: Dictionary=social.by_id[social.school.students[0]]
	check(not social.daily.spontaneous.choices(student).has("drive"),"children cannot request spontaneous driving")
	# Household departure waits for actual boarding and respects vehicle capacity.
	var group: Dictionary=social.families.filter(func(f):return f.get("vehicle_id","")!="" and f.members.size()>1)[0]
	var leader: Dictionary=social.by_id[group.leader_id]
	var car: Dictionary=social.households.vehicle(group.vehicle_id)
	car.status="PARKED"; car.speed=0; car.passengers=[]
	for index in range(group.members.size()):
		var member: Dictionary=social.by_id[group.members[index]]
		outdoors(social,member,car.position+Vector2(0,index*8)); member.objective="S1"; member.supervisor=""
	leader.position=car.position; leader.objective="S1"
	car.status="MOVING"; car.speed=20
	social.households.offer(leader,"S1")
	check(car.get("boarding_stop",false),"moving household vehicle requests a boarding stop")
	var car_before: Vector2=car.position
	social._move_vehicles(.1)
	check(car.speed<20 and car.position.distance_to(car_before)<=2.01,"boarding stop brakes without teleporting")
	car.speed=0; car.status="PARKED"; car.boarding_stop=false
	leader.position=car.position
	social.board(car,leader)
	check(not social.households.prepare_departure(car,leader),"departure waits for missing boarders")
	var old_capacity: int=car.capacity; car.capacity=car.passengers.size()
	var follower: Dictionary=social.by_id[group.members.filter(func(id):return id!=leader.id)[0]]
	check(not social.board(car,follower),"household seat capacity enforced")
	car.capacity=old_capacity
	var priority: float=social.config.family_priority
	social.config.family_priority=.1; car.boarding_started=-100
	check(social.households.prepare_departure(car,leader) and car.has("deliberately_left_behind"),"leaving missing passengers requires an explicit timeout/priority decision")
	social.config.family_priority=priority; leader.expected_boarders=group.members.duplicate(); car.boarding_started=0
	for id in group.members:
		if id==leader.id: continue
		var member: Dictionary=social.by_id[id]
		member.travel_group=group.id; member.boarding_vehicle=car.id; member.family_meeting=car.position
		for _step in range(300):
			var before: Vector2=member.position
			social.households.move_member(member,.1)
			check(member.position.distance_to(before)<=member.walk_speed*.1+.001,"family boarding approach never teleports")
			if member.get("riding","")==car.id: break
	check(social.households.prepare_departure(car,leader),"departure allowed only after expected passengers board")
	for id in car.passengers: check(social.by_id[id].position.distance_to(car.position)<65,"boarded passengers have physical positions")
	var couple: Dictionary=social.families.filter(func(f):return f.members.size()==2 and social.by_id[f.members[0]].age>=18 and social.by_id[f.members[1]].age>=18)[0]
	var proposer: Dictionary=social.by_id[couple.members[0]]
	var dissenter: Dictionary=social.by_id[couple.members[1]]
	var own_destination: String="S2"
	dissenter.objective=own_destination; dissenter.cooperation=0
	var previous_priority: float=social.config.family_priority
	social.config.family_priority=0
	social.households.receive(dissenter,proposer,{"subject":"family_plan","value":{"destination":"S1","vehicle":"","leader":proposer.id,"meeting":proposer.position}},true)
	check(dissenter.get("family_disagreement",false) and dissenter.objective==own_destination and dissenter.travel_group=="","family members may reject a shelter proposal and keep their own decision")
	social.config.family_priority=previous_priority
	# Walking groups use the slowest member and wait for visible stragglers.
	var lot: Dictionary=Map.parking_lots[0]
	var base: Vector2=lot.position
	for id in group.members:
		var member: Dictionary=social.by_id[id]
		outdoors(social,member,base); member.boarding_vehicle=""; member.travel_group=group.id; member.group_leader=leader.id; member.group_on_foot=true
	car.passengers=[]; leader.position=base+lot.tangent*25; follower.position=base-lot.tangent*15
	manager.phase="EVACUATION"
	check(social.households.move_member(leader,.1),"group leader waits for visible separated member")
	var before_follow: Vector2=follower.position
	social.households.move_member(follower,.1)
	check(follower.position.distance_to(before_follow)<=group.walk_speed*.1+.001,"group navigation uses shared walking speed")
	check(follower.position.distance_to(leader.position)<before_follow.distance_to(leader.position),"follower closes distance physically")
	social.next_tick=0; social.tick(0)
	check(group.status=="REUNITED","nearby household members reunify through physical proximity")
	var last_known: Dictionary=leader.known_locations.get(follower.id,{}).duplicate(true)
	outdoors(social,follower,base-lot.tangent*100)
	follower.travel_group=group.id; follower.group_leader=leader.id; follower.group_on_foot=true; follower.boarding_vehicle=""
	follower.group_destination="S4"; follower.known_locations[leader.id]={"position":leader.position,"source":"direct observation","timestamp":manager.elapsed_seconds,"confidence":1.0}
	social.next_tick=0; social.tick(0)
	check(group.status=="SEPARATED","separation detection records stragglers")
	check(leader.known_locations.get(follower.id,{})==last_known,"losing sight does not reveal a relative's new position")
	for _step in range(500):
		social.households.move_member(follower,.1)
		if follower.position.distance_to(leader.position)<40: break
	social.next_tick=0; social.tick(0)
	check(group.status=="REUNITED","walking back physically restores family reunion")
	# A parent must reach the child, including entering the school room.
	var parent: Dictionary=social.by_id[student.guardians[0]]
	parent.pickup_target=student.id; parent.pickup_walk=true
	var school_id: String=social.daily.room_for("School")
	outdoors(social,parent,social.daily.interiors.rooms[school_id].door_outside)
	parent.pickup_target=student.id; parent.pickup_walk=true; parent.school_building=school_id
	if student.indoor_id!="": social.daily.interiors.rooms[student.indoor_id].occupants.erase(student.id)
	student.indoor_id=school_id; student.riding=""; student.health=100
	student.position=social.daily.interiors.rooms[school_id].center
	parent.known_locations[student.id]={"position":social.school_position,"source":"remembered school plan","timestamp":0,"confidence":.5}
	for _step in range(1200):
		var before: Vector2=parent.position
		social.households.pickup_walk(parent,.1)
		check(parent.position.distance_to(before)<=parent.walk_speed*.1+.001,"school pickup uses doors and bounded movement")
		if parent.pickup_target=="": break
	if parent.pickup_target!="": print("PICKUP_DIAG "+str({"parent":parent.id,"position":parent.position,"indoor":parent.indoor_id,"transition":parent.interior_transition,"child":student.id,"child_position":student.position,"child_room":student.indoor_id,"visible":social.daily.interiors.can_see(parent,student),"goal":parent.current_goal}))
	check(parent.pickup_target=="" and student.supervisor==parent.id,"school pickup reunites a physically present parent and child")
	check(social.history.any(func(e):return e.event_type=="school.pickup_completed"),"school pickup event recorded for Kafka/Director")
	# The pre-warning duration is configurable and the manual alarm remains available.
	manager.initialize_run(); manager.ai_bridge.set_process(false); manager.social.close()
	manager.social.config.pre_disaster_seconds=1.0; manager.social.config.automatic_warning=true
	manager.start(); manager.advance_clock(1.25)
	check(manager.phase=="EVACUATION","configured pre-disaster duration triggers warning")
	check(manager.social.daily.interiors.slots.size()>0,"reset rebuilds valid spawn reservations")
	print("Living city: %d checks / %d failures | %d indoor / %d driving initial"%[checks,failures,indoor.size(),driving.size()])
	manager.queue_free(); await process_frame; await process_frame
	quit(1 if failures else 0)
