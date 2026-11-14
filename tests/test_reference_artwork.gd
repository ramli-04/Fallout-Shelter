extends SceneTree
const Art=preload("res://scripts/three_d/reference_sprite_catalog.gd")
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1; printerr("FAIL: "+label)
func run() -> void:
	var world:=Node3D.new(); root.add_child(world)
	for kind in Art.REGIONS:
		var texture: Texture2D=Art.atlas(kind)
		check(texture!=null,"atlas "+kind)
		check(Rect2(Vector2.ZERO,texture.get_size()).encloses(Art.REGIONS[kind]),"bounds "+kind)
	for path in [Art.CIVIC,Art.STREETS]:
		check((load(path) as Texture2D).get_image().get_pixel(0,0).a<.1,"transparent atlas background")
	var mesh:=Art.sprite(world,"medical",12)
	var shared:=mesh.material_override
	var fade=preload("res://scripts/three_d/material_fader.gd").new()
	fade.configure(world,{"occlusion_alpha":.2,"fade_seconds":.01}); fade.set_obscured(true)
	await fade.tween.finished
	check(mesh.material_override!=shared,"fading isolates shared atlas material")
	check(is_equal_approx(mesh.material_override.get_shader_parameter("opacity"),.2),"artwork fades")
	check(is_equal_approx(shared.get_shader_parameter("opacity"),1.0),"other buildings stay opaque")
	fade.set_obscured(false); await fade.tween.finished
	check(mesh.material_override==shared,"restores shared material")
	check(Art.road_material("sidewalk",Color.WHITE).get_shader_parameter("pavement"),"paving surface")
	check(not Art.road_material("asphalt",Color.WHITE).get_shader_parameter("pavement"),"road surface")
	world.queue_free(); await process_frame
	print("Reference artwork: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)
