extends RefCounted
## Shared procedural animation clips for the common pivot rig. Per-agent playback state stays local.
static var _library: AnimationLibrary
static var _machine: AnimationNodeStateMachine
const CLIPS := ["idle","walk","run","sprint","limp","injured","panic","look_around","fight","fall","get_up","interact","shelter_enter","shelter_exit"]

static func library() -> AnimationLibrary:
	if _library != null: return _library
	_library = AnimationLibrary.new()
	for clip in CLIPS:
		_library.add_animation(clip,_make_clip(clip))
	return _library

static func state_machine() -> AnimationNodeStateMachine:
	if _machine != null: return _machine
	_machine = AnimationNodeStateMachine.new()
	var columns := 4
	for i in range(CLIPS.size()):
		var node := AnimationNodeAnimation.new()
		node.animation = "character/" + CLIPS[i]
		_machine.add_node(CLIPS[i],node,Vector2(i%columns*220,i/columns*120))
	for from_state in CLIPS:
		for to_state in CLIPS:
			if from_state == to_state: continue
			var transition := AnimationNodeStateMachineTransition.new()
			transition.xfade_time = 0.10
			_machine.add_transition(from_state,to_state,transition)
	var initial_transition:=AnimationNodeStateMachineTransition.new()
	_machine.add_transition("Start","idle",initial_transition)
	return _machine

static func _make_clip(kind: String) -> Animation:
	var animation := Animation.new()
	animation.resource_name = kind
	animation.length = 1.0
	animation.loop_mode = Animation.LOOP_LINEAR if kind in ["idle","walk","run","sprint","limp","injured","panic","look_around","fight","interact"] else Animation.LOOP_NONE
	var left_arm := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(left_arm,NodePath("Skeleton/ArmLeft/Pose:rotation"))
	var right_arm := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(right_arm,NodePath("Skeleton/ArmRight/Pose:rotation"))
	var left_leg := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(left_leg,NodePath("Skeleton/LegLeft/Pose:rotation"))
	var right_leg := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(right_leg,NodePath("Skeleton/LegRight/Pose:rotation"))
	var head := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(head,NodePath("Skeleton/Head/Pose:rotation"))
	var body := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(body,NodePath("Skeleton:rotation"))
	var times := [0.0,0.25,0.5,0.75,1.0]
	for i in range(times.size()):
		var phase := float(i)*PI*0.5
		var gait := 0.0
		var arms := 0.0
		var lean := 0.0
		match kind:
			"walk": gait=sin(phase)*0.42; arms=0.0
			"run": gait=sin(phase)*0.78; arms=-0.08
			"sprint","panic": gait=sin(phase)*1.05; arms=-0.16; lean=-0.12
			"limp": gait=sin(phase)*0.46 if i%2==0 else sin(phase)*0.23; arms=-0.06
			"injured": gait=sin(phase)*0.24 if i%2==0 else sin(phase)*0.12; arms=0.08; lean=0.08
			"fight": gait=sin(phase)*0.18; arms=1.0 if i==2 else -0.25
			"interact": gait=0.0; arms=-0.9 if i in [1,2,3] else -0.1
			"look_around": gait=0.0; arms=0.08
			"shelter_enter": gait=sin(phase)*0.3; arms=-0.22; lean=-0.16
			"shelter_exit": gait=sin(phase)*0.3; arms=-0.12; lean=0.12
			"get_up": gait=0.0; arms=-0.45 if i<3 else 0.0; lean=0.0 if i==4 else 0.3
			"fall": gait=0.0; arms=0.65; lean=PI*0.5
			"idle": gait=0.0; arms=sin(phase)*0.035
		animation.track_insert_key(left_arm,times[i],Vector3(arms-gait,0,0))
		animation.track_insert_key(right_arm,times[i],Vector3(arms+gait,0,0))
		animation.track_insert_key(left_leg,times[i],Vector3(gait,0,0))
		animation.track_insert_key(right_leg,times[i],Vector3(-gait,0,0))
		animation.track_insert_key(head,times[i],Vector3(0,sin(phase*0.5)*0.22 if kind=="look_around" else 0,0))
		animation.track_insert_key(body,times[i],Vector3(lean,0,0))
	return animation
