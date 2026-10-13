extends Node3D
## Bounded camera mix observes authoritative warning records; it never drives agent perception.
const Audio = preload("res://scripts/warning_audio.gd")
const Warning = preload("res://scripts/warning_system.gd")
var manager: Node
var view: Node
var nodes: Array[Node3D] = []
var bank: Dictionary = {}
var listener: AudioListener3D
var director_player: AudioStreamPlayer
var explosion: AudioStreamPlayer3D
var test_id := ""
var test_deadline := 0.0
var impact_age := -1.0
var show_coverage := false
var mix_age := 0.0
var audible_ids: Array[String] = []
var last_phase := ""
func _ready() -> void:
	Audio.setup_bus()
	listener = AudioListener3D.new()
	add_child(listener)
	listener.make_current()
	director_player = AudioStreamPlayer.new()
	director_player.bus = "ESSAIMWarnings"
	director_player.volume_db = -38
	add_child(director_player)
	explosion = AudioStreamPlayer3D.new()
	explosion.bus = "ESSAIMWarnings"
	explosion.unit_size = 200
	explosion.max_distance = 1500
	explosion.volume_db = -12
	explosion.max_db = -6
	add_child(explosion)
func rebuild() -> void:
	stop_all()
	for node in nodes:
		remove_child(node)
		node.queue_free()
	nodes.clear()
	bank = Audio.load_bank(manager.warning_config)
	for record in manager.sirens:
		var node: Node3D = preload("res://scenes/three_d/WarningSiren.tscn").instantiate()
		node.configure(record)
		if record["mount"] == "ROOFTOP":
			for building in view.city.buildings:
				if building.footprint.get_center() == record["position"]:
					node.roof_building = building
					break
		add_child(node)
		node.coverage.visible = show_coverage
		nodes.append(node)
	impact_age = -1
	last_phase = manager.phase
func stop_all() -> void:
	for node in nodes: node.stop_audio()
	director_player.stop()
	explosion.stop()
	test_id = ""
	audible_ids.clear()
func test_siren(id: String) -> void:
	for node in nodes:
		if node.record["id"] == id and node.record["state"] not in ["DAMAGED","DESTROYED"]:
			test_id = id
			test_deadline = Time.get_ticks_msec()/1000.0+6.0
			sync_mix()
			return
func impact_audio() -> void:
	impact_age = 0
	test_id = ""
	for node in nodes: node.stop_audio()
	director_player.stop()
	explosion.position = preload("res://scripts/three_d/world_coordinates.gd").to_world(Vector2(manager.nuclear["impact_position"][0],manager.nuclear["impact_position"][1]))
	explosion.stream = bank.get("EXPLOSION")
	if explosion.stream: explosion.play()
	sync_mix()
func _process(delta: float) -> void:
	if manager == null or manager.warning_config.is_empty(): return
	if impact_age >= 0: impact_age += delta
	mix_age += delta
	if mix_age >= 0.1:
		mix_age = 0
		sync_mix()
	for node in nodes:
		if is_instance_valid(node.roof_building) and node.record["state"] != "DESTROYED":
			node.position.y = 0.18+node.record["base_height"]*(node.roof_building.scale.y-1)
		else: node.position.y = 0.18
		var active: bool = node.record["state"] == "ACTIVE" or node.record["id"] == test_id or (impact_age >= 0 and impact_age < manager.warning_config["survivor_tail_seconds"] and node.record.get("tail_allowed",false))
		var time: float = Time.get_ticks_msec()/1000.0 if (node.record.get("director_manual",false) and manager.phase == "PREPARATION") or node.record["id"] == test_id or impact_age >= 0 else manager.elapsed_seconds
		node.visual(time,active)
func sync_mix() -> void:
	if manager == null or bank.is_empty(): return
	var config: Dictionary = manager.warning_config
	var wall := Time.get_ticks_msec()/1000.0
	if wall >= test_deadline: test_id = ""
	if config["director_mix"]:
		listener.global_position = Vector3(view.camera_rig.target_focus.x,2,view.camera_rig.target_focus.z)
		listener.global_basis = Basis(Vector3.UP,deg_to_rad(view.camera_rig.yaw))
	else:
		listener.global_transform = view.camera.global_transform
	var candidates: Array[Node3D] = []
	for node in nodes:
		var tail: bool = impact_age >= 0 and impact_age < config["survivor_tail_seconds"] and node.record.get("tail_allowed",false)
		var manual: bool = node.record.get("director_manual",false) and manager.phase == "PREPARATION"
		var age: float = wall-node.record.get("manual_wall_start",wall)-node.record["start_offset"] if manual else manager.elapsed_seconds-node.record["active_since"]-node.record["start_offset"]
		if node.record["id"] == test_id or tail or (node.record["state"] == "ACTIVE" and age >= 0):
			if node.record["id"] == test_id or listener.global_position.distance_to(node.player.global_position) <= node.record["radius_world"]: candidates.append(node)
	candidates.sort_custom(func(a,b):
		if a == b: return false
		if a.record["id"] == test_id: return true
		if b.record["id"] == test_id: return false
		return a.position.distance_squared_to(listener.position) < b.position.distance_squared_to(listener.position))
	audible_ids.clear()
	for i in range(mini(int(config["max_audible_sirens"]),candidates.size())): audible_ids.append(candidates[i].record["id"])
	for node in nodes:
		if node.record["id"] not in audible_ids:
			node.stop_audio()
			continue
		var test: bool = node.record["id"] == test_id
		var manual: bool = node.record.get("director_manual",false) and manager.phase == "PREPARATION"
		var tail: bool = impact_age >= 0
		var mode: String = config["network_mode"] if test or manual else "FINAL_WARNING" if tail else Warning.mode_at(manager,node.record)
		var stream: AudioStream = bank.get(mode)
		if stream == null:
			node.stop_audio()
			continue
		var age: float = wall if test else wall-node.record.get("manual_wall_start",wall)-node.record["start_offset"] if manual else impact_age if tail else Warning.audio_age(manager,node.record,mode)
		if mode == "EMERGENCY_BROADCAST" and not test and not manual and config["network_mode"] != "EMERGENCY_BROADCAST" and age >= stream.get_length():
			node.stop_audio()
			continue
		var offset := fposmod(age,maxf(0.1,stream.get_length()))
		var paused: bool = not manager.running and not test and not manual and not tail
		if paused:
			# Cancel deferred 3D play requests too; resume reconstructs the frozen clock phase.
			node.stop_audio()
			node.player.stream_paused = true
			continue
		if node.playback_mode != mode or not node.player.playing:
			node.player.stream = stream
			node.player.play(offset)
			node.playback_mode = mode
		elif not paused and absf(node.player.get_playback_position()-offset) > 0.5: node.player.seek(offset)
		node.player.stream_paused = paused
		node.player.pitch_scale = node.record["pitch"]*(1.0 if test or manual or tail else manager.simulation_speed)
		node.player.volume_db = node.record["volume_db"]+config["master_volume_db"]
		var indoors: bool = view.listener_indoors or (view.follow_agent and is_instance_valid(view.selected_node) and view.selected_node.record.get("state", "") == "SHELTERED")
		var muffled: bool = indoors
		if config["environmental_muffling"] and not muffled:
			var query := PhysicsRayQueryParameters3D.create(listener.global_position,node.player.global_position,1)
			muffled = not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
		node.player.bus = "ESSAIMWarningsMuffled" if muffled else "ESSAIMWarnings"
		if indoors: node.player.volume_db += linear_to_db(config["indoor_gain"])
	# A very quiet camera-relative bed keeps an actual city warning noticeable at overview.
	if config["director_mix"] and manager.phase == "EVACUATION" and manager.sirens.any(func(s): return s["state"] == "ACTIVE"):
		var source: Dictionary = manager.sirens.filter(func(s): return s["state"] == "ACTIVE")[0]
		var mode: String = Warning.mode_at(manager,source)
		var stream: AudioStream = bank.get(mode)
		var phase: float = Warning.audio_age(manager,source,mode)
		if stream == null or (mode == "EMERGENCY_BROADCAST" and config["network_mode"] != "EMERGENCY_BROADCAST" and phase >= stream.get_length()):
			director_player.stop()
		else:
			var offset := fposmod(phase,maxf(0.1,stream.get_length()))
			if director_player.stream != stream or not director_player.playing:
				director_player.stream = stream
				director_player.play(offset)
			elif manager.running and absf(director_player.get_playback_position()-offset) > 0.5:
				director_player.seek(offset)
		director_player.volume_db = -30+config["master_volume_db"]
		director_player.pitch_scale = manager.simulation_speed
		director_player.stream_paused = not manager.running
	else: director_player.stop()
