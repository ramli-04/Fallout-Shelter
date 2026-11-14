extends RefCounted
const TILE_METRES := 0.5
static var shared: ShaderMaterial
static func material() -> ShaderMaterial:
	var seed: float=preload("res://scripts/city_map.gd").map_seed%10000
	if shared!=null and is_equal_approx(float(shared.get_shader_parameter("seed")),seed): return shared
	var shader:=Shader.new(); shader.code="""shader_type spatial;
render_mode cull_disabled;
uniform sampler2D atlas : source_color,filter_linear_mipmap,repeat_disable;
uniform vec2 source_size=vec2(1254.0);
uniform vec2 tops[13]; uniform vec2 across[13]; uniform vec2 along[13];
uniform float seed=0.0;
uniform float tile_metres=0.5;
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
 vec2 uv=.10+.8*abs(fract(ground/tile_metres)*2.0-1.0);
 float pixel=max(length(dFdx(ground)),length(dFdy(ground)));
 float lod=clamp(log2(max(pixel*180.0/tile_metres,.001)),0.0,5.0);
 float selector=noise(ground*.055)*5.99;
 int a=int(floor(selector)); int b=(a+1)%7;
 vec3 color=mix(sample_ground(a,uv,lod),sample_ground(b,uv,lod),smoothstep(.15,.85,fract(selector)));
 vec2 cell=floor(ground/tile_metres);
 if(hash(cell)>.90){
  int detail=7+int(hash(cell+vec2(3,17))*5.99);
  vec2 f=fract(ground/tile_metres); float edge=min(min(f.x,1.0-f.x),min(f.y,1.0-f.y));
  color=mix(color,sample_ground(detail,uv,lod),smoothstep(.0,.22,edge)*.65);
 }
 // Keep fine photographed detail without large yellow/green checker patches.
 float value=dot(color,vec3(.2126,.7152,.0722));
 ALBEDO=vec3(.235,.365,.145)*clamp(.84+value*.45,.88,1.12); ROUGHNESS=1.0;
}
"""
	var art=preload("res://scripts/three_d/road_ground_art.gd"); var config:=art.configuration()
	var tops:=PackedVector2Array(); var across:=PackedVector2Array(); var along:=PackedVector2Array()
	for i in range(13):
		var record: Dictionary=config.grass["ground_%02d"%i]
		tops.append(art.vector(record.top)); across.append(art.vector(record.cross)); along.append(art.vector(record.along))
	shared=ShaderMaterial.new(); shared.shader=shader; shared.set_shader_parameter("seed",seed); shared.set_shader_parameter("atlas",art.texture()); shared.set_shader_parameter("source_size",art.vector(config.source_size)); shared.set_shader_parameter("tops",tops); shared.set_shader_parameter("across",across); shared.set_shader_parameter("along",along); return shared
