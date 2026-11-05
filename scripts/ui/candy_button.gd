extends Button
## Chunky outlined candy button: thick dark border, coloured fill, hard drop
## shadow and white outlined text (font comes from the theme).

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
@export var press_scale: float = 0.97 ## Squash while the button is held.

var _gloss := StyleBoxFlat.new()
var _hovered: bool = false
var _held: bool = false
var _time: float = 0.0


func _ready() -> void:
	_gloss.bg_color = Color(1, 1, 1, 0.22)
	_gloss.corner_radius_top_left = 20
	_gloss.corner_radius_top_right = 20
	_gloss.corner_radius_bottom_left = 14
	_gloss.corner_radius_bottom_right = 14
	_apply_styles()
	_update_pivot()
	resized.connect(_update_pivot)
	mouse_entered.connect(_set_hovered.bind(true))
	mouse_exited.connect(_set_hovered.bind(false))
	button_down.connect(_set_held.bind(true))
	button_up.connect(_set_held.bind(false))


func _process(delta: float) -> void:
	# A bouncy idle while hovered or keyboard-focused; smooth so entering and
	# leaving feels springy rather than snappy.
	_time += delta
	# Bounce only for a real mouse hover. Keyboard focus keeps the theme's
	# focus ring but must not make PLAY wobble while the menu is idle.
	var active: bool = _hovered and not _held
	z_index = 1 if active or _held else 0
	var target_scale: float = press_scale if _held else 1.0
	var target_rotation: float = 0.0
	if active:
		target_scale = hover_scale + 0.012 * sin(_time * hover_speed * 2.0)
		target_rotation = deg_to_rad(hover_wobble_degrees) * sin(_time * hover_speed)
	var blend: float = 1.0 - exp(-16.0 * delta)
	scale = scale.lerp(Vector2.ONE * target_scale, blend)
	rotation = lerpf(rotation, target_rotation, blend)


func _set_hovered(value: bool) -> void:
	_hovered = value


func _set_held(value: bool) -> void:
	_held = value


func _update_pivot() -> void:
	pivot_offset = size * 0.5


func _draw() -> void:
	# Glossy sheen across the top half, like the candy buttons in the mockup.
	var inset: float = 14.0
	var height: float = size.y * 0.30
	draw_style_box(_gloss, Rect2(inset, 8.0, size.x - inset * 2.0, height))


func _apply_styles() -> void:
	add_theme_stylebox_override("normal", _make(fill_color, shadow_offset))
	add_theme_stylebox_override("hover", _make(fill_color.lightened(0.14), shadow_offset + 2))
	add_theme_stylebox_override("pressed", _make(fill_color.darkened(0.10), maxi(shadow_offset - 6, 2)))
	add_theme_stylebox_override("disabled", _make(Color("9a94b4"), 5))


func _make(color: Color, drop: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = corner_radius
	box.corner_radius_top_right = corner_radius
	box.corner_radius_bottom_left = corner_radius
	box.corner_radius_bottom_right = corner_radius
	box.border_width_left = 6
	box.border_width_top = 6
	box.border_width_right = 6
	box.border_width_bottom = 6
	box.border_color = Color("1e1b3a")
	box.shadow_color = Color(0.12, 0.1, 0.23, 0.5)
	box.shadow_size = 0
	box.shadow_offset = Vector2(0, drop)
	box.content_margin_left = 26
	box.content_margin_right = 26
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	box.anti_aliasing = true
	return box
