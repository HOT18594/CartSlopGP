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
@onready var _time_badge: PanelContainer = get_node_or_null("%TimeBadge") as PanelContainer
@onready var _time_value: Label = get_node_or_null("%TimeValue") as Label
@onready var _best_value: Label = get_node_or_null("%BestValue") as Label
@onready var _debug_label: Label = %DebugLabel

var _debug_visible: bool = false
var _hint_timer: float = 12.0
var _net_label: Label
var _net_timer: float = 0.0
var _scoreboard: PanelContainer
var _scoreboard_rows: VBoxContainer
var _scoreboard_count: Label
var _scoreboard_ping_header: Label
var _scoreboard_visible: bool = false
var _scoreboard_refresh: float = 0.0
var _scoreboard_rows_cache: Dictionary = {}
var _scoreboard_row_style: StyleBoxFlat
var _scoreboard_local_style: StyleBoxFlat
var _scoreboard_fade: Tween
var _boost_glow: float = 0.0
var _boost_glow_was_visible: bool = false
var _boost_percent: Label
var _last_boost_percent: int = -1
var _fps_label: Label
var _fps_timer: float = 0.0
var _cart_cache: CartPlayer
var _last_state_text: String = ""
var _last_state_color: Color = Color.WHITE
var _race_plaque: PanelContainer
var _plaque_pos: Label
var _plaque_of: Label
var _plaque_lap: Label
var _plaque_time: Label
var _plaque_best: Label
var _standings_panel: PanelContainer
var _standings_rows: VBoxContainer
var _standings_signature: String = ""


func _ready() -> void:
	# Controls live in the pause menu now; no permanent hint line in the race.
	_hint_timer = 0.0
	_hint_label.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if Network.is_session_active():
		_net_label = Label.new()
		_net_label.name = "NetStats"
		_net_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_net_label.anchor_left = 1.0
		_net_label.anchor_right = 1.0
		_net_label.offset_left = -270.0
		_net_label.offset_top = 24.0
		_net_label.offset_right = -24.0
		_net_label.offset_bottom = 48.0
		_net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_net_label.custom_minimum_size = Vector2(250, 0)
		_net_label.add_theme_font_size_override("font_size", 14)
		_net_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.86))
		_net_label.add_theme_color_override("font_outline_color", Color(0.10, 0.08, 0.18, 0.9))
		_net_label.add_theme_constant_override("outline_size", 4)
		add_child(_net_label)
		_build_scoreboard()
	_debug_label.visible = false
	_build_boost_percent()
	_position_badge.visible = show_position_badge
	_lap_badge.visible = show_lap_badge
	if _time_badge != null:
		_time_badge.visible = show_lap_badge
	$RaceBox.visible = false
	_build_race_plaque()
	_build_standings()
	_state_pill.visible = false
	GameSettings.changed.connect(_apply_display_settings)
	resized.connect(_apply_display_settings)
	_apply_display_settings()
	call_deferred("_apply_display_settings")


func _build_boost_percent() -> void:
	## Overlay the remaining boost inside the right edge of the meter. A separate
	## Label avoids redrawing a font glyph from `_draw()` every frame.
	_boost_percent = Label.new()
	_boost_percent.name = "BoostPercent"
	_boost_percent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boost_percent.anchor_left = 1.0
	_boost_percent.anchor_right = 1.0
	_boost_percent.anchor_top = 0.0
	_boost_percent.anchor_bottom = 1.0
	_boost_percent.offset_left = -58.0
	_boost_percent.offset_right = -10.0
	_boost_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_boost_percent.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_boost_percent.add_theme_font_size_override("font_size", 13)
	_boost_percent.add_theme_color_override("font_color", Color(0.06, 0.12, 0.22, 0.95))
	_boost_percent.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.45))
	_boost_percent.add_theme_constant_override("outline_size", 3)
	_boost_meter.add_child(_boost_percent)


func _apply_display_settings() -> void:
	var scale_factor: float = clampf(GameSettings.hud_scale, 0.75, 1.5)
	if GameSettings.show_fps:
		if _fps_label == null:
			_fps_label = Label.new()
			_fps_label.name = "FpsLabel"
			_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_fps_label.anchor_left = 1.0
			_fps_label.anchor_top = 1.0
			_fps_label.anchor_right = 1.0
			_fps_label.anchor_bottom = 1.0
			_fps_label.offset_left = -150.0
			_fps_label.offset_top = -52.0
			_fps_label.offset_right = -20.0
			_fps_label.offset_bottom = -22.0
			_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			_fps_label.add_theme_font_size_override("font_size", 14)
			_fps_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.86))
			_fps_label.add_theme_color_override("font_outline_color", Color(0.10, 0.08, 0.18, 0.9))
			_fps_label.add_theme_constant_override("outline_size", 4)
			add_child(_fps_label)
		_fps_label.visible = true
	elif _fps_label != null:
		_fps_label.visible = false
	# Scale each HUD cluster around its own anchor so corner elements grow
	# inward instead of off-screen. Scaling the full-screen root would push
	# the speedometer and boost bar past the viewport at 125-150%.
	for child: Node in get_children():
		if not (child is Control):
			continue
		var control := child as Control
		control.scale = Vector2.ONE * scale_factor
		control.pivot_offset = _hud_pivot(control)


func _hud_pivot(control: Control) -> Vector2:
	var pivot := Vector2.ZERO
	if is_equal_approx(control.anchor_left, 1.0) and is_equal_approx(control.anchor_right, 1.0):
		pivot.x = control.size.x
	elif not (is_equal_approx(control.anchor_left, 0.0) and is_equal_approx(control.anchor_right, 0.0)):
		pivot.x = control.size.x * 0.5
	if is_equal_approx(control.anchor_top, 1.0) and is_equal_approx(control.anchor_bottom, 1.0):
		pivot.y = control.size.y
	elif not (is_equal_approx(control.anchor_top, 0.0) and is_equal_approx(control.anchor_bottom, 0.0)):
		pivot.y = control.size.y * 0.5
	return pivot


func _panel_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(3)
	style.set_corner_radius_all(18)
	style.shadow_color = Color(0.06, 0.05, 0.12, 0.45)
	style.shadow_size = 8
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


func _label(text: String, size: int, color: Color,
		outline: int = 0) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if outline > 0:
		label.add_theme_color_override("font_outline_color", UiPalette.OUTLINE)
		label.add_theme_constant_override("outline_size", outline)
	return label


func _build_race_plaque() -> void:
	_race_plaque = PanelContainer.new()
	_race_plaque.name = "RacePlaque"
	_race_plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_race_plaque.anchor_left = 0.0
	_race_plaque.anchor_top = 0.0
	_race_plaque.offset_left = 24.0
	_race_plaque.offset_top = 20.0
	_race_plaque.offset_right = 24.0 + 320.0
	_race_plaque.offset_bottom = 20.0 + 132.0
	_race_plaque.add_theme_stylebox_override("panel",
		_panel_style(Color(0.118, 0.106, 0.227, 0.94), UiPalette.CREAM))
	add_child(_race_plaque)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	_race_plaque.add_child(column)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	column.add_child(top)
	_plaque_pos = _label("1ST", 64, UiPalette.YELLOW, 10)
	top.add_child(_plaque_pos)
	var pos_stack := VBoxContainer.new()
	pos_stack.size_flags_vertical = Control.SIZE_SHRINK_END
	pos_stack.add_theme_constant_override("separation", 0)
	top.add_child(pos_stack)
	_plaque_of = _label("OF 6", 14, Color(1, 1, 1, 0.72))
	pos_stack.add_child(_plaque_of)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	_plaque_lap = _label("LAP 1/3", 24, UiPalette.CREAM)
	_plaque_lap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_plaque_lap)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	column.add_child(bottom)
	var time_caption := _label("TIME", 13, Color(1, 1, 1, 0.65))
	time_caption.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(time_caption)
	_plaque_time = _label("0:00.000", 30, UiPalette.YELLOW)
	bottom.add_child(_plaque_time)
	var best_caption := _label("BEST", 13, Color(1, 1, 1, 0.55))
	best_caption.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(best_caption)
	_plaque_best = _label("—", 16, Color(1, 1, 1, 0.85))
	_plaque_best.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(_plaque_best)
	_race_plaque.visible = false


func _build_standings() -> void:
	_standings_panel = PanelContainer.new()
	_standings_panel.name = "LiveStandings"
	_standings_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_standings_panel.anchor_left = 1.0
	_standings_panel.anchor_right = 1.0
	_standings_panel.offset_left = -284.0
	_standings_panel.offset_right = -24.0
	_standings_panel.offset_top = 20.0
	_standings_panel.offset_bottom = 20.0 + 250.0
	_standings_panel.add_theme_stylebox_override("panel",
		_panel_style(Color(0.118, 0.106, 0.227, 0.86), Color(1, 1, 1, 0.35)))
	add_child(_standings_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	_standings_panel.add_child(column)
	column.add_child(_label("STANDINGS", 13, Color(1, 1, 1, 0.62)))
	_standings_rows = VBoxContainer.new()
	_standings_rows.add_theme_constant_override("separation", 2)
	column.add_child(_standings_rows)
	_standings_panel.visible = false


func set_standings(entries: Array[Dictionary]) -> void:
	## Live race order. Called at ~4 Hz by the race, never per frame.
	if _standings_rows == null or entries.is_empty():
		return
	var signature_parts: PackedStringArray = []
	for entry: Dictionary in entries:
		signature_parts.append("%s:%d" % [str(entry.get("name", "")),
			int(float(entry.get("progress", 0.0)))])
	var signature: String = "|".join(signature_parts)
	if signature == _standings_signature:
		return
	_standings_signature = signature
	for child in _standings_rows.get_children():
		child.queue_free()
	var leader: float = float(entries[0].get("progress", 0.0))
	var visible_count: int = mini(entries.size(), 5)
	for index in visible_count:
		var entry: Dictionary = entries[index]
		var row := PanelContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.custom_minimum_size = Vector2(0.0, 36.0)
		var local: bool = bool(entry.get("local", false))
		var row_style := _panel_style(
			Color(1.0, 0.96, 0.89, 0.18) if local else Color(1.0, 0.96, 0.89, 1.0),
			Color(1, 1, 1, 0.30) if local else Color(0.12, 0.10, 0.23, 0.16))
		row_style.shadow_size = 0
		row_style.set_corner_radius_all(12)
		row.add_theme_stylebox_override("panel", row_style)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		row.add_child(line)
		line.add_child(_label("%d" % (index + 1), 14,
			UiPalette.YELLOW if local else UiPalette.OUTLINE))
		var dot := ColorRect.new()
		var dot_color: Color = entry.get("color", Color.WHITE)
		dot.color = dot_color
		dot.custom_minimum_size = Vector2(7, 7)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(dot)
		var name_label := _label(str(entry.get("name", "?")), 14,
			Color(1, 1, 1, 1.0) if local else UiPalette.OUTLINE)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.clip_text = true
		line.add_child(name_label)
		var gap: float = maxf(leader - float(entry.get("progress", 0.0)), 0.0)
		line.add_child(_label("—" if local else ("%dm" % int(gap)), 12,
			Color(1, 1, 1, 0.55) if local else UiPalette.MUTED))
		_standings_rows.add_child(row)
	_standings_panel.visible = entries.size() > 1


func set_race_position(place: int, field_size: int = 0) -> void:
	## 1 -> "1st", 2 -> "2nd", ... Shows the race plaque automatically.
	show_position_badge = true
	if _race_plaque == null:
		return
	_race_plaque.visible = true
	var suffix: String = "th"
	if place % 100 < 11 or place % 100 > 13:
		match place % 10:
			1:
				suffix = "st"
			2:
				suffix = "nd"
			3:
				suffix = "rd"
	_plaque_pos.text = ("%d%s" % [place, suffix]).to_upper()
	if field_size > 0:
		_plaque_of.text = "OF %d" % field_size


func set_lap(current: int, total: int) -> void:
	show_lap_badge = true
	if _race_plaque == null:
		return
	_race_plaque.visible = true
	_plaque_lap.text = "LAP %d/%d" % [current, total]


func set_race_time(total_seconds: float, best_seconds: float = -1.0) -> void:
	## Fed by the race at ~20 Hz. The best lap is "—" until a lap is banked.
	if _plaque_time == null:
		return
	var total_text: String = _format_race_time(total_seconds)
	if _plaque_time.text != total_text:
		_plaque_time.text = total_text
	var best_text: String = _format_race_time(best_seconds) if best_seconds >= 0.0 else "—"
	if _plaque_best.text != best_text:
		_plaque_best.text = best_text


func _format_race_time(seconds: float) -> String:
	var safe: float = maxf(seconds, 0.0)
	var minutes: int = int(safe) / 60
	var remainder: float = fmod(safe, 60.0)
	return "%d:%s" % [minutes, ("%.3f" % remainder).lpad(6, "0")]


func _process(delta: float) -> void:
	if _fps_label != null and _fps_label.visible:
		_fps_timer += delta
		if _fps_timer >= 0.25:
			_fps_timer = 0.0
			_fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	if _net_label != null:
		_net_timer += delta
		if _net_timer >= 0.25:
			_net_timer = 0.0
			_update_net_stats()
	if _scoreboard_visible and _scoreboard != null:
		_scoreboard_refresh += delta
		if _scoreboard_refresh >= 1.0:
			_scoreboard_refresh = 0.0
			_update_scoreboard()
	if _cart_cache == null or not is_instance_valid(_cart_cache):
		_cart_cache = get_tree().get_first_node_in_group("player") as CartPlayer
	var cart: CartPlayer = _cart_cache
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
	var boost_percent: int = int(round(boost_ratio * 100.0))
	if boost_percent != _last_boost_percent and _boost_percent != null:
		_last_boost_percent = boost_percent
		_boost_percent.text = "%d%%" % boost_percent

	# Cheap speedometer glow: a few translucent circles drawn behind the dial.
	var glow_target: float = 1.0 if cart.boost_active else 0.0
	_boost_glow = move_toward(_boost_glow, glow_target, delta * 7.0)
	if _boost_glow > 0.001 or _boost_glow_was_visible:
		_boost_glow_was_visible = _boost_glow > 0.001
		queue_redraw()

	# Driving is the default; only interrupt the view when something happens.
	_state_pill.visible = cart.current_state != CartPlayer.CartState.DRIVING
	var state_text: String = _state_text(cart)
	if state_text != _last_state_text:
		_last_state_text = state_text
		_state_label.text = state_text
	var state_color: Color = _state_color(cart)
	if state_color != _last_state_color:
		_last_state_color = state_color
		_state_label.add_theme_color_override("font_color", state_color)

	if _hint_timer > 0.0:
		_hint_timer -= delta
		if _hint_timer <= 0.0:
			_hint_label.visible = false

	if _debug_visible:
		_update_debug(cart)


func _apply_hint() -> void:
	var pad: bool = Input.get_connected_joypads().size() > 0
	if pad:
		_hint_label.text = "L STICK STEER  ·  RT GO  ·  LT BRAKE  ·  A DRIFT  ·  X BOOST  ·  Y RESET  ·  START PAUSE"
	else:
		_hint_label.text = "WASD DRIVE  ·  SPACE DRIFT  ·  SHIFT BOOST  ·  R RESET  ·  ESC PAUSE"


func _draw() -> void:
	# Drawn on the HUD root, so the glow sits behind the opaque speedometer dial
	# and only its halo is visible. Three rings are cheaper than a shader.
	if _boost_glow <= 0.001 or _speed_gauge == null or _speed_gauge.size.x <= 0.0:
		return
	# get_global_rect includes the HUD-scale transform. Using position/size
	# directly put the halo up-left of the dial at 150% HUD scale.
	var gauge_rect: Rect2 = _speed_gauge.get_global_rect()
	var center: Vector2 = gauge_rect.position + gauge_rect.size * 0.5
	var radius: float = maxf(gauge_rect.size.x, gauge_rect.size.y) * 0.5
	var pulse: float = 0.9 + 0.1 * sin(Time.get_ticks_msec() * 0.012)
	for index in 3:
		var spread: float = radius + 8.0 + float(index) * 9.0
		var alpha: float = (0.16 - float(index) * 0.045) * _boost_glow * pulse
		draw_circle(center, spread, Color(0.25, 0.85, 1.0, alpha))


func _update_net_stats() -> void:
	if not is_instance_valid(_net_label):
		return
	# The host is the ENet server for the clients, but when the room is relayed
	# through the Pi its real ping is the round trip to that server.
	var ping: String
	if Network.is_host:
		ping = "%d ms (host)" % maxi(Network.host_ping_ms, 0)
	else:
		ping = "%d ms" % maxi(Network.latency_ms, 0)
	# FPS is debug information; the shipping HUD only shows the ping and the
	# player count. F3 still opens the full debug readout.
	_net_label.text = "PING %s   ·   %d/%d" % [
		ping, Network.peer_count(), Network.MAX_PLAYERS]


# --------------------------------------------------------------------------
# hold-Tab player list (Minecraft style)


func _build_scoreboard() -> void:
	_scoreboard = PanelContainer.new()
	_scoreboard.name = "Scoreboard"
	_scoreboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.15, 0.86)
	style.border_color = Color(0.12, 0.10, 0.23, 0.9)
	style.set_border_width_all(3)
	style.set_corner_radius_all(14)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 12.0
	_scoreboard.add_theme_stylebox_override("panel", style)
	_scoreboard.anchor_left = 0.5
	_scoreboard.anchor_right = 0.5
	_scoreboard.offset_left = -210.0
	_scoreboard.offset_right = 210.0
	_scoreboard.offset_top = 150.0
	_scoreboard.offset_bottom = 64.0
	_scoreboard.visible = false
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_scoreboard.add_child(column)

	# Header: PLAYERS N/8 on the left, PING over the right-hand column.
	var header_pad := MarginContainer.new()
	header_pad.add_theme_constant_override("margin_left", 8)
	header_pad.add_theme_constant_override("margin_right", 8)
	column.add_child(header_pad)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header_pad.add_child(header)
	_scoreboard_count = Label.new()
	_scoreboard_count.text = "PLAYERS  0/%d" % Network.MAX_PLAYERS
	_scoreboard_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_scoreboard_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scoreboard_count.add_theme_font_size_override("font_size", 15)
	_scoreboard_count.add_theme_color_override("font_color", Color(1, 1, 1, 0.72))
	header.add_child(_scoreboard_count)
	_scoreboard_ping_header = Label.new()
	_scoreboard_ping_header.text = "PING"
	_scoreboard_ping_header.custom_minimum_size = Vector2(64, 0)
	_scoreboard_ping_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_scoreboard_ping_header.add_theme_font_size_override("font_size", 13)
	_scoreboard_ping_header.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	header.add_child(_scoreboard_ping_header)

	_scoreboard_rows = VBoxContainer.new()
	_scoreboard_rows.add_theme_constant_override("separation", 2)
	column.add_child(_scoreboard_rows)

	_scoreboard_row_style = StyleBoxFlat.new()
	_scoreboard_row_style.bg_color = Color(0, 0, 0, 0)
	_scoreboard_row_style.set_corner_radius_all(8)
	_scoreboard_row_style.content_margin_left = 8.0
	_scoreboard_row_style.content_margin_right = 8.0
	_scoreboard_row_style.content_margin_top = 0.0
	_scoreboard_row_style.content_margin_bottom = 0.0

	_scoreboard_local_style = StyleBoxFlat.new()
	# The "(YOU)" suffix identifies the local row. No yellow bar/tint.
	_scoreboard_local_style.bg_color = Color(1.0, 1.0, 1.0, 0.10)
	_scoreboard_local_style.set_corner_radius_all(8)
	_scoreboard_local_style.content_margin_left = 8.0
	_scoreboard_local_style.content_margin_right = 8.0
	_scoreboard_local_style.content_margin_top = 0.0
	_scoreboard_local_style.content_margin_bottom = 0.0

	add_child(_scoreboard)


func _ping_color(ms: int) -> Color:
	if ms < 60:
		return Color(0.45, 0.95, 0.55)
	if ms < 120:
		return Color(1.0, 0.82, 0.35)
	return Color(1.0, 0.45, 0.42)


func _make_scoreboard_row() -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 40)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _scoreboard_row_style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	panel.add_child(row)
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(12, 12)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var name_label := Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	row.add_child(name_label)
	var ping_label := Label.new()
	ping_label.custom_minimum_size = Vector2(64, 0)
	ping_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ping_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ping_label.add_theme_font_size_override("font_size", 16)
	row.add_child(ping_label)
	_scoreboard_rows.add_child(panel)
	return {"panel": panel, "dot": dot, "name": name_label, "ping": ping_label}


func _update_scoreboard() -> void:
	## Updates the rows in place. Rebuilding the whole list every tick made the
	## ping list flicker and fight the state pill for the top of the screen.
	if _scoreboard_rows == null:
		return
	var ids: Array[int] = [multiplayer.get_unique_id()]
	for peer_id: int in multiplayer.get_peers():
		ids.append(peer_id)
	ids.sort()
	_scoreboard_count.text = "PLAYERS  %d/%d" % [ids.size(), Network.MAX_PLAYERS]

	var stale: Array[int] = []
	for peer_id: int in _scoreboard_rows_cache:
		if not ids.has(peer_id):
			stale.append(peer_id)
	for peer_id: int in stale:
		var old: Dictionary = _scoreboard_rows_cache[peer_id]
		var old_panel: Node = old.get("panel")
		if is_instance_valid(old_panel):
			_scoreboard_rows.remove_child(old_panel)
			old_panel.queue_free()
		_scoreboard_rows_cache.erase(peer_id)

	var local_id: int = multiplayer.get_unique_id()
	for index in ids.size():
		var peer_id: int = ids[index]
		var entry: Dictionary = _scoreboard_rows_cache.get(peer_id, {})
		if entry.is_empty():
			entry = _make_scoreboard_row()
			_scoreboard_rows_cache[peer_id] = entry
		var panel: PanelContainer = entry["panel"]
		_scoreboard_rows.move_child(panel, index)
		var is_local: bool = peer_id == local_id
		panel.add_theme_stylebox_override("panel",
			_scoreboard_local_style if is_local else _scoreboard_row_style)
		(entry["dot"] as ColorRect).color = Network.color_of(peer_id)
		var name_label: Label = entry["name"]
		var text: String = Network.name_of(peer_id)
		if is_local:
			text += "  (YOU)"
		if peer_id == 1:
			text = "[HOST]  " + text
		name_label.text = text
		var ms: int = int(Network.ping_table.get(peer_id, 0))
		if ms <= 0 and not Network.is_host and is_local:
			ms = maxi(Network.latency_ms, 0)
		if ms <= 0 and Network.is_host and peer_id == 1:
			ms = maxi(Network.host_ping_ms, 0)
		var ping_label: Label = entry["ping"]
		ping_label.text = "%d ms" % ms
		ping_label.add_theme_color_override("font_color", _ping_color(ms))


func _set_scoreboard_visible(visible_now: bool) -> void:
	_scoreboard_visible = visible_now
	if _scoreboard == null:
		return
	if _scoreboard_fade != null and _scoreboard_fade.is_valid():
		_scoreboard_fade.kill()
	if visible_now:
		_scoreboard.visible = true
		_scoreboard.modulate.a = 0.0
		_scoreboard_refresh = 0.0
		_update_scoreboard()
		_scoreboard_fade = create_tween()
		_scoreboard_fade.tween_property(_scoreboard, "modulate:a", 1.0, 0.14) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		_scoreboard.visible = false


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
			return UiPalette.CREAM
		CartPlayer.CartState.AIRBORNE_TUMBLE:
			return UiPalette.BLUE
		CartPlayer.CartState.CRASHED:
			return UiPalette.RED
		CartPlayer.CartState.RECOVERY:
			return UiPalette.YELLOW
	return UiPalette.CREAM


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null:
		return
	if key.keycode == KEY_TAB and _scoreboard != null:
		# Minecraft-style: hold Tab to see who is in the room and their ping.
		if not key.echo:
			_set_scoreboard_visible(key.pressed)
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
