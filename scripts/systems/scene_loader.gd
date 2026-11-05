extends CanvasLayer
## Global transition layer. Shows the themed loading screen while a scene is
## streamed in with ResourceLoader, then swaps to it. Autoload: SceneLoader.

const MIN_SHOW: float = 0.45 ## Never flash the overlay for less than this.
const POST_LOAD_PAUSE: float = 0.15 ## Beat between 100% and the scene swap.

@onready var _ui: Control = $UI
@onready var _title: Label = $UI/Title
@onready var _message: Label = $UI/Message
@onready var _percent: Label = $UI/Percent

var _busy: bool = false
var _task_mode: bool = false
var _path: String = ""


func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()


func is_busy() -> bool:
	return _busy


func begin_task(title: String, message: String = "") -> void:
	## Overlay without a scene load (e.g. hosting: UPnP + public IP).
	if _busy:
		return
	_busy = true
	_task_mode = true
	_title.text = title
	_message.text = message
	_percent.text = "..."
	_ui.set_indeterminate(true)
	_ui.set_progress(0.0)
	show()


func task_message(message: String) -> void:
	_message.text = message


func end_task() -> void:
	_task_mode = false
	_ui.set_indeterminate(false)
	hide()
	_busy = false


func go_to(path: String, title: String = "LOADING", message: String = "") -> void:
	if _busy:
		return
	_busy = true
	_path = path
	_title.text = title
	_message.text = message
	_percent.text = "0%"
	_ui.set_progress(0.0)
	show()

	var started: float = Time.get_ticks_msec() / 1000.0
	if not ResourceLoader.exists(path):
		get_tree().change_scene_to_file(path)
		_finish(started)
		return

	var error: Error = ResourceLoader.load_threaded_request(path, "", true)
	if error != OK:
		get_tree().change_scene_to_file(path)
		_finish(started)
		return
	_poll(started)


func _poll(started: float) -> void:
	var progress: Array = [0.0]
	while true:
		var status: int = ResourceLoader.load_threaded_get_status(_path, progress)
		_ui.set_progress(progress[0])
		_percent.text = "%d%%" % int(round(progress[0] * 100.0))
		await get_tree().process_frame
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			get_tree().change_scene_to_file(_path)
			_finish(started)
			return

	_ui.set_progress(1.0)
	_percent.text = "100%"
	var elapsed: float = Time.get_ticks_msec() / 1000.0 - started
	if elapsed < MIN_SHOW:
		await get_tree().create_timer(MIN_SHOW - elapsed).timeout
	await get_tree().create_timer(POST_LOAD_PAUSE).timeout
	var packed: PackedScene = ResourceLoader.load_threaded_get(_path)
	if packed != null:
		get_tree().change_scene_to_packed(packed)
	else:
		get_tree().change_scene_to_file(_path)
	await get_tree().process_frame
	_finish(started)


func _finish(started: float) -> void:
	var elapsed: float = Time.get_ticks_msec() / 1000.0 - started
	if elapsed < MIN_SHOW:
		await get_tree().create_timer(MIN_SHOW - elapsed).timeout
	hide()
	_ui.set_progress(0.0)
	_busy = false
