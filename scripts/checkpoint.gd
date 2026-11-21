class_name Checkpoint extends Area3D
## Add an Area3D + CollisionShape3D, attach this script. Player respawns here after dying.

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		body.set_checkpoint(global_position)
