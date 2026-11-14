extends SceneTree
const Art=preload("res://scripts/three_d/reference_sprite_catalog.gd")
const Sprites=preload("res://scripts/three_d/building_sprites.gd")
func _initialize() -> void:
	var checks:=0
	for kind in Art.REGIONS:
		var texture:=Sprites.texture("sheet:"+kind+":0")
		assert(texture!=null and texture.get_width()>0)
		assert(Rect2(Vector2.ZERO,texture.get_size()).encloses(Art.REGIONS[kind])); checks+=1
	var a:=Sprites.material("sheet:house0:0"); var b:=Sprites.material("sheet:police:0")
	assert(a.shader==b.shader and a.get_shader_parameter("artwork") is Texture2D)
	print("Reference texture loading: %d atlas regions and shared shader passed"%checks); quit()
