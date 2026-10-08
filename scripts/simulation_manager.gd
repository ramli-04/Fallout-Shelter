extends Node
## Owns run state and the fixed simulation clock. Rendering only observes signals.

signal run_initialized
signal clock_changed(elapsed: float, active: bool)
signal event_logged(entry: Dictionary)
signal setup_failed(message: String)
signal simulation_updated
signal siren_activated
signal impact_occurred(summary: Dictionary)

const ScenarioConfig = preload("res://scripts/scenario_config.gd")
const CityMap = preload("res://scripts/city_map.gd")
const Decisions = preload("res://scripts/evacuation_decisions.gd")
const Routes = preload("res://scripts/road_routes.gd")
const Admission = preload("res://scripts/shelter_admission.gd")
const CONFIG_PATH := "res://resources/phase1.json"

var settings: Dictionary = {}
var agents: Array[Dictionary] = []
var shelters: Array[Dictionary] = []
var events: Array[Dictionary] = []
var seed_value := 42
var elapsed_seconds := 0.0
var running := false
var simulation_speed := 1.0
var phase := "PREPARATION"
var countdown_seconds := 0
var remaining_seconds := 0.0
var summary: Dictionary = {}
var shelter_by_id: Dictionary = {}
var accumulator := 0.0
var next_decision_seconds := 0.0


func load_settings(path: String = CONFIG_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("Cannot open %s. Check that the configuration file exists." % path)
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return _fail("Invalid JSON in %s, line %d: %s" % [path, parser.get_error_line(), parser.get_error_message()])
	settings = parser.data
	var error := validate_settings(settings)
	if not error.is_empty():
		return _fail(error)
	seed_value = int(settings["seed"])
	simulation_speed = float(settings["simulation_speed"])
	return true


func _fail(message: String) -> bool:
	push_error(message)
	setup_failed.emit(message)
	return false


static func validate_settings(data: Dictionary) -> String:
	return ScenarioConfig.validate_settings(data)


func initialize_run() -> void:
	if settings.is_empty():
		return
	running = false
	elapsed_seconds = 0.0
	simulation_speed = float(settings["simulation_speed"])
	phase = "PREPARATION"
	summary.clear()
	shelter_by_id.clear()
	accumulator = 0.0
	next_decision_seconds = 0.0
	var countdown_rng := RandomNumberGenerator.new()
	countdown_rng.seed = seed_value + 2027
	countdown_seconds = countdown_rng.randi_range(int(settings["evacuation"]["countdown_range"][0]), int(settings["evacuation"]["countdown_range"][1]))
	remaining_seconds = countdown_seconds
	agents.clear()
	shelters.clear()
	events.clear()
	# Dedicated streams keep S5 independent of population/profile changes.
	var shelter_rng := RandomNumberGenerator.new()
	shelter_rng.seed = seed_value
	var agent_rng := RandomNumberGenerator.new()
	agent_rng.seed = seed_value + 1009
	var belief_rng := RandomNumberGenerator.new()
	belief_rng.seed = seed_value + 3037
	log_event("SYSTEM", "Run initialized • seed %d • Preparation" % seed_value)
	for definition in settings["shelters"]:
		var shelter: Dictionary = definition.duplicate(true)
		shelter["capacity"] = int(shelter["capacity"])
		var coordinates: Array = shelter["position"]
		shelter["position"] = Vector2(coordinates[0], coordinates[1])
		var probability: float = shelter["existence_probability"]
		# S5 is sampled here exactly once per initialization. Reset repeats the seed.
		shelter["exists"] = shelter_rng.randf() < probability if probability > 0 and probability < 1 else probability == 1
		shelter["occupancy"] = 0
		shelter["occupant_ids"] = []
		shelter["accepting"] = true
		shelter["operational"] = bool(definition["operational"]) and shelter["exists"]
		shelters.append(shelter)
		shelter_by_id[shelter["id"]] = shelter
		log_event("SHELTER", "%s initialized • %s • capacity %d" % [shelter["id"], "present" if shelter["exists"] else "absent", shelter["capacity"]])
	var slots: Array[Vector2] = CityMap.spawn_slots()
	# Reserve each shelter plaza, including S5's possible site.
	for index in range(slots.size() - 1, -1, -1):
		for shelter in shelters:
			if slots[index].distance_to(shelter["position"]) < 65:
				slots.remove_at(index)
				break
	if slots.size() < int(settings["agent_count"]):
		_fail("Not enough clear spawn slots. Move shelters or reduce agent_count.")
		return
	# Fisher–Yates shuffle uses our seeded RNG, rather than the global random stream.
	for index in range(slots.size() - 1, 0, -1):
		var other := agent_rng.randi_range(0, index)
		var temporary := slots[index]
		slots[index] = slots[other]
		slots[other] = temporary
	for index in range(int(settings["agent_count"])):
		var agent := {
			"id": "A%03d" % (index + 1),
			"role": "Authority" if index < int(settings["authority_count"]) else "Civilian",
			"movement_speed": agent_rng.randf_range(settings["speed_range"][0], settings["speed_range"][1]),
			"risk_tolerance": agent_rng.randf_range(settings["trait_range"][0], settings["trait_range"][1]),
			"trust_in_authority": agent_rng.randf_range(settings["trait_range"][0], settings["trait_range"][1]),
			"sociability": agent_rng.randf_range(settings["trait_range"][0], settings["trait_range"][1]),
			"position": slots[index], "state": "IDLE",
			"personality": settings["evacuation"]["personalities"][belief_rng.randi_range(0, settings["evacuation"]["personalities"].size() - 1)],
			"beliefs": Decisions.initialize_beliefs(settings["shelters"], belief_rng, settings["evacuation"]["belief_uncertainty"]),
			"objective": "", "shelter_id": "", "route": PackedVector2Array(), "route_index": 0,
			"decision_history": [], "decision_scores": {}, "decision_explanation": "Awaiting siren.",
			"state_history": [{"time": 0.0, "state": "IDLE"}], "next_reconsider_seconds": 0.0,
			"admission_priority": belief_rng.randi(),
		}
		agents.append(agent)
		log_event("AGENT", "%s spawned • %s • position (%d, %d)" % [agent["id"], agent["role"], agent["position"].x, agent["position"].y])
	log_event("SYSTEM", "Ready. Start sounds the siren and begins evacuation.")
	run_initialized.emit()
	clock_changed.emit(elapsed_seconds, running)
	simulation_updated.emit()


func start() -> void:
	if running or agents.is_empty() or phase == "IMPACT":
		return
	running = true
	if phase == "PREPARATION":
		phase = "EVACUATION"
		log_event("SIREN", "Nuclear attack siren activated • %ds until impact." % countdown_seconds)
		siren_activated.emit()
		for agent in agents:
			choose_destination(agent)
		next_decision_seconds = float(settings["evacuation"]["decision_interval_seconds"])
	else:
		log_event("CLOCK", "Evacuation resumed.")
	clock_changed.emit(elapsed_seconds, running)
	simulation_updated.emit()


func pause() -> void:
	if not running:
		return
	running = false
	log_event("CLOCK", "Evacuation paused.")
	clock_changed.emit(elapsed_seconds, running)


func _process(delta: float) -> void:
	advance_clock(delta)


func advance_clock(delta: float) -> void:
	if not running or phase != "EVACUATION" or delta <= 0 or not is_finite(delta):
		return
	accumulator = minf(accumulator + delta * simulation_speed, remaining_seconds)
	var step: float = settings["evacuation"]["fixed_step_seconds"]
	while running:
		var duration := minf(step, remaining_seconds)
		if accumulator + 0.0000001 < duration:
			break
		accumulator = maxf(0, accumulator - duration)
		_step(duration)
	clock_changed.emit(elapsed_seconds, running)
	simulation_updated.emit()


func _step(duration: float) -> void:
	if elapsed_seconds + 0.000001 >= next_decision_seconds:
		for agent in agents:
			if agent["state"] in ["MOVING", "DECIDING"]:
				choose_destination(agent)
		next_decision_seconds += settings["evacuation"]["decision_interval_seconds"]
	for agent in agents:
		if agent["state"] == "REJECTED" and elapsed_seconds + 0.000001 >= agent["next_reconsider_seconds"]:
			choose_destination(agent)
	var arrivals: Array[Dictionary] = []
	for agent in agents:
		agent["previous_position"] = agent["position"]
		if agent["state"] != "MOVING":
			continue
		var movement := Routes.move(agent, duration)
		if movement["arrived"]:
			arrivals.append({"agent": agent, "offset": movement["travel_seconds"]})
	elapsed_seconds = minf(countdown_seconds, elapsed_seconds + duration)
	remaining_seconds = maxf(0, countdown_seconds - elapsed_seconds)
	# Earlier arrivals in a tick win; seeded priorities break exact ties, not list order.
	arrivals.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["offset"] != b["offset"]:
			return a["offset"] < b["offset"]
		if a["agent"]["admission_priority"] == b["agent"]["admission_priority"]:
			return a["agent"]["id"] < b["agent"]["id"]
		return a["agent"]["admission_priority"] < b["agent"]["admission_priority"])
	for arrival in arrivals:
		admit_arrival(arrival["agent"])
	if remaining_seconds <= 0.000001:
		_trigger_impact()


func set_speed(value: float) -> void:
	if value not in [1.0, 2.0, 5.0, 10.0]:
		return
	simulation_speed = value
	log_event("CLOCK", "Simulation speed set to %dx." % int(value))
	clock_changed.emit(elapsed_seconds, running)


func new_run(new_seed: int) -> void:
	seed_value = new_seed
	initialize_run()


func _set_state(agent: Dictionary, state: String) -> void:
	if agent["state"] == state:
		return
	agent["state"] = state
	agent["state_history"].append({"time": elapsed_seconds, "state": state})


func choose_destination(agent: Dictionary) -> void:
	if phase != "EVACUATION" or agent["state"] in ["SHELTERED", "EXPOSED"]:
		return
	var previous: String = agent["objective"]
	var result := Decisions.evaluate(agent, remaining_seconds, settings["evacuation"]["weights"])
	agent["decision_scores"] = result["scores"]
	var destination: String = result["shelter_id"]
	if previous == destination and not destination.is_empty():
		return
	if not previous.is_empty() and result["scores"][previous]["eligible"] and not destination.is_empty():
		if result["score"] <= result["scores"][previous]["score"] + settings["evacuation"]["switch_margin"]:
			return
	_set_state(agent, "DECIDING" if previous.is_empty() else "CHANGING_DESTINATION")
	agent["objective"] = destination
	agent["decision_explanation"] = result["explanation"]
	agent["decision_history"].append({"time": elapsed_seconds, "shelter_id": destination,
		"explanation": result["explanation"], "scores": result["scores"].duplicate(true)})
	if destination.is_empty():
		agent["route"] = PackedVector2Array()
		agent["route_index"] = 0
		log_event("DECISION", "%s: no known reachable destination." % agent["id"])
		return
	agent["route"] = result["route"]
	agent["route_index"] = 1
	_set_state(agent, "MOVING")
	log_event("CHANGE" if not previous.is_empty() else "DECISION", "%s %s %s • %s" % [agent["id"], "changed destination to" if not previous.is_empty() else "chose", destination, result["explanation"]])


func admit_arrival(agent: Dictionary) -> String:
	if agent["state"] == "SHELTERED":
		return "Already admitted"
	if phase != "EVACUATION" or agent["objective"].is_empty():
		return "Evacuation is not accepting arrivals"
	var shelter: Dictionary = shelter_by_id[agent["objective"]]
	if agent["position"].distance_to(shelter["position"]) > 0.01:
		return "Agent has not reached entrance"
	log_event("ARRIVAL", "%s arrived at %s." % [agent["id"], shelter["id"]])
	var reason := Admission.try_admit(agent, shelter, phase == "EVACUATION")
	if reason.is_empty():
		_set_state(agent, "SHELTERED")
		log_event("ADMITTED", "%s entered %s • %d/%d." % [agent["id"], shelter["id"], shelter["occupancy"], shelter["capacity"]])
	else:
		_set_state(agent, "REJECTED")
		var belief: Dictionary = agent["beliefs"][shelter["id"]]
		belief["unavailable"] = true
		belief["source"] = "Observed at entrance: " + reason
		if not shelter["exists"]:
			belief["existence_probability"] = 0.0
		if reason == "Shelter is full":
			belief["estimated_occupancy"] = shelter["capacity"]
		agent["next_reconsider_seconds"] = elapsed_seconds + settings["evacuation"]["rejection_pause_seconds"]
		log_event("REJECTED", "%s rejected by %s: %s." % [agent["id"], shelter["id"], reason])
	return reason


func get_totals() -> Dictionary:
	var totals := {"sheltered": 0, "exposed": 0, "evacuating": 0, "population": agents.size()}
	for agent in agents:
		if agent["state"] == "SHELTERED":
			totals["sheltered"] += 1
		elif agent["state"] == "EXPOSED":
			totals["exposed"] += 1
		else:
			totals["evacuating"] += 1
	return totals


func _trigger_impact() -> void:
	phase = "IMPACT"
	running = false
	remaining_seconds = 0
	elapsed_seconds = countdown_seconds
	accumulator = 0
	for shelter in shelters:
		shelter["accepting"] = false
	for agent in agents:
		if agent["state"] != "SHELTERED":
			_set_state(agent, "EXPOSED")
	summary = get_totals()
	log_event("IMPACT", "Nuclear impact occurred. %d sheltered / %d exposed. Final survival belongs to Phase 3." % [summary["sheltered"], summary["exposed"]])
	impact_occurred.emit(summary.duplicate())


func log_event(category: String, message: String) -> void:
	var entry := {"time": elapsed_seconds, "category": category, "message": message}
	events.append(entry)
	event_logged.emit(entry)


