extends SceneTree
const Manager=preload("res://scripts/simulation_manager.gd")
var manager: Node
var checks:=0
var failures:=0
var delivered: Array=[]
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; printerr("FAIL: "+label)
func fresh() -> void:
	manager.social.replaying=false
	manager.phase="IMPACT"; manager.elapsed_seconds=0; manager.accumulator=0; manager.running=true; manager.post_impact_complete=false
	for s in manager.shelters:
		s.exists=true; s.structural_state="INTACT"; s.base_operational=true; s.operational=true; s.manual_door_state="CLOSED"; s.door_status="CLOSED"; s.water_liters=10000.0; s.supply_level=10000.0; s.manual_accessible=true; s.manual_safety_status="SAFE"
	for i in range(manager.agents.size()):
		var a: Dictionary=manager.agents[i]
		a.state="SHELTERED"; a.shelter_id="S%d"%(i%5+1); a.health=100.0; a.age=30; a.family_id="F%d"%(i%5); a.guardians=[]; a.relationships={}; a.emergency_exit_active=false; a.erase("evacuating_shelter")
	manager.social.shelter_life.initialize(manager.social)
	manager.social.shelter_life.storyteller.generation_paused=true
	manager.survival.begin(manager)
	manager.post_impact_end_seconds=manager.survival.day_seconds()*10
func run() -> void:
	manager=Manager.new(); root.add_child(manager); manager.set_process(false)
	check(manager.load_settings(),"settings")
	manager.social_config.llm_agents=0; manager.social_config.spontaneous_actions=false
	manager.initialize_run(); manager.ai_bridge.set_process(false); manager.social.close(); manager.social.next_send=INF
	manager.agents.assign(manager.agents.slice(0,10))
	fresh()
	var run=manager.survival
	check(run.elapsed_days()==0 and run.reports.is_empty(),"Day 1 starts at impact")
	check(run.initial.size()==10 and run.arrivals.size()==10,"initial and arrival populations")
	check(not run.configure("",{"outside_hazard":-1}),"invalid conditions rejected")
	check(not run.configure("S99",{"route_clear":true}),"unknown shelter rejected")
	manager.pause(); manager.advance_clock(100); check(manager.elapsed_seconds==0,"pause freezes simulated time")
	for speed in [1,5,20,50]:
		manager.start(); manager.set_speed(speed)
		var before: float=manager.elapsed_seconds
		manager.advance_clock(1)
		while manager.accumulator>=1: manager.advance_clock(.00000001)
		check(is_equal_approx(manager.elapsed_seconds-before,speed),"speed %dx"%speed)
	var received:=func(value):delivered.append(value)
	manager.pause()
	manager.ai_bridge.shelter_results.append({"run_id":manager.ai_bridge.run_id,"sent_time":manager.elapsed_seconds,"callback":received,"decision":{"action":"READ"}})
	manager.ai_bridge.drain_shelter_results()
	check(delivered.is_empty() and manager.ai_bridge.shelter_results.size()==1,"async response retained while paused")
	manager.start(); manager.ai_bridge.drain_shelter_results()
	check(delivered.size()==1 and delivered[0].action=="READ","async response delivered on resume")
	manager.ai_bridge.shelter_results.append({"run_id":"old-run","sent_time":manager.elapsed_seconds,"callback":received,"decision":{"action":"READ"}})
	manager.ai_bridge.drain_shelter_results(); check(delivered.size()==1,"old run response discarded")
	manager.ai_bridge.shelter_results.append({"run_id":manager.ai_bridge.run_id,"sent_time":manager.elapsed_seconds-1000,"callback":received,"decision":{"action":"READ"}})
	manager.ai_bridge.drain_shelter_results(); check(delivered.size()==2 and delivered.back().is_empty(),"stale response becomes rule fallback")
	manager.ai_bridge.shelter_results.append({"run_id":manager.ai_bridge.run_id,"sent_time":manager.elapsed_seconds,"callback":received,"decision":{"action":"READ"}})
	manager.ai_bridge.reset_run(); manager.ai_bridge.drain_shelter_results()
	check(delivered.size()==2 and manager.ai_bridge.shelter_results.is_empty(),"reset cancels queued callbacks")
	run.forward(); var before: float=manager.elapsed_seconds; manager.advance_clock(.016)
	check(manager.elapsed_seconds-before<=128,"fast-forward stays bounded")
	manager.social.shelter_life.storyteller.trigger("generator_failure","S1",.3)
	manager.advance_clock(.016)
	check(not run.fast_forward and not manager.running,"fast-forward stops on important event")
	fresh(); run=manager.survival
	var a: Dictionary=manager.agents[0]; var refuge: Dictionary=manager.social.shelter_life.shelters.S1
	a.current_activity_code="DRINK"; a.thirst=80
	var water: float=refuge.water_liters
	manager.social.shelter_life._complete_activity(a)
	check(refuge.water_liters<water and a.thirst<80,"drinking consumes finite water")
	refuge.water_liters=0; refuge.water=true; a.thirst=80; a.current_activity_code="DRINK"
	manager.social.shelter_life._complete_activity(a)
	check(a.thirst==80 and refuge.water_liters==0,"empty pool never creates water")
	refuge.water_liters=10000; refuge.water=true
	run.configure("S1",{"outside_verified":true,"outside_hazard":.1,"route_clear":true})
	run.configure("S2",{"outside_verified":true,"outside_hazard":.9,"route_clear":true})
	run.configure("S3",{"outside_verified":true,"outside_hazard":.1,"route_clear":false})
	run.configure("S4",{"outside_verified":true,"outside_hazard":.1,"route_clear":true})
	manager.shelter_by_id.S4.manual_door_state="JAMMED"; manager.shelter_by_id.S4.door_status="JAMMED"
	check(not run.opening_result("S1").can_open,"Day 1 cannot open despite safe outside")
	# Exercise the real manager, routines and storyteller through ten days.
	while manager.elapsed_seconds<manager.post_impact_end_seconds and not manager.post_impact_complete:
		manager._step(minf(1,manager.post_impact_end_seconds-manager.elapsed_seconds))
	check(manager.post_impact_complete and not manager.running,"ten days finish and stop")
	check(is_equal_approx(manager.elapsed_seconds,14400),"exact accelerated ten-day clock")
	check(run.reports.size()==10,"exactly ten daily reports")
	for i in range(10):
		check(run.reports[i].day==i+1,"report day %d"%(i+1))
		check(run.reports[i].simulation_seconds==(i+1)*86400,"separate simulation timestamp %d"%(i+1))
		check(run.reports[i].has("wall_clock_utc"),"wall clock timestamp %d"%(i+1))
		check(run.reports[i].shelters.size()==5,"S1–S5 daily metrics %d"%(i+1))
	var population: Dictionary=run.result.population
	check(population.survivors+population.deaths+population.missing==10,"population conserved")
	check(run.result.survivor_outcomes.size()==10,"every survivor evaluated")
	check(run.result.shelters.S1.opening.can_open,"verified safe S1 cleared")
	check(not run.result.shelters.S2.opening.can_open,"hazardous S2 stays closed")
	check(not run.result.shelters.S3.opening.can_open,"blocked route S3 stays closed")
	check(not run.result.shelters.S4.opening.can_open,"jammed S4 stays closed")
	check(not run.result.shelters.S5.opening.can_open,"unverified S5 stays closed")
	check(manager.summary.dead==run.result.population.deaths,"main summary uses final deaths")
	check(manager.shelter_by_id.S1.door_status=="OPEN","cleared door actually opens")
	check(run.result.shelters.S1.water_consumption_liters>0,"water consumption reported")
	check(run.result.ai.rule_based_decisions>0,"rule decisions measured")
	check(run.samples.size()>=240,"hourly comparison samples")
	manager.advance_clock(100); check(run.reports.size()==10,"no Day 11")
	check(not run.configure("",{"outside_verified":true}),"final evaluation immutable")
	var fixture:=FileAccess.open("res://outputs/survival-test-results.json",FileAccess.WRITE); fixture.store_string(JSON.stringify(run.result)); fixture.close()
	var frame: Dictionary=manager.social.capture_frame()
	var expected: Dictionary=JSON.parse_string(JSON.stringify(run.result))
	manager.social.replay_frames=[manager.social.decode(JSON.parse_string(JSON.stringify(manager.social.encode(frame))))]
	manager.social.replaying=true
	manager.social.apply_replay_frame(0)
	check(manager.survival.replaying,"actual replay restores lifecycle read-only")
	check(JSON.parse_string(JSON.stringify(manager.survival.result))==expected,"replay preserves final result after JSON numeric normalization")
	var count: int=manager.ai_bridge.metrics.get("calls",0)
	manager.survival.tick(999); manager.survival.forward()
	check(manager.ai_bridge.metrics.get("calls",0)==count and not manager.survival.fast_forward,"replay never requests decisions")
	fresh(); run=manager.survival
	check(run.result.is_empty() and run.reports.is_empty(),"reset clears results and reports")
	manager.agents[0].health=0; manager.agents[1].state="MISSING"
	var missing_id: String=manager.agents[2].id; manager.agents.remove_at(2)
	var measure: Dictionary=run.measure(0)
	check(measure.population.deaths==1 and measure.population.missing==2,"dead, explicitly missing, absent tracked separately")
	check(run.initial.has(missing_id),"missing identity retained")
	manager.elapsed_seconds=manager.post_impact_end_seconds
	var child: Dictionary=manager.agents[3]; child.age=9; child.state="SHELTERED"; child.shelter_id="S1"; child.shelter_caregiver=""
	check(run.configure("S1",{"outside_verified":true,"outside_hazard":.1,"route_clear":true}),"opening conditions configurable before final evaluation")
	run.finish()
	check(run.result.survivor_outcomes[child.id].outcome=="AWAITING_GUARDIAN","child cannot leave without supervision")
	fresh(); run=manager.survival
	manager.elapsed_seconds=manager.post_impact_end_seconds
	run.configure("S1",{"outside_verified":true,"outside_hazard":.1,"route_clear":true})
	manager.social.shelter_life.storyteller.trigger("fire","S1",.7)
	check(not run.opening_result("S1").can_open,"active fire prevents an otherwise cleared opening")
	fresh(); run=manager.survival
	for person in manager.agents: person.health=0
	manager.social.shelter_life.active=false
	manager.elapsed_seconds=manager.post_impact_end_seconds-1; run.reports.clear()
	manager._step(1)
	check(manager.post_impact_complete and run.result.population.survivors==0,"empty shelter cohort still completes lifecycle")
	var controls=preload("res://scripts/survival_controls.gd").new(); root.add_child(controls); controls.setup(manager); controls._process(1)
	check(controls.details.text.contains("10"),"results controls display final reports")
	controls.queue_free(); manager.finish_archives(); manager.queue_free()
	print("Survival lifecycle: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)
