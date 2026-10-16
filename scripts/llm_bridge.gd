extends Node
## HTTPRequest polls asynchronously; inference never blocks the render/fixed loop.
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
var applied_decisions := {}
var event_inflight := 0
var log_worker: Thread

func urgency(agent: Dictionary) -> float:
	return minf(100, (40.0 if agent["objective"].is_empty() else 0.0) + (30.0 if agent["state"] == "REJECTED" else 0.0) + float(agent.get("panic_level", 0))*0.2 + (20.0 if manager.remaining_seconds < 90 else 0.0))

func fallback(agent: Dictionary, reason: String) -> void:
	agent["ai_queue_status"] = "FALLBACK"
	agent["fallback_reason"] = reason
	agent["decision_provider"] = "FALLBACK_RULE_BASED"
	agent["next_llm_seconds"] = manager.elapsed_seconds + manager.ai_config["decision_interval_seconds"]
	record_result({"agent_id": agent["id"], "model": agent.get("model_tier", "llama3.2:1b"), "success": false, "inference_requested": false, "fallback_reason": reason})
	if manager.running and manager.phase in ["EVACUATION", "BOMB_FALL"] and agent["state"] not in ["SHELTERED", "EXPOSED", "SAFE", "FROZEN", "HELPING"]:
		manager.choose_rule_destination(agent)

func dashboard_text(group_filter: String = "ALL", agent_filter: String = "ALL") -> String:
	var counts := {}
	for agent in manager.agents:
		var model: String = agent.get("model_tier", "llama3.2:1b") if agent["configured_provider"] == "LOCAL_LLM" else "rules"
		if group_filter != "ALL" and model != group_filter: continue
		if agent_filter != "ALL" and agent["id"] != agent_filter: continue
		counts[model] = int(counts.get(model, 0)) + 1
	var lines: Array[String] = ["AI Infrastructure %s | queue %d HTTP active %d | backend queue %s active %s" % [status, decision_queue.size(), pending.size(), backend_health.get("pending", "?"), backend_health.get("active", "?")]]
	for model in counts:
		var stats: Dictionary = model_metrics.get(model, {})
		var server: Dictionary = backend_health.get("groups", {}).get(model, {})
		lines.append("%s: %d agents | %d applied / %d fallback | %s requests / %s invalid | %.2f s | %.1f tok/s | %.2f decisions/s" % [model, counts[model], stats.get("successful", 0), stats.get("fallbacks", 0), server.get("requests", 0), server.get("invalid_responses", 0), server.get("average_latency_seconds", 0), server.get("tokens_per_second", 0), server.get("decisions_per_second", 0)])
	lines.append("Model VRAM peak %.2f GB / budget %.1f GB | GPU MiB %s" % [float(backend_health.get("peak_vram_bytes", 0))/1e9, float(backend_health.get("memory_budget_bytes", 0))/1e9, str(backend_health.get("gpu_memory_mib", "unavailable"))])
	lines.append("Kafka %s | errors/rate limits and provider models:" % backend_health.get("kafka", "?"))
	for group in backend_health.get("groups", {}):
		if group_filter != "ALL" and group != group_filter: continue
		var infra: Dictionary = backend_health["groups"][group]
		lines.append("%s %s/%s | %s | active %s peak %s | errors %s rate limits %s" % [group, infra.get("provider"), infra.get("model"), infra.get("status"), infra.get("active"), infra.get("peak_active"), infra.get("errors"), infra.get("rate_limits")])
	for agent in manager.agents:
		if group_filter != "ALL" and agent.get("model_tier", "") != group_filter: continue
		if agent_filter != "ALL" and agent["id"] != agent_filter: continue
		lines.append("%s / %s / %s" % [agent["id"], agent["state"], agent.get("ai_queue_status", "IDLE")])
	return "\n".join(lines)

func record_result(entry: Dictionary) -> void:
	records.append(entry)
	var model: String = entry.get("group", entry.get("model", "A"))
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

static func write_log_file(path: String, snapshot: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute("res://outputs/ai_runs")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(snapshot))

func save_logs() -> void:
	if not logs_dirty: return
	if log_worker != null:
		if log_worker.is_alive(): return
		log_worker.wait_to_finish()
	log_worker = Thread.new()
	var snapshot := {"run_id": run_id, "seed": manager.seed_value, "preset": manager.ai_config.get("experiment_preset", "legacy"), "metrics": metrics, "per_model": model_metrics, "backend": backend_health, "decisions": records}
	if log_worker.start(write_log_file.bind("res://outputs/ai_runs/" + run_id + ".json", snapshot.duplicate(true))) == OK:
		logs_dirty = false

func configure(owner_manager: Node) -> void:
	manager = owner_manager
	health_request = HTTPRequest.new()
	health_request.use_threads = true
	health_request.timeout = 3
	add_child(health_request)
	health_request.request_completed.connect(_health_completed)

func reset_run() -> void:
	invalidate_run()
	if log_worker != null:
		log_worker.wait_to_finish()
		log_worker = null
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
	applied_decisions.clear()

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
			if manager.running and manager.phase in ["EVACUATION", "BOMB_FALL"] and agent["state"] not in ["SHELTERED", "EXPOSED", "SAFE", "FROZEN", "HELPING"]:
				manager.choose_rule_destination(agent)
		decision_queue.clear()
		queued.clear()
	_dispatch_next()
	if Time.get_ticks_msec() >= next_health_msec:
		next_health_msec = Time.get_ticks_msec() + int(manager.ai_config["health_interval_seconds"]*1000)
		if health_request.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
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
	if pending.size() >= int(manager.ai_config.get("max_concurrent_requests", 30)):
		fallback(agent, "HTTP capacity exhausted")
		return true
	if not _send_decision(agent):
		fallback(agent, "Could not start HTTP request")
	return true

func _exit_tree() -> void:
	if log_worker != null:
		log_worker.wait_to_finish()
		log_worker = null
	save_logs()
	if log_worker != null: log_worker.wait_to_finish()

func _dispatch_next() -> void:
	pass # No central inference backlog; each eligible agent dispatches directly.

func _send_decision(agent: Dictionary) -> bool:
	# Keep moving under the current plan while inference is pending.
	if agent["objective"].is_empty() and agent["state"] == "DECIDING":
		manager.choose_rule_destination(agent)
	agent["ai_queue_status"] = "INFERRING"
	agent["next_llm_seconds"] = manager.elapsed_seconds + manager.ai_config["decision_interval_seconds"]
	agent["llm_request_sequence"] += 1
	var sequence: int = agent["llm_request_sequence"]
	var started_msec := Time.get_ticks_msec()
	var sent_time: float = manager.elapsed_seconds
	var sent_run := run_id
	var request := HTTPRequest.new()
	request.set_meta("model", agent.get("model_tier", "llama3.2:1b"))
	request.use_threads = false
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
		if manager.phase not in ["EVACUATION", "BOMB_FALL"] or agent["state"] in ["SHELTERED", "EXPOSED", "SAFE"]:
			return
		var valid := result == HTTPRequest.RESULT_SUCCESS and code == 200 and data is Dictionary
		if valid:
			valid = data.get("run_id") == sent_run and data.get("request_id") == str(sequence) and data.get("agent_id") == agent["id"] and data.get("decision") is Dictionary and manager.elapsed_seconds-sent_time <= manager.ai_config["max_response_age_seconds"]
			valid = valid and not applied_decisions.has(agent["id"] + ":" + str(sequence))
		if valid and manager.running:
			valid = Actions.apply(manager, agent, data["decision"])
			if valid:
				applied_decisions[agent["id"] + ":" + str(sequence)] = true
				agent["actual_llm_model"] = data.get("model", "")
				agent["actual_llm_provider"] = data.get("provider", "")
				if not agent["decision_history"].is_empty():
					agent["decision_history"][-1]["model"] = data.get("model", "")
					agent["decision_history"][-1]["provider"] = data.get("provider", "")
				agent["llm_metrics"] = {"latency_seconds": data.get("latency_seconds", 0), "deviation_flags": data.get("deviation_flags", []), "input_tokens": data.get("input_tokens", 0), "output_tokens": data.get("output_tokens", 0)}
		else:
			valid = false
		if not valid:
			agent["ai_queue_status"] = "FALLBACK"
			status = "DISCONNECTED" if result != HTTPRequest.RESULT_SUCCESS else "DEGRADED"
			agent["fallback_reason"] = "HTTP %s / result %s, invalid, paused or stale" % [code, result]
			agent["decision_provider"] = "FALLBACK_RULE_BASED"
			manager.log_event("AI", "%s fallback: unavailable, invalid, paused or stale response." % agent["id"])
			if manager.running and not (agent["state"] in ["FROZEN", "HELPING", "DANCING", "STAGGERED"] and manager.elapsed_seconds < agent["wait_until"]):
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
		"group": agent.get("model_tier", "A"), "urgency": urgency(agent),
		"observation": Observation.generate(manager, agent)}
	var error := request.request(manager.ai_config["service_url"] + "/decide", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(packet))
	if error != OK:
		pending.erase(agent["id"])
		request.queue_free()
		return false
	return true

func publish_event(topic: String, payload: Dictionary, agent_id: String = "") -> void:
	if not manager.ai_config.get("enabled", false): return
	if not manager.running or status not in ["CONNECTED", "DEGRADED"]: return
	if event_inflight >= 64: return
	event_inflight += 1
	var event_request := HTTPRequest.new()
	event_request.use_threads = false
	event_request.timeout = 4
	add_child(event_request)
	event_request.request_completed.connect(func(_result, _code, _headers, _body):
		event_inflight -= 1
		event_request.queue_free())
	var body := {"topic": topic, "payload": payload, "run_id": run_id, "agent_id": agent_id, "correlation_id": str(Time.get_ticks_usec())}
	if event_request.request(manager.ai_config["service_url"] + "/events", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
		event_inflight -= 1
		event_request.queue_free()

func invalidate_run() -> void:
	if run_id.is_empty() or manager == null: return
	if pending.is_empty(): return
	var request := HTTPRequest.new()
	request.use_threads = true
	request.timeout = 3
	add_child(request)
	request.request_completed.connect(func(_result, _code, _headers, _body): request.queue_free())
	if request.request(manager.ai_config["service_url"] + "/runs/" + run_id + "/invalidate", ["Content-Type: application/json"], HTTPClient.METHOD_POST, "{}") != OK:
		request.queue_free()
