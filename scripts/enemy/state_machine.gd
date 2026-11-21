class_name StateMachine extends Node
## Put State nodes as children. The actor is this node's parent.

signal state_changed(from_state: StringName, to_state: StringName)

@export var initial_state: StringName = &"Idle"

var actor: Node
var current: State
var states := {}

func _ready() -> void:
	actor = get_parent()
	for c in get_children():
		if c is State:
			states[c.name] = c
			c.actor = actor
			c.machine = self
			c.transition_requested.connect(transition_to)
	call_deferred("_start")

func _start() -> void:
	if states.has(initial_state):
		transition_to(initial_state)

func transition_to(state_name: StringName) -> void:
	if not states.has(state_name):
		push_warning("StateMachine: no state '%s'" % state_name)
		return
	if current and current.name == state_name:
		return
	var prev: StringName = current.name if current else &""
	if current:
		current.exit()
	current = states[state_name]
	current.enter(prev)
	state_changed.emit(prev, state_name)

func _process(delta: float) -> void:
	if current:
		current.update(delta)

func _physics_process(delta: float) -> void:
	if current:
		current.physics_update(delta)
