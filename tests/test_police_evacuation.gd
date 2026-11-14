extends SceneTree
const Manager=preload("res://scripts/simulation_manager.gd")
const Map=preload("res://scripts/city_map.gd")
const Routes=preload("res://scripts/road_routes.gd")
const State=preload("res://scripts/shelter_state.gd")
var manager: Node
var sim: RefCounted
var evac: RefCounted
var checks:=0
var failures:=0
var movement_valid:=true
var vehicle_valid:=true
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1; printerr("FAIL: "+label)
func step() -> void:
	var previous: Dictionary={}
	var was_riding: Dictionary={}
	for a in manager.agents: previous[a.id]=a.position; was_riding[a.id]=a.riding
	manager.elapsed_seconds+=.2; manager.emergency.tick(0)
	sim.police.tick(.2); evac.tick(.2)
	for a in manager.agents:
		var bound: float=maxf(a.walk_speed,a.run_speed)*.2+.01 if was_riding[a.id]=="" and a.riding=="" else 115*.2+20
		if a.position.distance_to(previous[a.id])>bound and movement_valid: print("MOTION ",a.id," ",a.position.distance_to(previous[a.id])," bound ",bound," ",a.state," / ",a.get("evacuation_member_status",""))
		movement_valid=movement_valid and a.position.distance_to(previous[a.id])<=bound
	var cars: Dictionary={}
	for v in sim.vehicles: cars[v.id]=v.position
	for substep in range(4):
		sim.traffic.capture(sim.vehicles); sim._move_vehicles(.05); sim.traffic.resolve(sim,.05); sim._finish_vehicle_arrivals()
	for v in sim.vehicles: vehicle_valid=vehicle_valid and v.position.distance_to(cars[v.id])<=v.max_speed*.2+.01
func until(predicate: Callable, limit: int = 10000) -> bool:
	for i in range(limit):
		step()
		if predicate.call(): return true
	return false
func setup() -> void:
	manager=Manager.new(); root.add_child(manager); manager.load_settings(); manager.social_config.llm_agents=0; manager.initialize_run()
	manager.set_process(false); manager.ai_bridge.set_process(false); manager.ai_config.enabled=false; manager.phase="LIVING"; manager.elapsed_seconds=100
	sim=manager.social; evac=sim.evacuation
	sim.cognition.config.enabled=false; sim.driving.settings.ai_enabled=false; sim.config.spontaneous_actions=false
	evac.config.recruitment_seconds=300
	for a in manager.agents:
		a.position=Vector2(-9000,-9000); a.indoor_id=""; a.riding=""; a.cognition.action="CONTINUE"; a.cognition.until=0
	Map.roads.clear(); Map.edge_lookup.clear(); Map.closures.clear(); Map.roadblock_data.clear(); Map.traffic_signals.clear()
	Map.lots.clear(); Map.rock_obstacles.clear(); Map.parking_lots.clear(); Map.lake=Rect2(-10000,-10000,1,1); Map._rebuild_obstacle_index()
	Map.free_grid.fill_solid_region(Map.free_grid.region,false); Map.free_path_cache.clear()
	Map.graph=preload("res://scripts/road_graph.gd").new()
	var nodes: Array[Vector2]=[Vector2(400,400),Vector2(2200,400),Vector2(2200,1600),Vector2(400,1600)]
	for i in range(4): Map.graph.add_point(i,nodes[i])
	for i in range(4):
		var j: int=(i+1)%4
		var e: Dictionary={"from":i,"to":j,"a":nodes[i],"b":nodes[j],"points":PackedVector2Array([nodes[i],nodes[i].lerp(nodes[j],.5),nodes[j]]),"width":80.0,"lanes":2,"sidewalk":50.0,"kind":"boulevard","trail":false}
		Map.roads.append(e); Map.graph.connect_points(i,j); Map.edge_lookup[Vector2i(i,j)]=e.points; Map._store_cost(i,j,e.points)
	Map._rebuild_road_index(); sim.blocks.clear(); sim.traffic.scenes.clear()
	var fleet: Array=[]; var bays: Array=[]
	for i in range(sim.police.units.size()):
		var unit: Dictionary=sim.police.units[i]; var v: Dictionary=sim.police.vehicle(unit)
		var point:=Vector2(600+i*220,240)
		var approach:=PackedVector2Array([Vector2(point.x,400),Vector2(point.x,320),point])
		var exit_path:=approach.duplicate(); exit_path.reverse()
		var bay: Dictionary={"id":"BASE%d"%i,"position":point,"heading":PI/2,"occupied_by":v.id,"approach":approach}
		bays.append(bay)
		v.merge({"position":point,"body_position":point,"heading":PI/2,"speed":0.0,"height":0.0,"status":"PARKED","passengers":[],"parking_exit":exit_path,"destination":"","lane_offset":0.0,"target_lane_offset":0.0,"parking_bay":bay.id},true)
		fleet.append(v)
		for id in unit.officers:
			var a: Dictionary=sim.by_id[id]
			a.position=point; a.health=100; a.state="MOVING"; a.responding_to=""; a.duty_status="ON_DUTY"; a.social_target=""; a.group_on_foot=false; a.panic_level=0
	for i in range(6):
		var point:=Vector2(700+i*180,280)
		bays.append({"id":"DEST%d"%i,"position":point,"heading":PI/2,"occupied_by":"","approach":PackedVector2Array([Vector2(point.x,400),Vector2(point.x,340),point])})
	Map.parking_lots.append({"id":"TEST_LOT","bounds":Rect2(500,180,1500,210),"bays":bays})
	sim.vehicles=fleet
	for s in manager.shelters:
		s.capacity=50; s.occupant_ids.clear(); s.occupancy=0; s.exists=true; s.operational=true; s.accepting=true; s.operational_status="OPERATIONAL"; s.structural_state="INTACT"; s.door_status="OPEN"; s.manual_accessible=true; s.manual_safety_status="SAFE"
		s.position=Vector2(1700,900) if s.id=="S1" else Vector2(2000,1400)
		s.entrance_position=s.position; s.exit_position=s.position
		if s.id not in ["S1","S2"]: s.manual_safety_status="UNSAFE"
	State.project(manager.shelter_by_id.S1)
	manager.shelter_by_id.S1.capacity=8
	manager.emergency.refresh_shelters()
func run() -> void:
	setup()
	var people: Array=manager.agents.filter(func(a):return a.role=="Civilian" and a.age>=18 and a.id!="SPECIAL_I_AM_LEGEND").slice(0,17)
	for i in range(16):
		var a: Dictionary=people[i]
		a.position=Vector2(1000+(i%4)*45,530+(i/4)*40); a.health=100; a.state="MOVING"; a.indoor_id=""; a.authority_trust=100; a.cooperation=100; a.skepticism=0; a.cognitive_traits.aggression=0; a.panic_level=0; a.family_id="EVAC_"+a.id; a.relationships={}; a.group_on_foot=true; a.social_target=""
	people[0].family_id="EVAC_FAMILY"; people[1].family_id="EVAC_FAMILY"; people[0].relationships[people[1].id]="spouse"; people[1].relationships[people[0].id]="spouse"
	var refuser: Dictionary=people[15]; refuser.authority_trust=0; refuser.cooperation=0; refuser.empathy=0; refuser.cognitive_traits.altruism=0; refuser.cognitive_traits.aggression=100; refuser.skepticism=100
	var outsider: Dictionary=people[16]; outsider.position=Vector2(1670,900); outsider.state="MOVING"; outsider.emergency_evacuating=true; outsider.objective="S1"; outsider.movement_speed=outsider.walk_speed
	var source: String=manager.add_emergency("POLICE_SHELTER_EVACUATION",Vector2(1100,580),{"radius":250,"duration":5000,"severity":.7})
	check(source!="","new named event accepted")
	manager.emergency.tick(0)
	var op: Dictionary=evac.operation(source)
	check(not op.is_empty() and op.estimated_count==16 and op.destination=="S1","area estimate and safe destination planned before contact")
	check(op.tasks.size()==4,"large evacuation plans gather, escort, intersection and emergency access tasks")
	check(people.all(func(a):return a.evacuation_group==""),"event does not remotely compel civilians")
	check(until(func():return evac.groups.any(func(g):return evac._pending(g).size()>=5),4000),"A: officers physically arrive, approach and recruit scattered civilians")
	var large: Dictionary=evac.groups.filter(func(g):return evac._pending(g).size()>=5)[0]
	if large.state in ["GATHERING","WAITING_GUIDE","HOLDING"]:
		var subset: Array=evac._pending(large).slice(-1)
		var split: Dictionary=evac.split_group(large.id,subset,"Test regrouping")
		check(not split.is_empty() and evac.merge_groups(large.id,split.id),"groups split and merge by membership without relocating people")
	check(until(func():return evac.groups.any(func(g):return g.state=="MOVING" and g.destination=="S1" and g.size>=5),4000),"escort reaches a gathered group and begins real route movement")
	var moving: Dictionary=evac.groups.filter(func(g):return g.state=="MOVING" and g.destination=="S1")[0]
	var assigned: Array=op.tasks.values().map(func(id):return sim.police.request_for(id).unit).filter(func(id):return id!="")
	var unique: Dictionary={}
	for id in assigned: unique[id]=true
	check(assigned.size()>=3 and assigned.size()==unique.size(),"B: multiple units coordinate distinct tasks without duplicate crew assignment")
	check(sim.by_id[moving.leader].get("police_operation_briefing",{}).get("operation","")==source,"units share source-labelled command briefing")
	# C: A separate civilian takes a real shelter place while the group is en route.
	var path:=Routes.plan(outsider.position,manager.shelter_by_id.S1.position)
	var outsider_proxy: Dictionary={"position":outsider.position,"route":path,"route_index":1,"movement_speed":outsider.walk_speed}
	for i in range(100):
		Routes.move(outsider_proxy,.2); outsider.position=outsider_proxy.position
		step()
		if outsider.position.distance_to(manager.shelter_by_id.S1.position)<.01: break
	outsider.objective="S1"
	var outsider_result: String=manager.admit_arrival(outsider)
	check(outsider_result=="" and manager.shelter_by_id.S1.occupancy==1,"outside evacuee physically consumes a real place")
	check(until(func():return moving.destination=="S2",100),"C: incoming-capacity accounting redirects the larger moving group")
	check(manager.shelters.all(func(s):return s.occupancy<=s.capacity),"capacity estimates never manufacture occupancy")
	# D: A new hazard cuts the actual planned pedestrian corridor.
	var old_route: PackedVector2Array=moving.route.duplicate()
	var danger_point: Vector2=moving.position.lerp(manager.shelter_by_id.S2.position,.5)
	var hazard: String=manager.add_emergency("danger_zone",danger_point,{"radius":65,"duration":2000})
	manager.emergency.tick(0)
	check(until(func():return moving.revision==Map.navigation_revision and moving.route!=old_route and not moving.route.is_empty(),100),"D: new danger installs actual obstruction and changes group route")
	check(evac._path_safe(moving.route),"revised route respects physical hazard closures")
	# F: A real reflex moves one family member away from the group's path.
	until(func():return people[0].evacuation_group!="" and people[0].evacuation_group==people[1].evacuation_group,500)
	check(people[0].evacuation_group!="" and people[0].evacuation_group==people[1].evacuation_group,"family members join the same group where capacity permits")
	var family_group: Dictionary=evac.group(people[0].evacuation_group)
	sim.cognition.config.enabled=true
	var relative: Dictionary=people[1]
	sim.cognition._plan_away(relative,relative.position-Vector2(0,20),Vector2(0,-1),"FLEE",manager.elapsed_seconds,65)
	step()
	check(relative.evacuation_member_status=="SEPARATED","F: immediate safety reflex interrupts police following")
	step()
	check(people[0].current_goal.contains("separated family") or people[0].position.distance_to(relative.position)<45,"family attachment produces a bounded wait or nearby support")
	check(until(func():return relative.evacuation_member_status in ["FOLLOWING","REGROUPING","REJOINING","ARRIVED"],400),"separated member can rejoin through actual navigation")
	# E: A low-trust civilian remains free to refuse; no movement is fabricated.
	check(until(func():return op.refusals.has(refuser.id),3000),"E: low-trust/aggressive civilian can decline police evacuation")
	check(refuser.evacuation_group=="" and refuser.evacuation_member_status=="REFUSED","refusal does not assign hidden group membership")
	# G: An injured escort cannot remain assigned; a spare real patrol replaces it.
	var escort: Dictionary=sim.police.request_for(op.tasks.escort)
	var old_unit: String=escort.unit
	var disabled: Dictionary=sim.by_id[sim.police.unit_for(old_unit).officers[1]]
	sim.traffic.injure(sim,disabled,85)
	step()
	check(escort.state=="EVALUATED" and escort.unit=="","G: unavailable crew releases task for reassessment")
	check(until(func():return escort.state=="ACTIVE" and escort.unit!="" and escort.unit!=old_unit,5000),"replacement crew physically dispatches and reaches its assignment")
	if escort.state!="ACTIVE":
		var car: Dictionary=sim.police.vehicle(sim.police.unit_for(escort.unit))
		print("CAR ",car)
		print("DRIVER ",sim.by_id[car.driver].social_target," foot ",sim.by_id[car.driver].group_on_foot," board ",sim.by_id[car.driver].get("boarding_vehicle",""))
		quit(1); return
	manager.emergency.clear_event(hazard)
	check(until(func():return op.state=="COMPLETE",18000),"H: accepted civilians arrive and police physically return to normal operations")
	check(manager.shelter_by_id.S1.occupancy+manager.shelter_by_id.S2.occupancy>=16,"guided arrivals use real shelter admissions")
	check(manager.shelters.all(func(s):return s.occupancy==s.occupant_ids.size() and s.occupancy<=s.capacity),"final shelter counts match actual occupant membership")
	check(sim.police.units.all(func(u):return u.request not in op.tasks.values()),"operation releases all police assignments")
	var returned: Array=sim.police.units.filter(func(u):return sim.by_id[u.officers[0]].riding==u.vehicle and sim.police.crew_available(u))
	manager.elapsed_seconds+=3; sim.daily.tick(.1)
	check(not returned.is_empty() and returned.any(func(u):return sim.by_id[u.officers[0]].routine=="DRIVE" and sim.by_id[u.officers[0]].social_target.begins_with("routine:")),"returned crews resume existing vehicle routines instead of retaining on-foot recovery mode")
	check(movement_valid and vehicle_valid,"all operational walking and patrol travel remain speed bounded")
	check(evac.snapshot().operations.size()==1 and evac.inspection(source).contains("COMPLETE"),"recording and inspector retain operational history")
	manager.queue_free(); await process_frame
	await edge_cases()
	print("Police evacuation: %d checks / %d failures"%[checks,failures]); quit(1 if failures else 0)

func edge_cases() -> void:
	setup()
	evac.config.automatic_requests=false
	var civilians: Array=manager.agents.filter(func(a):return a.role=="Civilian" and a.age>=18 and a.id!="SPECIAL_I_AM_LEGEND").slice(0,4)
	for i in range(4):
		var a: Dictionary=civilians[i]
		a.position=Vector2(1060+i*20,530); a.state="MOVING"; a.health=100; a.authority_trust=100; a.cooperation=100; a.skepticism=0; a.cognitive_traits.aggression=0; a.family_id="BUNDLE%d"%(i/2); a.relationships={}; a.social_target=""
	for s in manager.shelters: s.manual_safety_status="UNSAFE"
	manager.emergency.refresh_shelters()
	var id: String=manager.add_emergency("police_shelter_evacuation",Vector2(1100,550),{"radius":180,"duration":3000})
	manager.emergency.tick(0)
	var op: Dictionary=evac.operation(id)
	check(not op.is_empty() and op.tasks.size()==2,"small operation uses two tasks and accepts lowercase event alias")
	check(until(func():return civilians.all(func(a):return a.evacuation_group!=""),3000),"people can regroup while safe shelters are unavailable")
	var g: Dictionary=evac.group(civilians[0].evacuation_group)
	check(g.state=="HOLDING" and g.destination=="" and manager.shelters.all(func(s):return s.occupancy==0),"no safe shelter holds group without fake admission")
	var positions: Array=civilians.map(func(a):return a.position)
	var split: Dictionary=evac.split_group(g.id,[civilians[2].id,civilians[3].id],"Reorganize family bundles")
	check(not split.is_empty() and split.size==2 and g.size==2,"explicit split preserves actual members")
	check(evac.merge_groups(g.id,split.id) and g.size==4,"compatible gathering groups merge")
	check(civilians.map(func(a):return a.position)==positions,"splitting and merging never relocates a member")
	var invalid: Dictionary={"action":"MOVE_TO_SHELTER","target":"MISSING","message":"","reason":"invalid test","confidence":.9}
	check(not preload("res://scripts/llm_actions.gd").apply(manager,civilians[0],invalid) and civilians[0].evacuation_group==g.id,"invalid asynchronous intention cannot detach a group member")
	for s in [manager.shelter_by_id.S1,manager.shelter_by_id.S2]: s.manual_safety_status="SAFE"; s.capacity=2
	manager.emergency.refresh_shelters()
	evac._allocate(g)
	for pass_index in range(2):
		for candidate in evac.groups.duplicate():
			if not evac._pending(candidate).is_empty(): evac._allocate(candidate)
	var active: Array=evac.groups.filter(func(candidate):return not evac._pending(candidate).is_empty())
	check(active.size()==2 and active.all(func(candidate):return candidate.size==2 and candidate.destination!=""),"capacity pressure splits a larger group into intact family bundles")
	check(active[0].destination!=active[1].destination and evac._committed("S1")==2 and evac._committed("S2")==2,"incoming commitments are shared across groups without overbooking")
	check(civilians[0].evacuation_group==civilians[1].evacuation_group and civilians[2].evacuation_group==civilians[3].evacuation_group,"automatic capacity splitting keeps families intact")
	manager.emergency.clear_event(id)
	check(until(func():return op.state=="COMPLETE",3000),"cancelled live operation releases memberships and physically returns crews")
	check(civilians.all(func(a):return a.evacuation_group=="") and manager.shelters.all(func(s):return s.occupancy==0),"cancel does not manufacture a successful evacuation")
	# Allow the command retry cooldown after cancellation, then use fresh local sensors.
	for cooldown_step in range(310): step()
	# Pending requests are deduplicated before the event-start tick creates an operation.
	var officer: Dictionary=sim.by_id[sim.police.units[0].officers[0]]
	for step_index in range(1000):
		manager.elapsed_seconds+=.2
		if sim.police._walk(officer,civilians[0].position,.2): break
	for a in civilians: a.state="WAITING_ROAD"
	officer.cognition.observations=preload("res://scripts/agent_perception.gd").observe(sim,officer,sim.cognition.config)
	evac.consider_authority_requests()
	var pending: Array=manager.environment_events.filter(func(e):return e.event_type==evac.EVENT and not e.ended)
	check(pending.size()==1,"fresh local observations of stranded civilians can trigger authority planning")
	check(evac.request_by_authority(officer,"Duplicate assessment")=="","authority requests deduplicate pending operations")
	for e in pending: manager.emergency.clear_event(e.event_id)
	manager.queue_free(); await process_frame
