class_name HealthBar3D extends Node3D
## Billboarded health bar drawn with a tiny shader. Call bind(health_component).

@export var width := 1.2
@export var height := 0.12

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float ratio : hint_range(0.0, 1.0) = 1.0;
uniform vec4 fill_color : source_color = vec4(0.9, 0.1, 0.12, 1.0);
uniform vec4 back_color : source_color = vec4(0.04, 0.04, 0.04, 1.0);
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	ALBEDO = UV.x <= ratio ? fill_color.rgb : back_color.rgb;
}
"""

var _mat := ShaderMaterial.new()

func _ready() -> void:
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	var quad := QuadMesh.new()
	quad.size = Vector2(width, height)
	quad.material = _mat
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func bind(health: HealthComponent) -> void:
	health.health_changed.connect(_on_changed)
	_on_changed(health.current_health, health.max_health)

func _on_changed(current: float, max_value: float) -> void:
	_mat.set_shader_parameter("ratio", current / max_value if max_value > 0.0 else 0.0)
