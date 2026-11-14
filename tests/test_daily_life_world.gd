extends SceneTree
const Map=preload("res://scripts/city_map.gd")
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	if not value: failures+=1; printerr("FAIL: "+label)
func run() -> void:
	var app: Node=preload("res://scenes/main.tscn").instantiate(); root.add_child(app)
	app.set_process(false); app.manager.set_process(false); app.manager.ai_bridge.set_process(false)
	app.manager.ai_config.enabled=false; app.manager.social.close(); app.manager.social.next_send=INF
	app.manager.social.config.spontaneous_actions=false
	for a in app.manager.agents: a.configured_provider="RULE_BASED"
	await physics_frame; await physics_frame
	var occupied: Array=app.manager.agents.filter(func(a):return a.get("indoor_id","")!="")
	check(not occupied.is_empty(),"scene contains indoor agents")
	var room: Dictionary=app.manager.social.daily.interiors.rooms[occupied[0].indoor_id]
	var building: Node3D=app.map_view.city.buildings[room.index]
	check(is_instance_valid(building.interior_door),"important building has an actual door mesh")
	check(is_instance_valid(building.interior_door_body),"important building has door physics")
	var details: Node=app.map_view.city.get_node("ValleyEnvironment/CityDetails")
	var shown: Dictionary={}
	for signal_head in details.signals:
		shown[signal_head.junction]=true
		check(Map.roadway_clear(signal_head.position,7),"signal mast stays off the carriageway")
	check(shown.size()==Map.traffic_signals.size(),"each controlled intersection has visible traffic signals")
	Map.interior_cutaway=true
	app.manager.start()
	var starts: Dictionary={}
	for a in app.manager.agents: starts[a.id]=a.position
	var samples: Array[float]=[]
	for _step in range(160):
		var before:=Time.get_ticks_usec()
		app.manager.advance_clock(.1)
		samples.append(float(Time.get_ticks_usec()-before)/1000)
		await physics_frame
	check(app.manager.phase=="LIVING","pre-disaster city continues before configured warning")
	check(app.manager.agents.any(func(a):return starts[a.id].distance_to(a.position)>20),"routines move in the real world")
	check(app.manager.social.history.any(func(e):return e.event_type in ["building.exited","routine.changed"]),"routine/door activity recorded")
	samples.sort()
	print("Living city world: %d failures, %d indoor starts, step CPU p50 %.2f / p95 %.2f ms"%[failures,occupied.size(),samples[80],samples[152]])
	app.manager.social.close(); app.queue_free(); await process_frame; await process_frame
	quit(1 if failures else 0)
