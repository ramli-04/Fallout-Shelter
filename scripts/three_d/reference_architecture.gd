extends RefCounted
## Original 3D architecture following the user's brick/stone neighbourhood references.
const G=preload("res://scripts/three_d/geometry.gd")
const Map=preload("res://scripts/city_map.gd")
static var masonry: Dictionary={}
const BRICKS=["865744","765044","94705b","a39b88","75584a","afa590"]
var batches: Dictionary={}
var root: Node3D

static func overview_material(color: Color) -> ShaderMaterial:
	var material:=ShaderMaterial.new(); var shader:=Shader.new()
	shader.code="""shader_type spatial;
uniform vec4 tint : source_color;
varying vec3 p;
varying vec3 n;
varying vec3 dimensions;
void vertex(){p=VERTEX+vec3(0.5); n=NORMAL; dimensions=vec3(length(MODEL_MATRIX[0].xyz),length(MODEL_MATRIX[1].xyz),length(MODEL_MATRIX[2].xyz));}
void fragment(){
 vec2 facade=vec2(abs(n.x)>0.5?p.z*dimensions.z:p.x*dimensions.x,p.y*dimensions.y);
 vec2 cell=fract(facade/vec2(2.8,3.1));
 float window=step(0.28,cell.x)*step(cell.x,0.72)*step(0.3,cell.y)*step(cell.y,0.80);
 ALBEDO=n.y>0.5?vec3(0.12,0.14,0.15):mix(tint.rgb,vec3(0.12,0.22,0.27),window);
 ROUGHNESS=0.85;
}"""
	material.shader=shader; material.set_shader_parameter("tint",color); return material

static func brick_material(color: Color) -> ShaderMaterial:
	var key:=color.to_html()
	if masonry.has(key): return masonry[key]
	var shader:=Shader.new()
	shader.code="""shader_type spatial;
render_mode depth_prepass_alpha;
uniform vec4 tint : source_color;
uniform float opacity = 1.0;
varying vec3 local_position;
varying vec3 local_normal;
void vertex(){ local_position=VERTEX; local_normal=NORMAL; }
void fragment(){
 vec3 p=local_position; vec3 n=abs(local_normal);
 float x=n.x>n.z?p.z:p.x;
 float row=floor(p.y/0.24); vec2 brick=vec2(x/0.58+mod(row,2.0)*0.5,p.y/0.24);
 vec2 cell=fract(brick); float mortar=step(cell.x,0.045)+step(cell.y,0.065);
 float shade=fract(sin(dot(floor(brick),vec2(12.9898,78.233)))*43758.5453);
 ALBEDO=mix(tint.rgb*(0.88+shade*0.18),tint.rgb*0.65+vec3(0.12),clamp(mortar,0.0,1.0));
 ROUGHNESS=0.92; ALPHA=opacity;
}"""
	var material:=ShaderMaterial.new(); material.shader=shader; material.set_shader_parameter("tint",color); material.set_shader_parameter("opacity",1.0); masonry[key]=material
	return material

func box(size: Vector3, at: Vector3, color: Color, basis: Basis=Basis.IDENTITY) -> void:
	var key:=color.to_html()
	if not batches.has(key): batches[key]={"color":color,"transforms":[]}
	batches[key].transforms.append(Transform3D(basis*Basis.from_scale(size),at))

func build(parent: Node3D, recipe: Dictionary, index: int) -> Node3D:
	root=Node3D.new(); root.name="ReferenceArchitecture"; parent.add_child(root)
	var kind:="house" if recipe.roof or Map.lot_districts[index]=="GROVE" or (Map.lot_districts[index]=="RESIDENTIAL" and recipe.height<=6) else "industrial" if recipe.chimneys else "office" if Map.lot_districts[index]=="DOWNTOWN" and index%3==0 else "apartment"
	for poi in Map.pois:
		if poi.footprint==Map.lots[index]: kind={"Fire Station":"fire","Police Station":"police","Medical Station":"medical","Bank":"office","School":"school"}.get(poi.kind,"apartment")
	root.set_meta("architecture_type",kind)
	var wings: Array=recipe.wings
	if not recipe.interior.is_empty(): wings=[[Vector3(recipe.size.x,recipe.height,recipe.size.y),Vector3.ZERO,recipe.color]]
	for wing in wings:
		var wing_kind: String="fire_tower" if kind=="fire" and wing[0].x<recipe.size.x*.3 else kind
		_wing(wing[0],wing[1],wing_kind,index)
	for batch in batches.values():
		var multi:=MultiMesh.new(); multi.transform_format=MultiMesh.TRANSFORM_3D; multi.mesh=BoxMesh.new(); multi.instance_count=batch.transforms.size()
		for i in range(batch.transforms.size()): multi.set_instance_transform(i,batch.transforms[i])
		var node:=MultiMeshInstance3D.new(); node.multimesh=multi; node.material_override=G.shared_material(batch.color); root.add_child(node)
	return root

func _wing(size: Vector3, base: Vector3, kind: String, index: int) -> void:
	var trim:=Color("b8b2a3"); var dark:=Color("343a3c"); var glass:=Color("354e58"); var brick:=Color(BRICKS[posmod(index,BRICKS.size())])
	if kind in ["fire","fire_tower","police"]: brick=Color("865744")
	if kind=="house" and index%3!=0: brick=[Color("aaa493"),Color("8d998e"),Color("929d9f")][index%3]
	if kind in ["office","medical"]: brick=Color("858b8a")
	var roof_rise:=minf(2.1,size.y*.25) if kind=="house" else 0.0
	var wall_height:=size.y-roof_rise
	var wall:=G.box(root,Vector3(size.x,wall_height,size.z),base+Vector3(0,wall_height*.5,0),brick)
	wall.material_override=brick_material(brick); wall.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	box(Vector3(size.x+.15,.30,size.z+.15),base+Vector3(0,.15,0),Color("777872"))
	var floors:=maxi(1,int(round(wall_height/3.1))); var storey:=wall_height/floors
	if kind=="house": _gable(size,base,wall_height,roof_rise,dark)
	else:
		box(Vector3(size.x,.12,size.z),base+Vector3(0,wall_height+.03,0),dark)
		for side in [-1,1]:
			box(Vector3(size.x+.18,.40,.20),base+Vector3(0,wall_height+.20,side*size.z*.5),trim)
			box(Vector3(.20,.40,size.z),base+Vector3(side*size.x*.5,wall_height+.20,0),trim)
		for unit in range(clampi(int(size.x/5),1,3)):
			var p:=base+Vector3((unit-(clampi(int(size.x/5),1,3)-1)*.5)*3,wall_height+.5,-size.z*.16)
			box(Vector3(1.3,.8,1.1),p,Color("858984")); box(Vector3(1.4,.08,1.2),p+Vector3(0,.44,0),trim)
			for slat in range(5): box(Vector3(1.06,.045,.03),p+Vector3(0,(slat-2)*.12,.56),dark)
			var fan:=G.cylinder(root,.38,.03,p+Vector3(0,.50,0),dark,16); fan.name="RoofVent"
		box(Vector3(minf(size.x*.18,3),.16,minf(size.z*.16,2.4)),base+Vector3(size.x*.25,wall_height+.14,size.z*.2),Color("6f7778"))
	for side in range(4):
		var basis:=Basis(Vector3.UP,side*PI*.5)
		var span:=size.x if side%2==0 else size.z; var depth: float=(size.z if side%2==0 else size.x)*.5
		var columns:=maxi(2,int(span/(2.1 if kind in ["office","medical"] else 2.9)))
		var spacing:=span/(columns+1)
		for floor_index in range(floors):
			var band_y: float=(floor_index+1)*storey
			if kind in ["office","medical"] or floor_index==floors-1:
				box(Vector3(span+.12,.14,.16),base+basis*Vector3(0,band_y,depth+.045),trim,basis)
			for col in range(columns):
				var x: float=(col-(columns-1)*.5)*spacing
				if side==0 and floor_index==0 and absf(x)<1.2: continue
				if side==0 and kind in ["police","medical"] and absf(x)<minf(span*.14,2.6): continue
				if kind=="fire" and side==0 and floor_index==0: continue
				var y: float=floor_index*storey+storey*.56
				var w:=minf(spacing*.62,1.35); var h:=minf(1.6,storey*.59)
				if kind in ["office","medical"]: w=spacing*.86; h=storey*.76
				box(Vector3(w+.18,h+.18,.09),base+basis*Vector3(x,y,depth+.045),trim,basis)
				box(Vector3(w,h,.045),base+basis*Vector3(x,y,depth+.10),glass.lightened(.06 if (col+floor_index)%3==0 else 0),basis)
				box(Vector3(.045,h,.04),base+basis*Vector3(x,y,depth+.13),dark,basis)
				box(Vector3(w,.045,.04),base+basis*Vector3(x,y-.12,depth+.13),dark,basis)
				box(Vector3(w+.28,.10,.23),base+basis*Vector3(x,y-h*.5-.08,depth+.10),trim,basis)
				if kind=="apartment" and floor_index>0 and col%3==1:
					box(Vector3(w+.45,.12,.62),base+basis*Vector3(x,y-h*.5-.13,depth+.27),trim,basis)
					box(Vector3(w+.4,.06,.06),base+basis*Vector3(x,y-h*.5+.65,depth+.55),dark,basis)
					for bar in range(7): box(Vector3(.035,.75,.035),base+basis*Vector3(x+(bar-3)*(w+.3)/6,y-h*.5+.28,depth+.55),dark,basis)
		# Stone piers frame the facade, rather than scaffolding-like bars on every floor.
		for edge in [-1,1]:
			box(Vector3(.32,wall_height,.16),base+basis*Vector3(edge*(span*.5-.16),wall_height*.5,depth+.05),trim,basis)
		if kind in ["office","medical"]:
			for col in range(columns+1):
				var x: float=(col-columns*.5)*spacing
				box(Vector3(.12,wall_height,.12),base+basis*Vector3(x,wall_height*.5,depth+.16),trim,basis)
		if side==0:
			if kind in ["police","medical"]:
				box(Vector3(minf(span*.28,5.2),wall_height,.04),base+Vector3(0,wall_height*.5,depth+.025),trim)
				if kind=="police":
					box(Vector3(.85,1.05,.12),base+Vector3(0,wall_height-1.2,depth+.34),Color("294a66"))
					box(Vector3(.45,.45,.13),base+Vector3(0,wall_height-1.2,depth+.42),Color("c3a04f"),Basis(Vector3.FORWARD,PI*.25))
			if kind=="fire":
				for bay in range(clampi(int(span/4.5),3,4)):
					var count:=clampi(int(span/4.5),3,4); var x: float=(bay-(count-1)*.5)*(span/count)
					box(Vector3(span/count-.25,2.2,.10),base+Vector3(x,1.1,depth+.09),Color("843c32"))
					for slat in range(7): box(Vector3(span/count-.30,.035,.03),base+Vector3(x,.25+slat*.28,depth+.16),dark)
					box(Vector3(span/count-.65,.42,.05),base+Vector3(x,1.55,depth+.18),glass)
					for edge in [-1,1]: box(Vector3(.12,.85,.12),base+Vector3(x+edge*(span/count-.3)*.5,.42,depth+.5),Color("d2ab43"))
			else:
				box(Vector3(1.45,2.15,.1),base+Vector3(0,1.07,depth+.10),glass)
				box(Vector3(.06,2.15,.08),base+Vector3(0,1.07,depth+.17),trim)
				box(Vector3(2.2,.18,.80),base+Vector3(0,2.32,depth+.30),trim)
				box(Vector3(2.1,.14,.65),base+Vector3(0,.07,depth+.28),trim)
			if kind in ["fire","police","medical","school"]:
				box(Vector3(minf(span-1,8),.65,.12),base+Vector3(0,2.9,depth+.13),trim)
				var label:=G.label(root,{"fire":"FIRE DEPARTMENT","police":"POLICE","medical":"MEDICAL CENTER","school":"SCHOOL"}[kind],base+Vector3(0,2.92,depth+.22),Color("222e37"),40,.009)
				label.billboard=BaseMaterial3D.BILLBOARD_DISABLED; label.outline_size=0
			if kind=="medical":
				box(Vector3(1.8,1.8,.12),base+Vector3(0,wall_height-1.3,depth+.18),Color("e4e3db"))
				box(Vector3(.35,1.25,.08),base+Vector3(0,wall_height-1.3,depth+.28),Color("ab3b35"))
				box(Vector3(1.25,.35,.08),base+Vector3(0,wall_height-1.3,depth+.29),Color("ab3b35"))
			for x in [-span*.36,span*.36]:
				if kind=="fire": continue
				box(Vector3(1.3,.32,.55),base+Vector3(x,.16,depth+.3),Color("6d7065"))
				box(Vector3(1.15,.55,.48),base+Vector3(x,.57,depth+.3),Color("475a39"))

func _gable(size: Vector3, base: Vector3, wall: float, rise: float, color: Color) -> void:
	var tool:=SurfaceTool.new(); tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w:=size.x*.5+.18; var d:=size.z*.5+.18
	var points: Array[Vector3]=[Vector3(-w,wall,-d),Vector3(w,wall,-d),Vector3(w,wall,d),Vector3(-w,wall,d),Vector3(0,wall+rise,-d),Vector3(0,wall+rise,d)]
	for tri in [[0,4,5],[0,5,3],[4,1,2],[4,2,5],[0,1,4],[3,5,2]]:
		for i in tri: tool.add_vertex(base+points[i])
	tool.generate_normals(); var mesh:=MeshInstance3D.new(); mesh.mesh=tool.commit(); mesh.material_override=G.material(color); mesh.material_override.cull_mode=BaseMaterial3D.CULL_DISABLED; root.add_child(mesh)
