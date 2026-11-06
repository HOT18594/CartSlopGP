extends Control
## In-game HUD: round speedometer, segmented boost meter, drive state and a
## controls hint. F3 toggles the debug readout.
##
## The race position / lap pills are only shown for race-style minigames: turn
## them on with `show_position_badge` / `show_lap_badge`, then feed them with
## set_race_position() and set_lap().

const UiPalette := preload("res://scripts/ui/ui_palette.gd")

@export_group("Minigame HUD")
@export var show_position_badge: bool = false ## Race placement pill (1st/2nd/...).
@export var show_lap_badge: bool = false ## Lap counter pill (LAP 1 / 3).

@onready var _speed_value: Label = %SpeedValue
@onready var _speed_gauge: Control = %SpeedGauge
@onready var _boost_meter: Control = %BoostMeter
@onready var _state_pill: PanelContainer = $StatePill
@onready var _state_label: Label = %StateLabel
@onready var _hint_label: Label = $HintLabel
@onready var _position_badge: PanelContainer = %PositionBadge
@onready var _place_label: Label = %PlaceLabel
@onready var _lap_badge: PanelContainer = %LapBadge
@onready var _lap_value: Label = %LapValue
@onready var _debug_label: Label = %DebugLabel

var _debug_visible: bool = false
var _hint_timer: float = 8.5
var _net_label: Label
var _net_timer: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if Network.is_session_active():
		_net_label = Label.new()
		_net_label.name = "NetStats"
		_net_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_net_label.anchor_left = 1.0
		_net_label.anchor_right = 1.0
		_net_label.offset_left = -270.0
		_net_label.offset_top = 14.0
		_net_label.offset_right = -16.0
		_net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_net_label.custom_minimum_size = Vector2(250, 0)
		_net_label.add_theme_font_size_override("font_size", 13)
		_net_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.86))
		_net_label.add_theme_color_override("font_outline_color", Color(0.10, 0.08, 0.18, 0.9))
		_net_label.add_theme_constant_override("outline_size", 4)
		add_child(_net_label)
	_debug_label.visible = false
	_position_badge.visible = show_position_badge
	_lap_badge.visible = show_lap_badge
	_state_pill.visible = false


func set_race_position(place: int) -> void:
	## 1 -> "1st", 2 -> "2nd", ... Shows the badge automatically.
	show_position_badge = true
	_position_badge.visible = true
	var suffix: String = "th"
	if place % 100 < 11 or place % 100 > 13:
		match place % 10:
			1:
				suffix = "st"
			2:
				suffix = "nd"
			3:
				suffix = "rd"
	_place_label.text = "%d%s" % [place, suffix]


func set_lap(current: int, total: int) -> void:
	show_lap_badge = true
	_lap_badge.visible = true
	_lap_value.text = "%d / %d" % [current, total]


func _process(delta: float) -> void:
	if _net_label != null:
		_net_timer += delta
		if _net_timer >= 0.25:
			_net_timer = 0.0
			_update_net_stats()
	var cart := get_tree().get_first_node_in_group("player") as CartPlayer
	if cart == null:
		return
	var horizontal := Vector3(cart.velocity.x, 0.0, cart.velocity.z)
	var speed_kmh: float = horizontal.length() * 3.6
	_speed_value.text = str(int(round(speed_kmh)))
	# Vehicles have different top speeds, so scale the dial to the current car.
	var gauge_max: float = cart.max_speed * cart.boost_speed_multiplier * 3.6 + 6.0
	if not is_equal_approx(float(_speed_gauge.get("max_speed_kmh")), gauge_max):
		_speed_gauge.set("max_speed_kmh", gauge_max)
	_speed_gauge.speed_kmh = speed_kmh

	var boost_ratio: float = clampf(cart.boost_amount / maxf(cart.max_boost, 0.1), 0.0, 1.0)
	_boost_meter.ratio = boost_ratio
	_boost_meter.boosting = cart.boost_active

	# Driving is the default; only interrupt the view when something happens.
	_state_pill.visible = cart.current_state != CartPlayer.CartState.DRIVING
	_state_label.text = _state_text(cart)
	_state_label.add_theme_color_override("font_color", _state_color(cart))

	if _hint_timer > 0.0:
		_hint_timer -= delta
		if _hint_timer <= 0.0:
			_hint_label.visible = false

	if _debug_visible:
		_update_debug(cart)


func _update_net_stats() -> void:
	if not is_instance_valid(_net_label):
		return
	var ping: String = "HOST" if Network.is_host else "%d ms" % Network.latency_ms
	_net_label.text = "%d FPS   PING %s   %d/%d" % [
		Engine.get_frames_per_second(), ping, Network.peer_count(), Network.MAX_PLAYERS]


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
			return UiPalette.INK
		CartPlayer.CartState.AIRBORNE_TUMBLE:
			return UiPalette.BLUE_DARK
		CartPlayer.CartState.CRASHED:
			return UiPalette.RED
		CartPlayer.CartState.RECOVERY:
			return Color("7a7392")
	return UiPalette.INK


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F3:
		_debug_visible = not _debug_visible
		_debug_label.visible = _debug_visible
		get_viewport().set_input_as_handled()


func _update_debug(cart: CartPlayer) -> void:
	var rig := get_tree().get_first_node_in_group("camera_rig") as ChaseCamera
	var fov_text: String = "-"
	if rig != null:
		fov_text = "%.1f" % rig.current_fov
	var feedback := get_tree().get_first_node_in_group("cart_feedback") as CartFeedback
	var dust_text: String = "off"
	var wind_text: String = "off"
	if feedback != null:
		dust_text = "on" if feedback.dust_active else "off"
		wind_text = "on" if feedback.speed_feedback_active else "off"
	_debug_label.text = "FOV %s   drift %s   smoke %s   speed FX %s\npos %.1f %.1f %.1f   vel %.1f" % [
		fov_text, cart.is_drifting, dust_text, wind_text,
		cart.global_position.x, cart.global_position.y, cart.global_position.z, cart.velocity.length()]
