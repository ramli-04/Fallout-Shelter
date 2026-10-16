extends SceneTree
const Manager = preload("res://scripts/simulation_manager.gd")
const Activity = preload("res://scripts/civilian_activity.gd")
const Map = preload("res://scripts/city_map.gd")
const Routes = preload("res://scripts/road_routes.gd")
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: "+text)

func run() -> void:
	var sim := Manager.new()
	root.add_child(sim)
	sim.set_process(false)
	check(sim.load_settings(),"configuration")
	sim.ai_config["enabled"] = false
	sim.new_run(42)
	check(sim.agents.all(func(a): return a["run_speed"] >= 28 and a["walk_speed"] > 10),"human-scale walking and running")
	check(sim.agents.any(func(a): return a["primary_personality"] == "NIHILIST"),"nihilist archetype")
	check(sim.agents.any(func(a): return a["primary_personality"] == "DESPAIRING"),"despairing archetype")
	var before: Array = sim.agents.map(func(a): return a["position"])
	sim.start()
	sim.advance_clock(2)
	var moved := 0
	for i in range(sim.agents.size()):
		if sim.agents[i]["position"].distance_to(before[i]) > 1: moved += 1
		check(Map.clear_point(sim.agents[i]["position"],0),"roaming remains outside obstacles")
	check(moved >= 25 and sim.phase == "LIVING","population roams before sirens")
	var point: Vector2 = Map.park.get_center()+Vector2(90,110)
	var target := point+Vector2(120,60)
	var direct := Routes.plan(point,target)
	check(direct.size() == 2,"cross-country route can leave roads")
	sim.launch_nuke()
	check(sim.agents.all(func(a): return a["movement_speed"] == a["run_speed"]),"alarm switches to running speed")
	var pusher: Dictionary = sim.agents[0]
	var victim: Dictionary = sim.agents[1]
	for agent in [pusher,victim]:
		agent["state"] = "MOVING"
		agent["next_push_time"] = 0
		agent["position"] = point
	pusher["cooperation"] = 0
	pusher["panic_level"] = 100
	pusher["primary_personality"] = "AGGRESSIVE"
	victim["position"] += Vector2(10,0)
	victim["cooperation"] = 100
	var victim_before: Vector2 = victim["position"]
	Activity.crowd_actions(sim)
	check(victim["state"] == "STAGGERED" and victim["position"] != victim_before,"crowd pushing displaces and staggers")
	check(victim["trust_relationships"].get(pusher["id"],1) < 0.5,"pushing affects trust")
	Activity.dance(sim,victim,3)
	check(victim["state"] == "DANCING" and Activity.special(sim,victim,0.1),"temporary dance action")
	var human = preload("res://scenes/three_d/agent.tscn").instantiate()
	human.configure(victim)
	root.add_child(human)
	human.update_visual(victim,1,true,sim.elapsed_seconds)
	human._process(0.25)
	check(human.arms.size() == 2 and human.legs.size() == 2 and human.bean.mesh is BoxMesh,"humanoid body replaces capsule")
	check(absf(human.arms[0].rotation.z) > 0.5,"dancing animates arms")
	human.queue_free()
	var shelter: Dictionary = sim.shelter_by_id["S1"]
	pusher["state"] = "SHELTERED"
	pusher["shelter_id"] = "S1"
	pusher["sheltered_at"] = 0
	pusher["panic_level"] = 100
	pusher["self_preservation"] = 100
	sim.elapsed_seconds = 3
	for seed_value in range(100):
		pusher["appearance_seed"] = seed_value
		pusher["activity_counter"] = 0
		if Activity.random(pusher).randf() < 0.65:
			pusher["activity_counter"] = 0
			break
	Activity.special(sim,pusher,0.1)
	check(shelter["door_status"] == "CLOSING" and not shelter["accepting"],"fear starts an early vault closure")
	sim.elapsed_seconds += 2.5
	Activity.crowd_actions(sim)
	check(shelter["door_status"] == "CLOSED" and shelter["closed_by_agent"] == pusher["id"],"fear closure completes and records actor")
	for speed in [1.0,10.0]:
		sim.new_run(42)
		sim.agents.resize(1)
		sim.start()
		sim.launch_nuke()
		sim.alarm_is_real = true
		sim.countdown_seconds = 1
		sim.remaining_seconds = 1
		sim.simulation_speed = speed
		sim.advance_clock(1.0/speed)
		check(sim.phase == "BOMB_FALL" and sim.running,"zero countdown starts descent instead of impact")
		sim.pause()
		sim.advance_clock(5)
		check(sim.bomb_fall_elapsed == 0,"pause freezes bomb descent")
		sim.start()
		sim.advance_clock(7.9)
		check(sim.phase == "BOMB_FALL","no early impact at selected simulation speed")
		var late_agent: Dictionary = sim.agents[0].duplicate(true)
		late_agent["id"] = "LATE_TEST"
		late_agent["shelter_id"] = ""
		sim.shelter_by_id["S1"]["accepting"] = true
		sim.ShelterState.set_door_state(sim.shelter_by_id["S1"],"OPEN")
		late_agent["position"] = sim.shelter_by_id["S1"]["position"]
		late_agent["objective"] = "S1"
		late_agent["state"] = "MOVING"
		check(sim.admit_arrival(late_agent).is_empty(),"agents may still enter during descent")
		sim.advance_clock(0.1)
		check(sim.phase == "IMPACT" and not sim.running,"impact exactly eight real seconds later")
	sim.new_run(42)
	check(sim.bomb_fall_elapsed == 0 and sim.phase == "PREPARATION","reset clears descent")
	var sound: AudioStream = load("res://assets/audio/warnings/bomb_dropping_cc0.mp3")
	check(sound.get_length() > 5 and sound.get_length() < 6,"internet whistle decodes")
	sim.queue_free()
	await process_frame
	print("Civilian activity: %d checks / %d failures" % [checks,failures])
	quit(1 if failures else 0)
