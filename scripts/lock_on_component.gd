class_name LockOnComponent extends Node
## Elden-Ring style lock-on. Anything in the "lockable" group can be targeted.
## Targets may implement get_lock_point() -> Vector3 and is_lockable() -> bool.

signal target_changed(target: Node3D)   # null when released

@export var max_range := 30.0
@export var break_range := 40.0
@export var group_name := &"lockable"
## Higher = prefers enemies near the screen centre over merely the closest
@export var angle_weight := 8.0

var target: Node3D
var _body: Node3D
var _camera: CameraComponent

func setup(body: Node3D, camera: CameraComponent) -> void:
	_body = body
	_camera = camera

func has_target() -> bool:
	return target != null and is_instance_valid(target)

func toggle() -> void:
	if has_target():
		release()
	else:
		acquire()

func acquire() -> bool:
	var best: Node3D = null
	var best_score := INF
	for n in get_tree().get_nodes_in_group(group_name):
		var t := n as Node3D
		if t == null or not _valid_target(t):
			continue
		var d := t.global_position.distance_to(_body.global_position)
		if d > max_range:
			continue
		var score := d + absf(_angle_to(t)) * angle_weight
		if score < best_score:
			best_score = score
			best = t
	if best:
		_set_target(best)
		return true
	return false

func release() -> void:
	_set_target(null)

## direction: +1 = target to the right, -1 = to the left
func cycle(direction: int) -> void:
	if not has_target():
		return
	var current := _angle_to(target)
	var best: Node3D = null
	var best_delta := INF
	for n in get_tree().get_nodes_in_group(group_name):
		var t := n as Node3D
		if t == null or t == target or not _valid_target(t):
			continue
		if t.global_position.distance_to(_body.global_position) > max_range:
			continue
		# positive angle = left of camera forward, so "right" means smaller angle
		var diff := (current - _angle_to(t)) * float(direction)
		if diff > 0.001 and diff < best_delta:
			best_delta = diff
			best = t
	if best:
		_set_target(best)

func get_target_point() -> Vector3:
	if not has_target():
		return Vector3.ZERO
	if target.has_method("get_lock_point"):
		return target.call("get_lock_point")
	return target.global_position + Vector3.UP

func _physics_process(_delta: float) -> void:
	if target == null:
		return
	if not is_instance_valid(target) or not _valid_target(target) or target.global_position.distance_to(_body.global_position) > break_range:
		release()

func _valid_target(t: Node3D) -> bool:
	return not t.has_method("is_lockable") or t.call("is_lockable")

func _angle_to(t: Node3D) -> float:
	var fwd := -_camera.get_yaw_basis().z
	var to := t.global_position - _body.global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return 0.0
	return fwd.signed_angle_to(to.normalized(), Vector3.UP)

func _set_target(t: Node3D) -> void:
	if t == target:
		return
	target = t
	target_changed.emit(t)
