extends SceneTree
const Manager=preload("res://scripts/simulation_manager.gd")
const Life=preload("res://scripts/shelter_life.gd")
const Controls=preload("res://scripts/shelter_event_controls.gd")
var manager: Node
var life: RefCounted
var story: RefCounted
var people: Array=[]
var tech: Dictionary
var medic: Dictionary
var fire: Dictionary
var commander: Dictionary
var civilian: Dictionary
var child: Dictionary
var police: Dictionary
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1; printerr("FAIL: "+label)
func place(a: Dictionary,room: String) -> void:
	for record in life.rooms.values(): record.occupants.erase(a.id); record.occupant_positions.erase(a.id); record.reserved_positions.erase(a.id)
	a.shelter_id=life.rooms[room].shelter_id; a.shelter_room_id=room; a.shelter_activity_state="ACTIVE"
	a.position=life.rooms[room].position; a.previous_position=a.position
	life.rooms[room].occupants.append(a.id)
func fresh() -> void:
	manager.elapsed_seconds=0.0; manager.phase="IMPACT"; manager.running=true
	manager.social.config.event_frequency=1.0
	for a in manager.agents: a.state="IDLE"; a.shelter_life_active=false
	for refuge in manager.shelters:
		refuge.base_operational=true; refuge.operational=true; refuge.accepting=true; refuge.manual_door_state=""; refuge.manual_accessible=true; refuge.manual_safety_status="SAFE"; refuge.structural_state="INTACT"
		refuge.maintenance_condition=100.0; refuge.erase("storyteller_conditions")
	for i in range(people.size()):
		var a: Dictionary=people[i]
		a.state="SHELTERED"; a.shelter_id="S1"; a.health=100.0; a.age=35; a.hunger=18.0; a.thirst=18.0; a.fatigue=0.0; a.stress=20.0; a.fear=15.0
		a.cooperation=80.0; a.empathy=80.0; a.role="Authority" if i in [1,2,3,6] else "Civilian"
		a.family_id=""; a.relationships={}; a.guardians=[]; a.shelter_relationships={}; a.emergency_exit_active=false; a.skills={}
		a.erase("evacuating_shelter"); a.erase("planned_transfer_shelter")
	tech.occupation="Technician"; medic.occupation="Medical"; fire.occupation="Fire"; commander.occupation="Crisis commander"; civilian.occupation="Resident"; child.occupation="School student"; police.occupation="Police"
	child.age=10; child.family_id="EVENT-FAMILY"; civilian.family_id="EVENT-FAMILY"; child.relationships[civilian.id]="parent"; civilian.relationships[child.id]="child"; child.guardians=[civilian.id]
	life.initialize(manager.social); story=life.storyteller; story.generation_paused=true
	for a in people: place(a,"S1:DINING"); a.current_activity_code="READ"
func working(a: Dictionary,event: Dictionary) -> void:
	place(a,story.response_room(event,a)); a.current_activity_code=story.config.events[event.event_type].activity
	a.shelter_event_assignment=event.event_id; story.learn(a,event,"direct observation",a.id)
func run() -> void:
	manager=Manager.new(); root.add_child(manager); manager.set_process(false)
	check(manager.load_settings(),"settings")
	manager.social_config.llm_agents=0; manager.social_config.spontaneous_actions=false
	manager.initialize_run(); manager.ai_bridge.set_process(false); manager.social.close(); manager.social.next_send=INF
	people=manager.agents.slice(0,7)
	tech=people[0]; medic=people[1]; fire=people[2]; commander=people[3]; civilian=people[4]; child=people[5]; police=people[6]
	life=manager.social.shelter_life
	fresh()
	check(story.catalog().size()==29,"all 29 requested event types are available")
	var names: Array=story.catalog()
	for name in names:
		fresh()
		if name=="food_theft": civilian.cooperation=10.0; civilian.hunger=95.0; child.hunger=90.0; life.shelters.S1.person_days=1.0
		var fixture_id: String=story.trigger(name,"S1",.3)
		check(not fixture_id.is_empty(),"catalog event can be triggered: "+name)
		if fixture_id.is_empty(): continue
		var fixture: Dictionary=story.find(fixture_id)
		var actor: Dictionary={"technical":tech,"medical":medic,"fire_safety":fire,"emergency":commander,"security":police,"social":commander,"care":civilian,"any":civilian}[story.config.events[name].skill]
		# A refuser must be mediated by a different resident.
		if actor.get("refusing_work_event","")==fixture_id: actor=medic
		working(actor,fixture)
		check(story.respond(fixture_id,actor,8.0) and fixture.status=="RESOLVED","catalog event has a feasible role-specific resolution: "+name)
	fresh()
	check(story.trigger("unknown","S1").is_empty() and story.trigger("fire","S1",NAN).is_empty(),"invalid controls are rejected")
	var id: String=story.trigger("generator_failure","S1",.4)
	var event: Dictionary=story.find(id)
	check(not id.is_empty() and event.origin=="MANUAL TEST" and event.manual,"manual events are clearly labeled")
	check(not life.shelters.S1.power and manager.environment_events.any(func(e):return e.event_id==id),"infrastructure truth and shared storyteller stream are integrated")
	check(not story.knows(tech,id) and not story.request_response(id,tech),"a technician does not receive omniscient incident knowledge")
	place(civilian,event.room_id); story.observe()
	check(story.knows(civilian,id) and story.knows(tech,id) and tech.shelter_event_knowledge[id].source==civilian.id,"local witness informs a technician through working shelter communications")
	check(not story.request_response(id,civilian),"unskilled resident cannot repair a generator")
	tech.current_activity_code="EAT"
	check(not story.request_response(id,tech),"noncritical maintenance does not interrupt a meal")
	tech.current_activity_code="READ"
	check(story.request_response(id,tech) and tech.shelter_activity_state=="MOVING","informed technician follows physical room navigation")
	var progress: float=event.progress
	check(not story.respond(id,tech,1.0) and event.progress==progress,"travel time does not count as repair work")
	working(tech,event); tech.stress=100.0
	check(not story.respond(id,tech,1.0),"overwhelmed technician cannot work immediately")
	tech.stress=0.0
	life._complete_activity(tech)
	check(not life.shelters.S1.power and event.progress==0.0,"routine completion cannot bypass storyteller repair work")
	life.shelters.S1.spare_parts=0.0
	story.respond(id,tech,4.0)
	check(event.active_status and not life.shelters.S1.power,"repair requires actual spare parts")
	life.shelters.S1.spare_parts=2.0
	check(story.respond(id,tech,.1) and event.status=="RESOLVED" and life.shelters.S1.power and life.shelters.S1.spare_parts==1,"completed skilled work restores power and consumes parts")
	check(story.trigger("generator_failure","S1",.3).is_empty(),"resolved event cooldown blocks immediate recurrence")
	story.elapsed_hours+=19
	check(not story.trigger("generator_failure","S1",.3).is_empty(),"event can recur after cooldown")
	fresh()
	id=story.trigger("communication_failure","S1",.4)
	event=story.find(id)
	place(civilian,event.room_id); story.observe()
	check(story.knows(civilian,id) and not story.knows(tech,id),"communication failure blocks remote reports")
	working(tech,event); story.respond(id,tech,4)
	check(life.shelters.S1.communications,"physical repair restores communications")
	fresh()
	id=story.trigger("fire","S1",.4); event=story.find(id)
	working(tech,event)
	check(not story.respond(id,tech,2),"technical role cannot substitute for fire-safety skill")
	working(fire,event)
	check(story.respond(id,fire,3) and not life.shelters.S1.fire,"firefighter can resolve fire with physical work")
	# Existing external emergencies retain their own authority and consequences.
	var external: String=manager.emergency.add_event("fire",manager.shelter_by_id.S1.position,{"shelter_id":"S1","duration":100,"severity":.7})
	manager.emergency.tick(.1); story.project("S1")
	check(not external.is_empty() and life.shelters.S1.fire,"shelter projection preserves an independently active external fire")
	manager.emergency.clear_event(external)
	fresh()
	id=story.trigger("injury","S1",.6); event=story.find(id)
	var patient: Dictionary=manager.social.by_id[event.patient]
	var health: float=patient.health; working(medic,event); story.respond(id,medic,3)
	check(patient.health>health and life.shelters.S1.medical_supplies<6.5,"medic treats simplified injury and consumes supplies")
	life.shelters.S1.medical_supplies=0.0; civilian.health=60.0
	place(medic,"S1:DINING"); place(civilian,"S1:DINING"); life._assist_patient(medic)
	check(civilian.health==60.0,"medical shortage also restricts ordinary medical assistance")
	fresh()
	id=story.trigger("water_pump_failure","S1",.4)
	check(not life.shelters.S1.water,"pump failure disables drinkable water")
	var thirst: float=civilian.thirst; life._update_needs(civilian,60/life.routine_clock_rate()*60)
	check(civilian.thirst>thirst,"water interruption affects resident needs")
	fresh()
	id=story.trigger("air_filtration_failure","S1",.5); event=story.find(id)
	health=civilian.health; story.consequences(event,1.0)
	check(not life.shelters.S1.air and civilian.health<health,"shared air failure has a simplified shelter-wide survival consequence")
	fresh()
	id=story.trigger("door_malfunction","S1",.5); event=story.find(id)
	manager.emergency.refresh_shelters()
	check(manager.shelter_by_id.S1.door_status=="BLOCKED" and not life.blocked_doors.is_empty(),"door malfunction blocks physical threshold and room route")
	working(tech,event)
	check(story.respond(id,tech,4),"technician can work on a blocked door from the reachable side")
	manager.emergency.refresh_shelters()
	check(life.blocked_doors.is_empty() and manager.shelter_by_id.S1.door_status=="OPEN","repair clears owned door restrictions")
	fresh()
	id=story.trigger("flooding","S1",.7); event=story.find(id); place(civilian,event.room_id)
	manager.emergency.refresh_shelters()
	check(manager.shelter_by_id.S1.safety_status=="UNSAFE","severe shelter events project into existing safety decisions")
	health=civilian.health; var old_severity: float=event.severity
	story.tick(3600/life.routine_clock_rate())
	check(civilian.health<health and event.severity>old_severity and story.counts.escalations>0,"unresolved hazard has local consequences and bounded escalation")
	check(story.adjust_severity(id,.2) and event.manually_adjusted and story.history[-1].action=="manual_severity","severity testing is audited")
	var started: int=story.events.size()
	story.pause_generation(true); story.tick(7200/life.routine_clock_rate())
	check(story.events.size()==started and event.severity>.2,"pause stops new generation while existing hazards continue")
	fresh()
	id=story.trigger("family_disagreement","S1",.3); event=story.find(id)
	check(not id.is_empty() and not str(event.linked_conflict).is_empty(),"social events use actual family interactions and disputes")
	working(commander,event)
	check(story.respond(id,commander,4) and event.status=="RESOLVED","cooperative commander can mediate a family disagreement")
	fresh()
	civilian.cooperation=10.0; civilian.hunger=95.0; child.hunger=90.0; life.shelters.S1.person_days=1.0
	id=story.trigger("food_theft","S1",.3)
	check(not id.is_empty() and life.shelters.S1.person_days<1.0,"food-theft story requires an actual scarce ration removal")
	fresh()
	id=story.trigger("refusal_to_work","S1",.4); event=story.find(id)
	var refuser: Dictionary=manager.social.by_id[event.members[0]]
	check(not life._activity_allowed(refuser,"CLEAN",life.shelters.S1),"work refusal changes routine eligibility")
	fresh()
	# Compare intrinsic shelter behavior at equal occupancy and supply pressure.
	place(people[0],"S2:DINING")
	manager.shelter_by_id.S1.capacity=6; manager.shelter_by_id.S2.capacity=1
	check(story.risk("S2","flooding")>story.risk("S1","flooding"),"damp metro shelter has greater flooding risk than residential shelter")
	story.conditions.S1.power=20
	var worn: float=story.risk("S1","generator_failure")
	story.conditions.S1.power=100; story.pacing.S1.maintenance_hours=10
	check(story.risk("S1","generator_failure")<worn,"infrastructure condition and maintenance change future risk")
	fresh()
	story.generation_paused=false; manager.social.config.event_frequency=80.0
	story.tick(48*3600/life.routine_clock_rate())
	var first: Array=story.events.duplicate(true)
	check(not first.is_empty() and first.size()<=4,"generation works and respects daily and active-event budgets")
	var times: Array=[]
	for entry in first: times.append(float(entry.started_hour))
	for i in range(1,times.size()): check(times[i]-times[i-1]>=float(story.config.minimum_gap_hours)-.00001,"automatic event spacing prevents catastrophe spam")
	check(story.active("S1").size()<=2,"active shelter event cap")
	fresh(); story.generation_paused=false; manager.social.config.event_frequency=80.0
	for i in range(48*12): story.tick(300/life.routine_clock_rate())
	check(story.events==first,"same seed reproduces event sequence across tick partitions")
	var source_state: int=story.rngs.S1.state
	for i in range(50): story.rngs.S2.randf()
	check(story.rngs.S1.state==source_state,"shelter RNG streams are independent")
	var snapshot: Dictionary=story.snapshot()
	check(not story.restore({"schema_version":1,"events":[],"conditions":{}},life) and story.events==snapshot.events,"incomplete replay state is rejected without modifying the current run")
	var encoded: String=JSON.stringify(manager.social.encode(snapshot),"",true,true)
	var decoded: Dictionary=manager.social.decode(JSON.parse_string(encoded))
	health=civilian.health; var audit_count: int=manager.social.history.size()
	check(story.restore(decoded,life),"JSON event replay restores snapshot")
	story.tick(3600); story.trigger("fire","S1",.5)
	var replay_state: Dictionary=manager.social.decode(JSON.parse_string(JSON.stringify(manager.social.encode(story.snapshot()),"",true,true)))
	check(replay_state==decoded and civilian.health==health and manager.social.history.size()==audit_count,"replay is read-only and never re-applies damage or makes RNG draws")
	check(not story.adjust_severity(first[0].event_id,.2),"replay rejects director mutation")
	manager.social.replay_frames=[manager.social.capture_frame().duplicate(true)]
	manager.social.replaying=true
	var preserved: Array=story.events.duplicate(true)
	manager.social.apply_replay_frame(0)
	check(story.events==preserved and story.replaying,"existing recorded-run player restores shelter event history and state")
	manager.social.replaying=false
	fresh(); story.generation_paused=false; manager.social.config.event_frequency=100.0
	story.config.max_active_per_shelter=99; story.config.minimum_gap_hours=0.0; story.config.warmup_hours=0.0
	story.tick(48*3600/life.routine_clock_rate())
	var per_day: Dictionary={}
	for incident in story.events:
		var event_day:=int(float(incident.started_hour)/24); per_day[event_day]=int(per_day.get(event_day,0))+1
	check(story.events.size()>=3 and per_day.values().all(func(amount):return int(amount)<=2),"daily cap holds independently of active-event and spacing limits")
	fresh()
	id=story.trigger("fire","S1",.7); event=story.find(id); place(commander,event.room_id); story.observe()
	for a in people:
		for b in a.beliefs.values(): b.existence_probability=0.0; b.unavailable=true
	var position: Vector2=civilian.position
	check(not story.order_transfer(id,commander) and civilian.position==position and not civilian.has("planned_transfer_shelter"),"commander cannot invent an accessible alternative or teleport residents")
	place(civilian,event.room_id)
	for a in [commander,civilian]:
		a.movement_speed=10.0
		for shelter_id in a.beliefs:
			if shelter_id=="S1": continue
			a.beliefs[shelter_id].existence_probability=1.0; a.beliefs[shelter_id].confidence=1.0; a.beliefs[shelter_id].unavailable=false; a.beliefs[shelter_id].accessible=true; a.beliefs[shelter_id].safety_status="SAFE"; a.beliefs[shelter_id].estimated_occupancy=0
	position=civilian.position
	check(story.order_transfer(id,commander) and civilian.position==position and civilian.get("evacuating_shelter","")=="S1","informed commander can order a verified reachable transfer without moving residents instantly")
	# Instantiate real controls to catch UI script errors and exercise history inspection.
	var controls:=Controls.new(); root.add_child(controls); controls.configure(manager); controls.refresh()
	check(controls.kind.item_count==29 and controls.selected_event.item_count==1 and "MANUAL TEST" in controls.audit.text,"testing controls expose catalog, event history and manual label")
	controls.queue_free()
	fresh(); story.generation_paused=false
	for refuge in life.shelters.values(): refuge.person_days=300.0
	for i in range(int(life.day_duration_seconds()*10/15)):
		life.tick(15.0); manager.elapsed_seconds+=15.0
	check(life.completed and is_equal_approx(story.elapsed_hours,240.0),"event storyteller integrates through all ten shelter days")
	check(story.counts.automatic>0 and story.active("S1").size()<=2,"live routine simulation generates paced shelter events")
	var file:=FileAccess.open("res://outputs/shelter-storyteller-test-metrics.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(manager.social.encode({"checks":checks,"failures":failures,"seeded_events":first,"metrics":story.metrics()}),"  ",true,true)); file.close()
	print("Shelter storyteller: %d checks / %d failures"%[checks,failures])
	manager.queue_free(); await process_frame; await process_frame
	quit(1 if failures else 0)
