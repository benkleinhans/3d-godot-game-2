class_name AttackData extends Resource
## One melee attack. Times are seconds. Hitbox offset/size are relative to the model (+Z = forward).

@export var id: StringName = &"slash_1"
@export var damage := 12.0
@export var duration := 0.45
@export var hit_start := 0.1
@export var hit_end := 0.3
@export var lunge_speed := 5.0
@export var lunge_time := 0.15
## 0..1 how much walking is allowed during the attack
@export var move_scale := 0.3
@export var hitbox_size := Vector3(1.8, 1.5, 1.6)
@export var hitbox_offset := Vector3(0.0, 1.0, 1.0)

static func make(p_id: StringName, p_damage: float, p_duration: float, p_hit_start: float, p_hit_end: float, p_lunge: float, p_lunge_time := 0.15, p_size := Vector3(1.8, 1.5, 1.6), p_offset := Vector3(0.0, 1.0, 1.0), p_move_scale := 0.3) -> AttackData:
	var a := AttackData.new()
	a.id = p_id
	a.damage = p_damage
	a.duration = p_duration
	a.hit_start = p_hit_start
	a.hit_end = p_hit_end
	a.lunge_speed = p_lunge
	a.lunge_time = p_lunge_time
	a.hitbox_size = p_size
	a.hitbox_offset = p_offset
	a.move_scale = p_move_scale
	return a
