extends RefCounted
## Shared local assets. Generated files are explicitly temporary, never licensed-recording claims.
static var streams: Dictionary = {}
static func load_bank(config: Dictionary) -> Dictionary:
	var result := {}
	for mode in ["CIVIL_DEFENSE_WAIL","EMERGENCY_BROADCAST","FINAL_WARNING","EXPLOSION"]:
		var path: String = config["audio_paths"].get(mode,"")
		if not ResourceLoader.exists(path):
			var wav := path.get_basename()+".wav"
			path = wav if ResourceLoader.exists(wav) else "res://assets/audio/warnings/temporary_"+mode.to_lower()+".wav"
		if not streams.has(path): streams[path] = load(path) if ResourceLoader.exists(path) else null
		result[mode] = streams[path]
	return result
static func setup_bus() -> void:
	for name in ["ESSAIMWarningMaster","ESSAIMWarnings","ESSAIMWarningsMuffled"]:
		if AudioServer.get_bus_index(name) >= 0: continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count-1
		AudioServer.set_bus_name(index,name)
		AudioServer.set_bus_send(index,"Master" if name == "ESSAIMWarningMaster" else "ESSAIMWarningMaster")
		if name.ends_with("Muffled"):
			var filter := AudioEffectLowPassFilter.new()
			filter.cutoff_hz = 1100
			AudioServer.add_bus_effect(index,filter)
		var limiter := AudioEffectLimiter.new()
		limiter.ceiling_db = -1
		limiter.threshold_db = -6
		AudioServer.add_bus_effect(index,limiter)
