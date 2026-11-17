extends Control
## In-game HUD: speed dial, segmented boost meter, drive state, race plaque and
## live standings. F3 toggles the debug readout.
##
## The race readout is one quiet plaque in the top-left corner (position, lap,
## time, best) instead of a stack of bordered pills. `show_position_badge` /
## `show_lap_badge` stay part of the API and are fed by set_race_position() and
## set_lap(); the plaque itself appears as soon as either is called.
##
## The speed dial is painted by _draw_dial(): one thin arc carries the speed,
## the number is the biggest thing on the dial and the units sit below it. The
## old needle script is gone from hud.tscn, so nothing sweeps across the digits
## at speed. SpeedGauge is the layout anchor for the dial, the digits and the
## gear chip underneath them.
##
## Network and standings share the top-right corner: the ping readout is its own
## block above the standings plate, so the two can never overlap, and the list
## grows to every player instead of clipping at five.

const UiPalette := preload("res://scripts/ui/ui_palette.gd")

const DIAL_START: float = PI * 0.75 ## Dial arc opens at the lower left.
const DIAL_SWEEP: float = PI * 1.5 ## 270 degrees, leaving the bottom gap free.
const DIAL_SURFACE: Color = Color("101e32")
const DIAL_MUTED: Color = Color("71859a")
const DIAL_CYAN: Color = Color("55dfef")
const DIAL_GOLD: Color = Color("ffd166")

const NET_TOP: float = 18.0 ## Own corner block, above the standings plate.
const NET_HEIGHT: float = 26.0
const STANDINGS_TOP: float = 52.0
const STANDINGS_ROW_HEIGHT: float = 26.0
const STANDINGS_MAX_ROWS: int = 12 ## Room for every cart plus a few spectators.

@export_group("Minigame HUD")
@export var show_position_badge: bool = false ## Race placement readout (1st/2nd/...).
@export var show_lap_badge: bool = false ## Lap counter readout (LAP 1 / 3).

@onready var _speed_value: Label = %SpeedValue
@onready var _speed_gauge: Control = %SpeedGauge
@onready var _boost_meter: Control = %BoostMeter
@onready var _state_pill: PanelContainer = $StatePill
@onready var _state_label: Label = %StateLabel
@onready var _hint_label: Label = $HintLabel
@onready var _debug_label: Label = %DebugLabel

var _debug_visible: bool = false
var _hint_timer: float = 12.0
var _net_panel: PanelContainer
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
var _standings_row_cache: Array[Dictionary] = []
var _boost_caption: Label
var _last_boost_caption: String = ""
var _last_place: int = 0
var _position_tween: Tween
var _standings_title: Label
var _dial_ratio: float = 0.0 ## Smoothed 0..1 arc fill.
var _dial_boost: float = 0.0 ## Smoothed accent tint while boosting.
var _dial_max_kmh: float = 120.0 ## Dial top speed, recomputed from the cart.


func _ready() -> void:
	# Controls live in the pause menu now; no permanent hint line in the race.
	_hint_timer = 0.0
	_hint_label.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if Network.is_session_active():
		_build_net_block()
		_build_scoreboard()
	_debug_label.visible = false
	_build_boost_percent()
	_build_race_plaque()
	_build_standings()
	_build_gear_badge()
	_state_pill.visible = false
	GameSettings.changed.connect(_apply_display_settings)
	resized.connect(_apply_display_settings)
	_apply_display_settings()
	call_deferred("_apply_display_settings")


func _build_boost_percent() -> void:
	_boost_caption = $BoostBox/BoostCaption
	_boost_caption.add_theme_font_size_override("font_size", 13)
	_boost_caption.add_theme_constant_override("outline_size", 3)
	_boost_percent = _label("100%", 13, Color("e7f3ff"), 3)
	_boost_percent.name = "BoostPercent"
	_boost_percent.anchor_left = 1.0
	_boost_percent.anchor_right = 1.0
	_boost_percent.offset_left = -64.0
	_boost_percent.offset_top = -27.0
	_boost_percent.offset_right = 0.0
	_boost_percent.offset_bottom = -5.0
	_boost_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_boost_meter.add_child(_boost_percent)


func _apply_display_settings() -> void:
	var available_scale: float = minf(size.x / 960.0, size.y / 600.0)
	var scale_factor: float = minf(clampf(GameSettings.hud_scale, 0.75, 1.5), maxf(available_scale, 0.5))
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
			_fps_label.offset_top = -270.0
			_fps_label.offset_right = -28.0
			_fps_label.offset_bottom = -246.0
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
	# The dial is painted from the scaled rect, so it must re-measure.
	queue_redraw()


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


func _panel_style(bg: Color) -> StyleBoxFlat:
	## Quiet translucent block: no outline, no stacked borders. Text and colour
	## carry the information, and the plate only severs it from the track.
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(16)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	style.anti_aliasing = true
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
	_race_plaque.offset_right = 24.0 + 340.0
	_race_plaque.offset_bottom = 20.0 + 120.0
	_race_plaque.add_theme_stylebox_override("panel",
		_panel_style(Color(0.063, 0.118, 0.196, 0.94)))
	add_child(_race_plaque)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	_race_plaque.add_child(column)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	column.add_child(top)
	_plaque_pos = _label("1ST", 44, Color("ffd166"))
	top.add_child(_plaque_pos)
	var pos_stack := VBoxContainer.new()
	pos_stack.size_flags_vertical = Control.SIZE_SHRINK_END
	pos_stack.add_theme_constant_override("separation", 0)
	top.add_child(pos_stack)
	_plaque_of = _label("OF —", 14, Color(1, 1, 1, 0.72))
	pos_stack.add_child(_plaque_of)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	_plaque_lap = _label("LAP 1/3", 20, UiPalette.CREAM)
	_plaque_lap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_plaque_lap)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	column.add_child(bottom)
	var time_caption := _label("TIME", 13, Color(1, 1, 1, 0.65))
	time_caption.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(time_caption)
	_plaque_time = _label("0:00.000", 26, UiPalette.YELLOW)
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
	_gear_badge = PanelContainer.new()
	_gear_badge.name = "GearBadge"
	_gear_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gear_badge.anchor_left = 0.5
	_gear_badge.anchor_top = 0.5
	_gear_badge.anchor_right = 0.5
	_gear_badge.anchor_bottom = 0.5
	_gear_badge.offset_left = -32.0
	_gear_badge.offset_top = 54.0
	_gear_badge.offset_right = 32.0
	_gear_badge.offset_bottom = 80.0
	var style := _panel_style(Color(0.5, 0.7, 0.85, 0.12))
	style.set_corner_radius_all(5)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 1.0
	style.content_margin_bottom = 1.0
	_gear_badge.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_gear_badge.add_child(row)
	var caption := _label("GEAR", 9, Color("98aebf"))
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(caption)
	_gear_value = _label("N", 17, Color("55dfef"))
	_gear_value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_gear_value)
	_speed_gauge.add_child(_gear_badge)


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


func _build_net_block() -> void:
	## Ping and peer count get their own corner block, stacked above the
	## standings. They used to share the corner, so the server line could be
	## drawn over the first standings row once the field grew.
	_net_panel = PanelContainer.new()
	_net_panel.name = "NetBlock"
	_net_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_net_panel.anchor_left = 1.0
	_net_panel.anchor_right = 1.0
	_net_panel.offset_left = -336.0
	_net_panel.offset_right = -24.0
	_net_panel.offset_top = NET_TOP
	_net_panel.offset_bottom = NET_TOP + NET_HEIGHT
	var style := _panel_style(Color(0.063, 0.118, 0.196, 0.78))
	style.set_corner_radius_all(10)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	_net_panel.add_theme_stylebox_override("panel", style)
	_net_label = _label("SERVER —", 13, Color(1, 1, 1, 0.86), 3)
	_net_label.name = "NetStats"
	_net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_net_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# A long readout is trimmed inside its block instead of pushing the block
	# past the screen edge.
	_net_label.clip_text = true
	_net_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_net_panel)
	_net_panel.add_child(_net_label)


func _build_standings() -> void:
	_standings_panel = PanelContainer.new()
	_standings_panel.name = "LiveStandings"
	_standings_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_standings_panel.anchor_left = 1.0
	_standings_panel.anchor_right = 1.0
	_standings_panel.offset_left = -300.0
	_standings_panel.offset_right = -24.0
	# Below the network block, never behind it.
	_standings_panel.offset_top = STANDINGS_TOP
	_standings_panel.offset_bottom = STANDINGS_TOP
	_standings_panel.add_theme_stylebox_override("panel",
		_panel_style(Color(0.063, 0.118, 0.196, 0.92)))
	add_child(_standings_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	_standings_panel.add_child(column)
	_standings_title = _label("STANDINGS", 13, Color(1, 1, 1, 0.62))
	column.add_child(_standings_title)
	_standings_rows = VBoxContainer.new()
	_standings_rows.add_theme_constant_override("separation", 2)
	column.add_child(_standings_rows)
	_standings_panel.visible = false


func set_standings(entries: Array[Dictionary]) -> void:
	## Live race order. Called at ~4 Hz by the race, never per frame.
	_explicit_standings_ms = Time.get_ticks_msec()
	_apply_standings(entries)


func _apply_standings(entries: Array[Dictionary]) -> void:
	if _standings_rows == null:
		return
	_standings_panel.visible = entries.size() > 1
	if entries.is_empty():
		return
	# Every cart gets a row. The old five-row cap silently deleted the back of
	# the field (and then substituted the local cart into the last slot, which
	# hid a real player); rows are 26 px tall so a full eight-cart room fits.
	var visible_count: int = mini(entries.size(), STANDINGS_MAX_ROWS)
	if entries.size() > 1:
		_standings_title.text = "STANDINGS  %d" % entries.size()
	else:
		_standings_title.text = "STANDINGS"
	while _standings_row_cache.size() < visible_count:
		var row := PanelContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.custom_minimum_size = Vector2(0, STANDINGS_ROW_HEIGHT)
		var style := _panel_style(Color(1, 1, 1, 0.035))
		style.set_corner_radius_all(6)
		style.content_margin_left = 8.0
		style.content_margin_right = 8.0
		style.content_margin_top = 3.0
		style.content_margin_bottom = 3.0
		row.add_theme_stylebox_override("panel", style)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 7)
		row.add_child(line)
		var place_label := _label("", 13, Color.WHITE)
		place_label.custom_minimum_size.x = 16.0
		line.add_child(place_label)
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(3, 12)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(dot)
		var name_label := _label("", 13, Color.WHITE)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.clip_text = true
		line.add_child(name_label)
		var gap_label := _label("", 10, Color("98aebf"))
		gap_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(gap_label)
		_standings_rows.add_child(row)
		_standings_row_cache.append({"row": row, "style": style, "place": place_label,
			"dot": dot, "name": name_label, "gap": gap_label})
	var leader: float = float(entries[0].get("progress", 0.0))
	var leader_time: float = float(entries[0].get("time", -1.0))
	for slot in _standings_row_cache.size():
		var cached: Dictionary = _standings_row_cache[slot]
		(cached["row"] as Control).visible = slot < visible_count
		if slot >= visible_count:
			continue
		var entry: Dictionary = entries[slot]
		var local: bool = bool(entry.get("local", false))
		(cached["style"] as StyleBoxFlat).bg_color = Color(0.33, 0.87, 0.94, 0.16) if local else Color(1, 1, 1, 0.035)
		var place: int = int(entry.get("place", 0))
		(cached["place"] as Label).text = str(place if place > 0 else slot + 1)
		(cached["place"] as Label).add_theme_color_override("font_color", Color("55dfef") if local else Color.WHITE)
		(cached["dot"] as ColorRect).color = entry.get("color", Color.WHITE)
		(cached["name"] as Label).text = str(entry.get("name", "PLAYER")) + (" · YOU" if local else "")
		var gap_text: String = "LEADER"
		if slot > 0:
			var entry_time: float = float(entry.get("time", -1.0))
			if entry_time > 0.0 and leader_time > 0.0:
				gap_text = "+%.2fs" % maxf(entry_time - leader_time, 0.0)
			else:
				gap_text = "+%dm" % int(maxf(leader - float(entry.get("progress", 0.0)), 0.0))
		(cached["gap"] as Label).text = gap_text


func set_race_position(place: int, field_size: int = 0) -> void:
	## 1 -> "1st", 2 -> "2nd", ... Shows the race plaque automatically.
	_explicit_position_ms = Time.get_ticks_msec()
	_show_position(place, field_size)


func _show_position(place: int, field_size: int = 0) -> void:
	if _race_plaque == null:
		return
	place = maxi(place, 1) ## A 0th place used to print "0TH".
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
	if _last_place > 0 and place != _last_place:
		if _position_tween != null and _position_tween.is_valid():
			_position_tween.kill()
		_plaque_pos.modulate = Color("55dfef") if place < _last_place else Color("ff887e")
		_position_tween = create_tween()
		_position_tween.tween_property(_plaque_pos, "modulate", Color.WHITE, 0.45)
	_last_place = place
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
		_last_lap_delta_ms = 0
		_last_place = 0
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
	_plaque_delta.add_theme_color_override("font_color", Color("98aebf"))
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
	_plaque_delta.add_theme_color_override("font_color", Color("98aebf"))
	if _plaque_delta.text != delta_text:
		_plaque_delta.text = delta_text
	_plaque_delta.visible = true


func _format_race_time(seconds: float) -> String:
	var milliseconds: int = roundi(maxf(seconds, 0.0) * 1000.0)
	return "%d:%02d.%03d" % [milliseconds / 60000, (milliseconds / 1000) % 60, milliseconds % 1000]


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
	_dial_max_kmh = ceilf((cart.max_speed * cart.boost_speed_multiplier * 3.6 + 6.0) / 20.0) * 20.0
	var target_ratio: float = clampf(speed_kmh / maxf(_dial_max_kmh, 20.0), 0.0, 1.0)
	var next_ratio: float = lerpf(_dial_ratio, target_ratio, 1.0 - exp(-delta * 15.0))
	var next_boost: float = move_toward(_dial_boost, 1.0 if cart.boost_active else 0.0, delta * 5.0)
	if absf(next_ratio - target_ratio) < 0.0015:
		next_ratio = target_ratio
	if not is_equal_approx(next_ratio, _dial_ratio) \
			or not is_equal_approx(next_boost, _dial_boost):
		_dial_ratio = next_ratio
		_dial_boost = next_boost
		queue_redraw()
	_update_gear(cart, speed_kmh)

	var boost_ratio: float = clampf(cart.boost_amount / maxf(cart.max_boost, 0.1), 0.0, 1.0)
	_boost_meter.ratio = boost_ratio
	_boost_meter.boosting = cart.boost_active
	var boost_caption: String = "BOOST ACTIVE" if cart.boost_active else ("RECHARGING" if boost_ratio < 0.15 else "BOOST READY")
	if boost_caption != _last_boost_caption:
		_last_boost_caption = boost_caption
		_boost_caption.text = boost_caption
		_boost_caption.add_theme_color_override("font_color", Color("ffd166") if cart.boost_active else Color("e7f3ff"))
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
	# Two passes: the boost halo first, then the opaque dial on top of it, so
	# only the halo ring outside the dial stays visible.
	_draw_boost_glow()
	_draw_dial()


func _gauge_rect() -> Rect2:
	## Dial rectangle in HUD-canvas space. get_global_rect() ignores the scale
	## _apply_display_settings() puts on the dial's own Control, which made the
	## painted dial shrink and drift away from its digits at 125-150% HUD scale.
	if _speed_gauge == null or not is_instance_valid(_speed_gauge):
		return Rect2()
	var gauge_scale: Vector2 = _speed_gauge.get_global_transform().get_scale()
	return Rect2(_speed_gauge.get_global_position(), _speed_gauge.size * gauge_scale)


func _draw_boost_glow() -> void:
	# Drawn on the HUD root, so the glow sits behind the opaque dial and only
	# its halo is visible. Three rings are cheaper than a shader.
	var gauge_rect: Rect2 = _gauge_rect()
	if _boost_glow <= 0.001 or gauge_rect.size.x <= 0.0:
		return
	var center: Vector2 = gauge_rect.position + gauge_rect.size * 0.5
	var radius: float = maxf(gauge_rect.size.x, gauge_rect.size.y) * 0.5
	var pulse: float = 1.0 if GameSettings.reduce_motion else 0.9 + 0.1 * sin(Time.get_ticks_msec() * 0.012)
	for index in 3:
		var spread: float = radius + 8.0 + float(index) * 9.0
		var alpha: float = (0.16 - float(index) * 0.045) * _boost_glow * pulse
		draw_circle(center, spread, Color(0.25, 0.85, 1.0, alpha))


func _draw_dial() -> void:
	## Arc-first speedometer: a 270 degree track carries the speed, a thin
	## bright cap marks the exact value and the big number stays untouched.
	## There is no needle, so nothing crosses the digits while driving, and no
	## tick numerals either: the hero digits are the only number on the dial.
	var gauge_rect: Rect2 = _gauge_rect()
	var radius: float = minf(gauge_rect.size.x, gauge_rect.size.y) * 0.5 - 5.0
	if radius < 24.0:
		return
	var center: Vector2 = gauge_rect.position + gauge_rect.size * 0.5
	var accent: Color = DIAL_CYAN.lerp(DIAL_GOLD, _dial_boost)
	var ring: float = radius * 0.92
	draw_circle(center + Vector2(0.0, 4.0), radius + 3.0, Color(0.02, 0.04, 0.08, 0.22))
	draw_circle(center, radius, Color(DIAL_SURFACE, 0.96))
	draw_arc(center, radius - 1.0, 0.0, TAU, 80, Color(0.7, 0.85, 1.0, 0.16), 1.5, true)
	draw_arc(center, ring, DIAL_START, DIAL_START + DIAL_SWEEP, 72,
		Color(0.55, 0.7, 0.85, 0.16), 9.0, true)
	if _dial_ratio > 0.004:
		draw_arc(center, ring, DIAL_START, DIAL_START + DIAL_SWEEP * _dial_ratio,
			maxi(3, int(72.0 * _dial_ratio)), accent, 9.0, true)
		# Thin arc-style indicator: a short bright cap on the arc plus a 2 px
		# outboard tick. It reads at a glance without hiding the arc.
		var tip: float = DIAL_START + DIAL_SWEEP * _dial_ratio
		draw_arc(center, ring, maxf(tip - 0.11, DIAL_START), tip, 12,
			Color(1, 1, 1, 0.88), 3.0, true)
		var direction := Vector2(cos(tip), sin(tip))
		draw_line(center + direction * (radius * 0.955),
			center + direction * (radius * 0.995), Color(1, 1, 1, 0.9), 2.0, true)
	for index in 25:
		var fraction: float = float(index) / 24.0
		var angle: float = DIAL_START + DIAL_SWEEP * fraction
		var direction := Vector2(cos(angle), sin(angle))
		var major: bool = index % 6 == 0
		var inner: float = 0.655 if major else 0.70
		var outer: float = 0.75 if major else 0.735
		var tick_color: Color = accent if fraction <= _dial_ratio + 0.0001 \
			else Color(DIAL_MUTED, 0.55)
		draw_line(center + direction * (radius * inner),
			center + direction * (radius * outer), tick_color,
			2.0 if major else 1.0, true)


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
	style.bg_color = Color(0.06, 0.07, 0.15, 0.82)
	style.set_corner_radius_all(UiKit.CORNER_RADIUS)
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
	# Zero height: the panel's own content sets the height, growing downward.
	# The old offset_bottom (64) was above offset_top, a negative rect.
	_scoreboard.offset_bottom = 150.0
	_scoreboard.grow_vertical = Control.GROW_DIRECTION_END
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
		## A peer with no sample yet is unknown, not a perfect 0 ms connection.
		if ms <= 0:
			ping_label.text = "—"
			ping_label.add_theme_color_override("font_color", Color(0.62, 0.66, 0.78))
		else:
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
