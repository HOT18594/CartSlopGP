extends Control
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## Room browser popup. Replaces the old inline room list that used to shove
## the whole lobby down the screen. BROWSE ONLINE ROOMS and FIND LAN ROOMS both
## open this; the search field filters the fetched list locally (no extra
## network calls), and picking a row hands the room back to the lobby.

signal room_selected(room: Dictionary)
signal closed

const CANDY_BUTTON: String = "res://scripts/ui/candy_button.gd"
const UiPalette := preload("res://scripts/ui/ui_palette.gd")

@onready var _panel: PanelContainer = %Panel
@onready var _title: Label = %Title
@onready var _close_button: Button = %CloseButton
@onready var _search_field: LineEdit = %SearchField
@onready var _refresh_button: Button = %RefreshButton
@onready var _list: VBoxContainer = %List
@onready var _status: Label = %StatusLabel

var _rooms: Array[Dictionary] = []
var _query: String = ""
var _mode: String = "online"
var _busy: bool = false


func _ready() -> void:
	add_to_group("nav_scope")
	hide()
	_close_button.pressed.connect(close)
	_refresh_button.pressed.connect(func() -> void: _refresh())
	_search_field.text_changed.connect(_on_search_changed)


func open(mode: String) -> void:
	_mode = "lan" if mode == "lan" else "online"
	_query = ""
	_search_field.text = ""
	_title.text = "LAN ROOMS" if _mode == "lan" else "ONLINE ROOMS"
	show()
	UiAnim.pop(_panel)
	MenuNav.refresh()
	_search_field.grab_focus()
	_refresh()


func close() -> void:
	if not visible:
		return
	hide()
	_panel.scale = Vector2.ONE
	_panel.modulate = Color.WHITE
	MenuNav.refresh()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _on_search_changed(text: String) -> void:
	_query = text.strip_edges().to_upper()
	_rebuild_list()


func _refresh() -> void:
	if _busy:
		return
	_busy = true
	_refresh_button.disabled = true
	_clear_list()
	_set_hint("LOOKING FOR ROOMS...")
	var result: Array = []
	if _mode == "lan":
		result = await Network.scan_lan_rooms()
	else:
		result = await Network.fetch_lobbies()
	if not is_inside_tree():
		return
	_busy = false
	_refresh_button.disabled = false
	_rooms.clear()
	for entry: Variant in result:
		if entry is Dictionary:
			_rooms.append(entry as Dictionary)
	_rebuild_list()
	MenuNav.refresh()


func set_rooms(rooms: Array) -> void:
	## Used by dev shots/tests to populate the list without a live server.
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
	var shown: int = 0
	for room: Dictionary in _rooms:
		if not _matches(room):
			continue
		shown += 1
		var button := _candy(_label(room), UiPalette.CYAN if _mode == "lan" else UiPalette.BLUE)
		button.disabled = _mode == "lan" and str(room.get("state", "lobby")) != "lobby"
		button.pressed.connect(_on_room_pressed.bind(room))
		_list.add_child(button)
	if _busy:
		return
	if shown == 0:
		_set_hint("NO MATCHING ROOMS" if not _rooms.is_empty() else "NO ROOMS RIGHT NOW")
	else:
		_set_hint("")
	MenuNav.refresh()


func _label(room: Dictionary) -> String:
	var name: String = str(room.get("name", "HOST")).to_upper()
	var players: int = int(room.get("players", 1))
	var tail: String = ""
	if _mode == "lan":
		tail = "IN GAME" if str(room.get("state", "lobby")) != "lobby" else "LOBBY"
	else:
		tail = str(room.get("room_code", "")).to_upper()
	return "%s   ·   %d PLAYER%s   ·   %s" % [name, players,
		"" if players == 1 else "S", tail]


func _matches(room: Dictionary) -> bool:
	var code: String = str(room.get("room_code", "")).to_upper()
	# Online rooms are joinable by 5-letter code only; drop malformed rows.
	if _mode == "online" and code.length() != 5:
		return false
	if _query == "":
		return true
	var haystack: String = str(room.get("name", "")).to_upper() + "  " + code
	return haystack.contains(_query)


func _on_room_pressed(room: Dictionary) -> void:
	room_selected.emit(room)
	close()


func _set_hint(text: String) -> void:
	_status.text = text


func _candy(text: String, color: Color) -> Button:
	var button := Button.new()
	button.set_script(load(CANDY_BUTTON))
	button.set("fill_color", color)
	button.set("corner_radius", 20)
	button.text = text
	button.custom_minimum_size = Vector2(0, 48)
	button.add_theme_font_size_override("font_size", 17)
	return button
