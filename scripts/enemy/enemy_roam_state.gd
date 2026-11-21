class_name EnemyRoamState extends State
## TODO: wander inside a designated area (export a roam radius / Area3D), then request &"Chase" when the player is seen.

func enter(_previous: StringName) -> void:
	(actor as Enemy).desired_velocity = Vector3.ZERO
