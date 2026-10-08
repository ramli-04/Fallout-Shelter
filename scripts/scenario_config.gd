extends RefCounted
## Configuration checks are separate from the runtime clock and agent loop.

const CityMap = preload("res://scripts/city_map.gd")

static func validate_settings(data: Dictionary) -> String:
	for key in ["seed", "agent_count", "authority_count", "speed_range", "trait_range", "simulation_speed", "shelters"]:
		if not data.has(key):
			return "Missing configuration key: %s" % key
	for key in ["seed", "agent_count", "authority_count"]:
		if not _is_number(data[key]) or float(data[key]) != floor(float(data[key])):
			return "%s must be an integer." % key
	if int(data["agent_count"]) < 1 or int(data["agent_count"]) > 24:
		return "agent_count must be 1–24 (available Phase 1 sidewalk positions)."
	if int(data["authority_count"]) < 0 or int(data["authority_count"]) > int(data["agent_count"]):
		return "authority_count must be between zero and agent_count."
	for key in ["speed_range", "trait_range"]:
		var bounds: Variant = data[key]
		if not bounds is Array or bounds.size() != 2:
			return "%s must be a two-number array." % key
		if not _is_number(bounds[0]) or not _is_number(bounds[1]):
			return "%s must contain finite numbers." % key
		if bounds[0] > bounds[1]:
			return "%s minimum must not exceed maximum." % key
	if data["speed_range"][0] <= 0:
		return "Movement speed must be positive."
	if data["trait_range"][0] < 0 or data["trait_range"][1] > 1:
		return "Traits must lie in [0, 1]."
	if not _is_number(data["simulation_speed"]) or data["simulation_speed"] not in [1.0, 2.0, 5.0, 10.0]:
		return "simulation_speed must be 1, 2, 5, or 10."
	var evacuation_error := _validate_evacuation(data.get("evacuation"))
	if not evacuation_error.is_empty():
		return evacuation_error
	if not data["shelters"] is Array or data["shelters"].size() != 5:
		return "Initialize exactly five shelter records."
	var ids: Array[String] = []
	for shelter in data["shelters"]:
		if not shelter is Dictionary:
			return "Each shelter must be a JSON object."
		for key in ["id", "name", "capacity", "resources", "supplies_person_days", "distance", "special", "existence_probability", "position", "color", "shape"]:
			if not shelter.has(key):
				return "Shelter is missing key: %s" % key
		for key in ["id", "name", "resources", "distance", "special", "color", "shape"]:
			if not shelter[key] is String or shelter[key].strip_edges().is_empty():
				return "Shelter %s must be a nonempty string." % key
		if shelter["id"] in ids or shelter["id"] not in ["S1", "S2", "S3", "S4", "S5"]:
			return "Shelter IDs must be unique S1–S5."
		ids.append(shelter["id"])
		if not _is_number(shelter["capacity"]) or shelter["capacity"] < 1 or shelter["capacity"] != floor(shelter["capacity"]):
			return "Shelter capacity must be a positive integer."
		var probability: Variant = shelter["existence_probability"]
		if not _is_number(probability) or probability < 0 or probability > 1:
			return "Shelter existence probability must lie in [0, 1]."
		var location: Variant = shelter["position"]
		if not location is Array or location.size() != 2:
			return "Shelter position needs two world coordinates."
		if not _is_number(location[0]) or not _is_number(location[1]):
			return "Shelter position must contain finite numbers."
		if not Rect2(Vector2.ZERO, CityMap.MAP_SIZE).has_point(Vector2(location[0], location[1])):
			return "Shelter position must lie inside the city map."
		var position := Vector2(location[0], location[1])
		var road_distance := (position - (position / 180).round() * 180).abs()
		if minf(road_distance.x, road_distance.y) > 30:
			return "Shelter positions must be on a road or adjacent sidewalk (within 30 units)."
		if not shelter.get("operational") is bool:
			return "Shelter operational must be true or false."
		for key in ["known_risk", "popularity", "official_support", "resource_score", "information_confidence", "public_existence_probability"]:
			var value: Variant = shelter.get(key)
			if not _is_number(value) or value < 0 or value > 1:
				return "Shelter %s must be a number in [0, 1]." % key
		if not Color.html_is_valid(shelter["color"]):
			return "Shelter color must be a valid HTML color."
		if shelter["shape"] not in ["hexagon", "square", "circle", "diamond", "triangle"]:
			return "Unsupported shelter shape."
		var supplies: Variant = shelter["supplies_person_days"]
		if supplies != null and (not _is_number(supplies) or supplies < 0):
			return "Supplies must be null (unspecified) or a nonnegative number."
	return ""


static func _validate_evacuation(evacuation: Variant) -> String:
	if not evacuation is Dictionary:
		return "evacuation must be a configuration object."
	var bounds: Variant = evacuation.get("countdown_range")
	if not bounds is Array or bounds.size() != 2:
		return "countdown_range must be [minimum, maximum]."
	for value in bounds:
		if not _is_number(value) or value != floor(value) or value < 300 or value > 600:
			return "Countdown bounds must be integers between 300 and 600."
	if bounds[0] > bounds[1]:
		return "Countdown minimum cannot exceed maximum."
	for key in ["fixed_step_seconds", "decision_interval_seconds", "rejection_pause_seconds"]:
		var value: Variant = evacuation.get(key)
		if not _is_number(value) or value <= 0:
			return "%s must be positive." % key
	if evacuation["fixed_step_seconds"] > 1 or evacuation["fixed_step_seconds"] < 0.01:
		return "fixed_step_seconds must be between 0.01 and 1."
	if evacuation["decision_interval_seconds"] < evacuation["fixed_step_seconds"]:
		return "Decision interval must be at least one fixed step."
	for key in ["switch_margin", "belief_uncertainty"]:
		var value: Variant = evacuation.get(key)
		if not _is_number(value) or value < 0 or (key == "belief_uncertainty" and value > 1):
			return "Invalid %s." % key
	var personalities: Variant = evacuation.get("personalities")
	if not personalities is Array or personalities.is_empty():
		return "personalities must be a nonempty array."
	for personality in personalities:
		if personality not in ["Cautious", "Bold", "Social", "Pragmatic"]:
			return "Unsupported personality: %s" % str(personality)
	var weights: Variant = evacuation.get("weights")
	if not weights is Dictionary:
		return "Decision weights must be an object."
	for key in ["resources", "capacity", "capacity_normalizer", "popularity", "authority", "travel", "risk", "existence", "uncertainty"]:
		var value: Variant = weights.get(key)
		if not _is_number(value) or value < 0 or (key == "capacity_normalizer" and value == 0):
			return "Invalid decision weight: %s" % key
	return ""


static func _is_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))



