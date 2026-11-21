extends Control
## Full-bleed static cover-cropped menu artwork slideshow with smooth crossfades,
## soft dim tint, and a subtle cinematic edge vignette.
##
## Drawn directly via `_draw()` (`draw_texture_rect`, `position = Vector2.ZERO`)
## with zero pan/zoom wobble and zero particle noise so menu artwork stays
## rock-steady and pixel-crisp.

const ART_DIR: String = "res://assets/ui/art/"

@export var texture_names: PackedStringArray = PackedStringArray()
@export var slide_seconds: float = 8.5
@export var fade_seconds: float = 1.15
@export var dim: float = 0.10 ## Extra darkening over the art, 0..1.
@export var left_scrim: float = 0.44 ## Left-rail racing-sim contrast gradient.
@export var enable_overlay: bool = true
@export var enable_ken_burns: bool = true

var _textures: Array[Texture2D] = []
var _names: Array[String] = []
var _current_index: int = 0
var _next_index: int = -1
var _fade_progress: float = 0.0
var _fading: bool = false
var _timer: float = 0.0
var _drift_time: float = 0.0
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
	_names.clear()
	for file_name: String in texture_names:
		var path: String = ART_DIR + file_name
		if ResourceLoader.exists(path):
			var texture: Texture2D = load(path) as Texture2D
			if texture != null:
				_textures.append(texture)
				_names.append(file_name)


func crossfade_to(file_name: String) -> void:
	## Smoothly transition the full-bleed backdrop to a specific key-art slide.
	var idx: int = _names.find(file_name)
	if idx < 0:
		var path: String = ART_DIR + file_name
		if ResourceLoader.exists(path):
			var tex: Texture2D = load(path) as Texture2D
			if tex != null:
				_textures.append(tex)
				_names.append(file_name)
				idx = _textures.size() - 1
	if idx < 0:
		return
	if idx == _current_index and not _fading:
		_timer = 0.0
		return
	if _fading and idx == _next_index:
		return
	_next_index = idx
	_fade_progress = 0.0
	_fading = true
	_timer = 0.0
	queue_redraw()


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
	var reduced: bool = _is_reduce_motion()
	if enable_ken_burns and not reduced and not _textures.is_empty():
		_drift_time += delta
		queue_redraw()
	if _fading:
		_fade_progress += delta / maxf(fade_seconds, 0.05)
		if _fade_progress >= 1.0:
			_current_index = _next_index
			_next_index = -1
			_fade_progress = 0.0
			_fading = false
		queue_redraw()
		return
	if _textures.size() < 2 or reduced:
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
	_draw_cover(_textures[cur], area, 1.0, float(cur) * 1.7)
	if _fading and _next_index >= 0 and _next_index < _textures.size():
		var alpha: float = smoothstep(0.0, 1.0, clampf(_fade_progress, 0.0, 1.0))
		_draw_cover(_textures[_next_index], area, alpha, float(_next_index) * 1.7)
	if dim > 0.0:
		draw_rect(Rect2(Vector2.ZERO, area), Color(0.04, 0.05, 0.14, clampf(dim, 0.0, 1.0)))
	if enable_overlay:
		_draw_vignette(area)


func _draw_cover(tex: Texture2D, area: Vector2, alpha: float, phase: float = 0.0) -> void:
	if tex == null or alpha <= 0.001:
		return
	var src: Vector2 = tex.get_size()
	if src.x <= 0.0 or src.y <= 0.0:
		return
	var zoom: float = 1.0
	var pan := Vector2.ZERO
	if enable_ken_burns and not _is_reduce_motion():
		zoom = 1.028 + 0.018 * sin(_drift_time * 0.24 + phase)
		pan = Vector2(
			sin(_drift_time * 0.17 + phase) * area.x * 0.012,
			cos(_drift_time * 0.13 + phase) * area.y * 0.008
		)
	var cover_scale: float = maxf(area.x / src.x, area.y / src.y) * zoom
	var drawn: Vector2 = src * cover_scale
	var origin: Vector2 = (area - drawn) * 0.5 + pan
	draw_texture_rect(tex, Rect2(origin, drawn), false, Color(1.0, 1.0, 1.0, alpha))


func _draw_vignette(area: Vector2) -> void:
	if area.x < 8.0 or area.y < 8.0:
		return
	# Racing-sim left-side gradient scrim for effortless navigation rail contrast.
	if left_scrim > 0.01:
		var scrim_w: float = area.x * 0.44
		var bands: int = 24
		var step: float = scrim_w / float(bands)
		for b in bands:
			var frac: float = 1.0 - (float(b) + 0.5) / float(bands)
			var a: float = left_scrim * frac * frac
			draw_rect(Rect2(float(b) * step, 0.0, step + 1.5, area.y),
				Color(0.045, 0.050, 0.125, a))

	# Subtle top vignette band for crisp title & header contrast.
	var top_h: float = area.y * 0.22
	var top_bands: int = 16
	var top_step: float = top_h / float(top_bands)
	for b in top_bands:
		var frac: float = 1.0 - (float(b) + 0.5) / float(top_bands)
		var alpha: float = 0.36 * frac * frac
		draw_rect(Rect2(0.0, float(b) * top_step, area.x, top_step + 1.0),
			Color(0.035, 0.040, 0.115, alpha))

	# Subtle bottom vignette band for grounded dock & footer contrast.
	var bot_h: float = area.y * 0.26
	var bot_y0: float = area.y - bot_h
	var bot_bands: int = 18
	var bot_step: float = bot_h / float(bot_bands)
	for b in bot_bands:
		var frac: float = (float(b) + 0.5) / float(bot_bands)
		var alpha: float = 0.42 * frac * frac
		draw_rect(Rect2(0.0, bot_y0 + float(b) * bot_step, area.x, bot_step + 1.0),
			Color(0.035, 0.040, 0.115, alpha))
