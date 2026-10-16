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
var arms: Array[Node3D] = []
var legs: Array[Node3D] = []
var animation_clock := 0.0

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
	_create_human(index)
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

func _create_human(index: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(record.get("appearance_seed",index*917))
	var skins := [Color("e2b994"),Color("be8c68"),Color("916044"),Color("65432e"),Color("edcfb0"),Color("ab7854")]
	var skin: Color = skins[rng.randi_range(0,skins.size()-1)]
	var hair_colors := [Color("332a25"),Color("654a31"),Color("af854e"),Color("c6c0ae"),Color("251f1e")]
	var hair: Color = hair_colors[rng.randi_range(0,hair_colors.size()-1)]
	var authority: bool = record.get("role","") == "Authority"
	if authority: unique_color = Color("355a78")
	bean = Geometry.box(body,Vector3(0.70,0.73,0.40),Vector3(0,1.33,0),unique_color)
	Geometry.box(body,Vector3(0.56,0.22,0.35),Vector3(0,0.94,0),Color("34424d"))
	Geometry.cylinder(body,0.13,0.16,Vector3(0,1.75,0),skin)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.26
	head_mesh.height = 0.50
	head_mesh.radial_segments = 12
	head_mesh.rings = 6
	head.mesh = head_mesh
	head.material_override = Geometry.material(skin)
	head.position = Vector3(0,2.0,0)
	body.add_child(head)
	Geometry.box(body,Vector3(0.49,0.16,0.43),Vector3(0,2.20,0.035),hair)
	Geometry.box(body,Vector3(0.13,0.12,0.12),Vector3(0,1.99,-0.25),skin)
	for side in [-1,1]:
		Geometry.box(body,Vector3(0.08,0.07,0.035),Vector3(side*0.11,2.06,-0.235),Color("f4eadf"))
		Geometry.box(body,Vector3(0.035,0.045,0.035),Vector3(side*0.11,2.06,-0.257),Color("27292a"))
		var arm := Node3D.new()
		arm.position = Vector3(side*0.44,1.60,0)
		body.add_child(arm)
		Geometry.box(arm,Vector3(0.22,0.46,0.25),Vector3(0,-0.22,0),unique_color.darkened(0.08))
		Geometry.box(arm,Vector3(0.18,0.22,0.20),Vector3(0,-0.55,0),skin)
		arms.append(arm)
		var leg := Node3D.new()
		leg.position = Vector3(side*0.18,0.91,0)
		body.add_child(leg)
		Geometry.box(leg,Vector3(0.24,0.73,0.27),Vector3(0,-0.34,0),Color("34424d"))
		Geometry.box(leg,Vector3(0.28,0.19,0.43),Vector3(0,-0.78,-0.065),Color("303333"))
		legs.append(leg)
	if authority:
		Geometry.cylinder(body,0.30,0.15,Vector3(0,2.28,0),Color("294c6a"))
		Geometry.box(body,Vector3(0.53,0.05,0.45),Vector3(0,2.23,-0.08),Color("213b50"))
		Geometry.box(body,Vector3(0.12,0.17,0.025),Vector3(-0.18,1.46,-0.21),Color("d7c18a"))
	elif index%4 == 0:
		Geometry.box(body,Vector3(0.52,0.58,0.25),Vector3(0,1.30,0.31),unique_color.darkened(0.38))
	elif index%4 == 1:
		var skirt := Geometry.cylinder(body,0.41,0.58,Vector3(0,0.92,0),unique_color.darkened(0.18))
		skirt.mesh.top_radius = 0.26
	elif index%4 == 2:
		Geometry.cylinder(body,0.29,0.11,Vector3(0,2.28,0),unique_color.darkened(0.25))

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
	body.rotation.z = PI/2 if data.get("survival_status", "") == "DEAD" else 0.0
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
	if active: animation_clock += delta
	var phase := animation_clock + int(str(record["id"]).substr(1))*0.3
	var state: String = record["state"]
	var moving := active and state in ["MOVING","ROAMING","SCRAMBLING"]
	var walking := state == "ROAMING"
	var swing := sin(phase*(7.0 if walking else 12.0))*(0.35 if walking else 0.85) if moving else 0.0
	body.rotation.y = lerp_angle(body.rotation.y,heading,1-exp(-12*delta))
	body.rotation.x = -0.12 if moving and not walking else 0.0
	body.rotation.z = 0.0
	body.position.y = absf(sin(phase*12))*0.08 if moving else 0.0
	for i in range(legs.size()):
		legs[i].rotation.x = swing*(1 if i == 0 else -1)
		arms[i].rotation = Vector3(-swing*(1 if i == 0 else -1),0,0)
	if state == "DANCING":
		body.rotation.y = phase*1.7
		body.rotation.z = sin(phase*5)*0.18
		body.position.y = absf(sin(phase*6))*0.18
		for i in range(arms.size()):
			arms[i].rotation.z = (1 if i == 0 else -1)*(1.8+sin(phase*4)*0.5)
			legs[i].rotation.x = sin(phase*6+i*PI)*0.4
	elif state == "STAGGERED":
		body.rotation.z = sin(phase*18)*0.3
		for arm in arms: arm.rotation.x = 1.4
	elif state in ["HELPING","CHATTING"] or visual_time < record.get("push_animation_until",-1):
		for arm in arms: arm.rotation.x = 1.2+sin(phase*4)*0.18
	elif state == "FROZEN":
		for arm in arms: arm.rotation.x = 2.2
	if record.get("survival_status","") == "DEAD":
		body.rotation = Vector3(0,heading,PI/2)
		body.position.y = 0.25

func _physics_process(_delta: float) -> void:
	if not visible or record.get("state", "") not in ["MOVING","ROAMING","SCRAMBLING"] or not active: return
	if record.get("free_movement",true):
		var route: PackedVector2Array = record["route"]
		var index: int = record["route_index"]
		navigation_reachable = index < route.size()
		if navigation_reachable: navigation_next = Coordinates.to_world(route[index])
		return
	if NavigationServer3D.map_get_iteration_id(get_world_3d().navigation_map) == 0: return
	# Maintain Godot's 3D path state for the current authoritative road waypoint.
	# Do not displace the avatar a second time or feed physics timing back into decisions.
	if not navigator.is_navigation_finished():
		navigation_next = navigator.get_next_path_position()
		navigation_reachable = navigator.is_target_reachable()
