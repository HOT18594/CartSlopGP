extends CanvasLayer
## Custom cartoon cursor: follows the mouse, switches sprite on hover and pops
## on click. Registered as the `CursorController` autoload.
## Menus call set_menu_mode(true); the driving scene calls set_menu_mode(false),
## which hides the sprite and captures the mouse.

@export_group("Look")
@export var enable_custom_cursor: bool = true ## Read again from Settings on every mode change.
@export var cursor_scale: float = 1.6 ## Sprite size multiplier (source art is 32 px).
@export var click_pop_strength: float = 0.22 ## Extra scale at the peak of the click pop.
@export var normal_texture: Texture2D
@export var hover_texture: Texture2D
@export var pressed_texture: Texture2D

@export_group("Feel")
@export var pop_duration: float = 0.10 ## Seconds of the click pop.
@export var hover_hotspot: Vector2 = Vector2(8, 5)
@export var pressed_hotspot: Vector2 = Vector2(6, 5)
@export var idle_hotspot: Vector2 = Vector2(3, 2)

@onready var _sprite: TextureRect = $Sprite
@onready var _click_audio: AudioStreamPlayer = $ClickAudio

var _menu_mode: bool = true
var _hovering: bool = false
var _pop_tween: Tween


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sprite.texture = normal_texture
	_apply_mode()


func set_menu_mode(menu_mode: bool) -> void:
	_menu_mode = menu_mode
	_apply_mode()


func is_menu_mode() -> bool:
	return _menu_mode


func _active() -> bool:
	if not enable_custom_cursor:
		return false
	var settings: Node = get_node_or_null("/root/GameSettings")
	if settings != null:
		var value: Variant = settings.get("custom_cursor")
		if value is bool:
			return value as bool
	return true


func _apply_mode() -> void:
	var show_custom: bool = _menu_mode and _active()
	_sprite.visible = show_custom
	if _menu_mode:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN if show_custom else Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if show_custom:
		_update_sprite()


func _process(_delta: float) -> void:
	if not _menu_mode:
		return
	var show_custom: bool = _active()
	if _sprite.visible != show_custom:
		_apply_mode()
	if not show_custom:
		return
	_hovering = _is_over_button(get_viewport().gui_get_hovered_control())
	_sprite.texture = hover_texture if _hovering else normal_texture
	var hotspot: Vector2 = hover_hotspot if _hovering else idle_hotspot
	_sprite.position = get_viewport().get_mouse_position() - hotspot * cursor_scale


func _is_over_button(control: Control) -> bool:
	var node: Node = control
	while node is Control:
		var button := node as BaseButton
		if button != null and not button.disabled:
			return true
		node = node.get_parent()
	return false


func _input(event: InputEvent) -> void:
	if not _menu_mode or not _sprite.visible:
		return
	var mouse := event as InputEventMouseButton
	if mouse == null or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	if mouse.pressed:
		_play_press(mouse.position)
	else:
		_play_release()


func _play_press(mouse_position: Vector2) -> void:
	_sprite.texture = pressed_texture if pressed_texture != null else normal_texture
	_sprite.position = mouse_position - pressed_hotspot * cursor_scale
	if _click_audio != null and _click_audio.stream != null:
		_click_audio.pitch_scale = randf_range(0.96, 1.05)
		_click_audio.play()
	if _pop_tween != null and _pop_tween.is_valid():
		_pop_tween.kill()
	_pop_tween = create_tween()
	_pop_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var base: Vector2 = Vector2.ONE * cursor_scale
	_sprite.scale = base * (1.0 + click_pop_strength)
	_pop_tween.tween_property(_sprite, "scale", base, pop_duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _play_release() -> void:
	_sprite.texture = hover_texture if _hovering else normal_texture


func _update_sprite() -> void:
	_sprite.scale = Vector2.ONE * cursor_scale
	_sprite.size = normal_texture.get_size() if normal_texture != null else Vector2(32, 32)
