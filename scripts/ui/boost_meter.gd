extends Control
## Segmented slanted arcade boost meter with recessed dark power cells, inner
## specular shine, frontier spark, and animated surge pulse while boosting.

@export var ratio: float = 1.0:
	set(value):
		var clamped: float = clampf(value, 0.0, 1.0)
		if not is_equal_approx(clamped, ratio):
			ratio = clamped
			queue_redraw()
@export var boosting: bool = false:
	set(value):
		if boosting != value:
			boosting = value
			queue_redraw()

const CELLS: int = 10
const GAP: float = 3.5
const SKEW: float = 5.0
const CYAN_START: Color = Color("1aa7ec")
const CYAN_MID: Color = Color("38d6f0")
const CYAN_END: Color = Color("7ef9ff")
const GOLD_START: Color = Color("ff9e00")
const GOLD_END: Color = Color("fff280")
const LOW_START: Color = Color("e5383b")
const LOW_END: Color = Color("ff758f")
const SLOT_BG: Color = Color(0.11, 0.17, 0.29, 0.82)
const SLOT_RIM: Color = Color(0.03, 0.05, 0.11, 0.92)

var _frame := StyleBoxFlat.new()
var _glow := StyleBoxFlat.new()
var _surge_time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.bg_color = Color(0.04, 0.08, 0.16, 0.96)
	_frame.set_corner_radius_all(9)
	_frame.set_border_width_all(2)
	_frame.border_color = Color(0.45, 0.80, 1.0, 0.36)
	_frame.shadow_color = Color(0.02, 0.03, 0.09, 0.50)
	_frame.shadow_size = 5
	_frame.shadow_offset = Vector2(0, 3)
	_frame.anti_aliasing = true

	_glow.draw_center = false
	_glow.set_corner_radius_all(11)
	_glow.set_border_width_all(2)
	_glow.border_color = Color("ffd166")
	_glow.expand_margin_left = 2.0
	_glow.expand_margin_right = 2.0
	_glow.expand_margin_top = 2.0
	_glow.expand_margin_bottom = 2.0
	_glow.shadow_color = Color(1.0, 0.82, 0.25, 0.42)
	_glow.shadow_size = 8
	_glow.anti_aliasing = true
	resized.connect(queue_redraw)


func _is_reduce_motion() -> bool:
	var gs: Node = get_node_or_null("/root/GameSettings")
	return bool(gs.get("reduce_motion")) if gs != null else false


func _process(delta: float) -> void:
	var low_warn: bool = ratio > 0.005 and ratio <= 0.16 and not boosting
	if (boosting or low_warn) and not _is_reduce_motion():
		_surge_time += delta
		queue_redraw()


func _draw() -> void:
	var low: bool = ratio <= 0.16 and not boosting
	var reduce: bool = _is_reduce_motion()
	var pulse: float = 1.0 if reduce else (0.5 + 0.5 * sin(_surge_time * 9.0))

	if boosting:
		_frame.border_color = Color("ffd166").lerp(Color.WHITE, 0.28 * pulse)
		_glow.shadow_color = Color(1.0, 0.82, 0.25, 0.32 + 0.20 * pulse)
		draw_style_box(_glow, Rect2(Vector2.ZERO, size))
	elif low and ratio > 0.005:
		_frame.border_color = Color("ff6b6b").lerp(Color(0.45, 0.80, 1.0, 0.36), 0.45 * (1.0 - pulse))
	else:
		_frame.border_color = Color(0.45, 0.80, 1.0, 0.38)
	draw_style_box(_frame, Rect2(Vector2.ZERO, size))

	var pad_x: float = 6.0
	var pad_y: float = 5.0
	var inner_w: float = size.x - pad_x * 2.0 - SKEW
	var inner_h: float = size.y - pad_y * 2.0
	if inner_w <= 8.0 or inner_h <= 4.0:
		return
	var cell_w: float = (inner_w - GAP * float(CELLS - 1)) / float(CELLS)
	if cell_w <= 1.0:
		return

	var filled_cells: float = ratio * float(CELLS)
	var lead_idx: int = clampi(int(ceilf(filled_cells)) - 1, -1, CELLS - 1)
	var wave_pos: float = fposmod(_surge_time * 12.0, float(CELLS) + 2.5) - 1.25

	for index in CELLS:
		var t: float = float(index) / float(CELLS - 1)
		var x0: float = pad_x + float(index) * (cell_w + GAP)
		var y0: float = pad_y
		var slot_pts: PackedVector2Array = _slanted_points(x0, y0, cell_w, inner_h, SKEW)
		draw_colored_polygon(slot_pts, SLOT_BG)
		draw_polyline(_closed_points(slot_pts), SLOT_RIM, 1.2, true)

		var amount: float = clampf(filled_cells - float(index), 0.0, 1.0)
		if amount <= 0.002:
			continue

		var fill: Color
		if boosting:
			fill = GOLD_START.lerp(GOLD_END, t)
			if not reduce:
				var surge: float = maxf(0.0, 1.0 - absf(float(index) - wave_pos) * 0.55)
				fill = fill.lerp(Color.WHITE, surge * 0.42)
		elif low:
			fill = LOW_START.lerp(LOW_END, t)
		else:
			fill = CYAN_START.lerp(CYAN_MID, clampf(t * 1.5, 0.0, 1.0))
			if t > 0.5:
				fill = fill.lerp(CYAN_END, (t - 0.5) * 2.0)

		var lit_w: float = cell_w * amount
		var lit_pts: PackedVector2Array = _slanted_points(x0, y0, lit_w, inner_h, SKEW)
		draw_colored_polygon(lit_pts, fill)

		# Crisp inner specular shine across the top of each lit slanted cell.
		var shine_pts: PackedVector2Array = _slanted_points(
			x0 + SKEW * 0.62, y0 + 1.0, maxf(lit_w - 1.2, 0.5),
			maxf(inner_h * 0.36, 2.2), SKEW * 0.34)
		draw_colored_polygon(shine_pts, Color(1.0, 1.0, 1.0, 0.38 if boosting else 0.26))

		# Bright spark edge on the leading active cell.
		if index == lead_idx and lit_w >= 2.2:
			var spark_w: float = minf(2.4, lit_w * 0.45)
			var spark_pts: PackedVector2Array = _slanted_points(
				x0 + lit_w - spark_w, y0 + 0.8, spark_w, maxf(inner_h - 1.6, 2.0), SKEW * 0.88)
			draw_colored_polygon(spark_pts, Color(1.0, 1.0, 1.0, 0.82))


func _slanted_points(x: float, y: float, w: float, h: float,
		skew_px: float = SKEW) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(x + skew_px, y),
		Vector2(x + skew_px + w, y),
		Vector2(x + w, y + h),
		Vector2(x, y + h),
	])


func _closed_points(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	if not out.is_empty():
		out.append(out[0])
	return out
