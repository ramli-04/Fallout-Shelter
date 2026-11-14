extends SceneTree
const Art=preload("res://scripts/three_d/reference_sprite_catalog.gd")
func _initialize() -> void:
	Art.load_collection(); var checks:=0
	for kind in Art.collection.assets:
		var data: Dictionary=Art.collection.assets[kind]
		var texture: Texture2D=load("res://assets/"+data.category+"/"+kind+".tres")
		assert(texture is AtlasTexture and texture.region==Art.REGIONS[kind]); checks+=1
		var scene: PackedScene=load("res://scenes/ReferenceAssets/"+data.category.get_file()+"/"+kind+".tscn")
		assert(scene!=null); var instance:=scene.instantiate(); assert(instance.get_child_count()>0); instance.free(); checks+=1
	for kind in ["straight_2lane","straight_4lane","intersection_4way","junction_T","corner","curve","sidewalk","wide_pavement","crosswalk","driveway","median","stop_line"]:
		assert(load("res://assets/Roads/"+kind+".tres") is AtlasTexture); checks+=1
	assert(load("res://assets/Nature/Grass/patchy_grass.tres") is ShaderMaterial); checks+=1
	print("Organized reference collection: %d checks passed"%checks); quit()
