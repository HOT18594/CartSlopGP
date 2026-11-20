extends Control
## Slop-Slash 10-cell standalone skewed parallelogram boost meter.
## Zero outer frame box: every cell is an independent comic-inked power slash
## with a hard offset shadow, vibrant cyan/gold/hot-pink fill, and white sheen.

const UiPalette := preload("res://scripts/ui/ui_palette.gd")

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
const GAP: float = 4.5
const SKEW: float = 8.0
const INK_BORDER: float = 2.5
const SHADOW_OFFSET := Vector2(3.0, 4.0)
const SHADOW_COLOR := Color(0.07, 0.05, 0.15, 0.88)
const EMPTY_FILL := Color(0.118, 0.106, 0.227, 0.90)

var _surge_time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	var pad_left: float = 2.0
	var pad_right: float = 5.0
	var pad_top: float = 2.0
	var pad_bottom: float = 5.5
	var inner_w: float = size.x - pad_left - pad_right - SKEW
	var inner_h: float = size.y - pad_top - pad_bottom
	if inner_w <= 12.0 or inner_h <= 4.0:
		return
	var cell_w: float = (inner_w - GAP * float(CELLS - 1)) / float(CELLS)
	if cell_w <= 1.5:
		return

	var low: bool = ratio <= 0.16 and not boosting
	var reduce: bool = _is_reduce_motion()
	var pulse: float = 1.0 if reduce else (0.5 + 0.5 * sin(_surge_time * 10.0))
	var filled_cells: float = ratio * float(CELLS)
	var lead_idx: int = clampi(int(ceilf(filled_cells)) - 1, -1, CELLS - 1)
	var wave_pos: float = fposmod(_surge_time * 14.0, float(CELLS) + 2.5) - 1.25

	# Pass 1: hard offset comic shadows for all 10 standalone cells.
	for index in CELLS:
		var x0: float = pad_left + float(index) * (cell_w + GAP)
		var shadow_pts: PackedVector2Array = _slanted_points(
			x0 + SHADOW_OFFSET.x, pad_top + SHADOW_OFFSET.y, cell_w, inner_h, SKEW)
		draw_colored_polygon(shadow_pts, SHADOW_COLOR)

	# Pass 2: cell bodies, vibrant active slashes, white top sheen, and ink borders.
	for index in CELLS:
		var t: float = float(index) / float(CELLS - 1)
		var x0: float = pad_left + float(index) * (cell_w + GAP)
		var y0: float = pad_top
		var slot_pts: PackedVector2Array = _slanted_points(x0, y0, cell_w, inner_h, SKEW)
		draw_colored_polygon(slot_pts, EMPTY_FILL)

		var amount: float = clampf(filled_cells - float(index), 0.0, 1.0)
		if amount > 0.002:
			var fill: Color = _cell_color(t, index, wave_pos, low, pulse, reduce)
			var lit_w: float = cell_w * amount
			var lit_pts: PackedVector2Array = _slanted_points(x0, y0, lit_w, inner_h, SKEW)
			draw_colored_polygon(lit_pts, fill)

			# Crisp comic white top sheen across each lit power cell.
			if lit_w > 1.6 and inner_h >= 7.0:
				var sheen_h: float = maxf(inner_h * 0.34, 2.4)
				var sheen_pts: PackedVector2Array = _slanted_points(
					x0 + SKEW * 0.64, y0 + 1.4, maxf(lit_w - 1.4, 0.6), sheen_h, SKEW * 0.34)
				draw_colored_polygon(sheen_pts, Color(1.0, 1.0, 1.0, 0.46 if boosting else 0.34))

			# Bright frontier spark slash on the leading active cell.
			if index == lead_idx and lit_w >= 2.4:
				var spark_w: float = minf(3.0, lit_w * 0.45)
				var spark_pts: PackedVector2Array = _slanted_points(
					x0 + lit_w - spark_w, y0 + 0.8, spark_w, maxf(inner_h - 1.6, 2.0), SKEW * 0.92)
				draw_colored_polygon(spark_pts, UiPalette.CREAM)

		var rim_col: Color = UiPalette.INK
		if boosting and amount > 0.5 and pulse > 0.58:
			rim_col = UiPalette.INK.lerp(UiPalette.CREAM, 0.35)
		draw_polyline(_closed_points(slot_pts), rim_col, INK_BORDER, true)


func _cell_color(t: float, index: int, wave_pos: float, low: bool,
		pulse: float, reduce: bool) -> Color:
	if boosting:
		var boost_col: Color = UiPalette.YELLOW.lerp(Color("ff3ec9"), clampf((t - 0.35) * 1.4, 0.0, 1.0))
		if not reduce:
			var surge: float = maxf(0.0, 1.0 - absf(float(index) - wave_pos) * 0.60)
			boost_col = boost_col.lerp(Color.WHITE, surge * 0.48)
		return boost_col
	if low:
		return Color("ff3b3f").lerp(UiPalette.PINK, 0.35 + 0.45 * pulse)
	if t < 0.55:
		return UiPalette.CYAN.lerp(Color("62f4ff"), t / 0.55)
	if t < 0.82:
		return Color("62f4ff").lerp(UiPalette.YELLOW, (t - 0.55) / 0.27)
	return UiPalette.YELLOW.lerp(UiPalette.PINK, (t - 0.82) / 0.18)


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
