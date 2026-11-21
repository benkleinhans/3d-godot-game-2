class_name HealthComponent extends Node

signal health_changed(current: float, max: float)
signal damaged(amount: float, source: Node)
signal healed(amount: float)
signal died

@export var max_health := 100.0
@export var invulnerable := false
## Glass "clink" played when damaged (optional).
@export var hit_sound: AudioStream
@export var log_changes := false

var current_health := 0.0
var is_dead := false
var _audio: AudioStreamPlayer

func _ready() -> void:
	current_health = max_health
	if hit_sound:
		_audio = AudioStreamPlayer.new()
		_audio.stream = hit_sound
		add_child(_audio)
	_emit()

func damage(amount: float, source: Node = null) -> void:
	if is_dead or invulnerable or amount <= 0.0:
		return
	current_health = clampf(current_health - amount, 0.0, max_health)
	damaged.emit(amount, source)
	if _audio:
		_audio.play()
	_emit()
	if current_health <= 0.0:
		is_dead = true
		died.emit()

func heal(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	current_health = clampf(current_health + amount, 0.0, max_health)
	healed.emit(amount)
	_emit()

func reset() -> void:
	is_dead = false
	current_health = max_health
	_emit()

func get_ratio() -> float:
	return current_health / max_health if max_health > 0.0 else 0.0

func _emit() -> void:
	health_changed.emit(current_health, max_health)
	if log_changes:
		print("%s HP: %d / %d" % [get_parent().name, current_health, max_health])
