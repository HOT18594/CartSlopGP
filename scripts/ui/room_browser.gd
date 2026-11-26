extends Control
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## Room browser popup: merged LAN + online list with padded ScrollContainer so
## focus rings never clip and zero repeated room-count/tutorial clutter.

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
	_apply_dark_slanted_theme()
	_close_button.pressed.connect(close)
	_refresh_button.pressed.connect(func() -> void: _refresh())
	_search_field.text_changed.connect(_on_search_changed)
	_search_field.set_meta("nav_default", true)
	_title.text = _base_title()
	_count_label.text = "0 ROOMS"
	_style_scrollbar()
	_apply_soft_disabled(_refresh_button)
	_build_action_button()
	resized.connect(_fit_panel)
	_fit_panel()


func _apply_dark_slanted_theme() -> void:
	if _panel != null:
		_panel.add_theme_stylebox_override("panel",
			UiKit.slanted_panel(Color(0.056, 0.068, 0.156, 0.95),
				Color(0.24, 0.84, 0.96, 0.56), 0.05, 4, 6, 36.0, 26.0))
	if _title != null:
		_title.add_theme_color_override("font_color", UiPalette.YELLOW)
		_title.add_theme_color_override("font_outline_color", UiPalette.INK)
		_title.add_theme_constant_override("outline_size", 8)
	if _count_label != null:
		_count_label.add_theme_color_override("font_color", UiPalette.CYAN)
	if _search_field != null:
		_search_field.set_meta("skip_kit", true)
		_search_field.add_theme_color_override("font_color", UiPalette.CREAM)
		_search_field.add_theme_color_override("font_placeholder_color", Color(0.62, 0.72, 0.88, 0.55))
		_search_field.add_theme_color_override("caret_color", UiPalette.YELLOW)
		_search_field.add_theme_color_override("selection_color", Color(UiPalette.CYAN, 0.35))
		var normal: StyleBoxFlat = UiKit.slanted_card(
			Color(0.045, 0.055, 0.125, 0.96), Color(0.28, 0.78, 0.96, 0.48),
			0.14, 3, 5, 16.0, 10.0)
		_search_field.add_theme_stylebox_override("normal", normal)
		var focus_st: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
		focus_st.border_color = UiPalette.YELLOW
		_search_field.add_theme_stylebox_override("focus", focus_st)
	if _list_scroll != null:
		var list_bg: StyleBoxFlat = UiKit.slanted_card(
			Color(0.038, 0.046, 0.106, 0.82), Color(0.24, 0.72, 0.94, 0.24),
			0.035, 2, 6, 8.0, 8.0)
		_list_scroll.add_theme_stylebox_override("panel", list_bg)


func _fit_panel() -> void:
	if _panel == null:
		return
	var vp: Vector2 = size if size.x > 1.0 else get_viewport_rect().size
	if vp.x < 1.0 or vp.y < 1.0:
		return
	_panel.custom_minimum_size = Vector2(
		clampf(vp.x - 48.0, 640.0, 820.0),
		clampf(vp.y - 48.0, 420.0, 540.0))


func open(mode: String) -> void:
	_mode = "all" if mode == "all" else ("lan" if mode == "lan" else "online")
	_query = ""
	_search_field.text = ""
	_title.text = _base_title()
	_fit_panel()
	show()
	UiAnim.pop(_panel)
	MenuNav.refresh()
	MenuNav.focus(_search_field)
	_ticket += 1
	_busy = false
	_error = false
	_online_failed = false
	_lan_pending = false
	_online_pending = false
	_refresh()


func request_close() -> void:
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
	_refresh_button.fit_text()
	MenuNav.refresh()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		UiKit.consume_input(self)
		close()


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
	_refresh_button.fit_text()
	_clear_list()
	_list_scroll.scroll_vertical = 0
	_count_label.text = "SCANNING"
	_set_state("loading", _loading_text() + "...", "", Callable())
	_title.text = _base_title()
	if _mode == "all":
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
	_refresh_button.fit_text()
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
	_render_partial(ticket)
	_finish_merged(ticket)


func _scan_online(ticket: int) -> void:
	var result: Array = await Network.fetch_lobbies()
	if not is_inside_tree() or ticket != _ticket:
		return
	_online_failed = not Network.server_online
	_online_rooms = _tag_rooms(result, SOURCE_ONLINE)
	_online_pending = false
	_render_partial(ticket)
	_finish_merged(ticket)


func _tag_rooms(entries: Array, source: String) -> Array[Dictionary]:
	var tagged: Array[Dictionary] = []
	for entry: Variant in entries:
		if entry is Dictionary:
			var room: Dictionary = (entry as Dictionary).duplicate()
			room["_source"] = source
			tagged.append(room)
	return tagged


func _render_partial(ticket: int) -> void:
	if ticket != _ticket or not is_inside_tree():
		return
	_rooms.clear()
	for room: Dictionary in _lan_rooms:
		if _prefilter(room):
			_rooms.append(room)
	for room: Dictionary in _online_rooms:
		if _prefilter(room):
			_rooms.append(room)
	_sort_rooms()
	_clear_list()
	if _rooms.is_empty():
		return
	var shown: int = 0
	for room: Dictionary in _rooms:
		if not _matches(room):
			continue
		shown += 1
		_list.add_child(_room_row(room))
	if shown > 0:
		_count_label.text = "%d ROOM%s" % [shown, "" if shown == 1 else "S"]
		_set_state("idle", "", "", Callable())
		_title.text = _base_title()
		MenuNav.refresh()
		_restore_row_focus()


func _prefilter(room: Dictionary) -> bool:
	if int(room.get("players", 1)) >= MAX_PLAYERS:
		return false
	var room_ver: String = str(room.get("version", "")).strip_edges()
	if room_ver != "":
		var local_ver: String = str(ProjectSettings.get_setting("application/config/version", "")).strip_edges()
		if local_ver != "" and room_ver != local_ver:
			return false
	return true


func _sort_rooms() -> void:
	_rooms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa: int = 0 if str(a.get("_source", SOURCE_ONLINE)) == SOURCE_LAN else 1
		var sb: int = 0 if str(b.get("_source", SOURCE_ONLINE)) == SOURCE_LAN else 1
		if sa != sb:
			return sa < sb
		return int(a.get("ping", 9999)) < int(b.get("ping", 9999)))


func _finish_merged(ticket: int) -> void:
	if not _busy or ticket != _ticket or _lan_pending or _online_pending:
		return
	_busy = false
	_refresh_button.disabled = false
	_refresh_button.text = "REFRESH"
	_refresh_button.fit_text()
	_rooms.clear()
	for room: Dictionary in _lan_rooms:
		if _prefilter(room):
			_rooms.append(room)
	for room: Dictionary in _online_rooms:
		if _prefilter(room):
			_rooms.append(room)
	_sort_rooms()
	_error = _rooms.is_empty() and _online_failed
	_rebuild_list()
	MenuNav.refresh()


func _loading_text() -> String:
	return "SEARCHING LAN & ONLINE" if _mode == "all" else "SEARCHING ROOMS"


func set_rooms(rooms: Array) -> void:
	_ticket += 1
	_busy = false
	_error = false
	_online_failed = false
	_lan_pending = false
	_online_pending = false
	_refresh_button.disabled = false
	_refresh_button.text = "REFRESH"
	_refresh_button.fit_text()
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
	_sort_rooms()
	var shown: int = 0
	for room: Dictionary in _rooms:
		if not _prefilter(room):
			continue
		if not _matches(room):
			continue
		shown += 1
		_list.add_child(_room_row(room))
	if shown > 0:
		var note: String = ""
		if _mode == "all" and _online_failed:
			note = "ONLINE ROOMS UNAVAILABLE  ·  SHOWING LAN ONLY"
		_set_state("idle", note, "", Callable())
		_title.text = _base_title()
		_count_label.text = "%d ROOM%s" % [shown, "" if shown == 1 else "S"]
		MenuNav.refresh()
		_restore_row_focus()
		return
	_title.text = _base_title()
	_count_label.text = "0 FOUND" if _query != "" and not _rooms.is_empty() else "0 ROOMS"
	# macOS 15+ can block LAN traffic until the player allows the app under
	# System Settings > Privacy & Security > Local Network. Without this line a
	# Mac user just sees "NO LAN ROOMS FOUND" with no way to fix it.
	var mac_hint: String = Network.local_network_hint() if _mode != "online" else ""
	if _error:
		var error_text: String = "COULDN'T REACH THE ROOM SERVER."
		if _mode == "all":
			error_text = "ONLINE SERVER UNREACHABLE & NO LAN ROOMS FOUND."
		_set_state("error", _with_hint(error_text, mac_hint), "RETRY", _refresh, UiPalette.YELLOW)
	elif _rooms.is_empty():
		if _mode == "all":
			_set_state("empty", _with_hint("NO ACTIVE ROOMS FOUND.", mac_hint),
				"SEARCH AGAIN", _refresh, UiPalette.YELLOW)
		else:
			var action_text: String = "HOST LAN ROOM" if _mode == "lan" else "HOST ONLINE ROOM"
			var empty_text: String = "NO LAN ROOMS FOUND." \
				if _mode == "lan" else "NO ONLINE ROOMS RIGHT NOW."
			_set_state("empty", _with_hint(empty_text, mac_hint), action_text,
				_host_requested, UiPalette.YELLOW)
	else:
		_set_state("nomatch", "NO ROOMS MATCH \"%s\"." % _query, "CLEAR SEARCH",
			_clear_search, UiPalette.BLUE)
	MenuNav.refresh()


func _with_hint(text: String, hint: String) -> String:
	## Keep the Mac-only permission note out of Windows/Linux builds.
	if hint == "":
		return text
	return text + "\n" + hint


func _restore_row_focus() -> void:
	var vp: Viewport = get_viewport()
	var focused: Control = vp.gui_get_focus_owner() if vp != null else null
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
	var button := Button.new()
	button.set_meta("keep_align", true)
	button.custom_minimum_size = Vector2(0, 56)
	button.add_theme_stylebox_override("normal", _row_style(Color(0.095, 0.115, 0.235, 0.92), Color(0.28, 0.78, 0.96, 0.30)))
	button.add_theme_stylebox_override("hover", _row_style(Color(0.155, 0.195, 0.365, 0.98), UiPalette.CYAN))
	button.add_theme_stylebox_override("pressed", _row_style(Color(0.20, 0.24, 0.42, 1.0), UiPalette.YELLOW))
	button.add_theme_stylebox_override("disabled", _row_style(Color(0.07, 0.08, 0.16, 0.60), Color(1.0, 1.0, 1.0, 0.10)))
	button.disabled = not joinable
	UiKit.apply_focus_ring(button, 6)
	button.pressed.connect(_on_room_pressed.bind(room))

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 20.0
	row.offset_right = -20.0
	row.add_theme_constant_override("separation", UiKit.SPACING)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)

	var name_label := Label.new()
	name_label.text = _room_name(room)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", 19)
	name_label.add_theme_color_override("font_color", UiPalette.CREAM if joinable else UiPalette.TEXT_DIM)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_label)

	if _mode == "all":
		row.add_child(_row_badge("LAN" if is_lan else "ONLINE",
			UiPalette.CYAN if is_lan else UiPalette.YELLOW, 84))

	var players_label := Label.new()
	players_label.text = "%d / %d" % [players, MAX_PLAYERS]
	players_label.custom_minimum_size = Vector2(72, 0)
	players_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	players_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	players_label.add_theme_font_size_override("font_size", 16)
	players_label.add_theme_color_override("font_color", UiPalette.CYAN if joinable else UiPalette.TEXT_DIM)
	players_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(players_label)

	var ping: int = int(room.get("ping", 0))
	if ping > 0:
		var ping_label := Label.new()
		ping_label.text = "%d ms" % ping
		ping_label.custom_minimum_size = Vector2(64, 0)
		ping_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		ping_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ping_label.add_theme_font_size_override("font_size", 14)
		ping_label.add_theme_color_override("font_color", UiPalette.GRASS if ping < 80 else UiPalette.YELLOW)
		ping_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(ping_label)

	if not joinable:
		var badge_text: String = "FULL" if full else "IN GAME"
		row.add_child(_row_badge(badge_text, UiPalette.RED))

	return button


func _row_badge(text: String, color: Color, min_width: float = 88.0) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.custom_minimum_size = Vector2(min_width, 30)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = UiPalette.INK
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.skew = Vector2(0.20, 0.0)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	style.anti_aliasing = true
	badge.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", UiPalette.CREAM if color.get_luminance() < 0.36 else UiPalette.INK)
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
	_status.add_theme_font_size_override("font_size", 15)
	var color: Color = UiPalette.CYAN
	match kind:
		"error":
			color = UiPalette.RED
		"empty":
			color = UiPalette.TEXT_DIM
		"nomatch":
			color = UiPalette.YELLOW
		_:
			color = UiPalette.CYAN
	_status.add_theme_color_override("font_color", color)
	_action_callable = action
	if _action_button != null:
		_action_button.visible = action_text != ""
		_action_button.disabled = false
		_action_button.text = action_text
		_action_button.set("fill_color", action_color)
		_action_button.fit_text()
	if kind == "loading":
		_loading_dots = 0
		_status_timer = 0.0


func _style_scrollbar() -> void:
	if _list_scroll == null:
		return
	var bar: VScrollBar = _list_scroll.get_v_scroll_bar()
	if bar == null:
		return
	bar.custom_minimum_size.x = 12
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.05, 0.06, 0.14, 0.55)
	track.set_corner_radius_all(5)
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(UiPalette.CYAN, 0.72)
	grab.set_corner_radius_all(5)
	var grab_hover: StyleBoxFlat = grab.duplicate()
	grab_hover.bg_color = UiPalette.CYAN.lightened(0.14)
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("grabber", grab)
	bar.add_theme_stylebox_override("grabber_highlight", grab_hover)
	bar.add_theme_stylebox_override("grabber_pressed", grab_hover)


func _apply_soft_disabled(_button: Button) -> void:
	## Slanted CandyButton renders its own muted dark parallelogram when disabled.
	pass


func _row_style(bg: Color, border: Color = Color(0.28, 0.78, 0.96, 0.30)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	style.skew = Vector2(0.14, 0.0)
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = UiKit.SPACING_TIGHT
	style.content_margin_bottom = UiKit.SPACING_TIGHT
	style.shadow_color = Color(0.02, 0.02, 0.08, 0.45)
	style.shadow_size = 4
	style.shadow_offset = Vector2(2, 3)
	style.anti_aliasing = true
	return style


func _candy(text: String, color: Color, height: int, font_size: int) -> Button:
	return UiKit.tile(text, color, float(height), font_size)
