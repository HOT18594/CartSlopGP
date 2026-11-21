extends Control
## Clean arcade HUD: essential race data, compact standings and slanted meters.
## Typography and contrast stay readable without decorative boxes or constant motion.

const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const TITLE_FONT: Font = preload("res://assets/ui/fonts/LuckiestGuy-Regular.ttf")
const BODY_FONT: Font = preload("res://assets/ui/fonts/Fredoka-Bold.ttf")

const DIAL_START: float = PI * 0.78 ## Lower-left opening of the 14-cell arc.
const DIAL_SWEEP: float = PI * 1.44 ## 260 degrees, framing the bottom gear slash.
const TACH_CELLS: int = 14
const HARD_SHADOW_COLOR := Color(0.08, 0.06, 0.16, 0.85)
const PLATE_SHADOW_COLOR := Color(0.07, 0.05, 0.15, 0.88)

const DRIFT_TIER_COLORS: Array[Color] = [
	Color("38d6f0"),
	Color("38e8ff"),
	Color("ff922b"),
	Color("ff3ec9"),
]
const DRIFT_TIER_NAMES: PackedStringArray = ["", "TURBO!", "BLAZE!", "ULTRA!"]

const NET_TOP: float = 16.0
const NET_HEIGHT: float = 32.0
const STANDINGS_SOLO_TOP: float = 18.0
const STANDINGS_NET_TOP: float = 56.0
const STANDINGS_ROW_HEIGHT: float = 29.0
const STANDINGS_COMPACT_ROW_HEIGHT: float = 24.0
const STANDINGS_MAX_ROWS: int = 16

@export_group("Minigame HUD")
@export var show_position_badge: bool = false
@export var show_lap_badge: bool = false

@onready var _speed_value: Label = %SpeedValue
@onready var _speed_gauge: Control = %SpeedGauge
@onready var _boost_box: VBoxContainer = $BoostBox
@onready var _boost_caption: Label = %BoostCaption
@onready var _boost_percent: Label = %BoostPercent
@onready var _boost_meter: Control = %BoostMeter
@onready var _state_pill: PanelContainer = $StatePill
@onready var _state_label: Label = %StateLabel
@onready var _hint_label: Label = $HintLabel
@onready var _debug_label: Label = %DebugLabel


class _SlashPlate extends Control:
	var skew_px: float = 12.0
	var fill_color: Color = Color("1e1b3a")
	var border_color: Color = Color("1e1b3a")
	var border_width: float = 3.5
	var shadow_offset := Vector2(4.0, 5.0)
	var accent_color := Color(0.0, 0.0, 0.0, 0.0)
	var accent_width: float = 0.0
	var draw_sheen: bool = true

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var pad_l: float = 2.0
		var pad_t: float = 2.0
		var pad_r: float = maxf(shadow_offset.x + 2.0, 3.0)
		var pad_b: float = maxf(shadow_offset.y + 2.0, 3.0)
		var sk: float = minf(skew_px, maxf(size.x * 0.22, 4.0))
		var w: float = size.x - pad_l - pad_r - sk
		var h: float = size.y - pad_t - pad_b
		if w <= 4.0 or h <= 4.0:
			return
		var pts := PackedVector2Array([
			Vector2(pad_l + sk, pad_t),
			Vector2(pad_l + sk + w, pad_t),
			Vector2(pad_l + w, pad_t + h),
			Vector2(pad_l, pad_t + h),
		])
		if shadow_offset.length_squared() > 0.1:
			var sh := PackedVector2Array([
				pts[0] + shadow_offset,
				pts[1] + shadow_offset,
				pts[2] + shadow_offset,
				pts[3] + shadow_offset,
			])
			draw_colored_polygon(sh, PLATE_SHADOW_COLOR)

		draw_colored_polygon(pts, fill_color)

		if accent_width > 0.5 and accent_color.a > 0.01:
			var aw: float = minf(accent_width, w * 0.45)
			var wedge := PackedVector2Array([
				Vector2(pad_l + sk, pad_t),
				Vector2(pad_l + sk + aw, pad_t),
				Vector2(pad_l + aw, pad_t + h),
				Vector2(pad_l, pad_t + h),
			])
			draw_colored_polygon(wedge, accent_color)
			draw_line(
				Vector2(pad_l + sk + aw, pad_t),
				Vector2(pad_l + aw, pad_t + h),
				UiPalette.INK, 2.5, true)

		if draw_sheen and h >= 12.0:
			var sh_h: float = maxf(h * 0.28, 2.5)
			var sheen := PackedVector2Array([
				Vector2(pad_l + sk + 1.5, pad_t + 1.5),
				Vector2(pad_l + sk + w - 1.5, pad_t + 1.5),
				Vector2(pad_l + sk * 0.72 + w - 1.5, pad_t + 1.5 + sh_h),
				Vector2(pad_l + sk * 0.72 + 1.5, pad_t + 1.5 + sh_h),
			])
			draw_colored_polygon(sheen, Color(1.0, 1.0, 1.0, 0.20))

		if border_width > 0.1:
			var closed := pts.duplicate()
			closed.append(pts[0])
			draw_polyline(closed, border_color, border_width, true)


class _PlaqueSlashBackdrop extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		# Sharp comic accent rule slashing under the 1ST + LAP 1/3 row (zero dark box!).
		var y: float = 56.0
		var w: float = minf(size.x - 18.0, 312.0)
		if w <= 24.0 or size.y < 64.0:
			return
		var sk: float = 10.0
		var h: float = 5.5
		var pts := PackedVector2Array([
			Vector2(4.0 + sk, y),
			Vector2(4.0 + sk + w, y),
			Vector2(4.0 + w, y + h),
			Vector2(4.0, y + h),
		])
		var sh := PackedVector2Array([
			pts[0] + Vector2(3.0, 3.5),
			pts[1] + Vector2(3.0, 3.5),
			pts[2] + Vector2(3.0, 3.5),
			pts[3] + Vector2(3.0, 3.5),
		])
		draw_colored_polygon(sh, PLATE_SHADOW_COLOR)
		draw_colored_polygon(pts, UiPalette.CYAN)
		var lead := PackedVector2Array([
			Vector2(4.0 + sk, y),
			Vector2(4.0 + sk + 78.0, y),
			Vector2(4.0 + 78.0, y + h),
			Vector2(4.0, y + h),
		])
		draw_colored_polygon(lead, UiPalette.YELLOW)
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, UiPalette.INK, 2.5, true)


class _LapPipSlash extends Control:
	var state: int = 0 ## 0 = upcoming, 1 = active, 2 = completed

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var sk: float = 5.5
		var w: float = size.x - sk - 4.0
		var h: float = size.y - 4.0
		if w <= 3.0 or h <= 3.0:
			return
		var pts := PackedVector2Array([
			Vector2(1.0 + sk, 1.0),
			Vector2(1.0 + sk + w, 1.0),
			Vector2(1.0 + w, 1.0 + h),
			Vector2(1.0, 1.0 + h),
		])
		var sh := PackedVector2Array([
			pts[0] + Vector2(2.5, 3.0),
			pts[1] + Vector2(2.5, 3.0),
			pts[2] + Vector2(2.5, 3.0),
			pts[3] + Vector2(2.5, 3.0),
		])
		draw_colored_polygon(sh, PLATE_SHADOW_COLOR)
		var fill: Color = Color(0.118, 0.106, 0.227, 0.88)
		if state == 2:
			fill = UiPalette.YELLOW
		elif state == 1:
			fill = UiPalette.CYAN
		draw_colored_polygon(pts, fill)
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, UiPalette.INK, 2.2, true)


class _DialCanvas extends Control:
	func _draw() -> void:
		var gauge: Node = get_parent()
		if gauge != null and gauge.get_parent() != null:
			gauge.get_parent().call("_draw_gauge_canvas", self)


class _SpeedLinesOverlay extends Control:
	## Radial anime/arcade speed streaks around viewport margins at high speed
	## or while boosting. Stays invisible below threshold and respects reduce_motion.
	var intensity: float = 0.0
	var boost_mix: float = 0.0
	var phase: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false

	func _draw() -> void:
		if intensity < 0.02 or size.x < 40.0 or size.y < 40.0:
			return
		var center: Vector2 = size * 0.5
		var outer_r: float = center.length() * 1.06
		var inner_base: float = minf(size.x, size.y) * lerpf(0.46, 0.34, intensity)
		var rays: int = 26
		for i in rays:
			var ang: float = TAU * float(i) / float(rays) + sin(float(i) * 3.1) * 0.05
			var pulse: float = 0.5 + 0.5 * sin(phase * 18.0 + float(i) * 2.3)
			var dir := Vector2(cos(ang), sin(ang))
			var perp := Vector2(-dir.y, dir.x)
			var r_in: float = inner_base + pulse * 48.0
			var tip: Vector2 = center + dir * r_in
			var base_p: Vector2 = center + dir * outer_r
			var half_w: float = (1.6 + 2.8 * intensity) * (0.65 + 0.5 * pulse)
			var col: Color = Color(1.0, 1.0, 1.0, 0.24 * intensity * (0.55 + 0.45 * pulse))
			if boost_mix > 0.15:
				var boost_col: Color = UiPalette.CYAN if i % 2 == 0 else UiPalette.YELLOW
				col = col.lerp(Color(boost_col.r, boost_col.g, boost_col.b, 0.36 * intensity), boost_mix)
			draw_colored_polygon(PackedVector2Array([
				tip,
				base_p + perp * half_w,
				base_p - perp * half_w,
			]), col)


var _dial_canvas: _DialCanvas
var _state_plate: _SlashPlate
var _debug_visible: bool = false
var _hint_timer: float = 0.0
var _net_panel: PanelContainer
var _net_plate: _SlashPlate
var _net_label: Label
var _net_timer: float = 0.0
var _scoreboard: PanelContainer
var _scoreboard_plate: _SlashPlate
var _scoreboard_rows: VBoxContainer
var _scoreboard_count: Label
var _scoreboard_ping_header: Label
var _scoreboard_visible: bool = false
var _scoreboard_refresh: float = 0.0
var _scoreboard_rows_cache: Dictionary = {}
var _scoreboard_fade: Tween
var _boost_glow: float = 0.0
var _boost_glow_was_visible: bool = false
var _last_boost_percent: int = -1
var _fps_label: Label
var _fps_timer: float = 0.0
var _cart_cache: CartPlayer
var _last_state_text: String = ""
var _last_state_color: Color = Color.WHITE
var _race_plaque: PanelContainer
var _plaque_pos: Label
var _plaque_of: Label
var _lap_tag_panel: PanelContainer
var _lap_tag_plate: _SlashPlate
var _plaque_lap: Label
var _plaque_time: Label
var _plaque_best: Label
var _plaque_delta: Label
var _delta_badge: PanelContainer
var _delta_plate: _SlashPlate
var _lap_pips: HBoxContainer
var _lap_pip_total: int = 0
var _lap_pip_index: int = -1
var _gear_badge: PanelContainer
var _gear_plate: _SlashPlate
var _gear_value: Label
var _last_gear: String = ""
var _drift_badge: PanelContainer
var _drift_plate: _SlashPlate
var _drift_badge_label: Label
var _drift_arc_ratio: float = 0.0
var _drift_tier: int = 0
var _drift_active: bool = false
var _wrong_way_banner: PanelContainer
var _wrong_way_plate: _SlashPlate
var _wrong_way_label: Label
var _wrong_way_active: bool = false
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
var _last_standings_entries: Array[Dictionary] = []
var _last_boost_caption: String = ""
var _last_boost_color: Color = Color.WHITE
var _last_place: int = 0
var _position_tween: Tween
var _standings_title: Label
var _dial_ratio: float = 0.0
var _dial_boost: float = 0.0
var _dial_max_kmh: float = 120.0
var _hud_scale_factor: float = 1.0
var _speed_lines: _SpeedLinesOverlay
var _callout_panel: PanelContainer
var _callout_plate: _SlashPlate
var _callout_label: Label
var _callout_tween: Tween
var _air_seconds: float = 0.0
var _was_airborne: bool = false
var _prev_drift_tier_for_callout: int = 0
var _callout_cooldown_ms: int = 0


func _ready() -> void:
	_hint_timer = 0.0
	_hint_label.visible = false
	if _boost_percent != null:
		_boost_percent.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_speed_lines()
	_build_state_plate()
	_build_dial_canvas()
	_build_net_block()
	_build_scoreboard()
	if _net_panel != null:
		_net_panel.visible = Network.is_session_active()
	if _scoreboard != null:
		_scoreboard.visible = false
	_debug_label.visible = false
	_build_boost_header()
	_build_race_plaque()
	_build_standings()
	_build_gear_badge()
	_build_drift_badge()
	_build_wrong_way_banner()
	_build_callout_banner()
	_state_pill.visible = false
	for child: Node in get_children():
		if child is Control:
			_bind_hud_cluster(child as Control)
	GameSettings.changed.connect(_apply_display_settings)
	resized.connect(_apply_display_settings)
	_apply_display_settings()
	call_deferred("_apply_display_settings")


func _bind_hud_cluster(control: Control) -> void:
	if control == null:
		return
	var cb: Callable = _update_cluster_pivot.bind(control)
	if not control.resized.is_connected(cb):
		control.resized.connect(cb)


func _update_cluster_pivot(control: Control) -> void:
	if control != null and is_instance_valid(control):
		control.pivot_offset = _hud_pivot(control)


func bind_cart(cart: CartPlayer) -> void:
	## Explicit cart binding hook used by race/minigame scenes.
	_cart_cache = cart


func set_cart(cart: CartPlayer) -> void:
	bind_cart(cart)


func _empty_style(pad_l: float = 0.0, pad_t: float = 0.0,
		pad_r: float = 0.0, pad_b: float = 0.0) -> StyleBoxEmpty:
	var st := StyleBoxEmpty.new()
	st.content_margin_left = pad_l
	st.content_margin_top = pad_t
	st.content_margin_right = pad_r
	st.content_margin_bottom = pad_b
	return st


func _attach_slash(host: Control, skew: float, fill: Color,
		border: Color = UiPalette.INK, border_w: float = 3.5,
		shadow := Vector2(4.0, 5.0)) -> _SlashPlate:
	var plate := _SlashPlate.new()
	plate.name = "SlashBackdrop"
	plate.skew_px = skew
	plate.fill_color = fill
	plate.border_color = border
	plate.border_width = minf(border_w, 1.5)
	plate.shadow_offset = shadow * 0.35
	plate.draw_sheen = false
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(plate)
	host.move_child(plate, 0)
	return plate


func _slash_margin(host: PanelContainer, pad_l: int, pad_t: int,
		pad_r: int, pad_b: int) -> MarginContainer:
	host.add_theme_stylebox_override("panel", _empty_style())
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", pad_l)
	margin.add_theme_constant_override("margin_top", pad_t)
	margin.add_theme_constant_override("margin_right", pad_r)
	margin.add_theme_constant_override("margin_bottom", pad_b)
	host.add_child(margin)
	return margin


func _label(text: String, font_size: int, color: Color,
		outline: int = 6, hard_shadow: bool = true) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.theme_type_variation = &"TitleLabel"
	label.add_theme_font_override("font", BODY_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if outline > 0:
		label.add_theme_color_override("font_outline_color", Color(0.05, 0.07, 0.11, 0.88))
		label.add_theme_constant_override("outline_size", mini(outline, 3))
	else:
		label.add_theme_constant_override("outline_size", 0)
	if hard_shadow:
		label.add_theme_color_override("font_shadow_color", HARD_SHADOW_COLOR)
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 2)
	else:
		label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.0))
		label.add_theme_constant_override("shadow_offset_x", 0)
		label.add_theme_constant_override("shadow_offset_y", 0)
	return label


func _build_state_plate() -> void:
	if _state_pill == null:
		return
	var margin := _slash_margin(_state_pill, 28, 8, 30, 12)
	if _state_label != null and _state_label.get_parent() == _state_pill:
		_state_label.reparent(margin)
	_state_plate = _attach_slash(_state_pill, 12.0, UiPalette.INK, UiPalette.CREAM, 3.5)


func _build_speed_lines() -> void:
	_speed_lines = _SpeedLinesOverlay.new()
	_speed_lines.name = "SpeedLinesOverlay"
	_speed_lines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_speed_lines)
	move_child(_speed_lines, 0)


func _build_callout_banner() -> void:
	_callout_panel = PanelContainer.new()
	_callout_panel.name = "StuntCallout"
	_callout_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_callout_panel.anchor_left = 0.5
	_callout_panel.anchor_right = 0.5
	_callout_panel.anchor_top = 0.0
	_callout_panel.anchor_bottom = 0.0
	_callout_panel.offset_left = -165.0
	_callout_panel.offset_right = 165.0
	_callout_panel.offset_top = 86.0
	_callout_panel.offset_bottom = 132.0
	_callout_panel.visible = false
	add_child(_callout_panel)
	var margin := _slash_margin(_callout_panel, 28, 8, 28, 10)
	_callout_plate = _attach_slash(_callout_panel, 12.0, Color(0.07, 0.09, 0.18, 0.90), UiPalette.YELLOW, 2.5)
	_callout_plate.accent_width = 14.0
	_callout_plate.accent_color = UiPalette.YELLOW
	_callout_label = _label("TURBO!", 22, UiPalette.YELLOW, 3, true)
	_callout_label.add_theme_font_override("font", TITLE_FONT)
	_callout_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	margin.add_child(_callout_label)


func show_callout(text: String, accent: Color = UiPalette.YELLOW) -> void:
	if _callout_panel == null or _callout_label == null:
		return
	var now: int = Time.get_ticks_msec()
	if now < _callout_cooldown_ms:
		return
	_callout_cooldown_ms = now + 450
	_callout_label.text = text.to_upper()
	_callout_label.add_theme_color_override("font_color", accent)
	if _callout_plate != null:
		_callout_plate.border_color = accent
		_callout_plate.accent_color = accent
		_callout_plate.queue_redraw()
	if _callout_tween != null and _callout_tween.is_valid():
		_callout_tween.kill()
	_callout_panel.visible = true
	_callout_panel.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_callout_panel.pivot_offset = _callout_panel.size * 0.5
	var base_scale: Vector2 = Vector2.ONE * _hud_scale_factor
	if GameSettings.reduce_motion:
		_callout_panel.scale = base_scale
		_callout_tween = create_tween()
		_callout_tween.tween_interval(1.1)
		_callout_tween.tween_callback(func() -> void: _callout_panel.visible = false)
		return
	_callout_panel.scale = base_scale * 0.72
	_callout_tween = create_tween()
	_callout_tween.tween_property(_callout_panel, "scale", base_scale * 1.08, 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_callout_tween.tween_property(_callout_panel, "scale", base_scale, 0.12)
	_callout_tween.tween_interval(0.78)
	_callout_tween.tween_property(_callout_panel, "modulate:a", 0.0, 0.28)
	_callout_tween.tween_callback(func() -> void:
		_callout_panel.visible = false
		_callout_panel.modulate.a = 1.0)


func _build_dial_canvas() -> void:
	_dial_canvas = _DialCanvas.new()
	_dial_canvas.name = "DialCanvas"
	_dial_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dial_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_speed_gauge.add_child(_dial_canvas)
	_speed_gauge.move_child(_dial_canvas, 0)
	_speed_gauge.resized.connect(func() -> void:
		if _dial_canvas != null:
			_dial_canvas.queue_redraw())


func _build_boost_header() -> void:
	_fps_label = _label("60 FPS", 14, UiPalette.CREAM, 6, true)
	_fps_label.name = "FpsLabel"
	_fps_label.visible = false
	_boost_box.add_child(_fps_label)
	_boost_box.move_child(_fps_label, 0)


func _current_scale_factor() -> float:
	var view_w: float = size.x if size.x > 1.0 else 1280.0
	var view_h: float = size.y if size.y > 1.0 else 720.0
	var available_scale: float = minf(view_w / 850.0, view_h / 480.0)
	return minf(clampf(GameSettings.hud_scale, 0.75, 1.5), maxf(available_scale, 0.5))


func _apply_display_settings() -> void:
	_hud_scale_factor = _current_scale_factor()
	if _fps_label != null:
		_fps_label.visible = GameSettings.show_fps
	if _boost_box != null:
		var box_min: Vector2 = _boost_box.get_combined_minimum_size()
		_boost_box.offset_left = 24.0
		_boost_box.offset_right = 24.0 + maxf(box_min.x, 292.0)
		_boost_box.offset_bottom = -22.0
		_boost_box.offset_top = -22.0 - box_min.y
	if _race_plaque != null:
		var p_min: Vector2 = _race_plaque.get_combined_minimum_size()
		_race_plaque.offset_left = 22.0
		_race_plaque.offset_top = 16.0
		_race_plaque.offset_right = 22.0 + maxf(p_min.x, 356.0)
		_race_plaque.offset_bottom = 16.0 + maxf(p_min.y, 128.0)
	if not _last_standings_entries.is_empty():
		_apply_standings(_last_standings_entries)
	else:
		_position_standings_panel()
	for child: Node in get_children():
		if not (child is Control):
			continue
		var control := child as Control
		if control == _speed_lines:
			control.scale = Vector2.ONE
			control.pivot_offset = Vector2.ZERO
			continue
		control.scale = Vector2.ONE * _hud_scale_factor
		control.pivot_offset = _hud_pivot(control)
	if _dial_canvas != null:
		_dial_canvas.queue_redraw()
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


func _build_race_plaque() -> void:
	_race_plaque = PanelContainer.new()
	_race_plaque.name = "RacePlaque"
	_race_plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_race_plaque.anchor_left = 0.0
	_race_plaque.anchor_top = 0.0
	_race_plaque.offset_left = 22.0
	_race_plaque.offset_top = 16.0
	_race_plaque.offset_right = 22.0 + 332.0
	_race_plaque.offset_bottom = 16.0 + 120.0
	_race_plaque.custom_minimum_size = Vector2(332.0, 118.0)
	_race_plaque.add_theme_stylebox_override("panel", _empty_style(2.0, 0.0, 4.0, 2.0))
	add_child(_race_plaque)

	var slash_bg := _PlaqueSlashBackdrop.new()
	slash_bg.name = "PlaqueSlashBackdrop"
	slash_bg.visible = false
	slash_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_race_plaque.add_child(slash_bg)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_race_plaque.add_child(column)

	# Row 1: Giant floating 1ST + skewed #ffd22e yellow LAP 1/3 parallelogram tag!
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(top)

	_plaque_pos = _label("1ST", 48, UiPalette.YELLOW, 3, true)
	_plaque_pos.add_theme_font_override("font", TITLE_FONT)
	_plaque_pos.custom_minimum_size = Vector2(118.0, 54.0)
	_plaque_pos.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(_plaque_pos)

	# Preserved hidden reference so legacy callers never null-fault; zero "OF —" clutter!
	_plaque_of = _label("", 12, UiPalette.CREAM, 0, false)
	_plaque_of.visible = false
	top.add_child(_plaque_of)

	_lap_tag_panel = PanelContainer.new()
	_lap_tag_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lap_tag_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_lap_tag_panel.custom_minimum_size = Vector2(156.0, 44.0)
	var lap_pad := _slash_margin(_lap_tag_panel, 24, 6, 26, 8)
	_lap_tag_plate = _attach_slash(_lap_tag_panel, 12.0, UiPalette.YELLOW, UiPalette.INK, 3.5)
	_plaque_lap = _label("LAP 1/3", 20, UiPalette.INK, 0, false)
	_plaque_lap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_plaque_lap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lap_pad.add_child(_plaque_lap)
	top.add_child(_lap_tag_panel)

	# Row 2: Crisp floating 28px LuckiestGuy race clock + BEST lap readout.
	var middle := HBoxContainer.new()
	middle.add_theme_constant_override("separation", 10)
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(middle)

	_plaque_time = _label("0:00.000", 28, UiPalette.CREAM, 7, true)
	_plaque_time.custom_minimum_size = Vector2(154.0, 30.0)
	_plaque_time.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	middle.add_child(_plaque_time)

	var best_slot := HBoxContainer.new()
	best_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	best_slot.alignment = BoxContainer.ALIGNMENT_END
	best_slot.add_theme_constant_override("separation", 5)
	best_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle.add_child(best_slot)

	var best_caption := _label("BEST", 13, UiPalette.CYAN, 5, true)
	best_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	best_slot.add_child(best_caption)

	_plaque_best = _label("—", 17, UiPalette.CREAM, 6, true)
	_plaque_best.custom_minimum_size = Vector2(88.0, 0.0)
	_plaque_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_plaque_best.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	best_slot.add_child(_plaque_best)

	# Row 3: Slanted parallelogram lap pips + green/pink skewed delta slash.
	var progress_row := HBoxContainer.new()
	progress_row.add_theme_constant_override("separation", 8)
	progress_row.custom_minimum_size = Vector2(0.0, 24.0)
	progress_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(progress_row)

	_lap_pips = HBoxContainer.new()
	_lap_pips.add_theme_constant_override("separation", 4)
	_lap_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lap_pips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lap_pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	progress_row.add_child(_lap_pips)

	var delta_slot := HBoxContainer.new()
	delta_slot.custom_minimum_size = Vector2(128.0, 24.0)
	delta_slot.alignment = BoxContainer.ALIGNMENT_END
	delta_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_row.add_child(delta_slot)

	_delta_badge = PanelContainer.new()
	_delta_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_delta_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var delta_pad := _slash_margin(_delta_badge, 18, 4, 20, 6)
	_delta_plate = _attach_slash(
		_delta_badge, 10.0, UiPalette.INK, UiPalette.INK, 2.8, Vector2(3.0, 3.5))
	_plaque_delta = _label("", 13, UiPalette.CREAM, 5, false)
	_plaque_delta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	delta_pad.add_child(_plaque_delta)
	_delta_badge.visible = false
	delta_slot.add_child(_delta_badge)

	_plaque_pos.visible = show_position_badge
	_lap_tag_panel.visible = show_lap_badge
	_lap_pips.visible = false
	_race_plaque.visible = false


func _build_gear_badge() -> void:
	_gear_badge = PanelContainer.new()
	_gear_badge.name = "GearBadge"
	_gear_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gear_badge.anchor_left = 0.5
	_gear_badge.anchor_top = 0.5
	_gear_badge.anchor_right = 0.5
	_gear_badge.anchor_bottom = 0.5
	_gear_badge.offset_left = -46.0
	_gear_badge.offset_top = 42.0
	_gear_badge.offset_right = 46.0
	_gear_badge.offset_bottom = 80.0
	var gear_pad := _slash_margin(_gear_badge, 18, 4, 20, 6)
	_gear_plate = _attach_slash(
		_gear_badge, 10.0, UiPalette.YELLOW, UiPalette.INK, 3.5, Vector2(3.5, 4.5))
	_gear_value = _label("GN", 18, UiPalette.INK, 0, false)
	_gear_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gear_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gear_pad.add_child(_gear_value)
	_speed_gauge.add_child(_gear_badge)
	_gear_badge.visible = false


func _build_drift_badge() -> void:
	_drift_badge = PanelContainer.new()
	_drift_badge.name = "DriftBadge"
	_drift_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drift_badge.anchor_left = 0.5
	_drift_badge.anchor_top = 0.0
	_drift_badge.anchor_right = 0.5
	_drift_badge.anchor_bottom = 0.0
	_drift_badge.offset_left = -64.0
	_drift_badge.offset_top = 10.0
	_drift_badge.offset_right = 64.0
	_drift_badge.offset_bottom = 42.0
	_drift_badge.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var drift_pad := _slash_margin(_drift_badge, 18, 4, 20, 6)
	_drift_plate = _attach_slash(
		_drift_badge, 10.0, DRIFT_TIER_COLORS[1], UiPalette.INK, 3.0, Vector2(3.0, 4.0))
	_drift_badge_label = _label("TURBO!", 14, UiPalette.INK, 0, false)
	_drift_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_drift_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	drift_pad.add_child(_drift_badge_label)
	_drift_badge.visible = false
	_speed_gauge.add_child(_drift_badge)


func _build_wrong_way_banner() -> void:
	_wrong_way_banner = PanelContainer.new()
	_wrong_way_banner.name = "WrongWayBanner"
	_wrong_way_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wrong_way_banner.anchor_left = 0.5
	_wrong_way_banner.anchor_top = 0.0
	_wrong_way_banner.anchor_right = 0.5
	_wrong_way_banner.anchor_bottom = 0.0
	_wrong_way_banner.offset_left = -168.0
	_wrong_way_banner.offset_top = 56.0
	_wrong_way_banner.offset_right = 168.0
	_wrong_way_banner.offset_bottom = 112.0
	_wrong_way_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var ww_pad := _slash_margin(_wrong_way_banner, 36, 8, 30, 12)
	_wrong_way_plate = _attach_slash(
		_wrong_way_banner, 14.0, Color("ff3b3f"), UiPalette.INK, 3.8, Vector2(4.0, 5.0))
	_wrong_way_plate.accent_color = UiPalette.YELLOW
	_wrong_way_plate.accent_width = 18.0
	_wrong_way_label = _label("WRONG WAY!", 26, UiPalette.YELLOW, 8, true)
	_wrong_way_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wrong_way_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ww_pad.add_child(_wrong_way_label)
	_wrong_way_banner.visible = false
	add_child(_wrong_way_banner)


func set_wrong_way(active: bool) -> void:
	## Upper-center comic wrong-way slash. Hidden by default; hazard-flashes when active.
	if _wrong_way_active == active and _wrong_way_banner != null \
			and _wrong_way_banner.visible == active:
		return
	_wrong_way_active = active
	if _wrong_way_banner == null:
		return
	_wrong_way_banner.visible = active
	_wrong_way_banner.modulate = Color.WHITE
	if _wrong_way_plate != null:
		_wrong_way_plate.fill_color = Color("ff3b3f")
		_wrong_way_plate.accent_color = UiPalette.YELLOW
		_wrong_way_plate.queue_redraw()
	_wrong_way_banner.pivot_offset = _hud_pivot(_wrong_way_banner)


func _lap_pips_for(total: int) -> void:
	_lap_pip_total = total
	_lap_pip_index = -1
	for child: Node in _lap_pips.get_children():
		_lap_pips.remove_child(child)
		child.queue_free()
	for _i in total:
		var pip := _LapPipSlash.new()
		pip.custom_minimum_size = Vector2(20.0, 11.0)
		pip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_lap_pips.add_child(pip)
	if _lap_pips != null:
		_lap_pips.visible = total > 0 and show_lap_badge


func _update_lap_pips(current: int) -> void:
	if _lap_pip_total <= 0 or _lap_pips == null:
		return
	if show_lap_badge:
		_lap_pips.visible = true
	var index: int = clampi(current - 1, 0, _lap_pip_total - 1)
	if index == _lap_pip_index:
		return
	_lap_pip_index = index
	var children: Array[Node] = _lap_pips.get_children()
	for i in children.size():
		var pip := children[i] as _LapPipSlash
		if pip == null:
			continue
		if i < index:
			pip.state = 2
		elif i == index:
			pip.state = 1
		else:
			pip.state = 0
		pip.queue_redraw()


func _build_net_block() -> void:
	_net_panel = PanelContainer.new()
	_net_panel.name = "NetBlock"
	_net_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_net_panel.anchor_left = 1.0
	_net_panel.anchor_right = 1.0
	_net_panel.offset_left = -328.0
	_net_panel.offset_right = -24.0
	_net_panel.offset_top = NET_TOP
	_net_panel.offset_bottom = NET_TOP + NET_HEIGHT
	var net_pad := _slash_margin(_net_panel, 20, 4, 22, 6)
	_net_plate = _attach_slash(
		_net_panel, 10.0, UiPalette.INK, UiPalette.CYAN, 2.8, Vector2(3.0, 4.0))
	_net_label = _label("SERVER —", 13, UiPalette.CREAM, 5, false)
	_net_label.name = "NetStats"
	_net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_net_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_net_label.clip_text = true
	_net_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_net_panel)
	net_pad.add_child(_net_label)


func _build_standings() -> void:
	_standings_panel = PanelContainer.new()
	_standings_panel.name = "LiveStandings"
	_standings_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_standings_panel.anchor_left = 1.0
	_standings_panel.anchor_right = 1.0
	_standings_panel.offset_left = -328.0
	_standings_panel.offset_right = -24.0
	_standings_panel.offset_top = STANDINGS_SOLO_TOP
	_standings_panel.offset_bottom = STANDINGS_SOLO_TOP
	_standings_panel.custom_minimum_size = Vector2(304.0, 0.0)
	# StyleBoxEmpty: ZERO dark outer box around LiveStandings!
	_standings_panel.add_theme_stylebox_override("panel", _empty_style())
	add_child(_standings_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_standings_panel.add_child(column)

	# Redundant header hidden per Slop-Slash design; preserved for script safety.
	_standings_title = _label("STANDINGS", 12, UiPalette.CREAM, 5, false)
	_standings_title.visible = false
	column.add_child(_standings_title)

	_standings_rows = VBoxContainer.new()
	_standings_rows.add_theme_constant_override("separation", 4)
	_standings_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_standings_rows)
	_standings_panel.visible = false


func _standings_top_y(scale_factor: float) -> float:
	if _net_panel != null and _net_panel.visible:
		var net_h: float = maxf(_net_panel.size.y, NET_HEIGHT)
		return maxf(STANDINGS_NET_TOP, NET_TOP + net_h * scale_factor + 6.0)
	return STANDINGS_SOLO_TOP


func _position_standings_panel() -> void:
	if _standings_panel == null:
		return
	var top_y: float = _standings_top_y(_hud_scale_factor)
	_standings_panel.offset_left = -328.0
	_standings_panel.offset_right = -24.0
	_standings_panel.offset_top = top_y
	var min_sz: Vector2 = _standings_panel.get_combined_minimum_size()
	_standings_panel.offset_bottom = top_y + min_sz.y
	_standings_panel.size = Vector2(304.0, min_sz.y)
	_standings_panel.scale = Vector2.ONE * _hud_scale_factor
	_standings_panel.pivot_offset = _hud_pivot(_standings_panel)


func set_standings(entries: Array[Dictionary]) -> void:
	## Live race order. Called at ~4 Hz by the race, never per frame.
	_explicit_standings_ms = Time.get_ticks_msec()
	_apply_standings(entries)


func _select_standings_slots(entries: Array[Dictionary], max_slots: int) -> Array[int]:
	## Maps each visible row slot to an entry index in `entries`, or `-1` for
	## a compact `"···"` ellipsis row when a large field is scaled up.
	var total: int = mini(entries.size(), STANDINGS_MAX_ROWS)
	var slots: Array[int] = []
	if total <= max_slots:
		for i in total:
			slots.append(i)
		return slots
	var local_idx: int = -1
	for i in total:
		if bool(entries[i].get("local", false)):
			local_idx = i
			break
	if local_idx < 0 or local_idx < max_slots - 1:
		for i in max_slots - 1:
			slots.append(i)
		slots.append(-1)
		return slots
	var top_count: int = 2 if max_slots >= 5 else 1
	for i in top_count:
		slots.append(i)
	slots.append(-1)
	var rem: int = maxi(max_slots - top_count - 1, 1)
	var win_start: int = clampi(local_idx - rem / 2, top_count + 1, total - rem)
	for i in rem:
		slots.append(win_start + i)
	return slots


func _apply_standings(entries: Array[Dictionary]) -> void:
	if _standings_rows == null:
		return
	_last_standings_entries = entries
	_standings_panel.visible = entries.size() > 1
	if entries.is_empty():
		return
	var scale_factor: float = _current_scale_factor()
	_hud_scale_factor = scale_factor
	var view_h: float = size.y if size.y > 1.0 else 720.0
	var gauge_h: float = _speed_gauge.size.y if _speed_gauge != null and _speed_gauge.size.y > 1.0 else 216.0
	var gauge_top_y: float = view_h - 24.0 - gauge_h * scale_factor
	var top_y: float = _standings_top_y(scale_factor)
	var max_unscaled_h: float = maxf((gauge_top_y - 20.0 - top_y) / maxf(scale_factor, 0.5), 88.0)

	var compact: bool = entries.size() > 8 or scale_factor > 1.12 or view_h < 600.0
	var row_h: float = STANDINGS_COMPACT_ROW_HEIGHT if compact else STANDINGS_ROW_HEIGHT
	var row_font: int = 12 if compact else 14
	var gap_font: int = 10 if compact else 11
	var sep: int = 3
	var avail_rows_h: float = maxf(max_unscaled_h - 12.0, row_h)
	var max_slots: int = clampi(
		int(floor((avail_rows_h + float(sep)) / (row_h + float(sep)))),
		3, STANDINGS_MAX_ROWS)

	var slot_map: Array[int] = _select_standings_slots(entries, max_slots)
	var visible_count: int = slot_map.size()

	while _standings_row_cache.size() < visible_count:
		var row := PanelContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.custom_minimum_size = Vector2(0.0, row_h)
		var row_pad := _slash_margin(row, 18, 2, 22, 3)

		var plate := _attach_slash(
			row, 10.0, Color(0.118, 0.106, 0.227, 0.88), UiPalette.INK, 2.5, Vector2(3.0, 3.5))
		plate.draw_sheen = false

		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row_pad.add_child(line)

		var place_label := _label("", row_font, UiPalette.CREAM, 5, false)
		place_label.custom_minimum_size.x = 24.0
		place_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		place_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(place_label)

		var name_label := _label("", row_font, UiPalette.CREAM, 5, false)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.clip_text = true
		line.add_child(name_label)

		var gap_label := _label("", gap_font, UiPalette.CYAN, 4, false)
		gap_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(gap_label)

		_standings_rows.add_child(row)
		_standings_row_cache.append({
			"row": row,
			"plate": plate,
			"place": place_label,
			"name": name_label,
			"gap": gap_label,
		})

	var leader: float = float(entries[0].get("progress", 0.0))
	var leader_time: float = float(entries[0].get("time", -1.0))
	var hidden_count: int = maxi(entries.size() - (visible_count - 1), 1)
	for slot in _standings_row_cache.size():
		var cached: Dictionary = _standings_row_cache[slot]
		var row_ctrl := cached["row"] as Control
		row_ctrl.visible = slot < visible_count
		if slot >= visible_count:
			continue
		row_ctrl.custom_minimum_size.y = row_h
		var plate := cached["plate"] as _SlashPlate
		var place_lbl := cached["place"] as Label
		var name_lbl := cached["name"] as Label
		var gap_lbl := cached["gap"] as Label
		place_lbl.add_theme_font_size_override("font_size", row_font)
		name_lbl.add_theme_font_size_override("font_size", row_font)
		gap_lbl.add_theme_font_size_override("font_size", gap_font)

		var entry_idx: int = slot_map[slot]
		if entry_idx < 0:
			plate.fill_color = Color(0.118, 0.106, 0.227, 0.72)
			plate.border_color = UiPalette.INK
			plate.accent_width = 0.0
			plate.draw_sheen = false
			plate.queue_redraw()
			place_lbl.text = "··"
			place_lbl.add_theme_constant_override("outline_size", 4)
			place_lbl.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
			name_lbl.text = "···"
			name_lbl.add_theme_constant_override("outline_size", 4)
			name_lbl.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
			gap_lbl.text = "+%d" % hidden_count if slot == visible_count - 1 else ""
			gap_lbl.add_theme_constant_override("outline_size", 4)
			gap_lbl.add_theme_color_override("font_color", UiPalette.CYAN)
			continue

		var entry: Dictionary = entries[entry_idx]
		var local: bool = bool(entry.get("local", false))
		var place: int = int(entry.get("place", 0))
		var shown_place: int = place if place > 0 else entry_idx + 1
		var rival_col: Color = entry.get("color", UiPalette.CYAN) as Color

		var chip_col: Color = rival_col.lightened(0.10)
		if shown_place == 1:
			chip_col = UiPalette.YELLOW
		elif shown_place == 2:
			chip_col = Color("eef6ff")
		elif shown_place == 3:
			chip_col = Color("ff9f43")

		place_lbl.text = str(shown_place)
		var display_name: String = str(entry.get("name", "PLAYER"))
		name_lbl.text = display_name if not local or display_name.to_upper() == "YOU" \
			else display_name + " · YOU"

		var gap_text: String = "LEAD"
		if entry_idx > 0:
			var entry_time: float = float(entry.get("time", -1.0))
			if entry_time > 0.0 and leader_time > 0.0:
				gap_text = "+%.2fs" % maxf(entry_time - leader_time, 0.0)
			else:
				gap_text = "+%dm" % int(maxf(leader - float(entry.get("progress", 0.0)), 0.0))
		gap_lbl.text = gap_text

		if local:
			# Local player: bold #ffd22e gold parallelogram slash + #1e1b3a ink text!
			plate.fill_color = UiPalette.YELLOW
			plate.border_color = UiPalette.INK
			plate.border_width = 3.0
			plate.accent_color = UiPalette.PINK
			plate.accent_width = 8.0
			plate.draw_sheen = false
			plate.queue_redraw()
			place_lbl.add_theme_constant_override("outline_size", 0)
			place_lbl.add_theme_color_override("font_color", UiPalette.INK)
			name_lbl.add_theme_constant_override("outline_size", 0)
			name_lbl.add_theme_color_override("font_color", UiPalette.INK)
			gap_lbl.add_theme_constant_override("outline_size", 0)
			gap_lbl.add_theme_color_override("font_color", UiPalette.INK)
		else:
			# Rival: compact #1e1b3a ink slash (alpha 0.86) + coloured left rank chip!
			plate.fill_color = Color(0.118, 0.106, 0.227, 0.86)
			plate.border_color = UiPalette.INK
			plate.border_width = 2.5
			plate.accent_color = chip_col
			plate.accent_width = 32.0
			plate.draw_sheen = false
			plate.queue_redraw()
			place_lbl.add_theme_constant_override("outline_size", 5)
			place_lbl.add_theme_color_override("font_color", UiPalette.CREAM)
			name_lbl.add_theme_constant_override("outline_size", 5)
			name_lbl.add_theme_color_override("font_color", UiPalette.CREAM)
			gap_lbl.add_theme_constant_override("outline_size", 4)
			gap_lbl.add_theme_color_override("font_color",
				UiPalette.YELLOW if shown_place == 1 else UiPalette.CYAN)

	_position_standings_panel()


func set_race_position(place: int, field_size: int = 0) -> void:
	_explicit_position_ms = Time.get_ticks_msec()
	_show_position(place, field_size)


func _show_position(place: int, _field_size: int = 0) -> void:
	if _race_plaque == null:
		return
	place = maxi(place, 1)
	if _plaque_pos != null:
		_plaque_pos.visible = show_position_badge
	_race_plaque.visible = show_position_badge or show_lap_badge
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
	var pos_color: Color = UiPalette.CREAM
	if place == 1:
		pos_color = UiPalette.YELLOW
	elif place == 2:
		pos_color = Color("eef6ff")
	elif place == 3:
		pos_color = Color("ff9f43")
	_plaque_pos.add_theme_color_override("font_color", pos_color)
	if _last_place > 0 and place != _last_place and not GameSettings.reduce_motion:
		if _position_tween != null and _position_tween.is_valid():
			_position_tween.kill()
		_plaque_pos.pivot_offset = _plaque_pos.size * 0.5
		_plaque_pos.scale = Vector2.ONE * (1.24 if place < _last_place else 0.90)
		_plaque_pos.modulate = UiPalette.CYAN if place < _last_place else UiPalette.PINK
		_position_tween = create_tween().set_parallel(true)
		_position_tween.tween_property(_plaque_pos, "modulate", Color.WHITE, 0.42)
		_position_tween.tween_property(_plaque_pos, "scale", Vector2.ONE, 0.30) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if place < _last_place and show_position_badge:
			show_callout("OVERTAKE!  %s" % _plaque_pos.text, UiPalette.YELLOW if place == 1 else UiPalette.CYAN)
	_last_place = place


func set_lap(current: int, total: int) -> void:
	if _race_plaque == null:
		return
	_race_plaque.visible = show_position_badge or show_lap_badge
	var safe_total: int = maxi(total, 1)
	var safe_current: int = clampi(current, 1, safe_total)
	if safe_current != _last_lap_seen:
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
	if _lap_tag_panel != null:
		_lap_tag_panel.visible = show_lap_badge
	if safe_total != _lap_pip_total:
		_lap_pips_for(safe_total)
	_update_lap_pips(safe_current)
	if _lap_pips != null:
		_lap_pips.visible = show_lap_badge and safe_total > 0
	_refresh_lap_readout()


func set_best_lap(best_seconds: float) -> void:
	## Explicit best-lap setter preserved for race controllers.
	if _plaque_best == null:
		return
	if best_seconds >= 0.0 and is_finite(best_seconds):
		_hud_best_lap = best_seconds
		var best_text: String = _format_race_time(best_seconds)
		if _plaque_best.text != best_text:
			_plaque_best.text = best_text
	else:
		_hud_best_lap = -1.0
		_plaque_best.text = "—"
	_refresh_lap_readout()


func set_last_lap(last_seconds: float, delta_seconds: float = NAN) -> void:
	## Explicit completed-lap setter; displays lap delta in the skewed slash slot.
	if not is_finite(last_seconds) or last_seconds < 0.0:
		return
	if is_finite(delta_seconds):
		_last_lap_delta = delta_seconds
		_last_lap_delta_ms = Time.get_ticks_msec()
	elif _hud_best_lap > 0.0:
		_last_lap_delta = last_seconds - _hud_best_lap
		_last_lap_delta_ms = Time.get_ticks_msec()
	if _hud_best_lap < 0.0 or last_seconds < _hud_best_lap:
		_hud_best_lap = last_seconds
		if _plaque_best != null:
			_plaque_best.text = _format_race_time(last_seconds)
	_external_lap_readout = false
	_refresh_lap_readout()


func set_race_time(total_seconds: float, best_seconds: float = -1.0) -> void:
	if _plaque_time == null or not is_finite(total_seconds):
		return
	if total_seconds + 1.0 < _race_clock:
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
	if best_seconds > 0.0 and is_finite(best_seconds):
		_hud_best_lap = best_seconds
	_refresh_lap_readout()


func _refresh_lap_readout() -> void:
	if _plaque_delta == null or _delta_badge == null or _external_lap_readout:
		return
	if _last_lap_seen <= 0:
		_delta_badge.visible = false
		return
	if _last_lap_delta_ms > 0 and Time.get_ticks_msec() - _last_lap_delta_ms < 6000:
		var delta: float = _last_lap_delta
		var text: String = ""
		if delta > 0.004:
			text = "+%.2fs" % delta
			_plaque_delta.add_theme_constant_override("outline_size", 5)
			_plaque_delta.add_theme_color_override("font_color", UiPalette.CREAM)
			if _delta_plate != null:
				_delta_plate.fill_color = UiPalette.PINK
				_delta_plate.queue_redraw()
		else:
			text = "-%.2fs" % absf(delta)
			_plaque_delta.add_theme_constant_override("outline_size", 0)
			_plaque_delta.add_theme_color_override("font_color", UiPalette.INK)
			if _delta_plate != null:
				_delta_plate.fill_color = UiPalette.GRASS
				_delta_plate.queue_redraw()
		if _plaque_delta.text != text:
			_plaque_delta.text = text
		_delta_badge.visible = true
		return
	var current: float = maxf(_race_clock - _lap_start_time, 0.0)
	if current >= 1.0:
		var lap_str: String = "LAP %s" % _format_short_lap(current)
		_plaque_delta.add_theme_constant_override("outline_size", 5)
		_plaque_delta.add_theme_color_override("font_color", UiPalette.CYAN)
		if _delta_plate != null:
			_delta_plate.fill_color = UiPalette.INK
			_delta_plate.queue_redraw()
		if _plaque_delta.text != lap_str:
			_plaque_delta.text = lap_str
		_delta_badge.visible = true
	else:
		_delta_badge.visible = false


func _format_short_lap(seconds: float) -> String:
	if not is_finite(seconds):
		return "—"
	var tenths: int = roundi(maxf(seconds, 0.0) * 10.0)
	return "%d:%02d.%d" % [tenths / 600, (tenths / 10) % 60, tenths % 10]


func set_lap_time(lap_seconds: float, best_lap_seconds: float = -1.0) -> void:
	if _plaque_delta == null or _delta_badge == null:
		return
	_external_lap_readout = true
	if lap_seconds < 0.0:
		_delta_badge.visible = false
		return
	var delta_text: String = "LAP %s" % _format_short_lap(lap_seconds)
	if best_lap_seconds > 0.0:
		_hud_best_lap = best_lap_seconds
	_plaque_delta.add_theme_constant_override("outline_size", 5)
	_plaque_delta.add_theme_color_override("font_color", UiPalette.CYAN)
	if _delta_plate != null:
		_delta_plate.fill_color = UiPalette.INK
		_delta_plate.queue_redraw()
	if _plaque_delta.text != delta_text:
		_plaque_delta.text = delta_text
	_delta_badge.visible = true


func _format_race_time(seconds: float) -> String:
	if not is_finite(seconds):
		return "—"
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
	if _wrong_way_active and _wrong_way_banner != null and _wrong_way_banner.visible:
		if GameSettings.reduce_motion:
			if _wrong_way_plate != null:
				_wrong_way_plate.fill_color = Color("ff3b3f")
				_wrong_way_plate.accent_color = UiPalette.YELLOW
				_wrong_way_plate.queue_redraw()
			_wrong_way_label.add_theme_color_override("font_color", UiPalette.YELLOW)
		else:
			var flash_on: bool = sin(float(Time.get_ticks_msec()) * 0.016) > 0.0
			if _wrong_way_plate != null:
				_wrong_way_plate.fill_color = Color("ff3b3f") if flash_on else UiPalette.YELLOW
				_wrong_way_plate.accent_color = UiPalette.YELLOW if flash_on else Color("ff3b3f")
				_wrong_way_plate.queue_redraw()
			_wrong_way_label.add_theme_color_override("font_color",
				UiPalette.YELLOW if flash_on else UiPalette.CREAM)
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
	if not is_finite(speed_kmh):
		speed_kmh = 0.0
	var speed_text: String = str(int(round(speed_kmh)))
	if speed_text != _last_speed_text:
		_last_speed_text = speed_text
		_speed_value.text = speed_text
	_speed_value.add_theme_color_override("font_color",
		UiPalette.YELLOW if cart.boost_active else UiPalette.CREAM)

	_dial_max_kmh = ceilf((cart.max_speed * cart.boost_speed_multiplier * 3.6 + 6.0) / 20.0) * 20.0
	var target_ratio: float = clampf(speed_kmh / maxf(_dial_max_kmh, 20.0), 0.0, 1.0)
	var next_ratio: float = lerpf(_dial_ratio, target_ratio, 1.0 - exp(-delta * 15.0))
	var next_boost: float = move_toward(_dial_boost, 1.0 if cart.boost_active else 0.0, delta * 5.0)
	if absf(next_ratio - target_ratio) < 0.0015:
		next_ratio = target_ratio

	var raw_drift_ratio: float = 0.0
	if cart.has_method("get_drift_charge_ratio"):
		raw_drift_ratio = clampf(float(cart.call("get_drift_charge_ratio")), 0.0, 1.0)
	var raw_drift_tier: int = 0
	if cart.has_method("get_drift_tier"):
		raw_drift_tier = clampi(int(cart.call("get_drift_tier")), 0, 3)
	var next_drift: float = lerpf(_drift_arc_ratio, raw_drift_ratio, 1.0 - exp(-delta * 18.0))
	if absf(next_drift - raw_drift_ratio) < 0.002:
		next_drift = raw_drift_ratio
	var drifting_now: bool = cart.is_drifting or raw_drift_ratio > 0.005 or raw_drift_tier > 0
	var dial_dirty: bool = not is_equal_approx(next_ratio, _dial_ratio) \
		or not is_equal_approx(next_boost, _dial_boost) \
		or not is_equal_approx(next_drift, _drift_arc_ratio) \
		or raw_drift_tier != _drift_tier \
		or drifting_now != _drift_active
	_dial_ratio = next_ratio
	_dial_boost = next_boost
	_drift_arc_ratio = next_drift
	_drift_active = drifting_now
	if raw_drift_tier != _drift_tier:
		if raw_drift_tier == 0 and _prev_drift_tier_for_callout > 0 and cart.boost_active:
			match _prev_drift_tier_for_callout:
				3:
					show_callout("ULTRA DRIFT!", Color("ff3ec9"))
				2:
					show_callout("BLAZE DRIFT!", UiPalette.ORANGE)
				1:
					show_callout("TURBO DRIFT!", UiPalette.CYAN)
		_prev_drift_tier_for_callout = raw_drift_tier
		_drift_tier = raw_drift_tier
		_update_drift_badge()

	# Airtime stunt detection for satisfying landing callouts!
	var airborne_now: bool = not cart.is_on_floor() and cart.global_position.y > 0.35
	if airborne_now:
		_air_seconds += delta
		_was_airborne = true
	else:
		if _was_airborne and _air_seconds >= 0.65 and cart.current_state == CartPlayer.CartState.DRIVING:
			if _air_seconds >= 1.75:
				show_callout("MEGA AIR!  %.1fs" % _air_seconds, UiPalette.PINK)
			elif _air_seconds >= 1.15:
				show_callout("BIG AIR!  %.1fs" % _air_seconds, UiPalette.YELLOW)
			else:
				show_callout("AIRTIME!  %.1fs" % _air_seconds, UiPalette.CYAN)
		_air_seconds = 0.0
		_was_airborne = false

	# Dynamic anime speed lines at high speed / boost (respects reduce_motion).
	if _speed_lines != null:
		var reduce: bool = GameSettings.reduce_motion
		var speed_factor: float = clampf((target_ratio - 0.68) / 0.32, 0.0, 1.0)
		var line_target: float = 0.0 if reduce else maxf(speed_factor * 0.72, 0.95 if cart.boost_active else 0.0)
		_speed_lines.intensity = lerpf(_speed_lines.intensity, line_target, 1.0 - exp(-delta * 10.0))
		_speed_lines.boost_mix = lerpf(_speed_lines.boost_mix, 1.0 if cart.boost_active else 0.0, 1.0 - exp(-delta * 10.0))
		_speed_lines.phase += delta
		var show_lines: bool = not reduce and _speed_lines.intensity >= 0.03
		_speed_lines.visible = show_lines
		if show_lines:
			_speed_lines.queue_redraw()

	_update_gear(cart, speed_kmh)

	var boost_ratio: float = clampf(cart.boost_amount / maxf(cart.max_boost, 0.1), 0.0, 1.0)
	_boost_meter.ratio = boost_ratio
	_boost_meter.boosting = cart.boost_active
	var boost_caption: String = "BOOST"
	var boost_col: Color = UiPalette.CREAM
	if _drift_tier == 3:
		boost_caption = "ULTRA!"
		boost_col = Color("ff3ec9")
	elif _drift_tier == 2:
		boost_caption = "BLAZE!"
		boost_col = UiPalette.ORANGE
	elif _drift_tier == 1 or cart.boost_active:
		boost_caption = "TURBO!"
		boost_col = UiPalette.YELLOW
	elif boost_ratio < 0.16:
		boost_caption = "LOW BOOST!"
		boost_col = UiPalette.PINK
	if boost_caption != _last_boost_caption or boost_col != _last_boost_color:
		_last_boost_caption = boost_caption
		_last_boost_color = boost_col
		_boost_caption.text = boost_caption
		_boost_caption.add_theme_color_override("font_color", boost_col)

	var glow_target: float = 1.0 if cart.boost_active else 0.0
	_boost_glow = move_toward(_boost_glow, glow_target, delta * 7.0)
	if _boost_glow > 0.001 or _boost_glow_was_visible or (_drift_tier > 0 and not GameSettings.reduce_motion):
		_boost_glow_was_visible = _boost_glow > 0.001
		dial_dirty = true
	if dial_dirty and _dial_canvas != null:
		_dial_canvas.queue_redraw()

	_state_pill.visible = cart.current_state != CartPlayer.CartState.DRIVING
	var state_text: String = _state_text(cart)
	if state_text != _last_state_text:
		_last_state_text = state_text
		_state_label.text = state_text
	var state_color: Color = _state_color(cart)
	if state_color != _last_state_color:
		_last_state_color = state_color
		_state_label.add_theme_color_override("font_color", state_color)
		if _state_plate != null:
			_state_plate.accent_color = state_color
			_state_plate.accent_width = 14.0
			_state_plate.queue_redraw()

	if _hint_timer > 0.0:
		_hint_timer -= delta
		if _hint_timer <= 0.0:
			_hint_label.visible = false

	if _debug_visible and not _scoreboard_visible:
		_update_debug(cart)


func _update_drift_badge() -> void:
	if _drift_badge == null:
		return
	if _drift_tier <= 0 or _drift_tier >= DRIFT_TIER_NAMES.size():
		_drift_badge.visible = false
		return
	var tier_color: Color = DRIFT_TIER_COLORS[_drift_tier]
	if _drift_plate != null:
		_drift_plate.fill_color = tier_color
		_drift_plate.queue_redraw()
	_drift_badge_label.text = DRIFT_TIER_NAMES[_drift_tier]
	_drift_badge_label.add_theme_constant_override("outline_size", 5 if _drift_tier == 3 else 0)
	_drift_badge_label.add_theme_color_override("font_color",
		UiPalette.CREAM if _drift_tier == 3 else UiPalette.INK)
	_drift_badge.visible = true
	if not GameSettings.reduce_motion:
		_drift_badge.pivot_offset = _drift_badge.size * 0.5
		_drift_badge.scale = Vector2.ONE * 1.18
		var tween: Tween = _drift_badge.create_tween()
		tween.tween_property(_drift_badge, "scale", Vector2.ONE, 0.16) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _draw_gauge_canvas(canvas: Control) -> void:
	var area: Vector2 = canvas.size
	var half: float = minf(area.x, area.y) * 0.5
	if half < 30.0:
		return
	var center: Vector2 = area * 0.5
	var max_r: float = half - 14.0

	# 1. Outer 3-segment slanted drift-charge spark arc when drifting!
	if _drift_active or _drift_arc_ratio > 0.004 or _drift_tier > 0:
		var drift_r_in: float = max_r + 1.5
		var drift_r_out: float = max_r + 8.5
		var seg_gap: float = 0.055
		var third: float = DIAL_SWEEP / 3.0
		var fill_ratio: float = clampf(_drift_arc_ratio, 0.0, 1.0)
		if _drift_tier > 0 and fill_ratio < float(_drift_tier) / 3.0:
			fill_ratio = float(_drift_tier) / 3.0
		var tier_col: Color = DRIFT_TIER_COLORS[clampi(_drift_tier, 0, 3)]
		for seg in 3:
			var a0: float = DIAL_START + third * float(seg) + (seg_gap * 0.5 if seg > 0 else 0.0)
			var a1: float = DIAL_START + third * float(seg + 1) - (seg_gap * 0.5 if seg < 2 else 0.0)
			var seg_pts: PackedVector2Array = _arc_blade_poly(
				center, drift_r_in, drift_r_out, a0, a1, 0.035, 10)
			var sh_pts := PackedVector2Array()
			for pt: Vector2 in seg_pts:
				sh_pts.append(pt + Vector2(3.0, 3.5))
			canvas.draw_colored_polygon(sh_pts, PLATE_SHADOW_COLOR)
			canvas.draw_colored_polygon(seg_pts, Color(0.118, 0.106, 0.227, 0.88))

			var seg_start_frac: float = float(seg) / 3.0
			var seg_fill: float = clampf((fill_ratio - seg_start_frac) * 3.0, 0.0, 1.0)
			if seg_fill > 0.01:
				var lit_a1: float = lerpf(a0, a1, seg_fill)
				var lit_pts: PackedVector2Array = _arc_blade_poly(
					center, drift_r_in, drift_r_out, a0, lit_a1, 0.035, maxi(4, int(10.0 * seg_fill)))
				canvas.draw_colored_polygon(lit_pts, tier_col)

			var closed_seg := seg_pts.duplicate()
			closed_seg.append(seg_pts[0])
			canvas.draw_polyline(closed_seg, UiPalette.INK, 2.2, true)

		if fill_ratio > 0.01:
			var spark_ang: float = DIAL_START + DIAL_SWEEP * fill_ratio + 0.02
			var spark_pos: Vector2 = center + Vector2(cos(spark_ang), sin(spark_ang)) * ((drift_r_in + drift_r_out) * 0.5)
			var spark_diamond := PackedVector2Array([
				spark_pos + Vector2(0.0, -5.5),
				spark_pos + Vector2(5.5, 0.0),
				spark_pos + Vector2(0.0, 5.5),
				spark_pos + Vector2(-5.5, 0.0),
			])
			canvas.draw_colored_polygon(spark_diamond, UiPalette.CREAM)
			var spark_closed := spark_diamond.duplicate()
			spark_closed.append(spark_diamond[0])
			canvas.draw_polyline(spark_closed, UiPalette.INK, 2.0, true)

	# 2. Rebellious 14-cell radial slanted parallelogram tachometer arc (NO dark circle!).
	var r_inner: float = max_r * 0.72
	var cell_step: float = DIAL_SWEEP / float(TACH_CELLS)
	var cell_span: float = cell_step * 0.74
	var skew_ang: float = 0.055
	var lit_cells: float = _dial_ratio * float(TACH_CELLS)
	var lead_cell: int = clampi(int(ceilf(lit_cells)) - 1, -1, TACH_CELLS - 1)
	var wave: float = fposmod(float(Time.get_ticks_msec()) * 0.015, float(TACH_CELLS) + 2.0) - 1.0

	# Pass A: hard comic shadows for all 14 radial cells.
	for i in TACH_CELLS:
		var frac: float = float(i) / float(TACH_CELLS - 1)
		var r_outer: float = max_r * lerpf(0.88, 0.99, frac)
		var a0: float = DIAL_START + cell_step * float(i)
		var a1: float = a0 + cell_span
		var pts: PackedVector2Array = _radial_cell_poly(center, r_inner, r_outer, a0, a1, skew_ang)
		var sh := PackedVector2Array([
			pts[0] + Vector2(3.5, 4.5),
			pts[1] + Vector2(3.5, 4.5),
			pts[2] + Vector2(3.5, 4.5),
			pts[3] + Vector2(3.5, 4.5),
		])
		canvas.draw_colored_polygon(sh, PLATE_SHADOW_COLOR)

	# Pass B: ink cell bodies, Cyan -> Gold -> Hot Pink active fills, sheen & ink borders.
	for i in TACH_CELLS:
		var frac: float = float(i) / float(TACH_CELLS - 1)
		var r_outer: float = max_r * lerpf(0.88, 0.99, frac)
		var a0: float = DIAL_START + cell_step * float(i)
		var a1: float = a0 + cell_span
		var pts: PackedVector2Array = _radial_cell_poly(center, r_inner, r_outer, a0, a1, skew_ang)
		canvas.draw_colored_polygon(pts, Color(0.118, 0.106, 0.227, 0.90))

		var amount: float = clampf(lit_cells - float(i), 0.0, 1.0)
		if amount > 0.01:
			var active_col: Color = _tach_cell_color(frac, i, wave)
			var lit_a1: float = lerpf(a0, a1, amount)
			var lit_pts: PackedVector2Array = _radial_cell_poly(
				center, r_inner, r_outer, a0, lit_a1, skew_ang)
			canvas.draw_colored_polygon(lit_pts, active_col)

			# Outer comic white sheen strip on each lit radial cell.
			var sheen_r_in: float = lerpf(r_inner, r_outer, 0.68)
			var sheen_pts: PackedVector2Array = _radial_cell_poly(
				center, sheen_r_in, r_outer - 1.2, a0 + 0.004, lit_a1 - 0.004, skew_ang)
			canvas.draw_colored_polygon(sheen_pts, Color(1.0, 1.0, 1.0, 0.34))

		var border_col: Color = UiPalette.CREAM if (i == lead_cell and amount > 0.2) else UiPalette.INK
		var closed := pts.duplicate()
		closed.append(pts[0])
		canvas.draw_polyline(closed, border_col, 2.8, true)


func _tach_cell_color(frac: float, index: int, wave: float) -> Color:
	var base: Color
	if frac < 0.45:
		base = UiPalette.CYAN.lerp(Color("66f7ff"), frac / 0.45)
	elif frac < 0.76:
		base = UiPalette.YELLOW.lerp(UiPalette.ORANGE, (frac - 0.45) / 0.31)
	else:
		base = UiPalette.PINK.lerp(Color("ff3ec9"), (frac - 0.76) / 0.24)
	if _dial_boost > 0.15:
		var overdrive: Color = UiPalette.YELLOW.lerp(Color("ff3ec9"), frac)
		if not GameSettings.reduce_motion:
			var surge: float = maxf(0.0, 1.0 - absf(float(index) - wave) * 0.65)
			overdrive = overdrive.lerp(Color.WHITE, surge * 0.42)
		base = base.lerp(overdrive, _dial_boost)
	return base


func _radial_cell_poly(center: Vector2, r_in: float, r_out: float,
		a0: float, a1: float, skew_ang: float) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(cos(a0), sin(a0)) * r_in,
		center + Vector2(cos(a0 + skew_ang), sin(a0 + skew_ang)) * r_out,
		center + Vector2(cos(a1 + skew_ang), sin(a1 + skew_ang)) * r_out,
		center + Vector2(cos(a1), sin(a1)) * r_in,
	])


func _arc_blade_poly(center: Vector2, r_in: float, r_out: float,
		a0: float, a1: float, skew_ang: float, steps: int) -> PackedVector2Array:
	var poly := PackedVector2Array()
	var n: int = maxi(steps, 2)
	for s in range(n + 1):
		var t: float = float(s) / float(n)
		var ang: float = lerpf(a0, a1, t) + skew_ang
		poly.append(center + Vector2(cos(ang), sin(ang)) * r_out)
	for s in range(n, -1, -1):
		var t: float = float(s) / float(n)
		var ang: float = lerpf(a0, a1, t)
		poly.append(center + Vector2(cos(ang), sin(ang)) * r_in)
	return poly


func _update_net_stats() -> void:
	if not is_instance_valid(_net_label):
		return
	var ms: int = _server_ping_ms()
	var ping_text: String
	if Network.is_host and Network.is_lan():
		ping_text = "LAN HOST"
	elif ms > 0:
		ping_text = "SERVER %d MS" % ms
		if Network.is_host:
			ping_text += " · HOST"
	else:
		ping_text = "SERVER —"
	var rx: String = _server_state_text()
	_net_label.text = "%s%s  ·  %d/%d" % [
		ping_text, rx, Network.peer_count(), Network.MAX_PLAYERS]


func _server_ping_ms() -> int:
	var relay: Variant = Network.get("relay_rtt_ms")
	if relay is int or relay is float:
		var rtt: int = int(relay)
		if rtt > 0:
			return rtt
	if Network.is_host:
		return maxi(Network.host_ping_ms, 0)
	return maxi(Network.latency_ms, 0)


func _server_state_text() -> String:
	if not Network.is_host or not Network.in_game or not Network.is_session_active():
		return ""
	var receiving: Variant = Network.get("race_state_receiving")
	if receiving is bool and bool(receiving):
		return " · RX"
	var enabled: Variant = Network.get("race_state_stream_enabled")
	if enabled is bool and not bool(enabled):
		return " · OFF"
	return " · WAIT"


func _update_gear(cart: CartPlayer, _speed_kmh: float) -> void:
	if _gear_value == null:
		return
	var forward: float = cart.velocity.dot(-cart.global_transform.basis.z)
	var gear: String = "GN"
	if forward < -0.6:
		gear = "GR"
	elif forward > 0.6:
		var ratio: float = clampf(forward / maxf(cart.max_speed, 0.1), 0.0, 1.0)
		gear = "G%d" % clampi(1 + int(ratio * 3.99), 1, 4)
	if gear == _last_gear:
		return
	_last_gear = gear
	_gear_value.text = gear
	var fill_col: Color = UiPalette.YELLOW
	var txt_col: Color = UiPalette.INK
	var out_sz: int = 0
	if gear == "GR":
		fill_col = Color("ff3b3f")
		txt_col = UiPalette.CREAM
		out_sz = 5
	elif gear == "GN":
		fill_col = UiPalette.CYAN
	elif gear == "G4":
		fill_col = UiPalette.PINK
		txt_col = UiPalette.CREAM
		out_sz = 5
	_gear_value.add_theme_constant_override("outline_size", out_sz)
	_gear_value.add_theme_color_override("font_color", txt_col)
	if _gear_plate != null:
		_gear_plate.fill_color = fill_col
		_gear_plate.queue_redraw()


func _update_network_standings(delta: float) -> void:
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
		var player_name: String = str(entry.get("name", entry.get("player", "")))
		if player_name == "":
			player_name = Network.name_of(peer_id) if peer_id > 0 else "PLAYER"
		var local: bool = bool(entry.get("local", peer_id == local_id))
		var color: Variant = entry.get("color", Color.WHITE)
		var place: int = int(entry.get("place", entry.get("position",
			entry.get("rank", 0))))
		var time: float = float(entry.get("time", entry.get("race_time", -1.0)))
		var progress: float = float(entry.get("progress", 0.0))
		if progress == 0.0 and time > 0.0:
			progress = -time
		entries.append({
			"name": player_name,
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
# hold-Tab player list (skewed comic slash board, zero dark rounded boxes)


func _build_scoreboard() -> void:
	_scoreboard = PanelContainer.new()
	_scoreboard.name = "Scoreboard"
	_scoreboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb_pad := _slash_margin(_scoreboard, 26, 16, 28, 20)
	_scoreboard_plate = _attach_slash(
		_scoreboard, 14.0, UiPalette.INK, UiPalette.YELLOW, 4.0, Vector2(5.0, 6.0))
	_scoreboard.anchor_left = 0.5
	_scoreboard.anchor_right = 0.5
	_scoreboard.offset_left = -224.0
	_scoreboard.offset_right = 224.0
	_scoreboard.offset_top = 140.0
	_scoreboard.offset_bottom = 140.0
	_scoreboard.grow_vertical = Control.GROW_DIRECTION_END
	_scoreboard.visible = false

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	sb_pad.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)

	_scoreboard_count = _label("PLAYERS  0/%d" % Network.MAX_PLAYERS, 16, UiPalette.YELLOW, 5, false)
	_scoreboard_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_scoreboard_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_scoreboard_count)

	_scoreboard_ping_header = _label("PING", 14, UiPalette.CYAN, 5, false)
	_scoreboard_ping_header.custom_minimum_size = Vector2(64.0, 0.0)
	_scoreboard_ping_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_scoreboard_ping_header)

	_scoreboard_rows = VBoxContainer.new()
	_scoreboard_rows.add_theme_constant_override("separation", 8)
	column.add_child(_scoreboard_rows)

	add_child(_scoreboard)


func _ping_color(ms: int) -> Color:
	if ms < 60:
		return UiPalette.GRASS
	if ms < 120:
		return UiPalette.YELLOW
	return UiPalette.PINK


func _make_scoreboard_row() -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0.0, 38.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb_row_pad := _slash_margin(panel, 18, 4, 20, 6)
	var plate := _attach_slash(
		panel, 8.0, Color(0.16, 0.14, 0.30, 0.92), UiPalette.INK, 2.5, Vector2(2.5, 3.0))
	plate.draw_sheen = false
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	sb_row_pad.add_child(row)

	var name_label := _label("", 16, UiPalette.CREAM, 5, false)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name_label)

	var ping_label := _label("", 15, UiPalette.CREAM, 5, false)
	ping_label.custom_minimum_size = Vector2(68.0, 0.0)
	ping_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ping_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(ping_label)

	_scoreboard_rows.add_child(panel)
	return {"panel": panel, "plate": plate, "name": name_label, "ping": ping_label}


func _update_scoreboard() -> void:
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
		var plate: _SlashPlate = entry["plate"]
		_scoreboard_rows.move_child(panel, index)
		var is_local: bool = peer_id == local_id
		plate.fill_color = UiPalette.YELLOW if is_local else Color(0.16, 0.14, 0.30, 0.92)
		plate.accent_color = Network.color_of(peer_id)
		plate.accent_width = 14.0
		plate.queue_redraw()
		var name_label: Label = entry["name"]
		var text: String = Network.name_of(peer_id)
		if is_local:
			text += " · YOU"
		if peer_id == 1:
			text = "HOST · " + text
		name_label.text = text
		name_label.add_theme_constant_override("outline_size", 0 if is_local else 5)
		name_label.add_theme_color_override("font_color", UiPalette.INK if is_local else UiPalette.CREAM)
		var ms: int = int(Network.ping_table.get(peer_id, 0))
		if ms <= 0 and not Network.is_host and is_local:
			ms = maxi(Network.latency_ms, 0)
		if ms <= 0 and Network.is_host and peer_id == 1:
			ms = maxi(Network.host_ping_ms, 0)
		var ping_label: Label = entry["ping"]
		ping_label.add_theme_constant_override("outline_size", 0 if is_local else 5)
		if ms <= 0:
			ping_label.text = "—"
			ping_label.add_theme_color_override("font_color",
				UiPalette.INK if is_local else UiPalette.TEXT_DIM)
		else:
			ping_label.text = "%d MS" % ms
			ping_label.add_theme_color_override("font_color",
				UiPalette.INK if is_local else _ping_color(ms))
	_scoreboard.pivot_offset = _hud_pivot(_scoreboard)


func _set_scoreboard_visible(visible_now: bool) -> void:
	_scoreboard_visible = visible_now
	_debug_label.visible = _debug_visible and not _scoreboard_visible
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
			return "AIRBORNE!"
		CartPlayer.CartState.CRASHED:
			return "CRASHED!"
		CartPlayer.CartState.RECOVERY:
			return "RECOVERY!"
	return "DRIVING"


func _state_color(cart: CartPlayer) -> Color:
	match cart.current_state:
		CartPlayer.CartState.DRIVING:
			return UiPalette.CREAM
		CartPlayer.CartState.AIRBORNE_TUMBLE:
			return UiPalette.CYAN
		CartPlayer.CartState.CRASHED:
			return Color("ff3b3f")
		CartPlayer.CartState.RECOVERY:
			return UiPalette.YELLOW
	return UiPalette.CREAM


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null:
		return
	if key.keycode == KEY_TAB and _scoreboard != null:
		if not key.echo:
			_set_scoreboard_visible(key.pressed)
			get_viewport().set_input_as_handled()
		return
	if key.pressed and not key.echo and key.keycode == KEY_F3:
		_debug_visible = not _debug_visible
		_debug_label.visible = _debug_visible and not _scoreboard_visible
		get_viewport().set_input_as_handled()


func _update_debug(cart: CartPlayer) -> void:
	var rig := get_tree().get_first_node_in_group("camera_rig") as ChaseCamera
	var fov_text: String = "-"
	if rig != null:
		fov_text = "%.1f" % rig.current_fov
	var feedback := get_tree().get_first_node_in_group("cart_feedback") as CartFeedback
	var dust_text: String = "OFF"
	var wind_text: String = "OFF"
	if feedback != null:
		dust_text = "ON" if feedback.dust_active else "OFF"
		wind_text = "ON" if feedback.speed_feedback_active else "OFF"
	_debug_label.text = "FOV %s   DRIFT %s   SMOKE %s   SPEED FX %s\nPOS %.1f %.1f %.1f   VEL %.1f" % [
		fov_text, cart.is_drifting, dust_text, wind_text,
		cart.global_position.x, cart.global_position.y, cart.global_position.z, cart.velocity.length()]
