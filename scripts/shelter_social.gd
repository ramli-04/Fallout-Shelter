extends RefCounted
## Synthetic social dynamics, not a clinical model. Only the fixed simulation clock advances it.
const DIMENSIONS := ["trust","friendship","family_attachment","respect","conflict","dependence","cooperation"]
const EMOTIONS := ["fear","anxiety","stress","morale","loneliness","hope","frustration","sense_of_safety"]
const CAUSES := ["food_allocation","water_distribution","sleeping_arrangements","security","leadership","family_protection","resource_theft","rule_violation","personal_disagreement"]
var life: RefCounted
var config: Dictionary = {}
var councils: Dictionary = {}
var conflicts: Array[Dictionary] = []
var counts: Dictionary = {}
var accumulator := 0.0
var social_hours := 0.0
var rng := RandomNumberGenerator.new()

func reset() -> void:
	councils.clear(); conflicts.clear(); counts.clear(); accumulator=0; social_hours=0

func initialize(owner_life: RefCounted) -> void:
	life=owner_life
	config=JSON.parse_string(FileAccess.get_file_as_string("res://resources/shelter_social.json"))
	councils.clear(); conflicts.clear(); counts.clear(); accumulator=0; social_hours=0
	for key in ["interactions","relationship_updates","elections","leadership_changes","rejections","challenges","conflicts_started","conflicts_resolved","cooperative_acts","food_shared","care_acts","conversations","rumor_challenges","ration_thefts"]: counts[key]=0
	for key in ["resident_hours","child_hours","supervised_child_hours","separated_resident_hours","resolution_hours"]: counts[key]=0.0
	rng.seed=life.manager.seed_for("behavior")+674031
	for id in life.shelters:
		councils[id]={"leader":"","support":0.0,"votes":{},"next_election":1.0,"groups":[],"tasks":{},"term":0}
	for a in life.manager.agents:
		if a.get("shelter_life_active",false): register(a)

func register(a: Dictionary) -> void:
	if not a.has("shelter_relationships"): a.shelter_relationships={}
	for emotion in EMOTIONS:
		if not a.has(emotion): a[emotion]=50.0 if emotion in ["morale","hope","sense_of_safety"] else 15.0
	if not a.has("shelter_social_profile"):
		a.shelter_social_profile={"communication":a.get("sociability",50),"experience":clampf((float(a.get("age",30))-18)*1.8,0,100),"confidence":a.get("courage",50),"crisis_management":a.get("stress_tolerance",50)}
	a["shelter_caregiver"]=""; a["shelter_social_task"]=""
	for id in a.get("relationships",{}):
		var other: Dictionary=life.social.by_id.get(id,{})
		if not other.is_empty(): relationship(a,other)

func residents(id: String) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for a in life.manager.agents:
		if a.get("state","")=="SHELTERED" and a.get("shelter_life_active",false) and a.get("shelter_id","")==id and a.get("health",0)>0 and not a.get("emergency_exit_active",false): result.append(a)
	result.sort_custom(func(a,b):return str(a.id)<str(b.id))
	return result

func together(a: Dictionary,b: Dictionary, room_required: bool = true) -> bool:
	if a.is_empty() or b.is_empty() or a.get("id","")==b.get("id",""): return false
	if str(a.get("shelter_id","")).is_empty() or a.get("shelter_id","")!=b.get("shelter_id",""): return false
	for member in [a,b]:
		if member.get("state","")!="SHELTERED" or not member.get("shelter_life_active",false) or member.get("health",0)<=0 or member.get("emergency_exit_active",false): return false
	return not room_required or (not str(a.get("shelter_room_id","")).is_empty() and a.get("shelter_room_id","")==b.get("shelter_room_id","") and a.get("shelter_activity_state","")!="MOVING" and b.get("shelter_activity_state","")!="MOVING")

func relationship(a: Dictionary,b: Dictionary) -> Dictionary:
	if not a.has("shelter_relationships"): a.shelter_relationships={}
	if not a.shelter_relationships.has(b.id):
		var link: String=str(a.get("relationships",{}).get(b.id,""))
		var family: bool=link in ["parent","child","spouse","sibling","grandparent","grandchild"]
		var known: bool=family or link=="friend"
		a.shelter_relationships[b.id]={"trust":75.0 if known else 40.0,"friendship":65.0 if known else 20.0,"family_attachment":90.0 if family else 0.0,"respect":55.0 if known else 40.0,"conflict":0.0,"dependence":70.0 if link=="parent" else 10.0,"cooperation":60.0 if known else 40.0,"interactions":0}
	return a.shelter_relationships[b.id]

func change(a: Dictionary,b: Dictionary,deltas: Dictionary) -> void:
	var relation:=relationship(a,b)
	for key in deltas:
		if key in DIMENSIONS: relation[key]=clampf(float(relation[key])+float(deltas[key]),0,100)
	relation.interactions+=1; counts.relationship_updates+=1
	# Compatibility with the earlier inspector's scalar friendship field.
	if not a.has("shelter_relationship_scores"): a.shelter_relationship_scores={}
	a.shelter_relationship_scores[b.id]=relation.friendship

func feel(a: Dictionary,deltas: Dictionary) -> void:
	for key in deltas:
		if key in EMOTIONS: a[key]=clampf(float(a.get(key,50))+float(deltas[key]),0,100)

func interact(a: Dictionary,b: Dictionary,kind: String) -> bool:
	if not together(a,b): return false
	var delta: Dictionary={"trust":2.0,"friendship":2.0,"cooperation":1.0}
	if kind in ["help","care","share","repair","protect","organize","support"]:
		delta={"trust":4.0,"friendship":2.0,"respect":3.0,"cooperation":4.0,"conflict":-3.0}
		counts.cooperative_acts+=1
		feel(b,{"stress":-3,"loneliness":-4,"hope":2,"morale":3,"sense_of_safety":2})
		feel(a,{"morale":1,"hope":1})
		if float(relationship(a,b).family_attachment)>0: delta["family_attachment"]=1.0
	elif kind=="argument":
		delta={"trust":-7.0,"friendship":-4.0,"respect":-3.0,"conflict":12.0,"cooperation":-5.0}
		feel(a,{"stress":5,"frustration":5,"morale":-2}); feel(b,{"stress":5,"frustration":5,"morale":-2})
	else:
		feel(a,{"loneliness":-3,"stress":-1,"morale":1}); feel(b,{"loneliness":-3,"stress":-1,"morale":1})
	change(a,b,delta); change(b,a,delta); counts.interactions+=1
	if kind in ["care","help","protect"]: change(b,a,{"dependence":2})
	life.social.emit_event("shelter.relationship_interaction",a.id,{"other":b.id,"kind":kind,"shelter_id":a.shelter_id})
	return true

func cooperation_probability(a: Dictionary,b: Dictionary) -> float:
	var r:=relationship(a,b)
	return clampf((float(a.get("cooperation",50))*.3+float(a.get("empathy",50))*.2+float(r.trust)*.2+float(r.cooperation)*.2+float(r.family_attachment)*.1-float(r.conflict)*.25-float(a.get("fatigue",0))*.1-float(a.get("stress",0))*.08+maxf(0,65-float(b.get("health",100)))*.15)/100,0,1)

func tick(seconds: float) -> void:
	accumulator+=seconds*life.routine_clock_rate()/3600.0
	var interval:=float(config.step_minutes)/60.0
	while accumulator+0.000001>=interval:
		accumulator-=interval; social_hours+=interval
		step(interval)

func step(hours: float) -> void:
	for id in councils:
		var members:=residents(id)
		if members.is_empty(): councils[id].leader=""; councils[id].support=0.0; continue
		supervise(members)
		for a in members:
			update_emotions(a,hours)
			counts.resident_hours+=hours
			if int(a.get("separated_family_count",0))>0: counts.separated_resident_hours+=hours
			if int(a.get("age",30))<18:
				counts.child_hours+=hours
				if together(a,life.social.by_id.get(a.get("shelter_caregiver",""),{})): counts.supervised_child_hours+=hours
			var neighbors: Array[Dictionary]=[]
			for b in members:
				if together(a,b) and b.get("current_activity_code","")!="SLEEP": neighbors.append(b)
			if a.get("current_activity_code","")=="SLEEP" or neighbors.is_empty(): continue
			var other: Dictionary=neighbors[rng.randi_range(0,neighbors.size()-1)]
			if float(a.get("cooperation",50))<30 and float(a.get("hunger",0))>65 and a.get("current_activity_code","")=="EAT" and rng.randf()<(float(a.hunger)-65)/100.0: take_extra_ration(a,other)
			var cause:=dispute_cause(a,other)
			if not cause.is_empty(): open_conflict(a,other,cause)
			elif rng.randf()<float(a.get("sociability",50))/100.0:
				interact(a,other,"conversation"); converse(a,other)
				if float(other.get("stress",0))>55 and rng.randf()<cooperation_probability(a,other): interact(a,other,"support")
			if int(a.get("age",30))>=18 and life.shelters[id].emergency and (int(other.get("age",30))<18 or float(other.health)<50) and rng.randf()<cooperation_probability(a,other):
				interact(a,other,"protect")
		var council: Dictionary=councils[id]
		if not council.leader.is_empty():
			council.support=leader_support(id,council.leader)
			if council.support<float(config.challenge_support):
				counts.challenges+=1; life.social.emit_event("shelter.authority_challenged",id,{"leader":council.leader,"support":council.support})
				council.leader=""; council.next_election=social_hours
		if social_hours>=float(council.next_election): elect(id)
		organize(id)
	for dispute in conflicts:
		if dispute.status!="OPEN": continue
		var members:=residents(dispute.shelter_id)
		var a: Dictionary=life.social.by_id.get(dispute.members[0],{})
		var b: Dictionary=life.social.by_id.get(dispute.members[1],{})
		if not together(a,b,false): dispute.status="CLOSED_DEPARTED"; continue
		for mediator in members:
			if mediator.id not in dispute.members and together(mediator,a) and together(mediator,b) and rng.randf()<cooperation_probability(mediator,a):
				if resolve(dispute.id,mediator): break
	if is_equal_approx(fmod(social_hours,1.0),0.0): life.social.emit_event("shelter.social_metrics","world",metrics())

func update_emotions(a: Dictionary,hours: float) -> void:
	var refuge: Dictionary=life.shelters[a.shelter_id]
	var missing:=0
	for id in a.get("relationships",{}):
		if a.relationships[id] not in ["parent","child","spouse","sibling"]: continue
		var relative: Dictionary=life.social.by_id.get(id,{})
		if relative.is_empty() or relative.get("health",0)<=0 or relative.get("shelter_id","")!=a.shelter_id or relative.get("state","")!="SHELTERED": missing+=1
	a["separated_family_count"]=missing
	var danger:=float(not refuge.power)+float(not refuge.air)+float(not refuge.water)+float(refuge.emergency)
	var deprivation:=maxf(0,float(a.get("hunger",0))-65)/20+maxf(0,float(a.get("thirst",0))-60)/20
	var unattended: bool=int(a.get("age",30))<18 and str(a.get("shelter_caregiver","")).is_empty()
	feel(a,{"fear":hours*(danger*3+missing*.8+(2 if unattended else 0)-.6),"anxiety":hours*(danger+missing*1.3+deprivation-.5),"stress":hours*(missing+deprivation),"morale":hours*(.5-danger-deprivation-missing*.4),"loneliness":hours*(1+missing*.8),"hope":hours*(.3-danger*.5-missing*.3),"frustration":hours*(deprivation+danger*.5-.3),"sense_of_safety":hours*(1-danger*3-(2 if unattended else 0))})

func supervise(members: Array[Dictionary]) -> void:
	var assigned: Dictionary={}
	for adult in members: adult["care_target"]=""
	for child in members:
		if int(child.get("age",30))>=18: continue
		child.shelter_caregiver=""
		var adults: Array[Dictionary]=[]
		for adult in members:
			if int(adult.get("age",0))<18 or float(adult.health)<35 or int(assigned.get(adult.id,0))>=int(config.caregiver_capacity): continue
			var parent: bool=adult.id in child.get("guardians",[]) or child.get("relationships",{}).get(adult.id,"")=="parent"
			if parent or (float(relationship(child,adult).trust)>=float(config.trusted_caregiver) and float(adult.get("empathy",50))>=50): adults.append(adult)
		adults.sort_custom(func(a,b):return float(relationship(child,a).family_attachment)>float(relationship(child,b).family_attachment))
		for adult in adults:
			if not together(child,adult): continue
			if adult.get("current_activity_code","")=="SLEEP" and child.get("current_activity_code","")!="SLEEP": continue
			child.shelter_caregiver=adult.id; assigned[adult.id]=int(assigned.get(adult.id,0))+1; break
		if child.shelter_caregiver.is_empty() and not adults.is_empty():
			var caregiver: Dictionary=adults[0]
			assigned[caregiver.id]=int(assigned.get(caregiver.id,0))+1
			caregiver.shelter_social_task="CHILDCARE"; caregiver["care_target"]=child.id
			# The routine planner routes CHILDCARE to this child's room. Never
			# redirect an in-progress meal, treatment or rest from a social tick.

func dispute_cause(a: Dictionary,b: Dictionary) -> String:
	if not together(a,b): return ""
	var pressure:=float(a.get("stress",0))*.45+float(a.get("frustration",0))*.4+float(relationship(a,b).conflict)*.25-float(a.get("cooperation",50))*.15
	if pressure<float(config.conflict_threshold): return ""
	var refuge: Dictionary=life.shelters[a.shelter_id]
	if float(a.get("hunger",0))>65 and (refuge.person_days<residents(a.shelter_id).size()*.333333 or absf(float(a.hunger)-float(b.get("hunger",0)))>25): return "food_allocation"
	if float(a.get("thirst",0))>65 and not refuge.water: return "water_distribution"
	if int(a.get("age",30))<18 and str(a.get("shelter_caregiver","")).is_empty(): return "family_protection"
	if refuge.emergency and a.get("current_activity_code","")!="SECURITY": return "security"
	var room: Dictionary=life.rooms.get(a.get("shelter_room_id",""),{})
	if float(a.get("fatigue",0))>75 and room.get("room_type","") in ["Dormitory","Family bedroom"] and room.get("occupants",[]).size()>=int(room.get("capacity",1)): return "sleeping_arrangements"
	if b.id==councils[a.shelter_id].leader and float(relationship(a,b).trust)<35: return "leadership"
	if float(relationship(a,b).conflict)>45: return "personal_disagreement"
	return ""

func open_conflict(a: Dictionary,b: Dictionary,cause: String) -> Dictionary:
	if cause not in CAUSES or not together(a,b): return {}
	for existing in conflicts:
		if existing.status=="OPEN" and a.id in existing.members and b.id in existing.members and existing.cause==cause: return existing
	var dispute: Dictionary={"id":"SC%05d"%int(counts.conflicts_started),"shelter_id":a.shelter_id,"members":[a.id,b.id],"cause":cause,"status":"OPEN","opened_hour":social_hours,"resolution":""}
	conflicts.append(dispute); counts.conflicts_started+=1
	interact(a,b,"argument")
	life.social.emit_event("shelter.conflict_started",a.id,dispute.duplicate(true))
	return dispute

func report_incident(a: Dictionary,b: Dictionary,cause: String,evidence: String) -> bool:
	# Called by actual theft/rule events; the periodic model never invents an offence.
	if cause not in ["resource_theft","rule_violation"] or evidence.strip_edges().is_empty(): return false
	var dispute:=open_conflict(a,b,cause)
	if dispute.is_empty(): return false
	dispute["evidence"]=evidence; return true

func take_extra_ration(a: Dictionary,witness: Dictionary) -> bool:
	# An actual unauthorized extra serving during scarcity, not an invented accusation.
	if not together(a,witness) or a.get("current_activity_code","")!="EAT" or int(a.get("age",30))<18: return false
	if float(a.get("hunger",0))<65 or float(witness.get("hunger",0))<65 or float(a.get("cooperation",50))>=30: return false
	var refuge: Dictionary=life.shelters[a.shelter_id]
	var room: Dictionary=life.rooms.get(a.get("shelter_room_id",""),{})
	if room.get("room_type","") not in ["Dining","Kitchen","Food storage","Supply storage"]: return false
	if refuge.person_days<=0 or refuge.person_days>=residents(a.shelter_id).size()*.666667: return false
	var taken:=minf(.166667,float(refuge.person_days)); refuge.person_days-=taken
	a.hunger=maxf(0,float(a.hunger)-16.0*taken/.166667)
	counts.ration_thefts+=1
	life.social.emit_event("shelter.extra_ration_taken",a.id,{"witness":witness.id,"person_days":taken,"shelter_id":a.shelter_id})
	return report_incident(a,witness,"resource_theft","Witnessed an unauthorized extra serving from scarce shared stores")

func resolve(id: String,mediator: Dictionary) -> bool:
	for dispute in conflicts:
		if dispute.id!=id or dispute.status!="OPEN": continue
		var a: Dictionary=life.social.by_id.get(dispute.members[0],{}); var b: Dictionary=life.social.by_id.get(dispute.members[1],{})
		if not together(a,b) or (mediator.id not in dispute.members and (not together(mediator,a) or not together(mediator,b))): return false
		var refuge: Dictionary=life.shelters[dispute.shelter_id]
		# Mediation cannot wish away an empty store or a broken water system.
		if dispute.cause=="food_allocation" and (refuge.person_days<.333333 or maxf(float(a.get("hunger",0)),float(b.get("hunger",0)))>65): return false
		if dispute.cause=="water_distribution" and (not refuge.water or maxf(float(a.get("thirst",0)),float(b.get("thirst",0)))>65): return false
		if dispute.cause=="security" and refuge.emergency: return false
		if dispute.cause=="sleeping_arrangements":
			var room: Dictionary=life.rooms.get(a.get("shelter_room_id",""),{})
			if room.get("occupants",[]).size()>=int(room.get("capacity",1)) and maxf(float(a.get("fatigue",0)),float(b.get("fatigue",0)))>75: return false
		if dispute.cause=="family_protection" and ((int(a.get("age",30))<18 and str(a.get("shelter_caregiver","")).is_empty()) or (int(b.get("age",30))<18 and str(b.get("shelter_caregiver","")).is_empty())): return false
		if float(a.get("cooperation",50))+float(b.get("cooperation",50))+float(relationship(a,mediator).trust)<90: return false
		dispute.status="RESOLVED"; dispute.resolution="negotiated agreement"; dispute["mediator"]=mediator.id; dispute["resolved_hour"]=social_hours
		change(a,b,{"conflict":-18,"trust":4,"cooperation":6}); change(b,a,{"conflict":-18,"trust":4,"cooperation":6})
		feel(a,{"stress":-5,"frustration":-7,"morale":3}); feel(b,{"stress":-5,"frustration":-7,"morale":3})
		counts.conflicts_resolved+=1; counts.resolution_hours+=maxf(0,social_hours-float(dispute.opened_hour))
		life.social.emit_event("shelter.conflict_resolved",mediator.id,dispute.duplicate(true)); return true
	return false

func leadership_potential(a: Dictionary) -> float:
	var p: Dictionary=a.get("shelter_social_profile",{})
	var technical:=80.0 if life._has_skill(a,"technical") else 30.0
	# IQ is deliberately absent: analytical task ability is not a mandate to lead.
	return float(p.get("communication",50))*.22+float(p.get("experience",50))*.14+float(p.get("confidence",50))*.12+float(a.get("cooperation",50))*.22+technical*.08+float(p.get("crisis_management",50))*.22

func preference(voter: Dictionary,candidate: Dictionary) -> float:
	if voter.id==candidate.id: return leadership_potential(candidate)*.7
	var r:=relationship(voter,candidate)
	return leadership_potential(candidate)*.45+float(r.trust)*.3+float(r.respect)*.15+float(r.cooperation)*.1-float(r.conflict)*.4

func leader_support(id: String,leader: String) -> float:
	var members:=residents(id); var candidate: Dictionary=life.social.by_id.get(leader,{})
	if candidate.is_empty() or candidate not in members: return 0.0
	var eligible:=0; var accepts:=0
	for voter in members:
		if int(voter.get("age",30))<18: continue
		eligible+=1
		if preference(voter,candidate)>=45: accepts+=1
	return float(accepts)/eligible if eligible>0 else 0.0

func elect(id: String) -> void:
	var council: Dictionary=councils[id]; var voters: Array[Dictionary]=[]
	for a in residents(id):
		if int(a.get("age",30))>=18: voters.append(a)
	var votes: Dictionary={}; var ballots: Dictionary={}
	for voter in voters:
		var best: String=""; var score:=45.0
		for candidate in voters:
			var value:=preference(voter,candidate)
			if value>score: best=candidate.id; score=value
		ballots[voter.id]=best
		voter["leadership_choice"]=best
		if not best.is_empty(): votes[best]=int(votes.get(best,0))+1
	var winner: String=""; var peak:=0
	for candidate in votes:
		if int(votes[candidate])>peak: peak=int(votes[candidate]); winner=candidate
	var support:=float(peak)/voters.size() if not voters.is_empty() else 0.0
	var previous:=str(council.leader)
	if support<float(config.minimum_acceptance): winner=""; counts.rejections+=1
	if winner!=previous: counts.leadership_changes+=1; council.term+=1
	council.leader=winner; council.support=support; council.votes=ballots; council.next_election=social_hours+float(config.election_hours)
	counts.elections+=1
	life.social.emit_event("shelter.election",id,{"leader":winner,"previous":previous,"votes":ballots,"support":support,"accepted":not winner.is_empty()})

func organize(id: String) -> void:
	var council: Dictionary=councils[id]; council.groups=[]; council.tasks={}
	for a in residents(id):
		if str(a.get("care_target","")).is_empty(): a.shelter_social_task=""
	if council.leader.is_empty(): return
	var leader: Dictionary=life.social.by_id[council.leader]; var team: Array=[]
	for a in residents(id):
		if int(a.get("age",30))<18 or a.id==leader.id or preference(a,leader)<45: continue
		team.append(a.id)
		var task: String="CLEAN"
		if life._has_skill(a,"medical"): task="ASSIST_MEDICAL"
		elif life._has_skill(a,"technical"): task="REPAIR_EQUIPMENT"
		elif life._has_skill(a,"security"): task="SECURITY"
		elif life._is_family_responsible(a): task="CHILDCARE"
		elif float(a.get("cooperation",50))>60: task="DISTRIBUTE_RESOURCES"
		if str(a.get("care_target","")).is_empty(): a.shelter_social_task=task
		council.tasks[a.id]=a.shelter_social_task
	if not team.is_empty(): council.groups.append({"id":id+":mutual_aid","organizer":leader.id,"members":team})

func converse(a: Dictionary,b: Dictionary) -> bool:
	if not together(a,b): return false
	counts.conversations+=1
	var beliefs: Dictionary=a.get("social_beliefs",{})
	if beliefs.is_empty():
		remember(b,{"topic":"personal_story","speaker":a.id,"origin":a.id,"time":social_hours,"evidence":"personal account"})
		return true
	var keys: Array=beliefs.keys(); keys.sort()
	var subject: String=keys[rng.randi_range(0,keys.size()-1)]; var claim: Dictionary=beliefs[subject]
	var origin:=str(claim.get("origin",claim.get("source",a.id)))
	var chain: Array=claim.get("relay_chain",[]).duplicate()
	if a.id not in chain: chain.append(a.id)
	var prior: Dictionary=b.get("social_beliefs",{}).get(subject,{})
	var hearsay:=clampf(float(claim.get("confidence",.5))*float(relationship(b,a).trust)/100.0*(1-float(b.get("skepticism",50))*.004),.01,.95)
	var challenged: bool=not prior.is_empty() and prior.get("claimed_value")!=claim.get("claimed_value") and (prior.get("evidence","")=="direct observation" or float(b.get("skepticism",50))>65)
	var packet: Dictionary={"subject":subject,"claimed_value":claim.get("claimed_value"),"source":a.id,"origin":origin,"origin_timestamp":claim.get("origin_timestamp",claim.get("acquired_at",null)),"origin_evidence":claim.get("origin_evidence",claim.get("evidence","unverified")),"relay_chain":chain.slice(-int(config.history_limit)),"confidence":hearsay,"evidence":"shelter conversation","acquired_at":life.manager.elapsed_seconds,"status":"CHALLENGED" if challenged else "RUMORED"}
	remember(b,packet)
	if challenged:
		counts.rumor_challenges+=1; change(b,a,{"respect":1}); life.social.emit_event("shelter.rumor_challenged",b.id,packet)
	elif prior.is_empty() or (prior.get("evidence","")!="direct observation" and hearsay>float(prior.get("confidence",0))):
		if not b.has("social_beliefs"): b.social_beliefs={}
		b.social_beliefs[subject]=packet.duplicate(true)
	life.social.emit_event("shelter.conversation",a.id,{"listener":b.id,"claim":packet})
	return true

func remember(a: Dictionary,item: Dictionary) -> void:
	if not a.has("shelter_conversations"): a.shelter_conversations=[]
	a.shelter_conversations.append(item.duplicate(true))
	if a.shelter_conversations.size()>int(config.history_limit): a.shelter_conversations.pop_front()

func metrics() -> Dictionary:
	var result: Dictionary=counts.duplicate(true); var emotions: Dictionary={}; var links: Dictionary={}
	for key in EMOTIONS: emotions[key]=0.0
	for key in DIMENSIONS: links[key]=0.0
	var n:=0; var edges:=0; var children:=0; var supervised:=0; var separated:=0; var open:=0; var causes: Dictionary={}
	for id in councils:
		for a in residents(id):
			n+=1; separated+=int(a.get("separated_family_count",0)>0)
			if int(a.get("age",30))<18:
				children+=1
				var caregiver: Dictionary=life.social.by_id.get(a.get("shelter_caregiver",""),{})
				supervised+=int(together(a,caregiver))
			for key in EMOTIONS: emotions[key]+=float(a.get(key,0))
			for r in a.get("shelter_relationships",{}).values():
				edges+=1
				for key in DIMENSIONS: links[key]+=float(r[key])
	for key in emotions: emotions[key]=emotions[key]/n if n>0 else null
	for key in links: links[key]=links[key]/edges if edges>0 else null
	for c in conflicts:
		open+=int(c.status=="OPEN"); causes[c.cause]=int(causes.get(c.cause,0))+1
	result["supervision_time_rate"]=float(counts.get("supervised_child_hours",0))/float(counts.child_hours) if float(counts.get("child_hours",0))>0 else null
	result["cooperative_acts_per_100_resident_hours"]=float(counts.get("cooperative_acts",0))*100/float(counts.resident_hours) if float(counts.get("resident_hours",0))>0 else null
	result["mean_conflict_resolution_hours"]=float(counts.get("resolution_hours",0))/int(counts.conflicts_resolved) if int(counts.get("conflicts_resolved",0))>0 else null
	result.merge({"schema_version":1,"social_hours":social_hours,"residents":n,"directed_relationships":edges,"mean_relationships":links,"emotions":emotions,"children":children,"supervised_children":supervised,"unsupervised_children":children-supervised,"supervision_rate":float(supervised)/children if children>0 else null,"separated_residents":separated,"open_conflicts":open,"conflicts_by_cause":causes,"councils":councils.duplicate(true)})
	return result
