extends Node
## Owns run state and the fixed simulation clock. Rendering only observes signals.

signal run_initialized
signal clock_changed(elapsed: float, active: bool)
signal event_logged(entry: Dictionary)
signal setup_failed(message: String)
signal simulation_updated
signal siren_activated
signal impact_occurred(summary: Dictionary)
signal all_clear

const ScenarioConfig = preload("res://scripts/scenario_config.gd")
const CityMap = preload("res://scripts/city_map.gd")
const Decisions = preload("res://scripts/evacuation_decisions.gd")
const Routes = preload("res://scripts/road_routes.gd")
const Admission = preload("res://scripts/shelter_admission.gd")
const ShelterState = preload("res://scripts/shelter_state.gd")
const Personality = preload("res://scripts/agent_personality.gd")
const Beliefs = preload("res://scripts/agent_beliefs.gd")
const Incidents = preload("res://scripts/environment_events.gd")
const Rumors = preload("res://scripts/rumor_system.gd")
const Reactions = preload("res://scripts/agent_reactions.gd")
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
var living: Dictionary = {}
var environment_events: Array[Dictionary] = []
var alarm_started_seconds := 0.0
var alarm_is_real := true
var next_contact_seconds := 0.0


func load_settings(path: String = CONFIG_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("Cannot open %s. Check that the configuration file exists." % path)
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return _fail("Invalid JSON in %s, line %d: %s" % [path, parser.get_error_line(), parser.get_error_message()])
	settings = parser.data
	var living_file := FileAccess.open("res://resources/living_world.json", FileAccess.READ)
	if living_file == null:
		return _fail("Missing resources/living_world.json")
	var living_parser := JSON.new()
	if living_parser.parse(living_file.get_as_text()) != OK or not living_parser.data is Dictionary:
		return _fail("Invalid resources/living_world.json")
	living = living_parser.data
	var living_error := validate_living(living)
	if not living_error.is_empty():
		return _fail(living_error)
	var error := validate_settings(settings)
	if not error.is_empty():
		return _fail(error)
	if living["event_spacing_seconds"]*4 > settings["evacuation"]["countdown_range"][0]*(living["event_window_fraction"][1]-living["event_window_fraction"][0]):
		return _fail("Event spacing must fit five events inside the shortest warning window.")
	seed_value = int(settings["seed"])
	simulation_speed = float(settings["simulation_speed"])
	return true


func _fail(message: String) -> bool:
	push_error(message)
	setup_failed.emit(message)
	return false


static func validate_settings(data: Dictionary) -> String:
	return ScenarioConfig.validate_settings(data)


static func validate_living(data: Dictionary) -> String:
	var required := ["event_probabilities", "event_duration_range", "event_window_fraction", "event_spacing_seconds", "event_radius", "road_radius", "observation_radius", "communication_radius", "communication_interval", "rumor_ttl_seconds", "rumor_max_hops", "rumor_history_limit", "memory_limit", "relay_radius", "false_alarm_probability", "public_warning_estimate_range", "capacity_estimates", "capacity_estimate_variation", "size_descriptions", "abundant_supply_days", "unknown_supply_range", "rat_supply_loss_fraction", "secondary_personality_probability", "trait_jitter", "denial_delay_range", "freeze_threshold", "freeze_seconds", "freeze_cooldown_seconds", "panic_decay_per_second", "help_radius", "help_seconds", "help_panic_reduction"]
	for key in required:
		if not data.has(key):
			return "Missing living world setting: " + str(key)
	for key in ["false_alarm_probability", "secondary_personality_probability", "rat_supply_loss_fraction", "capacity_estimate_variation"]:
		if not (data[key] is float or data[key] is int) or not is_finite(float(data[key])) or data[key] < 0 or data[key] > 1:
			return key + " must be a probability between 0 and 1."
	if not data["event_probabilities"] is Dictionary:
		return "event_probabilities must be a dictionary."
	for key in ["maintenance", "door", "road", "crowd", "rats"]:
		var value: Variant = data["event_probabilities"].get(key, -1)
		if not (value is float or value is int) or value < 0 or value > 1:
			return "Invalid event probability: " + key
	for key in ["communication_interval", "communication_radius", "observation_radius", "event_radius", "road_radius", "relay_radius", "rumor_ttl_seconds", "rumor_max_hops", "rumor_history_limit", "memory_limit", "help_radius", "help_seconds", "freeze_seconds", "freeze_cooldown_seconds", "event_spacing_seconds", "abundant_supply_days"]:
		if not (data[key] is float or data[key] is int) or not is_finite(float(data[key])) or data[key] <= 0:
			return key + " must be positive."
	for key in ["rumor_max_hops", "rumor_history_limit", "memory_limit"]:
		if float(data[key]) != floorf(float(data[key])):
			return key + " must be an integer."
	for key in ["event_duration_range", "event_window_fraction", "unknown_supply_range", "public_warning_estimate_range", "denial_delay_range"]:
		var pair: Variant = data[key]
		if not pair is Array or pair.size() != 2:
			return key + " must contain two bounds."
		for value in pair:
			if not (value is float or value is int) or not is_finite(float(value)) or value < 0:
				return "Invalid range: " + key
		if pair[1] < pair[0] or pair[1] <= 0:
			return "Invalid range order: " + key
	if data["event_window_fraction"][1] >= 0.9:
		return "Events must start before 90% of the warning window."
	for key in ["capacity_estimates", "size_descriptions"]:
		if not data[key] is Dictionary:
			return key + " must be a dictionary."
	for id in ["S1", "S2", "S3", "S4", "S5"]:
		var description: String = data["size_descriptions"].get(id, "")
		if not data["capacity_estimates"].has(description) or not (data["capacity_estimates"][description] is int or data["capacity_estimates"][description] is float) or data["capacity_estimates"][description] <= 0:
			return "Invalid capacity description for " + id
	for key in ["trait_jitter", "freeze_threshold", "help_panic_reduction", "panic_decay_per_second"]:
		if not (data[key] is float or data[key] is int) or not is_finite(float(data[key])) or data[key] < 0 or data[key] > 100:
			return "Invalid trait/reaction value: " + key
	return ""


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
	next_contact_seconds = 0.0
	alarm_started_seconds = 0.0
	var alarm_rng := RandomNumberGenerator.new()
	alarm_rng.seed = seed_value + 7081
	alarm_is_real = alarm_rng.randf() >= living["false_alarm_probability"]
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
	var profile_rng := RandomNumberGenerator.new()
	profile_rng.seed = seed_value + 6067
	var order: Array = Personality.TYPES.duplicate()
	for i in range(order.size()-1, 0, -1):
		var j := profile_rng.randi_range(0, i)
		var value: String = order[i]
		order[i] = order[j]
		order[j] = value
	var supply_rng := RandomNumberGenerator.new()
	supply_rng.seed = seed_value + 8081
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
		ShelterState.initialize(shelter, supply_rng, living)
		shelters.append(shelter)
		shelter_by_id[shelter["id"]] = shelter
		log_event("SHELTER", "%s initialized • %s • capacity %d" % [shelter["id"], "present" if shelter["exists"] else "absent", shelter["capacity"]], "director")
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
			"beliefs": Beliefs.initialize(settings["shelters"], belief_rng, living),
			"objective": "", "shelter_id": "", "route": PackedVector2Array(), "route_index": 0,
			"decision_history": [], "decision_scores": {}, "decision_explanation": "Awaiting siren.",
			"state_history": [{"time": 0.0, "state": "IDLE"}], "next_reconsider_seconds": 0.0,
			"admission_priority": belief_rng.randi(),
		}
		Personality.assign(agent, index, order, profile_rng, living)
		agent["current_beliefs"] = agent["beliefs"]
		agent["companion_id"] = "A%03d" % (((index + 1) % int(settings["agent_count"])) + 1)
		agents.append(agent)
		log_event("AGENT", "%s spawned • %s • position (%d, %d)" % [agent["id"], agent["role"], agent["position"].x, agent["position"].y])
	Rumors.initialize(agents)
	environment_events = Incidents.schedule(seed_value, shelters, countdown_seconds, living)
	log_event("DIRECTOR", "Hidden warning duration %ds; alarm %s; %d incidents scheduled." % [countdown_seconds, "real" if alarm_is_real else "false", environment_events.size()], "director")
	log_event("SYSTEM", "Ready. Start simulation activates the city; Launch nuke sounds the siren.")
	run_initialized.emit()
	clock_changed.emit(elapsed_seconds, running)
	simulation_updated.emit()


func start() -> void:
	if running or agents.is_empty() or phase in ["IMPACT", "ALL_CLEAR"]:
		return
	running = true
	if phase == "PREPARATION":
		phase = "LIVING"
		log_event("SYSTEM", "City simulation started. No emergency alarm.")
	else:
		log_event("CLOCK", "Evacuation resumed.")
	clock_changed.emit(elapsed_seconds, running)
	simulation_updated.emit()


func launch_nuke(force_false: bool = false) -> void:
	if phase not in ["PREPARATION", "LIVING"] or agents.is_empty():
		return
	if force_false:
		alarm_is_real = false
	phase = "EVACUATION"
	running = true
	alarm_started_seconds = elapsed_seconds
	remaining_seconds = countdown_seconds
	log_event("SIREN", "Emergency siren activated. Seek shelter; exact impact time is unknown.")
	log_event("DIRECTOR", "Alarm %s; hidden delay %ds." % ["real" if alarm_is_real else "false", countdown_seconds], "director")
	siren_activated.emit()
	for agent in agents:
		agent["panic_level"] = minf(100, agent["panic_level"] + 8*(1-agent["authority_trust"]/100.0))
		agent["wait_until"] = elapsed_seconds + agent["reaction_delay"]
		agent["current_goal"] = "Process warning; prepare to evacuate"
		_set_state(agent, "DELAYED")
	next_decision_seconds = elapsed_seconds
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
	if not running or phase not in ["LIVING", "EVACUATION"] or delta <= 0 or not is_finite(delta):
		return
	accumulator += delta * simulation_speed
	if phase == "EVACUATION":
		accumulator = minf(accumulator, remaining_seconds)
	var step: float = settings["evacuation"]["fixed_step_seconds"]
	while running:
		var duration := minf(step, remaining_seconds) if phase == "EVACUATION" else step
		if accumulator + 0.0000001 < duration:
			break
		accumulator = maxf(0, accumulator - duration)
		_step(duration)
	clock_changed.emit(elapsed_seconds, running)
	simulation_updated.emit()


func _step(duration: float) -> void:
	if phase == "EVACUATION":
		Incidents.update(self)
	if elapsed_seconds + 0.000001 >= next_contact_seconds:
		Reactions.perceive(self)
		Reactions.social_observations(self)
		Rumors.exchange(self)
		next_contact_seconds += living["communication_interval"]
	if phase == "LIVING":
		elapsed_seconds += duration
		return
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
		if agent["state"] == "WAITING_ROAD" and not Incidents.road_blocks(agent, environment_events, living["road_radius"]):
			_set_state(agent, "MOVING")
			agent["current_goal"] = "Reach " + agent["objective"]
			log_event("ENVIRONMENT", "%s resumed after road obstruction cleared." % agent["id"])
		if not Reactions.act(self, agent, duration):
			continue
		if Incidents.road_blocks(agent, environment_events, living["road_radius"]):
			_set_state(agent, "WAITING_ROAD")
			agent["current_goal"] = "Wait for blocked road to clear"
			log_event("ENVIRONMENT", "%s detected a road blockage and must wait." % agent["id"])
			continue
		var movement := Routes.move(agent, duration)
		if movement["arrived"]:
			arrivals.append({"agent": agent, "offset": movement["travel_seconds"]})
	elapsed_seconds = minf(alarm_started_seconds + countdown_seconds, elapsed_seconds + duration)
	remaining_seconds = maxf(0, alarm_started_seconds + countdown_seconds - elapsed_seconds)
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
		if alarm_is_real:
			_trigger_impact()
		else:
			_trigger_all_clear()


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
	# Public rough urgency is private to this agent. Never pass the hidden deadline.
	var perceived := maxf(30, agent["perceived_warning_seconds"] - (elapsed_seconds-alarm_started_seconds))
	var result := Decisions.evaluate(agent, perceived, settings["evacuation"]["weights"])
	agent["decision_scores"] = result["scores"]
	var destination: String = result["shelter_id"]
	if previous == destination and not destination.is_empty():
		if agent["state"] == "DECIDING":
			_set_state(agent, "MOVING")
			agent["current_goal"] = "Reach " + destination
		return
	if not previous.is_empty() and result["scores"][previous]["eligible"] and not destination.is_empty():
		var margin: float = settings["evacuation"]["switch_margin"] * (0.25 if agent["primary_personality"] == "OPPORTUNISTIC" else 1.0)
		if result["score"] <= result["scores"][previous]["score"] + margin:
			if agent["state"] == "DECIDING":
				_set_state(agent, "MOVING")
				agent["current_goal"] = "Reach " + previous
			return
	_set_state(agent, "DECIDING" if previous.is_empty() else "CHANGING_DESTINATION")
	agent["objective"] = destination
	agent["decision_explanation"] = result["explanation"]
	agent["current_goal"] = "Wait for useful information" if destination.is_empty() else "Reach " + destination
	if not destination.is_empty() and agent["recommendations"].has(destination):
		if agent["primary_personality"] == "FAMILY-ORIENTED":
			agent["current_goal"] = "Stay with companion toward " + destination
		elif agent["primary_personality"] == "FOLLOWER":
			agent["current_goal"] = "Follow trusted recommendation toward " + destination
	if not destination.is_empty() and agent["primary_personality"] == "FOLLOWER" and agent.get("observed_crowds", {}).get(destination, 0) > 0:
		agent["current_goal"] = "Follow nearby crowd toward " + destination
	Beliefs.remember(agent, elapsed_seconds, result["explanation"], living)
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
	if agent["primary_personality"] == "LEADER":
		agent["messages"].append({"rumor_id": "LEAD:%s:%.1f" % [agent["id"], elapsed_seconds], "claim": "Recommend " + destination, "shelter_id": destination,
			"kind": "recommendation", "original_source": agent["id"], "current_speaker": agent["id"], "timestamp": elapsed_seconds, "hops": 0, "perceived_credibility": 0.8})
		while agent["messages"].size() > int(living["rumor_history_limit"]):
			agent["messages"].pop_front()
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
	Beliefs.observe(agent, shelter, elapsed_seconds, living)
	var reason := Admission.try_admit(agent, shelter, phase == "EVACUATION")
	if reason.is_empty():
		_set_state(agent, "SHELTERED")
		shelter["current_occupancy"] = shelter["occupancy"]
		agent["current_goal"] = "Wait inside " + shelter["id"]
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
	Beliefs.remember(agent, elapsed_seconds, "Entrance " + shelter["id"] + ": " + ("admitted" if reason.is_empty() else reason), living)
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
	if not alarm_is_real:
		return
	phase = "IMPACT"
	running = false
	remaining_seconds = 0
	elapsed_seconds = alarm_started_seconds + countdown_seconds
	accumulator = 0
	for shelter in shelters:
		shelter["accepting"] = false
		ShelterState.refresh(shelter, environment_events)
	for agent in agents:
		if agent["state"] != "SHELTERED":
			_set_state(agent, "EXPOSED")
			agent["current_goal"] = "Exposed at impact; evacuation stopped"
		agent["survival_status"] = "PROTECTED_AT_IMPACT" if agent["state"] == "SHELTERED" else "EXPOSED_AT_IMPACT"
	summary = get_totals()
	log_event("IMPACT", "Nuclear impact occurred. %d sheltered / %d exposed. Final survival belongs to Phase 3." % [summary["sheltered"], summary["exposed"]])
	impact_occurred.emit(summary.duplicate())


func _trigger_all_clear() -> void:
	phase = "ALL_CLEAR"
	running = false
	remaining_seconds = 0
	accumulator = 0
	for agent in agents:
		if agent["state"] != "SHELTERED":
			_set_state(agent, "SAFE")
		agent["current_goal"] = "All-clear; no nuclear impact"
		agent["survival_status"] = "SAFE_FROM_STRIKE"
	summary = get_totals()
	log_event("ALL CLEAR", "False alarm confirmed. No impact occurred; all agents are safe from the strike.")
	all_clear.emit()


func log_event(category: String, message: String, visibility: String = "public") -> void:
	var entry := {"time": elapsed_seconds, "category": category, "message": message, "visibility": visibility}
	events.append(entry)
	event_logged.emit(entry)
