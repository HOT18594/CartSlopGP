extends HSlider
## Tactile arcade settings slider: slanted dark recessed rail, glowing golden
## fill bar with top specular sheen, and a 4x-supersampled slanted pill grabber
## with grip ticks. Colours come from UiPalette and every plate carries the
## shared 0.10 skew so the control matches the black-slanted theme.
## Mouse-wheel value changes stay disabled so scrolling over a slider never moves it.

const UiPalette := preload("res://scripts/ui/ui_palette.gd")

const OUTLINE: Color = UiPalette.INK
const FILL: Color = UiPalette.CREAM
const FILL_HOVER: Color = UiPalette.YELLOW
const FILL_DISABLED: Color = Color("cfc9da")
const RING: Color = UiPalette.YELLOW
const SKEW: float = 0.10

static var _grabber_cache: Dictionary = {}

var _ring := StyleBoxFlat.new()
var _rail := StyleBoxFlat.new()
var _fill_normal := StyleBoxFlat.new()
var _fill_hover := StyleBoxFlat.new()
var _hovered: bool = false


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	scrollable = false
	add_theme_icon_override("grabber", _grabber(OUTLINE, FILL, false))
	add_theme_icon_override("grabber_highlight",
		_grabber(OUTLINE, UiPalette.CREAM.lightened(0.35), true))
	add_theme_icon_override("grabber_disabled", _grabber(Color("5a5870"), FILL_DISABLED, false))

	_rail.bg_color = Color(UiPalette.SURFACE_CHIP, 0.90)
	_rail.set_border_width_all(2)
	_rail.border_color = OUTLINE
	_rail.set_corner_radius_all(5)
	_rail.skew = Vector2(SKEW, 0.0)
	_rail.content_margin_top = 7.0
	_rail.content_margin_bottom = 7.0
	_rail.anti_aliasing = true

	_fill_normal.bg_color = UiPalette.YELLOW
	_fill_normal.set_border_width_all(2)
	_fill_normal.border_color = OUTLINE
	_fill_normal.set_corner_radius_all(5)
	_fill_normal.skew = Vector2(SKEW, 0.0)
	_fill_normal.content_margin_top = 7.0
	_fill_normal.content_margin_bottom = 7.0
	_fill_normal.shadow_color = Color(1.0, 0.78, 0.16, 0.34)
	_fill_normal.shadow_size = 4
	_fill_normal.anti_aliasing = true

	_fill_hover = _fill_normal.duplicate() as StyleBoxFlat
	_fill_hover.bg_color = FILL_HOVER.lightened(0.10)
	_fill_hover.shadow_color = Color(1.0, 0.84, 0.22, 0.56)
	_fill_hover.shadow_size = 6

	add_theme_stylebox_override("slider", _rail)
	add_theme_stylebox_override("grabber_area", _fill_normal)
	add_theme_stylebox_override("grabber_area_highlight", _fill_hover)

	_ring.draw_center = false
	_ring.bg_color = Color(0, 0, 0, 0)
	_ring.border_color = RING
	_ring.set_border_width_all(3)
	_ring.set_corner_radius_all(8)
	_ring.skew = Vector2(SKEW, 0.0)
	_ring.expand_margin_left = 3.0
	_ring.expand_margin_top = 3.0
	_ring.expand_margin_right = 3.0
	_ring.expand_margin_bottom = 3.0
	_ring.shadow_color = Color(0.06, 0.05, 0.14, 0.60)
	_ring.shadow_size = 3
	_ring.anti_aliasing = true

	mouse_entered.connect(func() -> void:
		_hovered = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hovered = false
		queue_redraw())
	value_changed.connect(func(_v: float) -> void: queue_redraw())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _draw() -> void:
	# Subtle top specular sheen along the active left portion of the rail.
	var span: float = maxf(max_value - min_value, 0.0001)
	var ratio_now: float = clampf((value - min_value) / span, 0.0, 1.0)
	var grab_x: float = 12.0 + ratio_now * maxf(size.x - 24.0, 0.0)
	if grab_x > 20.0 and size.y >= 14.0:
		var sheen_y: float = size.y * 0.5 - 4.5
		draw_line(Vector2(6.0, sheen_y), Vector2(grab_x - 13.0, sheen_y),
			Color(1.0, 1.0, 1.0, 0.45 if (_hovered or has_focus()) else 0.32), 2.0, true)

	if not has_focus():
		return
	var rect := Rect2(Vector2.ZERO, size)
	_ring.set_corner_radius_all(maxi(int(size.y * 0.5), 6))
	draw_style_box(_ring, rect)


func _grabber(ring: Color, fill: Color, lit: bool) -> ImageTexture:
	var key: String = ring.to_html() + fill.to_html() + ("_1" if lit else "_0")
	if _grabber_cache.has(key):
		return _grabber_cache[key]
	# 4x supersampled tactile pill grabber with drop shadow, crisp outline,
	# top gloss band, and subtle vertical grip ridges.
	const SCALE: int = 4
	const W: int = 24
	const H: int = 30
	var pw: int = W * SCALE
	var ph: int = H * SCALE
	var image: Image = Image.create(pw, ph, false, Image.FORMAT_RGBA8)
	var cx: float = float(pw) * 0.5
	var cy: float = float(ph) * 0.47
	var half_w: float = float(pw) * 0.40
	var half_h: float = float(ph) * 0.42
	var corner_r: float = float(pw) * 0.34
	var border_px: float = 2.8 * float(SCALE)
	var shadow_col := Color(0.06, 0.05, 0.14, 0.34)
	var gloss_col := fill.lightened(0.24 if lit else 0.16)
	var grip_col := ring.lightened(0.18)
	grip_col.a = 0.42

	for y in ph:
		for x in pw:
			var pt := Vector2(float(x) + 0.5, float(y) + 0.5)
			# Slant the pill with the same skew as the rail: undo the shear
			# before the SDF test so the grabber reads as a parallelogram.
			var local := Vector2(pt.x - SKEW * (pt.y - cy), pt.y)
			var sd: float = _pill_sdf(local - Vector2(cx, cy), half_w, half_h, corner_r)
			if sd <= -border_px:
				var col: Color = fill
				if pt.y < cy - half_h * 0.12:
					col = gloss_col
				var gx: float = absf(pt.x - cx)
				if absf(pt.y - cy) < half_h * 0.34 and (absf(gx - 2.2 * SCALE) < 0.9 * SCALE):
					col = col.lerp(ring, 0.28)
				image.set_pixel(x, y, col)
			elif sd <= 0.0:
				image.set_pixel(x, y, ring)
			else:
				var sd_shadow: float = _pill_sdf(pt - Vector2(cx, cy + 2.2 * SCALE),
					half_w, half_h, corner_r)
				if sd_shadow <= 0.0:
					image.set_pixel(x, y, shadow_col)

	image.resize(W, H, Image.INTERPOLATE_LANCZOS)
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_grabber_cache[key] = texture
	return texture


static func _pill_sdf(p: Vector2, hx: float, hy: float, r: float) -> float:
	var cr: float = minf(r, minf(hx, hy))
	var q := Vector2(absf(p.x) - (hx - cr), absf(p.y) - (hy - cr))
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - cr
