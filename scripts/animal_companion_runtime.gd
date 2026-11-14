extends RefCounted
## Companion movement is simulation-clock driven; it never snaps to the owner.
const Map = preload("res://scripts/city_map.gd")
const Routes = preload("res://scripts/road_routes.gd")
const DOG_ID := "DOG_GSD_001"
const OWNER_ID := "SPECIAL_I_AM_LEGEND"

var social: RefCounted
var companions: Array[Dictionary] = []

func initialize(owner_social: RefCounted) -> void:
	social = owner_social
	companions.clear()
	if not social.config.get("named_agents_enabled", true) or not social.by_id.has(OWNER_ID): return
	var owner: Dictionary = social.by_id[OWNER_ID]
	var dog: Dictionary = {
		"id": DOG_ID, "name": "German Shepherd", "species": "Dog", "breed": "German Shepherd",
		"owner_id": OWNER_ID, "attachment": 0.98, "position": owner.position, "previous_position": owner.position,
		"indoor_id": "", "location_mode": "OUTDOOR", "riding": "", "boarding_vehicle": "",
		"route": PackedVector2Array(), "route_index": 0, "route_target": Vector2.INF,
		"route_replan": 0.0, "speed": 8.0, "run_speed": 12.0, "health": 100.0,
		"fear": 0.0, "state": "FOLLOWING", "goal": "Stay near I Am Legend",
		"survival_status": "UNDETERMINED", "shelter_id": "", "shelter_access_restricted": social.config.get("dog_shelter_access_restricted",false),
		"last_owner_position": owner.position, "last_seen_owner_at": social.manager.elapsed_seconds,
		"separated": false, "bark_serial": 0, "bark_until": -1.0, "next_bark_at": 0.0,
		"transition_path": PackedVector2Array(), "transition_index": 0, "transition_target_room": "",
		"memories": [{"time": social.manager.elapsed_seconds, "text": "Stays close to owner I Am Legend."}]
	}
	owner.companion_id = DOG_ID
	owner.companion_attachment = 0.98
	owner.companion_last_seen = owner.position
	if not owner.get("riding", "").is_empty():
		var vehicle: Dictionary = _vehicle(owner.riding)
		if not vehicle.is_empty(): _board_at_spawn(dog, vehicle)
	elif not owner.get("indoor_id", "").is_empty():
		var room_id: String = owner.indoor_id
		var slot: Vector2 = social.daily.interiors.reserve_slot(room_id, DOG_ID)
		if not slot.is_finite() and social.daily.interiors.rooms.has(room_id):
			for radius in [6.0, 9.0, 12.0, 16.0]:
				for index in range(8):
					var candidate: Vector2 = owner.position+Vector2.RIGHT.rotated(TAU*float(index)/8.0)*radius
					if social.daily.interiors.contains(room_id,candidate) and not social.manager.agents.any(func(agent):return agent.get("indoor_id","")==room_id and agent.position.distance_to(candidate)<4.0):
						slot=candidate; break
				if slot.is_finite(): break
		if slot.is_finite():
			dog.position = slot
			dog.indoor_id = room_id
			dog.location_mode = "INDOOR"
			social.daily.interiors.rooms[room_id].occupants.append(DOG_ID)
	else:
		var spawn := _spawn_near(owner.position)
		if spawn.is_finite(): dog.position = spawn
		dog.previous_position = dog.position
	dog.last_owner_position = dog.position
	companions.append(dog)

func tick(seconds: float) -> void:
	if social == null: return
	for dog in companions:
		if dog.health <= 0: continue
		dog.previous_position = dog.position
		var owner: Dictionary = social.by_id.get(dog.owner_id, {})
		if owner.is_empty():
			dog.state = "SEARCHING_OWNER"
			continue
		if not dog.get("riding", "").is_empty():
			var vehicle: Dictionary = _vehicle(dog.riding)
			if not vehicle.is_empty():
				dog.position = vehicle.position
				dog.state = "IN_VEHICLE"
				dog.goal = "Travel with owner in " + str(vehicle.id)
				_update_fear(dog, owner, seconds)
				continue
			dog.riding = ""
			dog.location_mode = "OUTDOOR"
		if owner.get("state", "") == "SHELTERED" and not dog.shelter_access_restricted:
			if dog.get("shelter_id", "") == owner.shelter_id:
				dog.state = "SHELTERED"
				dog.location_mode = "SHELTER"
				dog.goal = "Sheltered with I Am Legend"
				continue
		if owner.get("riding", "") != "" and owner.riding == dog.get("riding", ""):
			dog.position = owner.position
			continue
		_update_fear(dog, owner, seconds)
		var target_room: String = str(owner.get("indoor_id", ""))
		if dog.get("boarding_vehicle", "") != "":
			var car: Dictionary = _vehicle(dog.boarding_vehicle)
			if not car.is_empty():
				_follow_outdoor_target(dog, car.position, seconds, true)
				if dog.position.distance_to(car.position) <= 4.0 and car.speed <= 1.0:
					_board_at_spawn(dog, car)
				continue
			dog.boarding_vehicle = ""
		if target_room == dog.get("indoor_id", "") and not target_room.is_empty():
			var room: Dictionary = social.daily.interiors.rooms.get(target_room, {})
			if not room.is_empty():
				_move_direct(dog, owner.position, seconds, _speed(dog, owner))
				dog.last_owner_position = owner.position
				dog.last_seen_owner_at = social.manager.elapsed_seconds
				dog.goal = "Stay with owner indoors"
				_finish_follow_state(dog, owner)
				continue
		if not dog.get("indoor_id", "").is_empty():
			if not _advance_door_transition(dog, seconds):
				dog.goal = "Exit through the building door to follow owner"
				continue
		if not target_room.is_empty():
			_follow_room_door(dog, target_room, seconds)
		else:
			var target: Vector2 = owner.position
			if dog.position.distance_to(owner.position) <= social.manager.living.observation_radius:
				dog.last_owner_position = owner.position
				dog.last_seen_owner_at = social.manager.elapsed_seconds
			else:
				target = dog.last_owner_position
			_follow_outdoor_target(dog, target, seconds, false)
			dog.goal = "Follow owner along walkable streets"
		_finish_follow_state(dog, owner)

func prepare_vehicle_departure(owner: Dictionary, vehicle: Dictionary) -> bool:
	for dog in companions:
		var passenger: Dictionary = social.by_id.get(dog.owner_id, {})
		if passenger.is_empty(): continue
		var traveling_together: bool = passenger.id == owner.id or passenger.get("riding", "") == vehicle.id or passenger.get("boarding_vehicle", "") == vehicle.id or passenger.id in vehicle.passengers
		if not traveling_together: continue
		if dog.health <= 0 or dog.get("shelter_access_restricted", false) or dog.get("riding", "") == vehicle.id: continue
		if vehicle.speed <= 1.0 and dog.position.distance_to(vehicle.position) <= 4.0:
			_board_at_spawn(dog, vehicle)
			continue
		dog.boarding_vehicle = vehicle.id
		dog.goal = "Walk to owner's parked vehicle before departure"
		return false
	return true

func before_owner_admission(owner: Dictionary, shelter: Dictionary) -> bool:
	var dog: Dictionary = _for_owner(owner.id)
	if dog.is_empty() or dog.health <= 0: return true
	if dog.get("shelter_access_restricted", false):
		dog.state = "ACCESS_RESTRICTED"
		dog.goal = "Shelter access restriction; remains with owner until entry"
		return true
	if dog.get("shelter_id", "") == shelter.id: return true
	if dog.position.distance_to(shelter.position) <= 1.0:
		dog.shelter_id = shelter.id
		dog.state = "SHELTERED"
		dog.location_mode = "SHELTER"
		dog.goal = "Enter shelter with I Am Legend"
		_remember(dog, "Entered " + str(shelter.id) + " with owner.")
		return true
	owner.current_goal = "Wait for German Shepherd to reach shelter entrance"
	return false

func owner_admitted(owner: Dictionary, shelter: Dictionary) -> void:
	var dog: Dictionary = _for_owner(owner.id)
	if dog.is_empty() or dog.get("shelter_access_restricted", false) or dog.health <= 0: return
	dog.shelter_id = shelter.id
	dog.state = "SHELTERED"
	dog.location_mode = "SHELTER"
	dog.goal = "Sheltered with I Am Legend"
	_remember(dog, "Sheltered with owner at " + str(shelter.id) + ".")

func vehicle_arrived(vehicle: Dictionary) -> void:
	for dog in companions:
		if dog.get("riding", "") != vehicle.id: continue
		vehicle.get("animal_passengers", []).erase(dog.id)
		dog.riding = ""
		dog.location_mode = "OUTDOOR"
		dog.position = vehicle.position
		dog.last_owner_position = vehicle.position
		dog.goal = "Rejoin owner after vehicle arrival"

func impact() -> void:
	var blast = preload("res://scripts/blast_model.gd")
	for dog in companions:
		var damage := 0.0
		var sheltered: bool = not dog.get("shelter_id", "").is_empty()
		if not sheltered:
			damage = blast.intensity(dog.position, social.manager.nuclear) * float(social.manager.nuclear.outside_damage_multiplier)
		else:
			var shelter: Dictionary = social.manager.shelter_by_id.get(dog.shelter_id, {})
			if not shelter.is_empty():
				var state: String = shelter.get("structural_state", "INTACT")
				damage = float(social.manager.nuclear.destroyed_occupant_damage) if state == "DESTROYED" else float(social.manager.nuclear.damaged_occupant_damage) if state == "DAMAGED" else 0.0
		dog.health = maxf(0.0, dog.health - damage)
		dog.survival_status = "DEAD" if dog.health <= 0.0 else "INJURED" if damage > 0.0 else "PROTECTED_AT_IMPACT" if sheltered else "SURVIVED_OUTSIDE"
		dog.state = "DEAD" if dog.health <= 0.0 else "INJURED" if damage > 0.0 else dog.state
		dog.goal = "Impact outcome: " + dog.survival_status
		social.emit_event("animal.survival", dog.id, {"owner": dog.owner_id, "status": dog.survival_status, "simplified_damage": damage})
		_remember(dog, dog.goal)

func all_clear() -> void:
	for dog in companions:
		if dog.health <= 0: continue
		dog.survival_status = "SAFE_FROM_STRIKE"
		dog.goal = "All-clear; remain with owner I Am Legend"
		if dog.state != "SHELTERED": dog.state = "FOLLOWING"
		_remember(dog, dog.goal)

func text(dog_id: String) -> String:
	var dog: Dictionary = _by_id(dog_id)
	if dog.is_empty(): return ""
	var owner: Dictionary = social.by_id.get(dog.owner_id, {})
	var location: String = "shelter " + str(dog.shelter_id) if dog.get("shelter_id", "") != "" else "interior " + str(dog.indoor_id) if dog.get("indoor_id", "") != "" else "vehicle " + str(dog.riding) if dog.get("riding", "") != "" else "outdoors at %.0f, %.0f" % [dog.position.x, dog.position.y]
	return "[b]German Shepherd / %s[/b]\nStatus: %s / health %.0f / fear %.0f%%\nLocation: %s\nOwner: %s (%s) / attachment %.0f%%\nGoal: %s\nTogether: %s\nBarks: %d\nSurvival: %s\nRelationship: companion animal; human IQ and social traits do not affect animal behavior.\nInjury note: simplified scenario damage, not a veterinary prediction.\nRecent memories: %s" % [dog.id, dog.state, dog.health, dog.fear * 100.0, location, dog.owner_id, owner.get("display_name", owner.get("name", "unknown")), dog.attachment * 100.0, dog.goal, "yes" if not dog.separated else "separated; attempting reunion", dog.bark_serial, dog.survival_status, str(dog.memories.slice(-5))]

func close() -> void:
	for dog in companions:
		if not dog.get("indoor_id", "").is_empty() and social.daily.interiors.rooms.has(dog.indoor_id):
			social.daily.interiors.rooms[dog.indoor_id].occupants.erase(dog.id)
	companions.clear()

func _spawn_near(point: Vector2) -> Vector2:
	for radius in [5.0, 8.0, 12.0]:
		for index in range(8):
			var candidate: Vector2 = point + Vector2.RIGHT.rotated(TAU * float(index) / 8.0) * float(radius)
			if Map.clear_point(candidate, 3) and Map.roadway_clear(candidate, 2) and not social.daily.outdoor_slots.any(func(other): return other.distance_to(candidate) < 4.0):
				return candidate
	return point

func _follow_outdoor_target(dog: Dictionary, target: Vector2, seconds: float, boarding: bool) -> void:
	if not dog.has("route") or dog.route.is_empty() or dog.route_index >= dog.route.size() or dog.route_target.distance_to(target) > 12.0 or social.manager.elapsed_seconds >= dog.route_replan:
		dog.route = Map.free_route(dog.position, target)
		dog.route_index = 1 if dog.route.size() > 1 else 0
		dog.route_target = target
		dog.route_replan = social.manager.elapsed_seconds + (0.8 if boarding else 1.5)
	if dog.route.is_empty():
		_move_direct(dog, target, seconds, _speed(dog, social.by_id[dog.owner_id]))
		return
	var proxy: Dictionary = {"position": dog.position, "route": dog.route, "route_index": dog.route_index, "movement_speed": _speed(dog, social.by_id[dog.owner_id])}
	Routes.move(proxy, seconds)
	dog.position = proxy.position
	dog.route_index = proxy.route_index

func _follow_room_door(dog: Dictionary, room_id: String, seconds: float) -> void:
	if not social.daily.interiors.rooms.has(room_id):
		_follow_outdoor_target(dog, social.by_id[dog.owner_id].position, seconds, false)
		return
	if dog.get("transition_target_room", "") == room_id and not dog.transition_path.is_empty():
		_advance_door_transition(dog, seconds)
		return
	var room: Dictionary = social.daily.interiors.rooms[room_id]
	if dog.position.distance_to(room.door_outside) > 2.0:
		_follow_outdoor_target(dog, room.door_outside, seconds, false)
		dog.goal = "Follow owner to the entrance of " + room_id
		return
	dog.transition_path = PackedVector2Array([room.door, room.door_inside, room.center])
	dog.transition_index = 0
	dog.transition_target_room = room_id
	dog.state = "ENTERING"
	_advance_door_transition(dog, seconds)

func _advance_door_transition(dog: Dictionary, seconds: float) -> bool:
	if dog.transition_path.is_empty():
		var current: Dictionary = social.daily.interiors.rooms.get(dog.indoor_id, {})
		if current.is_empty():
			dog.indoor_id = ""
			return true
		dog.transition_path = PackedVector2Array([current.door_inside, current.door, current.door_outside])
		dog.transition_index = 0
		dog.transition_target_room = ""
		dog.state = "EXITING"
	var budget: float = _speed(dog, social.by_id[dog.owner_id]) * seconds
	while dog.transition_index < dog.transition_path.size() and budget > 0.00001:
		var target: Vector2 = dog.transition_path[dog.transition_index]
		var distance: float = dog.position.distance_to(target)
		if distance > budget:
			dog.position = dog.position.move_toward(target, budget)
			budget = 0
		else:
			dog.position = target
			budget = maxf(0.0, budget-distance)
			dog.transition_index += 1
	if dog.transition_index < dog.transition_path.size(): return false
	if not dog.get("indoor_id", "").is_empty():
		social.daily.interiors.rooms[dog.indoor_id].occupants.erase(dog.id)
		dog.indoor_id = ""
		dog.location_mode = "OUTDOOR"
	else:
		dog.indoor_id = dog.transition_target_room
		dog.location_mode = "INDOOR"
		if not dog.indoor_id.is_empty() and dog.id not in social.daily.interiors.rooms[dog.indoor_id].occupants:
			social.daily.interiors.rooms[dog.indoor_id].occupants.append(dog.id)
	dog.transition_path = PackedVector2Array()
	dog.transition_index = 0
	dog.transition_target_room = ""
	return true

func _move_direct(dog: Dictionary, target: Vector2, seconds: float, speed: float) -> void:
	dog.position = dog.position.move_toward(target, maxf(0.0, speed) * seconds)

func _speed(dog: Dictionary, owner: Dictionary) -> float:
	return float(dog.run_speed) if owner.get("state", "") in ["MOVING", "SCRAMBLING", "EXPOSED"] else float(dog.speed)

func _finish_follow_state(dog: Dictionary, owner: Dictionary) -> void:
	var distance: float = dog.position.distance_to(owner.position)
	dog.separated = distance > 28.0
	if dog.separated:
		dog.state = "REUNITING"
		dog.goal = "Find and reunite with owner I Am Legend"
	elif social.manager.elapsed_seconds < dog.get("bark_until", -1.0):
		dog.state = "BARKING"
	else:
		dog.state = "FEARFUL" if dog.fear >= 0.45 else "FOLLOWING" if distance > 4.0 else "IDLE"
	if not dog.separated and distance <= 12.0:
		owner.companion_last_seen = dog.position

func _update_fear(dog: Dictionary, owner: Dictionary, seconds: float) -> void:
	var alert: bool = owner.get("state", "") in ["MOVING", "EXPOSED", "WAITING_ROAD"] or owner.get("social_beliefs", {}).has("nuclear") or owner.get("panic_level", 0.0) >= 40.0
	dog.fear = clampf(dog.fear + (seconds * 0.025 if alert else -seconds * 0.012), 0.0, 1.0)
	if dog.fear >= 0.55 and social.manager.elapsed_seconds >= dog.next_bark_at:
		dog.bark_serial += 1
		dog.bark_until = social.manager.elapsed_seconds + 1.2
		dog.next_bark_at = social.manager.elapsed_seconds + 12.0
		_remember(dog, "Barked in response to fear and surrounding danger cues.")

func _board_at_spawn(dog: Dictionary, vehicle: Dictionary) -> void:
	dog.riding = vehicle.id
	dog.boarding_vehicle = ""
	dog.location_mode = "VEHICLE"
	dog.position = vehicle.position
	dog.previous_position = vehicle.position
	if not vehicle.has("animal_passengers"): vehicle.animal_passengers = []
	if dog.id not in vehicle.animal_passengers: vehicle.animal_passengers.append(dog.id)

func _vehicle(id: String) -> Dictionary:
	for vehicle in social.vehicles:
		if vehicle.id == id: return vehicle
	return {}

func _for_owner(owner_id: String) -> Dictionary:
	for dog in companions:
		if dog.owner_id == owner_id: return dog
	return {}

func _by_id(id: String) -> Dictionary:
	for dog in companions:
		if dog.id == id: return dog
	return {}

func _remember(dog: Dictionary, text_value: String) -> void:
	dog.memories.append({"time": social.manager.elapsed_seconds, "text": text_value})
	while dog.memories.size() > 24: dog.memories.pop_front()
