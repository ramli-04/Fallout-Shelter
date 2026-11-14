extends SceneTree
## No synthetic map or actor relocation: exercise the seeded 100-person runtime.
const Manager=preload("res://scripts/simulation_manager.gd")
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1; printerr("FAIL: "+label)
func run() -> void:
	var manager:=Manager.new(); root.add_child(manager); manager.load_settings()
	manager.social_config.llm_agents=0; manager.social_config.automatic_warning=false
	manager.initialize_run(); manager.set_process(false); manager.ai_bridge.set_process(false)
	manager.ai_config.enabled=false; manager.social.driving.settings.ai_enabled=false
	manager.start()
	var civilians: Array=manager.agents.filter(func(a):return a.role=="Civilian" and a.health>0)
	var center: Vector2=civilians[0].position; var count:=0
	for a in civilians:
		var nearby: int=civilians.filter(func(other):return other.position.distance_to(a.position)<=300).size()
		if nearby>count: count=nearby; center=a.position
	var source: String=manager.add_emergency("POLICE_SHELTER_EVACUATION",center,{"radius":300,"duration":1200})
	check(source!="" and manager.agents.size()==100,"actual seeded population accepts operation without repositioning actors")
	var finite:=true; var capacity:=true; var exclusive:=true
	for i in range(180):
		manager.advance_clock(1)
		finite=finite and manager.agents.all(func(a):return a.position.is_finite()) and manager.social.vehicles.all(func(v):return v.position.is_finite())
		capacity=capacity and manager.shelters.all(func(s):return s.occupancy==s.occupant_ids.size() and s.occupancy<=s.capacity)
		var assigned: Array=manager.social.police.requests.filter(func(r):return r.state not in ["EVALUATED","REQUESTED","REMOVED"] and r.unit!="").map(func(r):return r.unit)
		var unique: Dictionary={}
		for id in assigned: unique[id]=true
		exclusive=exclusive and unique.size()==assigned.size()
	var op: Dictionary=manager.social.evacuation.operation(source)
	check(not op.is_empty() and op.estimated_count==count,"operation estimate reflects actual affected population")
	check(absf(manager.elapsed_seconds-180)<0.001 and manager.phase=="LIVING","full fixed clock runs three simulated minutes with ordinary city activity (%.6f seconds, %s)"%[manager.elapsed_seconds,manager.phase])
	check(finite and capacity and exclusive,"natural concurrent runtime preserves finite positions, actual occupancy and exclusive police assignments")
	var dispatched: bool=manager.social.police.requests.any(func(r):return r.get("operation","")==source and r.history.any(func(h):return h.state=="DISPATCHED"))
	check(dispatched,"existing patrol physically dispatches in the unmodified seeded city")
	if not dispatched:
		for request_id in op.tasks.values():
			var request: Dictionary=manager.social.police.request_for(request_id)
			print(manager.social.police.inspection(request_id))
			var unit: Dictionary=manager.social.police.unit_for(request.unit)
			if not unit.is_empty():
				print("Vehicle ",manager.social.police.vehicle(unit))
				for officer_id in unit.officers:
					var officer: Dictionary=manager.social.by_id[officer_id]
					print("Officer ",officer_id," / ",officer.position," indoor ",officer.indoor_id," ride ",officer.get("riding","")," action ",officer.cognition.action," target ",officer.get("police_walk_target",Vector2.INF)," route ",officer.get("police_walk_route",[]))
	check(manager.agents.size()==100 and manager.social.police.units.size()==6,"operation neither spawns population nor extra patrols")
	print("Live evacuation operation: ",op.get("state","missing")," / groups ",manager.social.evacuation.groups.size()," / initially affected ",count)
	manager.queue_free(); await process_frame
	print("Police evacuation live: %d checks / %d failures"%[checks,failures]); quit(1 if failures else 0)
