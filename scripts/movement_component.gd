class_name MovementComponent extends Node
## Camera-relative movement: walk / run / flow / jump / charge-jump / double-jump / dash / air-dash.
## The model (ModelPivot) is rotated here; the CharacterBody3D itself never rotates.
## "Logical forward" is +Z of the ModelPivot.

signal landed
signal left_ground
signal jumped(kind: StringName)          # &"jump", &"charge_jump", &"double_jump"
signal dashed(in_air: bool)
signal dash_ready
signal flow_started
signal flow_ended
signal run_changed(running: bool)
signal jump_charge_changed(ratio: float)
signal air_dashes_changed(remaining: int)

enum Mode { NORMAL, FLOW, DASH }

@export_group("Walk / Run")
@export var walk_speed := 8.0
## Run multiplies the stick input strength
@export var run_multiplier := 1.5
@export var acceleration := 45.0
@export var deceleration := 55.0
@export_range(0.0, 1.0) var air_control := 0.6
@export var turn_smoothing := 14.0
## Run toggle switches itself off when you stop moving
@export var auto_cancel_run_on_stop := true

@export_group("Gravity")
@export var gravity_multiplier := 3.0
@export var max_fall_speed := 70.0
@export var coyote_time := 0.1

@export_group("Jump")
@export var jump_velocity := 12.0
@export var double_jump_velocity := 12.0
@export var max_air_jumps := 1
## Hold longer than this and it becomes a charge jump
@export var charge_jump_min_hold := 0.25
## Seconds to reach full charge (raise for a "very high" limit)
@export var charge_jump_max_hold := 2.5
@export var charge_jump_max_velocity := 45.0
@export_range(0.0, 1.0) var charge_move_scale := 0.3

@export_group("Dash")
@export var dash_speed := 30.0
@export var dash_duration := 0.22
@export var dash_cooldown := 1.0
@export var max_air_dashes := 1
@export_range(0.0, 1.0) var dash_exit_momentum := 0.35
@export var allow_dash_in_flow := false

@export_group("Flow")
@export var flow_multiplier := 3.0
@export var flow_launch_boost := 1.35
@export var flow_acceleration := 40.0
@export var flow_turn_rate := 2.2
@export var flow_hover_height := 1.3
@export var flow_hover_response := 8.0
@export_flags_3d_physics var hover_mask := 1

@export_group("Lock-on / Aim")
@export var lock_on_turn_smoothing := 8.0
@export var aim_turn_smoothing := 22.0

# ---- set from outside (Player glue) ----
var body: CharacterBody3D
var model: Node3D
var move_input := Vector2.ZERO
var reference_basis := Basis.IDENTITY     # camera yaw basis
var speed_multiplier := 1.0               # e.g. blade length penalty
var movement_scale := 1.0                 # attacks reduce this
var lock_target_point := Vector3.ZERO
var has_lock := false
var aim_facing := false

# ---- state (read-only for others) ----
var mode := Mode.NORMAL
var grounded := false
var run_enabled := false
var facing_yaw := 0.0
var plunging := false
var strafing: bool:
	get:
		return has_lock or aim_facing

var _charging := false
var _charge_time := 0.0
var _coyote := 0.0
var _air_jumps_left := 0
var _air_dashes_left := 0
var _dash_dir := Vector3.FORWARD
var _dash_time := 0.0
var _dash_cd := 0.0
var _flow_heading := 0.0
var _flow_stuck := 0.0
var _idle_time := 0.0
var _impulse_vel := Vector3.ZERO
var _impulse_time := 0.0
var _plunge_speed := 60.0
var _spinning := false
var _spin_total := 0.0
var _spin_time := 0.0
var _spin_duration := 0.5

func setup(p_body: CharacterBody3D, p_model: Node3D) -> void:
	body = p_body
	model = p_model
	_air_jumps_left = max_air_jumps
	_air_dashes_left = max_air_dashes

# ======================================================================
# Public queries
# ======================================================================
func get_facing_vector() -> Vector3:
	return Vector3(sin(facing_yaw), 0.0, cos(facing_yaw))

## x = right, y = forward, in m/s, relative to where the character faces
func get_local_velocity() -> Vector2:
	var v := Vector3(body.velocity.x, 0.0, body.velocity.z)
	var f := get_facing_vector()
	var r := f.cross(Vector3.UP)
	return Vector2(v.dot(r), v.dot(f))

func get_horizontal_speed() -> float:
	return Vector2(body.velocity.x, body.velocity.z).length()

func is_charging_jump() -> bool:
	return _charging

func get_dash_cooldown_left() -> float:
	return maxf(_dash_cd, 0.0)

# ======================================================================
# Input handlers (connected to InputComponent signals)
# ======================================================================
func on_run_toggled() -> void:
	if mode == Mode.FLOW:
		end_flow(true)
	elif mode == Mode.NORMAL:
		set_run(not run_enabled)

func on_flow_activated() -> void:
	if mode != Mode.NORMAL or plunging:
		return
	_cancel_charge()
	var dir := _wish_direction()
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		dir = get_facing_vector()
	_flow_heading = atan2(dir.x, dir.z)
	mode = Mode.FLOW
	var fwd := Vector3(sin(_flow_heading), 0.0, cos(_flow_heading))
	var v := fwd * walk_speed * flow_multiplier * flow_launch_boost * speed_multiplier
	body.velocity.x = v.x
	body.velocity.z = v.z
	_flow_stuck = 0.0
	flow_started.emit()

func end_flow(run_after: bool = true) -> void:
	if mode != Mode.FLOW:
		return
	mode = Mode.NORMAL
	set_run(run_after)
	flow_ended.emit()

func on_jump_pressed() -> void:
	if mode != Mode.NORMAL or plunging:
		return
	if grounded or _coyote > 0.0:
		_charging = true
		_charge_time = 0.0
	elif _air_jumps_left > 0:
		_air_jumps_left -= 1
		_launch_jump(double_jump_velocity, &"double_jump")

func on_jump_released() -> void:
	if not _charging:
		return
	var v := jump_velocity
	var kind := &"jump"
	if _charge_time >= charge_jump_min_hold:
		v = lerpf(jump_velocity, charge_jump_max_velocity, _charge_ratio())
		kind = &"charge_jump"
	_cancel_charge()
	_launch_jump(v, kind)

func on_dash_pressed() -> void:
	if mode == Mode.DASH or plunging or _dash_cd > 0.0:
		return
	if mode == Mode.FLOW and not allow_dash_in_flow:
		return
	var in_air := not grounded
	if in_air:
		if _air_dashes_left <= 0:
			return
		_air_dashes_left -= 1
		air_dashes_changed.emit(_air_dashes_left)
	var dir := _wish_direction()
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		dir = get_facing_vector()
	_cancel_charge()
	if mode == Mode.FLOW:
		end_flow(false)
	_dash_dir = dir.normalized()
	_dash_time = dash_duration
	_dash_cd = dash_cooldown
	mode = Mode.DASH
	body.velocity.y = 0.0
	dashed.emit(in_air)

# ======================================================================
# Called by other components (weapons etc.)
# ======================================================================
func set_run(value: bool) -> void:
	if run_enabled == value:
		return
	run_enabled = value
	run_changed.emit(value)

func start_impulse(velocity: Vector3, time: float) -> void:
	_impulse_vel = velocity
	_impulse_time = time

func snap_face_to_input() -> void:
	var wish := _wish_direction()
	if wish.length_squared() > 0.01 and not strafing:
		facing_yaw = atan2(wish.x, wish.z)

func start_spin(total_angle: float, duration: float) -> void:
	_spin_total = total_angle
	_spin_duration = maxf(duration, 0.01)
	_spin_time = 0.0
	_spinning = true

func start_plunge(speed: float) -> void:
	plunging = true
	_plunge_speed = speed
	_cancel_charge()

func stop_plunge() -> void:
	plunging = false

func reset_state() -> void:
	mode = Mode.NORMAL
	plunging = false
	_cancel_charge()
	_impulse_time = 0.0
	_spinning = false
	movement_scale = 1.0
	if body:
		body.velocity = Vector3.ZERO

# ======================================================================
# Main tick (called from Player._physics_process)
# ======================================================================
func tick(delta: float) -> void:
	if body == null:
		return
	_tick_timers(delta)
	var wish := _wish_direction()
	match mode:
		Mode.FLOW:
			_tick_flow(delta)
		Mode.DASH:
			_tick_dash(delta)
		_:
			_tick_normal(delta, wish)
	if _impulse_time > 0.0 and mode != Mode.DASH:
		_impulse_time -= delta
		body.velocity.x = _impulse_vel.x
		body.velocity.z = _impulse_vel.z
	body.move_and_slide()
	_after_move(delta)
	_update_facing(delta, wish)

func _wish_direction() -> Vector3:
	var v := move_input
	if v.length() > 1.0:
		v = v.normalized()
	return reference_basis * Vector3(v.x, 0.0, v.y)

func _tick_timers(delta: float) -> void:
	if _coyote > 0.0:
		_coyote -= delta
	if _dash_cd > 0.0:
		_dash_cd -= delta
		if _dash_cd <= 0.0:
			dash_ready.emit()
	if _charging:
		_charge_time += delta
		jump_charge_changed.emit(_charge_ratio())
		if not grounded and _coyote <= 0.0:
			_cancel_charge()
	if run_enabled and auto_cancel_run_on_stop and mode == Mode.NORMAL:
		if move_input.length() < 0.1:
			_idle_time += delta
			if _idle_time > 0.2:
				set_run(false)
		else:
			_idle_time = 0.0

func _tick_normal(delta: float, wish: Vector3) -> void:
	var run_mult := run_multiplier if run_enabled else 1.0
	var target := wish * walk_speed * run_mult * speed_multiplier * movement_scale
	if _charging:
		target *= charge_move_scale
	var h := Vector3(body.velocity.x, 0.0, body.velocity.z)
	var rate := acceleration if wish.length_squared() > 0.0001 else deceleration
	if not grounded:
		rate *= air_control
	h = h.move_toward(target, rate * delta)
	var vy := body.velocity.y
	if plunging:
		h = Vector3.ZERO
		vy = -_plunge_speed
	elif not grounded:
		vy = maxf(vy + body.get_gravity().y * gravity_multiplier * delta, -max_fall_speed)
	body.velocity = Vector3(h.x, vy, h.z)

func _tick_flow(delta: float) -> void:
	# Flow: constant forward motion, only left/right steering
	_flow_heading -= move_input.x * flow_turn_rate * delta
	var fwd := Vector3(sin(_flow_heading), 0.0, cos(_flow_heading))
	var target := fwd * walk_speed * flow_multiplier * speed_multiplier * movement_scale
	var h := Vector3(body.velocity.x, 0.0, body.velocity.z).move_toward(target, flow_acceleration * delta)
	body.velocity = Vector3(h.x, _hover_velocity(), h.z)

func _hover_velocity() -> float:
	var from := body.global_position + Vector3.UP * 0.5
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 40.0, hover_mask, [body.get_rid()])
	var hit: Dictionary = body.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return body.velocity.y * 0.9
	var target_y: float = hit.position.y + flow_hover_height
	return clampf((target_y - body.global_position.y) * flow_hover_response, -25.0, 25.0)

func _tick_dash(delta: float) -> void:
	_dash_time -= delta
	body.velocity = Vector3(_dash_dir.x * dash_speed, 0.0, _dash_dir.z * dash_speed)
	if _dash_time <= 0.0:
		mode = Mode.NORMAL
		body.velocity = Vector3(_dash_dir.x, 0.0, _dash_dir.z) * dash_speed * dash_exit_momentum

func _after_move(delta: float) -> void:
	var now := body.is_on_floor()
	if now and not grounded:
		grounded = true
		_air_jumps_left = max_air_jumps
		_air_dashes_left = max_air_dashes
		air_dashes_changed.emit(_air_dashes_left)
		plunging = false
		landed.emit()
	elif not now and grounded:
		grounded = false
		_coyote = coyote_time
		left_ground.emit()
	if mode == Mode.FLOW:
		if body.is_on_wall() and get_horizontal_speed() < walk_speed * 0.5:
			_flow_stuck += delta
		else:
			_flow_stuck = 0.0
		if _flow_stuck > 0.25:
			end_flow(true)

func _update_facing(delta: float, wish: Vector3) -> void:
	var target := facing_yaw
	var smoothing := turn_smoothing
	if mode == Mode.FLOW:
		target = _flow_heading
		smoothing = 30.0
	elif has_lock:
		var d := lock_target_point - body.global_position
		d.y = 0.0
		if d.length_squared() > 0.01:
			target = atan2(d.x, d.z)
		smoothing = lock_on_turn_smoothing
	elif aim_facing:
		var f := -reference_basis.z
		target = atan2(f.x, f.z)
		smoothing = aim_turn_smoothing
	elif mode == Mode.DASH:
		target = atan2(_dash_dir.x, _dash_dir.z)
	elif wish.length_squared() > 0.01:
		target = atan2(wish.x, wish.z)
	facing_yaw = lerp_angle(facing_yaw, target, 1.0 - exp(-smoothing * delta))
	model.rotation.y = facing_yaw + _spin_offset(delta)

func _spin_offset(delta: float) -> float:
	if not _spinning:
		return 0.0
	_spin_time += delta
	if _spin_time >= _spin_duration:
		_spinning = false
		return 0.0
	return _spin_total * (_spin_time / _spin_duration)

func _launch_jump(v: float, kind: StringName) -> void:
	body.velocity.y = v
	grounded = false
	_coyote = 0.0
	jumped.emit(kind)

func _charge_ratio() -> float:
	var span := maxf(charge_jump_max_hold - charge_jump_min_hold, 0.01)
	return clampf((_charge_time - charge_jump_min_hold) / span, 0.0, 1.0)

func _cancel_charge() -> void:
	if _charging:
		_charging = false
		jump_charge_changed.emit(0.0)
