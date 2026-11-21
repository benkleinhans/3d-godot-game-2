class_name HitboxComponent extends Area3D
## Deals damage to HurtboxComponents while active. Box shape is created in code.
## Each hurtbox is hit once per activation.

signal hit(hurtbox: HurtboxComponent, damage: float)

@export var damage := 10.0
@export var knockback := 6.0
var source: Node

var _active := false
var _box := BoxShape3D.new()
var _shape := CollisionShape3D.new()
var _hit_list: Array[HurtboxComponent] = []

func _ready() -> void:
	_shape.shape = _box
	add_child(_shape)
	monitorable = false
	monitoring = false

func configure(size: Vector3, offset: Vector3, dmg: float) -> void:
	_box.size = size
	_shape.position = offset
	damage = dmg

func set_active(on: bool) -> void:
	if on == _active:
		return
	_active = on
	monitoring = on
	if on:
		_hit_list.clear()

func clear_hits() -> void:
	_hit_list.clear()

func _physics_process(_delta: float) -> void:
	if not _active:
		return
	for a in get_overlapping_areas():
		if a is HurtboxComponent and not _hit_list.has(a):
			_hit_list.append(a)
			var dir: Vector3 = a.global_position - global_position
			dir.y = 0.0
			a.take_hit(damage, source, dir.normalized() * knockback)
			hit.emit(a, damage)
