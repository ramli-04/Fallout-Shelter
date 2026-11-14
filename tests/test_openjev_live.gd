extends SceneTree
const Manager=preload("res://scripts/simulation_manager.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var manager:=Manager.new(); root.add_child(manager); manager.set_process(false)
	if not manager.load_settings(): quit(1); return
	manager.social_config.llm_agents=0; manager.social_config.spontaneous_actions=false
	manager.social_config.phone_rate=1; manager.social_config.network_availability=1
	manager.initialize_run(); manager.ai_bridge.set_process(false); manager.social.close(); manager.social.next_send=INF
	manager.phase="LIVING"
	var actor: Dictionary=manager.agents.filter(func(a):return a.age>=18 and a.role=="Civilian" and not a.relationships.is_empty() and a.get("riding","")=="" and a.indoor_id==a.home_building)[0]
	actor.fatigue=98; actor.needs.fatigue=.98; actor.routine="HOME"
	var service: RefCounted=manager.social.daily.spontaneous
	for a in manager.agents: service.next_request[a.id]=INF
	service.next_request[actor.id]=0; service.config.max_pending=1
	service.tick()
	for _step in range(1000):
		await create_timer(.02).timeout
		if service.pending.is_empty(): break
	var success: bool=service.completed==1 and actor.get("spontaneous_provider","")=="OPENJEV"
	var events_before: int=manager.social.history.size()
	service.next_request[actor.id]=0
	service.tick()
	manager.phase="EVACUATION"; service.close()
	await create_timer(.5).timeout
	success=success and service.pending.is_empty() and manager.social.history.size()==events_before and not service.apply(actor,"rest","OPENJEV")
	print("OpenJev live: %s / %s / %s"%[service.status,actor.get("last_spontaneous_action","none"),actor.get("spontaneous_provider","none")])
	manager.social.close(); manager.queue_free(); await process_frame; await process_frame
	quit(0 if success else 1)
