extends Node3D
## Read-only avatar. Fixed-clock simulation positions own motion, never render/physics timing.
const Coordinates = preload("res://scripts/three_d/world_coordinates.gd")
const Geometry = preload("res://scripts/three_d/geometry.gd")
const CharacterAnimations = preload("res://scripts/three_d/character_animations.gd")
const RenderOptions = preload("res://scripts/three_d/render_options.gd")
static var shared_animation_options: Dictionary={}
var record: Dictionary = {}
var is_selected := false
var body: Node3D
var bean: MeshInstance3D
var selection_area: Area3D
var selection_ring: MeshInstance3D
var id_label: Label3D
var navigator: NavigationAgent3D
var animation_player: AnimationPlayer
var animation_tree: AnimationTree
var heading := 0.0
var visual_time := 0.0
var bob_height := 0.07
var active := false
var navigation_next := Vector3.ZERO
var navigation_reachable := false
var last_state := ""
var unique_color := Color.WHITE
var visual_category := "civilian"
var arms: Array[Node3D] = []
var legs: Array[Node3D] = []
var animation_clock := 0.0
var animation_accumulator := 0.0
var animation_next_interval := 0.0
var animation_state := "standing"
var animation_lod_tier := "full"
var previous_vehicle := ""
var vehicle_transition := ""
var transition_until := -1.0
var visual_initialized := false

func configure(data: Dictionary) -> void:
	record = data
	position = Coordinates.to_world(data["position"])

func _ready() -> void:
	if shared_animation_options.is_empty(): shared_animation_options=RenderOptions.load_options()
	navigator = $NavigationAgent3D
	var map=preload("res://scripts/city_map.gd")
	navigator.path_search_max_polygons=ceili(map.MAP_SIZE.x/map.FREE_CELL)*ceili(map.MAP_SIZE.y/map.FREE_CELL)+1
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/visual_3d.json"))
	bob_height = float(settings["agent_bob_height"])
	var index := int(record.get("population_index", 0))
	unique_color = Color.from_hsv(fmod(index*0.618034,1.0),0.48,0.95)
	body = Node3D.new()
	add_child(body)
	_create_human(index)
	_create_animation_controller()
	_detail_lod(body)
	selection_ring = Geometry.ring(self,0.9,Color("ffe8a3"))
	selection_ring.position.y = 0.035
	selection_ring.visible = false
	id_label = Geometry.label(self,record.get("display_name",record.get("id", "")),Vector3(0,2.7,0),Color.WHITE,36,0.022)
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
	var skin: Color = Color("563c32") if record.get("visual_skin_tone","")=="deep_brown" else skins[rng.randi_range(0,skins.size()-1)]
	var hair_colors := [Color("332a25"),Color("654a31"),Color("af854e"),Color("c6c0ae"),Color("251f1e")]
	var hair: Color = Color("211b19") if record.get("gender","")=="male" and record.get("display_name","")=="I Am Legend" else hair_colors[rng.randi_range(0,hair_colors.size()-1)]
	var authority: bool = record.get("role","") == "Authority"
	visual_category=str(record.get("visual_category",record.get("agent_type",record.get("authority_role",record.get("profession","civilian"))))).to_lower()
	if authority and visual_category=="civilian": visual_category="responder"
	var outfit: Color=unique_color
	if authority:
		outfit={"police":Color("294b70"),"fire":Color("814238"),"firefighter":Color("814238"),"medical":Color("c2c8b5"),"medic":Color("c2c8b5"),"military":Color("59654d"),"civil protection":Color("66734f"),"responder":Color("355a78")}.get(visual_category,Color("355a78"))
	if visual_category in ["zombie","infected"] or record.get("is_zombie",false):
		visual_category="zombie"
		if str(record.get("visual_skin_tone","")).is_empty(): skin=Color("8a9185")
		unique_color=Color("555d50")
		outfit=unique_color
	elif authority:
		unique_color={"police":Color("294b70"),"fire":Color("814238"),"firefighter":Color("814238"),"medical":Color("c2c8b5"),"medic":Color("c2c8b5"),"military":Color("59654d"),"civil protection":Color("66734f"),"responder":Color("355a78")}.get(visual_category,Color("355a78"))
	var skeleton:=Skeleton3D.new()
	skeleton.name="Skeleton"
	body.add_child(skeleton)
	for bone_name in ["Root","Torso","Head","ArmLeft","ArmRight","LegLeft","LegRight"]: skeleton.add_bone(bone_name)
	skeleton.set_bone_parent(1,0); skeleton.set_bone_parent(2,1); skeleton.set_bone_parent(3,1); skeleton.set_bone_parent(4,1); skeleton.set_bone_parent(5,0); skeleton.set_bone_parent(6,0)
	skeleton.set_bone_rest(1,Transform3D(Basis.IDENTITY,Vector3(0,1.33,0)))
	skeleton.set_bone_rest(2,Transform3D(Basis.IDENTITY,Vector3(0,.67,0)))
	skeleton.set_bone_rest(3,Transform3D(Basis.IDENTITY,Vector3(-.44,.27,0)))
	skeleton.set_bone_rest(4,Transform3D(Basis.IDENTITY,Vector3(.44,.27,0)))
	skeleton.set_bone_rest(5,Transform3D(Basis.IDENTITY,Vector3(-.18,.91,0)))
	skeleton.set_bone_rest(6,Transform3D(Basis.IDENTITY,Vector3(.18,.91,0)))
	# BoneAttachment3D follows the pose, not the rest transform. Without this
	# initialization every limb is piled at the root despite a valid skeleton.
	skeleton.reset_bone_poses()
	var torso:=_bone_attachment(skeleton,"Torso")
	bean=Geometry.capsule(torso,.31,.78,Vector3(0,.02,0),outfit,16,4)
	bean.scale.z=.62
	Geometry.box(torso,Vector3(.48,.25,.30),Vector3(0,-.39,0),Color("35424a"))
	Geometry.cylinder(torso,.145,.20,Vector3(0,.43,0),skin,10)
	Geometry.box(torso,Vector3(.15,.13,.025),Vector3(-.14,.16,-.20),outfit.lightened(.14))
	var head_attachment:=_bone_attachment(skeleton,"Head")
	var head_pose:=_pose_pivot(head_attachment)
	Geometry.sphere(head_pose,.25,.48,Vector3.ZERO,skin,14,8)
	var hair_cap:=Geometry.sphere(head_pose,.255,.45,Vector3(0,.17,.015),hair,12,6)
	hair_cap.scale=Vector3(1,.58,1)
	match posmod(index,4):
		0:
			var back_hair:=Geometry.sphere(head_pose,.20,.53,Vector3(0,-.06,.13),hair,10,5)
			back_hair.scale=Vector3(1,.92,.65)
		1:
			for side in [-1,1]: Geometry.sphere(head_pose,.105,.16,Vector3(side*.14,.18,0),hair,8,4)
		2:
			Geometry.sphere(head_pose,.11,.18,Vector3(0,.29,.02),hair,8,4)
		3:
			var fringe:=Geometry.sphere(head_pose,.18,.12,Vector3(0,.14,-.19),hair,10,5)
			fringe.scale=Vector3(1,.8,.5)
	for side in [-1,1]:
		Geometry.sphere(head_pose,.045,.085,Vector3(side*.235,-.015,0),skin,8,4)
		Geometry.sphere(head_pose,.032,.045,Vector3(side*.095,.045,-.218),Color("f4eadf"),8,4)
		Geometry.sphere(head_pose,.015,.026,Vector3(side*.095,.045,-.24),Color("27292a"),6,3)
		var arm_attachment := _bone_attachment(skeleton,"ArmLeft" if side<0 else "ArmRight")
		var arm:=_pose_pivot(arm_attachment)
		Geometry.capsule(arm,.115,.57,Vector3(0,-.265,0),outfit.darkened(.08),9,2)
		Geometry.capsule(arm,.085,.34,Vector3(0,-.61,-.025),skin,8,2)
		Geometry.sphere(arm,.095,.19,Vector3(0,-.80,-.025),skin,8,4)
		arms.append(arm)
		var leg_attachment := _bone_attachment(skeleton,"LegLeft" if side<0 else "LegRight")
		var leg:=_pose_pivot(leg_attachment)
		Geometry.capsule(leg,.12,.42,Vector3(0,-.21,0),Color("35424a"),9,2)
		Geometry.capsule(leg,.095,.36,Vector3(0,-.57,0),Color("35424a"),9,2)
		var shoe:=Geometry.box(leg,Vector3(.25,.14,.38),Vector3(0,-.75,-.075),Color("303333"))
		shoe.rotation.x=-.06
		legs.append(leg)
	if authority:
		if visual_category=="police":
			Geometry.cylinder(head_pose,.27,.12,Vector3(0,.29,0),outfit.darkened(.15),10)
			Geometry.box(head_pose,Vector3(.45,.045,.32),Vector3(0,.25,-.06),outfit.darkened(.2))
			Geometry.box(torso,Vector3(.09,.12,.035),Vector3(-.19,.18,-.30),Color("e5c976"))
		elif visual_category in ["fire","firefighter"]:
			Geometry.box(torso,Vector3(.70,.055,.34),Vector3(0,-.12,-.02),Color("f0c74f"))
			Geometry.box(torso,Vector3(.70,.055,.34),Vector3(0,-.34,-.02),Color("f0c74f"))
		elif visual_category in ["medical","medic"]:
			Geometry.box(torso,Vector3(.10,.26,.035),Vector3(-.13,.06,-.315),Color("b34743"))
			Geometry.box(torso,Vector3(.24,.08,.035),Vector3(-.13,.06,-.315),Color("b34743"))
		elif visual_category=="civil protection":
			Geometry.box(torso,Vector3(.70,.06,.34),Vector3(0,-.12,-.02),Color("e3a244"))
			Geometry.box(torso,Vector3(.14,.30,.035),Vector3(-.18,.06,-.31),Color("e3a244"))
		else:
			Geometry.cylinder(head_pose,.27,.10,Vector3(0,.28,0),outfit.darkened(.22),10)
	else:
		match posmod(index,4):
			0:
				var backpack:=Geometry.capsule(torso,.16,.50,Vector3(0,-.06,.29),outfit.darkened(.42),9,2)
				backpack.rotation.x=PI*.5
			1:
				var coat:=Geometry.capsule(torso,.38,.62,Vector3(0,-.08,.02),outfit.darkened(.22),10,2)
				coat.scale.z=.82
			2:
				Geometry.box(torso,Vector3(.10,.48,.035),Vector3(0,-.04,-.32),Color("d4b878"))
			3:
				Geometry.capsule(torso,.37,.25,Vector3(0,.30,0),outfit.lightened(.22),10,2)
	var age:=int(record.get("age",30))
	var height_scale:=.62 if age<5 else .76 if age<13 else .90 if age<18 else .97 if age>=70 else rng.randf_range(.96,1.06)
	var width_scale:=.88 if age<13 else .94 if age<18 else rng.randf_range(.94,1.06)
	body.scale=Vector3(width_scale,height_scale,width_scale)

func _bone_attachment(skeleton: Skeleton3D, bone_name: String) -> BoneAttachment3D:
	var attachment:=BoneAttachment3D.new()
	attachment.name=bone_name
	attachment.bone_name=bone_name
	skeleton.add_child(attachment)
	return attachment

func _pose_pivot(parent: Node3D) -> Node3D:
	var pivot:=Node3D.new()
	pivot.name="Pose"
	parent.add_child(pivot)
	return pivot

func _create_animation_controller() -> void:
	animation_player=AnimationPlayer.new()
	animation_player.name="AnimationPlayer"
	animation_player.root_node=NodePath("..")
	animation_player.add_animation_library("character",CharacterAnimations.library())
	body.add_child(animation_player)
	animation_tree=AnimationTree.new()
	animation_tree.name="AnimationTree"
	animation_tree.anim_player=NodePath("../AnimationPlayer")
	animation_tree.tree_root=CharacterAnimations.state_machine()
	animation_tree.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animation_tree.active=true
	body.add_child(animation_tree)

func _detail_lod(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh != null and child.mesh.get_aabb().size.y < 0.30:
			child.visibility_range_end = 120.0
		_detail_lod(child)

func set_selected(value: bool) -> void:
	is_selected = value
	selection_ring.visible = value and visible
	id_label.visible = value and visible
	_update_color()

func update_visual(data: Dictionary, alpha: float, running: bool, time: float = 0) -> void:
	record = data
	active = running
	visual_time = time
	var vehicle_id := str(data.get("riding",""))
	if visual_initialized and vehicle_id != previous_vehicle:
		vehicle_transition = "entering_vehicle" if not vehicle_id.is_empty() else "exiting_vehicle"
		transition_until = time+.45
	previous_vehicle = vehicle_id
	visual_initialized = true
	var previous: Vector2 = data.get("previous_position",data["position"])
	var point: Vector2 = previous.lerp(data["position"],clampf(alpha,0,1)) if running else data["position"]
	position = Coordinates.to_world(point,float(data.get("transport_height",0))+Coordinates.FLOOR_Y)
	var direction: Vector2 = data["position"]-previous
	if not direction.is_zero_approx():
		heading = atan2(-direction.x,-direction.y)
	var was_visible:=visible
	visible = (data["state"] != "SHELTERED" or data.get("shelter_life_active",false)) and (vehicle_id.is_empty() or time < transition_until)
	if visible and not was_visible: animation_next_interval=0.0; animation_accumulator=0.0
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
	bean.material_override = Geometry.material(color)

func _process(delta: float) -> void:
	if body == null or not visible: return
	animation_accumulator+=delta
	if animation_next_interval>0 and animation_accumulator<animation_next_interval: return
	var step_delta:=animation_accumulator
	animation_accumulator=0
	animation_next_interval=_animation_interval()
	if active: animation_clock += step_delta
	var phase := animation_clock + int(record.get("population_index",0))*0.3
	var state: String = record["state"]
	var shelter_moving: bool=record.get("shelter_life_active",false) and record.get("shelter_activity_state","")=="MOVING"
	var moving := active and (state in ["MOVING","ROAMING","SCRAMBLING"] or shelter_moving)
	var walking := state == "ROAMING"
	var clip:=_animation_for_state(state,moving,walking,shelter_moving)
	animation_state=clip
	if animation_tree!=null:
		var playback: AnimationNodeStateMachinePlayback=animation_tree.get("parameters/playback")
		if playback!=null and playback.get_current_node()!=clip: playback.travel(clip)
		animation_tree.advance(step_delta)
	body.rotation.y = lerp_angle(body.rotation.y,heading,1-exp(-12*step_delta))
	body.rotation.x = -0.12 if moving and not walking else 0.0
	body.rotation.z = 0.0
	body.position.y = absf(sin(phase*12))*0.08 if moving else 0.0
	if state in ["CHATTING","HELPING","FROZEN","STAGGERED"]:
		animation_state = {"CHATTING":"talking","HELPING":"interacting","FROZEN":"emergency","STAGGERED":"injured"}[state]
	if record.get("shelter_life_active",false) and not shelter_moving:
		var animation:=str(record.get("activity_animation","standing"))
		animation_state = animation
		match animation:
			"sleep": body.rotation.z=PI/2; body.position.y=-0.35
			"sitting": body.rotation.x=.18; body.position.y=-.12
			"reading": body.rotation.x=.08; arms[0].rotation.x=-.75; arms[1].rotation.x=-.75
			"eating","drinking","communicating": arms[0].rotation.x=-1.15
			"talking","helping","working","repairing","cleaning","cooking":
				arms[0].rotation.x=-1.0+sin(phase*3)*.16; arms[1].rotation.x=-.85+sin(phase*3+1)*.16
			"exercise": body.position.y=absf(sin(phase*5))*.18; arms[0].rotation.x=sin(phase*5)*.8; arms[1].rotation.x=-sin(phase*5)*.8
			"lying": body.rotation.z=PI/2; body.position.y=-.35
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
	if record.get("police_unit_busy",false):
		var pose: String=record.get("police_animation","")
		animation_state=pose
		match pose:
			"walking":
				for i in range(legs.size()): legs[i].rotation.x=sin(phase*7)*.35*(1 if i==0 else -1)
			"placing_barrier","deploying_cones","removing_barrier":
				body.rotation.x=.4; body.position.y=-.15
				for arm in arms: arm.rotation.x=-.9+sin(phase*3)*.2
			"stopping_vehicle": arms[0].rotation.x=-1.6
			"directing_traffic","pointing_route": arms[0].rotation.z=-1.3; arms[1].rotation.x=-.8+sin(phase*2)*.2
			"communicating","coordinating","helping": arms[0].rotation.x=-1.2; arms[1].rotation.x=-.7
	if visual_time < transition_until:
		animation_state = vehicle_transition
		body.rotation.x = .35
		body.position.y = -.15
		arms[0].rotation.x = -1.2
		legs[0].rotation.x = -.6
	if record.get("survival_status","") == "DEAD":
		animation_state = "lying"
		body.rotation = Vector3(0,heading,PI/2)
		body.position.y = 0.25

func _animation_interval() -> float:
	var camera:=get_viewport().get_camera_3d()
	if camera==null:
		animation_lod_tier="full"
		return 0.0
	var distance:=global_position.distance_to(camera.global_position)
	var options: Dictionary=shared_animation_options
	if distance<=float(options.animation_full_distance):
		animation_lod_tier="full"
		return 0.0
	if distance<=float(options.animation_medium_distance):
		animation_lod_tier="medium"
		return float(options.animation_medium_interval)
	animation_lod_tier="far"
	return float(options.animation_far_interval)

func _animation_for_state(state: String, moving: bool, walking: bool, shelter_moving: bool) -> String:
	if record.get("survival_status","")=="DEAD": return "fall"
	if visual_time<transition_until: return "shelter_enter" if vehicle_transition=="entering_vehicle" else "shelter_exit"
	if state in ["FALLING","DOWNED","COLLAPSED"]: return "fall"
	if state in ["GETTING_UP","RECOVERING"]: return "get_up"
	if state in ["FIGHTING","ATTACKING"]: return "fight"
	if state in ["ENTERING_SHELTER","EXITING_SHELTER"]: return "shelter_enter" if state=="ENTERING_SHELTER" else "shelter_exit"
	if state in ["INTERACTING","BOARDING","TREATING"]: return "interact"
	if state in ["LOOKING_AROUND","SCANNING"]: return "look_around"
	if float(record.get("panic_level",0.0))>=70.0 and moving: return "panic"
	if shelter_moving: return "shelter_enter"
	if record.get("shelter_life_active",false):
		var activity:=str(record.get("activity_animation","standing"))
		if activity in ["working","repairing","cleaning","cooking","eating","drinking","communicating","helping"]: return "interact"
		if activity in ["reading","sleep","sitting","lying"]: return "idle"
		if activity=="exercise": return "walk"
	if record.get("police_unit_busy",false): return "interact"
	if state=="SCRAMBLING": return "sprint"
	if state=="DANCING": return "panic"
	if state=="STAGGERED": return "injured"
	if state=="FROZEN" or state=="WAITING_ROAD": return "look_around"
	if state in ["CHATTING","HELPING"]: return "interact"
	if moving and walking: return "walk"
	if moving:
		if float(record.get("health",100))<45 or not str(record.get("injury","")).is_empty(): return "limp"
		return "run"
	if float(record.get("health",100))<35: return "injured"
	return "idle"

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
