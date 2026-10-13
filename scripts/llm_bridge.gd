extends Node
## HTTPRequest uses worker threads; inference never blocks the render/fixed loop.
const Observation = preload("res://scripts/agent_observation.gd")
const Actions = preload("res://scripts/llm_actions.gd")
var manager: Node
var status := "DISCONNECTED"
var pending := {}
var decision_queue: Array[Dictionary] = []
var queued := {}
var health_request: HTTPRequest
var next_health_msec := 0
var run_id := ""
var metrics := {}
var records: Array = []
var logs_dirty := false
var next_log_msec := 0
var total_latency := 0.0

func record_result(entry: Dictionary) -> void:
	records.append(entry)
	metrics["calls"] = int(metrics.get("calls", 0)) + (1 if entry.get("inference_requested", true) else 0)
	metrics["successful"] = int(metrics.get("successful", 0)) + (1 if entry.get("success", false) else 0)
	metrics["fallbacks"] = records.size() - int(metrics["successful"])
	total_latency += float(entry.get("latency_seconds", 0.0))
	metrics["average_latency_seconds"] = total_latency / max(1, int(metrics["calls"]))
	metrics["input_tokens"] = int(metrics.get("input_tokens", 0)) + int(entry.get("input_tokens", 0))
	metrics["output_tokens"] = int(metrics.get("output_tokens", 0)) + int(entry.get("output_tokens", 0))
	metrics["invalid_responses"] = int(metrics.get("invalid_responses", 0)) + int(entry.get("invalid_responses", 0))
	logs_dirty = true

func save_logs() -> void:
	if not logs_dirty:
		return
	DirAccess.make_dir_recursive_absolute("res://outputs/ai_runs")
	var file := FileAccess.open("res://outputs/ai_runs/" + run_id + ".json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"run_id": run_id, "metrics": metrics, "decisions": records}, "  "))
		logs_dirty = false


func configure(owner_manager: Node) -> void:
	manager = owner_manager
	health_request = HTTPRequest.new()
	health_request.use_threads = true
	health_request.timeout = 3
	add_child(health_request)
	health_request.request_completed.connect(_health_completed)

func reset_run() -> void:
	save_logs()
	total_latency = 0.0
	metrics.clear()
	records.clear()
	run_id = "%s-%s" % [Time.get_ticks_usec(), randi()]
	for request in pending.values():
		request.cancel_request()
		request.queue_free()
	pending.clear()
	decision_queue.clear()
	queued.clear()

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() >= next_log_msec:
		next_log_msec = Time.get_ticks_msec() + 1000
		save_logs()
	if manager == null or not manager.ai_config.get("enabled", false):
		return
	if manager.phase in ["IMPACT", "ALL_CLEAR"]:
		for agent in decision_queue:
			agent["ai_queue_status"] = "INACTIVE"
		decision_queue.clear()
		queued.clear()
	if status not in ["CONNECTED", "DEGRADED"] and not decision_queue.is_empty():
		for agent in decision_queue:
			agent["ai_queue_status"] = "FALLBACK"
			agent["fallback_reason"] = "AI service " + status
			agent["decision_provider"] = "FALLBACK_RULE_BASED"
			record_result({"agent_id": agent["id"], "success": false, "inference_requested": false, "fallback_reason": agent["fallback_reason"]})
			if manager.running and manager.phase == "EVACUATION" and agent["state"] not in ["SHELTERED", "EXPOSED", "SAFE", "FROZEN", "HELPING"]:
				manager.choose_rule_destination(agent)
		decision_queue.clear()
		queued.clear()
	_dispatch_next()
	if Time.get_ticks_msec() >= next_health_msec:
		next_health_msec = Time.get_ticks_msec() + int(manager.ai_config["health_interval_seconds"]*1000)
		health_request.request(manager.ai_config["service_url"] + "/health")

func _health_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var parser := JSON.new()
	var data: Variant = null
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and parser.parse(body.get_string_from_utf8()) == OK:
		data = parser.data
	status = "DISCONNECTED"
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and data is Dictionary:
		var value: String = data.get("status", "DEGRADED")
		status = value if value in ["CONNECTED", "DISCONNECTED", "MODEL_UNAVAILABLE", "DEGRADED"] else "DEGRADED"

func request_decision(agent: Dictionary) -> bool:
	if status not in ["CONNECTED", "DEGRADED"]:
		return false
	if pending.has(agent["id"]) or queued.has(agent["id"]):
		return true
	if manager.elapsed_seconds < agent.get("next_llm_seconds", 0):
		return agent["decision_provider"] == "LOCAL_LLM"
	decision_queue.append(agent)
	queued[agent["id"]] = true
	agent["ai_queue_status"] = "QUEUED"
	_dispatch_next()
	return true

func _exit_tree() -> void:
	save_logs()

func _dispatch_next() -> void:
	if manager == null or not manager.running or manager.phase != "EVACUATION" or not pending.is_empty() or status not in ["CONNECTED", "DEGRADED"]:
		return
	while not decision_queue.is_empty():
		var agent: Dictionary = decision_queue.pop_front()
		queued.erase(agent["id"])
		if agent["state"] in ["SHELTERED", "EXPOSED", "SAFE"] or agent.get("health", 0) <= 0:
			agent["ai_queue_status"] = "INACTIVE"
			continue
		if agent["state"] in ["FROZEN", "HELPING"] and manager.elapsed_seconds < agent["wait_until"]:
			agent["ai_queue_status"] = "RECOVERING"
			continue
		if not _send_decision(agent):
			agent["ai_queue_status"] = "FALLBACK"
			agent["fallback_reason"] = "Could not start HTTP request"
			agent["decision_provider"] = "FALLBACK_RULE_BASED"
			manager.choose_rule_destination(agent)
		return

func _send_decision(agent: Dictionary) -> bool:
	agent["ai_queue_status"] = "INFERRING"
	agent["next_llm_seconds"] = manager.elapsed_seconds + manager.ai_config["decision_interval_seconds"]
	agent["llm_request_sequence"] += 1
	var sequence: int = agent["llm_request_sequence"]
	var started_msec := Time.get_ticks_msec()
	var sent_time: float = manager.elapsed_seconds
	var sent_run := run_id
	var request := HTTPRequest.new()
	request.use_threads = true
	request.timeout = manager.ai_config["request_timeout_seconds"]
	add_child(request)
	pending[agent["id"]] = request
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
		request.queue_free()
		if sent_run != run_id:
			return
		pending.erase(agent["id"])
		agent["ai_queue_status"] = "IDLE"
		var parser := JSON.new()
		var data: Variant = null
		if result == HTTPRequest.RESULT_SUCCESS and code == 200 and parser.parse(body.get_string_from_utf8()) == OK:
			data = parser.data
		if manager.phase != "EVACUATION" or agent["state"] in ["SHELTERED", "EXPOSED", "SAFE"]:
			return
		var valid := result == HTTPRequest.RESULT_SUCCESS and code == 200 and data is Dictionary
		if valid:
			valid = data.get("run_id") == sent_run and data.get("request_id") == str(sequence) and data.get("agent_id") == agent["id"] and data.get("decision") is Dictionary and manager.elapsed_seconds-sent_time <= manager.ai_config["max_response_age_seconds"]
		if valid and manager.running:
			valid = Actions.apply(manager, agent, data["decision"])
			if valid:
				agent["llm_metrics"] = {"latency_seconds": data.get("latency_seconds", 0), "deviation_flags": data.get("deviation_flags", []), "input_tokens": data.get("input_tokens", 0), "output_tokens": data.get("output_tokens", 0)}
		else:
			valid = false
		if not valid:
			agent["ai_queue_status"] = "FALLBACK"
			status = "DISCONNECTED" if result != HTTPRequest.RESULT_SUCCESS else "DEGRADED"
			agent["fallback_reason"] = "HTTP %s / result %s, invalid, paused or stale" % [code, result]
			agent["decision_provider"] = "FALLBACK_RULE_BASED"
			manager.log_event("AI", "%s fallback: unavailable, invalid, paused or stale response." % agent["id"])
			if manager.running and not (agent["state"] in ["FROZEN", "HELPING"] and manager.elapsed_seconds < agent["wait_until"]):
				manager.choose_rule_destination(agent)
		var entry := {"request_id": str(sequence), "agent_id": agent["id"], "success": valid,
			"simulation_time": manager.elapsed_seconds, "fallback_reason": agent.get("fallback_reason", ""),
			"latency_seconds": (Time.get_ticks_msec()-started_msec)/1000.0}
		if data is Dictionary:
			entry.merge(data, true)
		record_result(entry)
		manager.simulation_updated.emit())
	var packet := {"schema_version": 1, "run_id": sent_run, "request_id": str(sequence),
		"observation": Observation.generate(manager, agent)}
	var error := request.request(manager.ai_config["service_url"] + "/decide", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(packet))
	if error != OK:
		pending.erase(agent["id"])
		request.queue_free()
		return false
	return true
