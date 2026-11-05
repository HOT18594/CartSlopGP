extends Control
## Scrollable release history, built from CHANGELOG.md so it always matches
## the shipped version. Opened from the main menu.

signal closed

const CHANGELOG_PATH: String = "res://CHANGELOG.md"

@onready var _current_label: Label = %CurrentVersion
@onready var _text: RichTextLabel = %ChangelogText
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	hide()
	_back_button.pressed.connect(close)
	_current_label.text = "v" + UpdateChecker.read_version_file()
	# Only one focusable control: loop Tab back onto itself.
	_back_button.focus_next = _back_button.get_path_to(_back_button)
	_back_button.focus_previous = _back_button.get_path_to(_back_button)


func open() -> void:
	_text.text = _build_bbcode()
	if _text.get_line_count() > 0:
		_text.scroll_to_line(0)
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


func _build_bbcode() -> String:
	if not FileAccess.file_exists(CHANGELOG_PATH):
		return "[i]Changelog not bundled in this build.[/i]"
	var file: FileAccess = FileAccess.open(CHANGELOG_PATH, FileAccess.READ)
	if file == null:
		return "[i]Changelog could not be read.[/i]"
	var lines: PackedStringArray = file.get_as_text().split("\n")
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
