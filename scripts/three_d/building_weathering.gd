extends Node3D
## Cosmetic age only: no occupancy, damage, navigation, or simulation RNG writes.
const G = preload("res://scripts/three_d/geometry.gd")
var instance_total := 0

func configure(size: Vector2, height: float, seed_value: int) -> void:
	name = "Weathering"
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var stains: Array[Transform3D] = []
	var boards: Array[Transform3D] = []
	var rubble: Array[Transform3D] = []
	for side in range(4):
		var basis := Basis(Vector3.UP, side*PI/2)
		var width := size.x if side%2 == 0 else size.y
		var depth := (size.y if side%2 == 0 else size.x)*.5
		for i in range(maxi(1, int(width/3))):
			var x := rng.randf_range(-width*.42, width*.42)
			var y := rng.randf_range(.8, maxf(.9, height-.8))
			stains.append(Transform3D(basis*Basis.from_scale(Vector3(rng.randf_range(.3,1.1), rng.randf_range(.7,1.8), .035)), basis*Vector3(x,y,depth+.025)))
			# Board only upper windows; never visually seal an active ground-floor door.
			if height > 4 and i%3 == seed_value%3:
				for slant in [-1,1]:
					boards.append(Transform3D(basis*Basis(Vector3.BACK,slant*.3)*Basis.from_scale(Vector3(1.6,.17,.08)), basis*Vector3(x,4.0,depth+.20)))
	for i in range(5):
		var point := Vector3(rng.randf_range(-size.x*.35,size.x*.35),height+.12,rng.randf_range(-size.y*.35,size.y*.35))
		rubble.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU)*Basis.from_scale(Vector3(.35,.22,.5)),point))
	_batch(stains, Color("676554"))
	_batch(boards, Color("776048"))
	_batch(rubble, Color("88806c"))

func _batch(transforms: Array[Transform3D], color: Color) -> void:
	if transforms.is_empty(): return
	var node := MultiMeshInstance3D.new()
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = BoxMesh.new()
	batch.instance_count = transforms.size()
	for i in range(transforms.size()): batch.set_instance_transform(i,transforms[i])
	node.multimesh = batch
	node.material_override = G.material(color)
	node.visibility_range_end = 400
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	instance_total += transforms.size()
