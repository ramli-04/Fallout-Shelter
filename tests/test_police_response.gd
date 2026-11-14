extends SceneTree
const Manager=preload("res://scripts/simulation_manager.gd")
const Map=preload("res://scripts/city_map.gd")
const World=preload("res://scripts/three_d/social_world.gd")
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures+=1; printerr("FAIL: "+label)
func run() -> void:
	var manager:=Manager.new(); root.add_child(manager); manager.load_settings(); manager.initialize_run()
	manager.set_process(false); manager.ai_bridge.set_process(false); manager.ai_config.enabled=false
	manager.phase="EVACUATION"; manager.elapsed_seconds=100
	var sim: RefCounted=manager.social; var police: RefCounted=sim.police
	check(manager.agents.size()==100 and police.units.size()==6,"existing population pairs twelve officers into six units")
	check(not police.stations.is_empty(),"existing police station retained")
	check(police.units.all(func(u):return u.officers.size()==2 and police.vehicle(u).kind=="Police"),"units use two existing officers and existing patrol vehicle")
	# Controlled starting conditions, then production movement only. No arrival teleports.
	for a in manager.agents: a.position=Vector2(-9000,-9000); a.indoor_id=""; a.riding=""
	Map.roads.clear(); Map.edge_lookup.clear(); Map.closures.clear(); Map.roadblock_data.clear(); Map.traffic_signals.clear()
	Map.lots.clear(); Map.rock_obstacles.clear(); Map.parking_lots.clear(); Map.lake=Rect2(-10000,-10000,1,1); Map._rebuild_obstacle_index()
	Map.graph=preload("res://scripts/road_graph.gd").new()
	var nodes: Array[Vector2]=[Vector2(400,400),Vector2(1000,400),Vector2(1000,1000),Vector2(400,1000)]
	for i in range(4): Map.graph.add_point(i,nodes[i])
	for i in range(4):
		var j: int=(i+1)%4
		var e: Dictionary={"from":i,"to":j,"a":nodes[i],"b":nodes[j],"points":PackedVector2Array([nodes[i],nodes[i].lerp(nodes[j],.5),nodes[j]]),"width":80.0,"lanes":2,"sidewalk":30.0,"kind":"boulevard","trail":false}
		Map.roads.append(e); Map.graph.connect_points(i,j); Map.edge_lookup[Vector2i(i,j)]=e.points; Map._store_cost(i,j,e.points)
	Map._rebuild_road_index(); Map.free_path_cache.clear()
	var bay: Dictionary={"id":"TEST_BAY","position":Vector2(850,1100),"heading":-PI/2,"occupied_by":"","approach":PackedVector2Array([Vector2(850,1000),Vector2(850,1050),Vector2(850,1100)])}
	Map.parking_lots.append({"id":"TEST_LOT","bounds":Rect2(800,1030,100,120),"bays":[bay]})
	var unit: Dictionary=police.units[0]; var alternative: Dictionary=police.units[1]
	var spare: Dictionary=police.vehicle(alternative)
	police.units=[unit]
	var v: Dictionary=police.vehicle(unit); sim.vehicles=[v]; sim.blocks=[]; sim.traffic.scenes.clear()
	v.merge({"position":Vector2(700,400),"body_position":Vector2(700,420),"heading":0.0,"speed":0.0,"height":0.0,"status":"PARKED","passengers":[],"parking_exit":PackedVector2Array(),"destination":"","lane_offset":20.0,"target_lane_offset":20.0},true)
	for id in unit.officers:
		var a: Dictionary=sim.by_id[id]
		a.position=v.position; a.indoor_id=""; a.riding=""; a.health=100; a.state="MOVING"; a.responding_to=""; a.duty_status="ON_DUTY"; a.cognition.until=0; a.social_target=""; a.group_on_foot=false
	sim.cognition.config.enabled=false; sim.driving.settings.ai_enabled=false; sim.config.spontaneous_actions=false
	var leader: Dictionary=sim.by_id[unit.officers[0]]
	var evidence: Dictionary={"hazard_kind":"nuclear","hazard_id":"nuclear_hazard","hazard_confidence":1.0,"hazard_position":Vector2(700,1200),"traffic_flow":1.0,"congestion":.5,"evacuation_demand":1.0,"available_personnel":2,"shelter_access_preserved":true,"emergency_vehicle_access_preserved":true}
	check(sim.create_block(leader,"police",Map.roads[2],Vector2(700,1000)).is_empty(),"direct AI/legacy creation cannot spawn unstaffed barrier")
	check(police.request_deployment("police",2,Vector2(700,1000),"",evidence).is_empty(),"reason is mandatory")
	var invalid: Dictionary=evidence.duplicate(); invalid.hazard_kind="fire"; invalid.hazard_id="MISSING"
	check(police.request_deployment("police",2,Vector2(700,1000),"No live fire",invalid).is_empty(),"missing operational event rejected")
	var r: Dictionary=police.request_deployment("police",2,Vector2(700,1000),"Protect access to nuclear danger zone",evidence)
	check(not r.is_empty() and r.state=="EVALUATED" and sim.blocks.is_empty(),"request evaluated without barrier")
	if r.is_empty(): quit(1); return
	var partner: Dictionary=sim.by_id[unit.officers[1]]; partner.health=0
	police.tick(.1)
	check(r.state=="EVALUATED" and r.pending_reason!="" and sim.blocks.is_empty(),"one available officer leaves request pending")
	partner.health=100; manager.elapsed_seconds+=3; police.tick(.1)
	check(r.state=="ASSIGNED" and r.unit==unit.id and r.road_distance>1000 and r.eta>0,"available unit assigned using actual road distance and ETA")
	check(sim.blocks.is_empty(),"assignment does not deploy barrier")
	# A near station does not override a unit's actual road travel cost.
	spare.merge({"position":Vector2(900,1000),"body_position":Vector2(900,980),"heading":PI,"speed":0.0,"height":0.0,"status":"PARKED","passengers":[],"parking_exit":PackedVector2Array()},true)
	sim.vehicles.append(spare)
	for id in alternative.officers:
		var a: Dictionary=sim.by_id[id]
		a.position=spare.position; a.indoor_id=""; a.riding=""; a.health=100; a.state="MOVING"; a.responding_to=""; a.duty_status="ON_DUTY"
	bay.occupied_by=""
	var nearer: Dictionary=police._candidate(alternative,r)
	check(not nearer.is_empty() and nearer.eta<r.eta and nearer.road_distance<r.road_distance,"nearby reachable patrol outranks distant patrol independently of station label")
	bay.occupied_by="POLICE:"+unit.id; sim.vehicles=[v]
	for id in alternative.officers: sim.by_id[id].position=Vector2(-9000,-9000)
	police.tick(.1)
	check(r.state=="DISPATCHED" and v.passengers.size()==2,"both officers physically board before dispatch")
	var before: Vector2=v.position; var bounded:=true
	for step in range(10000):
		manager.elapsed_seconds+=.1
		police.tick(.1)
		var previous: Vector2=v.position
		sim.traffic.capture(sim.vehicles); sim._move_vehicles(.1); sim.traffic.resolve(sim,.1); sim._finish_vehicle_arrivals()
		bounded=bounded and v.position.distance_to(previous)<=float(v.max_speed)*.1+.001
		if r.state in ["ACTIVE","REMOVED"]: break
	check(bounded and before.distance_to(v.position)>500,"patrol travel uses bounded physical road movement")
	check(r.state=="ACTIVE","crew physically travels, exits, walks and deploys")
	if r.state!="ACTIVE": printerr("State: ",r.state," / vehicle: ",v.status," ",v.position," / route ",v.route," / ",v.get("driving_reason","")); quit(1); return
	var states: Array=r.history.map(func(h):return h.state)
	check(states==["REQUESTED","EVALUATED","ASSIGNED","DISPATCHED","ARRIVED","DEPLOYING","ACTIVE"],"deployment history follows required lifecycle")
	check(unit.officers.all(func(id):return sim.by_id[id].riding=="" and sim.by_id[id].position.distance_to(police.officer_position(r,unit.officers.find(id)))<12),"two responsible officers present at active barrier")
	var block: Dictionary=sim.blocks[-1]
	partner.health=0; police.tick(.1)
	check(r.state=="EVALUATED" and block.active and block.unmanaged,"lost crew leaves physical barrier and queues replacement")
	manager.elapsed_seconds+=3; police.tick(.1)
	check(r.state=="EVALUATED" and r.pending_reason!="","unavailable replacement remains pending without spawning crew")
	partner.health=100
	for step in range(5000):
		manager.elapsed_seconds+=.1; police.tick(.1)
		sim.traffic.capture(sim.vehicles); sim._move_vehicles(.1); sim.traffic.resolve(sim,.1); sim._finish_vehicle_arrivals()
		if r.state=="ACTIVE": break
	check(r.state=="ACTIVE" and not block.unmanaged and sim.blocks.size()==1,"replacement physically reaches existing barrier without duplicating it")
	if r.state!="ACTIVE": printerr("Replacement: ",r.state," ",r.pending_reason," / ",v.position," / ",v.status," / ",r.history); quit(1); return
	check(block.active and block.unit_id==unit.id and block.officer_ids==unit.officers,"active barrier identifies crew and reason")
	check(not Map.graph.are_points_connected(2,3),"deployed barrier closes actual road graph")
	var world:=World.new(); root.add_child(world); world.manager=manager; world.rebuild(); world._process(.016)
	check(world.barrier_colliders.has(block.id),"deployed barrier has actual collision representation")
	check(world.barriers[block.id].has_meta("roadblock") and world.barriers[block.id].selection_area.collision_layer==128,"roadblock is selectable for inspection")
	var avatar=preload("res://scenes/three_d/agent.tscn").instantiate(); avatar.configure(leader); root.add_child(avatar)
	leader.police_animation="placing_barrier"; avatar.update_visual(leader,1,true,manager.elapsed_seconds); avatar._process(.1)
	check(avatar.animation_state=="placing_barrier" and avatar.body.rotation.x>0,"police work pose matches deployment action")
	leader.police_animation="directing_traffic"; avatar._process(.1)
	check(avatar.animation_state=="directing_traffic" and avatar.arms[0].rotation.z<0,"traffic gesture follows operational animation state")
	avatar.queue_free()
	var civilian: Dictionary=manager.agents.filter(func(a):return a.role=="Civilian")[0]
	civilian.position=r.position+Vector2(40,0); civilian.state="MOVING"; civilian.indoor_id=""; civilian.authority_trust=90
	r.next_instruction=0; police.tick(.1)
	check(civilian.get("police_instruction",{}).get("request","")==r.id,"nearby civilian perceives source-labelled police instructions")
	var car: Dictionary={"kind":"Civilian","position":Vector2(640,1000),"heading":0.0,"speed":20.0,"braking":20.0}
	check(police.controls_vehicle(car),"arrived officers stop approaching civilian traffic")
	car.kind="Medical"; check(not police.controls_vehicle(car),"registered emergency vehicles retain access")
	check(police.inspection(r.id).contains("Protect access") and police.inspection(r.id).contains(unit.id),"request inspection exposes reason, crew and history")
	sim.remove_block(block.id)
	check(block.active and r.state=="REMOVING","direct removal schedules physical work instead of disappearing barrier")
	for step in range(2000):
		manager.elapsed_seconds+=.1; police.tick(.1)
		if unit.state=="AVAILABLE": break
	check(r.state=="REMOVED" and not block.active,"officers physically remove deployed barrier")
	check(unit.state=="AVAILABLE" and v.passengers.size()==2,"officers return to parked patrol after removal")
	check(Map.graph.are_points_connected(2,3),"removal restores road connectivity")
	check(not leader.police_unit_busy and not partner.police_unit_busy,"routines resume after assignment")
	# A cleared operational event initiates removal automatically.
	var fire: String=manager.add_emergency("fire",Vector2(700,1200),{"radius":10,"duration":1000})
	manager.emergency.tick(0)
	var fire_evidence: Dictionary=evidence.duplicate(); fire_evidence.hazard_kind="fire"; fire_evidence.hazard_id=fire
	var second: Dictionary=police.request_deployment("police",2,Vector2(700,1000),"Prevent approach to reported fire",fire_evidence)
	check(not second.is_empty(),"live fire creates operational request")
	if second.is_empty(): quit(1); return
	for step in range(5000):
		manager.elapsed_seconds+=.1; police.tick(.1)
		sim.traffic.capture(sim.vehicles); sim._move_vehicles(.1); sim.traffic.resolve(sim,.1); sim._finish_vehicle_arrivals()
		if second.state=="ACTIVE": break
	check(second.state=="ACTIVE","returned crew can receive a new emergency assignment")
	manager.emergency.clear_event(fire); manager.elapsed_seconds+=.1; police.tick(.1)
	check(second.state=="REMOVING" and sim.blocks[-1].active,"cleared event requests removal while physical barrier remains")
	for step in range(2000):
		manager.elapsed_seconds+=.1; police.tick(.1)
		if unit.state=="AVAILABLE": break
	check(second.state=="REMOVED" and not sim.blocks[-1].active,"cleared event completes physical removal lifecycle")
	var snapshot: Dictionary=police.snapshot()
	check(snapshot.requests.size()==2 and snapshot.units[0].officers==unit.officers,"replay snapshot retains units, crew and lifecycle history")
	world.queue_free(); manager.queue_free(); await process_frame
	print("Police response: %d checks / %d failures"%[checks,failures]); quit(1 if failures else 0)
