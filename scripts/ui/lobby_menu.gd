extends Control
## Host / join screen for peer-to-peer sessions.

const PLAY_MENU_SCENE: String = "res://scenes/ui/play_menu.tscn"

@onready var _host_button: Button = %HostButton
@onready var _join_input: LineEdit = %JoinInput
@onready var _join_button: Button = %JoinButton
@onready var _join_status: Label = %JoinStatus
@onready var _host_box: VBoxContainer = %HostBox
@onready var _join_box: VBoxContainer = %JoinBox
@onready var _code_label: Label = %CodeLabel
@onready var _copy_button: Button = %CopyButton
@onready var _start_button: Button = %StartButton
@onready var _host_status: Label = %HostStatus
@onready var _players_label: Label = %PlayersLabel
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	CursorController.set_menu_mode(true)
	Network.host_started.connect(_on_host_started)
	Network.code_updated.connect(_on_code_updated)
	Network.join_succeeded.connect(_on_join_succeeded)
	Network.join_failed.connect(_on_join_failed)
	Network.join_status_changed.connect(_on_join_status)
	Network.peers_changed.connect(_refresh_players)
	Network.latency_changed.connect(_on_latency_changed)
	Network.session_ended.connect(_on_session_ended)
	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_copy_button.pressed.connect(_on_copy_pressed)
	_start_button.pressed.connect(_on_start_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_join_input.text_submitted.connect(func(_text: String) -> void: _on_join_pressed())
	_host_box.visible = false
	_join_status.visible = false
	_join_input.grab_focus()
	_refresh_players()


func _on_host_pressed() -> void:
	_host_button.disabled = true
	_host_status.text = "Opening a port (routers can take a moment)..."
	Network.host_game()


func _on_host_started(code: String) -> void:
	_host_button.visible = false
	_join_box.visible = false
	_join_status.visible = false
	_host_box.visible = true
	_start_button.visible = true
	_copy_button.visible = true
	_code_label.text = code
	_host_status.text = "Share this code. LAN players can join now."
	_refresh_players()


func _on_code_updated(code: String) -> void:
	_code_label.text = code
	_host_status.text = "Public address found - internet players can join."


func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(_code_label.text)
	_host_status.text = "Code copied to the clipboard."


func _on_start_pressed() -> void:
	Network.start_game()


func _on_join_pressed() -> void:
	var code: String = _join_input.text.strip_edges()
	if code == "":
		_join_status.text = "Enter the host's code first."
		_join_status.visible = true
		return
	_join_button.disabled = true
	_join_status.visible = true
	_join_status.text = "Connecting..."
	Network.join_game(code)


func _on_join_status(text: String) -> void:
	_join_status.visible = true
	_join_status.text = text


func _on_join_succeeded() -> void:
	_join_box.visible = false
	_host_button.visible = false
	_host_box.visible = true
	_start_button.visible = false
	_copy_button.visible = false
	_code_label.text = ""
	_host_status.text = "Connected. Waiting for the host to start the sandbox..."
	_refresh_players()


func _on_join_failed(reason: String) -> void:
	_join_button.disabled = false
	_join_status.visible = true
	_join_status.text = reason


func _on_session_ended(reason: String) -> void:
	if reason != "":
		_host_status.text = reason
	_refresh_players()


func _on_latency_changed(_ms: int) -> void:
	_refresh_players()


func _refresh_players() -> void:
	if not Network.is_session_active():
		_players_label.text = ""
		return
	var ids: Array[int] = [multiplayer.get_unique_id()]
	for peer_id: int in multiplayer.get_peers():
		ids.append(peer_id)
	ids.sort()
	var lines: PackedStringArray = []
	for peer_id: int in ids:
		var label: String = "HOST" if peer_id == 1 else "PLAYER %d" % peer_id
		if peer_id == multiplayer.get_unique_id():
			label += "  (YOU)"
		if peer_id == 1 and Network.is_client:
			label += "   %d ms" % Network.latency_ms
		lines.append(label)
	_players_label.text = "\n".join(lines)


func _on_back_pressed() -> void:
	if Network.is_session_active():
		Network.leave()
	get_tree().change_scene_to_file(PLAY_MENU_SCENE)
