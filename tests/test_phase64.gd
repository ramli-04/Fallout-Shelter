extends SceneTree
const Manager = preload("res://scripts/simulation_manager.gd")
const Map = preload("res://scripts/city_map.gd")
const SocialWorld = preload("res://scripts/three_d/social_world.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: "+label)

func run() -> void:
	var manager := Manager.new()
	root.add_child(manager)
	manager.set_process(false)
	check(manager.load_settings(),"project settings load")
	manager.social_config.llm_agents = 0
	manager.initialize_run()
	manager.ai_bridge.set_process(false)
	var social: RefCounted=manager.social
	var expected := {"Police":12,"Fire":8,"Medical":7,"Civil protection":5,"Crisis commander":3}
	for role in expected:
		check(manager.agents.filter(func(a):return a.role=="Authority" and a.occupation==role).size()==expected[role],"default authority quota: "+role)
	check(social.authorities.assignments.size()==35,"every authority receives an explicit duty assignment")
	check(manager.agents.filter(func(a):return a.role=="Authority" and not a.relationships.is_empty()).size()>0,"authorities retain personal relationships")

	var police: Dictionary=manager.agents.filter(func(a):return a.role=="Authority" and a.occupation=="Police")[0]
	var commander: Dictionary=manager.agents.filter(func(a):return a.role=="Authority" and a.occupation=="Crisis commander")[0]
	var civilian: Dictionary=manager.agents.filter(func(a):return a.role=="Civilian")[0]
	var no_hazard: Dictionary=social.authorities.evaluate_roadblock({"vehicle_count":8,"traffic_flow":1.0,"congestion":1.0,"evacuation_demand":1.0,"available_personnel":4,"shelter_access_preserved":true})
	check(no_hazard.action=="hold","no hazard means no roadblock regardless of traffic or configured frequency")
	check(not social.perform_action(police,{"action":"CREATE_ROADBLOCK","target":"police"}),"LLM roadblock request still requires policy evidence")
	var stopped_accident: Dictionary=social.authorities.evaluate_roadblock({"hazard_kind":"accident","hazard_confidence":1.0,"vehicle_count":0,"traffic_flow":0.0,"congestion":0.0,"evacuation_demand":0.0,"available_personnel":4,"shelter_access_preserved":true})
	check(stopped_accident.action=="hold","accident diversion requires approaching traffic")
	var unsafe: Dictionary=social.authorities.evaluate_roadblock({"hazard_kind":"accident","hazard_confidence":1.0,"vehicle_count":5,"traffic_flow":1.0,"congestion":0.8,"evacuation_demand":0.8,"available_personnel":4,"shelter_access_preserved":false})
	check(unsafe.action=="hold" and str(unsafe.reason).contains("isolate"),"shelter access vetoes a road closure")
	var unsafe_emergency: Dictionary=social.authorities.evaluate_roadblock({"hazard_kind":"accident","hazard_confidence":1.0,"vehicle_count":5,"traffic_flow":1.0,"congestion":0.8,"evacuation_demand":0.8,"available_personnel":4,"shelter_access_preserved":true,"emergency_vehicle_access_preserved":false})
	check(unsafe_emergency.action=="hold" and str(unsafe_emergency.reason).contains("emergency vehicle"),"emergency access vetoes a road closure")
	var evidence := {"hazard_kind":"accident","hazard_confidence":0.95,"vehicle_count":4,"traffic_flow":0.8,"congestion":0.7,"evacuation_demand":0.6,"available_personnel":3,"shelter_access_preserved":true}
	var decision: Dictionary=social.authorities.evaluate_roadblock(evidence)
	var repeated: Dictionary=social.authorities.evaluate_roadblock(evidence)
	check(decision.action=="redirect_traffic" and decision==repeated,"same traffic and safety observations yield the same roadblock decision")
	var nuclear_decision: Dictionary=social.authorities.evaluate_roadblock({"hazard_kind":"nuclear","hazard_confidence":0.8,"vehicle_count":0,"available_personnel":2,"shelter_access_preserved":true})
	check(nuclear_decision.action=="close_unsafe_road","confirmed danger can be closed even before traffic builds")
	var center: Vector2=Map.MAP_SIZE*.5
	var boundary_edge := -1
	var danger_radius := 0.0
	for index in range(Map.roads.size()):
		var points: PackedVector2Array=Map.roads[index].points
		var first_distance: float=points[0].distance_to(center); var last_distance: float=points[-1].distance_to(center)
		if absf(first_distance-last_distance)>500:
			boundary_edge=index; danger_radius=(first_distance+last_distance)*.5; break
	if boundary_edge>=0:
		var police_position: Vector2=police.position
		police.position=social.authorities._edge_center(Map.roads[boundary_edge])
		var nuclear_entries: Array=social.authorities._nuclear_entry_edges({"position":center,"location":{"danger_radius":danger_radius,"uncertainty_radius":0.0}},police)
		check(boundary_edge in nuclear_entries,"nuclear road controls target danger-zone entry edges, not random road positions")
		police.position=police_position
	var lane_decision: Dictionary=social.authorities.evaluate_roadblock({"hazard_kind":"accident","hazard_confidence":0.95,"vehicle_count":5,"traffic_flow":1.0,"congestion":0.8,"evacuation_demand":0.8,"lane_count":4,"capacity_utilization":0.9,"available_personnel":3,"shelter_access_preserved":true,"emergency_vehicle_access_preserved":true})
	check(lane_decision.action=="reserve_emergency_lane","high-capacity roads reserve a lane when traffic pressure is high")

	var report: Dictionary=social.authorities.report(commander,"test_authority_report",{"status":"test"},police.position,0.2,"direct observation",[police.id])
	check(not report.is_empty() and report.timestamp==manager.elapsed_seconds and report.source==commander.id and is_equal_approx(report.uncertainty,0.2),"radio report records timestamp, source, and uncertainty")
	check(police.authority_reports.any(func(item):return item.id==report.id) and civilian.authority_reports.is_empty(),"radio report reaches only the addressed authority")
	check(report.channel=="command-radio","reports use role-specific channels")

	# roadblock placement is exercised on a real road edge with a visible incident and local flow.
	var selected_incident := -1
	var selected_approach := -1
	var approach_position := Vector2.ZERO
	for incident_index in range(Map.roads.size()):
		for approach_index in social.authorities._adjacent_edges(incident_index):
			if not social.authorities._edge_has_active_block(approach_index) and social.authorities._shelter_access_preserved(approach_index):
				selected_incident=incident_index; selected_approach=approach_index; break
		if selected_incident>=0: break
	check(selected_incident>=0,"find an approach edge that preserves shelter access")
	if selected_incident>=0:
		var lane_edge: Dictionary=Map.roads[selected_approach]
		var lane_marker: Dictionary=social.create_block(police,"emergency_lane",lane_edge,social.authorities._edge_center(lane_edge),0,"test emergency lane",{},true)
		check(lane_marker.is_empty() and Map.graph.are_points_connected(lane_edge.from,lane_edge.to),"emergency lane requires physical deployment and preserves graph while pending")
		if not lane_marker.is_empty(): social.remove_block(lane_marker.id)
		var incident_position: Vector2=social.authorities._edge_center(Map.roads[selected_incident])
		approach_position=social.authorities._edge_center(Map.roads[selected_approach])
		police.position=approach_position
		police.indoor_id=""
		police.social_beliefs["accident:TEST"]={"claimed_value":incident_position,"confidence":1.0,"evidence":"direct observation","status":"KNOWN"}
		social.traffic.scenes.append({"vehicle":"TEST","position":incident_position,"block":"","created":manager.elapsed_seconds,"responders":[police.id],"secured":false,"treated":false,"recovered":false,"evacuated":[]})
		for vehicle in social.vehicles:
			vehicle.status="PARKED"; vehicle.speed=0
		var moving: Dictionary=social.vehicles[0]
		moving.status="MOVING"; moving.position=approach_position; moving.body_position=approach_position; moving.edge=selected_approach; moving.speed=0
		for person in manager.agents:
			if person.role=="Civilian" and person.health>0 and person.state not in ["SHELTERED","SAFE","EXPOSED"]:
				person.indoor_id=""; person.position=approach_position; person.state="MOVING"; break
		social.authorities._consider_roadblocks()
		var queued: Array=social.police.requests.filter(func(r):return r.state!="REMOVED")
		check(not queued.is_empty(),"local accident and traffic evidence request staffed deployment")
		check(social.blocks.filter(func(block):return block.active and block.get("managed_by_policy",false)).is_empty(),"policy cannot bypass officer dispatch and deployment")
		if not queued.is_empty():
			check(queued[0].rationale!="" and queued[0].evidence.vehicle_count>0,"request stores measured rationale and evidence")

	# Family rescue decisions use only the officer's own remembered report and personality traits.
	var relative: Dictionary=civilian
	var room_id: String=social.daily.interiors.rooms.keys()[0]
	var witness_position: Vector2=social.daily.interiors.rooms[room_id].center
	police.indoor_id=room_id; police.position=witness_position
	police.state="MOVING"; police.riding=""
	civilian.indoor_id=room_id; civilian.position=witness_position; civilian.state="MOVING"
	civilian.riding=""
	civilian.trust_relationships[police.id]=0.8
	var trust_before: float=civilian.trust_relationships[police.id]
	police.relationships[relative.id]="spouse"
	police.known_locations[relative.id]={"position":Map.graph.get_point_position(Map.graph.get_closest_point(approach_position)),"source":"family call","timestamp":manager.elapsed_seconds,"confidence":1.0}
	police.known_locations["nuclear_hazard"]={"position":police.known_locations[relative.id].position,"source":"command radio","timestamp":manager.elapsed_seconds,"confidence":0.9,"danger_radius":800.0,"uncertainty_radius":100.0}
	police.social_beliefs["nuclear"]={"confidence":0.95,"claimed_value":"warning","evidence":"alert"}
	police.perceived_danger=0.7; police.panic_level=70; police.stress=100; police.duty_commitment=10; police.authority_trust=10
	police.perceived_warning_seconds=10; police.personal_warning_known_at=manager.elapsed_seconds
	manager.remaining_seconds=10
	social.authorities._refresh_family_emergencies()
	var baseline: Dictionary=social.authorities.desertion_assessment(police)
	var iq_backup: float=police.iq
	police.iq=999
	var altered_iq: Dictionary=social.authorities.desertion_assessment(police)
	police.iq=iq_backup
	check(is_equal_approx(baseline.score,altered_iq.score),"desertion score is independent of IQ")
	var prior_assignment: Dictionary=social.authorities.assignment_for(police.id)
	check(social.daily.interiors.can_see(civilian,police),"test witness shares an observable room")
	manager.phase="EVACUATION"; manager.elapsed_seconds+=1; social.authorities.next_tick=0
	social.authorities.tick(.1)
	check(police.duty_status=="DESERTED" and police.authority_action=="abandon_duty_and_evacuate","high perceived danger, family risk, stress, low duty trust and short time can cause desertion")
	check(prior_assignment.status in ["UNFINISHED","REASSIGNED"],"desertion leaves the original assignment unfinished or reassigns it")
	check(social.authorities.desertion_events.any(func(item):return item.agent==police.id and item.has("family_risk") and item.has("duty_commitment") and item.has("time_pressure")),"desertion record explains the evaluated factors")
	check(social.counters.get("public_trust_changes",0)>0 and civilian.trust_relationships[police.id]<trust_before,"witnessed desertion reduces that civilian's trust in the officer")

	# A high roadblock-frequency preset no longer creates barriers without evidence.
	for block in social.blocks.duplicate(): social.remove_block(block.id)
	social.traffic.scenes.clear(); police.social_beliefs.erase("accident:TEST"); police.social_beliefs.erase("nuclear"); police.known_locations.erase("nuclear_hazard"); police.duty_status="ON_DUTY"
	social.config.roadblock_frequency=1.0; manager.elapsed_seconds+=2; social.authorities.next_tick=0
	social.authorities.tick(.1)
	check(social.blocks.filter(func(block):return block.active and block.get("managed_by_policy",false)).is_empty(),"roadblock frequency setting cannot cause unsupported automatic placement")
	manager.initialize_run()
	check(manager.social.authorities.assignments.size()==35 and manager.social.authorities.reports.is_empty() and manager.social.authorities.desertion_events.is_empty(),"reset recreates assignments and clears reports and desertion")
	manager.queue_free(); await process_frame
	print("Phase 6.4 authorities: %d checks / %d failures"%[checks,failures])
	quit(1 if failures else 0)
