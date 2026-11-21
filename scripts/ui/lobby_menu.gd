extends Control
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## Party-game multiplayer lobby:
## - Idle Screen: compact player strip (Name + Colour dots + Server status pill)
##   above 3 self-explanatory visual cards (CREATE ONLINE ROOM, CREATE LAN ROOM,
##   JOIN A ROOM with 5-letter code + Room Browser).
## - Active Room Screen: clean 2-column video-game lobby fitting 1280x720 with
##   zero scrolling — Left column shows the live 16:9 map screenshot, mode badge,
##   map title, [CHANGE MODE & MAP], [GARAGE], BOTS & PUBLIC/PRIVATE controls;
##   Right column shows the Room Code bar + Players list (or ALPHA vs BETA teams
##   in DELIVER); pinned footer holds [LEAVE ROOM] + [START MATCH].

const PLAY_MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"
const MINIGAMES_SCENE: String = "res://scenes/ui/minigames_menu.tscn"
const VEHICLE_SCENE: String = "res://scenes/ui/vehicle_select.tscn"
const LOBBY_SCENE: String = "res://scenes/ui/lobby_menu.tscn"
const ROOM_BROWSER_SCENE: String = "res://scenes/ui/room_browser.tscn"
const ART_DIR: String = "res://assets/ui/art/"
const PREVIEW_DIR: String = "res://assets/ui/minigames/"

const Catalog := preload("res://scripts/vehicles/vehicle_catalog.gd")
const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const TrackDefs := preload("res://scripts/minigames/track_defs.gd")
const VehicleSelect := preload("res://scripts/ui/vehicle_select.gd")
const MinigamesMenu := preload("res://scripts/ui/minigames_menu.gd")

const KIND_SANDBOX: String = "sandbox"
const KIND_RACE: String = "race"
const KIND_DELIVER: String = "deliver"
const KIND_KNOCKOUT: String = "knockout"
const KIND_BOMB_TAG: String = "bomb_tag"

const KIND_LABELS: PackedStringArray = [
	"SANDBOX", "RACING", "DELIVER", "KNOCKOUT", "BLAST TAG",
]
const KIND_VALUES: Array[String] = [
	KIND_SANDBOX, KIND_RACE, KIND_DELIVER, KIND_KNOCKOUT, KIND_BOMB_TAG,
]

const TEAM_LABELS: PackedStringArray = ["ALPHA", "BETA"]
const TEAM_COLORS: Array[Color] = [UiPalette.BLUE, UiPalette.RED]

const SERVER_DOWN: String = "Online server is unreachable right now. LAN rooms still work."
const LEAVE_WARNING: String = "Leaving will close the room for everyone."
const MAX_SLOTS: int = 8
const PANEL_MAX_WIDTH: float = 1088.0

const BOT_LABELS: PackedStringArray = ["0", "1", "2", "3", "4", "5"]
const BOT_VALUES: Array[int] = [0, 1, 2, 3, 4, 5]
const DIFFICULTY_LABELS: PackedStringArray = ["EASY", "NORMAL", "HARD"]

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


class _AnimatedBanner extends Control:
	## Animated Ken Burns preview banner with colored top accent strip.
	var texture: Texture2D = null
	var accent: Color = Color("ffd22e")
	var _time: float = 0.0
	var _phase: float = 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
		_phase = randf_range(0.0, TAU)
		resized.connect(queue_redraw)

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		var gs: Node = get_node_or_null("/root/GameSettings")
		if gs != null and bool(gs.get("reduce_motion")):
			return
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		if w < 12.0 or h < 12.0:
			return
		var sk: float = minf(14.0, w * 0.08)
		var bw: float = maxf(w - sk - 4.0, 8.0)
		var bh: float = maxf(h - 4.0, 8.0)
		var x0: float = 2.0
		var y0: float = 2.0
		var pts := PackedVector2Array([
			Vector2(x0 + sk, y0),
			Vector2(x0 + sk + bw, y0),
			Vector2(x0 + bw, y0 + bh),
			Vector2(x0, y0 + bh),
		])
		draw_colored_polygon(pts, Color(0.06, 0.08, 0.16, 1.0))
		if texture != null:
			var src: Vector2 = texture.get_size()
			if src.x > 0.0 and src.y > 0.0:
				var card_aspect: float = (bw + sk) / maxf(bh, 1.0)
				var tex_aspect: float = src.x / src.y
				var zoom: float = 1.08 + 0.03 * sin(_time * 0.65 + _phase)
				var uv_w: float = (1.0 / zoom) * minf(card_aspect / tex_aspect, 1.0)
				var uv_h: float = (1.0 / zoom) * minf(tex_aspect / card_aspect, 1.0)
				var u0: float = clampf(0.5 - uv_w * 0.5 + sin(_time * 0.45 + _phase) * 0.02, 0.0, 1.0 - uv_w)
				var v0: float = clampf(0.5 - uv_h * 0.5 + cos(_time * 0.35 + _phase) * 0.015, 0.0, 1.0 - uv_h)
				var skew_u: float = uv_w * (sk / maxf(bw + sk, 1.0)) * 0.5
				var uvs := PackedVector2Array([
					Vector2(clampf(u0 + skew_u, 0.0, 1.0), v0),
					Vector2(clampf(u0 + uv_w, 0.0, 1.0), v0),
					Vector2(clampf(u0 + uv_w - skew_u, 0.0, 1.0), v0 + uv_h),
					Vector2(clampf(u0, 0.0, 1.0), v0 + uv_h),
				])
				draw_polygon(pts, PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]), uvs, texture)
		var cl := pts.duplicate()
		cl.append(pts[0])
		draw_polyline(cl, UiPalette.INK, 3.0, true)


class _LobbyArtFallback extends Control:
	var accent: Color = Color("38d6f0")
	var art_id: String = ""

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		if w < 8.0 or h < 8.0:
			return
		var top_col := Color("141933")
		var bot_col := accent.darkened(0.36)
		for b in 18:
			var t: float = float(b) / 17.0
			draw_rect(Rect2(0.0, h * float(b) / 18.0, w, h / 18.0 + 1.5),
				top_col.lerp(bot_col, t))
		var c := Vector2(w * 0.5, h * 0.46)
		var r: float = minf(w, h) * 0.32
		for ring in 3:
			draw_arc(c, r * (1.2 - float(ring) * 0.28), 0.0, TAU, 36,
				Color(accent.lightened(0.25), 0.22 + float(ring) * 0.14), 2.5, true)


@onready var _frame: MarginContainer = $Frame
@onready var _panel: PanelContainer = $Frame/Panel
@onready var _shell: VBoxContainer = $Frame/Panel/Shell
@onready var _title: Label = $Frame/Panel/Shell/Header/Title
@onready var _profile_row: HBoxContainer = $Frame/Panel/Shell/ProfileRow
@onready var _body: VBoxContainer = %Body
@onready var _status: Label = %StatusLabel
@onready var _back_button: Button = %BackButton

var _name_input: LineEdit
var _server_pill_style: StyleBoxFlat
var _server_pill_label: Label
var _retry_button: Button
var _tag_swatch_buttons: Dictionary = {}

var _idle_box: VBoxContainer
var _host_pi_button: Button
var _lan_button: Button
var _join_input: LineEdit
var _join_button: Button
var _browse_button: Button
var _join_status: Label

var _room_box: VBoxContainer
var _room_footer: HBoxContainer
var _leave_button: Button
var _start_button: Button
var _client_wait_label: Label

var _lobby_preview_tex: TextureRect
var _lobby_preview_fallback: _LobbyArtFallback
var _lobby_mode_chip_style: StyleBoxFlat
var _lobby_mode_chip_label: Label
var _lobby_map_title: Label
var _lobby_map_sub: Label

var _game_pill: Button
var _change_mode_button: Button
var _map_button: Button
var _vehicle_button: Button
var _vehicle_mode_pill: Button
var _room_bots_pill: Button
var _difficulty_pill: Button
var _visibility_pill: Button
var _visibility_box: Control

var _code_caption: Label
var _code_label: Label
var _copy_button: Button
var _host_hint: Label

var _players_card: PanelContainer
var _players_box: VBoxContainer
var _players_header: Label

var _teams_card: PanelContainer
var _teams_lock_button: Button
var _teams_hint: Label
var _team_lists: Array[VBoxContainer] = []
var _team_headers: Array[Label] = []
var _team_focus_peer: int = 0

var _browser: Control
var _browser_mode: String = "all"
var _state: String = "idle"
var _local_kind: String = KIND_RACE
var _server_checked: bool = false
var _client_code: String = ""
var _leave_armed: bool = false
var _leave_ticket: int = 0


func _ready() -> void:
	CursorController.set_menu_mode(true)
	_tune_shell_chrome()
	_build_ui()
	resized.connect(_fit_panel)
	_fit_panel()
	Network.host_started.connect(_on_host_started)
	Network.host_failed.connect(_on_host_failed)
	Network.join_succeeded.connect(_on_join_succeeded)
	Network.join_failed.connect(_on_join_failed)
	Network.join_status_changed.connect(_on_join_status)
	Network.peers_changed.connect(_on_peers_changed)
	Network.names_changed.connect(_refresh_players)
	Network.names_changed.connect(_refresh_teams)
	Network.tag_colors_changed.connect(_refresh_players)
	Network.vehicles_changed.connect(_refresh_config)
	Network.vehicles_changed.connect(_refresh_players)
	Network.ping_table_changed.connect(_refresh_players)
	Network.teams_changed.connect(_refresh_teams)
	Network.latency_changed.connect(func(_ms: int) -> void: _refresh_players())
	Network.session_ended.connect(_on_session_ended)
	Network.session_config_changed.connect(_refresh_config)
	Network.server_status_changed.connect(_on_server_status)

	_name_input.text = GameSettings.player_name
	_local_kind = _detect_initial_kind()
	_set_state("idle")
	_set_server_status(false, "checking")
	_probe_server()
	if Network.is_host and Network.is_session_active():
		_on_host_started(Network.join_code)
	elif Network.is_client and Network.is_connected_to_server():
		_on_join_succeeded()
	call_deferred("_enter")
	if OS.get_environment("CART_UI_MEASURE") == "1":
		_report_layout.call_deferred()


func _tune_shell_chrome() -> void:
	if _panel != null:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.052, 0.062, 0.142, 0.88)
		style.border_color = Color(0.22, 0.84, 0.94, 0.42)
		style.border_width_top = 4
		style.border_width_bottom = 4
		style.border_width_left = 4
		style.border_width_right = 4
		style.set_corner_radius_all(6)
		style.shadow_color = Color(0.02, 0.02, 0.08, 0.65)
		style.shadow_size = 14
		style.shadow_offset = Vector2(0, 10)
		style.content_margin_left = 30.0
		style.content_margin_right = 30.0
		style.content_margin_top = 20.0
		style.content_margin_bottom = 20.0
		style.anti_aliasing = true
		_panel.add_theme_stylebox_override("panel", style)
	if _title != null:
		_title.add_theme_color_override("font_color", UiPalette.YELLOW)
		_title.add_theme_color_override("font_outline_color", UiPalette.INK)
		_title.add_theme_constant_override("outline_size", 8)
	if _shell != null:
		_shell.add_theme_constant_override("separation", 12)
	if _body != null:
		_body.alignment = BoxContainer.ALIGNMENT_BEGIN
		_body.add_theme_constant_override("separation", 12)
	var content_pad := get_node_or_null("Frame/Panel/Shell/Content/ContentPad") as MarginContainer
	if content_pad != null:
		content_pad.add_theme_constant_override("margin_left", 8)
		content_pad.add_theme_constant_override("margin_right", 8)
		content_pad.add_theme_constant_override("margin_top", 6)
		content_pad.add_theme_constant_override("margin_bottom", 10)


func _fit_panel() -> void:
	if _frame == null:
		return
	var vp: Vector2 = size if size.x > 1.0 else get_viewport_rect().size
	if vp.x < 1.0 or vp.y < 1.0:
		return
	var target_w: float = minf(PANEL_MAX_WIDTH, maxf(320.0, vp.x - 48.0))
	var side_margin: int = maxi(24, int(floor((vp.x - target_w) * 0.5)))
	var vert_margin: int = 24 if vp.y >= 660.0 else 14
	_frame.add_theme_constant_override("margin_left", side_margin)
	_frame.add_theme_constant_override("margin_right", side_margin)
	_frame.add_theme_constant_override("margin_top", vert_margin)
	_frame.add_theme_constant_override("margin_bottom", vert_margin)


func _report_layout() -> void:
	await UiKit.report_screen(self, "lobby:idle")


func _enter() -> void:
	UiAnim.modal_open($Frame/Panel)
	if _idle_box != null and _idle_box.visible:
		var scroll := _idle_box.get_node_or_null("IdleCardsScroll")
		if scroll != null and scroll.get_child_count() > 0:
			var cards_row := scroll.get_child(0)
			var nodes: Array[Control] = []
			for c in cards_row.get_children():
				if c is Control:
					nodes.append(c as Control)
			UiAnim.stagger_slide(nodes, Vector2(0.0, 22.0), 0.26, 0.055)
	MenuNav.refresh()
	match _state:
		"host":
			_focus_host()
		"client":
			_focus_client()
		_:
			_focus_idle()


func _focus_idle() -> void:
	if _host_pi_button != null and not _host_pi_button.disabled:
		MenuNav.focus(_host_pi_button)
	elif _lan_button != null:
		MenuNav.focus(_lan_button)
	elif _browse_button != null:
		MenuNav.focus(_browse_button)


func _focus_host() -> void:
	if _start_button != null and _start_button.visible:
		MenuNav.focus(_start_button)


func _focus_client() -> void:
	if _leave_button != null and _leave_button.visible:
		MenuNav.focus(_leave_button)


# --------------------------------------------------------------------------
# small builders


func _candy(text: String, color: Color, height: int, font_size: int) -> Button:
	return UiKit.tile(text, color, float(height), font_size)


func _pill(labels: PackedStringArray, values: Array, start_index: int,
		tile_width: float = 78.0, height: float = 42.0) -> Button:
	return UiKit.segmented(labels, values, start_index, tile_width, height)


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", UiPalette.CYAN)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _section(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", UiPalette.YELLOW)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.76, 0.82, 0.94, 0.86))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _style_dark_input(field: LineEdit) -> void:
	field.set_meta("skip_kit", true)
	field.add_theme_color_override("font_color", UiPalette.CREAM)
	field.add_theme_color_override("font_placeholder_color", Color(0.62, 0.72, 0.88, 0.55))
	field.add_theme_color_override("caret_color", UiPalette.YELLOW)
	field.add_theme_color_override("selection_color", Color(UiPalette.CYAN, 0.35))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.05, 0.06, 0.13, 0.94)
	normal.border_color = Color(0.32, 0.78, 0.95, 0.45)
	normal.set_border_width_all(3)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 12.0
	normal.content_margin_right = 12.0
	normal.content_margin_top = 8.0
	normal.content_margin_bottom = 8.0
	field.add_theme_stylebox_override("normal", normal)
	var focus_st: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	focus_st.border_color = UiPalette.YELLOW
	field.add_theme_stylebox_override("focus", focus_st)
	var ro_st: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	ro_st.bg_color = Color(0.08, 0.09, 0.16, 0.65)
	ro_st.border_color = Color(1.0, 1.0, 1.0, 0.14)
	field.add_theme_stylebox_override("read_only", ro_st)


func _card_panel(parent: Node, pad_h: int = 16, pad_v: int = 14,
		tint: Color = Color(0.075, 0.088, 0.195, 0.92),
		_accent: Color = Color(0.22, 0.84, 0.94, 0.50)) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = tint
	style.set_corner_radius_all(4)
	style.set_border_width_all(2)
	style.border_color = Color(1.0, 1.0, 1.0, 0.16)
	style.content_margin_left = pad_h
	style.content_margin_right = pad_h
	style.content_margin_top = pad_v
	style.content_margin_bottom = pad_v
	style.shadow_color = Color(0.02, 0.02, 0.08, 0.48)
	style.shadow_size = 6
	style.shadow_offset = Vector2(3, 5)
	style.anti_aliasing = true
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel


func _apply_soft_disabled(_button: Button) -> void:
	## Slanted CandyButton already renders its own muted parallelogram when disabled.
	pass


func _texture_at(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _first_texture(paths: Array[String]) -> Texture2D:
	for path: String in paths:
		var tex: Texture2D = _texture_at(path)
		if tex != null:
			return tex
	return null


# --------------------------------------------------------------------------
# UI build


func _build_ui() -> void:
	_back_button.pressed.connect(_on_back_pressed)
	_build_profile()
	_create_browser()
	_build_idle()
	_build_room()
	_build_room_footer()
	_set_status("")


func _build_profile() -> void:
	## Compact top strip: PLAYER: [Name] + colour dots + ONLINE/LAN status pill.
	_profile_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_profile_row.add_theme_constant_override("separation", 10)

	_profile_row.add_child(_caption("PLAYER"))
	_name_input = LineEdit.new()
	_name_input.placeholder_text = "YOUR NAME"
	_name_input.max_length = 16
	_name_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_input.custom_minimum_size = Vector2(188, 42)
	_name_input.add_theme_font_size_override("font_size", 18)
	_style_dark_input(_name_input)
	_name_input.text_submitted.connect(func(_t: String) -> void: _commit_name())
	_name_input.focus_exited.connect(_commit_name)
	_profile_row.add_child(_name_input)

	var swatch_grid := HBoxContainer.new()
	swatch_grid.add_theme_constant_override("separation", 6)
	swatch_grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_profile_row.add_child(swatch_grid)
	for swatch: Dictionary in TAG_COLORS:
		var hex: String = str(swatch["hex"])
		var swatch_button := Button.new()
		swatch_button.set_meta("skip_kit", true)
		swatch_button.custom_minimum_size = Vector2(32, 32)
		swatch_button.tooltip_text = "%s TAG" % str(swatch["name"])
		var swatch_style := StyleBoxFlat.new()
		swatch_style.bg_color = Color(hex)
		swatch_style.set_corner_radius_all(9)
		swatch_style.set_border_width_all(3)
		swatch_style.border_color = UiPalette.INK
		swatch_style.anti_aliasing = true
		swatch_button.add_theme_stylebox_override("normal", swatch_style)
		var hover_style: StyleBoxFlat = swatch_style.duplicate() as StyleBoxFlat
		hover_style.bg_color = Color(hex).lightened(0.12)
		swatch_button.add_theme_stylebox_override("hover", hover_style)
		var pressed_style: StyleBoxFlat = swatch_style.duplicate() as StyleBoxFlat
		pressed_style.bg_color = Color(hex).darkened(0.08)
		swatch_button.add_theme_stylebox_override("pressed", pressed_style)
		swatch_button.resized.connect(func() -> void:
			swatch_button.pivot_offset = swatch_button.size * 0.5)
		swatch_button.pressed.connect(_on_tag_color.bind(hex))
		swatch_grid.add_child(swatch_button)
		_tag_swatch_buttons[hex] = swatch_button
	_refresh_tag_swatches()

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_profile_row.add_child(spacer)

	var server_pill := PanelContainer.new()
	server_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	server_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_server_pill_style = StyleBoxFlat.new()
	_server_pill_style.bg_color = Color(UiPalette.BLUE, 0.22)
	_server_pill_style.set_corner_radius_all(12)
	_server_pill_style.set_border_width_all(2)
	_server_pill_style.border_color = UiPalette.OUTLINE
	_server_pill_style.content_margin_left = 18.0
	_server_pill_style.content_margin_right = 18.0
	_server_pill_style.content_margin_top = 8.0
	_server_pill_style.content_margin_bottom = 8.0
	_server_pill_style.anti_aliasing = true
	server_pill.add_theme_stylebox_override("panel", _server_pill_style)
	_server_pill_label = Label.new()
	_server_pill_label.text = "● CHECKING..."
	_server_pill_label.add_theme_font_size_override("font_size", 13)
	_server_pill_label.add_theme_color_override("font_color", UiPalette.INK)
	_server_pill_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	server_pill.add_child(_server_pill_label)
	_profile_row.add_child(server_pill)

	_retry_button = _candy("RETRY", UiPalette.CREAM, 40, 13)
	_retry_button.custom_minimum_size = Vector2(88, 40)
	_retry_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_retry_button.visible = false
	_retry_button.pressed.connect(_retry_server)
	_profile_row.add_child(_retry_button)
	_apply_soft_disabled(_retry_button)


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
	## 3 clean self-explanatory visual cards side-by-side:
	## [CREATE ONLINE ROOM] | [CREATE LAN ROOM] | [JOIN A ROOM]
	_idle_box = VBoxContainer.new()
	_idle_box.add_theme_constant_override("separation", 14)
	_idle_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_idle_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_idle_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_child(_idle_box)

	var idle_scroll := ScrollContainer.new()
	idle_scroll.name = "IdleCardsScroll"
	idle_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	idle_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	idle_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	idle_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	idle_scroll.follow_focus = true
	_idle_box.add_child(idle_scroll)

	var cards_row := HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", 18)
	cards_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	idle_scroll.add_child(cards_row)

	# 1. CREATE ONLINE ROOM card
	var online_panel: PanelContainer = _card_panel(cards_row, 16, 14,
		Color(0.088, 0.100, 0.212, 0.92), UiPalette.YELLOW)
	var online_col := VBoxContainer.new()
	online_col.add_theme_constant_override("separation", 10)
	online_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	online_panel.add_child(online_col)
	online_col.add_child(_idle_art_banner(
		_first_texture([ART_DIR + "bg_hero_arena.png", ART_DIR + "bg_arena.png", ART_DIR + "preview_stadium.png"]),
		UiPalette.YELLOW))
	var online_title := Label.new()
	online_title.text = "ONLINE"
	online_title.theme_type_variation = &"TitleLabel"
	online_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	online_title.add_theme_font_size_override("font_size", 26)
	online_title.add_theme_color_override("font_color", UiPalette.YELLOW)
	online_col.add_child(online_title)
	_host_pi_button = _candy("CREATE ONLINE", UiPalette.YELLOW, 56, 17)
	_host_pi_button.name = "CreateOnlineButton"
	_host_pi_button.set_meta("nav_default", true)
	_host_pi_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host_pi_button.pressed.connect(_on_host_pi)
	online_col.add_child(_host_pi_button)
	_apply_soft_disabled(_host_pi_button)
	_host_pi_button.fit_text()

	# 2. CREATE LAN ROOM card
	var lan_panel: PanelContainer = _card_panel(cards_row, 16, 14,
		Color(0.088, 0.100, 0.212, 0.92), UiPalette.CYAN)
	var lan_col := VBoxContainer.new()
	lan_col.add_theme_constant_override("separation", 10)
	lan_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lan_panel.add_child(lan_col)
	lan_col.add_child(_idle_art_banner(
		_first_texture([ART_DIR + "bg_hero_paddock.png", ART_DIR + "bg_parking.png", ART_DIR + "preview_sandbox.png"]),
		UiPalette.CYAN))
	var lan_title := Label.new()
	lan_title.text = "LAN"
	lan_title.theme_type_variation = &"TitleLabel"
	lan_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lan_title.add_theme_font_size_override("font_size", 26)
	lan_title.add_theme_color_override("font_color", UiPalette.CYAN)
	lan_col.add_child(lan_title)
	_lan_button = _candy("CREATE LAN", UiPalette.BLUE, 56, 17)
	_lan_button.name = "CreateLanButton"
	_lan_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lan_button.pressed.connect(_on_host_lan)
	lan_col.add_child(_lan_button)
	_lan_button.fit_text()

	# 3. JOIN ROOM card
	var join_panel: PanelContainer = _card_panel(cards_row, 16, 14,
		Color(0.088, 0.100, 0.212, 0.92), UiPalette.PINK)
	var join_col := VBoxContainer.new()
	join_col.add_theme_constant_override("separation", 10)
	join_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_panel.add_child(join_col)

	var join_title := Label.new()
	join_title.text = "JOIN ROOM"
	join_title.theme_type_variation = &"TitleLabel"
	join_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	join_title.add_theme_font_size_override("font_size", 26)
	join_title.add_theme_color_override("font_color", UiPalette.PINK)
	join_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_col.add_child(join_title)

	_join_input = LineEdit.new()
	_join_input.placeholder_text = "5-LETTER CODE"
	_join_input.max_length = 5
	_join_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_join_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_join_input.custom_minimum_size = Vector2(0, 50)
	_join_input.add_theme_font_size_override("font_size", 22)
	_style_dark_input(_join_input)
	_join_input.text_changed.connect(_on_code_typed)
	_join_input.text_submitted.connect(func(_t: String) -> void: _on_join_pressed())
	join_col.add_child(_join_input)

	_join_button = _candy("JOIN BY CODE", UiPalette.YELLOW, 52, 18)
	_join_button.name = "JoinByCodeButton"
	_join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_join_button.pressed.connect(_on_join)
	join_col.add_child(_join_button)
	_apply_soft_disabled(_join_button)
	_join_button.fit_text()

	_browse_button = _candy("BROWSE ROOMS", UiPalette.CYAN, 52, 17)
	_browse_button.name = "BrowseRoomsButton"
	_browse_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_browse_button.pressed.connect(_on_search)
	join_col.add_child(_browse_button)
	_browse_button.fit_text()

	_join_status = Label.new()
	_join_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_join_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_join_status.custom_minimum_size = Vector2(0, 20)
	_join_status.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_join_status.add_theme_font_size_override("font_size", 12)
	_join_status.add_theme_color_override("font_color", UiPalette.RED)
	join_col.add_child(_join_status)


func _idle_art_banner(texture: Texture2D, accent: Color) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(0.0, 186.0)
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.OUTLINE
	style.set_corner_radius_all(4)
	style.content_margin_left = 3.0
	style.content_margin_right = 3.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	style.anti_aliasing = true
	frame.add_theme_stylebox_override("panel", style)
	if texture != null:
		var anim_banner := _AnimatedBanner.new()
		anim_banner.texture = texture
		anim_banner.accent = accent
		frame.add_child(anim_banner)
	else:
		var fb := _LobbyArtFallback.new()
		fb.accent = accent
		frame.add_child(fb)
	return frame


func _build_room() -> void:
	## 2-Column Video Game Lobby:
	## Left: Live 16:9 Map Screenshot + Mode/Map/Garage/Bots/Visibility controls.
	## Right: Room Code bar + Players list (or ALPHA vs BETA teams in DELIVER).
	_room_box = VBoxContainer.new()
	_room_box.add_theme_constant_override("separation", 10)
	_room_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(_room_box)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_box.add_child(columns)

	# --- LEFT COLUMN: Selected Game & Map Card ---
	var left_panel: PanelContainer = _card_panel(columns, 14, 12,
		Color(0.082, 0.095, 0.205, 0.90), UiPalette.CYAN)
	left_panel.size_flags_stretch_ratio = 1.08
	var left_col := VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 8)
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.add_child(left_col)

	# Live 16:9 screenshot frame clipped cleanly to a true slanted parallelogram!
	var shot_frame := PanelContainer.new()
	shot_frame.custom_minimum_size = Vector2(0.0, 174.0)
	shot_frame.clip_contents = false
	shot_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shot_style := StyleBoxEmpty.new()
	shot_frame.add_theme_stylebox_override("panel", shot_style)
	left_col.add_child(shot_frame)

	var shot_stack := Control.new()
	shot_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shot_frame.add_child(shot_stack)

	_lobby_preview_fallback = _LobbyArtFallback.new()
	_lobby_preview_fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shot_stack.add_child(_lobby_preview_fallback)

	var para_mat := ShaderMaterial.new()
	para_mat.shader = preload("res://assets/materials/parallelogram_clip.gdshader")
	para_mat.set_shader_parameter("skew_uv", 0.065)
	para_mat.set_shader_parameter("border_px", 3.0)
	para_mat.set_shader_parameter("border_color", UiPalette.INK)
	_lobby_preview_tex = TextureRect.new()
	_lobby_preview_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lobby_preview_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_lobby_preview_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lobby_preview_tex.material = para_mat
	_lobby_preview_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shot_stack.add_child(_lobby_preview_tex)

	# Bottom dark scrim for map title readability over bright screenshots
	var scrim := ColorRect.new()
	scrim.color = Color(0.04, 0.05, 0.14, 0.68)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.anchor_left = 0.0
	scrim.anchor_right = 1.0
	scrim.anchor_top = 1.0
	scrim.anchor_bottom = 1.0
	scrim.offset_top = -56.0
	scrim.offset_bottom = 0.0
	shot_stack.add_child(scrim)

	var mode_chip := PanelContainer.new()
	mode_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mode_chip.anchor_left = 0.0
	mode_chip.anchor_top = 0.0
	mode_chip.offset_left = 10.0
	mode_chip.offset_top = 10.0
	_lobby_mode_chip_style = StyleBoxFlat.new()
	_lobby_mode_chip_style.bg_color = UiPalette.GRASS
	_lobby_mode_chip_style.set_corner_radius_all(8)
	_lobby_mode_chip_style.set_border_width_all(2)
	_lobby_mode_chip_style.border_color = UiPalette.OUTLINE
	_lobby_mode_chip_style.content_margin_left = 16.0
	_lobby_mode_chip_style.content_margin_right = 16.0
	_lobby_mode_chip_style.content_margin_top = 6.0
	_lobby_mode_chip_style.content_margin_bottom = 6.0
	_lobby_mode_chip_style.anti_aliasing = true
	mode_chip.add_theme_stylebox_override("panel", _lobby_mode_chip_style)
	_lobby_mode_chip_label = Label.new()
	_lobby_mode_chip_label.text = "RACING"
	_lobby_mode_chip_label.theme_type_variation = &"TitleLabel"
	_lobby_mode_chip_label.add_theme_font_size_override("font_size", 13)
	_lobby_mode_chip_label.add_theme_color_override("font_color", UiPalette.INK)
	_lobby_mode_chip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mode_chip.add_child(_lobby_mode_chip_label)
	shot_stack.add_child(mode_chip)

	var map_info_box := VBoxContainer.new()
	map_info_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_info_box.anchor_left = 0.0
	map_info_box.anchor_right = 1.0
	map_info_box.anchor_top = 1.0
	map_info_box.anchor_bottom = 1.0
	map_info_box.offset_left = 12.0
	map_info_box.offset_right = -12.0
	map_info_box.offset_top = -52.0
	map_info_box.offset_bottom = -6.0
	map_info_box.add_theme_constant_override("separation", 0)
	shot_stack.add_child(map_info_box)

	_lobby_map_title = Label.new()
	_lobby_map_title.text = "STADIUM CIRCUIT"
	_lobby_map_title.theme_type_variation = &"TitleLabel"
	_lobby_map_title.add_theme_font_size_override("font_size", 22)
	_lobby_map_title.add_theme_color_override("font_color", Color.WHITE)
	_lobby_map_title.add_theme_color_override("font_outline_color", UiPalette.OUTLINE)
	_lobby_map_title.add_theme_constant_override("outline_size", 5)
	_lobby_map_title.clip_text = true
	_lobby_map_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_lobby_map_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_info_box.add_child(_lobby_map_title)

	_lobby_map_sub = Label.new()
	_lobby_map_sub.text = "3 LAPS  ·  CIRCUIT RACE"
	_lobby_map_sub.add_theme_font_size_override("font_size", 12)
	_lobby_map_sub.add_theme_color_override("font_color", Color(0.86, 0.94, 1.0, 0.92))
	_lobby_map_sub.clip_text = true
	_lobby_map_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_lobby_map_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_info_box.add_child(_lobby_map_sub)

	# Quick 5-mode pill selector
	_game_pill = _pill(KIND_LABELS, KIND_VALUES, 1, 74.0, 40.0)
	_game_pill.name = "ModePill"
	_game_pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_game_pill.connect("option_changed", func(value: Variant) -> void: _on_game_mode(str(value)))
	left_col.add_child(_game_pill)

	# [CHANGE MODE & MAP] + quick [MAP] button
	var mode_btn_row := HBoxContainer.new()
	mode_btn_row.add_theme_constant_override("separation", 10)
	mode_btn_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.add_child(mode_btn_row)

	_change_mode_button = _candy("CHANGE MODE & MAP", UiPalette.CYAN, 46, 16)
	_change_mode_button.name = "ChangeModeMapButton"
	_change_mode_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_change_mode_button.pressed.connect(_on_open_all_modes)
	mode_btn_row.add_child(_change_mode_button)

	_map_button = _candy("MAP", UiPalette.YELLOW, 46, 15)
	_map_button.name = "QuickMapButton"
	_map_button.custom_minimum_size = Vector2(118, 46)
	_map_button.pressed.connect(_on_choose_map)
	mode_btn_row.add_child(_map_button)

	# [GARAGE: <vehicle>] + [PICK OWN | SHARED] room vehicle policy
	var veh_row := HBoxContainer.new()
	veh_row.add_theme_constant_override("separation", 10)
	veh_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.add_child(veh_row)

	_vehicle_button = _candy("GARAGE: SHOPPING CART", Color("8ed8f6"), 44, 14)
	_vehicle_button.name = "GarageButton"
	_vehicle_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vehicle_button.pressed.connect(_on_change_vehicle)
	veh_row.add_child(_vehicle_button)

	_vehicle_mode_pill = _pill(PackedStringArray(["PICK OWN", "SHARED"]),
		[Network.VEHICLE_MODE_PICK_OWN, Network.VEHICLE_MODE_SHARED],
		1 if GameSettings.multiplayer_vehicle_mode == Network.VEHICLE_MODE_SHARED else 0,
		74.0, 44.0)
	_vehicle_mode_pill.name = "VehicleModePill"
	_vehicle_mode_pill.connect("option_changed", _on_vehicle_mode_changed)
	veh_row.add_child(_vehicle_mode_pill)

	# Compact row: BOTS [0..5] + ROOM [PRIVATE / PUBLIC]
	var bottom_opts := HBoxContainer.new()
	bottom_opts.add_theme_constant_override("separation", 10)
	bottom_opts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.add_child(bottom_opts)

	var bots_lbl := _caption("BOTS")
	bottom_opts.add_child(bots_lbl)

	_room_bots_pill = _pill(BOT_LABELS, BOT_VALUES,
		clampi(GameSettings.effective_bot_count(), 0, 5), 34.0, 40.0)
	_room_bots_pill.name = "RoomBotsPill"
	_room_bots_pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_bots_pill.connect("option_changed", _on_bots_option)
	bottom_opts.add_child(_room_bots_pill)

	_visibility_pill = _pill(PackedStringArray(["PRIVATE", "PUBLIC"]),
		[false, true], 1 if GameSettings.room_public else 0, 68.0, 40.0)
	_visibility_pill.name = "VisibilityPill"
	_visibility_pill.connect("option_changed", _on_visibility_changed)
	_visibility_box = _visibility_pill
	bottom_opts.add_child(_visibility_pill)

	var difficulty_row := HBoxContainer.new()
	difficulty_row.add_theme_constant_override("separation", 12)
	left_col.add_child(difficulty_row)
	var difficulty_label := _caption("BOT SKILL")
	difficulty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	difficulty_row.add_child(difficulty_label)
	_difficulty_pill = _pill(DIFFICULTY_LABELS, [0, 1, 2],
		Network.bot_difficulty(), 150.0, 38.0)
	_difficulty_pill.name = "BotDifficulty"
	_difficulty_pill.connect("option_changed", _on_difficulty_option)
	difficulty_row.add_child(_difficulty_pill)

	# --- RIGHT COLUMN: Room Code + Players / Teams ---
	var right_col := VBoxContainer.new()
	right_col.add_theme_constant_override("separation", 10)
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.size_flags_stretch_ratio = 0.94
	columns.add_child(right_col)

	var code_card: PanelContainer = _card_panel(right_col, 16, 10,
		Color(0.110, 0.112, 0.235, 0.94), UiPalette.YELLOW)
	var code_outer := VBoxContainer.new()
	code_outer.add_theme_constant_override("separation", 2)
	code_card.add_child(code_outer)

	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 12)
	code_row.alignment = BoxContainer.ALIGNMENT_CENTER
	code_outer.add_child(code_row)

	var code_stack := VBoxContainer.new()
	code_stack.add_theme_constant_override("separation", 0)
	code_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_row.add_child(code_stack)

	_code_caption = _caption("ROOM CODE")
	_code_caption.add_theme_font_size_override("font_size", 11)
	code_stack.add_child(_code_caption)

	_code_label = Label.new()
	_code_label.text = "-----"
	_code_label.theme_type_variation = &"TitleLabel"
	_code_label.add_theme_font_size_override("font_size", 32)
	_code_label.add_theme_color_override("font_color", UiPalette.YELLOW)
	code_stack.add_child(_code_label)

	_copy_button = _candy("COPY CODE", UiPalette.CYAN, 42, 14)
	_copy_button.custom_minimum_size = Vector2(124, 42)
	_copy_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_copy_button.pressed.connect(_on_copy_code)
	code_row.add_child(_copy_button)
	_copy_button.fit_text()

	_host_hint = _hint("")
	_host_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_host_hint.visible = false
	code_outer.add_child(_host_hint)

	# Players Roster Card (FFA modes)
	_players_card = _card_panel(right_col, 14, 12, Color(0.082, 0.095, 0.205, 0.90), UiPalette.CYAN)
	_players_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var players_col := VBoxContainer.new()
	players_col.add_theme_constant_override("separation", 6)
	players_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_players_card.add_child(players_col)

	_players_header = _section("PLAYERS   1 / %d" % MAX_SLOTS)
	players_col.add_child(_players_header)

	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 5)
	players_col.add_child(_players_box)

	# Teams Roster Card (DELIVER mode)
	_build_teams(right_col)


func _build_teams(parent: VBoxContainer) -> void:
	_teams_card = _card_panel(parent, 14, 10, Color(0.082, 0.095, 0.205, 0.90), UiPalette.PINK)
	_teams_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var teams_vbox := VBoxContainer.new()
	teams_vbox.add_theme_constant_override("separation", 6)
	teams_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_teams_card.add_child(teams_vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", UiKit.SPACING_TIGHT)
	teams_vbox.add_child(header)
	var title := _section("TEAMS")
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_teams_lock_button = _candy("AUTO BALANCE", UiPalette.GRASS, 40, 12)
	_teams_lock_button.custom_minimum_size = Vector2(154, 40)
	_teams_lock_button.pressed.connect(_on_teams_lock_pressed)
	header.add_child(_teams_lock_button)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	teams_vbox.add_child(columns)
	for team in TEAM_LABELS.size():
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 4)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		columns.add_child(column)
		var team_label := _section("%s  0" % TEAM_LABELS[team])
		team_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		team_label.add_theme_color_override("font_color", TEAM_COLORS[team])
		column.add_child(team_label)
		_team_headers.append(team_label)
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 4)
		column.add_child(list)
		_team_lists.append(list)
	_teams_hint = _hint("")
	_teams_hint.visible = false
	teams_vbox.add_child(_teams_hint)
	_teams_card.visible = false


func _build_room_footer() -> void:
	## Pinned outside ScrollContainer so [LEAVE ROOM] and [START MATCH] are
	## always 100% visible at 1280x720 with zero clipping.
	_room_footer = HBoxContainer.new()
	_room_footer.name = "RoomFooter"
	_room_footer.add_theme_constant_override("separation", UiKit.SPACING)
	_room_footer.visible = false
	_shell.add_child(_room_footer)

	_leave_button = _candy("LEAVE ROOM", UiPalette.RED, 52, 16)
	_leave_button.custom_minimum_size = Vector2(196, 52)
	_leave_button.pressed.connect(_on_leave_pressed)
	_room_footer.add_child(_leave_button)
	_leave_button.fit_text()

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_footer.add_child(spacer)

	_client_wait_label = Label.new()
	_client_wait_label.text = "WAITING FOR HOST..."
	_client_wait_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_client_wait_label.add_theme_font_size_override("font_size", 16)
	_client_wait_label.add_theme_color_override("font_color", UiPalette.CYAN)
	_client_wait_label.visible = false
	_room_footer.add_child(_client_wait_label)

	_start_button = _candy("START MATCH", UiPalette.YELLOW, 54, 21)
	_start_button.custom_minimum_size = Vector2(296, 54)
	_start_button.pressed.connect(_on_start_pressed)
	_room_footer.add_child(_start_button)
	_start_button.fit_text()


# --------------------------------------------------------------------------
# teams


func _on_teams_lock_pressed() -> void:
	if not Network.is_host or not Network.is_session_active():
		return
	Network.set_teams_locked(not Network.teams_locked)


func _on_team_row_pressed(peer_id: int) -> void:
	_team_focus_peer = peer_id
	_move_peer_to_team(peer_id, 1 - Network.team_for_peer(peer_id))


func _on_team_row_input(event: InputEvent, peer_id: int) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	var team: int = -1
	if key.keycode == KEY_LEFT:
		team = 0
	elif key.keycode == KEY_RIGHT:
		team = 1
	if team < 0 or team == Network.team_for_peer(peer_id):
		return
	_team_focus_peer = peer_id
	_move_peer_to_team(peer_id, team)
	accept_event()


func _move_peer_to_team(peer_id: int, team: int) -> void:
	if not Network.is_host or _state != "host":
		return
	if not Network.is_session_active():
		return
	Network.set_peer_team(peer_id, team)


func _refresh_teams() -> void:
	if _teams_card == null:
		return
	var deliver_mode: bool = _state != "idle" and _is_deliver_room()
	_teams_card.visible = deliver_mode
	if _players_card != null:
		_players_card.visible = _state != "idle" and not deliver_mode
	if not deliver_mode:
		return
	var ids: Array[int] = []
	if Network.is_session_active():
		ids = Network.participants()
	var counts: Array[int] = [0, 0]
	for peer_id: int in ids:
		var side: int = clampi(Network.team_for_peer(peer_id), 0, 1)
		counts[side] = counts[side] + 1
	for list: VBoxContainer in _team_lists:
		for child: Node in list.get_children():
			list.remove_child(child)
			child.queue_free()
	if _team_headers.size() < TEAM_LABELS.size():
		return
	for team in TEAM_LABELS.size():
		_team_headers[team].text = "%s  %d" % [TEAM_LABELS[team], counts[team]]
	var movable: bool = Network.is_host and Network.is_session_active()
	for peer_id: int in ids:
		var side: int = clampi(Network.team_for_peer(peer_id), 0, 1)
		if side >= _team_lists.size():
			continue
		var label_text: String = Network.name_of(peer_id)
		if peer_id == multiplayer.get_unique_id():
			label_text += "  (YOU)"
		if peer_id == 1:
			label_text = "HOST · " + label_text
		var row: Button = _candy(label_text, TEAM_COLORS[side].lightened(0.08),
			40, 13)
		row.set_meta("keep_align", true)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.disabled = not movable
		row.fit_text()
		row.pressed.connect(_on_team_row_pressed.bind(peer_id))
		row.gui_input.connect(_on_team_row_input.bind(peer_id))
		_team_lists[side].add_child(row)
		if peer_id == _team_focus_peer:
			call_deferred("_focus_team_row", row)
	for team in TEAM_LABELS.size():
		if counts[team] > 0:
			continue
		var empty_label := _caption("OPEN")
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_team_lists[team].add_child(empty_label)
	if _teams_lock_button != null:
		_teams_lock_button.visible = movable
		_teams_lock_button.disabled = not movable
		_teams_lock_button.text = "LOCKED" if Network.teams_locked \
			else "AUTO BALANCE"
		_teams_lock_button.set("fill_color",
			UiPalette.YELLOW if Network.teams_locked else UiPalette.GRASS)
		_teams_lock_button.fit_text()
	if _teams_hint != null:
		_teams_hint.visible = false
		_teams_hint.text = ""


func _focus_team_row(row: Button) -> void:
	if row != null and is_instance_valid(row) and row.is_inside_tree():
		MenuNav.focus(row)


# --------------------------------------------------------------------------
# mode & map resolution (5 modes)


func _net_const(prop: String, fallback: String) -> String:
	if prop in Network:
		var val: String = str(Network.get(prop))
		if val != "":
			return val
	return fallback


func _is_deliver_room() -> bool:
	return _current_kind() == KIND_DELIVER


func _is_party_kind(kind: String) -> bool:
	return kind in [KIND_DELIVER, KIND_KNOCKOUT, KIND_BOMB_TAG]


func _preset_id_for_kind(kind: String) -> String:
	match kind:
		KIND_DELIVER:
			return "cargo_rush"
		KIND_KNOCKOUT:
			return "knockout"
		KIND_BOMB_TAG:
			return "bomb_tag"
	return ""


func _kind_for_preset_id(preset_id: String) -> String:
	match preset_id:
		"cargo_rush", "cargo", "deliver":
			return KIND_DELIVER
		"knockout":
			return KIND_KNOCKOUT
		"bomb_tag", "blast_tag":
			return KIND_BOMB_TAG
	return ""


func _kind_for_arena_id(arena_id: String) -> String:
	if arena_id == "":
		return ""
	for raw: Dictionary in TrackDefs.PRESETS:
		if not TrackDefs.is_minigame(raw):
			continue
		if TrackDefs.theme_ids(raw).has(arena_id):
			return _kind_for_preset_id(str(raw.get("id", "")))
	if arena_id.begins_with("ko_"):
		return KIND_KNOCKOUT
	if arena_id.begins_with("bt_"):
		return KIND_BOMB_TAG
	return ""


func _detect_initial_kind() -> String:
	if GameSettings.multiplayer_mode != GameSettings.GAME_MINIGAMES:
		return KIND_SANDBOX
	var by_arena: String = _kind_for_arena_id(GameSettings.selected_minigame)
	if by_arena != "":
		return by_arena
	return KIND_RACE


func _current_kind() -> String:
	if Network.is_session_active():
		if "session_event" in Network:
			var ev: String = str(Network.get("session_event")).strip_edges().to_lower()
			match ev:
				"sandbox":
					return KIND_SANDBOX
				"race", "racing":
					return KIND_RACE
				"cargo", "cargo_rush", "deliver":
					return KIND_DELIVER
				"knockout":
					return KIND_KNOCKOUT
				"bomb_tag", "blast_tag":
					return KIND_BOMB_TAG
		if Network.session_mode != GameSettings.GAME_MINIGAMES:
			return KIND_SANDBOX
		if "session_scene" in Network:
			var sc: String = str(Network.get("session_scene"))
			if sc.ends_with("knockout.tscn"):
				return KIND_KNOCKOUT
			if sc.ends_with("bomb_tag.tscn"):
				return KIND_BOMB_TAG
			if sc == Network.CARGO_SCENE or sc.ends_with("cargo_rush.tscn"):
				return KIND_DELIVER
			if sc == Network.RACE_SCENE or sc.ends_with("grass_race.tscn"):
				return KIND_RACE
		var by_session_arena: String = _kind_for_arena_id(Network.session_minigame)
		if by_session_arena != "":
			return by_session_arena
		if Network.is_deliver_session():
			return KIND_DELIVER
		return KIND_RACE
	return _local_kind


func _scene_for_kind(kind: String) -> String:
	match kind:
		KIND_SANDBOX:
			return Network.GAME_SCENE
		KIND_RACE:
			return Network.RACE_SCENE
		KIND_DELIVER:
			return Network.CARGO_SCENE
		KIND_KNOCKOUT:
			return _net_const("KNOCKOUT_SCENE", "res://scenes/minigames/knockout.tscn")
		KIND_BOMB_TAG:
			return _net_const("BOMB_TAG_SCENE", "res://scenes/minigames/bomb_tag.tscn")
	return Network.RACE_SCENE


func _event_for_kind(kind: String) -> String:
	match kind:
		KIND_SANDBOX:
			return _net_const("EVENT_SANDBOX", "sandbox")
		KIND_RACE:
			return _net_const("EVENT_RACE", "race")
		KIND_DELIVER:
			return _net_const("EVENT_CARGO", "cargo_rush")
		KIND_KNOCKOUT:
			return _net_const("EVENT_KNOCKOUT", "knockout")
		KIND_BOMB_TAG:
			return _net_const("EVENT_BOMB_TAG", "bomb_tag")
	return "race"


func _ensure_arena_for_kind(kind: String) -> String:
	var pid: String = _preset_id_for_kind(kind)
	if pid == "":
		return ""
	var preset: Dictionary = TrackDefs.get_minigame(pid)
	if preset.is_empty():
		return GameSettings.selected_minigame
	var valid_ids: PackedStringArray = TrackDefs.theme_ids(preset)
	var current: String = Network.session_minigame \
		if (Network.is_session_active() and Network.session_minigame != "") \
		else GameSettings.selected_minigame
	if valid_ids.has(current):
		return current
	var fallback_id: String = TrackDefs.default_theme(preset)
	if fallback_id != "":
		GameSettings.set_selected_minigame(fallback_id)
	return fallback_id


func _lobby_display_for_kind(kind: String, active: bool) -> Dictionary:
	if kind == KIND_SANDBOX:
		return {
			"mode": "SANDBOX",
			"accent": UiPalette.YELLOW,
			"title": "SLOPMART STUNT PARK",
			"sub": "FREE ROAM  ·  STUNTS & OPEN PLAY",
			"texture": _first_texture([
				ART_DIR + "preview_sandbox.png",
				ART_DIR + "bg_parking.png",
			]),
		}
	if kind == KIND_RACE:
		var map_id: String = Network.session_map_id \
			if (active and Network.session_map_id != "") \
			else GameSettings.selected_map
		var preset: Dictionary = TrackDefs.get_preset(map_id)
		var track_name: String = str(preset.get("name",
			GameSettings.minigame_name(map_id))).to_upper()
		var pfile: String = str(preset.get("preview", ""))
		var tex: Texture2D = _first_texture([
			ART_DIR + "preview_" + map_id + ".png",
			ART_DIR + pfile if pfile != "" else "",
			PREVIEW_DIR + pfile if pfile != "" else "",
			ART_DIR + "preview_stadium.png",
		])
		return {
			"mode": "RACING",
			"accent": UiPalette.GRASS,
			"title": track_name,
			"sub": "3 LAPS  ·  CIRCUIT RACE",
			"texture": tex,
		}

	var pid: String = _preset_id_for_kind(kind)
	var preset: Dictionary = TrackDefs.get_minigame(pid)
	var arena_id: String = Network.session_minigame \
		if (active and Network.session_minigame != "") \
		else GameSettings.selected_minigame
	var valid_ids: PackedStringArray = TrackDefs.theme_ids(preset)
	if not valid_ids.is_empty() and not valid_ids.has(arena_id):
		arena_id = TrackDefs.default_theme(preset)

	var arena_name: String = arena_id.to_upper()
	var names: PackedStringArray = TrackDefs.theme_names(preset)
	var idx: int = valid_ids.find(arena_id)
	if idx >= 0 and idx < names.size():
		arena_name = names[idx].to_upper()
	else:
		var raw_themes: Variant = preset.get("themes", [])
		if raw_themes is Array:
			for item: Variant in raw_themes as Array:
				if item is Dictionary and str((item as Dictionary).get("id", "")) == arena_id:
					arena_name = str((item as Dictionary).get("name", arena_name)).to_upper()
					break

	var mode_label: String = "DELIVER"
	var mode_accent: Color = UiPalette.CYAN
	var mode_sub: String = "2 TEAMS  ·  CAPTURE & SCORE CRATES"
	if kind == KIND_KNOCKOUT:
		mode_label = "KNOCKOUT"
		mode_accent = UiPalette.ORANGE
		mode_sub = "FFA BRAWL  ·  LAST CART STANDING"
	elif kind == KIND_BOMB_TAG:
		mode_label = "BLAST TAG"
		mode_accent = UiPalette.PINK
		mode_sub = "HOT POTATO  ·  PASS THE MEGA-BOMB"

	var tex: Texture2D = _first_texture([
		ART_DIR + "preview_" + arena_id + ".png",
		ART_DIR + "preview_" + pid + ".png",
		ART_DIR + "bg_arena.png",
	])
	return {
		"mode": mode_label,
		"accent": mode_accent,
		"title": arena_name if arena_name != "" else mode_label,
		"sub": mode_sub,
		"texture": tex,
	}


# --------------------------------------------------------------------------
# room browser


func _on_search() -> void:
	if Network.join_pending:
		_set_status("A join is already in progress.")
		return
	_browser_mode = "all"
	_browser.call("open", "all")


func _on_join() -> void:
	_on_join_pressed()


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
	var source: String = str(room.get("_source", _browser_mode))
	if source == "lan":
		Network.join_lan_room(room)
		return
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
	if _server_pill_label != null:
		_server_pill_label.text = "● CHECKING..."
	if _server_pill_style != null:
		_server_pill_style.bg_color = Color(UiPalette.BLUE, 0.25)
	_probe_server()


func _on_server_status(online: bool, detail: String) -> void:
	_set_server_status(online, detail)


func _set_server_status(online: bool, detail: String) -> void:
	if detail == "checking":
		if _server_pill_label != null:
			_server_pill_label.text = "● CHECKING..."
		if _server_pill_style != null:
			_server_pill_style.bg_color = Color(UiPalette.BLUE, 0.25)
		return
	_server_checked = true
	if _join_button != null:
		_join_button.disabled = not online
		_apply_soft_disabled(_join_button)
	if _join_input != null:
		_join_input.editable = online
		_join_input.focus_mode = Control.FOCUS_ALL if online else Control.FOCUS_NONE
	if _host_pi_button != null:
		_host_pi_button.disabled = not online
		_apply_soft_disabled(_host_pi_button)
	if _server_pill_label != null:
		_server_pill_label.text = "● ONLINE" if online else "● LAN ONLY"
	if _server_pill_style != null:
		_server_pill_style.bg_color = UiPalette.GRASS if online else UiPalette.YELLOW
	if _retry_button != null:
		_retry_button.visible = not online
		_retry_button.disabled = false
	_refresh_status()


# --------------------------------------------------------------------------
# state


func _set_state(state: String) -> void:
	_state = state
	var idle: bool = state == "idle"
	_idle_box.visible = idle
	_room_box.visible = not idle
	if _room_footer != null:
		_room_footer.visible = not idle
	_profile_row.visible = idle
	_start_button.visible = state == "host"
	if _client_wait_label != null:
		_client_wait_label.visible = state == "client"
	_visibility_box.visible = state == "host"
	_copy_button.visible = state != "idle" and not Network.is_lan() \
		and _code_label.text.length() == 5 and _code_label.text != "-----"
	_leave_button.visible = not idle
	_code_caption.visible = not idle
	_title.text = "MULTIPLAYER" if idle else ("YOUR ROOM" if state == "host" else "ROOM LOBBY")
	_reset_leave_button()
	if idle:
		_code_label.text = "-----"
		_host_hint.text = ""
		_host_hint.visible = false
		if _server_checked:
			var online: bool = Network.server_online
			_join_button.disabled = not online
			_host_pi_button.disabled = not online
			_join_input.editable = online
			_join_input.focus_mode = Control.FOCUS_ALL if online else Control.FOCUS_NONE
		_refresh_status()
	else:
		UiAnim.fade_in(_room_box, 0.20)
	_refresh_config()
	_refresh_players()
	_refresh_teams()
	MenuNav.refresh()


func _refresh_config() -> void:
	if _game_pill == null:
		return
	var active: bool = Network.is_session_active()
	var host: bool = Network.is_host and _state == "host"
	var kind: String = _current_kind()
	_local_kind = kind
	var kind_index: int = KIND_VALUES.find(kind)
	_game_pill.call("set_index", maxi(kind_index, 0))
	_game_pill.disabled = not host

	var bots: int = Network.session_bot_count if active else GameSettings.effective_bot_count()
	_set_bots_views(clampi(bots, 0, 5))
	if _room_bots_pill != null:
		_room_bots_pill.disabled = not host
	if _difficulty_pill != null:
		_difficulty_pill.call("set_index", Network.bot_difficulty())
		_difficulty_pill.disabled = not host

	# Update live 16:9 screenshot + mode badge + map title
	var display: Dictionary = _lobby_display_for_kind(kind, active)
	var accent: Color = display.get("accent", UiPalette.GRASS) as Color
	if _lobby_mode_chip_style != null:
		_lobby_mode_chip_style.bg_color = accent
	if _lobby_mode_chip_label != null:
		_lobby_mode_chip_label.text = str(display.get("mode", "RACING"))
	if _lobby_map_title != null:
		_lobby_map_title.text = str(display.get("title", "MAP"))
	if _lobby_map_sub != null:
		_lobby_map_sub.text = str(display.get("sub", ""))
	var tex: Texture2D = display.get("texture", null) as Texture2D
	if _lobby_preview_tex != null:
		_lobby_preview_tex.texture = tex
		_lobby_preview_tex.visible = tex != null
	if _lobby_preview_fallback != null:
		_lobby_preview_fallback.accent = accent
		_lobby_preview_fallback.queue_redraw()

	if _change_mode_button != null:
		_change_mode_button.disabled = not host
		_change_mode_button.text = "CHANGE MODE & MAP" if host else "HOST PICKS MODE"
		if _change_mode_button.disabled:
			_apply_soft_disabled(_change_mode_button)
		_change_mode_button.fit_text()

	if _map_button != null:
		_map_button.visible = kind != KIND_SANDBOX and host
		_map_button.disabled = not host or kind == KIND_SANDBOX
		_map_button.text = "PICK TRACK" if kind == KIND_RACE else "PICK MAP"
		_map_button.fit_text()

	var channel: String = "racing" if kind == KIND_RACE \
		else ("minigame" if _is_party_kind(kind) else "sandbox")
	var shared_mode: bool = (Network.session_vehicle_mode == Network.VEHICLE_MODE_SHARED) \
		if active else (GameSettings.multiplayer_vehicle_mode == Network.VEHICLE_MODE_SHARED)
	if _vehicle_mode_pill != null:
		_vehicle_mode_pill.call("set_index", 1 if shared_mode else 0)
		_vehicle_mode_pill.disabled = not host

	var my_id: int = multiplayer.get_unique_id() if (active and multiplayer.multiplayer_peer != null) else 0
	var vehicle_id: String = Network.effective_vehicle_for(my_id, channel) if active \
		else GameSettings.vehicle_for_channel(channel)
	var vehicle: Dictionary = Catalog.find(vehicle_id)
	var car_name: String = str(vehicle.get("name", "SHOPPING CART"))
	var locked_to_host: bool = _state == "client" and shared_mode
	var vehicle_text: String = ("HOST CAR: " if locked_to_host else ("SHARED: " if shared_mode else "GARAGE: ")) + car_name
	if _vehicle_button != null:
		_vehicle_button.text = vehicle_text
		_vehicle_button.disabled = locked_to_host
		if _vehicle_button.disabled:
			_apply_soft_disabled(_vehicle_button)
		_vehicle_button.fit_text()

	var public_room: bool = Network.room_public if active else GameSettings.room_public
	_visibility_pill.call("set_index", 1 if public_room else 0)
	_visibility_pill.disabled = not host

	match kind:
		KIND_RACE:
			_start_button.text = "START RACE"
		KIND_DELIVER:
			_start_button.text = "START DELIVER"
		KIND_KNOCKOUT:
			_start_button.text = "START KNOCKOUT"
		KIND_BOMB_TAG:
			_start_button.text = "START BLAST TAG"
		_:
			_start_button.text = "START SANDBOX"
	_start_button.fit_text()
	_refresh_teams()
	_refresh_players()


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
		var chosen: bool = hex == selected
		for state: String in ["normal", "hover", "pressed"]:
			var style: StyleBoxFlat = button.get_theme_stylebox(state) as StyleBoxFlat
			if style == null:
				continue
			style.set_border_width_all(4 if chosen else 2)
			style.border_color = Color.WHITE if chosen else Color(0.08, 0.09, 0.18, 0.90)
		button.scale = Vector2.ONE * (1.16 if chosen else 1.0)


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
	_set_host_hint("Starting the room...")
	_copy_button.visible = false
	_start_button.visible = false
	_set_status("")
	Network.host_game(mode)


func _on_host_started(code: String) -> void:
	_set_state("host")
	_set_status("")
	_start_button.visible = true
	if Network.is_lan():
		_code_caption.text = "LOCAL WI-FI"
		_code_label.text = "LAN ROOM"
		_copy_button.visible = false
	else:
		_code_caption.text = "ROOM CODE"
		_code_label.text = code
		_copy_button.visible = code.length() == 5
	_refresh_visibility_hint()
	_refresh_config()
	_refresh_players()
	_refresh_teams()
	call_deferred("_focus_host")


func _on_visibility_changed(value: Variant) -> void:
	if not Network.is_host:
		_refresh_config()
		return
	var public_room: bool = bool(value)
	GameSettings.set_room_public(public_room)
	Network.set_room_public(public_room)
	_refresh_visibility_hint()
	_refresh_config()


func _set_host_hint(text: String) -> void:
	if _host_hint == null:
		return
	_host_hint.text = text
	_host_hint.visible = text != ""


func _refresh_visibility_hint() -> void:
	_set_host_hint("")


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
	_set_join_status("Connecting...")
	Network.join_game(code)


func _on_join_status(text: String) -> void:
	_set_join_status(text)


func _on_join_failed(reason: String) -> void:
	_join_button.disabled = not Network.server_online
	_apply_soft_disabled(_join_button)
	_set_join_status(reason)
	if _status.text.begins_with("Joining"):
		_set_status("")


func _on_join_succeeded() -> void:
	_set_state("client")
	_set_status("")
	_set_join_status("")
	_client_code = str(Network.get_meta("last_join_code", _join_input.text)).strip_edges().to_upper()
	if Network.is_lan():
		_code_caption.text = "LOCAL WI-FI"
		_code_label.text = "LAN ROOM"
		_copy_button.visible = false
	elif _client_code.length() == 5:
		_code_caption.text = "ROOM CODE"
		_code_label.text = _client_code
		_copy_button.visible = true
	else:
		_code_caption.text = "CONNECTED"
		_code_label.text = "ONLINE"
		_copy_button.visible = false
	_set_host_hint("")
	_title.text = "ROOM LOBBY"
	_refresh_config()
	_refresh_players()
	_refresh_teams()
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
	if _status.text != "" and _status.text != SERVER_DOWN:
		return
	if _server_checked and not Network.server_online and _status.text == SERVER_DOWN:
		_set_status(SERVER_DOWN)
	else:
		_set_status("")


# --------------------------------------------------------------------------
# host configuration


func _apply_host_selection(kind: String) -> void:
	_local_kind = kind
	var mode: String = GameSettings.GAME_SANDBOX if kind == KIND_SANDBOX \
		else GameSettings.GAME_MINIGAMES
	var scene: String = _scene_for_kind(kind)
	var event_id: String = _event_for_kind(kind)
	var target_id: String = ""
	if kind == KIND_RACE:
		target_id = Network.session_map_id \
			if (Network.is_session_active() and Network.session_map_id != "") \
			else GameSettings.selected_map
	elif _is_party_kind(kind):
		target_id = _ensure_arena_for_kind(kind)

	GameSettings.set_multiplayer_mode(mode)
	Network.configure_session(mode, GameSettings.bots_enabled,
		GameSettings.effective_bot_count(),
		target_id if kind == KIND_RACE else "", scene)
	if _is_party_kind(kind) and target_id != "" and ("session_minigame" in Network):
		Network.set("session_minigame", target_id)
	if Network.has_method("set_host_event"):
		if kind != KIND_SANDBOX or ("EVENT_SANDBOX" in Network):
			Network.call("set_host_event", event_id, target_id)


func _on_game_mode(kind: String) -> void:
	if not Network.is_host:
		_refresh_config()
		return
	_apply_host_selection(kind)
	_refresh_config()
	_refresh_teams()


func _on_bots_option(value: Variant) -> void:
	_apply_bot_total(int(value))


func _on_difficulty_option(value: Variant) -> void:
	if Network.is_session_active() and not Network.is_host:
		_refresh_config()
		return
	GameSettings.set_ai_difficulty(int(value))
	if Network.is_host and Network.is_session_active():
		Network.configure_session(Network.session_mode, Network.session_bots,
			Network.session_bot_count)
	_refresh_config()


func _apply_bot_total(total: int) -> void:
	if _state != "idle" and not Network.is_host:
		_refresh_config()
		return
	var clean: int = clampi(total, 0, 5)
	GameSettings.set_bot_total(clean)
	_set_bots_views(clean)
	if Network.is_host and Network.is_session_active():
		Network.configure_session(Network.session_mode,
			GameSettings.bots_enabled, GameSettings.effective_bot_count())


func _set_bots_views(total: int) -> void:
	var clean: int = clampi(total, 0, 5)
	if _room_bots_pill != null:
		_room_bots_pill.call("set_index", clean)


func _on_open_all_modes() -> void:
	## Opens Page 1 (SELECT MODE) of MinigamesMenu so the host sees all 5 modes
	## and can pick any mode & map visually with screenshots.
	if Network.is_session_active() and not Network.is_host:
		_set_status("Only the host can change the mode or map.")
		return
	GameSettings.vehicle_return_scene = LOBBY_SCENE
	MinigamesMenu.open_for_mode("")
	SceneLoader.go_to(MINIGAMES_SCENE, "SELECT MODE", "Choose mode & map for the room")


func _on_choose_map() -> void:
	if Network.is_session_active() and not Network.is_host:
		_set_status("Only the host can change the map.")
		return
	var kind: String = _current_kind()
	if kind == KIND_SANDBOX:
		_on_open_all_modes()
		return
	GameSettings.vehicle_return_scene = LOBBY_SCENE
	var target_page: String = "racing"
	if kind == KIND_DELIVER:
		target_page = "cargo_rush"
	elif kind == KIND_KNOCKOUT:
		target_page = "knockout"
	elif kind == KIND_BOMB_TAG:
		target_page = "bomb_tag"
	MinigamesMenu.open_for_mode(target_page)
	SceneLoader.go_to(MINIGAMES_SCENE,
		"SELECT TRACK" if kind == KIND_RACE else "SELECT MAP",
		"Choose a map for the room")


func _on_vehicle_mode_changed(value: Variant) -> void:
	if not Network.is_host:
		_refresh_config()
		return
	Network.set_session_vehicle_mode(str(value))
	_refresh_config()
	_refresh_players()


func _on_change_vehicle() -> void:
	var kind: String = _current_kind()
	if _state == "client" and Network.is_shared_vehicle_mode():
		return
	GameSettings.vehicle_return_scene = LOBBY_SCENE
	GameSettings.vehicle_return_title = "MULTIPLAYER"
	GameSettings.vehicle_edit_minigame = _is_party_kind(kind)
	VehicleSelect.set_racing_intent(kind == KIND_RACE)
	SceneLoader.go_to(VEHICLE_SCENE, "GARAGE", "Choose your ride")


func _on_start_pressed() -> void:
	if not Network.is_host:
		return
	var kind: String = _current_kind()
	var mode: String = GameSettings.GAME_SANDBOX if kind == KIND_SANDBOX \
		else GameSettings.GAME_MINIGAMES
	_apply_host_selection(kind)
	Network.start_game("", mode)


# --------------------------------------------------------------------------
# players


func _on_peers_changed() -> void:
	_refresh_players()
	_refresh_teams()
	if Network.is_host and Network.is_session_active() and Network.is_connected_to_server():
		Network.refresh_session_config()


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
	for peer_id: int in ids:
		var is_local: bool = peer_id == multiplayer.get_unique_id()
		var row_panel := PanelContainer.new()
		var row_style := StyleBoxFlat.new()
		row_style.bg_color = Color(0.14, 0.28, 0.42, 0.85) if is_local \
			else Color(0.11, 0.13, 0.25, 0.82)
		row_style.border_color = UiPalette.CYAN if is_local else Color(1.0, 1.0, 1.0, 0.14)
		row_style.set_border_width_all(2)
		row_style.set_corner_radius_all(4)
		row_style.content_margin_left = 14.0
		row_style.content_margin_right = 14.0
		row_style.content_margin_top = 8.0
		row_style.content_margin_bottom = 8.0
		row_style.anti_aliasing = true
		row_panel.add_theme_stylebox_override("panel", row_style)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.custom_minimum_size = Vector2(0, 24)
		row_panel.add_child(row)

		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(12, 12)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.color = Network.color_of(peer_id) if Network.player_colors.has(peer_id) \
			else UiPalette.YELLOW
		row.add_child(dot)

		var name_label := Label.new()
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.clip_text = true
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.add_theme_font_size_override("font_size", 15)
		name_label.add_theme_color_override("font_color", UiPalette.YELLOW if is_local else UiPalette.CREAM)
		var label_text: String = Network.name_of(peer_id)
		if is_local:
			label_text += "  (YOU)"
		if peer_id == 1:
			label_text = "HOST · " + label_text
		name_label.text = label_text
		row.add_child(name_label)

		var p_kind: String = _current_kind()
		var p_channel: String = "racing" if p_kind == KIND_RACE \
			else ("minigame" if _is_party_kind(p_kind) else "sandbox")
		var p_vid: String = Network.effective_vehicle_for(peer_id, p_channel)
		var p_entry: Dictionary = Catalog.find(p_vid)
		var p_car_lbl := Label.new()
		p_car_lbl.text = str(p_entry.get("name", "CART")).to_upper()
		p_car_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		p_car_lbl.add_theme_font_size_override("font_size", 11)
		p_car_lbl.add_theme_color_override("font_color", Color(0.76, 0.86, 1.0, 0.84))
		row.add_child(p_car_lbl)

		if Network.is_session_active() and Network.is_connected_to_server():
			var ms: int = int(Network.ping_table.get(peer_id, 0))
			if ms <= 0 and not Network.is_host and is_local:
				ms = maxi(Network.latency_ms, 0)
			if ms <= 0 and Network.is_host and peer_id == 1:
				ms = maxi(Network.host_ping_ms, 0)
			if ms > 0:
				var ping_label := Label.new()
				ping_label.text = "%d ms" % ms
				ping_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				ping_label.add_theme_font_size_override("font_size", 12)
				ping_label.add_theme_color_override("font_color", UiPalette.CYAN)
				row.add_child(ping_label)
		_players_box.add_child(row_panel)

	var open_slots: int = maxi(MAX_SLOTS - ids.size(), 0)
	if open_slots > 0:
		var open_label := Label.new()
		open_label.text = "%d OPEN SLOT%s" % [open_slots, "" if open_slots == 1 else "S"]
		open_label.add_theme_font_size_override("font_size", 12)
		open_label.add_theme_color_override("font_color", Color(0.68, 0.74, 0.88, 0.72))
		_players_box.add_child(open_label)


func _on_leave_pressed() -> void:
	if _state == "host" and not _leave_armed:
		_leave_armed = true
		_leave_ticket += 1
		var ticket: int = _leave_ticket
		_leave_button.text = "CONFIRM LEAVE"
		_leave_button.set("fill_color", UiPalette.RED_DARK)
		_leave_button.fit_text()
		_set_status(LEAVE_WARNING)
		await get_tree().create_timer(3.0).timeout
		if is_inside_tree() and _leave_armed and ticket == _leave_ticket:
			_reset_leave_button()
		return
	_leave_ticket += 1
	_reset_leave_button()
	Network.leave()
	SceneLoader.end_task()
	_set_state("idle")
	_set_status("")
	UiAnim.pop($Frame/Panel)


func _reset_leave_button() -> void:
	_leave_armed = false
	if _leave_button != null:
		_leave_button.text = "LEAVE ROOM"
		_leave_button.set("fill_color", UiPalette.RED)
		_leave_button.fit_text()
	if _status != null and _status.text == LEAVE_WARNING:
		_set_status("")


func _on_back_pressed() -> void:
	if _state == "host" and Network.is_session_active() and not _leave_armed:
		_on_leave_pressed()
		return
	Network.leave()
	SceneLoader.end_task()
	SceneLoader.go_to(PLAY_MENU_SCENE, "PLAY")
