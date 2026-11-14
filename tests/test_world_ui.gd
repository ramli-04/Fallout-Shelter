extends SceneTree
const Map=preload("res://scripts/city_map.gd")
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1; printerr("FAIL: "+label)
func run() -> void:
	var app=preload("res://scenes/main.tscn").instantiate(); root.add_child(app)
	var manager: Node=app.manager; manager.set_process(false); manager.ai_bridge.set_process(false)
	manager.social_config.llm_agents=0; manager.social_config.automatic_warning=false
	var panel: Node=app.find_child("WorldGenerationControls",true,false)
	check(panel!=null and panel.preview!=null,"world panel includes actual map preview")
	panel.seed_input.value=42; panel.size_picker.select(0); panel.width_input.value=1.1
	panel._generate()
	check(manager.world.busy,"Director generate launches background pipeline")
	check(await manager.world.completed,"Director generation completes")
	var id: String=manager.world.current.world_id
	check(Map.map_seed==42 and app.seed_label.text.contains("WORLD 42"),"HUD displays actual world seed separately from run")
	check(is_equal_approx(Map.generation_settings.road_width_multiplier,1.1),"stored road settings reach shared renderer")
	check(app.map_view.city.collision.buildings.size()==Map.lots.size() and app.map_view.city.buildings.size()<Map.lots.size(),"world inventory persists while detailed scene assets stream")
	check(app.map_view.shelter_nodes.all(func(node):return node.record.id!="S5" or not node.visible),"S5 entrance remains hidden until discovered")
	panel.path_input.text="user://worlds/ui_roundtrip.json"
	check(manager.world.save_world(panel.path_input.text),"export actual world")
	manager.start(); panel._process(0)
	check(panel.apply_button.disabled and panel.size_picker.disabled,"generation locked during simulation")
	check(panel.world_buttons.filter(func(button):return button.text.begins_with("Copy") or button.text.begins_with("Save")).all(func(button):return not button.disabled),"copy and save remain available during simulation")
	manager.advance_clock(1); manager.pause()
	var recording: String="res://outputs/phase5/"+manager.ai_bridge.run_id+".jsonl"
	manager.social.recorder.close()
	await app.social_window._replay(recording)
	if not manager.social.replaying: printerr("Replay diagnostic: "+app.social_window.feedback.text+" / "+recording)
	check(manager.social.replaying and manager.world.current.world_id==id,"recording replays its saved canonical world through validation")
	check(not manager.running and manager.social.replay_frames.size()>0,"replay remains observation-only with actual frames")
	app.queue_free(); await process_frame
	print("World generation UI: %d checks / %d failures"%[checks,failures]); quit(1 if failures else 0)
