extends Control

const UiPalette := preload("res://scripts/ui/ui_palette.gd")
## In-game HUD: speed, boost bar, drive state and a controls hint.
## F3 toggles the old debug readout.

@onready var _speed_value: Label = %SpeedValue
@onready var _state_label: Label = %StateLabel
@onready var _boost_bar: ProgressBar = %BoostBar
@onready var _boost_value: Label = %BoostValue
@onready var _debug_label: Label = %DebugLabel

var _debug_visible: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_label.visible = false


func _process(_delta: float) -> void:
	var cart := get_tree().get_first_node_in_group("player") as CartPlayer
	if cart == null:
		return
	var horizontal := Vector3(cart.velocity.x, 0.0, cart.velocity.z)
	_speed_value.text = str(int(round(horizontal.length() * 3.6)))
	_state_label.text = _state_text(cart)
	_state_label.add_theme_color_override("font_color", _state_color(cart))

	var boost_ratio: float = clampf(cart.boost_amount / maxf(cart.max_boost, 0.1), 0.0, 1.0)
	_boost_bar.value = boost_ratio * 100.0
	_boost_value.text = "%d%%" % int(round(boost_ratio * 100.0))
	var fill_tint: Color = UiPalette.CORAL if cart.boost_active else Color.WHITE
	_boost_bar.modulate = fill_tint

	if _debug_visible:
		_update_debug(cart)


func _state_text(cart: CartPlayer) -> String:
	match cart.current_state:
		CartPlayer.CartState.DRIVING:
			return "DRIVING"
		CartPlayer.CartState.AIRBORNE_TUMBLE:
			return "AIRBORNE"
		CartPlayer.CartState.CRASHED:
			return "CRASHED"
		CartPlayer.CartState.RECOVERY:
			return "RECOVERY"
	return "DRIVING"


func _state_color(cart: CartPlayer) -> Color:
	match cart.current_state:
		CartPlayer.CartState.DRIVING:
			return UiPalette.ACCENT
		CartPlayer.CartState.AIRBORNE_TUMBLE:
			return UiPalette.CYAN
		CartPlayer.CartState.CRASHED:
			return UiPalette.CORAL
		CartPlayer.CartState.RECOVERY:
			return UiPalette.TEXT_DIM
	return UiPalette.TEXT


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F3:
		_debug_visible = not _debug_visible
		_debug_label.visible = _debug_visible
		get_viewport().set_input_as_handled()


func _update_debug(cart: CartPlayer) -> void:
	var rig := get_tree().get_first_node_in_group("camera_rig") as ChaseCamera
	var fov_text: String = "%.1f" % rig.current_fov if rig != null else "-"
	var feedback := get_tree().get_first_node_in_group("cart_feedback") as CartFeedback
	var dust_text: String = "off"
	var wind_text: String = "off"
	if feedback != null:
		dust_text = "on" if feedback.dust_active else "off"
		wind_text = "on" if feedback.speed_feedback_active else "off"
	_debug_label.text = "FOV %s   drift %s   smoke %s   speed FX %s\npos %.1f %.1f %.1f   vel %.1f" % [
		fov_text, cart.is_drifting, dust_text, wind_text,
		cart.global_position.x, cart.global_position.y, cart.global_position.z, cart.velocity.length()]
