extends CanvasLayer
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## Global transition layer. Heavy 3D scenes stream with the themed loading
## screen; cheap menu scenes swap directly with no overlay. Autoload: SceneLoader.
##
## The loading screen owns its own percentage and damped fill now. This layer
## only feeds it real progress values and animates the overlay in/out, so the
## number and the bar can never disagree.
##
## Progress is phased (see the LOAD_PHASE_* constants): resource streaming is
## only the first 72% of the bar; scene instantiation and the new scene's first
## frames own the rest, and 100% is reported explicitly only once gameplay is
## live and about to fade in. A fast load therefore never shows a stalled full
## bar while the track builds underneath it.

const MIN_SHOW: float = 0.25 ## Never flash the overlay for less than this.
const POST_LOAD_PAUSE: float = 0.10 ## Beat between the last warm-up frame and 100%.
const FADE_IN: float = 0.24
const FADE_OUT: float = 0.18

## Honest progress weights. The bar used to snap to 100% the moment the packed
## scene finished streaming, then the player watched a full bar while Godot
## instantiated the scene, built the track and compiled first-frame shaders.
## Now streaming owns only the first slice and the remaining slices are
## measured on the new scene itself:
##   0.04 -> 0.72  resource streaming (ResourceLoader's byte progress)
##   0.72 -> 0.80  scene instantiation (`_ready`: spawn setup, track build)
##   0.80 -> 0.985 first frames of _process/_physics (shader + asset warm-up)
##   1.00          only once the new scene is live and about to be faded in
const LOAD_PHASE_START: float = 0.04
const LOAD_PHASE_END: float = 0.72
const INSTANTIATE_START: float = 0.74
const WARMUP_START: float = 0.80
const WARMUP_END: float = 0.985
const WARMUP_FRAMES: int = 4 ## Frames given to the new scene before 100% is shown.


static func progress_for_stream(ratio: float) -> float:
	## Threaded-load ratio -> HUD bar value. Pure so the weighting can be
	## asserted headlessly without booting a real 3D scene.
	return LOAD_PHASE_START \
		+ (LOAD_PHASE_END - LOAD_PHASE_START) * clampf(ratio, 0.0, 1.0)


static func progress_for_warmup(t: float) -> float:
	## 0..1 warm-up frame ratio -> HUD bar value (never reaches 1.0: gameplay
	## readiness is signalled by the explicit terminal set_progress(1.0)).
	return lerpf(WARMUP_START, WARMUP_END, clampf(t, 0.0, 1.0))
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

## Request priority (WS5P3-02). Authoritative network requests — a match start
## or a host-ordered return to the lobby — outrank local screen navigation: the
## begin-game packet is not repeated, so a local BACK press must never replace a
## match that is already streaming. A UI request that arrives while a network
## load is in flight is dropped instead of queued.
const PRIORITY_UI: int = 0
const PRIORITY_NETWORK: int = 10
## WS5P3-01/-04: scenes that are only entered because a multiplayer session
## asked for them. If the session dies while one of these is streaming, the
## load is aborted instead of mounting a live-but-sessionless match.
const GAMEPLAY_SCENES: PackedStringArray = [
	"res://scenes/sandbox/sandbox.tscn",
	"res://scenes/minigames/grass_race.tscn",
	"res://scenes/minigames/cargo_rush.tscn",
	"res://scenes/minigames/knockout.tscn",
	"res://scenes/minigames/bomb_tag.tscn",
]
## WS5P3-11: a terminal load failure keeps the COULD NOT LOAD card readable for
## this long before the overlay is released and Network's rollback navigates away.
const FAIL_HOLD_SECONDS: float = 0.9

## Emitted once a scene swap settled and the overlay is about to release. The
## authoritative consumer is Network (match-start rollback aims at load_failed).
signal load_finished(path: String)
## Emitted when a scene could not be loaded at all (WS5P3-11). Listening code is
## expected to roll the session back instead of leaving peers on "playing".
signal load_failed(path: String, error: int)

@onready var _ui: Control = $UI
@onready var _title: Label = $UI/Title
@onready var _message: Label = $UI/Message

var _busy: bool = false
var _task_mode: bool = false
var _task_deadline_ms: int = 0
var _path: String = ""
var _active_priority: int = PRIORITY_UI
var _pending_path: String = ""
var _pending_title: String = ""
var _pending_message: String = ""
var _pending_priority: int = PRIORITY_UI
## Bumped when a load starts or is cancelled. A coroutine whose captured
## generation no longer matches has been abandoned and must not touch the
## overlay, _busy or the pending queue (WS5P3-01/-04 cancellation).
var _load_generation: int = 0
var _dropped_ui_requests: int = 0
## Headless-regression hook: fail the next overlay load without a real broken
## resource so the terminal-failure path (WS5P3-11) can be exercised.
var _test_fail_next_load: bool = false


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


func active_priority() -> int:
	## Priority of the load currently owning the overlay (0 = plain UI nav).
	return _active_priority


func network_priority() -> int:
	## Exposed so non-Network callers can opt into the authoritative queue.
	return PRIORITY_NETWORK


func is_authoritative_load() -> bool:
	return _active_priority >= PRIORITY_NETWORK


func queued_path() -> String:
	return _pending_path


func last_dropped_ui_requests() -> int:
	## Headless-audit hook for WS5P3-02 (a local nav was refused mid-match-load).
	return _dropped_ui_requests


func debug_force_next_load_failure() -> void:
	## Headless-regression hook for WS5P3-11: the next overlay load reports a
	## terminal failure without relying on a corrupted real resource.
	_test_fail_next_load = true


func _suspend_outgoing_focus() -> void:
	## WS5P3-03: the overlay blocks the mouse but keyboard/gamepad focus lives on
	## the viewport, so the outgoing screen's focused button would still receive
	## ui_accept while the next scene streams. Drop that focus before the load;
	## every menu re-establishes its own default focus in _ready (MenuNav.refresh).
	var viewport: Viewport = get_viewport()
	if viewport != null and viewport.gui_get_focus_owner() != null:
		viewport.gui_release_focus()


func cancel_gameplay_load(reason: String = "") -> bool:
	## WS5P3-01/-04: abort an in-flight or queued AUTHORITATIVE gameplay load
	## because the session it belonged to ended. Menu/garage loads are left
	## alone — they are valid without a session. Returns true when a request was
	## actually cancelled so the caller can mark the session loss for the mode
	## scenes' _ready guard.
	var cancelled: bool = false
	if _busy and _path in GAMEPLAY_SCENES:
		_load_generation += 1
		cancelled = true
		_busy = false
		_active_priority = PRIORITY_UI
		_path = ""
		hide()
		_ui.modulate = Color.WHITE
		_ui.set_indeterminate(false)
		_ui.set_progress(0.0, true)
		if reason != "":
			push_warning("SceneLoader: cancelled a gameplay load (%s)" % reason)
	if _pending_path != "" and _pending_path in GAMEPLAY_SCENES:
		cancelled = true
		_pending_path = ""
		_pending_title = ""
		_pending_message = ""
		_pending_priority = PRIORITY_UI
	if cancelled:
		call_deferred("_run_pending")
	return cancelled


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
	_suspend_outgoing_focus()
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
	_active_priority = PRIORITY_UI
	call_deferred("_run_pending")


func go_to(path: String, title: String = "LOADING", message: String = "",
		priority: int = PRIORITY_UI) -> void:
	if path == "":
		push_warning("SceneLoader: ignored a request with an empty scene path")
		return
	if not ALLOWED_SCENES.has(path):
		# Refuse before touching the tree: a rejected path previously reached
		# ResourceLoader/change_scene and could tear down the caller's UI first.
		push_error("SceneLoader: refused scene outside the allowlist: " + path)
		return
	if _busy:
		_queue_request(path, title, message, priority)
		return
	_start_load(path, title, message, priority)


func _queue_request(path: String, title: String, message: String,
		priority: int) -> void:
	## Single pending slot, but priority-aware (WS5P3-02). An authoritative
	## network target may replace anything; a local nav may never replace an
	## in-flight or queued network target, because the network request is not
	## repeated and dropping the local screen is the only safe outcome.
	if _active_priority >= PRIORITY_NETWORK and priority < PRIORITY_NETWORK:
		_dropped_ui_requests += 1
		push_warning("SceneLoader: dropped a local nav during an authoritative load: "
			+ path)
		return
	if _pending_path != "" and priority < _pending_priority:
		_dropped_ui_requests += 1
		return
	_pending_path = path
	_pending_title = title
	_pending_message = message
	_pending_priority = priority


func _start_load(path: String, title: String, message: String,
		priority: int) -> void:
	_notify_music_transition(path)
	if not _needs_overlay(path):
		# Menus are cheap. A direct swap avoids the overlay's fixed
		# MIN_SHOW + fade cost, which was longer than the load itself.
		_go_direct(path, priority)
		return
	get_tree().paused = false
	_busy = true
	_active_priority = priority
	_path = path
	_load_generation += 1
	var generation: int = _load_generation
	_title.text = title
	_message.text = message
	_ui.set_indeterminate(false)
	if _ui.has_method("set_task"):
		_ui.call("set_task", false)
	_ui.set_progress(0.0, true)
	_show_overlay()

	var started: float = Time.get_ticks_msec() / 1000.0
	if _test_fail_next_load:
		_test_fail_next_load = false
		await _fail_load(path, int(ERR_FILE_CORRUPT), started, generation)
		return
	if not ResourceLoader.exists(path):
		await _fail_load(path, int(ERR_FILE_NOT_FOUND), started, generation)
		return

	# Single-thread background loading avoids sub-thread preload lock contention
	# (notably on macOS/Metal with complex scene script dependency graphs).
	var error: Error = ResourceLoader.load_threaded_request(path, "", false)
	if error != OK:
		# Fall back to a blocking change; it may still succeed.
		var change_error: Error = get_tree().change_scene_to_file(path)
		await get_tree().process_frame
		if generation != _load_generation:
			return
		if change_error != OK:
			await _fail_load(path, int(change_error), started, generation)
			return
		await _finish(started, generation)
		return
	_poll(started, generation)


func _notify_music_transition(path: String) -> void:
	var music: Node = get_node_or_null("/root/Music")
	if music != null and music.has_method("transition_to_scene"):
		music.call("transition_to_scene", path)


func _needs_overlay(path: String) -> bool:
	return OVERLAY_SCENES.has(path)


func _go_direct(path: String, priority: int = PRIORITY_UI) -> void:
	## Instant swap for menu screens. The scene change itself is deferred to
	## the end of the frame by Godot, so keep _busy set until then.
	get_tree().paused = false
	# A doomed change_scene_to_file would report ERR_CANT_OPEN but can still
	# leave the caller's UI in a half-torn-down state. Refuse it up front so
	# the current screen stays interactive instead of going blank.
	if not ResourceLoader.exists(path):
		push_error("SceneLoader: no such scene " + path)
		load_failed.emit(path, int(ERR_FILE_NOT_FOUND))
		return
	_busy = true
	_active_priority = priority
	_path = path
	_load_generation += 1
	var generation: int = _load_generation
	var error: Error = get_tree().change_scene_to_file(path)
	if error != OK:
		push_error("SceneLoader: could not change to " + path)
		_busy = false
		_active_priority = PRIORITY_UI
		_path = ""
		_restore_menu_focus()
		load_failed.emit(path, int(error))
		return
	await get_tree().process_frame
	if generation != _load_generation:
		return
	_busy = false
	_active_priority = PRIORITY_UI
	var finished_path: String = _path
	_path = ""
	load_finished.emit(finished_path)
	call_deferred("_run_pending")


func _poll(started: float, generation: int) -> void:
	var target: String = _path
	var progress: Array = [0.0]
	var now_ms: int = Time.get_ticks_msec()
	var deadline: int = now_ms + 20000
	var stall_deadline: int = now_ms + 8000
	var last_progress: float = LOAD_PHASE_START
	while true:
		if generation != _load_generation:
			return
		var status: int = ResourceLoader.load_threaded_get_status(target, progress)
		var pct: float = float(progress[0]) if not progress.is_empty() else 0.0
		# Streaming is re-weighted into the first slice of the bar. Clamp upward
		# so the readout can never move backwards if the loader reports a dip.
		var weighted: float = progress_for_stream(pct)
		weighted = maxf(weighted, last_progress)
		last_progress = weighted
		_ui.set_progress(weighted)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			await _fail_load(target, int(ERR_FILE_CORRUPT), started, generation)
			return
		var tick_ms: int = Time.get_ticks_msec()
		if tick_ms > deadline or (last_progress <= LOAD_PHASE_START and tick_ms > stall_deadline):
			# A threaded load can stall on some drivers/filesystems. Never
			# leave multiplayer peers stuck on "Syncing players...". The
			# blocking fallback is still a real load attempt: only a change
			# that actually fails goes down the terminal-failure path.
			push_warning("Threaded scene load timed out; falling back: " + target)
			var fallback_error: Error = get_tree().change_scene_to_file(target)
			await get_tree().process_frame
			if generation != _load_generation:
				return
			if fallback_error != OK:
				await _fail_load(target, int(fallback_error), started, generation)
				return
			await _finish(started, generation)
			return
		await get_tree().process_frame

	# Everything is in memory. Give a fast machine enough wall-clock for the
	# overlay to read as a transition instead of a flash.
	_ui.set_progress(LOAD_PHASE_END)
	var elapsed: float = Time.get_ticks_msec() / 1000.0 - started
	if elapsed < MIN_SHOW:
		await get_tree().create_timer(MIN_SHOW - elapsed).timeout
		if generation != _load_generation:
			return

	# Phase 2: instantiate. The new scene's _ready (track build, cart spawn,
	# camera/audio setup) runs here, so the bar must not be at 100% yet.
	_ui.set_progress(INSTANTIATE_START)
	await get_tree().process_frame
	if generation != _load_generation:
		return
	var packed: PackedScene = ResourceLoader.load_threaded_get(target)
	var packed_error: Error = ERR_CANT_CREATE
	if packed != null:
		packed_error = get_tree().change_scene_to_packed(packed)
	else:
		packed_error = get_tree().change_scene_to_file(target)
	if packed_error != OK:
		# WS5P3-11: a refused swap is terminal. Do not warm up and fade away
		# over the old screen while peers believe a match is playing.
		await _fail_load(target, int(packed_error), started, generation)
		return

	# Phase 3: the scene is live. Spend a few real frames on it so first-frame
	# shader/asset warm-up and deferred spawn placement are covered by the bar,
	# then phase 4 reports an honest 100% immediately before the fade-out.
	await _warm_up_new_scene(generation)
	if generation != _load_generation:
		return
	await get_tree().create_timer(POST_LOAD_PAUSE).timeout
	if generation != _load_generation:
		return
	_ui.set_progress(1.0, true)
	await _finish(started, generation)


func _warm_up_new_scene(generation: int) -> void:
	for frame in WARMUP_FRAMES:
		await get_tree().process_frame
		if generation != _load_generation:
			return
		var t: float = float(frame + 1) / float(WARMUP_FRAMES)
		_ui.set_progress(progress_for_warmup(t))


func _finish(started: float, generation: int) -> void:
	if generation != _load_generation:
		return
	# Never let a pause flag from the outgoing scene freeze the new one.
	get_tree().paused = false
	var elapsed: float = Time.get_ticks_msec() / 1000.0 - started
	if elapsed < MIN_SHOW:
		await get_tree().create_timer(MIN_SHOW - elapsed).timeout
		if generation != _load_generation:
			return
	# Fade the overlay away after the new scene is already underneath it.
	var tween: Tween = UiAnim.fade_out(_ui, FADE_OUT)
	if tween != null:
		await tween.finished
	if generation != _load_generation:
		return
	hide()
	_ui.modulate = Color.WHITE
	_ui.set_progress(0.0, true)
	_busy = false
	_active_priority = PRIORITY_UI
	var finished_path: String = _path
	_path = ""
	load_finished.emit(finished_path)
	call_deferred("_run_pending")


func _fail_load(path: String, error: int, started: float, generation: int) -> void:
	## WS5P3-11: a scene that cannot be swapped in is a terminal state. Show it
	## on the overlay and emit load_failed so Network can roll the room back to
	## the lobby, instead of fading out as if a match had started.
	if generation != _load_generation:
		return
	push_error("SceneLoader: could not load %s (%d)" % [path, error])
	_title.text = "COULD NOT LOAD"
	_message.text = "The next screen failed to load."
	_ui.set_indeterminate(false)
	_ui.set_progress(0.0, true)
	load_failed.emit(path, error)
	# Keep the card readable for a beat before releasing the overlay. A listener
	# (Network rollback) queues the replacement screen while this load still owns
	# the overlay, so _run_pending navigates as soon as it is released.
	var hold: float = FAIL_HOLD_SECONDS - (Time.get_ticks_msec() / 1000.0 - started)
	if hold > 0.0:
		await get_tree().create_timer(hold).timeout
		if generation != _load_generation:
			return
	_busy = false
	_active_priority = PRIORITY_UI
	_path = ""
	hide()
	_ui.modulate = Color.WHITE
	_ui.set_progress(0.0, true)
	_restore_menu_focus()
	call_deferred("_run_pending")


func _restore_menu_focus() -> void:
	## If nothing navigated away after a failure the old screen is still live:
	## give keyboard/gamepad navigation a focus target back (WS5P3-03 release).
	var nav: Node = get_node_or_null("/root/MenuNav")
	if nav != null and nav.has_method("refresh"):
		nav.call("refresh")


func _run_pending() -> void:
	if _pending_path == "" or _busy:
		return
	var next_path: String = _pending_path
	var next_title: String = _pending_title
	var next_message: String = _pending_message
	var next_priority: int = _pending_priority
	_pending_path = ""
	_pending_title = ""
	_pending_message = ""
	_pending_priority = PRIORITY_UI
	# A rapid double press (or a retried network start) queues the same target
	# while the first load is still finishing. Replaying it would reload the
	# scene that just appeared - a race would replay its intro, a lobby would
	# rebuild itself - so drop a request the tree already satisfies. A
	# deliberate same-scene replay (CARGO RUSH's PLAY AGAIN) calls go_to()
	# directly, after the load has finished, and is not affected.
	if next_path == current_scene_path():
		return
	go_to(next_path, next_title, next_message, next_priority)
