class_name EnemyAttackState extends State
## TODO: enable the Enemy's HitboxComponent during a hit window (same component the player uses),
## dodge/dash can be another State that sets Enemy.desired_velocity or knockback_velocity.

func enter(_previous: StringName) -> void:
	(actor as Enemy).desired_velocity = Vector3.ZERO
