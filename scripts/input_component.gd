class_name InputComponent extends Node
## Turns raw input into signals + polled vectors. Contains NO gameplay logic.

signal jump_pressed
signal jump_released
signal dash_pressed
signal run_toggled
signal flow_activated
signal flow_charge_changed(ratio: float)
signal lock_on_pressed
signal lock_cycle(direction: int)
signal blades_pressed
signal attack_pressed
signal attack_released
signal launcher_pressed
signal launcher_released
signal mouse_look(relative: Vector2)
signal debug_hurt
signal debug_heal

## Seconds Shift / L3 must be held to activate Flow. (Spec says 5. Lower it while testing.)
@export var flow_hold_time := 5.0

var move_vector := Vector2.ZERO
var look_vector := Vector2.ZERO

var _flow_held := false
var _flow_time := 0.0
var _flow_fired := false

func _ready() -> void:
	InputBootstrap.ensure_actions()

func poll() -> void:
	move_vector = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	look_vector = Input.get_vector("look_left", "look_right", "look_up", "look_down")

func _process(delta: float) -> void:
	if _flow_held and not _flow_fired:
		_flow_time += delta
		flow_charge_changed.emit(clampf(_flow_time / maxf(flow_hold_time, 0.01), 0.0, 1.0))
		if _flow_time >= flow_hold_time:
			_flow_fired = true
			flow_charge_changed.emit(0.0)
			flow_activated.emit()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			mouse_look.emit(event.relative)
		return
	if event.is_action_pressed("jump"):
		jump_pressed.emit()
	if event.is_action_released("jump"):
		jump_released.emit()
	if event.is_action_pressed("dash"):
		dash_pressed.emit()
	if event.is_action_pressed("lock_on"):
		lock_on_pressed.emit()
	if event.is_action_pressed("lock_prev"):
		lock_cycle.emit(-1)
	if event.is_action_pressed("lock_next"):
		lock_cycle.emit(1)
	if event.is_action_pressed("blades"):
		blades_pressed.emit()
	if event.is_action_pressed("attack"):
		attack_pressed.emit()
	if event.is_action_released("attack"):
		attack_released.emit()
	if event.is_action_pressed("launcher"):
		launcher_pressed.emit()
	if event.is_action_released("launcher"):
		launcher_released.emit()
	if event.is_action_pressed("hurt"):
		debug_hurt.emit()
	if event.is_action_pressed("heal"):
		debug_heal.emit()
	# Shift / L3: tap toggles run, hold charges flow
	if event.is_action_pressed("run_flow"):
		_flow_held = true
		_flow_time = 0.0
		_flow_fired = false
	if event.is_action_released("run_flow"):
		if _flow_held and not _flow_fired:
			run_toggled.emit()
		_flow_held = false
		flow_charge_changed.emit(0.0)
