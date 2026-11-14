extends SceneTree
func _initialize() -> void:
	var art=preload("res://scripts/three_d/reference_sprite_catalog.gd"); art.load_collection()
	var count:=0
	for kind in art.collection.assets:
		var record: Dictionary=art.collection.assets[kind]
		var atlas:=AtlasTexture.new(); atlas.atlas=art.atlas(kind); atlas.region=art.REGIONS[kind]; atlas.filter_clip=true
		var file: String="res://assets/"+record.category+"/"+kind+".tres"
		assert(ResourceSaver.save(atlas,file)==OK); count+=1
		var scene_folder: String="res://scenes/ReferenceAssets/"+record.category.get_file()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scene_folder))
		var root_node:=Node3D.new(); root_node.name=kind
		if record.category.begins_with("buildings/"):
			var sprites=preload("res://scripts/three_d/building_sprites.gd")
			var placement:=sprites.registration(kind,atlas.region,Vector2(12,10))
			var node:=MeshInstance3D.new(); var quad:=QuadMesh.new(); quad.size=Vector2(placement.width,placement.height); node.mesh=quad; node.position.y=placement.anchor; node.material_override=sprites.material("sheet:"+kind+":0"); root_node.add_child(node); node.owner=root_node
		else:
			var width:=5.0 if record.category.ends_with("Trees") else 1.5
			var node: MeshInstance3D=art.sprite(root_node,kind,width); node.owner=root_node
		var packed:=PackedScene.new(); assert(packed.pack(root_node)==OK); assert(ResourceSaver.save(packed,scene_folder+"/"+kind+".tscn")==OK); root_node.free()
	for kind in ["road_damaged","road_pothole","accessible_paving","loading_paving"]:
		var atlas:=AtlasTexture.new(); atlas.atlas=art.atlas(kind); atlas.region=art.REGIONS[kind]; atlas.filter_clip=true; assert(ResourceSaver.save(atlas,"res://assets/Roads/"+kind+".tres")==OK)
	var roads={"straight_2lane":[18,649,161,98],"straight_4lane":[184,648,161,100],"intersection_4way":[353,654,154,92],"junction_T":[513,653,144,88],"corner":[675,658,146,86],"curve":[829,658,145,87],"sidewalk":[25,794,149,88],"crosswalk":[186,794,148,88],"turning_lane":[343,790,164,91],"driveway":[513,793,148,87],"wide_pavement":[674,792,142,84],"median":[832,791,154,91],"stop_line":[988,790,156,94],"lane_markings":[1155,791,152,94]}
	if FileAccess.file_exists("res://resources/road_ground_collection.json"): roads={}
	for name in roads:
		var r: Array=roads[name]; var atlas:=AtlasTexture.new(); atlas.atlas=load(art.STREETS); atlas.region=Rect2(r[0],r[1],r[2],r[3]); atlas.filter_clip=true; assert(ResourceSaver.save(atlas,"res://assets/Roads/"+name+".tres")==OK)
	if FileAccess.file_exists("res://resources/road_ground_collection.json"): preload("res://scripts/three_d/road_ground_art.gd").export_resources()
	var grass=preload("res://scripts/three_d/grass_material.gd").material(); assert(ResourceSaver.save(grass,"res://assets/Nature/Grass/patchy_grass.tres")==OK)
	print("Organized reference assets: ",count," atlas cutouts, road textures and grass material"); quit()
