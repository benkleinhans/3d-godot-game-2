class_name AnimationComponent extends Node
## Drop-in animation slots. Drag Animation resources onto the "Anim ..." slots in the inspector.
## Empty slots are simply skipped, so the game runs with zero animations.
##
## Builds an AnimationTree at runtime:
##   locomotion = BlendSpace1D  idle -> walk -> run (blend = speed / walk_speed)
##   strafe / strafe_run = BlendSpace2D (idle centre, forward/back/left/right) used in lock-on + aim
##   every other slot = its own state; transitions are cross-faded.
## Walk/run use ONE animation each: the model turns toward the move direction (smoothed by MovementComponent).

signal tree_built

@export var model_root: Node3D                   # optional, auto = first Node3D under ModelPivot
@export var blend_time := 0.15
@export var blend_smoothing := 12.0
@export var land_time := 0.12

@export_group("Locomotion")
@export var anim_idle: Animation
@export var anim_walk: Animation
@export var anim_run: Animation
@export var anim_flow: Animation

@export_group("Strafe walk (lock-on / aim)")
@export var anim_strafe_walk_forward: Animation
@export var anim_strafe_walk_back: Animation
@export var anim_strafe_walk_left: Animation
@export var anim_strafe_walk_right: Animation

@export_group("Strafe run (optional, falls back to strafe walk)")
@export var anim_strafe_run_forward: Animation
@export var anim_strafe_run_back: Animation
@export var anim_strafe_run_left: Animation
@export var anim_strafe_run_right: Animation

@export_group("Air / Movement actions")
@export var anim_jump: Animation
@export var anim_fall: Animation
@export var anim_double_jump: Animation
@export var anim_land: Animation
@export var anim_charge_jump: Animation
@export var anim_dash: Animation
@export var anim_air_dash: Animation

@export_group("Melee")
@export var anim_slash_1: Animation
@export var anim_slash_2: Animation
@export var anim_air_slash: Animation
@export var anim_run_stab: Animation
@export var anim_flow_attack: Animation
@export var anim_charge_windup: Animation
@export var anim_charge_attack: Animation
@export var anim_plunge: Animation

@export_group("Other")
@export var anim_death: Animation

const SLOTS: Array[StringName] = [
	&"idle", &"walk", &"run", &"flow",
	&"strafe_walk_forward", &"strafe_walk_back", &"strafe_walk_left", &"strafe_walk_right",
	&"strafe_run_forward", &"strafe_run_back", &"strafe_run_left", &"strafe_run_right",
	&"jump", &"fall", &"double_jump", &"land", &"charge_jump", &"dash", &"air_dash",
	&"slash_1", &"slash_2", &"air_slash", &"run_stab", &"flow_attack",
	&"charge_windup", &"charge_attack", &"plunge", &"death",
]
const LOOPING: Array[StringName] = [
	&"idle", &"walk", &"run", &"flow",
	&"strafe_walk_forward", &"strafe_walk_back", &"strafe_walk_left", &"strafe_walk_right",
	&"strafe_run_forward", &"strafe_run_back", &"strafe_run_left", &"strafe_run_right",
	&"fall", &"charge_jump", &"plunge",
]
const SINGLE_STATES: Array[StringName] = [
	&"flow", &"jump", &"fall", &"double_jump", &"land", &"charge_jump", &"dash", &"air_dash",
	&"slash_1", &"slash_2", &"air_slash", &"run_stab", &"flow_attack",
	&"charge_windup", &"charge_attack", &"plunge", &"death",
]

var _body: CharacterBody3D
var _movement: MovementComponent
var _player: AnimationPlayer
var _tree: AnimationTree
var _playback: AnimationNodeStateMachinePlayback
var _states := {}
var _current: StringName = &""
var _action: StringName = &""
var _dead := false
var _dash_in_air := false
var _double_jumped := false
var _land_timer := 0.0
var _loco := 0.0
var _strafe := Vector2.ZERO

func setup(body: CharacterBody3D, movement: MovementComponent, model_pivot: Node3D) -> void:
	_body = body
	_movement = movement
	if model_root == null:
		for c in model_pivot.get_children():
			if c is Node3D and not c is Area3D:
				model_root = c
				break
	_movement.dashed.connect(func(in_air: bool): _dash_in_air = in_air)
	_movement.jumped.connect(func(kind: StringName): _double_jumped = kind == &"double_jump")
	_movement.landed.connect(_on_landed)
	_player = AnimationPlayer.new()
	_player.name = "AnimationPlayer"
	add_child(_player)
	_register_animations()
	_build_tree()

# ---------------- public API (Player glue) ----------------
func play_action(id: StringName) -> void:
	if _playback == null or not _states.has(id):
		return
	_action = id
	_current = id
	if _playback.get_current_node() == id:
		_playback.start(id, true)
	else:
		_playback.travel(id)

func end_action(id: StringName = &"") -> void:
	if id == &"" or id == _action:
		_action = &""

func play_death() -> void:
	_dead = true
	_action = &""

func clear_death() -> void:
	_dead = false
	_action = &""
	_current = &""
	if _playback and _states.has(&"locomotion"):
		_playback.start(&"locomotion")

# ---------------- setup ----------------
func _register_animations() -> void:
	var lib: AnimationLibrary
	if _player.has_animation_library(&""):
		lib = _player.get_animation_library(&"")
	else:
		lib = AnimationLibrary.new()
		_player.add_animation_library(&"", lib)
	for slot in SLOTS:
		var a := get("anim_" + String(slot)) as Animation
		if a == null:
			continue
		var c := a.duplicate() as Animation
		c.loop_mode = Animation.LOOP_LINEAR if LOOPING.has(slot) else Animation.LOOP_NONE
		lib.add_animation(slot, c)

func _anim_node(anim_name: StringName) -> AnimationNodeAnimation:
	if not _player.has_animation(anim_name):
		return null
	var n := AnimationNodeAnimation.new()
	n.animation = anim_name
	return n

func _build_tree() -> void:
	if model_root == null or _player.get_animation_list().is_empty():
		return   # nothing to animate yet
	var root := AnimationNodeStateMachine.new()

	var loco := AnimationNodeBlendSpace1D.new()
	loco.min_space = 0.0
	loco.max_space = maxf(_movement.run_multiplier, 1.0) + 0.5
	for pair in [[&"idle", 0.0], [&"walk", 1.0], [&"run", _movement.run_multiplier]]:
		var n := _anim_node(pair[0])
		if n:
			loco.add_blend_point(n, pair[1])
	if loco.get_blend_point_count() > 0:
		_add_state(root, &"locomotion", loco)

	var strafe := _make_strafe(false)
	if strafe:
		_add_state(root, &"strafe", strafe)
	var strafe_run := _make_strafe(true)
	if strafe_run:
		_add_state(root, &"strafe_run", strafe_run)

	for s in SINGLE_STATES:
		var n := _anim_node(s)
		if n:
			_add_state(root, s, n)

	if _states.is_empty():
		return
	var names := _states.keys()
	for a in names:
		for b in names:
			if a != b:
				var t := AnimationNodeStateMachineTransition.new()
				t.xfade_time = blend_time
				t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
				root.add_transition(a, b, t)

	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	_tree.tree_root = root
	add_child(_tree)
	_tree.root_node = _tree.get_path_to(model_root)
	_tree.anim_player = _tree.get_path_to(_player)
	_player.root_node = _player.get_path_to(model_root)
	_tree.active = true
	_playback = _tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	var first: StringName = &"locomotion" if _states.has(&"locomotion") else names[0]
	_playback.start(first)
	_current = first
	tree_built.emit()

func _make_strafe(running: bool) -> AnimationNodeBlendSpace2D:
	var bs := AnimationNodeBlendSpace2D.new()
	bs.min_space = Vector2(-1.2, -1.2)
	bs.max_space = Vector2(1.2, 1.2)
	var prefix := "strafe_run_" if running else "strafe_walk_"
	var centre := _anim_node(&"idle")
	if centre:
		bs.add_blend_point(centre, Vector2.ZERO)
	var dirs := {"forward": Vector2(0, 1), "back": Vector2(0, -1), "left": Vector2(-1, 0), "right": Vector2(1, 0)}
	for d in dirs:
		var n := _anim_node(StringName(prefix + d))
		if n == null and running:
			n = _anim_node(StringName("strafe_walk_" + d))
		if n == null and d == "forward":
			n = _anim_node(&"run" if running else &"walk")
		if n:
			bs.add_blend_point(n, dirs[d])
	return bs if bs.get_blend_point_count() >= 3 else null

func _add_state(root: AnimationNodeStateMachine, state_name: StringName, node: AnimationRootNode) -> void:
	root.add_node(state_name, node)
	_states[state_name] = true

# ---------------- runtime ----------------
func _on_landed() -> void:
	_double_jumped = false
	if _states.has(&"land"):
		_land_timer = land_time

func _process(delta: float) -> void:
	if _tree == null or _playback == null:
		return
	if _land_timer > 0.0:
		_land_timer -= delta
	var k := 1.0 - exp(-blend_smoothing * delta)
	var walk := maxf(_movement.walk_speed, 0.01)
	_loco = lerpf(_loco, Vector2(_body.velocity.x, _body.velocity.z).length() / walk, k)
	var norm := walk * (_movement.run_multiplier if _movement.run_enabled else 1.0)
	_strafe = _strafe.lerp(_movement.get_local_velocity() / norm, k).limit_length(1.0)
	if _states.has(&"locomotion"):
		_tree.set("parameters/locomotion/blend_position", _loco)
	if _states.has(&"strafe"):
		_tree.set("parameters/strafe/blend_position", _strafe)
	if _states.has(&"strafe_run"):
		_tree.set("parameters/strafe_run/blend_position", _strafe)
	var want := _desired_state()
	if want != _current and _states.has(want):
		_current = want
		_playback.travel(want)

func _desired_state() -> StringName:
	if _dead:
		return &"death"
	if _action != &"":
		return _action
	match _movement.mode:
		MovementComponent.Mode.DASH:
			return &"air_dash" if _dash_in_air else &"dash"
		MovementComponent.Mode.FLOW:
			return &"flow"
	if _movement.is_charging_jump():
		return &"charge_jump"
	if not _movement.grounded:
		if _double_jumped:
			return &"double_jump"
		return &"jump" if _body.velocity.y > 0.5 else &"fall"
	if _land_timer > 0.0:
		return &"land"
	if _movement.strafing:
		return &"strafe_run" if _movement.run_enabled else &"strafe"
	return &"locomotion"
