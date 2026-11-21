class_name Enemy extends CharacterBody3D
## Stationary test dummy. Health + size follow the spec:
##   SMALL 0.5x size / 0.5x HP, MEDIUM 1x / 1x, LARGE 2x / 2x, OUTLIER 0.25x size / 4x HP.
## Uses HealthComponent, HurtboxComponent and a StateMachine, ready for roam/chase/attack states.

enum EnemySize { SMALL, MEDIUM, LARGE, OUTLIER }

@export var enemy_size := EnemySize.MEDIUM
@export var player_health := 100.0
@export var base_height := 1.8
@export var base_radius := 0.4
## Seconds until a dead dummy comes back. 0 = stays gone.
@export var respawn_time := 5.0
@export var gravity_multiplier := 3.0
@export var body_color := Color(0.75, 0.2, 0.25)
@export var knockback_scale := 1.0

@onready var health: HealthComponent = %HealthComponent
@onready var hurtbox: HurtboxComponent = %HurtboxComponent
@onready var health_bar: HealthBar3D = %HealthBar
@onready var body_mesh: MeshInstance3D = %BodyMesh
@onready var body_shape: CollisionShape3D = %BodyShape
@onready var hurtbox_shape: CollisionShape3D = %HurtboxShape
@onready var state_machine: StateMachine = %StateMachine

var size_scale := 1.0
var weight := 1.0
var desired_velocity := Vector3.ZERO      # written by states
var knockback_velocity := Vector3.ZERO
var last_hit_velocity := Vector3.ZERO
var player: Node3D
var is_dead := false

var _material := StandardMaterial3D.new()
var _spawn := Vector3.ZERO

func _ready() -> void:
	add_to_group("lockable")
	add_to_group("enemy")
	_spawn = global_position
	_apply_size()
	health_bar.bind(health)
	health.died.connect(_on_died)
	hurtbox.hit_received.connect(_on_hit_received)
	player = get_tree().get_first_node_in_group("player") as Node3D

func get_lock_point() -> Vector3:
	return global_position + Vector3.UP * base_height * size_scale * 0.6

func is_lockable() -> bool:
	return not is_dead

func _apply_size() -> void:
	var hp_mult := 1.0
	match enemy_size:
		EnemySize.SMALL:
			size_scale = 0.5
			hp_mult = 0.5
		EnemySize.MEDIUM:
			size_scale = 1.0
		EnemySize.LARGE:
			size_scale = 2.0
			hp_mult = 2.0
		EnemySize.OUTLIER:
			size_scale = 0.25
			hp_mult = 4.0
	weight = hp_mult
	health.max_health = player_health * hp_mult
	health.reset()
	var h := base_height * size_scale
	var r := base_radius * size_scale
	var cap := CapsuleShape3D.new()
	cap.radius = r
	cap.height = h
	body_shape.shape = cap
	body_shape.position.y = h * 0.5
	var hs := CapsuleShape3D.new()
	hs.radius = r * 1.15
	hs.height = h * 1.05
	hurtbox_shape.shape = hs
	hurtbox_shape.position.y = h * 0.5
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = h
	_material.albedo_color = body_color
	cm.material = _material
	body_mesh.mesh = cm
	body_mesh.position.y = h * 0.5
	health_bar.position = Vector3(0.0, h + 0.35, 0.0)

func _physics_process(delta: float) -> void:
	var vel := velocity
	if not is_on_floor():
		vel.y += get_gravity().y * gravity_multiplier * delta
	else:
		vel.y = 0.0
	vel.x = desired_velocity.x + knockback_velocity.x
	vel.z = desired_velocity.z + knockback_velocity.z
	knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, 25.0 * delta)
	velocity = vel
	move_and_slide()

func _on_hit_received(_amount: float, _source: Node, hit_velocity: Vector3) -> void:
	last_hit_velocity = hit_velocity
	if is_dead:
		return
	var kb := hit_velocity * knockback_scale / weight
	kb.y = 0.0
	knockback_velocity = kb.limit_length(10.0)
	_material.albedo_color = Color.WHITE
	create_tween().tween_property(_material, "albedo_color", body_color, 0.15)

func _on_died() -> void:
	is_dead = true
	remove_from_group("lockable")
	hurtbox.set_deferred("monitorable", false)
	state_machine.set_physics_process(false)
	desired_velocity = Vector3.ZERO
	# carry the blade's momentum; heavier enemies travel less
	var carry := last_hit_velocity / weight
	carry.y = 0.0
	knockback_velocity = carry.limit_length(40.0)
	await get_tree().create_timer(0.6).timeout
	visible = false
	body_shape.set_deferred("disabled", true)
	knockback_velocity = Vector3.ZERO
	if respawn_time > 0.0:
		await get_tree().create_timer(respawn_time).timeout
		_respawn()

func _respawn() -> void:
	global_position = _spawn
	velocity = Vector3.ZERO
	health.reset()
	is_dead = false
	visible = true
	body_shape.disabled = false
	hurtbox.monitorable = true
	add_to_group("lockable")
	state_machine.set_physics_process(true)
