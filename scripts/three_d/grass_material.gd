extends RefCounted
const TILE_METRES := 1.0
static var shared: ShaderMaterial
static func material() -> ShaderMaterial:
	var seed: float=preload("res://scripts/city_map.gd").map_seed%10000
	if shared!=null and is_equal_approx(float(shared.get_shader_parameter("seed")),seed): return shared
	var shader:=Shader.new(); shader.code="""shader_type spatial;
render_mode unshaded,cull_disabled;
uniform sampler2D atlas : source_color,filter_linear_mipmap,repeat_disable;
uniform vec2 source_size=vec2(1254.0);
uniform vec2 tops[13]; uniform vec2 across[13]; uniform vec2 along[13];
uniform float seed=0.0;
uniform float tile_metres=1.0;
varying vec2 ground;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7))+seed)*43758.5453);}
float noise(vec2 p){vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
vec3 sample_ground(int index,vec2 uv,float lod){
 vec2 p=tops[index]+across[index]*uv.x+along[index]*uv.y;
 vec4 c=textureLod(atlas,p/source_size,lod);
 if(c.a<.9)c=textureLod(atlas,(tops[index]+(across[index]+along[index])*.5)/source_size,0.0);
 return c.rgb;
}
void vertex(){ground=(MODEL_MATRIX*vec4(VERTEX,1.0)).xz;}
void fragment(){
 vec2 uv=.15+.70*abs(fract(ground/tile_metres)*2.0-1.0);
 float pixel=max(length(dFdx(ground)),length(dFdy(ground)));
 float lod=clamp(log2(max(pixel*120.0/tile_metres,.001)),0.0,4.0);
 // Plain green turf from the reference, without dirt/bush biome bands.
 vec3 color=sample_ground(2,uv,lod);
 float detail=clamp(dot(color,vec3(.2126,.7152,.0722))*1.5,.0,1.0);
 ALBEDO=vec3(.275,.45,.09)*(.95+detail*.10+noise(ground*3.0)*.02); ROUGHNESS=1.0;
}
"""
	var art=preload("res://scripts/three_d/road_ground_art.gd"); var config:=art.configuration()
	var tops:=PackedVector2Array(); var across:=PackedVector2Array(); var along:=PackedVector2Array()
	for i in range(13):
		var record: Dictionary=config.grass["ground_%02d"%i]
		tops.append(art.vector(record.top)); across.append(art.vector(record.cross)); along.append(art.vector(record.along))
	shared=ShaderMaterial.new(); shared.shader=shader; shared.set_shader_parameter("tile_metres",TILE_METRES); shared.set_shader_parameter("seed",seed); shared.set_shader_parameter("atlas",art.texture()); shared.set_shader_parameter("source_size",art.vector(config.source_size)); shared.set_shader_parameter("tops",tops); shared.set_shader_parameter("across",across); shared.set_shader_parameter("along",along); return shared
