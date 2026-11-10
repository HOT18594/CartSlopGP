extends Control
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## Multiplayer lobby. Two clear doors when idle, one room card when connected.
##
##   header: title / back
##   profile row: name + tag colour (idle only, compact)
##   idle: HOST card (online primary + LAN secondary)
##         JOIN card (code + JOIN primary + browse/LAN secondaries)
##   room: real code + COPY/LEAVE, 8 player slots, host settings, START
##   client: title LOBBY, real code, read-only setup summary
##
## Room lists never dump into the page. Both FIND LAN ROOMS and BROWSE
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
const OFFLINE_TEXT: String = "Online play is unavailable right now. LAN play still works."
const LEAVE_WARNING: String = "Leaving will close the room for everyone."
const MAX_SLOTS: int = 8

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

@onready var _title: Label = $Frame/Panel/Shell/Header/Title
@onready var _profile_row: HBoxContainer = $Frame/Panel/Shell/ProfileRow
@onready var _body: VBoxContainer = $Frame/Panel/Shell/Content/Body
@onready var _status: Label = %StatusLabel
@onready var _back_button: Button = %BackButton

var _name_input: LineEdit
var _typing_label: Label
var _typing_active: bool = false
var _typing_blink: float = 0.0
var _idle_box: VBoxContainer
var _offline_banner: PanelContainer
var _offline_label: Label
var _retry_button: Button
var _room_box: VBoxContainer
var _join_input: LineEdit
var _join_button: Button
var _join_status: Label
var _lan_button: Button
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
var _settings_row: HBoxContainer
var _setting_views: Dictionary = {} ## key -> Button
var _summary: Label
var _client_note: Label
var _start_button: Button
var _game_pill: Button
var _bots_pill: Button
var _map_button: Button
var _vehicle_button: Button
var _visibility_pill: Button
var _visibility_box: VBoxContainer
var _browser: Control
var _browser_mode: String = "online"
var _tag_swatch_buttons: Dictionary = {} ## hex -> Button
var _state: String = "idle"
var _server_checked: bool = false
var _client_code: String = ""
var _leave_armed: bool = false
var _leave_ticket: int = 0


func _ready() -> void:
	CursorController.set_menu_mode(true)
	_build_ui()
	Network.host_started.connect(_on_host_started)
	Network.host_failed.connect(_on_host_failed)
	Network.join_succeeded.connect(_on_join_succeeded)
	Network.join_failed.connect(_on_join_failed)
	Network.join_status_changed.connect(_on_join_status)
	Network.peers_changed.connect(_on_peers_changed)
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


func _focus_idle() -> void:
	pass


func _focus_host() -> void:
	pass


func _focus_client() -> void:
	pass


# --------------------------------------------------------------------------
# small builders


func _candy(text: String, color: Color, height: int, font_size: int) -> Button:
	var button := Button.new()
	button.set_script(load(CANDY_BUTTON))
	button.set("fill_color", color)
	button.set("corner_radius", mini(int(height / 2), 28))
	button.set("shadow_offset", clampi(int(height / 8), 3, 8))
	button.text = text
	button.custom_minimum_size = Vector2(0, height)
	button.add_theme_font_size_override("font_size", font_size)
	return button


func _pill(labels: PackedStringArray, values: Array, start_index: int) -> Button:
	var button := Button.new()
	button.set_script(load(PILL_CYCLER))
	button.set("fill_color", UiPalette.CREAM)
	button.set("corner_radius", 20)
	button.set("shadow_offset", 4)
	button.custom_minimum_size = Vector2(0, 46)
	button.add_theme_font_size_override("font_size", 17)
	button.call("configure", labels, values, start_index)
	return button


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", UiPalette.BLUE_DARK)
	return label


func _section(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", UiPalette.INK)
	return label


func _hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(0, 28)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", UiPalette.MUTED)
	return label


func _desc(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", UiPalette.MUTED)
	return label


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.theme_type_variation = &"TitleLabel"
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", UiPalette.INK)
	return label


func _vertical_spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


func _card(parent: Node) -> VBoxContainer:
	## Cream rounded panel with a thick navy outline. No coloured top bar.
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.CREAM
	style.set_corner_radius_all(22)
	style.set_border_width_all(5)
	style.border_color = UiPalette.INK
	style.shadow_color = Color(0.12, 0.10, 0.23, 0.30)
	style.shadow_offset = Vector2(0, 5)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(column)
	return column


func _soft_disabled_style() -> StyleBoxFlat:
	## The theme's disabled lavender, not the muddy grey candy_button default.
	var style := StyleBoxFlat.new()
	style.bg_color = Color("d8d3e4")
	style.set_corner_radius_all(22)
	style.set_border_width_all(5)
	style.border_color = Color("4b4560")
	style.shadow_color = Color(0.12, 0.10, 0.23, 0.30)
	style.shadow_offset = Vector2(0, 4)
	style.content_margin_left = 26
	style.content_margin_right = 26
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


func _apply_soft_disabled(button: Button) -> void:
	if button != null:
		button.add_theme_stylebox_override("disabled", _soft_disabled_style())


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
	_name_input.custom_minimum_size = Vector2(220, 46)
	_name_input.set_meta("skip_kit", true)
	_name_input.add_theme_font_size_override("font_size", 22)
	_name_input.text_submitted.connect(func(_t: String) -> void: _commit_name())
	_name_input.focus_exited.connect(_commit_name)
	_name_input.focus_entered.connect(_on_name_focus.bind(true))
	_name_input.focus_exited.connect(_on_name_focus.bind(false))
	_profile_row.add_child(_name_input)
	# Always visible with a reserved width. TYPING fades in and out, so the
	# row never reflows when the name field gains focus.
	_typing_label = Label.new()
	_typing_label.text = "TYPING"
	_typing_label.custom_minimum_size = Vector2(60, 0)
	_typing_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_typing_label.add_theme_font_size_override("font_size", 10)
	_typing_label.add_theme_color_override("font_color", UiPalette.GRASS)
	_typing_label.modulate.a = 0.0
	_typing_label.visible = true
	# Parent it: an unparented Node is never freed with the lobby scene and
	# would leak one Label on every visit. Alpha controls the fade instead.
	_profile_row.add_child(_typing_label)

	_profile_row.add_child(_caption("TAG"))
	var swatch_grid := GridContainer.new()
	swatch_grid.columns = 8
	swatch_grid.add_theme_constant_override("h_separation", 5)
	_profile_row.add_child(swatch_grid)
	for swatch: Dictionary in TAG_COLORS:
		var hex: String = str(swatch["hex"])
		var swatch_button := Button.new()
		# UiKit must not force these into 54 px tall pills.
		swatch_button.set_meta("skip_kit", true)
		swatch_button.custom_minimum_size = Vector2(44, 44)
		swatch_button.tooltip_text = "%s NAME TAG" % str(swatch["name"])
		var swatch_style := StyleBoxFlat.new()
		swatch_style.bg_color = Color(hex)
		swatch_style.set_corner_radius_all(8)
		swatch_style.set_border_width_all(3)
		swatch_style.border_color = UiPalette.INK
		swatch_button.add_theme_stylebox_override("normal", swatch_style)
		var hover_style: StyleBoxFlat = swatch_style.duplicate()
		hover_style.bg_color = Color(hex).lightened(0.12)
		swatch_button.add_theme_stylebox_override("hover", hover_style)
		swatch_button.add_theme_stylebox_override("pressed", hover_style)
		swatch_button.resized.connect(func() -> void:
			swatch_button.pivot_offset = swatch_button.size * 0.5)
		swatch_button.pressed.connect(_on_tag_color.bind(hex))
		swatch_grid.add_child(swatch_button)
		_tag_swatch_buttons[hex] = swatch_button
	_refresh_tag_swatches()


func _create_browser() -> void:
	_browser = (load(ROOM_BROWSER_SCENE) as PackedScene).instantiate()
	add_child(_browser)
	_browser.connect("room_selected", _on_room_selected)
	_browser.connect("host_requested", _on_browser_host)
	_browser.connect("closed", _on_browser_closed)


func _on_browser_closed() -> void:
	if _state == "idle":
		_focus_idle()


func _build_idle() -> void:
	_idle_box = VBoxContainer.new()
	_idle_box.add_theme_constant_override("separation", 12)
	_idle_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(_idle_box)

	_build_offline_banner()

	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 18)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_idle_box.add_child(cards)

	var host_col: VBoxContainer = _card(cards)
	host_col.alignment = BoxContainer.ALIGNMENT_BEGIN
	host_col.add_child(_heading("HOST A ROOM"))
	# Host door has fewer actions; two equal spacers keep the heading aligned
	# with the join card while its buttons sit balanced in the leftover height.
	host_col.add_child(_vertical_spacer())
	_host_pi_button = _candy("CREATE ONLINE ROOM", UiPalette.YELLOW, 58, 21)
	_host_pi_button.custom_minimum_size.x = 0
	_host_pi_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host_pi_button.pressed.connect(_on_host_pi)
	host_col.add_child(_host_pi_button)
	_apply_soft_disabled(_host_pi_button)
	_lan_button = _candy("HOST LAN ROOM", UiPalette.BLUE, 44, 16)
	_lan_button.custom_minimum_size.x = 0
	_lan_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lan_button.pressed.connect(_on_host_lan)
	host_col.add_child(_lan_button)
	host_col.add_child(_vertical_spacer())

	var join_col: VBoxContainer = _card(cards)
	join_col.alignment = BoxContainer.ALIGNMENT_BEGIN
	join_col.add_child(_heading("JOIN A ROOM"))
	_join_input = LineEdit.new()
	_join_input.placeholder_text = "5-LETTER CODE"
	_join_input.max_length = 5
	_join_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_join_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_join_input.custom_minimum_size = Vector2(0, 46)
	_join_input.add_theme_font_size_override("font_size", 22)
	# UiKit would flatten this field back to 50 px / 18 px; keep the big code.
	_join_input.set_meta("skip_kit", true)
	_join_input.text_changed.connect(_on_code_typed)
	_join_input.text_submitted.connect(func(_t: String) -> void: _on_join_pressed())
	join_col.add_child(_join_input)
	_join_button = _candy("JOIN", UiPalette.YELLOW, 58, 23)
	_join_button.custom_minimum_size.x = 0
	_join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_join_button.pressed.connect(_on_join)
	join_col.add_child(_join_button)
	_apply_soft_disabled(_join_button)
	_join_status = Label.new()
	_join_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_join_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_join_status.custom_minimum_size = Vector2(0, 34)
	_join_status.add_theme_font_size_override("font_size", 13)
	_join_status.add_theme_color_override("font_color", UiPalette.RED)
	join_col.add_child(_join_status)
	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 18)
	search_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_idle_box.add_child(search_row)
	_browse_button = _candy("SEARCH ONLINE", UiPalette.BLUE, 48, 18)
	_browse_button.custom_minimum_size.x = 0
	_browse_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_browse_button.pressed.connect(_on_browse)
	search_row.add_child(_browse_button)
	_apply_soft_disabled(_browse_button)
	_lan_scan_button = _candy("SEARCH LAN", UiPalette.CYAN, 48, 18)
	_lan_scan_button.custom_minimum_size.x = 0
	_lan_scan_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lan_scan_button.pressed.connect(_on_lan_scan)
	search_row.add_child(_lan_scan_button)


func _build_offline_banner() -> void:
	_offline_banner = PanelContainer.new()
	_offline_banner.visible = false
	_offline_banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.YELLOW
	style.set_corner_radius_all(16)
	style.set_border_width_all(4)
	style.border_color = UiPalette.INK
	style.shadow_color = Color(0.12, 0.10, 0.23, 0.28)
	style.shadow_offset = Vector2(0, 4)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	_offline_banner.add_theme_stylebox_override("panel", style)
	_idle_box.add_child(_offline_banner)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_offline_banner.add_child(row)
	_offline_label = Label.new()
	_offline_label.text = OFFLINE_TEXT
	_offline_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_offline_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_offline_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_offline_label.add_theme_font_size_override("font_size", 14)
	_offline_label.add_theme_color_override("font_color", UiPalette.INK)
	row.add_child(_offline_label)
	_retry_button = _candy("RETRY", UiPalette.CREAM, 44, 13)
	_retry_button.custom_minimum_size = Vector2(100, 44)
	_retry_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_retry_button.pressed.connect(_retry_server)
	row.add_child(_retry_button)
	_apply_soft_disabled(_retry_button)


func _build_room() -> void:
	_room_box = VBoxContainer.new()
	_room_box.add_theme_constant_override("separation", 10)
	_room_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(_room_box)

	_host_card = _card(_room_box)
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 16)
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host_card.add_child(split)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.95
	split.add_child(left)
	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(4, 0)
	divider.color = Color(UiPalette.INK, 0.30)
	divider.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(divider)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.05
	split.add_child(right)

	_code_caption = _caption("ROOM CODE")
	_code_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_caption.add_theme_font_size_override("font_size", 12)
	left.add_child(_code_caption)
	_code_label = Label.new()
	_code_label.text = "-----"
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_label.theme_type_variation = &"TitleLabel"
	_code_label.add_theme_font_size_override("font_size", 46)
	_code_label.add_theme_color_override("font_color", UiPalette.INK)
	left.add_child(_code_label)
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 8)
	code_row.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_child(code_row)
	_copy_button = _candy("COPY", UiPalette.CYAN, 38, 14)
	_copy_button.custom_minimum_size = Vector2(120, 44)
	_copy_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_copy_button.pressed.connect(_on_copy_code)
	code_row.add_child(_copy_button)
	_leave_button = _candy("LEAVE ROOM", UiPalette.RED, 38, 14)
	_leave_button.custom_minimum_size = Vector2(140, 44)
	_leave_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_leave_button.pressed.connect(_on_leave_pressed)
	code_row.add_child(_leave_button)
	_visibility_pill = _pill(PackedStringArray(["PRIVATE", "PUBLIC"]),
		[false, true], 1 if GameSettings.room_public else 0)
	_visibility_pill.tooltip_text = "PRIVATE: CODE ONLY  ·  PUBLIC: LISTED IN THE BROWSER"
	_visibility_pill.connect("option_changed", _on_visibility_changed)
	_visibility_box = _setting_box("ROOM", "room", _visibility_pill, UiPalette.PINK)
	left.add_child(_visibility_box)
	_host_hint = _hint("")
	left.add_child(_host_hint)

	_players_header = _section("PLAYERS")
	_players_header.add_theme_font_size_override("font_size", 16)
	right.add_child(_players_header)
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 1)
	right.add_child(_players_box)

	_config_box = VBoxContainer.new()
	_config_box.add_theme_constant_override("separation", 6)
	_room_box.add_child(_config_box)
	_config_box.add_child(_section("HOST SETTINGS"))
	_settings_row = HBoxContainer.new()
	_settings_row.add_theme_constant_override("separation", 10)
	_config_box.add_child(_settings_row)

	_game_pill = _pill(PackedStringArray(["SANDBOX", "MINIGAMES"]),
		[GameSettings.GAME_SANDBOX, GameSettings.GAME_MINIGAMES], 0)
	_game_pill.connect("option_changed", func(value: Variant) -> void: _on_game_mode(str(value)))
	_settings_row.add_child(_setting_box("MODE", "mode", _game_pill, UiPalette.YELLOW))

	_bots_pill = _pill(BOT_LABELS, BOT_VALUES, GameSettings.effective_bot_count())
	_bots_pill.connect("option_changed", _on_bots_changed)
	_settings_row.add_child(_setting_box("BOTS", "bots", _bots_pill, UiPalette.GRASS))

	_map_button = _candy("", UiPalette.CREAM, 46, 15)
	_map_button.tooltip_text = "CHOOSE MAP"
	_map_button.pressed.connect(_on_choose_map)
	_settings_row.add_child(_setting_box("MAP", "map", _map_button, UiPalette.CYAN))

	_vehicle_button = _candy("", UiPalette.CREAM, 46, 15)
	_vehicle_button.tooltip_text = "CHOOSE VEHICLE"
	_vehicle_button.pressed.connect(_on_change_vehicle)
	_settings_row.add_child(_setting_box("CAR", "vehicle", _vehicle_button, UiPalette.BLUE))

	_summary = Label.new()
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary.add_theme_font_size_override("font_size", 15)
	_summary.add_theme_color_override("font_color", UiPalette.MUTED)
	_summary.visible = false
	_room_box.add_child(_summary)

	_start_button = _candy("START", UiPalette.YELLOW, 72, 30)
	_start_button.custom_minimum_size = Vector2(480, 72)
	_start_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_start_button.pressed.connect(_on_start_pressed)
	_room_box.add_child(_start_button)

	_client_note = Label.new()
	_client_note.text = "ONLY THE HOST CAN START THE RACE."
	_client_note.visible = false
	_client_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_client_note.add_theme_font_size_override("font_size", 13)
	_client_note.add_theme_color_override("font_color", UiPalette.BLUE_DARK)
	_room_box.add_child(_client_note)


func _setting_box(label_text: String, key: String, control: Button, accent: Color) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", UiPalette.INK)
	box.add_child(label)
	control.custom_minimum_size = Vector2(0, 46)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(control)
	_decorate_setting(control, key, accent)
	return box


func _decorate_setting(control: Button, key: String, _accent: Color) -> void:
	## The value is the button, not a second tiny badge layered on top of it.
	for state: String in ["font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color", "font_disabled_color"]:
		control.add_theme_color_override(state, UiPalette.INK)
	control.add_theme_font_size_override("font_size", 17)
	_setting_views[key] = control


func _set_badge(key: String, text: String, _color: Color) -> void:
	var control: Button = _setting_views.get(key)
	if control != null:
		control.text = text


func _on_name_focus(focused: bool) -> void:
	_typing_active = focused
	if focused:
		_typing_blink = 0.0


func _process(delta: float) -> void:
	if _typing_label == null:
		return
	var target: float = 0.0
	if _typing_active:
		_typing_blink += delta
		target = 0.55 + 0.45 * sin(_typing_blink * 7.0)
	_typing_label.modulate.a = UiAnim.damp(_typing_label.modulate.a, target, delta, 14.0)


# --------------------------------------------------------------------------
# room browser


func _on_lan_scan() -> void:
	_on_find_lan()


func _on_browse() -> void:
	_on_browse_online()


func _on_join() -> void:
	_on_join_pressed()


func _on_find_lan() -> void:
	if Network.join_pending:
		_set_status("A join is already in progress.")
		return
	_browser_mode = "lan"
	_browser.call("open", "lan")


func _on_browse_online() -> void:
	if Network.join_pending:
		_set_status("A join is already in progress.")
		return
	if _server_checked and not Network.server_online:
		_set_status(SERVER_DOWN)
		UiAnim.shake(_idle_box, 5.0)
		return
	_browser_mode = "online"
	_browser.call("open", "online")


func _on_browser_host(mode: String) -> void:
	_browser.call("close")
	if mode == "lan":
		_on_host_lan()
	else:
		_on_host_pi()


func _on_room_selected(room: Dictionary) -> void:
	if Network.join_pending:
		_set_status("A join is already in progress.")
		return
	if _browser_mode == "lan":
		Network.join_lan_room(room)
		return
	# Public rooms are joined from the row itself; no code is shown or typed.
	_client_code = ""
	Network.set_meta("last_join_code", "")
	_set_status("Joining the room...")
	Network.join_public_room(room)


# --------------------------------------------------------------------------
# server status


func _probe_server() -> void:
	if _retry_button != null:
		_retry_button.disabled = true
	var ok: bool = await Network.probe_server()
	if not is_inside_tree():
		return
	_set_server_status(ok, "online" if ok else "offline")


func _retry_server() -> void:
	_server_checked = false
	if _retry_button != null:
		_retry_button.disabled = true
	if _offline_label != null:
		_offline_label.text = "Checking online play..."
	_probe_server()


func _on_server_status(online: bool, detail: String) -> void:
	_set_server_status(online, detail)


func _set_server_status(online: bool, detail: String) -> void:
	# Players do not need a server status light. Online means nothing is shown.
	# Offline gets one warm banner above the two doors, after the check finishes.
	if detail == "checking":
		return
	_server_checked = true
	if _join_button != null:
		_join_button.disabled = not online
		_apply_soft_disabled(_join_button)
	if _join_input != null:
		_join_input.editable = online
		_join_input.focus_mode = Control.FOCUS_ALL if online else Control.FOCUS_NONE
	if _browse_button != null:
		_browse_button.disabled = not online
		_apply_soft_disabled(_browse_button)
	if _host_pi_button != null:
		_host_pi_button.disabled = not online
		_apply_soft_disabled(_host_pi_button)
	if _offline_banner != null:
		_offline_banner.visible = not online
	if _offline_label != null:
		_offline_label.text = OFFLINE_TEXT
	if _retry_button != null:
		_retry_button.disabled = false
	_refresh_status()


# --------------------------------------------------------------------------
# state


func _set_state(state: String) -> void:
	_state = state
	var idle: bool = state == "idle"
	_idle_box.visible = idle
	_room_box.visible = not idle
	_profile_row.visible = idle
	_config_box.visible = state == "host"
	_start_button.visible = state == "host"
	_visibility_box.visible = state == "host"
	_client_note.visible = state == "client"
	_copy_button.visible = state != "idle" and not Network.is_lan() \
		and _code_label.text.length() == 5 and _code_label.text != "-----"
	_leave_button.visible = not idle
	_code_caption.visible = not idle
	_title.text = "MULTIPLAYER" if idle else ("YOUR ROOM" if state == "host" else "LOBBY")
	_reset_leave_button()
	if idle:
		_code_label.text = "-----"
		# Re-arm the online doors after a session ends. Before the first probe
		# finishes (_server_checked false) they stay live instead of reading
		# broken for several seconds.
		if _server_checked:
			var online: bool = Network.server_online
			_join_button.disabled = not online
			_browse_button.disabled = not online
			_host_pi_button.disabled = not online
			_join_input.editable = online
			_join_input.focus_mode = Control.FOCUS_ALL if online else Control.FOCUS_NONE
		_refresh_status()
	else:
		UiAnim.fade_in(_room_box, 0.22)
	_refresh_config()
	_refresh_players()
	MenuNav.refresh()


func _refresh_config() -> void:
	if _game_pill == null:
		return
	var active: bool = Network.is_session_active()
	var mode: String = Network.session_mode if active else GameSettings.multiplayer_mode
	_game_pill.call("set_index", 0 if mode == GameSettings.GAME_SANDBOX else 1)
	_set_badge("mode", "SANDBOX" if mode == GameSettings.GAME_SANDBOX else "MINIGAMES",
		UiPalette.YELLOW if mode == GameSettings.GAME_SANDBOX else UiPalette.GRASS)
	var bots: int = Network.session_bot_count if active else GameSettings.effective_bot_count()
	bots = clampi(bots, 0, BOT_LABELS.size() - 1)
	_bots_pill.call("set_index", bots)
	_set_badge("bots", BOT_LABELS[bots],
		UiPalette.GRASS if bots > 0 else UiPalette.TEXT_DIM)
	var map_id: String = Network.session_minigame if active and Network.is_host \
		else GameSettings.selected_minigame
	var map_text: String = GameSettings.minigame_name(map_id) \
		if mode == GameSettings.GAME_MINIGAMES else "FREEROAM"
	_set_badge("map", map_text,
		UiPalette.CYAN if mode == GameSettings.GAME_MINIGAMES else UiPalette.TEXT_DIM)
	_map_button.disabled = mode != GameSettings.GAME_MINIGAMES
	if _map_button.disabled:
		_apply_soft_disabled(_map_button)
	var vehicle_id: String = GameSettings.minigame_vehicle \
		if mode == GameSettings.GAME_MINIGAMES else GameSettings.selected_vehicle
	var vehicle: Dictionary = Catalog.find(vehicle_id)
	var vehicle_text: String = str(vehicle.get("name", "SHOPPING CART"))
	if _state == "client" and mode == GameSettings.GAME_MINIGAMES:
		# The race forces the host's car onto everyone; the client's local
		# pick is not what it will drive.
		vehicle_text = "HOST CHOICE"
	_set_badge("vehicle", vehicle_text, UiPalette.BLUE)
	var public_room: bool = Network.room_public if active and Network.is_host else GameSettings.room_public
	_visibility_pill.call("set_index", 1 if public_room else 0)
	_set_badge("room", "PUBLIC" if public_room else "PRIVATE",
		UiPalette.PINK if public_room else UiPalette.TEXT_DIM)
	_start_button.text = "START RACE" if mode == GameSettings.GAME_MINIGAMES else "START SANDBOX"
	_refresh_summary()


func _setup_line() -> String:
	var active: bool = Network.is_session_active()
	var mode: String = Network.session_mode if active else GameSettings.multiplayer_mode
	var map_id: String = Network.session_minigame if active and Network.is_host \
		else GameSettings.selected_minigame
	var map_text: String = GameSettings.minigame_name(map_id) \
		if mode == GameSettings.GAME_MINIGAMES else "FREEROAM"
	var vehicle_id: String = GameSettings.minigame_vehicle \
		if mode == GameSettings.GAME_MINIGAMES else GameSettings.selected_vehicle
	var vehicle: Dictionary = Catalog.find(vehicle_id)
	var vehicle_text: String = str(vehicle.get("name", "SHOPPING CART"))
	if _state == "client" and mode == GameSettings.GAME_MINIGAMES:
		vehicle_text = "HOST CHOICE"
	var bots: int = Network.session_bot_count if active else GameSettings.effective_bot_count()
	bots = clampi(bots, 0, 5)
	var bot_text: String = "NO BOTS" if bots <= 0 else ("%d BOT%s" % [bots, "" if bots == 1 else "S"])
	return "%s  ·  %s  ·  %s  ·  %s" % [
		"MINIGAMES" if mode == GameSettings.GAME_MINIGAMES else "SANDBOX",
		map_text, vehicle_text, bot_text]


func _refresh_summary() -> void:
	if _summary == null:
		return
	if _state == "client":
		_summary.text = "HOST SETUP  ·  " + _setup_line()
	elif _state == "host":
		_summary.text = _setup_line()
	else:
		_summary.text = ""
	_summary.visible = _summary.text != ""


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
	if not Network.join_pending:
		_set_join_status("")


# --------------------------------------------------------------------------
# hosting


func _on_host_lan() -> void:
	_begin_host("lan")


func _on_host_pi() -> void:
	if _server_checked and not Network.server_online:
		_set_status(SERVER_DOWN)
		UiAnim.shake(_idle_box, 5.0)
		return
	_begin_host("pi")


func _begin_host(mode: String) -> void:
	if Network.join_pending:
		_set_status("A join is already in progress. Wait for it to finish or press LEAVE.")
		return
	_commit_name()
	_set_state("host")
	_code_caption.text = "OPENING"
	_code_label.text = "....."
	_host_hint.text = "Starting the room..."
	_copy_button.visible = false
	_start_button.visible = false
	_set_status("")
	Network.host_game(mode)


func _on_host_started(code: String) -> void:
	_set_state("host")
	_set_status("")
	_start_button.visible = true
	if Network.is_lan():
		_code_caption.text = "ROOM ON THIS WI-FI"
		_code_label.text = "LAN"
		_copy_button.visible = false
	else:
		_code_caption.text = "ROOM CODE"
		_code_label.text = code
		_copy_button.visible = code.length() == 5
	_refresh_visibility_hint()
	_refresh_config()
	_refresh_players()
	call_deferred("_focus_host")


func _on_visibility_changed(value: Variant) -> void:
	if not Network.is_host:
		return
	var public_room: bool = bool(value)
	GameSettings.set_room_public(public_room)
	Network.set_room_public(public_room)
	_refresh_visibility_hint()
	_refresh_config()


func _refresh_visibility_hint() -> void:
	if _host_hint == null or _state != "host":
		return
	if Network.is_lan():
		if Network.room_public:
			_host_hint.text = ""
		else:
			_host_hint.text = "Switch ROOM to PUBLIC so friends can find it."
	else:
		if Network.room_public:
			_host_hint.text = ""
		else:
			_host_hint.text = "Share this code with your friends."


func _on_host_failed(reason: String) -> void:
	_set_state("idle")
	_set_status(reason)
	call_deferred("_focus_idle")


func _on_copy_code() -> void:
	if _code_label.text.length() == 5 and _code_label.text != "-----":
		DisplayServer.clipboard_set(_code_label.text)
		_set_status("Room code copied.")


# --------------------------------------------------------------------------
# joining


func _on_join_pressed() -> void:
	if Network.join_pending:
		_set_join_status("A join is already in progress.")
		return
	_commit_name()
	if _server_checked and not Network.server_online:
		_set_join_status(SERVER_DOWN)
		UiAnim.shake(_idle_box, 5.0)
		return
	var code: String = _join_input.text.strip_edges().to_upper()
	if code.length() != 5:
		_set_join_status("Enter the 5-letter room code from the host.")
		return
	_client_code = code
	Network.set_meta("last_join_code", code)
	_join_button.disabled = true
	_apply_soft_disabled(_join_button)
	_set_join_status("Connecting to the Cart Slop server...")
	Network.join_game(code)


func _on_join_status(text: String) -> void:
	_set_join_status(text)


func _on_join_failed(reason: String) -> void:
	_join_button.disabled = not Network.server_online
	_apply_soft_disabled(_join_button)
	_set_join_status(reason)
	# A room-browser pick writes "Joining..." into the bottom bar. Clear that
	# stale message now that the attempt is over; the join card holds the error.
	if _status.text.begins_with("Joining"):
		_set_status("")


func _on_join_succeeded() -> void:
	_set_state("client")
	_set_status("")
	_set_join_status("")
	_client_code = str(Network.get_meta("last_join_code", _join_input.text)).strip_edges().to_upper()
	if Network.is_lan():
		_code_caption.text = "LAN ROOM"
		_code_label.text = "LAN"
		_copy_button.visible = false
		_host_hint.text = "Connected over Wi-Fi. Waiting for the host..."
	elif _client_code.length() == 5:
		_code_caption.text = "ROOM CODE"
		_code_label.text = _client_code
		_copy_button.visible = true
		_host_hint.text = "You're in. Waiting for the host to start."
	else:
		_code_caption.text = "CONNECTED"
		_code_label.text = "ROOM"
		_copy_button.visible = false
		_host_hint.text = "Waiting for the host to start..."
	_title.text = "LOBBY"
	_refresh_config()
	_refresh_players()
	call_deferred("_focus_client")


func _on_session_ended(reason: String) -> void:
	_client_code = ""
	_set_state("idle")
	if reason != "":
		_set_status(reason)
	call_deferred("_focus_idle")


func _set_status(text: String) -> void:
	_status.text = text
	_status.visible = text != ""


func _set_join_status(text: String) -> void:
	if _join_status == null:
		return
	_join_status.text = text
	_join_status.add_theme_color_override("font_color",
		UiPalette.BLUE_DARK if text.begins_with("Connecting") or text.begins_with("Joining")
		else UiPalette.RED)


func _refresh_status() -> void:
	## Keep a real join/host error. When idle and offline, the warm banner is
	## the only message; StatusLabel stays hidden unless an action failed.
	if _status.text != "" and _status.text != SERVER_DOWN:
		return
	if _server_checked and not Network.server_online and _status.text == SERVER_DOWN:
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
	if GameSettings.multiplayer_mode != GameSettings.GAME_MINIGAMES:
		_set_status("Maps are for minigames. Switch MODE to MINIGAMES first.")
		return
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


func _on_peers_changed() -> void:
	_refresh_players()
	# A joining client has no session config yet. Rebroadcast the host's
	# current setup on every peer change so the read-only client summary is
	# accurate instead of falling back to local defaults.
	if Network.is_host and Network.is_session_active() and Network.is_connected_to_server():
		Network.configure_session(GameSettings.multiplayer_mode,
			GameSettings.bots_enabled, GameSettings.effective_bot_count())


func _refresh_players() -> void:
	if _players_box == null:
		return
	for child: Node in _players_box.get_children():
		_players_box.remove_child(child)
		child.queue_free()
	var ids: Array[int] = []
	if Network.is_session_active():
		ids.append(multiplayer.get_unique_id())
		for peer_id: int in multiplayer.get_peers():
			ids.append(peer_id)
		ids.sort()
	_players_header.text = "PLAYERS   %d / %d" % [ids.size(), MAX_SLOTS]
	for slot in MAX_SLOTS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 7)
		row.custom_minimum_size = Vector2(0, 19)
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(11, 11)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)
		var name_label := Label.new()
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.clip_text = true
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.add_theme_font_size_override("font_size", 14)
		name_label.add_theme_color_override("font_color", UiPalette.INK)
		row.add_child(name_label)
		if slot < ids.size():
			var peer_id: int = ids[slot]
			dot.color = Network.color_of(peer_id) if Network.player_colors.has(peer_id) \
				else UiPalette.YELLOW
			var label_text: String = Network.name_of(peer_id)
			if peer_id == multiplayer.get_unique_id():
				label_text += "  (YOU)"
			if peer_id == 1:
				label_text = "[HOST]  " + label_text
			name_label.text = label_text
			if Network.is_session_active() and Network.is_connected_to_server():
				var ms: int = int(Network.ping_table.get(peer_id, 0))
				if ms <= 0 and not Network.is_host and peer_id == multiplayer.get_unique_id():
					ms = maxi(Network.latency_ms, 0)
				var ping_label := Label.new()
				ping_label.text = "%d ms" % ms
				ping_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				ping_label.add_theme_font_size_override("font_size", 11)
				ping_label.add_theme_color_override("font_color", UiPalette.BLUE_DARK)
				row.add_child(ping_label)
		else:
			dot.color = Color(UiPalette.INK, 0.10)
			name_label.text = "OPEN SLOT"
			name_label.add_theme_font_size_override("font_size", 12)
			name_label.add_theme_color_override("font_color", UiPalette.MUTED)
		_players_box.add_child(row)


func _on_leave_pressed() -> void:
	if _state == "host" and not _leave_armed:
		_leave_armed = true
		_leave_ticket += 1
		var ticket: int = _leave_ticket
		_leave_button.text = "CLICK AGAIN TO LEAVE"
		_leave_button.set("fill_color", UiPalette.RED_DARK)
		_set_status(LEAVE_WARNING)
		await get_tree().create_timer(3.0).timeout
		if is_inside_tree() and _leave_armed and ticket == _leave_ticket:
			_reset_leave_button()
		return
	_leave_ticket += 1
	_reset_leave_button()
	Network.leave()
	# host_game() can still be awaiting a relay registration and owns the
	# full-screen SceneLoader task. Leaving must dismiss it immediately.
	SceneLoader.end_task()
	_set_state("idle")
	_set_status("")
	UiAnim.pop($Frame/Panel)


func _reset_leave_button() -> void:
	_leave_armed = false
	if _leave_button != null:
		_leave_button.text = "LEAVE ROOM"
		_leave_button.set("fill_color", UiPalette.RED)
	if _status != null and _status.text == LEAVE_WARNING:
		_set_status("")


func _on_back_pressed() -> void:
	# A host closing the room drops every client. Route BACK through the same
	# click-twice confirmation as LEAVE ROOM instead of bypassing it.
	if _state == "host" and Network.is_session_active() and not _leave_armed:
		_on_leave_pressed()
		return
	Network.leave()
	SceneLoader.end_task()
	SceneLoader.go_to(PLAY_MENU_SCENE, "PLAY")
