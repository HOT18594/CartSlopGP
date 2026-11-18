extends Control
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## 10-segment slanted arcade power-cell comparison bar for the garage picker.
## Features dark recessed track slots, vibrant gradient-lit active segments,
## top specular sheen, and a glowing leading cell.

const UiPalette := preload("res://scripts/ui/ui_palette.gd")

const SEGMENTS: int = 10
const GAP: float = 4.5
const SKEW: float = 4.5
const TRACK_SLOT: Color = Color(0.12, 0.14, 0.22, 0.85)
const TRACK_RIM: Color = Color(0.06, 0.08, 0.14, 0.92)

@export var fill_color: Color = Color("45b6f0")
@export var bar_height: float = 18.0

var _target: float = 0.0
var _shown: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(170, 22)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func set_ratio(value: float, immediate: bool = false) -> void:
	_target = clampf(value, 0.0, 1.0)
	if immediate:
		_shown = _target
	queue_redraw()


func _process(delta: float) -> void:
	if is_equal_approx(_shown, _target):
		return
	_shown = UiAnim.damp(_shown, _target, delta, 13.0)
	if absf(_shown - _target) < 0.001:
		_shown = _target
	queue_redraw()


func _draw() -> void:
	var height: float = clampf(bar_height, 8.0, size.y - 2.0)
	var y: float = (size.y - height) * 0.5
	var usable_w: float = size.x - SKEW - 2.0
	var width: float = (usable_w - GAP * float(SEGMENTS - 1)) / float(SEGMENTS)
	if width <= 1.5:
		return
	var filled: float = _shown * float(SEGMENTS)
	var c_start: Color = fill_color.darkened(0.12)
	var c_end: Color = fill_color.lightened(0.20)
	var lead_index: int = clampi(int(ceilf(filled)) - 1, -1, SEGMENTS - 1)

	for index in SEGMENTS:
		var x: float = 1.0 + float(index) * (width + GAP)
		var slot_pts: PackedVector2Array = _cell_poly(x, y, width, height, SKEW)
		# Dark recessed track slot + crisp outline.
		draw_colored_polygon(slot_pts, TRACK_SLOT)
		draw_polyline(_closed_poly(slot_pts), TRACK_RIM, 1.4, true)

		var amount: float = clampf(filled - float(index), 0.0, 1.0)
		if amount <= 0.003:
			continue

		var t: float = float(index) / float(SEGMENTS - 1)
		var seg_col: Color = c_start.lerp(c_end, t)
		var lit_w: float = width * amount

		# Soft halo behind the leading active cell.
		if index == lead_index and filled > 0.12:
			var glow_pts: PackedVector2Array = _cell_poly(x - 1.5, y - 1.5,
				lit_w + 3.0, height + 3.0, SKEW)
			draw_colored_polygon(glow_pts,
				Color(c_end.r, c_end.g, c_end.b, 0.30))

		var active_pts: PackedVector2Array = _cell_poly(x, y, lit_w, height, SKEW)
		draw_colored_polygon(active_pts, seg_col)

		# Top specular sheen strip across the active power cell.
		if lit_w > 1.5 and height >= 8.0:
			var sheen_h: float = maxf(height * 0.34, 2.2)
			var sheen_pts: PackedVector2Array = _cell_poly(
				x + SKEW * 0.62, y + 1.2, maxf(lit_w - 1.5, 0.6), sheen_h, SKEW * 0.34)
			draw_colored_polygon(sheen_pts, Color(1.0, 1.0, 1.0, 0.36))

		draw_polyline(_closed_poly(active_pts), UiPalette.OUTLINE, 1.5, true)

		# Crisp bright leading edge spark on the frontier cell.
		if index == lead_index and lit_w >= 2.2:
			var spark_w: float = minf(2.6, lit_w * 0.45)
			var spark_pts: PackedVector2Array = _cell_poly(
				x + lit_w - spark_w, y + 1.0, spark_w, maxf(height - 2.0, 2.0), SKEW * 0.85)
			draw_colored_polygon(spark_pts, Color(1.0, 1.0, 1.0, 0.72))


func _cell_poly(x: float, y: float, w: float, h: float, skew_px: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(x + skew_px, y),
		Vector2(x + skew_px + w, y),
		Vector2(x + w, y + h),
		Vector2(x, y + h),
	])


func _closed_poly(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	if not out.is_empty():
		out.append(out[0])
	return out
