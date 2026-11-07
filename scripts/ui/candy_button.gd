extends Button
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## Chunky outlined candy button: thick dark border, coloured fill, hard drop
## shadow and white outlined text (font comes from the theme).
##
## Motion is shared with every other menu through UiAnim's frame-rate
## independent damping. Keyboard focus now gets the same springy treatment as
## a mouse hover (plus visible selector arrows), so arrow-key navigation reads
## clearly instead of looking like nothing happened.

@export var fill_color: Color = Color("45b6f0"):
	set(value):
		fill_color = value
		if is_node_ready():
			_apply_styles()
@export var shadow_offset: int = 9 ## Vertical offset of the hard shadow in px.
@export var corner_radius: int = 30

@export_group("Hover Wiggle")
@export var hover_scale: float = 1.045 ## Peak scale while hovered/focused.
@export var hover_wobble_degrees: float = 1.8 ## Side-to-side tilt.
@export var hover_speed: float = 3.6 ## Wiggle speed.
@export var press_scale: float = 0.96 ## Squash while the button is held.

const UiPalette := preload("res://scripts/ui/ui_palette.gd")

var _gloss := StyleBoxFlat.new()
var _hovered: bool = false
var _focused: bool = false
var _held: bool = false
var _time: float = 0.0
var _scale_now: float = 1.0
var _rotation_now: float = 0.0


func _ready() -> void:
	_gloss.bg_color = Color(1, 1, 1, 0.22)
	_gloss.set_corner_radius_all(20)
	_apply_styles()
	_update_pivot()
	resized.connect(_update_pivot)
	mouse_entered.connect(_set_hovered.bind(true))
	mouse_exited.connect(_set_hovered.bind(false))
	focus_entered.connect(_set_focused.bind(true))
	focus_exited.connect(_set_focused.bind(false))
	button_down.connect(_set_held.bind(true))
	button_up.connect(_set_held.bind(false))
	_focused = has_focus()


func _process(delta: float) -> void:
	_time += delta
	var active: bool = (_hovered or _focused) and not _held
	z_index = 1 if active or _held else 0
	var target_scale: float = press_scale if _held else 1.0
	var target_rotation: float = 0.0
	if active:
		# Focused buttons wobble a little less: a keyboard selection should feel
		# deliberate, not jittery while the player reads the screen.
		var energy: float = 1.0 if _hovered else 0.55
		target_scale = hover_scale + 0.012 * sin(_time * hover_speed * 2.0) * energy
		target_rotation = deg_to_rad(hover_wobble_degrees) \
			* sin(_time * hover_speed) * energy
	_scale_now = UiAnim.damp(_scale_now, target_scale, delta, 18.0)
	_rotation_now = UiAnim.damp(_rotation_now, target_rotation, delta, 15.0)
	scale = Vector2.ONE * _scale_now
	rotation = _rotation_now
	if _focused:
		queue_redraw()


func _set_hovered(value: bool) -> void:
	_hovered = value


func _set_focused(value: bool) -> void:
	_focused = value
	queue_redraw()


func _set_held(value: bool) -> void:
	_held = value


func _update_pivot() -> void:
	pivot_offset = size * 0.5


func _draw() -> void:
	# Glossy sheen across the top half, like the candy buttons in the mockup.
	var inset: float = 14.0
	var height: float = size.y * 0.30
	draw_style_box(_gloss, Rect2(inset, 8.0, size.x - inset * 2.0, height))
	if _focused:
		_draw_selectors()


func _draw_selectors() -> void:
	## Two inward chevrons mark the keyboard selection. They breathe slowly so
	## a static screenshot still shows which button the arrow keys are on.
	var pulse: float = 0.72 + 0.28 * sin(_time * 4.2)
	var color := Color(UiPalette.OUTLINE.r, UiPalette.OUTLINE.g, UiPalette.OUTLINE.b,
		0.55 + 0.35 * pulse)
	var mid: float = size.y * 0.5
	var reach: float = minf(size.y * 0.20, 14.0) * (0.9 + 0.1 * pulse)
	for side in [-1.0, 1.0]:
		var base_x: float = 16.0 if side < 0.0 else size.x - 16.0
		# Both chevrons must point INWARD (">  <"). The old sign made the left
		# arrow point left and the right arrow point right, reading as "< >".
		var points := PackedVector2Array([
			Vector2(base_x, mid - reach),
			Vector2(base_x - side * reach * 0.8, mid),
			Vector2(base_x, mid + reach),
		])
		draw_colored_polygon(points, color)


func _apply_styles() -> void:
	add_theme_stylebox_override("normal", _make(fill_color, shadow_offset))
	add_theme_stylebox_override("hover", _make(fill_color.lightened(0.14), shadow_offset + 2))
	add_theme_stylebox_override("pressed", _make(fill_color.darkened(0.10), maxi(shadow_offset - 6, 2)))
	add_theme_stylebox_override("disabled", _make(Color("9a94b4"), 5))


func _make(color: Color, drop: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(corner_radius)
	box.set_border_width_all(6)
	box.border_color = UiPalette.OUTLINE
	box.shadow_color = Color(0.12, 0.1, 0.23, 0.5)
	box.shadow_size = 0
	box.shadow_offset = Vector2(0, drop)
	box.content_margin_left = 26
	box.content_margin_right = 26
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	box.anti_aliasing = true
	return box
