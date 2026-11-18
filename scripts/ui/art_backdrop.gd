extends Control
## Full-bleed menu artwork with slow Ken-Burns breathing pan/zoom, crossfade
## slideshow, cinematic edge vignette, and subtle arcade speed-telemetry motes.
##
## Sizing is explicit rather than anchor-based: when this node is added to a
## plain Control (not a Container), Godot does not always resolve PRESET_FULL_RECT
## before the first layout pass. Motion pauses automatically when
## `GameSettings.reduce_motion` is enabled.

const ART_DIR: String = "res://assets/ui/art/"
const CYAN_MOTE: Color = Color("38d6f0")
const GOLD_MOTE: Color = Color("ffd22e")

@export var texture_names: PackedStringArray = PackedStringArray()
@export var slide_seconds: float = 9.0
@export var fade_seconds: float = 1.4
@export var dim: float = 0.14 ## Extra darkening over the art, 0..1.
@export var enable_overlay: bool = true

class _OverlayCanvas extends Control:
	var backdrop: Control

	func _draw() -> void:
		if backdrop != null:
			backdrop.call("_draw_overlay", self)


var _layers: Array[TextureRect] = []
var _textures: Array[Texture2D] = []
var _shade: ColorRect
var _overlay: _OverlayCanvas
var _motes: Array[Dictionary] = []
var _streaks: Array[Dictionary] = []
var _index: int = 0
var _top: int = 0
var _timer: float = 0.0
var _anim_time: float = 0.0
var _advance_tween: Tween
var _last_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_seed_particles()
	_load_textures()
	if not _textures.is_empty():
		for i in 2:
			var layer := TextureRect.new()
			layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			layer.modulate.a = 0.0
			add_child(layer)
			_layers.append(layer)
		_layers[0].texture = _textures[0]
		_layers[0].modulate.a = 1.0
		_top = 0
		if dim > 0.0:
			_shade = ColorRect.new()
			_shade.color = Color(0.04, 0.05, 0.14, dim)
			_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_shade)
	if enable_overlay:
		_overlay = _OverlayCanvas.new()
		_overlay.name = "OverlayCanvas"
		_overlay.backdrop = self
		_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_overlay)
	_fit()
	_apply_ken_burns()


func _seed_particles() -> void:
	## Deterministic edge-weighted bokeh motes and telemetry streaks so center
	## UI cards stay clean while screen edges feel alive.
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xCA475109
	_motes.clear()
	for i in 18:
		var edge_band: float = rng.randf_range(0.03, 0.24)
		var x_norm: float = edge_band if i % 2 == 0 else (1.0 - edge_band)
		if i % 5 == 0:
			x_norm = rng.randf_range(0.20, 0.80)
		var y_norm: float = rng.randf_range(0.05, 0.95)
		if x_norm > 0.26 and x_norm < 0.74:
			y_norm = rng.randf_range(0.04, 0.18) if i % 2 == 0 else rng.randf_range(0.82, 0.96)
		_motes.append({
			"x": x_norm,
			"y": y_norm,
			"r": rng.randf_range(3.5, 13.0),
			"vx": rng.randf_range(-0.008, 0.014),
			"vy": rng.randf_range(-0.018, -0.006),
			"phase": rng.randf_range(0.0, TAU),
			"gold": i % 3 != 0,
			"alpha": rng.randf_range(0.08, 0.20),
		})
	_streaks = [
		{"x": 0.08, "y": 0.14, "len": 135.0, "w": 2.2, "gold": true, "speed": 18.0, "a": 0.18},
		{"x": 0.14, "y": 0.20, "len": 88.0, "w": 1.5, "gold": false, "speed": 24.0, "a": 0.16},
		{"x": 0.86, "y": 0.13, "len": 118.0, "w": 2.0, "gold": false, "speed": 20.0, "a": 0.17},
		{"x": 0.91, "y": 0.82, "len": 148.0, "w": 2.4, "gold": true, "speed": 22.0, "a": 0.18},
		{"x": 0.83, "y": 0.88, "len": 94.0, "w": 1.6, "gold": false, "speed": 16.0, "a": 0.15},
		{"x": 0.11, "y": 0.86, "len": 112.0, "w": 1.8, "gold": false, "speed": 19.0, "a": 0.16},
	]


func _load_textures() -> void:
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
	for layer: TextureRect in _layers:
		layer.size = target
		layer.pivot_offset = target * 0.5
	if _shade != null:
		_shade.size = target
		_shade.position = Vector2.ZERO
	if _overlay != null:
		_overlay.size = target
		_overlay.position = Vector2.ZERO
		_overlay.queue_redraw()


func has_art() -> bool:
	return not _textures.is_empty()


func _process(delta: float) -> void:
	var parent: Control = get_parent() as Control
	if parent != null and (absf(parent.size.x - _last_size.x) > 0.5
			or absf(parent.size.y - _last_size.y) > 0.5):
		_fit()
	var reduce: bool = _is_reduce_motion()
	if not reduce:
		_anim_time += delta
	_apply_ken_burns()
	if _overlay != null and not reduce:
		_overlay.queue_redraw()
	if _textures.size() < 2 or reduce:
		return
	if _advance_tween != null and _advance_tween.is_valid():
		return
	_timer += delta
	if _timer >= slide_seconds:
		_timer = 0.0
		_advance()


func _apply_ken_burns() -> void:
	if _layers.is_empty() or _last_size.x <= 0.0:
		return
	var reduce: bool = _is_reduce_motion()
	for i in _layers.size():
		var layer: TextureRect = _layers[i]
		layer.pivot_offset = _last_size * 0.5
		if reduce:
			layer.scale = Vector2.ONE
			layer.position = Vector2.ZERO
			continue
		var phase: float = float(i) * 2.15
		var zoom: float = 1.06 + 0.02 * sin(_anim_time * 0.28 + phase)
		var pan := Vector2(
			sin(_anim_time * 0.19 + phase) * _last_size.x * 0.013,
			cos(_anim_time * 0.15 + phase * 0.8) * _last_size.y * 0.011
		)
		layer.scale = Vector2.ONE * zoom
		layer.position = pan


func _advance() -> void:
	_index = (_index + 1) % _textures.size()
	var next: int = 1 - _top
	_layers[next].texture = _textures[_index]
	_layers[next].modulate.a = 0.0
	move_child(_layers[next], _layers.size() - 1)
	if _shade != null:
		move_child(_shade, get_child_count() - 1)
	if _overlay != null:
		move_child(_overlay, get_child_count() - 1)
	if _advance_tween != null and _advance_tween.is_valid():
		_advance_tween.kill()
	_advance_tween = create_tween()
	_advance_tween.set_parallel(true)
	_advance_tween.tween_property(_layers[next], "modulate:a", 1.0, fade_seconds) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_advance_tween.tween_property(_layers[_top], "modulate:a", 0.0, fade_seconds) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_top = next


func show_still(index: int) -> void:
	if _textures.is_empty():
		return
	_index = clampi(index, 0, _textures.size() - 1)
	_layers[_top].texture = _textures[_index]
	_layers[_top].modulate.a = 1.0


func _draw_overlay(canvas: Control) -> void:
	var area: Vector2 = canvas.size
	if area.x < 8.0 or area.y < 8.0:
		return
	var reduce: bool = _is_reduce_motion()
	var t_anim: float = 0.0 if reduce else _anim_time

	# Top cinematic vignette band so page titles & top status pills pop cleanly.
	var top_h: float = area.y * 0.22
	var top_bands: int = 20
	var top_step: float = top_h / float(top_bands)
	for b in top_bands:
		var frac: float = 1.0 - (float(b) + 0.5) / float(top_bands)
		var alpha: float = 0.34 * frac * frac
		canvas.draw_rect(Rect2(0.0, float(b) * top_step, area.x, top_step + 1.0),
			Color(0.03, 0.04, 0.12, alpha))

	# Bottom cinematic vignette band for grounded button & footer contrast.
	var bot_h: float = area.y * 0.28
	var bot_y0: float = area.y - bot_h
	var bot_bands: int = 24
	var bot_step: float = bot_h / float(bot_bands)
	for b in bot_bands:
		var frac: float = (float(b) + 0.5) / float(bot_bands)
		var alpha: float = 0.42 * frac * frac
		canvas.draw_rect(Rect2(0.0, bot_y0 + float(b) * bot_step, area.x, bot_step + 1.0),
			Color(0.03, 0.04, 0.12, alpha))

	# Soft radial/side edge darkening to frame foreground cards.
	var side_w: float = area.x * 0.14
	var side_bands: int = 12
	var side_step: float = side_w / float(side_bands)
	for b in side_bands:
		var frac: float = 1.0 - (float(b) + 0.5) / float(side_bands)
		var alpha: float = 0.22 * frac * frac
		var col := Color(0.03, 0.04, 0.12, alpha)
		canvas.draw_rect(Rect2(float(b) * side_step, 0.0, side_step + 1.0, area.y), col)
		canvas.draw_rect(Rect2(area.x - (float(b) + 1.0) * side_step, 0.0, side_step + 1.0, area.y), col)

	# Diagonal translucent arcade speed-telemetry lines near screen edges.
	var dir := Vector2(0.951, -0.309)
	for streak: Dictionary in _streaks:
		var base := Vector2(area.x * float(streak["x"]), area.y * float(streak["y"]))
		var travel: float = 0.0 if reduce else sin(t_anim * 0.45 + float(streak["speed"])) * 26.0
		var center: Vector2 = base + dir * travel
		var half_len: float = float(streak["len"]) * 0.5
		var base_col: Color = GOLD_MOTE if bool(streak["gold"]) else CYAN_MOTE
		var pulse: float = 1.0 if reduce else (0.78 + 0.22 * sin(t_anim * 1.3 + float(streak["len"])))
		var line_col := Color(base_col.r, base_col.g, base_col.b, float(streak["a"]) * pulse)
		var p0: Vector2 = center - dir * half_len
		var p1: Vector2 = center + dir * half_len
		canvas.draw_line(p0, p1, line_col, float(streak["w"]), true)
		canvas.draw_circle(p1, float(streak["w"]) * 1.15,
			Color(1.0, 1.0, 1.0, float(streak["a"]) * 0.85 * pulse))

	# Floating golden-cyan bokeh motes drifting gently across outer edges.
	for mote: Dictionary in _motes:
		var mx: float = fposmod(float(mote["x"]) + t_anim * float(mote["vx"]), 1.0) * area.x
		var my: float = fposmod(float(mote["y"]) + t_anim * float(mote["vy"]), 1.0) * area.y
		var shimmer: float = 1.0 if reduce else (0.72 + 0.28 * sin(t_anim * 1.6 + float(mote["phase"])))
		var radius: float = float(mote["r"])
		var tint: Color = GOLD_MOTE if bool(mote["gold"]) else CYAN_MOTE
		var a: float = float(mote["alpha"]) * shimmer
		canvas.draw_circle(Vector2(mx, my), radius * 1.65, Color(tint.r, tint.g, tint.b, a * 0.34))
		canvas.draw_circle(Vector2(mx, my), radius, Color(tint.r, tint.g, tint.b, a))
		canvas.draw_circle(Vector2(mx, my), maxf(radius * 0.38, 1.5), Color(1.0, 1.0, 1.0, a * 0.85))
