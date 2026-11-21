class_name IKComponent extends Node
## Finds the model's Skeleton3D and adds BoneAimModifier nodes to it (no manual setup):
##  - arms aim at the launcher target (works over walk / run / strafe animations)
##  - spine / neck / head twist toward the lock-on target
## Bone names are matched by SUFFIX, so "mixamorig:RightArm" and "mixamorig_RightArm" both match "RightArm".

@export var skeleton: Skeleton3D          # optional, auto-found under ModelPivot
@export var right_arm_bone := "RightArm"
@export var right_forearm_bone := "RightForeArm"
@export var right_hand_bone := "RightHand"
@export var left_arm_bone := "LeftArm"
@export var left_forearm_bone := "LeftForeArm"
@export var left_hand_bone := "LeftHand"
@export var spine_lower_bone := "Spine1"
@export var spine_upper_bone := "Spine2"
@export var neck_bone := "Neck"
@export var head_bone := "Head"
@export var lock_on_max_twist_deg := 70.0
@export var blend_speed := 10.0

var lock_active := false
var lock_point := Vector3.ZERO

var _model_pivot: Node3D
var _twists: Array[BoneAimModifier] = []
var _right: BoneAimModifier
var _left: BoneAimModifier
var _right_hand := -1
var _left_hand := -1
var _right_active := false
var _left_active := false
var _aim_point := Vector3.ZERO
var _lock_w := 0.0
var _right_w := 0.0
var _left_w := 0.0

func setup(model_pivot: Node3D) -> void:
	_model_pivot = model_pivot
	if skeleton == null:
		var found := model_pivot.find_children("*", "Skeleton3D", true, false)
		if found.size() > 0:
			skeleton = found[0] as Skeleton3D
	if skeleton == null:
		push_warning("IKComponent: no Skeleton3D found under ModelPivot. IK disabled.")
		return
	var max_yaw := deg_to_rad(lock_on_max_twist_deg)
	_add_twist(spine_lower_bone, 0.2, max_yaw)
	_add_twist(spine_upper_bone, 0.3, max_yaw)
	_add_twist(neck_bone, 0.2, max_yaw)
	_add_twist(head_bone, 0.3, max_yaw)
	_right = _add_arm(right_arm_bone, right_forearm_bone)
	_left = _add_arm(left_arm_bone, left_forearm_bone)
	_right_hand = _find_bone(right_hand_bone)
	_left_hand = _find_bone(left_hand_bone)

func set_aim(right_on: bool, left_on: bool, point: Vector3) -> void:
	_right_active = right_on
	_left_active = left_on
	_aim_point = point

## World position of a hand bone, or Vector3.INF if unavailable
func get_hand_position(right: bool) -> Vector3:
	var idx := _right_hand if right else _left_hand
	if skeleton == null or idx < 0:
		return Vector3.INF
	return skeleton.to_global(skeleton.get_bone_global_pose(idx).origin)

func _process(delta: float) -> void:
	if skeleton == null:
		return
	var k := 1.0 - exp(-blend_speed * delta)
	_lock_w = lerpf(_lock_w, 1.0 if lock_active else 0.0, k)
	var fwd := _model_pivot.global_basis.z
	for m in _twists:
		m.influence = _lock_w
		m.active = _lock_w > 0.01
		m.target_global = lock_point
		m.reference_forward = fwd
	_right_w = lerpf(_right_w, 1.0 if _right_active else 0.0, k)
	_left_w = lerpf(_left_w, 1.0 if _left_active else 0.0, k)
	_drive_arm(_right, _right_w)
	_drive_arm(_left, _left_w)

func _drive_arm(m: BoneAimModifier, w: float) -> void:
	if m == null:
		return
	m.influence = w
	m.active = w > 0.01
	m.target_global = _aim_point

func _add_twist(suffix: String, share: float, max_yaw: float) -> void:
	var idx := _find_bone(suffix)
	if idx < 0:
		push_warning("IKComponent: bone '%s' not found" % suffix)
		return
	var m := BoneAimModifier.new()
	m.name = "Twist_" + suffix
	m.mode = BoneAimModifier.Mode.YAW_TWIST
	m.bone_index = idx
	m.yaw_share = share
	m.max_yaw = max_yaw
	m.influence = 0.0
	m.active = false
	skeleton.add_child(m)
	_twists.append(m)

func _add_arm(arm: String, forearm: String) -> BoneAimModifier:
	var a := _find_bone(arm)
	var f := _find_bone(forearm)
	if a < 0 or f < 0:
		push_warning("IKComponent: arm bones '%s'/'%s' not found" % [arm, forearm])
		return null
	var m := BoneAimModifier.new()
	m.name = "Aim_" + arm
	m.mode = BoneAimModifier.Mode.POINT_AXIS
	m.bone_index = a
	m.child_index = f
	m.influence = 0.0
	m.active = false
	skeleton.add_child(m)
	return m

func _find_bone(suffix: String) -> int:
	for i in skeleton.get_bone_count():
		if skeleton.get_bone_name(i).ends_with(suffix):
			return i
	return -1
