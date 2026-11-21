extends CanvasLayer
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## Global transition layer. Heavy 3D scenes stream with the themed loading
## screen; cheap menu scenes swap directly with no overlay. Autoload: SceneLoader.
##
## The loading screen owns its own percentage and damped fill now. This layer
## only feeds it real progress values and animates the overlay in/out, so the
## number and the bar can never disagree.

const MIN_SHOW: float = 0.25 ## Never flash the overlay for less than this.
const POST_LOAD_PAUSE: float = 0.10 ## Beat between 100% and the scene swap.
const FADE_IN: float = 0.24
const FADE_OUT: float = 0.18
## A task overlay is opened by a caller (hosting, LAN discovery, ...). If that
## caller returns early on a stale ticket and forgets end_task(), the game must
## not sit on a frozen overlay forever. Any task_message refreshes the clock.
const TASK_TIMEOUT_MS: int = 25000

## Only scenes that actually spend time building a 3D world get the overlay.
## Headless timings on the target machine: menus load in 0.05-0.5 s (the
## overlay's own minimum show + fade is ~0.43 s, so it made short hops slower),
## while Meadow Loop takes ~3.7 s and the sandbox/driving scene ~0.5 s.
const OVERLAY_SCENES: PackedStringArray = [
	"res://scenes/minigames/grass_race.tscn",
	"res://scenes/minigames/cargo_rush.tscn",
	"res://scenes/minigames/knockout.tscn",
	"res://scenes/minigames/bomb_tag.tscn",
	"res://scenes/minigames/meadow_lobby.tscn",
	"res://scenes/sandbox/sandbox.tscn",
]
## Every scene the loader may swap in. The loader is the only route between
## screens, so this is the one place that can refuse an arbitrary resource path:
## a typo or a smuggled path must fail loudly instead of blanking the game.
## A new screen has to be listed here before go_to() will accept it.
const ALLOWED_SCENES: PackedStringArray = [
	"res://scenes/ui/main_menu.tscn",
	"res://scenes/ui/play_menu.tscn",
	"res://scenes/ui/lobby_menu.tscn",
	"res://scenes/ui/minigames_menu.tscn",
	"res://scenes/ui/vehicle_select.tscn",
	"res://scenes/ui/room_browser.tscn",
	"res://scenes/sandbox/sandbox.tscn",
	"res://scenes/minigames/grass_race.tscn",
	"res://scenes/minigames/cargo_rush.tscn",
	"res://scenes/minigames/knockout.tscn",
	"res://scenes/minigames/bomb_tag.tscn",
	"res://scenes/minigames/meadow_lobby.tscn",
]

@onready var _ui: Control = $UI
@onready var _title: Label = $UI/Title
@onready var _message: Label = $UI/Message

var _busy: bool = false
var _task_mode: bool = false
var _task_deadline_ms: int = 0
var _path: String = ""
var _pending_path: String = ""
var _pending_title: String = ""
var _pending_message: String = ""


func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()


func _process(_delta: float) -> void:
	# Safety net for the task-mode overlay. _task_deadline_ms is refreshed by
	# task_message, so a live, progressing operation is never cut short.
	if _task_mode and _task_deadline_ms != 0 \
			and Time.get_ticks_msec() > _task_deadline_ms:
		push_warning("SceneLoader: task overlay timed out; releasing it")
		end_task()


func is_busy() -> bool:
	return _busy


func current_scene_path() -> String:
	## The path of the live scene, or "" while the tree has no scene. Used to
	## recognise a navigation request that is already satisfied.
	var tree: SceneTree = get_tree()
	if tree == null or tree.current_scene == null:
		return ""
	return tree.current_scene.scene_file_path


func begin_task(title: String, message: String = "") -> void:
	## Overlay without a scene load (e.g. hosting: UPnP + public IP).
	if _busy:
		return
	# The previous scene's pause menu will be destroyed; never carry a frozen
	# pause flag into the next screen.
	get_tree().paused = false
	_busy = true
	_task_mode = true
	_task_deadline_ms = Time.get_ticks_msec() + TASK_TIMEOUT_MS
	_title.text = title
	_message.text = message
	_ui.set_progress(0.0, true)
	_ui.set_indeterminate(true)
	if _ui.has_method("set_task"):
		_ui.call("set_task", true, title, message)
	_show_overlay()


func _show_overlay() -> void:
	if _ui.has_method("randomize_art"):
		_ui.call("randomize_art")
	_ui.modulate = Color(1, 1, 1, 0)
	show()
	UiAnim.fade_in(_ui, FADE_IN)


func task_message(message: String) -> void:
	if not _task_mode:
		return
	_task_deadline_ms = Time.get_ticks_msec() + TASK_TIMEOUT_MS
	_message.text = message
	if _ui.has_method("set_task"):
		_ui.call("set_task", true, _title.text, message)


func end_task() -> void:
	# Only the operation that started a task may end it. Without this, BACK
	# during a scene load could clear another operation's overlay.
	if not _task_mode:
		return
	_task_mode = false
	_task_deadline_ms = 0
	_ui.set_indeterminate(false)
	if _ui.has_method("set_task"):
		_ui.call("set_task", false)
	hide()
	_ui.modulate = Color.WHITE
	_busy = false
	call_deferred("_run_pending")


func go_to(path: String, title: String = "LOADING", message: String = "") -> void:
	if path == "":
		push_warning("SceneLoader: ignored a request with an empty scene path")
		return
	if not ALLOWED_SCENES.has(path):
		# Refuse before touching the tree: a rejected path previously reached
		# ResourceLoader/change_scene and could tear down the caller's UI first.
		push_error("SceneLoader: refused scene outside the allowlist: " + path)
		return
	if _busy:
		# Never drop a navigation request. Network start messages are not
		# repeated, so queue the newest target instead of desyncing peers.
		_pending_path = path
		_pending_title = title
		_pending_message = message
		return
	if not _needs_overlay(path):
		# Menus are cheap. A direct swap avoids the overlay's fixed
		# MIN_SHOW + fade cost, which was longer than the load itself.
		_go_direct(path)
		return
	get_tree().paused = false
	_busy = true
	_path = path
	_title.text = title
	_message.text = message
	_ui.set_indeterminate(false)
	if _ui.has_method("set_task"):
		_ui.call("set_task", false)
	_ui.set_progress(0.0, true)
	_show_overlay()

	var started: float = Time.get_ticks_msec() / 1000.0
	if not ResourceLoader.exists(path):
		_change_scene_to_file(path)
		_finish(started)
		return

	# Single-thread background loading avoids sub-thread preload lock contention
	# (notably on macOS/Metal with complex scene script dependency graphs).
	var error: Error = ResourceLoader.load_threaded_request(path, "", false)
	if error != OK:
		_change_scene_to_file(path)
		await get_tree().process_frame
		_finish(started)
		return
	_poll(started)


func _change_scene_to_file(path: String) -> void:
	## change_scene_to_* is deferred, so a failure only shows up in its return
	## value. Surface it instead of fading the overlay over the old scene and
	## looking like a successful (but empty) navigation.
	var error: Error = get_tree().change_scene_to_file(path)
	if error != OK:
		push_error("SceneLoader: could not change to %s (%d)" % [path, error])


func _needs_overlay(path: String) -> bool:
	return OVERLAY_SCENES.has(path)


func _go_direct(path: String) -> void:
	## Instant swap for menu screens. The scene change itself is deferred to
	## the end of the frame by Godot, so keep _busy set until then.
	get_tree().paused = false
	# A doomed change_scene_to_file would report ERR_CANT_OPEN but can still
	# leave the caller's UI in a half-torn-down state. Refuse it up front so
	# the current screen stays interactive instead of going blank.
	if not ResourceLoader.exists(path):
		push_error("SceneLoader: no such scene " + path)
		return
	_busy = true
	_path = path
	var error: Error = get_tree().change_scene_to_file(path)
	if error != OK:
		push_error("SceneLoader: could not change to " + path)
	await get_tree().process_frame
	_busy = false
	call_deferred("_run_pending")


func _poll(started: float) -> void:
	var progress: Array = [0.0]
	var now_ms: int = Time.get_ticks_msec()
	var deadline: int = now_ms + 20000
	var stall_deadline: int = now_ms + 8000
	var last_progress: float = -1.0
	while true:
		var status: int = ResourceLoader.load_threaded_get_status(_path, progress)
		var pct: float = float(progress[0]) if not progress.is_empty() else 0.0
		_ui.set_progress(pct)
		if pct > last_progress + 0.001:
			last_progress = pct
			stall_deadline = Time.get_ticks_msec() + 8000
		await get_tree().process_frame
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_change_scene_to_file(_path)
			await get_tree().process_frame
			_finish(started)
			return
		var tick_ms: int = Time.get_ticks_msec()
		if tick_ms > deadline or (last_progress <= 0.0 and tick_ms > stall_deadline):
			# A threaded load can stall on some drivers/filesystems. Never
			# leave multiplayer peers stuck on "Syncing players..."
			push_warning("Threaded scene load timed out; falling back: " + _path)
			_change_scene_to_file(_path)
			await get_tree().process_frame
			_finish(started)
			return

	_ui.set_progress(1.0, true)
	var elapsed: float = Time.get_ticks_msec() / 1000.0 - started
	if elapsed < MIN_SHOW:
		await get_tree().create_timer(MIN_SHOW - elapsed).timeout
	await get_tree().create_timer(POST_LOAD_PAUSE).timeout
	var packed: PackedScene = ResourceLoader.load_threaded_get(_path)
	if packed != null:
		var packed_error: Error = get_tree().change_scene_to_packed(packed)
		if packed_error != OK:
			push_error("SceneLoader: could not change to %s (%d)" % [_path, packed_error])
	else:
		_change_scene_to_file(_path)
	await get_tree().process_frame
	_finish(started)


func _finish(started: float) -> void:
	# Never let a pause flag from the outgoing scene freeze the new one.
	get_tree().paused = false
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
	# A rapid double press (or a retried network start) queues the same target
	# while the first load is still finishing. Replaying it would reload the
	# scene that just appeared - a race would replay its intro, a lobby would
	# rebuild itself - so drop a request the tree already satisfies. A
	# deliberate same-scene replay (CARGO RUSH's PLAY AGAIN) calls go_to()
	# directly, after the load has finished, and is not affected.
	if next_path == current_scene_path():
		return
	go_to(next_path, next_title, next_message)
