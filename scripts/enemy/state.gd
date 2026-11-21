class_name State extends Node
## Base class for state-machine states (enemies now, anything later).

signal transition_requested(to_state: StringName)

var actor: Node
var machine: StateMachine

func enter(_previous: StringName) -> void:
	pass

func exit() -> void:
	pass

func update(_delta: float) -> void:
	pass

func physics_update(_delta: float) -> void:
	pass
