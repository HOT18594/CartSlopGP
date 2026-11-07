extends Control
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## Multiplayer lobby. One clean column, no decoration, no filler.
##
##   header: title / back
##   profile row: name + tag colour
##   idle: 1 HOST A ROOM (two buttons), 2 JOIN A ROOM (code + two browse buttons)
##   room: one room card, host settings, START, LEAVE ROOM
##
## Room lists no longer dump into the page. Both FIND LAN ROOMS and BROWSE
## ONLINE ROOMS open the searchable RoomBrowser popup instead.

const PLAY_MENU_SCENE: String = "res://scenes/ui/play_menu.tscn"
const MINIGAMES_SCENE: String = "res://scenes/ui/minigames_menu.tscn"
const VEHICLE_SCENE: String = "res://scenes/ui/vehicle_select.tscn"
const LOBBY_SCENE: String = "res://scenes/ui/lobby_menu.tscn"
const ROOM_BROWSER_SCENE: String = "res://scenes/ui/room_browser.tscn"
const Catalog := preload("res://scripts/vehicles/vehicle_catalog.gd")
const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const CANDY_BUTTON: String = "res://scripts/ui/candy_button.gd"
const PILL_CYCLER: String = "res://scripts/ui/pill_cycler.gd"

const SERVER_DOWN: String = "Game server is down. Try again later."

const BOT_LABELS: PackedStringArray = ["NO BOTS", "1 BOT", "2 BOTS", "3 BOTS", "4 BOTS", "5 BOTS"]
const BOT_VALUES: Array[int] = [0, 1, 2, 3, 4, 5]
const TAG_COLORS: Array[Dictionary] = [
	{"name": "YELLOW", "hex": "ffd22e"},
	{"name": "CREAM", "hex": "fff6e3"},
	{"name": "CYAN", "hex": "45b6f0"},
	{"name": "GREEN", "hex": "4cd964"},
	{"name": "PINK", "hex": "f26ca7"},
	{"name": "RED", "hex": "ff4d4d"},
	{"name": "ORANGE", "hex": "ff9f43"},
	{"name": "PURPLE", "hex": "a06cff"},
]

@onready var _profile_row: HBoxContainer = $Frame/Panel/Shell/ProfileRow
@onready var _body: VBoxContainer = $Frame/Panel/Shell/Content/Body
@onready var _status: Label = %StatusLabel
@onready var _back_button: Button = %BackButton

var _name_input: LineEdit
var _typing_label: Label
var _typing_blink: float = 0.0
var _idle_box: VBoxContainer
var _room_box: VBoxContainer
var _join_input: LineEdit
var _join_button: Button
var _lan_scan_button: Button
var _browse_button: Button
var _host_pi_button: Button
var _host_card: VBoxContainer
var _code_caption: Label
var _code_label: Label
var _copy_button: Button
var _leave_button: Button
var _host_hint: Label
var _players_box: VBoxContainer
var _players_header: Label
var _config_box: VBoxContainer
var _start_button: Button
var _game_pill: Button
var _bots_pill: Button
var _map_button: Button
var _vehicle_button: Button
var _browser: Control
var _browser_mode: String = "online"
var _tag_swatch_buttons: Dictionary = {} ## hex -> Button
var _state: String = "idle"
var _server_checked: bool = false


func _ready() -> void:
	CursorController.set_menu_mode(true)
	_build_ui()
	Network.host_started.connect(_on_host_started)
	Network.host_failed.connect(_on_host_failed)
	Network.join_succeeded.connect(_on_join_succeeded)
	Network.join_failed.connect(_on_join_failed)
	Network.join_status_changed.connect(_on_join_status)
	Network.peers_changed.connect(_refresh_players)
	Network.names_changed.connect(_refresh_players)
	Network.tag_colors_changed.connect(_refresh_players)
	Network.ping_table_changed.connect(_refresh_players)
	Network.latency_changed.connect(func(_ms: int) -> void: _refresh_players())
	Network.session_ended.connect(_on_session_ended)
	Network.session_config_changed.connect(_refresh_config)
	Network.server_status_changed.connect(_on_server_status)

	_name_input.text = GameSettings.player_name
	_set_state("idle")
	_set_server_status(false, "checking")
	_probe_server()
	if Network.is_host and Network.is_session_active():
		_on_host_started(Network.join_code)
	elif Network.is_client and Network.is_connected_to_server():
		_on_join_succeeded()
	call_deferred("_enter")


func _enter() -> void:
	UiAnim.pop($Frame/Panel)
	MenuNav.refresh()


# --------------------------------------------------------------------------
# small builders


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
	button.set("shadow_offset", 5)
	button.custom_minimum_size = Vector2(0, 46)
	button.add_theme_font_size_override("font_size", 17)
	button.call("configure", labels, values, start_index)
	return button


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", UiPalette.INK)
	return label


func _section(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", UiPalette.INK)
	return label


func _hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", UiPalette.BLUE_DARK)
	return label


func _card(parent: Node) -> VBoxContainer:
	## Plain rounded panel. No coloured top bar - it carried no information.
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.CREAM
	style.set_corner_radius_all(20)
	style.set_border_width_all(4)
	style.border_color = UiPalette.INK
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(column)
	return column


# --------------------------------------------------------------------------
# layout


func _build_ui() -> void:
	_back_button.pressed.connect(_on_back_pressed)
	_build_profile()
	_create_browser()
	_build_idle()
	_build_room()
	_set_status("")


func _build_profile() -> void:
	_profile_row.add_child(_caption("NAME"))
	_name_input = LineEdit.new()
	_name_input.placeholder_text = "YOUR NAME"
	_name_input.max_length = 16
	_name_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_input.custom_minimum_size = Vector2(230, 50)
	_name_input.text_submitted.connect(func(_t: String) -> void: _commit_name())
	_name_input.focus_exited.connect(_commit_name)
	_name_input.focus_entered.connect(_on_name_focus.bind(true))
	_name_input.focus_exited.connect(_on_name_focus.bind(false))
	_profile_row.add_child(_name_input)
	_typing_label = Label.new()
	_typing_label.text = "TYPING"
	_typing_label.visible = false
	_typing_label.custom_minimum_size = Vector2(62, 0)
	_typing_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_typing_label.add_theme_font_size_override("font_size", 11)
	_typing_label.add_theme_color_override("font_color", UiPalette.GRASS)
	_profile_row.add_child(_typing_label)

	_profile_row.add_child(_caption("TAG"))
	var swatch_grid := GridContainer.new()
	swatch_grid.columns = 8
	swatch_grid.add_theme_constant_override("h_separation", 6)
	_profile_row.add_child(swatch_grid)
	for swatch: Dictionary in TAG_COLORS:
		var hex: String = str(swatch["hex"])
		var swatch_button := Button.new()
		# UiKit must not force these into 54 px tall pills.
		swatch_button.set_meta("skip_kit", true)
		swatch_button.custom_minimum_size = Vector2(40, 40)
		swatch_button.tooltip_text = "%s NAME TAG" % str(swatch["name"])
		var swatch_style := StyleBoxFlat.new()
		swatch_style.bg_color = Color(hex)
		swatch_style.set_corner_radius_all(9)
		swatch_style.set_border_width_all(3)
		swatch_style.border_color = UiPalette.INK
		swatch_button.add_theme_stylebox_override("normal", swatch_style)
		var hover_style: StyleBoxFlat = swatch_style.duplicate()
		hover_style.bg_color = Color(hex).lightened(0.12)
		swatch_button.add_theme_stylebox_override("hover", hover_style)
		swatch_button.add_theme_stylebox_override("pressed", hover_style)
		swatch_button.pressed.connect(_on_tag_color.bind(hex))
		swatch_grid.add_child(swatch_button)
		_tag_swatch_buttons[hex] = swatch_button
	_refresh_tag_swatches()


func _create_browser() -> void:
	_browser = (load(ROOM_BROWSER_SCENE) as PackedScene).instantiate()
	add_child(_browser)
	_browser.connect("room_selected", _on_room_selected)


func _build_idle() -> void:
	_idle_box = VBoxContainer.new()
	_idle_box.add_theme_constant_override("separation", 14)
	_idle_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(_idle_box)

	var host_step: Label = _section("1   HOST A ROOM")
	host_step.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_idle_box.add_child(host_step)
	var host_row := HBoxContainer.new()
	host_row.add_theme_constant_override("separation", 14)
	host_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_idle_box.add_child(host_row)
	var lan_button := _candy("HOST LAN ROOM", UiPalette.GRASS, 64, 22)
	lan_button.custom_minimum_size.x = 320
	lan_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	lan_button.pressed.connect(_on_host_lan)
	host_row.add_child(lan_button)
	_host_pi_button = _candy("CREATE ONLINE ROOM", UiPalette.BLUE, 64, 22)
	_host_pi_button.custom_minimum_size.x = 320
	_host_pi_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_host_pi_button.pressed.connect(_on_host_pi)
	host_row.add_child(_host_pi_button)

	var join_step: Label = _section("2   JOIN A ROOM")
	join_step.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_idle_box.add_child(join_step)
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 12)
	join_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_idle_box.add_child(join_row)
	_join_input = LineEdit.new()
	_join_input.placeholder_text = "5-LETTER CODE"
	_join_input.max_length = 5
	_join_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_join_input.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_join_input.custom_minimum_size = Vector2(360, 58)
	_join_input.add_theme_font_size_override("font_size", 26)
	_join_input.text_changed.connect(_on_code_typed)
	_join_input.text_submitted.connect(func(_t: String) -> void: _on_join_pressed())
	join_row.add_child(_join_input)
	_join_button = _candy("JOIN", UiPalette.YELLOW, 58, 24)
	_join_button.custom_minimum_size = Vector2(180, 58)
	_join_button.pressed.connect(_on_join_pressed)
	join_row.add_child(_join_button)

	var browse_row := HBoxContainer.new()
	browse_row.add_theme_constant_override("separation", 12)
	browse_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_idle_box.add_child(browse_row)
	_lan_scan_button = _candy("FIND LAN ROOMS", UiPalette.CYAN, 52, 18)
	_lan_scan_button.custom_minimum_size.x = 320
	_lan_scan_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_lan_scan_button.pressed.connect(_on_find_lan)
	browse_row.add_child(_lan_scan_button)
	_browse_button = _candy("BROWSE ONLINE ROOMS", UiPalette.BLUE, 52, 18)
	_browse_button.custom_minimum_size.x = 320
	_browse_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_browse_button.pressed.connect(_on_browse_online)
	browse_row.add_child(_browse_button)


func _build_room() -> void:
	_room_box = VBoxContainer.new()
	_room_box.add_theme_constant_override("separation", 14)
	_room_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(_room_box)

	_room_box.add_child(_section("YOUR ROOM"))
	_host_card = _card(_room_box)
	# Code on the left, players on the right. No tall stack of unrelated rows.
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 18)
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host_card.add_child(split)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(left)
	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(3, 0)
	divider.color = Color(UiPalette.INK, 0.18)
	divider.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(divider)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)

	_code_caption = _caption("ROOM CODE")
	_code_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_caption.add_theme_font_size_override("font_size", 13)
	_code_caption.add_theme_color_override("font_color", UiPalette.BLUE_DARK)
	left.add_child(_code_caption)
	_code_label = Label.new()
	_code_label.text = "-----"
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_label.theme_type_variation = &"TitleLabel"
	_code_label.add_theme_font_size_override("font_size", 42)
	_code_label.add_theme_color_override("font_color", UiPalette.INK)
	left.add_child(_code_label)
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 10)
	code_row.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_child(code_row)
	_copy_button = _candy("COPY CODE", UiPalette.CYAN, 46, 17)
	_copy_button.custom_minimum_size = Vector2(178, 46)
	_copy_button.pressed.connect(_on_copy_code)
	code_row.add_child(_copy_button)
	_leave_button = _candy("LEAVE ROOM", UiPalette.RED, 46, 17)
	_leave_button.custom_minimum_size = Vector2(178, 46)
	_leave_button.pressed.connect(_on_leave_pressed)
	code_row.add_child(_leave_button)
	# The hint is about the code, so it belongs in the left column.
	_host_hint = _hint("")
	left.add_child(_host_hint)

	_players_header = _section("PLAYERS")
	right.add_child(_players_header)
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 3)
	right.add_child(_players_box)

	_config_box = VBoxContainer.new()
	_config_box.add_theme_constant_override("separation", 8)
	_room_box.add_child(_config_box)
	_config_box.add_child(_section("HOST SETTINGS"))
	var config_top := HBoxContainer.new()
	config_top.add_theme_constant_override("separation", 10)
	config_top.alignment = BoxContainer.ALIGNMENT_CENTER
	_config_box.add_child(config_top)
	_game_pill = _pill(PackedStringArray(["SANDBOX", "MINIGAMES"]),
		[GameSettings.GAME_SANDBOX, GameSettings.GAME_MINIGAMES], 0)
	_game_pill.custom_minimum_size.x = 330
	_game_pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_game_pill.connect("option_changed", func(value: Variant) -> void: _on_game_mode(str(value)))
	config_top.add_child(_game_pill)
	_bots_pill = _pill(BOT_LABELS, BOT_VALUES, GameSettings.effective_bot_count())
	_bots_pill.custom_minimum_size.x = 330
	_bots_pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bots_pill.connect("option_changed", _on_bots_changed)
	config_top.add_child(_bots_pill)
	var config_map := HBoxContainer.new()
	config_map.add_theme_constant_override("separation", 10)
	config_map.alignment = BoxContainer.ALIGNMENT_CENTER
	_config_box.add_child(config_map)
	_map_button = _candy("MAP: MEADOW LOOP", UiPalette.CYAN, 48, 16)
	_map_button.custom_minimum_size.x = 330
	_map_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_map_button.pressed.connect(_on_choose_map)
	config_map.add_child(_map_button)
	_vehicle_button = _candy("VEHICLE: SHOPPING CART", UiPalette.BLUE, 48, 16)
	_vehicle_button.custom_minimum_size.x = 330
	_vehicle_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_vehicle_button.pressed.connect(_on_change_vehicle)
	config_map.add_child(_vehicle_button)

	_start_button = _candy("START", UiPalette.YELLOW, 62, 26)
	_start_button.custom_minimum_size.x = 400
	_start_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_start_button.pressed.connect(_on_start_pressed)
	_room_box.add_child(_start_button)


func _on_name_focus(focused: bool) -> void:
	if _typing_label != null:
		_typing_label.visible = focused
		_typing_blink = 0.0


func _process(delta: float) -> void:
	if _typing_label != null and _typing_label.visible:
		_typing_blink += delta
		_typing_label.modulate.a = 0.55 + 0.45 * sin(_typing_blink * 7.0)


# --------------------------------------------------------------------------
# room browser


func _on_find_lan() -> void:
	_browser_mode = "lan"
	_browser.call("open", "lan")


func _on_browse_online() -> void:
	if not Network.server_online:
		_set_status(SERVER_DOWN)
		return
	_browser_mode = "online"
	_browser.call("open", "online")


func _on_room_selected(room: Dictionary) -> void:
	if _browser_mode == "lan":
		Network.join_lan_room(room)
		return
	var code: String = str(room.get("room_code", "")).to_upper()
	if code.length() != 5:
		return
	_join_input.text = code
	_on_join_pressed()


# --------------------------------------------------------------------------
# server status


func _probe_server() -> void:
	var ok: bool = await Network.probe_server()
	if not is_inside_tree():
		return
	_set_server_status(ok, "online" if ok else "offline")


func _on_server_status(online: bool, detail: String) -> void:
	_set_server_status(online, detail)


func _set_server_status(online: bool, detail: String) -> void:
	# Players do not need a server status light. Online means nothing is shown.
	# Offline gets one plain error line, after the check has actually finished.
	if detail == "checking":
		return
	_server_checked = true
	if _join_button != null:
		_join_button.disabled = not online
	if _join_input != null:
		_join_input.editable = online
	if _browse_button != null:
		_browse_button.disabled = not online
	if _host_pi_button != null:
		_host_pi_button.disabled = not online
	_refresh_status()


# --------------------------------------------------------------------------
# state


func _set_state(state: String) -> void:
	_state = state
	var idle: bool = state == "idle"
	_idle_box.visible = idle
	_room_box.visible = not idle
	_config_box.visible = state == "host"
	_start_button.visible = state == "host"
	_copy_button.visible = state == "host" and not Network.is_lan()
	_leave_button.visible = not idle
	_code_caption.visible = not idle
	if idle:
		_code_label.text = "-----"
		_refresh_status()
		_join_button.disabled = not Network.server_online
		_browse_button.disabled = not Network.server_online
		_host_pi_button.disabled = not Network.server_online
	else:
		UiAnim.fade_in(_room_box, 0.22)
	_refresh_config()
	_refresh_players()
	MenuNav.refresh()


func _refresh_config() -> void:
	if _game_pill == null:
		return
	var mode: String = Network.session_mode if Network.is_session_active() \
		else GameSettings.multiplayer_mode
	_game_pill.call("set_index", 0 if mode == GameSettings.GAME_SANDBOX else 1)
	_game_pill.set("fill_color", UiPalette.GRASS if mode == GameSettings.GAME_MINIGAMES else UiPalette.YELLOW)
	_bots_pill.call("set_index", GameSettings.effective_bot_count())
	_bots_pill.set("fill_color", UiPalette.GRASS if GameSettings.effective_bot_count() > 0 else UiPalette.TEXT_DIM)
	_map_button.visible = mode == GameSettings.GAME_MINIGAMES
	var vehicle_id: String = GameSettings.minigame_vehicle if mode == GameSettings.GAME_MINIGAMES \
		else GameSettings.selected_vehicle
	var vehicle: Dictionary = Catalog.find(vehicle_id)
	if mode == GameSettings.GAME_MINIGAMES and Network.is_host:
		_vehicle_button.text = "RACE CAR: %s  (ALL PLAYERS)" % str(vehicle.get("name", "SHOPPING CART"))
	else:
		_vehicle_button.text = "VEHICLE: " + str(vehicle.get("name", "SHOPPING CART"))
	_start_button.text = "START RACE" if mode == GameSettings.GAME_MINIGAMES else "START SANDBOX"


# --------------------------------------------------------------------------
# name, tag colour and code


func _commit_name() -> void:
	var clean: String = GameSettings.sanitize_name(_name_input.text)
	_name_input.text = clean
	Network.set_local_name(clean)


func _on_tag_color(hex: String) -> void:
	Network.set_local_tag_color(hex)
	_refresh_tag_swatches()


func _refresh_tag_swatches() -> void:
	var selected: String = GameSettings.player_tag_color
	for hex: String in _tag_swatch_buttons:
		var button: Button = _tag_swatch_buttons[hex]
		var style: StyleBoxFlat = button.get_theme_stylebox("normal") as StyleBoxFlat
		if style != null:
			style.set_border_width_all(6 if hex == selected else 3)
		button.scale = Vector2.ONE * (1.12 if hex == selected else 1.0)


func _on_code_typed(text: String) -> void:
	var clean: String = ""
	for character: String in text.to_upper():
		if Network.ROOM_CODE_ALPHABET.contains(character):
			clean += character
	if clean.length() > 5:
		clean = clean.substr(0, 5)
	if clean != _join_input.text:
		_join_input.text = clean
		_join_input.caret_column = clean.length()


# --------------------------------------------------------------------------
# hosting


func _on_host_lan() -> void:
	_begin_host("lan")


func _on_host_pi() -> void:
	if not Network.server_online:
		_set_status(SERVER_DOWN)
		return
	_begin_host("pi")


func _begin_host(mode: String) -> void:
	_commit_name()
	_set_state("host")
	_code_caption.text = "OPENING"
	_code_label.text = "....."
	_host_hint.text = "Starting the room..."
	_set_status("")
	_start_button.visible = false
	_copy_button.visible = false
	Network.host_game(mode)


func _on_host_started(code: String) -> void:
	_set_state("host")
	_start_button.visible = true
	if Network.is_lan():
		_code_caption.text = "ROOM ON THIS WI-FI"
		_code_label.text = "LAN"
		_copy_button.visible = false
		_host_hint.text = "Players on your Wi-Fi can find this room."
	else:
		_code_caption.text = "5-LETTER ROOM CODE"
		_code_label.text = code
		_copy_button.visible = true
		_host_hint.text = "Share this code with your friends."
	_refresh_config()
	_refresh_players()


func _on_host_failed(reason: String) -> void:
	_set_state("idle")
	_set_status(reason)


func _on_copy_code() -> void:
	if _code_label.text != "" and _code_label.text != "LAN":
		DisplayServer.clipboard_set(_code_label.text)
		_set_status("Room code copied.")


# --------------------------------------------------------------------------
# joining


func _on_join_pressed() -> void:
	_commit_name()
	if not Network.server_online:
		_set_status(SERVER_DOWN)
		return
	var code: String = _join_input.text.strip_edges()
	if code.length() != 5:
		_set_status("Enter the 5-letter room code from the host.")
		return
	_join_button.disabled = true
	_set_status("Connecting to the Cart Slop server...")
	Network.join_game(code)


func _on_join_status(text: String) -> void:
	_set_status(text)


func _on_join_failed(reason: String) -> void:
	_join_button.disabled = false
	_set_status(reason)


func _on_join_succeeded() -> void:
	_set_state("client")
	_code_caption.text = "CONNECTED"
	_code_label.text = "ROOM"
	_copy_button.visible = false
	_start_button.visible = false
	_host_hint.text = "Waiting for the host to start..."
	_refresh_players()


func _on_session_ended(reason: String) -> void:
	_set_state("idle")
	if reason != "":
		_set_status(reason)


func _set_status(text: String) -> void:
	_status.text = text
	_status.visible = text != ""


func _refresh_status() -> void:
	## Keep the "server is down" line across state changes without ever
	## overwriting a real join/host error with a stale online message.
	if _status.text != "" and _status.text != SERVER_DOWN:
		return
	if _server_checked and not Network.server_online:
		_set_status(SERVER_DOWN)
	else:
		_set_status("")


# --------------------------------------------------------------------------
# host configuration


func _on_game_mode(mode: String) -> void:
	if not Network.is_host:
		return
	GameSettings.set_multiplayer_mode(mode)
	Network.configure_session(mode, GameSettings.bots_enabled, GameSettings.effective_bot_count())
	_refresh_config()


func _on_bots_changed(value: Variant) -> void:
	if not Network.is_host:
		return
	GameSettings.set_bot_total(int(value))
	Network.configure_session(GameSettings.multiplayer_mode,
		GameSettings.bots_enabled, GameSettings.effective_bot_count())
	_refresh_config()


func _on_choose_map() -> void:
	GameSettings.vehicle_return_scene = LOBBY_SCENE
	SceneLoader.go_to(MINIGAMES_SCENE, "CHOOSE A MAP", "PICK A MAP")


func _on_change_vehicle() -> void:
	GameSettings.vehicle_return_scene = LOBBY_SCENE
	GameSettings.vehicle_return_title = "MULTIPLAYER"
	GameSettings.vehicle_edit_minigame = GameSettings.multiplayer_mode == GameSettings.GAME_MINIGAMES
	SceneLoader.go_to(VEHICLE_SCENE, "VEHICLE", "Choose your ride")


func _on_start_pressed() -> void:
	var mode: String = GameSettings.multiplayer_mode
	Network.start_game(
		Network.RACE_SCENE if mode == GameSettings.GAME_MINIGAMES else Network.GAME_SCENE,
		mode)


# --------------------------------------------------------------------------
# players


func _refresh_players() -> void:
	if _players_box == null:
		return
	for child: Node in _players_box.get_children():
		child.queue_free()
	if not Network.is_session_active():
		_players_header.text = "PLAYERS"
		return
	var ids: Array[int] = [multiplayer.get_unique_id()]
	for peer_id: int in multiplayer.get_peers():
		ids.append(peer_id)
	ids.sort()
	_players_header.text = "PLAYERS   %d / 8" % ids.size()
	for peer_id: int in ids:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 7)
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(13, 13)
		dot.color = Network.color_of(peer_id) if Network.player_colors.has(peer_id) \
			else UiPalette.YELLOW
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)
		var label_text: String = Network.name_of(peer_id)
		if peer_id == multiplayer.get_unique_id():
			label_text += "  (YOU)"
		if peer_id == 1:
			label_text = "[HOST]  " + label_text
		var name_label := Label.new()
		name_label.text = label_text
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 16)
		name_label.add_theme_color_override("font_color", UiPalette.INK)
		row.add_child(name_label)
		if Network.is_session_active() and Network.is_connected_to_server():
			var ms: int = int(Network.ping_table.get(peer_id, 0))
			if ms <= 0 and not Network.is_host and peer_id == multiplayer.get_unique_id():
				ms = maxi(Network.latency_ms, 0)
			var ping_label := Label.new()
			ping_label.text = "%d ms" % ms
			ping_label.add_theme_font_size_override("font_size", 13)
			ping_label.add_theme_color_override("font_color", UiPalette.BLUE_DARK)
			row.add_child(ping_label)
		_players_box.add_child(row)


func _on_leave_pressed() -> void:
	Network.leave()
	_set_state("idle")
	UiAnim.pop($Frame/Panel)


func _on_back_pressed() -> void:
	Network.leave()
	SceneLoader.end_task()
	SceneLoader.go_to(PLAY_MENU_SCENE, "PLAY")
