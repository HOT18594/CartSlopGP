extends Control
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## Paged release history built straight from CHANGELOG.md.
##
## The old panel packed two releases onto a fixed 430 px box with four-space
## indented bullets, so wrapped markdown lines dangled under each bullet and
## every new release added another page. This version:
##   * anchors the panel to the viewport (it grows with the window),
##   * paginates by a line budget instead of a release count, so one long
##     future release simply gets its own page instead of overflowing,
##   * joins markdown soft-wraps into single flush-left bullet paragraphs,
##   * keeps the text scrollable, so a page can hold a LOT more history.

signal closed

const CHANGELOG_PATH: String = "res://CHANGELOG.md"
const PAGE_LINE_BUDGET: int = 165 ## Rendered lines per page, not releases.

const INK: String = "#1e1b3a"
const BLUE: String = "#2a8fc4"
const CYAN: String = "#45b6f0"
const GOLD: String = "#b97900"
const MUTED: String = "#7284a6"

@onready var _current_label: Label = %CurrentVersion
@onready var _text: RichTextLabel = %ChangelogText
@onready var _prev_button: Button = %PrevButton
@onready var _next_button: Button = %NextButton
@onready var _back_button: Button = %BackButton
@onready var _page_label: Label = %PageLabel
@onready var _hint_label: Label = %Hint
@onready var _panel: PanelContainer = %Panel

var _pages: Array[Dictionary] = []
var _page_index: int = 0


func _ready() -> void:
	add_to_group("nav_scope")
	hide()
	_back_button.pressed.connect(close)
	_prev_button.pressed.connect(_turn_page.bind(-1))
	_next_button.pressed.connect(_turn_page.bind(1))
	_current_label.text = "v" + UpdateChecker.read_version_file()


func open() -> void:
	_pages = _split_pages(_parse_releases(_read_changelog()))
	_page_index = 0
	_show_page()
	show()
	UiAnim.pop(_panel)
	MenuNav.refresh()
	_back_button.grab_focus()


func close() -> void:
	hide()
	_panel.scale = Vector2.ONE
	_panel.modulate = Color.WHITE
	MenuNav.refresh()
	closed.emit()


func nav_horizontal(direction: int) -> bool:
	## MenuNav routes left/right here, so paging works from anywhere in the
	## panel instead of only when the PREV/NEXT buttons happen to have focus.
	_turn_page(direction)
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _read_changelog() -> String:
	if not FileAccess.file_exists(CHANGELOG_PATH):
		return ""
	var file: FileAccess = FileAccess.open(CHANGELOG_PATH, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


# --------------------------------------------------------------------------
# markdown -> structured blocks


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
		if version == "" or line.begins_with("#"):
			continue
		if line == "":
			blank = true
			continue
		if line.begins_with("- "):
			blocks.append({"type": "bullet", "text": line.substr(2)})
		elif line.begins_with("### "):
			blocks.append({"type": "sub", "text": line.substr(4)})
		elif not blank and not blocks.is_empty() \
				and (blocks.back()["type"] == "bullet" or blocks.back()["type"] == "text"):
			# Markdown soft-wrap. Fold it into the previous paragraph so the
			# rendered bullet is ONE flush-left line, with no orphan text and
			# no fake indentation.
			var last: Dictionary = blocks.back()
			last["text"] = str(last["text"]) + " " + line
		else:
			blocks.append({"type": "text", "text": line})
		blank = false
	if version != "":
		releases.append({"version": version, "date": date, "blocks": blocks})
	return releases


func _build_bbcode(release: Dictionary) -> String:
	var out: PackedStringArray = []
	out.append("[font_size=25][color=%s][b]v%s[/b][/color][/font_size]" % [
		INK, _escape(str(release.get("version", "")))])
	out.append("[font_size=14][color=%s]%s[/color][/font_size]" % [
		MUTED, _escape(str(release.get("date", "")))])
	for raw: Dictionary in release.get("blocks", []):
		match str(raw.get("type", "")):
			"sub":
				out.append("")
				out.append("[font_size=16][color=%s][b]%s[/b][/color][/font_size]" % [
					GOLD, _escape(str(raw.get("text", "")).to_upper())])
			"bullet":
				out.append("[font_size=15][color=%s]•[/color]  [color=%s]%s[/color][/font_size]" % [
					CYAN, INK, _inline(str(raw.get("text", "")))])
			"text":
				out.append("[font_size=15][color=%s][i]%s[/i][/color][/font_size]" % [
					BLUE, _inline(str(raw.get("text", "")))])
	out.append("")
	out.append("")
	return "\n".join(out)


func _split_pages(releases: Array[Dictionary]) -> Array[Dictionary]:
	if releases.is_empty():
		return []
	var pages: Array[Dictionary] = []
	var chunk: Array[Dictionary] = []
	var lines: int = 0
	for release: Dictionary in releases:
		var bbcode: String = _build_bbcode(release)
		var weight: int = bbcode.split("\n").size() + 1
		if not chunk.is_empty() and lines + weight > PAGE_LINE_BUDGET:
			pages.append(_make_page(chunk))
			chunk = []
			lines = 0
		chunk.append({"bbcode": bbcode, "version": str(release.get("version", ""))})
		lines += weight
	if not chunk.is_empty():
		pages.append(_make_page(chunk))
	return pages


func _make_page(chunk: Array[Dictionary]) -> Dictionary:
	var parts: PackedStringArray = []
	for entry: Dictionary in chunk:
		parts.append(str(entry.get("bbcode", "")))
	return {
		"bbcode": "\n".join(parts),
		"first": str(chunk.front().get("version", "")),
		"last": str(chunk.back().get("version", "")),
	}


func _show_page() -> void:
	if _pages.is_empty():
		_text.text = "[i]Changelog not bundled in this build.[/i]"
		_page_label.text = "NO RELEASES"
		_prev_button.disabled = true
		_next_button.disabled = true
		return
	_page_index = clampi(_page_index, 0, _pages.size() - 1)
	var page: Dictionary = _pages[_page_index]
	_text.text = str(page.get("bbcode", ""))
	_text.scroll_to_line(0)
	UiAnim.fade_in(_text, 0.18)
	var first: String = str(page.get("first", ""))
	var last: String = str(page.get("last", ""))
	var range_text: String = ("v%s  ->  v%s" % [first, last]) if first != last else "v%s" % first
	_page_label.text = "PAGE %d / %d     %s" % [_page_index + 1, _pages.size(), range_text]
	# A compact changelog can fit on one page. Do not show dead arrows or a
	# "use the arrows" hint when there is nowhere to turn.
	var multi_page: bool = _pages.size() > 1
	_prev_button.visible = multi_page
	_next_button.visible = multi_page
	_hint_label.text = "SCROLL THE PANEL FOR MORE  ·  LEFT / RIGHT ARROWS CHANGE PAGE" \
		if multi_page else ""
	_prev_button.disabled = _page_index <= 0
	_next_button.disabled = _page_index >= _pages.size() - 1
	MenuNav.refresh()


func _turn_page(direction: int) -> void:
	if _pages.is_empty():
		return
	var next_index: int = clampi(_page_index + direction, 0, _pages.size() - 1)
	if next_index == _page_index:
		return
	_page_index = next_index
	_show_page()


# --------------------------------------------------------------------------
# inline markdown


func _inline(text: String) -> String:
	var cleaned: String = _escape(text.replace("`", ""))
	# **bold** -> BBCode bold, applied AFTER escaping so our own tags survive.
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
	## RichTextLabel parses square brackets as BBCode tags. The engine's
	## bracket-escape tags are not reliable across versions, so plain
	## parentheses keep release notes like [HOST] readable everywhere.
	return text.replace("[", "(").replace("]", ")")
