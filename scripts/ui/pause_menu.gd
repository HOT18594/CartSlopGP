extends Control
## Esc shows RESUME / SETTINGS / QUIT TO MENU.
##
## Single player: the world pauses.
## Multiplayer: the world keeps running in the background, Minecraft-style.
## Opening this menu never changes the room state on the Pi and never pauses
## the server. Settings still work because this layer is PROCESS_MODE_ALWAYS.

const MAIN_MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"

@onready var _title: Label = $Center/Panel/Body/Title
@onready var _resume_button: Button = %ResumeButton
@onready var _settings_button: Button = %PauseSettingsButton
@onready var _quit_button: Button = %QuitToMenuButton
@onready var _settings_menu: Control = %SettingsMenu

var _is_open: bool = false
var _multiplayer: bool = false
var _mode_hint: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mode_hint = Label.new()
	_mode_hint.name = "ModeHint"
	_mode_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_hint.add_theme_font_size_override("font_size", 15)
	_mode_hint.add_theme_color_override("font_color", Color("b9b2c9"))
	_mode_hint.text = "MULTIPLAYER  -  THE GAME KEEPS RUNNING"
	_mode_hint.visible = false
	_title.get_parent().add_child(_mode_hint)
	_title.get_parent().move_child(_mode_hint, _title.get_index() + 1)
	hide()
	_resume_button.pressed.connect(close)
	_settings_button.pressed.connect(_on_settings_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_settings_menu.closed.connect(_on_settings_closed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if _settings_menu.visible:
			return
		if _is_open:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


func open() -> void:
	if _is_open:
		return
	_is_open = true
	_multiplayer = Network.is_session_active()
	# Show and lay out the menu *before* pausing: a paused tree does not flush
	# the redraw of a Control that only just became visible.
	visible = true
	_title.text = "MENU" if _multiplayer else "PAUSED"
	_mode_hint.visible = _multiplayer
	_resume_button.text = "BACK TO GAME" if _multiplayer else "RESUME"
	_resume_button.grab_focus()
	# Multiplayer is a live world: do not pause the tree or the server.
	get_tree().paused = not _multiplayer
	CursorController.set_menu_mode(true)


func close() -> void:
	if not _is_open:
		return
	if _settings_menu.visible:
		_settings_menu.close()
	_is_open = false
	visible = false
	get_tree().paused = false
	CursorController.set_menu_mode(false)


func _on_settings_pressed() -> void:
	_settings_menu.open()


func _on_settings_closed() -> void:
	_resume_button.grab_focus()


func _on_quit_pressed() -> void:
	_is_open = false
	visible = false
	get_tree().paused = false
	if Network.is_session_active():
		Network.leave()
	SceneLoader.go_to(MAIN_MENU_SCENE, "MAIN MENU")
