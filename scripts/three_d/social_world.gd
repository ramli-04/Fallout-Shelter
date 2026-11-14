extends Node3D
## Lightweight visual observers. No vehicle physics or decisions run in rendering.
const Map=preload("res://scripts/city_map.gd")
const C=preload("res://scripts/three_d/world_coordinates.gd")
const G=preload("res://scripts/three_d/geometry.gd")
var manager: Node
var view: Node
var vehicle_bodies: Dictionary={}
var cars := {}
var barriers := {}
var barrier_labels := {}
var barrier_unmanaged := {}
var barrier_colliders := {}
var labels := {}
var school: Node3D
var debug_mesh: MeshInstance3D
var last_run := ""
var evacuation_markers: Dictionary={}

func rebuild() -> void:
	for child in get_children(): child.queue_free()
	evacuation_markers.clear()
	vehicle_bodies.clear(); cars.clear(); barriers.clear(); barrier_labels.clear(); barrier_unmanaged.clear(); barrier_colliders.clear(); labels.clear(); school=null; debug_mesh=null
	if manager.social==null: return
	last_run=manager.ai_bridge.run_id
	school=Node3D.new(); school.position=C.to_world(manager.social.school_position)
	add_child(school)
	for v in manager.social.vehicles:
		var physical:=G.collider(self,Vector3(v.width*.1,v.body_height,v.length*.1),C.to_world(v.position)+Vector3.UP*v.body_height*.5,32)
		physical.collision_mask=1|32|64; vehicle_bodies[v.id]=physical
		if _wanted(v): _make_car(v)
	var mesh:=ImmediateMesh.new(); mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for edge in Map.roads:
		for i in range(1,edge.points.size()):
			var first: float=10 if edge.get("elevated",false) else 10*(1-float(i-1)/(edge.points.size()-1)) if edge.get("ramp",false) else 0
			var last: float=10 if edge.get("elevated",false) else 10*(1-float(i)/(edge.points.size()-1)) if edge.get("ramp",false) else 0
			mesh.surface_add_vertex(C.to_world(edge.points[i-1],first+.7)); mesh.surface_add_vertex(C.to_world(edge.points[i],last+.7))
	mesh.surface_end()
	debug_mesh=MeshInstance3D.new(); debug_mesh.mesh=mesh; debug_mesh.material_override=G.material(Color("e6bd60")); debug_mesh.material_override.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; add_child(debug_mesh)

func _wanted(v: Dictionary) -> bool:
	if v.status=="REMOVED": return false
	if view==null or view.city==null or view.city.streamer==null: return true
	return not view.render_config.enabled or view.city.streamer.wants_point(v.position)

func _make_car(v: Dictionary) -> void:
	var car:=preload("res://scripts/three_d/vehicle_3d.gd").new()
	car.configure(v)
	add_child(car)
	cars[v.id]=car
	var label: Label3D=G.label(car,v.id+" / "+v.kind,Vector3(0,2.8,0),Color.WHITE,25,.03); labels[v.id]=label

func _process(delta: float) -> void:
	if manager==null or manager.social==null: return
	if last_run!=manager.ai_bridge.run_id: rebuild()
	_sync_evacuation_markers()
	var debug: bool=manager.get_meta("road_debug",false)
	if is_instance_valid(debug_mesh): debug_mesh.visible=debug
	for v in manager.social.vehicles:
		var physical: StaticBody3D=vehicle_bodies.get(v.id)
		if physical!=null:
			physical.position=C.to_world(v.position,(.07 if v.status=="PARKED" else .25)+.97*float(v.get("height",0))+maxf(0,float(v.get("curb_clearance",.15))-.15)+v.body_height*.5)
			var center: Vector2=v.get("body_position",v.position); physical.position.x=center.x*.1; physical.position.z=center.y*.1
			physical.rotation.y=-float(v.get("heading",v.parking_heading))+PI*.5
			physical.collision_layer=32 if v.status!="REMOVED" else 0
		if not _wanted(v):
			if cars.has(v.id): cars[v.id].queue_free(); cars.erase(v.id); labels.erase(v.id)
			continue
		if not cars.has(v.id): _make_car(v)
		var car: Node3D=cars[v.id]
		car.position=C.to_world(v.position,(.07 if v.status=="PARKED" else .25)+.97*float(v.get("height",0)))
		car.position.y+=maxf(0,float(v.get("curb_clearance",.15))-.15)
		car.rotation.y=-float(v.get("heading",v.parking_heading))+PI*.5
		var body: Vector2=v.get("body_position",v.position)
		car.position.x=body.x*.1; car.position.z=body.y*.1
		car.visible=v.status!="REMOVED"
		car.rotation.z=.25 if v.status in ["ACCIDENT","DESTROYED"] else 0.0
		car.sync_vehicle(v,delta)

		labels[v.id].visible=debug
		if debug: labels[v.id].text="%s / %s / HP %.0f / %s / %s / %s"%[v.id,v.kind,v.health,v.status,v.get("driving_reason",""),v.get("driving_provider","")]
	for block in manager.social.blocks:
		if not barriers.has(block.id):
			var barrier:=preload("res://scripts/three_d/roadblock_3d.gd").new(); barrier.record=block; barrier.position=C.to_world(block.position,.4+float(block.get("height",0))); add_child(barrier)
			var color:=Color("6b82a0") if block.get("managed_by_policy",false) else Color("b56f3f")
			if block.kind=="emergency_lane":
				var edge: Dictionary=Map.roads[block.edge]
				var tangent: Vector2=(edge.points[-1]-edge.points[0]).normalized()
				for offset in [-20.0,0.0,20.0]: G.cylinder(barrier,.12,.38,Vector3(tangent.x*offset*.1,.19,tangent.y*offset*.1),Color("e7bd4a"))
			else:
				var edge: Dictionary=Map.roads[block.edge]
				var barrier_width: float=float(edge.width)*.1
				G.box(barrier,Vector3(barrier_width,1,.35),Vector3(0,.5,0),color)
				for side in [-barrier_width*.4,barrier_width*.4]: G.box(barrier,Vector3(.3,1.6,.3),Vector3(side,.5,0),Color("e3dbba"))
				var road_direction: Vector2=preload("res://scripts/traffic_conventions.gd").edge_tangent(edge,block.position)
				barrier.rotation.y=-road_direction.angle()+PI*.5
				var collider: StaticBody3D=G.collider(barrier,Vector3(barrier_width,1,.5),Vector3(0,.5,0),64)
				collider.collision_mask=0; barrier_colliders[block.id]=collider
				manager.social.traffic.register_barrier(block,collider)
			if block.has("deployment_id") and block.kind!="emergency_lane":
				for offset in [-2.0,0.0,2.0]:
					var cone:=G.cylinder(barrier,.24,.65,Vector3(offset,.32,1.2),Color("e69538")); G.make_mesh_unique(cone); cone.mesh.top_radius=.05
			var unmanaged_on_create: bool=block.get("unmanaged",false)
			var caption: String=("EMERGENCY LANE" if block.kind=="emergency_lane" else block.kind.to_upper())+(" / UNMANAGED" if unmanaged_on_create else "")
			barrier_labels[block.id]=G.label(barrier,caption,Vector3(0,2,0),Color("eddbb1"),28,.035)
			var area:=Area3D.new(); area.collision_layer=128; area.collision_mask=0; area.set_meta("entity_owner",barrier)
			var shape:=CollisionShape3D.new(); var box:=BoxShape3D.new(); box.size=Vector3(float(Map.roads[block.edge].width)*.1,2,2)
			shape.shape=box; shape.position.y=1; area.add_child(shape); barrier.add_child(area); barrier.selection_area=area
			barriers[block.id]=barrier
			barrier_unmanaged[block.id]=unmanaged_on_create
		barriers[block.id].visible=block.active
		barriers[block.id].selection_area.collision_layer=128 if block.active else 0
		if barrier_colliders.has(block.id): barrier_colliders[block.id].collision_layer=64 if block.active else 0
		var current_unmanaged: bool=block.get("unmanaged",false)
		if barrier_unmanaged.get(block.id,current_unmanaged)!=current_unmanaged:
			barrier_unmanaged[block.id]=current_unmanaged
			var current_caption: Label3D=barrier_labels[block.id]
			current_caption.text=("EMERGENCY LANE" if block.kind=="emergency_lane" else block.kind.to_upper())+(" / UNMANAGED" if current_unmanaged else "")
			if block.get("managed_by_policy",false):
				var plank: MeshInstance3D=barriers[block.id].get_child(0)
				plank.material_override=G.material(Color("895c74") if current_unmanaged else Color("6b82a0"))

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode==KEY_F8:
		manager.set_meta("road_debug",not manager.get_meta("road_debug",false))

func _sync_evacuation_markers() -> void:
	for op in manager.social.evacuation.operations:
		if not op.gathering.is_finite(): continue
		if not evacuation_markers.has(op.id):
			var marker:=Node3D.new(); add_child(marker)
			G.cylinder(marker,1.8,.04,Vector3(0,.04,0),Color("a69d63"))
			var caption:=G.label(marker,"",Vector3(0,3,0),Color("e2dba5"),24,.03)
			evacuation_markers[op.id]={"node":marker,"label":caption}
		var entry: Dictionary=evacuation_markers[op.id]
		entry.node.position=C.to_world(op.gathering,.08); entry.node.visible=op.state!="COMPLETE"
		entry.label.text=op.id+" / GATHERING\n"+op.state+" / estimated "+str(op.estimated_count)
