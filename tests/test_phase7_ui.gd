extends SceneTree
const Coordinates=preload("res://scripts/three_d/world_coordinates.gd")
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1; printerr("FAIL: "+label)
func run() -> void:
	var app=preload("res://scenes/main.tscn").instantiate(); root.add_child(app)
	app.manager.set_process(false); app.manager.ai_bridge.set_process(false)
	app.social_window.set_config(preload("res://scripts/social_config.gd").defaults())
	app.social_window.fields.llm_agents.value=0
	await app.social_window._start()
	var manager: Node=app.manager
	var control: Node=app.find_child("EmergencyControls",true,false)
	var police: Node=app.find_child("PoliceControls",true,false)
	var index: int=manager.emergency.TYPES.find("POLICE_SHELTER_EVACUATION")
	check(index>=0 and control!=null and police!=null,"Director exposes new emergency and existing police inspector")
	control.kind.select(index); control.kind.item_selected.emit(index); control.target.select(1)
	check(control.duration.value>=1200 and control.radius.value>=250,"organized evacuation has useful dispatch duration and area defaults")
	var civilian: Dictionary=manager.agents.filter(func(a):return a.role=="Civilian")[0]
	var area: Vector2=civilian.position
	app.map_view.camera_rig.target_focus=Coordinates.to_world(area)
	var before: Array=manager.agents.map(func(a):return a.position)
	control.trigger()
	var source: String=control.last_event
	var e: Dictionary=manager.environment_events.filter(func(event):return event.event_id==source)[0]
	check(e.target_location.distance_to(area)<.01 and e.target_id=="S1","camera selects affected area while shelter selector sets destination preference")
	check(manager.agents.map(func(a):return a.position)==before,"triggering the event never teleports a civilian or officer")
	manager.advance_clock(.1)
	var op: Dictionary=manager.social.evacuation.operation(source)
	check(not op.is_empty() and not op.tasks.is_empty(),"full simulation clock starts coordinated planning and real dispatch")
	police.refresh()
	check(police.details.text.contains("ORGANIZED EVACUATION") and police.details.text.contains(source),"police inspector displays operation and group history")
	app.map_view.social_world._process(0)
	check(app.map_view.social_world.evacuation_markers.has(source),"gathering marker reflects actual operation record")
	var elapsed: float=manager.elapsed_seconds
	manager.pause(); manager.advance_clock(3)
	check(manager.elapsed_seconds==elapsed,"pause freezes evacuation simulation time")
	manager.emergency.clear_event(source)
	manager.start(); manager.advance_clock(.2)
	check(op.state in ["RETURNING","COMPLETE"],"clearing event initiates cleanup through normal simulation clock")
	var snapshot: Dictionary=manager.social.evacuation.snapshot().duplicate(true)
	check(snapshot.operations[0].id==source,"snapshot retains source event and operation identity")
	var encoded: Variant=manager.social.encode(snapshot)
	check(JSON.parse_string(JSON.stringify(encoded)) is Dictionary,"operation and group snapshots serialize through existing recorder")
	app.queue_free(); await process_frame
	print("Phase 7 UI: %d checks / %d failures"%[checks,failures]); quit(1 if failures else 0)
