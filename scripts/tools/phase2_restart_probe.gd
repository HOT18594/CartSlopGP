extends Node
## Two-process MP rematch (RACE AGAIN / PLAY AGAIN) e2e probe — WS5-01.
##
## Proves that a host's result-card rematch actually rebuilds the match on BOTH
## peers: each process records the live match scene's instance id, the host calls
## `Network.start_game(<race>, GAME_MINIGAMES, true)` exactly like the result card
## does, and each peer asserts a NEW scene instance appears and the session is
## still live/playing (no deadlock, no "room stuck on playing" weirdness).
##
## Run from the workspace root, host first, then client:
##   set CSGP_RESTART_ROLE=host  & Godot ... res://scripts/tools/phase2_restart_probe.tscn
##   set CSGP_RESTART_ROLE=client& Godot ... res://scripts/tools/phase2_restart_probe.tscn
##
## Exit code = number of failed checks. The suite prints one `P2_RESTART[role]`
## PASS/FAIL line; run_e2e.ps1-style wrappers treat that marker as authoritative
## because Start-Process does not always surface a short-lived child's exit code.

const SCENE_LOAD_TIMEOUT_MS: int = 45000
const SYNC_TIMEOUT_MS: int = 30000

var _role: String = "host"
var _host_ready: bool = false
var _host_failed: bool = false
var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	# Survive the SceneLoader swaps this probe triggers: live at tree root,
	# outside the current scene, and always processing.
	var tree: SceneTree = get_tree()
	if tree != null:
		var root_node: Node = tree.root
		var parent: Node = get_parent()
		if parent != null and parent != root_node:
			parent.remove_child(self)
			root_node.add_child(self)
		if tree.current_scene == self:
			tree.current_scene = null
	process_mode = Node.PROCESS_MODE_ALWAYS
	_role = OS.get_environment("CSGP_RESTART_ROLE").strip_edges().to_lower()
	if _role == "":
		_role = "host"
	# Wall-clock watchdog: a parse/logic regression must never leave an orphan
	# process holding the LAN ports for the next run.
	var watchdog := Timer.new()
	watchdog.wait_time = 180.0
	watchdog.one_shot = true
	watchdog.autostart = true
	watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	watchdog.timeout.connect(_on_watchdog_timeout)
	add_child(watchdog)
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	_checks += 1
	print("%s  [%s] %s" % ["OK  " if condition else "FAIL", _role, label])
	if not condition:
		_failures += 1
		push_error("P2_RESTART: " + label)


func _on_host_started(_code: String) -> void:
	_host_ready = true


func _on_host_failed(reason: String) -> void:
	_host_failed = true
	print("P2_RESTART[host] host_failed: " + reason)


func _on_watchdog_timeout() -> void:
	push_error("P2_RESTART: watchdog timeout, exiting")
	print("P2_RESTART[%s]: FAIL (watchdog after 180 s)" % _role)
	if get_tree() != null:
		get_tree().quit(99)


func _race_scene_path() -> String:
	return "res://scenes/minigames/grass_race.tscn"


func _current_path() -> String:
	var tree: SceneTree = get_tree()
	if tree == null or tree.current_scene == null:
		return ""
	return tree.current_scene.scene_file_path


func _instance_id() -> int:
	var tree: SceneTree = get_tree()
	if tree == null or tree.current_scene == null:
		return 0
	return int(tree.current_scene.get_instance_id())


func _wait_until(predicate: Callable, timeout_ms: int) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await get_tree().process_frame
	return bool(predicate.call())


func _scene_settled(path: String, old_id: int, want_new: bool) -> bool:
	if SceneLoader.is_busy() or _current_path() != path or _instance_id() == 0:
		return false
	if want_new:
		return _instance_id() != old_id
	return true


func _wait_scene(path: String, timeout_ms: int) -> int:
	var ok: bool = await _wait_until(
		func() -> bool: return _scene_settled(path, 0, false), timeout_ms)
	return _instance_id() if ok else 0


func _wait_new_scene(path: String, old_id: int, timeout_ms: int) -> int:
	var ok: bool = await _wait_until(
		func() -> bool: return _scene_settled(path, old_id, true), timeout_ms)
	return _instance_id() if ok else 0


func _run() -> void:
	print("P2_RESTART[%s] start pid=%d os=%s" % [
		_role, OS.get_process_id(), OS.get_name()])
	if _role == "client":
		await _run_client()
	else:
		await _run_host()
	_report()


func _report() -> void:
	print("P2_RESTART[%s]: %d checks, %d failure(s)" % [_role, _checks, _failures])
	print("P2_RESTART[%s]: %s" % [_role, "PASS" if _failures == 0 else "FAIL"])
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(_failures)


# --------------------------------------------------------------------------
# host: open a LAN room, start a match, then use the result-card restart path.

func _host_settled() -> bool:
	return _host_ready or _host_failed \
		or (Network.is_host and Network._lan_listener != null)


func _run_host() -> void:
	Network.host_started.connect(_on_host_started)
	Network.host_failed.connect(_on_host_failed)
	print("P2_RESTART[host] host_game called")
	Network.host_game("lan")
	await _wait_until(func() -> bool: return _host_settled(), SYNC_TIMEOUT_MS)
	print("P2_RESTART[host] host_game settled ready=%s failed=%s is_host=%s listener=%s" % [
		str(_host_ready), str(_host_failed), str(Network.is_host),
		str(Network._lan_listener != null)])
	_check((_host_ready or (Network.is_host and Network._lan_listener != null))
		and not _host_failed, "host opened a LAN room")
	if not Network.is_host:
		return
	# A private room does not beacon; the test room must be discoverable.
	Network.set_room_public(true)
	print("P2_RESTART[host] listening port=%d" % Network.port)

	var peers_deadline: int = Time.get_ticks_msec() + SCENE_LOAD_TIMEOUT_MS
	while Network.peer_count() < 2 and Time.get_ticks_msec() < peers_deadline:
		await get_tree().process_frame
	_check(Network.peer_count() >= 2, "client joined the LAN room")
	if Network.peer_count() < 2:
		return
	var client_peer: int = 1
	for peer_id: int in Network.multiplayer.get_peers():
		if peer_id > 1:
			client_peer = peer_id
			break
	_check(client_peer > 1, "host resolved the client peer id")
	await get_tree().create_timer(0.4).timeout

	# First match, exactly like the lobby START path.
	Network.start_game(_race_scene_path(), GameSettings.GAME_MINIGAMES)
	var first_id: int = await _wait_scene(_race_scene_path(), SCENE_LOAD_TIMEOUT_MS)
	_check(first_id != 0, "first match scene loaded on the host")
	if first_id == 0:
		return
	var client_ready: bool = await _wait_until(
		func() -> bool: return Network.is_scene_ready(client_peer), SCENE_LOAD_TIMEOUT_MS)
	_check(client_ready, "client loaded the first match scene")
	await get_tree().create_timer(0.6).timeout
	_check(Network.room_state == "playing", "room state is playing during the match")

	# This is the exact call the mode result cards make for RACE AGAIN.
	print("P2_RESTART[host] scene_before id=%d room=%s" % [first_id, Network.room_state])
	Network.start_game(_race_scene_path(), GameSettings.GAME_MINIGAMES, true)
	var second_id: int = await _wait_new_scene(_race_scene_path(), first_id,
		SCENE_LOAD_TIMEOUT_MS)
	_check(second_id != 0, "RACE AGAIN reloaded a NEW match scene instance on the host")
	_check(_current_path() == _race_scene_path(),
		"host is back on the match scene after the restart")
	_check(Network.room_state == "playing", "room state is playing after the restart")
	_check(Network.in_game, "in_game is still true after the restart")
	var restarted_client_ready: bool = await _wait_until(
		func() -> bool: return Network.is_scene_ready(client_peer), 20000)
	_check(restarted_client_ready, "client reported ready on the restarted match scene")
	print("P2_RESTART[host] scene_after id=%d room=%s" % [second_id, Network.room_state])
	# The client only leaves after it sees this run finish; give it the window
	# before tearing the session down.
	await get_tree().create_timer(3.0).timeout
	Network.leave()


# --------------------------------------------------------------------------
# client: discover/join the LAN room, wait for both match loads, assert restart.

var _joined: bool = false
var _join_failure: String = ""


func _run_client() -> void:
	Network.join_succeeded.connect(func() -> void: _joined = true)
	Network.join_failed.connect(func(reason: String) -> void: _join_failure = reason)
	var rooms: Array = []
	var scan_deadline: int = Time.get_ticks_msec() + SCENE_LOAD_TIMEOUT_MS
	while rooms.is_empty() and Time.get_ticks_msec() < scan_deadline:
		rooms = await Network.scan_lan_rooms(1.4)
		if rooms.is_empty():
			await get_tree().create_timer(0.5).timeout
	_check(not rooms.is_empty(), "client discovered the LAN room")
	if rooms.is_empty():
		return
	Network.join_lan_room(rooms[0])
	var join_deadline: int = Time.get_ticks_msec() + SYNC_TIMEOUT_MS
	while not _joined and _join_failure == "" and Time.get_ticks_msec() < join_deadline:
		await get_tree().process_frame
	_check(_joined, "client joined the LAN room")
	if not _joined:
		print("P2_RESTART[client] join_failed: " + _join_failure)
		return

	var first_id: int = await _wait_scene(_race_scene_path(), SCENE_LOAD_TIMEOUT_MS)
	_check(first_id != 0, "client loaded the first match scene from the host start")
	if first_id == 0:
		return
	await get_tree().create_timer(0.6).timeout
	print("P2_RESTART[client] scene_before id=%d" % first_id)

	var second_id: int = await _wait_new_scene(_race_scene_path(), first_id,
		SCENE_LOAD_TIMEOUT_MS)
	_check(second_id != 0, "host RACE AGAIN reloaded a NEW match scene instance on the client")
	_check(_current_path() == _race_scene_path(),
		"client is back on the match scene after the restart")
	_check(Network.is_session_active(), "client session is still active after the restart")
	_check(Network.is_connected_to_server(), "client ENet link is still connected after the restart")
	print("P2_RESTART[client] scene_after id=%d" % second_id)
	# Hold the session open long enough for the host to observe this client's
	# post-restart scene-ready report before the client exits (the host asserts
	# that bookkeeping; without the hold the two processes race the teardown).
	var host_announce: bool = await _wait_until(
		func() -> bool: return Network.is_scene_ready(1), 20000)
	_check(host_announce, "client saw the host announce the restarted match scene")
	await get_tree().create_timer(6.0).timeout
	Network.leave()
