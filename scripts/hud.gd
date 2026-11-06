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
var _scoreboard: PanelContainer
var _scoreboard_rows: VBoxContainer
var _scoreboard_count: Label
var _scoreboard_visible: bool = false
var _scoreboard_refresh: float = 0.0


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
		_build_scoreboard()
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
	if _scoreboard_visible and _scoreboard != null:
		_scoreboard_refresh += delta
		if _scoreboard_refresh >= 0.3:
			_scoreboard_refresh = 0.0
			_update_scoreboard()
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
	# The host IS the server, so its round trip is 0 ms; clients show real ms.
	var ping: String = "0 ms (host)" if Network.is_host else "%d ms" % maxi(Network.latency_ms, 0)
	_net_label.text = "%d FPS   PING %s   %d/%d" % [
		Engine.get_frames_per_second(), ping, Network.peer_count(), Network.MAX_PLAYERS]


# --------------------------------------------------------------------------
# hold-Tab player list (Minecraft style)


func _build_scoreboard() -> void:
	_scoreboard = PanelContainer.new()
	_scoreboard.name = "Scoreboard"
	_scoreboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.15, 0.84)
	style.border_color = Color(0.12, 0.10, 0.23, 0.9)
	style.set_border_width_all(3)
	style.set_corner_radius_all(14)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 12.0
	_scoreboard.add_theme_stylebox_override("panel", style)
	_scoreboard.anchor_left = 0.5
	_scoreboard.anchor_right = 0.5
	_scoreboard.offset_left = -190.0
	_scoreboard.offset_right = 190.0
	_scoreboard.offset_top = 52.0
	_scoreboard.visible = false
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_scoreboard.add_child(column)
	_scoreboard_count = Label.new()
	_scoreboard_count.text = "PLAYERS"
	_scoreboard_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scoreboard_count.add_theme_font_size_override("font_size", 15)
	_scoreboard_count.add_theme_color_override("font_color", Color(1, 1, 1, 0.66))
	column.add_child(_scoreboard_count)
	_scoreboard_rows = VBoxContainer.new()
	_scoreboard_rows.add_theme_constant_override("separation", 4)
	column.add_child(_scoreboard_rows)
	add_child(_scoreboard)


func _ping_color(ms: int) -> Color:
	if ms < 60:
		return Color(0.45, 0.95, 0.55)
	if ms < 120:
		return Color(1.0, 0.82, 0.35)
	return Color(1.0, 0.45, 0.42)


func _update_scoreboard() -> void:
	if _scoreboard_rows == null:
		return
	for child: Node in _scoreboard_rows.get_children():
		child.queue_free()
	var ids: Array[int] = [multiplayer.get_unique_id()]
	for peer_id: int in multiplayer.get_peers():
		ids.append(peer_id)
	ids.sort()
	_scoreboard_count.text = "PLAYERS  ·  %d/%d" % [ids.size(), Network.MAX_PLAYERS]
	for peer_id: int in ids:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 9)
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(12, 12)
		dot.color = Network.color_of(peer_id)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)
		var name_label := Label.new()
		var text: String = Network.name_of(peer_id)
		if peer_id == multiplayer.get_unique_id():
			text += "  (YOU)"
		if peer_id == 1:
			text = "[HOST]  " + text
		name_label.text = text
		name_label.add_theme_font_size_override("font_size", 17)
		name_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(name_label)
		var ms: int = int(Network.ping_table.get(peer_id, 0))
		if ms <= 0 and not Network.is_host and peer_id == multiplayer.get_unique_id():
			ms = maxi(Network.latency_ms, 0)
		var ping_label := Label.new()
		ping_label.text = "%d ms" % ms
		ping_label.add_theme_font_size_override("font_size", 15)
		ping_label.add_theme_color_override("font_color", _ping_color(ms))
		row.add_child(ping_label)
		_scoreboard_rows.add_child(row)


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
	if key == null:
		return
	if key.keycode == KEY_TAB and _scoreboard != null:
		# Minecraft-style: hold Tab to see who is in the room and their ping.
		if not key.echo:
			_scoreboard_visible = key.pressed
			_scoreboard.visible = _scoreboard_visible
			if _scoreboard_visible:
				_update_scoreboard()
			get_viewport().set_input_as_handled()
		return
	if key.pressed and not key.echo and key.keycode == KEY_F3:
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
