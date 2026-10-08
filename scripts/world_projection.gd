extends RefCounted
## A read-only UI projection. Observer geometry cannot reveal the S5 existence draw.

static func shelter(record: Dictionary, director: bool) -> Dictionary:
	if director:
		return record
	var masked: Dictionary = {}
	for key in ["id", "name", "position", "color", "shape", "distance", "special", "resources", "known_information"]:
		masked[key] = record[key]
	masked["exists"] = true
	masked["capacity"] = 0
	masked["occupancy"] = 0
	masked["operational"] = true
	masked["accepting"] = true
	masked["resources_quantity_person_days"] = null
	masked["supplies_person_days"] = null
	masked["supply_level"] = null
	masked["door_status"] = "UNVERIFIED"
	masked["maintenance_condition"] = null
	masked["operational_status"] = "UNVERIFIED"
	masked["hidden_information"] = {}
	masked["event_history"] = []
	masked["observer_masked"] = true
	masked["rumored"] = record["id"] == "S5"
	return masked

static func shelters(records: Array, director: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record in records:
		result.append(shelter(record, director))
	return result
