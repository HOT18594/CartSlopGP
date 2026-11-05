extends Control
## Mode select shown after PLAY. Sandbox works today; HOST / JOIN are wired to
## the lobby placeholder and will start real sessions once multiplayer exists.

const VEHICLE_SCENE: String = "res://scenes/ui/vehicle_select.tscn"
const MAIN_MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"

@onready var _sandbox_button: Button = %SandboxButton
@onready var _host_button: Button = %HostButton
@onready var _join_button: Button = %JoinButton
@onready var _back_button: Button = %BackButton
@onready var _notice: Label = %NoticeLabel


func _ready() -> void:
	CursorController.set_menu_mode(true)
	_notice.text = ""
	_sandbox_button.pressed.connect(_on_sandbox)
	_host_button.pressed.connect(_on_host)
	_join_button.pressed.connect(_on_join)
	_back_button.pressed.connect(_on_back)
	_sandbox_button.grab_focus()


func _on_sandbox() -> void:
	get_tree().change_scene_to_file(VEHICLE_SCENE)


func _on_host() -> void:
	_show_notice("Hosting opens with multiplayer. Use the sandbox for now.")


func _on_join() -> void:
	_show_notice("Joining opens with multiplayer. Use the sandbox for now.")


func _on_back() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _show_notice(text: String) -> void:
	_notice.text = text
	_notice.visible = true
