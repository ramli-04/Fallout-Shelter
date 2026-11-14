extends Node3D
## Reusable orbit/pan rig. Receives camera intent only; has no simulation or RNG reference.
var settings: Dictionary = {}
var camera: Camera3D
var pivot: Node3D
var target_focus := Vector3.ZERO
var target_yaw := 45.0
var target_pitch := 30.0
var target_distance := 145.0
var distance := 145.0
var yaw := 45.0
var pitch := 30.0
var focus_velocity:=Vector3.ZERO
var settle_sway:=0.0
var settle_velocity:=0.0

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
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = settings["overview_distance"]
	reset_overview()

static func validate(data: Dictionary) -> String:
	for key in ["move_speed", "zoom_sensitivity", "smoothing", "min_distance", "max_distance", "overview_distance", "isometric_yaw_degrees", "isometric_pitch_degrees"]:
		if not data.has(key) or not (data[key] is int or data[key] is float) or not is_finite(float(data[key])):
			return "Missing or invalid number: " + key
	for key in ["move_speed", "zoom_sensitivity", "smoothing", "min_distance"]:
		if data[key] <= 0:
			return key + " must be positive."
	if data["min_distance"] >= data["max_distance"] or data["overview_distance"] < data["min_distance"] or data["overview_distance"] > data["max_distance"]:
		return "Zoom distances must contain the overview between minimum and maximum."
	if data["isometric_pitch_degrees"] < 20 or data["isometric_pitch_degrees"] > 70:
		return "Isometric pitch must stay between 20 and 70 degrees."
	if data["zoom_sensitivity"] >= 0.9:
		return "Invalid zoom sensitivity."
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
	var bounds: Vector2 = preload("res://scripts/city_map.gd").MAP_SIZE * 0.1
	settings["bounds_max"] = [bounds.x, bounds.y]
	settings["max_distance"] = bounds.x*1.35
	camera.far = bounds.x*9.0
	settings["overview_distance"] = bounds.x * 1.12
	target_focus = Vector3(bounds.x/2, 0.18, bounds.y/2)
	target_yaw = float(settings.get("isometric_yaw_degrees",45.0))
	target_pitch = float(settings.get("isometric_pitch_degrees",30.0))
	target_distance = settings["overview_distance"]
	snap()

func focus_at(point: Vector3) -> void:
	if settings.is_empty(): return
	target_focus = Vector3(point.x,point.y,point.z)
	_clamp_focus()

func pan(direction: Vector2, delta: float) -> void:
	if direction.is_zero_approx() or settings.is_empty(): return
	var basis := Basis(Vector3.UP, deg_to_rad(target_yaw))
	var horizontal := basis * Vector3(direction.x,0,direction.y)
	target_focus += horizontal.normalized()*settings["move_speed"]*delta*clampf(target_distance/settings["overview_distance"],0.3,2.0)
	_clamp_focus()
	_ground_focus()

func drag_pan(relative: Vector2, viewport_height: float) -> void:
	if settings.is_empty(): return
	var units_per_pixel := target_distance/maxf(1,viewport_height)
	var basis := Basis(Vector3.UP,deg_to_rad(target_yaw))
	target_focus += basis * Vector3(-relative.x,0,-relative.y/maxf(0.3,sin(deg_to_rad(target_pitch)))) * units_per_pixel
	_clamp_focus()
	_ground_focus()

func rotate_drag(relative: Vector2) -> void:
	# Keep the isometric basis stable so roads and navigation remain visually consistent.
	return

func zoom_steps(steps: float) -> void:
	if settings.is_empty(): return
	target_distance = clampf(target_distance*pow(1-settings["zoom_sensitivity"],steps),settings["min_distance"],settings["max_distance"])

func _clamp_focus() -> void:
	target_focus.x = clampf(target_focus.x,settings["bounds_min"][0],settings["bounds_max"][0])
	target_focus.z = clampf(target_focus.z,settings["bounds_min"][1],settings["bounds_max"][1])

func _ground_focus() -> void:
	target_focus.y = preload("res://scripts/city_map.gd").elevation(Vector2(target_focus.x,target_focus.z)/0.1) + 0.18

func advance(delta: float) -> void:
	if settings.is_empty(): return
	var blend := 1-exp(-settings["smoothing"]*maxf(0,delta))
	# Exact critically damped spring: smooth follow with stable behaviour at low FPS.
	var dt:=maxf(0,delta); var omega:=float(settings.get("follow_response",8.0))
	var offset:=position-target_focus; var decay:=exp(-omega*dt)
	var impulse:=focus_velocity+offset*omega
	var previous_velocity:=focus_velocity
	position=target_focus+(offset+impulse*dt)*decay
	focus_velocity=(focus_velocity-impulse*omega*dt)*decay
	# A small damped pitch response to deceleration, capped below a quarter degree.
	var braking:=clampf((previous_velocity.length()-focus_velocity.length())*.015,-.1,.1)
	settle_velocity+=braking
	var sway_impulse:=settle_velocity+settle_sway*10.0
	settle_sway=(settle_sway+sway_impulse*dt)*exp(-10.0*dt)
	settle_velocity=(settle_velocity-sway_impulse*10.0*dt)*exp(-10.0*dt)
	settle_sway=clampf(settle_sway,-.004,.004)
	if position.distance_squared_to(target_focus)<.000001 and focus_velocity.length_squared()<.000001:
		position=target_focus; focus_velocity=Vector3.ZERO
	yaw = rad_to_deg(lerp_angle(deg_to_rad(yaw),deg_to_rad(target_yaw),blend))
	pitch = lerpf(pitch,target_pitch,blend)
	distance = lerpf(distance,target_distance,blend)
	camera.size = distance
	_apply_transform()

func snap() -> void:
	if settings.is_empty(): return
	position = target_focus
	focus_velocity=Vector3.ZERO; settle_sway=0; settle_velocity=0
	yaw = target_yaw
	pitch = target_pitch
	distance = target_distance
	camera.size = distance
	_apply_transform()

func _apply_transform() -> void:
	rotation.y = deg_to_rad(yaw)
	pivot.rotation.x = deg_to_rad(-pitch)+settle_sway
	camera.position = Vector3(0,0,distance)
