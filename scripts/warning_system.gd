extends RefCounted
## Authoritative acoustic perception uses ground-plane world units, never Director audio gain.
const Coordinates = preload("res://scripts/three_d/world_coordinates.gd")
const Beliefs = preload("res://scripts/agent_beliefs.gd")
static var speech_availability: Dictionary = {}
const REFERENCE_VOLUME_DB := -16.0
const MODES := ["CIVIL_DEFENSE_WAIL","EMERGENCY_BROADCAST","FINAL_WARNING"]
static func validate(config: Variant) -> String:
	if not config is Dictionary: return "Warnings configuration must be an object."
	for key in ["sound_radius_world","tower_volume_db","tower_pitch","master_volume_db","max_audible_sirens","announcement_interval_seconds","announcement_duration_seconds","first_announcement_seconds","final_warning_seconds","start_offset_seconds","hearing_threshold","comprehension_threshold","indoor_gain","survivor_tail_seconds","siren_resistance"]:
		if not config.has(key) or not (config[key] is int or config[key] is float) or not is_finite(float(config[key])): return "Invalid warning setting: " + key
	if config["sound_radius_world"] <= 0 or config["tower_pitch"] <= 0 or config["tower_pitch"] > 2 or config["siren_resistance"] <= 0: return "Invalid siren radius, pitch or resistance."
	if config["max_audible_sirens"] < 1 or config["max_audible_sirens"] > 8 or config["max_audible_sirens"] != floorf(config["max_audible_sirens"]): return "Audible siren limit must be 1?8."
	if config["master_volume_db"] > 0 or config["master_volume_db"] < -60 or config["tower_volume_db"] > 0 or config["tower_volume_db"] < -60: return "Warning volume must be -60 to 0 dB."
	for key in ["announcement_interval_seconds","announcement_duration_seconds","final_warning_seconds"]:
		if config[key] <= 0: return "Warning timing must be positive."
	if config["announcement_duration_seconds"] >= config["announcement_interval_seconds"] or config["start_offset_seconds"] < 0 or config["first_announcement_seconds"] < 0: return "Invalid announcement/offset timing."
	for key in ["hearing_threshold","comprehension_threshold","indoor_gain"]:
		if config[key] <= 0 or config[key] > 1: return "Warning gains must be in (0,1]."
	for key in ["announcements_enabled","environmental_muffling","director_mix","announcement_comprehensible"]:
		if not config.get(key) is bool: return "Warning toggle must be boolean: " + key
	if config.get("network_mode") not in MODES or not config.get("announcement_text") is String or not config.get("audio_paths") is Dictionary: return "Invalid warning mode/text/audio paths."
	for mode in MODES+["EXPLOSION"]:
		var path: Variant = config["audio_paths"].get(mode)
		if not path is String or not path.begins_with("res://") or path.get_extension().to_lower() not in ["wav","ogg"]: return "Audio paths must be project WAV/OGG resources."
	var overrides: Variant = config.get("siren_overrides",{})
	if not overrides is Dictionary: return "siren_overrides must be an object."
	for id in overrides:
		if not id is String or not overrides[id] is Dictionary: return "Invalid per-siren override."
		for key in overrides[id]:
			var value: Variant = overrides[id][key]
			if key in ["radius_world","volume_db","pitch"]:
				if not (value is int or value is float) or not is_finite(float(value)): return "Invalid per-siren number."
				if (key == "radius_world" and value <= 0) or (key == "volume_db" and (value < -60 or value > 0)) or (key == "pitch" and (value < 0.5 or value > 2)): return "Per-siren number out of range."
			elif key == "mechanical_rotation":
				if not value is bool: return "Invalid rotation override."
			elif key == "state":
				if value not in ["ACTIVE","INACTIVE","DAMAGED","DESTROYED"]: return "Invalid initial siren state."
			else: return "Unsupported siren override key: " + str(key)
	return ""
static func initialize(manager: Node) -> void:
	manager.sirens.clear()
	var points: Array[Dictionary] = []
	for poi in manager.points_of_interest:
		if poi["kind"] in ["Police Station","Fire Station","School"]:
			points.append({"position": poi["footprint"].get_center(),"mount": "ROOFTOP","site": poi["kind"],"base_height": 3.5 if poi["kind"] == "School" else 4.5})
	for x in range(180,int(manager.CityMap.MAP_SIZE.x),900):
		for y in range(180,int(manager.CityMap.MAP_SIZE.y),900):
			points.append({"position": Vector2(x+20,y+20),"mount": "POLE","site": "Intersection / dedicated tower","base_height": 0.0})
	for i in range(points.size()):
		var data: Dictionary = points[i]
		data.merge({"id": "WS%02d" % (i+1),"state": "INACTIVE","enabled": true,"mode": "CIVIL_DEFENSE_WAIL","radius_world": manager.warning_config["sound_radius_world"],"volume_db": manager.warning_config["tower_volume_db"],"pitch": manager.warning_config["tower_pitch"],"mechanical_rotation": true,"start_offset": 0.0 if i == 0 else fmod(i*0.731+manager.seed_value*0.013,manager.warning_config["start_offset_seconds"]+0.001),"active_since": 0.0,"survived": false,"director_manual": false})
		data.merge(manager.warning_config.get("siren_overrides",{}).get(data["id"],{}),true)
		manager.sirens.append(data)
	for agent in manager.agents:
		agent["warning_observations"] = []
		agent["warning_keys"] = {}
static func activate(manager: Node, enabled: bool, manual: bool = false) -> void:
	if manager.phase == "IMPACT" and enabled: return
	for siren in manager.sirens:
		if not enabled: siren["tail_allowed"] = false
		if siren["state"] in ["DAMAGED","DESTROYED"]: continue
		siren["enabled"] = enabled
		siren["state"] = "ACTIVE" if enabled else "INACTIVE"
		siren["active_since"] = manager.elapsed_seconds
		siren["director_manual"] = manual and manager.phase == "PREPARATION"
		if siren["director_manual"]:
			siren["manual_wall_start"] = Time.get_ticks_msec()/1000.0
		else: siren.erase("manual_wall_start")
static func mode_at(manager: Node, siren: Dictionary) -> String:
	var config: Dictionary = manager.warning_config
	var age: float = manager.elapsed_seconds-siren["active_since"]-siren["start_offset"]
	if manager.phase == "EVACUATION" and manager.remaining_seconds <= config["final_warning_seconds"]: return "FINAL_WARNING"
	if config["announcements_enabled"] and announcement_available(config) and age >= config["first_announcement_seconds"] and fmod(age-config["first_announcement_seconds"],config["announcement_interval_seconds"]) < config["announcement_duration_seconds"]:
		return "EMERGENCY_BROADCAST"
	return "CIVIL_DEFENSE_WAIL" if config["network_mode"] == "EMERGENCY_BROADCAST" and not config["announcements_enabled"] else config["network_mode"]
static func gain(point: Vector2, siren: Dictionary, indoor: bool, config: Dictionary) -> float:
	var distance := point.distance_to(siren["position"])*Coordinates.SCALE
	var result := pow(maxf(0,1-distance/float(siren["radius_world"])),2)*db_to_linear(siren["volume_db"]-REFERENCE_VOLUME_DB)
	return result*config["indoor_gain"] if indoor else result
static func perceive(manager: Node) -> void:
	if manager.phase != "EVACUATION": return
	for agent in manager.agents:
		if agent.get("health",100) <= 0: continue
		var indoor: bool = agent.get("indoors",false) or agent["state"] == "SHELTERED"
		var best := 0.0
		var source: Dictionary = {}
		for siren in manager.sirens:
			if siren["state"] != "ACTIVE" or manager.elapsed_seconds < siren["active_since"]+siren["start_offset"]: continue
			var loudness := gain(agent["position"],siren,indoor,manager.warning_config)
			if loudness > best:
				best = loudness
				source = siren
		if source.is_empty() or best < manager.warning_config["hearing_threshold"]: continue
		var mode := mode_at(manager,source)
		source["mode"] = mode
		var key := "SIREN_HEARD:" + ("URGENT" if mode == "FINAL_WARNING" else "INITIAL")
		if mode != "EMERGENCY_BROADCAST" and not agent["warning_keys"].has(key):
			_observe(manager,agent,key,"SIREN_HEARD",source["id"],"Urgent outdoor warning; seek shelter now." if mode == "FINAL_WARNING" else "Outdoor civil-defense siren heard. Seek shelter.")
			agent["panic_level"] = minf(100,agent["panic_level"]+(3 if mode == "FINAL_WARNING" else 8)*(0.5+agent["self_preservation"]/100.0)*(1-agent["authority_trust"]/200.0))
			_alert(manager,agent)
		if mode == "EMERGENCY_BROADCAST" and announcement_available(manager.warning_config) and best >= manager.warning_config["comprehension_threshold"]:
			var age: float = manager.elapsed_seconds-source["active_since"]
			var batch := int(age/manager.warning_config["announcement_interval_seconds"])
			key = "MESSAGE:%d" % batch
			if not agent["warning_keys"].has(key):
				var text: String = manager.warning_config["announcement_text"]
				_observe(manager,agent,key,"WARNING_MESSAGE_RECEIVED",source["id"],text)
				agent["alarm_confidence"] = clampf(agent["alarm_confidence"]+0.1*agent["authority_trust"]/100.0-0.03*agent["skepticism"]/100.0,0.1,1)
				_alert(manager,agent)
				agent["messages"].append({"rumor_id":"WARN:%s:%d" % [agent["id"],batch],"claim":text,"original_source":"Civil-defense loudspeaker","current_speaker":agent["id"],"timestamp":manager.elapsed_seconds,"hops":0,"kind":"warning","perceived_credibility":0.8})
				while agent["messages"].size() > manager.living["rumor_history_limit"]: agent["messages"].pop_front()
static func _alert(manager: Node, agent: Dictionary) -> void:
	if agent["state"] != "IDLE": return
	agent["wait_until"] = manager.elapsed_seconds+agent["reaction_delay"]
	agent["current_goal"] = "Process perceived warning; prepare to evacuate"
	manager._set_state(agent,"DELAYED")
static func _observe(manager: Node, agent: Dictionary, key: String, kind: String, source: String, text: String) -> void:
	agent["warning_keys"][key] = true
	agent["warning_observations"].append({"type":kind,"time":manager.elapsed_seconds,"source":source,"text":text})
	while agent["warning_observations"].size() > 16: agent["warning_observations"].pop_front()
	Beliefs.remember(agent,manager.elapsed_seconds,kind+": "+text,manager.living)
	manager.log_event(kind,agent["id"]+": "+text,"private:"+agent["id"])
static func impact(manager: Node) -> void:
	for siren in manager.sirens:
		var load: float = manager.Blast.intensity(siren["position"],manager.nuclear)
		siren["state"] = "DESTROYED" if load >= manager.warning_config["siren_resistance"] else "DAMAGED" if load > 0 else "INACTIVE"
		siren["survived"] = load == 0
		siren["tail_allowed"] = load == 0 and siren["enabled"]
		siren["director_manual"] = false

static func audio_age(manager: Node, siren: Dictionary, mode: String) -> float:
	var age: float = manager.elapsed_seconds-siren["active_since"]-siren["start_offset"]
	if mode == "FINAL_WARNING" and manager.phase == "EVACUATION" and manager.remaining_seconds <= manager.warning_config["final_warning_seconds"]:
		return manager.warning_config["final_warning_seconds"]-manager.remaining_seconds
	if mode == "EMERGENCY_BROADCAST" and manager.warning_config["network_mode"] != "EMERGENCY_BROADCAST":
		return fposmod(age-manager.warning_config["first_announcement_seconds"],manager.warning_config["announcement_interval_seconds"])
	return age

static func announcement_available(config: Dictionary) -> bool:
	if not config["announcement_comprehensible"]: return false
	var path: String = config["audio_paths"].get("EMERGENCY_BROADCAST","")
	# Recordings are immutable during a run. Cache decoding/availability, not agent knowledge.
	if not speech_availability.has(path):
		var stream: AudioStream = preload("res://scripts/warning_audio.gd").load_bank(config).get("EMERGENCY_BROADCAST")
		speech_availability[path] = stream != null and stream.get_length() > 0
	return speech_availability[path]
