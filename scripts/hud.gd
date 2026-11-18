extends Control
## In-game HUD: arcade speedometer with 3-tier drift-charge halo, slanted boost
## meter, drive state pill, non-jittering race plaque, wrong-way alert banner,
## and dynamically windowed live standings. F3 toggles the debug readout.

const UiPalette := preload("res://scripts/ui/ui_palette.gd")

const DIAL_START: float = PI * 0.75 ## Dial arc opens at the lower left.
const DIAL_SWEEP: float = PI * 1.5 ## 270 degrees, leaving the bottom gap free.
const DIAL_SURFACE: Color = Color("0d192b")
const DIAL_MUTED: Color = Color("6b8299")
const DIAL_CYAN: Color = Color("55dfef")
const DIAL_GOLD: Color = Color("ffd166")
const DIAL_REDLINE: Color = Color("ff6b6b")

const DRIFT_TIER_COLORS: Array[Color] = [
	Color("38d6f0"),
	Color("38e8ff"),
	Color("ff922b"),
	Color("ff3ec9"),
]
const DRIFT_TIER_NAMES: PackedStringArray = ["", "TURBO", "BLAZE", "ULTRA!"]

const NET_TOP: float = 18.0
const NET_HEIGHT: float = 26.0
const STANDINGS_SOLO_TOP: float = 20.0
const STANDINGS_NET_TOP: float = 48.0
const STANDINGS_ROW_HEIGHT: float = 24.0
const STANDINGS_COMPACT_ROW_HEIGHT: float = 22.0
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


class _DialCanvas extends Control:
	func _draw() -> void:
		var gauge: Node = get_parent()
		if gauge != null and gauge.get_parent() != null:
			gauge.get_parent().call("_draw_gauge_canvas", self)


var _dial_canvas: _DialCanvas
var _debug_visible: bool = false
var _hint_timer: float = 0.0
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
var _delta_badge: PanelContainer
var _delta_badge_style: StyleBoxFlat
var _lap_pips: HBoxContainer
var _lap_pip_total: int = 0
var _lap_pip_index: int = -1
var _pip_done_style: StyleBoxFlat
var _pip_active_style: StyleBoxFlat
var _pip_upcoming_style: StyleBoxFlat
var _gear_badge: PanelContainer
var _gear_style: StyleBoxFlat
var _gear_value: Label
var _last_gear: String = ""
var _drift_badge: PanelContainer
var _drift_badge_style: StyleBoxFlat
var _drift_badge_label: Label
var _drift_arc_ratio: float = 0.0
var _drift_tier: int = 0
var _drift_active: bool = false
var _wrong_way_banner: PanelContainer
var _wrong_way_style: StyleBoxFlat
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
var _last_place: int = 0
var _position_tween: Tween
var _standings_title: Label
var _dial_ratio: float = 0.0
var _dial_boost: float = 0.0
var _dial_max_kmh: float = 120.0
var _hud_scale_factor: float = 1.0


func _ready() -> void:
	_hint_timer = 0.0
	_hint_label.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_dial_canvas()
	if Network.is_session_active():
		_build_net_block()
		_build_scoreboard()
	_debug_label.visible = false
	_build_boost_header()
	_build_race_plaque()
	_build_standings()
	_build_gear_badge()
	_build_drift_badge()
	_build_wrong_way_banner()
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
	_fps_label = _label("60 FPS", 13, Color(1, 1, 1, 0.88), 4)
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
		_boost_box.offset_right = 24.0 + maxf(box_min.x, 288.0)
		_boost_box.offset_bottom = -24.0
		_boost_box.offset_top = -24.0 - box_min.y
	if not _last_standings_entries.is_empty():
		_apply_standings(_last_standings_entries)
	else:
		_position_standings_panel()
	for child: Node in get_children():
		if not (child is Control):
			continue
		var control := child as Control
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


func _panel_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(16)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	style.anti_aliasing = true
	return style


func _label(text: String, font_size: int, color: Color,
		outline: int = 0) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
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
	_race_plaque.offset_right = 24.0 + 348.0
	_race_plaque.offset_bottom = 20.0 + 134.0
	_race_plaque.custom_minimum_size = Vector2(348.0, 134.0)
	var style := _panel_style(Color(0.045, 0.092, 0.172, 0.95))
	style.border_width_left = 4
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.42, 0.80, 1.0, 0.42)
	style.shadow_color = Color(0.02, 0.04, 0.10, 0.54)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 4)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	_race_plaque.add_theme_stylebox_override("panel", style)
	add_child(_race_plaque)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_race_plaque.add_child(column)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(top)
	_plaque_pos = _label("1ST", 40, Color("ffd166"), 4)
	_plaque_pos.theme_type_variation = &"TitleLabel"
	_plaque_pos.custom_minimum_size = Vector2(88.0, 0.0)
	top.add_child(_plaque_pos)
	var pos_stack := VBoxContainer.new()
	pos_stack.size_flags_vertical = Control.SIZE_SHRINK_END
	pos_stack.add_theme_constant_override("separation", 0)
	pos_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(pos_stack)
	_plaque_of = _label("OF —", 14, Color(1, 1, 1, 0.72))
	pos_stack.add_child(_plaque_of)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	_plaque_lap = _label("LAP 1/3", 20, UiPalette.CREAM, 3)
	_plaque_lap.theme_type_variation = &"TitleLabel"
	_plaque_lap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_plaque_lap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_plaque_lap)

	# Fixed-width time slots so ticking milliseconds never push BEST sideways.
	var middle := HBoxContainer.new()
	middle.add_theme_constant_override("separation", 8)
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(middle)

	var time_slot := HBoxContainer.new()
	time_slot.custom_minimum_size = Vector2(168.0, 28.0)
	time_slot.add_theme_constant_override("separation", 6)
	time_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle.add_child(time_slot)
	var time_caption := _label("TIME", 12, Color(1, 1, 1, 0.62))
	time_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	time_slot.add_child(time_caption)
	_plaque_time = _label("0:00.000", 23, UiPalette.YELLOW, 3)
	_plaque_time.custom_minimum_size = Vector2(124.0, 0.0)
	_plaque_time.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	time_slot.add_child(_plaque_time)

	var best_slot := HBoxContainer.new()
	best_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	best_slot.alignment = BoxContainer.ALIGNMENT_END
	best_slot.add_theme_constant_override("separation", 6)
	best_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle.add_child(best_slot)
	var best_caption := _label("BEST", 12, Color(1, 1, 1, 0.56))
	best_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	best_slot.add_child(best_caption)
	_plaque_best = _label("—", 16, Color(1, 1, 1, 0.90), 2)
	_plaque_best.custom_minimum_size = Vector2(84.0, 0.0)
	_plaque_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_plaque_best.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	best_slot.add_child(_plaque_best)

	# Progress row: lap pips on the left, dedicated fixed-width badge slot on the
	# right so _lap_pips never jumps in width when the lap-delta badge appears.
	var progress_row := HBoxContainer.new()
	progress_row.add_theme_constant_override("separation", 10)
	progress_row.custom_minimum_size = Vector2(0.0, 22.0)
	progress_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(progress_row)

	_lap_pips = HBoxContainer.new()
	_lap_pips.add_theme_constant_override("separation", 5)
	_lap_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lap_pips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lap_pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	progress_row.add_child(_lap_pips)

	var delta_slot := HBoxContainer.new()
	delta_slot.custom_minimum_size = Vector2(124.0, 20.0)
	delta_slot.alignment = BoxContainer.ALIGNMENT_END
	delta_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_row.add_child(delta_slot)

	_delta_badge = PanelContainer.new()
	_delta_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_delta_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_delta_badge_style = StyleBoxFlat.new()
	_delta_badge_style.bg_color = Color(1.0, 1.0, 1.0, 0.10)
	_delta_badge_style.set_corner_radius_all(6)
	_delta_badge_style.set_border_width_all(1)
	_delta_badge_style.border_color = Color(0.65, 0.82, 0.98, 0.25)
	_delta_badge_style.content_margin_left = 7.0
	_delta_badge_style.content_margin_right = 7.0
	_delta_badge_style.content_margin_top = 1.0
	_delta_badge_style.content_margin_bottom = 1.0
	_delta_badge_style.anti_aliasing = true
	_delta_badge.add_theme_stylebox_override("panel", _delta_badge_style)
	_plaque_delta = _label("", 12, Color("b8cce0"))
	_plaque_delta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_delta_badge.add_child(_plaque_delta)
	_delta_badge.visible = false
	delta_slot.add_child(_delta_badge)

	_race_plaque.visible = false


func _build_gear_badge() -> void:
	_gear_badge = PanelContainer.new()
	_gear_badge.name = "GearBadge"
	_gear_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gear_badge.anchor_left = 0.5
	_gear_badge.anchor_top = 0.5
	_gear_badge.anchor_right = 0.5
	_gear_badge.anchor_bottom = 0.5
	_gear_badge.offset_left = -38.0
	_gear_badge.offset_top = 46.0
	_gear_badge.offset_right = 38.0
	_gear_badge.offset_bottom = 74.0
	_gear_style = StyleBoxFlat.new()
	_gear_style.bg_color = Color(0.10, 0.20, 0.34, 0.85)
	_gear_style.set_corner_radius_all(8)
	_gear_style.set_border_width_all(1)
	_gear_style.border_color = Color(0.50, 0.78, 0.96, 0.36)
	_gear_style.content_margin_left = 8.0
	_gear_style.content_margin_right = 8.0
	_gear_style.content_margin_top = 2.0
	_gear_style.content_margin_bottom = 2.0
	_gear_style.anti_aliasing = true
	_gear_badge.add_theme_stylebox_override("panel", _gear_style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gear_badge.add_child(row)
	var caption := _label("GEAR", 12, Color("a8c4d8"))
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(caption)
	_gear_value = _label("N", 17, Color("55dfef"), 2)
	_gear_value.theme_type_variation = &"TitleLabel"
	_gear_value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_gear_value)
	_speed_gauge.add_child(_gear_badge)


func _build_drift_badge() -> void:
	_drift_badge = PanelContainer.new()
	_drift_badge.name = "DriftBadge"
	_drift_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drift_badge.anchor_left = 0.5
	_drift_badge.anchor_top = 0.0
	_drift_badge.anchor_right = 0.5
	_drift_badge.anchor_bottom = 0.0
	_drift_badge.offset_left = -44.0
	_drift_badge.offset_top = 20.0
	_drift_badge.offset_right = 44.0
	_drift_badge.offset_bottom = 42.0
	_drift_badge.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_drift_badge_style = StyleBoxFlat.new()
	_drift_badge_style.bg_color = DRIFT_TIER_COLORS[1]
	_drift_badge_style.set_corner_radius_all(8)
	_drift_badge_style.set_border_width_all(2)
	_drift_badge_style.border_color = UiPalette.OUTLINE
	_drift_badge_style.content_margin_left = 8.0
	_drift_badge_style.content_margin_right = 8.0
	_drift_badge_style.content_margin_top = 1.0
	_drift_badge_style.content_margin_bottom = 1.0
	_drift_badge_style.anti_aliasing = true
	_drift_badge.add_theme_stylebox_override("panel", _drift_badge_style)
	_drift_badge_label = _label("TURBO", 12, UiPalette.INK)
	_drift_badge_label.theme_type_variation = &"TitleLabel"
	_drift_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_drift_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_drift_badge.add_child(_drift_badge_label)
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
	_wrong_way_banner.offset_left = -148.0
	_wrong_way_banner.offset_top = 64.0
	_wrong_way_banner.offset_right = 148.0
	_wrong_way_banner.offset_bottom = 112.0
	_wrong_way_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_wrong_way_style = StyleBoxFlat.new()
	_wrong_way_style.bg_color = Color(0.14, 0.05, 0.09, 0.94)
	_wrong_way_style.set_corner_radius_all(14)
	_wrong_way_style.set_border_width_all(4)
	_wrong_way_style.border_color = UiPalette.YELLOW
	_wrong_way_style.content_margin_left = 18.0
	_wrong_way_style.content_margin_right = 18.0
	_wrong_way_style.content_margin_top = 6.0
	_wrong_way_style.content_margin_bottom = 6.0
	_wrong_way_style.shadow_color = Color(0.95, 0.25, 0.25, 0.35)
	_wrong_way_style.shadow_size = 8
	_wrong_way_style.anti_aliasing = true
	_wrong_way_banner.add_theme_stylebox_override("panel", _wrong_way_style)
	_wrong_way_label = _label("◀ WRONG WAY ▶", 22, UiPalette.YELLOW, 4)
	_wrong_way_label.theme_type_variation = &"TitleLabel"
	_wrong_way_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wrong_way_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_wrong_way_banner.add_child(_wrong_way_label)
	_wrong_way_banner.visible = false
	add_child(_wrong_way_banner)


func set_wrong_way(active: bool) -> void:
	## Upper-center wrong-way alert pill. Hidden by default; pulses unless reduce_motion is on.
	if _wrong_way_active == active and _wrong_way_banner != null \
			and _wrong_way_banner.visible == active:
		return
	_wrong_way_active = active
	if _wrong_way_banner == null:
		return
	_wrong_way_banner.visible = active
	_wrong_way_banner.modulate = Color.WHITE
	_wrong_way_style.border_color = UiPalette.YELLOW
	_wrong_way_banner.pivot_offset = _hud_pivot(_wrong_way_banner)


func _ensure_pip_styles() -> void:
	if _pip_done_style != null:
		return
	_pip_done_style = StyleBoxFlat.new()
	_pip_done_style.bg_color = UiPalette.YELLOW
	_pip_done_style.set_corner_radius_all(3)
	_pip_done_style.set_border_width_all(1)
	_pip_done_style.border_color = Color(1.0, 0.95, 0.65, 0.75)
	_pip_done_style.anti_aliasing = true

	_pip_active_style = StyleBoxFlat.new()
	_pip_active_style.bg_color = UiPalette.CYAN
	_pip_active_style.set_corner_radius_all(3)
	_pip_active_style.set_border_width_all(1)
	_pip_active_style.border_color = Color(1.0, 1.0, 1.0, 0.88)
	_pip_active_style.shadow_color = Color(0.22, 0.84, 0.96, 0.45)
	_pip_active_style.shadow_size = 3
	_pip_active_style.anti_aliasing = true

	_pip_upcoming_style = StyleBoxFlat.new()
	_pip_upcoming_style.bg_color = Color(0.14, 0.22, 0.34, 0.78)
	_pip_upcoming_style.set_corner_radius_all(3)
	_pip_upcoming_style.set_border_width_all(1)
	_pip_upcoming_style.border_color = Color(0.55, 0.78, 1.0, 0.18)
	_pip_upcoming_style.anti_aliasing = true


func _lap_pips_for(total: int) -> void:
	_ensure_pip_styles()
	_lap_pip_total = total
	_lap_pip_index = -1
	for child: Node in _lap_pips.get_children():
		_lap_pips.remove_child(child)
		child.queue_free()
	for _i in total:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(0, 7)
		pip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.add_theme_stylebox_override("panel", _pip_upcoming_style)
		_lap_pips.add_child(pip)
	_lap_pips.visible = total > 0


func _update_lap_pips(current: int) -> void:
	if _lap_pip_total <= 0:
		return
	_ensure_pip_styles()
	var index: int = clampi(current - 1, 0, _lap_pip_total - 1)
	if index == _lap_pip_index:
		return
	_lap_pip_index = index
	var children: Array[Node] = _lap_pips.get_children()
	for i in children.size():
		var pip := children[i] as Panel
		if pip == null:
			continue
		if i < index:
			pip.add_theme_stylebox_override("panel", _pip_done_style)
		elif i == index:
			pip.add_theme_stylebox_override("panel", _pip_active_style)
		else:
			pip.add_theme_stylebox_override("panel", _pip_upcoming_style)


func _build_net_block() -> void:
	_net_panel = PanelContainer.new()
	_net_panel.name = "NetBlock"
	_net_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_net_panel.anchor_left = 1.0
	_net_panel.anchor_right = 1.0
	_net_panel.offset_left = -324.0
	_net_panel.offset_right = -24.0
	_net_panel.offset_top = NET_TOP
	_net_panel.offset_bottom = NET_TOP + NET_HEIGHT
	var style := _panel_style(Color(0.045, 0.092, 0.172, 0.88))
	style.set_corner_radius_all(10)
	style.set_border_width_all(1)
	style.border_color = Color(0.42, 0.80, 1.0, 0.30)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	_net_panel.add_theme_stylebox_override("panel", style)
	_net_label = _label("SERVER —", 13, Color(1, 1, 1, 0.88), 3)
	_net_label.name = "NetStats"
	_net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_net_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
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
	_standings_panel.offset_top = STANDINGS_SOLO_TOP
	_standings_panel.offset_bottom = STANDINGS_SOLO_TOP
	_standings_panel.custom_minimum_size = Vector2(276.0, 0.0)
	var style := _panel_style(Color(0.045, 0.092, 0.172, 0.94))
	style.set_border_width_all(2)
	style.border_color = Color(0.42, 0.80, 1.0, 0.34)
	style.shadow_color = Color(0.02, 0.04, 0.10, 0.50)
	style.shadow_size = 7
	style.shadow_offset = Vector2(0, 4)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	_standings_panel.add_theme_stylebox_override("panel", style)
	add_child(_standings_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_standings_panel.add_child(column)
	_standings_title = _label("STANDINGS", 12, Color(1, 1, 1, 0.65))
	column.add_child(_standings_title)
	_standings_rows = VBoxContainer.new()
	_standings_rows.add_theme_constant_override("separation", 2)
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
	_standings_panel.offset_left = -300.0
	_standings_panel.offset_right = -24.0
	_standings_panel.offset_top = top_y
	var min_sz: Vector2 = _standings_panel.get_combined_minimum_size()
	_standings_panel.offset_bottom = top_y + min_sz.y
	_standings_panel.size = Vector2(276.0, min_sz.y)
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
	var max_unscaled_h: float = maxf((gauge_top_y - 16.0 - top_y) / maxf(scale_factor, 0.5), 92.0)

	var compact: bool = entries.size() > 8 or scale_factor > 1.12 or view_h < 600.0
	var row_h: float = STANDINGS_COMPACT_ROW_HEIGHT if compact else STANDINGS_ROW_HEIGHT
	var row_font: int = 12 if compact else 13
	var row_pad_v: float = 1.0 if compact else 2.0
	var sep: int = 2
	var avail_rows_h: float = maxf(max_unscaled_h - 38.0, row_h)
	var max_slots: int = clampi(
		int(floor((avail_rows_h + float(sep)) / (row_h + float(sep)))),
		3, STANDINGS_MAX_ROWS)

	var slot_map: Array[int] = _select_standings_slots(entries, max_slots)
	var visible_count: int = slot_map.size()
	if entries.size() > 1:
		_standings_title.text = "STANDINGS  %d" % entries.size()
	else:
		_standings_title.text = "STANDINGS"

	while _standings_row_cache.size() < visible_count:
		var row := PanelContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.custom_minimum_size = Vector2(0, row_h)
		var style := _panel_style(Color(1, 1, 1, 0.035))
		style.set_corner_radius_all(6)
		style.content_margin_left = 8.0
		style.content_margin_right = 8.0
		style.content_margin_top = row_pad_v
		style.content_margin_bottom = row_pad_v
		row.add_theme_stylebox_override("panel", style)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 7)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(line)
		var place_label := _label("", row_font, Color.WHITE)
		place_label.custom_minimum_size.x = 18.0
		line.add_child(place_label)
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(3, 12)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(dot)
		var name_label := _label("", row_font, Color.WHITE)
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
	var hidden_count: int = maxi(entries.size() - (visible_count - 1), 1)
	for slot in _standings_row_cache.size():
		var cached: Dictionary = _standings_row_cache[slot]
		var row_ctrl := cached["row"] as Control
		row_ctrl.visible = slot < visible_count
		if slot >= visible_count:
			continue
		row_ctrl.custom_minimum_size.y = row_h
		var row_style := cached["style"] as StyleBoxFlat
		row_style.content_margin_top = row_pad_v
		row_style.content_margin_bottom = row_pad_v
		var place_lbl := cached["place"] as Label
		var name_lbl := cached["name"] as Label
		var dot_rect := cached["dot"] as ColorRect
		var gap_lbl := cached["gap"] as Label
		place_lbl.add_theme_font_size_override("font_size", row_font)
		name_lbl.add_theme_font_size_override("font_size", row_font)
		var entry_idx: int = slot_map[slot]
		if entry_idx < 0:
			row_style.bg_color = Color(1, 1, 1, 0.015)
			row_style.border_width_left = 0
			place_lbl.text = "··"
			place_lbl.add_theme_color_override("font_color", Color("7f95ab"))
			dot_rect.visible = false
			name_lbl.text = "···"
			name_lbl.add_theme_color_override("font_color", Color("7f95ab"))
			gap_lbl.text = "+%d" % hidden_count if slot == visible_count - 1 else ""
			continue
		dot_rect.visible = true
		var entry: Dictionary = entries[entry_idx]
		var local: bool = bool(entry.get("local", false))
		var place: int = int(entry.get("place", 0))
		var shown_place: int = place if place > 0 else entry_idx + 1
		if local:
			row_style.bg_color = Color(0.24, 0.80, 0.96, 0.22)
			row_style.border_width_left = 3
			row_style.border_color = Color("55dfef")
		elif shown_place == 1:
			row_style.bg_color = Color(1.0, 0.82, 0.25, 0.11)
			row_style.border_width_left = 2
			row_style.border_color = Color(1.0, 0.82, 0.25, 0.65)
		else:
			row_style.bg_color = Color(1, 1, 1, 0.04)
			row_style.border_width_left = 0
		place_lbl.text = str(shown_place)
		var place_col: Color = Color("ffd166") if shown_place == 1 else Color.WHITE
		place_lbl.add_theme_color_override("font_color", Color("55dfef") if local else place_col)
		dot_rect.color = entry.get("color", Color.WHITE)
		name_lbl.text = str(entry.get("name", "PLAYER")) + (" · YOU" if local else "")
		name_lbl.add_theme_color_override("font_color", Color("e7fbff") if local else Color.WHITE)
		var gap_text: String = "LEADER"
		if entry_idx > 0:
			var entry_time: float = float(entry.get("time", -1.0))
			if entry_time > 0.0 and leader_time > 0.0:
				gap_text = "+%.2fs" % maxf(entry_time - leader_time, 0.0)
			else:
				gap_text = "+%dm" % int(maxf(leader - float(entry.get("progress", 0.0)), 0.0))
		gap_lbl.text = gap_text

	_position_standings_panel()


func set_race_position(place: int, field_size: int = 0) -> void:
	_explicit_position_ms = Time.get_ticks_msec()
	_show_position(place, field_size)


func _show_position(place: int, field_size: int = 0) -> void:
	if _race_plaque == null:
		return
	place = maxi(place, 1)
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
	var pos_color: Color = UiPalette.CREAM
	if place == 1:
		pos_color = Color("ffd166")
	elif place == 2:
		pos_color = Color("dce8f5")
	elif place == 3:
		pos_color = Color("f4a261")
	_plaque_pos.add_theme_color_override("font_color", pos_color)
	if _last_place > 0 and place != _last_place and not GameSettings.reduce_motion:
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
	## Explicit completed-lap setter; displays lap delta in the dedicated badge slot.
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
			_plaque_delta.add_theme_color_override("font_color", Color("ff887e"))
			_delta_badge_style.bg_color = Color(0.95, 0.33, 0.35, 0.22)
			_delta_badge_style.border_color = Color(1.0, 0.50, 0.48, 0.45)
		else:
			text = "-%.2fs" % absf(delta)
			_plaque_delta.add_theme_color_override("font_color", Color("6bf18d"))
			_delta_badge_style.bg_color = Color(0.25, 0.85, 0.45, 0.22)
			_delta_badge_style.border_color = Color(0.42, 0.95, 0.56, 0.45)
		if _plaque_delta.text != text:
			_plaque_delta.text = text
		_delta_badge.visible = true
		return
	var current: float = maxf(_race_clock - _lap_start_time, 0.0)
	if current >= 1.0:
		var lap_str: String = "LAP %s" % _format_short_lap(current)
		_plaque_delta.add_theme_color_override("font_color", Color("a8c0d6"))
		_delta_badge_style.bg_color = Color(1.0, 1.0, 1.0, 0.08)
		_delta_badge_style.border_color = Color(0.65, 0.82, 0.98, 0.22)
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
	_plaque_delta.add_theme_color_override("font_color", Color("a8c0d6"))
	_delta_badge_style.bg_color = Color(1.0, 1.0, 1.0, 0.08)
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
			_wrong_way_style.border_color = UiPalette.YELLOW
			_wrong_way_banner.modulate.a = 1.0
		else:
			var wave: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.012)
			_wrong_way_style.border_color = UiPalette.RED.lerp(UiPalette.YELLOW, wave)
			_wrong_way_label.add_theme_color_override("font_color",
				Color("ff887e").lerp(UiPalette.YELLOW, wave))
			_wrong_way_banner.modulate.a = 0.88 + 0.12 * wave
			_wrong_way_banner.queue_redraw()
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
		_drift_tier = raw_drift_tier
		_update_drift_badge()

	_update_gear(cart, speed_kmh)

	var boost_ratio: float = clampf(cart.boost_amount / maxf(cart.max_boost, 0.1), 0.0, 1.0)
	_boost_meter.ratio = boost_ratio
	_boost_meter.boosting = cart.boost_active
	var boost_caption: String = "BOOSTING!" if cart.boost_active else ("LOW BOOST" if boost_ratio < 0.16 else "BOOST READY")
	if boost_caption != _last_boost_caption:
		_last_boost_caption = boost_caption
		_boost_caption.text = boost_caption
		_boost_caption.add_theme_color_override("font_color", Color("ffd166") if cart.boost_active else Color("e7f3ff"))
	var boost_percent: int = int(round(boost_ratio * 100.0))
	if boost_percent != _last_boost_percent and _boost_percent != null:
		_last_boost_percent = boost_percent
		_boost_percent.text = "%d%%" % boost_percent

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
	_drift_badge_style.bg_color = tier_color
	_drift_badge_label.text = DRIFT_TIER_NAMES[_drift_tier]
	_drift_badge_label.add_theme_color_override("font_color",
		Color.WHITE if _drift_tier == 3 else UiPalette.INK)
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
	var dial_radius: float = half - 14.0

	# Boost glow rings behind the dial plate.
	if _boost_glow > 0.001:
		var pulse: float = 1.0 if GameSettings.reduce_motion else 0.90 + 0.10 * sin(float(Time.get_ticks_msec()) * 0.012)
		for index in 3:
			var spread: float = dial_radius + 6.0 + float(index) * 5.0
			var alpha: float = (0.17 - float(index) * 0.045) * _boost_glow * pulse
			canvas.draw_circle(center, spread, Color(0.28, 0.88, 1.0, alpha))

	# Outer 3-Tier Drift-Charge Halo (Cyan -> Orange -> Magenta).
	if _drift_active or _drift_arc_ratio > 0.004 or _drift_tier > 0:
		var halo_r: float = half - 5.0
		var seg_gap: float = 0.045
		var third: float = DIAL_SWEEP / 3.0
		for seg in 3:
			var a0: float = DIAL_START + third * float(seg) + (seg_gap * 0.5 if seg > 0 else 0.0)
			var a1: float = DIAL_START + third * float(seg + 1) - (seg_gap * 0.5 if seg < 2 else 0.0)
			canvas.draw_arc(center, halo_r, a0, a1, 20, Color(0.08, 0.14, 0.24, 0.65), 7.0, true)
			canvas.draw_arc(center, halo_r, a0, a1, 20, Color(0.55, 0.75, 0.92, 0.24), 4.5, true)
		var fill_ratio: float = clampf(_drift_arc_ratio, 0.0, 1.0)
		if _drift_tier > 0 and fill_ratio < float(_drift_tier) / 3.0:
			fill_ratio = float(_drift_tier) / 3.0
		if fill_ratio > 0.006:
			var tier_idx: int = clampi(_drift_tier, 0, 3)
			var drift_col: Color = DRIFT_TIER_COLORS[tier_idx]
			var drift_end: float = DIAL_START + DIAL_SWEEP * fill_ratio
			var pulse_a: float = 1.0 if GameSettings.reduce_motion else (0.85 + 0.15 * sin(float(Time.get_ticks_msec()) * 0.016))
			if _drift_tier > 0:
				canvas.draw_arc(center, halo_r, DIAL_START, drift_end,
					maxi(8, int(64.0 * fill_ratio)),
					Color(drift_col.r, drift_col.g, drift_col.b, 0.34 * pulse_a), 12.0, true)
			canvas.draw_arc(center, halo_r, DIAL_START, drift_end,
				maxi(8, int(64.0 * fill_ratio)), drift_col, 5.5, true)
			var halo_tip := center + Vector2(cos(drift_end), sin(drift_end)) * halo_r
			canvas.draw_circle(halo_tip, 3.2, Color(1.0, 1.0, 1.0, 0.92))

	# Main opaque arcade dial plate + bevel ring + inner speed hub.
	canvas.draw_circle(center + Vector2(0.0, 5.0), dial_radius + 3.0, Color(0.02, 0.03, 0.08, 0.42))
	canvas.draw_circle(center, dial_radius + 1.5, Color(0.04, 0.08, 0.16, 0.98))
	canvas.draw_circle(center, dial_radius, Color(DIAL_SURFACE, 0.97))
	canvas.draw_arc(center, dial_radius - 1.2, 0.0, TAU, 72, Color(0.56, 0.84, 1.0, 0.28), 2.0, true)
	canvas.draw_circle(center, dial_radius * 0.56, Color(0.03, 0.07, 0.14, 0.62))
	canvas.draw_arc(center, dial_radius * 0.56, 0.0, TAU, 48, Color(0.45, 0.78, 1.0, 0.14), 1.2, true)

	# Racing tachometer track + redline band.
	var ring: float = dial_radius * 0.88
	var redline_start: float = DIAL_START + DIAL_SWEEP * 0.80
	canvas.draw_arc(center, ring, DIAL_START, DIAL_START + DIAL_SWEEP, 64,
		Color(0.03, 0.06, 0.12, 0.75), 12.0, true)
	canvas.draw_arc(center, ring, DIAL_START, redline_start, 56,
		Color(0.50, 0.70, 0.88, 0.18), 9.5, true)
	canvas.draw_arc(center, ring, redline_start, DIAL_START + DIAL_SWEEP, 20,
		Color(DIAL_REDLINE.r, DIAL_REDLINE.g, DIAL_REDLINE.b, 0.28), 9.5, true)

	var speed_accent: Color = DIAL_CYAN.lerp(DIAL_GOLD, _dial_boost)
	if _dial_ratio > 0.82 and _dial_boost < 0.25:
		speed_accent = speed_accent.lerp(DIAL_REDLINE, clampf((_dial_ratio - 0.82) / 0.18, 0.0, 0.75))

	if _dial_ratio > 0.004:
		var tip: float = DIAL_START + DIAL_SWEEP * _dial_ratio
		var arc_steps: int = maxi(4, int(72.0 * _dial_ratio))
		canvas.draw_arc(center, ring, DIAL_START, tip, arc_steps,
			Color(speed_accent.r, speed_accent.g, speed_accent.b, 0.28), 15.0, true)
		canvas.draw_arc(center, ring, DIAL_START, tip, arc_steps, speed_accent, 9.5, true)
		canvas.draw_arc(center, ring + 1.8, DIAL_START, tip, arc_steps,
			Color(1.0, 1.0, 1.0, 0.24), 2.2, true)
		canvas.draw_arc(center, ring, maxf(tip - 0.09, DIAL_START), tip, 10,
			Color(1, 1, 1, 0.94), 4.5, true)
		var tip_dir := Vector2(cos(tip), sin(tip))
		canvas.draw_line(center + tip_dir * (dial_radius * 0.77),
			center + tip_dir * (dial_radius * 0.96), Color(1, 1, 1, 0.96), 2.8, true)

	# Color-reactive speed ticks.
	for index in 25:
		var fraction: float = float(index) / 24.0
		var angle: float = DIAL_START + DIAL_SWEEP * fraction
		var direction := Vector2(cos(angle), sin(angle))
		var major: bool = index % 6 == 0
		var inner: float = 0.66 if major else 0.71
		var outer: float = 0.76 if major else 0.745
		var lit: bool = fraction <= _dial_ratio + 0.0001
		var tick_color: Color = Color(DIAL_MUTED, 0.50)
		if lit:
			tick_color = DIAL_REDLINE if fraction >= 0.80 and _dial_boost < 0.3 else speed_accent
		elif fraction >= 0.80:
			tick_color = Color(DIAL_REDLINE, 0.42)
		canvas.draw_line(center + direction * (dial_radius * inner),
			center + direction * (dial_radius * outer), tick_color,
			2.2 if major else 1.2, true)


func _update_net_stats() -> void:
	if not is_instance_valid(_net_label):
		return
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
	var gear_color: Color = Color("55dfef")
	if gear == "R":
		gear_color = Color("ff6b6b")
	elif gear == "N":
		gear_color = Color("a8c4d8")
	elif gear == "5":
		gear_color = Color("ffd166")
	_gear_value.add_theme_color_override("font_color", gear_color)


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
# hold-Tab player list


func _build_scoreboard() -> void:
	_scoreboard = PanelContainer.new()
	_scoreboard.name = "Scoreboard"
	_scoreboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.16, 0.92)
	style.set_corner_radius_all(UiKit.CORNER_RADIUS)
	style.set_border_width_all(2)
	style.border_color = Color(0.42, 0.80, 1.0, 0.34)
	style.shadow_color = Color(0.02, 0.03, 0.09, 0.52)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 4)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 12.0
	style.anti_aliasing = true
	_scoreboard.add_theme_stylebox_override("panel", style)
	_scoreboard.anchor_left = 0.5
	_scoreboard.anchor_right = 0.5
	_scoreboard.offset_left = -210.0
	_scoreboard.offset_right = 210.0
	_scoreboard.offset_top = 140.0
	_scoreboard.offset_bottom = 140.0
	_scoreboard.grow_vertical = Control.GROW_DIRECTION_END
	_scoreboard.visible = false
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_scoreboard.add_child(column)

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
	panel.custom_minimum_size = Vector2(0, 38)
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
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	row.add_child(name_label)
	var ping_label := Label.new()
	ping_label.custom_minimum_size = Vector2(64, 0)
	ping_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ping_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ping_label.add_theme_font_size_override("font_size", 15)
	row.add_child(ping_label)
	_scoreboard_rows.add_child(panel)
	return {"panel": panel, "dot": dot, "name": name_label, "ping": ping_label}


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
		if ms <= 0:
			ping_label.text = "—"
			ping_label.add_theme_color_override("font_color", Color(0.62, 0.66, 0.78))
		else:
			ping_label.text = "%d ms" % ms
			ping_label.add_theme_color_override("font_color", _ping_color(ms))
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
	var dust_text: String = "off"
	var wind_text: String = "off"
	if feedback != null:
		dust_text = "on" if feedback.dust_active else "off"
		wind_text = "on" if feedback.speed_feedback_active else "off"
	_debug_label.text = "FOV %s   drift %s   smoke %s   speed FX %s\npos %.1f %.1f %.1f   vel %.1f" % [
		fov_text, cart.is_drifting, dust_text, wind_text,
		cart.global_position.x, cart.global_position.y, cart.global_position.z, cart.velocity.length()]
