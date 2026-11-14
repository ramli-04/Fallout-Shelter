extends RefCounted
## Flat sheet artwork registered to its ground footprint, not the image bottom.
const Map=preload("res://scripts/city_map.gd")
static var catalog: Dictionary={}
static var materials: Dictionary={}
static var view_facing:=0
static var textures: Dictionary={}
static var shared_shader: Shader
static var transparent_texture: Texture2D
static var missing: Dictionary={}
# Projected ground depth / sprite width, excluding the vertical building body.
const GROUND_DEPTH={"new_house0":.45,"new_house1":.44,"new_house2":.43,"new_house3":.44,"new_house4":.38,"new_apartment":.4,"new_police":.45,"new_fire":.45,"new_office":.4,"new_parking":.45,"house0":.45,"house1":.45,"house2":.42,"house3":.44,"house4":.45,"house5":.43,"house6":.43,"house7":.42,"house8":.42,"large_house":.40,"duplex":.38,"townhouse":.32,"apartment_small":.44,"apartment_mid":.42,"apartment":.38,"office":.40,"motel":.32,"motel_single":.13,"fire":.36,"police":.35,"medical":.38}
static func registration(kind: String,region: Rect2,size: Vector2) -> Dictionary:
	var width: float=(size.x+size.y)*.70710678*.85
	var height: float=width*region.size.y/region.size.x
	var ground_depth: float=width*float(GROUND_DEPTH.get(kind,.4))
	# Image-space contact centre must project onto the logical parcel centre.
	var anchor: float=(height*.47-ground_depth*.5)/.8660254
	return {"width":width,"height":height,"anchor":anchor,"ground_depth":ground_depth}

static func texture(key: String) -> Texture2D:
	if key.begins_with("sheet:"): return preload("res://scripts/three_d/reference_sprite_catalog.gd").atlas(key.split(":")[1])
	if textures.get(key) is Texture2D: return textures[key]
	var path: String="res://assets/building_sprites/"+key+".png"
	var result: Texture2D=load(path) as Texture2D if ResourceLoader.exists(path) else null
	if result!=null and result.get_width()>0:
		textures[key]=result; return result
	# Do not cache failed loads: a later asset import can repair them.
	if not missing.has(key): push_warning("Building sprite unavailable: "+path); missing[key]=true
	var kind: String=key.substr(0,key.rfind("_"))
	var fallback: String="res://assets/building_sprites/"+kind+"_0.png"
	if key!=kind+"_0" and ResourceLoader.exists(fallback):
		result=load(fallback) as Texture2D
		if result!=null: return result
	if transparent_texture==null:
		var image:=Image.create(1,1,false,Image.FORMAT_RGBA8); image.fill(Color.TRANSPARENT)
		transparent_texture=ImageTexture.create_from_image(image)
	return transparent_texture
static func set_camera(camera: Camera3D) -> void:
	var yaw:=atan2(camera.global_basis.z.x,camera.global_basis.z.z)
	var facing:=roundi((yaw-PI*.25)/(TAU/72))
	if facing==view_facing: return
	view_facing=facing
	for key in materials:
		materials[key].set_shader_parameter("artwork",texture(view_key(key)))
static func view_key(key: String) -> String:
	if key.begins_with("sheet:"): return key
	var split:=key.rfind("_"); var kind:=key.substr(0,split); var facing:=int(key.substr(split+1))
	var count:=int(catalog.get(kind,{}).get("facings",72))
	return kind+"_"+str(posmod(facing-view_facing,count))
static func info(recipe: Dictionary,index: int) -> Dictionary:
	var kind:="house" if recipe.roof or Map.lot_districts[index]=="GROVE" or (Map.lot_districts[index]=="RESIDENTIAL" and recipe.height<=6) else "industrial" if recipe.chimneys or Map.lot_districts[index]=="INDUSTRIAL" else "office" if Map.lot_districts[index]=="DOWNTOWN" and index%3==0 else "apartment"
	for poi in Map.pois:
		if poi.footprint==Map.lots[index]: kind={"Fire Station":"fire","Police Station":"police","Medical Station":"medical","School":"school","Bank":"office"}.get(poi.kind,"apartment")
	var art=preload("res://scripts/three_d/reference_sprite_catalog.gd")
	# Only the latest supplied building collection is active.
	var sprite_kind: String={"police":"new_police","fire":"new_fire","medical":"new_office","school":"new_office","office":"new_office","industrial":"new_parking","apartment":"new_apartment"}.get(kind,"new_house%d"%posmod(index,5))
	var region: Rect2=art.REGIONS[sprite_kind]
	var visual_size: Vector2=recipe.size
	if kind=="house":
		var limit:=Vector2(14,12) if sprite_kind=="large_house" else Vector2(11,10)
		visual_size=visual_size.min(limit)
	var placement:=registration(sprite_kind,region,visual_size)
	if index<Map.building_data.size() and Map.building_data[index].has("station_art"): placement=Map.building_data[index].station_art
	var width: float=placement.width
	var height: float=placement.height
	var facing:=posmod(roundi(Map.lot_angles[index]/(PI*.5)),4)
	return {"kind":kind,"key":"sheet:%s:%d"%[sprite_kind,facing],"width":width,"height":height,"anchor":placement.anchor,"ground_depth":placement.ground_depth,"offset":placement.get("offset",Vector2.ZERO)}
static func material(key: String) -> ShaderMaterial:
	if materials.has(key): return materials[key]
	if shared_shader==null: shared_shader=Shader.new(); shared_shader.code=shader_source()
	var result:=ShaderMaterial.new(); result.shader=shared_shader; result.set_shader_parameter("artwork",texture(view_key(key)))
	if key.begins_with("sheet:"):
		var art=preload("res://scripts/three_d/reference_sprite_catalog.gd")
		var kind: String=key.split(":")[1]; var r: Rect2=art.REGIONS[kind]; var size:=Vector2(texture(key).get_size())
		result.set_shader_parameter("uv_region",Vector4(r.position.x/size.x,r.position.y/size.y,r.size.x/size.x,r.size.y/size.y))
		result.set_shader_parameter("mirror",int(key.split(":")[2]) in [1,2])
		result.set_shader_parameter("cutout_mask",art.cutout_mode(kind))
		if kind in ["new_police","new_fire"]:
			var width: float=34.0 if kind=="new_police" else 36.0
			var height: float=width*r.size.y/r.size.x
			result.set_shader_parameter("station_apron",1 if kind=="new_police" else 2)
			result.set_shader_parameter("station_height",height)
			result.set_shader_parameter("station_ground_center",.97-width*.45/(2*height))
			result.set_shader_parameter("station_anchor",(height*.47-width*.45*.5)/.8660254)
	materials[key]=result; return result
static func shader_source() -> String:
	return """shader_type spatial;
render_mode unshaded,cull_disabled,depth_prepass_alpha;
uniform sampler2D artwork : source_color,filter_linear_mipmap,repeat_disable;
uniform float opacity=1.0;
uniform vec4 uv_region=vec4(0.0,0.0,1.0,1.0);
uniform bool mirror=false;
uniform int cutout_mask=0;
uniform int station_apron=0;
uniform float station_height=1.0;
uniform float station_ground_center=.8;
uniform float station_anchor=0.0;
varying float sprite_depth;
varying float ground_view_z;
void vertex(){
 MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
 MODELVIEW_MATRIX[0]*=length(MODEL_MATRIX[0].xyz);
 MODELVIEW_MATRIX[1]*=length(MODEL_MATRIX[1].xyz);
 // Sort the flat artwork at the near edge of its reserved footprint.
 // Centre depth lets the ground in front of the centre erase the sprite base.
 vec4 sort_position=MODELVIEW_MATRIX[3];
 sort_position.z+=abs(VERTEX.x)*length(MODEL_MATRIX[0].xyz)*0.9;
 vec4 clip=PROJECTION_MATRIX*sort_position;
 sprite_depth=clip.z/clip.w;
 ground_view_z=(VIEW_MATRIX*(MODEL_MATRIX[3]-vec4(0.0,station_anchor,0.0,0.0))).z;
}
void fragment(){vec2 uv=vec2(mirror?1.0-UV.x:UV.x,UV.y); if(cutout_mask==1 && uv.x<.11 && uv.y<.68)discard;
 if(cutout_mask==2 && ((uv.x>.75 && uv.y>.86)||(uv.x>.8 && uv.y<.025)))discard;
 if(cutout_mask==3 && uv.x>.88 && uv.y>.70)discard;
 if(cutout_mask==4 && uv.y<.13 && (uv.x<.47 || uv.x>.52))discard;
 if(cutout_mask==5 && uv.x>.61 && uv.y>.9)discard;
 vec4 c=texture(artwork,uv_region.xy+uv*uv_region.zw); if(c.a<0.1)discard; ALBEDO=c.rgb; ALPHA=c.a*opacity;
 float depth=sprite_depth;
 // Painted apron pixels lie on the ground, so real fleet vehicles can cover them.
 float apron_edge=station_apron==1?.48+uv.x*.60:.36+uv.x*.50;
 if(station_apron>0 && uv.y>apron_edge){
  vec4 apron_clip=PROJECTION_MATRIX*vec4(0.0,0.0,ground_view_z+(UV.y-station_ground_center)*station_height*1.7320508,1.0);
  depth=apron_clip.z/apron_clip.w;
 }
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
 DEPTH=depth*0.5+0.5;
#else
 DEPTH=depth;
#endif
}
"""
static func build(parent: Node3D,recipe: Dictionary,index: int) -> Node3D:
	var data:=info(recipe,index); var root:=Node3D.new(); root.name="BuildingSprite"; root.set_meta("architecture_type",data.kind); parent.add_child(root)
	var node:=MeshInstance3D.new(); var quad:=QuadMesh.new(); quad.size=Vector2(data.width,data.height); node.mesh=quad; root.position=parent.basis.inverse()*Vector3(data.offset.x,0,data.offset.y); node.position.y=data.anchor; node.material_override=material(data.key); node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; node.extra_cull_margin=data.height; root.add_child(node); return root

static func visual_door(recipe: Dictionary,index: int) -> Vector2:
	var data:=info(recipe,index)
	var uv:=Vector2(.46,.90)
	if int(data.key.split(":")[2]) in [1,2]: uv.x=1-uv.x
	var ground_center: float=.97-float(data.ground_depth)/(2*float(data.height))
	var screen_x: float=(uv.x-.5)*float(data.width)
	var screen_down: float=(uv.y-ground_center)*float(data.height)
	var offset:=Vector2(screen_x+screen_down/.5,-screen_x+screen_down/.5)/sqrt(2.0)
	return Map.lots[index].get_center()+(offset+data.offset)/.1
