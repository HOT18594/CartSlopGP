extends Control
## Self-timed, shuffled full-bleed menu artwork slideshow with smooth crossfades,
## soft dim tint, and a subtle cinematic edge vignette.
##
## Drawn directly via `_draw()` (`draw_texture_rect`, `position = Vector2.ZERO`)
## with zero pan/zoom wobble and zero particle noise so menu artwork stays
## rock-steady and pixel-crisp.
##
## This is the one and only owner of menu backdrop changes (0.8.7 correction):
## the slideshow cycles on its own timer and is deliberately INDEPENDENT of the
## UI - hovering, clicking or focusing a button/card never calls into this node
## and can never pause it, retarget it or swap the art. Each screen only supplies
## its own texture pool through `set_slides()` (via `MenuBackground`).
##
## Timing: one randomized 8-12 s beat per slide (`slide_seconds_min/max`), a
## smooth crossfade (`fade_seconds`), and a shuffled order bag so the same plate
## never appears twice in a row. Reduced motion (`GameSettings.reduce_motion`)
## holds a still plate (no auto-advance, no Ken Burns drift) while still leaving
## the art on screen; hover/focus independence is identical in both modes.

const ART_DIR: String = "res://assets/ui/art/"
const MIN_SLIDE_SECONDS: float = 8.0
const MAX_SLIDE_SECONDS: float = 12.0

@export var texture_names: PackedStringArray = PackedStringArray()
@export var slide_seconds_min: float = MIN_SLIDE_SECONDS
@export var slide_seconds_max: float = MAX_SLIDE_SECONDS
@export var fade_seconds: float = 1.15
@export var dim: float = 0.10 ## Extra darkening over the art, 0..1.
@export var left_scrim: float = 0.44 ## Left-rail racing-sim contrast gradient.
@export var enable_overlay: bool = true
@export var enable_ken_burns: bool = true
## The slideshow is always on for menus. Kept as an explicit flag only so a
## future non-menu host can freeze on one plate; nothing in the menu code is
## allowed to toggle it any more.
@export var auto_advance: bool = true
## Randomized next-slide order. `true` = shuffled bag, never the same plate twice
## in a row; `false` = straight 0..N loop (kept for single-screen hosts/tests).
@export var shuffle: bool = true

var _textures: Array[Texture2D] = []
var _names: Array[String] = []
var _current_index: int = 0
var _next_index: int = -1
var _fade_progress: float = 0.0
var _fading: bool = false
var _timer: float = 0.0
var _slide_delay: float = 8.5
var _drift_time: float = 0.0
var _last_size: Vector2 = Vector2.ZERO
var _advances: int = 0
var _shuffle_bag: Array[int] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	position = Vector2.ZERO
	_load_textures()
	resized.connect(queue_redraw)
	_fit()
	_slide_delay = roll_slide_delay()
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
	_shuffle_bag.clear()


func set_slides(names: PackedStringArray) -> void:
	## Replace this backdrop's texture pool. Called by `MenuBackground` with the
	## current screen's own art set; the slideshow keeps cycling by itself.
	if names == texture_names:
		return
	texture_names = names
	_load_textures()
	_current_index = 0
	_next_index = -1
	_fade_progress = 0.0
	_fading = false
	_timer = 0.0
	_slide_delay = roll_slide_delay()
	queue_redraw()


func roll_slide_delay() -> float:
	## One randomized 8-12 s beat. Exposed so headless checks can prove the
	## cadence band without waiting out a real slide.
	var lo: float = clampf(minf(slide_seconds_min, slide_seconds_max),
		0.05, 600.0)
	var hi: float = clampf(maxf(slide_seconds_min, slide_seconds_max),
		lo, 600.0)
	return randf_range(lo, hi)


func slide_names() -> PackedStringArray:
	## Names of the plates actually loaded for this backdrop (missing files are
	## skipped, so a typo can never wedge the slideshow on an empty pool).
	return PackedStringArray(_names)


func current_index() -> int:
	return _current_index


func current_slide_name() -> String:
	if _names.is_empty():
		return ""
	return _names[clampi(_current_index, 0, _names.size() - 1)]


func advance_count() -> int:
	## Number of completed/started slide changes; lets a headless check prove the
	## timer really advances without waiting slide by slide.
	return _advances


func next_slide_delay() -> float:
	return _slide_delay


func reset_schedule() -> void:
	## Restart the current beat from zero (used by checks after retiming the
	## cadence exports, and by any future screen that swaps its pool mid-beat).
	_timer = 0.0
	_slide_delay = roll_slide_delay()


func reduced_motion() -> bool:
	return _is_reduce_motion()


func ken_burns_active() -> bool:
	return enable_ken_burns and not _is_reduce_motion()


func has_art() -> bool:
	return not _textures.is_empty()


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


func _pick_next_index() -> int:
	## Randomized order with no immediate repeat: a shuffled bag of every index
	## except the one on screen, refilled only once the bag is empty, so each
	## plate is seen once per cycle.
	var count: int = _textures.size()
	if count <= 1:
		return _current_index
	if not shuffle:
		return (_current_index + 1) % count
	if _shuffle_bag.is_empty():
		for index in count:
			if index != _current_index:
				_shuffle_bag.append(index)
		_shuffle_bag.shuffle()
	return _shuffle_bag.pop_back()


func _begin_next_slide() -> void:
	_next_index = _pick_next_index()
	if _next_index < 0 or _next_index == _current_index:
		return
	_fade_progress = 0.0
	_fading = true
	_advances += 1
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
	# Reduced motion (and a single-plate pool) hold a still slide: no automated
	# crossfade. Hover/focus never reaches this node either way.
	if _textures.size() < 2 or reduced or not auto_advance:
		return
	_timer += delta
	if _timer >= _slide_delay:
		_timer = 0.0
		_slide_delay = roll_slide_delay()
		_begin_next_slide()


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
