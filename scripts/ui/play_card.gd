extends Button
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## Large squareish PLAY card: a hand-drawn shopping-cart icon on top, the
## mode name underneath. One cart for SINGLE, two for MULTIPLAYER.
## Focus chevrons point inward (">  <") to match every other candy button.

const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const CartDrawing := preload("res://scripts/ui/cart_drawing.gd")
const DISPLAY_FONT := "res://assets/ui/fonts/LuckiestGuy-Regular.ttf"

@export var fill_color: Color = Color("ffd22e"):
	set(value):
		fill_color = value
		if is_node_ready():
			_apply_styles()
@export var label_text: String = "SINGLE"
@export var two_carts: bool = false

var _hovered: bool = false
var _focused: bool = false
var _held: bool = false
var _time: float = 0.0
var _scale_now: float = 1.0
var _rotation_now: float = 0.0
var _display: Font


func _ready() -> void:
	_display = load(DISPLAY_FONT)
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_styles()
	_update_pivot()
	resized.connect(_update_pivot)
	mouse_entered.connect(func() -> void: _hovered = true)
	mouse_exited.connect(func() -> void: _hovered = false)
	focus_entered.connect(func() -> void: _focused = true)
	focus_exited.connect(func() -> void: _focused = false)
	button_down.connect(func() -> void: _held = true)
	button_up.connect(func() -> void: _held = false)
	_focused = has_focus()


func _process(delta: float) -> void:
	_time += delta
	var active: bool = (_hovered or _focused) and not _held
	var target_scale: float = 0.97 if _held else (1.03 if active else 1.0)
	var target_rotation: float = deg_to_rad(1.2) * sin(_time * 3.0) if active else 0.0
	_scale_now = UiAnim.damp(_scale_now, target_scale, delta, 16.0)
	_rotation_now = UiAnim.damp(_rotation_now, target_rotation, delta, 14.0)
	scale = Vector2.ONE * _scale_now
	rotation = _rotation_now
	if _focused or active:
		queue_redraw()


func _update_pivot() -> void:
	pivot_offset = size * 0.5


func _draw() -> void:
	_draw_icon()
	_draw_label()
	if _focused:
		_draw_selectors()


func _draw_icon() -> void:
	var area: Vector2 = size
	var icon_bottom: float = area.y * 0.66
	var center_x: float = area.x * 0.5
	if two_carts:
		var s: float = area.y / 460.0
		var gap: float = area.x * 0.20
		_ground(Vector2(center_x - gap, icon_bottom), s)
		_ground(Vector2(center_x + gap, icon_bottom), s)
		CartDrawing.draw_cart(self, Vector2(center_x - gap, icon_bottom), s, false)
		CartDrawing.draw_cart(self, Vector2(center_x + gap, icon_bottom), s * 0.94, true)
	else:
		var s: float = area.y / 330.0
		_ground(Vector2(center_x, icon_bottom), s)
		CartDrawing.draw_cart(self, Vector2(center_x, icon_bottom), s, false)


func _ground(origin: Vector2, scale: float) -> void:
	draw_set_transform(origin + Vector2(0.0, 3.0 * scale), 0.0, Vector2(1.0, 0.28))
	draw_circle(Vector2.ZERO, 92.0 * scale, Color(0.1, 0.08, 0.2, 0.16))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_label() -> void:
	if _display == null:
		return
	var font_size: int = int(clampf(size.y * 0.115, 22.0, 34.0))
	var width: float = _display.get_string_size(label_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var x: float = (size.x - width) * 0.5
	var baseline: float = size.y * 0.88
	# Manual outline: five offset passes in cream, then the ink on top.
	for offset: Vector2 in [Vector2(-3, 0), Vector2(3, 0), Vector2(0, -3),
			Vector2(0, 3), Vector2(-2, -2), Vector2(2, 2)]:
		draw_string(_display, Vector2(x + offset.x, baseline + offset.y), label_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UiPalette.CREAM)
	draw_string(_display, Vector2(x, baseline), label_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UiPalette.INK)


func _draw_selectors() -> void:
	var pulse: float = 0.72 + 0.28 * sin(_time * 4.2)
	var color := Color(UiPalette.OUTLINE.r, UiPalette.OUTLINE.g, UiPalette.OUTLINE.b,
		0.55 + 0.35 * pulse)
	var mid: float = size.y * 0.5
	var reach: float = minf(size.y * 0.09, 20.0)
	for side in [-1.0, 1.0]:
		var base_x: float = 18.0 if side < 0.0 else size.x - 18.0
		var points := PackedVector2Array([
			Vector2(base_x, mid - reach),
			Vector2(base_x - side * reach * 0.8, mid),
			Vector2(base_x, mid + reach),
		])
		draw_colored_polygon(points, color)


func _apply_styles() -> void:
	add_theme_stylebox_override("normal", _make(fill_color, 9))
	add_theme_stylebox_override("hover", _make(fill_color.lightened(0.12), 11))
	add_theme_stylebox_override("pressed", _make(fill_color.darkened(0.10), 3))
	add_theme_stylebox_override("disabled", _make(Color("9a94b4"), 5))


func _make(color: Color, drop: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(30)
	box.set_border_width_all(6)
	box.border_color = UiPalette.OUTLINE
	box.shadow_color = Color(0.12, 0.1, 0.23, 0.5)
	box.shadow_size = 0
	box.shadow_offset = Vector2(0, drop)
	box.anti_aliasing = true
	return box
