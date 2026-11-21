class_name HurtboxComponent extends Area3D
## Receives hits. Put on layer 4 (player) or 5 (enemy). Forwards damage to a sibling HealthComponent.

signal hit_received(amount: float, source: Node, hit_velocity: Vector3)

@export var health: HealthComponent
@export var damage_multiplier := 1.0

func _ready() -> void:
	if health == null:
		var p := get_parent()
		if p:
			for c in p.get_children():
				if c is HealthComponent:
					health = c
					break

func take_hit(amount: float, source: Node = null, hit_velocity: Vector3 = Vector3.ZERO) -> void:
	var final_amount := amount * damage_multiplier
	hit_received.emit(final_amount, source, hit_velocity)
	if health:
		health.damage(final_amount, source)
