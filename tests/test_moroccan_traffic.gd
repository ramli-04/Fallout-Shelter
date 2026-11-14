extends SceneTree
const Manager=preload("res://scripts/simulation_manager.gd")
const Map=preload("res://scripts/city_map.gd")
const Rules=preload("res://scripts/traffic_rules.gd")
const Convention=preload("res://scripts/traffic_conventions.gd")
const Navigation=preload("res://scripts/vehicle_navigation.gd")
const Runtime=preload("res://scripts/vehicle_runtime.gd")
const Coordinates=preload("res://scripts/three_d/world_coordinates.gd")
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1; printerr("FAIL: "+label)
func run() -> void:
	var manager:=Manager.new(); root.add_child(manager); manager.load_settings(); manager.initialize_run()
	manager.set_process(false); manager.ai_bridge.set_process(false); manager.ai_config.enabled=false
	manager.elapsed_seconds=100; manager.phase="LIVING"
	var sim: RefCounted=manager.social
	sim.config.spontaneous_actions=false; sim.blocks=[]
	for agent in manager.agents: agent.position=Vector2(-9000,-9000); agent.indoor_id=""; agent.riding=""
	Map.roads.clear(); Map.edge_lookup.clear(); Map.closures.clear(); Map.roadblock_data.clear(); Map.traffic_signals.clear()
	Map.lots.clear(); Map.rock_obstacles.clear(); Map.parking_lots.clear(); Map.lake=Rect2(-10000,-10000,1,1); Map._rebuild_obstacle_index()
	Map.graph=preload("res://scripts/road_graph.gd").new()
	var nodes: Array[Vector2]=[Vector2(400,400),Vector2(1000,400),Vector2(1000,1000),Vector2(400,1000)]
	for i in range(nodes.size()): Map.graph.add_point(i,nodes[i])
	for i in range(4):
		var j: int=(i+1)%4
		var edge: Dictionary={"from":i,"to":j,"a":nodes[i],"b":nodes[j],"points":PackedVector2Array([nodes[i],nodes[i].lerp(nodes[j],.5),nodes[j]]),"width":80.0,"lanes":2,"sidewalk":30.0,"kind":"boulevard","trail":false}
		Map.roads.append(edge); Map.graph.connect_points(i,j); Map.edge_lookup[Vector2i(i,j)]=edge.points; Map._store_cost(i,j,edge.points)
	Map._rebuild_road_index()
	for angle in [0.0,PI*.5,PI,PI*1.5,.73]:
		var forward:=Vector2.from_angle(angle)
		check(forward.cross(Convention.right(forward))>.999,"right-side basis for heading %.2f"%angle)
		var face: Vector3=Basis(Vector3.UP,Convention.signal_yaw(forward))*Vector3.BACK
		check(Vector2(face.x,face.z).dot(-forward)>.999,"signal lamp faces approaching driver %.2f"%angle)
	check(Convention.right(Vector2.RIGHT)==Vector2.DOWN,"eastbound vehicles use +map Y")
	var start:=Vector2(800,400); var destination:=Vector2(850,1000)
	var route: PackedVector2Array=Navigation.route(sim,start,destination,false,0,{})
	check(route.has(nodes[1]) and route.has(nodes[2]),"short road-network route")
	var congested: PackedVector2Array=Navigation.route(sim,start,destination,false,0,{1:100.0})
	check(congested.has(nodes[3]) and not congested.has(nodes[1]),"known congestion changes route cost")
	check(Navigation.route(sim,start,destination,false,0,{1:0.0}).has(nodes[1]),"expired congestion report no longer penalizes route")
	Map.roads[0].one_way=true
	var directed: PackedVector2Array=Navigation.route(sim,Vector2(800,400),Vector2(500,400),false,0,{})
	check(Map._path_length(directed)>1800 and directed.has(nodes[2]),"one-way route loops through legal directions")
	Map.roads[0].erase("one_way")
	sim.blocks=[{"id":"ACC","edge":1,"kind":"accident","active":true,"position":Vector2(1000,700),"height":0.0}]
	var blocked: PackedVector2Array=Navigation.route(sim,start,destination,false,0,{})
	check(blocked.has(nodes[3]),"accident reroutes around blocked edge")
	check(Map.graph.are_points_connected(1,2),"vehicle planner does not mutate shared graph")
	var original_points: PackedVector2Array=Map.roads[0].points
	Map.roads[0].points=PackedVector2Array([nodes[0],Vector2(700,400),Vector2(700,700),nodes[1]])
	var curve_block: Dictionary={"edge":0,"position":Vector2(700,650),"height":0.0}
	var curve_car: Dictionary={"position":Vector2(735,550),"length":40.0,"width":18.0,"heading":PI*.5,"height":0.0,"body_height":1.5}
	check(not Runtime.block_contact(curve_car,Vector2(735,550),Vector2(735,750),curve_block).is_empty(),"barrier collision follows local curved-road tangent")
	Map.roads[0].points=original_points
	check(not Navigation.connector_clear(sim,PackedVector2Array([Vector2(1000,500),Vector2(1000,900)]),Map.roads[1],false),"route connector cannot cross a wreck")
	sim.blocks[0].kind="police"
	check(Navigation.connector_clear(sim,PackedVector2Array([Vector2(1000,500),Vector2(1000,900)]),Map.roads[1],true),"authorized emergency checkpoint routing")
	sim.blocks=[]
	var v: Dictionary=sim.vehicles[0]
	var driver: Dictionary=sim.by_id[v.driver]
	sim.vehicles=[v]
	v.merge({"position":Vector2(700,400),"body_position":Vector2(700,420),"heading":0.0,"speed":0.0,"height":0.0,"length":40.0,"width":18.0,"status":"BLOCKED","route":PackedVector2Array([Vector2(700,400),nodes[1],nodes[2]]),"route_index":1,"lane_offset":20.0,"target_lane_offset":20.0,"passengers":[driver.id],"rules_edge":Map.roads[0],"rules_edge_due":1000.0},true)
	driver.position=v.position; driver.indoor_id=""; driver.riding=v.id; driver.responding_to=""
	sim.traffic.prepare_spatial(sim)
	v.status="MOVING"; sim.traffic.capture(sim.vehicles); sim.traffic.resolve(sim,.1)
	check(v.body_position.y>v.position.y,"actual collision body occupies eastbound right lane")
	v.status="BLOCKED"
	check(sim.driving.begin_reverse(v),"clear low-speed reverse is accepted")
	var before: Vector2=v.position
	sim.driving.advance_recovery(v,.5)
	check(v.position.x<before.x and is_equal_approx(before.distance_to(v.position),4),"reverse uses bounded speed and keeps heading")
	v.recovery_mode="STOPPED"
	var person: Dictionary=manager.agents[-1]
	person.position=v.body_position-Vector2(15,0); person.state="MOVING"; person.transport_height=0
	check(not sim.driving.begin_reverse(v),"reverse is rejected with a pedestrian behind")
	person.position=Vector2(-9000,-9000)
	v.speed=10
	check(not sim.driving.begin_reverse(v),"moving vehicle cannot begin reverse")
	v.speed=0; v.height=10
	check(not sim.driving.safe_disembark(v,driver),"elevated unsafe exit rejected")
	v.height=0
	check(not sim.driving.safe_disembark(v,driver) and v.recovery_mode=="PULLING_OVER","foot transition begins with actual pull-over")
	for i in range(120):
		sim.driving.advance_recovery(v,.1)
		if v.recovery_mode=="ABANDONED": break
	check(v.status=="PARKED" and driver.riding=="" and driver.group_on_foot,"stopped car parks and occupants continue on foot")
	check(driver.position.y>v.position.y and Map.clear_point(driver.position,4),"exit places pedestrian beside right-hand parked car")
	check(v.passengers.is_empty() and driver.cognition.action=="ABANDON_VEHICLE","actual membership and cognition update together")
	# Signal cycles and unsignalled priority use actual directions.
	var signal_record: Dictionary={"position":nodes[1],"offset":0.0,"approaches":[],"enabled":true}
	check(Rules.light(signal_record,Vector2.RIGHT,0,sim.driving.settings)=="GREEN" and Rules.light(signal_record,Vector2.DOWN,0,sim.driving.settings)=="RED","crossing signal phases do not share green")
	signal_record.enabled=false; Map.traffic_signals[1]=signal_record
	v.merge({"position":Vector2(800,400),"body_position":Vector2(800,420),"speed":20.0,"heading":0.0,"status":"MOVING","route":PackedVector2Array([Vector2(800,400),nodes[1],nodes[2]]),"route_index":1},true)
	v.erase("committed_junction")
	var other: Dictionary=v.duplicate(true); other.id="CROSS"; other.position=Vector2(1000,550); other.body_position=other.position; other.heading=-PI*.5
	sim.vehicles=[v,other]; sim.traffic.prepare_spatial(sim)
	var limit: Dictionary=sim.driving.junction_limit(v,Map.roads[0],Vector2.RIGHT,100,.1)
	check(is_finite(float(limit.travel)),"unsignalled approach yields to traffic from right")
	sim.vehicles=[v]; sim.traffic.prepare_spatial(sim); sim.junction_reservations.clear()
	limit=sim.driving.junction_limit(v,Map.roads[0],Vector2.RIGHT,100,.1)
	check(not is_finite(float(limit.travel)),"clear junction permits progress")
	v.route=PackedVector2Array([Vector2(800,400),nodes[1],Vector2(1000,100)])
	check(Vector2.RIGHT.cross(Rules.exit_direction(v,nodes[1],Vector2.RIGHT,40))<0,"left-turn intent derives from route geometry")
	signal_record.enabled=true; signal_record.offset=0.0; manager.elapsed_seconds=0
	other.position=Vector2(1150,400); other.body_position=other.position; other.heading=PI; other.speed=20
	sim.vehicles=[v,other]; sim.traffic.prepare_spatial(sim); sim.junction_reservations.clear(); v.erase("committed_junction")
	limit=sim.driving.junction_limit(v,Map.roads[0],Vector2.RIGHT,100,.1)
	check(is_finite(float(limit.travel)),"left turn yields to oncoming traffic")
	sim.vehicles=[v]; sim.traffic.prepare_spatial(sim); sim.junction_reservations.clear(); v.erase("committed_junction")
	manager.elapsed_seconds=24
	limit=sim.driving.junction_limit(v,Map.roads[0],Vector2.RIGHT,100,.1)
	check(is_finite(float(limit.travel)),"red signal imposes physical stop distance")
	Map.traffic_signals.clear(); sim.junction_reservations.clear()
	v.route=PackedVector2Array([v.position,nodes[1]]); v.route_index=1; v.speed=35; v.lane_offset=20; v.body_position=v.position+Vector2(0,20)
	person.position=v.body_position+Vector2(65,0); person.state="MOVING"; person.riding=""; person.indoor_id=""
	var pedestrian_limit: Dictionary=sim.driving.plan(v,Vector2.RIGHT,100,.1)
	check(float(pedestrian_limit.speed)<100 and is_finite(float(pedestrian_limit.travel)),"driver slows and yields to pedestrian crossing lane")
	person.position=Vector2(-9000,-9000)
	# The collision query must use the same world as rendered colliders.
	var viewport:=SubViewport.new(); viewport.own_world_3d=true; root.add_child(viewport)
	var world:=Node3D.new(); viewport.add_child(world)
	var body:=preload("res://scripts/three_d/geometry.gd").collider(world,Vector3(3,3,3),Coordinates.to_world(Vector2(700,400),1.5),64)
	await physics_frame; await physics_frame
	v.position=Vector2(700,400); v.height=0
	sim.traffic.bind_world(world)
	check(not sim.traffic.physics_query(v,v.position,v.position).is_empty(),"physics reads rendered SubViewport obstacle world")
	sim.traffic.register_barrier({"id":"PHYS_CHECKPOINT","kind":"police"},body)
	v.kind="Civilian"
	check(not sim.traffic.physics_query(v,v.position,v.position).is_empty(),"civilian still respects physical police checkpoint")
	v.kind="Medical"
	check(sim.traffic.physics_query(v,v.position,v.position).is_empty(),"authorized emergency exception matches rendered physics")
	body.queue_free(); viewport.queue_free()
	sim.close(); manager.queue_free(); await process_frame
	print("Moroccan traffic: %d checks / %d failures"%[checks,failures]); quit(1 if failures else 0)
