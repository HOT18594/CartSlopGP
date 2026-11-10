extends Node
## Controller bindings added at startup, in code rather than in project.godot.
##
## Godot's InputMap is serialised as huge Object(...) literals in project.godot;
## adding events here keeps the file readable and makes the bindings testable.
## Keyboard stays exactly as it was; every action only gains a joypad source.

const STEER_DEADZONE: float = 0.12
const TRIGGER_DEADZONE: float = 0.15
const MENU_DEADZONE: float = 0.25


func _ready() -> void:
	# Driving.
	_axis("accelerate", JOY_AXIS_TRIGGER_RIGHT, 1.0, TRIGGER_DEADZONE)
	_axis("brake", JOY_AXIS_TRIGGER_LEFT, 1.0, TRIGGER_DEADZONE)
	_axis("steer_left", JOY_AXIS_LEFT_X, -1.0, STEER_DEADZONE)
	_axis("steer_right", JOY_AXIS_LEFT_X, 1.0, STEER_DEADZONE)
	_button("handbrake", JOY_BUTTON_A)
	_button("boost", JOY_BUTTON_X)
	_button("reset_cart", JOY_BUTTON_Y)
	_button("horn", JOY_BUTTON_RIGHT_SHOULDER)
	_button("pause", JOY_BUTTON_START)

	# Menus: A confirm, B back, d-pad and left stick to move.
	_button("ui_accept", JOY_BUTTON_A)
	_button("ui_cancel", JOY_BUTTON_B)
	_button("ui_up", JOY_BUTTON_DPAD_UP)
	_button("ui_down", JOY_BUTTON_DPAD_DOWN)
	_button("ui_left", JOY_BUTTON_DPAD_LEFT)
	_button("ui_right", JOY_BUTTON_DPAD_RIGHT)
	_axis("ui_up", JOY_AXIS_LEFT_Y, -1.0, MENU_DEADZONE)
	_axis("ui_down", JOY_AXIS_LEFT_Y, 1.0, MENU_DEADZONE)
	_axis("ui_left", JOY_AXIS_LEFT_X, -1.0, MENU_DEADZONE)
	_axis("ui_right", JOY_AXIS_LEFT_X, 1.0, MENU_DEADZONE)

	# One-hand keyboard: arrows to drive, comma/period/slash next to them.
	_key("handbrake", KEY_COMMA)
	_key("boost", KEY_PERIOD)
	_key("reset_cart", KEY_SLASH)
	_key("horn", KEY_H)


func _axis(action: StringName, axis: int, value: float, deadzone: float) -> void:
	_ensure(action)
	InputMap.action_set_deadzone(action, deadzone)
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion:
			var motion := event as InputEventJoypadMotion
			if motion.axis == axis and is_equal_approx(motion.axis_value, value):
				return
	var added := InputEventJoypadMotion.new()
	added.axis = axis
	added.axis_value = value
	added.device = -1
	InputMap.action_add_event(action, added)


func _button(action: StringName, button: int) -> void:
	_ensure(action)
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadButton:
			if (event as InputEventJoypadButton).button_index == button:
				return
	var added := InputEventJoypadButton.new()
	added.button_index = button
	added.device = -1
	InputMap.action_add_event(action, added)


func _key(action: StringName, keycode: Key) -> void:
	_ensure(action)
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			if (event as InputEventKey).physical_keycode == keycode:
				return
	var added := InputEventKey.new()
	added.physical_keycode = keycode
	added.device = -1
	InputMap.action_add_event(action, added)


func _ensure(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
