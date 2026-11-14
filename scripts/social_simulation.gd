extends RefCounted
## Director world state stays here; decisions read only each agent's acquired evidence.
const Map = preload("res://scripts/city_map.gd")
const POLICE_BLOCKS := ["police","checkpoint","evacuation_checkpoint","restricted","damaged_road","emergency_lane"]
const EMERGENCY_PASS := ["police","checkpoint","evacuation_checkpoint","restricted"]
const Routes = preload("res://scripts/road_routes.gd")
var manager: Node
var config := {}
var families: Array = []
var school := {}
var by_id := {}
var vehicles: Array = []
var blocks: Array = []
var posts: Array = []
var alerts: Array = []
var deliveries: Array = []
var history: Array = []
var counters := {}
var rng := RandomNumberGenerator.new()
var next_tick := 0.0
var next_record := 0.0
var recorder: RefCounted
var replay_frames: Array = []
var replay_cursor := 0
var replaying := false
var school_position := Vector2.ZERO
var school_destination := ""
var school_status := "NORMAL"
var iq_stats := {}
var outbox: Array = []
var sending := false
var event_request: HTTPRequest
var next_send := 0.0
var junction_reservations := {}
var last_decisions := {}
var daily = preload("res://scripts/daily_life.gd").new()
var households = preload("res://scripts/household_travel.gd").new()
var traffic = preload("res://scripts/vehicle_runtime.gd").new()
var driving = preload("res://scripts/traffic_rules.gd").new()
var authorities = preload("res://scripts/authority_coordination.gd").new()
var companion_runtime = preload("res://scripts/animal_companion_runtime.gd").new()
var shelter_life = preload("res://scripts/shelter_life.gd").new()
var next_shelter_frame := 0.0
var cognition = preload("res://scripts/agent_cognition.gd").new()
var police = preload("res://scripts/police_response.gd").new()
var evacuation = preload("res://scripts/police_evacuation.gd").new()
var companions: Array[Dictionary] = []

func initialize(owner_manager: Node, population: Dictionary) -> void:
	if shelter_life!=null: shelter_life.stop()
	manager = owner_manager
	config = population.config.duplicate(true)
	families = population.families.duplicate(true)
	school = population.school.duplicate(true)
	iq_stats = population.iq_stats.duplicate(true)
	rng.seed = manager.seed_for("scenario")+51031
	traffic.reset(); junction_reservations.clear(); last_decisions.clear()
	vehicles.clear(); blocks.clear(); posts.clear(); alerts.clear(); deliveries.clear(); history.clear(); by_id.clear()
	companions.clear(); companion_runtime.close()
	counters = {"calls":0,"texts":0,"posts":0,"shares":0,"corrections":0,"alerts_delivered":0,"accidents":0,"orders":0,"compliance":0,"congested_seconds":0.0,"arrivals":[],"reunions":0,"trust_changes":0,"public_trust_changes":0}
	next_tick = 0; next_record = 0; replaying = false; outbox.clear(); sending=false
	school_status = "NORMAL"; school_destination = ""
	school_position = Map.pois[4].position if Map.pois.size()>4 else Map.nearest_lane_point(Map.MAP_SIZE*Vector2(.4,.6))
	for i in range(manager.agents.size()):
		var a: Dictionary = manager.agents[i]
		var profile: Dictionary = population.agents[i]
		for key in profile: a[key] = profile[key].duplicate(true) if profile[key] is Dictionary or profile[key] is Array else profile[key]
		a.home_location = Map.nearest_lane_point(Vector2(a.home_uv[0],a.home_uv[1])*Map.MAP_SIZE)
		a.known_locations = {}; a.social_beliefs = {}; a.inbox = []; a.calls = []; a.authority_reports=[]; a.authority_orders=[]
		a.phone = {"owner":a.id,"connected":a.has_phone and rng.randf()<config.network_availability,"battery":1.0,"groups":{},"contacts":[],"messages":[],"calls":[]}
		a.trusted_contacts = a.relationships.keys(); a.untrusted_contacts = []
		a.fatigue = 0.0; a.stress = 0.0; a.perceived_danger = 0.0; a.family_concern = 0.0
		a.social_target = ""; a.vehicle_id = ""; a.next_social = float(i%11)
		a.next_rule_decision = float(i)/manager.agents.size()*maxf(manager.settings.evacuation.decision_interval_seconds,manager.ai_config.decision_interval_seconds)
		a.configured_provider = "LOCAL_LLM" if profile.llm_enabled and profile.model_tier != "rules" else "RULE_BASED"
		a.decision_provider = a.configured_provider
		a.iq_influence = config.iq_influence
		a.position = school_position+Vector2(i%4*5,0) if a.school in ["SCHOOL","SCHOOL_STAFF"] else a.position
		if a.age < 18:
			a.walk_speed *= .7; a.run_speed *= .7; a.movement_speed = a.walk_speed
		for relative in a.relationships:
			a.phone.contacts.append(relative)
			# A remembered schedule is uncertain, never a live location feed.
			a.known_locations[relative] = {"position":school_position if a.relationships[relative] == "child" else a.home_location,"source":"remembered schedule","timestamp":0.0,"confidence":.55}
		by_id[a.id] = a
	for a in manager.agents:
		if a.role == "Authority":
			a.commander = ""
			for commander in manager.agents:
				if commander.occupation == "Crisis commander": a.commander = commander.id; break
			for other in manager.agents:
				if other.role == "Authority" and other.id not in a.phone.contacts: a.phone.contacts.append(other.id)
	for child in manager.agents:
		if child.age<18:
			for guardian in child.guardians:
				for staff in school.staff:
					if staff not in by_id[guardian].phone.contacts: by_id[guardian].phone.contacts.append(staff)
					if guardian not in by_id[staff].phone.contacts: by_id[staff].phone.contacts.append(guardian)
	var emergency := []
	for kind in ["Police","Medical","Fire","Civil protection"]:
		var requested: int = config[{"Police":"police_vehicles","Medical":"ambulances","Fire":"fire_trucks","Civil protection":"civil_protection_vehicles"}[kind]]
		for a in manager.agents:
			if requested <= 0: break
			if a.role == "Authority" and not emergency.has(a.id) and a.occupation == kind:
				_add_vehicle(a,kind); emergency.append(a.id); requested -= 1
		for a in manager.agents:
			if requested <= 0: break
			if a.role == "Authority" and not emergency.has(a.id):
				_add_vehicle(a,kind); emergency.append(a.id); requested -= 1
	for a in manager.agents:
		if a.owns_vehicle and a.vehicle_id.is_empty(): _add_vehicle(a,"Civilian")
	for f in families:
		f.status = "SEPARATED"
		for id in f.members:
			by_id[id].phone.groups[f.id]=f.members.duplicate()
			for contact in f.members:
				if contact!=id and contact not in by_id[id].phone.contacts: by_id[id].phone.contacts.append(contact)
	for s in manager.shelters:
		if s.id != "S5" and rng.randf()>config.shelter_availability:
			s.accepting = false; s.operational = false
	DirAccess.make_dir_recursive_absolute("res://outputs/phase5")
	if recorder!=null: recorder.close()
	recorder = preload("res://scripts/social_recorder.gd").new()
	recorder.start("res://outputs/phase5/"+manager.ai_bridge.run_id+".jsonl")
	daily.initialize(self)
	for a in manager.agents:
		if a.personal_memory.is_empty(): a.personal_memory.append({"time":manager.elapsed_seconds,"text":"I am at my initial daily routine: "+str(a.routine).to_lower()+"."})
	households.initialize(self)
	driving.initialize(self)
	authorities.initialize(self)
	police.initialize(self)
	evacuation.initialize(self)
	companion_runtime.initialize(self)
	companions = companion_runtime.companions
	cognition.initialize(self)
	rng.seed=manager.seed_for("behavior")+51031
	_record({"record_type":"initial","schema_version":1,"config":config,"master_seed":manager.seed_value,"world":manager.world.current,"world_json":manager.world.current_json,"world_metadata":manager.world_metadata(),"experiment_seeds":manager.experiment_seeds,"city_settings":manager.city_settings,"map_scale":manager.nuclear.map_scale,"map_version":Map.layout_version,"population":population,"agents":manager.agents,"companions":companions,"shelters":manager.shelters})

func _add_vehicle(a: Dictionary, kind: String) -> void:
	var id := "V%03d"%(vehicles.size()+1)
	var vehicle_rng: RandomNumberGenerator=rng
	if not manager.world.current.is_empty():
		vehicle_rng=RandomNumberGenerator.new(); vehicle_rng.seed=int(manager.world.current.streams.vehicles)+int(a.get("population_index",0))*173
	var model: String=preload("res://scripts/vehicle_catalog.gd").choose(kind,vehicle_rng)
	var catalog: Dictionary=preload("res://scripts/vehicle_catalog.gd").TYPES
	if kind=="Civilian":
		for family in families:
			if a.id in family.members and family.members.size()>catalog[model].capacity:
				model="sedan" if family.members.size()<=5 else "van" if family.members.size()<=7 else "minibus"
	var spec: Dictionary=catalog[model]
	var v: Dictionary=spec.duplicate(true)
	v.merge({"id":id,"owner":a.id,"driver":a.id,"kind":kind,"model":model,"passengers":[],"speed":0.0,"health":100.0,"status":"PARKED","route":PackedVector2Array(),"route_index":0,"destination":"","height":0.0,"edge":-1,"next_route":0.0,"steering":0.0,"collision_state":"CLEAR"})
	var bay: Dictionary=traffic.reserve_spawn(v,vehicles,a.position)
	if bay.is_empty(): return
	a.vehicle_id=id
	var exit_path: PackedVector2Array=bay.approach.duplicate(); exit_path.reverse()
	v.merge({"position":bay.position,"body_position":bay.position,"heading":bay.heading,"body_height":spec.height,"height":0.0,"parking_bay":bay.id,"parking_heading":bay.heading,"parking_exit":exit_path},true)
	vehicles.append(v)

func encode(value: Variant) -> Variant:
	if value is float and not is_finite(value): return null
	if value is Vector2: return {"__v2":[value.x,value.y]}
	if value is PackedVector2Array:
		var points := []
		for p in value: points.append([p.x,p.y])
		return {"__route":points}
	if value is Dictionary:
		var result := {}
		for key in value: result[str(key)] = encode(value[key])
		return result
	if value is Array:
		var result := []
		for item in value: result.append(encode(item))
		return result
	return value

func decode(value: Variant) -> Variant:
	if value is Dictionary:
		if value.has("__float"): return INF if value.__float=="inf" else -INF
		if value.has("__v2"): return Vector2(value.__v2[0],value.__v2[1])
		if value.has("__route"):
			var result := PackedVector2Array()
			for p in value.__route: result.append(Vector2(p[0],p[1]))
			return result
		var result := {}
		for key in value: result[key] = decode(value[key])
		return result
	if value is Array:
		var result := []
		for item in value: result.append(decode(item))
		return result
	return value

func _record(packet: Dictionary) -> void:
	if packet.get("record_type","")=="frame" and not packet.has("companions"): packet["companions"]=companions
	if recorder!=null and not replaying: recorder.enqueue(packet)

func close() -> void:
	driving.close()
	authorities.close()
	companion_runtime.close()
	companions.clear()
	daily.close()
	if recorder!=null: recorder.close(); recorder=null
	if is_instance_valid(event_request):
		event_request.cancel_request(); event_request.queue_free(); event_request=null
	sending=false

func emit_event(kind: String, source: String, payload: Dictionary) -> void:
	if manager.emergency.owner!=null:
		if kind=="vehicle.accident": manager.emergency.record_accident(source,payload)
		elif kind=="traffic.recovered": manager.emergency.record_recovery(source)
	if kind=="vehicle.accident" and payload.get("position") is Vector2:
		for observer in manager.agents:
			if observer.has("cognition") and observer.position.distance_to(payload.position)<=float(cognition.config.observation_radius):
				observer.cognition.next_observe=manager.elapsed_seconds
				observer.cognition.next_decide=manager.elapsed_seconds
	var event := {"schema_version":1,"event_id":manager.ai_bridge.run_id+":"+str(history.size()),"run_id":manager.ai_bridge.run_id,"event_type":kind,"simulation_timestamp":manager.elapsed_seconds,"wall_timestamp":Time.get_datetime_string_from_system(true)+"Z","source_entity":source,"payload":encode(payload)}
	event.merge(manager.world_metadata())
	history.append(event)
	_record({"record_type":"event","event":event})
	# Existing Kafka topic carries versioned typed social events, keyed by source.
	outbox.append(event)

func acquire(a: Dictionary, subject: String, value: Variant, source: String, confidence: float, evidence: String) -> void:
	var previous: Dictionary = a.social_beliefs.get(subject,{})
	if previous.get("status","") == "KNOWN" and evidence != "direct observation": return
	if not previous.is_empty() and previous.get("status","")!="KNOWN" and evidence == "direct observation":
		var reliability: float=float(a.trust_relationships.get(previous.source,.5))
		if previous.get("claimed_value") != value: counters.corrections+=1; reliability-=.1
		else: reliability+=.05
		a.trust_relationships[previous.source]=clampf(reliability,0,1); counters.trust_changes+=1
	a.social_beliefs[subject] = {"subject":subject,"claimed_value":value,"source":source,"acquired_at":manager.elapsed_seconds,"confidence":clampf(confidence,0,1),"evidence":evidence,"last_update":manager.elapsed_seconds,"status":"KNOWN" if evidence == "direct observation" else "BELIEVED" if confidence >= .7 else "RUMORED"}
	if subject=="nuclear" and not a.has("personal_warning_known_at"): a.personal_warning_known_at=manager.elapsed_seconds
	var parts:=subject.split(":")
	if parts.size()==3 and parts[0]=="shelter" and parts[2]=="full" and a.beliefs.has(parts[1]):
		var belief: Dictionary=a.beliefs[parts[1]]
		if belief.evidence_type!="direct_observation" and confidence>.35 and value is bool:
			belief.estimated_occupancy=belief.capacity if value else 0
			belief.confidence=confidence; belief.source=source; belief.evidence_type=evidence
			belief.last_update_time=manager.elapsed_seconds
	emit_event("agent.belief_updated",a.id,a.social_beliefs[subject])

func connected(a: Dictionary) -> bool:
	return a.has_phone and a.phone.battery>0 and a.phone.connected and a.health>0

func send_phone(sender: Dictionary, target: String, content: Dictionary, channel: String = "text") -> bool:
	if not by_id.has(target) or target not in sender.phone.contacts or not connected(sender): return false
	var recipient: Dictionary = by_id[target]
	if not connected(recipient): return false
	var load: float = clampf(float(deliveries.size())/maxf(1,manager.agents.size()),0,.65)
	if rng.randf() > (1-load): return false
	var message := {"id":"M%d"%history.size(),"sender":sender.id,"recipient":target,"timestamp":manager.elapsed_seconds,"channel":channel,"content":content.duplicate(true),"due":manager.elapsed_seconds+rng.randf_range(1,5)+load*10}
	deliveries.append(message)
	sender.phone.messages.append(message.duplicate(true))
	if sender.phone.messages.size()>30: sender.phone.messages.pop_front()
	counters["calls" if channel=="call" else "texts"] += 1
	if channel == "call":
		sender.phone.calls.append(message.duplicate(true))
		emit_event("phone.call_started",sender.id,{"recipient":target,"message_id":message.id})
	emit_event("phone.message_sent",sender.id,message)
	return true

func issue_alert(issuer: Dictionary, kind: String, message: String, instructions: String, center: Vector2, radius: float) -> Dictionary:
	if issuer.role != "Authority" or kind not in ["nuclear","evacuate","shelter_in_place","road_closure","school","final"]: return {}
	var alert := {"id":"AL%03d"%(alerts.size()+1),"name":"ESSAIM CIVIL DEFENSE ALERT","issuer":issuer.id,"kind":kind,"timestamp":manager.elapsed_seconds,"severity":"EXTREME" if kind in ["nuclear","final"] else "SEVERE","center":center,"radius":radius,"message":message,"instructions":instructions,"expires":manager.elapsed_seconds+120,"recipients":[]}
	alerts.append(alert)
	for a in manager.agents:
		if connected(a) and a.position.distance_to(center)<=radius and rng.randf()<config.alert_reach:
			deliveries.append({"id":alert.id+":"+a.id,"sender":issuer.id,"recipient":a.id,"timestamp":manager.elapsed_seconds,"due":manager.elapsed_seconds+rng.randf_range(.2,3),"channel":"alert","content":{"subject":kind,"value":instructions,"message":message,"alert_id":alert.id}})
	emit_event("authority.alert_issued",issuer.id,alert)
	return alert

func warning() -> void:
	daily.warning()
	authorities.nuclear_warning()
	for a in manager.agents:
		if a.occupation == "Crisis commander":
			issue_alert(a,"nuclear","Nuclear threat reported. Seek protection.","Seek a known nearby shelter; verify family instructions.",Map.MAP_SIZE*.5,Map.MAP_SIZE.length())
			break
	for f in families:
		emit_event("family.member_missing",f.id,{"members":f.members})

func publish_post(a: Dictionary, subject: String, value: Variant, audience: Array = [], original_source: String = "", propagation: Array = []) -> Dictionary:
	if not connected(a) or not a.social_user: return {}
	var post := {"id":"P%08d"%int(counters.posts),"source":a.id,"original_source":a.id if original_source.is_empty() else original_source,"timestamp":manager.elapsed_seconds,"content":subject+": "+str(value),"subject":subject,"value":value,"audience":audience.duplicate(),"credibility":.45,"propagation":[a.id] if propagation.is_empty() else propagation.duplicate(),"readers":[],"comments":[],"reactions":{}}
	posts.append(post); counters.posts += 1
	emit_event("social.post_created",a.id,post)
	return post

func _deliver(message: Dictionary) -> void:
	var a: Dictionary = by_id[message.recipient]
	if not connected(a): return
	var sender: Dictionary = by_id[message.sender]
	var body: Dictionary = message.content
	households.receive(a,sender,body)
	a.phone.messages.append(message.duplicate(true))
	if a.phone.messages.size()>30: a.phone.messages.pop_front()
	if message.channel=="call":
		a.phone.calls.append(message.duplicate(true))
		if a.phone.calls.size()>30: a.phone.calls.pop_front()
	a.inbox.append(message.duplicate(true))
	if a.inbox.size()>30: a.inbox.pop_front()
	var trust: float = .9 if sender.id in a.relationships else a.authority_trust/100 if sender.role=="Authority" else .5
	var confidence := clampf(trust*(1-a.skepticism/200),.1,.95)
	if body.has("subject"): acquire(a,body.subject,body.get("value",""),sender.id,confidence,message.channel)
	if body.has("position") and body.get("subject","")=="family_location":
		a.known_locations[sender.id] = {"position":body.position,"source":message.channel+":"+sender.id,"timestamp":manager.elapsed_seconds,"confidence":confidence}
	if body.get("subject","")=="authority_family_checkin" and sender.id in a.relationships:
		a.known_locations[sender.id] = {"position":body.get("position",sender.position),"source":"family call:"+sender.id,"timestamp":manager.elapsed_seconds,"confidence":confidence}
		send_phone(a,sender.id,{"subject":"family_location","value":"I am here; this is my current position.","position":a.position},"call")
	if body.get("subject","")=="school_enquiry" and a.id in school.staff and not school_destination.is_empty():
		send_phone(a,sender.id,{"subject":"school_destination","value":school_destination},"call")
	if message.channel == "alert":
		counters.alerts_delivered += 1
		for alert in alerts:
			if alert.id == body.alert_id: alert.recipients.append(a.id)
		if a.state == "IDLE" and rng.randf()<trust:
			manager._set_state(a,"DECIDING"); manager.choose_rule_destination(a)
		if rng.randf()<trust: counters.compliance += 1
	if body.get("subject","") == "school_destination" and a.beliefs.has(body.value) and rng.randf()<trust:
		a.recommendations[body.value] = confidence
		a.social_target = ""
	if body.get("subject","")=="order" and a.role=="Authority" and rng.randf()<trust:
		a.current_goal="Order: "+str(body.value); counters.compliance+=1
	if body.get("subject","")=="accident_report" and a.role=="Authority":
		a.known_locations["accident:"+str(body.value)]={"position":body.position,"source":sender.id,"timestamp":manager.elapsed_seconds,"confidence":confidence}
		if not a.get("police_unit_busy",false) and a.occupation in ["Medical","Fire","Police"]: a.social_target="accident:"+str(body.value)
	if message.channel=="call": emit_event("phone.call_ended",sender.id,{"recipient":a.id,"message_id":message.id})

func tick(seconds: float) -> void:
	if replaying: return
	if manager.phase=="IMPACT":
		shelter_life.tick(seconds)
		if manager.elapsed_seconds>=next_shelter_frame:
			next_shelter_frame=manager.elapsed_seconds+3600.0/shelter_life.routine_clock_rate()
			capture_frame()
		return
	Map.traffic_time=manager.elapsed_seconds
	flush_events()
	if cognition.owner==null: cognition.initialize(self)
	cognition.tick(seconds)
	police.tick(seconds)
	evacuation.tick(seconds)
	daily.tick(seconds)
	households.tick(seconds)
	# Vehicles move on every fixed tick. Social work is staggered and runs once/second.
	var steps: int=maxi(1,int(ceil(seconds/.05)))
	for _step in range(steps):
		traffic.capture(vehicles)
		_move_vehicles(seconds/steps)
		traffic.resolve(self,seconds/steps)
		_finish_vehicle_arrivals()
	companion_runtime.tick(seconds)
	traffic.respond(self,seconds)
	authorities.tick(seconds)
	if manager.elapsed_seconds < next_tick: return
	next_tick = manager.elapsed_seconds+1
	for i in range(deliveries.size()-1,-1,-1):
		if deliveries[i].due <= manager.elapsed_seconds:
			_deliver(deliveries[i]); deliveries.remove_at(i)
	for block in blocks:
		if block.active and manager.elapsed_seconds>=block.expires: remove_block(block.id)
	for a in manager.agents:
		a.stress = a.panic_level
		a.perceived_danger = a.panic_level/100
		a.fatigue = clampf(a.fatigue+(.02 if a.state=="MOVING" else -.01),0,100)
		if a.state in ["SHELTERED","EXPOSED","SAFE"]: continue
		_observe(a)
		var signature: String=str(a.objective)+":"+str(a.get("latest_llm_action",""))+":"+a.current_goal
		if last_decisions.get(a.id,"")!=signature:
			last_decisions[a.id]=signature
			emit_event("agent.decision",a.id,{"destination":a.objective,"goal":a.current_goal,"provider":a.decision_provider})
		if a.get("police_unit_busy",false) or a.get("evacuation_group","")!="" or manager.phase not in ["EVACUATION","BOMB_FALL"] or manager.elapsed_seconds<a.next_social: continue
		a.next_social = manager.elapsed_seconds+8+rng.randf()*8
		_social_action(a)
	if manager.phase in ["EVACUATION","BOMB_FALL"] and manager.remaining_seconds<=60 and not alerts.any(func(al):return al.kind=="final"):
		for a in manager.agents:
			if a.occupation=="Crisis commander":
				issue_alert(a,"final","Urgent civil defense warning","Take immediate protection. Do not rely on unverified rumors.",Map.MAP_SIZE*.5,Map.MAP_SIZE.length()); break
	_school()
	for family in families:
		var together := true
		var first: Dictionary = by_id[family.members[0]]
		for id in family.members:
			var a: Dictionary = by_id[id]
			if not daily.interiors.can_see(first,a) or a.position.distance_to(first.position)>65 or (a.state=="SHELTERED" and a.shelter_id!=first.shelter_id): together=false
		if together and family.status!="REUNITED": counters.reunions+=1; emit_event("family.reunited",family.id,{"members":family.members})
		family.status = "REUNITED" if together else "SEPARATED"
	if manager.elapsed_seconds>=next_record:
		next_record=manager.elapsed_seconds+1
		capture_frame()

func _observe(a: Dictionary) -> void:
	var visible_contacts: Array=a.relationships.keys()
	if not a.get("supervisor","").is_empty() and a.supervisor not in visible_contacts: visible_contacts.append(a.supervisor)
	for id in visible_contacts:
		var other: Dictionary = by_id[id]
		if daily.interiors.can_see(a,other) and other.position.distance_to(a.position)<manager.living.observation_radius and other.state not in ["SHELTERED","EXPOSED"]:
			a.known_locations[id] = {"position":other.position,"source":"direct observation","timestamp":manager.elapsed_seconds,"confidence":1.0}
	for block in blocks:
		if block.active and a.position.distance_to(block.position)<manager.living.observation_radius and not a.social_beliefs.has("road:"+block.id):
			acquire(a,"road:"+block.id,"closed",a.id,1,"direct observation")
	if a.position.distance_to(school_position)<manager.living.observation_radius and a.social_beliefs.get("school_status",{}).get("claimed_value","")!=school_status:
		acquire(a,"school_status",school_status,a.id,1,"direct observation")

func _social_action(a: Dictionary) -> void:
	if not a.family_id.is_empty() and rng.randf()<.2: send_group(a,a.family_id,{"subject":"family_location","value":"Family check-in","position":a.position})
	for id in a.relationships:
		if rng.randf()<.65:
			send_phone(a,id,{"subject":"family_location","value":"I am here","position":a.position},"call" if rng.randf()<.25 else "text")
			if not school_destination.is_empty() and a.school=="SCHOOL_STAFF": send_phone(a,id,{"subject":"school_destination","value":school_destination})
	if a.role=="Authority":
		if a.occupation in ["Medical","Fire","Civil protection"]:
			for other in manager.agents:
				if other.health>0 and other.health<90 and other.position.distance_to(a.position)<65:
					other.health=minf(100,other.health+5); a.current_goal="Assist injured "+other.id; break
	if connected(a) and a.social_user:
		if rng.randf()<config.rumor_probability:
			if not a.social_beliefs.is_empty():
				var subject: String = a.social_beliefs.keys()[rng.randi_range(0,a.social_beliefs.size()-1)]
				publish_post(a,subject,a.social_beliefs[subject].claimed_value)
			else: publish_post(a,"shelter:S1:full",rng.randf()<.5)
		for post in posts.slice(-12):
			if post.source==a.id or a.id in post.readers or (not post.audience.is_empty() and a.id not in post.audience) or rng.randf()>.25: continue
			post.readers.append(a.id)
			var confidence: float = clampf((.8 if post.source in a.relationships else float(a.trust_relationships.get(post.source,post.credibility)))*(1-a.skepticism/100*config.credibility_sensitivity),.05,.95)
			acquire(a,post.subject,post.value,post.source,confidence,"social media")
			if confidence<.25:
				post.comments.append({"source":a.id,"content":"Unverified; seek direct evidence"}); post.reactions[a.id]="skeptical"
			elif rng.randf()<config.rumor_probability and post.propagation.size()<4 and a.id not in post.propagation:
				post.propagation.append(a.id); counters.shares+=1
				var value: Variant=post.value
				if rng.randf()<.1 and value is bool: value=not value
				publish_post(a,post.subject,value,a.phone.contacts,post.original_source,post.propagation)
				emit_event("social.rumor_shared",a.id,{"post_id":post.id,"original_source":post.original_source})
	if posts.size()>300: posts=posts.slice(-300)
	for id in a.relationships:
		if a.relationships[id]!="child": continue
		if rng.randf()<.4:
			for staff in school.staff: send_phone(a,staff,{"subject":"school_enquiry","value":id},"call")
		var known: Dictionary = a.known_locations.get(id,{})
		a.family_concern = 1.0 if known.get("source","")!="direct observation" else .2
		if known.is_empty(): continue
		var trust_school: bool = a.social_beliefs.has("school_destination") and rng.randf()<a.authority_trust/100
		if not trust_school and a.position.distance_to(known.position)>55 and rng.randf()<config.family_priority:
			a.social_target=id; a.current_goal="Find child "+id+" at last known location"

func _school() -> void:
	if manager.phase not in ["EVACUATION","BOMB_FALL"]: return
	if school_status=="NORMAL":
		for id in school.staff:
			var staff: Dictionary = by_id[id]
			if staff.social_beliefs.has("nuclear") or staff.state!="IDLE":
				manager.choose_rule_destination(staff)
				if staff.objective.is_empty(): continue
				school_destination=staff.objective; school_status="EVACUATING"
				staff.supervising_school=true
				for student_id in school.students: staff.run_speed=minf(staff.run_speed,by_id[student_id].run_speed*.85)
				staff.movement_speed=minf(staff.movement_speed,staff.run_speed)
				for student_id in school.students:
					var student: Dictionary = by_id[student_id]
					if student.get("indoor_id","")==daily.room_for("School") or student.position.distance_to(school_position)<100:
						student.supervisor=id
						student.known_locations[id]={"position":staff.position,"source":"staff instruction","timestamp":manager.elapsed_seconds,"confidence":1.0}
						acquire(student,"school_destination",school_destination,id,.9,"staff instruction")
						for guardian in student.guardians:
							if guardian not in staff.phone.contacts: staff.phone.contacts.append(guardian)
							send_phone(staff,guardian,{"subject":"school_destination","value":school_destination})
				emit_event("school.evacuation_started",id,{"destination":school_destination,"students":school.students})
				break
	if school_status=="EVACUATING":
		var complete := true
		for id in school.students:
			if by_id[id].state!="SHELTERED": complete=false
		if complete:
			school_status="COMPLETED"; emit_event("school.evacuation_completed","SCHOOL",{"destination":school_destination})

func create_block(issuer: Dictionary, kind: String, edge: Dictionary, position: Vector2 = Vector2.INF, height: float = 0, rationale: String = "", evidence: Dictionary = {}, managed_by_policy: bool = false, deployment_id: String = "") -> Dictionary:
	if kind not in POLICE_BLOCKS+["accident"]: return {}
	if kind in POLICE_BLOCKS and (issuer.role!="Authority" or issuer.occupation!="Police"): return {}
	var index: int = Map.roads.find(edge)
	if kind in POLICE_BLOCKS and not police.authorizes(deployment_id,issuer,index):
		if not evidence.is_empty(): police.request_deployment(kind,index,position,rationale,evidence)
		return {}
	for b in blocks:
		if b.active and b.edge==index and b.kind==kind and (kind!="accident" or b.position.distance_to(position)<100): return b
	var points: PackedVector2Array = edge.points
	var b := {"id":"B%03d"%blocks.size(),"edge":index,"position":Map.nearest_edge(issuer.position).point if position==Vector2.INF else position,"height":height,"kind":kind,"issuer":issuer.id,"active":true,"expires":INF if kind=="accident" or managed_by_policy else manager.elapsed_seconds+(60 if kind=="police" else 90),"rationale":rationale,"evidence":evidence.duplicate(true),"managed_by_policy":managed_by_policy,"managed_by":issuer.id,"unmanaged":false}
	blocks.append(b)
	if deployment_id!="": b["deployment_id"]=deployment_id
	Map.roadblock_data[b.id]=b
	if height<3 and kind!="emergency_lane": Map.set_closure(b.id,b.position,true)
	if kind!="emergency_lane": Map.graph.disconnect_points(edge.from,edge.to)
	emit_event("roadblock.created",issuer.id,b)
	return b

func remove_block(id: String, removal_token: String = "") -> void:
	for b in blocks:
		if b.id==id and b.active:
			if b.has("deployment_id") and (removal_token!=b.deployment_id or not police.authorizes_removal(removal_token)):
				police.request_removal(b.deployment_id,"Removal requested"); return
			b.active=false
			if b.kind=="accident":
				for v in vehicles:
					if v.status=="ACCIDENT" and v.position.distance_to(b.position)<100: v.status="REMOVED"
			Map.roadblock_data.erase(b.id)
			if b.height<3 and b.kind!="emergency_lane": Map.set_closure(b.id,b.position,false)
			var edge: Dictionary = Map.roads[b.edge]
			if b.kind!="emergency_lane" and not blocks.any(func(other):return other.active and other.edge==b.edge and other.kind!="emergency_lane"): Map.graph.connect_points(edge.from,edge.to)
			emit_event("roadblock.removed",b.issuer,{"id":id})

func _vehicle_route(start: Vector2, destination: Vector2, emergency: bool = false, height: float = 0, known_traffic: Dictionary = {}) -> PackedVector2Array:
	return preload("res://scripts/vehicle_navigation.gd").route(self,start,destination,emergency,height,known_traffic)

func board(vehicle: Dictionary, passenger: Dictionary) -> bool:
	if passenger.health<=0: return false
	if passenger.get("riding","")!="" and passenger.riding!=vehicle.id: return false
	if passenger.id in vehicle.passengers: return true
	if passenger.health<=0 or passenger.get("indoor_id","")!="": return false
	if vehicle.passengers.size()>=vehicle.capacity or passenger.position.distance_to(vehicle.position)>65 or vehicle.speed>1 or passenger.state in ["SHELTERED","EXPOSED","SAFE"]: return false
	if passenger.id not in vehicle.passengers: vehicle.passengers.append(passenger.id)
	passenger.riding=vehicle.id; passenger.location_mode="VEHICLE"
	return true

func leave(vehicle: Dictionary, passenger: Dictionary) -> bool:
	if vehicle.speed>1 or passenger.id not in vehicle.passengers: return false
	vehicle.passengers.erase(passenger.id); passenger.riding=""; passenger.boarding_vehicle=""; passenger.position=vehicle.position; passenger.transport_height=0.0; passenger.location_mode="OUTDOOR"
	return true

func _move_vehicles(seconds: float) -> void:
	if manager.phase not in ["LIVING","EVACUATION","BOMB_FALL"]: return
	traffic.prepare_spatial(self,true)
	for vehicle in vehicles:
		vehicle.emergency_active=vehicle.kind!="Civilian" and (by_id[vehicle.driver].get("responding_to","")!="" or by_id[vehicle.driver].get("police_unit_busy",false))
	var ordered: Array=vehicles.duplicate()
	ordered.sort_custom(func(a,b):
		if a.emergency_active!=b.emergency_active: return a.emergency_active
		return a.id<b.id)
	for junction in junction_reservations.keys():
		var owner_id: String=junction_reservations[junction]
		for owner in vehicles:
			if owner.id==owner_id and (owner.position.distance_to(Map.graph.get_point_position(junction))>200 or owner.status in ["ACCIDENT","PARKED","REMOVED"]):
				junction_reservations.erase(junction)
				if owner.get("committed_junction",-1)==junction: owner.erase("committed_junction")
				if owner.get("stop_checked_junction",-1)==junction: owner.erase("stop_checked_junction")
	for v in ordered:
		var driver: Dictionary = by_id[v.driver]
		if driver.state in ["SHELTERED","EXPOSED","SAFE"] or driver.health<=0 or v.status in ["ACCIDENT","REMOVED","DESTROYED"] or driver.get("supervising_school",false): continue
		if driving.advance_recovery(v,seconds): traffic.update_vehicle(v); continue
		if v.get("boarding_stop",false):
			v.speed=move_toward(v.speed,0,v.braking*seconds)
			v.position+=Vector2.from_angle(v.heading)*v.speed*seconds
			for id in v.passengers: by_id[id].position=v.position
			traffic.update_vehicle(v)
			if v.speed<=.01: v.status="PARKED"; v.boarding_stop=false
			continue
		if driver.get("evacuation_group","")!="": continue
		if driver.get("police_unit_busy",false):
			var unit: Dictionary=police.unit_for(driver.get("police_unit_id",""))
			if unit.get("vehicle","")!=v.id or unit.get("state","")!="EN_ROUTE": continue
		if driver.get("riding","")!="" and driver.riding!=v.id: continue
		if driver.get("indoor_id","")!="" or driver.get("pickup_walk",false) or driver.get("group_on_foot",false): continue
		if driver.get("boarding_vehicle","")!="" and driver.boarding_vehicle!=v.id: continue
		var target: String = driver.social_target if not driver.social_target.is_empty() else driver.objective
		if target.is_empty(): continue
		var point: Vector2
		if driver.known_locations.has(target): point=driver.known_locations[target].position
		elif driver.beliefs.has(target): point=driver.beliefs[target].position
		else: continue
		if v.status=="PARKED":
			# Driver must walk to their parked car before boarding.
			if driver.position.distance_to(v.position)>35:
				_walk_toward(driver,v.position,driver.movement_speed,seconds)
				continue
			if not traffic.departure_clear(v,vehicles): v.driving_reason="WAIT_PARKING_EXIT"; continue
			if not driver.get("police_unit_busy",false) and not companion_runtime.prepare_vehicle_departure(driver,v): continue
			if not board(v,driver): continue
			for id in driver.relationships:
				if not driver.get("police_unit_busy",false) and by_id[id].get("indoor_id","")=="" and by_id[id].position.distance_to(v.position)<45 and (by_id[id].get("boarding_vehicle","")==v.id or by_id[id].family_id==driver.family_id): board(v,by_id[id])
			if not driver.get("police_unit_busy",false) and not households.prepare_departure(v,driver): continue
			v.status="MOVING"; Map.release_parking(v.id); traffic.reservations.erase(v.id); emit_event("vehicle.departed",v.id,{"driver":driver.id})
		if not traffic.parking_maneuver(v) and (v.destination!=target or (manager.elapsed_seconds>=v.next_route and v.status in ["BLOCKED","CONGESTED"] and v.get("driving_mode","") not in ["EVADING","RETURNING"])):
			if not v.get("parking_exit",PackedVector2Array()).is_empty():
				var exit_path: PackedVector2Array=v.parking_exit
				v["parking_exit_end"]=exit_path.size()-1
				var onward: PackedVector2Array=daily.driving_route(v,exit_path[-1],point,v.kind!="Civilian",v.height,driver.get("known_traffic",{})) if (manager.phase=="LIVING" and not driver.get("police_unit_busy",false)) or driver.pickup_target!="" else _vehicle_route(exit_path[-1],point,v.kind!="Civilian",v.height,driver.get("known_traffic",{}))
				v.route=exit_path.duplicate(); v.route.append_array(onward); v.parking_exit=PackedVector2Array()
			else: v.route=daily.driving_route(v,v.position,point,v.kind!="Civilian",v.height,driver.get("known_traffic",{})) if (manager.phase=="LIVING" and not driver.get("police_unit_busy",false)) or driver.pickup_target!="" else _vehicle_route(v.position,point,v.kind!="Civilian",v.height,driver.get("known_traffic",{}))
			if driver.get("police_unit_busy",false):
				var dispatch: Dictionary=police.request_for(police.unit_for(driver.police_unit_id).request)
				if not dispatch.is_empty(): v.route.append_array(dispatch.parking_bay.approach)
			v.route_index=1; v.destination=target; v.next_route=manager.elapsed_seconds+5
			if v.route.size()>1 and (v.route[1]-v.position).normalized().dot(Vector2.from_angle(float(v.heading)))<-.2 and not Map.parking_lots.any(func(lot):return lot.bounds.grow(8).has_point(v.position)):
				v.route=PackedVector2Array(); v.driving_reason="TURNAROUND_REQUIRES_SAFE_RECOVERY"
		if v.route.is_empty(): v.status="BLOCKED"; v.speed=move_toward(v.speed,0,v.braking*seconds); continue
		if v.route_index>=v.route.size(): continue
		if manager.elapsed_seconds>=v.get("next_edge_update",0):
			var nearest: Dictionary = Map.nearest_edge(v.position,true,v.height)
			v.edge=Map.roads.find(nearest.edge); v.next_edge_update=manager.elapsed_seconds+2
		var blocked: bool = police.controls_vehicle(v)
		for block in blocks:
			if block.kind=="emergency_lane": continue
			var approach: Vector2=v.route[v.route_index]-v.position
			var toward: bool=(block.position-v.position).dot(approach)>0
			if block.active and driving.block_requires_stop(v,block) and absf(block.height-v.height)<3 and toward and v.position.distance_to(block.position)<v.speed*v.speed/(2*v.braking)+45 and (block.kind not in EMERGENCY_PASS or v.kind=="Civilian"):
				blocked=true
				if not driver.social_beliefs.has("road:"+block.id): acquire(driver,"road:"+block.id,"closed",driver.id,1,"direct observation")
		var desired: float = v.max_speed*(1-config.traffic_density*.45)
		var tangent: Vector2 = (v.route[v.route_index]-v.position).normalized()
		var constraint: Dictionary=driving.plan(v,tangent,desired,seconds)
		desired=constraint.speed
		if blocked: desired=0
		v.speed=move_toward(v.speed,desired,(v.braking if desired<v.speed else v.acceleration)*seconds)
		# A fixed step may never cross a closed stop line or the protected bumper gap.
		if is_finite(float(constraint.travel)): v.speed=minf(v.speed,maxf(0,float(constraint.travel))/seconds)
		v.congestion_time=float(v.get("congestion_time",0))+seconds if desired<10 else 0.0
		v.status="BLOCKED" if blocked else "CONGESTED" if v.congestion_time>8 else "MOVING"
		if v.status=="CONGESTED" and v.edge>=0:
			if not driver.has("known_traffic"): driver.known_traffic={}
			driver.known_traffic[v.edge]=manager.elapsed_seconds
			if not driver.social_beliefs.has("traffic:"+str(v.edge)): acquire(driver,"traffic:"+str(v.edge),"congested",driver.id,1,"direct observation")
		if desired<10:
			counters.congested_seconds+=seconds
			if int(manager.elapsed_seconds)%15==0 and manager.elapsed_seconds>=v.get("next_congestion",0):
				v.next_congestion=manager.elapsed_seconds+15; emit_event("traffic.congestion",v.id,{"edge":v.edge})
		var proxy := {"position":v.position,"route":v.route,"route_index":v.route_index,"movement_speed":maxf(0,v.speed)}
		var predicted: Vector2=v.position.move_toward(v.route[v.route_index],v.speed*seconds)
		for block in blocks:
			if block.active and driving.block_requires_stop(v,block) and absf(block.height-v.height)<3 and (block.kind not in EMERGENCY_PASS or v.kind=="Civilian") and Geometry2D.get_closest_point_to_segment(block.position,v.position,predicted).distance_to(block.position)<28:
				if predicted.distance_to(block.position)<v.position.distance_to(block.position): proxy.movement_speed=.001; v.speed=0
		var turn: float=wrapf(tangent.angle()-float(v.heading),-PI,PI)
		v.steering=clampf(turn,-.6,.6)
		v.heading=rotate_toward(float(v.heading),tangent.angle(),seconds*1.8)
		var result := Routes.move(proxy,seconds)
		v.position=proxy.position; v.route_index=proxy.route_index
		if int(v.get("parking_exit_end",0))>0 and v.route_index>int(v.parking_exit_end): v.parking_exit_end=0; v.parking_bay=""
		traffic.update_vehicle(v)
		if manager.elapsed_seconds>=v.get("next_height_update",0):
			v.target_height=Map.route_height(v.position,tangent,float(v.get("height",0))); v.next_height_update=manager.elapsed_seconds+.5
		v.height=move_toward(float(v.get("height",0)),float(v.get("target_height",0)),seconds*4)
		for id in v.passengers:
			by_id[id].position=v.position; by_id[id].transport_height=v.height

		if result.arrived: v.pending_arrival=target
	traffic.end_spatial_step()

func _finish_vehicle_arrivals() -> void:
	for v in vehicles:
		if not v.has("pending_arrival"): continue
		var target: String=v.pending_arrival
		v.erase("pending_arrival")
		if v.status in ["ACCIDENT","REMOVED","DESTROYED"]: continue
		if police.vehicle_arrived(v,target): continue
		v.speed=0; v.status="ARRIVED"
		companion_runtime.vehicle_arrived(v)
		for id in v.passengers.duplicate():
			leave(v,by_id[id])
			if by_id[id].get("emergency_evacuating",false):
				by_id[id].group_on_foot=true; by_id[id].force_route_replan=true
			if target.begins_with("medical:") and id!=v.driver:
				by_id[id].medical_evacuated=true; by_id[id].current_goal="Receiving care at Medical Station"
				emit_event("emergency.patient_evacuated",id,{"vehicle":v.id,"destination":target})
			if by_id[id].beliefs.has(target):
				by_id[id].objective=target; manager.admit_arrival(by_id[id]); counters.arrivals.append(manager.elapsed_seconds-manager.alarm_started_seconds)
		var driver: Dictionary=by_id[v.driver]
		if (manager.phase=="LIVING" and not driver.get("emergency_evacuating",false)) or driver.pickup_target!="":
			var retained_target: String=driver.social_target
			daily.vehicle_arrived(v,driver)
			if driver.pickup_target!="": driver.social_target=retained_target
		households.vehicle_arrived(driver,target)
		v.destination=""; v.status="PARKED"
		emit_event("vehicle.arrived",v.id,{"destination":target})

func accident(v: Dictionary) -> void:
	traffic.impact(self,v,{},maxf(3,v.speed/10),"loss_of_control")

func move_social(a: Dictionary, seconds: float) -> bool:
	if a.state in ["SHELTERED","EXPOSED","SAFE"]: return false
	if a.get("police_unit_busy",false): return true
	if a.get("evacuation_group","")!="": return true
	if cognition.move(a,seconds): return true
	if a.id == "SPECIAL_I_AM_LEGEND" and a.get("riding", "") == "" and a.get("indoor_id", "") == "":
		for dog in companions:
			if dog.owner_id != a.id or dog.health <= 0 or dog.get("shelter_id", "") != "": continue
			var separation: float = a.position.distance_to(dog.position)
			if separation > 24.0 and separation <= manager.living.observation_radius:
				a.current_goal = "Pause and reunite with German Shepherd"
				_walk_toward(a,dog.position,minf(a.movement_speed,float(dog.speed)),seconds)
				return true
	if a.get("pickup_walk",false) and a.health>0: return households.pickup_walk(a,seconds)
	if a.get("indoor_id","")!="" and a.health>0:
		if a.state in ["STAYING_HOME","FROZEN","WAITING"] and manager.elapsed_seconds<float(a.get("wait_until",0)): return true
		if a.alarm_confidence>0 or a.social_beliefs.has("nuclear") or a.social_beliefs.has("school_destination") or a.get("group_destination","")!="":
			daily.interiors.exit_building(a,seconds)
		return true
	if a.health<=0 or a.get("medical_evacuated",false): return true
	if a.get("riding","")!="": return true
	if households.move_member(a,seconds): return true
	if not a.vehicle_id.is_empty() and not a.get("supervising_school",false) and not a.get("group_on_foot",false):
		for v in vehicles:
			if v.id==a.vehicle_id and v.status not in ["ACCIDENT","REMOVED"] and (not a.objective.is_empty() or not a.social_target.is_empty()): return true
	if a.age<18:
		var supervisor: String = a.get("supervisor","")
		for guardian in a.guardians:
			if daily.interiors.can_see(a,by_id[guardian]) and by_id[guardian].position.distance_to(a.position)<55: supervisor=guardian; a.supervisor=guardian; break
		if not supervisor.is_empty() and by_id.has(supervisor):
			var adult: Dictionary = by_id[supervisor]
			var visible: bool=daily.interiors.can_see(a,adult)
			var remembered: Dictionary=a.known_locations.get(supervisor,{})
			if not visible and remembered.is_empty(): return true
			var target_point: Vector2=adult.position if visible else remembered.position
			manager._set_state(a,"MOVING"); a.current_goal="Follow guardian/staff "+supervisor
			if a.position.distance_to(target_point)>25:
				_walk_toward(a,target_point,a.run_speed,seconds)
			if visible and adult.state=="SHELTERED" and a.position.distance_to(adult.position)<55:
				a.objective=adult.shelter_id; manager.admit_arrival(a)
			return true
		# Unsupervised children seek a known guardian, rather than using adult LLM policy.
		if a.guardians.size()>0: a.social_target=a.guardians[0]
	if a.social_target.is_empty(): return a.age<18
	var known: Dictionary = a.known_locations.get(a.social_target,{})
	if known.is_empty(): a.social_target=""; return false
	if a.position.distance_to(known.position)<35:
		a.social_target=""; return false
	_walk_toward(a,known.position,a.movement_speed,seconds)
	return true

func snapshot_text() -> String:
	var casualties: int=manager.agents.filter(func(a):return a.get("injury","")=="FATAL").size()
	var injured: int=manager.agents.filter(func(a):return a.get("injury","") in ["MINOR","SERIOUS"]).size()
	var reunited: int = families.filter(func(f):return f.status=="REUNITED").size()
	return "DIRECTOR / OMNISCIENT SOCIAL METRICS\n%d agents | %d civilians / %d authorities | %d children\nIQ synthetic: sampled mean %.2f / SD %.2f\nFamilies %d reunited / %d separated | School %s\nPhones: %d calls / %d texts | %d posts / %d shares / %d corrections\nAlerts: %d deliveries | Orders %d / compliance %d\nVehicles %d | Accidents %d | Active closures %d\nCongestion %.1f vehicle-seconds | Mode %s"%[manager.agents.size(),config.civilians,config.authorities,config.children,iq_stats.mean,iq_stats.std,reunited,families.size()-reunited,school_status,counters.calls,counters.texts,counters.posts,counters.shares,counters.corrections,counters.alerts_delivered,counters.orders,counters.compliance,vehicles.size(),counters.accidents,blocks.filter(func(b):return b.active).size(),counters.congested_seconds,config.execution_mode]+"\nTraffic casualties: %d fatal / %d injured | Secured scenes %d | Recovered %d"%[casualties,injured,traffic.scenes.filter(func(scene):return scene.secured).size(),traffic.scenes.filter(func(scene):return scene.recovered).size()]+daily.summary_text()+"\nDriving AI: %s / %d choices / %d fallbacks"%[driving.status,driving.completed,driving.fallbacks]

func load_replay(path: String) -> bool:
	close()
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null: return false
	var frames := []
	while not file.eof_reached():
		var line := file.get_line()
		if line.strip_edges().is_empty(): continue
		var packet: Variant = JSON.parse_string(line)
		if packet is Dictionary and packet.get("record_type")=="frame": frames.append(decode(packet))
	if frames.is_empty(): return false
	replay_frames=frames; replay_cursor=0; replaying=true
	manager.ai_bridge.reset_run()
	manager.running=false
	apply_replay_frame(0)
	return true

func apply_replay_frame(index: int) -> void:
	if index<0 or index>=replay_frames.size(): return
	replay_cursor=index
	var frame: Dictionary = replay_frames[index]
	Map.traffic_time=float(frame.get("traffic_time",frame.get("time",0)))
	# Keep avatar dictionary references intact for an already initialized matching run.
	for i in range(mini(manager.agents.size(),frame.agents.size())):
		for key in frame.agents[i]: manager.agents[i][key]=frame.agents[i][key]
		if not frame.agents[i].has("indoor_id"):
			manager.agents[i].indoor_id=""; manager.agents[i].interior_transition=""
			manager.agents[i].location_mode="VEHICLE" if manager.agents[i].get("riding","")!="" else "OUTDOOR"
	for i in range(mini(manager.shelters.size(),frame.shelters.size())):
		for key in frame.shelters[i]: manager.shelters[i][key]=frame.shelters[i][key]
	if frame.has("environment_events"): manager.environment_events.assign(frame.environment_events)
	if frame.has("evacuation_state"):
		evacuation.operations=frame.evacuation_state.operations; evacuation.groups=frame.evacuation_state.groups; evacuation.sequence=int(frame.evacuation_state.sequence)
	else:
		evacuation.operations.clear(); evacuation.groups.clear()
		for a in manager.agents: a.evacuation_group=""; a.evacuation_member_status=""
	if frame.has("police_state"):
		police.units=frame.police_state.units; police.requests=frame.police_state.requests; police.stations=frame.police_state.stations
	else:
		police.requests.clear(); police.units.clear()
		for a in manager.agents:
			a.police_unit_busy=false; a.police_animation=""; a.erase("police_unit_id")
	vehicles=frame.vehicles; blocks=frame.blocks; families=frame.families; counters=frame.counters
	if frame.has("companions"):
		for i in range(mini(companions.size(),frame.companions.size())): companions[i].merge(frame.companions[i],true)
	traffic.scenes=frame.get("accident_scenes",[])
	if frame.has("interior_state"):
		for id in frame.interior_state:
			if daily.interiors.rooms.has(id): daily.interiors.rooms[id].merge(frame.interior_state[id],true)
	# Older recordings have no dimensions; upgrade their visual records safely.
	for v in vehicles:
		if not v.has("length"):
			var model: String={"Police":"police","Medical":"ambulance","Fire":"fire_engine","Civil protection":"rescue_truck"}.get(v.kind,"sedan")
			var spec: Dictionary=preload("res://scripts/vehicle_catalog.gd").TYPES[model]
			v.merge(spec); v.body_height=spec.height
			v.height=float(frame.vehicles[vehicles.find(v)].get("height",0))
			v.heading=float(v.get("parking_heading",0))
	Map.restore_parking(vehicles)
	alerts=frame.alerts; posts=frame.posts; school_status=frame.school_status
	var old_phase: String=manager.phase
	manager.elapsed_seconds=frame.time; manager.phase=frame.phase; manager.remaining_seconds=frame.remaining
	manager.summary=frame.get("summary",{})
	if frame.has("structures"): manager.structures.assign(frame.structures)
	if frame.has("world_objects"): manager.world_objects.assign(frame.world_objects)
	if frame.get("shelter_storyteller",{}).get("schema_version",0)==1:
		shelter_life.social=self; shelter_life.manager=manager
		if shelter_life.config.is_empty(): shelter_life.config=JSON.parse_string(FileAccess.get_file_as_string("res://resources/shelter_life.json"))
		shelter_life.storyteller.restore(frame.shelter_storyteller,shelter_life)
	manager.survival.restore(frame.get("survival_lifecycle",{}),manager)
	if frame.phase=="IMPACT" and old_phase!="IMPACT": manager.impact_occurred.emit(manager.summary)
	manager.simulation_updated.emit()

func perform_action(a: Dictionary, decision: Dictionary) -> bool:
	var target: String=decision.target
	if a.get("police_unit_busy",false) and decision.action in ["FIND_FAMILY","DRIVE_TO_SHELTER"]: return false
	match decision.action:
		"CALL","TEXT":
			if target not in a.phone.contacts: return false
			return send_phone(a,target,{"subject":"agent_message","value":decision.message,"position":a.position},"call" if decision.action=="CALL" else "text")
		"POST":
			return not publish_post(a,"agent_claim",decision.message).is_empty()
		"FIND_FAMILY":
			if not a.relationships.has(target) or not a.known_locations.has(target): return false
			if a.get("evacuation_group","")!="": evacuation.leave_group(a,"Choose to find family")
			a.social_target=target; a.current_goal="Find family "+target; return true
		"DRIVE_TO_SHELTER":
			if a.vehicle_id.is_empty() or not a.beliefs.has(target) or a.beliefs[target].unavailable: return false
			if a.get("evacuation_group","")!="": evacuation.leave_group(a,"Choose own vehicle evacuation")
			a.objective=target; manager._set_state(a,"MOVING"); return true
		"CREATE_ROADBLOCK":
			return authorities.request_roadblock(a)
		"REMOVE_ROADBLOCK":
			return authorities.request_block_removal(a,target)
		"ISSUE_ALERT":
			return not issue_alert(a,target if target in ["nuclear","evacuate","shelter_in_place","road_closure","school","final"] else "evacuate",decision.message,"Seek verified nearby protection",a.position,1000).is_empty()
	return false

func flush_events() -> void:
	if sending or outbox.is_empty() or Time.get_ticks_msec()<next_send: return
	next_send=Time.get_ticks_msec()+50
	sending=true
	var batch: Array=outbox.slice(0,32)
	var request:=HTTPRequest.new(); request.timeout=5; manager.ai_bridge.add_child(request)
	event_request=request
	request.request_completed.connect(func(result,code,_headers,_body):
		event_request=null
		sending=false
		if result==HTTPRequest.RESULT_SUCCESS and code==200:
			for _i in range(batch.size()):
				if not outbox.is_empty(): outbox.pop_front()
		request.queue_free())
	if request.request(manager.ai_config.service_url+"/social/events",["Content-Type: application/json"],HTTPClient.METHOD_POST,JSON.stringify({"events":batch}))!=OK:
		sending=false; event_request=null; request.queue_free()

func pedestrian_blocked(a: Dictionary, seconds: float) -> bool:
	if a.route_index>=a.route.size(): return false
	var next: Vector2=a.position.move_toward(a.route[a.route_index],a.movement_speed*seconds)
	for b in blocks:
		if not b.active or b.kind=="emergency_lane" or b.height>3: continue
		if next.distance_to(b.position)>a.position.distance_to(b.position) and a.position.distance_to(b.position)<45: continue
		var distance: float=Geometry2D.get_closest_point_to_segment(b.position,a.position,next).distance_to(b.position)
		if distance<45:
			if not a.social_beliefs.has("road:"+b.id): acquire(a,"road:"+b.id,"closed",a.id,1,"direct observation")
			if not a.objective.is_empty() and a.beliefs.has(a.objective):
				a.route=Map.free_route(a.position,a.beliefs[a.objective].position); a.route_index=1
			return true
	return false

func experiment_metrics() -> Dictionary:
	var reunion_count: int=families.filter(func(f):return f.status=="REUNITED").size()
	var reached: Dictionary={}
	for alert in alerts:
		for id in alert.recipients: reached[id]=true
	var arrivals:=[]
	var missing_members:=0
	var stress_bins: Array=[0,0,0,0,0]
	var agreement: Dictionary={}
	for a in manager.agents:
		if (a.get("sheltered_at") is float or a.get("sheltered_at") is int) and is_finite(float(a.sheltered_at)): arrivals.append(a.sheltered_at-manager.alarm_started_seconds)
		stress_bins[clampi(int(a.stress/20),0,4)]+=1
		for id in a.relationships:
			if not a.known_locations.has(id) or manager.elapsed_seconds-a.known_locations[id].timestamp>60: missing_members+=1
		for subject in a.social_beliefs:
			if not agreement.has(subject): agreement[subject]={}
			var value: String=str(a.social_beliefs[subject].claimed_value)
			agreement[subject][value]=int(agreement[subject].get(value,0))+1
	var consensus:=0.0
	for subject in agreement:
		var total:=0
		var peak:=0
		for count in agreement[subject].values(): total+=int(count); peak=maxi(peak,int(count))
		consensus+=float(peak)/maxi(1,total)
	var arrival_mean:=0.0
	for value in arrivals: arrival_mean+=value
	return {"schema_version":1,"seed":manager.seed_value,"world":manager.world_metadata(),"config":config,"survival_rate":float(manager.summary.get("survivors",0))/manager.agents.size() if manager.phase=="IMPACT" else null,
		"mean_shelter_arrival_seconds":arrival_mean/arrivals.size() if not arrivals.is_empty() else null,
		"family_reunification_rate":float(reunion_count)/families.size() if not families.is_empty() else null,"separated_families":families.size()-reunion_count,
		"stale_or_unknown_family_contacts":missing_members,"accidents":counters.accidents,"congestion_vehicle_seconds":counters.congested_seconds,
		"rumor_shares":counters.shares,"rumor_corrections":counters.corrections,"trust_changes":counters.trust_changes,
		"authority_compliance_events":counters.compliance,"authority":authorities.metrics(),"alert_unique_reach":reached.size(),"consensus_among_acquired_beliefs":consensus/agreement.size() if not agreement.is_empty() else null,
		"stress_histogram":stress_bins,"shelter_social":shelter_life.dynamics.metrics(),"shelter_storyteller":shelter_life.storyteller.metrics(),"ai":manager.ai_bridge.metrics.duplicate(true)}

func finalize() -> void:
	var metrics:=experiment_metrics()
	_record({"record_type":"metrics","metrics":metrics})
	_record({"record_type":"frame","environment_events":manager.environment_events,"time":manager.elapsed_seconds,"phase":manager.phase,"remaining":manager.remaining_seconds,"agents":manager.agents,"shelters":manager.shelters,"vehicles":vehicles,"accident_scenes":traffic.scenes,"interior_state":daily.interiors.rooms,"traffic_signals":Map.traffic_signals,"traffic_time":Map.traffic_time,"blocks":blocks,"families":families,"school_status":school_status,"alerts":alerts,"posts":posts,"counters":counters,"authority_state":authorities.export_state(),"police_state":police.snapshot(),"evacuation_state":evacuation.snapshot(),"summary":manager.summary,"structures":manager.structures,"world_objects":manager.world_objects,"sirens":manager.sirens})
	var file:=FileAccess.open("res://outputs/phase5/"+manager.ai_bridge.run_id+"-metrics.json",FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(encode(metrics),"  ",true,true))

func capture_frame() -> Dictionary:
	var frame: Dictionary={"record_type":"frame","survival_lifecycle":manager.survival.snapshot(),"shelter_storyteller":shelter_life.storyteller.snapshot(),"environment_events":manager.environment_events,"time":manager.elapsed_seconds,"phase":manager.phase,"remaining":manager.remaining_seconds,"agents":manager.agents,"shelters":manager.shelters,"vehicles":vehicles,"accident_scenes":traffic.scenes,"interior_state":daily.interiors.rooms,"traffic_signals":Map.traffic_signals,"traffic_time":Map.traffic_time,"blocks":blocks,"families":families,"school_status":school_status,"alerts":alerts,"posts":posts,"counters":counters,"authority_state":authorities.export_state(),"police_state":police.snapshot(),"evacuation_state":evacuation.snapshot(),"summary":manager.summary,"structures":manager.structures,"world_objects":manager.world_objects,"sirens":manager.sirens}
	_record(frame)
	return frame


func begin_shelter_life() -> void:
	next_shelter_frame=manager.elapsed_seconds
	shelter_life.initialize(self)

func shelter_life_text() -> String:
	if shelter_life==null or not shelter_life.config: return ""
	var measured: Dictionary=shelter_life.dynamics.metrics()
	return "Shelter life: day %d / %d | %d residents | disputes %d open / %d resolved | cooperation %d | children supervised %d/%d | mean morale %s"%[shelter_life.day,shelter_life.config.duration_days,measured.residents,measured.open_conflicts,measured.get("conflicts_resolved",0),measured.get("cooperative_acts",0),measured.supervised_children,measured.children,str(measured.emotions.morale)]

func _walk_toward(a: Dictionary, point: Vector2, speed: float, seconds: float) -> void:
	if not a.has("social_walk_route") or point.distance_to(a.get("social_walk_target",Vector2.INF))>30 or manager.elapsed_seconds>=a.get("social_walk_replan",0):
		a.social_walk_route=Map.free_route(a.position,point); a.social_walk_index=1; a.social_walk_target=point; a.social_walk_replan=manager.elapsed_seconds+3
	var proxy: Dictionary={"position":a.position,"route":a.social_walk_route,"route_index":a.social_walk_index,"movement_speed":speed}
	Routes.move(proxy,seconds); a.position=proxy.position; a.social_walk_index=proxy.route_index

func impact() -> void:
	var blast=preload("res://scripts/blast_model.gd")
	for v in vehicles:
		var load: float=blast.intensity(v.position,manager.nuclear)
		v.health=maxf(0,v.health-load*100)
		if v.health<=0: v.status="DESTROYED"; v.speed=0
	if blast.intensity(school_position,manager.nuclear)>=1: school_status="DESTROYED"
	companion_runtime.impact()

func all_clear() -> void:
	companion_runtime.all_clear()

func send_group(sender: Dictionary, group: String, content: Dictionary) -> int:
	if not sender.phone.groups.has(group): return 0
	var count:=0
	for id in sender.phone.groups[group]:
		if id!=sender.id and send_phone(sender,id,content,"family_group"): count+=1
	return count

func send_dm(sender: Dictionary, target: String, content: Dictionary) -> bool:
	if not sender.social_user or not by_id.has(target) or not by_id[target].social_user: return false
	return send_phone(sender,target,content,"social_dm")
