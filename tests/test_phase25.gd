extends SceneTree
## Run the real controller, including local perception and scheduled consequences.
const Manager = preload("res://scripts/simulation_manager.gd")
const Rumors = preload("res://scripts/rumor_system.gd")
const Beliefs = preload("res://scripts/agent_beliefs.gd")
const Incidents = preload("res://scripts/environment_events.gd")
const ShelterState = preload("res://scripts/shelter_state.gd")
const WorldView = preload("res://scripts/world_projection.gd")
const Personality = preload("res://scripts/agent_personality.gd")
const Reactions = preload("res://scripts/agent_reactions.gd")
const Routes = preload("res://scripts/road_routes.gd")
const MAIN = preload("res://scenes/main.tscn")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + description)

func make_manager(seed_number: int = 42) -> Node:
	var manager := Manager.new()
	root.add_child(manager)
	manager.set_process(false)
	check(manager.load_settings(), "configs load")
	manager.new_run(seed_number)
	return manager

func event(type: String, location: Vector2, id: String = "", at: float = 1.0) -> Dictionary:
	return {"event_id": "TEST:" + type, "event_type": type, "target_id": id, "target_location": location,
		"scheduled_time": at, "duration": 6.0, "severity": 1.0, "active_status": false,
		"started": false, "ended": false, "actual_effect": Incidents.EFFECTS[type],
		"visibility_to_agents": [], "event_log_message": type + " test incident"}

func _run() -> void:
	var manager := make_manager()
	check(Manager.validate_living(manager.living).is_empty(), "living config validates")
	var incomplete: Dictionary = manager.living.duplicate(true)
	incomplete.erase("observation_radius")
	check(not Manager.validate_living(incomplete).is_empty(), "missing living setting rejected without runtime exception")
	for bad_key in ["communication_interval", "false_alarm_probability", "event_duration_range", "size_descriptions"]:
		var bad: Dictionary = manager.living.duplicate(true)
		bad[bad_key] = -1
		check(not Manager.validate_living(bad).is_empty(), "invalid config rejected: " + bad_key)
	var personalities := {}
	for agent in manager.agents:
		personalities[agent["primary_personality"]] = true
		for property in Personality.TRAITS:
			check(agent[property] >= 0 and agent[property] <= 100, "numeric trait in range")
		for id in agent["beliefs"]:
			check(not agent["beliefs"][id]["capacity_exact"], "no initial exact capacity knowledge")
		check(agent["beliefs"]["S5"]["existence_probability"] == 0.5, "S5 initially a rumor")
	check(personalities.size() == 15, "all archetypes represented in default population")
	# Same archetype does not imply identical traits or urgency.
	var repeated := false
	for first in manager.agents:
		for second in manager.agents:
			if first != second and first["primary_personality"] == second["primary_personality"]:
				repeated = repeated or first["trust_level"] != second["trust_level"]
	check(repeated, "individual variation within the same archetype")
	var s5_count := 0
	var event_counts := {"maintenance":0, "door":0, "road":0, "crowd":0, "rats":0}
	var alarms := 0
	for seed_number in range(512):
		manager.new_run(seed_number)
		if manager.shelter_by_id["S5"]["exists"]: s5_count += 1
		if not manager.alarm_is_real: alarms += 1
		var previous := -INF
		for incident in manager.environment_events:
			check(incident["scheduled_time"] >= previous+manager.living["event_spacing_seconds"], "scheduled incidents staggered")
			check(incident["scheduled_time"] < manager.countdown_seconds, "incident starts during warning window")
			previous = incident["scheduled_time"]
			event_counts[incident["event_type"]] += 1
	check(s5_count > 205 and s5_count < 307, "S5 frequency near 50% over 512 fixed seeds")
	check(alarms > 0 and alarms < 30, "2% false alarm sampling exercised")
	for type in event_counts:
		check(event_counts[type] > 0, "default autonomous schedule includes " + type)
	print("512 scenarios: S5 present %d (%.1f%%); false alarms %d; incidents %s" % [s5_count, s5_count/5.12, alarms, event_counts])
	manager.new_run(42)
	var initial_agents: Array = manager.agents.duplicate(true)
	var initial_shelters: Array = manager.shelters.duplicate(true)
	var schedule: Array = manager.environment_events.duplicate(true)
	var truth: bool = manager.alarm_is_real
	manager.start()
	check(manager.phase == "LIVING" and manager.running, "Start city without alarm")
	manager.advance_clock(8)
	check(not manager.events.any(func(e: Dictionary): return e["category"] == "SIREN"), "ambient clock never starts siren")
	manager.launch_nuke()
	check(manager.phase == "EVACUATION" and is_equal_approx(manager.alarm_started_seconds, 8), "alarm anchored to living clock")
	manager.advance_clock(50)
	manager.initialize_run()
	check(manager.agents == initial_agents and manager.shelters == initial_shelters and manager.environment_events == schedule and manager.alarm_is_real == truth, "Reset reproduces profiles, truth and event schedules")
	var sliced := make_manager(42)
	var batched := make_manager(42)
	for sample in [sliced, batched]:
		sample.living["false_alarm_probability"] = 0
		sample.living["event_probabilities"]["maintenance"] = 1
		sample.initialize_run()
		sample.launch_nuke()
	for i in range(200): sliced.advance_clock(1)
	batched.advance_clock(200)
	check(sliced.agents == batched.agents and sliced.environment_events == batched.environment_events and sliced.events == batched.events, "event, communication and decision replay independent of frame partition")
	sliced.queue_free()
	batched.queue_free()
	# Hidden states including the countdown cannot change a policy decision.
	manager.launch_nuke()
	var observer: Dictionary = manager.agents[0]
	observer["state"] = "DECIDING"
	manager.choose_destination(observer)
	var chosen: String = observer["objective"]
	var scores: Dictionary = observer["decision_scores"].duplicate(true)
	manager.remaining_seconds = 1
	manager.countdown_seconds = 999
	manager.alarm_is_real = false
	manager.shelter_by_id["S2"]["capacity"] = 1
	manager.shelter_by_id["S5"]["exists"] = false
	manager.choose_destination(observer)
	check(observer["objective"] == chosen and observer["decision_scores"] == scores, "policy insulated from hidden countdown, alarm and shelter truth")
	var projection := WorldView.shelters(manager.shelters, false)
	check(projection[4]["exists"] and projection[4]["rumored"] and not projection[4].has("nominal_capacity"), "observer projection masks absent S5 geometry and capacities")
	# Local observations update exactly one mind, then can be communicated.
	manager.initialize_run()
	manager.launch_nuke()
	var absent: Dictionary = manager.shelter_by_id["S5"]
	absent["exists"] = false
	absent["operational"] = false
	absent["capacity"] = 0
	absent["door_status"] = "ABSENT"
	var investigator: Dictionary = manager.agents[0]
	investigator["position"] = absent["position"]
	investigator["objective"] = "S5"
	investigator["state"] = "MOVING"
	check(manager.admit_arrival(investigator) == "Shelter does not exist", "rumored absent location rejects admission")
	check(investigator["beliefs"]["S5"]["existence_probability"] == 0 and not investigator["personal_memory"].is_empty(), "absence remembered locally")
	check(manager.agents[1]["beliefs"]["S5"]["existence_probability"] == 0.5, "absence not broadcast magically")
	# Same claim, source and evidence, different individual traits.
	var gullible: Dictionary = manager.agents[1].duplicate(true)
	var skeptical: Dictionary = gullible.duplicate(true)
	gullible["primary_personality"] = "GULLIBLE"
	skeptical["primary_personality"] = "SKEPTICAL"
	gullible["trust_level"] = 90
	gullible["skepticism"] = 10
	skeptical["trust_level"] = 10
	skeptical["skepticism"] = 95
	var rumor := {"rumor_id":"test-rumor", "claim":Rumors.CLAIMS[0], "original_source":"Neighbor", "current_speaker":"Neighbor", "timestamp":0.0, "perceived_credibility":0.65, "hops":0, "kind":"rumor"}
	var source := {"id":"Neighbor", "role":"Civilian"}
	check(Rumors.receive(gullible, rumor, source, 1, manager.living) == "believe", "trusting recipient believes rumor")
	check(Rumors.receive(skeptical, rumor, source, 1, manager.living) == "reject", "skeptical recipient rejects same rumor")
	check(gullible["beliefs"]["S5"]["existence_probability"] != skeptical["beliefs"]["S5"]["existence_probability"], "individual rumor reactions change beliefs differently")
	var corrected := Rumors.observation_message(investigator, "S5", 2)
	check(Rumors.receive(gullible, corrected, investigator, 3, manager.living) == "believe report" and gullible["beliefs"]["S5"]["existence_probability"] == 0, "fresh entrance evidence corrects false rumor")
	var local: Dictionary = manager.agents[2]
	local["position"] = Vector2(900, 0)
	local["messages"] = []
	var distant: Dictionary = manager.agents[3]
	distant["position"] = Vector2(1800, 1080)
	distant["heard_ids"] = {}
	local["messages"].append(rumor)
	Rumors.exchange(manager)
	check(not distant["heard_ids"].has("test-rumor"), "local communication excludes distant recipients")
	# S3 can relay deposited evidence to someone outside ordinary communication radius.
	manager.initialize_run()
	var relay: Dictionary = manager.shelter_by_id["S3"]
	var depositor: Dictionary = manager.agents[0]
	depositor["position"] = manager.shelter_by_id["S1"]["position"]
	Beliefs.observe(depositor, manager.shelter_by_id["S1"], 1, manager.living)
	var report := Rumors.observation_message(depositor, "S1", 1)
	depositor["messages"] = [report]
	depositor["position"] = relay["position"]
	var receiver: Dictionary = manager.agents[1]
	receiver["position"] = relay["position"] + Vector2(180, 0)
	receiver["trust_level"] = 90
	receiver["skepticism"] = 10
	manager.elapsed_seconds = 2
	Rumors.exchange(manager)
	check(receiver["heard_ids"].has(report["rumor_id"]) and receiver["beliefs"]["S1"]["capacity_exact"], "S3 communicates deposited observation beyond ordinary contact radius")
	check(not receiver["beliefs"]["S2"]["capacity_exact"], "S3 never invents knowledge of unobserved shelters")
	# Expired packets cannot spread.
	manager.elapsed_seconds = 200
	var newcomer: Dictionary = manager.agents[2]
	newcomer["position"] = relay["position"]
	Rumors.exchange(manager)
	check(not newcomer["heard_ids"].has(report["rumor_id"]), "expired relay packets are ignored")
	# Event consequences operate solely through fixed clock; no director intervention.
	manager.initialize_run()
	manager.living["false_alarm_probability"] = 0
	manager.initialize_run()
	manager.launch_nuke()
	manager.environment_events.assign([event("maintenance", manager.shelter_by_id["S2"]["position"], "S2"), event("door", manager.shelter_by_id["S1"]["position"], "S1", 2), event("rats", manager.shelter_by_id["S2"]["position"], "S2", 3)])
	var supplies_before: float = manager.shelter_by_id["S2"]["supply_level"]
	manager.advance_clock(4)
	check(not manager.shelter_by_id["S2"]["operational"] and manager.shelter_by_id["S1"]["door_status"] == "BLOCKED", "scheduled incidents autonomously disable entrances")
	check(manager.shelter_by_id["S2"]["infested"] and manager.shelter_by_id["S2"]["supply_level"] < supplies_before, "rats cause contamination and supply damage")
	var traveler: Dictionary = manager.agents[0]
	traveler["position"] = manager.shelter_by_id["S1"]["position"]
	traveler["state"] = "MOVING"
	traveler["objective"] = "S1"
	traveler["shelter_id"] = ""
	check(manager.admit_arrival(traveler) == "Shelter door is blocked", "blocked door rejects actual arrival")
	check(manager.events.any(func(e: Dictionary): return e["category"] == "ENVIRONMENT" and e["message"].contains("started")), "journal records actual event activation")
	manager.advance_clock(6)
	check(manager.shelter_by_id["S2"]["operational"] and manager.shelter_by_id["S1"]["door_status"] == "OPEN" and not manager.shelter_by_id["S2"]["infested"], "temporary incidents clear without clobbering other states")
	check(manager.shelter_by_id["S2"]["supply_level"] < supplies_before, "lost supplies remain lost after rats clear")
	manager.initialize_run()
	manager.launch_nuke()
	manager.environment_events.assign([event("road", Vector2(720,540), "", 0)])
	var road_agent: Dictionary = manager.agents[0]
	road_agent["primary_personality"] = "SURVIVALIST"
	road_agent["state"] = "MOVING"
	road_agent["objective"] = "S2"
	road_agent["position"] = Vector2(720,540)
	road_agent["route"] = PackedVector2Array([Vector2(720,540), Vector2(900,540), Vector2(900,720)])
	road_agent["route_index"] = 1
	manager.next_decision_seconds = 1000
	manager.advance_clock(1)
	check(road_agent["state"] == "WAITING_ROAD" and road_agent["position"] == Vector2(720,540), "road blockage physically stops affected traveler")
	manager.advance_clock(7)
	check(road_agent["state"] == "MOVING" and road_agent["position"] != Vector2(720,540), "traveler resumes when road clears")
	manager.initialize_run()
	manager.launch_nuke()
	var crowd_agent: Dictionary = manager.agents[0]
	manager.environment_events.assign([event("crowd", crowd_agent["position"], "", 0)])
	Incidents.update(manager)
	var panic_before: float = crowd_agent["panic_level"]
	Reactions.perceive(manager)
	check(crowd_agent["panic_level"] > panic_before and not crowd_agent["avoided_locations"].is_empty(), "local crowd observation raises panic and route avoidance")
	var calm: Dictionary = crowd_agent.duplicate(true)
	calm["primary_personality"] = "OVERWHELMED"
	calm["panic_level"] = 40
	calm["state"] = "MOVING"
	Reactions.act(manager, calm, 0.1)
	check(calm["state"] != "FROZEN", "overwhelmed label alone never guarantees freezing")
	calm["panic_level"] = 95
	Reactions.act(manager, calm, 0.1)
	check(calm["state"] == "FROZEN" and calm["wait_until"] > manager.elapsed_seconds, "extreme stress produces temporary freeze")
	# Force chance=1 through the supported config, exercising true false-alarm lifecycle.
	manager.living["false_alarm_probability"] = 1
	for seed_number in range(8):
		manager.new_run(seed_number)
		manager.start()
		manager.advance_clock(3)
		manager.launch_nuke()
		manager.advance_clock(1000)
		check(manager.phase == "ALL_CLEAR" and not manager.running and manager.get_totals()["exposed"] == 0, "false alarm ends safely")
		check(not manager.events.any(func(e: Dictionary): return e["category"] == "IMPACT"), "false alarm never logs impact")
		check(is_equal_approx(manager.elapsed_seconds, manager.countdown_seconds+3), "false alarm all-clear uses anchored hidden delay")
		for a in manager.agents:
			check(a["messages"].size() <= manager.living["rumor_history_limit"] and a["personal_memory"].size() <= manager.living["memory_limit"] and a["rumors_heard"].size() <= manager.living["rumor_history_limit"], "bounded messages and memories")
	manager.queue_free()
	# Main scene, view-mode isolation, reset, seed controls and actual trace export.
	var app: Control = MAIN.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	app.manager.set_process(false)
	app.manager.living["false_alarm_probability"] = 0
	app.manager.initialize_run()
	check(app.countdown_label.text == "--:--" and app.director_mode, "director is the only viewing mode")
	app.start_button.pressed.emit()
	check(app.manager.phase == "LIVING" and not app.effects.player.playing, "Start button does not sound siren")
	app.launch_button.pressed.emit()
	check(app.countdown_label.text != "Unknown" and app.effects.player.playing, "director sees actual deadline while siren sounds")
	app.manager.advance_clock(10)
	var state: Array = app.manager.agents.duplicate(true)
	var logs: Array = app.manager.events.duplicate(true)
	var clock: float = app.manager.elapsed_seconds
	var camera_position: Vector3 = app.map_view.camera_rig.position
	app.map_view.camera_rig.pan(Vector2.RIGHT, 1)
	app.map_view.camera_rig.rotate_drag(Vector2(30,10))
	app.map_view.camera_rig.zoom_steps(1)
	app.map_view.camera_rig.advance(0.2)
	await process_frame
	check(app.manager.agents == state and app.manager.events == logs and app.manager.elapsed_seconds == clock, "3D camera never mutates engine")
	check(app.map_view.camera_rig.position != camera_position, "3D camera actually moved")
	check(app.countdown_label.text != "Unknown" and app.false_alarm_button.visible, "director reveals deadline and manual false alarm")
	app.export_button.pressed.emit()
	var trace_path := "user://essaim_trace_%d.json" % app.manager.seed_value
	var trace: Variant = JSON.parse_string(FileAccess.get_file_as_string(trace_path))
	check(trace is Dictionary and trace["agents"][0]["position"] is Array and trace["environment"] is Array, "export creates parseable reproducibility trace")
	app.manager.advance_clock(1000)
	check(app.manager.phase == "IMPACT" and is_instance_valid(app.map_view.impact_effect), "real alarm still ends in visual impact")
	app.reset_button.pressed.emit()
	app.false_alarm_button.pressed.emit()
	app.manager.advance_clock(1000)
	check(app.manager.phase == "ALL_CLEAR" and app.summary_panel.visible and not is_instance_valid(app.map_view.impact_effect), "director false-alarm control never creates impact effect")
	app.random_button.pressed.emit()
	check(app.manager.phase == "PREPARATION" and app.seed_picker.value == app.manager.seed_value, "random scenario stores displayed seed")
	app.seed_picker.value = 42
	app.new_run_button.pressed.emit()
	check(app.manager.seed_value == 42, "Use seed honors chosen value exactly")
	check(app.event_feed.get_parsed_text().contains("Hidden warning") and app.map_view.shelter_nodes.size() == 5, "director sees scenario truth")
	app.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("Phase 2.5: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
