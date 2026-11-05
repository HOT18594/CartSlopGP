extends Control
## Host / join screen for peer-to-peer sessions.
## Profile (name), connection mode (LAN / Online), join code and player list.

const PLAY_MENU_SCENE: String = "res://scenes/ui/play_menu.tscn"
const MINIGAMES_SCENE: String = "res://scenes/ui/minigames_menu.tscn"
const MODE_LAN: String = "lan"
const MODE_ONLINE: String = "online"
const CANDY_BUTTON: String = "res://scripts/ui/candy_button.gd"
const PILL_CYCLER: String = "res://scripts/ui/pill_cycler.gd"
const UiPalette := preload("res://scripts/ui/ui_palette.gd")

const BOT_LABELS: PackedStringArray = ["NO BOTS", "1 BOT", "2 BOTS", "3 BOTS", "4 BOTS", "5 BOTS"]
const BOT_VALUES: Array[int] = [0, 1, 2, 3, 4, 5]

@onready var _name_input: LineEdit = %NameInput
@onready var _lan_button: Button = %LanButton
@onready var _online_button: Button = %OnlineButton
@onready var _mode_hint: Label = %ModeHint
@onready var _public_ip_box: HBoxContainer = %PublicIpBox
@onready var _public_ip_input: LineEdit = %PublicIpInput
@onready var _host_button: Button = %HostButton
@onready var _join_box: VBoxContainer = %JoinBox
@onready var _server_box: HBoxContainer = %ServerBox
@onready var _server_input: LineEdit = %ServerInput
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
@onready var _profile_row: Control = $Center/Panel/Body/ProfileRow
@onready var _mode_row: Control = $Center/Panel/Body/ModeRow
@onready var _public_ip_row: Control = $Center/Panel/Body/PublicIpBox

var _mode: String = MODE_ONLINE
var _game_row: HBoxContainer
var _bots_row: HBoxContainer
var _mode_pill: Button
var _advanced_button: Button
var _game_pill: Button
var _bots_pill: Button
var _minigame_picker: Button
var _game_hint: Label
var _lan_row: HBoxContainer
var _lan_code_label: Label
var _copy_lan_button: Button
var _advanced_open: bool = false
var _browse_button: Button
var _lobby_list: VBoxContainer
var _session_state: String = "idle"


func _ready() -> void:
	CursorController.set_menu_mode(true)
	_build_session_controls()
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
	Network.session_config_changed.connect(_refresh_session_controls)

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
	_server_input.text_changed.connect(func(text: String) -> void: Network.set_relay_server(text))
	_server_input.text = GameSettings.relay_server
	_join_input.text_submitted.connect(func(_t: String) -> void: _on_join_pressed())

	_name_input.text = GameSettings.player_name
	_name_input.max_length = 16
	_host_box.visible = false
	_join_status.visible = false
	_set_mode(GameSettings.connection_preference)
	_name_input.grab_focus()
	_refresh_players()
	_refresh_session_controls()
	# Returning from the minigame picker must restore the live session panel.
	if Network.is_host and Network.join_code != "":
		_on_host_started(Network.join_code)
	elif Network.is_client and Network.is_connected_to_server():
		_on_join_succeeded()
	else:
		_set_session_state("idle")


func _build_session_controls() -> void:
	## Host-only session settings, inserted just above BACK so the existing
	## host/join layout stays untouched.
	var body: VBoxContainer = $Center/Panel/Body

	# One cycling pill replaces the LAN/ONLINE pair.
	_lan_button.visible = false
	_online_button.visible = false
	_mode_pill = _pill(PackedStringArray(["ONLINE", "WI-FI / LAN"]),
		["online", "lan"], 0 if _mode == MODE_ONLINE else 1)
	_mode_pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_pill.connect("option_changed", func(value: Variant) -> void: _set_mode(str(value)))
	_mode_row.add_child(_mode_pill)
	_advanced_button = _candy("ADVANCED", UiPalette.TEXT_DIM, 36, 12)
	_advanced_button.custom_minimum_size = Vector2(126, 36)
	_advanced_button.pressed.connect(_on_advanced_pressed)
	_mode_row.add_child(_advanced_button)

	_game_row = HBoxContainer.new()
	_game_row.add_theme_constant_override("separation", 10)
	var caption := Label.new()
	caption.custom_minimum_size = Vector2(90, 0)
	caption.text = "GAME"
	caption.add_theme_font_size_override("font_size", 16)
	caption.add_theme_color_override("font_color", UiPalette.INK)
	_game_row.add_child(caption)
	_game_pill = _pill(PackedStringArray(["SANDBOX", "MINIGAMES"]),
		[GameSettings.GAME_SANDBOX, GameSettings.GAME_MINIGAMES], 0)
	_game_pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_game_pill.connect("option_changed", func(value: Variant) -> void: _on_game_mode(str(value)))
	_game_row.add_child(_game_pill)

	_bots_row = HBoxContainer.new()
	_bots_row.add_theme_constant_override("separation", 10)
	var bots_caption := Label.new()
	bots_caption.custom_minimum_size = Vector2(90, 0)
	bots_caption.text = "AI BOTS"
	bots_caption.add_theme_font_size_override("font_size", 16)
	bots_caption.add_theme_color_override("font_color", UiPalette.INK)
	_bots_row.add_child(bots_caption)
	_bots_pill = _pill(BOT_LABELS, BOT_VALUES, GameSettings.effective_bot_count())
	_bots_pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bots_pill.connect("option_changed", _on_bots_changed)
	_bots_row.add_child(_bots_pill)

	_minigame_picker = _candy("CHOOSE MINIGAME", UiPalette.CYAN, 48, 20)
	_minigame_picker.pressed.connect(_on_choose_minigame)
	_game_hint = Label.new()
	_game_hint.add_theme_font_size_override("font_size", 13)
	_game_hint.add_theme_color_override("font_color", UiPalette.BLUE_DARK)
	_game_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# Browse public rooms advertised by the Pi server.
	var join_row: HBoxContainer = $Center/Panel/Body/JoinBox/JoinRow
	_browse_button = _candy("BROWSE", UiPalette.CYAN, 52, 16)
	_browse_button.custom_minimum_size = Vector2(124, 52)
	_browse_button.pressed.connect(_on_browse_pressed)
	join_row.add_child(_browse_button)
	_lobby_list = VBoxContainer.new()
	_lobby_list.add_theme_constant_override("separation", 4)
	_lobby_list.visible = false
	$Center/Panel/Body/JoinBox.add_child(_lobby_list)

	body.add_child(_game_row)
	body.add_child(_bots_row)
	body.add_child(_minigame_picker)
	body.add_child(_game_hint)
	body.move_child(_back_button, body.get_child_count() - 1)

	# Secondary LAN code under the main code: instantly usable on the same
	# Wi-Fi even when the router refuses UPnP.
	_lan_row = HBoxContainer.new()
	_lan_row.add_theme_constant_override("separation", 8)
	_lan_code_label = Label.new()
	_lan_code_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lan_code_label.add_theme_font_size_override("font_size", 13)
	_lan_code_label.add_theme_color_override("font_color", UiPalette.BLUE_DARK)
	_lan_code_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lan_row.add_child(_lan_code_label)
	_copy_lan_button = _candy("COPY LAN", UiPalette.CYAN, 34, 13)
	_copy_lan_button.custom_minimum_size = Vector2(120, 34)
	_copy_lan_button.pressed.connect(_on_copy_lan_pressed)
	_lan_row.add_child(_copy_lan_button)
	_host_box.add_child(_lan_row)
	_host_box.move_child(_lan_row, 3) # under CodeRow


func _candy(text: String, color: Color, height: int, font_size: int) -> Button:
	var button := Button.new()
	button.set_script(load(CANDY_BUTTON))
	button.set("fill_color", color)
	button.set("corner_radius", mini(int(height / 2), 28))
	button.text = text
	button.custom_minimum_size = Vector2(0, height)
	button.add_theme_font_size_override("font_size", font_size)
	return button


func _pill(labels: PackedStringArray, values: Array, start_index: int) -> Button:
	var button := Button.new()
	button.set_script(load(PILL_CYCLER))
	button.set("corner_radius", 22)
	button.set("shadow_offset", 6)
	button.custom_minimum_size = Vector2(0, 44)
	button.add_theme_font_size_override("font_size", 17)
	button.call("configure", labels, values, start_index)
	return button


func _host_can_configure() -> bool:
	return not Network.is_session_active() or Network.is_host


func _set_session_state(state: String) -> void:
	## "idle" shows host/join setup, "host" shows the live host panel, and
	## "client" hides host-only configuration.
	_session_state = state
	var editing: bool = state == "idle"
	_profile_row.visible = editing
	_mode_row.visible = editing
	_mode_hint.visible = editing
	_public_ip_row.visible = editing and _mode == MODE_ONLINE and _advanced_open
	_advanced_button.visible = editing and _mode == MODE_ONLINE
	_host_button.visible = editing
	_join_box.visible = editing
	_server_box.visible = editing and _mode == MODE_ONLINE
	_host_box.visible = not editing
	# Game/bot options only matter once you are hosting.
	_game_row.visible = state == "host"
	_bots_row.visible = state == "host"
	_minigame_picker.visible = state == "host" and GameSettings.multiplayer_mode == GameSettings.GAME_MINIGAMES
	_game_hint.visible = state == "host"
	if editing:
		_join_status.visible = false
	else:
		_join_box.visible = false
		_host_button.visible = false


func _on_game_mode(mode: String) -> void:
	if not _host_can_configure():
		return
	GameSettings.set_multiplayer_mode(mode)
	if Network.is_host:
		Network.configure_session(mode, GameSettings.bots_enabled,
			GameSettings.effective_bot_count())
	_refresh_session_controls()


func _on_bots_changed(value: Variant) -> void:
	if not _host_can_configure():
		return
	GameSettings.set_bot_total(int(value))
	if Network.is_host:
		Network.configure_session(GameSettings.multiplayer_mode,
			GameSettings.bots_enabled, GameSettings.effective_bot_count())
	_refresh_session_controls()


func _on_advanced_pressed() -> void:
	_advanced_open = not _advanced_open
	_advanced_button.set("fill_color", UiPalette.YELLOW if _advanced_open else UiPalette.TEXT_DIM)
	_advanced_button.text = "HIDE ADVANCED" if _advanced_open else "ADVANCED"
	_public_ip_row.visible = _mode == MODE_ONLINE and _advanced_open


func _on_choose_minigame() -> void:
	SceneLoader.go_to(MINIGAMES_SCENE, "MINIGAMES", "CHOOSE A MINIGAME")


func _refresh_session_controls() -> void:
	if _game_row == null:
		return
	var mode: String = Network.session_mode if Network.is_session_active() else GameSettings.multiplayer_mode
	var count: int = Network.session_bot_count if Network.is_session_active() else GameSettings.effective_bot_count()
	var can_edit: bool = _host_can_configure()
	_game_pill.call("set_index", 0 if mode == GameSettings.GAME_SANDBOX else 1)
	_game_pill.set("fill_color", UiPalette.GRASS if mode == GameSettings.GAME_MINIGAMES else UiPalette.YELLOW)
	_game_pill.disabled = not can_edit
	_bots_pill.call("set_index", count)
	_bots_pill.set("fill_color", UiPalette.GRASS if count > 0 else UiPalette.TEXT_DIM)
	_bots_pill.disabled = not can_edit
	_minigame_picker.visible = _session_state == "host" and mode == GameSettings.GAME_MINIGAMES
	_start_button.text = "START RACE" if mode == GameSettings.GAME_MINIGAMES else "START SANDBOX"
	_game_hint.text = "Host picks the game and bots. Everyone loads the same world."
	if not can_edit:
		_game_hint.text = "Waiting for the host to start."


func _on_name_typed(_text: String) -> void:
	# Keep the field responsive; full sanitising happens on commit.
	pass


func _commit_name() -> void:
	var clean: String = GameSettings.sanitize_name(_name_input.text)
	_name_input.text = clean
	Network.set_local_name(clean)
	_refresh_players()


func _set_mode(mode: String) -> void:
	_mode = MODE_LAN if mode == MODE_LAN else MODE_ONLINE
	GameSettings.set_connection_preference(_mode)
	Network.custom_public_ip = _public_ip_input.text if _mode == MODE_ONLINE else ""
	if _mode_pill != null:
		_mode_pill.call("set_index", 0 if _mode == MODE_ONLINE else 1)
		_mode_pill.set("fill_color", UiPalette.BLUE if _mode == MODE_ONLINE else UiPalette.GRASS)
	if _advanced_button != null:
		_advanced_button.visible = _mode == MODE_ONLINE
	_public_ip_row.visible = _mode == MODE_ONLINE and _advanced_open
	_server_box.visible = _mode == MODE_ONLINE
	_mode_hint.text = "Server field is optional on your Wi-Fi; enter the public Pi address for internet friends." \
		if _mode == MODE_ONLINE else "Same network only. No port forwarding needed."
	_refresh_session_controls()


func _on_host_pressed() -> void:
	_commit_name()
	_clear_lobby_list()
	_host_button.disabled = true
	_set_session_state("host")
	_host_status.text = "Opening a port (routers can take a moment)..."
	# START/COPY only work once the server actually exists.
	_start_button.visible = false
	_copy_button.visible = false
	_code_label.text = "...."
	Network.host_game(_mode)


func _on_host_failed(reason: String) -> void:
	_host_button.disabled = false
	_set_session_state("idle")
	_host_status.text = reason
	_join_status.visible = true
	_join_status.text = reason


func _on_host_started(code: String) -> void:
	_set_session_state("host")
	_start_button.visible = true
	_copy_button.visible = true
	_code_label.text = code
	_lan_row.visible = not Network.relay_active and _mode == MODE_ONLINE \
		and Network.online_code != "" and Network.lan_code != ""
	_lan_code_label.text = "LAN: " + Network.lan_code
	if Network.relay_active:
		var server_host: String = Network.relay_server_host if Network.relay_base_public \
			else (Network.relay_public_host if Network.relay_public_host != "" else Network.relay_lan_host)
		var tunnel: String = "TCP tunnel" if Network.relay_tunnel_token != "" else "direct UDP"
		if server_host != "":
			_host_status.text = "Server: %s (%s) - share code %s." % [server_host, tunnel, code]
		else:
			_host_status.text = "Online via the Cart Slop Pi server (%s) - share code %s." % [tunnel, code]
	elif _mode == MODE_LAN:
		_host_status.text = "Wi-Fi / LAN - share this code with players on your network."
	elif Network.has_online_route() and not Network.upnp_mapped:
		_host_status.text = "Using your PUBLIC IP - make sure UDP %d is forwarded to this PC." % Network.port
	elif Network.has_online_route():
		_host_status.text = "Online - share the main code with anyone. LAN code works on your Wi-Fi."
	elif Network.behind_cgnat:
		_host_status.text = "Your ISP uses carrier NAT (CGNAT). Online P2P needs a VPN/tunnel or manual forwarding."
	elif Network.public_address != "":
		_host_status.text = "No automatic port. Use the LAN code on Wi-Fi, forward UDP %d (public IP %s), or use a VPN/tunnel." % [Network.port, Network.public_address]
	else:
		_host_status.text = "No internet route found. Use the LAN code on Wi-Fi, forward UDP %d, or use a VPN/tunnel." % Network.port
	_refresh_players()


func _on_code_updated(code: String) -> void:
	_code_label.text = code
	if Network.has_online_route():
		_lan_row.visible = Network.lan_code != ""
		_lan_code_label.text = "LAN: " + Network.lan_code
		_host_status.text = "Online route ready - anyone with this code can join."


func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(_code_label.text)
	_host_status.text = "Main code copied to the clipboard."


func _on_copy_lan_pressed() -> void:
	DisplayServer.clipboard_set(Network.lan_code)
	_host_status.text = "LAN code copied - use it on the same Wi-Fi."


func _on_start_pressed() -> void:
	var mode: String = GameSettings.multiplayer_mode
	Network.start_game(
		Network.RACE_SCENE if mode == GameSettings.GAME_MINIGAMES else Network.GAME_SCENE,
		mode)


func _on_browse_pressed() -> void:
	_browse_button.disabled = true
	_join_status.visible = true
	_join_status.text = "Looking for rooms..."
	var lobbies: Array = await Network.fetch_lobbies()
	_clear_lobby_list()
	if lobbies.is_empty():
		_join_status.text = "No lobby server or rooms found. Host a game first."
		_browse_button.disabled = false
		return
	_lobby_list.visible = true
	for entry: Variant in lobbies:
		if not (entry is Dictionary):
			continue
		var lobby: Dictionary = entry as Dictionary
		var code: String = str(lobby.get("room_code", ""))
		if code == "":
			continue
		var label: String = "%s  ·  %d player%s  ·  %s" % [
			str(lobby.get("name", "HOST")), int(lobby.get("players", 1)),
			"" if int(lobby.get("players", 1)) == 1 else "s", code]
		var button: Button = _candy(label, UiPalette.YELLOW, 38, 15)
		button.pressed.connect(func() -> void:
			_join_input.text = code
			_on_join_pressed())
		_lobby_list.add_child(button)
	_browse_button.disabled = false
	_join_status.text = "Pick a room or type its code."


func _clear_lobby_list() -> void:
	for child: Node in _lobby_list.get_children():
		child.queue_free()
	_lobby_list.visible = false


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
	_clear_lobby_list()
	_set_session_state("client")
	_start_button.visible = false
	_copy_button.visible = false
	_code_label.visible = false
	_lan_row.visible = false
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
	Network.leave()
	SceneLoader.end_task()
	get_tree().change_scene_to_file(PLAY_MENU_SCENE)
