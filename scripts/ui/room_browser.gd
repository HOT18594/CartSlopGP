extends Control
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## Room browser popup. BROWSE ONLINE ROOMS and FIND LAN ROOMS both open this;
## the search field filters the fetched list locally (no extra network calls),
## and picking a row hands the room back to the lobby.
##
## Rows are structured: host name on the left, N/8 players in the middle and a
## chevron on the right. Room codes are never shown here: public rooms join in
## one click, private rooms stay out of the list and use the typed code path.
## Loading, empty, no-match and server-error states each get their own message
## and a recovery action instead of all looking like the same blank list.

signal room_selected(room: Dictionary)
signal closed
signal host_requested(mode: String)

const CANDY_BUTTON: String = "res://scripts/ui/candy_button.gd"
const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const MAX_PLAYERS: int = 8

@onready var _body: VBoxContainer = $Center/Panel/Body
@onready var _panel: PanelContainer = %Panel
@onready var _title: Label = %Title
@onready var _close_button: Button = %CloseButton
@onready var _search_field: LineEdit = %SearchField
@onready var _refresh_button: Button = %RefreshButton
@onready var _list_scroll: ScrollContainer = %ListScroll
@onready var _list: VBoxContainer = %List
@onready var _status: Label = %StatusLabel

var _rooms: Array[Dictionary] = []
var _query: String = ""
var _mode: String = "online"
var _busy: bool = false
var _error: bool = false
var _status_kind: String = "idle"
var _loading_dots: int = 0
var _status_timer: float = 0.0
var _ticket: int = 0
var _action_button: Button
var _action_callable: Callable = Callable()


func _ready() -> void:
	add_to_group("nav_scope")
	hide()
	_close_button.pressed.connect(close)
	_refresh_button.pressed.connect(func() -> void: _refresh())
	_search_field.text_changed.connect(_on_search_changed)
	_style_scrollbar()
	_apply_soft_disabled(_refresh_button)
	_build_action_button()


func open(mode: String) -> void:
	_mode = "lan" if mode == "lan" else "online"
	_query = ""
	_search_field.text = ""
	_title.text = _base_title()
	show()
	UiAnim.pop(_panel)
	MenuNav.refresh()
	# A scan from a previous open may still be awaiting. Invalidate it so its
	# late result cannot repaint this fresh list.
	_ticket += 1
	_busy = false
	_error = false
	_refresh()


func close() -> void:
	if not visible:
		return
	hide()
	_ticket += 1
	_busy = false
	_panel.scale = Vector2.ONE
	_panel.modulate = Color.WHITE
	_refresh_button.disabled = false
	MenuNav.refresh()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible or not _busy or _status_kind != "loading":
		return
	_status_timer += delta
	if _status_timer >= 0.35:
		_status_timer = 0.0
		_loading_dots = (_loading_dots + 1) % 4
		_status.text = "LOOKING FOR ROOMS" + ".".repeat(_loading_dots)


func _on_search_changed(text: String) -> void:
	_query = text.strip_edges().to_upper()
	_rebuild_list()


func _refresh() -> void:
	if _busy:
		return
	_busy = true
	_ticket += 1
	var ticket: int = _ticket
	_refresh_button.disabled = true
	_clear_list()
	_set_state("loading", "LOOKING FOR ROOMS...", "", Callable())
	_title.text = _base_title()
	var result: Array = []
	if _mode == "lan":
		result = await Network.scan_lan_rooms()
	else:
		result = await Network.fetch_lobbies()
	if not is_inside_tree() or ticket != _ticket:
		return
	_busy = false
	_refresh_button.disabled = false
	_rooms.clear()
	for entry: Variant in result:
		if entry is Dictionary:
			_rooms.append(entry as Dictionary)
	_error = _mode == "online" and _rooms.is_empty() and not Network.server_online
	_rebuild_list()
	MenuNav.refresh()


func set_rooms(rooms: Array) -> void:
	## Used by dev shots/tests to populate the list without a live server.
	_ticket += 1
	_busy = false
	_error = false
	_refresh_button.disabled = false
	_rooms.clear()
	for entry: Variant in rooms:
		if entry is Dictionary:
			_rooms.append(entry as Dictionary)
	_rebuild_list()


func _clear_list() -> void:
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()


func _rebuild_list() -> void:
	_clear_list()
	if _busy:
		return
	var shown: int = 0
	for room: Dictionary in _rooms:
		if not _matches(room):
			continue
		shown += 1
		var row_button: Button = _room_row(room)
		_list.add_child(row_button)
		if row_button.disabled:
			# candy_button applies its own disabled style on _ready; replace it
			# with the readable lavender one after the row enters the tree.
			_apply_soft_disabled(row_button)
	if shown > 0:
		_set_state("idle", "", "", Callable())
		_title.text = "%s  ·  %d OPEN" % [_base_title(), shown]
		MenuNav.refresh()
		return
	_title.text = _base_title()
	if _error:
		_set_state("error", "COULDN'T REACH THE ROOM SERVICE.", "RETRY", _refresh,
			UiPalette.YELLOW)
	elif _rooms.is_empty():
		var action_text: String = "HOST LAN ROOM" if _mode == "lan" else "HOST ONLINE ROOM"
		var empty_text: String = "NO LAN ROOMS FOUND. ASK A FRIEND TO HOST." \
			if _mode == "lan" else "NO ONLINE ROOMS RIGHT NOW."
		_set_state("empty", empty_text, action_text, _host_requested, UiPalette.YELLOW)
	else:
		_set_state("nomatch", "NO ROOMS MATCH \"%s\"." % _query, "CLEAR SEARCH",
			_clear_search, UiPalette.BLUE)
	MenuNav.refresh()


func _room_row(room: Dictionary) -> Button:
	var state: String = _room_state(room)
	var is_lan: bool = _mode == "lan"
	var players: int = clampi(int(room.get("players", 1)), 0, MAX_PLAYERS)
	var full: bool = players >= MAX_PLAYERS
	var joinable: bool = (not is_lan or state == "lobby") and not full
	var button := _candy("", UiPalette.CREAM, 60, 17)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.disabled = not joinable
	if full:
		button.tooltip_text = "ROOM IS FULL"
	elif not joinable:
		button.tooltip_text = "ROOM IN PROGRESS"
	else:
		button.tooltip_text = "JOIN ROOM"
	_apply_soft_disabled(button)
	button.pressed.connect(_on_room_pressed.bind(room))

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 18
	row.offset_right = -18
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)

	var name_label := Label.new()
	name_label.text = _room_name(room)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", UiPalette.INK)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_label)

	var players_label := Label.new()
	players_label.text = "%d/%d PLAYERS" % [players, MAX_PLAYERS]
	players_label.custom_minimum_size = Vector2(112, 0)
	players_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	players_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	players_label.add_theme_font_size_override("font_size", 15)
	players_label.add_theme_color_override("font_color", UiPalette.BODY_BLUE)
	players_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(players_label)

	# Room codes are never shown in the browser. A dim badge appears only when
	# a room cannot be joined, so a normal public row is just host + players.
	if not joinable:
		var badge_text: String = "FULL" if full else "IN GAME"
		row.add_child(_row_badge(badge_text, UiPalette.TEXT_DIM))

	return button


func _row_badge(text: String, color: Color) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.custom_minimum_size = Vector2(88, 30)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(9)
	style.set_border_width_all(2)
	style.border_color = UiPalette.INK
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	badge.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", UiPalette.INK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(label)
	return badge


func _room_name(room: Dictionary) -> String:
	return str(room.get("name", room.get("host", "HOST"))).strip_edges().to_upper()


func _room_state(room: Dictionary) -> String:
	return str(room.get("state", "lobby")).strip_edges().to_lower()


func _matches(room: Dictionary) -> bool:
	# The server only lists public rooms; this also hides a private row if a
	# stale/offline fixture ever supplies one.
	if _mode == "online" and room.has("public") and not bool(room.get("public")):
		return false
	if _query == "":
		return true
	return _room_name(room).contains(_query)


func _on_room_pressed(room: Dictionary) -> void:
	room_selected.emit(room)
	close()


func _host_requested() -> void:
	host_requested.emit(_mode)
	close()


func _clear_search() -> void:
	_query = ""
	_search_field.text = ""
	_rebuild_list()


func _base_title() -> String:
	return "LAN ROOMS" if _mode == "lan" else "ONLINE ROOMS"


func _build_action_button() -> void:
	_action_button = _candy("", UiPalette.YELLOW, 44, 16)
	_action_button.custom_minimum_size = Vector2(240, 44)
	_action_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_action_button.visible = false
	_action_button.pressed.connect(_on_action_pressed)
	_body.add_child(_action_button)


func _on_action_pressed() -> void:
	if _action_callable.is_valid():
		_action_callable.call()


func _set_state(kind: String, text: String, action_text: String = "",
		action: Callable = Callable(), action_color: Color = Color.WHITE) -> void:
	_status_kind = kind
	_status.text = text
	_status.visible = text != ""
	_status.add_theme_font_size_override("font_size",
		16 if kind == "loading" else (17 if kind == "error" else 18))
	var color: Color = UiPalette.BODY_BLUE
	match kind:
		"error":
			color = UiPalette.ERROR
		"empty":
			color = UiPalette.MUTED
		"nomatch":
			color = UiPalette.INK
		_:
			color = UiPalette.BODY_BLUE
	_status.add_theme_color_override("font_color", color)
	_action_callable = action
	if _action_button != null:
		_action_button.visible = action_text != ""
		_action_button.disabled = false
		_action_button.text = action_text
		_action_button.set("fill_color", action_color)
	if kind == "loading":
		_loading_dots = 0
		_status_timer = 0.0


func _style_scrollbar() -> void:
	if _list_scroll == null:
		return
	var bar: VScrollBar = _list_scroll.get_v_scroll_bar()
	if bar == null:
		return
	bar.custom_minimum_size.x = 14
	var track := StyleBoxFlat.new()
	track.bg_color = Color(UiPalette.INK, 0.10)
	track.set_corner_radius_all(7)
	var grab := StyleBoxFlat.new()
	grab.bg_color = UiPalette.BLUE
	grab.set_corner_radius_all(7)
	grab.set_border_width_all(2)
	grab.border_color = UiPalette.INK
	var grab_hover: StyleBoxFlat = grab.duplicate()
	grab_hover.bg_color = UiPalette.BLUE.lightened(0.12)
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("grabber", grab)
	bar.add_theme_stylebox_override("grabber_highlight", grab_hover)
	bar.add_theme_stylebox_override("grabber_pressed", grab_hover)


func _apply_soft_disabled(button: Button) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("d8d3e4")
	style.set_corner_radius_all(20)
	style.set_border_width_all(5)
	style.border_color = Color("4b4560")
	style.shadow_color = Color(0.12, 0.10, 0.23, 0.30)
	style.shadow_offset = Vector2(0, 4)
	style.content_margin_left = 26
	style.content_margin_right = 26
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	button.add_theme_stylebox_override("disabled", style)


func _candy(text: String, color: Color, height: int, font_size: int) -> Button:
	var button := Button.new()
	button.set_script(load(CANDY_BUTTON))
	button.set("fill_color", color)
	button.set("corner_radius", mini(int(height / 2), 28))
	button.set("shadow_offset", clampi(int(height / 10), 3, 8))
	button.text = text
	button.custom_minimum_size = Vector2(0, height)
	button.add_theme_font_size_override("font_size", font_size)
	return button
