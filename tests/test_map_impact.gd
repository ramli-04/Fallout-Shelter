extends SceneTree
const Blast=preload("res://scripts/blast_model.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var size:=Vector2(14000,9000); var center:=Vector2(500,700)
	var config={"impact_position":[center.x,center.y],"radius":Blast.map_coverage_radius(center,size,.9),"zone_fractions":[.25,.6,.9],"zone_damage":[1.0,.6,.2],"severity":1.0}
	for corner in [Vector2.ZERO,Vector2(size.x,0),size,Vector2(0,size.y)]: assert(Blast.intensity(corner,config)>0)
	var effect=preload("res://scripts/three_d/impact_3d.gd").new(); effect.radius=config.radius; root.add_child(effect); effect.set_process(false); effect._process(6)
	assert(effect.wave.scale.x>=config.radius and is_equal_approx(effect.wave.scale.y,1.0))
	assert(effect.dust.scale.x>config.radius*.9)
	effect.queue_free(); await process_frame; print("Map impact: corner coverage and wave expansion passed"); quit()
