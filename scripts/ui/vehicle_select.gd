extends Control
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## Vehicle picker shown after SANDBOX and from the multiplayer lobby / minigame
## screen. Cycles through the catalog with a live spinning 3D preview and a
## garage-relative stat sheet.
##
## Stats no longer show raw numbers. Each row is a 10-block bar normalised
## against the whole catalog, so the sheet reads at a glance and stays aligned
## no matter which car is selected.

const StatBar := preload("res://scripts/ui/stat_bar.gd")
const Catalog := preload("res://scripts/vehicles/vehicle_catalog.gd")
const VehicleVisual := preload("res://scripts/vehicles/vehicle_visual.gd")
const UiPalette := preload("res://scripts/ui/ui_palette.gd")

const DRIVE_SCENE: String = "res://scenes/sandbox/sandbox.tscn"
const BACK_SCENE: String = "res://scenes/ui/play_menu.tscn"

var STATS: Array[Dictionary] = [
	{"key": "top_speed", "label": "TOP SPEED", "color": UiPalette.YELLOW},
	{"key": "weight", "label": "WEIGHT", "color": UiPalette.BLUE},
	{"key": "accel", "label": "ACCEL", "color": UiPalette.RED},
	{"key": "grip", "label": "GRIP", "color": UiPalette.GRASS},
	{"key": "steering", "label": "STEERING", "color": UiPalette.CYAN},
	{"key": "smoke", "label": "SMOKE", "color": UiPalette.PINK},
	{"key": "skid_width", "label": "SKID WIDTH", "color": UiPalette.BLUE_DARK},
	{"key": "push", "label": "PUSH", "color": UiPalette.YELLOW_DARK},
]

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
var _stats_grid: GridContainer
var _stat_bars: Dictionary = {}
var _tag_label: Label
var _ranges: Dictionary = {}
var _time: float = 0.0


func _ready() -> void:
	CursorController.set_menu_mode(true)
	# Copy matches what the button actually does. Opened from the lobby or the
	# map picker it saves and returns; opened from the main flow it starts a run.
	if GameSettings.vehicle_return_scene != "":
		_drive_button.text = "SAVE & RETURN"
	_back_button.pressed.connect(_on_back)
	_entries = Catalog.all()
	_ranges = Catalog.stat_ranges()
	if _entries.is_empty():
		# Never leave the player on a dead screen.
		_name_label.text = "NO VEHICLES AVAILABLE"
		_index_label.text = ""
		_prev_button.disabled = true
		_next_button.disabled = true
		_drive_button.disabled = true
		pass
		return
	_build_stats()
	var current_id: String = GameSettings.minigame_vehicle if GameSettings.vehicle_edit_minigame \
		else GameSettings.selected_vehicle
	_current = clampi(Catalog.index_of(current_id), 0, _entries.size() - 1)
	_camera.look_at_from_position(Vector3(2.4, 1.6, -3.3), Vector3(0.0, 0.55, 0.0), Vector3.UP)
	_light_preview()
	_prev_button.pressed.connect(_step.bind(-1))
	_next_button.pressed.connect(_step.bind(1))
	_drive_button.pressed.connect(_on_drive)
	_show_current()
	pass
	call_deferred("_enter")


func _enter() -> void:
	UiAnim.pop($Center/Panel)
	MenuNav.refresh()


func nav_horizontal(direction: int) -> bool:
	## Left/right arrows flip through the garage, not just the two arrow buttons.
	_step(direction)
	return true


func _light_preview() -> void:
	## The single sun left the camera-facing side of the car almost black.
	## Add a soft sky fill and a shadowless key from the camera side.
	var preview: Node = _camera.get_parent()
	if preview == null:
		return
	if preview.get_node_or_null("PreviewEnvironment") == null:
		var world := WorldEnvironment.new()
		world.name = "PreviewEnvironment"
		var env := Environment.new()
		# Keep the SubViewport transparent; only add ambient fill.
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
	_tag_label = Label.new()
	_tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tag_label.add_theme_font_size_override("font_size", 16)
	_tag_label.add_theme_color_override("font_color", UiPalette.BLUE_DARK)
	body.add_child(_tag_label)
	body.move_child(_tag_label, _index_label.get_index() + 1)

	var caption := Label.new()
	caption.text = ""
	caption.visible = false
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 14)
	caption.add_theme_color_override("font_color", UiPalette.BLUE_DARK)
	body.add_child(caption)
	body.move_child(caption, _tag_label.get_index() + 1)

	# Two aligned columns. Every cell has a fixed-width right-aligned label
	# and an equally wide bar, so all eight rows line up under the preview.
	_stats_grid = GridContainer.new()
	_stats_grid.columns = 2
	_stats_grid.add_theme_constant_override("h_separation", 22)
	_stats_grid.add_theme_constant_override("v_separation", 5)
	body.add_child(_stats_grid)
	body.move_child(_stats_grid, caption.get_index() + 1)
	# The action row needs its own lane; without this the focus ring of the
	# drive button touches the last stat row.
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.custom_minimum_size = Vector2(0, 14)
	body.add_child(spacer)
	body.move_child(spacer, _stats_grid.get_index() + 1)

	for stat: Dictionary in STATS:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 10)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var label := Label.new()
		label.text = str(stat["label"])
		label.custom_minimum_size = Vector2(112, 0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_color", UiPalette.INK)
		cell.add_child(label)
		var bar := StatBar.new()
		bar.fill_color = stat["color"] as Color
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(bar)
		_stats_grid.add_child(cell)
		_stat_bars[str(stat["key"])] = bar


func _show_current() -> void:
	if _holder != null:
		_holder.queue_free()
		_holder = null
	var entry: Dictionary = _entries[_current]
	_holder = VehicleVisual.build(entry)
	_model_root.add_child(_holder)
	_holder.scale = Vector3.ONE * 0.86
	var tween: Tween = _holder.create_tween()
	tween.tween_property(_holder, "scale", Vector3.ONE, 0.32) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_name_label.text = str(entry.get("name", ""))
	_index_label.text = "%d / %d" % [_current + 1, _entries.size()]
	UiAnim.fade_in(_name_label, 0.20)
	_fill_stats(entry)


func _fill_stats(entry: Dictionary) -> void:
	var has_engine: bool = bool(entry.get("has_engine", true))
	_tag_label.text = "ENGINE  ·  IDLE + REV" if has_engine \
		else "NO ENGINE  ·  LEG POWER / WHEEL RATTLE"
	for key: String in _stat_bars:
		var bar: StatBar = _stat_bars[key]
		bar.set_ratio(Catalog.stat_ratio(entry, key, _ranges) * 0.94 + 0.06)


func _step(direction: int) -> void:
	if _entries.is_empty():
		return
	_current = wrapi(_current + direction, 0, _entries.size())
	_show_current()


func _on_drive() -> void:
	var vehicle_id: String = str(_entries[_current].get("id", Catalog.DEFAULT_ID))
	# A minigame/lobby pick must not silently overwrite the player's Sandbox
	# car, and a Sandbox pick must not overwrite the race car.
	if GameSettings.vehicle_edit_minigame:
		GameSettings.set_minigame_options(GameSettings.minigame_difficulty,
			GameSettings.minigame_rounds, vehicle_id)
	else:
		GameSettings.set_selected_vehicle(vehicle_id)
	GameSettings.vehicle_edit_minigame = false
	if GameSettings.vehicle_return_scene != "":
		var scene: String = GameSettings.vehicle_return_scene
		var title: String = GameSettings.vehicle_return_title
		GameSettings.vehicle_return_scene = ""
		SceneLoader.go_to(scene, title, "Vehicle saved")
		return
	SceneLoader.go_to(DRIVE_SCENE, "LET'S DRIVE", "Warming up the engine...")


func _on_back() -> void:
	if GameSettings.vehicle_return_scene != "":
		var scene: String = GameSettings.vehicle_return_scene
		var title: String = GameSettings.vehicle_return_title
		GameSettings.vehicle_return_scene = ""
		SceneLoader.go_to(scene, title)
		return
	SceneLoader.go_to(BACK_SCENE, "PLAY")
