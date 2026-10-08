extends Node3D
## Read-only avatar. Fixed-clock simulation positions own motion, never render/physics timing.
const Coordinates = preload("res://scripts/three_d/world_coordinates.gd")
const Geometry = preload("res://scripts/three_d/geometry.gd")
var record: Dictionary = {}
var is_selected := false
var body: Node3D
var bean: MeshInstance3D
var selection_area: Area3D
var selection_ring: MeshInstance3D
var id_label: Label3D
var navigator: NavigationAgent3D
var heading := 0.0
var visual_time := 0.0
var bob_height := 0.07
var active := false
var navigation_next := Vector3.ZERO
var navigation_reachable := false
var last_state := ""
var unique_color := Color.WHITE

func configure(data: Dictionary) -> void:
	record = data
	position = Coordinates.to_world(data["position"])

func _ready() -> void:
	navigator = $NavigationAgent3D
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/visual_3d.json"))
	bob_height = float(settings["agent_bob_height"])
	var index := int(str(record.get("id", "A001")).substr(1))
	unique_color = Color.from_hsv(fmod(index*0.618034,1.0),0.48,0.95)
	body = Node3D.new()
	add_child(body)
	bean = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.52
	capsule.height = 2.0
	capsule.radial_segments = 12
	capsule.rings = 4
	bean.mesh = capsule
	bean.position.y = 1.0
	bean.material_override = Geometry.material(unique_color)
	body.add_child(bean)
	for side in [-1,1]:
		var eye := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.065
		sphere.height = 0.13
		sphere.radial_segments = 8
		sphere.rings = 4
		eye.mesh = sphere
		eye.position = Vector3(side*0.17,1.45,-0.45)
		eye.material_override = Geometry.material(Color("203442"))
		body.add_child(eye)
	if record.get("role", "") == "Authority":
		Geometry.cylinder(body,0.48,0.17,Vector3(0,1.94,0),Color("294c6a"))
	selection_ring = Geometry.ring(self,0.9,Color("ffe8a3"))
	selection_ring.position.y = 0.035
	selection_ring.visible = false
	id_label = Geometry.label(self,record.get("id", ""),Vector3(0,2.7,0),Color.WHITE,36,0.022)
	id_label.visible = false
	selection_area = Area3D.new()
	selection_area.collision_layer = 4
	selection_area.collision_mask = 0
	selection_area.set_meta("entity_owner",self)
	var collider := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.8
	shape.height = 2.6
	collider.shape = shape
	collider.position.y = 1.1
	selection_area.add_child(collider)
	add_child(selection_area)
	update_visual(record,1,false)

func set_selected(value: bool) -> void:
	is_selected = value
	selection_ring.visible = value and visible
	id_label.visible = value and visible
	_update_color()

func update_visual(data: Dictionary, alpha: float, running: bool, time: float = 0) -> void:
	record = data
	active = running
	visual_time = time
	var previous: Vector2 = data.get("previous_position",data["position"])
	var point: Vector2 = previous.lerp(data["position"],clampf(alpha,0,1)) if running else data["position"]
	position = Coordinates.to_world(point)
	var direction: Vector2 = data["position"]-previous
	if not direction.is_zero_approx():
		heading = atan2(-direction.x,-direction.y)
	visible = data["state"] != "SHELTERED"
	if selection_area != null:
		selection_area.collision_layer = 4 if visible else 0
	if body == null: return
	selection_ring.visible = is_selected and visible
	id_label.visible = is_selected and visible
	if last_state != data["state"]:
		last_state = data["state"]
		_update_color()
	var route: PackedVector2Array = data["route"]
	var index: int = data["route_index"]
	if visible and index < route.size() and data["state"] == "MOVING":
		var target := Coordinates.to_world(route[index])
		if not navigator.target_position.is_equal_approx(target):
			navigator.target_position = target

func _update_color() -> void:
	if bean == null: return
	var color := unique_color
	if record["state"] == "EXPOSED": color = Color("ee6960")
	elif record["state"] == "REJECTED": color = Color("efad4d")
	elif record["state"] in ["DELAYED", "FROZEN", "STAYING_HOME", "WAITING_ROAD"]: color = unique_color.lerp(Color("b294d7"),0.5)
	elif record["state"] == "HELPING": color = Color("eae29c")
	if is_selected: color = color.lightened(0.25)
	bean.material_override.albedo_color = color

func _process(delta: float) -> void:
	if body == null: return
	body.rotation.y = lerp_angle(body.rotation.y,heading,1-exp(-12*delta))
	body.position.y = sin(visual_time*5+int(str(record["id"]).substr(1)))*bob_height if active and record["state"] == "MOVING" else 0.0

func _physics_process(_delta: float) -> void:
	if not visible or record.get("state", "") != "MOVING" or not active: return
	if NavigationServer3D.map_get_iteration_id(get_world_3d().navigation_map) == 0: return
	# Maintain Godot's 3D path state for the current authoritative road waypoint.
	# Do not displace the avatar a second time or feed physics timing back into decisions.
	if not navigator.is_navigation_finished():
		navigation_next = navigator.get_next_path_position()
		navigation_reachable = navigator.is_target_reachable()
