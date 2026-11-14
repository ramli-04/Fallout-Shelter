extends RefCounted
const Map=preload("res://scripts/city_map.gd")
const C=preload("res://scripts/three_d/world_coordinates.gd")
static var materials: Dictionary={}
const NODE_TILES=["intersection_4way","intersection_alt_1","intersection_alt_2","intersection_alt_3","junction_T_N","junction_T_E","junction_T_S","junction_T_W","corner_NE","corner_NW","corner_SE","corner_SW","dead_end","dead_end_crosswalk","cul_de_sac","roundabout_garden","roundabout_lawn","roundabout_fountain"]
static func material(lanes: int) -> Material:
	if materials.has(lanes): return materials[lanes]
	var art=preload("res://scripts/three_d/street_surface_art.gd")
	var shader:=Shader.new(); shader.code="""shader_type spatial;
render_mode unshaded,cull_disabled;
uniform sampler2D sheet : source_color,filter_linear_mipmap,repeat_disable;
uniform vec4 straight_region;
uniform vec4 parking_region;
uniform vec4 node_regions[18];
uniform int node_turns[18];
uniform bool parking=false;
uniform bool plain=false;
uniform vec2 road_band=vec2(.25,.52);
vec3 asphalt(){return textureLod(sheet,straight_region.xy+straight_region.zw*vec2(.39,.39),0.0).rgb;}
void fragment(){
 vec2 uv=vec2(road_band.x+road_band.y*clamp(UV.x,0.0,1.0),fract(UV.y));
 vec4 region=straight_region;
 if(UV2.x>.5){
  int index=clamp(int(UV2.x+.1)-1,0,17);
  region=node_regions[index]; uv=clamp(UV,vec2(.005),vec2(.995));
  int turns=node_turns[index];
  if(index==14)uv.y-=.07;
  if(turns==1)uv=vec2(uv.y,1.0-uv.x);
  if(turns==2)uv=vec2(1.0-uv.x,1.0-uv.y);
  if(turns==3)uv=vec2(1.0-uv.y,uv.x);
 }
 if(parking){region=parking_region;uv=vec2(.68-.56*clamp(UV.y,0.0,1.0),clamp(.031+1.02*UV.x,.025,.98));}
 vec4 color=texture(sheet,region.xy+region.zw*uv);
 if(plain || color.a<.8)color=vec4(asphalt(),1.0);
 if(UV2.x>.5 && !parking){
  bool grass=color.g>color.r*1.08;
  bool paving=color.r>.42 && color.r-color.b>.025 && color.b>color.r*.55;
  if(grass || paving)color=vec4(asphalt(),1.0);
 }
 ALBEDO=color.rgb; ROUGHNESS=1.0;
}
"""
	var result:=ShaderMaterial.new(); result.shader=shader
	result.set_shader_parameter("sheet",art.texture()); result.set_shader_parameter("parking",lanes==-2); result.set_shader_parameter("plain",lanes==-1)
	result.set_shader_parameter("straight_region",art.region("median" if lanes==5 else "straight_4lane" if lanes>=4 else "straight_2lane"))
	result.set_shader_parameter("parking_region",art.region("parking"))
	result.set_shader_parameter("road_band",Vector2(.17,.66) if lanes>=4 else Vector2(.25,.52))
	var names=["intersection","intersection","intersection","intersection","junction_T","junction_T","junction_T","junction_T","corner","corner","corner","corner","cul_de_sac","cul_de_sac","cul_de_sac","roundabout","roundabout","roundabout"]
	if lanes>=4:
		for i in range(8,12): names[i]="corner_4lane"
	var regions: Array[Vector4]=[]
	for name in names: regions.append(art.region(name))
	result.set_shader_parameter("node_regions",regions)
	var turns:=PackedInt32Array([0,0,0,0,1,2,3,0,0,3,1,2,0,0,0,0,0,0])
	# The wide corner's generated base orientation is left/bottom.
	if lanes>=4:
		for i in range(8,12): turns[i]=(turns[i]+2)%4
	result.set_shader_parameter("node_turns",turns)
	materials[lanes]=result; return result
static func conforming_surface(parent: Node3D,vertices: PackedVector3Array) -> void:
	var groups: Dictionary={}
	for i in range(0,vertices.size(),3):
		var center: Vector2=C.to_simulation((vertices[i]+vertices[i+1]+vertices[i+2])/3)
		var nearest: Dictionary=Map.nearest_edge(center)
		var road: Dictionary=nearest.edge; var lanes:=int(road.lanes)
		if lanes==4 and road.kind=="arterial" and int(road.from)%3==0: lanes=5
		var a: Vector2=road.points[nearest.segment]; var b: Vector2=road.points[nearest.segment+1]
		var tangent: Vector2=(b-a).normalized(); var normal:=tangent.orthogonal(); var width:=float(road.width)
		var parking: Dictionary={}
		for lot in Map.parking_lots:
			if Geometry2D.is_point_in_polygon(center,lot.polygon): parking=lot; lanes=-1; break
		var plain:=0.0; var junction_center:=Vector2.ZERO
		for id in [road.from,road.to]:
			var connections: PackedInt64Array=Map.graph.get_point_connections(id)
			var node: Vector2=Map.graph.get_point_position(id)
			if center.distance_to(node)>width*1.1+25: continue
			if connections.size()>=4: plain=1+posmod(int(id),4)
			elif connections.size()==3:
				var mask:=0
				for connection in connections:
					var direction: Vector2=Map.graph.get_point_position(connection)-node
					mask|=(1 if direction.x>0 else 2) if absf(direction.x)>absf(direction.y) else (4 if direction.y>0 else 8)
				plain=5+({8:0,1:1,4:2,2:3}.get(15^mask,0))
			elif connections.size()==1: plain=13+posmod(int(id),2)
			elif connections.size()==2:
				var first: Vector2=(Map.graph.get_point_position(connections[0])-node).normalized()
				var second: Vector2=(Map.graph.get_point_position(connections[1])-node).normalized()
				if absf(first.dot(second))<.5: plain=9+posmod(int(id),4)
			if plain>0: junction_center=node
		if Geometry2D.is_point_in_polygon(center,Map.grove.bulb): plain=15; junction_center=Map.grove.center
		for roundabout in Map.roundabout_data:
			var round_center:=Map._v2(roundabout.center)
			if center.distance_to(round_center)<float(roundabout.radius)*1.25: plain=16+posmod(int(road.from),3); junction_center=round_center
		if not parking.is_empty(): plain=0.0
		if not groups.has(lanes):
			var surface:=SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES); groups[lanes]=surface
		var surface: SurfaceTool=groups[lanes]
		for j in range(3):
			var point: Vector2=C.to_simulation(vertices[i+j]); var offset: Vector2=point-a
			var uv:=Vector2(.5+offset.dot(normal)/width,offset.dot(tangent)/width)
			if plain>0:
				uv=Vector2(.5,.5)+(point-junction_center)/(width*2.6)
			if not parking.is_empty():
				var relative: Vector2=point-parking.polygon[0]
				uv=Vector2(relative.dot(parking.tangent)/230,relative.dot(parking.normal)/150)
			surface.set_uv(uv); surface.set_uv2(Vector2(plain,0)); surface.add_vertex(vertices[i+j])
	for lanes in groups:
		var node:=MeshInstance3D.new(); node.name="ReferenceRoadArtwork"; node.mesh=groups[lanes].commit(); node.material_override=material(lanes); node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; parent.add_child(node)

static func paving_surface(parent: Node3D,vertices: PackedVector3Array) -> void:
	var groups: Dictionary={}
	for i in range(0,vertices.size(),3):
		var point: Vector2=C.to_simulation((vertices[i]+vertices[i+1]+vertices[i+2])/3)
		var nearest: Dictionary=Map.nearest_edge(point)
		var key: String="wide_sidewalk" if float(nearest.edge.sidewalk)>=70 else "sidewalk"
		if not groups.has(key):
			var surface:=SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES); groups[key]=surface
		var road: Dictionary=nearest.edge
		var start: Vector2=road.points[nearest.segment]; var direction: Vector2=(road.points[nearest.segment+1]-start).normalized(); var normal:=direction.orthogonal()
		for j in range(3):
			var position: Vector2=C.to_simulation(vertices[i+j]); var delta: Vector2=position-start
			var side: float=(absf(delta.dot(normal))-float(road.width)*.5)/maxf(float(road.sidewalk),1)
			groups[key].set_uv(Vector2(side,delta.dot(direction)/(80.0 if key=="wide_sidewalk" else 40.0))); groups[key].add_vertex(vertices[i+j])
	for key in groups:
		var node:=MeshInstance3D.new(); node.name="ReferencePaving_"+key; groups[key].generate_normals(); node.mesh=groups[key].commit(); node.material_override=preload("res://scripts/three_d/reference_sprite_catalog.gd").road_material(key,Color.WHITE); parent.add_child(node)
