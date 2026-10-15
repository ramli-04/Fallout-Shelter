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
var backend_health := {}
var model_metrics := {}
var run_started_msec := 0

func urgency(agent: Dictionary) -> float:
	return minf(100, (40.0 if agent["objective"].is_empty() else 0.0) + (30.0 if agent["state"] == "REJECTED" else 0.0) + float(agent.get("panic_level", 0))*0.2 + (20.0 if manager.remaining_seconds < 90 else 0.0))

func fallback(agent: Dictionary, reason: String) -> void:
	agent["ai_queue_status"] = "FALLBACK"
	agent["fallback_reason"] = reason
	agent["decision_provider"] = "FALLBACK_RULE_BASED"
	agent["next_llm_seconds"] = manager.elapsed_seconds + manager.ai_config["decision_interval_seconds"]
	record_result({"agent_id": agent["id"], "model": agent.get("model_tier", "llama3.2:1b"), "success": false, "inference_requested": false, "fallback_reason": reason})
	if manager.running and manager.phase == "EVACUATION" and agent["state"] not in ["SHELTERED", "EXPOSED", "SAFE", "FROZEN", "HELPING"]:
		manager.choose_rule_destination(agent)

func dashboard_text() -> String:
	var counts := {}
	for agent in manager.agents:
		var model: String = agent.get("model_tier", "llama3.2:1b") if agent["configured_provider"] == "LOCAL_LLM" else "rules"
		counts[model] = int(counts.get(model, 0)) + 1
	var lines: Array[String] = ["AI %s | local queue %d active %d | backend queue %s active %s" % [status, decision_queue.size(), pending.size(), backend_health.get("pending", "?"), backend_health.get("active", "?")]]
	for model in counts:
		var stats: Dictionary = model_metrics.get(model, {})
		var server: Dictionary = backend_health.get("per_model", {}).get(model, {})
		lines.append("%s: %d agents | %d applied / %d fallback | %s requests / %s invalid | %.2f s | %.1f tok/s | %.2f decisions/s" % [model, counts[model], stats.get("successful", 0), stats.get("fallbacks", 0), server.get("requests", 0), server.get("invalid_responses", 0), server.get("average_latency_seconds", 0), server.get("tokens_per_second", 0), server.get("decisions_per_second", 0)])
	lines.append("Pool %s | resident %s | peak VRAM %.2f GB | unloads %s %s" % [backend_health.get("mode", "?"), str(backend_health.get("residency", {}).keys()), float(backend_health.get("peak_vram_bytes", 0))/1e9, backend_health.get("observed_unloads", 0), "SWAP WARNING" if backend_health.get("swap_warning", false) else ""])
	return "\n".join(lines)

func record_result(entry: Dictionary) -> void:
	records.append(entry)
	var model: String = entry.get("model", "llama3.2:1b")
	if not model_metrics.has(model): model_metrics[model] = {"requests": 0, "successful": 0, "fallbacks": 0, "invalid_responses": 0}
	var stats: Dictionary = model_metrics[model]
	stats["requests"] += 1 if entry.get("inference_requested", true) else 0
	stats["successful"] += 1 if entry.get("success", false) else 0
	stats["fallbacks"] += 0 if entry.get("success", false) else 1
	stats["invalid_responses"] += int(entry.get("invalid_responses", 0))
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
		file.store_string(JSON.stringify({"run_id": run_id, "seed": manager.seed_value, "preset": manager.ai_config.get("experiment_preset", "legacy"), "metrics": metrics, "per_model": model_metrics, "backend": backend_health, "decisions": records}, "  "))
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
	model_metrics.clear()
	run_started_msec = Time.get_ticks_msec()
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
			record_result({"agent_id": agent["id"], "model": agent.get("model_tier", "llama3.2:1b"), "success": false, "inference_requested": false, "fallback_reason": agent["fallback_reason"]})
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
		backend_health = data
		var value: String = data.get("status", "DEGRADED")
		status = value if value in ["CONNECTED", "DISCONNECTED", "MODEL_UNAVAILABLE", "DEGRADED"] else "DEGRADED"

func request_decision(agent: Dictionary) -> bool:
	if status not in ["CONNECTED", "DEGRADED"]:
		return false
	if pending.has(agent["id"]) or queued.has(agent["id"]):
		return true
	if manager.elapsed_seconds < agent.get("next_llm_seconds", 0):
		return agent["decision_provider"] == "LOCAL_LLM"
	if decision_queue.size() >= int(manager.ai_config.get("queue_limit", 128)):
		fallback(agent, "Godot queue full")
		return true
	decision_queue.append(agent)
	agent["llm_queued_msec"] = Time.get_ticks_msec()
	queued[agent["id"]] = true
	agent["ai_queue_status"] = "QUEUED"
	_dispatch_next()
	return true

func _exit_tree() -> void:
	save_logs()

func _dispatch_next() -> void:
	if manager == null or not manager.running or manager.phase != "EVACUATION" or status not in ["CONNECTED", "DEGRADED"]:
		return
	decision_queue.sort_custom(func(a, b): return float(a.get("llm_queued_msec", 0))/1000.0 - urgency(a)*0.1 < float(b.get("llm_queued_msec", 0))/1000.0 - urgency(b)*0.1)
	while not decision_queue.is_empty() and pending.size() < int(manager.ai_config.get("max_concurrent_requests", 1)):
		var active_models := {}
		for request in pending.values():
			var model: String = request.get_meta("model", "llama3.2:1b")
			active_models[model] = int(active_models.get(model, 0)) + 1
		var eligible := -1
		for i in range(decision_queue.size()):
			var model: String = decision_queue[i].get("model_tier", "llama3.2:1b")
			if int(active_models.get(model, 0)) < int(manager.ai_config.get("per_model_concurrency", 1)):
				eligible = i
				break
		if eligible < 0: return
		var agent: Dictionary = decision_queue[eligible]
		decision_queue.remove_at(eligible)
		queued.erase(agent["id"])
		if agent["state"] in ["SHELTERED", "EXPOSED", "SAFE"] or agent.get("health", 0) <= 0:
			agent["ai_queue_status"] = "INACTIVE"
			continue
		if agent["state"] in ["FROZEN", "HELPING"] and manager.elapsed_seconds < agent["wait_until"]:
			agent["ai_queue_status"] = "RECOVERING"
			continue
		if (Time.get_ticks_msec()-int(agent.get("llm_queued_msec", 0)))/1000.0 > float(manager.ai_config.get("queue_timeout_seconds", 120)):
			fallback(agent, "Godot queue deadline expired")
			continue
		if not _send_decision(agent):
			fallback(agent, "Could not start HTTP request")

func _send_decision(agent: Dictionary) -> bool:
	agent["ai_queue_status"] = "INFERRING"
	agent["next_llm_seconds"] = manager.elapsed_seconds + manager.ai_config["decision_interval_seconds"]
	agent["llm_request_sequence"] += 1
	var sequence: int = agent["llm_request_sequence"]
	var started_msec := Time.get_ticks_msec()
	var sent_time: float = manager.elapsed_seconds
	var sent_run := run_id
	var request := HTTPRequest.new()
	request.set_meta("model", agent.get("model_tier", "llama3.2:1b"))
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
		var entry := {"request_id": str(sequence), "agent_id": agent["id"], "success": valid, "model": agent.get("model_tier", "llama3.2:1b"),
			"simulation_time": manager.elapsed_seconds, "fallback_reason": agent.get("fallback_reason", ""),
			"latency_seconds": (Time.get_ticks_msec()-started_msec)/1000.0}
		if data is Dictionary:
			entry.merge(data, true)
		entry["success"] = valid
		entry["simulation_time"] = manager.elapsed_seconds
		entry["fallback_reason"] = agent.get("fallback_reason", "")
		record_result(entry)
		manager.simulation_updated.emit())
	var packet := {"schema_version": 1, "run_id": sent_run, "request_id": str(sequence),
		"model": agent.get("model_tier", "llama3.2:1b"), "urgency": urgency(agent),
		"observation": Observation.generate(manager, agent)}
	var error := request.request(manager.ai_config["service_url"] + "/decide", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(packet))
	if error != OK:
		pending.erase(agent["id"])
		request.queue_free()
		return false
	return true
