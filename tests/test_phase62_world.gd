extends SceneTree
## Full-scene physics integration and a small reproducible CPU timing sample.
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var app: Node=preload("res://scenes/main.tscn").instantiate(); root.add_child(app)
	app.set_process(false); app.manager.set_process(false); app.manager.ai_bridge.set_process(false)
	app.manager.ai_config.enabled=false; app.manager.social.close()
	app.manager.social.next_send=INF # This test exercises physics without network ingestion.
	for agent in app.manager.agents: agent.configured_provider="RULE_BASED"
	await physics_frame; await physics_frame
	app.manager.start(); app.manager.launch_nuke()
	var samples: Array[float]=[]
	for _step in range(120):
		var before:=Time.get_ticks_usec()
		app.manager.advance_clock(.05)
		samples.append(float(Time.get_ticks_usec()-before)/1000)
		await physics_frame
	samples.sort()
	print("Phase 6.2 full scene: %d vehicles, step CPU p50 %.2f ms / p95 %.2f ms (headless, 0.05 s steps)"%[app.manager.social.vehicles.size(),samples[60],samples[114]])
	app.manager.social.close(); app.queue_free()
	await process_frame; await process_frame; quit()
