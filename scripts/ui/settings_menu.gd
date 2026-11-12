extends Control
## Settings overlay used by the main menu and the pause menu.
##
## One calm card, a left section rail and plain rows: label, control, gap. There
## are no separator rules, no bordered rows and no double borders. Grouping is
## carried by the 24 px block gap and the section heading, so the eye only has
## to read controls.
##
## Controls match the value being edited: a real slider for a continuous value,
## the shared ToggleSwitch for on/off and a strip of equal tiles for a small
## discrete choice. Every row stays one MenuNav focus stop.

signal closed

const UiAnim := preload("res://scripts/ui/ui_anim.gd")
const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const CANDY_BUTTON: String = "res://scripts/ui/candy_button.gd"
const FOCUS_SLIDER: String = "res://scripts/ui/focus_slider.gd"

const SECTIONS: Array[String] = ["AUDIO", "VIDEO", "GAMEPLAY", "ACCESSIBILITY", "UPDATES"]

var _body: VBoxContainer
var _content: VBoxContainer
var _nav_buttons: Array[Button] = []
var _pages: Array[VBoxContainer] = []
var _current_page: int = 0

var _master_slider: HSlider
var _music_slider: HSlider
var _sfx_slider: HSlider
var _camera_slider: HSlider
var _hud_slider: HSlider
var _deadzone_slider: HSlider
var _master_value: Label
var _music_value: Label
var _sfx_value: Label
var _camera_value: Label
var _hud_value: Label
var _deadzone_value: Label

var _fullscreen_toggle: ToggleSwitch
var _cursor_toggle: ToggleSwitch
var _boost_toggle: ToggleSwitch
var _drift_toggle: ToggleSwitch
var _reduce_motion_toggle: ToggleSwitch
var _show_fps_toggle: ToggleSwitch
var _quality_button: Button
var _difficulty_button: Button

var _check_button: Button
var _update_status: Label
var _offline_note: Label
var _desc_label: Label
var _refreshing: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("nav_scope")
	hide()
	_body = $Center/Panel/Body
	_build_ui()
	UpdateChecker.check_finished.connect(_on_check_finished)


func open() -> void:
	_refresh()
	show()
	visible = true
	_show_page(_current_page)
	if _desc_label != null:
		_desc_label.text = "Hover or focus a row to see what it changes."
	UiAnim.pop($Center/Panel)
	MenuNav.refresh()
	_check_button.disabled = false
	if UpdateChecker.status == "available":
		_update_status.text = "v%s available" % UpdateChecker.latest_version
	elif UpdateChecker.status == "up_to_date":
		_update_status.text = "Up to date (v%s)" % UpdateChecker.local_version()
	else:
		_update_status.text = ""


func close() -> void:
	hide()
	$Center/Panel.scale = Vector2.ONE
	$Center/Panel.modulate = Color.WHITE
	MenuNav.refresh()
	closed.emit()


func _build_ui() -> void:
	_body.add_theme_constant_override("separation", UiKit.SPACING)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", UiKit.SPACING)
	_body.add_child(header)
	var title := _label("SETTINGS", UiKit.TITLE_SIZE, UiPalette.INK)
	title.theme_type_variation = &"TitleLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title)
	var close_button := _candy_button("BACK", UiPalette.RED, 46, 18)
	close_button.custom_minimum_size = Vector2(128, 46)
	close_button.tooltip_text = "Close Settings and return. Escape does the same."
	close_button.pressed.connect(close)
	header.add_child(close_button)

	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", UiKit.SPACING_WIDE)
	_body.add_child(main)

	var nav := VBoxContainer.new()
	nav.custom_minimum_size = Vector2(196, 0)
	nav.add_theme_constant_override("separation", UiKit.SPACING_TIGHT)
	nav.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	main.add_child(nav)
	for index in SECTIONS.size():
		var button := _plain_button(SECTIONS[index], 18, 48)
		# The shared UiKit centres every button label. The section rail reads
		# better as a left-aligned list, so opt this one sizing rule out.
		button.set_meta("skip_kit", true)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.tooltip_text = "Show the %s settings." % SECTIONS[index].to_lower()
		button.pressed.connect(_show_page.bind(index))
		nav.add_child(button)
		_nav_buttons.append(button)
	# Enter on a freshly opened Settings panel lands on the section rail.
	nav.get_child(0).set_meta("nav_default", true)

	# One tinted block holds the page. No inner border: the panel behind it is
	# already the frame, and stacking two outlines read as a boxed-in screen.
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel",
		UiKit.flat_card(Color(1.0, 1.0, 1.0, 0.38)))
	main.add_child(card)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", UiKit.SPACING_WIDE)
	margin.add_theme_constant_override("margin_right", UiKit.SPACING_WIDE)
	margin.add_theme_constant_override("margin_top", UiKit.SPACING)
	margin.add_theme_constant_override("margin_bottom", UiKit.SPACING)
	card.add_child(margin)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", UiKit.SPACING)
	margin.add_child(_content)

	for _section: String in SECTIONS:
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", UiKit.SPACING)
		page.visible = false
		_content.add_child(page)
		_pages.append(page)

	_build_audio(_pages[0])
	_build_video(_pages[1])
	_build_gameplay(_pages[2])
	_build_accessibility(_pages[3])
	_build_updates(_pages[4])

	# One quiet help line for the whole card. Every row writes its explanation
	# here on hover or keyboard focus, so the panel stays fast to scan instead
	# of repeating a paragraph under all fourteen controls.
	_desc_label = UiKit.caption("")
	_desc_label.custom_minimum_size = Vector2(0, 34)
	_content.add_child(_desc_label)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", UiKit.SPACING)
	_body.add_child(footer)
	var reset := _candy_button("RESET DEFAULTS", UiPalette.BLUE, 46, 16)
	reset.custom_minimum_size = Vector2(220, 46)
	reset.tooltip_text = "Put every setting back to its original value."
	reset.pressed.connect(_on_reset_defaults)
	footer.add_child(reset)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var version := _label("v%s" % UpdateChecker.read_version_file(), 13, UiPalette.MUTED)
	version.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(version)


func _build_audio(page: VBoxContainer) -> void:
	var rows := _page_header(page, "AUDIO",
		"Balance the game against your own music and voice chat.")
	_master_slider = _slider_row(rows, "Master volume",
		"Overall loudness of the game. This scales music and effects together.",
		0, 100, 1, _on_master_changed)
	_master_value = _last_value
	_music_slider = _slider_row(rows, "Music",
		"Volume of the soundtrack only. Sound effects and voice chat stay as they are.",
		0, 100, 1, _on_music_changed)
	_music_value = _last_value
	_sfx_slider = _slider_row(rows, "Sound effects",
		"Engine, crashes, boosts and menu clicks. Lower it to hear chat or your own music.",
		0, 100, 1, _on_sfx_changed)
	_sfx_value = _last_value


func _build_video(page: VBoxContainer) -> void:
	var rows := _page_header(page, "VIDEO",
		"Resolution and comfort. The game keeps the UI at native size.")
	_fullscreen_toggle = _toggle_row(rows, "Fullscreen",
		"Fill the whole monitor instead of a window. The web build follows the browser tab.",
		_on_fullscreen_toggled)
	_cursor_toggle = _toggle_row(rows, "Custom cursor",
		"Draw the cartoon cursor on menus. Turn it off to use the system pointer.",
		_on_cursor_toggled)
	_camera_slider = _slider_row(rows, "Camera shake",
		"How much the camera kicks on landings, crashes and boosts. 0% is the calmest.",
		0, 150, 1, _on_camera_changed)
	_camera_value = _last_value
	_hud_slider = _slider_row(rows, "HUD scale",
		"Size of the in-race speed, boost and standings panels.",
		75, 150, 5, _on_hud_changed)
	_hud_value = _last_value
	_quality_button = _choice_row(rows, "Quality preset",
		"Automatic resolution and effect quality. Lower it for the web build or an older GPU.",
		GameSettings.QUALITY_NAMES, [0, 1, 2], GameSettings.quality_preset,
		_on_quality_changed)


func _build_gameplay(page: VBoxContainer) -> void:
	var rows := _page_header(page, "GAMEPLAY",
		"Driving assists that do not change the physics.")
	_boost_toggle = _toggle_row(rows, "Hold boost instead of toggle",
		"Hold the boost button to boost. Off: press once to start and once to stop.",
		_on_boost_toggled)
	_drift_toggle = _toggle_row(rows, "Hold drift instead of toggle",
		"Hold to drift. Off: tap once to latch the handbrake on and again to release.",
		_on_drift_toggled)
	_deadzone_slider = _slider_row(rows, "Stick deadzone",
		"How far the stick must move before the cart reacts. Raise it for a worn or drifty pad.",
		0, 40, 1, _on_deadzone_changed)
	_deadzone_value = _last_value
	_difficulty_button = _choice_row(rows, "Bot difficulty",
		"How hard the AI carts race in single-player events. Hosts set it in the room.",
		PackedStringArray(["EASY", "NORMAL", "HARD"]), [0, 1, 2],
		GameSettings.minigame_difficulty, _on_difficulty_changed)


func _build_accessibility(page: VBoxContainer) -> void:
	var rows := _page_header(page, "ACCESSIBILITY", "Less motion, clearer information.")
	_reduce_motion_toggle = _toggle_row(rows, "Reduce motion",
		"Damps camera roll, shake and FOV kicks without slowing the cart.",
		_on_reduce_motion_toggled)
	_show_fps_toggle = _toggle_row(rows, "Show FPS",
		"Draw a small frame-rate counter in the corner of the HUD.",
		_on_show_fps_toggled)


func _build_updates(page: VBoxContainer) -> void:
	var rows := _page_header(page, "UPDATES", "The game checks GitHub, then a trusted mirror.")
	_offline_note = _label("Offline - update check skipped.", 14, UiPalette.RED)
	_offline_note.visible = false
	rows.add_child(_offline_note)
	_check_button = _candy_button("CHECK FOR UPDATES", UiPalette.YELLOW, 48, 18)
	_check_button.custom_minimum_size = Vector2(280, 48)
	_check_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_check_button.tooltip_text = "Ask the update server whether a newer build exists."
	_check_button.pressed.connect(_on_check_updates)
	rows.add_child(_check_button)
	_update_status = _label("", 14, UiPalette.MUTED)
	rows.add_child(_update_status)


func _page_header(page: VBoxContainer, title_text: String,
		subtitle_text: String) -> VBoxContainer:
	## Heading plus one quiet line, then a tight group of rows. The 16 px page
	## gap separates the heading from the rows, and 8 px keeps the rows together.
	## No rule is drawn: spacing carries the grouping.
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)
	page.add_child(block)
	block.add_child(_label(title_text, 24, UiPalette.INK))
	var subtitle := _label(subtitle_text, UiKit.CAPTION_SIZE, UiPalette.MUTED)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	block.add_child(subtitle)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", UiKit.SPACING_TIGHT)
	page.add_child(rows)
	return rows


func _slider_row(page: VBoxContainer, label_text: String, description: String,
		min_value: float, max_value: float, step: float,
		callback: Callable) -> HSlider:
	## A real slider, one line: name on the left, track in the middle and the
	## current value on the right. Continuous values never become pills.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiKit.SPACING)
	row.custom_minimum_size = Vector2(0, 40)
	page.add_child(row)
	var label := _label(label_text, 18, UiPalette.INK)
	label.custom_minimum_size = Vector2(190, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var slider := HSlider.new()
	slider.set_script(load(FOCUS_SLIDER))
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(240, 26)
	slider.tooltip_text = description
	slider.value_changed.connect(callback)
	row.add_child(slider)
	_describe(slider, description)
	var value := _label("", 18, UiPalette.BODY_BLUE)
	value.custom_minimum_size = Vector2(56, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value)
	_last_value = value
	return slider


var _last_value: Label


func _toggle_row(page: VBoxContainer, label_text: String, description: String,
		callback: Callable) -> ToggleSwitch:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiKit.SPACING)
	row.custom_minimum_size = Vector2(0, 40)
	page.add_child(row)
	var label := _label(label_text, 18, UiPalette.INK)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var toggle := ToggleSwitch.new()
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_END
	toggle.tooltip_text = description
	toggle.toggled.connect(callback)
	row.add_child(toggle)
	_describe(toggle, description)
	return toggle


func _choice_row(page: VBoxContainer, label_text: String, description: String,
		labels: PackedStringArray, values: Array, current: int,
		callback: Callable) -> Button:
	## Two to four discrete values become equal tiles in one strip, not a
	## "&lt; VALUE &gt;" pill stretched across the row.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiKit.SPACING)
	row.custom_minimum_size = Vector2(0, 40)
	page.add_child(row)
	var label := _label(label_text, 18, UiPalette.INK)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var strip := UiKit.segmented(labels, values, current, 108.0, 42.0)
	strip.size_flags_horizontal = Control.SIZE_SHRINK_END
	strip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strip.tooltip_text = description
	strip.connect("option_changed", callback)
	row.add_child(strip)
	_describe(strip, description)
	return strip


func _describe(control: Control, description: String) -> void:
	## Hover and keyboard focus both explain the row in the shared help line.
	control.mouse_entered.connect(_show_description.bind(description))
	control.focus_entered.connect(_show_description.bind(description))


func _show_description(description: String) -> void:
	if _desc_label != null and is_instance_valid(_desc_label):
		_desc_label.text = description


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _plain_button(text: String, font_size: int, height: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, height)
	button.add_theme_font_size_override("font_size", font_size)
	_ink_text(button)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_stylebox_override("normal", _row_style(Color(0, 0, 0, 0)))
	button.add_theme_stylebox_override("hover", _row_style(Color(1, 1, 1, 0.55)))
	button.add_theme_stylebox_override("pressed", _row_style(UiPalette.YELLOW))
	UiKit.apply_focus_ring(button, UiKit.CORNER_RADIUS)
	return button


func _ink_text(button: Button) -> void:
	## The shared candy theme paints every button label white. Settings uses
	## flat ink labels instead, so override all interaction states explicitly.
	for key: String in ["font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color", "font_disabled_color"]:
		button.add_theme_color_override(key, UiPalette.INK)
	button.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0))
	button.add_theme_constant_override("outline_size", 0)


func _candy_button(text: String, color: Color, height: int, font_size: int) -> Button:
	var button := Button.new()
	button.set_script(load(CANDY_BUTTON))
	button.set("fill_color", color)
	button.text = text
	button.custom_minimum_size = Vector2(0, height)
	button.add_theme_font_size_override("font_size", font_size)
	return button


func _row_style(bg: Color) -> StyleBoxFlat:
	## Flat selection fill: no border and no rule, so the selected row reads by
	## colour alone. The focus ring is the only outline on this screen.
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(UiKit.CORNER_RADIUS)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.anti_aliasing = true
	return style


func _show_page(index: int) -> void:
	_current_page = clampi(index, 0, _pages.size() - 1)
	for i in _pages.size():
		_pages[i].visible = i == _current_page
		var selected: bool = i == _current_page
		var button := _nav_buttons[i]
		_ink_text(button)
		button.add_theme_stylebox_override("normal",
			_row_style(UiPalette.YELLOW if selected else Color(0, 0, 0, 0)))
		button.add_theme_stylebox_override("hover",
			_row_style(UiPalette.YELLOW if selected else Color(1, 1, 1, 0.55)))
	if _desc_label != null:
		_desc_label.text = "Hover or focus a row to see what it changes."
	# The visible page changed, so the focus map has to as well.
	MenuNav.refresh()


func _refresh() -> void:
	_refreshing = true
	_master_slider.value = GameSettings.master_volume * 100.0
	_music_slider.value = GameSettings.music_volume * 100.0
	_sfx_slider.value = GameSettings.sfx_volume * 100.0
	_camera_slider.value = GameSettings.camera_shake * 100.0
	_hud_slider.value = GameSettings.hud_scale * 100.0
	_deadzone_slider.value = GameSettings.stick_deadzone * 100.0
	_fullscreen_toggle.on = GameSettings.fullscreen
	_cursor_toggle.on = GameSettings.custom_cursor
	_boost_toggle.on = GameSettings.boost_toggle
	_drift_toggle.on = GameSettings.drift_toggle
	_reduce_motion_toggle.on = GameSettings.reduce_motion
	_show_fps_toggle.on = GameSettings.show_fps
	_quality_button.call("set_index", clampi(GameSettings.quality_preset, 0, 2))
	_difficulty_button.call("set_index", clampi(GameSettings.minigame_difficulty, 0, 2))
	_update_values()
	_refreshing = false


func _update_values() -> void:
	_master_value.text = "%d%%" % int(round(_master_slider.value))
	_music_value.text = "%d%%" % int(round(_music_slider.value))
	_sfx_value.text = "%d%%" % int(round(_sfx_slider.value))
	_camera_value.text = "%d%%" % int(round(_camera_slider.value))
	_hud_value.text = "%d%%" % int(round(_hud_slider.value))
	_deadzone_value.text = "%d%%" % int(round(_deadzone_slider.value))


func _on_master_changed(value: float) -> void:
	if not _refreshing:
		GameSettings.set_master_volume(value / 100.0)
		_update_values()


func _on_music_changed(value: float) -> void:
	if not _refreshing:
		GameSettings.set_music_volume(value / 100.0)
		_update_values()


func _on_sfx_changed(value: float) -> void:
	if not _refreshing:
		GameSettings.set_sfx_volume(value / 100.0)
		_update_values()


func _on_camera_changed(value: float) -> void:
	if not _refreshing:
		GameSettings.set_camera_shake(value / 100.0)
		_update_values()


func _on_hud_changed(value: float) -> void:
	if not _refreshing:
		GameSettings.set_hud_scale(value / 100.0)
		_update_values()


func _on_deadzone_changed(value: float) -> void:
	if not _refreshing:
		GameSettings.set_stick_deadzone(value / 100.0)
		_update_values()


func _on_fullscreen_toggled(pressed: bool) -> void:
	if not _refreshing:
		GameSettings.set_fullscreen(pressed)


func _on_cursor_toggled(pressed: bool) -> void:
	if not _refreshing:
		GameSettings.set_custom_cursor(pressed)
		CursorController.set_menu_mode(CursorController.is_menu_mode())


func _on_boost_toggled(pressed: bool) -> void:
	if not _refreshing:
		GameSettings.set_boost_toggle(pressed)


func _on_drift_toggled(pressed: bool) -> void:
	if not _refreshing:
		GameSettings.set_drift_toggle(pressed)


func _on_reduce_motion_toggled(pressed: bool) -> void:
	if not _refreshing:
		GameSettings.set_reduce_motion(pressed)


func _on_show_fps_toggled(pressed: bool) -> void:
	if not _refreshing:
		GameSettings.set_show_fps(pressed)


func _on_quality_changed(value: Variant) -> void:
	GameSettings.set_quality_preset(int(value))


func _on_difficulty_changed(value: Variant) -> void:
	GameSettings.set_ai_difficulty(int(value))


func _on_reset_defaults() -> void:
	GameSettings.reset_to_defaults()
	CursorController.set_menu_mode(CursorController.is_menu_mode())
	_refresh()


func _on_check_updates() -> void:
	if UpdateChecker.is_downloading():
		_update_status.text = "Update downloading..."
		return
	_check_button.disabled = true
	_update_status.text = "Checking for updates..."
	UpdateChecker.check_for_updates(true)
	get_tree().create_timer(8.0).timeout.connect(_re_enable_check)


func _re_enable_check() -> void:
	if is_instance_valid(_check_button):
		_check_button.disabled = false


func _on_check_finished(available: bool) -> void:
	if not visible:
		return
	_check_button.disabled = false
	if available:
		_update_status.text = "v%s available - open it from the main menu" % UpdateChecker.latest_version
	elif UpdateChecker.status == "up_to_date":
		_update_status.text = "Up to date (v%s)" % UpdateChecker.local_version()
	elif UpdateChecker.status == "offline":
		_update_status.text = "Offline - couldn't reach the update server"
	else:
		_update_status.text = "Check failed - try again later"


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
