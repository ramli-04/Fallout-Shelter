extends Node3D
## Reusable static obstruction; color/height are deterministic visual choices, not RNG draws.
const Geometry = preload("res://scripts/three_d/geometry.gd")
const EnvironmentTextures = preload("res://scripts/three_d/environment_textures.gd")
const ModelCatalog = preload("res://scripts/three_d/runtime_model_catalog.gd")
var exposed_objects: Array[Node3D] = []
var destruction_state := "INTACT"
var collapse_tween: Tween
var footprint := Rect2()
var height := 0.0
var interior_record: Dictionary={}
var interior_upper: Array[Node3D]=[]
var interior_art: Array[Node3D]=[]
var interior_label: Label3D
var interior_door: MeshInstance3D
var interior_door_body: StaticBody3D
var obscured := false
var fade_materials: Array[StandardMaterial3D] = []
var imported_visual: Node3D

var visual_only:=false
var source_index:=-1
var fader: RefCounted
var fade_amount: float:
	get: return 1.0 if fader==null else fader.amount
var detail_enabled:=true
var fade_settings: Dictionary=preload("res://scripts/three_d/render_options.gd").load_options()

func configure(rect: Rect2, index: int) -> void:
	var map=preload("res://scripts/city_map.gd")
	var recipe: Dictionary=preload("res://scripts/three_d/building_shape.gd").plan(index)
	source_index=index; set_meta("building_index",index)
	var size: Vector2=recipe.size
	footprint=Rect2(rect.get_center()-size*5,size*10)
	position=preload("res://scripts/three_d/world_coordinates.gd").to_world(rect.get_center())
	rotation.y=map.lot_angles[index]; height=recipe.height
	var color: Color=recipe.color
	if not recipe.interior.is_empty(): interior_record=recipe.interior
	var shell: Node3D=preload("res://scripts/three_d/building_sprites.gd").build(self,recipe,index)
	set_meta("architecture_type",shell.get_meta("architecture_type"))
	if not interior_record.is_empty():
		_accessible_interior(size,color)
		for child in get_children():
			if child!=shell and child is VisualInstance3D:
				interior_art.append(child); child.visible=false
		interior_upper.append(shell)
	else:
		for box in preload("res://scripts/three_d/building_shape.gd").boxes(recipe): _collider(box.size,box.position)

func _add_imported_visual(index: int, size: Vector2, building_height: float) -> bool:
	var packed := load(ModelCatalog.building_path(index)) as PackedScene
	if packed == null:
		return false
	var instance := packed.instantiate() as Node3D
	if instance == null:
		return false
	var bounds := ModelCatalog.local_bounds(instance)
	if bounds.size.x <= 0.001 or bounds.size.y <= 0.001 or bounds.size.z <= 0.001:
		instance.free()
		return false
	var fit := Vector3(size.x/bounds.size.x,building_height/bounds.size.y,size.y/bounds.size.z)
	instance.scale=fit
	instance.position=Vector3(-bounds.get_center().x*fit.x,-bounds.position.y*fit.y,-bounds.get_center().z*fit.z)
	instance.name="ImportedBuildingModel"
	instance.set_meta("asset_path",ModelCatalog.building_path(index))
	add_child(instance)
	imported_visual=instance
	return true

func _collider(size: Vector3, at: Vector3) -> StaticBody3D:
	return null if visual_only else Geometry.collider(self,size,at)

func _wing(size: Vector3, base: Vector3, color: Color, windows_enabled: bool = true) -> void:
	var body := Geometry.box(self,size,base+Vector3(0,size.y/2,0),color)
	body.material_override=EnvironmentTextures.facade_material(color)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	Geometry.box(self,Vector3(size.x+0.25,0.28,size.z+0.25),base+Vector3(0,size.y,0),Color("647471"))
	_collider(size,base+Vector3(0,size.y/2,0))
	if not windows_enabled: return
	var windows := MultiMeshInstance3D.new()
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.1,1.0,0.06)
	instances.mesh = mesh
	var transforms: Array[Transform3D] = []
	var floors := maxi(1,int((size.y-0.5)/2.6))
	for side in range(4):
		var frontage := size.x if side%2 == 0 else size.z
		var half_depth := (size.z if side%2 == 0 else size.x)*0.5
		var columns := maxi(1,int((frontage-1)/2.8))
		var basis := Basis(Vector3.UP,side*PI/2)
		for floor_index in range(floors):
			for column in range(columns):
				var offset := (column-(columns-1)*0.5)*2.8
				var point := base + basis*Vector3(offset,1.5+floor_index*2.6,half_depth+0.04)
				transforms.append(Transform3D(basis,point))
	instances.instance_count = transforms.size()
	for i in range(transforms.size()): instances.set_instance_transform(i,transforms[i])
	windows.multimesh = instances
	windows.material_override = Geometry.material(Color("a8c8cf"))
	windows.visibility_range_end = float(fade_settings.detail_distance)
	add_child(windows)

func add_poi(kind: String) -> void:
	if has_meta("architecture_type"): return
	var front := footprint.size.y*0.05+0.12
	var color := Color("618eae") if kind == "Police Station" else Color("b95450") if kind == "Fire Station" else Color("e4eadc") if kind == "Medical Station" else Color("b4b891")
	Geometry.box(self,Vector3(9.3,1.0,0.2),Vector3(0,2.6,front),color)
	Geometry.label(self,kind.to_upper(),Vector3(0,height+1.2,0),color,24,0.025)
	Geometry.box(self,Vector3(2.5,2.1,0.1),Vector3(0,1.1,front),Color("88c9d5"))
	if kind in ["Police Station","Fire Station","Medical Station"]:
		if kind == "Medical Station":
			Geometry.box(self,Vector3(0.25,1.2,0.15),Vector3(3,2.6,front+0.15),Color("bd4c47"))
			Geometry.box(self,Vector3(1.2,0.25,0.15),Vector3(3,2.6,front+0.15),Color("bd4c47"))
		for x in [-2.0,2.0]:
			if kind == "Fire Station":
				Geometry.box(self,Vector3(2.7,2.5,0.2),Vector3(x,1.25,front),Color("545e60"))
	elif kind == "Bank":
		for x in [-3.0,3.0]:
			Geometry.cylinder(self,0.4,3,Vector3(x,1.5,front),Color("d2d8c6"))
		Geometry.box(self,Vector3(0.3,0.3,0.5),Vector3(1.8,2.9,front+0.1),Color("414b4c"))
	elif kind == "School":
		Geometry.box(self,Vector3(7,0.12,2.0),Vector3(0,0.15,6),Color("d8b879"))
		for side in [-1,1]:
			Geometry.box(self,Vector3(0.15,1.8,0.15),Vector3(side*1.2,0.95,6),Color("bb7550"))
		Geometry.box(self,Vector3(2.7,0.15,0.15),Vector3(0,1.9,6),Color("bb7550"))
		Geometry.box(self,Vector3(0.6,0.15,0.6),Vector3(0,0.65,6),Color("52889e"))
func destroy_to(state: String, delay: float) -> void:
	reset_fade()
	destruction_state = state
	if state == "INTACT": return
	for object in exposed_objects: object.hide()
	for child in get_children():
		if child is StaticBody3D: child.collision_layer = 0
	collapse_tween = create_tween()
	collapse_tween.tween_interval(delay)
	collapse_tween.tween_property(self,"scale:y",0.08 if state == "DESTROYED" else 0.55,1.0)
	collapse_tween.parallel().tween_property(self,"rotation:z",0.12,0.8)
	for child in get_children():
		if child is GeometryInstance3D and child.material_override is StandardMaterial3D:
			child.material_override = child.material_override.duplicate()
			child.material_override.albedo_color = Color("706b60")
func set_obscured(value: bool) -> void:
	if not interior_record.is_empty() and preload("res://scripts/city_map.gd").interior_cutaway: value=false
	obscured=value
	if fader==null:
		fader=preload("res://scripts/three_d/material_fader.gd").new(); fader.configure(self,fade_settings)
	fader.set_obscured(value)

func reset_fade() -> void:
	if fader!=null: fader.reset()
	obscured=false

func set_detail_enabled(value: bool) -> void:
	detail_enabled=value
	for child in get_children():
		if child is MultiMeshInstance3D or child.name in ["Weathering","StreetFacade"]: child.visible=value

func _accessible_interior(size: Vector2, color: Color) -> void:
	var wall_height:=3.2
	var gap:=1.6
	Geometry.box(self,Vector3(size.x,.12,size.y),Vector3(0,.02,0),Color("c8bd9e"))
	var normal: Vector2=interior_record.door_normal
	for side in [Vector2.RIGHT,Vector2.LEFT,Vector2.DOWN,Vector2.UP]:
		var edge_length: float=size.y if side.x else size.x
		var extent: float=(size.x if side.x else size.y)*.5
		if side==normal:
			var piece: float=(edge_length-gap)*.5
			for sign_value in [-1,1]:
				var offset: Vector2=side*extent+side.orthogonal()*sign_value*(edge_length+gap)*.25
				var dimensions:=Vector3(.18,wall_height,piece) if side.x else Vector3(piece,wall_height,.18)
				Geometry.box(self,dimensions,Vector3(offset.x,wall_height*.5,offset.y),color)
				_collider(dimensions,Vector3(offset.x,wall_height*.5,offset.y))
		else:
			var dimensions:=Vector3(.18,wall_height,edge_length) if side.x else Vector3(edge_length,wall_height,.18)
			Geometry.box(self,dimensions,Vector3(side.x*extent,wall_height*.5,side.y*extent),color)
			_collider(dimensions,Vector3(side.x*extent,wall_height*.5,side.y*extent))
	var door_point: Vector2=normal*(size.x if normal.x else size.y)*.5
	var door_size:=Vector3(.16,2.2,gap) if normal.x else Vector3(gap,2.2,.16)
	interior_door=Geometry.box(self,door_size,Vector3(door_point.x,1.1,door_point.y),Color("557d7b"))
	interior_door_body=_collider(door_size,interior_door.position)
	var ceiling:=Geometry.box(self,Vector3(size.x+.2,.18,size.y+.2),Vector3(0,wall_height,0),Color("67716a"))
	interior_upper.append(ceiling)
	if height>3.5:
		var upper:=Geometry.box(self,Vector3(size.x,height-wall_height,size.y),Vector3(0,(height+wall_height)*.5,0),color)
		upper.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		interior_upper.append(upper)
		_collider(Vector3(size.x,height-wall_height,size.y),upper.position)
	# Flat activity zones add room identity while leaving navigation unobstructed.
	var zone_color: Color=Color("b2c4bb") if interior_record.kind in ["Home","Apartment"] else Color("b7c3db")
	Geometry.box(self,Vector3(minf(4,size.x*.5),.025,minf(3,size.y*.4)),Vector3(0,.1,0),zone_color)
	if interior_record.kind=="School":
		for row in range(3): Geometry.box(self,Vector3(minf(5,size.x*.55),.025,.7),Vector3(0,.12,(row-1)*1.4),Color("94adbd"))
	elif interior_record.kind=="Medical Station":
		Geometry.box(self,Vector3(2,.025,.6),Vector3(0,.13,0),Color("b76a65"))
		Geometry.box(self,Vector3(.6,.025,2),Vector3(0,.14,0),Color("b76a65"))
	# Wall-side storage leaves the reserved interior walking grid clear.
	var storage_size:=Vector3(.35,1.0,maxf(.5,size.y*.35)) if normal.x else Vector3(maxf(.5,size.x*.35),1.0,.35)
	var storage_position:=Vector3(-normal.x*(size.x*.5-.3),.5,-normal.y*(size.y*.5-.3))
	Geometry.box(self,storage_size,storage_position,Color("8c7a5f"))
	interior_label=Geometry.label(self,interior_record.kind+" / "+interior_record.id,Vector3(0,3.5,0),Color("e4d5a6"),24,.03)

func _process(_delta: float) -> void:
	if interior_record.is_empty() or destruction_state!="INTACT": return
	var map=preload("res://scripts/city_map.gd")
	var weathering := get_node_or_null("Weathering")
	if weathering != null: weathering.visible = detail_enabled and not map.interior_cutaway
	if imported_visual!=null: imported_visual.visible=not map.interior_cutaway
	for object in interior_upper: object.visible=not map.interior_cutaway and (detail_enabled or object.name!="StreetFacade")
	for object in interior_art: object.visible=map.interior_cutaway and not object in interior_upper
	interior_label.visible=map.interior_cutaway
	# Door timers use simulation time, stored by the authoritative transitions.
	var is_open: bool=bool(interior_record.get("door_is_open",false))
	interior_door.visible=map.interior_cutaway and not is_open
	if interior_door_body!=null: interior_door_body.collision_layer=0 if is_open else 1

# Batched Italian-style street walls: limestone bands, tall framed windows,
# cornices, ground-floor shops and small iron balconies. No imported texture costs.
func _detail_batch(parent: Node3D, transforms: Array[Transform3D], color: Color) -> void:
	if transforms.is_empty(): return
	var node:=MultiMeshInstance3D.new()
	var batch:=MultiMesh.new(); batch.transform_format=MultiMesh.TRANSFORM_3D
	var box:=BoxMesh.new(); box.size=Vector3.ONE; batch.mesh=box
	batch.instance_count=transforms.size()
	for i in range(transforms.size()): batch.set_instance_transform(i,transforms[i])
	node.multimesh=batch; node.material_override=Geometry.material(color); node.visibility_range_end=float(fade_settings.detail_distance)
	parent.add_child(node)

func _street_facade(size: Vector2, roof_height: float, color: Color) -> Node3D:
	var details:=Node3D.new(); details.name="StreetFacade"; add_child(details)
	var stone:=Color("89816c").lerp(color,.3)
	var floors: int=maxi(1,int(floor(roof_height/3.3)))
	var frames: Array[Transform3D]=[]; var glass: Array[Transform3D]=[]; var iron: Array[Transform3D]=[]
	for floor_index in range(1,floors+1):
		var band_height:=.28 if floor_index==floors else .13
		frames.append(Transform3D(Basis.from_scale(Vector3(size.x+.38,band_height,size.y+.38)),Vector3(0,floor_index*3.3-.10,0)))
	frames.append(Transform3D(Basis.from_scale(Vector3(size.x+.5,.35,size.y+.5)),Vector3(0,roof_height+.15,0)))
	for side in range(4):
		var basis:=Basis(Vector3.UP,side*PI*.5)
		var frontage: float=size.x if side%2==0 else size.y
		var depth: float=(size.y if side%2==0 else size.x)*.5
		var columns: int=maxi(2,int(frontage/3.1))
		var spacing: float=(frontage-2)/columns
		for floor_index in range(floors):
			for column in range(columns):
				var x: float=(column-(columns-1)*.5)*spacing
				# Keep a generous central ground-floor entrance on each frontage.
				if floor_index==0 and absf(x)<1.5: continue
				var y: float=1.8+floor_index*3.3
				var width:=1.35 if floor_index>0 else 1.65
				frames.append(Transform3D((basis*Basis.from_scale(Vector3(width+.28,2.0,.13))),basis*Vector3(x,y,depth+.06)))
				var pane := Transform3D((basis*Basis.from_scale(Vector3(width,1.72,.08))),basis*Vector3(x,y,depth+.15))
				glass.append(pane)
				frames.append(Transform3D((basis*Basis.from_scale(Vector3(width+.45,.13,.30))),basis*Vector3(x,y-1.02,depth+.11)))
				if floor_index in [1,2] and column%3==1:
					# Balconies project less than the 5-unit envelope reserve.
					frames.append(Transform3D((basis*Basis.from_scale(Vector3(width+.5,.12,.48))),basis*Vector3(x,y-.95,depth+.20)))
					iron.append(Transform3D((basis*Basis.from_scale(Vector3(width+.4,.07,.07))),basis*Vector3(x,y-.2,depth+.40)))
					for bar in range(6):
						iron.append(Transform3D((basis*Basis.from_scale(Vector3(.045,.75,.045))),basis*Vector3(x+(bar-2.5)*width/5,y-.57,depth+.40)))
		# Tall stone pilasters and a shop lintel reference the supplied street photograph.
		for x in [-frontage*.5+.35,frontage*.5-.35]:
			frames.append(Transform3D((basis*Basis.from_scale(Vector3(.38,roof_height-.5,.22))),basis*Vector3(x,roof_height*.5,depth+.1)))
		frames.append(Transform3D((basis*Basis.from_scale(Vector3(frontage-.5,.45,.2))),basis*Vector3(0,3.05,depth+.1)))
	_detail_batch(details,frames,stone)
	_detail_batch(details,glass,Color("415b64"))
	_detail_batch(details,iron,Color("454b48"))
	return details
