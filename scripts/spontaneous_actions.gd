extends RefCounted
## OpenJev chooses from a bounded menu. Physical feasibility remains authoritative in Godot.
var _social_ref: WeakRef
var social: RefCounted:
	get: return _social_ref.get_ref() if _social_ref!=null else null
	set(value): _social_ref=weakref(value) if value!=null else null
var _life_ref: WeakRef
var life: RefCounted:
	get: return _life_ref.get_ref() if _life_ref!=null else null
	set(value): _life_ref=weakref(value) if value!=null else null
var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://config/openjev.json"))
var pending: Dictionary={}
var next_request: Dictionary={}
var status:="NOT_QUERIED"
var completed:=0
var fallbacks:=0
var generation:=0
var next_wall_try:=0

func initialize(owner_social: RefCounted, owner_life: RefCounted) -> void:
	social=owner_social; life=owner_life; generation+=1
	for index in range(social.manager.agents.size()): next_request[social.manager.agents[index].id]=5.0+index*.75

func choices(a: Dictionary) -> Dictionary:
	var result: Dictionary={"continue_routine":"Keep the current schedule or duty","rest":"Rest briefly at the current safe place","check_family":"Call or message a known family contact"}
	if a.age>=18 and a.school=="" and a.role=="Civilian":
		result.merge({"shop":"Visit a shop","socialize":"Visit a remembered friend address","walk":"Take a short sidewalk walk"})
		if not a.vehicle_id.is_empty(): result.drive="Drive to the scheduled workplace using a parking space"
	if a.fatigue>=float(life.settings.fatigue_rest_threshold):
		result={"rest":"Recover from high fatigue at the current safe place","check_family":"Contact family while taking a break"}
	return result

func state_for(a: Dictionary) -> Dictionary:
	var memories: Array=[]
	for id in a.relationships:
		if a.known_locations.has(id):
			var known: Dictionary=a.known_locations[id]
			memories.append({"relation":a.relationships[id],"age_of_information":maxf(0,social.manager.elapsed_seconds-float(known.get("timestamp",0))),"source":known.get("source","remembered")})
	var percentages: Dictionary={}
	for key in a.needs: percentages[key]=int(roundf(float(a.needs[key])*100))
	return {"age":a.age,"role":a.role,"occupation":a.occupation,"routine":a.routine,"indoors":a.indoor_id!="","needs_percent":percentages,"remembered_contacts":memories.slice(0,4)}

func tick() -> void:
	if not social.manager.ai_config.enabled: return
	if Time.get_ticks_msec()<next_wall_try or social.manager.elapsed_seconds<=social.driving.priority_until: return
	for a in social.manager.agents:
		if pending.size()+social.driving.pending.size()>=int(config.max_pending): break
		if pending.has(a.id) or a.health<=0 or a.get("riding","")!="" or a.interior_transition!="": continue
		if social.manager.elapsed_seconds<float(next_request.get(a.id,0)): continue
		next_request[a.id]=social.manager.elapsed_seconds+float(config.interval_seconds)
		var allowed: Dictionary=choices(a)
		var request:=HTTPRequest.new(); request.timeout=float(config.timeout_seconds)
		social.manager.ai_bridge.add_child(request); pending[a.id]=request
		var current_generation: int=generation
		var run_id: String=social.manager.ai_bridge.run_id
		var body: Dictionary={"model":config.model,"state":JSON.stringify(state_for(a)),"questions":{"action":{"type":"choice","instructions":"Choose a plausible small voluntary daily action for this person. Respect work and school duties. Needs are percentages from 0 to 100. Prefer rest when fatigued and family contact when concerned.","criteria":allowed}}}
		request.request_completed.connect(func(result,code,_headers,bytes):
			if pending.get(a.id)==request: pending.erase(a.id)
			request.queue_free()
			if generation!=current_generation or run_id!=social.manager.ai_bridge.run_id or social.manager.phase!="LIVING" or a.health<=0 or not social.manager.ai_config.enabled: return
			if result==HTTPRequest.RESULT_SUCCESS and code==200:
				var decoded: Variant=JSON.parse_string(bytes.get_string_from_utf8())
				var selected: String=parse_choice(decoded,allowed)
				if selected!="": status="CONNECTED"; completed+=1; apply(a,selected,"OPENJEV"); return
			status="UNAVAILABLE"; fallbacks+=1; next_wall_try=Time.get_ticks_msec()+5000
			apply(a,"rest" if a.fatigue>65 else "check_family" if a.family_concern>.5 else "continue_routine","RULE_FALLBACK"))
		var headers:=PackedStringArray(["Content-Type: application/json"])
		var key: String=OS.get_environment("OPENJEV_API_KEY")
		if key!="": headers.append("Authorization: Bearer "+key)
		if request.request(config.endpoint,headers,HTTPClient.METHOD_POST,JSON.stringify(body))!=OK:
			pending.erase(a.id); request.queue_free(); status="UNAVAILABLE"; fallbacks+=1; next_wall_try=Time.get_ticks_msec()+5000
			apply(a,"continue_routine","RULE_FALLBACK")
			break

static func parse_choice(packet: Variant, allowed: Dictionary) -> String:
	if not packet is Dictionary or not packet.get("answers") is Dictionary: return ""
	var answer: Variant=packet.answers.get("action")
	if not answer is Dictionary or not answer.get("choice") is String: return ""
	if not allowed.has(answer.choice): return ""
	var confidence: Variant=answer.get("confidence",0)
	if not (confidence is int or confidence is float) or not is_finite(float(confidence)) or confidence<0 or confidence>1: return ""
	return answer.choice

func apply(a: Dictionary, action: String, provider: String) -> bool:
	if a.get("cognition",{}).get("layer","")=="REFLEX" and social.manager.elapsed_seconds<float(a.cognition.get("until",0)): return false
	if social.manager.phase!="LIVING" or a.get("riding","")!="" or a.get("interior_transition","")!="" or not choices(a).has(action): return false
	match action:
		"rest":
			if a.indoor_id!="": life.schedule(a,"REST",a.indoor_id)
			else: a.routine="REST_OUTDOOR"; a.routine_until=social.manager.elapsed_seconds+12
		"shop": life.schedule(a,"SHOP",a.shop_building)
		"socialize": life.schedule(a,"VISIT_FRIEND",a.friend_home)
		"walk": life.schedule(a,"WALK",a.home_building)
		"drive": life.schedule(a,"DRIVE",a.work_building,true)
		"check_family":
			for id in a.relationships:
				if social.send_phone(a,id,{"subject":"family_location","value":"Checking in","position":a.position},"call"): break
	a.spontaneous_provider=provider; a.last_spontaneous_action=action
	social.emit_event("agent.spontaneous_action",a.id,{"action":action,"provider":provider})
	return true

func close() -> void:
	generation+=1
	for request in pending.values():
		if is_instance_valid(request): request.cancel_request(); request.queue_free()
	pending.clear()
