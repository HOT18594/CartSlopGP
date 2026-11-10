extends Control
## Settings overlay used by the main menu and the pause menu.
##
## Modern, low-density layout: a left section rail, one calm content card and
## label/control rows. Every toggle is a switch with a separate ink label, so
## no control inherits the white candy-button text colour.

signal closed

const UiAnim := preload("res://scripts/ui/ui_anim.gd")
const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const CANDY_BUTTON: String = "res://scripts/ui/candy_button.gd"

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
	_body.add_theme_constant_override("separation", 0)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	_body.add_child(header)
	var title := _label("SETTINGS", 40, UiPalette.INK)
	title.theme_type_variation = &"TitleLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := _candy_button("BACK", UiPalette.RED, 46, 18)
	close_button.custom_minimum_size = Vector2(150, 46)
	close_button.pressed.connect(close)
	header.add_child(close_button)

	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 3)
	rule.color = Color(UiPalette.INK, 0.9)
	_body.add_child(rule)

	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 18)
	_body.add_child(main)

	var nav := VBoxContainer.new()
	nav.custom_minimum_size = Vector2(190, 0)
	nav.add_theme_constant_override("separation", 8)
	main.add_child(nav)
	for index in SECTIONS.size():
		var button := _plain_button(SECTIONS[index], 18, 46)
		# The shared UiKit centres every button label. The section rail reads
		# better as a left-aligned list, so opt this one control out.
		button.set_meta("skip_kit", true)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_show_page.bind(index))
		nav.add_child(button)
		_nav_buttons.append(button)

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _card_style())
	main.add_child(card)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	card.add_child(margin)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 10)
	margin.add_child(_content)

	for section in SECTIONS:
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 10)
		page.visible = false
		_content.add_child(page)
		_pages.append(page)

	_build_audio(_pages[0])
	_build_video(_pages[1])
	_build_gameplay(_pages[2])
	_build_accessibility(_pages[3])
	_build_updates(_pages[4])

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	_body.add_child(footer)
	var reset := _candy_button("RESET DEFAULTS", UiPalette.BLUE, 46, 16)
	reset.custom_minimum_size = Vector2(220, 46)
	reset.pressed.connect(_on_reset_defaults)
	footer.add_child(reset)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var version := _label("v%s" % UpdateChecker.read_version_file(), 13, UiPalette.MUTED)
	version.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(version)


func _build_audio(page: VBoxContainer) -> void:
	_page_header(page, "AUDIO", "Balance the game against your own music and voice chat.")
	_master_slider = _slider_row(page, "Master volume", 0, 100, 1, _on_master_changed)
	_master_value = _last_value
	_music_slider = _slider_row(page, "Music", 0, 100, 1, _on_music_changed)
	_music_value = _last_value
	_sfx_slider = _slider_row(page, "Sound effects", 0, 100, 1, _on_sfx_changed)
	_sfx_value = _last_value


func _build_video(page: VBoxContainer) -> void:
	_page_header(page, "VIDEO", "Resolution and comfort. The game keeps the UI at native size.")
	_fullscreen_toggle = _toggle_row(page, "Fullscreen", _on_fullscreen_toggled)
	_cursor_toggle = _toggle_row(page, "Custom cursor", _on_cursor_toggled)
	_camera_slider = _slider_row(page, "Camera shake", 0, 150, 1, _on_camera_changed)
	_camera_value = _last_value
	_hud_slider = _slider_row(page, "HUD scale", 75, 150, 5, _on_hud_changed)
	_hud_value = _last_value
	var quality := HBoxContainer.new()
	quality.add_theme_constant_override("separation", 14)
	page.add_child(quality)
	var quality_label := _label("Quality preset", 17, UiPalette.INK)
	quality_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quality.add_child(quality_label)
	_quality_button = _plain_button(_cycle_text(GameSettings.quality_name()), 17, 42)
	_quality_button.custom_minimum_size = Vector2(180, 42)
	_quality_button.add_theme_stylebox_override("normal",
		_flat_style(Color(1, 0.96, 0.89, 1.0), UiPalette.INK))
	_quality_button.add_theme_stylebox_override("hover",
		_flat_style(UiPalette.YELLOW, UiPalette.INK))
	_quality_button.pressed.connect(_on_quality_pressed)
	quality.add_child(_quality_button)


func _build_gameplay(page: VBoxContainer) -> void:
	_page_header(page, "GAMEPLAY", "Driving assists that do not change the physics.")
	_boost_toggle = _toggle_row(page, "Hold boost instead of toggle", _on_boost_toggled)
	_drift_toggle = _toggle_row(page, "Hold drift instead of toggle", _on_drift_toggled)
	_deadzone_slider = _slider_row(page, "Stick deadzone", 0, 40, 1, _on_deadzone_changed)
	_deadzone_value = _last_value
	var difficulty := HBoxContainer.new()
	difficulty.add_theme_constant_override("separation", 14)
	page.add_child(difficulty)
	var difficulty_label := _label("Bot difficulty", 17, UiPalette.INK)
	difficulty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	difficulty.add_child(difficulty_label)
	_difficulty_button = _plain_button(_cycle_text(GameSettings.ai_difficulty_name()), 17, 42)
	_difficulty_button.custom_minimum_size = Vector2(180, 42)
	_difficulty_button.add_theme_stylebox_override("normal",
		_flat_style(Color(1, 0.96, 0.89, 1.0), UiPalette.INK))
	_difficulty_button.add_theme_stylebox_override("hover",
		_flat_style(UiPalette.YELLOW, UiPalette.INK))
	_difficulty_button.pressed.connect(_on_difficulty_pressed)
	difficulty.add_child(_difficulty_button)


func _build_accessibility(page: VBoxContainer) -> void:
	_page_header(page, "ACCESSIBILITY", "Less motion, clearer information.")
	_reduce_motion_toggle = _toggle_row(page, "Reduce motion", _on_reduce_motion_toggled)
	_show_fps_toggle = _toggle_row(page, "Show FPS", _on_show_fps_toggled)


func _build_updates(page: VBoxContainer) -> void:
	_page_header(page, "UPDATES", "The game checks GitHub, then a trusted mirror.")
	_offline_note = _label("Offline - update check skipped.", 14, UiPalette.RED)
	_offline_note.visible = false
	page.add_child(_offline_note)
	_check_button = _candy_button("CHECK FOR UPDATES", UiPalette.YELLOW, 48, 18)
	_check_button.custom_minimum_size = Vector2(280, 48)
	_check_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_check_button.pressed.connect(_on_check_updates)
	page.add_child(_check_button)
	_update_status = _label("", 14, UiPalette.MUTED)
	page.add_child(_update_status)


func _page_header(page: VBoxContainer, title_text: String, subtitle_text: String) -> void:
	var title := _label(title_text, 26, UiPalette.INK)
	page.add_child(title)
	var subtitle := _label(subtitle_text, 14, UiPalette.MUTED)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(subtitle)
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 2)
	rule.color = Color(UiPalette.INK, 0.16)
	page.add_child(rule)


func _slider_row(page: VBoxContainer, label_text: String, min_value: float,
		max_value: float, step: float, callback: Callable) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	page.add_child(row)
	var label := _label(label_text, 17, UiPalette.INK)
	label.custom_minimum_size = Vector2(210, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(240, 36)
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(callback)
	row.add_child(slider)
	var value := _label("", 20, UiPalette.BODY_BLUE)
	value.custom_minimum_size = Vector2(64, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value)
	_last_value = value
	return slider


var _last_value: Label


func _toggle_row(page: VBoxContainer, label_text: String,
		callback: Callable) -> ToggleSwitch:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	page.add_child(row)
	var label := _label(label_text, 17, UiPalette.INK)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var toggle := ToggleSwitch.new()
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	toggle.toggled.connect(callback)
	row.add_child(toggle)
	return toggle


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
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("normal", _flat_style(Color(1, 1, 1, 0.0), Color(0, 0, 0, 0)))
	button.add_theme_stylebox_override("hover", _flat_style(Color(1, 0.96, 0.89, 0.75), UiPalette.INK))
	button.add_theme_stylebox_override("pressed", _flat_style(UiPalette.YELLOW, UiPalette.INK))
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


func _flat_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2 if border.a > 0.0 else 0)
	style.set_corner_radius_all(12)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.98, 0.93, 0.72)
	style.border_color = Color(UiPalette.INK, 0.22)
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	return style


func _show_page(index: int) -> void:
	_current_page = clampi(index, 0, _pages.size() - 1)
	for i in _pages.size():
		_pages[i].visible = i == _current_page
		var selected: bool = i == _current_page
		var button := _nav_buttons[i]
		_ink_text(button)
		button.add_theme_stylebox_override("normal",
			_flat_style(UiPalette.YELLOW if selected else Color(1, 1, 1, 0.0),
				UiPalette.INK if selected else Color(0, 0, 0, 0)))
		button.add_theme_stylebox_override("hover",
			_flat_style(UiPalette.YELLOW if selected else Color(1, 0.96, 0.89, 0.75),
				UiPalette.INK))


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
	_quality_button.text = _cycle_text(GameSettings.quality_name())
	_difficulty_button.text = _cycle_text(GameSettings.ai_difficulty_name())
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


func _on_quality_pressed() -> void:
	GameSettings.set_quality_preset((GameSettings.quality_preset + 1) % 3)
	_quality_button.text = _cycle_text(GameSettings.quality_name())


func _on_difficulty_pressed() -> void:
	GameSettings.set_ai_difficulty((GameSettings.minigame_difficulty + 1) % 3)
	_difficulty_button.text = _cycle_text(GameSettings.ai_difficulty_name())


func _cycle_text(value: String) -> String:
	return "<  %s  >" % value


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
