class_name WeaponComponent extends Node
## Piercer: melee (arm blades) + launcher (single / dual). All timing is code-driven, so it
## works with zero animations; animations just listen to attack_started / attack_finished.

signal mode_changed(mode: Mode)
signal attack_started(attack_id: StringName)
signal attack_finished(attack_id: StringName)
signal hit_landed(target: Node, damage: float)
signal charge_changed(ratio: float)
signal charge_maxed
signal dual_charge_changed(ratio: float)
signal launcher_fired(dual: bool)
signal launcher_cooldown_changed(remaining: float, total: float)
signal launcher_ready

enum Mode { UNARMED, MELEE, LAUNCHER, LAUNCHER_DUAL }

@export_group("Piercer customisation")
## 0 = short blade (fast, weak)  ...  1 = long blade (slow, strong)
@export_range(0.0, 1.0) var blade_length := 0.5
@export var min_damage_scale := 0.6
@export var max_damage_scale := 1.6
@export var max_speed_scale := 1.15
@export var min_speed_scale := 0.85

@export_group("Melee attacks (leave empty for defaults)")
@export var slash_1: AttackData
@export var slash_2: AttackData
@export var air_slash: AttackData
@export var run_stab: AttackData
@export var flow_attack: AttackData
@export var charge_attack: AttackData
@export var plunge_attack: AttackData
@export var combo_window := 0.4
## Hold attack this long in air = plunge, in Flow = charge attack
@export var hold_threshold := 0.25
@export var charge_max_time := 1.5
@export var charge_max_damage_scale := 3.0
@export var plunge_speed := 60.0

@export_group("Launcher")
@export var launcher_damage := 40.0
## Base 60s. Lower while testing.
@export var launcher_cooldown := 60.0
@export var melee_cooldown_reduction := 4.0
@export var dual_hold_time := 5.0
@export var projectile_speed := 80.0
@export var aim_range := 150.0
@export_flags_3d_physics var aim_mask := 21
@export var laser_color := Color(1.0, 0.1, 0.1)

var mode := Mode.UNARMED
var aim_point := Vector3.ZERO

var _body: CharacterBody3D
var _movement: MovementComponent
var _camera: CameraComponent
var _hitbox: HitboxComponent
var _ik: IKComponent
var _lock_on: LockOnComponent

var _attack: AttackData
var _attack_time := 0.0
var _damage_mult := 1.0
var _combo_index := 0
var _combo_timer := 0.0
var _buffered := false
var _attack_held := false
var _attack_hold_time := 0.0
var _hold_decided := true
var _charging := false
var _charge_time := 0.0
var _charge_maxed := false
var _plunge_diving := false

var _cooldown := 0.0
var _dual_armed := false
var _dual_time := 0.0
var _prev_melee := false
var _lasers: Array[MeshInstance3D] = []
var _dots: Array[MeshInstance3D] = []

func _ready() -> void:
	if slash_1 == null:
		slash_1 = AttackData.make(&"slash_1", 12.0, 0.45, 0.12, 0.32, 5.0)
	if slash_2 == null:
		slash_2 = AttackData.make(&"slash_2", 14.0, 0.5, 0.14, 0.34, 5.0)
	if air_slash == null:
		air_slash = AttackData.make(&"air_slash", 16.0, 0.5, 0.05, 0.45, 0.0, 0.0, Vector3(3.2, 1.8, 3.2), Vector3(0.0, 1.0, 0.0), 1.0)
	if run_stab == null:
		run_stab = AttackData.make(&"run_stab", 18.0, 0.5, 0.1, 0.3, 16.0, 0.25, Vector3(1.0, 1.2, 2.4), Vector3(0.0, 1.0, 1.4), 1.0)
	if flow_attack == null:
		flow_attack = AttackData.make(&"flow_attack", 25.0, 0.6, 0.05, 0.5, 38.0, 0.45, Vector3(1.6, 1.6, 3.0), Vector3(0.0, 1.0, 1.5), 1.0)
	if charge_attack == null:
		charge_attack = AttackData.make(&"charge_attack", 45.0, 0.8, 0.0, 0.65, 42.0, 0.55, Vector3(3.0, 2.2, 3.5), Vector3(0.0, 1.0, 1.4), 0.0)
	if plunge_attack == null:
		plunge_attack = AttackData.make(&"plunge", 30.0, 0.45, 0.0, 0.3, 0.0, 0.0, Vector3(3.5, 1.6, 3.5), Vector3(0.0, 0.6, 0.0), 0.0)
	for i in 2:
		var laser := _make_laser()
		_lasers.append(laser)
		_dots.append(laser.get_child(0) as MeshInstance3D)

func setup(body: CharacterBody3D, movement: MovementComponent, camera: CameraComponent, hitbox: HitboxComponent, ik: IKComponent, lock_on: LockOnComponent) -> void:
	_body = body
	_movement = movement
	_camera = camera
	_hitbox = hitbox
	_ik = ik
	_lock_on = lock_on
	_hitbox.source = body
	_hitbox.hit.connect(_on_hitbox_hit)
	_movement.landed.connect(_on_landed)

# ======================================================================
# Queries
# ======================================================================
func is_launcher_mode() -> bool:
	return mode == Mode.LAUNCHER or mode == Mode.LAUNCHER_DUAL

func get_damage_scale() -> float:
	return lerpf(min_damage_scale, max_damage_scale, blade_length)

## Movement penalty of a long blade (only while blades are out in melee mode)
func get_speed_scale() -> float:
	if mode != Mode.MELEE:
		return 1.0
	return lerpf(max_speed_scale, min_speed_scale, blade_length)

func get_cooldown_left() -> float:
	return _cooldown

func _busy() -> bool:
	return _attack != null or _charging

# ======================================================================
# Input handlers
# ======================================================================
func toggle_blades() -> void:
	if _body == null or _busy() or is_launcher_mode():
		return
	_set_mode(Mode.UNARMED if mode == Mode.MELEE else Mode.MELEE)

func on_launcher_pressed() -> void:
	if _body == null or _busy():
		return
	if is_launcher_mode():
		_dual_armed = true
		_dual_time = 0.0
	else:
		_prev_melee = mode == Mode.MELEE
		_set_mode(Mode.LAUNCHER)

func on_launcher_released() -> void:
	if _dual_armed:
		_dual_armed = false
		dual_charge_changed.emit(0.0)
		_set_mode(Mode.MELEE if _prev_melee else Mode.UNARMED)

func on_attack_pressed() -> void:
	if _body == null:
		return
	if is_launcher_mode():
		_fire()
	elif mode == Mode.MELEE:
		_attack_held = true
		_attack_hold_time = 0.0
		_hold_decided = false
		if _movement.mode == MovementComponent.Mode.FLOW or not _movement.grounded:
			return  # decided on hold / release
		_try_ground_attack()

func on_attack_released() -> void:
	_attack_held = false
	if _charging:
		_release_charge()
		return
	if mode == Mode.MELEE and not _hold_decided:
		_hold_decided = true
		_tap_special()

func on_died() -> void:
	cancel_all()
	_set_mode(Mode.UNARMED)

func cancel_all() -> void:
	if _hitbox:
		_hitbox.set_active(false)
	_attack = null
	_charging = false
	_plunge_diving = false
	_attack_held = false
	_dual_armed = false
	if _movement:
		_movement.stop_plunge()
		_movement.movement_scale = 1.0
	attack_finished.emit(&"")

# ======================================================================
# Ticks
# ======================================================================
func _physics_process(delta: float) -> void:
	if _body == null:
		return
	if _cooldown > 0.0:
		_cooldown = maxf(_cooldown - delta, 0.0)
		launcher_cooldown_changed.emit(_cooldown, launcher_cooldown)
		if _cooldown == 0.0:
			launcher_ready.emit()
	if _combo_timer > 0.0:
		_combo_timer -= delta
	if _dual_armed and mode == Mode.LAUNCHER:
		_dual_time += delta
		dual_charge_changed.emit(clampf(_dual_time / maxf(dual_hold_time, 0.01), 0.0, 1.0))
		if _dual_time >= dual_hold_time:
			_dual_armed = false
			dual_charge_changed.emit(0.0)
			_set_mode(Mode.LAUNCHER_DUAL)
	if mode == Mode.MELEE and _attack_held and not _hold_decided:
		_attack_hold_time += delta
		if _attack_hold_time >= hold_threshold:
			_hold_decided = true
			_hold_action()
	if _charging:
		_tick_charge(delta)
	_tick_attack(delta)

func _process(_delta: float) -> void:
	_update_aim()

# ======================================================================
# Melee
# ======================================================================
func _try_ground_attack() -> void:
	_hold_decided = true
	if _attack != null:
		_buffered = true
		return
	if _movement.run_enabled and _movement.move_input.length() > 0.2:
		_start_attack(run_stab)
		return
	var idx := _combo_index if _combo_timer > 0.0 else 0
	_start_attack(slash_1 if idx % 2 == 0 else slash_2)
	_combo_index = idx + 1

func _tap_special() -> void:
	if _attack != null:
		return
	if _movement.mode == MovementComponent.Mode.FLOW:
		_start_attack(flow_attack)
	elif not _movement.grounded:
		_start_attack(air_slash, TAU)

func _hold_action() -> void:
	if _attack != null:
		return
	if _movement.mode == MovementComponent.Mode.FLOW:
		_begin_charge()
	elif not _movement.grounded:
		_begin_plunge()

func _start_attack(data: AttackData, spin := 0.0, damage_mult := 1.0) -> void:
	_attack = data
	_attack_time = 0.0
	_buffered = false
	_damage_mult = damage_mult
	_hitbox.configure(data.hitbox_size, data.hitbox_offset, data.damage * get_damage_scale() * damage_mult)
	_hitbox.set_active(false)
	_movement.movement_scale = data.move_scale
	_movement.snap_face_to_input()
	if data.lunge_speed > 0.0:
		_movement.start_impulse(_movement.get_facing_vector() * data.lunge_speed, data.lunge_time)
	if spin != 0.0:
		_movement.start_spin(spin, data.duration)
	attack_started.emit(data.id)

func _tick_attack(delta: float) -> void:
	if _attack == null:
		return
	if _plunge_diving:
		_hitbox.set_active(true)   # dive hurts too; landing resets the hit list
		return
	_attack_time += delta
	_hitbox.set_active(_attack_time >= _attack.hit_start and _attack_time <= _attack.hit_end)
	if _attack_time >= _attack.duration:
		_finish_attack()

func _finish_attack() -> void:
	var id := _attack.id
	_hitbox.set_active(false)
	_movement.movement_scale = 1.0
	_attack = null
	_combo_timer = combo_window
	attack_finished.emit(id)
	if _buffered:
		_buffered = false
		if _movement.grounded and mode == Mode.MELEE:
			_try_ground_attack()

func _begin_charge() -> void:
	_charging = true
	_charge_time = 0.0
	_charge_maxed = false
	_movement.movement_scale = 0.35
	attack_started.emit(&"charge_windup")
	charge_changed.emit(0.0)

func _tick_charge(delta: float) -> void:
	if _movement.mode != MovementComponent.Mode.FLOW:
		_charging = false
		_movement.movement_scale = 1.0
		charge_changed.emit(0.0)
		attack_finished.emit(&"charge_windup")
		return
	_charge_time += delta
	var r := clampf(_charge_time / maxf(charge_max_time, 0.01), 0.0, 1.0)
	charge_changed.emit(r)
	if r >= 1.0 and not _charge_maxed:
		_charge_maxed = true
		charge_maxed.emit()

func _release_charge() -> void:
	var r := clampf(_charge_time / maxf(charge_max_time, 0.01), 0.0, 1.0)
	_charging = false
	charge_changed.emit(0.0)
	_movement.movement_scale = 1.0
	_movement.end_flow(false)   # charge attack ends the supersprint
	_start_attack(charge_attack, TAU * 2.0, lerpf(1.0, charge_max_damage_scale, r))

func _begin_plunge() -> void:
	_plunge_diving = true
	_start_attack(plunge_attack)
	_movement.start_plunge(plunge_speed)

func _on_landed() -> void:
	if _plunge_diving:
		_plunge_diving = false
		_attack_time = 0.0
		_hitbox.clear_hits()   # slam can hit again

func _on_hitbox_hit(hurtbox: HurtboxComponent, dmg: float) -> void:
	_cooldown = maxf(_cooldown - melee_cooldown_reduction, 0.0)
	hit_landed.emit(hurtbox.get_parent(), dmg)

# ======================================================================
# Launcher
# ======================================================================
func _fire() -> void:
	if _cooldown > 0.0:
		return
	var dual := mode == Mode.LAUNCHER_DUAL
	var origins: Array[Vector3] = [_muzzle(true)]
	if dual:
		origins.append(_muzzle(false))
	var ex: Array[RID] = [_body.get_rid()]
	for o in origins:
		var p := PiercerProjectile.new()
		p.damage = launcher_damage
		p.speed = projectile_speed
		p.collision_mask = aim_mask
		p.exclude = ex
		get_tree().current_scene.add_child(p)
		p.launch(o, aim_point - o, _body)
	_cooldown = launcher_cooldown
	launcher_fired.emit(dual)
	launcher_cooldown_changed.emit(_cooldown, launcher_cooldown)

func _muzzle(right: bool) -> Vector3:
	if _ik:
		var hand := _ik.get_hand_position(right)
		if hand.is_finite():
			return hand + (aim_point - hand).normalized() * 0.45
	var side := _movement.get_facing_vector().cross(Vector3.UP) * (0.3 if right else -0.3)
	return _body.global_position + Vector3.UP * 1.3 + side + _movement.get_facing_vector() * 0.4

func _update_aim() -> void:
	if _body == null:
		return
	if not is_launcher_mode():
		for l in _lasers:
			l.visible = false
		if _ik:
			_ik.set_aim(false, false, Vector3.ZERO)
		return
	if _lock_on and _lock_on.has_target():
		aim_point = _lock_on.get_target_point()
	else:
		var ex: Array[RID] = [_body.get_rid()]
		aim_point = _camera.cast_aim_ray(aim_range, aim_mask, ex)["position"]
	var dual := mode == Mode.LAUNCHER_DUAL
	if _ik:
		_ik.set_aim(true, dual, aim_point)
	_set_laser(0, _muzzle(true))
	if dual:
		_set_laser(1, _muzzle(false))
	else:
		_lasers[1].visible = false

func _set_laser(i: int, from: Vector3) -> void:
	var ex: Array[RID] = [_body.get_rid()]
	var q := PhysicsRayQueryParameters3D.create(from, aim_point, aim_mask, ex)
	q.collide_with_areas = true
	var hit: Dictionary = _body.get_world_3d().direct_space_state.intersect_ray(q)
	var to: Vector3 = hit.position if not hit.is_empty() else aim_point
	var v := to - from
	var length := v.length()
	var laser := _lasers[i]
	if length < 0.05:
		laser.visible = false
		return
	var dir := v / length
	var q_rot := Quaternion(Vector3.UP, dir) if dir.dot(Vector3.UP) > -0.9999 else Quaternion(Vector3.RIGHT, PI)
	laser.visible = true
	(laser.mesh as CylinderMesh).height = length
	laser.global_transform = Transform3D(Basis(q_rot), from + v * 0.5)
	_dots[i].position = Vector3(0.0, length * 0.5, 0.0)

func _make_laser() -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = laser_color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.008
	cyl.bottom_radius = 0.008
	cyl.radial_segments = 6
	cyl.rings = 1
	cyl.height = 1.0
	cyl.material = mat
	var laser := MeshInstance3D.new()
	laser.mesh = cyl
	laser.top_level = true
	laser.visible = false
	laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sphere := SphereMesh.new()
	sphere.radius = 0.05
	sphere.height = 0.1
	sphere.material = mat
	var dot := MeshInstance3D.new()
	dot.mesh = sphere
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	laser.add_child(dot)
	add_child(laser)
	return laser

func _set_mode(m: Mode) -> void:
	if m == mode:
		return
	mode = m
	if m != Mode.MELEE and (_attack != null or _charging):
		cancel_all()
	mode_changed.emit(m)
