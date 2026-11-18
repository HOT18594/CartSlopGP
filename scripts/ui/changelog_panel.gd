extends Control
## Release history with one button per version and a separate detail view.

signal closed

const CHANGELOG_PATH: String = "res://CHANGELOG.md"
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
const UiPalette := preload("res://scripts/ui/ui_palette.gd")

const INK: String = "#1e1b3a"
const BLUE: String = "#2a8fc4"
const CYAN: String = "#45b6f0"
const GOLD: String = "#b97900"
const MUTED: String = "#7284a6"
const NOTE_INK: String = "#4b5c82"

const PANEL_MAX_WIDTH: float = 860.0
const PANEL_MAX_HEIGHT: float = 600.0
const PANEL_MARGIN_X: float = 64.0
const PANEL_MARGIN_Y: float = 56.0
const SCROLL_PAD_X: float = 20.0 ## 10 px left + 10 px right inside ScrollPad.
const PHOTO_WIDTH: int = 380
const PHOTO_HEIGHT: int = 214
const PHOTO_ROOT: String = "res://assets/ui/art/changelog_"

@onready var _current_label: Label = %CurrentVersion
@onready var _text: RichTextLabel = %ChangelogText
@onready var _back_button: Button = %BackButton
@onready var _all_versions_button: Button = %AllVersionsButton
@onready var _list_view: VBoxContainer = %ListView
@onready var _detail_view: VBoxContainer = %DetailView
@onready var _scroll: ScrollContainer = %Scroll
@onready var _version_list: GridContainer = %VersionList
@onready var _panel: PanelContainer = %Panel

var _releases: Array[Dictionary] = []
var _release_buttons: Array[Button] = []
var _selected_release: int = -1


func _ready() -> void:
	add_to_group("nav_scope")
	hide()
	_back_button.pressed.connect(close)
	_all_versions_button.pressed.connect(_show_list)
	_compact_button(_back_button, float(UiKit.SPACING), float(UiKit.SPACING_TIGHT))
	_compact_button(_all_versions_button, float(UiKit.SPACING), float(UiKit.SPACING_TIGHT))
	_back_button.fit_text()
	_all_versions_button.fit_text()
	_current_label.text = "CURRENT  v" + UpdateChecker.read_version_file()
	resized.connect(_fit_panel)
	_fit_panel()


func _fit_panel() -> void:
	var vp: Vector2 = get_viewport_rect().size
	if vp.x < 1.0 or vp.y < 1.0:
		return
	var w: float = minf(PANEL_MAX_WIDTH, maxf(320.0, vp.x - PANEL_MARGIN_X))
	var h: float = minf(PANEL_MAX_HEIGHT, maxf(320.0, vp.y - PANEL_MARGIN_Y))
	var cx: float = vp.x * 0.5
	var cy: float = vp.y * 0.5
	_panel.anchor_left = (cx - w * 0.5) / vp.x
	_panel.anchor_right = (cx + w * 0.5) / vp.x
	_panel.anchor_top = (cy - h * 0.5) / vp.y
	_panel.anchor_bottom = (cy + h * 0.5) / vp.y
	_panel.offset_left = 0.0
	_panel.offset_right = 0.0
	_panel.offset_top = 0.0
	_panel.offset_bottom = 0.0


func open() -> void:
	_releases = _parse_releases(_read_changelog())
	_selected_release = -1
	_fit_panel()
	_build_version_list()
	_show_list()
	_scroll_list_top()
	show()
	UiAnim.pop(_panel)
	MenuNav.refresh()
	_focus_list()


func request_close() -> void:
	close()


func _scroll_list_top() -> void:
	if _scroll != null:
		_scroll.scroll_vertical = 0


func _focus_list() -> void:
	if _releases.is_empty() or _release_buttons.is_empty():
		MenuNav.focus(_back_button)
		return
	var index: int = clampi(_selected_release, 0, _release_buttons.size() - 1)
	MenuNav.focus(_release_buttons[index])


func close() -> void:
	hide()
	_panel.scale = Vector2.ONE
	_panel.modulate = Color.WHITE
	MenuNav.refresh()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		if _detail_view.visible:
			_show_list()
		else:
			close()
		get_viewport().set_input_as_handled()


func _scrollbar_reserve() -> float:
	if _scroll == null:
		return 16.0
	var bar: VScrollBar = _scroll.get_v_scroll_bar()
	if bar == null:
		return 16.0
	return maxf(bar.get_combined_minimum_size().x, 14.0) + 4.0


func _build_version_list() -> void:
	for child: Node in _version_list.get_children():
		_version_list.remove_child(child)
		child.queue_free()
	_release_buttons.clear()
	var vp_w: float = get_viewport_rect().size.x
	var card_w: float = minf(PANEL_MAX_WIDTH, maxf(320.0, vp_w - PANEL_MARGIN_X))
	var inner_w: float = maxf(220.0,
		card_w - _panel_content_margin() * 2.0 - SCROLL_PAD_X - _scrollbar_reserve())
	var stacked: bool = inner_w < 580.0
	_version_list.columns = 1 if stacked else 2
	var button_w: float = inner_w if stacked else (inner_w - 16.0) * 0.5 - 2.0
	var tile_font: int = 15 if button_w >= 310.0 else 13
	for i in _releases.size():
		var release: Dictionary = _releases[i]
		var button := UiKit.tile("", UiPalette.BLUE if i % 2 == 0 else UiPalette.CYAN,
			50.0, tile_font)
		button.custom_minimum_size.x = maxf(150.0, button_w)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var date_text: String = str(release.get("date", "")).strip_edges()
		if date_text == "":
			date_text = "DATE UNKNOWN"
		button.text = "v%s  ·  %s" % [str(release.get("version", "")), date_text]
		button.pressed.connect(_show_release.bind(i))
		_version_list.add_child(button)
		_compact_button(button, float(UiKit.SPACING), float(UiKit.SPACING_TIGHT))
		button.fit_text(button_w)
		_release_buttons.append(button)
	if _releases.is_empty():
		var empty := Label.new()
		empty.text = "Changelog not bundled in this build."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		_version_list.add_child(empty)


func _panel_content_margin() -> float:
	var style: StyleBox = _panel.get_theme_stylebox("panel")
	if style == null:
		return 36.0
	return style.get_margin(SIDE_LEFT)


func _compact_button(button: Button, padding_x: float, padding_y: float) -> void:
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var box: StyleBox = button.get_theme_stylebox(state)
		if box == null:
			continue
		var flat: StyleBoxFlat = box.duplicate() as StyleBoxFlat
		if flat == null:
			continue
		flat.content_margin_left = padding_x
		flat.content_margin_right = padding_x
		flat.content_margin_top = padding_y
		flat.content_margin_bottom = padding_y
		button.add_theme_stylebox_override(state, flat)


func _show_list() -> void:
	_list_view.visible = true
	_detail_view.visible = false
	MenuNav.refresh()
	_focus_list()


func _show_release(index: int) -> void:
	if index < 0 or index >= _releases.size():
		return
	_selected_release = index
	_text.text = _build_bbcode(_releases[index])
	_list_view.visible = false
	_detail_view.visible = true
	_text.scroll_to_line(0)
	_text.get_v_scroll_bar().value = 0.0
	UiAnim.fade_in(_detail_view, 0.18)
	MenuNav.refresh()
	MenuNav.focus(_all_versions_button)


func _read_changelog() -> String:
	if not FileAccess.file_exists(CHANGELOG_PATH):
		return ""
	var file: FileAccess = FileAccess.open(CHANGELOG_PATH, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func _parse_releases(source: String) -> Array[Dictionary]:
	var releases: Array[Dictionary] = []
	var blocks: Array[Dictionary] = []
	var version: String = ""
	var date: String = ""
	var blank: bool = true
	for raw: String in source.split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("## ["):
			if version != "":
				releases.append({"version": version, "date": date, "blocks": blocks})
			var closing: int = line.find("]")
			version = line.substr(4, closing - 4) if closing > 4 else line.substr(4)
			date = line.substr(closing + 1).strip_edges().trim_prefix("-").strip_edges()
			blocks = []
			blank = true
			continue
		if line.begins_with("### "):
			blocks.append({"type": "sub", "text": line.substr(4)})
			blank = false
			continue
		if line.begins_with("![") and line.ends_with(")"):
			var split_at: int = line.find("](")
			if split_at > 2:
				var caption: String = line.substr(2, split_at - 2)
				var path: String = line.substr(split_at + 2,
					line.length() - split_at - 3)
				blocks.append({"type": "image", "text": caption, "path": path})
				blank = true
				continue
		if line.begins_with("> "):
			blocks.append({"type": "note", "text": line.substr(2)})
			blank = false
			continue
		if version == "" or line.begins_with("#"):
			continue
		if line == "":
			blank = true
			continue
		if line.begins_with("- "):
			blocks.append({"type": "bullet", "text": line.substr(2)})
		elif not blank and not blocks.is_empty() \
				and _joins_previous(blocks.back()):
			var last: Dictionary = blocks.back()
			last["text"] = str(last["text"]) + " " + line
		else:
			blocks.append({"type": "text", "text": line})
		blank = false
	if version != "":
		releases.append({"version": version, "date": date, "blocks": blocks})
	return releases


func _joins_previous(block: Dictionary) -> bool:
	match str(block.get("type", "")):
		"bullet", "text", "note":
			return true
	return false


func _build_bbcode(release: Dictionary) -> String:
	var out: PackedStringArray = []
	out.append("[font_size=28][color=%s][b]v%s[/b][/color][/font_size]" % [
		INK, _escape(str(release.get("version", "")))])
	out.append("[font_size=16][color=%s]%s[/color][/font_size]" % [
		MUTED, _escape(str(release.get("date", "")))])
	for raw: Dictionary in release.get("blocks", []):
		match str(raw.get("type", "")):
			"sub":
				out.append("")
				out.append("[font_size=18][color=%s][b]%s[/b][/color][/font_size]" % [
					GOLD, _escape(str(raw.get("text", "")).to_upper())])
			"bullet":
				out.append("[font_size=17][color=%s]•[/color]  [color=%s]%s[/color][/font_size]" % [
					CYAN, INK, _inline(str(raw.get("text", "")))])
			"text":
				out.append("[font_size=16][color=%s][i]%s[/i][/color][/font_size]" % [
					BLUE, _inline(str(raw.get("text", "")))])
			"note":
				out.append("[font_size=15][color=%s]%s[/color][/font_size]" % [
					NOTE_INK, _inline(str(raw.get("text", "")))])
			"image":
				_append_photo(out, str(raw.get("path", "")),
					str(raw.get("text", "")))
	out.append("")
	return "\n".join(out)


func _append_photo(out: PackedStringArray, path: String, caption: String) -> void:
	if not path.begins_with(PHOTO_ROOT) or not path.ends_with(".png"):
		return
	if not ResourceLoader.exists(path):
		return
	var vp_w: float = get_viewport_rect().size.x
	var card_w: float = minf(PANEL_MAX_WIDTH, maxf(320.0, vp_w - PANEL_MARGIN_X))
	var photo_w: int = int(maxf(180.0, minf(float(PHOTO_WIDTH), card_w - 104.0)))
	var photo_h: int = int(roundf(float(photo_w) * float(PHOTO_HEIGHT)
		/ float(PHOTO_WIDTH)))
	out.append("")
	out.append("[center][img=%dx%d]%s[/img][/center]" % [
		photo_w, photo_h, path])
	if caption != "":
		out.append("[center][font_size=13][color=%s][i]%s[/i][/color][/font_size][/center]" % [
			MUTED, _escape(caption)])
	out.append("")


func _inline(text: String) -> String:
	var cleaned: String = _escape(text.replace("`", ""))
	var parts: PackedStringArray = cleaned.split("**")
	if parts.size() == 1:
		return cleaned
	var out: String = ""
	for index in parts.size():
		out += parts[index]
		if index % 2 == 0 and index < parts.size() - 1:
			out += "[b]"
		elif index % 2 == 1:
			out += "[/b]"
	return out


func _escape(text: String) -> String:
	return text.replace("[", "(").replace("]", ")")
