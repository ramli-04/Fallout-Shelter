extends SceneTree
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(v: bool, text: String) -> void:
	checks+=1
	if not v: failures+=1; printerr("FAIL: "+text)
func run() -> void:
	var app=preload("res://scenes/main.tscn").instantiate(); root.add_child(app)
	app.manager.set_process(false); app.manager.ai_bridge.set_process(false)
	var menu: Window=app.social_window
	check(menu.current().total==100 and menu.current().civilians==65 and menu.current().authorities==35,"default population menu")
	menu.fields.civilians.value=66
	check(menu.current().total==101,"civilian adjustment maintains total")
	menu.fields.authorities.value=30
	check(menu.current().civilians==71,"authority adjustment maintains total")
	menu.set_config(preload("res://scripts/social_config.gd").defaults())
	menu.fields.llm_agents.value=0
	await menu._start()
	check(app.manager.running and app.manager.phase=="LIVING","configuration start launches simulation")
	check(app.manager.agents.size()==100 and app.manager.agents.all(func(a):return a.configured_provider=="RULE_BASED"),"rule-only UI selection applied")
	var emergencies: Node=app.find_child("EmergencyControls",true,false)
	check(emergencies!=null,"director emergency controls available")
	var police: Node=app.find_child("PoliceControls",true,false)
	check(police!=null,"director police inspection controls available")
	police.refresh()
	check(police.details.text.contains("POLICE UNITS: 6"),"police panel shows actual paired patrol roster")
	emergencies.kind.select(app.manager.emergency.TYPES.find("shelter_closure")); emergencies.target.select(1)
	emergencies.trigger(); app.manager.advance_clock(.1)
	check(not app.manager.shelter_by_id.S1.accessible,"director control applies real shelter closure")
	app.manager.emergency.clear_event(emergencies.last_event)
	check(app.manager.shelter_by_id.S1.accessible,"director event clear restores shelter access")
	app.manager.pause()
	menu._start()
	check(menu.feedback.text.contains("Reset"),"running scenario cannot silently reconfigure")
	app.queue_free(); await process_frame
	print("Phase 5 UI: %d checks / %d failures"%[checks,failures]); quit(1 if failures else 0)
