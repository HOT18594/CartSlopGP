extends Control
## Full-bleed static cover-cropped menu artwork slideshow with smooth crossfades,
## soft dim tint, and a subtle cinematic edge vignette.
##
## Drawn directly via `_draw()` (`draw_texture_rect`, `position = Vector2.ZERO`)
## with zero pan/zoom wobble and zero particle noise so menu artwork stays
## rock-steady and pixel-crisp.

const ART_DIR: String = "res://assets/ui/art/"

@export var texture_names: PackedStringArray = PackedStringArray()
@export var slide_seconds: float = 9.0
@export var fade_seconds: float = 1.4
@export var dim: float = 0.14 ## Extra darkening over the art, 0..1.
@export var enable_overlay: bool = true

var _textures: Array[Texture2D] = []
var _current_index: int = 0
var _next_index: int = -1
var _fade_progress: float = 0.0
var _fading: bool = false
var _timer: float = 0.0
var _last_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	position = Vector2.ZERO
	_load_textures()
	resized.connect(queue_redraw)
	_fit()
	queue_redraw()


func _load_textures() -> void:
	_textures.clear()
	for file_name: String in texture_names:
		var path: String = ART_DIR + file_name
		if ResourceLoader.exists(path):
			var texture: Texture2D = load(path) as Texture2D
			if texture != null:
				_textures.append(texture)


func _is_reduce_motion() -> bool:
	var gs: Node = get_node_or_null("/root/GameSettings")
	if gs != null:
		return bool(gs.get("reduce_motion"))
	return false


func _fit() -> void:
	var parent: Control = get_parent() as Control
	if parent == null:
		return
	var target: Vector2 = parent.size
	if target.x <= 0.0 or target.y <= 0.0:
		return
	_last_size = target
	size = target
	position = Vector2.ZERO
	queue_redraw()


func has_art() -> bool:
	return not _textures.is_empty()


func show_still(index: int) -> void:
	if _textures.is_empty():
		return
	_current_index = clampi(index, 0, _textures.size() - 1)
	_next_index = -1
	_fade_progress = 0.0
	_fading = false
	_timer = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	var parent: Control = get_parent() as Control
	if parent != null and (absf(parent.size.x - _last_size.x) > 0.5
			or absf(parent.size.y - _last_size.y) > 0.5):
		_fit()
	if _fading:
		_fade_progress += delta / maxf(fade_seconds, 0.05)
		if _fade_progress >= 1.0:
			_current_index = _next_index
			_next_index = -1
			_fade_progress = 0.0
			_fading = false
		queue_redraw()
		return
	if _textures.size() < 2 or _is_reduce_motion():
		return
	_timer += delta
	if _timer >= slide_seconds:
		_timer = 0.0
		_next_index = (_current_index + 1) % _textures.size()
		_fade_progress = 0.0
		_fading = true
		queue_redraw()


func _draw() -> void:
	var area: Vector2 = size
	if _textures.is_empty() or area.x < 4.0 or area.y < 4.0:
		return
	var cur: int = clampi(_current_index, 0, _textures.size() - 1)
	_draw_cover(_textures[cur], area, 1.0)
	if _fading and _next_index >= 0 and _next_index < _textures.size():
		var alpha: float = smoothstep(0.0, 1.0, clampf(_fade_progress, 0.0, 1.0))
		_draw_cover(_textures[_next_index], area, alpha)
	if dim > 0.0:
		draw_rect(Rect2(Vector2.ZERO, area), Color(0.04, 0.05, 0.14, clampf(dim, 0.0, 1.0)))
	if enable_overlay:
		_draw_vignette(area)


func _draw_cover(tex: Texture2D, area: Vector2, alpha: float) -> void:
	if tex == null or alpha <= 0.001:
		return
	var src: Vector2 = tex.get_size()
	if src.x <= 0.0 or src.y <= 0.0:
		return
	var cover_scale: float = maxf(area.x / src.x, area.y / src.y)
	var drawn: Vector2 = (src * cover_scale).round()
	var origin: Vector2 = ((area - drawn) * 0.5).round()
	draw_texture_rect(tex, Rect2(origin, drawn), false, Color(1.0, 1.0, 1.0, alpha))


func _draw_vignette(area: Vector2) -> void:
	if area.x < 8.0 or area.y < 8.0:
		return
	# Subtle top vignette band for crisp title & header contrast.
	var top_h: float = area.y * 0.20
	var top_bands: int = 16
	var top_step: float = top_h / float(top_bands)
	for b in top_bands:
		var frac: float = 1.0 - (float(b) + 0.5) / float(top_bands)
		var alpha: float = 0.28 * frac * frac
		draw_rect(Rect2(0.0, float(b) * top_step, area.x, top_step + 1.0),
			Color(0.03, 0.04, 0.12, alpha))

	# Subtle bottom vignette band for grounded button & footer contrast.
	var bot_h: float = area.y * 0.24
	var bot_y0: float = area.y - bot_h
	var bot_bands: int = 18
	var bot_step: float = bot_h / float(bot_bands)
	for b in bot_bands:
		var frac: float = (float(b) + 0.5) / float(bot_bands)
		var alpha: float = 0.34 * frac * frac
		draw_rect(Rect2(0.0, bot_y0 + float(b) * bot_step, area.x, bot_step + 1.0),
			Color(0.03, 0.04, 0.12, alpha))

	# Gentle side-edge darkening to frame foreground cards cleanly.
	var side_w: float = area.x * 0.12
	var side_bands: int = 10
	var side_step: float = side_w / float(side_bands)
	for b in side_bands:
		var frac: float = 1.0 - (float(b) + 0.5) / float(side_bands)
		var alpha: float = 0.18 * frac * frac
		var col := Color(0.03, 0.04, 0.12, alpha)
		draw_rect(Rect2(float(b) * side_step, 0.0, side_step + 1.0, area.y), col)
		draw_rect(Rect2(area.x - (float(b) + 1.0) * side_step, 0.0, side_step + 1.0, area.y), col)
