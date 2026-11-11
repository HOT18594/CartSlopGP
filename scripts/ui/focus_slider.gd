extends HSlider
## Settings slider with keyboard/gamepad focus. Left/right (or the d-pad)
## change the value in place while the slider is focused; a yellow ring matches
## the rest of the menu. The stock grabber is a translucent dot, so these are
## drawn opaque to read clearly on the cream settings panel. Mouse-wheel value
## changes stay disabled: scrolling over a slider must never move it.

const OUTLINE: Color = Color("1e1b3a")
const FILL: Color = Color("fff6e3")
const FILL_HOVER: Color = Color("ffd22e")
const FILL_DISABLED: Color = Color("cfc9da")
const RING: Color = Color("ffd22e")

static var _grabber_cache: Dictionary = {}

var _ring := StyleBoxFlat.new()


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	scrollable = false
	add_theme_icon_override("grabber", _grabber(OUTLINE, FILL))
	add_theme_icon_override("grabber_highlight", _grabber(OUTLINE, FILL_HOVER))
	add_theme_icon_override("grabber_disabled", _grabber(Color("5a5870"), FILL_DISABLED))
	_ring.draw_center = false
	_ring.bg_color = Color(0, 0, 0, 0)
	_ring.border_color = RING
	_ring.set_border_width_all(3)
	_ring.set_corner_radius_all(9)
	_ring.expand_margin_left = 3.0
	_ring.expand_margin_top = 3.0
	_ring.expand_margin_right = 3.0
	_ring.expand_margin_bottom = 3.0
	_ring.anti_aliasing = true
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _draw() -> void:
	if not has_focus():
		return
	var rect := Rect2(Vector2.ZERO, size)
	_ring.set_corner_radius_all(maxi(int(size.y * 0.5), 6))
	draw_style_box(_ring, rect)


func _grabber(ring: Color, fill: Color) -> ImageTexture:
	var key: String = ring.to_html() + fill.to_html()
	if _grabber_cache.has(key):
		return _grabber_cache[key]
	# Draw at 4x and downsample, so the circle has a clean anti-aliased edge
	# while every interior pixel stays fully opaque.
	const SCALE: int = 4
	const SIZE: int = 28
	var pixels: int = SIZE * SCALE
	var image: Image = Image.create(pixels, pixels, false, Image.FORMAT_RGBA8)
	var centre: Vector2 = Vector2(pixels, pixels) * 0.5
	var outer_radius: float = float(pixels) * 0.5
	var inner_radius: float = outer_radius - 3.0 * float(SCALE)
	for y in pixels:
		for x in pixels:
			var distance: float = Vector2(x + 0.5, y + 0.5).distance_to(centre)
			if distance <= inner_radius:
				image.set_pixel(x, y, fill)
			elif distance <= outer_radius:
				image.set_pixel(x, y, ring)
	image.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_grabber_cache[key] = texture
	return texture
