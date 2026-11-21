class_name PiercerProjectile extends Node3D
## Launched arm blade. Swept ray each physics frame (no tunnelling), embeds half-way in what it hits.

signal embedded(collider: Object)

var speed := 80.0
var damage := 40.0
var life_time := 3.0
var blade_length := 0.9
var embed_time := 6.0
var collision_mask := 17
var exclude: Array[RID] = []
var source: Node

var _dir := Vector3.FORWARD
var _embedded := false

func _ready() -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.05, blade_length)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.95, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.8, 1.0)
	box.material = mat
	mi.mesh = box
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

## Call AFTER add_child()
func launch(from: Vector3, dir: Vector3, src: Node) -> void:
	source = src
	_dir = dir.normalized()
	var up := Vector3.UP if absf(_dir.y) < 0.99 else Vector3.RIGHT
	global_transform = Transform3D(Basis.looking_at(_dir, up), from)

func _physics_process(delta: float) -> void:
	if _embedded:
		return
	life_time -= delta
	if life_time <= 0.0:
		queue_free()
		return
	var from := global_position
	var to := from + _dir * speed * delta
	var q := PhysicsRayQueryParameters3D.create(from, to, collision_mask, exclude)
	q.collide_with_areas = true
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		global_position = to
		return
	_embedded = true
	global_position = hit.position
	var collider: Object = hit.collider
	if collider is HurtboxComponent:
		var hurtbox := collider as HurtboxComponent
	# velocity is passed so a killed enemy can "carry" the blade's momentum
		hurtbox.take_hit(damage, source, _dir * speed)
		var host: Node = hurtbox.get_parent()
		if host and is_instance_valid(host):
			reparent(host, true)
	embedded.emit(collider)
	get_tree().create_timer(embed_time).timeout.connect(queue_free)
