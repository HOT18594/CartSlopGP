extends Control
## Paged release history, built from CHANGELOG.md so it always matches the
## shipped version. Two releases per page keep long histories readable.

signal closed

const CHANGELOG_PATH: String = "res://CHANGELOG.md"
const RELEASES_PER_PAGE: int = 2

@onready var _current_label: Label = %CurrentVersion
@onready var _text: RichTextLabel = %ChangelogText
@onready var _back_button: Button = %BackButton

var _pages: Array[String] = []
var _page_index: int = 0
var _prev_button: Button
var _next_button: Button
var _page_label: Label


func _ready() -> void:
	hide()
	_back_button.pressed.connect(close)
	_current_label.text = "v" + UpdateChecker.read_version_file()
	_build_pager()


func _build_pager() -> void:
	var body: VBoxContainer = _back_button.get_parent() as VBoxContainer
	if body == null:
		return
	var pager := HBoxContainer.new()
	pager.name = "PageRow"
	pager.add_theme_constant_override("separation", 10)
	_prev_button = Button.new()
	_prev_button.text = "< PREV"
	_prev_button.custom_minimum_size = Vector2(120, 46)
	_prev_button.add_theme_font_size_override("font_size", 17)
	_prev_button.pressed.connect(_turn_page.bind(-1))
	pager.add_child(_prev_button)
	_page_label = Label.new()
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_label.add_theme_font_size_override("font_size", 16)
	_page_label.add_theme_color_override("font_color", Color("2a8fc4"))
	pager.add_child(_page_label)
	_next_button = Button.new()
	_next_button.text = "NEXT >"
	_next_button.custom_minimum_size = Vector2(120, 46)
	_next_button.add_theme_font_size_override("font_size", 17)
	_next_button.pressed.connect(_turn_page.bind(1))
	pager.add_child(_next_button)
	body.add_child(pager)
	body.move_child(pager, _back_button.get_index())
	# Keep the pager and BACK in a predictable Tab loop.
	_prev_button.focus_next = _prev_button.get_path_to(_next_button)
	_prev_button.focus_previous = _prev_button.get_path_to(_back_button)
	_next_button.focus_next = _next_button.get_path_to(_back_button)
	_next_button.focus_previous = _next_button.get_path_to(_prev_button)
	_back_button.focus_next = _back_button.get_path_to(_prev_button)
	_back_button.focus_previous = _back_button.get_path_to(_next_button)


func open() -> void:
	_pages = _split_pages(_read_changelog())
	_page_index = 0
	_show_page()
	show()
	_back_button.grab_focus()


func close() -> void:
	hide()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_turn_page(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_turn_page(1)
		get_viewport().set_input_as_handled()


func _read_changelog() -> String:
	if not FileAccess.file_exists(CHANGELOG_PATH):
		return ""
	var file: FileAccess = FileAccess.open(CHANGELOG_PATH, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func _split_pages(source: String) -> Array[String]:
	var lines: PackedStringArray = source.split("\n")
	var releases: Array[String] = []
	var current: PackedStringArray = []
	for raw: String in lines:
		var line: String = raw.strip_edges()
		if line.begins_with("## ["):
			if not current.is_empty():
				releases.append("\n".join(current))
			current = PackedStringArray([line])
		elif not current.is_empty():
			current.append(line)
	if not current.is_empty():
		releases.append("\n".join(current))
	if releases.is_empty():
		return [source]
	var pages: Array[String] = []
	var index: int = 0
	while index < releases.size():
		var chunk: PackedStringArray = []
		for offset in RELEASES_PER_PAGE:
			if index + offset < releases.size():
				chunk.append(releases[index + offset])
		pages.append("\n\n".join(chunk))
		index += RELEASES_PER_PAGE
	return pages


func _show_page() -> void:
	if _pages.is_empty():
		_text.text = "[i]Changelog not bundled in this build.[/i]"
		_page_label.text = ""
		_prev_button.disabled = true
		_next_button.disabled = true
		return
	_page_index = clampi(_page_index, 0, _pages.size() - 1)
	_text.text = _build_bbcode(_pages[_page_index])
	if _text.get_line_count() > 0:
		_text.scroll_to_line(0)
	_page_label.text = "PAGE %d / %d" % [_page_index + 1, _pages.size()]
	_prev_button.disabled = _page_index <= 0
	_next_button.disabled = _page_index >= _pages.size() - 1


func _turn_page(direction: int) -> void:
	if _pages.is_empty():
		return
	var next_index: int = clampi(_page_index + direction, 0, _pages.size() - 1)
	if next_index == _page_index:
		return
	_page_index = next_index
	_show_page()


func _build_bbcode(source: String) -> String:
	var lines: PackedStringArray = source.split("\n")
	var output: PackedStringArray = []
	for raw_line: String in lines:
		var line: String = raw_line.strip_edges()
		if line.begins_with("## ["):
			var heading: String = line.trim_prefix("## ").replace("[", "").replace("]", "")
			output.append("")
			output.append("[font_size=27][color=#1e1b3a][b]%s[/b][/color][/font_size]" % _escape(heading))
		elif line.begins_with("### "):
			output.append("[font_size=19][color=#2a8fc4][b]%s[/b][/color][/font_size]" % _escape(line.trim_prefix("### ")))
		elif line.begins_with("- "):
			output.append("    •  %s" % _inline(line.trim_prefix("- ")))
		elif line.begins_with("#"):
			continue
		elif line == "":
			output.append("")
		else:
			output.append(_inline(line))
	return "\n".join(output)


func _inline(text: String) -> String:
	var cleaned: String = text.replace("**", "").replace("`", "")
	var regex := RegEx.new()
	regex.compile("\\[([^\\]]+)\\]\\(([^)]+)\\)")
	cleaned = regex.sub(cleaned, "$1  ($2)", true)
	return _escape(cleaned)


func _escape(text: String) -> String:
	## RichTextLabel treats square brackets as BBCode tags.
	return text.replace("[", "[lb]").replace("]", "[rb]")
