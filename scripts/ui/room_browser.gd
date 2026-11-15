extends Control
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## Room browser popup. SEARCH opens it in merged mode: it scans LAN rooms and
## public online rooms at the same time and shows one list, LAN rows first.
## Every merged row is badged LAN or ONLINE so the player knows the source.
##
## The search field filters the fetched list locally (no extra network calls),
## and picking a row hands the room back to the lobby. Rows are structured:
## host name on the left, source badge, N/8 players and a chevron-equivalent
## status badge on the right. Room codes are never shown here: public rooms
## join in one click, private rooms stay out of the list and use the typed code
## path. Loading, empty, no-match and server-error states each get their own
## message and a recovery action instead of all looking like a blank list.

signal room_selected(room: Dictionary)
signal closed
signal host_requested(mode: String)

const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const MAX_PLAYERS: int = 8
const SOURCE_LAN: String = "lan"
const SOURCE_ONLINE: String = "online"

@onready var _body: VBoxContainer = $Center/Panel/Body
@onready var _panel: PanelContainer = %Panel
@onready var _title: Label = %Title
@onready var _count_label: Label = %RoomCount
@onready var _close_button: Button = %CloseButton
@onready var _search_field: LineEdit = %SearchField
@onready var _refresh_button: Button = %RefreshButton
@onready var _list_scroll: ScrollContainer = %ListScroll
@onready var _list: VBoxContainer = %List
@onready var _status: Label = %StatusLabel

var _rooms: Array[Dictionary] = []
var _lan_rooms: Array[Dictionary] = []
var _online_rooms: Array[Dictionary] = []
var _query: String = ""
var _mode: String = "all"
var _busy: bool = false
var _error: bool = false
var _online_failed: bool = false
var _lan_pending: bool = false
var _online_pending: bool = false
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
	_search_field.set_meta("nav_default", true)
	_title.text = _base_title()
	_count_label.text = "0 ROOMS"
	_close_button.tooltip_text = "Close the browser and go back to the lobby."
	_refresh_button.tooltip_text = "Scan LAN and public online rooms again."
	_search_field.tooltip_text = "Filter the merged list by host name. Rooms join with one click."
	_style_scrollbar()
	_apply_soft_disabled(_refresh_button)
	_build_action_button()


func open(mode: String) -> void:
	_mode = "all" if mode == "all" else ("lan" if mode == "lan" else "online")
	_query = ""
	_search_field.text = ""
	_title.text = _base_title()
	show()
	UiAnim.pop(_panel)
	MenuNav.refresh()
	MenuNav.focus(_search_field)
	# A scan from a previous open may still be awaiting. Invalidate it so its
	# late result cannot repaint this fresh list.
	_ticket += 1
	_busy = false
	_error = false
	_online_failed = false
	_lan_pending = false
	_online_pending = false
	_refresh()


func request_close() -> void:
	## MenuNav's Escape fallback calls this; only the browser itself closes.
	close()


func close() -> void:
	if not visible:
		return
	hide()
	_ticket += 1
	_busy = false
	_panel.scale = Vector2.ONE
	_panel.modulate = Color.WHITE
	_refresh_button.disabled = false
	_refresh_button.text = "REFRESH"
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
		_status.text = _loading_text() + ".".repeat(_loading_dots)


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
	_refresh_button.text = "REFRESHING"
	_clear_list()
	# A refresh starts at the top of the list again, so a scan that returns
	# fewer rooms can never leave the scroll past the new end.
	_list_scroll.scroll_vertical = 0
	_count_label.text = "SCANNING"
	_set_state("loading", _loading_text() + "...", "", Callable())
	_title.text = _base_title()
	if _mode == "all":
		# Both sources are asked at the same time. The list appears once both
		# have answered so LAN and online rows never flicker into place.
		_lan_rooms.clear()
		_online_rooms.clear()
		_lan_pending = true
		_online_pending = true
		_online_failed = false
		_scan_lan(ticket)
		_scan_online(ticket)
		return
	var result: Array = []
	if _mode == "lan":
		result = await Network.scan_lan_rooms()
	else:
		result = await Network.fetch_lobbies()
	if not is_inside_tree() or ticket != _ticket:
		return
	_busy = false
	_refresh_button.disabled = false
	_refresh_button.text = "REFRESH"
	_rooms.clear()
	for entry: Variant in result:
		if entry is Dictionary:
			_rooms.append(entry as Dictionary)
	_error = _mode == "online" and _rooms.is_empty() and not Network.server_online
	_rebuild_list()
	MenuNav.refresh()


func _scan_lan(ticket: int) -> void:
	var result: Array = await Network.scan_lan_rooms()
	if not is_inside_tree() or ticket != _ticket:
		return
	_lan_rooms = _tag_rooms(result, SOURCE_LAN)
	_lan_pending = false
	_finish_merged(ticket)


func _scan_online(ticket: int) -> void:
	var result: Array = await Network.fetch_lobbies()
	if not is_inside_tree() or ticket != _ticket:
		return
	_online_failed = not Network.server_online
	_online_rooms = _tag_rooms(result, SOURCE_ONLINE)
	_online_pending = false
	_finish_merged(ticket)


func _tag_rooms(entries: Array, source: String) -> Array[Dictionary]:
	## Copy every row and stamp its source, so join routing and the row badge
	## cannot depend on whichever page happened to open the browser.
	var tagged: Array[Dictionary] = []
	for entry: Variant in entries:
		if entry is Dictionary:
			var room: Dictionary = (entry as Dictionary).duplicate()
			room["_source"] = source
			tagged.append(room)
	return tagged


func _finish_merged(ticket: int) -> void:
	if not _busy or ticket != _ticket or _lan_pending or _online_pending:
		return
	_busy = false
	_refresh_button.disabled = false
	_refresh_button.text = "REFRESH"
	_rooms.clear()
	# LAN first: local rooms need no internet and should be the first thing the
	# player sees. Online rows follow in the same list.
	for room: Dictionary in _lan_rooms:
		_rooms.append(room)
	for room: Dictionary in _online_rooms:
		_rooms.append(room)
	_error = _rooms.is_empty() and _online_failed
	_rebuild_list()
	MenuNav.refresh()


func _loading_text() -> String:
	return "SEARCHING LAN AND ONLINE" if _mode == "all" else "LOOKING FOR ROOMS"


func set_rooms(rooms: Array) -> void:
	## Used by dev shots/tests to populate the list without a live server.
	_ticket += 1
	_busy = false
	_error = false
	_online_failed = false
	_lan_pending = false
	_online_pending = false
	_refresh_button.disabled = false
	_rooms.clear()
	for entry: Variant in rooms:
		if entry is Dictionary:
			_rooms.append(entry as Dictionary)
	_list_scroll.scroll_vertical = 0
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
		_list.add_child(_room_row(room))
	if shown > 0:
		var note: String = ""
		if _mode == "all" and _online_failed:
			note = "  ·  ONLINE SEARCH UNAVAILABLE"
		_set_state("idle", "%d ROOM%s%s  ·  TAB TO A ROOM, THEN PRESS ENTER" % [
			shown, "" if shown == 1 else "S", note], "", Callable())
		_title.text = _base_title()
		_count_label.text = "%d ROOM%s" % [shown, "" if shown == 1 else "S"]
		MenuNav.refresh()
		_restore_row_focus()
		return
	_title.text = _base_title()
	_count_label.text = "0 FOUND" if _query != "" and not _rooms.is_empty() else "0 ROOMS"
	if _error:
		var error_text: String = "COULDN'T REACH THE ROOM SERVICE."
		if _mode == "all":
			error_text = "COULDN'T REACH THE ROOM SERVICE, AND NO LAN ROOMS ANSWERED."
		_set_state("error", error_text, "RETRY", _refresh, UiPalette.YELLOW)
	elif _rooms.is_empty():
		if _mode == "all":
			_set_state("empty", "NO LAN OR ONLINE ROOMS RIGHT NOW. ASK A FRIEND TO HOST.",
				"SEARCH AGAIN", _refresh, UiPalette.YELLOW)
		else:
			var action_text: String = "HOST LAN ROOM" if _mode == "lan" else "HOST ONLINE ROOM"
			var empty_text: String = "NO LAN ROOMS FOUND. ASK A FRIEND TO HOST." \
				if _mode == "lan" else "NO ONLINE ROOMS RIGHT NOW."
			_set_state("empty", empty_text, action_text, _host_requested, UiPalette.YELLOW)
	else:
		_set_state("nomatch", "NO ROOMS MATCH \"%s\"." % _query, "CLEAR SEARCH",
			_clear_search, UiPalette.BLUE)
	MenuNav.refresh()


func _restore_row_focus() -> void:
	## A refresh replaces every row, and the focused row that was freed left the
	## keyboard ring on nothing: Enter did nothing until the nav timer noticed.
	## Put the ring on the first open row straight away, unless the search field
	## (or another live control) still owns it.
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null and is_instance_valid(focused) and focused.is_visible_in_tree():
		return
	for child: Node in _list.get_children():
		var row := child as Button
		if row != null and not row.disabled:
			if MenuNav.focus(row):
				return


func _room_row(room: Dictionary) -> Button:
	var state: String = _room_state(room)
	var source: String = _room_source(room)
	var is_lan: bool = source == SOURCE_LAN
	var players: int = clampi(int(room.get("players", 1)), 0, MAX_PLAYERS)
	var full: bool = players >= MAX_PLAYERS
	var joinable: bool = (not is_lan or state == "lobby") and not full
	# A room is a quiet tinted row, not a bordered pill: the gap between rows
	# already separates them and the focus ring is the only outline.
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 56)
	button.add_theme_stylebox_override("normal", _row_style(Color(UiPalette.CREAM, 0.60)))
	button.add_theme_stylebox_override("hover", _row_style(Color(1, 1, 1, 0.95)))
	button.add_theme_stylebox_override("pressed", _row_style(UiPalette.YELLOW))
	button.add_theme_stylebox_override("disabled", _row_style(Color(0.84, 0.81, 0.89, 0.55)))
	button.disabled = not joinable
	UiKit.apply_focus_ring(button, UiKit.CORNER_RADIUS)
	if full:
		button.tooltip_text = "ROOM IS FULL"
	elif not joinable:
		button.tooltip_text = "ROOM IN PROGRESS"
	elif _mode == "all":
		button.tooltip_text = "JOIN THIS %s ROOM" % ("LAN" if is_lan else "ONLINE")
	else:
		button.tooltip_text = "JOIN ROOM"
	button.pressed.connect(_on_room_pressed.bind(room))

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = UiKit.SPACING
	row.offset_right = -UiKit.SPACING
	row.add_theme_constant_override("separation", UiKit.SPACING)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)

	var name_label := Label.new()
	name_label.text = _room_name(room)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", UiPalette.INK)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_label)

	# Merged results must say where the room lives, because tapping it runs a
	# different join path. Single-source lists already say it in the title.
	if _mode == "all":
		row.add_child(_row_badge("LAN" if is_lan else "ONLINE",
			UiPalette.CYAN if is_lan else UiPalette.BLUE, 78))

	var players_label := Label.new()
	players_label.text = "%d/%d PLAYERS" % [players, MAX_PLAYERS]
	players_label.custom_minimum_size = Vector2(112, 0)
	players_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	players_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	players_label.add_theme_font_size_override("font_size", 15)
	players_label.add_theme_color_override("font_color", UiPalette.BODY_BLUE)
	players_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(players_label)

	# Ping is optional: LAN discovery and the lobby listing do not carry it, so
	# the label only appears when a room dictionary already knows its latency.
	var ping: int = int(room.get("ping", 0))
	if ping > 0:
		var ping_label := Label.new()
		ping_label.text = "%d ms" % ping
		ping_label.custom_minimum_size = Vector2(64, 0)
		ping_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		ping_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ping_label.add_theme_font_size_override("font_size", 13)
		ping_label.add_theme_color_override("font_color", UiPalette.BODY_BLUE)
		ping_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(ping_label)

	# Room codes are never shown in the browser. A dim badge appears only when
	# a room cannot be joined, so a normal public row is just host + players.
	if not joinable:
		var badge_text: String = "FULL" if full else "IN GAME"
		row.add_child(_row_badge(badge_text, UiPalette.TEXT_DIM))

	return button


func _row_badge(text: String, color: Color, min_width: float = 88.0) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.custom_minimum_size = Vector2(min_width, 30)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(10)
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


func _room_source(room: Dictionary) -> String:
	var tagged: String = str(room.get("_source", ""))
	if tagged == SOURCE_LAN or tagged == SOURCE_ONLINE:
		return tagged
	return SOURCE_LAN if _mode == "lan" else SOURCE_ONLINE


func _room_name(room: Dictionary) -> String:
	return str(room.get("name", room.get("host", "HOST"))).strip_edges().to_upper()


func _room_state(room: Dictionary) -> String:
	return str(room.get("state", "lobby")).strip_edges().to_lower()


func _matches(room: Dictionary) -> bool:
	# The server only lists public rooms; this also hides a private row if a
	# stale/offline fixture ever supplies one. LAN rows carry no public flag.
	if _room_source(room) == SOURCE_ONLINE and room.has("public") \
			and not bool(room.get("public")):
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
	if _mode == "all":
		return "LAN + ONLINE ROOMS"
	return "LAN ROOMS" if _mode == "lan" else "ONLINE ROOMS"


func _build_action_button() -> void:
	_action_button = _candy("", UiPalette.YELLOW, 48, 16)
	_action_button.custom_minimum_size = Vector2(220, 48)
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
	grab.bg_color = Color(UiPalette.BLUE, 0.75)
	grab.set_corner_radius_all(7)
	var grab_hover: StyleBoxFlat = grab.duplicate()
	grab_hover.bg_color = UiPalette.BLUE.lightened(0.12)
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("grabber", grab)
	bar.add_theme_stylebox_override("grabber_highlight", grab_hover)
	bar.add_theme_stylebox_override("grabber_pressed", grab_hover)


func _apply_soft_disabled(button: Button) -> void:
	## One quiet disabled tint. The old style stacked a 5 px outline and a
	## drop shadow on top of the candy border, which read as a double border.
	var style := StyleBoxFlat.new()
	style.bg_color = Color("d8d3e4")
	style.set_corner_radius_all(UiKit.CORNER_RADIUS)
	style.content_margin_left = UiKit.SPACING
	style.content_margin_right = UiKit.SPACING
	style.content_margin_top = UiKit.SPACING_TIGHT
	style.content_margin_bottom = UiKit.SPACING_TIGHT
	button.add_theme_stylebox_override("disabled", style)


func _row_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(UiKit.CORNER_RADIUS)
	style.content_margin_left = UiKit.SPACING
	style.content_margin_right = UiKit.SPACING
	style.content_margin_top = UiKit.SPACING_TIGHT
	style.content_margin_bottom = UiKit.SPACING_TIGHT
	style.anti_aliasing = true
	return style


func _candy(text: String, color: Color, height: int, font_size: int) -> Button:
	return UiKit.tile(text, color, float(height), font_size)
