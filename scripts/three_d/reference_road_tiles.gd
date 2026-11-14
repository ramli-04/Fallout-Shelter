extends RefCounted
const Map=preload("res://scripts/city_map.gd")
const C=preload("res://scripts/three_d/world_coordinates.gd")
static var materials: Dictionary={}
const NODE_TILES=["intersection_4way","intersection_alt_1","intersection_alt_2","intersection_alt_3","junction_T_N","junction_T_E","junction_T_S","junction_T_W","corner_NE","corner_NW","corner_SE","corner_SW","dead_end","dead_end_crosswalk","cul_de_sac","roundabout_garden","roundabout_lawn","roundabout_fountain"]
static func material(lanes: int) -> Material:
	if materials.has(lanes): return materials[lanes]
	var shader:=Shader.new(); shader.code="""shader_type spatial;
render_mode unshaded,cull_disabled;
uniform sampler2D sheet : source_color,filter_linear_mipmap,repeat_disable;
uniform vec2 source_size=vec2(1254.0);
uniform vec2 top; uniform vec2 across; uniform vec2 along;
uniform vec2 node_top[18]; uniform vec2 node_across[18]; uniform vec2 node_along[18];
uniform bool parking=false;
uniform vec2 road_band=vec2(.16,.35);
vec3 asphalt(){vec2 p=vec2(111,68)+vec2(-83,82)*.38+vec2(122,126)*.43;return textureLod(sheet,p/source_size,0.0).rgb;}
void fragment(){
 vec2 uv=vec2(road_band.x+road_band.y*clamp(UV.x,0.0,1.0),.10+.80*fract(UV.y));
 vec2 p=top+across*uv.x+along*uv.y;
 if(UV2.x>.5){int index=clamp(int(UV2.x+.1)-1,0,17);vec2 junction=clamp(UV,vec2(.04),vec2(.96));p=node_top[index]+node_along[index]*junction.x+node_across[index]*junction.y;}
 vec4 color=textureLod(sheet,p/source_size,0.0);
 if(parking || (UV2.x<.5 && (UV.x<0.0 || UV.x>1.0)) || color.a<.95)color=vec4(asphalt(),1.0);
 if(UV2.x>.5 && UV2.x<15.5 && (color.g>color.r*1.1 || color.r-color.b>.04))color=vec4(asphalt(),1.0);
 // Reference junction pictures include their own raised curbs and perspective.
 // Keep their asphalt detail on the connected surface; physical curbs and lane
 // strokes are built from actual road directions, so no curb crosses a lane.
 if(UV2.x>.5 && UV2.x<15.5){
  vec3 base=asphalt();
  float detail=dot(color.rgb,vec3(.2126,.7152,.0722))/max(dot(base,vec3(.2126,.7152,.0722)),.01);
  color=vec4(base*clamp(detail,.90,1.10),1.0);
 }
 ALBEDO=color.rgb; ROUGHNESS=1.0;
}
"""
	var art=preload("res://scripts/three_d/road_ground_art.gd"); var config:=art.configuration()
	var result:=ShaderMaterial.new(); result.shader=shader; result.set_shader_parameter("sheet",art.texture()); result.set_shader_parameter("source_size",art.vector(config.source_size)); art.apply(result,"straight_median" if lanes==5 else "straight_4lane" if lanes>=4 else "straight_2lane"); result.set_shader_parameter("parking",lanes==-1); result.set_shader_parameter("road_band",Vector2(.16,.62) if lanes==5 else Vector2(.17,.48) if lanes>=4 else Vector2(.16,.35))
	var tops:=PackedVector2Array(); var across:=PackedVector2Array(); var along:=PackedVector2Array()
	for name in NODE_TILES:
		var record: Dictionary=config.roads[name]; tops.append(art.vector(record.top)); across.append(art.vector(record.cross)); along.append(art.vector(record.along))
	result.set_shader_parameter("node_top",tops); result.set_shader_parameter("node_across",across); result.set_shader_parameter("node_along",along); materials[lanes]=result; return result
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
