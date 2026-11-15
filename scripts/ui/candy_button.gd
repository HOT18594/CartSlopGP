extends Button
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## Chunky outlined candy button: thick dark border, coloured fill, hard drop
## shadow and white outlined text (font comes from the theme).
##
## Motion is shared with every other menu through UiAnim's frame-rate
## independent damping. The button reacts to the mouse and to keyboard/gamepad
## focus: a focused pill keeps a small, deliberate wiggle so the player can see
## where Enter/Space will land, and UiKit paints the focus ring.
##
## A pill never grows to fit a long label: the authored width is the cap and the
## label shrinks its font inside it (UiKit.fit_button), so a rewritten label such
## as "SELECT MAP · ..." cannot push a button over the screen edge.

@export var fill_color: Color = Color("45b6f0"):
	set(value):
		fill_color = value
		if is_node_ready():
			_apply_styles()
@export var shadow_offset: int = 9 ## Vertical offset of the hard shadow in px.
@export var corner_radius: int = 16 ## One shared radius: rounded square, not a pill.

@export_group("Hover Wiggle")
@export var hover_scale: float = 1.03 ## Peak scale while hovered/focused.
@export var hover_wobble_degrees: float = 0.3 ## Side-to-side tilt.
@export var hover_speed: float = 3.6 ## Wiggle speed.
@export var press_scale: float = 0.96 ## Squash while the button is held.

const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const MIN_LABEL_FONT: int = 13 ## Floor for the shrink-to-fit label ramp.

var _gloss := StyleBoxFlat.new()
var _hovered: bool = false
var _held: bool = false
var _time: float = 0.0
var _scale_now: float = 1.0
var _rotation_now: float = 0.0


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	_gloss.bg_color = Color(1, 1, 1, 0.22)
	_gloss.set_corner_radius_all(maxi(corner_radius - 4, 4))
	_apply_styles()
	_update_pivot()
	resized.connect(_update_pivot)
	mouse_entered.connect(_set_hovered.bind(true))
	mouse_exited.connect(_set_hovered.bind(false))
	button_down.connect(_set_held.bind(true))
	button_up.connect(_set_held.bind(false))
	fit_text()


func fit_text(max_width: float = -1.0, min_font: int = MIN_LABEL_FONT) -> void:
	## Shrink the label into the pill instead of letting the pill widen.
	## Screens that rewrite `text` at runtime (a selected map name, a room code)
	## call this again; UiKit measures the real theme font, never a guess.
	if text.is_empty():
		return
	var kit: Node = get_node_or_null("/root/UiKit")
	if kit == null or not kit.has_method("fit_button"):
		return
	var cap: float = max_width
	if cap <= 0.0:
		cap = custom_minimum_size.x if custom_minimum_size.x > 0.0 else size.x
	if cap <= 0.0:
		return
	if not has_meta("kit_font_size"):
		set_meta("kit_font_size", maxi(get_theme_font_size("font_size"), 1))
	kit.call("fit_button", self, cap, min_font)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	var focused: bool = has_focus()
	var active: bool = (_hovered or focused) and not _held and not disabled
	if disabled:
		_held = false
	z_index = 1 if active or _held else 0
	var target_scale: float = press_scale if _held else 1.0
	var target_rotation: float = 0.0
	if active:
		# Focused buttons wobble a little less: a keyboard selection should feel
		# deliberate, not jittery while the player reads the screen.
		var energy: float = 1.0 if _hovered else 0.30
		target_scale = hover_scale + 0.004 * sin(_time * hover_speed * 2.0) * energy
		target_rotation = deg_to_rad(hover_wobble_degrees) \
			* sin(_time * hover_speed) * energy
	_scale_now = UiAnim.damp(_scale_now, target_scale, delta, 18.0)
	_rotation_now = UiAnim.damp(_rotation_now, target_rotation, delta, 15.0)
	scale = Vector2.ONE * _scale_now
	rotation = _rotation_now


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
	_gloss.set_corner_radius_all(maxi(corner_radius - 4, 4))
	add_theme_stylebox_override("normal", _make(fill_color, shadow_offset))
	add_theme_stylebox_override("hover", _make(fill_color.lightened(0.14), shadow_offset + 2))
	add_theme_stylebox_override("pressed", _make(fill_color.darkened(0.10), maxi(shadow_offset - 6, 2)))
	add_theme_stylebox_override("disabled", _make(Color("9a94b4"), 5))
	# The ring follows this button's authored corner radius, not UiKit's default.
	var kit: Node = get_node_or_null("/root/UiKit")
	if kit != null and kit.has_method("apply_focus_ring"):
		kit.call("apply_focus_ring", self, corner_radius)


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
