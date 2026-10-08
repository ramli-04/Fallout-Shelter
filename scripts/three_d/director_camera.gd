extends Node3D
## Reusable orbit/pan rig. Receives camera intent only; has no simulation or RNG reference.
var settings: Dictionary = {}
var camera: Camera3D
var pivot: Node3D
var target_focus := Vector3.ZERO
var target_yaw := 45.0
var target_pitch := 45.0
var target_distance := 145.0
var distance := 145.0
var yaw := 45.0
var pitch := 45.0

func _ready() -> void:
	pivot = $Pivot
	camera = $Pivot/Camera3D
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://resources/visual_3d.json"))
	if not data is Dictionary or not data.get("camera") is Dictionary:
		push_error("visual_3d.json must contain a camera object.")
		return
	settings = data["camera"]
	var error := validate(settings)
	if not error.is_empty():
		push_error("3D camera configuration: " + error)
		settings.clear()
		return
	camera.fov = settings["field_of_view"]
	reset_overview()

static func validate(data: Dictionary) -> String:
	for key in ["move_speed", "zoom_sensitivity", "rotation_sensitivity", "tilt_sensitivity", "smoothing", "min_distance", "max_distance", "overview_distance", "overview_yaw_degrees", "overview_pitch_degrees", "min_pitch_degrees", "max_pitch_degrees", "field_of_view"]:
		if not data.has(key) or not (data[key] is int or data[key] is float) or not is_finite(float(data[key])):
			return "Missing or invalid number: " + key
	for key in ["move_speed", "zoom_sensitivity", "rotation_sensitivity", "tilt_sensitivity", "smoothing", "min_distance"]:
		if data[key] <= 0:
			return key + " must be positive."
	if data["min_distance"] >= data["max_distance"] or data["overview_distance"] < data["min_distance"] or data["overview_distance"] > data["max_distance"]:
		return "Zoom distances must contain the overview between minimum and maximum."
	if data["min_pitch_degrees"] < 20 or data["max_pitch_degrees"] > 80 or data["min_pitch_degrees"] > data["overview_pitch_degrees"] or data["overview_pitch_degrees"] > data["max_pitch_degrees"]:
		return "Pitch must stay between 20 and 80 degrees and contain the overview."
	if data["field_of_view"] <= 10 or data["field_of_view"] >= 100 or data["zoom_sensitivity"] >= 0.9:
		return "Invalid field of view or zoom sensitivity."
	for key in ["bounds_min", "bounds_max", "overview_focus"]:
		if not data.has(key) or not data[key] is Array or data[key].size() != 2:
			return key + " must have two coordinates."
		for value in data[key]:
			if not (value is float or value is int) or not is_finite(float(value)):
				return "Invalid coordinate in " + key
	for i in range(2):
		if data["bounds_min"][i] >= data["bounds_max"][i] or data["overview_focus"][i] < data["bounds_min"][i] or data["overview_focus"][i] > data["bounds_max"][i]:
			return "Camera bounds must contain overview_focus."
	return ""

func reset_overview() -> void:
	if settings.is_empty(): return
	target_focus = Vector3(settings["overview_focus"][0], 0.18, settings["overview_focus"][1])
	target_yaw = settings["overview_yaw_degrees"]
	target_pitch = settings["overview_pitch_degrees"]
	target_distance = settings["overview_distance"]
	snap()

func focus_at(point: Vector3) -> void:
	if settings.is_empty(): return
	target_focus = Vector3(point.x,0.18,point.z)
	_clamp_focus()

func pan(direction: Vector2, delta: float) -> void:
	if direction.is_zero_approx() or settings.is_empty(): return
	var basis := Basis(Vector3.UP, deg_to_rad(target_yaw))
	var horizontal := basis * Vector3(direction.x,0,direction.y)
	target_focus += horizontal.normalized()*settings["move_speed"]*delta*clampf(target_distance/settings["overview_distance"],0.3,2.0)
	_clamp_focus()

func drag_pan(relative: Vector2, viewport_height: float) -> void:
	if settings.is_empty(): return
	var units_per_pixel := 2*target_distance*tan(deg_to_rad(camera.fov/2))/maxf(1,viewport_height)
	var basis := Basis(Vector3.UP,deg_to_rad(target_yaw))
	target_focus += basis * Vector3(-relative.x,0,-relative.y/maxf(0.3,sin(deg_to_rad(target_pitch)))) * units_per_pixel
	_clamp_focus()

func rotate_drag(relative: Vector2) -> void:
	if settings.is_empty(): return
	target_yaw = wrapf(target_yaw-relative.x*settings["rotation_sensitivity"],-180,180)
	target_pitch = clampf(target_pitch+relative.y*settings["tilt_sensitivity"],settings["min_pitch_degrees"],settings["max_pitch_degrees"])

func zoom_steps(steps: float) -> void:
	if settings.is_empty(): return
	target_distance = clampf(target_distance*pow(1-settings["zoom_sensitivity"],steps),settings["min_distance"],settings["max_distance"])

func _clamp_focus() -> void:
	target_focus.x = clampf(target_focus.x,settings["bounds_min"][0],settings["bounds_max"][0])
	target_focus.z = clampf(target_focus.z,settings["bounds_min"][1],settings["bounds_max"][1])

func advance(delta: float) -> void:
	if settings.is_empty(): return
	var blend := 1-exp(-settings["smoothing"]*maxf(0,delta))
	position = position.lerp(target_focus,blend)
	yaw = rad_to_deg(lerp_angle(deg_to_rad(yaw),deg_to_rad(target_yaw),blend))
	pitch = lerpf(pitch,target_pitch,blend)
	distance = lerpf(distance,target_distance,blend)
	_apply_transform()

func snap() -> void:
	if settings.is_empty(): return
	position = target_focus
	yaw = target_yaw
	pitch = target_pitch
	distance = target_distance
	_apply_transform()

func _apply_transform() -> void:
	rotation.y = deg_to_rad(yaw)
	pivot.rotation.x = deg_to_rad(-pitch)
	camera.position = Vector3(0,0,distance)
