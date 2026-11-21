class_name CameraComponent extends Node3D
## Independent 3rd-person camera (Elden Ring style). Needs these unique-name children:
## %CameraPitch (Node3D) > %SpringArm (SpringArm3D) > %Camera3D (Camera3D)

enum Mode { FREE, LOCK_ON, AIM, OVERHEAD }

@export_group("Look")
@export var mouse_sensitivity := 0.0028
@export var stick_sensitivity := 3.0
@export var invert_y := false
@export_range(-89.0, 0.0) var min_pitch_deg := -75.0
@export_range(0.0, 89.0) var max_pitch_deg := 50.0
## Starting yaw in degrees (0 looks toward -Z, -90 looks toward +X)
@export var initial_yaw_deg := -90.0

@export_group("Follow")
@export var target_offset := Vector3(0.0, 1.4, 0.0)
@export var follow_smoothing := 25.0
## While in Flow the camera swings behind the player (unless you move the camera)
@export var flow_follow_speed := 2.5

@export_group("Lock-on")
@export var lock_pitch_deg := -14.0
@export var lock_turn_smoothing := 7.0

@export_group("Profiles")
@export var free_profile: CameraProfile
@export var lock_profile: CameraProfile
@export var aim_profile: CameraProfile
@export var overhead_profile: CameraProfile
@export var profile_blend_speed := 8.0

@onready var _pitch_pivot: Node3D = %CameraPitch
@onready var _spring: SpringArm3D = %SpringArm
@onready var _camera: Camera3D = %Camera3D

var mode := Mode.FREE
var stick_look := Vector2.ZERO
var follow_yaw_enabled := false
var follow_yaw := 0.0

var _target: Node3D
var _lock_target: Node3D
var _yaw := 0.0
var _pitch := -0.2
var _look_accum := Vector2.ZERO

func _ready() -> void:
	top_level = true
	if free_profile == null:
		free_profile = CameraProfile.create(4.0, 0.0, 0.0, 75.0)
	if lock_profile == null:
		lock_profile = CameraProfile.create(4.6, 0.6, 0.3, 70.0)
	if aim_profile == null:
		aim_profile = CameraProfile.create(2.0, 0.9, 0.2, 60.0)
	if overhead_profile == null:
		overhead_profile = CameraProfile.create(2.6, 0.0, 1.8, 65.0)
	_yaw = deg_to_rad(initial_yaw_deg)
	_camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func setup(target: Node3D) -> void:
	_target = target
	if target is CollisionObject3D:
		_spring.add_excluded_object(target.get_rid())
	global_position = target.global_position + target_offset

func set_mode(m: Mode) -> void:
	mode = m

func set_lock_target(t: Node3D) -> void:
	_lock_target = t

func on_mouse_look(relative: Vector2) -> void:
	_look_accum += relative

func get_yaw_basis() -> Basis:
	return Basis(Vector3.UP, _yaw)

func get_camera() -> Camera3D:
	return _camera

## Ray from the screen centre. Returns { position, hit }.
func cast_aim_ray(max_dist: float, mask: int, exclude: Array[RID]) -> Dictionary:
	var from := _camera.global_position
	var to := from + (-_camera.global_basis.z) * max_dist
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	q.collide_with_areas = true
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return {"position": to, "hit": false}
	return {"position": hit.position, "hit": true}

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
	if _target == null:
		return
	var tpos := _target.get_global_transform_interpolated().origin + target_offset
	global_position = global_position.lerp(tpos, 1.0 - exp(-follow_smoothing * delta))
	_update_rotation(delta)
	_apply_profile(delta)

func _update_rotation(delta: float) -> void:
	var min_p := deg_to_rad(min_pitch_deg)
	var max_p := deg_to_rad(max_pitch_deg)
	if mode == Mode.LOCK_ON and _lock_target != null and is_instance_valid(_lock_target):
		var to := _lock_point() - global_position
		var k := 1.0 - exp(-lock_turn_smoothing * delta)
		_yaw = lerp_angle(_yaw, atan2(-to.x, -to.z), k)
		var horiz := Vector2(to.x, to.z).length()
		var elev := atan2(to.y, maxf(horiz, 0.01))
		_pitch = lerpf(_pitch, clampf(deg_to_rad(lock_pitch_deg) + elev * 0.35, min_p, max_p), k)
		_look_accum = Vector2.ZERO
	else:
		var look := _look_accum * mouse_sensitivity + stick_look * stick_sensitivity * delta
		_look_accum = Vector2.ZERO
		_yaw -= look.x
		_pitch += look.y if invert_y else -look.y
		if follow_yaw_enabled and mode == Mode.FREE and look.length() < 0.0005:
			_yaw = lerp_angle(_yaw, follow_yaw, 1.0 - exp(-flow_follow_speed * delta))
		_pitch = clampf(_pitch, min_p, max_p)
	rotation.y = _yaw
	_pitch_pivot.rotation.x = _pitch

func _apply_profile(delta: float) -> void:
	var p := _profile_for(mode)
	var k := 1.0 - exp(-profile_blend_speed * delta)
	_spring.spring_length = lerpf(_spring.spring_length, p.distance, k)
	_camera.h_offset = lerpf(_camera.h_offset, p.shoulder, k)
	_pitch_pivot.position.y = lerpf(_pitch_pivot.position.y, p.height, k)
	_camera.fov = lerpf(_camera.fov, p.fov, k)

func _profile_for(m: Mode) -> CameraProfile:
	match m:
		Mode.LOCK_ON:
			return lock_profile
		Mode.AIM:
			return aim_profile
		Mode.OVERHEAD:
			return overhead_profile
	return free_profile

func _lock_point() -> Vector3:
	if _lock_target.has_method("get_lock_point"):
		return _lock_target.call("get_lock_point")
	return _lock_target.global_position + Vector3.UP
