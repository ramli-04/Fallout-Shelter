extends Node3D
## Low-cost stylized companion avatar. Simulation records own all movement and state.
const Coordinates = preload("res://scripts/three_d/world_coordinates.gd")
const Geometry = preload("res://scripts/three_d/geometry.gd")

var record: Dictionary = {}
var body: Node3D
var legs: Array[Node3D] = []
var tail: Node3D
var head: Node3D
var jaw: MeshInstance3D
var selection_ring: MeshInstance3D
var selection_area: Area3D
var id_label: Label3D
var bark_player: AudioStreamPlayer3D
var selected := false
var active := false
var heading := 0.0
var animation_time := 0.0
var last_bark_serial := 0

func configure(data: Dictionary) -> void:
	record = data
	position = Coordinates.to_world(data.get("position",Vector2.ZERO))

func _ready() -> void:
	body = Node3D.new()
	body.name = "GermanShepherdModel"
	add_child(body)
	_create_model()
	selection_ring = Geometry.ring(self,0.95,Color("ffe8a3"))
	selection_ring.position.y = 0.04
	selection_ring.visible = false
	id_label = Geometry.label(self,"German Shepherd",Vector3(0,1.9,0),Color.WHITE,30,0.024)
	id_label.visible = false
	selection_area = Area3D.new()
	selection_area.collision_layer = 4
	selection_area.collision_mask = 0
	selection_area.set_meta("entity_owner",self)
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.55
	capsule.height = 1.65
	collider.shape = capsule
	collider.position.y = 0.7
	selection_area.add_child(collider)
	add_child(selection_area)
	bark_player = AudioStreamPlayer3D.new()
	bark_player.name = "BarkAudio"
	bark_player.volume_db = -5.0
	bark_player.max_distance = 42.0
	bark_player.stream = _make_bark_stream()
	add_child(bark_player)
	update_visual(record,1.0,false,0.0)

func _create_model() -> void:
	# Brown coat, black saddle/muzzle, upright ears and a red collar identify the breed.
	Geometry.box(body,Vector3(0.70,0.56,1.22),Vector3(0,0.67,0),Color("a66b3e"))
	Geometry.box(body,Vector3(0.63,0.22,0.79),Vector3(0,0.97,0.06),Color("292622"))
	head = Node3D.new()
	head.position = Vector3(0,0.92,-0.64)
	body.add_child(head)
	Geometry.box(head,Vector3(0.34,0.34,0.40),Vector3.ZERO,Color("9d6138"))
	Geometry.box(head,Vector3(0.25,0.16,0.39),Vector3(0,-0.16,-0.29),Color("302923"))
	jaw = Geometry.box(head,Vector3(0.28,0.10,0.14),Vector3(0,-0.23,-0.50),Color("171819"))
	for side in [-1,1]:
		Geometry.box(head,Vector3(0.15,0.29,0.15),Vector3(side*0.15,0.25,-0.04),Color("28221e")).rotation.z = -0.16*side
		Geometry.box(head,Vector3(0.10,0.07,0.05),Vector3(side*0.13,0.06,-0.20),Color("d6ad76"))
	Geometry.box(body,Vector3(0.73,0.12,0.10),Vector3(0,0.90,-0.48),Color("bf3540"))
	tail = Node3D.new()
	tail.position = Vector3(0,0.78,0.62)
	body.add_child(tail)
	Geometry.box(tail,Vector3(0.16,0.17,0.55),Vector3(0,0.03,0.25),Color("a66b3e"))
	for side in [-1,1]:
		for z in [-0.42,0.42]:
			var leg := Node3D.new()
			leg.position = Vector3(side*0.24,0.48,z)
			body.add_child(leg)
			Geometry.box(leg,Vector3(0.20,0.45,0.22),Vector3(0,-0.20,0),Color("9d6138"))
			Geometry.box(leg,Vector3(0.19,0.22,0.22),Vector3(0,-0.48,-0.015),Color("332a24"))
			legs.append(leg)

func update_visual(data: Dictionary, alpha: float, running: bool, time: float = 0.0) -> void:
	record = data
	active = running
	var previous: Vector2 = data.get("previous_position",data.get("position",Vector2.ZERO))
	var point: Vector2 = previous.lerp(data.get("position",previous),clampf(alpha,0.0,1.0)) if running else data.get("position",previous)
	position = Coordinates.to_world(point,float(data.get("transport_height",0.0))+Coordinates.FLOOR_Y)
	var direction: Vector2 = data.get("position",point)-previous
	if not direction.is_zero_approx(): heading = atan2(-direction.x,-direction.y)
	visible = data.get("state","") not in ["SHELTERED"]
	selection_area.collision_layer = 4 if visible else 0
	selection_ring.visible = selected and visible
	id_label.visible = selected and visible
	if data.get("bark_serial",0) != last_bark_serial:
		last_bark_serial = data.bark_serial
		bark_player.play()
	if data.get("survival_status","") == "DEAD":
		body.rotation.z = PI/2
	else:
		body.rotation.z = 0.0
	body.rotation.y = heading
	body.position.y = -0.12 if data.get("state","") == "FEARFUL" else 0.0
	if time != 0.0: animation_time = time

func set_selected(value: bool) -> void:
	selected = value
	if selection_ring != null: selection_ring.visible = value and visible
	if id_label != null: id_label.visible = value and visible

func _process(delta: float) -> void:
	if body == null: return
	animation_time += delta
	var moving_speed: float = record.get("previous_position",record.get("position",Vector2.ZERO)).distance_to(record.get("position",Vector2.ZERO)) / maxf(delta,0.0001)
	var moving: bool = active and moving_speed > 0.15 and record.get("state","") not in ["SHELTERED","DEAD"]
	var running: bool = moving_speed > 7.5
	var swing: float = sin(animation_time*(15.0 if running else 9.0))*(0.75 if running else 0.48) if moving else 0.0
	for index in range(legs.size()):
		legs[index].rotation.x = swing * (1.0 if index % 2 == 0 else -1.0)
		legs[index].rotation.z = 0.0
	if tail != null:
		if record.get("state","") == "FEARFUL":
			tail.rotation.x = -0.7
			tail.rotation.z = 0.0
		else:
			tail.rotation.x = sin(animation_time*4.0) * (0.15 if moving else 0.26)
			tail.rotation.z = sin(animation_time*5.0)*0.14
	if head != null:
		head.rotation.x = sin(animation_time*25.0)*0.12 if record.get("state","") == "BARKING" else 0.0
	if jaw != null: jaw.rotation.x = -0.22 if record.get("state","") == "BARKING" else 0.0
	if record.get("state","") == "FEARFUL": body.rotation.z += sin(animation_time*18.0)*0.025

func _make_bark_stream() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	var samples := 6600
	var bytes := PackedByteArray()
	bytes.resize(samples*2)
	for i in range(samples):
		var t := float(i)/stream.mix_rate
		var pulse := 1.0 if t < 0.09 or (t > 0.13 and t < 0.23) else 0.0
		var envelope := exp(-maxf(0.0,fposmod(t,0.13)-0.02)*23.0)*pulse
		var tone := sin(TAU*(185.0-60.0*t)*t) + 0.35*sin(TAU*420.0*t)
		bytes.encode_s16(i*2,int(clampi(roundi(tone*envelope*10500.0),-32767,32767)))
	stream.data = bytes
	return stream
