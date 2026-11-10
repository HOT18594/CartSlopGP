extends HSlider
## Menus are mouse/touch only, so sliders never take keyboard focus. The stock
## grabber is a translucent dot; these are drawn opaque so the handle reads
## clearly on the cream settings panel. Mouse-wheel value changes are disabled
## as well - scrolling over a slider should never move it by accident.

const OUTLINE: Color = Color("1e1b3a")
const FILL: Color = Color("fff6e3")
const FILL_HOVER: Color = Color("ffd22e")
const FILL_DISABLED: Color = Color("cfc9da")

static var _grabber_cache: Dictionary = {}


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	scrollable = false
	add_theme_icon_override("grabber", _grabber(OUTLINE, FILL))
	add_theme_icon_override("grabber_highlight", _grabber(OUTLINE, FILL_HOVER))
	add_theme_icon_override("grabber_disabled", _grabber(Color("5a5870"), FILL_DISABLED))


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
