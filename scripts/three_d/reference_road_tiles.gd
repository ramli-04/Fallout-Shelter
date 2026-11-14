extends RefCounted
const Map=preload("res://scripts/city_map.gd")
const C=preload("res://scripts/three_d/world_coordinates.gd")
static var materials: Dictionary={}
static func material(lanes: int) -> Material:
	if materials.has(lanes): return materials[lanes]
	var shader:=Shader.new(); shader.code="""shader_type spatial;
render_mode unshaded,cull_disabled;
uniform sampler2D sheet : source_color,filter_linear_mipmap,repeat_disable;
uniform vec2 origin;
uniform bool swap_axes=false;
uniform bool parking=false;
uniform vec2 tile_steps=vec2(80.0,43.0);
void fragment(){
 vec2 uv=vec2(clamp(UV.x,0.02,0.98),fract(UV.y));
 if(swap_axes)uv=uv.yx;
 vec2 pixel=origin+vec2((uv.x-uv.y)*tile_steps.x,(uv.x+uv.y)*tile_steps.y);
 if(UV.x<0.0 || UV.x>1.0) pixel=vec2(54.0,692.0);
 if(parking)pixel=vec2(54.0,692.0);
 if(UV2.x>0.5) pixel=vec2(54.0,692.0);
 vec4 c=textureLod(sheet,pixel/vec2(1312.0,1199.0),0.0);
 if(c.a<0.98)c=textureLod(sheet,vec2(54.0,692.0)/vec2(1312.0,1199.0),0.0);
 ALBEDO=c.rgb; ROUGHNESS=1.0;
}
"""
	var result:=ShaderMaterial.new(); result.shader=shader; result.set_shader_parameter("sheet",load("res://assets/reference_city/streets.png")); result.set_shader_parameter("origin",Vector2(274,655) if lanes>=4 else Vector2(94,655))
	result.set_shader_parameter("swap_axes",lanes>=4)
	result.set_shader_parameter("parking",lanes==-1)
	if lanes==-1: result.set_shader_parameter("origin",Vector2(1233,973)); result.set_shader_parameter("tile_steps",Vector2(65,38))
	materials[lanes]=result; return result
static func conforming_surface(parent: Node3D,vertices: PackedVector3Array) -> void:
	var groups: Dictionary={}
	for i in range(0,vertices.size(),3):
		var center: Vector2=C.to_simulation((vertices[i]+vertices[i+1]+vertices[i+2])/3)
		var nearest: Dictionary=Map.nearest_edge(center)
		var road: Dictionary=nearest.edge; var lanes:=int(road.lanes)
		var a: Vector2=road.points[nearest.segment]; var b: Vector2=road.points[nearest.segment+1]
		var tangent: Vector2=(b-a).normalized(); var normal:=tangent.orthogonal(); var width:=float(road.width)
		var parking: Dictionary={}
		for lot in Map.parking_lots:
			if Geometry2D.is_point_in_polygon(center,lot.polygon): parking=lot; lanes=-1; break
		var plain:=0.0; var junction_center:=Vector2.ZERO
		for id in [road.from,road.to]:
			if Map.graph.get_point_connections(id).size()>2 and center.distance_to(Map.graph.get_point_position(id))<width*.75+25:
				plain=1.0; junction_center=Map.graph.get_point_position(id)
		if not parking.is_empty(): plain=0.0
		if not groups.has(lanes):
			var surface:=SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES); groups[lanes]=surface
		var surface: SurfaceTool=groups[lanes]
		for j in range(3):
			var point: Vector2=C.to_simulation(vertices[i+j]); var offset: Vector2=point-a
			var uv:=Vector2(.5+offset.dot(normal)/width,offset.dot(tangent)/width)
			if plain>0:
				uv=Vector2(.5,.5)+(point-junction_center)/(width*1.5)
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
		for j in range(3): groups[key].add_vertex(vertices[i+j])
	for key in groups:
		var node:=MeshInstance3D.new(); node.name="ReferencePaving_"+key; groups[key].generate_normals(); node.mesh=groups[key].commit(); node.material_override=preload("res://scripts/three_d/reference_sprite_catalog.gd").road_material(key,Color.WHITE); parent.add_child(node)
