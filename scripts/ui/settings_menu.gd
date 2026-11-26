extends Control
## Settings overlay used by the main menu and the pause menu.
## Redesigned in the 0.8.5 Dark Telemetry Slanted Parallelogram UI style:
## - Skewed dark-glass modal shell with cyan inner rim
## - Left rail of 5 slanted parallelogram section tabs with true parallelogram focus halos
## - Recessed dark-glass control rows with high-contrast white labels & cyan telemetry readouts
## - Responsive sizing down to 960x540 with zero text clipping.

signal closed

const UiAnim := preload("res://scripts/ui/ui_anim.gd")
const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const SlantedShell := preload("res://scripts/ui/slanted_shell.gd")
const CANDY_BUTTON: String = "res://scripts/ui/candy_button.gd"
const FOCUS_SLIDER: String = "res://scripts/ui/focus_slider.gd"
const BODY_FONT: Font = preload("res://assets/ui/fonts/Fredoka-Bold.ttf")

const SECTIONS: Array[String] = ["AUDIO", "VIDEO", "GAMEPLAY", "ACCESSIBILITY", "UPDATES"]
const LABEL_COLUMN: float = 226.0
const VALUE_COLUMN: float = 62.0
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
var _pause_focus_toggle: ToggleSwitch
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


class _SlantedNavTab extends Button:
	## Slanted parallelogram section tab for the Settings left rail, with true
	## parallelogram focus outline, hover slide-right, and golden active plate.
	var label_text: String = ""
	var is_active_tab: bool = false
	var _hovered: bool = false
	var _held: bool = false
	var _hover_t: float = 0.0
	var _shine_t: float = 2.0

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		flat = true
		clip_contents = false
		set_meta("skip_kit", true)
		set_meta("custom_focus", true)
		set_meta("keep_align", true)
		var empty := StyleBoxEmpty.new()
		for st: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			add_theme_stylebox_override(st, empty)
		var clear := Color(0.0, 0.0, 0.0, 0.0)
		for ck: String in ["font_color", "font_hover_color", "font_focus_color",
				"font_pressed_color", "font_disabled_color"]:
			add_theme_color_override(ck, clear)
		mouse_entered.connect(func() -> void: _hovered = true; _shine_t = -0.35; queue_redraw())
		mouse_exited.connect(func() -> void: _hovered = false; queue_redraw())
		focus_entered.connect(func() -> void: _shine_t = -0.35; queue_redraw())
		focus_exited.connect(queue_redraw)
		button_down.connect(func() -> void: _held = true; queue_redraw())
		button_up.connect(func() -> void: _held = false; queue_redraw())

	func set_active_tab(on: bool) -> void:
		is_active_tab = on
		queue_redraw()

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		var hot: bool = (_hovered or has_focus() or is_active_tab) and not disabled
		var target: float = 1.0 if hot else 0.0
		_hover_t = UiAnim.damp(_hover_t, target, delta, 16.0)
		if _shine_t < 1.5:
			_shine_t += delta * 2.6
			queue_redraw()
		elif absf(_hover_t - target) > 0.004:
			queue_redraw()

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		if w < 24.0 or h < 18.0:
			return
		var focused: bool = has_focus() and not disabled
		var sk: float = 12.0
		var shift: float = _hover_t * 6.0
		var x0: float = 3.0 + shift
		var y0: float = 2.0 + (1.5 if _held else 0.0)
		var bw: float = maxf(w - sk - 14.0, 20.0)
		var bh: float = maxf(h - 6.0, 14.0)
		var pts := PackedVector2Array([
			Vector2(x0 + sk, y0),
			Vector2(x0 + sk + bw, y0),
			Vector2(x0 + bw, y0 + bh),
			Vector2(x0, y0 + bh),
		])
		var sh := PackedVector2Array([
			pts[0] + Vector2(3.0, 4.0), pts[1] + Vector2(3.0, 4.0),
			pts[2] + Vector2(3.0, 4.0), pts[3] + Vector2(3.0, 4.0),
		])
		draw_colored_polygon(sh, Color(0.02, 0.02, 0.08, 0.58))

		if focused:
			var halo := PackedVector2Array([
				Vector2(x0 + sk - 3.0, y0 - 2.5),
				Vector2(x0 + sk + bw + 3.0, y0 - 2.5),
				Vector2(x0 + bw + 3.0, y0 + bh + 2.5),
				Vector2(x0 - 3.0, y0 + bh + 2.5),
				Vector2(x0 + sk - 3.0, y0 - 2.5),
			])
			# Soft outward glow instead of one hard clipped polyline.
			var ring_col: Color = Color.WHITE if is_active_tab else UiPalette.YELLOW
			UiAnim.draw_soft_outline(self, halo, ring_col, 3.2, ring_col, 3, 2.0, 0.14)

		var fill: Color
		if is_active_tab:
			fill = UiPalette.YELLOW.lightened(0.06 if _hovered else 0.0)
		elif _hovered or focused:
			fill = UiPalette.SURFACE_CHIP
		else:
			fill = UiPalette.SURFACE_ROW
		draw_colored_polygon(pts, fill)

		var cl := pts.duplicate()
		cl.append(pts[0])
		draw_polyline(cl, UiPalette.OUTLINE, 3.2, true)

		var fsz: int = 17
		var ascent: float = BODY_FONT.get_ascent(fsz)
		var ty: float = y0 + (bh + ascent * 0.72) * 0.5
		var t_col: Color = UiPalette.INK if is_active_tab else UiPalette.TEXT
		draw_string(BODY_FONT, Vector2(x0 + sk + 12.0, ty), label_text,
			HORIZONTAL_ALIGNMENT_LEFT, bw - 18.0, fsz, t_col)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("nav_scope")
	hide()
	UiKit.apply_scrim(get_node_or_null("Dim") as ColorRect)
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
		clampf(vp.x - UiKit.MODAL_MARGIN, 800.0, 1040.0),
		clampf(vp.y - UiKit.MODAL_MARGIN, 480.0, 585.0))


func open() -> void:
	_fit_panel()
	_refresh()
	show()
	visible = true
	_show_page(_current_page)
	UiAnim.modal_open($Center/Panel, get_node_or_null("Dim"))
	UiAnim.stagger_slide(_nav_buttons, Vector2(-20.0, 0.0), 0.035, 0.20)
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
	_panel.add_theme_stylebox_override("panel", UiKit.modal_shell_style(38.0, 26.0))
	var bg: Control = SlantedShell.new()
	bg.name = "SlantedSettingsBackdrop"
	bg.set("skew_px", 22.0)
	bg.set("pad_x", 26.0)
	bg.set("pad_y", 20.0)
	_panel.add_child(bg)
	_panel.move_child(bg, 0)

	_body.add_theme_constant_override("separation", UiKit.SPACING_MED)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", UiKit.SPACING)
	_body.add_child(header)
	var title: Label = UiKit.page_title("SETTINGS", UiPalette.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title)
	var close_button: Button = UiKit.compact_button("BACK", UiPalette.RED)
	close_button.custom_minimum_size = Vector2(154, 48)
	close_button.pressed.connect(close)
	header.add_child(close_button)

	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", UiKit.SPACING)
	_body.add_child(main)

	var nav := VBoxContainer.new()
	nav.custom_minimum_size = Vector2(218, 0)
	nav.add_theme_constant_override("separation", UiKit.SPACING_TIGHT)
	nav.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	main.add_child(nav)
	for index in SECTIONS.size():
		var button := _SlantedNavTab.new()
		button.label_text = SECTIONS[index]
		button.text = SECTIONS[index]
		button.custom_minimum_size = Vector2(216, 48)
		button.pressed.connect(_show_page.bind(index))
		nav.add_child(button)
		_nav_buttons.append(button)
	nav.get_child(0).set_meta("nav_default", true)

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel",
		UiKit.slanted_card(UiPalette.SURFACE_GLASS,
			Color(UiPalette.CYAN, 0.22), 0.035, 2, 6, 0.0, 0.0))
	main.add_child(card)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", UiKit.SPACING_WIDE)
	margin.add_theme_constant_override("margin_right", UiKit.SPACING_WIDE)
	margin.add_theme_constant_override("margin_top", UiKit.SPACING)
	margin.add_theme_constant_override("margin_bottom", UiKit.SPACING)
	card.add_child(margin)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", UiKit.SPACING_MED)
	margin.add_child(_content)

	for _section: String in SECTIONS:
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", UiKit.SPACING_TIGHT)
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		page.visible = false
		_content.add_child(page)
		_pages.append(page)

	_build_audio(_pages[0])
	_build_video(_pages[1])
	_build_gameplay(_pages[2])
	_build_accessibility(_pages[3])
	_build_updates(_pages[4])

	_desc_label = _label(IDLE_HINT, UiKit.CAPTION_SIZE, UiPalette.TEXT_DIM)
	_desc_label.custom_minimum_size = Vector2(0, 26)
	_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_desc_label)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", UiKit.SPACING)
	_body.add_child(footer)
	var reset: Button = UiKit.compact_button("RESET DEFAULTS", UiPalette.BLUE)
	reset.custom_minimum_size = Vector2(246, 48)
	reset.pressed.connect(_on_reset_defaults)
	footer.add_child(reset)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var version := _label("v%s" % UpdateChecker.read_version_file(),
		UiKit.CAPTION_SIZE, UiPalette.YELLOW)
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
		_on_quality_changed, 108.0)


func _build_gameplay(page: VBoxContainer) -> void:
	_boost_mode_button = _choice_row(page, "Boost input",
		"HOLD: boost while button is held. TOGGLE: tap once to start, tap again to stop.",
		PackedStringArray(["HOLD", "TOGGLE"]), [false, true],
		1 if GameSettings.boost_toggle else 0, _on_boost_mode_changed, 102.0)
	_drift_mode_button = _choice_row(page, "Drift input",
		"HOLD: drift while button is held. TOGGLE: tap once to latch drift, tap again to release.",
		PackedStringArray(["HOLD", "TOGGLE"]), [false, true],
		1 if GameSettings.drift_toggle else 0, _on_drift_mode_changed, 102.0)
	_deadzone_slider = _slider_row(page, "deadzone", "Stick deadzone",
		"Minimum stick movement before steering reacts.",
		0, 40, 1, _on_deadzone_changed)
	_difficulty_button = _choice_row(page, "Bot difficulty",
		"AI pace in single-player races and arena matches.",
		PackedStringArray(["EASY", "NORMAL", "HARD"]), [0, 1, 2],
		GameSettings.minigame_difficulty, _on_difficulty_changed, 102.0)


func _build_accessibility(page: VBoxContainer) -> void:
	_reduce_motion_toggle = _toggle_row(page, "Reduce motion",
		"Damps camera roll, shake, FOV kicks, and HUD pulses.",
		_on_reduce_motion_toggled)
	_show_fps_toggle = _toggle_row(page, "Show FPS",
		"Displays a live frame-rate readout above the boost bar.",
		_on_show_fps_toggled)
	# Pause a solo game when the window/tab loses focus, so an Alt-Tab cannot
	# cost a race. Multiplayer never auto-pauses, so the label says solo.
	_pause_focus_toggle = _toggle_row(page, "Pause on focus loss",
		"Pauses a solo race when the game window loses focus. Multiplayer never pauses.",
		_on_pause_focus_toggled)


func _build_updates(page: VBoxContainer) -> void:
	page.alignment = BoxContainer.ALIGNMENT_CENTER
	_offline_note = _label("", 15, UiPalette.RED)
	_offline_note.visible = false
	page.add_child(_offline_note)
	_check_button = _candy_button("CHECK FOR UPDATES", UiPalette.YELLOW, 52, 18)
	_check_button.custom_minimum_size = Vector2(280, 52)
	_check_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_check_button.pressed.connect(_on_check_updates)
	_describe(_check_button, _check_button, "Check whether a newer release is available.")
	page.add_child(_check_button)
	_update_status = _label("", 16, UiPalette.TEXT_DIM)
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
	slider.custom_minimum_size = Vector2(200, 28)
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
		callback: Callable, tile_width: float = 104.0) -> Button:
	var row := _row(page)
	row.add_child(_row_label(label_text))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var strip := UiKit.segmented(labels, values, current, tile_width, 42.0)
	strip.size_flags_horizontal = Control.SIZE_SHRINK_END
	strip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strip.connect("option_changed", callback)
	row.add_child(strip)
	_describe(row, strip, description)
	return strip


func _row(page: VBoxContainer) -> HBoxContainer:
	var row_card := PanelContainer.new()
	var row_st: StyleBoxFlat = UiKit.row_style()
	row_st.content_margin_top = 6.0
	row_st.content_margin_bottom = 6.0
	row_card.add_theme_stylebox_override("panel", row_st)
	page.add_child(row_card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiKit.SPACING_MED)
	row.custom_minimum_size = Vector2(0, 38)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row_card.add_child(row)
	return row


func _row_label(text: String) -> Label:
	var label := _label(text, 18, UiPalette.TEXT)
	label.custom_minimum_size = Vector2(LABEL_COLUMN, 0)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _value_label(row: HBoxContainer) -> Label:
	var value := _label("", 18, UiPalette.CYAN)
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


func _candy_button(text: String, color: Color, height: int, font_size: int) -> Button:
	return UiKit.tile(text, color, float(height), font_size)


func _show_page(index: int) -> void:
	_current_page = clampi(index, 0, _pages.size() - 1)
	for i in _pages.size():
		_pages[i].visible = i == _current_page
		var selected: bool = i == _current_page
		var button := _nav_buttons[i]
		if button is _SlantedNavTab:
			(button as _SlantedNavTab).set_active_tab(selected)
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
	_pause_focus_toggle.on = GameSettings.pause_on_focus_loss
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


func _on_pause_focus_toggled(pressed: bool) -> void:
	if not _refreshing:
		GameSettings.set_pause_on_focus_loss(pressed)


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
		UiKit.consume_input(self)
		close()
