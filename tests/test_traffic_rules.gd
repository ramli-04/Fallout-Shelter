extends SceneTree
const Map=preload("res://scripts/city_map.gd")
const Traffic=preload("res://scripts/traffic_rules.gd")
const SAT=preload("res://scripts/vehicle_collisions.gd")
var checks:=0
var failures:=0
var manager: Node
var social: RefCounted
var rules: RefCounted
var origin:=Vector2(-3000,-3000)
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures+=1; printerr("FAIL: "+label)
func car(id: String, x: float, offset: float, speed: float = 70) -> Dictionary:
	var driver: Dictionary=manager.agents[0 if id=="A" else 1]
	return {"id":id,"driver":driver.id,"kind":"Civilian","position":origin+Vector2(x,0),"body_position":origin+Vector2(x,-offset),"heading":0.0,"height":0.0,"body_height":1.5,"length":43.0,"width":18.0,"speed":speed,"max_speed":100.0,"braking":70.0,"acceleration":30.0,"status":"MOVING","passengers":[],"health":100.0,"lane_offset":offset,"target_lane_offset":offset,"edge":0,"next_route":INF,"next_edge_update":INF,"next_height_update":INF,"route":PackedVector2Array([origin+Vector2(x,0),origin+Vector2(2500,0)]),"route_index":1,"destination":"traffic_test"}
func run() -> void:
	manager=preload("res://scripts/simulation_manager.gd").new(); root.add_child(manager); manager.set_process(false)
	check(manager.load_settings(),"load current settings"); manager.social_config.llm_agents=0; manager.initialize_run()
	manager.ai_bridge.set_process(false); manager.ai_config.enabled=false; manager.social.close(); social=manager.social; rules=social.driving
	var saved: Dictionary={"roads":Map.roads,"graph":Map.graph,"lots":Map.lots,"rocks":Map.rock_obstacles,"parking":Map.parking_lots,"signals":Map.traffic_signals.duplicate(true)}
	Map.lots=[]; Map.rock_obstacles=[]; Map.parking_lots=[]; Map.traffic_signals={}
	Map.graph=preload("res://scripts/road_graph.gd").new()
	for i in range(3): Map.graph.add_point(i,origin+Vector2(i*2000,0))
	Map.graph.connect_points(0,1); Map.graph.connect_points(1,2)
	var edge: Dictionary={"from":0,"to":1,"a":origin,"b":origin+Vector2(2000,0),"points":PackedVector2Array([origin,origin+Vector2(2000,0)]),"width":70.0,"sidewalk":40.0,"lanes":2,"kind":"residential"}
	Map.roads=[edge]; social.blocks=[]; social.junction_reservations.clear()
	for agent in manager.agents: agent.indoor_id="TEST_ROOM"; agent.social_target=""; agent.objective=""
	var driver: Dictionary=manager.agents[0]; driver.indoor_id=""; driver.riding="A"; driver.position=origin+Vector2(1600,0); driver.social_target="traffic_test"
	driver.known_locations.traffic_test={"position":origin+Vector2(2500,0)}
	manager.phase="LIVING"; manager.elapsed_seconds=24
	var signal_record: Dictionary={"position":origin+Vector2(2000,0),"offset":0.0,"approaches":[]}
	Map.traffic_signals[1]=signal_record
	for second in range(92):
		var east: String=Traffic.light(signal_record,Vector2.RIGHT,second,rules.settings)
		var north: String=Traffic.light(signal_record,Vector2.UP,second,rules.settings)
		check(not(east in ["GREEN","AMBER"] and north in ["GREEN","AMBER"]),"conflicting approaches never receive simultaneous permission")
	check(Traffic.light(signal_record,Vector2.RIGHT,18,rules.settings)=="AMBER","amber interval")
	check(Traffic.light(signal_record,Vector2.RIGHT,21,rules.settings)=="RED" and Traffic.light(signal_record,Vector2.UP,21,rules.settings)=="RED","all-red clearance")
	check(is_equal_approx(Traffic.lane_offset(edge),17.5),"two-lane carriageway keeps its half")
	var a:=car("A",1600,17.5,100); a.passengers=[driver.id]; social.vehicles=[a]
	for step in range(120):
		social.traffic.capture(social.vehicles); social._move_vehicles(.05); social.traffic.resolve(social,.05)
	check(a.position.x<=origin.x+2000-35-102-a.length*.5+.01,"red signal stops bumper before crossing line")
	check(a.speed<.1 and a.driving_reason=="RED_LIGHT","red signal produces a stationary queue")
	var stopped: Vector2=a.position; manager.elapsed_seconds=0
	for step in range(50):
		social.traffic.capture(social.vehicles); social._move_vehicles(.05); social.traffic.resolve(social,.05)
	check(a.position.x>stopped.x+50,"green signal releases stopped traffic")
	check(a.status!="ACCIDENT","signal approach does not create a collision")
	Map.traffic_signals.clear(); edge.width=140; edge.lanes=4; edge.kind="boulevard"
	a=car("A",800,52.5,70); var b:=car("B",950,52.5,20); social.vehicles=[a,b]
	a.slow_wait=4; a.lead_gap=107
	check(is_equal_approx(Traffic.lane_offset(edge),52.5) and is_equal_approx(Traffic.lane_offset(edge,true),17.5),"four-lane curb/passing lanes remain on same side")
	check(rules.can_pass(a,edge,Vector2.RIGHT),"clear adjacent same-direction lane permits a pass")
	b.position=origin+Vector2(740,0); b.body_position=b.position+Vector2(0,-17.5); b.speed=130
	check(not rules.can_pass(a,edge,Vector2.RIGHT),"fast rear approach prevents cutting into a passing lane")
	b.position=origin+Vector2(950,0); b.body_position=b.position+Vector2(0,-52.5); b.speed=20
	edge.lanes=2; check(not rules.can_pass(a,edge,Vector2.RIGHT),"no normal passing into an oncoming lane"); edge.lanes=4
	check(rules.begin_action(a,"overtake","DRIVING_AI"),"tactical AI can begin a validated pass")
	var safe_pass:=true; var lateral_moved:=false
	for step in range(200):
		manager.elapsed_seconds+=.05
		social.traffic.capture(social.vehicles)
		var plan: Dictionary=rules.plan(a,Vector2.RIGHT,100,.05)
		a.speed=move_toward(a.speed,plan.speed,(a.braking if plan.speed<a.speed else a.acceleration)*.05)
		if is_finite(float(plan.travel)): a.speed=minf(a.speed,maxf(0,float(plan.travel))/.05)
		a.position.x+=a.speed*.05; b.position.x+=b.speed*.05; b.body_position=b.position+Vector2(0,-52.5)
		social.traffic.resolve(social,.05)
		if a.status=="ACCIDENT": safe_pass=false
		if a.lane_offset<30: lateral_moved=true
	check(lateral_moved and safe_pass,"passing changes lane gradually without intersecting lead vehicle")
	check(a.position.x>b.position.x,"passing makes forward progress beyond a slow driver")
	# Emergency pavement escape: an imminent rear-end threat, no pedestrians or obstacles.
	edge.width=70; edge.lanes=2; edge.kind="residential"
	a=car("A",800,17.5,100); b=car("B",900,17.5,0); b.status="ACCIDENT"; social.vehicles=[a,b]
	var plan: Dictionary=rules.plan(a,Vector2.RIGHT,100,.05)
	check(a.imminent_collision and a.get("driving_mode","")=="EVADING","imminent collision can choose a clear pavement escape")
	check(a.target_lane_offset>edge.width*.5 and plan.speed<=rules.settings.pavement_max_speed,"pavement escape uses low speed and outer corridor")
	var accident_block: Dictionary={"kind":"accident"}
	check(rules.block_requires_stop(a,accident_block),"accident closure stops a vehicle until it leaves the carriageway")
	a.lane_offset=47
	check(not rules.block_requires_stop(a,accident_block),"clear emergency pavement corridor permits physically bypassing a wreck closure")
	check(rules.block_requires_stop(a,{"kind":"police"}),"pavement escape cannot bypass police restrictions")
	a=car("A",800,17.5,100); a.passengers=[driver.id]; social.vehicles=[a,b]
	social.blocks=[{"id":"TEST_WRECK","kind":"accident","active":true,"height":0.0,"position":b.position,"edge":0}]
	var stayed_clear:=true
	for step in range(300):
		manager.elapsed_seconds+=.05; social.traffic.capture(social.vehicles)
		social._move_vehicles(.05); social.traffic.resolve(social,.05)
		if a.status=="ACCIDENT": stayed_clear=false
	check(stayed_clear and a.position.x>b.position.x+60,"actual movement bypasses a wreck and its closure without a collision")
	social.blocks=[]
	a=car("A",800,17.5,100); social.vehicles=[a,b]
	var pedestrian: Dictionary=manager.agents[2]; pedestrian.indoor_id=""; pedestrian.riding=""; pedestrian.state="EXPLORING"; pedestrian.position=origin+Vector2(865,-49); pedestrian.movement_speed=15
	plan=rules.plan(a,Vector2.RIGHT,100,.05)
	check(a.get("driving_mode","")!="EVADING","pedestrians veto an emergency pavement manoeuvre")
	pedestrian.position=origin+Vector2(870,-17.5)
	plan=rules.plan(a,Vector2.RIGHT,100,.05)
	check(a.driving_reason=="YIELD_PEDESTRIAN" and plan.speed<70,"driver brakes for a pedestrian in the lane")
	pedestrian.indoor_id="TEST_ROOM"; a=car("A",800,17.5,70); b=car("B",680,17.5,100); b.emergency_active=true; social.vehicles=[a,b]
	plan=rules.plan(a,Vector2.RIGHT,100,.05)
	check(a.driving_reason=="YIELD_EMERGENCY" and plan.speed<=35,"responding emergency vehicle receives local priority")
	check(not rules.begin_action(a,"evade_pavement","OPENJEV"),"AI cannot authorize pavement use without imminent danger")
	a.status="ACCIDENT"; check(not rules.begin_action(a,"overtake","OPENJEV"),"late AI reply cannot move a wreck")
	a=car("A",800,0,20); a.position.y+=200; a.body_position=a.position; social.vehicles=[a]
	plan=rules.plan(a,Vector2.RIGHT,70,.05)
	check(plan.has("speed") and a.traffic_light=="NONE","parking/off-road approaches return a valid plan without a signal")
	manager.ai_config.enabled=true; a.next_driving_ai=0; a.status="MOVING"
	manager.phase="EVACUATION"; driver.stress=100; driver.risk_tolerance=100
	Map.traffic_signals[1]=signal_record
	var reckless:=car("A",1800,17.5,70)
	for identity in range(100):
		reckless.id="ALERT%d"%identity
		if rules.alert_urgency(reckless)>.58: break
	manager.elapsed_seconds=24
	var rush: Dictionary=rules.junction_limit(reckless,edge,Vector2.RIGHT,80,.05)
	check(reckless.driving_reason=="ALERT_IGNORE_SIGNAL" and rush.speed==80,"some alerted drivers disregard a red signal")
	manager.phase="LIVING"
	var ordinary: Dictionary=rules.junction_limit(reckless,edge,Vector2.RIGHT,80,.05)
	check(ordinary.speed<80 and is_finite(ordinary.travel),"same driver respects signal before alert")
	var daily_request:=HTTPRequest.new(); manager.ai_bridge.add_child(daily_request)
	social.daily.spontaneous.pending["TEST_PENDING"]=daily_request
	rules.request_advice(a,true)
	social.daily.spontaneous.pending.erase("TEST_PENDING"); daily_request.queue_free()
	for agent in manager.agents: social.daily.spontaneous.next_request[agent.id]=0
	social.daily.spontaneous.tick()
	check(social.daily.spontaneous.pending.is_empty(),"daily model actions yield the next free slot to waiting driving advice")
	rules.close(); manager.ai_config.enabled=false
	Map.roads=saved.roads; Map.graph=saved.graph; Map.lots=saved.lots; Map.rock_obstacles=saved.rocks; Map.parking_lots=saved.parking
	manager.initialize_run(); manager.ai_bridge.set_process(false); manager.social.close()
	check(manager.social.driving.pending.is_empty() and manager.social.junction_reservations.is_empty(),"reset clears AI requests and intersection reservations")
	for siren in manager.sirens:
		if siren.mount=="POLE": check(Map.roadway_clear(siren.position,9),"siren tower remains outside every road and junction")
	print("Traffic rules: %d checks / %d failures"%[checks,failures])
	manager.queue_free(); await process_frame; await process_frame; quit(1 if failures else 0)
