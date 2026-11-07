extends Control
## Full-bleed AI artwork with an optional slow crossfade slideshow.
##
## Used behind the menu shell and inside the game selector preview. Sizing is
## explicit rather than anchor-based: when this node is added to a plain
## Control (not a Container), Godot does not always resolve PRESET_FULL_RECT
## before the first layout pass, which leaves the art at 0x0 forever.

const ART_DIR: String = "res://assets/ui/art/"

@export var texture_names: PackedStringArray = PackedStringArray()
@export var slide_seconds: float = 5.0
@export var fade_seconds: float = 0.75
@export var dim: float = 0.0 ## Extra darkening over the art, 0..1.

var _layers: Array[TextureRect] = []
var _textures: Array[Texture2D] = []
var _shade: ColorRect
var _index: int = 0
var _top: int = 0
var _timer: float = 0.0
var _advance_tween: Tween
var _last_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_textures()
	if _textures.is_empty():
		return
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
		_shade.color = Color(0.05, 0.06, 0.16, dim)
		_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_shade)
	_fit()


func _load_textures() -> void:
	for file_name: String in texture_names:
		var path: String = ART_DIR + file_name
		if ResourceLoader.exists(path):
			var texture: Texture2D = load(path) as Texture2D
			if texture != null:
				_textures.append(texture)


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
		layer.position = Vector2.ZERO
	if _shade != null:
		_shade.size = target
		_shade.position = Vector2.ZERO


func has_art() -> bool:
	return not _textures.is_empty()


func _process(delta: float) -> void:
	if _textures.is_empty():
		return
	# Containers resize their children on their own; plain Controls do not,
	# so track the parent size every frame and refit when it changes.
	var parent: Control = get_parent() as Control
	if parent != null and (absf(parent.size.x - _last_size.x) > 0.5
			or absf(parent.size.y - _last_size.y) > 0.5):
		_fit()
	if _textures.size() < 2:
		return
	if _advance_tween != null and _advance_tween.is_valid():
		return
	_timer += delta
	if _timer >= slide_seconds:
		_timer = 0.0
		_advance()


func _advance() -> void:
	_index = (_index + 1) % _textures.size()
	var next: int = 1 - _top
	_layers[next].texture = _textures[_index]
	_layers[next].modulate.a = 0.0
	move_child(_layers[next], _layers.size() - 1)
	if _shade != null:
		move_child(_shade, get_child_count() - 1)
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
