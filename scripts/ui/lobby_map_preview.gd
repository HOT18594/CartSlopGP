extends Control
## Black-slanted lobby map preview card with cheap, fluid 3D-style motion (WS3).
##
## 0.8.6 built the in-room preview from four stacked pieces: a raw TextureRect
## clipped by `parallelogram_clip.gdshader`, an unskewed gradient
## `_LobbyArtFallback` behind it, a separate skinned scrim PanelContainer and the
## mode chip on top. The seams showed — a missing screenshot revealed a plain
## rectangle, the clip had no plate/rim of its own and the block never quite
## matched the pause/settings shell. 0.8.7 replaces the whole stack with this one
## custom-drawn Control:
##
##   drop shadow -> dark-glass slanted plate -> textured slanted mask ->
##   top gloss band -> bottom readability scrim -> ink outline + cyan hairline
##   (+ accent edge / hover glow)
##
## Motion is deliberately subtle ("alive", not a screensaver): a slow horizontal
## card sway, an asymmetric breathing tilt of the top edge and a slow parallax
## drift of the source window. Because the mask is drawn as a four-corner quad
## with per-corner UVs, the tiny corner offsets read as a real perspective
## wobble rather than a flat image being squashed. Hover/focus adds a little
## extra tilt and an accent glow; changing map/mode kicks a short bump.
##
## Cost: ONE CanvasItem and ONE textured quad per repaint — no second Viewport,
## no 3D camera, no ShaderMaterial. Reduce Motion freezes the geometry (the
## static black-slanted card is still drawn) and keeps only the hover colour
## feedback. The module paints strictly inside its own rect, so the map title and
## mode chip (sibling controls above it) can never be clipped by the motion.

const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const UiAnim := preload("res://scripts/ui/ui_anim.gd")

## Slant of the whole card, as a fraction of its width (matches the 0.14 skew
## family of the button/banner styleboxes closely enough to read as one theme).
const SKEW_RATIO: float = 0.075
const SKEW_MIN: float = 8.0 ## px, keeps small previews visibly slanted.
const SKEW_MAX: float = 34.0
const FRAME_PAD: float = 5.0 ## px of breathing room for shadow/outline.
const OUTLINE_WIDTH: float = 4.0
const RIM_WIDTH: float = 1.6

## Motion envelope. Every value is a hard maximum: the audit harness asserts
## the live transform never exceeds these bounds.
const IDLE_SWAY_PX: float = 5.0 ## Horizontal card sway amplitude.
const IDLE_TILT_PX: float = 6.5 ## Asymmetric top-edge tilt amplitude.
const IDLE_SWAY_HZ: float = 0.11 ## Card sway cycles per second (slow).
const IDLE_TILT_HZ: float = 0.075 ## Breathing tilt cycles per second.
const PARALLAX_UV: float = 0.018 ## Source-window drift as a UV fraction.
const PARALLAX_ZOOM: float = 0.025 ## Slow breathing zoom inside the mask.
const HOVER_LIFT_PX: float = 3.5 ## Extra upward lift while hovered.
const HOVER_TILT_BOOST: float = 0.65 ## Hover multiplies the tilt by 1+this.
const HOVER_DAMP_SPEED: float = 9.0 ## Exponential damp for hover transitions.
const BUMP_TILT_PX: float = 4.0 ## One-shot kick when the map/mode changes.
const BUMP_DAMP: float = 5.5 ## Kick decay speed.
const SCRIM_BAND: float = 0.34 ## Bottom band kept dark behind the map title.
const FALLBACK_TOP: Color = Color(0.075, 0.09, 0.19, 1.0)

var _texture: Texture2D = null
var _accent: Color = UiPalette.GRASS
var _time: float = 0.0
var _phase: float = 0.0
var _hover_target: float = 0.0
var _hover: float = 0.0
var _bump: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_phase = 0.0
	resized.connect(queue_redraw)
	mouse_entered.connect(func() -> void: set_hover(true))
	mouse_exited.connect(func() -> void: set_hover(false))
	set_process(true)


func set_texture(texture: Texture2D) -> void:
	if texture != _texture:
		_bump = 1.0
	_texture = texture
	queue_redraw()


func get_preview_texture() -> Texture2D:
	return _texture


func set_accent(accent: Color) -> void:
	if not is_equal_approx(_accent.r, accent.r) \
			or not is_equal_approx(_accent.g, accent.g) \
			or not is_equal_approx(_accent.b, accent.b):
		_bump = 1.0
	_accent = accent
	queue_redraw()


func get_accent() -> Color:
	return _accent


func set_hover(active: bool) -> void:
	_hover_target = 1.0 if active else 0.0


func set_phase_radians(value: float) -> void:
	## Test hook: pin the idle phase so geometry samples are deterministic.
	_phase = value
	queue_redraw()


func is_reduce_motion() -> bool:
	var settings: Node = get_node_or_null("/root/GameSettings")
	return settings != null and bool(settings.get("reduce_motion"))


func motion_mix() -> float:
	return 0.0 if is_reduce_motion() else 1.0


func _process(delta: float) -> void:
	var visible_now: bool = is_visible_in_tree()
	if not visible_now:
		return
	var reduce: bool = is_reduce_motion()
	var mix: float = 0.0 if reduce else 1.0
	if mix > 0.0:
		_time += delta
	_hover = UiAnim.damp(_hover, _hover_target, delta, HOVER_DAMP_SPEED)
	_bump = UiAnim.damp(_bump, 0.0, delta, BUMP_DAMP)
	queue_redraw()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w < 32.0 or h < 24.0:
		return
	var quad: PackedVector2Array = frame_points()
	if quad.size() < 4:
		return
	var closed: PackedVector2Array = quad.duplicate()
	closed.append(quad[0])
	# 1. Soft dark shadow under the plate.
	var shadow := PackedVector2Array([
		quad[0] + Vector2(5.0, 8.0), quad[1] + Vector2(5.0, 8.0),
		quad[2] + Vector2(5.0, 8.0), quad[3] + Vector2(5.0, 8.0),
	])
	draw_colored_polygon(shadow, UiPalette.MODAL_SHADE)
	# 2. Dark-glass plate (the black slate the screenshot sits in).
	draw_colored_polygon(quad, UiPalette.SHELL_FILL)
	# 3. Textured slanted mask, or the slanted gradient fallback.
	if _texture != null:
		_draw_texture(quad)
	else:
		_draw_fallback(quad)
	# 4. Top glass highlight band, fading into the plate.
	var band_t: float = 0.30
	var band := PackedVector2Array([
		quad[0], quad[1],
		quad[1].lerp(quad[2], band_t), quad[0].lerp(quad[3], band_t),
	])
	UiAnim.draw_vertical_fade(self, band, Color.WHITE, 0.055)
	# 5. Bottom scrim band: keeps the map title readable on any screenshot.
	var scrim := PackedVector2Array([
		quad[0].lerp(quad[3], 1.0 - SCRIM_BAND),
		quad[1].lerp(quad[2], 1.0 - SCRIM_BAND),
		quad[2], quad[3],
	])
	draw_colored_polygon(scrim, Color(0.02, 0.03, 0.09, 0.74))
	# 6. Hover accent glow (colour feedback only under Reduce Motion).
	if _hover > 0.01:
		var glow: Color = _accent
		glow.a = 0.55 * _hover
		UiAnim.draw_soft_outline(self, closed, glow, 2.0, _accent, 3, 2.4,
			0.10 * _hover)
	# 7. Ink outline + inner cyan hairline: the shared shell signature.
	draw_polyline(closed, UiPalette.OUTLINE, OUTLINE_WIDTH, true)
	var inset := _inset_quad(quad, 3.0)
	var inset_closed: PackedVector2Array = inset.duplicate()
	inset_closed.append(inset[0])
	draw_polyline(inset_closed, UiPalette.SHELL_RIM, RIM_WIDTH, true)
	# 8. Accent edge along the bottom of the card.
	draw_line(quad[3], quad[2], Color(_accent.r, _accent.g, _accent.b, 0.85), 3.0,
		true)


func _draw_texture(quad: PackedVector2Array) -> void:
	var src: Vector2 = _texture.get_size()
	if src.x <= 0.0 or src.y <= 0.0:
		_draw_fallback(quad)
		return
	var base: PackedVector2Array = base_points()
	if base.size() < 4:
		return
	var pad: float = FRAME_PAD
	var bw: float = size.x - pad * 2.0 - slant_px()
	var bh: float = size.y - pad * 2.0
	var card_aspect: float = maxf(bw, 1.0) / maxf(bh, 1.0)
	var tex_aspect: float = src.x / src.y
	var mix: float = motion_mix()
	var zoom: float = 1.0 + (0.02 + PARALLAX_ZOOM) * mix \
		* sin(_time * 0.55 + _phase)
	var uv_w: float = (1.0 / zoom) * minf(card_aspect / tex_aspect, 1.0)
	var uv_h: float = (1.0 / zoom) * minf(tex_aspect / card_aspect, 1.0)
	var drift: float = mix * PARALLAX_UV
	var u0: float = clampf(0.5 - uv_w * 0.5 + sin(_time * 0.31 + _phase) * drift,
		0.0, maxf(1.0 - uv_w, 0.0))
	var v0: float = clampf(0.5 - uv_h * 0.5 + cos(_time * 0.24 + _phase * 1.3)
		* drift * 0.7, 0.0, maxf(1.0 - uv_h, 0.0))
	var uvs := PackedVector2Array([
		Vector2(u0, v0),
		Vector2(u0 + uv_w, v0),
		Vector2(u0 + uv_w, v0 + uv_h),
		Vector2(u0, v0 + uv_h),
	])
	var white := Color(1.0, 1.0, 1.0, 1.0)
	draw_polygon(quad, PackedColorArray([white, white, white, white]), uvs,
		_texture)


func _draw_fallback(quad: PackedVector2Array) -> void:
	## Slanted gradient fallback (no screenshot available): vertical bands drawn
	## between the slanted edges, so a missing texture never shows a rectangle.
	var top: Color = FALLBACK_TOP
	var bottom: Color = _accent.darkened(0.52)
	var bands: int = 9
	for band in bands:
		var t0: float = float(band) / float(bands)
		var t1: float = float(band + 1) / float(bands)
		var c0: Color = top.lerp(bottom, t0)
		var c1: Color = top.lerp(bottom, t1)
		draw_polygon(PackedVector2Array([
			quad[0].lerp(quad[3], t0), quad[1].lerp(quad[2], t0),
			quad[1].lerp(quad[2], t1), quad[0].lerp(quad[3], t1),
		]), PackedColorArray([c0, c0, c1, c1]))
	# Three inset slanted rings read as a procedural "no art yet" map motif.
	for ring in 3:
		var factor: float = 0.16 + float(ring) * 0.17
		var inner: PackedVector2Array = _inset_quad(quad, 0.0, factor, 1.0)
		var closed: PackedVector2Array = inner.duplicate()
		closed.append(inner[0])
		draw_polyline(closed, Color(_accent.r, _accent.g, _accent.b,
			0.13 + float(ring) * 0.10), 2.0, true)


func _inset_quad(quad: PackedVector2Array, inset_px: float,
		scale_x: float = 1.0, scale_y: float = 1.0) -> PackedVector2Array:
	## Shrink the quad toward its centre by px (and optional per-axis scale).
	var center: Vector2 = (quad[0] + quad[1] + quad[2] + quad[3]) * 0.25
	var out := PackedVector2Array()
	for point: Vector2 in quad:
		var direction: Vector2 = point - center
		var length: float = direction.length()
		var shrink: float = inset_px
		if length > 0.001:
			direction = direction / length * maxf(length * scale_x - shrink, 0.0)
			if not is_equal_approx(scale_y, 1.0):
				direction.y *= scale_y
		out.append(center + direction)
	return out


# --------------------------------------------------------------------------
# geometry (public for audit/tests)
# --------------------------------------------------------------------------


func slant_px() -> float:
	## Horizontal offset between a top and a bottom corner of the plate.
	var pad: float = FRAME_PAD
	var w: float = maxf(size.x - pad * 2.0, 1.0)
	return clampf(w * SKEW_RATIO, SKEW_MIN, SKEW_MAX)


func base_points() -> PackedVector2Array:
	## The undistorted slanted plate: TL, TR, BR, BL (top edge shifted right).
	var w: float = size.x
	var h: float = size.y
	if w < 32.0 or h < 24.0:
		return PackedVector2Array()
	var pad: float = FRAME_PAD
	var sk: float = clampf((w - pad * 2.0) * SKEW_RATIO, SKEW_MIN, SKEW_MAX)
	var bw: float = maxf(w - pad * 2.0 - sk, 8.0)
	var bh: float = maxf(h - pad * 2.0, 8.0)
	var x0: float = pad
	var y0: float = pad
	return PackedVector2Array([
		Vector2(x0 + sk, y0),
		Vector2(x0 + sk + bw, y0),
		Vector2(x0 + bw, y0 + bh),
		Vector2(x0, y0 + bh),
	])


func frame_points() -> PackedVector2Array:
	## The live, animated plate used for drawing. Bounded by motion_bounds().
	var base: PackedVector2Array = base_points()
	if base.size() < 4:
		return PackedVector2Array()
	var mix: float = motion_mix()
	var hover: float = _hover * mix
	var sway: float = sin(_time * IDLE_SWAY_HZ * TAU + _phase) * IDLE_SWAY_PX \
		* mix
	var tilt: float = (sin(_time * IDLE_TILT_HZ * TAU + _phase * 1.37)
		* IDLE_TILT_PX + _bump * BUMP_TILT_PX) * mix
	tilt *= 1.0 + HOVER_TILT_BOOST * hover
	var lift: float = hover * HOVER_LIFT_PX * mix
	var out: PackedVector2Array = base.duplicate()
	out[0] += Vector2(sway, tilt - lift)
	out[1] += Vector2(sway * 0.55, -tilt * 0.75 - lift)
	out[2] += Vector2(-sway * 0.30, -lift * 0.4)
	out[3] += Vector2(-sway, -lift * 0.2)
	return out


func motion_info() -> Dictionary:
	return {
		"time": _time,
		"phase": _phase,
		"hover": _hover,
		"bump": _bump,
		"motion_mix": motion_mix(),
		"sway_px": sin(_time * IDLE_SWAY_HZ * TAU + _phase) * IDLE_SWAY_PX \
			* motion_mix(),
		"tilt_px": (sin(_time * IDLE_TILT_HZ * TAU + _phase * 1.37)
			* IDLE_TILT_PX + _bump * BUMP_TILT_PX) * motion_mix(),
	}


func motion_bounds() -> Dictionary:
	## Hard limits the live geometry must never exceed (audit assertion).
	return {
		"max_sway_px": IDLE_SWAY_PX * 1.05,
		"max_tilt_px": IDLE_TILT_PX * (1.0 + HOVER_TILT_BOOST) \
			+ BUMP_TILT_PX,
		"max_lift_px": HOVER_LIFT_PX,
		"parallax_uv": PARALLAX_UV,
	}


func content_bounds() -> Rect2:
	## Everything the card paints stays inside this (local) rect.
	return Rect2(Vector2(-2.0, -2.0), size + Vector2(12.0, 14.0))


func title_band_rect() -> Rect2:
	## Bottom band kept dark so the sibling map-title label stays readable.
	var pad: float = FRAME_PAD
	var band_h: float = maxf(size.y * SCRIM_BAND, 8.0)
	return Rect2(pad, maxf(size.y - pad - band_h, pad), maxf(size.x - pad * 2.0,
		1.0), band_h)
