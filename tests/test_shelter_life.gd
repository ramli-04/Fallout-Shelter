extends SceneTree

const Manager=preload("res://scripts/simulation_manager.gd")
const ShelterLife=preload("res://scripts/shelter_life.gd")

var checks:=0
var failures:=0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks+=1
	if not value:
		failures+=1
		printerr("FAIL: "+label)

func run() -> void:
	var manager:=Manager.new()
	root.add_child(manager)
	manager.set_process(false)
	check(manager.load_settings(),"settings load")
	manager.social_config.llm_agents=0
	manager.social_config.spontaneous_actions=false
	manager.initialize_run()
	manager.ai_bridge.set_process(false)
	manager.social.close()
	manager.social.next_send=INF
	manager.phase="IMPACT"
	manager.running=true
	var social: RefCounted=manager.social
	var family_a: Dictionary=manager.agents[0]
	var family_b: Dictionary=manager.agents[1]
	family_a.family_id="SHELTER-TEST-FAMILY"
	family_b.family_id="SHELTER-TEST-FAMILY"
	family_a.relationships[family_b.id]="spouse"
	family_b.relationships[family_a.id]="spouse"
	social.families.append({"id":"SHELTER-TEST-FAMILY","members":[family_a.id,family_b.id],"active_conflict":false})
	for agent in [family_a,family_b]:
		agent.state="SHELTERED"
		agent.shelter_id="S1"
		agent.position=manager.shelter_by_id.S1.position
		agent.health=100.0
	var life: RefCounted=ShelterLife.new()
	life.initialize(social)
	check(life.active,"post-impact routine activates for sheltered survivors")
	check(life.day_duration_seconds()==1440.0,"ten simulated days follow the configured accelerated daily clock")
	var actor: Dictionary=family_a
	actor.hunger=100.0; actor.thirst=0.0; actor.fatigue=0.0
	check(life.choose_activity(actor)=="EAT","high hunger selects eating")
	actor.hunger=0.0; actor.thirst=100.0
	check(life.choose_activity(actor)=="DRINK","high thirst selects drinking")
	actor.thirst=0.0; actor.fatigue=100.0
	check(life.choose_activity(actor)=="SLEEP","high fatigue selects sleep")
	var resident: Dictionary={"occupation":"Resident","skills":{}}
	check(not life._has_skill(resident,"technical"),"residents do not gain technical skills automatically")
	check(not life._activity_allowed(resident,"MAINTAIN_GENERATOR",life.shelters["S1"]),"unskilled resident cannot maintain a generator")
	actor.occupation="Technician"
	actor.hunger=0.0; actor.thirst=0.0; actor.fatigue=0.0; actor.stress=0.0; actor.health=100.0
	life.shelters["S1"].power=false
	check(life.choose_activity(actor)=="MAINTAIN_GENERATOR","technician prioritizes a broken generator")
	actor.occupation="Medical"; family_b.health=75.0
	check(life.choose_activity(actor)=="ASSIST_MEDICAL","medical worker prioritizes an injured survivor")
	actor.occupation="Technician"
	var outsider: Dictionary=family_b.duplicate(true)
	outsider.id="OUTSIDER"; outsider.family_id=""
	var family_room: String=life._room_of_type("S1",["Family bedroom"])
	check(life._select_room(outsider,"SLEEP",life._room_of_type("S1",["Entrance"]))!=family_room,"family bedroom access stays with assigned family members")
	var room_start: Vector2=actor.position
	var movement_speed:=maxf(.1,float(actor.get("walk_speed",1.2)))
	var moved:=false
	for _step in range(2500):
		var before: Vector2=actor.position
		life._advance_room_route(actor,.1)
		check(actor.position.distance_to(before)<=movement_speed*.1+.002,"shelter room navigation respects walking speed")
		if actor.position.distance_to(room_start)>.01: moved=true
		if actor.shelter_activity_state!="MOVING": break
	check(moved and actor.shelter_activity_state=="ACTIVE","survivor walks from the entrance to an assigned room")
	life._start_activity(actor,"EAT",10.0)
	check(actor.current_activity_code=="EAT" and actor.activity_animation=="eating","activity state selects its matching eating animation")
	actor.current_activity_code="READ"; actor.current_activity="Reading"; actor.activity_animation="reading"
	actor.activity_remaining_seconds=30.0; actor.shelter_activity_state="ACTIVE"
	actor.thirst=100.0; actor.hunger=0.0; actor.fatigue=0.0
	life._decide(actor,true)
	check(actor.current_activity_code=="DRINK" and actor.activity_interruptions>0,"critical thirst interrupts a lower-priority activity")
	var family_record: Dictionary=social.families.filter(func(f):return f.id=="SHELTER-TEST-FAMILY")[0]
	actor.shelter_activity_partner=family_b.id
	life._argue(actor)
	check(family_record.active_conflict,"family argument creates an active conflict")
	life._reconcile(family_b)
	check(not family_record.active_conflict,"family member can reconcile after an argument")
	for agent in manager.agents: agent.shelter_life_active=false
	life.active=true; life.completed=false; manager.elapsed_seconds=life.started_at
	life.tick(life.day_duration_seconds()*float(life.config.duration_days))
	check(life.completed and life.day==10,"shelter simulation advances through ten daily cycles")
	print("Shelter life: %d checks / %d failures"%[checks,failures])
	manager.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures else 0)
