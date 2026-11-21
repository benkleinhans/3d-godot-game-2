class_name BoneAimModifier extends SkeletonModifier3D
## Tiny procedural "IK" modifier (needs Godot 4.3+ SkeletonModifier3D). Created by IKComponent.
##  POINT_AXIS: rotates a bone so the segment toward its child points at target_global (arms)
##  YAW_TWIST : twists a bone about world-up toward target_global, clamped (spine / neck / head)
## Blend with the built-in `influence` property.

enum Mode { POINT_AXIS, YAW_TWIST }

var mode := Mode.POINT_AXIS
var bone_index := -1
var child_index := -1
var straighten_child := true
var target_global := Vector3.ZERO
var reference_forward := Vector3.BACK     # YAW_TWIST: direction the character logically faces
var yaw_share := 1.0
var max_yaw := deg_to_rad(80.0)

var _last_usec := 0

func _process_modification() -> void:
	_apply()

func _process_modification_with_delta(_delta: float) -> void:
	_apply()

func _apply() -> void:
	# some engine versions call both virtuals in one dispatch; only run once
	var now := Time.get_ticks_usec()
	if now - _last_usec < 300:
		return
	_last_usec = now
	var sk := get_skeleton()
	if sk == null or bone_index < 0:
		return
	if mode == Mode.POINT_AXIS:
		_point_axis(sk)
	else:
		_yaw_twist(sk)

func _point_axis(sk: Skeleton3D) -> void:
	if child_index < 0:
		return
	if straighten_child:
		sk.set_bone_pose_rotation(child_index, sk.get_bone_rest(child_index).basis.get_rotation_quaternion())
	var gp := sk.get_bone_global_pose(bone_index)
	var axis_local := sk.get_bone_rest(child_index).origin.normalized()
	var current := (gp.basis * axis_local).normalized()
	var want := sk.to_local(target_global) - gp.origin
	if want.length_squared() < 0.0001:
		return
	var q := _arc(current, want.normalized())
	sk.set_bone_global_pose(bone_index, Transform3D(Basis(q) * gp.basis, gp.origin))

func _yaw_twist(sk: Skeleton3D) -> void:
	var to := target_global - sk.global_position
	to.y = 0.0
	var f := reference_forward
	f.y = 0.0
	if to.length_squared() < 0.01 or f.length_squared() < 0.01:
		return
	var err := f.normalized().signed_angle_to(to.normalized(), Vector3.UP)
	var twist := clampf(err, -max_yaw, max_yaw) * yaw_share
	var up_local := (sk.global_transform.basis.inverse() * Vector3.UP).normalized()
	var gp := sk.get_bone_global_pose(bone_index)
	sk.set_bone_global_pose(bone_index, Transform3D(Basis(up_local, twist) * gp.basis, gp.origin))

static func _arc(a: Vector3, b: Vector3) -> Quaternion:
	if a.dot(b) < -0.9999:
		var axis := a.cross(Vector3.UP)
		if axis.length_squared() < 0.001:
			axis = a.cross(Vector3.RIGHT)
		return Quaternion(axis.normalized(), PI)
	return Quaternion(a, b)
