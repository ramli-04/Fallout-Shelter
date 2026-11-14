extends RefCounted
const Convention=preload("res://scripts/traffic_conventions.gd")
var collision_world: WeakRef
var barrier_bodies: Dictionary={}

func bind_world(node: Node3D) -> void:
	collision_world=weakref(node)

func register_barrier(block: Dictionary, body: StaticBody3D) -> void:
	barrier_bodies[block.id]={"kind":block.kind,"body":weakref(body)}
## Deterministic planar dynamics; 10 simulation units = 1 m. No suspension solver.
const Map=preload("res://scripts/city_map.gd")
const SAT=preload("res://scripts/vehicle_collisions.gd")
var previous: Dictionary={}
var reservations: Dictionary={}
var scenes: Array=[]
var settings: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/vehicle_physics.json"))
const SPATIAL_CELL_SIZE := 96.0
var vehicle_cells: Dictionary={}
var pedestrian_cells: Dictionary={}
var vehicle_cell_by_id: Dictionary={}
var pedestrian_cell_by_id: Dictionary={}
var spatial_ready:=false
var spatial_step_active:=false

func reset() -> void:
	# A new population must not query the previous world's still-visible physics.
	collision_world=null
	barrier_bodies.clear()
	previous.clear(); reservations.clear(); scenes.clear(); vehicle_cells.clear(); pedestrian_cells.clear()
	vehicle_cell_by_id.clear(); pedestrian_cell_by_id.clear(); spatial_ready=false; spatial_step_active=false
	settings=JSON.parse_string(FileAccess.get_file_as_string("res://resources/vehicle_physics.json"))

func prepare_spatial(sim: RefCounted, step_active: bool = false) -> void:
	vehicle_cells.clear(); pedestrian_cells.clear(); vehicle_cell_by_id.clear(); pedestrian_cell_by_id.clear()
	for vehicle in sim.vehicles:
		if vehicle.status!="REMOVED": _index_actor(vehicle_cells,vehicle_cell_by_id,vehicle,SAT.body_position(vehicle))
	for agent in sim.manager.agents:
		if agent.get("riding","")!="" or agent.get("indoor_id","")!="" or agent.state in ["SHELTERED","SAFE","EXPOSED"]: continue
		_index_actor(pedestrian_cells,pedestrian_cell_by_id,agent,agent.position)
	spatial_ready=true; spatial_step_active=step_active

func ensure_spatial(sim: RefCounted) -> void:
	if not spatial_step_active: prepare_spatial(sim)

func end_spatial_step() -> void:
	spatial_step_active=false

func update_vehicle(vehicle: Dictionary) -> void:
	_remove_actor(vehicle_cells,vehicle_cell_by_id,vehicle)
	if vehicle.status!="REMOVED": _index_actor(vehicle_cells,vehicle_cell_by_id,vehicle,SAT.body_position(vehicle))

func _index_actor(grid: Dictionary, cells_by_id: Dictionary, actor: Dictionary, point: Vector2) -> void:
	var cell:=Vector2i((point/SPATIAL_CELL_SIZE).floor())
	if not grid.has(cell): grid[cell]=[]
	grid[cell].append(actor)
	cells_by_id[actor.get("id","")]=cell

func _remove_actor(grid: Dictionary, cells_by_id: Dictionary, actor: Dictionary) -> void:
	if not cells_by_id.has(actor.get("id","")): return
	var cell: Vector2i=cells_by_id[actor.get("id","")]
	if grid.has(cell):
		var bucket: Array=grid[cell]
		for i in range(bucket.size()-1,-1,-1):
			if bucket[i].get("id","")==actor.get("id",""):
				bucket.remove_at(i); break
		if bucket.is_empty(): grid.erase(cell)
	cells_by_id.erase(actor.get("id",""))

func _nearby(grid: Dictionary, point: Vector2, radius: float, body_position: bool = false) -> Array:
	var result: Array=[]
	var radius_squared:=radius*radius
	var first:=Vector2i(((point-Vector2.ONE*radius)/SPATIAL_CELL_SIZE).floor())
	var last:=Vector2i(((point+Vector2.ONE*radius)/SPATIAL_CELL_SIZE).floor())
	for x in range(first.x,last.x+1):
		for y in range(first.y,last.y+1):
			for actor in grid.get(Vector2i(x,y),[]):
				var position: Vector2=SAT.body_position(actor) if body_position else actor.position
				if point.distance_squared_to(position)<=radius_squared: result.append(actor)
	return result

func nearby_vehicles(point: Vector2, radius: float) -> Array:
	return _nearby(vehicle_cells,point,radius,true)

func nearby_pedestrians(point: Vector2, radius: float) -> Array:
	return _nearby(pedestrian_cells,point,radius)

func reserve_spawn(v: Dictionary, vehicles: Array, near: Vector2) -> Dictionary:
	var bays: Array=[]
	for lot in Map.parking_lots:
		for bay in lot.bays:
			if bay.occupied_by.is_empty(): bays.append(bay)
	bays.sort_custom(func(a,b): return near.distance_squared_to(a.position)<near.distance_squared_to(b.position))
	for i in range(mini(bays.size(),int(settings.spawn_attempts))):
		var bay: Dictionary=bays[i]
		var probe: Dictionary=v.duplicate(); probe.position=bay.position; probe.heading=bay.heading
		probe.height=0.0; probe.body_height=v.height
		probe.length+=float(settings.spawn_clearance)*2; probe.width+=float(settings.spawn_clearance)*2
		var clear:=true
		for other in vehicles+reservations.values():
			if not SAT.contact(probe,bay.position,bay.position,other,other.position,other.position).is_empty(): clear=false; break
		if not clear: continue
		for rect in Map.lots+Map.rock_obstacles:
			if not static_contact(probe,bay.position,bay.position,rect).is_empty(): clear=false; break
		if not clear or not physics_query(probe,bay.position,bay.position).is_empty(): continue
		bay.occupied_by=v.id; reservations[v.id]=probe
		return bay
	return {}

func capture(vehicles: Array) -> void:
	previous.clear()
	for v in vehicles:
		previous[v.id]={"body":SAT.body_position(v),"position":v.position,"speed":v.speed,"heading":v.get("heading",0),"route_index":v.get("route_index",0)}

static func parking_maneuver(v: Dictionary) -> bool:
	return int(v.get("parking_exit_end",0))>0 and int(v.get("route_index",0))<=int(v.parking_exit_end)

func departure_clear(v: Dictionary, vehicles: Array) -> bool:
	# One departure owns the shared aisle until it reaches the road. Wrecks
	# remain physical obstacles; this does not disable parking collisions.
	for lot in Map.parking_lots:
		if not lot.bounds.grow(8).has_point(v.position): continue
		for other in vehicles:
			if other.id!=v.id and parking_maneuver(other) and other.get("departure_lot","")==lot.id and other.status not in ["ACCIDENT","DESTROYED","REMOVED"]: return false
		v["departure_lot"]=lot.id
		break
	return true

static func static_contact(v: Dictionary, start: Vector2, finish: Vector2, rect: Rect2) -> Dictionary:
	var obstacle: Dictionary={"position":rect.get_center(),"length":rect.size.x,"width":rect.size.y,"heading":0.0,"height":v.height,"body_height":20}
	return SAT.contact(v,start,finish,obstacle,obstacle.position,obstacle.position)

static func block_contact(v: Dictionary, start: Vector2, finish: Vector2, block: Dictionary) -> Dictionary:
	var edge: Dictionary=Map.roads[int(block.edge)]
	var tangent: Vector2=Convention.edge_tangent(edge,block.position)
	var obstacle: Dictionary={"position":block.position,"length":float(edge.width),"width":8.0,"heading":tangent.angle()+PI*.5,"height":float(block.height),"body_height":2.0}
	return SAT.contact(v,start,finish,obstacle,obstacle.position,obstacle.position)

func resolve(sim: RefCounted, seconds: float) -> void:
	if seconds<=0: return
	if not spatial_ready: prepare_spatial(sim)
	for v in sim.vehicles:
		var in_parking: bool=parking_maneuver(v) or Map.parking_lots.any(func(lot):return lot.bounds.grow(8).has_point(v.position))
		var desired_offset: float=0.0 if in_parking or v.status=="REMOVED" else float(v.get("lane_offset",0)) if v.status in ["PARKED","ACCIDENT","DESTROYED"] else float(v.get("target_lane_offset",11.0))
		v.lane_offset=move_toward(float(v.get("lane_offset",0)),desired_offset,seconds*float(v.get("lane_change_rate",30)))
		v.body_position=v.position+Convention.right(Vector2.from_angle(float(v.heading)))*v.lane_offset
	for pair in SAT.candidates(sim.vehicles,previous):
		var a: Dictionary=pair[0]; var b: Dictionary=pair[1]
		if a.status=="ACCIDENT" and b.status=="ACCIDENT": continue
		var pa: Dictionary=previous[a.id]; var pb: Dictionary=previous[b.id]
		var hit:=SAT.contact(a,pa.body,a.body_position,b,pb.body,b.body_position)
		if hit.is_empty(): continue
		var velocity_a: Vector2=(a.body_position-pa.body)/seconds
		var velocity_b: Vector2=(b.body_position-pb.body)/seconds
		var severity: float=absf((velocity_a-velocity_b).dot(hit.normal))/10
		stop_at(a,pa,hit.time); stop_at(b,pb,hit.time)
		if severity>=float(settings.minimum_impact_mps):
			var total_mass: float=float(a.get("mass",1500))+float(b.get("mass",1500))
			impact(sim,a,b,severity*2*float(b.get("mass",1500))/total_mass,"vehicle")
			impact(sim,b,a,severity*2*float(a.get("mass",1500))/total_mass,"vehicle")
	for v in sim.vehicles:
		if v.status in ["PARKED","REMOVED","ACCIDENT"]: continue
		var before: Dictionary=previous[v.id]
		var earliest:=1.0; var kind:=""; var victim: Dictionary={}
		var physical:=physics_query(v,before.body,v.body_position)
		if not physical.is_empty(): earliest=physical.time; kind="world_obstacle"
		if v.height<3:
			for rect in Map.static_obstacles_near(SAT.swept_bounds(v,before.body,v.body_position)):
				var hit:=static_contact(v,before.body,v.body_position,rect)
				if not hit.is_empty() and hit.time<earliest: earliest=hit.time; kind="building"
		for block in sim.blocks:
			if not block.active or block.kind=="emergency_lane" or absf(block.height-v.height)>3: continue
			if block.kind in sim.EMERGENCY_PASS and v.kind!="Civilian": continue
			var hit:=block_contact(v,before.body,v.body_position,block)
			if not hit.is_empty() and hit.time<earliest: earliest=hit.time; kind="barrier"
		var path_center: Vector2=(before.body+v.body_position)*.5
		var path_radius: float=before.body.distance_to(v.body_position)*.5+maxf(v.length,v.width)+20
		for agent in nearby_pedestrians(path_center,path_radius):
			if agent.health<=0: continue
			if absf(float(agent.get("transport_height",0))-v.height)>3: continue
			var hit:=static_contact(v,before.body,v.body_position,Rect2(agent.position-Vector2(3,3),Vector2(6,6)))
			if not hit.is_empty() and hit.time<earliest:
				earliest=hit.time; kind="pedestrian"
				victim=agent
		if not kind.is_empty():
			var severity: float=maxf(before.speed,v.speed)/10
			stop_at(v,before,earliest)
			if kind=="pedestrian" and not victim.is_empty(): injure(sim,victim,severity*float(settings.pedestrian_damage_per_mps))
			if severity>=float(settings.minimum_impact_mps): impact(sim,v,{},severity,kind)
	for v in sim.vehicles:
		for id in v.passengers: sim.by_id[id].position=v.position
	spatial_ready=false; spatial_step_active=false

func stop_at(v: Dictionary, before: Dictionary, time: float) -> void:
	v.position=before.position.lerp(v.position,maxf(0,time-.002))
	v.body_position=before.body.lerp(v.body_position,maxf(0,time-.002)); v.speed=0
	v.collision_state="CONTACT"
	if before.has("route_index"): v.route_index=before.route_index
	v.heading=lerp_angle(float(before.get("heading",v.heading)),float(v.heading),clampf(time,0,1))

func injure(sim: RefCounted, agent: Dictionary, damage: float) -> void:
	agent.health=maxf(0,agent.health-damage)
	agent.injury="FATAL" if agent.health<=0 else "SERIOUS" if agent.health<40 else "MINOR"
	if agent.health<=0: agent.movement_speed=0; agent.objective=""; agent.social_target=""; agent.survival_status="DEAD"; agent.state="EXPOSED"
	sim.emit_event("traffic.casualty",agent.id,{"health":agent.health,"injury":agent.injury,"model":"simplified simulation assumption"})

func impact(sim: RefCounted, v: Dictionary, other: Dictionary, severity: float, kind: String) -> void:
	if v.status in ["ACCIDENT","REMOVED"]: return
	v.health=maxf(0,v.health-severity*float(settings.vehicle_damage_per_mps))
	sim.daily.release_destination(v)
	v.status="ACCIDENT"; v.speed=0; v.collision_state=kind; sim.counters.accidents+=1
	for id in v.passengers.duplicate():
		injure(sim,sim.by_id[id],severity*float(settings.occupant_damage_per_mps)); sim.leave(v,sim.by_id[id])
	var driver: Dictionary=sim.by_id[v.driver]
	var nearest: Dictionary=Map.nearest_edge(v.position,true,v.height)
	var edge: Dictionary=nearest.edge
	var normal: Vector2=(edge.b-edge.a).normalized().orthogonal()
	var offset: float=(SAT.body_position(v)-nearest.point).dot(normal)
	var reach: float=SAT.radius_on(v,normal)
	var lane_count: int=int(edge.get("lanes",2))
	var lane_width: float=float(edge.width)/maxi(1,lane_count)
	var affected: Array=[]
	for lane in range(lane_count):
		var left: float=-float(edge.width)*.5+lane*lane_width
		if offset+reach>=left and offset-reach<=left+lane_width: affected.append(lane)
	var block: Dictionary={"id":""}
	if not affected.is_empty():
		block=sim.create_block(driver,"accident",nearest.edge,v.position,v.height)
		var combined: Array=block.get("blocked_lanes",[]).duplicate()
		for lane in affected:
			if lane not in combined: combined.append(lane)
		block.blocked_lanes=combined; block.scope="whole_edge_conservative"
	var scene: Dictionary={"vehicle":v.id,"position":v.position,"block":block.id,"created":sim.manager.elapsed_seconds,"responders":[],"secured":false,"treated":false,"recovered":false,"evacuated":[]}
	scenes.append(scene)
	sim.emit_event("vehicle.accident",v.id,{"position":v.position,"other":other.get("id",""),"impact_mps":severity,"health":v.health,"kind":kind,"block":block.id,"blocked_lanes":affected,"road_edge":Map.roads.find(edge),"closure_scope":block.get("scope","none")})
	for a in sim.manager.agents:
		if a.position.distance_to(v.position)<sim.manager.living.observation_radius:
			sim.acquire(a,"accident:"+v.id,v.position,a.id,1,"direct observation")
	# Addressed emergency-system notification, never broadcast civilian knowledge.
	for role in ["Police","Medical","Fire"]:
		var best: Dictionary={}; var distance:=INF
		for a in sim.manager.agents:
			if a.get("police_unit_busy",false) or a.occupation!=role or a.health<=0 or a.get("responding_to","")!="" or a.state in ["SHELTERED","SAFE","EXPOSED"]: continue
			var d: float=a.position.distance_squared_to(v.position)
			if d<distance: best=a; distance=d
		if best.is_empty(): continue
		best.responding_to=v.id; best.social_target="accident:"+v.id
		best.known_locations[best.social_target]={"position":v.position,"source":"emergency dispatch","confidence":1,"timestamp":sim.manager.elapsed_seconds}
		scene.responders.append(best.id)
		sim.emit_event("emergency.dispatched",best.id,{"accident":v.id,"service":role})

func respond(sim: RefCounted, seconds: float) -> void:
	for scene in scenes:
		if scene.recovered: continue
		# Medical transport uses the existing vehicle boarding and road routing system.
		for id in scene.responders:
			var medic: Dictionary=sim.by_id[id]
			if medic.occupation!="Medical" or medic.health<=0 or not scene.treated: continue
			for ambulance in sim.vehicles:
				if ambulance.driver!=id or ambulance.status in ["ACCIDENT","REMOVED","DESTROYED"]: continue
				if medic.position.distance_to(scene.position)>80: continue
				var loaded:=false
				for patient in sim.manager.agents:
					if patient.id==id or patient.health<=0 or patient.health>=80 or patient.position.distance_to(ambulance.position)>65 or patient.id in scene.evacuated: continue
					if sim.board(ambulance,patient): scene.evacuated.append(patient.id); loaded=true
				if loaded:
					var target: String="medical:"+scene.vehicle
					medic.known_locations[target]={"position":Map.pois[2].position,"source":"emergency dispatch","confidence":1,"timestamp":sim.manager.elapsed_seconds}
					medic.social_target=target; ambulance.destination=""; ambulance.status="MOVING"
					sim.board(ambulance,medic)
					sim.emit_event("emergency.evacuation_started",id,{"accident":scene.vehicle,"patients":scene.evacuated})
		for id in scene.responders:
			var a: Dictionary=sim.by_id[id]
			if a.health<=0 or a.position.distance_to(scene.position)>80: continue
			if a.occupation=="Police" and not scene.secured:
				scene.secured=true; sim.emit_event("emergency.scene_secured",id,{"accident":scene.vehicle})
			if a.occupation in ["Medical","Fire"]:
				for patient in sim.manager.agents:
					if patient.health>0 and patient.health<80 and patient.position.distance_to(scene.position)<80:
						patient.health=minf(80,patient.health+float(settings.treatment_per_second)*seconds)
				if not scene.treated: scene.treated=true; sim.emit_event("emergency.treatment_started",id,{"accident":scene.vehicle})
		if settings.recovery_enabled and scene.secured and sim.manager.elapsed_seconds-scene.created>=float(settings.recovery_seconds):
			sim.remove_block(scene.block); scene.recovered=true
			for vehicle in sim.vehicles:
				if vehicle.id==scene.vehicle and vehicle.status=="ACCIDENT": vehicle.status="REMOVED"
			for id in scene.responders:
				sim.by_id[id].responding_to=""
				if sim.by_id[id].social_target=="accident:"+scene.vehicle: sim.by_id[id].social_target=""
			sim.emit_event("traffic.recovered",scene.vehicle,{"block":scene.block})

# Layers: 1 structures, 8 terrain, 32 vehicles, 64 furniture/curbs.
# Terrain and selection Areas are deliberately excluded from vehicle obstacle casts.
func physics_query(v: Dictionary, start: Vector2, finish: Vector2) -> Dictionary:
	var tree: SceneTree=Engine.get_main_loop() as SceneTree
	if tree==null: return {}
	var source: Node3D=collision_world.get_ref() if collision_world!=null else null
	var space: PhysicsDirectSpaceState3D=source.get_world_3d().direct_space_state if is_instance_valid(source) else tree.root.find_world_3d().direct_space_state
	var shape:=BoxShape3D.new(); shape.size=Vector3(v.length*.1,maxf(.3,float(v.get("body_height",1.5))-.4),v.width*.1)
	var query:=PhysicsShapeQueryParameters3D.new(); query.shape=shape; query.collision_mask=1|64
	if v.get("kind","Civilian")!="Civilian":
		var exclusions: Array[RID]=[]
		for record in barrier_bodies.values():
			var body: StaticBody3D=record.body.get_ref()
			if is_instance_valid(body) and record.kind in ["police","checkpoint","evacuation_checkpoint","restricted"]: exclusions.append(body.get_rid())
		query.exclude=exclusions
	var coordinates=preload("res://scripts/three_d/world_coordinates.gd")
	query.transform=Transform3D(Basis(Vector3.UP,-float(v.heading)),coordinates.to_world(start,float(v.height)+float(v.get("curb_clearance",.15))+shape.size.y*.5))
	query.motion=coordinates.to_world(finish,float(v.height)+float(v.get("curb_clearance",.15))+shape.size.y*.5)-query.transform.origin
	if not space.intersect_shape(query,1).is_empty(): return {"time":0.0}
	var fractions: PackedFloat32Array=space.cast_motion(query)
	if fractions.size()==2 and fractions[0]<1: return {"time":fractions[0]}
	return {}
