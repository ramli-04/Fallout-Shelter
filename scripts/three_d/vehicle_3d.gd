extends Node3D
## Presentation-only 3D vehicle. VehicleRuntime remains the sole movement/collision authority.
const Geometry = preload("res://scripts/three_d/geometry.gd")
const ModelCatalog = preload("res://scripts/three_d/runtime_model_catalog.gd")
var vehicle_id := ""
var model := "sedan"
var kind := "Civilian"
var length := 4.4
var width := 1.9
var height := 1.6
var wheel_radius := 0.31
var wheel_positions: Array[Vector3] = []
var wheel_is_front: Array[bool] = []
var imported_wheels: Array[Node3D] = []
var imported_wheel_rest: Array[Transform3D] = []
var imported_model_root: Node3D
var tire_batch: MultiMeshInstance3D
var hub_batch: MultiMeshInstance3D
var wheel_steering := 0.0
var lamps: Dictionary = {}
var paint_mesh: MeshInstance3D
var paint_meshes: Array[MeshInstance3D] = []
var base_paint := Color.WHITE
var smoke: GPUParticles3D
var fire: GPUParticles3D
var previous_heading := 0.0
var wheel_phase := 0.0
var light_clock := 0.0
var last_health := -1.0
var far_lod := false

func configure(record: Dictionary) -> void:
	vehicle_id = str(record.get("id","vehicle"))
	model = str(record.get("model",record.get("vehicle_model",_model_from_kind(str(record.get("kind","Civilian"))))))
	kind = str(record.get("kind","Civilian"))
	var dimensions:=ModelCatalog.vehicle_dimensions(model)
	length=dimensions.z; width=dimensions.x; height=dimensions.y
	name = vehicle_id
	_build_model()

func _model_from_kind(value: String) -> String:
	return {"Police":"police","Medical":"ambulance","Fire":"fire_engine","Civil protection":"rescue_truck"}.get(value,"sedan")

func _build_model() -> void:
	var emergency := kind != "Civilian"
	var paint: Color = {"Police":Color("294c70"),"Medical":Color("e8e8dc"),"Fire":Color("a83c32"),"Civil protection":Color("62704d")}.get(kind,Color.from_hsv(fposmod(float(abs(vehicle_id.hash()))*.0001,1.0),.38,.72))
	if model=="swat": paint=Color("202b35")
	base_paint=paint
	wheel_radius = clampf(width*.17,.24,.40)
	var cabin_height: float = clampf(height*.48,.48,1.15)
	var chassis_height: float = clampf(height*.40,.45,.82)
	var axle_z: float = length*.34
	var wheel_y: float = wheel_radius
	var wheel_x: float = width*.43
	var cabin_length: float = length*(.48 if model in ["van","delivery_truck","minibus","ambulance","fire_engine","rescue_truck"] else .56)
	var cabin_z: float = length*(.27 if model in ["van","delivery_truck","minibus","ambulance","fire_engine","rescue_truck"] else -.02)
	var using_imported_model := _build_imported_model()
	if not using_imported_model:
		paint_mesh = Geometry.box(self,Vector3(width*.78,chassis_height,length*.88),Vector3(0,wheel_y+chassis_height*.5,0),paint)
		paint_mesh.material_override = Geometry.shared_material(paint)
		paint_meshes.append(paint_mesh)
		var cargo: bool = model in ["van","delivery_truck","minibus","ambulance","fire_engine","rescue_truck"]
		if cargo:
			var rear_length: float = length*.55
			var rear_center := -length*.18
			var cargo_height: float = maxf(.55,height-wheel_y-chassis_height*.62)
			var cargo_color: Color = paint.lightened(.10) if kind=="Medical" else paint
			var box_body := Geometry.box(self,Vector3(width*.76,cargo_height,rear_length),Vector3(0,wheel_y+chassis_height*.45+cargo_height*.5,rear_center),cargo_color)
			if kind=="Medical": box_body.material_override=Geometry.shared_material(cargo_color)
			paint_meshes.append(box_body)
			var cab_height: float=minf(cabin_height,maxf(.60,cargo_height*.66))
			var cab:=Geometry.box(self,Vector3(width*.70,cab_height,length*.32),Vector3(0,wheel_y+chassis_height*.48+cab_height*.5,cabin_z),paint)
			cab.material_override=Geometry.shared_material(paint)
			paint_meshes.append(cab)
			Geometry.box(self,Vector3(width*.56,cab_height*.42,.035),Vector3(0,wheel_y+chassis_height*.48+cab_height*.69,cabin_z+length*.16),Color("507078"))
			if model in ["fire_engine","rescue_truck"]:
				for side in [-1.0,1.0]:
					Geometry.box(self,Vector3(.055,.16,length*.70),Vector3(side*width*.395,wheel_y+chassis_height*.6,-.05),Color("dfd5b8"))
				Geometry.box(self,Vector3(width*.46,.12,.14),Vector3(0,wheel_y+chassis_height*.68,-length*.30),Color("d4c6a5"))
		else:
			var roof_y: float=wheel_y+chassis_height+cabin_height*.5
			var roof_width: float=width*.68
			var roof_mesh:=Geometry.box(self,Vector3(roof_width,cabin_height,cabin_length),Vector3(0,roof_y,cabin_z),Color("58747a"))
			roof_mesh.material_override=Geometry.shared_material(Color("58747a"))
			if model=="suv" or model=="pickup":
				Geometry.box(self,Vector3(width*.70,.10,cabin_length*.96),Vector3(0,roof_y+cabin_height*.52,cabin_z),paint.darkened(.08))
			if model=="pickup":
				Geometry.box(self,Vector3(width*.70,.40,length*.30),Vector3(0,wheel_y+chassis_height*.95,-length*.31),paint.lightened(.08))
	# Imported static wheel meshes are animated here; the fallback wheels remain batched.
	if using_imported_model:
		wheel_radius=maxf(.12,minf(width,height)*.17)
	else:
		for side in [-1.0,1.0]:
			for axle in [-1.0,1.0]:
				wheel_positions.append(Vector3(side*wheel_x,wheel_y,axle*axle_z))
				wheel_is_front.append(axle>0)
		tire_batch=_wheel_batch(Geometry.cylinder_mesh(wheel_radius,.24,12),Color("232729"),"TireBatch")
		hub_batch=_wheel_batch(Geometry.cylinder_mesh(wheel_radius*.48,.255,10),Color("9da7a3"),"HubBatch")
		hub_batch.visible=not far_lod
	# Front/rear lamps use their own material because they change state at runtime.
	for side in [-1.0,1.0]:
		lamps["head_%s"%side]=_lamp(Vector3(side*width*.31,wheel_y+chassis_height*.47,length*.455),Vector3(.18,.13,.07),Color("e7e2c7"))
		lamps["tail_%s"%side]=_lamp(Vector3(side*width*.31,wheel_y+chassis_height*.45,-length*.455),Vector3(.15,.16,.07),Color("9d382f"))
		lamps["reverse_%s"%side]=_lamp(Vector3(side*width*.20,wheel_y+chassis_height*.34,-length*.455),Vector3(.10,.09,.07),Color("d8d9c8"))
	if emergency:
		var lightbar:=Geometry.box(self,Vector3(width*.48,.13,.34),Vector3(0,wheel_y+chassis_height+cabin_height+.10,cabin_z),Color("303b41"))
		lightbar.material_override=Geometry.material(Color("303b41"))
		lamps["siren_red"]=_lamp(Vector3(-width*.17,wheel_y+chassis_height+cabin_height+.20,cabin_z),Vector3(.18,.12,.24),Color("e4493c"))
		lamps["siren_blue"]=_lamp(Vector3(width*.17,wheel_y+chassis_height+cabin_height+.20,cabin_z),Vector3(.18,.12,.24),Color("4d9cea"))
		if model=="ambulance":
			Geometry.box(self,Vector3(.08,.44,.04),Vector3(0,wheel_y+chassis_height*.8,-length*.06),Color("c54339"))
			Geometry.box(self,Vector3(.38,.08,.04),Vector3(0,wheel_y+chassis_height*.8,-length*.06),Color("c54339"))
		if model=="police":
			Geometry.box(self,Vector3(.035,.22,length*.68),Vector3(width*.40,wheel_y+chassis_height*.58,0),Color("e2e2d6"))

func _build_imported_model() -> bool:
	var path: String=ModelCatalog.vehicle_path(model,kind)
	if path.is_empty(): return false
	var packed := load(path) as PackedScene
	if packed == null:
		return false
	var instance := packed.instantiate() as Node3D
	if instance == null:
		return false
	var bounds := ModelCatalog.local_bounds(instance)
	if bounds.size.x <= 0.001 or bounds.size.y <= 0.001 or bounds.size.z <= 0.001:
		instance.free()
		return false
	var fit := Vector3(width/bounds.size.x,height/bounds.size.y,length/bounds.size.z)
	instance.scale=fit
	instance.position=Vector3(-bounds.get_center().x*fit.x,-bounds.position.y*fit.y,-bounds.get_center().z*fit.z)
	instance.name="ImportedVehicleModel"
	add_child(instance)
	imported_model_root=instance
	for node in instance.find_children("*","Node3D",true,false):
		var wheel_name:=str(node.name).to_lower()
		# The SUV includes one static rear-mounted spare as well as its four road wheels.
		if wheel_name.contains("wheel") and wheel_name!="wheel-back":
			var wheel:=node as Node3D
			imported_wheels.append(wheel)
			imported_wheel_rest.append(wheel.transform)
			wheel_is_front.append(str(wheel.name).to_lower().contains("front"))
	if model=="swat":
		for node in instance.find_children("*","MeshInstance3D",true,false):
			if not str(node.name).to_lower().contains("wheel"):
				node.material_override=Geometry.shared_material(Color("202b35"))
		Geometry.label(self,"SWAT",Vector3(width*.51,height*.62,0),Color.WHITE,28,.012)
	if imported_wheels.size()<4:
		instance.free()
		imported_model_root=null
		imported_wheels.clear(); imported_wheel_rest.clear(); wheel_is_front.clear()
		return false
	return true

func _wheel_batch(mesh: Mesh, color: Color, batch_name: String) -> MultiMeshInstance3D:
	var instances:=MultiMesh.new()
	instances.transform_format=MultiMesh.TRANSFORM_3D
	instances.mesh=mesh
	instances.instance_count=wheel_positions.size()
	for index in range(wheel_positions.size()): instances.set_instance_transform(index,_wheel_transform(index,0.0,0.0))
	var batch:=MultiMeshInstance3D.new()
	batch.name=batch_name
	batch.multimesh=instances
	batch.material_override=Geometry.shared_material(color)
	add_child(batch)
	return batch

func _wheel_transform(index: int, phase: float, steering: float) -> Transform3D:
	var steer:=steering if wheel_is_front[index] else 0.0
	var basis:=Basis(Vector3.UP,steer)*Basis(Vector3.RIGHT,phase)*Basis(Vector3(0,0,1),PI*.5)
	return Transform3D(basis,wheel_positions[index])

func _lamp(at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var lamp:=Geometry.box(self,size,at,color)
	lamp.material_override=Geometry.material(color)
	var material: StandardMaterial3D=lamp.material_override
	material.emission_enabled=true
	material.emission=color
	material.emission_energy_multiplier=0.0
	return lamp

func sync_vehicle(record: Dictionary, delta: float) -> void:
	if not is_inside_tree(): return
	light_clock+=delta
	var speed: float=float(record.get("speed",0.0))
	wheel_phase+=speed*.1*delta/maxf(.05,wheel_radius)
	var heading: float=float(record.get("heading",record.get("parking_heading",previous_heading)))
	var change: float=wrapf(heading-previous_heading,-PI,PI)
	wheel_steering=clampf(float(record.get("steering",record.get("steering_angle",change*2.0))),-.58,.58)
	if not imported_wheels.is_empty():
		for index in range(imported_wheels.size()):
			var wheel:=imported_wheels[index]
			if not is_instance_valid(wheel): continue
			var steer:=wheel_steering if wheel_is_front[index] else 0.0
			var rest: Transform3D=imported_wheel_rest[index]
			wheel.transform=Transform3D(Basis(Vector3.UP,steer)*Basis(Vector3.RIGHT,wheel_phase)*rest.basis,rest.origin)
	else:
		for index in range(wheel_positions.size()):
			var transform:=_wheel_transform(index,wheel_phase,wheel_steering)
			tire_batch.multimesh.set_instance_transform(index,transform)
			hub_batch.multimesh.set_instance_transform(index,transform)
	previous_heading=heading
	var emergency_active: bool=bool(record.get("siren_active",record.get("emergency_response",false))) and record.get("status","") not in ["PARKED","REMOVED"]
	var phase_on: bool=int(light_clock*6.0)%2==0
	_set_lamp("siren_red",emergency_active and phase_on)
	_set_lamp("siren_blue",emergency_active and not phase_on)
	var headlights: bool=bool(record.get("headlights_on",false))
	var braking: bool=bool(record.get("braking",false)) or str(record.get("status","")) in ["ACCIDENT","DESTROYED"]
	var reversing: bool=bool(record.get("reversing",false)) or speed<-.1
	for side in [-1.0,1.0]:
		_set_lamp("head_%s"%side,headlights)
		_set_lamp("tail_%s"%side,braking)
		_set_lamp("reverse_%s"%side,reversing)
	var health:=float(record.get("health",100.0))
	var damaged: bool=health<100.0
	if damaged and not is_equal_approx(health,last_health):
		var damaged_paint:=Geometry.material(base_paint.lerp(Color("5c5045"),clampf((100-health)/130.0,0,.55)))
		for mesh in paint_meshes: mesh.material_override=damaged_paint
		last_health=health
	var crashed: bool=str(record.get("status","")) in ["ACCIDENT","DESTROYED"]
	if crashed and health<78.0:
		_ensure_particles()
		smoke.emitting=true
		fire.emitting=health<18.0 or str(record.get("status",""))=="DESTROYED"
	elif smoke!=null:
		smoke.emitting=false; fire.emitting=false
	var camera:=get_viewport().get_camera_3d()
	if camera!=null:
		var distant:=global_position.distance_to(camera.global_position)>135.0
		if distant!=far_lod:
			far_lod=distant
			if hub_batch!=null: hub_batch.visible=not far_lod

func _set_lamp(key: String, enabled: bool) -> void:
	if not lamps.has(key): return
	var material: StandardMaterial3D=lamps[key].material_override
	material.emission_energy_multiplier=2.4 if enabled else 0.0

func _ensure_particles() -> void:
	if smoke!=null: return
	smoke=_particles(Color("646965"),.65,2.2)
	smoke.position=Vector3(0,height+.18,-length*.12)
	fire=_particles(Color("e87532"),.35,.7)
	fire.position=Vector3(0,height*.48,-length*.12)

func _particles(color: Color, velocity: float, lifetime: float) -> GPUParticles3D:
	var particles:=GPUParticles3D.new()
	particles.amount=16
	particles.lifetime=lifetime
	particles.emitting=false
	particles.visibility_aabb=AABB(Vector3(-2,-1,-2),Vector3(4,6,4))
	var process_material:=ParticleProcessMaterial.new()
	process_material.emission_shape=ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_material.emission_sphere_radius=.18
	process_material.direction=Vector3(0,1,0)
	process_material.initial_velocity_min=velocity*.45
	process_material.initial_velocity_max=velocity
	process_material.gravity=Vector3(0,.45,0)
	process_material.scale_min=.10
	process_material.scale_max=.30
	process_material.color=color
	particles.process_material=process_material
	var puff:=SphereMesh.new(); puff.radius=.35; puff.height=.7; puff.radial_segments=6; puff.rings=3
	var puff_material:=StandardMaterial3D.new(); puff_material.vertex_color_use_as_albedo=true
	puff.material=puff_material
	particles.draw_pass_1=puff
	add_child(particles)
	return particles
