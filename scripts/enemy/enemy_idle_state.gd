class_name EnemyIdleState extends State

func enter(_previous: StringName) -> void:
	(actor as Enemy).desired_velocity = Vector3.ZERO
