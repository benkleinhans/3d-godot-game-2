class_name InputBootstrap extends RefCounted
## Registers every input action the game needs, only if it is missing.
## If an action already exists but has no controller binding, the controller binding is added.

static func ensure_actions() -> void:
	_ensure(&"move_left", [_key(KEY_A)], [_axis(JOY_AXIS_LEFT_X, -1.0)])
	_ensure(&"move_right", [_key(KEY_D)], [_axis(JOY_AXIS_LEFT_X, 1.0)])
	_ensure(&"move_up", [_key(KEY_W)], [_axis(JOY_AXIS_LEFT_Y, -1.0)])
	_ensure(&"move_down", [_key(KEY_S)], [_axis(JOY_AXIS_LEFT_Y, 1.0)])
	_ensure(&"look_left", [], [_axis(JOY_AXIS_RIGHT_X, -1.0)])
	_ensure(&"look_right", [], [_axis(JOY_AXIS_RIGHT_X, 1.0)])
	_ensure(&"look_up", [], [_axis(JOY_AXIS_RIGHT_Y, -1.0)])
	_ensure(&"look_down", [], [_axis(JOY_AXIS_RIGHT_Y, 1.0)])
	# Shift / left stick press: tap = toggle run, hold = charge Flow
	_ensure(&"run_flow", [_key(KEY_SHIFT)], [_pad(JOY_BUTTON_LEFT_STICK)])
	_ensure(&"jump", [_key(KEY_SPACE)], [_pad(JOY_BUTTON_A)])
	_ensure(&"dash", [_mouse(MOUSE_BUTTON_RIGHT)], [_pad(JOY_BUTTON_RIGHT_SHOULDER), _pad(JOY_BUTTON_B)])
	_ensure(&"lock_on", [_key(KEY_Q)], [_pad(JOY_BUTTON_RIGHT_STICK)])
	_ensure(&"lock_prev", [_mouse(MOUSE_BUTTON_WHEEL_UP)], [])
	_ensure(&"lock_next", [_mouse(MOUSE_BUTTON_WHEEL_DOWN)], [])
	_ensure(&"blades", [_mouse(MOUSE_BUTTON_MIDDLE)], [_pad(JOY_BUTTON_Y)])
	_ensure(&"attack", [_mouse(MOUSE_BUTTON_LEFT)], [_pad(JOY_BUTTON_X)])
	_ensure(&"launcher", [_key(KEY_F)], [_pad(JOY_BUTTON_LEFT_SHOULDER)])
	_ensure(&"hurt", [_key(KEY_H)], [])
	_ensure(&"heal", [_key(KEY_J)], [])

static func _ensure(action: StringName, key_events: Array, pad_events: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	var has_pad := false
	var has_other := false
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton or e is InputEventJoypadMotion:
			has_pad = true
		else:
			has_other = true
	if not has_other:
		for e in key_events:
			InputMap.action_add_event(action, e)
	if not has_pad:
		for e in pad_events:
			InputMap.action_add_event(action, e)

static func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e

static func _mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e

static func _pad(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	return e

static func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e
