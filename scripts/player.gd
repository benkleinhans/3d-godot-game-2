class_name Player extends CharacterBody3D
## Glue only: wires components together with signals. Gameplay lives in the components.

@export var debug_keys := true
@export var respawn_delay := 2.0

@onready var model_pivot: Node3D = %ModelPivot
@onready var hitbox: HitboxComponent = %Hitbox
@onready var input_component: InputComponent = %InputComponent
@onready var movement_component: MovementComponent = %MovementComponent
@onready var health_component: HealthComponent = %HealthComponent
@onready var camera_component: CameraComponent = %CameraComponent
@onready var lock_on_component: LockOnComponent = %LockOnComponent
@onready var weapon_component: WeaponComponent = %WeaponComponent
@onready var animation_component: AnimationComponent = %AnimationComponent
@onready var ik_component: IKComponent = %IKComponent
@onready var glow_component: GlowComponent = %GlowComponent

var checkpoint_position := Vector3.ZERO
var _dead := false

func _ready() -> void:
	add_to_group("Character")
	add_to_group("player")
	checkpoint_position = global_position

	movement_component.setup(self, model_pivot)
	camera_component.setup(self)
	lock_on_component.setup(self, camera_component)
	ik_component.setup(model_pivot)
	weapon_component.setup(self, movement_component, camera_component, hitbox, ik_component, lock_on_component)
	animation_component.setup(self, movement_component, model_pivot)
	glow_component.setup(model_pivot)

	# input -> components
	input_component.jump_pressed.connect(movement_component.on_jump_pressed)
	input_component.jump_released.connect(movement_component.on_jump_released)
	input_component.dash_pressed.connect(movement_component.on_dash_pressed)
	input_component.run_toggled.connect(movement_component.on_run_toggled)
	input_component.flow_activated.connect(movement_component.on_flow_activated)
	input_component.mouse_look.connect(camera_component.on_mouse_look)
	input_component.lock_on_pressed.connect(lock_on_component.toggle)
	input_component.lock_cycle.connect(lock_on_component.cycle)
	input_component.blades_pressed.connect(weapon_component.toggle_blades)
	input_component.attack_pressed.connect(weapon_component.on_attack_pressed)
	input_component.attack_released.connect(weapon_component.on_attack_released)
	input_component.launcher_pressed.connect(weapon_component.on_launcher_pressed)
	input_component.launcher_released.connect(weapon_component.on_launcher_released)
	if debug_keys:
		input_component.debug_hurt.connect(func(): health_component.damage(10.0))
		input_component.debug_heal.connect(func(): health_component.heal(10.0))

	# lock-on / weapon -> camera, ik
	lock_on_component.target_changed.connect(_on_lock_target_changed)
	weapon_component.mode_changed.connect(func(_m): _update_camera_mode())

	# weapon -> animation
	weapon_component.attack_started.connect(animation_component.play_action)
	weapon_component.attack_finished.connect(animation_component.end_action)

	# glow
	movement_component.jump_charge_changed.connect(glow_component.set_source.bind(&"jump_charge"))
	weapon_component.charge_changed.connect(glow_component.set_source.bind(&"attack_charge"))
	movement_component.jumped.connect(glow_component.pulse)

	# health
	health_component.died.connect(_on_died)

func _physics_process(delta: float) -> void:
	if _dead:
		return
	input_component.poll()
	camera_component.stick_look = input_component.look_vector

	var has_lock := lock_on_component.has_target()
	movement_component.move_input = input_component.move_vector
	movement_component.reference_basis = camera_component.get_yaw_basis()
	movement_component.has_lock = has_lock
	movement_component.aim_facing = weapon_component.is_launcher_mode()
	movement_component.speed_multiplier = weapon_component.get_speed_scale()
	if has_lock:
		movement_component.lock_target_point = lock_on_component.get_target_point()
	movement_component.tick(delta)

	ik_component.lock_active = has_lock
	if has_lock:
		ik_component.lock_point = lock_on_component.get_target_point()

	camera_component.follow_yaw_enabled = movement_component.mode == MovementComponent.Mode.FLOW
	camera_component.follow_yaw = movement_component.facing_yaw + PI

func set_checkpoint(pos: Vector3) -> void:
	checkpoint_position = pos

func _on_lock_target_changed(t: Node3D) -> void:
	camera_component.set_lock_target(t)
	_update_camera_mode()

func _update_camera_mode() -> void:
	var m := CameraComponent.Mode.FREE
	if lock_on_component.has_target():
		m = CameraComponent.Mode.LOCK_ON
	elif weapon_component.mode == WeaponComponent.Mode.LAUNCHER:
		m = CameraComponent.Mode.AIM
	elif weapon_component.mode == WeaponComponent.Mode.LAUNCHER_DUAL:
		m = CameraComponent.Mode.OVERHEAD
	camera_component.set_mode(m)

func _on_died() -> void:
	_dead = true
	movement_component.reset_state()
	weapon_component.on_died()
	lock_on_component.release()
	animation_component.play_death()
	await get_tree().create_timer(respawn_delay).timeout
	respawn()

func respawn() -> void:
	global_position = checkpoint_position
	velocity = Vector3.ZERO
	health_component.reset()
	animation_component.clear_death()
	_dead = false
