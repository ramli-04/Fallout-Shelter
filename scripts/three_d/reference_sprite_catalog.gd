extends RefCounted
## User-supplied isometric artwork, prepared with imagegen. Rendering only.
const Map=preload("res://scripts/city_map.gd")
const CIVIC="res://assets/reference_city/civic.png"
const STREETS="res://assets/reference_city/streets.png"
const REGIONS={
	"fire":Rect2(515,575,495,410), "police":Rect2(5,630,505,355),
	"medical":Rect2(1005,550,530,460),"office":Rect2(132,452,386,564), "apartment":Rect2(705,531,800,483),
	"house0":Rect2(4,30,177,137), "house1":Rect2(183,28,169,141),
	"house2":Rect2(356,21,193,143), "house3":Rect2(570,24,185,147),
	"house4":Rect2(4,177,177,147),"house5":Rect2(184,178,175,146),
	"house6":Rect2(370,175,177,150),"house7":Rect2(573,169,186,159),
	"house8":Rect2(774,165,187,162),"large_house":Rect2(963,15,346,303),
	"duplex":Rect2(6,382,227,211),"motel_single":Rect2(951,516,359,110),
	"apartment_small":Rect2(525,395,183,190), "apartment_mid":Rect2(710,339,229,257),
	"townhouse":Rect2(238,365,278,217), "motel":Rect2(951,351,359,166),
	"lamp":Rect2(21,949,48,105), "stop":Rect2(233,955,44,96),
	"yield":Rect2(301,956,44,95), "street_sign":Rect2(363,952,62,100),
	"hydrant":Rect2(445,961,46,79), "bench":Rect2(145,1084,81,86),
	"wood_fence":Rect2(588,954,100,105), "iron_fence":Rect2(684,954,87,105),
	"hedge":Rect2(588,1068,102,108), "brick_wall":Rect2(858,955,94,102),
	"utility_pole":Rect2(77,950,75,110),"mailbox":Rect2(510,957,53,98),
	"bin":Rect2(10,1090,57,90),"recycling":Rect2(77,1090,61,94),
	"bus_stop":Rect2(233,1071,97,115),"manhole":Rect2(333,1103,57,47),
	"drain":Rect2(394,1094,68,66),"bollard":Rect2(475,1085,37,87),
	"bike_rack":Rect2(521,1092,48,85),"chain_fence":Rect2(690,954,77,104),
	"white_fence":Rect2(770,955,84,104),"gate":Rect2(693,1084,77,94),
	"accessible_paving":Rect2(967,1082,111,82),"loading_paving":Rect2(1080,1082,118,82),
	"road_damaged":Rect2(987,650,158,102),"road_pothole":Rect2(1154,650,157,102),
	"stone_wall":Rect2(772,1074,89,105),"concrete_wall":Rect2(865,1074,86,105)
}
static var textures: Dictionary={}
static var materials: Dictionary={}
static var road_materials: Dictionary={}

static func road_material(kind: String,color: Color) -> Material:
	if kind not in ["asphalt","sidewalk","wide_sidewalk","curb","highway_elevated"] and not kind.begins_with("ramp"):
		return preload("res://scripts/three_d/geometry.gd").material(color)
	if road_materials.has(kind): return road_materials[kind]
	var shader:=Shader.new()
	shader.code="""shader_type spatial;
render_mode cull_disabled;
uniform sampler2D sheet : source_color, filter_linear_mipmap, repeat_disable;
uniform bool pavement = false;
uniform bool wide_paving=false;
varying vec2 ground;
void vertex(){ ground=(MODEL_MATRIX*vec4(VERTEX,1.0)).xz; }
void fragment(){
 vec2 tile=fract(ground/(pavement?(wide_paving?6.0:3.0):2.0));
 // Unproject the reference's paving diamond into a square on the road mesh.
 vec2 pixel=pavement ? vec2(100.0+(tile.x-tile.y)*68.0,800.0+(tile.x+tile.y)*33.0)
                     : vec2(50.0,690.0)+tile*vec2(12.0,12.0);
 if(wide_paving) pixel=vec2(746.0+(tile.x-tile.y)*60.0,797.0+(tile.x+tile.y)*33.0);
 vec3 detail=textureLod(sheet,pixel/vec2(1312.0,1199.0),0.0).rgb;
 ALBEDO=detail;
 ROUGHNESS=0.97;
}
"""
	var result:=ShaderMaterial.new(); result.shader=shader
	result.set_shader_parameter("sheet",atlas("house0")); result.set_shader_parameter("pavement",kind in ["sidewalk","wide_sidewalk","curb"])
	result.set_shader_parameter("wide_paving",kind=="wide_sidewalk")
	road_materials[kind]=result
	return result

static func building_kind(recipe: Dictionary,index: int) -> String:
	for poi in Map.pois:
		if poi.footprint==Map.lots[index]:
			return {"Fire Station":"fire","Police Station":"police","Medical Station":"medical","Bank":"apartment","School":"townhouse"}.get(poi.kind,"apartment")
	if recipe.roof or Map.lot_districts[index]=="GROVE" or maxf(recipe.size.x,recipe.size.y)<9: return "house%d"%posmod(index,4)
	if recipe.chimneys: return "motel"
	return "townhouse" if recipe.height<8 else ["apartment","apartment_small","apartment_mid"][posmod(index,3)]

static func atlas(kind: String) -> Texture2D:
	var path: String="res://assets/reference_city/civic-detailed.png" if kind in ["fire","police","medical"] else CIVIC if kind in ["office","apartment"] else STREETS
	if not textures.has(path): textures[path]=load(path)
	return textures[path]

static func material(kind: String) -> ShaderMaterial:
	if materials.has(kind): return materials[kind]
	var shader:=Shader.new()
	shader.code="""shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;
uniform sampler2D sheet : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 region;
uniform float opacity = 1.0;
uniform bool fire_crop = false;
uniform bool flip_x=false;
uniform bool building_anchor = false;
void vertex() {
 MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
 MODELVIEW_MATRIX[0] *= length(MODEL_MATRIX[0].xyz);
 MODELVIEW_MATRIX[1] *= length(MODEL_MATRIX[1].xyz);
 MODELVIEW_MATRIX[2] *= length(MODEL_MATRIX[2].xyz);
 if(building_anchor){
  vec3 forward=normalize(vec3(INV_VIEW_MATRIX[2].x,0.0,INV_VIEW_MATRIX[2].z));
  MODELVIEW_MATRIX[3] += VIEW_MATRIX*vec4(forward*abs(VERTEX.x)*0.6*length(MODEL_MATRIX[0].xyz),0.0);
 }
}
void fragment() {
 if (fire_crop && UV.y > 0.90 && UV.x < 0.44) discard;
 vec2 art_uv=vec2(flip_x?1.0-UV.x:UV.x,UV.y);
 vec4 pixel=texture(sheet,region.xy+art_uv*region.zw);
 if(pixel.a<0.15) discard;
 ALBEDO=pixel.rgb; ALPHA=pixel.a*opacity;
}
"""
	var result:=ShaderMaterial.new(); result.shader=shader
	var texture:=atlas(kind); var r: Rect2=REGIONS[kind]; var s:=Vector2(texture.get_size())
	result.set_shader_parameter("sheet",texture)
	result.set_shader_parameter("region",Vector4(r.position.x/s.x,r.position.y/s.y,r.size.x/s.x,r.size.y/s.y))
	result.set_shader_parameter("opacity",1.0); result.set_shader_parameter("fire_crop",kind=="fire")
	result.set_shader_parameter("building_anchor",kind in ["fire","police","medical","apartment","apartment_small","apartment_mid","townhouse","motel"] or kind.begins_with("house"))
	materials[kind]=result
	return result

static func sprite(parent: Node3D,kind: String,width: float,at: Vector3=Vector3.ZERO) -> MeshInstance3D:
	var node:=MeshInstance3D.new(); node.name="Artwork_"+kind
	var r: Rect2=REGIONS[kind]; var h: float=width*r.size.y/r.size.x
	var quad:=QuadMesh.new(); quad.size=Vector2(width,h)
	# Centre is raised in billboard space so the bottom edge meets the anchor.
	quad.center_offset=Vector3(0,h*.5,0); node.mesh=quad
	node.material_override=material(kind); node.position=at
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin=h; node.set_meta("reference_asset",kind); parent.add_child(node)
	return node

static func build(parent: Node3D,recipe: Dictionary,index: int) -> Node3D:
	var root:=Node3D.new(); root.name="ReferenceArtwork"; parent.add_child(root)
	var kind:=building_kind(recipe,index); root.set_meta("architecture_type",kind)
	var width: float=(recipe.size.x+recipe.size.y)*.7071
	# Base slabs have depth baked into the image: anchor at the front of the parcel.
	var node:=sprite(root,kind,width)
	node.position=Vector3(0,0,0)
	return root

static var ground_materials: Dictionary={}
static func ground_decal(parent: Node3D,kind: String,size: Vector2,at: Vector3,heading: float=0.0) -> void:
	if not ground_materials.has(kind):
		var shader:=Shader.new(); shader.code="""shader_type spatial;
render_mode unshaded,cull_disabled;
uniform sampler2D sheet : source_color,filter_linear_mipmap,repeat_disable;
uniform vec4 region;
void fragment(){vec2 uv=vec2(.5+(UV.x-UV.y)*.45,.06+(UV.x+UV.y)*.44); vec4 c=textureLod(sheet,region.xy+uv*region.zw,0.0); if(c.a<.8)discard; ALBEDO=c.rgb;}
"""
		var material:=ShaderMaterial.new(); material.shader=shader; var rect: Rect2=REGIONS[kind]; var texture_size:=Vector2(atlas(kind).get_size())
		material.set_shader_parameter("sheet",atlas(kind)); material.set_shader_parameter("region",Vector4(rect.position.x/texture_size.x,rect.position.y/texture_size.y,rect.size.x/texture_size.x,rect.size.y/texture_size.y)); ground_materials[kind]=material
	var node:=MeshInstance3D.new(); node.name="GroundArtwork_"+kind; var plane:=PlaneMesh.new(); plane.size=size; node.mesh=plane; node.material_override=ground_materials[kind]; node.position=at; node.rotation.y=-heading; node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; parent.add_child(node)

static func fence_sprite(parent: Node3D,kind: String,width: float,at: Vector3,direction: Vector2) -> void:
	var node:=sprite(parent,kind,width,at)
	if absf(direction.x)>absf(direction.y):
		var key: String="flipped:"+kind
		if not materials.has(key):
			materials[key]=material(kind).duplicate(); materials[key].set_shader_parameter("flip_x",true)
		node.material_override=materials[key]
