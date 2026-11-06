extends Control
## Vehicle picker shown after SANDBOX and from the multiplayer lobby / minigame
## screen. Cycles through the catalog with a live spinning 3D preview, a full
## stat sheet and a remembered choice.

const Catalog := preload("res://scripts/vehicles/vehicle_catalog.gd")
const VehicleVisual := preload("res://scripts/vehicles/vehicle_visual.gd")
const UiPalette := preload("res://scripts/ui/ui_palette.gd")

const DRIVE_SCENE: String = "res://scenes/dev/driving_test.tscn"
const BACK_SCENE: String = "res://scenes/ui/play_menu.tscn"

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
var _tag_label: Label


func _ready() -> void:
	CursorController.set_menu_mode(true)
	_back_button.pressed.connect(_on_back)
	_entries = Catalog.all()
	if _entries.is_empty():
		# Never leave the player on a dead screen.
		_name_label.text = "NO VEHICLES AVAILABLE"
		_index_label.text = ""
		_prev_button.disabled = true
		_next_button.disabled = true
		_drive_button.disabled = true
		_back_button.grab_focus()
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
	_drive_button.grab_focus()


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
	if _model_root != null:
		_model_root.rotation.y += delta * 0.55


func _build_stats() -> void:
	var body: VBoxContainer = $Center/Panel/Body
	_tag_label = Label.new()
	_tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tag_label.add_theme_font_size_override("font_size", 14)
	_tag_label.add_theme_color_override("font_color", UiPalette.BLUE_DARK)
	body.add_child(_tag_label)
	body.move_child(_tag_label, _index_label.get_index() + 1)

	_stats_grid = GridContainer.new()
	_stats_grid.columns = 4
	_stats_grid.add_theme_constant_override("h_separation", 18)
	_stats_grid.add_theme_constant_override("v_separation", 3)
	body.add_child(_stats_grid)
	body.move_child(_stats_grid, _tag_label.get_index() + 1)


func _show_current() -> void:
	if _holder != null:
		_holder.queue_free()
		_holder = null
	var entry: Dictionary = _entries[_current]
	_holder = VehicleVisual.build(entry)
	_model_root.add_child(_holder)
	_name_label.text = str(entry.get("name", ""))
	_index_label.text = "%d / %d" % [_current + 1, _entries.size()]
	_fill_stats(entry)


func _fill_stats(entry: Dictionary) -> void:
	var top_speed: float = float(entry.get("max_speed", 0.0)) * 3.6
	var mass: float = float(entry.get("mass", 0.0))
	var engine: float = float(entry.get("engine_power", 0.0))
	var accel: float = (engine * Catalog.REFERENCE_MASS / maxf(mass, 1.0)) \
		if engine > 0.0 else float(entry.get("push_accel", 0.0))
	var grip: float = float(entry.get("grip", 1.0))
	var steering: float = float(entry.get("steering", 1.0))
	var smoke: float = float(entry.get("smoke", 0.0))
	var skid: float = float(entry.get("skid_width", 0.0)) * 100.0
	var has_engine: bool = bool(entry.get("has_engine", true))
	_tag_label.text = "ENGINE  ·  IDLE + REV" if has_engine \
		else "NO ENGINE  ·  LEG POWER / WHEEL RATTLE"
	for child: Node in _stats_grid.get_children():
		_stats_grid.remove_child(child)
		child.queue_free()
	_add_stat("TOP SPEED", "%d KM/H" % int(round(top_speed)),
		"WEIGHT", ("%.2f T" % (mass / 1000.0)) if mass >= 1000.0 else "%d KG" % int(mass))
	_add_stat("ACCEL M/S²", "%.1f" % accel, "GRIP", "%d%%" % int(round(grip * 100.0)))
	_add_stat("STEERING", "%d%%" % int(round(steering * 100.0)),
		"SMOKE", "%d%%" % int(round(smoke * 100.0)))
	_add_stat("SKID WIDTH", "%.0f CM" % skid,
		"PUSH", "%d%%" % int(round(float(entry.get("push_scale", 1.0)) * 100.0)))


func _add_stat(label_a: String, value_a: String, label_b: String, value_b: String) -> void:
	for text: String in [label_a, value_a, label_b, value_b]:
		var label := Label.new()
		label.text = text
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color",
			UiPalette.BLUE_DARK if text == label_a or text == label_b else UiPalette.INK)
		_stats_grid.add_child(label)


func _step(direction: int) -> void:
	if _entries.is_empty():
		return
	_current = wrapi(_current + direction, 0, _entries.size())
	_show_current()


func _on_drive() -> void:
	var vehicle_id: String = str(_entries[_current].get("id", Catalog.DEFAULT_ID))
	GameSettings.set_selected_vehicle(vehicle_id)
	GameSettings.set_minigame_options(GameSettings.minigame_difficulty,
		GameSettings.minigame_rounds, vehicle_id)
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
