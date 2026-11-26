class_name ToggleSwitch
extends Control
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## Tactile arcade switch used by Settings: slanted dark-glass OFF track, glowing
## emerald ON track with crisp inner rim, smooth damped thumb slide, and soft
## layered thumb shadow. The track and its focus halo carry the shared 0.14
## skew so the toggle matches the black-slanted parallelogram theme.

signal toggled(on: bool)

const UiPalette := preload("res://scripts/ui/ui_palette.gd")

const INK := UiPalette.INK
const TRACK_OFF := UiPalette.SURFACE_CHIP
const TRACK_ON := Color("3ed65c")
const KNOB := UiPalette.CREAM
const RING := UiPalette.YELLOW
const SKEW: float = 0.14 ## Same slant as the button family.

var on: bool = false:
	set(value):
		on = value
		if not is_inside_tree() or _is_reduce_motion():
			_pos = 1.0 if on else 0.0
		queue_redraw()
var _pos: float = 0.0
var _hovered: bool = false
var _held: bool = false
var _track := StyleBoxFlat.new()
var _inner_glow := StyleBoxFlat.new()
var _ring := StyleBoxFlat.new()


func _ready() -> void:
	custom_minimum_size = Vector2(72, 36)
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_filter = Control.MOUSE_FILTER_STOP
	_pos = 1.0 if on else 0.0

	_track.set_border_width_all(2)
	_track.border_color = INK
	_track.skew = Vector2(SKEW, 0.0)
	_track.anti_aliasing = true

	_inner_glow.draw_center = false
	_inner_glow.set_border_width_all(2)
	_inner_glow.skew = Vector2(SKEW, 0.0)
	_inner_glow.anti_aliasing = true

	_ring.draw_center = false
	_ring.bg_color = Color(0, 0, 0, 0)
	_ring.border_color = RING
	_ring.set_border_width_all(3)
	_ring.skew = Vector2(SKEW, 0.0)
	_ring.shadow_color = Color(0.06, 0.05, 0.14, 0.65)
	_ring.shadow_size = 3
	_ring.expand_margin_left = 3.0
	_ring.expand_margin_top = 3.0
	_ring.expand_margin_right = 3.0
	_ring.expand_margin_bottom = 3.0
	_ring.anti_aliasing = true

	mouse_entered.connect(func() -> void:
		_hovered = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hovered = false
		_held = false
		queue_redraw())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _is_reduce_motion() -> bool:
	var gs: Node = get_node_or_null("/root/GameSettings")
	return bool(gs.get("reduce_motion")) if gs != null else false


func _process(delta: float) -> void:
	var target: float = 1.0 if on else 0.0
	if is_equal_approx(_pos, target):
		return
	if _is_reduce_motion():
		_pos = target
	else:
		_pos = UiAnim.damp(_pos, target, delta, 18.0)
		if absf(_pos - target) < 0.004:
			_pos = target
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.button_index == MOUSE_BUTTON_LEFT:
			_held = click.pressed
			queue_redraw()
			if click.pressed:
				_flip()
				accept_event()
		return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		_flip()
		accept_event()
		return
	if event.is_action_pressed("ui_accept"):
		_flip()
		accept_event()
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_SPACE:
			_flip()
			accept_event()


func _flip() -> void:
	on = not on
	toggled.emit(on)


func _draw() -> void:
	var radius: float = size.y * 0.5
	var base_track: Color = TRACK_OFF.lerp(TRACK_ON, _pos)
	if _hovered or has_focus():
		base_track = base_track.lightened(0.08)
	_track.bg_color = base_track
	_track.shadow_color = Color(0.24, 0.90, 0.42, 0.32 * _pos)
	_track.shadow_size = int(round(5.0 * _pos))
	_track.set_corner_radius_all(int(radius))
	draw_style_box(_track, Rect2(Vector2.ZERO, size))

	# Crisp inner glow / bevel rim inside the capsule track.
	_inner_glow.border_color = Color(0.75, 1.0, 0.80, 0.42) if _pos > 0.5 \
		else Color(1.0, 1.0, 1.0, 0.10)
	_inner_glow.set_corner_radius_all(maxi(int(radius) - 2, 4))
	draw_style_box(_inner_glow, Rect2(2.0, 2.0, size.x - 4.0, size.y - 4.0))

	# Smooth thumb shadow + crisp bordered knob + specular highlight.
	var knob_radius: float = radius - 4.5 + (0.8 if _held else 0.0)
	var knob_x: float = lerpf(radius, size.x - radius, _pos)
	var knob_center := Vector2(knob_x, radius)
	draw_circle(knob_center + Vector2(0.0, 2.4), knob_radius + 1.0, Color(0.05, 0.04, 0.14, 0.34))
	draw_circle(knob_center + Vector2(0.0, 1.2), knob_radius + 0.4, Color(0.05, 0.04, 0.14, 0.22))
	draw_circle(knob_center, knob_radius + 1.6, INK)
	draw_circle(knob_center, knob_radius, KNOB)
	draw_circle(knob_center + Vector2(-knob_radius * 0.24, -knob_radius * 0.26),
		maxf(knob_radius * 0.34, 2.0), Color(1.0, 1.0, 1.0, 0.75))

	if has_focus():
		_ring.set_corner_radius_all(int(radius) + 4)
		draw_style_box(_ring, Rect2(Vector2.ZERO, size))
