extends Control
## Mode select shown after PLAY. Sandbox works today; HOST / JOIN are wired to
## the lobby placeholder and will start real sessions once multiplayer exists.

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
	_sandbox_button.pressed.connect(_on_sandbox)
	_host_button.pressed.connect(_on_host)
	_join_button.pressed.connect(_on_join)
	_minigames_button.pressed.connect(_on_minigames)
	_back_button.pressed.connect(_on_back)
	_sandbox_button.grab_focus()


func _on_sandbox() -> void:
	SceneLoader.go_to(VEHICLE_SCENE, "PICK YOUR RIDE", "Loading the garage...")


func _on_host() -> void:
	SceneLoader.go_to(LOBBY_SCENE, "MULTIPLAYER", "Opening the lobby...")


func _on_join() -> void:
	SceneLoader.go_to(LOBBY_SCENE, "MULTIPLAYER", "Opening the lobby...")


func _on_minigames() -> void:
	SceneLoader.go_to(MINIGAMES_SCENE, "MINIGAMES", "Setting up the playground...")


func _on_back() -> void:
	SceneLoader.go_to(MAIN_MENU_SCENE, "MAIN MENU")


func _show_notice(text: String) -> void:
	_notice.text = text
	_notice.visible = true
