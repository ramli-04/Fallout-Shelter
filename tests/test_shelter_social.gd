extends SceneTree
const Manager=preload("res://scripts/simulation_manager.gd")
const Life=preload("res://scripts/shelter_life.gd")
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1; printerr("FAIL: "+label)
func colocate(agents: Array,room: String) -> void:
	for a in agents:
		a.shelter_room_id=room; a.shelter_activity_state="ACTIVE"; a.current_activity_code="READ"
func run() -> void:
	var manager:=Manager.new(); root.add_child(manager); manager.set_process(false)
	check(manager.load_settings(),"settings load")
	manager.social_config.llm_agents=0; manager.social_config.spontaneous_actions=false
	manager.initialize_run(); manager.ai_bridge.set_process(false); manager.social.close(); manager.social.next_send=INF
	manager.phase="IMPACT"; manager.running=true
	var people: Array=manager.agents.slice(0,5)
	for a in manager.agents: a.shelter_life_active=false; a.state="IDLE"
	for a in people:
		a.state="SHELTERED"; a.shelter_id="S1"; a.health=100.0; a.age=35; a.family_id=""; a.relationships={}; a.guardians=[]
		a.cooperation=80.0; a.empathy=80.0; a.sociability=50.0; a.skepticism=50.0; a.occupation="Resident"
	var parent: Dictionary=people[0]; var child: Dictionary=people[1]; var friend: Dictionary=people[2]; var rival: Dictionary=people[3]; var medic: Dictionary=people[4]
	child.age=10; child.family_id="SOCIAL-FAMILY"; parent.family_id="SOCIAL-FAMILY"; child.guardians=[parent.id]
	child.relationships[parent.id]="parent"; parent.relationships[child.id]="child"; medic.occupation="Medical"
	var life:=Life.new(); life.initialize(manager.social)
	life.storyteller.generation_paused=true # Isolate social/routine regression from the event suite.
	var dynamics: RefCounted=life.dynamics
	colocate(people,"S1:DINING")
	var relation: Dictionary=dynamics.relationship(parent,friend)
	var trust: float=relation.trust
	check(dynamics.interact(parent,friend,"help") and relation.trust>trust,"help increases directed trust")
	check(dynamics.relationship(friend,parent).respect>40,"recipient respects helper")
	dynamics.change(parent,friend,{"trust":500,"conflict":-100})
	check(relation.trust==100 and relation.conflict==0,"relationship bounds")
	check(dynamics.relationship(child,parent).family_attachment==90,"family attachment seeded from real family links")
	friend.shelter_room_id="S1:ENTRY"
	check(not dynamics.interact(parent,friend,"help"),"no remote interaction across shelter rooms")
	friend.shelter_room_id="S1:DINING"
	var probability: float=dynamics.cooperation_probability(parent,friend)
	dynamics.change(parent,friend,{"trust":-90,"conflict":90,"cooperation":-50})
	check(dynamics.cooperation_probability(parent,friend)<probability,"cooperation responds to relationships")
	for a in people:
		a.shelter_social_profile={"communication":25,"experience":25,"confidence":25,"crisis_management":25}
	parent.shelter_social_profile={"communication":95,"experience":95,"confidence":95,"crisis_management":95}
	parent.iq=75.0; rival.iq=160.0
	var potential: float=dynamics.leadership_potential(parent)
	parent.iq=170.0
	check(dynamics.leadership_potential(parent)==potential,"IQ does not confer leadership")
	parent.iq=75.0
	dynamics.elect("S1")
	check(dynamics.councils.S1.leader==parent.id,"residents elect a trusted capable representative")
	check(not dynamics.councils.S1.votes.has(child.id),"children have care and no adult leadership duties")
	dynamics.organize("S1")
	check(not dynamics.councils.S1.groups.is_empty() and dynamics.councils.S1.tasks.get(medic.id)=="ASSIST_MEDICAL","accepted leader organizes skilled mutual aid")
	parent.shelter_social_profile={"communication":5,"experience":5,"confidence":5,"crisis_management":5}
	rival.shelter_social_profile={"communication":100,"experience":100,"confidence":100,"crisis_management":100}
	for a in people:
		if a.id!=parent.id: dynamics.change(a,parent,{"trust":-100,"respect":-100,"conflict":100})
		if a.id!=rival.id: dynamics.change(a,rival,{"trust":100,"respect":100,"cooperation":100,"conflict":-100})
	dynamics.step(.25)
	check(dynamics.counts.challenges>0 and dynamics.councils.S1.leader==rival.id,"lost trust triggers challenge and leadership replacement")
	for a in people:
		a.shelter_social_profile={"communication":0,"experience":0,"confidence":0,"crisis_management":0}; a.cooperation=0.0
		for b in people:
			if a.id!=b.id: dynamics.change(a,b,{"trust":-100,"respect":-100,"cooperation":-100,"conflict":100})
	dynamics.elect("S1")
	check(dynamics.councils.S1.leader.is_empty() and dynamics.counts.rejections>0,"residents can reject all candidates")
	dynamics.organize("S1")
	check(str(medic.shelter_social_task).is_empty(),"rejected authority leaves no stale work orders")
	for a in people: a.cooperation=80.0; a.stress=10.0; a.frustration=10.0
	parent.stress=100.0; parent.frustration=100.0; parent.hunger=95.0; friend.hunger=10.0
	life.shelters.S1.person_days=0.0
	check(dynamics.dispute_cause(parent,friend)=="food_allocation","food disputes derive from stress and unequal deprivation")
	var dispute: Dictionary=dynamics.open_conflict(parent,friend,"food_allocation")
	var initial_count: int=dynamics.counts.conflicts_started
	dynamics.open_conflict(parent,friend,"food_allocation")
	check(dynamics.counts.conflicts_started==initial_count,"same open dispute is not duplicated")
	check(not dynamics.resolve(dispute.id,medic),"mediation cannot erase starvation")
	life.shelters.S1.person_days=10.0; parent.hunger=20.0
	dynamics.change(parent,medic,{"trust":100})
	check(dynamics.resolve(dispute.id,medic) and dispute.status=="RESOLVED","improved conditions and mediation resolve resource dispute")
	check(not dynamics.report_incident(parent,friend,"resource_theft",""),"theft requires evidence from an interaction")
	parent.cooperation=0.0; parent.hunger=95.0; friend.hunger=90.0; parent.current_activity_code="EAT"; life.shelters.S1.person_days=1.0
	check(dynamics.take_extra_ration(parent,friend) and life.shelters.S1.person_days<1.0 and parent.hunger<95.0,"scarcity theft consumes actual supplies and creates a witnessed dispute")
	parent.cooperation=80.0; parent.current_activity_code="READ"
	check(dynamics.report_incident(parent,friend,"resource_theft","Observed removal from a reserved ration"),"witnessed resource theft generates an evidence-linked dispute")
	check(dynamics.report_incident(parent,friend,"rule_violation","Observed taking an occupied bed"),"witnessed rule violations are recorded")
	parent.stress=0.0; parent.frustration=0.0; parent.hunger=0.0; parent.thirst=95.0; life.shelters.S1.water=false
	parent.stress=100.0; parent.frustration=100.0
	check(dynamics.dispute_cause(parent,friend)=="water_distribution","broken water and thirst produce a water dispute")
	life.shelters.S1.water=true; parent.thirst=0.0
	dynamics.supervise(dynamics.residents("S1"))
	check(child.shelter_caregiver==parent.id,"present parent supervises child")
	parent.shelter_id="S2"
	dynamics.change(child,friend,{"trust":100,"conflict":-100})
	dynamics.supervise(dynamics.residents("S1"))
	check(child.shelter_caregiver==friend.id,"trusted adult can supervise separated child")
	var fear: float=child.fear; var anxiety: float=child.anxiety
	dynamics.update_emotions(child,1.0)
	check(child.separated_family_count>0 and child.anxiety>anxiety and child.fear>fear,"family separation has distinct emotional consequences")
	friend.shelter_id="S2"; medic.shelter_id="S2"; rival.shelter_id="S2"
	dynamics.supervise(dynamics.residents("S1"))
	check(child.shelter_caregiver.is_empty(),"absent adults never count as supervision")
	check(not life._activity_allowed(child,"CHILDCARE",life.shelters.S1),"children cannot supervise children")
	for a in people: a.shelter_id="S1"
	colocate(people,"S1:DINING")
	parent.current_activity_code="SLEEP"
	for a in [friend,medic,rival]: dynamics.change(child,a,{"trust":-100})
	dynamics.supervise(dynamics.residents("S1"))
	check(child.shelter_caregiver.is_empty(),"sleeping adult cannot supervise an awake child")
	parent.current_activity_code="READ"
	child.hunger=80.0; life.shelters.S1.person_days=1.0
	var stores: float=life.shelters.S1.person_days
	life._distribute(parent,life.shelters.S1)
	check(child.hunger<80 and life.shelters.S1.person_days<stores and dynamics.counts.food_shared>0,"parent feeds child using conserved shelter stores")
	child.shelter_caregiver=parent.id; var care_count: int=dynamics.counts.care_acts
	life._care_for_child(parent)
	check(dynamics.counts.care_acts>care_count,"childcare completes a real care interaction")
	friend.health=60.0; life._assist_patient(medic)
	check(friend.health==70.0,"medical cooperation helps injured survivor")
	friend.stress=80.0; friend.morale=20.0; var morale: float=friend.morale
	dynamics.interact(medic,friend,"support")
	check(friend.morale>morale and friend.stress<80,"support changes morale and stress independently")
	medic.occupation="Technician"; life.shelters.S1.power=false
	var cooperation_before: int=dynamics.counts.cooperative_acts
	life._repair(medic,"power")
	check(life.shelters.S1.power and dynamics.counts.cooperative_acts>cooperation_before,"skilled repairs restore infrastructure and build cooperative relationships")
	medic.occupation="Medical"
	friend.health=50.0; friend.shelter_room_id="S1:ENTRY"; life._assist_patient(medic)
	check(friend.health==50.0,"treatment cannot occur remotely")
	friend.shelter_room_id="S1:DINING"
	parent.social_beliefs={"outside:road":{"claimed_value":"blocked","source":"WITNESS","confidence":.8,"evidence":"unverified report","acquired_at":123.0}}
	friend.social_beliefs={}; friend.skepticism=10.0
	dynamics.change(friend,parent,{"trust":100,"conflict":-100})
	dynamics.converse(parent,friend)
	check(friend.social_beliefs["outside:road"].origin=="WITNESS" and friend.social_beliefs["outside:road"].source==parent.id,"conversation preserves origin and immediate speaker")
	check(friend.social_beliefs["outside:road"].evidence=="shelter conversation" and friend.social_beliefs["outside:road"].confidence<.8,"hearsay stays uncertain")
	medic.social_beliefs={}; dynamics.converse(friend,medic)
	check(medic.social_beliefs["outside:road"].origin=="WITNESS" and parent.id in medic.social_beliefs["outside:road"].relay_chain,"multi-hop provenance is retained")
	check(medic.social_beliefs["outside:road"].origin_timestamp==123.0,"original information timestamp survives multiple relays")
	friend.social_beliefs={"outside:road":{"claimed_value":"open","source":friend.id,"confidence":1.0,"evidence":"direct observation"}}
	dynamics.converse(parent,friend)
	check(friend.social_beliefs["outside:road"].claimed_value=="open" and dynamics.counts.rumor_challenges>0,"direct observation survives a conflicting rumor")
	var before_hours: float=dynamics.social_hours
	dynamics.tick(900.0/life.routine_clock_rate())
	check(is_equal_approx(dynamics.social_hours,before_hours+.25),"social dynamics use accelerated fixed simulation clock")
	var measured: Dictionary=dynamics.metrics()
	check(measured.emotions.size()==8 and measured.mean_relationships.size()==7,"metrics preserve eight emotions and seven relationship dimensions")
	check(measured.conflicts_by_cause.has("food_allocation") and measured.cooperative_acts>0 and measured.leadership_changes>=2,"measurable social outcomes")
	var saved_people: Array=[]
	for a in people: saved_people.append(a.duplicate(true))
	dynamics.initialize(life); dynamics.tick(3600.0/life.routine_clock_rate())
	var bulk: Dictionary=dynamics.metrics()
	for i in range(people.size()): people[i].clear(); people[i].merge(saved_people[i].duplicate(true))
	dynamics.initialize(life)
	for i in range(4): dynamics.tick(900.0/life.routine_clock_rate())
	check(dynamics.metrics()==bulk,"fixed social steps reproduce outcomes across tick partitions")
	var file:=FileAccess.open("res://outputs/shelter-social-test-metrics.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(measured,"  ",true,true)); file.close()
	# Run the actual room/routine integration for ten days in fixed 15-second steps.
	for a in people:
		a.health=100.0; a.hunger=15.0; a.thirst=15.0; a.fatigue=0.0; a.stress=15.0; a.cooperation=80.0
		a.shelter_relationships={}; a.social_beliefs={}; a.shelter_social_profile={"communication":70,"experience":60,"confidence":65,"crisis_management":70}
	parent.shelter_social_profile.communication=95
	life.initialize(manager.social)
	life.storyteller.generation_paused=true # Isolate social/routine regression from the event suite.
	for refuge in life.shelters.values(): refuge.person_days=250.0; refuge.truth.maintenance_failure_probability=0.0
	var duration: float=life.day_duration_seconds()*10
	for i in range(int(duration/15.0)):
		life.tick(15.0); manager.elapsed_seconds+=15.0
	var long_metrics: Dictionary=life.dynamics.metrics()
	check(life.completed and life.day==10 and is_equal_approx(long_metrics.social_hours,240.0),"social simulation integrates across all ten shelter days")
	check(long_metrics.residents==5 and long_metrics.elections>0 and long_metrics.conversations>0,"ten-day residents survive, communicate and hold elections")
	file=FileAccess.open("res://outputs/shelter-social-ten-day-metrics.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(long_metrics,"  ",true,true)); file.close()
	life.stop()
	check(life.dynamics.metrics().residents==0,"new-run reset clears former council and social metrics")
	print("Shelter social dynamics: %d checks / %d failures"%[checks,failures])
	manager.queue_free(); await process_frame; await process_frame
	quit(1 if failures else 0)
