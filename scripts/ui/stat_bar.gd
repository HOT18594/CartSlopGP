extends Control
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## 10-segment slanted arcade parallelogram stat bar for the garage picker.
## Mathematically centered horizontally & vertically with bold #1e1b3a ink
## outlines and a crisp hard comic drop shadow behind every slot.

const UiPalette := preload("res://scripts/ui/ui_palette.gd")

const SEGMENTS: int = 10
const GAP: float = 4.5
const SKEW: float = 4.5
const TRACK_SLOT: Color = Color(0.14, 0.16, 0.26, 0.90)
const SLOT_SHADOW: Color = Color(0.117647, 0.105882, 0.227451, 0.28)

@export var fill_color: Color = Color("45b6f0")
@export var bar_height: float = 16.0

var _target: float = 0.0
var _shown: float = 0.0


func _ready() -> void:
	if custom_minimum_size.x <= 0.0:
		custom_minimum_size.x = 256.0
	if custom_minimum_size.y <= 0.0:
		custom_minimum_size.y = 22.0
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
	var height: float = clampf(bar_height, 8.0, size.y - 5.0)
	var y: float = (size.y - height) * 0.5
	var max_span: float = size.x - 6.0
	var width: float = (max_span - SKEW - GAP * float(SEGMENTS - 1)) / float(SEGMENTS)
	if width <= 1.5:
		return
	var total_span: float = float(SEGMENTS) * width + float(SEGMENTS - 1) * GAP + SKEW
	var start_x: float = (size.x - total_span) * 0.5

	var filled: float = _shown * float(SEGMENTS)
	var c_start: Color = fill_color.darkened(0.10)
	var c_end: Color = fill_color.lightened(0.18)

	# Pass 1: Hard comic shadow (2.0, 2.5) behind every slot so the bar pops on cream.
	for index in SEGMENTS:
		var sx: float = start_x + float(index) * (width + GAP)
		var shadow_pts: PackedVector2Array = _cell_poly(sx + 2.0, y + 2.5, width, height, SKEW)
		draw_colored_polygon(shadow_pts, SLOT_SHADOW)

	# Pass 2: Recessed slots, active fills, top gloss, and bold 2.0px INK outlines.
	for index in SEGMENTS:
		var x: float = start_x + float(index) * (width + GAP)
		var slot_pts: PackedVector2Array = _cell_poly(x, y, width, height, SKEW)
		draw_colored_polygon(slot_pts, TRACK_SLOT)

		var amount: float = clampf(filled - float(index), 0.0, 1.0)
		if amount > 0.003:
			var t: float = float(index) / float(SEGMENTS - 1)
			var seg_col: Color = c_start.lerp(c_end, t)
			var lit_w: float = width * amount
			# Soft leading edge: a partial cell ramps out instead of ending on a
			# clipped vertical line (same treatment as the loading bar).
			var soft_w: float = minf(9.0, lit_w)
			var solid_w: float = maxf(lit_w - soft_w, 0.0)
			if solid_w > 0.5:
				var solid_pts: PackedVector2Array = _cell_poly(x, y, solid_w, height, SKEW)
				draw_colored_polygon(solid_pts, seg_col)
			if soft_w > 0.5:
				var lead_pts: PackedVector2Array = _cell_poly(
					x + solid_w, y, soft_w, height, SKEW)
				draw_polygon(lead_pts, PackedColorArray([
					seg_col, Color(seg_col.r, seg_col.g, seg_col.b, 0.0),
					Color(seg_col.r, seg_col.g, seg_col.b, 0.0), seg_col,
				]))

			if lit_w > 1.5 and height >= 8.0:
				var sheen_h: float = maxf(height * 0.36, 2.2)
				var sheen_pts: PackedVector2Array = _cell_poly(
					x + SKEW * 0.62, y + 1.2, maxf(lit_w - 1.5, 0.6), sheen_h, SKEW * 0.34)
				UiAnim.draw_vertical_fade(self, sheen_pts, Color.WHITE, 0.38)

		draw_polyline(_closed_poly(slot_pts), UiPalette.INK, 2.0, true)


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
