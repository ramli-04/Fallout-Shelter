extends SceneTree
const Manager=preload("res://scripts/simulation_manager.gd")
const Map=preload("res://scripts/city_map.gd")
const Sensor=preload("res://scripts/agent_perception.gd")
const Mind=preload("res://scripts/agent_cognition.gd")
const Observation=preload("res://scripts/agent_observation.gd")
const Actions=preload("res://scripts/llm_actions.gd")
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1; printerr("FAIL: "+label)
func outdoor(a: Dictionary, point: Vector2) -> void:
	a.indoor_id=""; a.riding=""; a.position=point; a.previous_position=point
	a.transport_height=0; a.state="MOVING"; a.group_on_foot=true; a.social_target=""; a.health=100
func run() -> void:
	var manager:=Manager.new(); root.add_child(manager)
	check(manager.load_settings(),"settings load")
	manager.initialize_run(); manager.set_process(false); manager.ai_config.enabled=false
	manager.ai_bridge.status="DISCONNECTED"
	var sim: RefCounted=manager.social
	var mind: RefCounted=sim.cognition
	check(manager.agents.size()==100 and manager.agents.all(func(a):return a.has("cognition")),"all 100 people have independent cognition")
	var edge: Dictionary=Map.roads.filter(func(e):return not e.get("elevated",false) and not e.get("ramp",false))[0]
	var point: Vector2=edge.points[1]
	var direction: Vector2=(edge.points[2]-point).normalized()
	var a: Dictionary=manager.agents[0]
	var b: Dictionary=manager.agents[1]
	outdoor(a,point); outdoor(b,point+direction*12)
	b.health=30
	var seen: Array=Sensor.observe(sim,a,mind.config)
	check(seen.any(func(item):return item.id==b.id and item.kind=="injured"),"local injury is perceived")
	check(seen.all(func(item):return item.has("distance") and item.has("position") and item.has("severity") and item.has("confidence") and item.has("timestamp")),"uniform observation metadata")
	var barrier_point: Vector2=point+direction*25
	Map.closures["sense-test"]=Rect2(barrier_point-Vector2.ONE*5,Vector2.ONE*10)
	sim.blocks.append({"id":"sense-test","position":barrier_point,"active":true,"height":0,"edge":0,"kind":"accident"})
	check(Sensor.observe(sim,a,mind.config).any(func(item):return item.id=="sense-test" and item.kind=="roadblock"),"movement closure does not hide its own visible barrier")
	check(not Map.clear_segment(point,barrier_point),"barrier still blocks movement")
	Map.closures.erase("sense-test"); sim.blocks.pop_back()
	b.indoor_id="unseen-room"
	check(not Sensor.observe(sim,a,mind.config).any(func(item):return item.id==b.id),"interior boundary hides person")
	b.indoor_id=""; b.health=0
	check(Sensor.observe(sim,a,mind.config).any(func(item):return item.id==b.id and item.kind=="deceased"),"deceased people visible")
	b.health=30
	a.cognition.observations=[Sensor.entry("injured",b.id,b.position,a,0,.7)]
	a.cognition.memory=[]; a.objective="S1"
	a.cognitive_traits.altruism=100; a.cognitive_traits.courage=100; a.cognitive_traits.fear=0; a.cognitive_traits.self_preservation=0
	check(Mind.evaluate(a).action=="HELP","altruism changes assistance choice")
	a.cognitive_traits.altruism=0; a.cognitive_traits.courage=0; a.cognitive_traits.fear=90; a.cognitive_traits.self_preservation=100
	check(Mind.evaluate(a).action!="HELP","self preservation can outweigh assistance")
	a.cognition.observations=[Sensor.entry("fire","fire-test",point-direction*15,a,0,.9)]
	mind._remember(a,0)
	check(not mind.immediate_threat(a).is_empty(),"immediate fire triggers reflex")
	mind._escape(a,a.cognition.observations[0],0)
	check(a.cognition.layer=="REFLEX","reflex overrides utility")
	manager.phase="EVACUATION"; manager.elapsed_seconds=0
	check(not Actions.apply(manager,a,{"action":"WAIT","target":"","message":"","reason":"late response","confidence":.9}),"late AI cannot override active reflex")
	var before: Vector2=a.position
	mind.move(a,.1)
	check(a.position.distance_to(before)<=a.run_speed*.1+.001,"escape respects movement budget")
	check(Map.clear_point(a.position,0),"escape remains on navigable ground")
	var preserved_position: Vector2=a.position
	a.cognition.action="FLEE"; a.cognition.until=10
	a.cognition.route=PackedVector2Array([a.position,a.position+direction*30]); a.cognition.index=1
	Map.closures["route-change"]=Rect2(a.position+direction*20-Vector2.ONE*4,Vector2.ONE*8)
	mind.move(a,.1)
	check(a.position==preserved_position and a.cognition.navigation=="ROUTE_INVALIDATED","new closure invalidates escape before movement")
	Map.closures.erase("route-change")
	a.cognition.observations=[]
	check(Mind.evaluate(a).scores.has("DETOUR"),"remembered danger influences utility")
	mind._remember(a,1000)
	check(a.cognition.memory.is_empty(),"experience expires")
	for i in range(100): mind._experience(a,"route_failure",Vector2(i*20,0),i)
	check(a.cognition.memory.size()==int(mind.config.memory_limit),"memory bounded")
	var projection:=Observation.generate(manager,a)
	check(projection.has("perceptions") and projection.has("experience") and not projection.has("vehicles"),"private AI projection includes bounded evidence")
	# Two observers decide from separate records in the same tick.
	for actor in [a,b]:
		outdoor(actor,point+direction*(0 if actor.id==a.id else 12))
		actor.cognition.next_observe=0; actor.cognition.next_decide=0; actor.cognition.until=0
	manager.environment_events.append({"event_id":"C_FIRE","event_type":"fire","target_location":point,"severity":.9,"active_status":true})
	manager.elapsed_seconds=5; mind.tick(.1)
	check(a.cognition.layer=="REFLEX" and b.cognition.layer=="REFLEX","simultaneous agents react independently")
	check(a.cognition.history!=b.cognition.history,"decision histories are individual")
	manager.environment_events.pop_back()
	# Bounded driver recovery: no progress -> reroute -> stopped ground-level exit.
	var v: Dictionary=sim.vehicles[0]
	var driver: Dictionary=sim.by_id[v.driver]
	outdoor(driver,v.position)
	driver.riding=v.id; driver.responding_to=""; driver.cognition.vehicle_id=v.id
	driver.cognition.progress_position=v.position; driver.cognition.progress_time=0; driver.cognition.replans=0
	v.passengers=[driver.id]; v.status="BLOCKED"; v.speed=0; v.height=0; v.traffic_light="NONE"
	driver.cognition.observations=[Sensor.entry("roadblock","test-block",v.position,driver,0,.7)]
	mind._driver_recovery(driver,float(mind.config.stuck_seconds)+1)
	check(driver.cognition.replans==1,"stalled driver attempts reroute")
	v.traffic_light="RED"
	mind._driver_recovery(driver,float(mind.config.abandon_seconds)+1)
	check(driver.riding==v.id,"red light does not cause abandonment")
	v.traffic_light="NONE"; driver.cognition.progress_time=0
	v.height=10
	mind._driver_recovery(driver,float(mind.config.abandon_seconds)+1)
	check(driver.riding==v.id and driver.id in v.passengers,"unsafe elevated exit is rejected")
	check(driver.cognition.action!="ABANDON_VEHICLE","rejected exit is not reported as completed")
	var inspector:=preload("res://scripts/object_inspector.gd")
	a.needs={"hunger":.5,"thirst":.5,"fatigue":.5,"health":1.0,"stress":.2}
	check(inspector.agent_text(a).contains("Autonomous cognition"),"inspector tolerates shelter needs and exposes cognition")
	# Full fixed-clock execution exercises simultaneous routines and evacuation.
	manager.new_run(42); manager.ai_config.enabled=false; manager.start(); manager.advance_clock(2)
	check(manager.agents.all(func(actor):return actor.has("cognition")),"new run rebuilds cognition")
	manager.launch_nuke(); manager.advance_clock(3)
	check(manager.agents.all(func(actor):return actor.cognition.memory.size()<=int(sim.cognition.config.memory_limit)),"multi-agent clock run keeps memory bounded")
	var first_trace: Array=[]
	for actor in manager.agents: first_trace.append([actor.id,actor.position,actor.cognition.action])
	manager.new_run(42); manager.ai_config.enabled=false; manager.start(); manager.advance_clock(2)
	manager.launch_nuke(); manager.advance_clock(3)
	var second_trace: Array=[]
	for actor in manager.agents: second_trace.append([actor.id,actor.position,actor.cognition.action])
	check(first_trace==second_trace,"same-seed local cognition produces identical multi-agent trace")
	for id in manager.social.daily.spontaneous.next_request: manager.social.daily.spontaneous.next_request[id]=0
	manager.social.daily.spontaneous.tick()
	check(manager.social.daily.spontaneous.pending.is_empty(),"AI-disabled run makes no spontaneous model requests")
	manager.social.close(); manager.queue_free(); await process_frame
	print("Agent cognition: %d checks / %d failures"%[checks,failures])
	quit(1 if failures else 0)
