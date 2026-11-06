extends Control
## Multiplayer lobby, Fall Guys-style.
##
## Two ways to start a world:
##   HOST ON THIS WI-FI  - this PC is the server; nearby players see the room.
##   HOST ONLINE         - the Cart Slop Pi returns a 5-letter room code.
## Joining is code-only for online rooms and room-card-only for LAN rooms.
## There is no IP address, port, hostname or advanced server field anywhere.

const PLAY_MENU_SCENE: String = "res://scenes/ui/play_menu.tscn"
const MINIGAMES_SCENE: String = "res://scenes/ui/minigames_menu.tscn"
const VEHICLE_SCENE: String = "res://scenes/ui/vehicle_select.tscn"
const LOBBY_SCENE: String = "res://scenes/ui/lobby_menu.tscn"
const Catalog := preload("res://scripts/vehicles/vehicle_catalog.gd")
const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const CANDY_BUTTON: String = "res://scripts/ui/candy_button.gd"
const PILL_CYCLER: String = "res://scripts/ui/pill_cycler.gd"

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

@onready var _body: VBoxContainer = $Center/Scroll/Panel/Body

var _name_input: LineEdit
var _typing_label: Label
var _typing_blink: float = 0.0
var _server_pill: Label
var _status: Label
var _profile_row: HBoxContainer
var _intro: Label
var _mode_row: HBoxContainer
var _join_card: VBoxContainer
var _join_input: LineEdit
var _join_button: Button
var _lan_scan_button: Button
var _browse_button: Button
var _host_pi_button: Button
var _lan_box: VBoxContainer
var _host_card: VBoxContainer
var _code_caption: Label
var _code_label: Label
var _copy_button: Button
var _host_hint: Label
var _players_box: VBoxContainer
var _config_box: VBoxContainer
var _start_button: Button
var _back_button: Button
var _game_pill: Button
var _bots_pill: Button
var _map_button: Button
var _vehicle_button: Button
var _tag_swatch_buttons: Dictionary = {} ## hex -> Button
var _state: String = "idle"
var _scanning: bool = false
var _browsing: bool = false


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


# --------------------------------------------------------------------------
# layout


func _build_ui() -> void:
	_body.add_theme_constant_override("separation", 8)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	_body.add_child(header)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = "MULTIPLAYER"
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", UiPalette.INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_server_pill = Label.new()
	_server_pill.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_server_pill.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_server_pill.custom_minimum_size = Vector2(230, 42)
	_server_pill.add_theme_font_size_override("font_size", 14)
	_server_pill.mouse_filter = Control.MOUSE_FILTER_STOP
	_server_pill.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_server_pill.tooltip_text = "Check the Cart Slop server again"
	_server_pill.gui_input.connect(_on_server_pill_input)
	header.add_child(_server_pill)

	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 4)
	rule.color = UiPalette.INK
	_body.add_child(rule)

	var profile := HBoxContainer.new()
	profile.add_theme_constant_override("separation", 10)
	_body.add_child(profile)
	_profile_row = profile
	var name_caption := _caption("YOUR NAME", 90)
	profile.add_child(name_caption)
	_name_input = LineEdit.new()
	_name_input.placeholder_text = "YOUR NAME"
	_name_input.max_length = 16
	_name_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_input.text_submitted.connect(func(_t: String) -> void: _commit_name())
	_name_input.focus_exited.connect(_commit_name)
	_name_input.focus_entered.connect(_on_name_focus.bind(true))
	_name_input.focus_exited.connect(_on_name_focus.bind(false))
	profile.add_child(_name_input)
	_typing_label = Label.new()
	_typing_label.text = "TYPING"
	_typing_label.visible = false
	_typing_label.custom_minimum_size = Vector2(74, 0)
	_typing_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_typing_label.add_theme_font_size_override("font_size", 12)
	_typing_label.add_theme_color_override("font_color", UiPalette.GRASS)
	profile.add_child(_typing_label)

	var tag_row := HBoxContainer.new()
	tag_row.add_theme_constant_override("separation", 7)
	_body.add_child(tag_row)
	tag_row.add_child(_caption("TAG COLOR", 90))
	for swatch: Dictionary in TAG_COLORS:
		var hex: String = str(swatch["hex"])
		var swatch_button := Button.new()
		swatch_button.custom_minimum_size = Vector2(38, 32)
		swatch_button.tooltip_text = "%s NAME TAG" % str(swatch["name"])
		swatch_button.focus_mode = Control.FOCUS_NONE
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
		tag_row.add_child(swatch_button)
		_tag_swatch_buttons[hex] = swatch_button
	_refresh_tag_swatches()

	var intro := Label.new()
	intro.text = "Host a world on your Wi-Fi, or let the Cart Slop server hand out a tiny room code."
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", 15)
	intro.add_theme_color_override("font_color", UiPalette.BLUE_DARK)
	_body.add_child(intro)
	_intro = intro

	# Two big host cards -----------------------------------------------------
	_mode_row = HBoxContainer.new()
	_mode_row.add_theme_constant_override("separation", 12)
	_body.add_child(_mode_row)

	var lan_card := _card(UiPalette.GRASS)
	var lan_title := _card_title("HOST ON THIS WI-FI")
	lan_card.add_child(lan_title)
	var lan_desc := _card_desc("No internet needed. Players on your Wi-Fi see the room appear.")
	lan_card.add_child(lan_desc)
	var lan_button := _candy("HOST LAN ROOM", UiPalette.GRASS, 54, 20)
	lan_button.pressed.connect(_on_host_lan)
	lan_card.add_child(lan_button)

	var pi_card := _card(UiPalette.BLUE)
	var pi_title := _card_title("HOST ONLINE")
	pi_card.add_child(pi_title)
	var pi_desc := _card_desc("The Cart Slop server gives you a 5-letter code. Works anywhere.")
	pi_card.add_child(pi_desc)
	var pi_button := _candy("CREATE ONLINE ROOM", UiPalette.BLUE, 54, 20)
	pi_button.pressed.connect(_on_host_pi)
	pi_card.add_child(pi_button)
	_host_pi_button = pi_button
	_attach_card(_mode_row, lan_card)
	_attach_card(_mode_row, pi_card)

	# Join card --------------------------------------------------------------
	_join_card = _card(UiPalette.YELLOW)
	_attach_card(_body, _join_card)
	var join_title := _card_title("JOIN A ROOM")
	_join_card.add_child(join_title)
	var join_hint := _card_desc("Type the 5-letter code from the host. No IP addresses, ever.")
	_join_card.add_child(join_hint)
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	_join_card.add_child(join_row)
	_join_input = LineEdit.new()
	_join_input.placeholder_text = "5-LETTER CODE"
	_join_input.max_length = 5
	_join_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_join_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_join_input.add_theme_font_size_override("font_size", 24)
	_join_input.text_changed.connect(_on_code_typed)
	_join_input.text_submitted.connect(func(_t: String) -> void: _on_join_pressed())
	join_row.add_child(_join_input)
	_join_button = _candy("JOIN", UiPalette.YELLOW, 54, 22)
	_join_button.custom_minimum_size = Vector2(160, 54)
	_join_button.pressed.connect(_on_join_pressed)
	join_row.add_child(_join_button)

	var lan_row := HBoxContainer.new()
	lan_row.add_theme_constant_override("separation", 8)
	_join_card.add_child(lan_row)
	_lan_scan_button = _candy("FIND LAN ROOMS", UiPalette.CYAN, 46, 17)
	_lan_scan_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lan_scan_button.pressed.connect(_scan_lan_rooms)
	lan_row.add_child(_lan_scan_button)
	_browse_button = _candy("BROWSE ONLINE ROOMS", UiPalette.BLUE, 46, 17)
	_browse_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_browse_button.pressed.connect(_browse_pi_rooms)
	lan_row.add_child(_browse_button)

	_lan_box = VBoxContainer.new()
	_lan_box.add_theme_constant_override("separation", 4)
	_join_card.add_child(_lan_box)

	# Live host / client card ------------------------------------------------
	_host_card = _card(UiPalette.CREAM)
	_attach_card(_body, _host_card)
	_code_caption = _caption("ROOM CODE", 0)
	_code_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_caption.add_theme_font_size_override("font_size", 14)
	_code_caption.add_theme_color_override("font_color", UiPalette.BLUE_DARK)
	_host_card.add_child(_code_caption)
	_code_label = Label.new()
	_code_label.text = "-----"
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_label.add_theme_font_size_override("font_size", 40)
	_code_label.add_theme_color_override("font_color", UiPalette.INK)
	_host_card.add_child(_code_label)
	_copy_button = _candy("COPY CODE", UiPalette.CYAN, 44, 18)
	_copy_button.pressed.connect(_on_copy_code)
	_host_card.add_child(_copy_button)
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 3)
	_host_card.add_child(_players_box)
	_host_hint = _card_desc("")
	_host_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_host_card.add_child(_host_hint)

	_config_box = VBoxContainer.new()
	_config_box.add_theme_constant_override("separation", 6)
	_host_card.add_child(_config_box)
	var config_top := HBoxContainer.new()
	config_top.add_theme_constant_override("separation", 8)
	_config_box.add_child(config_top)
	_game_pill = _pill(PackedStringArray(["SANDBOX", "MINIGAMES"]),
		[GameSettings.GAME_SANDBOX, GameSettings.GAME_MINIGAMES], 0)
	_game_pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_game_pill.connect("option_changed", func(value: Variant) -> void: _on_game_mode(str(value)))
	config_top.add_child(_game_pill)
	_bots_pill = _pill(BOT_LABELS, BOT_VALUES, GameSettings.effective_bot_count())
	_bots_pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bots_pill.connect("option_changed", _on_bots_changed)
	config_top.add_child(_bots_pill)
	var config_map := HBoxContainer.new()
	config_map.add_theme_constant_override("separation", 8)
	_config_box.add_child(config_map)
	_map_button = _candy("MAP: MEADOW LOOP", UiPalette.CYAN, 46, 16)
	_map_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_button.pressed.connect(_on_choose_map)
	config_map.add_child(_map_button)
	_vehicle_button = _candy("VEHICLE: SHOPPING CART", UiPalette.BLUE, 46, 16)
	_vehicle_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vehicle_button.pressed.connect(_on_change_vehicle)
	config_map.add_child(_vehicle_button)
	_start_button = _candy("START", UiPalette.YELLOW, 54, 24)
	_start_button.pressed.connect(_on_start_pressed)
	_host_card.add_child(_start_button)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", UiPalette.RED)
	_body.add_child(_status)

	_back_button = _candy("BACK", UiPalette.RED, 46, 20)
	_back_button.pressed.connect(_on_back_pressed)
	_body.add_child(_back_button)


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
	button.custom_minimum_size = Vector2(0, 44)
	button.add_theme_font_size_override("font_size", 17)
	button.call("configure", labels, values, start_index)
	return button


func _caption(text: String, width: int) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", UiPalette.INK)
	return label


func _card(accent: Color) -> VBoxContainer:
	## A chunky Fall Guys-style card. Returns the inner column; use
	## `_attach_card(parent, column)` to place the panel in the layout.
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.CREAM
	style.corner_radius_top_left = 22
	style.corner_radius_top_right = 22
	style.corner_radius_bottom_left = 22
	style.corner_radius_bottom_right = 22
	style.border_width_left = 5
	style.border_width_top = 5
	style.border_width_right = 5
	style.border_width_bottom = 5
	style.border_color = UiPalette.INK
	style.shadow_color = Color(0.12, 0.1, 0.23, 0.35)
	style.shadow_offset = Vector2(0, 7)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	panel.add_child(column)
	var bar := ColorRect.new()
	bar.custom_minimum_size = Vector2(0, 5)
	bar.color = accent
	column.add_child(bar)
	column.set_meta("panel", panel)
	return column


func _attach_card(parent: Node, column: VBoxContainer) -> void:
	var panel: PanelContainer = column.get_meta("panel")
	parent.add_child(panel)


func _show_card(column: VBoxContainer, value: bool) -> void:
	column.visible = value
	var panel: Variant = column.get_meta("panel", null)
	if panel is CanvasItem:
		(panel as CanvasItem).visible = value


func _card_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", UiPalette.INK)
	return label


func _card_desc(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", UiPalette.BLUE_DARK)
	return label


func _on_name_focus(focused: bool) -> void:
	if _typing_label != null:
		_typing_label.visible = focused
		_typing_blink = 0.0


func _process(delta: float) -> void:
	if _typing_label != null and _typing_label.visible:
		_typing_blink += delta
		_typing_label.modulate.a = 0.55 + 0.45 * sin(_typing_blink * 7.0)


# --------------------------------------------------------------------------
# server status


func _on_server_pill_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
		_set_server_status(false, "checking")
		_probe_server()


func _probe_server() -> void:
	var ok: bool = await Network.probe_server()
	if not is_inside_tree():
		return
	_set_server_status(ok, "online" if ok else "offline")


func _on_server_status(online: bool, detail: String) -> void:
	_set_server_status(online, detail)


func _set_server_status(online: bool, detail: String) -> void:
	if _server_pill == null:
		return
	if detail == "checking":
		_server_pill.text = "PI SERVER  ·  CHECKING"
		_server_pill.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	else:
		_server_pill.text = "PI SERVER  ·  " + ("ONLINE" if online else "OFFLINE")
		_server_pill.add_theme_color_override("font_color",
			UiPalette.GRASS if online else UiPalette.RED)
	if _join_button != null:
		_join_button.disabled = not online
	if _join_input != null:
		_join_input.editable = online
	if _browse_button != null:
		_browse_button.disabled = not online
	if _host_pi_button != null:
		_host_pi_button.disabled = not online


# --------------------------------------------------------------------------
# state


func _set_state(state: String) -> void:
	_state = state
	var idle: bool = state == "idle"
	_mode_row.visible = idle
	_profile_row.visible = idle
	_intro.visible = idle
	_show_card(_join_card, idle)
	_show_card(_host_card, not idle)
	_config_box.visible = state == "host"
	_start_button.visible = state == "host"
	_copy_button.visible = state == "host" and not Network.is_lan()
	_code_caption.visible = not idle
	_status.visible = not idle or _status.text != ""
	if idle:
		_code_label.text = "-----"
		_status.text = ""
		_lan_box.visible = false
		_join_button.disabled = not Network.server_online
		_browse_button.disabled = not Network.server_online
		_host_pi_button.disabled = not Network.server_online
	_refresh_config()
	_refresh_players()


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
		# One car for the whole field in races; only the name tags differ.
		_vehicle_button.text = "RACE CAR: %s  (ALL PLAYERS)" % str(vehicle.get("name", "SHOPPING CART"))
	else:
		_vehicle_button.text = "VEHICLE: " + str(vehicle.get("name", "SHOPPING CART"))
	_start_button.text = "START RACE" if mode == GameSettings.GAME_MINIGAMES else "START SANDBOX"


# --------------------------------------------------------------------------
# name and code


func _commit_name() -> void:
	var clean: String = GameSettings.sanitize_name(_name_input.text)
	_name_input.text = clean
	Network.set_local_name(clean)


func _on_tag_color(hex: String) -> void:
	## Pick a name tag colour; saved locally and announced to the session.
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
		_set_status("The Cart Slop server is offline. Host a LAN room or try again.")
		return
	_begin_host("pi")


func _begin_host(mode: String) -> void:
	_commit_name()
	_set_state("host")
	_code_caption.text = "OPENING"
	_code_label.text = "....."
	_host_hint.text = "Starting the room..."
	_status.text = ""
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
		_host_hint.text = "No code needed. Players on your Wi-Fi can pick this room from FIND LAN ROOMS."
	else:
		_code_caption.text = "5-LETTER ROOM CODE"
		_code_label.text = code
		_copy_button.visible = true
		_host_hint.text = "Share this code. Friends anywhere can join through the Cart Slop server."
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
		_set_status("The Cart Slop server is offline. Check the internet, or join a LAN room.")
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
	_config_box.visible = false
	_host_hint.text = "Waiting for the host to start..."
	_refresh_players()


func _on_session_ended(reason: String) -> void:
	_set_state("idle")
	if reason != "":
		_set_status(reason)


func _set_status(text: String) -> void:
	_status.text = text
	_status.visible = text != ""


# --------------------------------------------------------------------------
# LAN / online room lists


func _scan_lan_rooms() -> void:
	if _scanning:
		return
	_scanning = true
	_lan_scan_button.disabled = true
	_clear_rooms()
	_set_status("Looking for rooms on your Wi-Fi...")
	var rooms: Array = await Network.scan_lan_rooms()
	if not is_inside_tree():
		return
	_scanning = false
	_lan_scan_button.disabled = false
	if rooms.is_empty():
		_set_status("No LAN rooms found. Ask a friend to press HOST LAN ROOM.")
		return
	_lan_box.visible = true
	for entry: Variant in rooms:
		if not (entry is Dictionary):
			continue
		var room: Dictionary = entry as Dictionary
		var label: String = "%s  ·  %d player%s  ·  %s" % [
			str(room.get("name", "HOST")),
			int(room.get("players", 1)),
			"" if int(room.get("players", 1)) == 1 else "s",
			"IN GAME" if str(room.get("state", "lobby")) != "lobby" else "LOBBY",
		]
		var button: Button = _candy(label, UiPalette.CYAN, 40, 15)
		button.disabled = str(room.get("state", "lobby")) != "lobby"
		button.pressed.connect(func() -> void: Network.join_lan_room(room))
		_lan_box.add_child(button)
	_set_status("Pick a LAN room.")


func _browse_pi_rooms() -> void:
	if _browsing:
		return
	_browsing = true
	_browse_button.disabled = true
	_clear_rooms()
	_set_status("Looking for online rooms...")
	var lobbies: Array = await Network.fetch_lobbies()
	if not is_inside_tree():
		return
	_browsing = false
	_browse_button.disabled = false
	if lobbies.is_empty():
		_set_status("No online rooms right now. Create one!")
		return
	_lan_box.visible = true
	var shown: int = 0
	for entry: Variant in lobbies:
		if shown >= 5 or not (entry is Dictionary):
			continue
		var lobby: Dictionary = entry as Dictionary
		var code: String = str(lobby.get("room_code", "")).to_upper()
		if code.length() != 5:
			continue
		shown += 1
		var label: String = "%s  ·  %d player%s  ·  %s" % [
			str(lobby.get("name", "HOST")),
			int(lobby.get("players", 1)),
			"" if int(lobby.get("players", 1)) == 1 else "s",
			code,
		]
		var button: Button = _candy(label, UiPalette.BLUE, 40, 15)
		button.pressed.connect(func() -> void:
			_join_input.text = code
			_on_join_pressed())
		_lan_box.add_child(button)
	_set_status("Pick a room or type its code.")


func _clear_rooms() -> void:
	for child: Node in _lan_box.get_children():
		child.queue_free()
	_lan_box.visible = false


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
	SceneLoader.go_to(MINIGAMES_SCENE, "MINIGAMES", "CHOOSE A MINIGAME")


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
		return
	var ids: Array[int] = [multiplayer.get_unique_id()]
	for peer_id: int in multiplayer.get_peers():
		ids.append(peer_id)
	ids.sort()
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


func _on_back_pressed() -> void:
	Network.leave()
	SceneLoader.end_task()
	SceneLoader.go_to(PLAY_MENU_SCENE, "PLAY")
