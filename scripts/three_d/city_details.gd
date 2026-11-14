extends Node3D
## Original neighbourhood props and an optional district overlay; no simulation.
const Map=preload("res://scripts/city_map.gd")
const C=preload("res://scripts/three_d/world_coordinates.gd")
const G=preload("res://scripts/three_d/geometry.gd")
static var signal_placements: Array=[]
static var light_placements: Array=[]
var visual_bounds:=Rect2()
var streamed:=false
var overlay_only:=false
var district_layer: Node3D
var bay_markers: Array=[]
var signals: Array=[]
var update_age:=0.0
const Art=preload("res://scripts/three_d/reference_sprite_catalog.gd")
const Traffic=preload("res://scripts/traffic_rules.gd")

func _ready() -> void:
	name="CityDetails"
	_build_districts()
	if overlay_only: return
	for item in Map.prop_data:
		if streamed or not _inside(Map._v2(item.position)): continue
		var p:=C.to_world(Map._v2(item.position))
		var prop:=G.box(self,Vector3(.8,.55,.8),p+Vector3.UP*.275,Color("8e8067") if item.variant=="crate" else Color("686e66"))
		prop.rotation.y=float(item.rotation)
		G.collider(self,Vector3(.8,.55,.8),p+Vector3.UP*.275,64)
	for item in Map.infrastructure_data:
		if not _inside(Map._v2(item.position)): continue
		if item.kind!="metro_entrance": continue
		var p:=C.to_world(Map._v2(item.position))
		G.box(self,Vector3(3,.15,3),p+Vector3.UP*.08,Color("646e68"))
		G.label(self,"METRO / S2",p+Vector3.UP*2.4,Color("c7c6ad"),35,.025)
	for lot in Map.parking_lots:
		if lot.get("integrated_station",false): continue
		if not _inside(lot.position): continue
		var sign_position: Vector3=C.to_world(lot.position+lot.tangent*120)
		G.box(self,Vector3(.12,2.6,.12),sign_position+Vector3.UP*1.3,Color("687576"))
		G.box(self,Vector3(1.3,1.1,.12),sign_position+Vector3.UP*2.7,Color("3d747e"))
		G.label(self,"P",sign_position+Vector3(0,2.7,.09),Color("f0ecda"),40,.025)
		for bay in lot.bays:
			var marker:=G.cylinder(self,.20,.08,C.to_world(bay.position,.20),Color("70a575"))
			marker.material_override=G.material(Color("70a575"))
			bay_markers.append({"bay":bay,"node":marker})
	if _inside(Map.grove.entrance):
		var entrance_sign: Vector2=Map.roadside_position(Map.grove.entrance,40)
		if not entrance_sign.is_finite(): entrance_sign=Map.grove.gathering
		var point: Vector3=C.to_world(entrance_sign)
		G.box(self,Vector3(.12,3.0,.12),point+Vector3(0,1.5,0),Color("747d71"))
		G.box(self,Vector3(7,.9,.16),point+Vector3(0,3,0),Color("3f7561"))
		G.label(self,"ALDER COURT",point+Vector3(0,3,.11),Color("eeecd6"),35,.024)
	if _inside(Map.grove.gathering):
		var gathering: Vector3=C.to_world(Map.grove.gathering)
		G.cylinder(self,7,.2,gathering+Vector3.UP*.15,Color("b6a384"))
		G.cylinder(self,1.2,.65,gathering+Vector3.UP*.5,Color("b4a487"))
		for side in [-1,1]:
			Art.sprite(self,"bench",3,gathering+Vector3(side*3,0,1))
	for i in range(Map.building_data.size()):
		var building: Dictionary=Map.building_data[i]
		if building.district!="GROVE" or not _inside(Map.lots[i].get_center()): continue
		var yard: Rect2=Map._rect(building.yard)
		# Side/rear fence artwork leaves the frontage and driveway open.
		for side in [-1,1]:
			var fence_point:=Vector2(yard.position.x if side<0 else yard.end.x,yard.get_center().y)
			if Map.clear_point(fence_point,4) and Map.roadway_clear(fence_point,4):
				Art.sprite(self,["wood_fence","iron_fence","hedge","brick_wall"][i%4],minf(yard.size.y*.075,6),C.to_world(fence_point))
	_build_property_fences()
	_build_streetscape()
	_build_signals()
	_build_regulatory_signs()
	_street_lights()
	for point in light_placements:
		if not _inside(point): continue
		var offset: Vector2=point+Vector2(12,12)
		if Map.clear_point(offset,4) and Map.roadway_clear(offset,4): Art.sprite(self,"hydrant",.65,C.to_world(offset))
		var sign_point: Vector2=point-Vector2(12,12)
		if Map.clear_point(sign_point,4) and Map.roadway_clear(sign_point,4): Art.sprite(self,"street_sign",1.7,C.to_world(sign_point))

func _inside(point: Vector2) -> bool: return visual_bounds.size==Vector2.ZERO or visual_bounds.has_point(point)

func _plan_lights() -> void:
	# Seeded street furniture is placed beside actual junctions.
	var rng:=RandomNumberGenerator.new(); rng.seed=Map.map_seed+610161
	for id in Map.graph.get_point_ids():
		var p: Vector2=Map.graph.get_point_position(id)
		if id%9!=0 or not Rect2(Vector2.ZERO,Map.MAP_SIZE).has_point(p): continue
		var placement: Vector2=Map.roadside_position(p+Vector2(120,120),14)
		if not placement.is_finite(): continue
		light_placements.append(placement)

func _street_lights(physics_root: Node3D = null) -> void:
	if light_placements.is_empty(): _plan_lights()
	for placement in light_placements:
		var base:=C.to_world(placement)
		if physics_root!=null:
			G.collider(physics_root,Vector3(.18,5,.18),base+Vector3.UP*2.5,64); continue
		if not _inside(placement): continue
		Art.sprite(self,"lamp",2.3,base)
		if not streamed: G.collider(self,Vector3(.18,5,.18),base+Vector3.UP*2.5,64)


func _build_districts() -> void:
	district_layer=Node3D.new(); district_layer.name="DistrictOverlay"; add_child(district_layer)
	if visual_bounds.size!=Vector2.ZERO: return
	for district in Map.districts:
		var surface:=SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for triangle in district.triangles:
			for p in triangle: surface.add_vertex(C.to_world(Map._v2(p),.45))
		var node:=MeshInstance3D.new(); node.mesh=surface.commit()
		var color:=Color(district.color); color.a=.22
		node.material_override=G.material(color,true)
		node.material_override.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		node.material_override.no_depth_test=true
		node.material_override.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		district_layer.add_child(node)
		var label:=G.label(district_layer,district.name.replace("_"," "),C.to_world(district.center,18),Color.WHITE,42,.2)
		label.no_depth_test=true

func _process(_delta: float) -> void:
	update_age+=_delta
	if update_age<.1: return
	update_age=0.0
	for record in signals:
		var state: String=Traffic.light(record.signal_record,record.tangent,Map.traffic_time,Map.signal_settings)
		if record.get("state","")==state: continue
		record.state=state
		for color_name in record.lamps:
			var material: StandardMaterial3D=record.lamps[color_name].material_override
			material.albedo_color=record.colors[color_name] if color_name==state else record.colors[color_name].darkened(.8)
			material.emission_enabled=color_name==state
			material.emission=record.colors[color_name]
	district_layer.visible=Map.generation_settings.get("show_districts",false)
	var debug: bool=Map.generation_settings.get("show_parking",false)
	for record in bay_markers:
		record.node.visible=debug
		var color: Color=Color("c4785c") if not record.bay.occupied_by.is_empty() else Color("70a575")
		if not record.node.material_override.albedo_color.is_equal_approx(color): record.node.material_override.albedo_color=color

func _plan_signals() -> void:
	var used: Array[Vector2]=[]
	for id in Map.traffic_signals:
		var signal_record: Dictionary=Map.traffic_signals[id]
		for approach in signal_record.approaches:
			var tangent: Vector2=approach.tangent
			var point:=Vector2.INF
			for setback in [112.0,135.0,160.0]:
				for side in [1.0]:
					var anchor: Vector2=signal_record.position-tangent*(float(approach.width)*.5+setback)
					var candidate: Vector2=anchor+preload("res://scripts/traffic_conventions.gd").right(tangent)*side*(float(approach.width)*.5+14)
					if not Map.roadway_clear(candidate,7) or not Map.clear_point(candidate,7): continue
					if used.any(func(other):return candidate.distance_to(other)<18): continue
					if Map.parking_lots.any(func(lot):return lot.bounds.grow(7).has_point(candidate)): continue
					point=candidate; break
				if point.is_finite(): break
			if not point.is_finite(): continue
			used.append(point)
			signal_placements.append({"point":point,"tangent":tangent,"signal_record":signal_record,"id":id})

func _build_signals(physics_root: Node3D = null) -> void:
	if signal_placements.is_empty(): _plan_signals()
	for placement in signal_placements:
		var point: Vector2=placement.point; var tangent: Vector2=placement.tangent
		var signal_record: Dictionary=placement.signal_record; var id: Variant=placement.id
		if physics_root!=null:
			G.collider(physics_root,Vector3(.18,3.4,.18),C.to_world(point)+Vector3.UP*1.7,64); continue
		if not _inside(point): continue
		var pole:=Node3D.new(); pole.name="Signal_%s"%id; pole.position=C.to_world(point)
		pole.rotation.y=preload("res://scripts/traffic_conventions.gd").signal_yaw(tangent); add_child(pole)
		G.box(pole,Vector3(.14,3.4,.14),Vector3(0,1.7,0),Color("4a5551"))
		if not streamed: G.collider(pole,Vector3(.18,3.4,.18),Vector3(0,1.7,0),64)
		G.box(pole,Vector3(.48,1.3,.28),Vector3(0,3.2,0),Color("303938"))
		var colors: Dictionary={"RED":Color("ee4e40"),"AMBER":Color("f4bb44"),"GREEN":Color("64dc84")}
		var lamps: Dictionary={}; var index:=0
		for key in ["RED","AMBER","GREEN"]:
			lamps[key]=G.box(pole,Vector3(.29,.29,.08),Vector3(0,3.61-index*.4,.18),colors[key]); index+=1
			lamps[key].material_override=G.material(colors[key])
		signals.append({"signal_record":signal_record,"tangent":tangent,"lamps":lamps,"colors":colors,"position":point,"junction":id})

func _build_regulatory_signs() -> void:
	for edge in Map.roads:
		var points: PackedVector2Array=edge.points
		for forward in [true,false]:
			var allowed: bool=preload("res://scripts/traffic_conventions.gd").permitted(edge,forward)
			var control: String=str(edge.get("junction_control",""))
			if allowed and control not in ["stop","yield"]: continue
			var tangent: Vector2=(points[-1]-points[-2]).normalized() if forward else (points[0]-points[1]).normalized()
			var end: Vector2=points[-1] if forward else points[0]
			var point: Vector2=end-tangent*(float(edge.width)*.5+115)+preload("res://scripts/traffic_conventions.gd").right(tangent)*(float(edge.width)*.5+14)
			if not Map.clear_point(point,5): continue
			if not _inside(point): continue
			if allowed:
				Art.sprite(self,"stop" if control=="stop" else "yield",1.3,C.to_world(point)); continue
			var pole:=Node3D.new(); pole.name="RoadRestriction"; pole.position=C.to_world(point)
			pole.rotation.y=preload("res://scripts/traffic_conventions.gd").signal_yaw(tangent); add_child(pole)
			G.box(pole,Vector3(.09,2,.09),Vector3(0,1,0),Color("74796d"))
			var face:=G.cylinder(pole,.48,.10,Vector3(0,2.1,0),Color("ab3b2d"))
			face.rotation.x=PI*.5
			G.label(pole,"STOP" if control=="stop" and allowed else "CEDEZ" if allowed else "SENS INTERDIT",Vector3(0,2.1,.1),Color.WHITE,18,.012)

func _build_streetscape() -> void:
	var furniture: Array=["bin","recycling","mailbox","bus_stop","bike_rack","bench","utility_pole","hydrant","street_sign","bollard","manhole","drain"]
	for i in range(Map.building_data.size()):
		var record: Dictionary=Map.building_data[i]
		if not record.has("road_entry") or not _inside(Map._v2(record.road_entry)): continue
		var entry:=Map._v2(record.road_entry); var doorway:=Map._v2(record.entrance)
		var normal: Vector2=(doorway-entry).normalized(); var tangent:=normal.orthogonal()
		var road: Dictionary=Map.nearest_edge(entry)
		var curb: float=float(road.edge.width)*.5+float(road.edge.sidewalk)+12
		for side in [-1,1]:
			var point: Vector2=entry+normal*curb+tangent*side*55
			if not _safe_furniture(point): continue
			var kind: String=furniture[posmod(i+(0 if side<0 else 4),furniture.size())]
			var width: float=3.2 if kind in ["bus_stop","bench"] else 2.5 if kind=="utility_pole" else 1.2
			Art.sprite(self,kind,width,C.to_world(point))
		# Reference-sheet hedge segments form a frontage while leaving a gate gap.
		if record.district in ["RESIDENTIAL","GROVE","SERVICES"]:
			for section in [-2,-1,1,2]:
				var hedge_point: Vector2=entry+normal*(curb+18)+tangent*section*48
				if _safe_furniture(hedge_point,Vector2i(2,1) if absf(tangent.x)>absf(tangent.y) else Vector2i(1,2)): Art.sprite(self,"new_hedge" if i%2==0 else "hedge",4.6,C.to_world(hedge_point))
		# Boundaries sit behind street furniture, leaving the central entrance open.
		if record.district=="RESIDENTIAL" and i%3==0:
			var point: Vector2=entry+normal*(curb+20)+tangent*85
			if _safe_furniture(point): Art.sprite(self,["white_fence","chain_fence","stone_wall","concrete_wall","gate"][i%5],3.5,C.to_world(point))

func _safe_furniture(point: Vector2,footprint: Vector2i=Vector2i.ONE,building_owner: String="") -> bool:
	if not Map.clear_point(point,10) or not Map.roadway_clear(point,8) or Map.lake.has_point(point): return false
	for lot in Map.parking_lots:
		if lot.bounds.grow(15).has_point(point): return false
	for record in Map.building_data:
		if record.has("access_path") or record.has("driveway"):
			var path=record.get("access_path",record.get("driveway",[]))
			for k in range(1,path.size()):
				if point.distance_to(Geometry2D.get_closest_point_to_segment(point,Map._v2(path[k-1]),Map._v2(path[k])))<22: return false
	if Map.tile_grid!=null and not Map.tile_grid.chunks.is_empty():
		return Map.tile_grid.place_decoration(point,footprint,"furniture:"+str(point),building_owner)
	return true

func _build_property_fences() -> void:
	for index in range(Map.building_data.size()):
		var record: Dictionary=Map.building_data[index]; var center:=Map.lots[index].get_center()
		if record.district not in ["RESIDENTIAL","GROVE"] or not _inside(center): continue
		var entry: Vector2=Map._v2(record.get("road_entry",record.get("driveway",[[center.x,center.y+100]])[0]))
		var front: Vector2=(entry-center).normalized(); var tangent:=front.orthogonal()
		var size: Vector2=Map._v2(record.get("local_size",[Map.lots[index].size.x*.67,Map.lots[index].size.y*.67]))
		var width: float=size.x*.5+20; var depth: float=size.y*.5+20
		var segments: Array=[[center-front*depth-tangent*width,center-front*depth+tangent*width]]
		for side in [-1,1]: segments.append([center-front*depth+tangent*side*width,center+front*size.y*.1+tangent*side*width])
		for side in [-1,1]:
			var bush_point: Vector2=center+tangent*side*(size.x*.5+15)
			if _safe_furniture(bush_point,Vector2i.ONE,"building:%d"%index): Art.sprite(self,"new_cypress" if index%7==0 else "new_bush%d"%(index%6),1.5,C.to_world(bush_point))
		var kind: String=["wood_fence","white_fence","chain_fence"][index%3]
		for segment in segments:
			var length: float=segment[0].distance_to(segment[1]); var count:=maxi(1,roundi(length/40))
			for i in range(count):
				var point: Vector2=segment[0].lerp(segment[1],(i+.5)/count)
				if _safe_furniture(point,Vector2i.ONE,"building:%d"%index): Art.fence_sprite(self,kind,minf(4,length/count*.1)*.8,C.to_world(point),(segment[1]-segment[0]).normalized())
