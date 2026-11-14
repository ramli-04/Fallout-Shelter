extends RefCounted
static var shared: ShaderMaterial
static func material() -> ShaderMaterial:
	if shared!=null and is_equal_approx(float(shared.get_shader_parameter("seed")),float(preload("res://scripts/city_map.gd").map_seed%10000)): return shared
	var shader:=Shader.new(); shader.code="""shader_type spatial;
uniform float seed=0.0;
varying vec2 ground;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7))+seed)*43758.5453);}
float noise(vec2 p){vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void vertex(){ground=(MODEL_MATRIX*vec4(VERTEX,1.0)).xz;}
void fragment(){
 float pixel=max(length(dFdx(ground)),length(dFdy(ground)));
 float broad=noise(ground*.065);
 float clump=mix(.5,noise(ground*.45),1.0-smoothstep(.5,4.0,pixel));
 float grain=mix(.5,noise(ground*4.0),1.0-smoothstep(.05,.5,pixel));
 vec3 lush=mix(vec3(.21,.29,.13),vec3(.36,.42,.20),clump);
 vec3 dry=vec3(.42,.43,.27);
 vec3 soil=vec3(.35,.30,.20);
 vec3 grass=mix(lush,dry,smoothstep(.48,.78,broad)*.4);
 grass=mix(grass,soil,smoothstep(.78,.94,clump+broad*.12)*.65);
 ALBEDO=grass*(.86+grain*.24); ROUGHNESS=1.0;
}
"""
	shared=ShaderMaterial.new(); shared.shader=shader; shared.set_shader_parameter("seed",float(preload("res://scripts/city_map.gd").map_seed%10000)); return shared
