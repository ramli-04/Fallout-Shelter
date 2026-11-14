extends SceneTree
const Manager = preload("res://scripts/simulation_manager.gd")
const Map = preload("res://scripts/city_map.gd")
const Inspector = preload("res://scripts/object_inspector.gd")
const CompanionView = preload("res://scripts/three_d/animal_companion_3d.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: "+label)

func _clear_old_room_occupancy(social: RefCounted, agent: Dictionary, entity_id: String) -> void:
	var room_id: String = agent.get("indoor_id","")
	if not room_id.is_empty() and social.daily.interiors.rooms.has(room_id):
		social.daily.interiors.rooms[room_id].occupants.erase(entity_id)

func _find_clear_near(center: Vector2, min_distance: float, max_distance: float) -> Vector2:
	for radius in range(int(min_distance),int(max_distance)+1,4):
		for index in range(16):
			var point: Vector2 = center + Vector2.RIGHT.rotated(TAU*float(index)/16.0)*float(radius)
			if Map.clear_point(point,3) and Map.roadway_clear(point,2): return point
	return Vector2.INF

func run() -> void:
	var manager := Manager.new()
	root.add_child(manager)
	manager.set_process(false)
	check(manager.load_settings(),"project settings load")
	manager.social_config.llm_agents = 0
	manager.social_config.zack_age = 41
	manager.social_config.legend_age = 37
	manager.initialize_run()
	manager.ai_bridge.set_process(false)
	var social: RefCounted = manager.social
	var humans: Array = manager.agents
	check(humans.size()==100,"named people stay inside the configured human population")
	check(humans.filter(func(a):return a.role=="Civilian").size()==65,"civilian quota remains unchanged")
	check(humans.filter(func(a):return a.id=="SPECIAL_ZACK_KAMILI").size()==1,"Zack has a persistent generated identity")
	check(humans.filter(func(a):return a.id=="SPECIAL_I_AM_LEGEND").size()==1,"I Am Legend has a persistent generated identity")
	var ids: Array = humans.map(func(a):return a.id)
	check(ids.size()==ids.duplicate().size(),"human IDs are unique")
	var zack: Dictionary = social.by_id["SPECIAL_ZACK_KAMILI"]
	var legend: Dictionary = social.by_id["SPECIAL_I_AM_LEGEND"]
	check(zack.role=="Civilian" and zack.age==41 and zack.has("iq") and not zack.personal_memory.is_empty(),"Zack keeps civilian behavior, configured age, synthetic IQ, and personal memory")
	check(legend.role=="Civilian" and legend.age==37 and legend.gender=="male" and legend.visual_skin_tone=="deep_brown","I Am Legend uses a visual-only skin attribute and configured age")
	check(not legend.relationships.is_empty() and legend.companion_id=="DOG_GSD_001","I Am Legend retains human relationships and strong companion attachment")
	check(social.companions.size()==1 and social.companions[0].id=="DOG_GSD_001","the German Shepherd is a separate animal entity")
	var dog: Dictionary = social.companions[0]
	check(dog.owner_id==legend.id and dog.id not in ids,"dog ownership is explicit and does not enter the human population")
	check(not dog.shelter_access_restricted,"scenario shelter restrictions are opt-in and disabled by default")
	check(social.daily.valid_spawn(zack) and social.daily.valid_spawn(legend),"named human spawns pass the existing outdoor/interior/vehicle validation")
	if not dog.indoor_id.is_empty():
		check(social.daily.interiors.contains(dog.indoor_id,dog.position),"dog interior spawn is inside an accessible room")
	elif not dog.riding.is_empty():
		check(social.vehicles.any(func(v):return v.id==dog.riding),"dog driving spawn is inside its owner's vehicle")
	else:
		check(Map.clear_point(dog.position,3),"dog outdoor spawn is validated against static obstacles")

	# Walk the dog across a free-space road route and ensure simulation time bounds displacement.
	_clear_old_room_occupancy(social,legend,legend.id)
	_clear_old_room_occupancy(social,dog,dog.id)
	legend.indoor_id=""; legend.riding=""; legend.state="MOVING"
	dog.indoor_id=""; dog.riding=""; dog.shelter_id=""; dog.state="FOLLOWING"
	var road_slots: Array[Vector2] = Map.spawn_slots()
	var owner_point := Vector2.INF; var dog_point := Vector2.INF
	var road_route := PackedVector2Array()
	for first_index in range(mini(40,road_slots.size())):
		for second_index in range(first_index+1,mini(first_index+8,road_slots.size())):
			if road_slots[first_index].distance_to(road_slots[second_index])<30.0: continue
			var candidate_route: PackedVector2Array=Map.free_route(road_slots[second_index],road_slots[first_index])
			if not candidate_route.is_empty():
				owner_point=road_slots[first_index]; dog_point=road_slots[second_index]; road_route=candidate_route; break
		if not road_route.is_empty(): break
	check(not road_route.is_empty(),"dog can plan an outdoor route across the street network")
	if not road_route.is_empty():
		legend.position=owner_point; dog.position=dog_point; dog.previous_position=dog.position
		dog.route=PackedVector2Array(); dog.route_index=0; dog.route_target=Vector2.INF; dog.route_replan=0.0
		var before: Vector2=dog.position
		var distance_before: float=dog.position.distance_to(legend.position)
		social.companion_runtime.tick(0.5)
		check(dog.position.distance_to(before)<=dog.run_speed*0.5+0.01,"dog movement is time-bounded and does not teleport")
		check(dog.position.distance_to(legend.position)<distance_before,"dog follows its owner and starts reuniting")
		check(dog.state=="REUNITING" or dog.separated,"separation is detected and the dog seeks its owner")
		legend.position=owner_point; dog.position=legend.position+Vector2(40,0); dog.shelter_id=""; dog.separated=true
		var owner_response: bool=social.move_social(legend,0.5)
		check(owner_response and legend.current_goal.to_lower().contains("reunite"),"strong owner attachment makes I Am Legend respond to a nearby separation")

	# Same-room navigation and the real door chain between two accessible interiors.
	var room_ids: Array=social.daily.interiors.rooms.keys()
	check(not room_ids.is_empty(),"accessible building interiors exist")
	if not room_ids.is_empty():
		var room: Dictionary=social.daily.interiors.rooms[room_ids[0]]
		legend.riding=""; legend.indoor_id=room.id; legend.position=room.center
		dog.riding=""; dog.indoor_id=room.id; dog.location_mode="INDOOR"
		dog.position=room.center+Vector2(10,0).rotated(room.angle); dog.previous_position=dog.position
		dog.route=PackedVector2Array(); dog.transition_path=PackedVector2Array()
		var before_indoor: Vector2=dog.position
		social.companion_runtime.tick(0.5)
		check(dog.indoor_id==room.id and dog.position.distance_to(before_indoor)<=dog.run_speed*0.5+0.01,"dog follows inside the same building without teleporting")
		_clear_old_room_occupancy(social,dog,dog.id)
		dog.indoor_id=""; dog.position=room.door_outside; dog.transition_path=PackedVector2Array(); dog.route=PackedVector2Array()
		legend.indoor_id=room.id; legend.position=room.center; legend.state="ROUTINE"
		for _step in range(32): social.companion_runtime.tick(0.5)
		check(dog.indoor_id==room.id,"dog enters the owner's interior through the actual door corridor")
		_clear_old_room_occupancy(social,dog,dog.id)
		legend.indoor_id=""; legend.position=room.door_outside; dog.position=room.center
		dog.indoor_id=room.id; dog.transition_path=PackedVector2Array(); dog.route=PackedVector2Array()
		for _step in range(32): social.companion_runtime.tick(0.5)
		check(dog.indoor_id.is_empty(),"dog exits an interior through its actual door corridor to reunite")

	# Vehicle departure waits for the animal and transports it separately from human occupancy.
	var owner_car: Dictionary={}
	for vehicle in social.vehicles:
		if vehicle.owner==legend.id: owner_car=vehicle; break
	if not owner_car.is_empty():
		_clear_old_room_occupancy(social,legend,legend.id); _clear_old_room_occupancy(social,dog,dog.id)
		legend.indoor_id=""; legend.riding=""; dog.indoor_id=""; dog.riding=""; dog.shelter_id=""
		owner_car.status="PARKED"; owner_car.speed=0.0
		legend.position=owner_car.position; dog.position=owner_car.position+Vector2(2,0)
		var boarded: bool=social.companion_runtime.prepare_vehicle_departure(legend,owner_car)
		check(boarded and dog.riding==owner_car.id and dog.id in owner_car.animal_passengers,"owner's dog boards a shared vehicle before it departs")
		social.companion_runtime.vehicle_arrived(owner_car)
		check(dog.riding=="" and dog.location_mode=="OUTDOOR","dog exits with its owner at a vehicle arrival")
	else:
		check(false,"named civilian has an assigned household vehicle for the boarding test")

	# The owner waits at the shelter until the dog physically reaches the entrance.
	var shelter: Dictionary=manager.shelter_by_id.get("S1",{})
	manager.phase="EVACUATION"
	_clear_old_room_occupancy(social,legend,legend.id); _clear_old_room_occupancy(social,dog,dog.id)
	legend.indoor_id=""; legend.riding=""; legend.position=shelter.position; legend.objective=shelter.id; legend.state="MOVING"
	dog.indoor_id=""; dog.riding=""; dog.shelter_id=""; dog.position=shelter.position+Vector2(42,0)
	var waiting: String=manager.admit_arrival(legend)
	check(waiting.contains("Waiting for companion") and legend.state!="SHELTERED","owner does not enter shelter ahead of an unrestricted dog")
	dog.position=shelter.position
	var admission: String=manager.admit_arrival(legend)
	check(admission.is_empty() and dog.shelter_id==shelter.id and dog.state=="SHELTERED","dog and owner enter the same shelter together")
	social.companion_runtime.impact()
	check(dog.survival_status=="PROTECTED_AT_IMPACT" and dog.health==100.0,"dog survival status reflects shelter protection")
	social.companion_runtime.all_clear()
	check(dog.survival_status=="SAFE_FROM_STRIKE" and dog.goal.contains("All-clear"),"false-alarm resolution marks the dog safe without separating its owner")
	var restricted_shelter: Dictionary=manager.shelter_by_id.get("S2",{})
	legend.state="MOVING"; legend.shelter_id=""; legend.objective=restricted_shelter.id; legend.position=restricted_shelter.position
	dog.shelter_access_restricted=true; dog.shelter_id=""; dog.position=restricted_shelter.position+Vector2(42,0)
	var restricted_entry: String=manager.admit_arrival(legend)
	check(restricted_entry.is_empty() and legend.state=="SHELTERED" and dog.shelter_id.is_empty() and dog.position.distance_to(restricted_shelter.position)>10.0,"only an explicit scenario restriction allows the owner to enter without the dog")
	var director_text: String=Inspector.companion_text(social.companion_runtime,dog.id)
	check(director_text.contains("German Shepherd") and director_text.contains("I Am Legend") and director_text.contains(dog.survival_status),"Director companion view shows owner, location, status, relationship, and goal")

	var visual_dog: Dictionary=dog.duplicate(true)
	visual_dog.state="FOLLOWING"; visual_dog.shelter_id=""; visual_dog.position=Map.nearest_lane_point(Map.MAP_SIZE*0.5)
	visual_dog.previous_position=visual_dog.position; visual_dog.survival_status="UNDETERMINED"
	var avatar := CompanionView.new()
	avatar.configure(visual_dog)
	root.add_child(avatar)
	await process_frame
	visual_dog.bark_serial+=1; visual_dog.state="BARKING"
	avatar.update_visual(visual_dog,1.0,true,1.0)
	check(avatar.last_bark_serial==visual_dog.bark_serial and avatar.bark_player.stream.data.size()>0,"dog renderer provides bark audio and state-driven animation")
	avatar.set_selected(true)
	check(avatar.selection_area.collision_layer==4 and avatar.selection_ring.visible,"dog can be selected in Director Mode")
	avatar.queue_free(); await process_frame

	manager.initialize_run()
	check(manager.agents.size()==100 and manager.social.companions.size()==1 and manager.social.companions[0].id=="DOG_GSD_001","reset clears old state and recreates exactly one persistent companion")
	manager.social_config.named_agents_enabled=false
	manager.initialize_run()
	check(manager.agents.size()==100 and manager.social.companions.is_empty() and not manager.social.by_id.has("SPECIAL_ZACK_KAMILI") and not manager.social.by_id.has("SPECIAL_I_AM_LEGEND"),"disabling named agents preserves the configured human total and removes the companion")
	manager.social.close()
	manager.queue_free(); await process_frame
	await process_frame
	print("Phase 6.5 special agents and companion: %d checks / %d failures"%[checks,failures])
	quit(1 if failures else 0)
