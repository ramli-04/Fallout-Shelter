extends SceneTree
## Integration and boundary scenarios; no plugins, networking, or survival model.

const Manager = preload("res://scripts/simulation_manager.gd")
const Decisions = preload("res://scripts/evacuation_decisions.gd")
const Routes = preload("res://scripts/road_routes.gd")
const Admission = preload("res://scripts/shelter_admission.gd")
const MAIN_SCENE = preload("res://scenes/main.tscn")

var failures := 0
var checks := 0


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
	check(manager.load_settings(), "default configuration loads")
	manager.seed_value = seed_number
	manager.initialize_run()
	return manager


func force_trip(manager: Node, agent: Dictionary, id: String, start: Vector2) -> void:
	agent["state"] = "MOVING"
	agent["position"] = start
	agent["previous_position"] = start
	agent["objective"] = id
	agent["route"] = Routes.plan(start, manager.shelter_by_id[id]["position"])
	agent["route_index"] = 1


func _run() -> void:
	var manager := make_manager()
	var initial_agents: Array = manager.agents.duplicate(true)
	var initial_shelters: Array = manager.shelters.duplicate(true)
	var countdown: int = manager.countdown_seconds
	var countdown_values: Array[int] = []
	var s5_values: Array[bool] = []
	for seed_number in range(32):
		manager.new_run(seed_number)
		check(manager.countdown_seconds >= 300 and manager.countdown_seconds <= 600, "countdown remains within 5–10 minutes")
		if manager.countdown_seconds not in countdown_values:
			countdown_values.append(manager.countdown_seconds)
		if manager.shelters[4]["exists"] not in s5_values:
			s5_values.append(manager.shelters[4]["exists"])
	check(countdown_values.size() > 1, "countdown varies between seeds")
	check(s5_values.size() == 2, "both S5 existence outcomes exercised")
	manager.new_run(42)
	check(manager.agents == initial_agents and manager.shelters == initial_shelters, "seed restores initial profiles and shelters")
	check(manager.countdown_seconds == countdown, "seed restores countdown")
	manager.start()
	check(manager.phase == "EVACUATION" and manager.running, "Start activates evacuation")
	for agent in manager.agents:
		check(not agent["objective"].is_empty(), "each default agent chooses a destination")
		if not agent["objective"].is_empty():
			check(agent["decision_scores"][agent["objective"]]["eligible"], "chosen destination is belief-eligible")
		check(agent["decision_history"].size() == 1, "initial explanation recorded once")
	var siren_events := 0
	check(manager.admit_arrival(manager.agents[0]) == "Agent has not reached entrance", "remote agent cannot request admission or learn hidden state")
	for event in manager.events:
		if event["category"] == "SIREN": siren_events += 1
	manager.pause()
	manager.start()
	var resumed_sirens := 0
	for event in manager.events:
		if event["category"] == "SIREN": resumed_sirens += 1
	check(siren_events == 1 and resumed_sirens == 1 and manager.countdown_seconds == countdown, "Resume does not resample countdown or retrigger siren")
	var agent: Dictionary = manager.agents[0]
	var position: Vector2 = agent["position"]
	var distance_before := Routes.remaining_distance(agent)
	manager.advance_clock(1)
	check(is_equal_approx(manager.elapsed_seconds, 1), "fixed clock advances one simulated second")
	check(absf(distance_before - Routes.remaining_distance(agent) - agent["movement_speed"]) < 0.01, "movement spends exactly speed × simulated time")
	check(agent["position"].distance_to(position) <= agent["movement_speed"] + 0.01, "movement never teleports")
	manager.pause()
	var paused: Array = manager.agents.duplicate(true)
	var paused_time: float = manager.elapsed_seconds
	manager.advance_clock(100)
	check(manager.agents == paused and manager.elapsed_seconds == paused_time, "Pause freezes positions, decisions, and clock")
	manager.start()
	manager.set_speed(10)
	manager.advance_clock(1)
	check(is_equal_approx(manager.elapsed_seconds, paused_time + 10), "10x scales movement and countdown together")
	manager.set_speed(3)
	check(manager.simulation_speed == 10, "unsupported speed rejected")
	manager.initialize_run()
	check(manager.phase == "PREPARATION" and manager.agents == initial_agents and manager.shelters == initial_shelters, "Reset restores entire initial scenario")
	# Same simulated duration with different frame partitions gives identical state/events.
	var small_frames := make_manager()
	var large_frames := make_manager()
	small_frames.start()
	large_frames.start()
	for frame in range(600): small_frames.advance_clock(1.0 / 60.0)
	large_frames.advance_clock(10)
	check(small_frames.agents == large_frames.agents and small_frames.events == large_frames.events, "60 FPS and one long frame produce the same ten-second simulation")
	# Geometry check for every initial planned path, including distant shelters.
	for profile in initial_agents:
		for belief in profile["beliefs"].values():
			var route := Routes.plan(profile["position"], belief["position"])
			var clear := true
			var orthogonal := true
			for segment in range(1, route.size()):
				orthogonal = orthogonal and (is_equal_approx(route[segment].x, route[segment - 1].x) or is_equal_approx(route[segment].y, route[segment - 1].y))
				for fraction in [0.0, 0.25, 0.5, 0.75, 1.0]:
					var point := route[segment - 1].lerp(route[segment], fraction)
					for building in Manager.CityMap.building_rects():
						clear = clear and not building.grow(11).has_point(point)
			check(orthogonal and clear, "road route is orthogonal and sampled points clear buildings")
	small_frames.queue_free()
	large_frames.queue_free()
	# Hidden runtime availability cannot influence a belief-only choice.
	var context: Dictionary = manager.agents[0].duplicate(true)
	var before := Decisions.evaluate(context, 500, manager.settings["evacuation"]["weights"])
	manager.shelter_by_id["S5"]["exists"] = not manager.shelter_by_id["S5"]["exists"]
	manager.shelter_by_id["S2"]["operational"] = false
	check(Decisions.evaluate(context, 500, manager.settings["evacuation"]["weights"]) == before, "decisions do not access hidden runtime truth")
	check(context["beliefs"]["S5"]["existence_probability"] == 0.5, "S5 belief remains uncertain")
	var cautious: Dictionary = context.duplicate(true)
	var bold: Dictionary = context.duplicate(true)
	cautious["personality"] = "Cautious"
	bold["personality"] = "Bold"
	check(Decisions.evaluate(cautious, 500, manager.settings["evacuation"]["weights"])["scores"] != Decisions.evaluate(bold, 500, manager.settings["evacuation"]["weights"])["scores"], "personality changes reasoned shelter scores")
	check(Decisions.evaluate(context, 0, manager.settings["evacuation"]["weights"])["shelter_id"].is_empty(), "unreachable destinations are ineligible")
	# Capacity, duplicate, absent, and nonoperational admission boundaries.
	manager.initialize_run()
	manager.start()
	var shelter: Dictionary = manager.shelter_by_id["S1"]
	shelter["capacity"] = 1
	force_trip(manager, manager.agents[0], "S1", shelter["position"])
	check(manager.admit_arrival(manager.agents[0]).is_empty(), "eligible arrival admitted")
	check(manager.agents[0]["state"] == "SHELTERED" and shelter["occupancy"] == 1, "admission updates agent and shelter")
	check(manager.admit_arrival(manager.agents[0]) == "Already admitted" and shelter["occupancy"] == 1, "duplicate admission cannot increment occupancy")
	force_trip(manager, manager.agents[1], "S1", shelter["position"])
	check(manager.admit_arrival(manager.agents[1]) == "Shelter is full", "full shelter rejects arrival")
	check(manager.agents[1]["state"] == "REJECTED" and manager.agents[1]["beliefs"]["S1"]["unavailable"], "rejection updates only arriving agent's knowledge")
	check(not manager.agents[2]["beliefs"]["S1"]["unavailable"], "rejection does not magically inform neighbors")
	manager.advance_clock(1.2)
	check(manager.agents[1]["objective"] != "S1" and manager.agents[1]["state"] == "MOVING", "rejected agent changes destination after local observation")
	var changed := false
	for event in manager.events:
		if event["category"] == "CHANGE" and event["message"].contains(manager.agents[1]["id"]): changed = true
	check(changed, "destination change event recorded")
	var absent: Dictionary = manager.shelter_by_id["S5"]
	absent["exists"] = false
	absent["operational"] = false
	force_trip(manager, manager.agents[2], "S5", absent["position"])
	check(manager.admit_arrival(manager.agents[2]) == "Shelter does not exist" and absent["occupancy"] == 0, "nonexistent S5 never admits")
	var unavailable: Dictionary = manager.shelter_by_id["S2"]
	unavailable["operational"] = false
	force_trip(manager, manager.agents[3], "S2", unavailable["position"])
	check(manager.admit_arrival(manager.agents[3]) == "Shelter is not operational", "nonoperational shelter rejects")
	# Keep one agent definitely outside until the deadline; no invented mortality.
	manager.agents[4]["state"] = "DECIDING"
	for belief in manager.agents[4]["beliefs"].values(): belief["unavailable"] = true
	var protected_position: Vector2 = manager.agents[0]["position"]
	manager.advance_clock(10000)
	check(manager.phase == "IMPACT" and not manager.running and manager.remaining_seconds == 0, "countdown clamps exactly to impact")
	check(manager.agents[4]["state"] == "EXPOSED", "outside agent becomes EXPOSED")
	check(manager.agents[0]["state"] == "SHELTERED" and manager.agents[0]["position"] == protected_position, "sheltered agent stays still and sheltered")
	check(manager.summary["sheltered"] + manager.summary["exposed"] == 20, "all population accounted for at impact")
	var occupants := 0
	for record in manager.shelters:
		check(record["occupancy"] <= record["capacity"], "capacity never exceeded")
		check(not record["accepting"], "impact closes admissions")
		occupants += record["occupancy"]
	check(occupants == manager.summary["sheltered"], "shelter occupancy equals sheltered population")
	var frozen_agents: Array = manager.agents.duplicate(true)
	var frozen_events: Array = manager.events.duplicate(true)
	manager.start()
	manager.choose_destination(manager.agents[4])
	manager.advance_clock(100)
	check(manager.agents == frozen_agents and manager.events == frozen_events, "no decisions, movement, or resume after impact")
	check(Admission.try_admit(manager.agents[4], shelter, false) == "Admissions closed", "late arrival denied")
	manager.queue_free()
	# Deadline boundary: no overshoot, even when the final step is shorter than a tick.
	var boundary := make_manager()
	boundary.start()
	boundary.next_decision_seconds = 1000
	boundary.elapsed_seconds = boundary.countdown_seconds - 0.05
	boundary.remaining_seconds = 0.05
	var boundary_shelter: Dictionary = boundary.shelter_by_id["S1"]
	var boundary_agent: Dictionary = boundary.agents[0]
	boundary_agent["movement_speed"] = 2
	force_trip(boundary, boundary_agent, "S1", boundary_shelter["position"] + Vector2(0.1, 0))
	boundary.advance_clock(10)
	check(boundary.phase == "IMPACT" and boundary_agent["state"] == "SHELTERED", "arrival exactly at deadline processed before impact")
	check(is_equal_approx(boundary.elapsed_seconds, boundary.countdown_seconds), "final fractional tick cannot overshoot impact")
	boundary.queue_free()
	# GUI integration: speed picker, new seed, live occupancy, summary and reset effects.
	var app: Control = MAIN_SCENE.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	app.manager.set_process(false)
	check(app.effects.player.stream.data.size() == 11025 * 3 * 2, "three-second 16-bit warning waveform generated")
	app.start_button.pressed.emit()
	check(app.effects.player.playing, "siren signal starts audio playback")
	check(app.countdown_label.text != "--:--" and app.manager.phase == "EVACUATION", "Start updates phase and countdown UI")
	app.speed_picker.item_selected.emit(3)
	check(app.manager.simulation_speed == 10 and app.top_speed_label.text == "10x", "speed selector controls centralized speed")
	app.manager.advance_clock(1000)
	check(app.summary_panel.visible and app.totals_label.text == "%d / %d" % [app.manager.summary["sheltered"], app.manager.summary["exposed"]], "impact summary and totals displayed")
	check(is_instance_valid(app.map_view.impact_effect), "impact visual created")
	app.reset_button.pressed.emit()
	await process_frame
	check(not app.summary_panel.visible and not is_instance_valid(app.map_view.impact_effect) and app.map_view.agent_nodes.size() == 20, "Reset clears impact and preserves unique agent nodes")
	check(not app.effects.player.playing, "Reset stops warning playback")
	var old_seed: int = app.manager.seed_value
	app.new_run_button.pressed.emit()
	check(app.manager.seed_value != old_seed and app.manager.phase == "PREPARATION", "New run uses a different seed")
	app.queue_free()
	await process_frame
	# AudioServer releases playback resources on its mixing thread, not this frame.
	await create_timer(0.1).timeout
	print("Phase 2: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
