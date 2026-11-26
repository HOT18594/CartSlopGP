extends Control
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
const UiPalette := preload("res://scripts/ui/ui_palette.gd")
## Esc shows RESUME / SETTINGS / QUIT TO MENU in the 0.8.5 dark-glass slanted
## parallelogram racing-sim telemetry shell.
##
## Single player: the world pauses.
## Multiplayer: the world keeps running in the background, Minecraft-style.
## Opening this menu never changes the room state on the Pi and never pauses
## the server. Settings still work because this layer is PROCESS_MODE_ALWAYS.

const MAIN_MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"
const SINGLE_HINT: String = "SINGLE PLAYER  ·  THE RACE IS PAUSED"
const MULTIPLAYER_HINT: String = "MULTIPLAYER  ·  THE GAME KEEPS RUNNING"
const QUIT_WARNING: String = "HOST: QUITTING CLOSES THE ROOM FOR EVERYONE"
const CLOSE_HINT: String = "ESC OR START CLOSES THIS MENU"

@onready var _panel: PanelContainer = $Center/Panel
@onready var _title: Label = $Center/Panel/Body/Title
@onready var _resume_button: Button = %ResumeButton
@onready var _settings_button: Button = %PauseSettingsButton
@onready var _quit_button: Button = %QuitToMenuButton
@onready var _settings_menu: Control = %SettingsMenu

var _is_open: bool = false
var _multiplayer: bool = false
var _mode_hint: Label
var _quit_armed: bool = false
var _quit_ticket: int = 0


class _SlantedBackdrop extends Control:
	## Custom-drawn skewed dark-glass parallelogram plate behind the Pause Menu body.
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		if w < 32.0 or h < 32.0:
			return
		var sk: float = 20.0
		var pad_x: float = 28.0
		var pad_y: float = 22.0
		var x0: float = -pad_x - sk * 0.5
		var y0: float = -pad_y
		var bw: float = w + pad_x * 2.0
		var bh: float = h + pad_y * 2.0
		var pts := PackedVector2Array([
			Vector2(x0 + sk, y0),
			Vector2(x0 + sk + bw, y0),
			Vector2(x0 + bw, y0 + bh),
			Vector2(x0, y0 + bh),
		])
		var sh := PackedVector2Array([
			pts[0] + Vector2(6.0, 9.0), pts[1] + Vector2(6.0, 9.0),
			pts[2] + Vector2(6.0, 9.0), pts[3] + Vector2(6.0, 9.0),
		])
		draw_colored_polygon(sh, Color(0.02, 0.02, 0.07, 0.72))
		draw_colored_polygon(pts, Color(0.075, 0.086, 0.175, 0.96))
		# Subtle inner top glass highlight band
		var gloss_h: float = 34.0
		var t_g: float = clampf(gloss_h / maxf(bh, 1.0), 0.0, 1.0)
		var gloss := PackedVector2Array([
			pts[0],
			pts[1],
			pts[1].lerp(pts[2], t_g),
			pts[0].lerp(pts[3], t_g),
		])
		draw_colored_polygon(gloss, Color(1.0, 1.0, 1.0, 0.045))
		var cl := pts.duplicate()
		cl.append(pts[0])
		draw_polyline(cl, UiPalette.OUTLINE, 4.5, true)
		var inner := PackedVector2Array([
			pts[0] + Vector2(3.0, 3.0),
			pts[1] + Vector2(-4.0, 3.0),
			pts[2] + Vector2(-3.0, -3.0),
			pts[3] + Vector2(4.0, -3.0),
			pts[0] + Vector2(3.0, 3.0),
		])
		draw_polyline(inner, Color(0.35, 0.82, 1.0, 0.18), 1.6, true)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("nav_scope")
	_apply_dark_parallelogram_shell()
	_mode_hint = Label.new()
	_mode_hint.name = "ModeHint"
	_mode_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_hint.add_theme_font_size_override("font_size", 15)
	_mode_hint.add_theme_color_override("font_color", UiPalette.RED)
	_mode_hint.text = ""
	_mode_hint.visible = false
	_mode_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.get_parent().add_child(_mode_hint)
	_title.get_parent().move_child(_mode_hint, _title.get_index() + 1)
	hide()
	_resume_button.pressed.connect(close)
	_settings_button.pressed.connect(_on_settings_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_settings_menu.closed.connect(_on_settings_closed)


func _apply_dark_parallelogram_shell() -> void:
	if _panel == null:
		return
	_panel.custom_minimum_size = Vector2(520, 0)
	var pad_box := StyleBoxFlat.new()
	pad_box.draw_center = false
	pad_box.bg_color = Color(0, 0, 0, 0)
	pad_box.content_margin_left = 42.0
	pad_box.content_margin_right = 42.0
	pad_box.content_margin_top = 28.0
	pad_box.content_margin_bottom = 32.0
	_panel.add_theme_stylebox_override("panel", pad_box)
	var bg := _SlantedBackdrop.new()
	bg.name = "SlantedBackdrop"
	_panel.add_child(bg)
	_panel.move_child(bg, 0)
	if _title != null:
		_title.add_theme_color_override("font_color", UiPalette.TEXT)
		_title.add_theme_color_override("font_outline_color", UiPalette.OUTLINE)
		_title.add_theme_constant_override("outline_size", 8)


func _add_close_hint() -> void:
	var hint := Label.new()
	hint.name = "CloseHint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	hint.text = CLOSE_HINT
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.get_parent().add_child(hint)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		UiKit.consume_input(self)
		if SceneLoader.is_busy():
			return
		if _settings_menu.visible:
			_settings_menu.close()
			return
		if _is_open:
			close()
		else:
			open()


func open() -> void:
	if _is_open or SceneLoader.is_busy():
		return
	_is_open = true
	_multiplayer = Network.is_session_active()
	visible = true
	_title.text = "MENU" if _multiplayer else "PAUSED"
	_resume_button.text = "BACK TO GAME" if _multiplayer else "RESUME"
	_fit(_resume_button)
	_quit_ticket += 1
	_reset_quit_button()
	Network.input_locked = _multiplayer
	get_tree().paused = not _multiplayer
	CursorController.set_menu_mode(true)
	UiAnim.modal_open($Center/Panel, get_node_or_null("Dim"))
	UiAnim.stagger_slide([_resume_button, _settings_button, _quit_button],
		Vector2(-24.0, 0.0), 0.045, 0.22)
	MenuNav.refresh()
	MenuNav.focus(_resume_button)


func close() -> void:
	if not _is_open:
		return
	if _settings_menu.visible:
		_settings_menu.close()
	_quit_ticket += 1
	_reset_quit_button()
	_is_open = false
	visible = false
	$Center/Panel.scale = Vector2.ONE
	$Center/Panel.modulate = Color.WHITE
	MenuNav.refresh()
	Network.input_locked = false
	get_tree().paused = false
	CursorController.set_menu_mode(_another_menu_visible())


func _another_menu_visible() -> bool:
	for node: Node in get_tree().get_nodes_in_group("nav_scope"):
		if node == self or not (node is CanvasItem):
			continue
		if (node as CanvasItem).visible:
			return true
	return false


func _on_settings_pressed() -> void:
	if _settings_menu.visible:
		return
	_settings_menu.open()


func _on_settings_closed() -> void:
	MenuNav.refresh()
	MenuNav.focus(_settings_button)


func _on_quit_pressed() -> void:
	if Network.is_host and Network.is_session_active() and not _quit_armed:
		_quit_armed = true
		_quit_ticket += 1
		var ticket: int = _quit_ticket
		_quit_button.text = "CONFIRM QUIT"
		_fit(_quit_button)
		_mode_hint.text = QUIT_WARNING
		_mode_hint.visible = true
		await get_tree().create_timer(3.0).timeout
		if is_inside_tree() and _quit_armed and ticket == _quit_ticket:
			_reset_quit_button()
		return
	_quit_ticket += 1
	_reset_quit_button()
	_is_open = false
	visible = false
	Network.input_locked = false
	get_tree().paused = false
	if Network.is_session_active():
		Network.leave()
	SceneLoader.go_to(MAIN_MENU_SCENE, "MAIN MENU")


func _reset_quit_button() -> void:
	_quit_armed = false
	if _quit_button != null:
		_quit_button.text = "QUIT"
		_fit(_quit_button)
	if _mode_hint != null:
		_mode_hint.text = ""
		_mode_hint.visible = false


func _fit(button: Button) -> void:
	if button != null and button.has_method("fit_text"):
		button.call("fit_text")


func _exit_tree() -> void:
	Network.input_locked = false
	get_tree().paused = false
