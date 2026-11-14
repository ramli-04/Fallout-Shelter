extends RefCounted
## Versioned pre-run settings. NumPy sampling is performed before the clock starts.
const DEFAULT_PATH := "res://resources/social_config.json"
const INTEGER_KEYS := ["schema_version","total","civilians","authorities","children","school_students","seed","police_vehicles","ambulances","fire_trucks","civil_protection_vehicles","warning_min","warning_max","simulation_speed","llm_agents","concurrency","provider_concurrency","zack_age","legend_age"]
const USER_PATH := "user://social_preset.json"

static func defaults() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(DEFAULT_PATH))

static func validate(c: Dictionary) -> String:
	var base := defaults()
	for added in ["vehicles_in_use_rate","vehicle_collisions","pre_disaster_seconds","automatic_warning","day_start_hour","routine_clock_rate","spontaneous_actions","named_agents_enabled","zack_age","legend_age","dog_shelter_access_restricted"]:
		if not c.has(added): c[added]=base[added]
	for key in base:
		if not c.has(key): return "Missing setting: " + key
		if base[key] is bool and not c[key] is bool: return "Boolean required: "+key
		if base[key] is float or base[key] is int:
			if not (c[key] is float or c[key] is int) or not is_finite(float(c[key])): return "Invalid number: " + key
			if key in INTEGER_KEYS and c[key] != floorf(c[key]): return "Integer required: " + key
	if c.pre_disaster_seconds<0 or c.pre_disaster_seconds>86400 or c.day_start_hour<0 or c.day_start_hour>=24 or c.routine_clock_rate<1 or c.routine_clock_rate>3600: return "Invalid daily routine timing"
	if c.schema_version != 1: return "Unsupported schema version"
	if c.total < 1 or c.total > 400 or c.authorities < 0 or c.civilians < 0 or c.total != c.authorities+c.civilians: return "Civilians + authorities must equal total (1–400)"
	if c.children < 0 or c.school_students < 0 or c.school_students > c.children or c.children > c.civilians or (c.children > 0 and c.children == c.total): return "Students <= children <= civilians; children need guardians"
	if c.named_agents_enabled and c.civilians-c.children < 2: return "Named agents require at least two adult civilian slots"
	if c.zack_age < 18 or c.zack_age > 100 or c.legend_age < 18 or c.legend_age > 100: return "Named civilian ages must be 18-100"
	for key in ["family_rate","iq_influence","stress_tolerance","cooperation","authority_trust","skepticism","risk_tolerance","sociability","vehicle_rate","vehicles_in_use_rate","traffic_density","accident_probability","roadblock_frequency","phone_rate","social_adoption","rumor_probability","credibility_sensitivity","network_availability","alert_reach","shelter_availability","family_priority"]:
		if c[key] < 0 or c[key] > 1: return key + " must be 0–1"
	if c.police_vehicles < 0 or c.ambulances < 0 or c.fire_trucks < 0 or c.civil_protection_vehicles<0 or c.police_vehicles+c.ambulances+c.fire_trucks+c.civil_protection_vehicles > c.authorities: return "Emergency vehicles exceed authority drivers"
	if c.llm_agents < 0 or c.llm_agents > c.total-c.children or c.concurrency < 1 or c.concurrency > 120: return "Invalid AI limits"
	if c.iq_influence>.1: return "Synthetic IQ influence must be at most 0.1"
	if c.provider_concurrency<1 or c.provider_concurrency>16: return "Provider concurrency must be 1-16"
	if c.iq_mean < 1 or c.iq_mean > 200 or c.iq_std <= 0 or c.iq_std > 50: return "Invalid IQ distribution"
	if c.warning_min < 30 or c.warning_max < c.warning_min or c.warning_max > 3600: return "Invalid warning interval"
	if c.execution_mode not in ["async","sync"] or float(c.simulation_speed) not in [1.0,2.0,5.0,10.0]: return "Invalid execution mode or speed"
	if c.inference_interval < 1 or c.inference_interval > 300 or c.event_frequency < 0 or c.event_frequency > 10: return "Invalid frequency"
	if c.seed < 0 or c.seed > 2147483647: return "Invalid seed"
	for key in ["group_a","group_b","group_c"]:
		if c[key] not in ["A","B","C","rules"]: return "Unknown provider group"
	for suffix in ["a","b","c"]:
		if c["provider_"+suffix] not in ["ollama","gemini","grok","openai"]: return "Unknown provider"
		if not c["model_"+suffix] is String or c["model_"+suffix].is_empty() or c["model_"+suffix].length()>120: return "Invalid model name"
	return ""

static func population(config: Dictionary) -> Dictionary:
	var cached: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://resources/social_population.json"))
	if cached is Dictionary and same_config(cached.get("config",{}),config): return cached
	var input := ProjectSettings.globalize_path("user://population_request_%d.json"%OS.get_process_id())
	var output := ProjectSettings.globalize_path("user://population_result_%d.json"%OS.get_process_id())
	var file := FileAccess.open(input,FileAccess.WRITE)
	file.store_string(JSON.stringify(config))
	file.close()
	var python := ProjectSettings.globalize_path("res://.venv/Scripts/python.exe")
	if not FileAccess.file_exists(python): python = "python3"
	var logs := []
	var result := OS.execute(python,["-m","ai_service.social_population","--config",input,"--output",output],logs,true)
	if result != 0:
		push_error("NumPy population generation failed: " + str(logs))
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(output))
	return data if data is Dictionary else {}

static func save_preset(config: Dictionary, path: String = USER_PATH) -> Error:
	if not validate(config).is_empty(): return ERR_INVALID_DATA
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(config,"  ",true,true))
	return OK

static func same_config(first: Dictionary, second: Dictionary) -> bool:
	if first.size()!=second.size(): return false
	for key in first:
		if not second.has(key): return false
		if (first[key] is float or first[key] is int) and (second[key] is float or second[key] is int):
			if float(first[key])!=float(second[key]): return false
		elif first[key]!=second[key]: return false
	return true
