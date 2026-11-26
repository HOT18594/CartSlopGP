extends SceneTree
## Phase 3 post-implementation bug-fix regression suite (WS5 Phase-3 findings).
##
## Covers the fixes that need a real process to prove:
##   WS5P3-01  host loss during a match (re)load keeps the HOST DISCONNECTED
##             overlay: the in-flight match load is cancelled and the live match
##             scene's pause menu receives the notice; a parked notice is picked
##             up by the next PauseMenu._ready if the swap had already committed.
##   WS5P3-02  SceneLoader gives authoritative network loads a priority: a local
##             navigation request during a match load is dropped, never queued
##             over the match.
##   WS5P3-03  the loading overlay releases the outgoing screen's GUI focus, and
##             the lobby's focused-button handlers are SceneLoader.is_busy()-gated.
##   WS5P3-04  a session teardown while a match streams aborts the load (never a
##             silent offline match); the mode scenes' _ready guard covers the
##             late-swap window.
##   WS5P3-06  the pause menu actually shows its mode/close hints (MP says the
##             world keeps running).
##   WS5P3-11  a terminal scene-load failure rolls the room back to the lobby
##             instead of leaving it advertised "playing".
## Also pins the WS5P3-12 wire contract (16-arg config + additive bot-team RPC).
##
## Exit code = number of failures (same contract as the other suites).
## Run from the workspace root:
##   downloads/godot_editor/Godot_v4.7.2-stable_win64_console.exe --headless \
##     --path godot_project --script res://scripts/tools/phase3_bugfix_smoke.gd

const NETWORK_SCRIPT := "res://scripts/net/network.gd"
const SCENE_LOADER_SCRIPT := "res://scripts/systems/scene_loader.gd"
const LOBBY_SCRIPT := "res://scripts/ui/lobby_menu.gd"
const PAUSE_SCRIPT := "res://scripts/ui/pause_menu.gd"
const MODE_SCRIPTS: PackedStringArray = [
	"res://scripts/minigames/grass_race.gd",
	"res://scripts/minigames/cargo_rush.gd",
	"res://scripts/minigames/knockout.gd",
	"res://scripts/minigames/bomb_tag.gd",
	"res://scripts/sandbox.gd",
]
const SANDBOX_SCENE := "res://scenes/sandbox/sandbox.tscn"
const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const LOBBY_SCENE := "res://scenes/ui/lobby_menu.tscn"
const MINIGAMES_SCENE := "res://scenes/ui/minigames_menu.tscn"
const PAUSE_MENU_SCENE := "res://scenes/ui/pause_menu.tscn"
const LEGACY_CONFIG_ARITY: int = 16

var _failures: int = 0
var _checks: int = 0
var _load_failed_events: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	print("%s  %s" % ["OK  " if condition else "FAIL", message])
	if not condition:
		_failures += 1
		push_error("P3_BUGFIX: " + message)


func _loader() -> Node:
	return root.get_node_or_null("/root/SceneLoader")


func _net() -> Node:
	return root.get_node_or_null("/root/Network")


func _loader_busy() -> bool:
	var loader: Node = _loader()
	return loader != null and bool(loader.call("is_busy"))


func _wait_idle(timeout_ms: int = 30000) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if not _loader_busy():
			await process_frame
			if not _loader_busy():
				return true
		await process_frame
	return false


func _wait_scene(path: String, timeout_ms: int = 30000) -> Node:
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var scene: Node = current_scene
		if scene != null and scene.scene_file_path == path and not _loader_busy():
			return scene
		await process_frame
	return null


func _wait_scene_path(path: String, timeout_ms: int = 30000) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var scene: Node = current_scene
		if scene != null and scene.scene_file_path == path and not _loader_busy():
			return true
		await process_frame
	return false


func _goto(path: String, timeout_ms: int = 30000) -> Node:
	var loader: Node = _loader()
	loader.call("go_to", path, "TEST", "test navigation")
	return await _wait_scene(path, timeout_ms)


func _on_watchdog() -> void:
	_check(false, "suite watchdog fired (a section hung past its deadline)")
	print("P3_BUGFIX_SMOKE: %d checks, %d failures" % [_checks, _failures])
	print("P3_BUGFIX_SMOKE: FAIL (watchdog)")
	quit(99)


func _run() -> void:
	var watchdog: SceneTreeTimer = create_timer(180.0)
	watchdog.timeout.connect(_on_watchdog)
	print("P3_BUGFIX_SMOKE: start")
	_ensure_offline_peer()
	await _test_signal_surface()
	await _test_web_flag_alignment()
	await _test_priority_guard()
	await _test_host_loss_during_reload()
	await _test_session_teardown_during_load()
	await _test_failed_load_rollback()
	await _test_focus_and_gating()
	await _test_pause_hints()
	await _test_pending_host_lost_notice()
	print("P3_BUGFIX_SMOKE: %d checks, %d failures" % [_checks, _failures])
	print("P3_BUGFIX_SMOKE: %s" % ("PASS" if _failures == 0 else "FAIL"))
	quit(0 if _failures == 0 else _failures)


# --------------------------------------------------------------------------
# shared helpers


func _ensure_offline_peer() -> void:
	## The suite fakes session state on the real Network autoload while no ENet
	## peer exists. An OfflineMultiplayerPeer makes get_peers()/get_unique_id()
	## legal in that state (no engine "No multiplayer peer" error spam), which is
	## what a real in-process session looks like to the UI code under test.
	if root.multiplayer.multiplayer_peer != null:
		return
	root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _func_source(source: String, func_name: String) -> String:
	## Slice of a GDScript file for one function, used for cheap static guards.
	var marker: String = "func " + func_name + "("
	var start: int = source.find(marker)
	if start < 0:
		return ""
	var next: int = source.find("\nfunc ", start + marker.length())
	if next < 0:
		next = source.length()
	return source.substr(start, next - start)


func _restore_network() -> void:
	var net: Node = _net()
	if net == null:
		return
	net.set("is_host", false)
	net.set("is_client", false)
	net.set("in_game", false)
	net.set("room_state", "lobby")
	net.set("_session_ended_during_load", false)
	net.set("_match_host_lost_pending", "")
	_ensure_offline_peer()
	paused = false


# --------------------------------------------------------------------------
# API surface + static guards


func _test_signal_surface() -> void:
	print("--- WS5P3 API surface and static guards")
	var loader: Node = _loader()
	var net: Node = _net()
	_check(loader != null, "SceneLoader autoload present")
	_check(net != null, "Network autoload present")
	if loader == null or net == null:
		return
	_check(loader.has_signal("load_finished"), "SceneLoader exposes load_finished")
	_check(loader.has_signal("load_failed"),
		"SceneLoader exposes the terminal-failure signal load_failed")
	for method: String in ["cancel_gameplay_load", "active_priority", "network_priority",
			"is_authoritative_load", "debug_force_next_load_failure",
			"last_dropped_ui_requests"]:
		_check(loader.has_method(method), "SceneLoader exposes %s()" % method)
	for method: String in ["consume_match_host_lost_pending",
			"has_match_host_lost_pending", "consume_session_ended_during_load"]:
		_check(net.has_method(method), "Network exposes %s()" % method)

	# WS5P3-12 wire contract: RPC dispatch is arity-strict, so the legacy config
	# packet must stay 16 arguments and bot teams must travel separately.
	var config_arity: int = -1
	var bot_rpc_present: bool = false
	for entry: Dictionary in net.get_method_list():
		var method_name: String = str(entry.get("name", ""))
		if method_name == "_net_session_config":
			config_arity = (entry.get("args", []) as Array).size()
		elif method_name == "_net_bot_teams":
			bot_rpc_present = true
	_check(config_arity == LEGACY_CONFIG_ARITY,
		"config RPC keeps the legacy %d-argument arity (got %d)" % [
			LEGACY_CONFIG_ARITY, config_arity])
	_check(bot_rpc_present, "bot teams travel in their own additive RPC")

	# WS5P3-03: the focused-button handlers in the lobby refuse to navigate while
	# a transition owns the tree.
	var lobby_source: String = FileAccess.get_file_as_string(LOBBY_SCRIPT)
	_check(lobby_source.length() > 0, "lobby source readable")
	for func_name: String in ["_on_join_pressed", "_begin_host", "_on_start_pressed",
			"_on_leave_pressed", "_on_back_pressed", "_on_open_all_modes",
			"_on_choose_map", "_on_change_vehicle"]:
		var body: String = _func_source(lobby_source, func_name)
		_check(body.contains("SceneLoader.is_busy()"),
			"%s is gated on SceneLoader.is_busy()" % func_name)

	# WS5P3-04: every mode scene that can be entered from a room has the guard.
	for path: String in MODE_SCRIPTS:
		var mode_source: String = FileAccess.get_file_as_string(path)
		_check(mode_source.contains("consume_session_ended_during_load")
				and mode_source.contains("_abort_stale_session_load"),
			"%s refuses a late stale-session match start" % path)

	var loader_source: String = FileAccess.get_file_as_string(SCENE_LOADER_SCRIPT)
	for needle: String in ["cancel_gameplay_load", "load_failed.emit",
			"dropped a local nav during an authoritative load", "gui_release_focus",
			"COULD NOT LOAD", "PRIORITY_NETWORK"]:
		_check(loader_source.contains(needle),
			"scene_loader implements: %s" % needle)

	# WS5P3-06: the pause-hint constants must be wired, not dead declarations.
	var pause_source: String = FileAccess.get_file_as_string(PAUSE_SCRIPT)
	_check(pause_source.contains("_mode_hint.text = MULTIPLAYER_HINT"),
		"pause menu writes MULTIPLAYER_HINT in open()")
	_check(pause_source.contains("_add_close_hint()\n"),
		"pause menu calls _add_close_hint()")


# --------------------------------------------------------------------------
# WS5P3-09 forced-web acceptance: the menu-gating flag and the render-profile
# flag must be provable TOGETHER (previously each was only ever exercised alone).


func _test_web_flag_alignment() -> void:
	var force_menu: bool = OS.get_environment("CSGP_FORCE_WEB") == "1"
	var force_quality: bool = OS.get_environment("CARTSLOP_FORCE_WEB_QUALITY") == "1"
	if not force_menu and not force_quality:
		print("--- WS5P3-09 forced-web flags not set (combined run is the env mode)")
		return
	print("--- WS5P3-09 combined forced-web acceptance")
	var menu_script: GDScript = load("res://scripts/ui/main_menu.gd") as GDScript
	_check(menu_script != null and bool(menu_script.call("is_web_build")) == force_menu,
		"MainMenu.is_web_build() follows CSGP_FORCE_WEB=%s" % str(force_menu))
	var fx: GDScript = load("res://scripts/effects/fx_quality.gd") as GDScript
	_check(fx != null and bool(fx.call("is_web")) == force_quality,
		"FxQuality.is_web() follows CARTSLOP_FORCE_WEB_QUALITY=%s" % str(force_quality))
	if force_quality:
		_check(int(fx.call("tier")) == 0,
			"the FX policy runs the PERFORMANCE tier when forced to web")
		var tier: String = OS.get_environment("CARTSLOP_WEB_QUALITY").strip_edges().to_lower()
		if tier == "low":
			_check(Engine.max_fps == 30,
				"low web tier caps the 3D frame rate at 30 (got %d)" % Engine.max_fps)
			_check(Engine.max_physics_steps_per_frame == 3,
				"low web tier caps physics catch-up at 3 steps (got %d)"
					% Engine.max_physics_steps_per_frame)
		else:
			_check(Engine.max_fps == 60,
				"balanced web tier caps the 3D frame rate at 60 (got %d)" % Engine.max_fps)
			_check(Engine.max_physics_steps_per_frame == 4,
				"balanced web tier caps physics catch-up at 4 steps (got %d)"
					% Engine.max_physics_steps_per_frame)
	if force_menu:
		var menu: Control = (load(MAIN_MENU_SCENE) as PackedScene).instantiate() as Control
		root.add_child(menu)
		await process_frame
		await process_frame
		_check(menu.find_child("WebTag", true, false) != null,
			"the forced-web menu shows the WEB tag instead of QUIT")
		_check(menu.find_child("QuitButton", true, false) == null,
			"the forced-web menu hides the desktop QUIT tab")
		menu.queue_free()
		await process_frame


# --------------------------------------------------------------------------
# WS5P3-02 priority guard (+ WS5P3-03 focus release)


func _test_priority_guard() -> void:
	print("--- WS5P3-02 authoritative load priority + WS5P3-03 focus release")
	var loader: Node = _loader()
	if loader == null:
		return
	await _goto(MAIN_MENU_SCENE)
	_check(current_scene != null and current_scene.scene_file_path == MAIN_MENU_SCENE,
		"start from the main menu")

	# A focused control in the OUTGOING scene must lose viewport focus as soon as
	# the loading overlay appears (keyboard/gamepad ui_accept can no longer reach
	# the screen that is being replaced).
	var probe := Button.new()
	probe.name = "FocusProbe"
	probe.text = "PROBE"
	root.add_child(probe)
	await process_frame
	probe.grab_focus()
	_check(root.gui_get_focus_owner() == probe,
		"focus probe owns the viewport focus before the load")

	# Authoritative match load.
	loader.call("go_to", SANDBOX_SCENE, "STARTING SANDBOX", "Syncing players...",
		loader.call("network_priority"))
	_check(_loader_busy(), "authoritative match load started (loader busy)")
	_check(root.gui_get_focus_owner() == null,
		"loading overlay released the outgoing screen's GUI focus")
	_check(bool(loader.call("is_authoritative_load")),
		"the in-flight load is marked authoritative")

	# A local navigation request while the match streams must be DROPPED, not
	# queued over the match (the old last-writer-wins queue).
	loader.call("go_to", MINIGAMES_SCENE, "SELECT MODE", "local nav")
	_check(int(loader.call("last_dropped_ui_requests")) >= 1,
		"local nav during a match load was refused")
	var sandbox: Node = await _wait_scene(SANDBOX_SCENE, 45000)
	_check(sandbox != null, "the authoritative match scene won the race")
	_check(current_scene != null
			and current_scene.scene_file_path == SANDBOX_SCENE,
		"the local nav did not replace the match scene")
	_check(not _loader_busy(), "the loader settles idle after the match load")
	_check(str(loader.call("queued_path")) == "",
		"no stale queued navigation is replayed")
	probe.queue_free()
	await process_frame


# --------------------------------------------------------------------------
# WS5P3-01 host loss during a match (re)load


func _test_host_loss_during_reload() -> void:
	print("--- WS5P3-01 host loss during a match (re)load")
	var loader: Node = _loader()
	var net: Node = _net()
	if loader == null or net == null:
		return
	# The priority test left a live sandbox instance in the tree.
	var old_scene: Node = current_scene
	_check(old_scene != null and old_scene.scene_file_path == SANDBOX_SCENE,
		"a live match scene is current before the host-loss probe")
	if old_scene == null or old_scene.scene_file_path != SANDBOX_SCENE:
		return
	var old_id: int = old_scene.get_instance_id()
	var pause_root: Control = old_scene.get_node_or_null("PauseMenu/Root") as Control
	_check(pause_root != null, "the live match scene has a pause menu")

	# Start a rematch load (same scene, authoritative priority), then simulate the
	# host disconnecting mid-load exactly like Network._on_server_disconnected.
	loader.call("go_to", SANDBOX_SCENE, "STARTING SANDBOX", "Syncing players...",
		loader.call("network_priority"))
	_check(_loader_busy(), "rematch load is streaming")
	net.set("is_client", true)
	net.set("in_game", true)
	net.call("_on_server_disconnected")
	_ensure_offline_peer()
	await process_frame
	await process_frame

	_check(not _loader_busy(),
		"the in-flight match load was cancelled by the session teardown")
	_check(current_scene != null and current_scene.get_instance_id() == old_id,
		"the live match scene was kept (no sessionless match replaced it)")
	if pause_root != null:
		_check(bool(pause_root.get("_host_lost")),
			"the live pause menu entered the HOST DISCONNECTED state")
		var title: Label = pause_root.find_child("Title", true, false) as Label
		_check(title != null and title.text == "HOST DISCONNECTED",
			"the overlay is titled HOST DISCONNECTED")
		_check(paused, "the abandoned match is frozen behind the overlay")
	else:
		_check(false, "pause menu available for the host-loss overlay")
	_check(not bool(net.call("has_match_host_lost_pending")),
		"the host-left notice was delivered, not left parked")

	# Cleanup: drop the overlay and return to a neutral menu.
	paused = false
	if pause_root != null:
		pause_root.set("_host_lost", false)
		pause_root.call("close")
	paused = false
	_restore_network()
	await _goto(MAIN_MENU_SCENE)


# --------------------------------------------------------------------------
# WS5P3-04 session teardown during a match stream


func _test_session_teardown_during_load() -> void:
	print("--- WS5P3-04 session teardown during a match stream")
	var loader: Node = _loader()
	var net: Node = _net()
	if loader == null or net == null:
		return
	await _goto(MAIN_MENU_SCENE)

	# (a) The load itself is aborted: no scene swap, no silent offline race.
	net.set("is_host", true)
	loader.call("go_to", SANDBOX_SCENE, "STARTING SANDBOX", "Syncing players...",
		loader.call("network_priority"))
	_check(_loader_busy(), "match load is streaming before the teardown")
	await process_frame
	net.call("leave")
	_ensure_offline_peer()
	await process_frame
	_check(not _loader_busy(), "session teardown cancelled the match load")
	_check(bool(net.call("consume_session_ended_during_load")),
		"the teardown is marked for the mode-scene stale-start guard")
	var raced_scene: Node = current_scene
	_check(raced_scene != null and raced_scene.scene_file_path == MAIN_MENU_SCENE,
		"an aborted match load does not mount the match scene offline")

	# (b) Late-swap guard: if the engine had already committed the swap, the
	# incoming mode scene must abort back to the lobby instead of starting solo.
	net.set("is_host", true)
	net.set("_session_ended_during_load", true)
	loader.call("go_to", SANDBOX_SCENE, "STARTING SANDBOX", "Syncing players...",
		loader.call("network_priority"))
	var lobby_ok: bool = await _wait_scene_path(LOBBY_SCENE, 45000)
	_check(lobby_ok, "a late stale-session match start returns to the lobby")
	_check(not bool(net.call("consume_session_ended_during_load")),
		"the stale-session marker was consumed by the mode-scene guard")
	_restore_network()
	await _goto(MAIN_MENU_SCENE)


# --------------------------------------------------------------------------
# WS5P3-11 failed scene change must not leave the room "playing"


func _test_failed_load_rollback() -> void:
	print("--- WS5P3-11 terminal load failure rolls the room back")
	var loader: Node = _loader()
	var net: Node = _net()
	if loader == null or net == null:
		return
	await _goto(MAIN_MENU_SCENE)
	_load_failed_events.clear()
	loader.connect("load_failed",
		func(path: String, error: int) -> void:
			_load_failed_events.append({"path": path, "error": error}),
		CONNECT_ONE_SHOT)
	net.set("is_host", true)
	net.set("is_client", false)
	net.set("in_game", true)
	net.call("set_room_state", "playing")
	_check(str(net.get("room_state")) == "playing",
		"room is advertised playing before the load attempt")

	loader.call("debug_force_next_load_failure")
	net.call("_begin_game_common", SANDBOX_SCENE, "sandbox", false, 0, 0, false)
	var lobby_ok: bool = await _wait_scene_path(LOBBY_SCENE, 45000)
	_check(not _load_failed_events.is_empty(),
		"a terminal scene-load failure emits load_failed")
	if not _load_failed_events.is_empty():
		_check(str(_load_failed_events[0].get("path", "")) == SANDBOX_SCENE,
			"load_failed names the failed match scene")
	_check(lobby_ok, "the failed start recovers to the lobby screen")
	await process_frame
	_check(str(net.get("room_state")) == "lobby",
		"the room is rolled back to 'lobby', never left on 'playing'")
	_check(not bool(net.get("in_game")),
		"Network no longer reports an in-game session")
	_restore_network()
	await _goto(MAIN_MENU_SCENE)


# --------------------------------------------------------------------------
# WS5P3-03 gating (runtime half; the static half is in _test_signal_surface)


func _test_focus_and_gating() -> void:
	print("--- WS5P3-03 loading overlay focus ownership")
	var loader: Node = _loader()
	if loader == null:
		return
	var probe := Button.new()
	probe.name = "FocusProbeTwo"
	root.add_child(probe)
	await process_frame
	probe.grab_focus()
	_check(root.gui_get_focus_owner() == probe, "focus probe owns the focus")
	loader.call("begin_task", "HOSTING", "Opening the room...")
	_check(bool(loader.call("is_busy")), "task overlay owns the transition")
	_check(root.gui_get_focus_owner() == null,
		"task overlay releases the outgoing screen's GUI focus")
	loader.call("end_task")
	await process_frame
	_check(not _loader_busy(), "task overlay releases cleanly")
	probe.queue_free()
	await process_frame


# --------------------------------------------------------------------------
# WS5P3-06 pause hints


func _test_pause_hints() -> void:
	print("--- WS5P3-06 pause menu mode/close hints")
	var net: Node = _net()
	if net == null:
		return
	var shell: Node = (load(PAUSE_MENU_SCENE) as PackedScene).instantiate()
	root.add_child(shell)
	await process_frame
	var pause: Control = shell.get_node_or_null("Root") as Control
	_check(pause != null, "pause menu scene instantiates")
	if pause == null:
		return
	var hint: Label = pause.get("_mode_hint") as Label
	_check(hint != null and not hint.visible,
		"the mode hint starts hidden before the menu opens")

	# Solo: the world is paused and the menu says so.
	net.set("is_host", false)
	net.set("is_client", false)
	pause.call("open")
	_check(bool(pause.get("_is_open")), "pause menu opens in solo")
	_check(hint != null and hint.visible
			and hint.text.contains("SINGLE PLAYER")
			and hint.text.contains("THE RACE IS PAUSED"),
		"solo pause explains that the race is paused (got '%s')"
			% ("" if hint == null else hint.text))
	pause.call("close")

	# Multiplayer: the world keeps running and the menu must say so.
	net.set("is_client", true)
	pause.call("open")
	_check(bool(pause.get("_is_open")), "pause menu opens in multiplayer")
	_check(hint != null and hint.visible
			and hint.text.contains("MULTIPLAYER")
			and hint.text.contains("KEEPS RUNNING"),
		"multiplayer pause warns that the world keeps running (got '%s')"
			% ("" if hint == null else hint.text))
	var close_hint: Label = pause.find_child("CloseHint", true, false) as Label
	_check(close_hint != null and close_hint.visible
			and close_hint.text == "ESC OR START CLOSES THIS MENU",
		"the close hint is now built and visible")
	var close_hint_count: int = 0
	for child: Node in pause.get_node("Center/Panel/Body").get_children():
		if child is Label and (child as Label).name == "CloseHint":
			close_hint_count += 1
	_check(close_hint_count == 1, "exactly one close hint label exists")
	pause.call("close")
	_restore_network()
	shell.queue_free()
	await process_frame


# --------------------------------------------------------------------------
# WS5P3-01 parked notice across a scene swap


func _test_pending_host_lost_notice() -> void:
	print("--- WS5P3-01 parked host-left notice is consumed by the next pause menu")
	var net: Node = _net()
	if net == null:
		return
	net.set("_match_host_lost_pending", "The host left the match.")
	var shell: Node = (load(PAUSE_MENU_SCENE) as PackedScene).instantiate()
	root.add_child(shell)
	await process_frame
	await process_frame
	var pause: Control = shell.get_node_or_null("Root") as Control
	_check(pause != null, "pause menu instantiates for the parked-notice probe")
	if pause != null:
		_check(bool(pause.get("_host_lost")),
			"the incoming pause menu replayed the parked host-left notice")
		var title: Label = pause.find_child("Title", true, false) as Label
		_check(title != null and title.text == "HOST DISCONNECTED",
			"the replayed overlay is titled HOST DISCONNECTED")
	_check(not bool(net.call("has_match_host_lost_pending")),
		"the parked notice is consumed once, not replayed forever")
	paused = false
	_restore_network()
	shell.queue_free()
	await process_frame
