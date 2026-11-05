extends Control
## Esc pauses driving, restores the mouse cursor and shows RESUME / SETTINGS /
## QUIT TO MENU. Runs while the tree is paused.

const MAIN_MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"

@onready var _resume_button: Button = %ResumeButton
@onready var _settings_button: Button = %PauseSettingsButton
@onready var _quit_button: Button = %QuitToMenuButton
@onready var _settings_menu: Control = %SettingsMenu

var _is_open: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	# Show and lay out the menu *before* pausing: a paused tree does not flush
	# the redraw of a Control that only just became visible.
	visible = true
	_resume_button.grab_focus()
	get_tree().paused = true
	CursorController.set_menu_mode(true)


func close() -> void:
	if not _is_open:
		return
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
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
