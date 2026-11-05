extends Control
## Mode select shown after PLAY: sandbox, multiplayer lobby and the minigames hub.

const VEHICLE_SCENE: String = "res://scenes/ui/vehicle_select.tscn"
const MAIN_MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"
const LOBBY_SCENE: String = "res://scenes/ui/lobby_menu.tscn"
const MINIGAMES_SCENE: String = "res://scenes/ui/minigames_menu.tscn"

@onready var _sandbox_button: Button = %SandboxButton
@onready var _host_button: Button = %HostButton
@onready var _join_button: Button = %JoinButton
@onready var _minigames_button: Button = %MinigamesButton
@onready var _back_button: Button = %BackButton
@onready var _notice: Label = %NoticeLabel


func _ready() -> void:
	CursorController.set_menu_mode(true)
	_notice.text = ""
	_notice.visible = false
	_sandbox_button.pressed.connect(_on_sandbox)
	_host_button.pressed.connect(_on_host)
	_join_button.pressed.connect(_on_join)
	_minigames_button.pressed.connect(_on_minigames)
	_back_button.pressed.connect(_on_back)
	_sandbox_button.grab_focus()


func _on_sandbox() -> void:
	get_tree().change_scene_to_file(VEHICLE_SCENE)


func _on_host() -> void:
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_join() -> void:
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_minigames() -> void:
	get_tree().change_scene_to_file(MINIGAMES_SCENE)


func _on_back() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _show_notice(text: String) -> void:
	_notice.text = text
	_notice.visible = true
