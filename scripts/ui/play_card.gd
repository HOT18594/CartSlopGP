extends Button
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## Large hero PLAY card: diagonal shine band, soft radial glow behind the
## hand-drawn cart illustration on hover/focus, drop-shadowed pill badge, and
## bold outlined mode title underneath.

const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const CartDrawing := preload("res://scripts/ui/cart_drawing.gd")
const DISPLAY_FONT := "res://assets/ui/fonts/LuckiestGuy-Regular.ttf"

@export var fill_color: Color = Color("ffd22e"):
	set(value):
		fill_color = value
		if is_node_ready():
			_apply_styles()
@export var label_text: String = "SOLO"
@export var badge_text: String = ""
@export var two_carts: bool = false

var _hovered: bool = false
var _held: bool = false
var _scale_now: float = 1.0
var _glow_now: float = 0.0
var _display: Font
var _inner_rim := StyleBoxFlat.new()
var _top_gloss := StyleBoxFlat.new()
var _badge_style := StyleBoxFlat.new()


func _ready() -> void:
	_display = load(DISPLAY_FONT)
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	_inner_rim.draw_center = false
	_inner_rim.set_border_width_all(2)
	_inner_rim.set_corner_radius_all(24)
	_inner_rim.anti_aliasing = true
	_top_gloss.bg_color = Color(1, 1, 1, 0.22)
	_top_gloss.corner_radius_top_left = 22
	_top_gloss.corner_radius_top_right = 22
	_top_gloss.corner_radius_bottom_left = 8
	_top_gloss.corner_radius_bottom_right = 8
	_top_gloss.anti_aliasing = true
	_badge_style.bg_color = UiPalette.CREAM
	_badge_style.set_corner_radius_all(11)
	_badge_style.set_border_width_all(3)
	_badge_style.border_color = UiPalette.INK
	_badge_style.shadow_color = Color(0.08, 0.06, 0.18, 0.36)
	_badge_style.shadow_size = 2
	_badge_style.shadow_offset = Vector2(0, 3)
	_badge_style.anti_aliasing = true
	_apply_styles()
	focus_mode = Control.FOCUS_ALL
	_update_pivot()
	resized.connect(_on_resized)
	mouse_entered.connect(func() -> void:
		_hovered = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hovered = false
		queue_redraw())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	button_down.connect(func() -> void:
		_held = true
		queue_redraw())
	button_up.connect(func() -> void:
		_held = false
		queue_redraw())


func _on_resized() -> void:
	_update_pivot()
	queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var focused: bool = has_focus()
	var active: bool = (_hovered or focused) and not _held and not disabled
	if disabled:
		_held = false
	var target_scale: float = 1.0
	if not disabled:
		if _held:
			target_scale = 0.96
		elif _hovered:
			target_scale = 1.03
		elif focused:
			target_scale = 1.015
	var target_glow: float = 1.0 if active else 0.22
	_scale_now = UiAnim.damp(_scale_now, target_scale, delta, 18.0)
	if absf(_scale_now - target_scale) < 0.0005:
		_scale_now = target_scale
	var next_glow: float = UiAnim.damp(_glow_now, target_glow, delta, 12.0)
	if absf(next_glow - target_glow) < 0.001:
		next_glow = target_glow
	if not is_equal_approx(next_glow, _glow_now):
		_glow_now = next_glow
		queue_redraw()
	scale = Vector2.ONE * _scale_now
	rotation = 0.0


func _update_pivot() -> void:
	pivot_offset = size * 0.5


func _draw() -> void:
	if size.x < 40.0 or size.y < 40.0:
		return
	_draw_card_sheen()
	_draw_radial_glow()
	_draw_icon()
	_draw_badge()
	_draw_label()


func _draw_card_sheen() -> void:
	var active: bool = (_hovered or has_focus()) and not disabled
	# Top glossy band + inner rim inside the 6px outline.
	_top_gloss.bg_color = Color(1.0, 1.0, 1.0, 0.26 if active else 0.19)
	draw_style_box(_top_gloss, Rect2(14.0, 8.0, size.x - 28.0, size.y * 0.22))

	# Rich diagonal shine bands kept strictly within the card's safe interior.
	var pad: float = 20.0
	var x0: float = pad + size.x * 0.08
	var x1: float = x0 + size.x * 0.20
	var y_top: float = pad
	var y_bot: float = size.y - pad
	var skew: float = size.x * 0.22
	if x1 + skew < size.x - pad:
		var main_band := PackedVector2Array([
			Vector2(x0 + skew, y_top),
			Vector2(x1 + skew, y_top),
			Vector2(x1, y_bot),
			Vector2(x0, y_bot),
		])
		draw_colored_polygon(main_band, Color(1.0, 1.0, 1.0, 0.15 if active else 0.10))
		var thin_x0: float = x1 + 10.0
		var thin_x1: float = thin_x0 + size.x * 0.055
		if thin_x1 + skew < size.x - pad:
			var thin_band := PackedVector2Array([
				Vector2(thin_x0 + skew, y_top),
				Vector2(thin_x1 + skew, y_top),
				Vector2(thin_x1, y_bot),
				Vector2(thin_x0, y_bot),
			])
			draw_colored_polygon(thin_band, Color(1.0, 1.0, 1.0, 0.10 if active else 0.06))

	_inner_rim.border_color = Color(1.0, 1.0, 1.0, 0.44 if active else 0.28)
	draw_style_box(_inner_rim, Rect2(6.0, 6.0, size.x - 12.0, size.y - 12.0))


func _draw_radial_glow() -> void:
	if _glow_now <= 0.01:
		return
	var center := Vector2(size.x * 0.5, size.y * (0.42 if badge_text == "" else 0.46))
	var base_r: float = minf(size.x, size.y) * (0.28 + 0.08 * _glow_now)
	for ring in 4:
		var frac: float = 1.0 - float(ring) * 0.22
		var alpha: float = (0.09 + 0.16 * _glow_now) * (0.35 + 0.22 * float(ring))
		draw_circle(center, base_r * frac, Color(1.0, 0.99, 0.90, alpha))


func _draw_badge() -> void:
	if badge_text == "" or _display == null:
		return
	var font_size: int = 13
	var text_w: float = _display.get_string_size(badge_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var badge_w: float = text_w + 30.0
	var badge_h: float = 30.0
	var rect := Rect2(Vector2((size.x - badge_w) * 0.5, 16.0), Vector2(badge_w, badge_h))
	draw_style_box(_badge_style, rect)
	var ascent: float = _display.get_ascent(font_size)
	var descent: float = _display.get_descent(font_size)
	var baseline: float = rect.position.y + (badge_h + ascent - descent) * 0.5
	draw_string(_display, Vector2(rect.position.x, baseline),
		badge_text, HORIZONTAL_ALIGNMENT_CENTER, badge_w, font_size, UiPalette.INK)


func _draw_icon() -> void:
	var area: Vector2 = size
	var icon_bottom: float = area.y * (0.62 if badge_text == "" else 0.68)
	var center_x: float = area.x * 0.5
	if two_carts:
		var s: float = area.y / 460.0
		var gap: float = area.x * 0.20
		_ground(Vector2(center_x - gap, icon_bottom), s)
		_ground(Vector2(center_x + gap, icon_bottom), s)
		CartDrawing.draw_cart(self, Vector2(center_x - gap, icon_bottom), s, false)
		CartDrawing.draw_cart(self, Vector2(center_x + gap, icon_bottom), s * 0.94, true)
	else:
		var s: float = area.y / 335.0
		_ground(Vector2(center_x, icon_bottom), s)
		CartDrawing.draw_cart(self, Vector2(center_x, icon_bottom), s, false)


func _ground(origin: Vector2, cart_scale: float) -> void:
	draw_set_transform(origin + Vector2(0.0, 3.0 * cart_scale), 0.0, Vector2(1.0, 0.28))
	draw_circle(Vector2.ZERO, 94.0 * cart_scale, Color(0.1, 0.08, 0.2, 0.18))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_label() -> void:
	if _display == null:
		return
	var font_size: int = int(clampf(size.y * 0.115, 22.0, 34.0))
	var width: float = _display.get_string_size(label_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var x: float = (size.x - width) * 0.5
	var baseline: float = size.y * 0.88
	# Crisp soft shadow under outlined sticker text.
	draw_string(_display, Vector2(x, baseline + 5.0), label_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.08, 0.06, 0.18, 0.34))
	for offset: Vector2 in [Vector2(-3, 0), Vector2(3, 0), Vector2(0, -3),
			Vector2(0, 3), Vector2(-2, -2), Vector2(2, 2), Vector2(-2, 2), Vector2(2, -2)]:
		draw_string(_display, Vector2(x + offset.x, baseline + offset.y), label_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UiPalette.CREAM)
	draw_string(_display, Vector2(x, baseline), label_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UiPalette.INK)


func _apply_styles() -> void:
	add_theme_stylebox_override("normal", _make(fill_color, 10))
	add_theme_stylebox_override("hover", _make(fill_color.lightened(0.12), 12))
	add_theme_stylebox_override("pressed", _make(fill_color.darkened(0.10), 4))
	add_theme_stylebox_override("disabled", _make(Color("9a94b4"), 5))
	var kit: Node = get_node_or_null("/root/UiKit")
	if kit != null and kit.has_method("apply_focus_ring"):
		kit.call("apply_focus_ring", self, 30)
	queue_redraw()


func _make(color: Color, drop: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(30)
	box.set_border_width_all(6)
	box.border_color = UiPalette.OUTLINE
	box.shadow_color = Color(0.08, 0.06, 0.18, 0.54)
	box.shadow_size = 3
	box.shadow_offset = Vector2(0, drop)
	box.anti_aliasing = true
	return box
