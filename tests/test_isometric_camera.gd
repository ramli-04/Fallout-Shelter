extends SceneTree

const CameraRig=preload("res://scenes/three_d/camera_rig.tscn")

var failures:=0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	if not value:
		failures+=1
		printerr("FAIL: "+label)

func run() -> void:
	var rig: Node3D=CameraRig.instantiate()
	root.add_child(rig)
	await process_frame
	check(rig.settings.size()>0,"camera configuration loads")
	check(rig.camera.projection==Camera3D.PROJECTION_ORTHOGONAL,"world camera uses orthographic projection")
	check(is_equal_approx(rig.camera.size,rig.target_distance),"orthographic zoom uses camera size")
	check(is_equal_approx(rig.target_yaw,45.0) and is_equal_approx(rig.target_pitch,35.264),"camera uses a fixed isometric viewing angle")
	var original_focus: Vector3=rig.target_focus
	rig.zoom_steps(1)
	check(rig.target_distance<rig.distance,"wheel zoom changes the orthographic view scale")
	rig.rotate_drag(Vector2(80,60))
	check(is_equal_approx(rig.target_yaw,45.0) and is_equal_approx(rig.target_pitch,35.264),"camera angle stays fixed during pointer drags")
	rig.drag_pan(Vector2(25,-10),600)
	check(rig.target_focus.distance_to(original_focus)>0,"drag pan moves the focus without changing world coordinates")
	rig.queue_free()
	await process_frame
	print("Isometric camera: %d failures"%failures)
	quit(1 if failures else 0)
