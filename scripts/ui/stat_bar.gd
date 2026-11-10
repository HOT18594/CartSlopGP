extends Control
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## A 10-section comparison bar for the vehicle picker. No raw numbers: each
## stat is normalised against the best/worst value in the whole garage, so the
## blocks are a visual "how does this car stack up" instead of a spec sheet.
## The fill damps toward its target, so switching cars animates the bars.

const SEGMENTS: int = 10
const GAP: float = 5.0
const TRACK: Color = Color("e9e5f4")
const TRACK_EDGE: Color = Color("d3cee6")

@export var fill_color: Color = Color("45b6f0")
@export var bar_height: float = 18.0

var _target: float = 0.0
var _shown: float = 0.0
var _box := StyleBoxFlat.new()


func _ready() -> void:
	custom_minimum_size = Vector2(170, 22)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.set_corner_radius_all(6)
	_box.anti_aliasing = true


func set_ratio(value: float, immediate: bool = false) -> void:
	_target = clampf(value, 0.0, 1.0)
	if immediate:
		_shown = _target
	queue_redraw()


func _process(delta: float) -> void:
	if is_equal_approx(_shown, _target):
		return
	_shown = UiAnim.damp(_shown, _target, delta, 13.0)
	if absf(_shown - _target) < 0.001:
		_shown = _target
	queue_redraw()


func _draw() -> void:
	var height: float = clampf(bar_height, 8.0, size.y)
	var y: float = (size.y - height) * 0.5
	var width: float = (size.x - GAP * float(SEGMENTS - 1)) / float(SEGMENTS)
	if width <= 1.0:
		return
	var filled: float = _shown * float(SEGMENTS)
	for index in SEGMENTS:
		var amount: float = clampf(filled - float(index), 0.0, 1.0)
		var x: float = float(index) * (width + GAP)
		# Unfilled blocks stay light so the whole 10-section scale is readable.
		_box.bg_color = TRACK.lerp(fill_color, amount)
		_box.border_color = TRACK_EDGE if amount < 0.5 else fill_color.darkened(0.18)
		_box.set_border_width_all(2 if amount < 0.5 else 1)
		draw_style_box(_box, Rect2(x, y, width, height))
	# A soft leading glow on the last lit block.
	if filled > 0.5:
		var head: float = minf(filled, float(SEGMENTS))
		var head_x: float = (head - 1.0) * (width + GAP)
		draw_rect(Rect2(head_x + 2.0, y + 2.0, maxf(width - 4.0, 1.0), 3.0),
			Color(1, 1, 1, 0.35 * clampf(head - floorf(head) + 0.4, 0.0, 1.0)))
