class_name EnemyChaseState extends State
## TODO: NavigationAgent3D path-finding to Enemy.player, lock on, request &"Attack" in range.

func enter(_previous: StringName) -> void:
	(actor as Enemy).desired_velocity = Vector3.ZERO
