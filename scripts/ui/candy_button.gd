extends Button
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## Unified Slanted Parallelogram Racing-Sim / Arcade Button.
## Draws a crisp skewed parallelogram plate with bold comic ink outline,
## hard drop shadow, top glossy slant band, optional left color wedge,
## animated diagonal sheen sweep on hover, and a matching SLANTED PARALLELOGRAM
## focus outline (never a mismatched rounded rectangle!).

@export var fill_color: Color = Color("45b6f0"):
	set(value):
		fill_color = value
		if is_node_ready():
			_apply_styles()
@export var shadow_offset: int = 6 ## Vertical offset of the hard shadow in px.
@export var corner_radius: int = 16 ## Kept for scene property compatibility.
@export var skew_px: float = 12.0 ## Horizontal parallelogram slant in px.
@export var slash_accent: Color = Color(0.0, 0.0, 0.0, 0.0) ## Optional angled left color bar.

@export_group("Hover Scale")
@export var hover_scale: float = 1.035 ## Static scale while hovered.
@export var focus_scale: float = 1.02 ## Static scale while focused (not hovered).
@export var press_scale: float = 0.96 ## Squash while the button is held.

const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const MIN_LABEL_FONT: int = 13 ## Floor for the shrink-to-fit label ramp.

var _hovered: bool = false
var _held: bool = false
var _hover_t: float = 0.0
var _scale_now: float = 1.0
var _last_fit_width: float = -1.0
var _shine_t: float = 2.0


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	clip_contents = false
	set_meta("custom_focus", true)
	_apply_styles()
	_update_pivot()
	resized.connect(_on_resized)
	mouse_entered.connect(_set_hovered.bind(true))
	mouse_exited.connect(_set_hovered.bind(false))
	focus_entered.connect(_on_focus.bind(true))
	focus_exited.connect(_on_focus.bind(false))
	button_down.connect(_set_held.bind(true))
	button_up.connect(_set_held.bind(false))
	fit_text()


func _on_focus(on: bool) -> void:
	if on and not disabled:
		_shine_t = -0.35
	queue_redraw()


func _on_resized() -> void:
	_update_pivot()
	queue_redraw()
	if size.x > 0.0 and not is_equal_approx(size.x, _last_fit_width):
		_last_fit_width = size.x
		fit_text()


func fit_text(max_width: float = -1.0, min_font: int = MIN_LABEL_FONT) -> void:
	if text.is_empty():
		return
	var kit: Node = get_node_or_null("/root/UiKit")
	if kit == null or not kit.has_method("fit_button"):
		return
	var cap: float = max_width
	if cap <= 0.0:
		cap = size.x if size.x > 0.0 else custom_minimum_size.x
	if cap <= 0.0:
		return
	if not has_meta("kit_font_size"):
		set_meta("kit_font_size", maxi(get_theme_font_size("font_size"), 1))
	kit.call("fit_button", self, cap, min_font)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var focused: bool = has_focus()
	var active: bool = (_hovered or focused) and not _held and not disabled
	if disabled:
		_held = false
	z_index = 2 if active or _held else 0
	var target_h: float = 1.0 if active else 0.0
	_hover_t = UiAnim.damp(_hover_t, target_h, delta, 18.0)
	var target_scale: float = 1.0
	if not disabled:
		if _held:
			target_scale = press_scale
		elif _hovered:
			target_scale = hover_scale
		elif focused:
			target_scale = focus_scale
	_scale_now = UiAnim.damp(_scale_now, target_scale, delta, 20.0)
	if absf(_scale_now - target_scale) < 0.0005:
		_scale_now = target_scale
	scale = Vector2.ONE * _scale_now
	rotation = 0.0
	if _shine_t < 1.5:
		_shine_t += delta * 2.7
		queue_redraw()
	elif absf(_hover_t - target_h) > 0.004:
		queue_redraw()


func _set_hovered(value: bool) -> void:
	_hovered = value
	if value and not disabled:
		_shine_t = -0.35
	queue_redraw()


func _set_held(value: bool) -> void:
	_held = value
	queue_redraw()


func _update_pivot() -> void:
	pivot_offset = size * 0.5


func _para(x0: float, y0: float, w: float, h: float, sk: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(x0 + sk, y0),
		Vector2(x0 + sk + w, y0),
		Vector2(x0 + w, y0 + h),
		Vector2(x0, y0 + h),
	])


func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	if not out.is_empty():
		out.append(out[0])
	return out


func _draw() -> void:
	if size.x < 16.0 or size.y < 14.0:
		return
	var focused: bool = has_focus() and not disabled
	var active: bool = (_hovered or focused) and not disabled
	var sk: float = minf(skew_px, size.x * 0.22)
	var pad_x: float = 3.0
	var pad_t: float = 2.0
	var drop_y: float = 2.0 if _held else float(clampi(shadow_offset, 3, 7))
	var bw: float = maxf(size.x - sk - pad_x * 2.0 - 3.0, 8.0)
	var bh: float = maxf(size.y - pad_t - drop_y - 2.0, 8.0)
	var x0: float = pad_x
	var y0: float = pad_t + (2.0 if _held else 0.0)

	var pts: PackedVector2Array = _para(x0, y0, bw, bh, sk)

	# 1. Hard comic drop shadow parallelogram
	var sh_off := Vector2(3.5 if not _held else 1.5, drop_y)
	var sh := PackedVector2Array([
		pts[0] + sh_off, pts[1] + sh_off, pts[2] + sh_off, pts[3] + sh_off,
	])
	draw_colored_polygon(sh, Color(0.04, 0.03, 0.12, 0.62))

	# 2. Outer glowing slanted parallelogram focus halo (matches button slant 100%!)
	if focused:
		var halo: PackedVector2Array = _para(x0 - 3.5, y0 - 3.0, bw + 7.0, bh + 6.0, sk)
		var ring_col: Color = Color.WHITE if fill_color.get_luminance() > 0.60 else UiPalette.YELLOW
		# Soft multi-pass glow (no hard clipped polyline edge in the halo).
		UiAnim.draw_soft_outline(self, _closed(halo),
			Color(0.05, 0.04, 0.14, 0.85), 7.5, Color(0.05, 0.04, 0.14), 3, 1.6, 0.18)
		UiAnim.draw_soft_outline(self, _closed(halo), ring_col, 3.6,
			ring_col, 4, 2.2, 0.16)

	# 3. Main slanted plate fill
	var col: Color = fill_color
	if disabled:
		col = Color("5c6078")
	elif _held:
		col = fill_color.darkened(0.10)
	elif active:
		col = fill_color.lightened(0.12)
	draw_colored_polygon(pts, col)

	# 4. Subtle top highlight sheen + bottom lip bevel (clean, zero side-bar clutter)
	# Both are vertical alpha fades now, so they dissolve into the plate instead
	# of ending on a hard horizontal line.
	var gloss_h: float = bh * 0.34
	var gloss: PackedVector2Array = _para(x0 + sk * 0.66 + 1.5, y0 + 1.5, bw - 3.0, gloss_h, sk * 0.34)
	UiAnim.draw_vertical_fade(self, gloss, Color.WHITE,
		0.10 if disabled else (0.22 if active else 0.14))
	if not _held and bh > 20.0:
		var lip_h: float = clampf(bh * 0.14, 3.0, 6.0)
		var lip: PackedVector2Array = _para(x0 + 1.5, y0 + bh - lip_h - 1.0, bw - 3.0, lip_h, sk * (lip_h / bh))
		UiAnim.draw_vertical_fade(self, lip, Color(0.04, 0.03, 0.12), 0.16)

	# 5. Animated diagonal gloss sweep across the parallelogram on hover
	if _shine_t >= -0.35 and _shine_t <= 1.35 and not disabled:
		var sx: float = lerpf(x0 - 24.0, x0 + bw + 24.0, _shine_t)
		var sw: float = clampf(bw * 0.16, 16.0, 38.0)
		var x_tl: float = clampf(sx + sk, x0 + sk, x0 + sk + bw)
		var x_tr: float = clampf(sx + sk + sw, x0 + sk, x0 + sk + bw)
		var x_br: float = clampf(sx + sw, x0, x0 + bw)
		var x_bl: float = clampf(sx, x0, x0 + bw)
		if x_tr > x_tl + 2.0 and x_br > x_bl + 2.0:
			UiAnim.draw_soft_band(self, PackedVector2Array([
				Vector2(x_tl, y0 + 2.0),
				Vector2(x_tr, y0 + 2.0),
				Vector2(x_br, y0 + bh - 2.0),
				Vector2(x_bl, y0 + bh - 2.0),
			]), Color.WHITE, 0.26)

	# 6. Crisp inner rim highlight + bold ink outer border
	var inner_pts: PackedVector2Array = _para(x0 + 2.5, y0 + 2.5, maxf(bw - 5.0, 4.0), maxf(bh - 5.0, 4.0), sk * 0.88)
	draw_polyline(_closed(inner_pts), Color(1.0, 1.0, 1.0, 0.14 if disabled else (0.38 if active else 0.20)), 1.6, true)
	draw_polyline(_closed(pts), UiPalette.INK, 3.8, true)

	# 7. Crisp centered label text with generous horizontal breathing room (zero overflow!)
	if not text.is_empty():
		var font: Font = get_theme_font("font")
		if font != null:
			var fsz: int = maxi(get_theme_font_size("font_size"), 14)
			var pad_l: float = sk * 0.5 + 10.0
			var max_w: float = maxf(bw - 20.0, 12.0)
			# Auto-shrink slightly if a label would otherwise overflow the slanted interior
			while fsz > 12 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x > max_w:
				fsz -= 1
			var dark_fill: bool = col.get_luminance() < 0.34
			var txt_col: Color = Color(0.84, 0.86, 0.94, 0.72) if disabled \
				else (UiPalette.CREAM if dark_fill else UiPalette.INK)
			var ascent: float = font.get_ascent(fsz)
			var descent: float = font.get_descent(fsz)
			var baseline_y: float = y0 + (bh + ascent - descent) * 0.5
			if dark_fill and not disabled:
				draw_string(font, Vector2(x0 + pad_l, baseline_y + 2.0), text,
					alignment, max_w, fsz, Color(0.03, 0.03, 0.10, 0.85))
			draw_string(font, Vector2(x0 + pad_l, baseline_y), text,
				alignment, max_w, fsz, txt_col)


func _apply_styles() -> void:
	var pad_box := StyleBoxEmpty.new()
	var h_pad: float = maxf(skew_px + 12.0, 22.0)
	pad_box.content_margin_left = h_pad
	pad_box.content_margin_right = h_pad
	pad_box.content_margin_top = 8.0
	pad_box.content_margin_bottom = 12.0
	for st: String in ["normal", "hover", "pressed", "disabled"]:
		add_theme_stylebox_override(st, pad_box)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# Built-in Button text is suppressed; _draw() renders crisp text above the plate.
	var clear := Color(0.0, 0.0, 0.0, 0.0)
	add_theme_color_override("font_color", clear)
	add_theme_color_override("font_hover_color", clear)
	add_theme_color_override("font_focus_color", clear)
	add_theme_color_override("font_pressed_color", clear)
	add_theme_color_override("font_disabled_color", clear)
	queue_redraw()
