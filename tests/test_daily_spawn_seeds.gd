extends SceneTree
const Manager=preload("res://scripts/simulation_manager.gd")
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures+=1; printerr("FAIL: "+label)
func run() -> void:
	var manager:=Manager.new(); root.add_child(manager); manager.set_process(false)
	check(manager.load_settings(),"settings load")
	manager.social_config.llm_agents=0; manager.social_config.spontaneous_actions=false
	for seed_value in [0,2,7]:
		manager.seed_value=seed_value; manager.initialize_run(); manager.ai_bridge.set_process(false); manager.social.close()
		check(manager.last_setup_error.is_empty(),"seed %d setup"%seed_value)
		for a in manager.agents: check(manager.social.daily.valid_spawn(a),"seed %d spawn %s"%[seed_value,a.id])
		for family in manager.social.families:
			var home: String=manager.social.by_id[family.members[0]].home_building
			for id in family.members: check(manager.social.by_id[id].home_building==home,"household shares a home")
	manager.social_config.total=400; manager.social_config.civilians=365; manager.social_config.children=30; manager.social_config.school_students=25
	manager.seed_value=42; manager.initialize_run(); manager.ai_bridge.set_process(false); manager.social.close()
	check(manager.last_setup_error.is_empty(),"400-agent setup")
	for a in manager.agents: check(manager.social.daily.valid_spawn(a),"400-agent valid spawn "+a.id)
	print("Living spawn seeds/capacity: %d checks / %d failures"%[checks,failures])
	manager.queue_free(); await process_frame; await process_frame; quit(1 if failures else 0)
