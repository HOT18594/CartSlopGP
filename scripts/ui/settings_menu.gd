extends Control
## Settings overlay used by the main menu and the pause menu.
## Streamlined layout: left section rail, clean control rows with no redundant
## headings or duplicate tooltip popups, and responsive sizing down to 960x540.

signal closed

const UiAnim := preload("res://scripts/ui/ui_anim.gd")
const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const CANDY_BUTTON: String = "res://scripts/ui/candy_button.gd"
const FOCUS_SLIDER: String = "res://scripts/ui/focus_slider.gd"

const SECTIONS: Array[String] = ["AUDIO", "VIDEO", "GAMEPLAY", "ACCESSIBILITY", "UPDATES"]
const LABEL_COLUMN: float = 210.0
const VALUE_COLUMN: float = 54.0
const IDLE_HINT: String = ""

var _panel: PanelContainer
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

var _fullscreen_toggle: ToggleSwitch
var _cursor_toggle: ToggleSwitch
var _reduce_motion_toggle: ToggleSwitch
var _show_fps_toggle: ToggleSwitch
var _boost_mode_button: Button
var _drift_mode_button: Button
var _quality_button: Button
var _difficulty_button: Button

var _check_button: Button
var _update_status: Label
var _offline_note: Label
var _desc_label: Label
var _refreshing: bool = false
var _value_labels: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("nav_scope")
	hide()
	_panel = $Center/Panel
	_body = $Center/Panel/Body
	_build_ui()
	resized.connect(_fit_panel)
	_fit_panel()
	UpdateChecker.check_finished.connect(_on_check_finished)


func _fit_panel() -> void:
	if _panel == null:
		return
	var vp: Vector2 = size if size.x > 1.0 else get_viewport_rect().size
	if vp.x < 1.0 or vp.y < 1.0:
		return
	_panel.custom_minimum_size = Vector2(
		clampf(vp.x - 48.0, 760.0, 1000.0),
		clampf(vp.y - 48.0, 460.0, 560.0))


func open() -> void:
	_fit_panel()
	_refresh()
	show()
	visible = true
	_show_page(_current_page)
	UiAnim.pop($Center/Panel)
	MenuNav.refresh()
	_check_button.disabled = false
	_offline_note.visible = false
	if UpdateChecker.status == "available":
		_update_status.text = "v%s available" % UpdateChecker.latest_version
	elif UpdateChecker.status == "up_to_date":
		_update_status.text = "Up to date (v%s)" % UpdateChecker.local_version()
	elif UpdateChecker.status == "offline":
		_update_status.text = "Offline — check connection"
	else:
		_update_status.text = ""


func close() -> void:
	hide()
	$Center/Panel.scale = Vector2.ONE
	$Center/Panel.modulate = Color.WHITE
	MenuNav.refresh()
	closed.emit()


func _build_ui() -> void:
	_body.add_theme_constant_override("separation", 12)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", UiKit.SPACING)
	_body.add_child(header)
	var title := _label("SETTINGS", 36, UiPalette.INK)
	title.theme_type_variation = &"TitleLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title)
	var close_button := _candy_button("BACK", UiPalette.RED, 44, 17)
	close_button.custom_minimum_size = Vector2(124, 44)
	close_button.pressed.connect(close)
	header.add_child(close_button)

	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", UiKit.SPACING)
	_body.add_child(main)

	var nav := VBoxContainer.new()
	nav.custom_minimum_size = Vector2(176, 0)
	nav.add_theme_constant_override("separation", 6)
	nav.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	main.add_child(nav)
	for index in SECTIONS.size():
		var button := _plain_button(SECTIONS[index], 17, 44)
		button.set_meta("skip_kit", true)
		button.set_meta("keep_align", true)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_show_page.bind(index))
		nav.add_child(button)
		_nav_buttons.append(button)
	nav.get_child(0).set_meta("nav_default", true)

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel",
		UiKit.flat_card(Color(1.0, 1.0, 1.0, 0.38)))
	main.add_child(card)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	card.add_child(margin)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 16)
	margin.add_child(_content)

	for _section: String in SECTIONS:
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 14)
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		page.visible = false
		_content.add_child(page)
		_pages.append(page)

	_build_audio(_pages[0])
	_build_video(_pages[1])
	_build_gameplay(_pages[2])
	_build_accessibility(_pages[3])
	_build_updates(_pages[4])

	_desc_label = UiKit.caption("")
	_desc_label.custom_minimum_size = Vector2(0, 26)
	_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc_label.text = IDLE_HINT
	_content.add_child(_desc_label)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", UiKit.SPACING)
	_body.add_child(footer)
	var reset := _candy_button("RESET DEFAULTS", UiPalette.BLUE, 44, 15)
	reset.custom_minimum_size = Vector2(210, 44)
	reset.pressed.connect(_on_reset_defaults)
	footer.add_child(reset)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var version := _label("v%s" % UpdateChecker.read_version_file(), 13, UiPalette.MUTED)
	version.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(version)


func _build_audio(page: VBoxContainer) -> void:
	_master_slider = _slider_row(page, "master", "Master volume",
		"Overall loudness of the game, scaling music and sound effects together.",
		0, 100, 1, _on_master_changed)
	_music_slider = _slider_row(page, "music", "Music",
		"Soundtrack volume only.",
		0, 100, 1, _on_music_changed)
	_sfx_slider = _slider_row(page, "sfx", "Sound effects",
		"Engine, drift, boost, crash, and menu sound effects.",
		0, 100, 1, _on_sfx_changed)


func _build_video(page: VBoxContainer) -> void:
	_fullscreen_toggle = _toggle_row(page, "Fullscreen",
		"Fill the whole monitor instead of running in a window.",
		_on_fullscreen_toggled)
	_cursor_toggle = _toggle_row(page, "Custom cursor",
		"Use the cartoon cursor on menus instead of the OS pointer.",
		_on_cursor_toggled)
	_camera_slider = _slider_row(page, "camera", "Camera shake",
		"Camera impact on landings, crashes, and boosts. 0% is calmest.",
		0, 150, 1, _on_camera_changed)
	_hud_slider = _slider_row(page, "hud", "HUD scale",
		"Size of the in-game speedometer, boost bar, race plaque, and standings.",
		75, 150, 5, _on_hud_changed)
	_quality_button = _choice_row(page, "Quality preset",
		"Rendering and visual effect detail.",
		GameSettings.QUALITY_NAMES, [0, 1, 2], GameSettings.quality_preset,
		_on_quality_changed, 104.0)


func _build_gameplay(page: VBoxContainer) -> void:
	_boost_mode_button = _choice_row(page, "Boost input",
		"HOLD: boost while button is held. TOGGLE: tap once to start, tap again to stop.",
		PackedStringArray(["HOLD", "TOGGLE"]), [false, true],
		1 if GameSettings.boost_toggle else 0, _on_boost_mode_changed, 96.0)
	_drift_mode_button = _choice_row(page, "Drift input",
		"HOLD: drift while button is held. TOGGLE: tap once to latch drift, tap again to release.",
		PackedStringArray(["HOLD", "TOGGLE"]), [false, true],
		1 if GameSettings.drift_toggle else 0, _on_drift_mode_changed, 96.0)
	_deadzone_slider = _slider_row(page, "deadzone", "Stick deadzone",
		"Minimum stick movement before steering reacts.",
		0, 40, 1, _on_deadzone_changed)
	_difficulty_button = _choice_row(page, "Bot difficulty",
		"AI pace in single-player races and arena matches.",
		PackedStringArray(["EASY", "NORMAL", "HARD"]), [0, 1, 2],
		GameSettings.minigame_difficulty, _on_difficulty_changed, 96.0)


func _build_accessibility(page: VBoxContainer) -> void:
	_reduce_motion_toggle = _toggle_row(page, "Reduce motion",
		"Damps camera roll, shake, FOV kicks, and HUD pulses.",
		_on_reduce_motion_toggled)
	_show_fps_toggle = _toggle_row(page, "Show FPS",
		"Displays a live frame-rate readout above the boost bar.",
		_on_show_fps_toggled)


func _build_updates(page: VBoxContainer) -> void:
	page.alignment = BoxContainer.ALIGNMENT_CENTER
	_offline_note = _label("", 14, UiPalette.RED)
	_offline_note.visible = false
	page.add_child(_offline_note)
	_check_button = _candy_button("CHECK FOR UPDATES", UiPalette.YELLOW, 48, 17)
	_check_button.custom_minimum_size = Vector2(260, 48)
	_check_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_check_button.pressed.connect(_on_check_updates)
	_describe(_check_button, _check_button, "Check whether a newer release is available.")
	page.add_child(_check_button)
	_update_status = _label("", 15, UiPalette.MUTED)
	_update_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(_update_status)


func _slider_row(page: VBoxContainer, key: String, label_text: String,
		description: String, min_value: float, max_value: float, step: float,
		callback: Callable) -> HSlider:
	var row := _row(page)
	row.add_child(_row_label(label_text))
	var slider := HSlider.new()
	slider.set_script(load(FOCUS_SLIDER))
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(200, 26)
	slider.value_changed.connect(callback)
	row.add_child(slider)
	_value_labels[key] = _value_label(row)
	_describe(row, slider, description)
	return slider


func _toggle_row(page: VBoxContainer, label_text: String,
		description: String, callback: Callable) -> ToggleSwitch:
	var row := _row(page)
	row.add_child(_row_label(label_text))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var toggle := ToggleSwitch.new()
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_END
	toggle.toggled.connect(callback)
	row.add_child(toggle)
	_describe(row, toggle, description)
	return toggle


func _choice_row(page: VBoxContainer, label_text: String, description: String,
		labels: PackedStringArray, values: Array, current: int,
		callback: Callable, tile_width: float = 100.0) -> Button:
	var row := _row(page)
	row.add_child(_row_label(label_text))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var strip := UiKit.segmented(labels, values, current, tile_width, 40.0)
	strip.size_flags_horizontal = Control.SIZE_SHRINK_END
	strip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strip.connect("option_changed", callback)
	row.add_child(strip)
	_describe(row, strip, description)
	return strip


func _row(page: VBoxContainer) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.custom_minimum_size = Vector2(0, 38)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	page.add_child(row)
	return row


func _row_label(text: String) -> Label:
	var label := _label(text, 17, UiPalette.INK)
	label.custom_minimum_size = Vector2(LABEL_COLUMN, 0)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _value_label(row: HBoxContainer) -> Label:
	var value := _label("", 17, UiPalette.BODY_BLUE)
	value.custom_minimum_size = Vector2(VALUE_COLUMN, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value)
	return value


func _describe(row: Control, control: Control, description: String) -> void:
	row.mouse_entered.connect(_show_description.bind(description))
	row.mouse_exited.connect(_clear_description)
	control.focus_entered.connect(_show_description.bind(description))
	control.focus_exited.connect(_clear_description)


func _show_description(description: String) -> void:
	if _desc_label != null and is_instance_valid(_desc_label):
		_desc_label.text = description


func _clear_description() -> void:
	if _desc_label != null and is_instance_valid(_desc_label):
		_desc_label.text = IDLE_HINT


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
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(UiKit.CORNER_RADIUS)
	style.content_margin_left = UiKit.SPACING
	style.content_margin_right = UiKit.SPACING
	style.content_margin_top = UiKit.SPACING_TIGHT
	style.content_margin_bottom = UiKit.SPACING_TIGHT
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
		_desc_label.text = IDLE_HINT
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
	_reduce_motion_toggle.on = GameSettings.reduce_motion
	_show_fps_toggle.on = GameSettings.show_fps
	_boost_mode_button.call("set_index", 1 if GameSettings.boost_toggle else 0)
	_drift_mode_button.call("set_index", 1 if GameSettings.drift_toggle else 0)
	_quality_button.call("set_index", clampi(GameSettings.quality_preset, 0, 2))
	_difficulty_button.call("set_index", clampi(GameSettings.minigame_difficulty, 0, 2))
	_update_values()
	_refreshing = false


func _update_values() -> void:
	for key: String in _value_labels:
		var label := _value_labels[key] as Label
		if label != null:
			label.text = "%d%%" % int(round(_slider_for(key).value))


func _slider_for(key: String) -> HSlider:
	match key:
		"master":
			return _master_slider
		"music":
			return _music_slider
		"sfx":
			return _sfx_slider
		"camera":
			return _camera_slider
		"hud":
			return _hud_slider
	return _deadzone_slider


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


func _on_boost_mode_changed(value: Variant) -> void:
	if not _refreshing:
		GameSettings.set_boost_toggle(bool(value))


func _on_drift_mode_changed(value: Variant) -> void:
	if not _refreshing:
		GameSettings.set_drift_toggle(bool(value))


func _on_reduce_motion_toggled(pressed: bool) -> void:
	if not _refreshing:
		GameSettings.set_reduce_motion(pressed)


func _on_show_fps_toggled(pressed: bool) -> void:
	if not _refreshing:
		GameSettings.set_show_fps(pressed)


func _on_quality_changed(value: Variant) -> void:
	if not _refreshing:
		GameSettings.set_quality_preset(int(value))


func _on_difficulty_changed(value: Variant) -> void:
	if not _refreshing:
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
	_offline_note.visible = false
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
	_offline_note.visible = false
	if available:
		_update_status.text = "v%s available" % UpdateChecker.latest_version
	elif UpdateChecker.status == "up_to_date":
		_update_status.text = "Up to date (v%s)" % UpdateChecker.local_version()
	elif UpdateChecker.status == "offline":
		_update_status.text = "Offline — check connection"
	else:
		_update_status.text = "Check failed"


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
