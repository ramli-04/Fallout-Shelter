extends RefCounted
## Orthographic adaptation of the user's latest street reference sheet.
static var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/street_surface_collection.json"))
static var image: Texture2D
static var materials: Dictionary={}
static func texture() -> Texture2D:
	if image==null: image=load(config.atlas)
	return image
static func region(name: String) -> Vector4:
	var r: Array=config.tiles[name]
	return Vector4(float(r[0])/1536,float(r[1])/1024,float(r[2])/1536,float(r[3])/1024)
static func surface_material(name: String) -> ShaderMaterial:
	if materials.has(name): return materials[name]
	var shader:=Shader.new(); shader.code="""shader_type spatial;
render_mode unshaded,cull_disabled;
uniform sampler2D atlas : source_color,filter_linear_mipmap,repeat_disable;
uniform vec4 region;
uniform bool plain=false;
void fragment(){
 vec2 uv=plain?vec2(.39,.39):.01+.98*fract(UV);
 vec4 color=texture(atlas,region.xy+region.zw*uv);
 ALBEDO=color.rgb; ROUGHNESS=1.0;
}
"""
	var result:=ShaderMaterial.new(); result.shader=shader; result.set_shader_parameter("atlas",texture()); result.set_shader_parameter("region",region("straight_2lane" if name=="asphalt" else name)); result.set_shader_parameter("plain",name=="asphalt"); materials[name]=result; return result
static func export_resources() -> void:
	for name in config.tiles:
		var r: Array=config.tiles[name]
		var atlas:=AtlasTexture.new(); atlas.atlas=texture(); atlas.region=Rect2(r[0],r[1],r[2],r[3]); atlas.filter_clip=true
		assert(ResourceSaver.save(atlas,"res://assets/Roads/current_"+name+".tres")==OK)
