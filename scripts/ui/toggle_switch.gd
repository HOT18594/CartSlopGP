class_name ToggleSwitch
extends Control
## Compact modern switch used by Settings. Draws its own track and knob so it
## cannot inherit the oversized CheckButton padding or white candy text.
##
## Focusable from the keyboard/gamepad: Enter or Space flips it, and a yellow
## ring matches every other menu control. Styleboxes are cached, so `_draw()`
## does not allocate.

signal toggled(on: bool)

const INK := Color("1e1b3a")
const TRACK_OFF := Color("d8d2c4")
const TRACK_ON := Color("4fbf52")
const KNOB := Color("fff6e3")
const RING := Color("ffd22e")

var on: bool = false:
	set(value):
		on = value
		queue_redraw()
var _hovered: bool = false
var _held: bool = false
var _track := StyleBoxFlat.new()
var _ring := StyleBoxFlat.new()


func _ready() -> void:
	custom_minimum_size = Vector2(58, 30)
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_filter = Control.MOUSE_FILTER_STOP
	_track.set_border_width_all(2)
	_track.border_color = INK
	_track.anti_aliasing = true
	_ring.draw_center = false
	_ring.bg_color = Color(0, 0, 0, 0)
	_ring.border_color = RING
	_ring.set_border_width_all(3)
	_ring.shadow_color = Color(0.06, 0.05, 0.12, 0.6)
	_ring.shadow_size = 2
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
	if event.is_action_pressed("ui_accept"):
		_flip()
		accept_event()


func _flip() -> void:
	on = not on
	toggled.emit(on)


func _draw() -> void:
	var radius: float = size.y * 0.5
	_track.bg_color = TRACK_ON if on else TRACK_OFF
	if _hovered or has_focus():
		_track.bg_color = _track.bg_color.lightened(0.08)
	_track.set_corner_radius_all(int(radius))
	draw_style_box(_track, Rect2(Vector2.ZERO, size))
	var knob_radius: float = radius - 5.0
	if _held:
		knob_radius += 1.0
	var knob_x: float = size.x - radius if on else radius
	draw_circle(Vector2(knob_x, radius), knob_radius, KNOB)
	draw_arc(Vector2(knob_x, radius), knob_radius, 0.0, TAU, 24, INK, 1.5, true)
	if has_focus():
		_ring.set_corner_radius_all(int(radius) + 4)
		draw_style_box(_ring, Rect2(Vector2.ZERO, size))
