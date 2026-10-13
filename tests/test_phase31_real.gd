extends SceneTree
const Manager = preload("res://scripts/simulation_manager.gd")
func _initialize() -> void:
    run.call_deferred()
func run() -> void:
    var manager := Manager.new()
    root.add_child(manager)
    manager.load_settings()
    manager.initialize_run()
    await create_timer(1.0).timeout
    if manager.ai_bridge.status != "CONNECTED":
        printerr("Real test: service disconnected")
        quit(1)
        return
    manager.launch_nuke()
    var agent: Dictionary = manager.agents.filter(func(a): return a["configured_provider"] == "LOCAL_LLM")[0]
    agent["wait_until"] = 0
    manager.choose_destination(agent)
    var deadline := Time.get_ticks_msec() + 35000
    while Time.get_ticks_msec() < deadline and not agent.has("latest_llm_action"):
        await process_frame
    var success: bool = agent.has("latest_llm_action")
    print("REAL OLLAMA: ", agent["id"], " / ", agent.get("latest_llm_action", "FAILED"), " / target ", agent["objective"], " / state ", agent["state"], " / ", agent.get("latest_llm_explanation", agent.get("fallback_reason", "")))
    manager.queue_free()
    await process_frame
    quit(0 if success else 1)
