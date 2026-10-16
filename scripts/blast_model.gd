extends RefCounted
## Fictional experimental damage, never a physical nuclear-effects prediction.
const Coordinates = preload("res://scripts/three_d/world_coordinates.gd")
static func intensity(point: Vector2, config: Dictionary) -> float:
	var center := Vector2(config["impact_position"][0],config["impact_position"][1])
	var distance := point.distance_to(center)*Coordinates.SCALE
	for i in range(3):
		if distance <= config["radius"]*config["zone_fractions"][i]:
			return config["severity"]*config["zone_damage"][i]
	return 0.0
static func shelter_result(shelter: Dictionary, config: Dictionary) -> Dictionary:
	var center := Vector2(config["impact_position"][0],config["impact_position"][1])
	var load: float = intensity(shelter["position"],config)/(1.0+shelter.get("terrain_protection",0.0))
	var resistance: float = shelter.get("blast_resistance",1.3)
	return {"distance_world": shelter["position"].distance_to(center)*Coordinates.SCALE,
		"damage_load": load, "structural_state": "ABSENT" if not shelter["exists"] else "DESTROYED" if load >= resistance else "DAMAGED" if load >= resistance*0.5 else "INTACT"}
static func apply(shelter: Dictionary, config: Dictionary) -> void:
	var result := shelter_result(shelter,config)
	shelter.merge(result,true)
	if result["structural_state"] == "DESTROYED":
		shelter["operational"] = false
		shelter["base_operational"] = false
		shelter["accepting"] = false
		shelter["door_status"] = "DESTROYED"
		shelter["operational_status"] = "DESTROYED"
		shelter["capacity"] = 0
		shelter["supply_level"] = 0.0
	elif result["structural_state"] == "DAMAGED":
		shelter["capacity"] = int(shelter["capacity"]*config["damaged_capacity_fraction"])
		shelter["supply_level"] *= config["damaged_supply_fraction"]
		shelter["door_status"] = "JAMMED"
		shelter["operational_status"] = "DAMAGED"

static func validate(config: Variant) -> String:
	if not config is Dictionary: return "Nuclear configuration must be an object."
	for key in ["map_scale","radius","severity","building_resistance","damaged_capacity_fraction","damaged_supply_fraction","damaged_occupant_damage","destroyed_occupant_damage","outside_damage_multiplier"]:
		if not config.has(key) or not (config[key] is float or config[key] is int) or not is_finite(float(config[key])) or config[key] < 0:
			return "Invalid nuclear number: " + key
	if config["building_resistance"] <= 0: return "Building resistance must be positive."
	if config["map_scale"] not in [2.0,2.5,3.0,3.75] or config["radius"] < 10 or config["radius"] > 700 or config["severity"] > 4:
		return "Nuclear map scale, radius or severity out of bounds."
	for key in ["damaged_capacity_fraction","damaged_supply_fraction"]:
		if config[key] > 1: return "Damage fractions must be within [0,1]."
	if not config.get("random_impact") is bool: return "random_impact must be boolean."
	for key in ["impact_position","zone_fractions","zone_damage"]:
		var values: Variant = config.get(key)
		if not values is Array or values.size() != (2 if key == "impact_position" else 3): return "Invalid array: " + key
		for value in values:
			if not (value is float or value is int) or not is_finite(float(value)) or value < 0: return "Invalid nuclear array value."
	if not (0 < config["zone_fractions"][0] and config["zone_fractions"][0] < config["zone_fractions"][1] and config["zone_fractions"][1] < config["zone_fractions"][2] and config["zone_fractions"][2] <= 1):
		return "Blast zone fractions must increase within (0,1]."
	if config["zone_damage"][0] < config["zone_damage"][1] or config["zone_damage"][1] < config["zone_damage"][2]: return "Blast damage must decrease with distance."
	var bounds := Vector2(1800,1080)*float(config["map_scale"])
	if config["impact_position"][0] > bounds.x or config["impact_position"][1] > bounds.y: return "Impact lies outside configured city."
	return ""

static func structure_state(point: Vector2, config: Dictionary) -> String:
	var load := intensity(point,config)
	return "DESTROYED" if load >= config["building_resistance"] else "DAMAGED" if load > 0 else "INTACT"
