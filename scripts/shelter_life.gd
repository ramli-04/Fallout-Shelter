extends RefCounted
## Event-driven routines and physical room-to-room movement during the ten-day shelter phase.
## Supplies, shelter truth and admissions remain owned by SimulationManager.
const PLANS := {
	"S1": [["ENTRY","Entrance",0,0],["DORM-A","Dormitory",1,0],["DORM-B","Dormitory",2,0],["FAMILY","Family bedroom",3,0],["KITCHEN","Kitchen",0,1],["COMMON","Common room",1,1],["DINING","Dining",2,1],["FOOD","Food storage",3,1],["MEDICAL","Medical",0,2],["SANITATION","Sanitation",1,2],["RECREATION","Recreation",2,2],["GENERATOR","Generator",3,2]],
	"S2": [["ENTRY","Entrance",0,0],["CONCOURSE","Metro corridor",1,0],["PLATFORM","Dormitory",2,0],["STORAGE","Supply storage",3,0],["GENERATOR","Generator",0,1],["WATER","Water storage",1,1],["WORKSHOP","Workshop",2,1],["ELECTRICAL","Electrical",3,1],["SANITATION","Sanitation",0,2],["CONTROL","Control",1,2],["DINING","Dining",2,2],["AIR","Air filtration",3,2]],
	"S3": [["ENTRY","Entrance",0,0],["OPERATIONS","Operations",1,0],["RADIO","Radio room",2,0],["COMMUNICATIONS","Communication",3,0],["MEDICAL","Medical",0,1],["CONTROL","Control",1,1],["AIR","Air filtration",2,1],["GENERATOR","Generator",3,1],["SANITATION","Sanitation",0,2],["WATER","Water treatment",1,2],["DINING","Dining",2,2],["FOOD","Food storage",3,2]],
	"S4": [["ENTRY","Entrance",0,0],["DORM-A","Dormitory",1,0],["DORM-B","Dormitory",2,0],["FAMILY","Family bedroom",3,0],["GENERATOR","Generator",0,1],["DINING","Dining",1,1],["FOOD","Food storage",2,1],["WORKSHOP","Industrial workshop",3,1],["SANITATION","Sanitation",0,2],["WATER","Water storage",1,2],["MEDICAL","Medical",2,2],["RECREATION","Recreation",3,2]],
	"S5": [["ENTRY","Secure entrance",0,0],["CHECKPOINT","Security",1,0],["CONTROL","Control",2,0],["DORMITORY","Dormitory",3,0],["GENERATOR","Generator",0,1],["OPERATIONS","Operations",1,1],["COMMUNICATIONS","Communication",2,1],["STORAGE","Storage",3,1],["SANITATION","Sanitation",0,2],["MEDICAL","Medical",1,2],["DINING","Dining",2,2],["RECREATION","Recreation",3,2]]
}
const ROOM_W := 8.0
const ROOM_D := 6.0
const POSITIONS_PER_ROOM := 35
const ROOM_TYPES := {
	"SLEEP":["Dormitory","Family bedroom"], "EAT":["Dining","Kitchen","Common room"],
	"DRINK":["Water storage","Water treatment","Kitchen","Common room","Storage","Dining"],
	"SANITATION":["Sanitation"], "TREATMENT":["Medical"],
	"TALK_FAMILY":["Common room","Dining","Recreation"], "TALK_FRIEND":["Common room","Recreation","Dining"],
	"MEET_NEIGHBORS":["Common room","Recreation","Dining"], "ARGUE":["Common room","Dining"],
	"RECONCILE":["Common room","Medical"], "GROUP_ACTIVITY":["Recreation","Dining","Common room"],
	"CLEAN":["Common room","Dining","Sanitation","Dormitory","Metro corridor"], "REPAIR_EQUIPMENT":["Workshop","Industrial workshop","Electrical","Generator","Air filtration"],
	"ORGANIZE_SUPPLIES":["Food storage","Supply storage","Storage","Warehouse"],
	"PREPARE_MEAL":["Kitchen","Dining"], "MAINTAIN_GENERATOR":["Generator","Workshop"],
	"MAINTAIN_AIR":["Air filtration","Workshop","Industrial workshop","Electrical"], "MAINTAIN_WATER":["Water treatment","Water storage","Workshop","Industrial workshop"],
	"DISTRIBUTE_RESOURCES":["Food storage","Supply storage","Storage","Dining","Kitchen"],
	"ASSIST_MEDICAL":["Medical"], "SECURITY":["Security","Entrance","Checkpoint","Control"],
	"FIRE_SAFETY":["Workshop","Generator","Storage","Entrance"], "EMERGENCY_RESPONSE":["Control","Operations","Entrance","Medical"],
	"CHILDCARE":["Family bedroom","Dormitory","Common room","Dining"], "READ":["Dormitory","Family bedroom","Recreation","Common room","Dining","Radio room"],
	"EXERCISE":["Recreation","Common room","Metro corridor","Dormitory"], "REFLECT":["Dormitory","Family bedroom","Common room"],
	"OBSERVE":["Entrance","Communications","Radio room","Operations"], "COMMUNICATE":["Communication","Radio room","Operations","Control"],
	"PLAY_DOG":["Recreation","Common room","Dining","Metro corridor"]
}

var manager: Node
var social: RefCounted
var config: Dictionary = {}
var shelters: Dictionary = {}
var rooms: Dictionary = {}
var rooms_by_shelter: Dictionary = {}
var blocked_doors: Dictionary = {}
var next_decision: Dictionary = {}
var agent_rng: Dictionary = {}
var pending_cognitive: Dictionary = {}
var generation := 0
var active := false
var completed := false
var started_at := 0.0
var ends_at := 0.0
var elapsed := 0.0
var day := 0
var rng := RandomNumberGenerator.new()
var cognitive_fallbacks := 0
var dynamics = preload("res://scripts/shelter_social.gd").new()
var storyteller = preload("res://scripts/environment_events.gd").shelter_storyteller()

func initialize(owner_social: RefCounted) -> void:
	social=owner_social; manager=social.manager
	config=JSON.parse_string(FileAccess.get_file_as_string("res://resources/shelter_life.json"))
	shelters.clear(); rooms.clear(); rooms_by_shelter.clear(); blocked_doors.clear(); next_decision.clear(); agent_rng.clear(); pending_cognitive.clear()
	generation+=1; completed=false; active=false; elapsed=0.0; day=0
	rng.seed=manager.seed_for("events")+67021
	for shelter in manager.shelters:
		if shelter.get("exists",false): _create_shelter(shelter)
	for agent in manager.agents:
		if agent.get("state","")!="SHELTERED" or agent.get("health",0)<=0: continue
		if not shelters.has(agent.get("shelter_id","")): continue
		_initialize_agent(agent)
	started_at=manager.elapsed_seconds
	ends_at=started_at+float(config.duration_days)*day_duration_seconds()
	active=manager.agents.any(func(a):return a.get("shelter_life_active",false))
	dynamics.initialize(self)
	storyteller.initialize(self)
	if active:
		social.emit_event("shelter.life_started","world",{"days":config.duration_days,"survivors":manager.agents.filter(func(a):return a.get("shelter_life_active",false)).size()})

func _create_shelter(shelter: Dictionary) -> void:
	var id:=str(shelter.id)
	var plan: Array=PLANS.get(id,PLANS["S1"])
	var total:=int(shelter.capacity)
	var center: Vector2=shelter.position
	var ids: Array[String]=[]
	var family_rooms: Array[String]=[]
	var data: Dictionary={"id":id,"truth":shelter,"rooms":[],"emergency":false,"fire":false,"power":shelter.get("operational",true),"air":shelter.get("operational",true),"water":true,"person_days":maxf(0,float(shelter.get("supply_level",0))),"supply_known":str(shelter.get("resources","Unknown"))!="Unknown","last_incident_day":-1,"day":0}
	for index in range(plan.size()):
		var item: Array=plan[index]; var rid:=id+":"+str(item[0]); var col:=int(item[2]); var row:=int(item[3])
		var room_capacity:=total
		var room_position:=center+Vector2(-110+col*80,-30+row*60)
		var room: Dictionary={"id":rid,"shelter_id":id,"room_type":str(item[1]),"grid":Vector2i(col,row),"position":room_position,"dimensions":Vector2(80,60),"capacity":room_capacity,"access":"FAMILY" if str(item[1])=="Family bedroom" else "PUBLIC","family_access":[],"doors":[],"furniture":[],"navigation_connections":[],"occupants":[],"reserved":0,"reserved_positions":{},"occupant_positions":{},"slots":[]}
		var slot_columns:=clampi(int(ceil(sqrt(float(room_capacity)*ROOM_W/ROOM_D))),1,18)
		var slot_rows:=int(ceil(float(room_capacity)/slot_columns))
		for slot in range(room_capacity):
			var slot_x:=slot%slot_columns; var slot_y:=int(slot/slot_columns)
			var spacing_x:=minf(11.0,ROOM_W*10.0/float(slot_columns))
			var spacing_y:=minf(11.0,ROOM_D*10.0/float(slot_rows))
			room.slots.append(room_position+Vector2((float(slot_x)-float(slot_columns-1)*.5)*spacing_x,(float(slot_y)-float(slot_rows-1)*.5)*spacing_y))
		rooms[rid]=room
		if str(item[1])=="Family bedroom": family_rooms.append(rid)
		if not rooms_by_shelter.has(id): rooms_by_shelter[id]=[]
		rooms_by_shelter[id].append(rid); ids.append(rid); data.rooms.append(rid)
	for rid in ids:
		var room: Dictionary=rooms[rid]
		for other_id in ids:
			if rid==other_id: continue
			var other: Dictionary=rooms[other_id]
			if (abs(room.grid.x-other.grid.x)==1 and room.grid.y==other.grid.y) or (abs(room.grid.y-other.grid.y)==1 and room.grid.x==other.grid.x):
				room.navigation_connections.append(other_id); room.doors.append({"to":other_id,"state":"OPEN"})
	shelters[id]=data
	if not family_rooms.is_empty():
		var family_ids: Array[String]=[]
		for family in social.families:
			if family.members.any(func(member_id):return manager.social.by_id.get(member_id,{}).get("shelter_id","")==id):
				family_ids.append(str(family.id))
		for family_index in range(family_ids.size()):
			var family_room: Dictionary=rooms[family_rooms[family_index%family_rooms.size()]]
			family_room.family_access.append(family_ids[family_index])

func _initialize_agent(agent: Dictionary) -> void:
	var social_ref:=social
	agent["hunger"]=clampf(float(agent.get("hunger",18)),0,100)
	agent["thirst"]=clampf(float(agent.get("thirst",18)),0,100)
	agent["fatigue"]=clampf(float(agent.get("fatigue",0)),0,100)
	agent["stress"]=clampf(float(agent.get("stress",agent.get("panic_level",0))),0,100)
	agent["sanitation_need"]=float(agent.get("sanitation_need",15))
	agent["shelter_life_active"]=true
	agent["shelter_clock_rate"]=routine_clock_rate()
	agent["shelter_room_id"]=""
	agent["shelter_target_room"]=""
	agent["shelter_route"]=PackedVector2Array()
	agent["shelter_route_index"]=0
	agent["shelter_target_slot"]=Vector2.INF
	agent["shelter_activity_state"]="MOVING"
	agent["current_activity"]="Entering shelter accommodation"
	agent["previous_activity"]="Impact response"
	agent["next_planned_activity"]="Rest and check on family"
	agent["activity_started_at"]=manager.elapsed_seconds
	agent["activity_duration_seconds"]=0.0
	agent["activity_ends_at"]=manager.elapsed_seconds
	agent["activity_remaining_seconds"]=0.0
	agent["current_activity_code"]=""
	agent["activity_animation"]="walking"
	agent["activity_interruptions"]=0
	agent["shelter_relationship_scores"]={}
	agent["shelter_event_assignment"]=""; agent["shelter_event_knowledge"]={}; agent["refusing_work_event"]=""
	var serial:=int(agent.get("population_index",0))
	var random:=RandomNumberGenerator.new(); random.seed=manager.seed_for("behavior")+serial*1237+6203; agent_rng[agent.id]=random
	var entry:=_room_of_type(agent.shelter_id,["Entrance","Secure entrance"])
	var target:=_select_room(agent,"SLEEP",entry)
	if target.is_empty(): target=entry
	if not target.is_empty(): _move_to_room(agent,target,true)
	else: agent.shelter_life_active=false
	next_decision[agent.id]=manager.elapsed_seconds+decision_interval_seconds()*fmod(float(serial),3.0)/3.0
	agent["next_planned_activity"]=_next_planned(agent)
	agent["current_goal"]="Move to assigned shelter sleeping area"

func _room_of_type(shelter_id: String, types: Array) -> String:
	for rid in rooms_by_shelter.get(shelter_id,[]):
		if rooms[rid].room_type in types: return rid
	return ""

func _has_skill(agent: Dictionary, skill: String) -> bool:
	var learned: Dictionary=agent.get("skills",{})
	if learned.get(skill,false) is bool and learned.get(skill,false): return true
	var job:=str(agent.get("occupation",""))
	match skill:
		"medical": return job=="Medical"
		"technical": return job=="Technician" or str(agent.get("specialization","")) in ["Technician","Engineer"]
		"security": return job=="Police" or job=="Crisis commander"
		"fire_safety": return job=="Fire"
		"emergency": return job in ["Civil protection","Crisis commander","Fire","Medical","Police"]
		"leadership": return job=="Crisis commander"
	return false

func routine_clock_rate() -> float:
	return maxf(1.0,float(social.config.get("routine_clock_rate",60.0)))

func day_duration_seconds() -> float:
	return 86400.0/routine_clock_rate()

func decision_interval_seconds(critical: bool = false) -> float:
	var key: String="critical_decision_interval_seconds" if critical else "decision_interval_seconds"
	return maxf(0.05,float(config.get(key,30.0 if critical else 300.0))/routine_clock_rate())

func _hour() -> float:
	return fposmod(float(config.day_start_hour)+maxf(0,manager.elapsed_seconds-started_at)*routine_clock_rate()/3600.0,24.0)

func _is_family_responsible(agent: Dictionary) -> bool:
	return agent.get("relationships",{}).values().has("child") or agent.get("occupation","")=="Family member"

func _family_needs(agent: Dictionary) -> float:
	var urgency:=0.0
	for other in manager.agents:
		if other.id==agent.id or other.family_id!=agent.family_id or other.get("shelter_id","")!=agent.get("shelter_id","") or other.health<=0: continue
		if agent.relationships.get(other.id,"") in ["child","parent","spouse","sibling"]:
			urgency=maxf(urgency,maxf(float(other.get("hunger",0)),maxf(float(other.get("stress",0))*.7,100.0-float(other.health))))
	return urgency

func _available_partner(agent: Dictionary, family_only: bool) -> Dictionary:
	var candidates: Array[Dictionary]=[]
	for other in manager.agents:
		if other.id==agent.id or other.get("shelter_id","")!=agent.get("shelter_id","") or other.health<=0: continue
		if family_only and (agent.family_id.is_empty() or other.family_id!=agent.family_id): continue
		candidates.append(other)
	if candidates.is_empty(): return {}
	var random: RandomNumberGenerator=agent_rng[agent.id]
	candidates.sort_custom(func(a,b):return agent.position.distance_squared_to(a.position)<agent.position.distance_squared_to(b.position))
	return candidates[0] if family_only else candidates[random.randi_range(0,candidates.size()-1)]

func choose_activity(agent: Dictionary) -> String:
	if not agent.get("shelter_life_active",false): return ""
	var refuge: Dictionary=shelters.get(agent.get("shelter_id",""),{})
	if refuge.is_empty(): return "REST"
	var hour:=_hour(); var windows: Dictionary=config.daily_windows
	var stress:=float(agent.stress); var fatigue:=float(agent.fatigue); var hunger:=float(agent.hunger); var thirst:=float(agent.thirst)
	var health:=float(agent.health); var personality:=str(agent.get("primary_personality",""))
	var scores: Dictionary={}
	scores["SLEEP"]=fatigue*.66+(35.0 if hour>=float(windows.sleep) or hour<float(windows.wake) else 0.0)+(45.0 if fatigue>=80 else 0.0)
	scores["EAT"]=hunger*.88+(22.0 if absf(hour-float(windows.breakfast))<1.0 or absf(hour-float(windows.lunch))<1.0 or absf(hour-float(windows.dinner))<1.0 else 0.0)
	scores["DRINK"]=thirst*1.05
	scores["REST"]=fatigue*.28+stress*.22
	scores["SANITATION"]=float(agent.sanitation_need)*.9
	scores["TREATMENT"]=(100-health)*1.2 if health<90 else 0.0
	scores["TALK_FAMILY"]=12.0+float(agent.get("empathy",50))*.12+float(agent.get("sociability",50))*.12+float(agent.get("family_concern",0))*.35
	scores["TALK_FRIEND"]=5.0+float(agent.get("sociability",50))*.18
	scores["MEET_NEIGHBORS"]=4.0+float(agent.get("sociability",50))*.14
	scores["ARGUE"]=maxf(0,stress-72)*.5 if personality=="AGGRESSIVE" else 0.0
	scores["RECONCILE"]=70.0 if _has_conflict(agent) else 0.0
	scores["GROUP_ACTIVITY"]=10.0+float(agent.get("sociability",50))*.1+(14.0 if hour>=float(windows.recreation) and hour<float(windows.sleep) else 0.0)
	scores["CLEAN"]=8.0+float(agent.get("cooperation",50))*.12
	scores["REPAIR_EQUIPMENT"]=10.0 if _has_skill(agent,"technical") else 0.0
	scores["ORGANIZE_SUPPLIES"]=35.0 if not refuge.supply_known else 7.0+float(agent.get("cooperation",50))*.08
	scores["PREPARE_MEAL"]=11.0+float(agent.get("cooperation",50))*.1+(8.0 if absf(hour-float(windows.dinner))<1.0 or absf(hour-float(windows.breakfast))<1.0 else 0.0)
	scores["MAINTAIN_GENERATOR"]=90.0 if not refuge.power else (11.0 if _has_skill(agent,"technical") else 0.0)
	scores["MAINTAIN_AIR"]=90.0 if not refuge.air else (9.0 if _has_skill(agent,"technical") else 0.0)
	scores["MAINTAIN_WATER"]=90.0 if not refuge.water else (8.0 if _has_skill(agent,"technical") else 0.0)
	scores["FIRE_SAFETY"]=90.0 if refuge.get("fire",false) and _has_skill(agent,"fire_safety") else (7.0 if _has_skill(agent,"fire_safety") else 0.0)
	scores["EMERGENCY_RESPONSE"]=90.0 if refuge.get("emergency",false) and _has_skill(agent,"emergency") else 0.0
	scores["DISTRIBUTE_RESOURCES"]=15.0+_family_needs(agent)*.18 if _is_family_responsible(agent) else 8.0
	scores["ASSIST_MEDICAL"]=90.0 if _has_skill(agent,"medical") and _has_injured_neighbor(agent) else (0.0 if not _has_skill(agent,"medical") else 8.0)
	scores["SECURITY"]=12.0 if _has_skill(agent,"security") else 0.0
	scores["CHILDCARE"]=14.0+_family_needs(agent)*.12 if _is_family_responsible(agent) else 0.0
	scores["READ"]=6.0+float(agent.get("adaptability",50))*.08 if agent.age>=8 else 0.0
	scores["EXERCISE"]=8.0+float(agent.get("adaptability",50))*.08 if health>40 and fatigue<75 else 0.0
	scores["REFLECT"]=8.0+stress*.08 if bool(config.reflection_allowed) else 0.0
	scores["OBSERVE"]=7.0+float(agent.get("skepticism",50))*.06
	scores["COMMUNICATE"]=8.0 if agent.get("has_phone",false) and agent.get("phone",{}).get("battery",0)>0 else 0.0
	scores["PLAY_DOG"]=20.0 if _has_dog(agent) else 0.0
	for activity in ["MAINTAIN_GENERATOR","MAINTAIN_AIR","MAINTAIN_WATER","FIRE_SAFETY","EMERGENCY_RESPONSE"]:
		if not storyteller.known_failure(agent,[activity]): scores[activity]=minf(12.0,float(scores[activity]))
	if hunger>90: scores.EAT+=40.0
	if thirst>88: scores.DRINK+=55.0
	if fatigue>88: scores.SLEEP+=55.0
	if health<35: scores.TREATMENT+=60.0
	if _is_family_responsible(agent): scores.DISTRIBUTE_RESOURCES+=minf(25,_family_needs(agent)*.4)
	if hour>=float(windows.work_start) and hour<17.0:
		if _has_skill(agent,"technical"): scores.REPAIR_EQUIPMENT+=6.0
		if _has_skill(agent,"medical"): scores.ASSIST_MEDICAL+=7.0
		if _has_skill(agent,"security"): scores.SECURITY+=5.0
	if hour>=float(windows.rest) and hour<float(windows.recreation): scores.REST+=8.0
	if hour>=float(windows.social) and hour<float(windows.sleep): scores.GROUP_ACTIVITY+=8.0
	if personality=="FAMILY-ORIENTED": scores.TALK_FAMILY+=14.0; scores.CHILDCARE+=8.0
	if personality=="COOPERATIVE" or float(agent.get("cooperation",0))>75: scores.CLEAN+=7.0; scores.DISTRIBUTE_RESOURCES+=5.0
	if personality in ["OVERWHELMED","DESPAIRING","PANICKED"]: scores.REST+=stress*.18; scores.REFLECT+=stress*.05
	if not refuge.supply_known: scores.ORGANIZE_SUPPLIES+=20.0
	if float(refuge.person_days)<=0.0: scores.EAT=0.0; scores.PREPARE_MEAL=0.0
	if not refuge.water: scores.DRINK=0.0
	if not _is_family_responsible(agent): scores.CHILDCARE=0.0
	if not str(agent.get("care_target","")).is_empty(): scores.CHILDCARE=maxf(float(scores.CHILDCARE),40.0)
	var social_task:=str(agent.get("shelter_social_task",""))
	if social_task in scores and int(agent.get("age",30))>=18: scores[social_task]+=12.0
	if _available_partner(agent,true).is_empty(): scores.TALK_FAMILY=0.0; scores.ARGUE=0.0; scores.RECONCILE=0.0
	if _available_partner(agent,false).is_empty(): scores.TALK_FRIEND=0.0; scores.MEET_NEIGHBORS=0.0
	if refuge.truth.get("structural_state","")=="DESTROYED": scores.SECURITY=0.0
	var best: String="REST"; var highest: float=-INF
	for activity in scores:
		var score:=float(scores[activity])
		if not _activity_allowed(agent,activity,refuge): continue
		var target:=_select_room(agent,activity,str(agent.get("shelter_room_id","")))
		if target.is_empty(): continue
		# Stable individual variation avoids synchronized schedules without dominating urgent needs.
		var rand: RandomNumberGenerator=agent_rng[agent.id]
		score+=rand.randf_range(-3.0,3.0)
		if score>highest: highest=score; best=activity
	return best

func _activity_allowed(agent: Dictionary, activity: String, refuge: Dictionary) -> bool:
	if activity not in ROOM_TYPES: return false
	if not str(agent.get("refusing_work_event","")).is_empty() and activity in ["CLEAN","REPAIR_EQUIPMENT","MAINTAIN_GENERATOR","MAINTAIN_AIR","MAINTAIN_WATER","PREPARE_MEAL","DISTRIBUTE_RESOURCES","SECURITY"]: return false
	if int(agent.get("age",30))<18 and activity in ["CHILDCARE","SECURITY","REPAIR_EQUIPMENT","MAINTAIN_GENERATOR","MAINTAIN_AIR","MAINTAIN_WATER","FIRE_SAFETY","EMERGENCY_RESPONSE","ASSIST_MEDICAL","DISTRIBUTE_RESOURCES"]: return false
	if activity=="MAINTAIN_GENERATOR" or activity=="REPAIR_EQUIPMENT": return _has_skill(agent,"technical")
	if activity=="MAINTAIN_AIR": return _has_skill(agent,"technical")
	if activity=="MAINTAIN_WATER": return _has_skill(agent,"technical")
	if activity=="FIRE_SAFETY": return _has_skill(agent,"fire_safety")
	if activity=="EMERGENCY_RESPONSE": return _has_skill(agent,"emergency")
	if activity=="ASSIST_MEDICAL" or activity=="TREATMENT": return _has_skill(agent,"medical") or activity=="TREATMENT"
	if activity=="SECURITY": return _has_skill(agent,"security")
	if activity=="PLAY_DOG": return _has_dog(agent)
	if activity=="REFLECT": return bool(config.reflection_allowed)
	if activity=="ARGUE": return float(agent.get("stress",0))>=65.0 and not _available_partner(agent,true).is_empty()
	if activity=="RECONCILE": return _has_conflict(agent)
	if activity=="TALK_FAMILY": return not _available_partner(agent,true).is_empty()
	if activity in ["TALK_FRIEND","MEET_NEIGHBORS"]: return not _available_partner(agent,false).is_empty()
	return true

func _has_injured_neighbor(agent: Dictionary) -> bool:
	for other in manager.agents:
		if other.id!=agent.id and other.get("shelter_id","")==agent.get("shelter_id","") and other.health>0 and other.health<90: return true
	return false

func _has_dog(agent: Dictionary) -> bool:
	for dog in social.companions:
		if dog.health>0 and dog.owner_id==agent.id and dog.get("shelter_id","")==agent.get("shelter_id",""): return true
	return false

func _has_conflict(agent: Dictionary) -> bool:
	for dispute in dynamics.conflicts:
		if dispute.status=="OPEN" and agent.id in dispute.members: return true
	for family in social.families:
		if agent.id in family.members and family.get("active_conflict",false): return true
	return false

func _select_room(agent: Dictionary, activity: String, from_room: String = "") -> String:
	var shelter_id:=str(agent.get("shelter_id","")); var permitted: Array=ROOM_TYPES.get(activity,[])
	var options: Array[String]=[]
	for rid in rooms_by_shelter.get(shelter_id,[]):
		var room: Dictionary=rooms[rid]
		if room.room_type not in permitted or room.get("functional",true)==false: continue
		if room.get("access","PUBLIC")=="FAMILY" and (str(agent.get("family_id","")).is_empty() or agent.get("family_id","") not in room.get("family_access",[])): continue
		if room.room_type in ["Security","Checkpoint","Control","Operations"] and activity not in ["SECURITY","EMERGENCY_RESPONSE","OBSERVE","COMMUNICATE"]: continue
		var already_here: bool=room.occupants.has(agent.id)
		if int(room.occupants.size()+room.reserved-(1 if already_here else 0))>=int(room.capacity): continue
		if not _reachable(from_room,rid): continue
		options.append(rid)
	if options.is_empty(): return ""
	options.sort_custom(func(a,b):return _room_distance(from_room,a)<_room_distance(from_room,b))
	return options[0]

func _room_distance(from_room: String, to_room: String) -> int:
	if from_room.is_empty(): return 0
	var route:=_room_path(from_room,to_room)
	return route.size()

func _reachable(from_room: String,to_room: String) -> bool:
	return from_room.is_empty() or from_room==to_room or not _room_path(from_room,to_room).is_empty()

func _room_path(from_room: String,to_room: String) -> Array[String]:
	var queue: Array[String]=[from_room]; var previous: Dictionary={from_room:""}
	while not queue.is_empty():
		var current: String=queue.pop_front()
		if current==to_room: break
		for next in rooms.get(current,{}).get("navigation_connections",[]):
			if previous.has(next) or blocked_doors.has(_door_key(current,next)): continue
			previous[next]=current; queue.append(next)
	if not previous.has(to_room): return []
	var route: Array[String]=[]; var step:=to_room
	while step!="": route.push_front(step); step=previous[step]
	return route

func _door_key(a: String,b: String) -> String:
	return a+"|"+b if a<b else b+"|"+a

func _move_to_room(agent: Dictionary, target: String, from_entrance: bool = false) -> bool:
	if not rooms.has(target): return false
	var current:=str(agent.get("shelter_room_id",""))
	if current==target: return true
	var previous_target:=str(agent.get("shelter_target_room",""))
	_release_reservation(agent)
	var refuge: Dictionary=shelters.get(agent.get("shelter_id",""),{})
	var start:=current if not current.is_empty() else previous_target if not previous_target.is_empty() else _room_of_type(str(agent.shelter_id),["Entrance","Secure entrance"])
	var path:=_room_path(start,target)
	if path.is_empty(): return false
	var room: Dictionary=rooms[target]
	if room.occupants.size()+room.reserved>=room.capacity: return false
	room.reserved+=1; agent.shelter_target_room=target; agent.shelter_target_slot=_slot_for(room,agent.id); room.reserved_positions[agent.id]=agent.shelter_target_slot
	var points:=PackedVector2Array()
	if from_entrance:
		points.append(room_entry_position(str(agent.shelter_id)))
		for index in range(maxi(0,path.size()-1)):
			var first: Dictionary=rooms[path[index]]; var second: Dictionary=rooms[path[index+1]]
			points.append((first.position+second.position)*.5); points.append(second.position)
	else:
		if current.is_empty() and not previous_target.is_empty():
			var old_route: PackedVector2Array=agent.get("shelter_route",PackedVector2Array())
			for route_index in range(int(agent.get("shelter_route_index",0)),old_route.size()): points.append(old_route[route_index])
			points.append(rooms[previous_target].position)
		for index in range(maxi(0,path.size()-1)):
			var first: Dictionary=rooms[path[index]]; var second: Dictionary=rooms[path[index+1]]
			points.append((first.position+second.position)*.5); points.append(second.position)
	points.append(agent.shelter_target_slot)
	agent.shelter_route=points; agent.shelter_route_index=0; agent.shelter_activity_state="MOVING"
	if not current.is_empty():
		rooms[current].occupants.erase(agent.id); rooms[current].occupant_positions.erase(agent.id)
	agent.shelter_room_id=""
	if current.is_empty() and not refuge.is_empty(): agent.shelter_activity_animation="walking"
	return true

func room_entry_position(shelter_id: String) -> Vector2:
	var entry:=_room_of_type(shelter_id,["Entrance","Secure entrance"])
	return rooms[entry].position if not entry.is_empty() else shelters[shelter_id].truth.position

func _slot_for(room: Dictionary,agent_id: String) -> Vector2:
	var used: Dictionary={}
	for point in room.occupant_positions.values(): used[point]=true
	for point in room.reserved_positions.values(): used[point]=true
	for index in range(room.slots.size()):
		var point: Vector2=room.slots[index]
		if not used.has(point): return point
	return room.position

func _start_activity(agent: Dictionary, activity: String, duration_override: float = -1.0) -> void:
	var target:=_select_room(agent,activity,str(agent.get("shelter_room_id","")))
	var incident: Dictionary=storyteller.find(str(agent.get("shelter_event_assignment","")))
	if incident.get("active_status",false) and storyteller.config.events[incident.event_type].activity==activity: target=storyteller.response_room(incident,agent)
	if activity=="CHILDCARE":
		var child: Dictionary=social.by_id.get(agent.get("care_target",""),{})
		var child_room:=str(child.get("shelter_room_id",""))
		if not child_room.is_empty() and child.get("shelter_id","")==agent.shelter_id and _reachable(str(agent.get("shelter_room_id","")),child_room): target=child_room
	if target.is_empty(): return
	var previous:=str(agent.get("current_activity",""))
	if previous not in ["",activity,"Entering shelter accommodation"]: agent.previous_activity=previous
	var partner: Dictionary={}
	if activity in ["TALK_FAMILY","TALK_FRIEND","MEET_NEIGHBORS","ARGUE","RECONCILE"]: partner=_available_partner(agent,activity in ["TALK_FAMILY","ARGUE","RECONCILE"])
	if not partner.is_empty(): agent.shelter_activity_partner=partner.id
	else: agent.shelter_activity_partner=""
	var data:=_activity_info(activity)
	agent.current_activity=data.label
	agent.current_activity_code=activity
	agent.activity_animation=data.animation
	agent.next_planned_activity=_next_planned(agent)
	agent.current_goal=data.label
	var durations: Dictionary=config.activity_durations_minutes
	var duration: float=duration_override if duration_override>0 else float(durations.get(data.duration,30))*60.0/routine_clock_rate()*agent_rng[agent.id].randf_range(.8,1.2)
	agent.activity_duration_seconds=duration; agent.activity_remaining_seconds=duration; agent.activity_started_at=manager.elapsed_seconds
	agent.activity_ends_at=manager.elapsed_seconds+duration
	if str(agent.get("shelter_room_id",""))!=target:
		if _move_to_room(agent,target):
			agent.activity_remaining_seconds=duration
		else: agent.activity_remaining_seconds=minf(60,duration)
	else: agent.shelter_activity_state="ACTIVE"
	if partner.has("id") and activity in ["TALK_FAMILY","TALK_FRIEND","MEET_NEIGHBORS","GROUP_ACTIVITY"]:
		partner.shelter_activity_invite={"by":agent.id,"activity":activity,"room":target,"expires":manager.elapsed_seconds+900}
	social.emit_event("shelter.activity_started",agent.id,{"shelter_id":agent.shelter_id,"room_id":target,"activity":activity,"previous":previous,"duration_seconds":duration})

func _activity_info(activity: String) -> Dictionary:
	var table: Dictionary={
		"SLEEP":{"label":"Sleeping","animation":"sleep","duration":"sleep"},"EAT":{"label":"Eating","animation":"eating","duration":"meal"},"DRINK":{"label":"Drinking","animation":"drinking","duration":"drink"},"REST":{"label":"Resting","animation":"sitting","duration":"rest"},"SANITATION":{"label":"Using sanitation facilities","animation":"walking","duration":"sanitation"},"TREATMENT":{"label":"Receiving medical treatment","animation":"sitting","duration":"treatment"},"TALK_FAMILY":{"label":"Talking with family","animation":"talking","duration":"conversation"},"TALK_FRIEND":{"label":"Talking with a friend","animation":"talking","duration":"conversation"},"MEET_NEIGHBORS":{"label":"Meeting a survivor","animation":"talking","duration":"conversation"},"ARGUE":{"label":"Arguing","animation":"talking","duration":"conversation"},"RECONCILE":{"label":"Reconciling","animation":"talking","duration":"conversation"},"GROUP_ACTIVITY":{"label":"Group activity","animation":"talking","duration":"group"},"CLEAN":{"label":"Cleaning shared rooms","animation":"cleaning","duration":"work"},"REPAIR_EQUIPMENT":{"label":"Repairing equipment","animation":"repairing","duration":"work"},"ORGANIZE_SUPPLIES":{"label":"Organizing supplies","animation":"working","duration":"work"},"PREPARE_MEAL":{"label":"Preparing a meal","animation":"cooking","duration":"work"},"MAINTAIN_GENERATOR":{"label":"Maintaining the generator","animation":"repairing","duration":"work"},"MAINTAIN_AIR":{"label":"Maintaining air filtration","animation":"repairing","duration":"work"},"DISTRIBUTE_RESOURCES":{"label":"Distributing resources","animation":"working","duration":"work"},"ASSIST_MEDICAL":{"label":"Assisting medical staff","animation":"helping","duration":"work"},"SECURITY":{"label":"Security patrol","animation":"walking","duration":"work"},"CHILDCARE":{"label":"Caring for family","animation":"helping","duration":"conversation"},"READ":{"label":"Reading","animation":"reading","duration":"personal"},"EXERCISE":{"label":"Exercising","animation":"exercise","duration":"exercise"},"REFLECT":{"label":"Prayer or reflection","animation":"sitting","duration":"personal"},"OBSERVE":{"label":"Observing the shelter","animation":"standing","duration":"personal"},"COMMUNICATE":{"label":"Using communication equipment","animation":"communicating","duration":"personal"},"PLAY_DOG":{"label":"Playing with the German Shepherd","animation":"talking","duration":"conversation"}}
	table["MAINTAIN_WATER"]={"label":"Maintaining water systems","animation":"repairing","duration":"work"}
	table["FIRE_SAFETY"]={"label":"Fire prevention and equipment checks","animation":"repairing","duration":"work"}
	table["EMERGENCY_RESPONSE"]={"label":"Responding to a shelter emergency","animation":"helping","duration":"work"}
	return table.get(activity,table.REST)

func _next_planned(agent: Dictionary) -> String:
	var hour:=_hour(); var windows: Dictionary=config.daily_windows
	if hour>=float(windows.sleep) or hour<float(windows.wake): return "Wake, drink and check on family"
	if hour<float(windows.work_start): return "Breakfast and morning sanitation"
	if hour<float(windows.lunch): return "Work, maintenance or family care"
	if hour<float(windows.rest): return "Lunch and rest"
	if hour<float(windows.recreation): return "Rest or social time"
	if hour<float(windows.dinner): return "Recreation, exercise or reading"
	if hour<float(windows.social): return "Dinner and resource distribution"
	return "Social time, then sleep"

func _release_reservation(agent: Dictionary) -> void:
	var target:=str(agent.get("shelter_target_room",""))
	if target.is_empty() or not rooms.has(target): return
	var room: Dictionary=rooms[target]
	room.reserved=maxi(0,int(room.reserved)-1); room.reserved_positions.erase(agent.id)
	agent.shelter_target_room=""; agent.shelter_target_slot=Vector2.INF

func _arrive_room(agent: Dictionary) -> void:
	var target:=str(agent.get("shelter_target_room",""))
	if not rooms.has(target): return
	var room: Dictionary=rooms[target]
	room.reserved=maxi(0,int(room.reserved)-1); room.reserved_positions.erase(agent.id)
	room.occupants.append(agent.id); room.occupant_positions[agent.id]=agent.shelter_target_slot
	agent.shelter_room_id=target; agent.shelter_target_room=""; agent.shelter_route=PackedVector2Array(); agent.shelter_route_index=0
	agent.position=agent.shelter_target_slot; agent.previous_position=agent.position; agent.transport_height=8.3
	agent.shelter_activity_state="ACTIVE"; agent.activity_started_at=manager.elapsed_seconds
	agent.activity_ends_at=manager.elapsed_seconds+float(agent.get("activity_remaining_seconds",0))
	if agent.get("current_activity_code","")=="": _start_activity(agent,choose_activity(agent))

func tick(seconds: float) -> void:
	if not active or completed or seconds<=0: return
	elapsed=maxf(0,manager.elapsed_seconds-started_at+seconds)
	var day_seconds:=day_duration_seconds()
	var target_day=mini(int(config.duration_days),int(floor(elapsed/day_seconds)))
	while day<target_day:
		day+=1; _daily_shelter_events(day)
	for agent in manager.agents:
		if not agent.get("shelter_life_active",false) or agent.health<=0: continue
		if agent.get("emergency_exit_active",false): continue
		agent.previous_position=agent.position
		_update_needs(agent,seconds)
		if agent.shelter_activity_state=="MOVING":
			_advance_room_route(agent,seconds)
			if _critical_need(agent) and manager.elapsed_seconds>=float(next_decision.get(agent.id,0)):
				next_decision[agent.id]=manager.elapsed_seconds+decision_interval_seconds(true)
				_decide(agent,true)
			continue
		if agent.shelter_activity_state=="ACTIVE":
			agent.activity_remaining_seconds=maxf(0,float(agent.activity_remaining_seconds)-seconds)
			if agent.activity_remaining_seconds<=0.0001: _complete_activity(agent)
		var critical:=_critical_need(agent)
		var interval:=decision_interval_seconds(critical)
		if manager.elapsed_seconds>=float(next_decision.get(agent.id,manager.elapsed_seconds)) or (critical and agent.get("activity_remaining_seconds",0)>interval):
			next_decision[agent.id]=manager.elapsed_seconds+interval
			_decide(agent,critical)
	dynamics.tick(minf(seconds,maxf(0,float(config.duration_days)*day_seconds-(elapsed-seconds))))
	storyteller.tick(minf(seconds,maxf(0,float(config.duration_days)*day_seconds-(elapsed-seconds))))
	if elapsed>=float(config.duration_days)*day_seconds:
		completed=true; active=false

func _advance_room_route(agent: Dictionary, seconds: float) -> void:
	var route: PackedVector2Array=agent.shelter_route
	var budget:=maxf(.1,float(agent.get("walk_speed",agent.get("movement_speed",1.2))))*seconds
	while int(agent.shelter_route_index)<route.size() and budget>0:
		var point: Vector2=route[agent.shelter_route_index]; var distance: float=agent.position.distance_to(point); var step:=minf(distance,budget)
		agent.position=agent.position.move_toward(point,step); budget-=step
		if distance<=step+.001: agent.shelter_route_index+=1
		else: break
	if agent.has("transfer_entry_length"):
		var proxy: Dictionary={"position":agent.position,"route":agent.shelter_route,"route_index":agent.shelter_route_index}
		agent.transport_height=8.3*clampf(1.0-preload("res://scripts/road_routes.gd").remaining_distance(proxy)/float(agent.transfer_entry_length),0,1)
		if int(agent.shelter_route_index)>=route.size(): agent.erase("transfer_entry_length")
	if int(agent.shelter_route_index)>=route.size(): _arrive_room(agent)

func advance_emergency_exit(agent: Dictionary, seconds: float) -> bool:
	var entry: String=_room_of_type(agent.shelter_id,["Entrance","Secure entrance"])
	if entry.is_empty(): return false
	if not agent.get("emergency_exit_active",false):
		agent.emergency_exit_active=true; agent.current_activity_code="EMERGENCY_EGRESS"
		agent.current_activity="Evacuating unsafe shelter"; agent.activity_animation="walking"
		if not _move_to_room(agent,entry): agent.emergency_exit_active=false; return false
	if agent.get("shelter_room_id","")!=entry:
		_advance_room_route(agent,seconds)
		return false
	if not agent.has("portal_exit_route"):
		agent.portal_exit_route=PackedVector2Array([agent.position,rooms[entry].position,shelters[agent.shelter_id].truth.exit_position])
		agent.portal_exit_index=1; agent.portal_exit_length=maxf(.01,preload("res://scripts/road_routes.gd").length(agent.portal_exit_route))
		agent.portal_exit_height=float(agent.get("transport_height",8.3))
	var proxy: Dictionary={"position":agent.position,"route":agent.portal_exit_route,"route_index":agent.portal_exit_index,"movement_speed":float(agent.walk_speed)}
	agent.previous_position=agent.position
	var moved: Dictionary=preload("res://scripts/road_routes.gd").move(proxy,seconds)
	agent.position=proxy.position; agent.portal_exit_index=proxy.route_index
	agent.transport_height=float(agent.portal_exit_height)*preload("res://scripts/road_routes.gd").remaining_distance(proxy)/float(agent.portal_exit_length)
	if not moved.arrived: return false
	rooms[entry].occupants.erase(agent.id); rooms[entry].occupant_positions.erase(agent.id)
	agent.shelter_life_active=false; agent.emergency_exit_active=false; agent.shelter_activity_state="INACTIVE"; agent.shelter_room_id=""; agent.transport_height=0.0
	agent.erase("portal_exit_route"); agent.erase("portal_exit_index")
	return true

func accept_transfer(agent: Dictionary) -> void:
	var relationships: Dictionary=agent.get("shelter_relationship_scores",{}).duplicate()
	var interruptions: int=int(agent.get("activity_interruptions",0))
	_initialize_agent(agent)
	dynamics.register(agent)
	agent.transfer_entry_length=maxf(.01,preload("res://scripts/road_routes.gd").remaining_distance({"position":agent.position,"route":agent.shelter_route,"route_index":agent.shelter_route_index}))
	agent.shelter_relationship_scores=relationships; agent.activity_interruptions=interruptions+1

func _update_needs(agent: Dictionary, seconds: float) -> void:
	var hourly: Dictionary=config.need_rates_per_hour; var hours:=seconds*routine_clock_rate()/3600.0
	agent.hunger=clampf(float(agent.hunger)+float(hourly.hunger)*hours,0,100)
	var refuge: Dictionary=shelters.get(agent.shelter_id,{})
	if refuge.get("water",true): agent.thirst=clampf(float(agent.thirst)+float(hourly.thirst)*hours,0,100)
	else: agent.thirst=clampf(float(agent.thirst)+float(hourly.thirst)*hours*1.5,0,100)
	agent.sanitation_need=clampf(float(agent.sanitation_need)+3.5*hours,0,100)
	if agent.get("current_activity_code","")=="SLEEP": agent.fatigue=maxf(0,float(agent.fatigue)+float(hourly.fatigue_sleep)*hours)
	elif agent.get("current_activity_code","")=="REST": agent.fatigue=maxf(0,float(agent.fatigue)+float(hourly.fatigue_rest)*hours)
	else: agent.fatigue=clampf(float(agent.fatigue)+float(hourly.fatigue_awake)*hours,0,100)
	if agent.get("current_activity_code","") not in ["TALK_FAMILY","TALK_FRIEND","MEET_NEIGHBORS","GROUP_ACTIVITY","EXERCISE","REFLECT"]: agent.stress=clampf(float(agent.stress)+float(hourly.stress_idle)*hours,0,100)
	if float(agent.hunger)>=85: agent.health=maxf(0,float(agent.health)+float(hourly.health_hunger_critical)*hours)
	if float(agent.thirst)>=85: agent.health=maxf(0,float(agent.health)+float(hourly.health_thirst_critical)*hours)
	agent.needs={"hunger":float(agent.hunger)/100.0,"thirst":float(agent.thirst)/100.0,"fatigue":float(agent.fatigue)/100.0,"stress":float(agent.stress)/100.0,"health":float(agent.health)/100.0,"sanitation":float(agent.sanitation_need)/100.0}
	if agent.health<=0:
		agent.survival_status="DEAD"; agent.shelter_life_active=false; agent.current_activity="Deceased"; agent.activity_animation="lying"; agent.shelter_activity_state="INACTIVE"

func _critical_need(agent: Dictionary) -> bool:
	return float(agent.thirst)>=88 or float(agent.hunger)>=90 or float(agent.fatigue)>=90 or float(agent.health)<35 or float(agent.sanitation_need)>=90

func _decide(agent: Dictionary, critical: bool) -> void:
	if agent.health<=0: return
	var incident: Dictionary=storyteller.find(str(agent.get("shelter_event_assignment","")))
	if not critical and incident.get("active_status",false) and storyteller.request_response(incident.event_id,agent): return
	var invite: Dictionary=agent.get("shelter_activity_invite",{})
	if not invite.is_empty() and invite.get("expires",0)>manager.elapsed_seconds and not critical:
		var invited:=str(invite.get("activity",""))
		if invited in ["TALK_FAMILY","TALK_FRIEND","MEET_NEIGHBORS","GROUP_ACTIVITY"] and _activity_allowed(agent,invited,shelters[agent.shelter_id]):
			agent.shelter_activity_invite={}; _start_activity(agent,invited); return
	var selected:=choose_activity(agent)
	if selected.is_empty(): return
	var current:=str(agent.get("current_activity_code",""))
	if current==selected and float(agent.get("activity_remaining_seconds",0))>0: return
	if not critical and float(agent.get("activity_remaining_seconds",0))>0: return
	if current!="" and float(agent.get("activity_remaining_seconds",0))>0:
		agent.previous_activity=str(agent.current_activity); agent.activity_interruptions=int(agent.get("activity_interruptions",0))+1
		social.emit_event("shelter.activity_interrupted",agent.id,{"activity":current,"reason":selected,"shelter_id":agent.shelter_id})
	agent["rule_decision_count"]=int(agent.get("rule_decision_count",0))+1
	_start_activity(agent,selected)
	_request_complex_decision(agent,selected)

func _complete_activity(agent: Dictionary) -> void:
	var code:=str(agent.get("current_activity_code","")); var effects: Dictionary=config.activity_effects; var refuge: Dictionary=shelters.get(agent.shelter_id,{})
	var incident: Dictionary=storyteller.find(str(agent.get("shelter_event_assignment","")))
	if incident.get("active_status",false) and code==storyteller.config.events[incident.event_type].activity:
		# Actual work advances at the storyteller's fixed cadence, never by clicking
		# through activity completions or by writing an infrastructure flag.
		agent.activity_remaining_seconds=300.0/routine_clock_rate(); return
	match code:
		"SLEEP": agent.fatigue=maxf(0,float(agent.fatigue)-45)
		"EAT":
			var ration:=float(effects.meal_person_days); var served:=minf(ration,float(refuge.person_days)); refuge.person_days=maxf(0,float(refuge.person_days)-served)
			if served>0: agent.hunger=maxf(0,float(agent.hunger)+float(effects.meal_hunger)*(served/ration))
		"DRINK":
			if refuge.water:
				var amount:=minf(.5,float(refuge.get("water_liters",.5)))
				if refuge.has("water_liters"): refuge.water_liters=maxf(0,refuge.water_liters-amount)
				agent.thirst=maxf(0,float(agent.thirst)+float(effects.drink_thirst)*amount/.5)
				if refuge.has("water_liters") and refuge.water_liters<=0: refuge.water=false
		"REST": agent.fatigue=maxf(0,float(agent.fatigue)-12); agent.stress=maxf(0,float(agent.stress)-2)
		"SANITATION": agent.sanitation_need=0.0
		"TREATMENT":
			if float(refuge.get("medical_supplies",0))>=.25:
				refuge.medical_supplies-=.25; agent.health=minf(100,float(agent.health)+float(effects.medical_health)); agent.stress=maxf(0,float(agent.stress)-2)
		"TALK_FAMILY","TALK_FRIEND","MEET_NEIGHBORS": _socialize(agent,code)
		"ARGUE": _argue(agent)
		"RECONCILE": _reconcile(agent)
		"GROUP_ACTIVITY": _group_activity(agent)
		"MAINTAIN_GENERATOR","REPAIR_EQUIPMENT": _repair(agent,"power")
		"MAINTAIN_AIR": _repair(agent,"air")
		"MAINTAIN_WATER": _repair(agent,"water")
		"FIRE_SAFETY": _handle_fire(agent)
		"EMERGENCY_RESPONSE": _handle_emergency(agent)
		"SECURITY": _restore_security(agent)
		"ORGANIZE_SUPPLIES": _discover_supplies(agent,refuge)
		"ASSIST_MEDICAL": _assist_patient(agent)
		"DISTRIBUTE_RESOURCES": _distribute(agent,refuge)
		"CHILDCARE": _care_for_child(agent)
		"EXERCISE": agent.fatigue=minf(100,float(agent.fatigue)+10); agent.stress=maxf(0,float(agent.stress)-float(effects.recreation_stress))
		"READ","REFLECT": agent.stress=maxf(0,float(agent.stress)-float(effects.reflect_stress))
		"PLAY_DOG": _play_with_dog(agent)
		"COMMUNICATE":
			var partner:=_available_partner(agent,false)
			dynamics.converse(agent,partner)
	if refuge.has("truth") and not refuge.truth.is_empty():
		refuge.truth["power_available"]=refuge.power; refuge.truth["air_available"]=refuge.air; refuge.truth["water_available"]=refuge.water
	agent.previous_activity=str(agent.current_activity); agent.current_activity_code=""; agent.current_activity="Waiting for next activity decision"; agent.activity_animation="standing"; agent.activity_remaining_seconds=0.0; agent.shelter_activity_state="ACTIVE"
	next_decision[agent.id]=manager.elapsed_seconds
	social.emit_event("shelter.activity_completed",agent.id,{"activity":code,"room_id":agent.shelter_room_id,"duration_seconds":agent.activity_duration_seconds})

func _socialize(agent: Dictionary, code: String) -> void:
	var partner: Dictionary=manager.social.by_id.get(agent.get("shelter_activity_partner",""),{})
	if partner.is_empty() or partner.get("shelter_room_id","")!=agent.get("shelter_room_id",""):
		agent.stress=maxf(0,float(agent.stress)-1.0); return
	dynamics.interact(agent,partner,"conversation")
	dynamics.converse(agent,partner)
	partner.stress=maxf(0,float(partner.stress)+float(config.activity_effects.social_stress))
	agent.stress=maxf(0,float(agent.stress)+float(config.activity_effects.social_stress))
	if code=="TALK_FAMILY" and agent.get("relationships",{}).get(partner.id,"") in ["parent","child"]:
		partner.stress=maxf(0,float(partner.stress)-2.0); partner.family_support_count=int(partner.get("family_support_count",0))+1

func _argue(agent: Dictionary) -> void:
	var partner: Dictionary=manager.social.by_id.get(agent.get("shelter_activity_partner",""),{})
	if partner.is_empty(): return
	dynamics.open_conflict(agent,partner,"personal_disagreement")
	for family in social.families:
		if agent.id in family.members and partner.id in family.members:
			family.active_conflict=true; family.conflict_pair=[agent.id,partner.id]; family.conflict_started=manager.elapsed_seconds
			agent.stress=clampf(float(agent.stress)+8,0,100); partner.stress=clampf(float(partner.stress)+5,0,100)
			social.emit_event("family.conflict",family.id,{"members":[agent.id,partner.id]}); return

func _reconcile(agent: Dictionary) -> void:
	for dispute in dynamics.conflicts:
		if dispute.status=="OPEN" and agent.id in dispute.members: dynamics.resolve(dispute.id,agent)
	for family in social.families:
		if agent.id in family.members and family.get("active_conflict",false):
			family.active_conflict=false; family.erase("conflict_pair"); family.reconciliations=int(family.get("reconciliations",0))+1
			for id in family.members:
				if manager.social.by_id[id].get("shelter_id","")==agent.shelter_id: manager.social.by_id[id].stress=maxf(0,float(manager.social.by_id[id].stress)-8)
			social.emit_event("family.reconciled",family.id,{"agent_id":agent.id}); return

func _group_activity(agent: Dictionary) -> void:
	var room: Dictionary=rooms.get(agent.get("shelter_room_id",""),{})
	for id in room.get("occupants",[]):
		var member: Dictionary=manager.social.by_id[id]
		member.stress=maxf(0,float(member.stress)-2.0); member.social_group_count=int(member.get("social_group_count",0))+1
		dynamics.interact(agent,member,"organize")

func _repair(agent: Dictionary, system: String) -> void:
	if not _has_skill(agent,"technical"): return
	if int(agent.get("age",30))<18: return
	for event in storyteller.active(agent.shelter_id):
		if storyteller.config.events[event.event_type].activity==agent.get("current_activity_code",""):
			storyteller.observe(); storyteller.request_response(event.event_id,agent); return
	var refuge: Dictionary=shelters[agent.shelter_id]; refuge[system]=true
	refuge["maintenance_actions"]=int(refuge.get("maintenance_actions",0))+1
	if system=="water" and float(refuge.get("water_liters",1))<=0: refuge.water=false
	if refuge.has("storyteller_base"): refuge.storyteller_base[system]=true
	if storyteller.conditions.has(agent.shelter_id) and storyteller.conditions[agent.shelter_id].has(system): storyteller.conditions[agent.shelter_id][system]=minf(100,float(storyteller.conditions[agent.shelter_id][system])+5)
	for other in dynamics.residents(agent.shelter_id):
		dynamics.interact(agent,other,"repair")
	if system=="power": refuge.truth["power_available"]=true
	if system=="air": refuge.truth["air_available"]=true
	if system=="water": refuge.truth["water_available"]=refuge.water
	social.emit_event("shelter.system_repaired",agent.id,{"shelter_id":agent.shelter_id,"system":system})

func _discover_supplies(agent: Dictionary,refuge: Dictionary) -> void:
	if not refuge.supply_known:
		refuge.supply_known=true; agent.shelter_known_person_days=refuge.person_days
		agent.personal_memory.append({"time":manager.elapsed_seconds,"text":"I inspected the stores; supplies were found."})
		social.emit_event("shelter.supplies_discovered",agent.id,{"shelter_id":agent.shelter_id,"description":"Initial stores inspected"})

func _assist_patient(agent: Dictionary) -> void:
	var refuge: Dictionary=shelters.get(agent.get("shelter_id",""),{})
	if float(refuge.get("medical_supplies",0))<.25: return
	var patients: Array=manager.agents.filter(func(other):return dynamics.together(agent,other) and other.health<90)
	if patients.is_empty(): return
	refuge.medical_supplies-=.25
	patients.sort_custom(func(a,b):return a.health<b.health)
	patients[0].health=minf(100,float(patients[0].health)+10); patients[0].last_treatment_at=manager.elapsed_seconds
	dynamics.interact(agent,patients[0],"help")

func _distribute(agent: Dictionary,refuge: Dictionary) -> void:
	var dependents: Array=manager.agents.filter(func(other):return dynamics.together(agent,other) and agent.get("relationships",{}).get(other.id,"")=="child")
	if dependents.is_empty():
		if not refuge.supply_known: _discover_supplies(agent,refuge)
		for other in dynamics.residents(agent.shelter_id):
			if dynamics.together(agent,other) and (int(other.get("age",30))<18 or float(other.health)<65 or float(other.get("hunger",0))>65) and rng.randf()<dynamics.cooperation_probability(agent,other): dependents.append(other)
		if dependents.is_empty(): return
	if refuge.person_days<=0: return
	dependents.sort_custom(func(a,b):return a.hunger>b.hunger)
	var child: Dictionary=dependents[0]; var ration:=minf(.333333,float(refuge.person_days)); refuge.person_days-=ration
	child.hunger=maxf(0,float(child.hunger)-20*(ration/.333333))
	var counter: String="food_received_from_parent" if agent.get("relationships",{}).get(child.id,"")=="child" else "food_received_from_neighbor"
	child[counter]=int(child.get(counter,0))+1
	dynamics.interact(agent,child,"share")
	dynamics.counts.food_shared+=1

func _care_for_child(agent: Dictionary) -> void:
	if int(agent.get("age",30))<18: return
	for other in manager.agents:
		if int(other.get("age",30))>=18 or not dynamics.together(agent,other): continue
		if other.get("shelter_caregiver","")==agent.id or agent.get("relationships",{}).get(other.id,"")=="child":
			dynamics.interact(agent,other,"care"); dynamics.counts.care_acts+=1

func _play_with_dog(agent: Dictionary) -> void:
	for dog in social.companions:
		if dog.owner_id==agent.id and dog.health>0 and dog.get("shelter_id","")==agent.shelter_id:
			dog.stress=maxf(0,float(dog.get("stress",20))-6); dog.current_goal="Play with owner in shelter"; return

func _handle_fire(agent: Dictionary) -> void:
	for event in storyteller.active(agent.shelter_id):
		if event.event_type=="fire": storyteller.observe(); storyteller.request_response(event.event_id,agent); return
	if _has_skill(agent,"fire_safety"): shelters[agent.shelter_id].fire=false

func _handle_emergency(agent: Dictionary) -> void:
	if not _has_skill(agent,"emergency"): return
	if not storyteller.active(agent.shelter_id).is_empty():
		for event in storyteller.active(agent.shelter_id):
			if event.severity>=.65: storyteller.order_transfer(event.event_id,agent)
		return
	var refuge: Dictionary=shelters[agent.shelter_id]
	refuge.emergency=false
	if refuge.fire and _has_skill(agent,"fire_safety"): refuge.fire=false
	if not refuge.power and _has_skill(agent,"technical"): refuge.power=true
	if not refuge.air and _has_skill(agent,"technical"): refuge.air=true
	if not refuge.water and _has_skill(agent,"technical") and float(refuge.get("water_liters",1))>0: refuge.water=true
	social.emit_event("shelter.emergency_resolved",agent.id,{"shelter_id":agent.shelter_id})

func _restore_security(agent: Dictionary) -> void:
	if not _has_skill(agent,"security"): return
	var prefix:=str(agent.shelter_id)+":"
	for key in blocked_doors.keys():
		if str(key).begins_with(prefix) and key not in storyteller.door_blocks.get(agent.shelter_id,[]): blocked_doors.erase(key)
	shelters[agent.shelter_id].emergency=false

func _daily_shelter_events(new_day: int) -> void:
	# The contextual storyteller owns incident generation; no second random roll.
	for refuge in shelters.values(): refuge.day=new_day
	for key in blocked_doors.keys():
		if float(blocked_doors[key])<=manager.elapsed_seconds: blocked_doors.erase(key)

func _request_complex_decision(agent: Dictionary, selected_activity: String) -> void:
	if selected_activity not in ["ARGUE","RECONCILE","DISTRIBUTE_RESOURCES","MAINTAIN_GENERATOR","MAINTAIN_AIR","MAINTAIN_WATER","EMERGENCY_RESPONSE"]: return
	if agent.get("configured_provider","")!="LOCAL_LLM" or manager.ai_bridge==null or not manager.ai_config.get("enabled",false): return
	if pending_cognitive.has(agent.id) or pending_cognitive.size()>=int(config.get("maximum_cognitive_requests",2)) or manager.elapsed_seconds<float(agent.get("next_shelter_cognitive_at",0)): return
	agent.next_shelter_cognitive_at=manager.elapsed_seconds+float(config.cognitive_cooldown_seconds)/routine_clock_rate()
	var allowed: Array[String]=["CONTINUE","CONSERVE","SHARE","MEDIATE","SEEK_HELP"]
	var refuge: Dictionary=shelters[agent.shelter_id]
	var context: Dictionary={"shelter_id":agent.shelter_id,"activity":selected_activity,"room_type":rooms.get(agent.get("shelter_room_id",""),{}).get("room_type","transit"),"needs":{"hunger":agent.hunger,"thirst":agent.thirst,"fatigue":agent.fatigue,"stress":agent.stress,"health":agent.health},"resources_known":bool(refuge.supply_known),"resource_pressure":float(refuge.person_days) if refuge.supply_known else null,"family_conflict":_has_conflict(agent),"power_available":refuge.power,"air_available":refuge.air,"water_available":refuge.water}
	pending_cognitive[agent.id]=true
	var started_generation:=generation
	var request_id: String=manager.ai_bridge.request_shelter_decision(agent,context,allowed,func(result: Dictionary):
		pending_cognitive.erase(agent.id)
		if started_generation!=generation or not agent.get("shelter_life_active",false): return
		if result.is_empty(): cognitive_fallbacks+=1; return
		apply_cognitive_decision(agent,result)
	)
	if request_id.is_empty(): pending_cognitive.erase(agent.id); cognitive_fallbacks+=1

func apply_cognitive_decision(agent: Dictionary, result: Dictionary) -> bool:
	if not agent.get("shelter_life_active",false) or result.get("action","") not in ["CONTINUE","CONSERVE","SHARE","MEDIATE","SEEK_HELP"]: return false
	agent["last_complex_decision"]={"action":result.action,"reason":result.get("reason",""),"time":manager.elapsed_seconds,"provider":"LangGraph"}
	match result.action:
		"CONSERVE": agent["resource_decision"]="conserve"
		"SHARE": agent["resource_decision"]="share"
		"MEDIATE": _reconcile(agent)
		"SEEK_HELP":
			agent.stress=maxf(0,float(agent.stress)-2.0)
			social.emit_event("shelter.leadership_request",agent.id,{"shelter_id":agent.shelter_id,"reason":result.get("reason","")})
	return true

func stop() -> void:
	active=false; completed=true; generation+=1; pending_cognitive.clear()
	config.clear(); dynamics.reset()
	storyteller.reset()

func shelter_status(shelter_id: String) -> Dictionary:
	var refuge: Dictionary=shelters.get(shelter_id,{})
	if refuge.is_empty(): return {}
	return {"id":shelter_id,"day":day,"days_total":int(config.get("duration_days",10)),"person_days_remaining":refuge.person_days if refuge.supply_known else null,"supplies_known":refuge.supply_known,"power":refuge.power,"air":refuge.air,"water":refuge.water,"occupants":manager.agents.filter(func(a):return a.get("shelter_id","")==shelter_id and a.get("shelter_life_active",false)).size(),"rooms":rooms_by_shelter.get(shelter_id,[]).size()}
