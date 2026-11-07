extends CanvasLayer
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## Global transition layer. Shows the themed loading screen while a scene is
## streamed in with ResourceLoader, then swaps to it. Autoload: SceneLoader.
##
## The loading screen owns its own percentage and damped fill now. This layer
## only feeds it real progress values and animates the overlay in/out, so the
## number and the bar can never disagree.

const MIN_SHOW: float = 0.45 ## Never flash the overlay for less than this.
const POST_LOAD_PAUSE: float = 0.18 ## Beat between 100% and the scene swap.
const FADE_IN: float = 0.24
const FADE_OUT: float = 0.22

@onready var _ui: Control = $UI
@onready var _title: Label = $UI/Title
@onready var _message: Label = $UI/Message

var _busy: bool = false
var _task_mode: bool = false
var _path: String = ""
var _pending_path: String = ""
var _pending_title: String = ""
var _pending_message: String = ""


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
	# The previous scene's pause menu will be destroyed; never carry a frozen
	# pause flag into the next screen.
	get_tree().paused = false
	_busy = true
	_task_mode = true
	_title.text = title
	_message.text = message
	_ui.set_progress(0.0, true)
	_ui.set_indeterminate(true)
	_show_overlay()


func _show_overlay() -> void:
	_ui.modulate = Color(1, 1, 1, 0)
	show()
	UiAnim.fade_in(_ui, FADE_IN)


func task_message(message: String) -> void:
	_message.text = message


func end_task() -> void:
	# Only the operation that started a task may end it. Without this, BACK
	# during a scene load could clear another operation's overlay.
	if not _task_mode:
		return
	_task_mode = false
	_ui.set_indeterminate(false)
	hide()
	_ui.modulate = Color.WHITE
	_busy = false
	call_deferred("_run_pending")


func go_to(path: String, title: String = "LOADING", message: String = "") -> void:
	if _busy:
		# Never drop a navigation request. Network start messages are not
		# repeated, so queue the newest target instead of desyncing peers.
		_pending_path = path
		_pending_title = title
		_pending_message = message
		return
	get_tree().paused = false
	_busy = true
	_path = path
	_title.text = title
	_message.text = message
	_ui.set_indeterminate(false)
	_ui.set_progress(0.0, true)
	_show_overlay()

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
	var deadline: int = Time.get_ticks_msec() + 12000
	while true:
		var status: int = ResourceLoader.load_threaded_get_status(_path, progress)
		_ui.set_progress(progress[0])
		await get_tree().process_frame
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			get_tree().change_scene_to_file(_path)
			_finish(started)
			return
		if Time.get_ticks_msec() > deadline:
			# A threaded load can stall on some drivers/filesystems. Never
			# leave multiplayer peers stuck on "Syncing players..."
			push_warning("Threaded scene load timed out; falling back: " + _path)
			get_tree().change_scene_to_file(_path)
			_finish(started)
			return

	_ui.set_progress(1.0, true)
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
	# Fade the overlay away after the new scene is already underneath it.
	var tween: Tween = UiAnim.fade_out(_ui, FADE_OUT)
	if tween != null:
		await tween.finished
	hide()
	_ui.modulate = Color.WHITE
	_ui.set_progress(0.0, true)
	_busy = false
	call_deferred("_run_pending")


func _run_pending() -> void:
	if _pending_path == "" or _busy:
		return
	var next_path: String = _pending_path
	var next_title: String = _pending_title
	var next_message: String = _pending_message
	_pending_path = ""
	_pending_title = ""
	_pending_message = ""
	go_to(next_path, next_title, next_message)
