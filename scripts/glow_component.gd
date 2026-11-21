class_name GlowComponent extends Node
## Drives emission on the model's materials ("tertiary glow"): jump pulse, jump charge, attack charge.
## Several sources can feed it; the strongest wins.

@export var tertiary_color := Color(0.2, 0.9, 1.0)
@export var base_energy := 0.0
@export var max_energy := 3.0
@export var pulse_amount := 0.45
@export var pulse_time := 0.25
@export var smoothing := 14.0
## Only affect materials whose resource_name contains this. Empty = every StandardMaterial3D.
@export var material_name_filter := ""

var _materials: Array[StandardMaterial3D] = []
var _sources := {}
var _pulse := 0.0
var _level := 0.0

func setup(model_root: Node) -> void:
	for node in model_root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s) as StandardMaterial3D
			if mat == null:
				continue
			if material_name_filter != "" and not mat.resource_name.contains(material_name_filter):
				continue
			var dup := mat.duplicate() as StandardMaterial3D
			dup.emission_enabled = true
			dup.emission = tertiary_color
			dup.emission_energy_multiplier = base_energy
			mi.set_surface_override_material(s, dup)
			_materials.append(dup)

func set_source(ratio: float, source: StringName) -> void:
	_sources[source] = ratio

func pulse(_kind: StringName = &"") -> void:
	_pulse = 1.0

func _process(delta: float) -> void:
	if _materials.is_empty():
		return
	var target := _pulse * pulse_amount
	for v in _sources.values():
		target = maxf(target, v)
	_pulse = move_toward(_pulse, 0.0, delta / maxf(pulse_time, 0.01))
	_level = lerpf(_level, target, 1.0 - exp(-smoothing * delta))
	var energy := base_energy + _level * max_energy
	for m in _materials:
		m.emission_energy_multiplier = energy
