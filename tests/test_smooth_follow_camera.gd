extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var rig=preload("res://scenes/three_d/camera_rig.tscn").instantiate(); root.add_child(rig)
	rig.focus_at(Vector3(100,.18,100)); rig.snap(); var start: Vector3=rig.position
	rig.focus_at(Vector3(130,.18,120)); rig.advance(1.0/60)
	assert(rig.position.distance_to(start)>0 and rig.position.distance_to(rig.target_focus)>1)
	for i in range(300): rig.advance(1.0/60)
	assert(rig.position.distance_to(rig.target_focus)<.001)
	assert(absf(rig.settle_sway)<.0001)
	# Moving targets are followed continuously without snapping to each new position.
	for i in range(120):
		rig.focus_at(Vector3(130+i*.05,.18,120)); rig.advance(1.0/60)
	assert(rig.position.distance_to(rig.target_focus)<2)
	rig.snap(); assert(rig.focus_velocity==Vector3.ZERO and rig.settle_sway==0)
	var positions: Array=[]
	for rate in [30,60,144]:
		rig.focus_at(start); rig.snap(); rig.focus_at(Vector3(130,.18,120))
		for i in range(rate): rig.advance(1.0/rate)
		positions.append(rig.position)
	assert(positions[0].distance_to(positions[2])<.001)
	rig.queue_free(); await process_frame; print("Smooth follow: movement, settling, snap and frame-rate checks passed"); quit()
