extends Node3D
## World records persist; this bounded working set contains presentation only.
const Map=preload("res://scripts/city_map.gd")
const C=preload("res://scripts/three_d/world_coordinates.gd")
const G=preload("res://scripts/three_d/geometry.gd")
const ModelCatalog=preload("res://scripts/three_d/runtime_model_catalog.gd")
var config: Dictionary=preload("res://scripts/three_d/render_options.gd").load_options()
var city: Node3D
var camera: Camera3D
var chunks: Dictionary={}
var building_nodes: Dictionary={}
var queue: Array[Vector2i]=[]
var pool: Array[Vector2i]=[]
var damage_records: Array=[]
var damage_config: Dictionary={}
var age:=0.0
var load_ms:=0.0
var unload_ms:=0.0
var loads:=0
var unloads:=0
var reused:=0
var overview: Node3D
var proxy_instances: Dictionary={}
var visible_bounds:=Rect2()
var near_bounds:=Rect2()

func _ready() -> void:
	name="VisualChunks"
	config.chunk_size=Map.tile_grid.chunk_world_size() if Map.tile_grid!=null and not Map.tile_grid.chunks.is_empty() else maxf(120,roundf(float(config.chunk_size)/120)*120)
	for x in range(ceili(Map.MAP_SIZE.x/config.chunk_size)):
		for y in range(ceili(Map.MAP_SIZE.y/config.chunk_size)): _descriptor(Vector2i(x,y))
	for cell in city.get_node("ValleyEnvironment").road_chunks: _descriptor(cell)
	for i in range(Map.lots.size()):
		var cell: Vector2i=Map.tile_grid.owner_chunk("building:%d"%i,Map.lots[i].get_center()) if Map.tile_grid!=null else Vector2i((Map.lots[i].get_center()/float(config.chunk_size)).floor())
		_descriptor(cell).buildings.append(i)
		_descriptor(cell).height=maxf(float(_descriptor(cell).get("height",8)),float(Map.building_data[i].get("height_m",5.2)))
	for tree in city.landscape_trees: _descriptor(Vector2i((Map._v2(tree.position)/float(config.chunk_size)).floor())).trees.append(tree)
	for prop in Map.prop_data: _descriptor(Vector2i((Map._v2(prop.position)/float(config.chunk_size)).floor())).props.append(prop)
	_build_overview()

func _descriptor(cell: Vector2i) -> Dictionary:
	if not chunks.has(cell): chunks[cell]={"bounds":Rect2(Vector2(cell)*float(config.chunk_size),Vector2.ONE*float(config.chunk_size)),"state":"UNLOADED","visible":false,"near":false,"node":null,"buildings":[],"trees":[],"props":[],"cursor":0,"stage":0}
	return chunks[cell]

static func camera_bounds(view: Camera3D) -> Rect2:
	var screen:=view.get_viewport().get_visible_rect()
	var bounds:=Rect2(); var first:=true
	for pixel in [screen.position,Vector2(screen.end.x,screen.position.y),screen.end,Vector2(screen.position.x,screen.end.y)]:
		var origin:=view.project_ray_origin(pixel); var direction:=view.project_ray_normal(pixel)
		var point: Variant=Plane(Vector3.UP,0).intersects_ray(origin,direction)
		if point==null: continue
		var xy:=Vector2(point.x,point.z)*10
		if first: bounds=Rect2(xy,Vector2.ZERO); first=false
		else: bounds=bounds.expand(xy)
	return bounds.grow(300) # Roof/terrain height projected along the camera ray.

func configure(value: Camera3D) -> void:
	camera=value; refresh()

func refresh() -> void:
	if not is_instance_valid(camera): return
	preload("res://scripts/three_d/building_sprites.gd").set_camera(camera)
	visible_bounds=camera_bounds(camera)
	near_bounds=visible_bounds.grow(float(config.preload_distance))
	var detailed: bool=camera.size<=float(config.detail_view_size)
	overview.visible=true
	overview.get_child(0).position.y=-5.0 if detailed else -1.0
	overview.get_child(2).visible=not detailed
	overview.get_child(2).position.y=-.5 if detailed else 0.0
	var keep:=visible_bounds.grow(float(config.unload_distance))
	for cell in chunks:
		var chunk: Dictionary=chunks[cell]
		chunk.visible=detailed and chunk.bounds.intersects(visible_bounds)
		chunk.visible=detailed and _in_view(chunk,0)
		chunk.near=detailed and _in_view(chunk,float(config.preload_distance))
		if (chunk.near or not config.enabled) and chunk.state in ["UNLOADED","POOLED"]:
			if chunk.state=="POOLED":
				pool.erase(cell); chunk.node.show(); chunk.node.process_mode=Node.PROCESS_MODE_INHERIT; chunk.state="ACTIVE"; reused+=1; _register(chunk)
			else: chunk.state="QUEUED"; queue.append(cell)
		elif chunk.state in ["ACTIVE","LOADING","QUEUED"] and (not detailed or not _in_view(chunk,float(config.unload_distance))) and config.enabled: _unload(cell)
	queue.sort_custom(func(a,b):return chunks[a].bounds.get_center().distance_squared_to(visible_bounds.get_center())<chunks[b].bounds.get_center().distance_squared_to(visible_bounds.get_center()))
	for building in building_nodes.values(): building.set_detail_enabled(camera.size<=float(config.facade_view_size))

func _in_view(chunk: Dictionary, margin: float) -> bool:
	var bounds: Rect2=chunk.bounds; var projected:=Rect2(); var first:=true; var front:=false
	for xy in [bounds.position,bounds.end,Vector2(bounds.end.x,bounds.position.y),Vector2(bounds.position.x,bounds.end.y)]:
		for height in [0.0,float(chunk.get("height",8.0))]:
			var point:=C.to_world(xy,height); front=front or not camera.is_position_behind(point)
			var pixel:=camera.unproject_position(point)
			if first: projected=Rect2(pixel,Vector2.ZERO); first=false
			else: projected=projected.expand(pixel)
	var screen:=camera.get_viewport().get_visible_rect()
	return front and projected.intersects(screen.grow(margin*.1/maxf(1,camera.size)*screen.size.y))

func wants_point(point: Vector2) -> bool:
	if not is_instance_valid(camera): return false
	if not config.enabled: return true
	var target:=C.to_world(point,1.2); var screen:=camera.get_viewport().get_visible_rect()
	return camera.size<=float(config.detail_view_size) and not camera.is_position_behind(target) and screen.grow(float(config.preload_distance)*.1/maxf(1,camera.size)*screen.size.y).has_point(camera.unproject_position(target))

func _process(delta: float) -> void:
	age+=delta
	if age>=float(config.update_interval): age=0; refresh()
	var started:=Time.get_ticks_usec(); var built:=0
	while not queue.is_empty() and float(Time.get_ticks_usec()-started)/1000<float(config.frame_budget_ms):
		var cell: Vector2i=queue[0]; var chunk: Dictionary=chunks[cell]
		if chunk.state=="QUEUED":
			chunk.node=Node3D.new(); chunk.node.name="Chunk_%d_%d"%[cell.x,cell.y]; add_child(chunk.node)
			chunk.state="LOADING"; chunk.cursor=0; chunk.stage=0; loads+=1
		if chunk.stage==0:
			chunk.node.add_child(_terrain(chunk.bounds)); chunk.node.add_child(city.get_node("ValleyEnvironment").make_chunk(cell)); chunk.stage=1
		elif chunk.cursor<chunk.buildings.size():
			if built>=int(config.buildings_per_frame): break
			var index: int=chunk.buildings[chunk.cursor]
			var building=preload("res://scenes/three_d/building.tscn").instantiate(); building.visual_only=true
			building.configure(Map.lots[index],index)
			for poi in Map.pois:
				if poi.footprint==Map.lots[index]: building.add_poi(poi.kind)
			chunk.node.add_child(building); city.buildings.append(building); building_nodes[index]=building
			building.set_detail_enabled(camera.size<=float(config.facade_view_size))
			_set_proxy(index,false)
			_restore_damage(building,index); chunk.cursor+=1; built+=1
		else:
			_foliage(chunk); _props(chunk)
			var details=preload("res://scripts/three_d/city_details.gd").new(); details.visual_bounds=chunk.bounds; details.streamed=true; chunk.node.add_child(details)
			chunk.state="ACTIVE"; queue.pop_front()
			_damage_batches(chunk.node)
	load_ms=maxf(load_ms,float(Time.get_ticks_usec()-started)/1000)

func _register(chunk: Dictionary) -> void:
	_damage_batches(chunk.node)
	for child in chunk.node.get_children():
		if child.has_meta("building_index"):
			var index: int=child.get_meta("building_index"); city.buildings.append(child); building_nodes[index]=child; _restore_damage(child,index)
			_set_proxy(index,false)

func _restore_damage(building: Node3D,index: int) -> void:
	if index>=damage_records.size() or damage_records[index].destruction_state=="INTACT": return
	building.destroy_to(damage_records[index].destruction_state,0)
	if is_instance_valid(building.collapse_tween): building.collapse_tween.kill()
	building.scale.y=.08 if building.destruction_state=="DESTROYED" else .55; building.rotation.z=.12

func _unload(cell: Vector2i) -> void:
	var begin:=Time.get_ticks_usec(); var chunk: Dictionary=chunks[cell]
	queue.erase(cell)
	if is_instance_valid(chunk.node):
		for index in chunk.buildings:
			if building_nodes.has(index):
				var building: Node3D=building_nodes[index]; building.reset_fade(); city.buildings.erase(building); building_nodes.erase(index)
				_set_proxy(index,true)
		chunk.node.hide(); chunk.node.process_mode=Node.PROCESS_MODE_DISABLED
		if chunk.state=="ACTIVE" and int(config.pooled_chunks)>0: chunk.state="POOLED"; pool.append(cell)
		else: chunk.node.queue_free(); chunk.node=null; chunk.state="UNLOADED"
	else: chunk.state="UNLOADED"
	unloads+=1
	while pool.size()>int(config.pooled_chunks):
		var old: Dictionary=chunks[pool.pop_front()]; old.node.queue_free(); old.node=null; old.state="UNLOADED"
	unload_ms=maxf(unload_ms,float(Time.get_ticks_usec()-begin)/1000)

func _terrain(bounds: Rect2, step_override: float = 0) -> MeshInstance3D:
	var step: float=Map.terrain_cell if step_override==0 else step_override
	var surface:=SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var end: Vector2=bounds.end.min(Map.MAP_SIZE); var start: Vector2=bounds.position.max(Vector2.ZERO)
	for x in range(int(start.x/step),ceili(end.x/step)):
		for y in range(int(start.y/step),ceili(end.y/step)):
			var a: Vector2=(Vector2(x,y)*step).max(start); var c: Vector2=((Vector2(x,y)+Vector2.ONE)*step).min(end)
			for point in [a,c,Vector2(a.x,c.y),a,Vector2(c.x,a.y),c]:
				surface.set_color(city._terrain_color(point)); surface.add_vertex(C.to_world(point,-.02 if step_override==0 else -.1))
	var node:=MeshInstance3D.new()
	if end.x<=start.x or end.y<=start.y: return node
	surface.generate_normals(); node.mesh=surface.commit(); node.material_override=preload("res://scripts/three_d/grass_material.gd").material()
	return node

func apply_damage(records: Array,options: Dictionary) -> void:
	damage_records=records; damage_config=options.duplicate(true)
	for index in range(Map.lots.size()): _set_proxy(index,not building_nodes.has(index))
	for chunk in chunks.values():
		if is_instance_valid(chunk.node): _damage_batches(chunk.node)

func _damage_batches(root: Node3D) -> void:
	if damage_config.is_empty(): return
	var blast=preload("res://scripts/blast_model.gd")
	for child in root.find_children("*","MultiMeshInstance3D",true,false):
		var batch:=child as MultiMeshInstance3D
		if batch==null: continue
		for i in range(batch.multimesh.instance_count):
			var transform: Transform3D=batch.multimesh.get_instance_transform(i)
			if blast.intensity(C.to_simulation(transform.origin),damage_config)>0:
				transform.basis=Basis().scaled(Vector3.ZERO); batch.multimesh.set_instance_transform(i,transform)

func _foliage(chunk: Dictionary) -> void:
	var art=preload("res://scripts/three_d/reference_sprite_catalog.gd")
	art.load_collection()
	var groups: Dictionary={}
	for tree in chunk.trees:
		var point:=Map._v2(tree.position)
		var variant:=posmod(roundi(point.x*.1+point.y*.173),8)
		if not groups.has(variant): groups[variant]=[]
		groups[variant].append(tree)
	for variant in groups:
		var kind: String="new_tree%d"%variant; var region: Rect2=art.REGIONS[kind]
		var multi:=MultiMesh.new(); multi.transform_format=MultiMesh.TRANSFORM_3D
		var quad:=QuadMesh.new(); quad.size=Vector2.ONE; quad.center_offset=Vector3(0,.5,0); multi.mesh=quad; multi.instance_count=groups[variant].size()
		for i in range(groups[variant].size()):
			var tree: Dictionary=groups[variant][i]; var h: float=[9.0,8.0,5.5,8.0,6.0,6.0,5.5,4.5][variant]*float(tree.scale)
			var w: float=h*region.size.x/region.size.y
			multi.set_instance_transform(i,Transform3D(Basis.from_scale(Vector3(w,h,1)),C.to_world(Map._v2(tree.position))))
		var node:=MultiMeshInstance3D.new(); node.name="TreeArtwork_%d"%variant; node.multimesh=multi; node.material_override=art.material(kind); node.extra_cull_margin=15; node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; chunk.node.add_child(node)

func _props(chunk: Dictionary) -> void:
	var multi:=MultiMesh.new(); multi.transform_format=MultiMesh.TRANSFORM_3D
	var mesh:=BoxMesh.new(); mesh.size=Vector3(.8,.55,.8); multi.mesh=mesh; multi.instance_count=chunk.props.size()
	for i in range(chunk.props.size()):
		var prop: Dictionary=chunk.props[i]; multi.set_instance_transform(i,Transform3D(Basis(Vector3.UP,float(prop.rotation)),C.to_world(Map._v2(prop.position))+Vector3.UP*.275))
	var node:=MultiMeshInstance3D.new(); node.multimesh=multi; node.material_override=G.material(Color("8e8067")); chunk.node.add_child(node)

func _set_proxy(index: int, enabled: bool) -> void:
	if not proxy_instances.has(index): return
	var proxy: Dictionary=proxy_instances[index]
	var transform: Transform3D=proxy.transform
	if index<damage_records.size() and damage_records[index].destruction_state!="INTACT":
		var height_scale:=.08 if damage_records[index].destruction_state=="DESTROYED" else .55
		transform.basis=transform.basis*Basis.from_scale(Vector3(1,height_scale,1))
	if not enabled: transform.basis=Basis().scaled(Vector3.ZERO)
	(proxy.batch as MultiMeshInstance3D).multimesh.set_instance_transform(int(proxy.slot),transform)

func _overview_buildings() -> Node3D:
	var group:=Node3D.new(); group.name="BuildingOverviewLOD"; proxy_instances.clear()
	var art=preload("res://scripts/three_d/building_sprites.gd")
	var groups: Dictionary={}
	for index in range(Map.lots.size()):
		var recipe: Dictionary=preload("res://scripts/three_d/building_shape.gd").plan(index)
		var item: Dictionary=art.info(recipe,index); item.index=index
		if not groups.has(item.key): groups[item.key]=[]
		groups[item.key].append(item)
	for key in groups:
		var multi:=MultiMesh.new(); multi.transform_format=MultiMesh.TRANSFORM_3D
		var mesh:=QuadMesh.new(); mesh.size=Vector2.ONE
		multi.mesh=mesh; multi.instance_count=groups[key].size()
		var batch:=MultiMeshInstance3D.new(); batch.name="SpriteOverview"; batch.multimesh=multi; batch.material_override=art.material(key); batch.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		group.add_child(batch)
		for slot in range(groups[key].size()):
			var item: Dictionary=groups[key][slot]; var index: int=item.index
			var transform:=Transform3D(Basis.from_scale(Vector3(item.width,item.height,1)),C.to_world(Map.lots[index].get_center())+Vector3(item.offset.x,item.anchor,item.offset.y))
			multi.set_instance_transform(slot,transform); proxy_instances[index]={"batch":batch,"slot":slot,"transform":transform}
	return group

func _build_overview() -> void:
	overview=Node3D.new(); overview.name="WorldOverviewLOD"; add_child(overview)
	overview.add_child(_terrain(Rect2(Vector2.ZERO,Map.MAP_SIZE),Map.terrain_cell))
	overview.add_child(_overview_buildings())
	var road_layer:=Node3D.new(); road_layer.name="ConnectedRoadOverview"
	var valley: Node=city.get_node("ValleyEnvironment")
	var records:=[]
	for part in valley.art_chunks.values(): records.append_array(part)
	valley._make_art_mesh(road_layer,records)
	var roads:=SurfaceTool.new(); roads.begin(Mesh.PRIMITIVE_TRIANGLES)
	for edge in Map.roads:
		if not edge.get("elevated",false) and not edge.get("ramp",false): continue
		# Follow terrain at short intervals, including long straight block edges.
		var samples:=PackedVector2Array([edge.points[0]])
		for segment in range(1,edge.points.size()):
			var start: Vector2=edge.points[segment-1]
			var finish: Vector2=edge.points[segment]
			var steps:=maxi(1,ceili(start.distance_to(finish)/20.0))
			for step in range(1,steps+1): samples.append(start.lerp(finish,float(step)/steps))
		for i in range(1,samples.size()):
			var a: Vector2=samples[i-1]; var b: Vector2=samples[i]
			if not Rect2(Vector2.ZERO,Map.MAP_SIZE).has_point((a+b)*.5): continue
			var right: Vector2=(b-a).orthogonal().normalized()*float(edge.width)*.5
			var first_height: float=10 if edge.get("elevated",false) else 10*(1-float(i-1)/(samples.size()-1)) if edge.get("ramp",false) else 0
			var last_height: float=10 if edge.get("elevated",false) else 10*(1-float(i)/(samples.size()-1)) if edge.get("ramp",false) else 0
			var aa:=C.to_world(a-right,first_height+.3); var ab:=C.to_world(a+right,first_height+.3)
			var ba:=C.to_world(b-right,last_height+.3); var bb:=C.to_world(b+right,last_height+.3)
			for point in [aa,bb,ab,aa,ba,bb]: roads.add_vertex(point)
	roads.generate_normals()
	var lines:=MeshInstance3D.new(); lines.mesh=roads.commit(); lines.material_override=preload("res://scripts/three_d/road_ground_art.gd").plain_asphalt_material(); road_layer.add_child(lines); overview.add_child(road_layer)
	var water:=G.cylinder(overview,Map.lake.size.x*.05,.03,Vector3(Map.lake.get_center().x*.1,-.28,Map.lake.get_center().y*.1),Color("508a93"))
	water.scale.z=Map.lake.size.y/Map.lake.size.x

func metrics() -> Dictionary:
	return {"loaded_chunks":chunks.values().filter(func(chunk):return chunk.state in ["ACTIVE","LOADING"]).size(),"pending_chunks":queue.size(),"pooled_chunks":pool.size(),"active_buildings":building_nodes.size(),"loads":loads,"unloads":unloads,"pool_reuses":reused,"max_load_frame_ms":load_ms,"max_unload_ms":unload_ms}
