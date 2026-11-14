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
	return preload("res://scripts/three_d/street_surface_art.gd").surface_material("pavement")

static func plain_asphalt_material() -> ShaderMaterial:
	return preload("res://scripts/three_d/street_surface_art.gd").surface_material("asphalt")
