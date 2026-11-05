extends Control
## Vehicle picker shown after SANDBOX. Cycles through the catalog with a live
## spinning 3D preview and remembers the choice in GameSettings.

const Catalog := preload("res://scripts/vehicles/vehicle_catalog.gd")
const VehicleVisual := preload("res://scripts/vehicles/vehicle_visual.gd")

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


func _ready() -> void:
	CursorController.set_menu_mode(true)
	_entries = Catalog.all()
	if _entries.is_empty():
		return
	_current = clampi(Catalog.index_of(GameSettings.selected_vehicle), 0, _entries.size() - 1)
	_camera.look_at_from_position(Vector3(2.4, 1.6, -3.3), Vector3(0.0, 0.55, 0.0), Vector3.UP)
	_prev_button.pressed.connect(_step.bind(-1))
	_next_button.pressed.connect(_step.bind(1))
	_drive_button.pressed.connect(_on_drive)
	_back_button.pressed.connect(_on_back)
	_show_current()
	_drive_button.grab_focus()


func _process(delta: float) -> void:
	if _model_root != null:
		_model_root.rotation.y += delta * 0.55


func _step(direction: int) -> void:
	if _entries.is_empty():
		return
	_current = wrapi(_current + direction, 0, _entries.size())
	_show_current()


func _show_current() -> void:
	if _holder != null:
		_holder.queue_free()
		_holder = null
	var entry: Dictionary = _entries[_current]
	_holder = VehicleVisual.build(entry)
	_model_root.add_child(_holder)
	_name_label.text = str(entry.get("name", ""))
	_index_label.text = "%d / %d" % [_current + 1, _entries.size()]


func _on_drive() -> void:
	GameSettings.set_selected_vehicle(str(_entries[_current].get("id", Catalog.DEFAULT_ID)))
	SceneLoader.go_to(DRIVE_SCENE, "LET'S DRIVE", "Warming up the engine...")


func _on_back() -> void:
	SceneLoader.go_to(BACK_SCENE, "BACK", "")
