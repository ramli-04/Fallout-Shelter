extends SceneTree
const Manager=preload("res://scripts/simulation_manager.gd")
const Observation=preload("res://scripts/agent_observation.gd")
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures+=1; printerr("FAIL: "+label)
func arrive(manager: Node, a: Dictionary, shelter_id: String) -> void:
	if a.get("riding","")!="":
		for v in manager.social.vehicles: v.passengers.erase(a.id)
	a.riding=""; a.indoor_id=""; a.travel_group=""; a.boarding_vehicle=""
	a.position=manager.shelter_by_id[shelter_id].position; a.objective=shelter_id
	a.state="MOVING"; a.health=100
	manager.admit_arrival(a)
func run() -> void:
	var manager:=Manager.new(); root.add_child(manager); manager.set_process(false)
	check(manager.load_settings(),"settings")
	manager.social_config.llm_agents=0; manager.social_config.spontaneous_actions=false
	manager.initialize_run(); manager.ai_bridge.set_process(false); manager.social.close(); manager.social.next_send=INF
	check(manager.shelters.size()==5,"five academic shelter records remain")
	check(manager.shelters.map(func(s):return int(s.capacity))==[125,37,90,175,250],"academic shelter capacities remain")
	var first: Dictionary=manager.agents[0]; var second: Dictionary=manager.agents[1]
	manager.phase="EVACUATION"
	var indoors: Dictionary=manager.agents.filter(func(a):return a.age>=18 and a.indoor_id!="")[0]
	var original: Vector2=indoors.position
	var decision: Dictionary={"action":"MOVE_TO_SHELTER","target":"S1","message":"","reason":"Use my known exit and shelter","confidence":.8}
	check(preload("res://scripts/llm_actions.gd").apply(manager,indoors,decision),"existing LLM shelter actions can plan from inside a building")
	check(indoors.position==original and not indoors.route.is_empty(),"LLM planning never teleports an indoor agent")
	check(preload("res://scripts/evacuation_decisions.gd").evaluate(indoors,600,manager.settings.evacuation.weights).shelter_id!="","rule policy can plan from the agent's known door")
	var s1: Dictionary=manager.shelter_by_id.S1
	s1.capacity=1; s1.accepting=true; s1.operational=true
	manager.ShelterState.set_door_state(s1,"OPEN")
	arrive(manager,first,"S1")
	check(first.state=="SHELTERED" and s1.occupancy==1,"physical shelter arrival admits an agent")
	arrive(manager,second,"S1")
	check(second.state=="REJECTED" and s1.occupancy==1,"full shelter rejects without changing occupancy")
	check(not manager.can_observe(second,first),"sheltered relatives are not visible outdoors")
	check(not Observation.generate(manager,second).nearby_agents.any(func(a):return a.id==first.id),"LLM observations do not reveal hidden sheltered occupants")
	var s2: Dictionary=manager.shelter_by_id.S2
	manager.ShelterState.set_door_state(s2,"CLOSED")
	arrive(manager,second,"S2")
	check(second.state!="SHELTERED" and s2.occupancy==0,"closed shelter door still refuses entry")
	manager.initialize_run(); manager.ai_bridge.set_process(false); manager.social.close()
	check(manager.shelters.all(func(s):return s.occupancy==0),"reset clears shelter occupancy")
	check(manager.agents.all(func(a):return manager.social.daily.valid_spawn(a)),"reset restores valid living-city spawns")
	print("Living shelter regression: %d checks / %d failures"%[checks,failures])
	manager.queue_free(); await process_frame; await process_frame; quit(1 if failures else 0)
