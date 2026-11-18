extends Control
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## Garage vehicle picker: 3D turntable flanked by < / > arrows, Q/E + PageUp/
## PageDown + LB/RB cycling, 5 crisp arcade stat bars for Sandbox/Deliver, and
## live stat-point allocation + paint swatches for Racing.

const StatBar := preload("res://scripts/ui/stat_bar.gd")
const Catalog := preload("res://scripts/vehicles/vehicle_catalog.gd")
const VehicleVisual := preload("res://scripts/vehicles/vehicle_visual.gd")
const UiPalette := preload("res://scripts/ui/ui_palette.gd")

const DRIVE_SCENE: String = "res://scenes/sandbox/sandbox.tscn"
const BACK_SCENE: String = "res://scenes/ui/play_menu.tscn"

static var _racing_intent: int = -1


static func set_racing_intent(enabled: bool) -> void:
	_racing_intent = 1 if enabled else 0


var STATS: Array[Dictionary] = [
	{"key": "top_speed", "label": "TOP SPEED", "color": UiPalette.YELLOW},
	{"key": "accel", "label": "ACCEL", "color": UiPalette.RED},
	{"key": "steering", "label": "HANDLING", "color": UiPalette.CYAN},
	{"key": "grip", "label": "DRIFT GRIP", "color": UiPalette.GRASS},
	{"key": "weight", "label": "WEIGHT", "color": UiPalette.BLUE},
]

const RACING_STATS: Array[Dictionary] = [
	{"key": "top_speed", "label": "TOP SPEED"},
	{"key": "accel", "label": "ACCELERATION"},
	{"key": "grip", "label": "GRIP / HANDLING"},
	{"key": "weight", "label": "WEIGHT"},
]

const RACE_COLORS: Array[Dictionary] = [
	{"name": "YELLOW", "hex": "ffd22e"},
	{"name": "CREAM", "hex": "fff6e3"},
	{"name": "CYAN", "hex": "45b6f0"},
	{"name": "GREEN", "hex": "4cd964"},
	{"name": "PINK", "hex": "f26ca7"},
	{"name": "RED", "hex": "ff4d4d"},
	{"name": "ORANGE", "hex": "ff9f43"},
	{"name": "PURPLE", "hex": "a06cff"},
]

@onready var _panel: PanelContainer = $Center/Panel
@onready var _viewport_container: SubViewportContainer = %ViewportContainer
@onready var _model_root: Node3D = %ModelRoot
@onready var _camera: Camera3D = %PreviewCamera
@onready var _name_label: Label = %NameLabel
@onready var _index_label: Label = %IndexLabel
@onready var _prev_button: Button = %PrevButton
@onready var _next_button: Button = %NextButton
@onready var _drive_button: Button = %DriveButton
@onready var _back_button: Button = %BackButton

var _entries: Array[Dictionary] = []
var _current: int = 0
var _holder: Node3D = null
var _stats_list: VBoxContainer
var _stat_bars: Dictionary = {}
var _ranges: Dictionary = {}
var _time: float = 0.0
var _racing: bool = false
var _allocation: Dictionary = {}
var _alloc_points: Dictionary = {}
var _alloc_readouts: Dictionary = {}
var _alloc_minus: Dictionary = {}
var _alloc_plus: Dictionary = {}
var _color_buttons: Dictionary = {}


func _ready() -> void:
	CursorController.set_menu_mode(true)
	if GameSettings.vehicle_return_scene != "":
		_drive_button.text = "SAVE & RETURN"
		_back_button.text = "CANCEL"
	_drive_button.fit_text()
	_back_button.fit_text()
	_prev_button.tooltip_text = "Previous vehicle (Q / LB)"
	_next_button.tooltip_text = "Next vehicle (E / RB)"
	_name_label.clip_text = true
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_back_button.pressed.connect(_on_back)

	var intent: int = _racing_intent
	_racing_intent = -1
	if OS.get_environment("CART_VEHICLE_RACING") == "1":
		intent = 1
	_racing = GameSettings.racing_mode_active() if intent < 0 else intent == 1
	if _racing:
		_entries = Catalog.racing_all()
		_ranges = Catalog.racing_stat_ranges()
		_allocation = GameSettings.racing_allocation()
	else:
		_entries = Catalog.all()
		_ranges = Catalog.stat_ranges()
	if _entries.is_empty():
		_name_label.text = "NO VEHICLES AVAILABLE"
		_name_label.add_theme_font_size_override("font_size", 22)
		_index_label.text = ""
		_prev_button.disabled = true
		_next_button.disabled = true
		_drive_button.disabled = true
		var hint := UiKit.label("THE VEHICLE CATALOG RETURNED NO ENTRIES.",
			int(UiKit.CAPTION_SIZE), UiPalette.MUTED)
		hint.name = "EmptyState"
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		($Center/Panel/Body as VBoxContainer).add_child(hint)
		MenuNav.refresh()
		MenuNav.focus(_back_button)
		return
	if _racing:
		_build_racing_stats()
	else:
		_build_stats()
	var current_id: String = ""
	if _racing:
		current_id = GameSettings.racing_vehicle_id()
	elif GameSettings.vehicle_edit_minigame:
		current_id = GameSettings.minigame_vehicle
	else:
		current_id = GameSettings.selected_vehicle
	_current = _entry_index(current_id)
	if _racing:
		_viewport_container.custom_minimum_size = Vector2(440, 134)
		_camera.look_at_from_position(Vector3(2.8, 1.8, -3.8),
			Vector3(0.0, 0.45, 0.0), Vector3.UP)
	else:
		_viewport_container.custom_minimum_size = Vector2(440, 156)
		_camera.look_at_from_position(Vector3(2.4, 1.6, -3.3),
			Vector3(0.0, 0.55, 0.0), Vector3.UP)
	_light_preview()
	_prev_button.pressed.connect(_step.bind(-1))
	_next_button.pressed.connect(_step.bind(1))
	_drive_button.pressed.connect(_on_drive)
	resized.connect(_fit_panel)
	_show_current()
	call_deferred("_enter")
	if OS.get_environment("CART_UI_MEASURE") == "1":
		_report_layout.call_deferred()


func _fit_panel() -> void:
	if _panel == null:
		return
	var vp: Vector2 = size if size.y > 1.0 else get_viewport_rect().size
	if vp.y < 640.0 and _panel.size.y > 0.0:
		var scale_y: float = clampf((vp.y - 32.0) / maxf(_panel.size.y, 560.0), 0.72, 1.0)
		_panel.scale = Vector2.ONE * scale_y
		_panel.pivot_offset = _panel.size * 0.5
	else:
		_panel.scale = Vector2.ONE


func _report_layout() -> void:
	await UiKit.report_screen(self, "vehicle_select:racing" if _racing \
		else "vehicle_select:roster")
	var panel: Control = $Center/Panel
	var body: Control = $Center/Panel/Body
	print("UI_BLOCKS %s panel=%.0fx%.0f body=%.0fx%.0f fits720=%s"
		% ["vehicle_select", panel.size.x, panel.size.y, body.size.x, body.size.y,
		str(panel.size.y <= UiKit.SCREEN_HEIGHT - UiKit.SCREEN_MARGIN * 2.0)])


func _enter() -> void:
	_fit_panel()
	UiAnim.pop($Center/Panel)
	MenuNav.refresh()
	if _entries.is_empty():
		MenuNav.focus(_back_button)
	else:
		MenuNav.focus(_drive_button)


func _unhandled_input(event: InputEvent) -> void:
	if SceneLoader.is_busy():
		return
	if event.is_action_pressed("ui_cancel"):
		_on_back()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			if key.keycode == KEY_Q or key.keycode == KEY_PAGEUP:
				_step(-1)
				get_viewport().set_input_as_handled()
				return
			elif key.keycode == KEY_E or key.keycode == KEY_PAGEDOWN:
				_step(1)
				get_viewport().set_input_as_handled()
				return
	elif event is InputEventJoypadButton:
		var pad_btn := event as InputEventJoypadButton
		if pad_btn.pressed:
			if pad_btn.button_index == JOY_BUTTON_LEFT_SHOULDER:
				_step(-1)
				get_viewport().set_input_as_handled()
				return
			elif pad_btn.button_index == JOY_BUTTON_RIGHT_SHOULDER:
				_step(1)
				get_viewport().set_input_as_handled()
				return
	var direction: int = 0
	if event.is_action_pressed("ui_left"):
		direction = -1
	elif event.is_action_pressed("ui_right"):
		direction = 1
	if direction != 0 and nav_horizontal(direction):
		get_viewport().set_input_as_handled()


func nav_horizontal(direction: int) -> bool:
	_step(direction)
	return true


func _light_preview() -> void:
	var preview: Node = _camera.get_parent()
	if preview == null:
		return
	if preview.get_node_or_null("PreviewEnvironment") == null:
		var world := WorldEnvironment.new()
		world.name = "PreviewEnvironment"
		var env := Environment.new()
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.72, 0.80, 0.92)
		env.ambient_light_energy = 0.55
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		world.environment = env
		preview.add_child(world)
	if preview.get_node_or_null("PreviewFill") == null:
		var fill := DirectionalLight3D.new()
		fill.name = "PreviewFill"
		fill.rotation_degrees = Vector3(-28.0, -145.0, 0.0)
		fill.light_energy = 0.85
		fill.light_color = Color(0.86, 0.92, 1.0)
		fill.shadow_enabled = false
		preview.add_child(fill)
	var sun := preview.get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.light_energy = 1.05
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 12.0


func _process(delta: float) -> void:
	_time += delta
	if _model_root != null:
		_model_root.rotation.y += delta * 0.55
	if _holder != null:
		_holder.position.y = sin(_time * 1.7) * 0.018


func _build_stats() -> void:
	var body: VBoxContainer = $Center/Panel/Body
	_stats_list = VBoxContainer.new()
	_stats_list.name = "StatsList"
	_stats_list.add_theme_constant_override("separation", 6)
	body.add_child(_stats_list)
	body.move_child(_stats_list, _index_label.get_index() + 1)

	for stat: Dictionary in STATS:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 12)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var label := Label.new()
		label.text = str(stat["label"])
		label.custom_minimum_size = Vector2(124, 0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 15)
		label.add_theme_color_override("font_color", UiPalette.INK)
		cell.add_child(label)
		var bar := StatBar.new()
		bar.fill_color = stat["color"] as Color
		bar.bar_height = 16.0
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(bar)
		_stats_list.add_child(cell)
		_stat_bars[str(stat["key"])] = bar


func _build_racing_stats() -> void:
	var body: VBoxContainer = $Center/Panel/Body
	var rows := VBoxContainer.new()
	rows.name = "AllocationRows"
	rows.add_theme_constant_override("separation", 6)
	body.add_child(rows)
	body.move_child(rows, _index_label.get_index() + 1)

	for stat: Dictionary in RACING_STATS:
		var key: String = str(stat["key"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UiKit.SPACING_TIGHT)
		rows.add_child(row)

		var label := Label.new()
		label.text = str(stat["label"])
		label.custom_minimum_size = Vector2(120, 0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", UiPalette.INK)
		row.add_child(label)

		var minus := _stepper_button("−", "Take one point from " + label.text)
		minus.pressed.connect(_adjust_stat.bind(key, -1))
		row.add_child(minus)

		var points := Label.new()
		points.custom_minimum_size = Vector2(26, 0)
		points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		points.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		points.add_theme_font_size_override("font_size", 18)
		points.add_theme_color_override("font_color", UiPalette.INK)
		points.text = "0"
		row.add_child(points)

		var plus := _stepper_button("+", "Spend one point on " + label.text)
		plus.pressed.connect(_adjust_stat.bind(key, 1))
		row.add_child(plus)

		var readout := Label.new()
		readout.custom_minimum_size = Vector2(88, 0)
		readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		readout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		readout.add_theme_font_size_override("font_size", 14)
		readout.add_theme_color_override("font_color", UiPalette.BODY_BLUE)
		readout.text = ""
		row.add_child(readout)

		var bar := StatBar.new()
		bar.fill_color = UiPalette.YELLOW
		bar.bar_height = 15.0
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(bar)

		_alloc_points[key] = points
		_alloc_readouts[key] = readout
		_alloc_minus[key] = minus
		_alloc_plus[key] = plus
		_stat_bars[key] = bar

	var color_row := HBoxContainer.new()
	color_row.name = "ColorRow"
	color_row.alignment = BoxContainer.ALIGNMENT_CENTER
	color_row.add_theme_constant_override("separation", 8)
	body.add_child(color_row)
	body.move_child(color_row, rows.get_index() + 1)
	var color_caption := Label.new()
	color_caption.text = "PAINT"
	color_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	color_caption.add_theme_font_size_override("font_size", 14)
	color_caption.add_theme_color_override("font_color", UiPalette.INK)
	color_row.add_child(color_caption)
	for swatch: Dictionary in RACE_COLORS:
		var hex: String = str(swatch["hex"])
		var button := _color_swatch(hex, str(swatch["name"]))
		button.pressed.connect(_on_color_picked.bind(hex))
		color_row.add_child(button)
		_color_buttons[hex] = button
	_refresh_color_swatches()


func _stepper_button(glyph: String, tooltip: String) -> Button:
	var button := Button.new()
	button.text = glyph
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(38, 28)
	button.add_theme_font_size_override("font_size", 19)
	button.add_theme_color_override("font_color", UiPalette.INK)
	button.add_theme_color_override("font_hover_color", UiPalette.INK)
	button.add_theme_color_override("font_pressed_color", UiPalette.INK)
	button.add_theme_color_override("font_disabled_color", UiPalette.MUTED)
	button.add_theme_stylebox_override("normal", _stepper_style(UiPalette.YELLOW))
	button.add_theme_stylebox_override("hover",
		_stepper_style(UiPalette.YELLOW.lightened(0.14)))
	button.add_theme_stylebox_override("pressed",
		_stepper_style(UiPalette.YELLOW.darkened(0.10)))
	button.add_theme_stylebox_override("disabled",
		_stepper_style(Color("cfc9da")))
	return button


func _stepper_style(fill: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(12)
	style.set_border_width_all(3)
	style.border_color = UiPalette.INK
	style.content_margin_left = 0.0
	style.content_margin_right = 0.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	style.anti_aliasing = true
	return style


func _color_swatch(hex: String, color_name: String) -> Button:
	var button := Button.new()
	button.set_meta("skip_kit", true)
	button.custom_minimum_size = Vector2(36, 36)
	button.tooltip_text = "%s PAINT" % color_name
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(hex)
	normal.set_corner_radius_all(12)
	normal.set_border_width_all(3)
	normal.border_color = UiPalette.INK
	normal.anti_aliasing = true
	button.add_theme_stylebox_override("normal", normal)
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(hex).lightened(0.12)
	button.add_theme_stylebox_override("hover", hover)
	var pressed_style: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	pressed_style.bg_color = Color(hex).darkened(0.08)
	button.add_theme_stylebox_override("pressed", pressed_style)
	button.resized.connect(func() -> void:
		button.pivot_offset = button.size * 0.5)
	return button


func _refresh_color_swatches() -> void:
	var selected: String = GameSettings.player_tag_color
	for hex: String in _color_buttons:
		var button: Button = _color_buttons[hex]
		var chosen: bool = hex == selected
		for state: String in ["normal", "hover", "pressed"]:
			var style: StyleBoxFlat = button.get_theme_stylebox(state) as StyleBoxFlat
			if style == null:
				continue
			style.set_border_width_all(6 if chosen else 3)
			style.border_color = UiPalette.INK
		button.scale = Vector2.ONE * (1.10 if chosen else 1.0)


func _on_color_picked(hex: String) -> void:
	if Network.is_session_active():
		Network.set_local_tag_color(hex)
	else:
		GameSettings.set_player_tag_color(hex)
	_refresh_color_swatches()
	if _racing:
		_swap_model(false)


func _adjust_stat(key: String, direction: int) -> void:
	if not _racing or _entries.is_empty():
		return
	var points: int = int(_allocation.get(key, 0))
	var total: int = Catalog.allocation_total(_allocation)
	if direction > 0:
		if points >= Catalog.RACING_STAT_MAX or total >= Catalog.RACING_STAT_POINTS:
			return
	elif points <= 0:
		return
	_allocation[key] = points + direction
	_fill_racing_stats(_composed_current())
	_keep_focus(key)


func _keep_focus(key: String) -> void:
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused == null or not (focused is Button):
		return
	if not (focused as Button).disabled:
		return
	var used_minus: bool = focused == _alloc_minus.get(key)
	var sibling_map: Dictionary = _alloc_plus if used_minus else _alloc_minus
	var sibling: Button = sibling_map.get(key) as Button
	if sibling != null and not sibling.disabled:
		sibling.grab_focus()
	elif _drive_button != null and not _drive_button.disabled:
		_drive_button.grab_focus()


func _entry_index(id: String) -> int:
	for index in _entries.size():
		if str(_entries[index].get("id", "")) == id:
			return index
	return 0


func _composed_current() -> Dictionary:
	if _entries.is_empty():
		return {}
	var base: Dictionary = _entries[_current]
	if not _racing:
		return base
	return Catalog.compose_racing_entry(str(base.get("id", "")), _allocation,
		GameSettings.tag_color())


func _racing_value(key: String, value: float) -> String:
	match key:
		"top_speed":
			return "%d KM/H" % roundi(value)
		"accel":
			return "%.1f" % value
		"grip":
			return "%.2f" % value
		"weight":
			return "%d KG" % roundi(value)
	return "%.2f" % value


func _fill_racing_stats(entry: Dictionary) -> void:
	var total: int = Catalog.allocation_total(_allocation)
	var left: int = maxi(Catalog.RACING_STAT_POINTS - total, 0)
	_set_status("RACE TUNING  ·  %d / %d PTS LEFT" % [left,
		Catalog.RACING_STAT_POINTS])
	var values: Dictionary = Catalog.stats_for(entry)
	for stat: Dictionary in RACING_STATS:
		var key: String = str(stat["key"])
		var points: int = int(_allocation.get(key, 0))
		var points_label: Label = _alloc_points[key] as Label
		points_label.text = str(points)
		var readout: Label = _alloc_readouts[key] as Label
		readout.text = _racing_value(key, float(values.get(key, 0.0)))
		var bar: StatBar = _stat_bars[key] as StatBar
		bar.set_ratio(Catalog.stat_ratio(entry, key, _ranges) * 0.94 + 0.06)
		var minus: Button = _alloc_minus[key] as Button
		minus.disabled = points <= 0
		var plus: Button = _alloc_plus[key] as Button
		plus.disabled = points >= Catalog.RACING_STAT_MAX \
			or total >= Catalog.RACING_STAT_POINTS


func _show_current(animate: bool = true) -> void:
	var entry: Dictionary = _composed_current()
	_swap_model(animate)
	_name_label.text = str(entry.get("name", ""))
	UiAnim.fade_in(_name_label, 0.20)
	if _racing:
		_fill_racing_stats(entry)
	else:
		_fill_stats(entry)


func _swap_model(animate: bool) -> void:
	if _holder != null:
		_model_root.remove_child(_holder)
		_holder.queue_free()
		_holder = null
	_holder = VehicleVisual.build(_composed_current())
	_model_root.add_child(_holder)
	if animate:
		_holder.scale = Vector3.ONE * 0.86
		var tween: Tween = _holder.create_tween()
		tween.tween_property(_holder, "scale", Vector3.ONE, 0.32) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_holder.scale = Vector3.ONE


func _fill_stats(entry: Dictionary) -> void:
	var stats: Dictionary = Catalog.stats_for(entry)
	var weight_kg: int = maxi(roundi(float(stats.get("weight", entry.get("mass", 80.0)))), 1)
	var weight_class: String = "HEAVYWEIGHT"
	if weight_kg < 65:
		weight_class = "FEATHERWEIGHT"
	elif weight_kg < 115:
		weight_class = "LIGHTWEIGHT"
	elif weight_kg < 185:
		weight_class = "MIDDLEWEIGHT"
	_set_status("%s  ·  %d KG" % [weight_class, weight_kg])
	for key: String in _stat_bars:
		var bar: StatBar = _stat_bars[key]
		bar.set_ratio(Catalog.stat_ratio(entry, key, _ranges) * 0.94 + 0.06)


func _set_status(detail: String) -> void:
	_index_label.text = "%d / %d  ·  %s" % [_current + 1, _entries.size(), detail]


func _step(direction: int) -> void:
	if _entries.is_empty():
		return
	_current = wrapi(_current + direction, 0, _entries.size())
	_show_current()


func _on_drive() -> void:
	if _entries.is_empty():
		return
	var vehicle_id: String = str(_entries[_current].get("id", Catalog.DEFAULT_ID))
	if _racing:
		GameSettings.set_racing_vehicle(vehicle_id)
		GameSettings.set_racing_allocation(_allocation)
	elif GameSettings.vehicle_edit_minigame:
		GameSettings.set_minigame_options(GameSettings.minigame_difficulty,
			GameSettings.minigame_rounds, vehicle_id)
	else:
		GameSettings.set_selected_vehicle(vehicle_id)
	GameSettings.vehicle_edit_minigame = false
	if GameSettings.vehicle_return_scene != "":
		var scene: String = GameSettings.vehicle_return_scene
		var title: String = GameSettings.vehicle_return_title
		GameSettings.vehicle_return_scene = ""
		GameSettings.vehicle_return_title = ""
		SceneLoader.go_to(scene, title, "Vehicle saved")
		return
	SceneLoader.go_to(DRIVE_SCENE, "LET'S DRIVE", "Warming up the engine...")


func _on_back() -> void:
	GameSettings.vehicle_edit_minigame = false
	if GameSettings.vehicle_return_scene != "":
		var scene: String = GameSettings.vehicle_return_scene
		var title: String = GameSettings.vehicle_return_title
		GameSettings.vehicle_return_scene = ""
		GameSettings.vehicle_return_title = ""
		SceneLoader.go_to(scene, title)
		return
	SceneLoader.go_to(BACK_SCENE, "PLAY")
