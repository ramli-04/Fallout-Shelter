extends SceneTree
const MAIN = preload("res://scenes/main.tscn")
const Observation = preload("res://scripts/agent_observation.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: "+text)
func run() -> void:
	var app = MAIN.instantiate()
	root.add_child(app)
	var sim: Node = app.manager
	var network: Node3D = app.map_view.siren_network
	sim.set_process(false)
	sim.ai_config["enabled"] = false
	sim.initialize_run()
	for i in range(4): await physics_frame
	check(sim.Warning.validate(sim.warning_config).is_empty(),"warning configuration validates")
	var invalid: Dictionary = sim.warning_config.duplicate(true)
	invalid["max_audible_sirens"] = 50
	check(not sim.Warning.validate(invalid).is_empty(),"invalid channel cap rejected")
	check(sim.sirens.size() == 43 and network.nodes.size() == sim.sirens.size(),"43 reusable physical sirens across expanded city")
	for site in ["Police Station","Fire Station","School"]:
		check(sim.sirens.any(func(s): return s["site"] == site and s["mount"] == "ROOFTOP"),"rooftop siren at "+site)
	check(sim.sirens.any(func(s): return s["mount"] == "POLE"),"dedicated intersection towers")
	check(app.map_view.world_viewport.audio_listener_enable_3d and network.listener.is_current(),"active isolated 3D listener")
	for node in network.nodes:
		check(node.player is AudioStreamPlayer3D and node.player.attenuation_model == AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE,"true spatial audio per tower")
	for mode in ["CIVIL_DEFENSE_WAIL","EMERGENCY_BROADCAST","FINAL_WARNING","EXPLOSION"]:
		check(network.bank[mode] is AudioStream and network.bank[mode].get_length() > 1,"local shared audio for "+mode)
	var countdown: int = sim.countdown_seconds
	var agents_before: Array = sim.agents.duplicate(true)
	network.test_siren(sim.sirens[0]["id"])
	check(sim.phase == "PREPARATION" and sim.countdown_seconds == countdown and sim.agents == agents_before,"individual test never starts countdown or observations")
	check(network.nodes[0].player.playing,"individual test starts selected source")
	sim.initialize_run()
	check(network.test_id.is_empty() and network.nodes.all(func(n): return not n.player.playing),"reset cancels test and all loops")
	var source: Dictionary = sim.sirens[0]
	var near: Dictionary = sim.agents[0]
	var distant: Dictionary = sim.agents[1]
	near["position"] = source["position"]
	distant["position"] = Vector2(10000,10000)
	var indoor: Dictionary = sim.agents[2]
	indoor["position"] = source["position"]+Vector2(700,0)
	indoor["indoors"] = true
	sim.launch_nuke()
	check(sim.sirens.all(func(s): return s["state"] == "ACTIVE"),"alert activates network")
	check(sim.countdown_seconds == countdown and countdown >= 300 and countdown <= 600,"existing seeded 5?10 minute delay preserved")
	check(near["warning_observations"].any(func(e): return e["type"] == "SIREN_HEARD"),"covered agent hears initial wail")
	check(distant["warning_observations"].is_empty() and distant["state"] == "IDLE","outside coverage does not receive global warning")
	check(near["state"] == "DELAYED" and near["panic_level"] > agents_before[0]["panic_level"],"personality-dependent response initiates evacuation")
	var gain_near: float = sim.Warning.gain(source["position"],source,false,sim.warning_config)
	var gain_far: float = sim.Warning.gain(source["position"]+Vector2(900,0),source,false,sim.warning_config)
	check(gain_near > gain_far and gain_far > 0,"faint distance attenuation within radius")
	check(sim.Warning.gain(source["position"],source,true,sim.warning_config) < gain_near,"indoors reduces audible gain")
	var quiet: Dictionary = source.duplicate(true)
	quiet["volume_db"] = -60
	check(sim.Warning.gain(source["position"],quiet,false,sim.warning_config) < sim.warning_config["hearing_threshold"],"source volume reduces actual agent audibility")
	app.map_view.camera_rig.focus_at(network.nodes[0].position)
	network.sync_mix()
	check(network.nodes[0].player.playing,"real alert starts nearby tower playback")
	check(network.audible_ids.size() <= 4,"bounded simultaneous spatial sources")
	sim.pause()
	var elapsed: float = sim.elapsed_seconds
	network.sync_mix()
	check(network.nodes.all(func(n): return not n.player.playing),"pause silences all actual spatial warning streams")
	sim.advance_clock(100)
	check(sim.elapsed_seconds == elapsed,"pause leaves warning clock unchanged")
	sim.start()
	sim.set_speed(5)
	network.sync_mix()
	check(network.nodes.filter(func(n): return n.player.playing).all(func(n): return is_equal_approx(n.player.pitch_scale,n.record["pitch"]*5)),"speed scales spatial playback")
	check(network.nodes.filter(func(n): return n.player.playing).all(func(n): return not n.player.stream_paused),"resume unpauses warnings")
	# Direct model perception at scheduled announcement time isolates speech from social reports.
	sim.elapsed_seconds = 14
	sim.remaining_seconds = countdown-14
	sim.Warning.perceive(sim)
	check(is_equal_approx(sim.Warning.audio_age(sim,source,"EMERGENCY_BROADCAST"),2),"announcement phase starts at scheduled beginning")
	check(near["warning_observations"].any(func(e): return e["type"] == "WARNING_MESSAGE_RECEIVED"),"comprehensible local announcement is a separate observation")
	check(not indoor["warning_observations"].any(func(e): return e["type"] == "WARNING_MESSAGE_RECEIVED"),"muffled indoor announcement not understood")
	check(distant["warning_observations"].is_empty(),"announcement does not leak outside acoustic coverage")
	var payload := JSON.stringify(Observation.generate(sim,near))
	check(payload.contains("WARNING_MESSAGE_RECEIVED") and not payload.contains("impact_position") and not payload.contains("countdown_seconds") and not payload.contains("remaining_seconds"),"LLM receives heard facts but no exact deadline/location")
	var observations: int = near["warning_observations"].size()
	sim.Warning.perceive(sim)
	check(near["warning_observations"].size() == observations,"perception deduplicates announcement and siren")
	sim.warning_config["announcements_enabled"] = false
	sim.elapsed_seconds = 90
	sim.Warning.perceive(sim)
	check(near["warning_observations"].size() == observations,"disabled announcements do not create message observations")
	sim.remaining_seconds = 59
	check(sim.Warning.mode_at(sim,source) == "FINAL_WARNING","last simulated minute escalates urgency")
	sim.Warning.perceive(sim)
	check(near["warning_observations"].any(func(e): return e["text"].contains("Urgent")),"urgent observation omits countdown")
	sim.Warning.activate(sim,false)
	network.sync_mix()
	check(network.nodes.all(func(n): return not n.player.playing),"Director deactivation stops all sources")
	sim.Warning.activate(sim,true)
	check(sim.phase == "EVACUATION" and sim.countdown_seconds == countdown,"reactivation never resamples countdown")
	# Isolate near damage/distant survival without changing the preserved impact model.
	sim.nuclear["impact_position"] = [source["position"].x,source["position"].y]
	sim.nuclear["radius"] = 20
	sim.remaining_seconds = 0
	sim.alarm_is_real = true
	sim._trigger_impact()
	check(source["state"] == "DESTROYED" and not source["survived"],"blast destroys affected siren")
	check(sim.sirens.any(func(s): return s["state"] == "INACTIVE" and s["survived"]),"distant towers retain intact surviving state")
	check(not network.nodes[0].player.playing and network.explosion.playing,"destroyed tower interrupts and explosion audio starts")
	check(network.nodes.filter(func(n): return n.player.playing).all(func(n): return n.record["survived"]),"only surviving towers may play a brief tail")
	network.impact_age = 5
	network.sync_mix()
	check(network.nodes.all(func(n): return not n.player.playing),"survivor tail ends after bounded presentation time")
	sim.Warning.activate(sim,true)
	check(source["state"] == "DESTROYED","destroyed tower cannot reactivate")
	sim.initialize_run()
	for i in range(3):
		network.test_siren(sim.sirens[0]["id"])
		sim.initialize_run()
	check(network.nodes.size() == sim.sirens.size() and network.nodes.all(func(n): return not n.player.playing),"repeated test/reset does not accumulate loops")
	check(sim.sirens.all(func(s): return s["state"] == "INACTIVE") and not network.explosion.playing and network.nodes.size() == sim.sirens.size(),"reset restores towers without duplicate players")
	sim.launch_nuke(true)
	sim.advance_clock(1000)
	check(sim.phase == "ALL_CLEAR" and sim.sirens.all(func(s): return s["state"] == "INACTIVE"),"false alarm clears sirens without blast")
	sim.warning_config["siren_overrides"] = {"WS01":{"radius_world":75.0,"pitch":0.8,"volume_db":-20.0,"mechanical_rotation":false}}
	sim.initialize_run()
	check(sim.sirens[0]["radius_world"] == 75 and network.nodes[0].player.max_distance == 75 and sim.sirens[0]["pitch"] == 0.8,"per-tower overrides configure physical audio and model")
	app.queue_free()
	await process_frame
	print("Warnings: %d checks / %d failures" % [checks,failures])
	quit(1 if failures else 0)
