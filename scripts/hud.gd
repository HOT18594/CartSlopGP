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
var _plaque_delta: Label
var _lap_pips: HBoxContainer
var _lap_pip_total: int = 0
var _lap_pip_index: int = -1
var _gear_badge: PanelContainer
var _gear_value: Label
var _last_gear: String = ""
var _last_speed_text: String = ""
var _race_clock: float = 0.0
var _lap_start_time: float = 0.0
var _last_lap_seen: int = 0
var _hud_best_lap: float = -1.0
var _external_lap_readout: bool = false
var _last_lap_delta: float = 0.0
var _last_lap_delta_ms: int = 0
var _explicit_standings_ms: int = 0
var _explicit_position_ms: int = 0
var _network_standings_timer: float = 0.0
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
		_net_label.offset_left = -350.0
		_net_label.offset_top = 24.0
		_net_label.offset_right = -24.0
		_net_label.offset_bottom = 48.0
		_net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_net_label.custom_minimum_size = Vector2(326, 0)
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
	_build_gear_badge()
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
	_race_plaque.offset_right = 24.0 + 368.0
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
	var progress_row := HBoxContainer.new()
	progress_row.add_theme_constant_override("separation", 8)
	column.add_child(progress_row)
	_lap_pips = HBoxContainer.new()
	_lap_pips.add_theme_constant_override("separation", 4)
	_lap_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lap_pips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lap_pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	progress_row.add_child(_lap_pips)
	_plaque_delta = _label("", 13, Color(1, 1, 1, 0.6))
	_plaque_delta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_plaque_delta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_plaque_delta.visible = false
	progress_row.add_child(_plaque_delta)
	_race_plaque.visible = false


func _build_gear_badge() -> void:
	## Bottom-right, left of the dial: one quiet pill with the current gear.
	## Kept outside the speedometer so the needle and big digits stay clean.
	_gear_badge = PanelContainer.new()
	_gear_badge.name = "GearBadge"
	_gear_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gear_badge.anchor_left = 1.0
	_gear_badge.anchor_top = 1.0
	_gear_badge.anchor_right = 1.0
	_gear_badge.anchor_bottom = 1.0
	_gear_badge.offset_left = -330.0
	_gear_badge.offset_top = -100.0
	_gear_badge.offset_right = -206.0
	_gear_badge.offset_bottom = -60.0
	_gear_badge.add_theme_stylebox_override("panel",
		_panel_style(Color(0.118, 0.106, 0.227, 0.88), Color(1, 1, 1, 0.30)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_gear_badge.add_child(row)
	var caption := _label("GEAR", 12, Color(1, 1, 1, 0.6))
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(caption)
	_gear_value = _label("N", 28, UiPalette.YELLOW, 7)
	_gear_value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_gear_value)
	add_child(_gear_badge)


func _lap_pips_for(total: int) -> void:
	## Coarse track progress: one pip per lap. Rebuilt only when the lap count
	## changes, never per frame.
	_lap_pip_total = total
	_lap_pip_index = -1
	for child: Node in _lap_pips.get_children():
		_lap_pips.remove_child(child)
		child.queue_free()
	for _i in total:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(0, 6)
		pip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.color = Color(1, 1, 1, 0.22)
		_lap_pips.add_child(pip)
	_lap_pips.visible = total > 0


func _update_lap_pips(current: int) -> void:
	if _lap_pip_total <= 0:
		return
	var index: int = clampi(current - 1, 0, _lap_pip_total - 1)
	if index == _lap_pip_index:
		return
	_lap_pip_index = index
	var children: Array[Node] = _lap_pips.get_children()
	for i in children.size():
		var pip := children[i] as ColorRect
		if pip == null:
			continue
		if i < index:
			pip.color = UiPalette.YELLOW
		elif i == index:
			pip.color = UiPalette.YELLOW.lerp(Color.WHITE, 0.35)
		else:
			pip.color = Color(1, 1, 1, 0.22)


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
	_explicit_standings_ms = Time.get_ticks_msec()
	_apply_standings(entries)


func _apply_standings(entries: Array[Dictionary]) -> void:
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
	for child: Node in _standings_rows.get_children():
		_standings_rows.remove_child(child)
		child.queue_free()
	var leader: float = float(entries[0].get("progress", 0.0))
	var leader_time: float = float(entries[0].get("time", -1.0))
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
		var gap_text: String = "—"
		if not local:
			var entry_time: float = float(entry.get("time", -1.0))
			if entry_time > 0.0 and leader_time > 0.0:
				# Server standings carry a race time instead of a distance.
				gap_text = "+%.2fs" % maxf(entry_time - leader_time, 0.0)
			else:
				gap_text = "%dm" % int(gap)
		line.add_child(_label(gap_text, 12,
			Color(1, 1, 1, 0.55) if local else UiPalette.MUTED))
		_standings_rows.add_child(row)
	_standings_panel.visible = entries.size() > 1


func set_race_position(place: int, field_size: int = 0) -> void:
	## 1 -> "1st", 2 -> "2nd", ... Shows the race plaque automatically.
	_explicit_position_ms = Time.get_ticks_msec()
	_show_position(place, field_size)


func _show_position(place: int, field_size: int = 0) -> void:
	if _race_plaque == null:
		return
	show_position_badge = true
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
	var safe_total: int = maxi(total, 1)
	var safe_current: int = clampi(current, 1, safe_total)
	if safe_current != _last_lap_seen:
		# Bank the lap that just ended. The race owns the authoritative best
		# time; this local copy only bridges the gap until it is published.
		if _last_lap_seen > 0 and safe_current > _last_lap_seen:
			var completed: float = maxf(_race_clock - _lap_start_time, 0.0)
			if completed > 1.0:
				if _hud_best_lap > 0.0:
					_last_lap_delta = completed - _hud_best_lap
					_last_lap_delta_ms = Time.get_ticks_msec()
				if _hud_best_lap < 0.0 or completed < _hud_best_lap:
					_hud_best_lap = completed
		if safe_current <= 1 or safe_current < _last_lap_seen:
			_hud_best_lap = -1.0
			_last_lap_delta_ms = 0
			_lap_start_time = 0.0
		else:
			_lap_start_time = _race_clock
		_last_lap_seen = safe_current
		_external_lap_readout = false
	_plaque_lap.text = "LAP %d/%d" % [safe_current, safe_total]
	if safe_total != _lap_pip_total:
		_lap_pips_for(safe_total)
	_update_lap_pips(safe_current)
	_refresh_lap_readout()


func set_race_time(total_seconds: float, best_seconds: float = -1.0) -> void:
	## Fed by the race at ~20 Hz. The best lap is "—" until a lap is banked.
	if _plaque_time == null:
		return
	if total_seconds + 1.0 < _race_clock:
		# The clock jumped backwards: a new race started on the same HUD.
		_race_clock = 0.0
		_lap_start_time = 0.0
		_last_lap_seen = 0
		_hud_best_lap = -1.0
		_external_lap_readout = false
	_race_clock = maxf(total_seconds, 0.0)
	var total_text: String = _format_race_time(total_seconds)
	if _plaque_time.text != total_text:
		_plaque_time.text = total_text
	var best_text: String = _format_race_time(best_seconds) if best_seconds >= 0.0 else "—"
	if _plaque_best.text != best_text:
		_plaque_best.text = best_text
	if best_seconds > 0.0:
		_hud_best_lap = best_seconds
	_refresh_lap_readout()


func _refresh_lap_readout() -> void:
	## Live current lap time, plus the delta of the lap that just finished. The
	## delta is shown for a few seconds after the lap line rather than faking a
	## live comparison the HUD has no split data for.
	if _plaque_delta == null or _external_lap_readout:
		return
	if _last_lap_seen <= 0:
		return
	var current: float = maxf(_race_clock - _lap_start_time, 0.0)
	var parts: PackedStringArray = []
	if current >= 1.0:
		parts.append("LAP %s" % _format_race_time(current))
	if _last_lap_delta_ms > 0 \
			and Time.get_ticks_msec() - _last_lap_delta_ms < 6000:
		var delta: float = _last_lap_delta
		if delta >= 0.0:
			parts.append("LAST +%.2f" % delta)
			_plaque_delta.add_theme_color_override("font_color", Color(1, 0.55, 0.45))
		else:
			parts.append("LAST -%.2f" % absf(delta))
			_plaque_delta.add_theme_color_override("font_color", Color(0.55, 1.0, 0.65))
	if parts.is_empty():
		_plaque_delta.visible = false
		return
	var text: String = "  ·  ".join(parts)
	if _plaque_delta.text != text:
		_plaque_delta.text = text
	_plaque_delta.visible = true


func set_lap_time(lap_seconds: float, best_lap_seconds: float = -1.0) -> void:
	## Additive: an explicit current lap time and delta from an external race
	## clock. When unused, the plaque derives the same read from set_race_time.
	if _plaque_delta == null:
		return
	_external_lap_readout = true
	if lap_seconds < 0.0:
		_plaque_delta.visible = false
		return
	var delta_text: String = "LAP %s" % _format_race_time(lap_seconds)
	if best_lap_seconds > 0.0:
		_hud_best_lap = best_lap_seconds
		var delta: float = lap_seconds - best_lap_seconds
		if delta >= 0.0:
			delta_text += "  +%.2f" % delta
			_plaque_delta.add_theme_color_override("font_color", Color(1, 0.55, 0.45))
		else:
			delta_text += "  -%.2f" % absf(delta)
			_plaque_delta.add_theme_color_override("font_color", Color(0.55, 1.0, 0.65))
	if _plaque_delta.text != delta_text:
		_plaque_delta.text = delta_text
	_plaque_delta.visible = true


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
	_update_network_standings(delta)
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
	var speed_text: String = str(int(round(speed_kmh)))
	if speed_text != _last_speed_text:
		_last_speed_text = speed_text
		_speed_value.text = speed_text
	# Vehicles have different top speeds, so scale the dial to the current car.
	var gauge_max: float = cart.max_speed * cart.boost_speed_multiplier * 3.6 + 6.0
	if not is_equal_approx(float(_speed_gauge.get("max_speed_kmh")), gauge_max):
		_speed_gauge.set("max_speed_kmh", gauge_max)
	_speed_gauge.speed_kmh = speed_kmh
	_update_gear(cart, speed_kmh)

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
	# The relay round trip is what the player actually feels once the room is
	# going through the Pi; fall back to the peer latency on older servers.
	var ms: int = _server_ping_ms()
	var ping_text: String
	if Network.is_host and Network.is_lan():
		ping_text = "LAN HOST"
	elif ms > 0:
		ping_text = "SERVER %d ms" % ms
		if Network.is_host:
			ping_text += " (host)"
	else:
		ping_text = "SERVER —"
	var rx: String = _server_state_text()
	_net_label.text = "%s%s   ·   %d/%d" % [
		ping_text, rx, Network.peer_count(), Network.MAX_PLAYERS]


func _server_ping_ms() -> int:
	## relay_rtt_ms is the real server hop (Pi); older builds only expose
	## latency_ms / host_ping_ms, so never assume the new property is there.
	var relay: Variant = Network.get("relay_rtt_ms")
	if relay is int or relay is float:
		var rtt: int = int(relay)
		if rtt > 0:
			return rtt
	if Network.is_host:
		return maxi(Network.host_ping_ms, 0)
	return maxi(Network.latency_ms, 0)


func _server_state_text() -> String:
	## Host-only acknowledgement that the Pi is receiving live race state.
	## Clients do not stream state, so they keep just the ping readout.
	if not Network.is_host or not Network.in_game or not Network.is_session_active():
		return ""
	var receiving: Variant = Network.get("race_state_receiving")
	if receiving is bool and bool(receiving):
		return "  ·  RX"
	var enabled: Variant = Network.get("race_state_stream_enabled")
	if enabled is bool and not bool(enabled):
		return "  ·  OFF"
	return "  ·  WAIT"


func _update_gear(cart: CartPlayer, _speed_kmh: float) -> void:
	if _gear_value == null:
		return
	var forward: float = cart.velocity.dot(-cart.global_transform.basis.z)
	var gear: String = "N"
	if forward < -0.6:
		gear = "R"
	elif forward > 0.6:
		var ratio: float = clampf(forward / maxf(cart.max_speed, 0.1), 0.0, 1.0)
		gear = str(clampi(1 + int(ratio * 4.99), 1, 5))
	if gear == _last_gear:
		return
	_last_gear = gear
	_gear_value.text = gear


func _update_network_standings(delta: float) -> void:
	## Fallback feed for builds where the race fills Network.race_standings
	## instead of calling set_standings(). The explicit feed always wins; this
	## only runs when the race has not pushed a list for two seconds.
	if _standings_rows == null:
		return
	_network_standings_timer += delta
	if _network_standings_timer < 0.5:
		return
	_network_standings_timer = 0.0
	var raw: Variant = Network.get("race_standings")
	if not (raw is Array) or (raw as Array).is_empty():
		return
	var now: int = Time.get_ticks_msec()
	if now - _explicit_standings_ms < 2000:
		return
	var entries: Array[Dictionary] = _network_entries(raw as Array)
	if entries.is_empty():
		return
	_apply_standings(entries)
	if now - _explicit_position_ms > 3000:
		for index in entries.size():
			if bool(entries[index].get("local", false)):
				_show_position(index + 1, entries.size())
				break


func _network_entries(raw: Array) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var local_id: int = multiplayer.get_unique_id()
	for row: Variant in raw:
		if not (row is Dictionary):
			continue
		var entry: Dictionary = row
		var peer_id: int = int(entry.get("peer_id", entry.get("id", 0)))
		var name: String = str(entry.get("name", entry.get("player", "")))
		if name == "":
			name = Network.name_of(peer_id) if peer_id > 0 else "PLAYER"
		var local: bool = bool(entry.get("local", peer_id == local_id))
		var color: Variant = entry.get("color", Color.WHITE)
		var place: int = int(entry.get("place", entry.get("position",
			entry.get("rank", 0))))
		var time: float = float(entry.get("time", entry.get("race_time", -1.0)))
		var progress: float = float(entry.get("progress", 0.0))
		if progress == 0.0 and time > 0.0:
			# A server race reports finishing times, not track distance.
			progress = -time
		entries.append({
			"name": name,
			"progress": progress,
			"time": time,
			"local": local,
			"color": color if color is Color else Color.WHITE,
			"place": place,
		})
	var has_places: bool = true
	for entry: Dictionary in entries:
		if int(entry.get("place", 0)) <= 0:
			has_places = false
			break
	if has_places:
		entries.sort_custom(_sort_by_place)
	else:
		entries.sort_custom(_sort_by_progress)
	return entries


func _sort_by_place(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("place", 0)) < int(b.get("place", 0))


func _sort_by_progress(a: Dictionary, b: Dictionary) -> bool:
	return float(a.get("progress", 0.0)) > float(b.get("progress", 0.0))


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
