extends Button
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## Chunky outlined Steam-arcade candy button: thick dark border, coloured fill,
## crisp inner rim, top-half glossy specular band, bottom bevel shade, and hard
## drop shadow.
##
## A pill never grows to fit a long label: the authored width is the cap and the
## label shrinks its font inside it (UiKit.fit_button).

@export var fill_color: Color = Color("45b6f0"):
	set(value):
		fill_color = value
		if is_node_ready():
			_apply_styles()
@export var shadow_offset: int = 8 ## Vertical offset of the hard shadow in px.
@export var corner_radius: int = 16 ## Shared rounded-square radius.

@export_group("Hover Scale")
@export var hover_scale: float = 1.03 ## Static scale while hovered.
@export var focus_scale: float = 1.015 ## Static scale while focused (not hovered).
@export var press_scale: float = 0.96 ## Squash while the button is held.

const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const MIN_LABEL_FONT: int = 13 ## Floor for the shrink-to-fit label ramp.

var _gloss := StyleBoxFlat.new()
var _inner_rim := StyleBoxFlat.new()
var _bevel_shade := StyleBoxFlat.new()
var _hovered: bool = false
var _held: bool = false
var _scale_now: float = 1.0
var _last_fit_width: float = -1.0


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	_gloss.bg_color = Color(1, 1, 1, 0.22)
	_gloss.anti_aliasing = true
	_inner_rim.draw_center = false
	_inner_rim.bg_color = Color(0, 0, 0, 0)
	_inner_rim.set_border_width_all(2)
	_inner_rim.border_color = Color(1, 1, 1, 0.30)
	_inner_rim.anti_aliasing = true
	_bevel_shade.bg_color = Color(0.05, 0.04, 0.14, 0.16)
	_bevel_shade.anti_aliasing = true
	_apply_styles()
	_update_pivot()
	resized.connect(_on_resized)
	mouse_entered.connect(_set_hovered.bind(true))
	mouse_exited.connect(_set_hovered.bind(false))
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	button_down.connect(_set_held.bind(true))
	button_up.connect(_set_held.bind(false))
	fit_text()


func _on_resized() -> void:
	_update_pivot()
	queue_redraw()
	if size.x > 0.0 and not is_equal_approx(size.x, _last_fit_width):
		_last_fit_width = size.x
		fit_text()


func fit_text(max_width: float = -1.0, min_font: int = MIN_LABEL_FONT) -> void:
	## Shrink the label into the pill instead of letting the pill widen.
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
	z_index = 1 if active or _held else 0
	var target_scale: float = 1.0
	if not disabled:
		if _held:
			target_scale = press_scale
		elif _hovered:
			target_scale = hover_scale
		elif focused:
			target_scale = focus_scale
	_scale_now = UiAnim.damp(_scale_now, target_scale, delta, 18.0)
	if absf(_scale_now - target_scale) < 0.0005:
		_scale_now = target_scale
	scale = Vector2.ONE * _scale_now
	rotation = 0.0


func _set_hovered(value: bool) -> void:
	_hovered = value
	queue_redraw()


func _set_held(value: bool) -> void:
	_held = value
	queue_redraw()


func _update_pivot() -> void:
	pivot_offset = size * 0.5


func _draw() -> void:
	if size.x < 20.0 or size.y < 18.0:
		return
	var active: bool = (_hovered or has_focus()) and not disabled
	var inner_rect := Rect2(6.0, 6.0, size.x - 12.0, size.y - 12.0)

	# Subtle bottom inner lip bevel for chunky arcade button depth.
	if not _held and inner_rect.size.y > 16.0:
		var lip_h: float = clampf(inner_rect.size.y * 0.20, 4.0, 10.0)
		draw_style_box(_bevel_shade, Rect2(inner_rect.position.x + 2.0,
			inner_rect.end.y - lip_h, inner_rect.size.x - 4.0, lip_h))

	# Top-half glossy inner specular highlight band.
	var gloss_alpha: float = 0.10 if disabled else (0.14 if _held else (0.27 if active else 0.22))
	_gloss.bg_color = Color(1.0, 1.0, 1.0, gloss_alpha)
	var gloss_inset: float = 10.0
	var gloss_h: float = clampf((size.y - 14.0) * 0.38, 6.0, 26.0)
	if size.x > gloss_inset * 2.0 + 6.0:
		draw_style_box(_gloss, Rect2(gloss_inset, 7.0, size.x - gloss_inset * 2.0, gloss_h))

	# Crisp inner highlight rim inside the dark outline.
	_inner_rim.border_color = Color(1.0, 1.0, 1.0, 0.14 if disabled else (0.44 if active else 0.28))
	draw_style_box(_inner_rim, inner_rect)


func _apply_styles() -> void:
	var inner_r: int = maxi(corner_radius - 5, 4)
	_gloss.corner_radius_top_left = inner_r
	_gloss.corner_radius_top_right = inner_r
	_gloss.corner_radius_bottom_left = maxi(inner_r - 4, 3)
	_gloss.corner_radius_bottom_right = maxi(inner_r - 4, 3)
	_inner_rim.set_corner_radius_all(inner_r)
	_bevel_shade.corner_radius_top_left = 2
	_bevel_shade.corner_radius_top_right = 2
	_bevel_shade.corner_radius_bottom_left = inner_r
	_bevel_shade.corner_radius_bottom_right = inner_r
	add_theme_stylebox_override("normal", _make(fill_color, shadow_offset))
	add_theme_stylebox_override("hover", _make(fill_color.lightened(0.13), shadow_offset + 2))
	add_theme_stylebox_override("pressed", _make(fill_color.darkened(0.10), maxi(shadow_offset - 5, 2)))
	add_theme_stylebox_override("disabled", _make(Color("9a94b4"), 4))
	var kit: Node = get_node_or_null("/root/UiKit")
	if kit != null and kit.has_method("apply_focus_ring"):
		kit.call("apply_focus_ring", self, corner_radius)
	queue_redraw()


func _make(color: Color, drop: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(corner_radius)
	box.set_border_width_all(6)
	box.border_color = UiPalette.OUTLINE
	box.shadow_color = Color(0.08, 0.06, 0.18, 0.52)
	box.shadow_size = 2
	box.shadow_offset = Vector2(0, drop)
	box.content_margin_left = 26
	box.content_margin_right = 26
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	box.anti_aliasing = true
	return box
