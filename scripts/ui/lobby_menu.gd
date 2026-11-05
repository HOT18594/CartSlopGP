extends Control
## Host / join screen for peer-to-peer sessions.
## Profile (name), connection mode (LAN / Online), join code and player list.

const PLAY_MENU_SCENE: String = "res://scenes/ui/play_menu.tscn"
const MODE_LAN: String = "lan"
const MODE_ONLINE: String = "online"

@onready var _name_input: LineEdit = %NameInput
@onready var _lan_button: Button = %LanButton
@onready var _online_button: Button = %OnlineButton
@onready var _mode_hint: Label = %ModeHint
@onready var _public_ip_box: HBoxContainer = %PublicIpBox
@onready var _public_ip_input: LineEdit = %PublicIpInput
@onready var _host_button: Button = %HostButton
@onready var _join_box: VBoxContainer = %JoinBox
@onready var _join_input: LineEdit = %JoinInput
@onready var _join_button: Button = %JoinButton
@onready var _join_status: Label = %JoinStatus
@onready var _host_box: VBoxContainer = %HostBox
@onready var _code_label: Label = %CodeLabel
@onready var _copy_button: Button = %CopyButton
@onready var _start_button: Button = %StartButton
@onready var _host_status: Label = %HostStatus
@onready var _players_label: Label = %PlayersLabel
@onready var _back_button: Button = %BackButton

var _mode: String = MODE_ONLINE


func _ready() -> void:
	CursorController.set_menu_mode(true)
	Network.host_started.connect(_on_host_started)
	Network.host_failed.connect(_on_host_failed)
	Network.code_updated.connect(_on_code_updated)
	Network.join_succeeded.connect(_on_join_succeeded)
	Network.join_failed.connect(_on_join_failed)
	Network.join_status_changed.connect(_on_join_status)
	Network.peers_changed.connect(_refresh_players)
	Network.names_changed.connect(_refresh_players)
	Network.latency_changed.connect(func(_ms: int) -> void: _refresh_players())
	Network.session_ended.connect(_on_session_ended)

	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_copy_button.pressed.connect(_on_copy_pressed)
	_start_button.pressed.connect(_on_start_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_lan_button.pressed.connect(_set_mode.bind(MODE_LAN))
	_online_button.pressed.connect(_set_mode.bind(MODE_ONLINE))
	_name_input.text_submitted.connect(func(_t: String) -> void: _commit_name())
	_name_input.focus_exited.connect(_commit_name)
	_name_input.text_changed.connect(_on_name_typed)
	_public_ip_input.text_changed.connect(func(text: String) -> void: Network.set_custom_public_ip(text))
	_join_input.text_submitted.connect(func(_t: String) -> void: _on_join_pressed())

	_name_input.text = GameSettings.player_name
	_name_input.max_length = 16
	_host_box.visible = false
	_join_status.visible = false
	_set_mode(MODE_ONLINE)
	_name_input.grab_focus()
	_refresh_players()


func _on_name_typed(_text: String) -> void:
	# Keep the field responsive; full sanitising happens on commit.
	pass


func _commit_name() -> void:
	var clean: String = GameSettings.sanitize_name(_name_input.text)
	_name_input.text = clean
	Network.set_local_name(clean)
	_refresh_players()


func _set_mode(mode: String) -> void:
	_mode = mode
	Network.custom_public_ip = _public_ip_input.text if mode == MODE_ONLINE else ""
	_lan_button.fill_color = Color("8ed8f6") if mode == MODE_LAN else Color("b9b2c9")
	_online_button.fill_color = Color("ffd22e") if mode == MODE_ONLINE else Color("b9b2c9")
	_public_ip_box.visible = mode == MODE_ONLINE
	_mode_hint.text = "Online: UPnP forwards the port automatically. If that fails, use a public IP below." \
		if mode == MODE_ONLINE else "LAN: same Wi-Fi only - the code uses your local address."


func _on_host_pressed() -> void:
	_commit_name()
	_host_button.disabled = true
	_host_status.text = "Opening a port (routers can take a moment)..."
	_host_box.visible = true
	_start_button.visible = true
	_copy_button.visible = true
	_code_label.text = "...."
	Network.host_game(_mode)


func _on_host_failed(reason: String) -> void:
	_host_button.disabled = false
	_host_status.text = reason


func _on_host_started(code: String) -> void:
	_host_button.visible = false
	_join_box.visible = false
	_host_box.visible = true
	_start_button.visible = true
	_copy_button.visible = true
	_code_label.text = code
	_host_status.text = "Online - share this code." if _mode == MODE_ONLINE else "LAN - share this code on your Wi-Fi."
	_refresh_players()


func _on_code_updated(code: String) -> void:
	_code_label.text = code
	_host_status.text = "Public address found - anyone with the code can join."


func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(_code_label.text)
	_host_status.text = "Code copied to the clipboard."


func _on_start_pressed() -> void:
	Network.start_game()


func _on_join_pressed() -> void:
	_commit_name()
	var code: String = _join_input.text.strip_edges()
	if code == "":
		_join_status.visible = true
		_join_status.text = "Enter the host's code first."
		return
	_join_button.disabled = true
	_join_status.visible = true
	_join_status.text = "Connecting..."
	Network.join_game(code)


func _on_join_status(text: String) -> void:
	_join_status.visible = true
	_join_status.text = text


func _on_join_failed(reason: String) -> void:
	_join_button.disabled = false
	_join_status.visible = true
	_join_status.text = reason


func _on_join_succeeded() -> void:
	_join_box.visible = false
	_host_button.visible = false
	_host_box.visible = true
	_start_button.visible = false
	_copy_button.visible = false
	_code_label.visible = false
	_host_status.text = "Connected. Waiting for the host to start..."
	_refresh_players()


func _on_session_ended(reason: String) -> void:
	if reason != "":
		_host_status.text = reason
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
		var label: String = Network.name_of(peer_id)
		if peer_id == multiplayer.get_unique_id():
			label += "  (YOU)"
		if peer_id == 1:
			label = "[HOST] " + label
		if peer_id == 1 and Network.is_client:
			label += "   %d ms" % Network.latency_ms
		lines.append(label)
	_players_label.text = "\n".join(lines)


func _on_back_pressed() -> void:
	if Network.is_session_active():
		Network.leave()
	SceneLoader.go_to(PLAY_MENU_SCENE, "MAIN MENU")
