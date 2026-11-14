extends RefCounted
static var data: Dictionary={}
static var image: Texture2D
static func configuration() -> Dictionary:
	if data.is_empty(): data=JSON.parse_string(FileAccess.get_file_as_string("res://resources/road_ground_collection.json"))
	return data
static func texture() -> Texture2D:
	if image==null: image=load(configuration().atlas)
	return image
static func vector(value: Array) -> Vector2: return Vector2(value[0],value[1])
static func apply(material: ShaderMaterial,name: String,prefix: String="") -> void:
	var record: Dictionary=configuration().roads[name]
	material.set_shader_parameter(prefix+"top",vector(record.top)); material.set_shader_parameter(prefix+"across",vector(record.cross)); material.set_shader_parameter(prefix+"along",vector(record.along))
static func export_resources() -> int:
	var config:=configuration(); var ratio:=Vector2(texture().get_size())/vector(config.source_size); var count:=0
	for group in [config.roads,config.grass]:
		for name in group:
			var record: Dictionary=group[name]; var r: Array=record.region
			var atlas:=AtlasTexture.new(); atlas.atlas=texture(); atlas.region=Rect2(Vector2(r[0],r[1])*ratio,Vector2(r[2],r[3])*ratio); atlas.filter_clip=true
			assert(ResourceSaver.save(atlas,"res://assets/"+record.category+"/"+name+".tres")==OK); count+=1
	return count

static var paving: Dictionary={}
static func paving_material(wide: bool) -> ShaderMaterial:
	if paving.has(wide): return paving[wide]
	var shader:=Shader.new(); shader.code="""shader_type spatial;
render_mode unshaded,cull_disabled;
uniform sampler2D atlas : source_color,filter_linear_mipmap,repeat_disable;
uniform vec2 source_size=vec2(1254.0);
uniform bool pavement=true;
uniform vec2 top; uniform vec2 across; uniform vec2 along;
void fragment(){
 vec2 uv=vec2(.57+.06*clamp(UV.x,0.0,1.0),.15+.70*fract(UV.y));
 vec4 color=textureLod(atlas,(top+across*uv.x+along*uv.y)/source_size,0.0);
 if(color.a<.95)color=textureLod(atlas,(top+across*.6+along*.5)/source_size,0.0);
 ALBEDO=color.rgb; ROUGHNESS=pavement?1.0:.9;
}
"""
	var result:=ShaderMaterial.new(); result.shader=shader; result.set_shader_parameter("atlas",texture()); result.set_shader_parameter("source_size",vector(configuration().source_size)); apply(result,"straight_2lane"); result.set_shader_parameter("pavement",true); paving[wide]=result; return result

static func plain_asphalt_material() -> ShaderMaterial:
	if paving.has("asphalt"): return paving["asphalt"]
	var shader:=Shader.new(); shader.code="""shader_type spatial;
render_mode unshaded,cull_disabled;
uniform sampler2D atlas : source_color,filter_linear_mipmap,repeat_disable;
uniform vec2 source_size=vec2(1254.0);
void fragment(){vec2 pixel=vec2(111,68)+vec2(-83,82)*.38+vec2(122,126)*.43;ALBEDO=textureLod(atlas,pixel/source_size,0.0).rgb;ROUGHNESS=1.0;}
"""
	var material:=ShaderMaterial.new(); material.shader=shader; material.set_shader_parameter("atlas",texture()); material.set_shader_parameter("source_size",vector(configuration().source_size)); paving["asphalt"]=material; return material
