extends SceneTree
## Phase 2 second-pass bug-fix regression suite (WS5 findings).
##
## Covers the fixes that need a real process to prove:
##   WS5-01  same-scene multiplayer rematch reloads the live scene instance and
##           keeps the begin-game retry guard for a plain repeated start.
##   WS5-02  deterministic close-finish ordering helper (reliable report is the
##           single crossing-time source; the progress latch only bounds it).
##   WS5-05  `scoreboard` InputMap action exists on keyboard AND gamepad and the
##           HUD opens/closes on the action, not on a raw key.
##   WS5-06  settings save is atomic: tmp + rename + crash recovery.
##   WS5-03  web menu replaces MULTIPLAYER/QUIT/UPDATE dead ends with hints.
##   WS5-13  lobby presence helpers gate the host START.
##
## Exit code = number of failures (same contract as the other suites).
## Run from the workspace root:
##   downloads/godot_editor/Godot_v4.7.2-stable_win64_console.exe --headless \
##     --path godot_project --script res://scripts/tools/phase2_bugfix_smoke.gd

const NETWORK_SCRIPT := "res://scripts/net/network.gd"
const GRASS_RACE_SCRIPT := "res://scripts/minigames/grass_race.gd"
const GAME_SETTINGS_SCRIPT := "res://scripts/systems/game_settings.gd"
const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const HUD_SCENE := "res://scenes/ui/hud.tscn"
const PAUSE_MENU_SCENE := "res://scenes/ui/pause_menu.tscn"
const LOBBY_SCENE := "res://scenes/ui/lobby_menu.tscn"
const SANDBOX_SCENE := "res://scenes/sandbox/sandbox.tscn"

## The WS5-06 probe must live outside user://: spawned Godot processes on this
## dev machine cannot write the user data dir (the documented "Failed to open
## user://logs" noise), so the test uses a workspace scratch directory instead.
var _settings_path: String = ""
var _settings_tmp: String = ""

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	print("%s  %s" % ["OK  " if condition else "FAIL", message])
	if not condition:
		_failures += 1
		push_error("P2_BUGFIX: " + message)


func _prepare_scratch() -> void:
	var workspace_dir: String = ProjectSettings.globalize_path("res://") \
		.trim_suffix("/").get_base_dir()
	var scratch_dir: String = workspace_dir.path_join("_audit/logs/p2-bugfix/tmp")
	DirAccess.make_dir_recursive_absolute(scratch_dir)
	_settings_path = scratch_dir.path_join("phase2_atomic_test.cfg")
	_settings_tmp = scratch_dir.path_join("phase2_atomic_test.cfg.tmp")


func _on_watchdog() -> void:
	## Never let a hung scene load hold the shared test ports forever: a hard
	## wall-clock cap that still reports which section stalled.
	_check(false, "suite watchdog fired (a section hung past its deadline)")
	print("P2_BUGFIX_SMOKE: %d checks, %d failures" % [_checks, _failures])
	print("P2_BUGFIX_SMOKE: FAIL (watchdog)")
	quit(99)


func _run() -> void:
	var watchdog: SceneTreeTimer = create_timer(150.0)
	watchdog.timeout.connect(_on_watchdog)
	_prepare_scratch()
	print("P2_BUGFIX_SMOKE: start")
	await _test_atomic_settings()
	await _test_finish_ordering()
	await _test_scoreboard_action()
	await _test_web_menu_guards()
	await _test_lobby_presence_helpers()
	await _test_lobby_start_gate_ui()
	await _test_host_lost_overlay()
	await _test_focus_loss_pause()
	await _test_rematch_reload()
	print("P2_BUGFIX_SMOKE: %d checks, %d failures" % [_checks, _failures])
	print("P2_BUGFIX_SMOKE: %s" % ("PASS" if _failures == 0 else "FAIL"))
	quit(0 if _failures == 0 else _failures)


# --------------------------------------------------------------------------
# WS5-06 atomic settings


func _wipe(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_atomic_settings() -> void:
	print("--- WS5-06 atomic settings save")
	var settings: Node = root.get_node_or_null("/root/GameSettings")
	_check(settings != null, "GameSettings autoload present")
	if settings == null:
		return
	var script: GDScript = load(GAME_SETTINGS_SCRIPT) as GDScript
	_check(script != null, "GameSettings script loads")
	if script == null:
		return
	_wipe(_settings_path)
	_wipe(_settings_tmp)

	# 1. A normal save lands under the live name and leaves no staging file.
	var config := ConfigFile.new()
	config.set_value("probe", "value", 1)
	var write_error: Error = int(script.call("commit_config_atomic", config,
		_settings_path, _settings_tmp))
	_check(write_error == OK, "atomic commit returns OK (%d)" % write_error)
	_check(FileAccess.file_exists(_settings_path),
		"atomic commit writes the live settings file")
	_check(not FileAccess.file_exists(_settings_tmp),
		"atomic commit leaves no staging file behind")
	var read_back := ConfigFile.new()
	_check(read_back.load(_settings_path) == OK
			and int(read_back.get_value("probe", "value", -1)) == 1,
		"atomic commit round-trips the written values")

	# 2. Saving over an existing file replaces it (the rename must overwrite).
	var config2 := ConfigFile.new()
	config2.set_value("probe", "value", 2)
	write_error = int(script.call("commit_config_atomic", config2,
		_settings_path, _settings_tmp))
	_check(write_error == OK, "a second atomic commit succeeds")
	read_back = ConfigFile.new()
	_check(read_back.load(_settings_path) == OK
			and int(read_back.get_value("probe", "value", -1)) == 2,
		"the second save replaced the previous file")

	# 3. A partial/garbage staging file (crash before the rename) never touches
	#    the live file: recovery discards it.
	var partial := FileAccess.open(_settings_tmp, FileAccess.WRITE)
	_check(partial != null, "the staging file can be simulated")
	if partial != null:
		partial.store_string("[probe]\nvalue=trunc")
		partial.close()
	var adopted: bool = bool(script.call("recover_staged_settings",
		_settings_path, _settings_tmp))
	_check(not adopted, "a leftover staging file is not adopted over a live save")
	_check(not FileAccess.file_exists(_settings_tmp),
		"recovery removes the stale staging file")
	read_back = ConfigFile.new()
	_check(read_back.load(_settings_path) == OK
			and int(read_back.get_value("probe", "value", -1)) == 2,
		"the live save survived the interrupted write")

	# 4. A crash inside the filesystem rename window (live name missing, staging
	#    complete) adopts the staged save on the next boot.
	var staged := ConfigFile.new()
	staged.set_value("probe", "value", 3)
	_check(staged.save(_settings_tmp) == OK, "a complete staged save is written")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_settings_path))
	adopted = bool(script.call("recover_staged_settings", _settings_path,
		_settings_tmp))
	_check(adopted, "recovery adopts a complete staged save when the live file is gone")
	_check(FileAccess.file_exists(_settings_path),
		"recovery restored the live settings file")
	read_back = ConfigFile.new()
	_check(read_back.load(_settings_path) == OK
			and int(read_back.get_value("probe", "value", -1)) == 3,
		"the recovered file holds the staged values")

	_wipe(_settings_path)
	_wipe(_settings_tmp)


# --------------------------------------------------------------------------
# WS5-02 deterministic close-finish ordering


func _test_finish_ordering() -> void:
	print("--- WS5-02 close-finish ordering")
	var race_script: GDScript = load(GRASS_RACE_SCRIPT) as GDScript
	_check(race_script != null, "grass_race script loads")
	if race_script == null:
		return
	var race: Node = race_script.new()
	_check(race != null, "grass_race helper instance exists")
	if race == null:
		return
	# Same true crossing (~60.0 s): the peer measured 60.010 s on its own clock
	# with a 90 ms RTT, the host's 20 Hz progress latch saw it at 60.080 s.
	var compensated: float = float(race.call("compensated_finish_time", 60.010,
		45.0, 61.5, 60.080))
	_check(absf(compensated - (60.010 + 0.045)) < 0.0001,
		"reliable report is re-aligned by half the measured RTT (%.3f s)" % compensated)
	# Two peers, same relayed arrival window, reversed packet arrival order: the
	# report-derived crossing decides the podium, not arrival.
	var peer_a: float = float(race.call("compensated_finish_time", 59.980, 60.0,
		60.600, 60.060))
	var peer_b: float = float(race.call("compensated_finish_time", 60.010, 60.0,
		60.600, 60.050))
	_check(peer_a < peer_b,
		"crossing time orders the pair even when the later crossing packet arrived first")
	# A report cannot claim a crossing far earlier than the host's own progress
	# latch (cheat guard): it is clamped into the observed window.
	var cheat: float = float(race.call("compensated_finish_time", 0.100, 20.0,
		60.0, 60.000))
	_check(cheat >= 60.0 - 0.6 - 0.0001,
		"an implausible short report is clamped to the host's observed crossing (%.3f s)" % cheat)
	# Without a progress latch the report may only trail the host clock by the
	# documented slack, so a zero-second claim cannot win.
	var unlatched: float = float(race.call("compensated_finish_time", 0.0, 20.0,
		60.0, -1.0))
	_check(unlatched >= 60.0 - 2.0 - 0.02 - 0.0001,
		"an unobserved short report is bounded by the report slack (%.3f s)" % unlatched)
	# The result is deterministic for identical inputs.
	var again: float = float(race.call("compensated_finish_time", 60.010, 45.0,
		61.5, 60.080))
	_check(is_equal_approx(compensated, again), "the compensation is deterministic")
	# A finished row with an authoritative time sorts before a later one through
	# the reconciliation contract (unchanged).
	race.free()


# --------------------------------------------------------------------------
# WS5-05 scoreboard on every device


func _test_scoreboard_action() -> void:
	print("--- WS5-05 scoreboard action")
	_check(InputMap.has_action(&"scoreboard"),
		"InputSetup created the scoreboard action")
	if not InputMap.has_action(&"scoreboard"):
		return
	var has_key: bool = false
	var has_pad: bool = false
	for event: InputEvent in InputMap.action_get_events(&"scoreboard"):
		if event is InputEventKey \
				and (event as InputEventKey).physical_keycode == KEY_TAB:
			has_key = true
		if event is InputEventJoypadButton \
				and (event as InputEventJoypadButton).button_index == JOY_BUTTON_BACK:
			has_pad = true
	_check(has_key, "scoreboard is bound to Tab")
	_check(has_pad, "scoreboard is bound to the gamepad Select/View button")

	var hud: Control = (load(HUD_SCENE) as PackedScene).instantiate() as Control
	root.add_child(hud)
	await process_frame
	if hud == null:
		_check(false, "HUD scene instantiates")
		return
	var pressed := InputEventAction.new()
	pressed.action = &"scoreboard"
	pressed.pressed = true
	hud.call("_unhandled_input", pressed)
	_check(bool(hud.get("_scoreboard_visible")), "pressing the action opens the scoreboard")
	var released := InputEventAction.new()
	released.action = &"scoreboard"
	released.pressed = false
	hud.call("_unhandled_input", released)
	_check(not bool(hud.get("_scoreboard_visible")), "releasing the action closes the scoreboard")
	hud.queue_free()
	await process_frame


# --------------------------------------------------------------------------
# WS5-03 web menu guards


func _test_web_menu_guards() -> void:
	print("--- WS5-03 web menu dead ends")
	OS.set_environment("CSGP_FORCE_WEB", "1")
	var menu: Control = (load(MAIN_MENU_SCENE) as PackedScene).instantiate() as Control
	root.add_child(menu)
	await process_frame
	await process_frame
	_check(menu.find_child("UpdateButton", true, false) == null,
		"web menu hides the desktop updater tab")
	_check(menu.find_child("QuitButton", true, false) == null,
		"web menu hides the QUIT tab (a tab cannot close itself)")
	_check(menu.find_child("WebTag", true, false) != null,
		"web menu shows a WEB tag instead of QUIT")
	var web_notice: Label = menu.find_child("WebNotice", true, false) as Label
	_check(web_notice != null, "web menu owns a hint line")
	var multi: Button = menu.find_child("MultiplayerButton", true, false) as Button
	_check(multi != null, "web menu still offers MULTIPLAYER as a labelled entry")
	if multi != null:
		_check(multi.tooltip_text.to_upper().contains("DESKTOP"),
			"MULTIPLAYER explains that it needs the desktop build")
		menu.call("_on_multiplayer_pressed")
		_check(web_notice != null and web_notice.visible,
			"pressing MULTIPLAYER on web shows the desktop-only hint")
		_check(web_notice != null and web_notice.text.to_upper().contains("DESKTOP"),
			"the hint names the desktop download")
	_check(not _scene_loader_busy(),
		"the web multiplayer entry does not start a scene load")
	menu.queue_free()
	await process_frame
	OS.set_environment("CSGP_FORCE_WEB", "")


# --------------------------------------------------------------------------
# WS5-13 lobby presence gate


func _test_lobby_presence_helpers() -> void:
	print("--- WS5-13 lobby presence gate")
	var net: Node = root.get_node_or_null("/root/Network")
	_check(net != null, "Network autoload present")
	if net == null:
		return
	var old_host: bool = bool(net.get("is_host"))
	var old_client: bool = bool(net.get("is_client"))
	_check(bool(net.call("is_lobby_peer_present", 1)),
		"the host is always present/ready")
	net.set("lobby_presence", {77: true})
	_check(bool(net.call("is_lobby_peer_present", 77)),
		"a peer that reported into the lobby is present")
	_check(not bool(net.call("is_lobby_peer_present", 78)),
		"an unreported peer is not present (START gate blocks)")
	net.set("lobby_presence", {})
	# Offline: reporting presence is a harmless no-op (nothing to send to).
	net.set("is_host", false)
	net.set("is_client", false)
	net.call("set_lobby_presence", true)
	_check(not bool(net.get("_lobby_presence_sent")),
		"offline presence reporting is a safe no-op")
	net.set("is_host", old_host)
	net.set("is_client", old_client)


func _test_lobby_start_gate_ui() -> void:
	## The helper checks above cannot see a runtime SCRIPT ERROR, and the host
	## gate aborted at runtime once because of a typed-array assignment. This
	## exercises the real lobby scene in its host state and proves the gate path
	## runs to completion (the tooltip sentinel is the last statement's effect).
	print("--- WS5-13 lobby START gate UI")
	var lobby_script: GDScript = load("res://scripts/ui/lobby_menu.gd") as GDScript
	_check(lobby_script != null, "lobby script loads")
	if lobby_script == null:
		return
	_check(str(lobby_script.call("start_gate_text", "START RACE", 0, false))
			== "START RACE",
		"no away players keeps the normal START label")
	var one_away: String = str(lobby_script.call("start_gate_text", "START RACE", 1, false))
	_check(one_away.contains("WAITING FOR 1 PLAYER") and not one_away.contains("PLAYERS"),
		"one away player gets singular WAITING label (%s)" % one_away)
	var two_away: String = str(lobby_script.call("start_gate_text", "START RACE", 2, false))
	_check(two_away.contains("WAITING FOR 2 PLAYERS"),
		"two away players get the plural WAITING label (%s)" % two_away)
	var armed: String = str(lobby_script.call("start_gate_text", "START RACE", 2, true))
	_check(armed.contains("START ANYWAY"),
		"the deliberate second press shows START ANYWAY (%s)" % armed)

	var lobby: Control = (load(LOBBY_SCENE) as PackedScene).instantiate() as Control
	root.add_child(lobby)
	await process_frame
	await process_frame
	lobby.call("audit_room_state") ## host in-room state, same hook ui_layout_audit uses
	await process_frame
	var button: Button = lobby.get("_start_button") as Button
	_check(button != null and button.visible,
		"the host lobby shows the START button")
	if button != null:
		button.tooltip_text = "P2_SENTINEL"
		lobby.call("_refresh_start_gate")
		_check(button.tooltip_text == "",
			"the host START gate runs to completion (typed-array abort caught)")
		_check(button.text.begins_with("START"),
			"the host START label is restored when no peer is away (got '%s')" % button.text)
	lobby.queue_free()
	await process_frame


# --------------------------------------------------------------------------
# WS5-07 host disconnect overlay


func _test_host_lost_overlay() -> void:
	print("--- WS5-07 host disconnect overlay")
	var net: Node = root.get_node_or_null("/root/Network")
	_check(net != null and net.has_signal("match_host_lost"),
		"Network exposes the match-host-lost signal")
	if net == null or not net.has_signal("match_host_lost"):
		return
	var shell: Node = (load(PAUSE_MENU_SCENE) as PackedScene).instantiate()
	root.add_child(shell)
	await process_frame
	var pause: Control = shell.get_node_or_null("Root") as Control
	_check(pause != null, "pause menu scene instantiates")
	if pause == null:
		shell.queue_free()
		return
	net.emit_signal("match_host_lost", "The host left the match.")
	_check(bool(pause.get("_host_lost")),
		"the pause menu switches into the host-disconnected state")
	var title: Label = pause.find_child("Title", true, false) as Label
	_check(title != null and title.text == "HOST DISCONNECTED",
		"the overlay is titled HOST DISCONNECTED")
	var resume: Button = pause.find_child("ResumeButton", true, false) as Button
	_check(resume != null and not resume.visible,
		"the frozen match cannot be resumed behind the overlay")
	var quit: Button = pause.find_child("QuitToMenuButton", true, false) as Button
	_check(quit != null and quit.text == "MAIN MENU",
		"the overlay offers one clear exit back to the main menu")
	paused = false
	shell.queue_free()
	await process_frame


# --------------------------------------------------------------------------
# WS5-04 focus-loss auto-pause


func _test_focus_loss_pause() -> void:
	print("--- WS5-04 focus-loss auto-pause")
	var net: Node = root.get_node_or_null("/root/Network")
	var settings: Node = root.get_node_or_null("/root/GameSettings")
	_check(net != null and settings != null, "Network and GameSettings autoloads present")
	if net == null or settings == null:
		return
	var shell: Node = (load(PAUSE_MENU_SCENE) as PackedScene).instantiate()
	root.add_child(shell)
	await process_frame
	var pause: Control = shell.get_node_or_null("Root") as Control
	_check(pause != null, "pause menu scene instantiates")
	if pause == null:
		shell.queue_free()
		return
	# Simulate SOLO gameplay: the pause menu belongs to the live scene.
	var old_host: bool = bool(net.get("is_host"))
	var old_client: bool = bool(net.get("is_client"))
	var old_setting: bool = bool(settings.get("pause_on_focus_loss"))
	net.set("is_host", false)
	net.set("is_client", false)
	settings.set("pause_on_focus_loss", true)
	paused = false
	current_scene = shell
	root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await process_frame
	await process_frame
	_check(bool(pause.get("_is_open")), "focus loss opens the solo pause menu")
	_check(paused, "focus loss pauses the solo world")
	# The COMFORT setting opts out.
	pause.call("close")
	settings.set("pause_on_focus_loss", false)
	root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await process_frame
	await process_frame
	_check(not bool(pause.get("_is_open")),
		"the pause-on-focus-loss setting can disable the auto-pause")
	# Multiplayer must never auto-pause: the world keeps running for everyone.
	settings.set("pause_on_focus_loss", true)
	net.set("is_client", true)
	root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await process_frame
	await process_frame
	_check(not bool(pause.get("_is_open")),
		"multiplayer never auto-pauses on focus loss")
	net.set("is_client", false)
	# A scene load / transition must not be disturbed by a focus blip.
	var loader: Node = root.get_node_or_null("/root/SceneLoader")
	if loader != null:
		loader.call("begin_task", "LOADING", "test")
		root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		await process_frame
		await process_frame
		_check(not bool(pause.get("_is_open")),
			"a focus blip during a scene load does not open the pause menu")
		loader.call("end_task")
		await process_frame
	current_scene = null
	settings.set("pause_on_focus_loss", old_setting)
	net.set("is_host", old_host)
	net.set("is_client", old_client)
	paused = false
	shell.queue_free()
	await process_frame


# --------------------------------------------------------------------------
# WS5-01 same-scene rematch


func _scene_loader_busy() -> bool:
	## Autoload singletons are not global identifiers in `--script` mode, so the
	## regression suite resolves them through the root node like the other tools.
	var loader: Node = root.get_node_or_null("/root/SceneLoader")
	return loader != null and bool(loader.call("is_busy"))


func _wait_for_scene(path: String, timeout_ms: int) -> Node:
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var scene: Node = current_scene
		if scene != null and scene.scene_file_path == path \
				and not _scene_loader_busy():
			return scene
		await process_frame
	return null


func _test_rematch_reload() -> void:
	## The host's rematch RPC runs with call_local, so calling the shared handler
	## directly is exactly what `rpc("_net_restart_game", ...)` executes on the
	## host. Testing it session-less keeps the suite off the shared LAN discovery
	## port (two-process suites own that port) and still proves the guard/reload
	## contract the player-facing RACE AGAIN button depends on.
	print("--- WS5-01 same-scene rematch")
	var net: Node = root.get_node_or_null("/root/Network")
	_check(net != null, "Network autoload present")
	if net == null:
		return
	_check(net.has_method("_net_restart_game"),
		"the dedicated restart RPC exists")
	_check(net.has_method("_begin_game_common"),
		"begin/restart share one validated handler")
	var old_host: bool = bool(net.get("is_host"))
	var old_client: bool = bool(net.get("is_client"))
	var old_in_game: bool = bool(net.get("in_game"))
	var old_room_state: String = str(net.get("room_state"))
	# Host the sandbox locally without an ENet peer: the scene-load half of the
	# start path (and the retry guard) is what the rematch bug lived in.
	net.set("is_host", true)
	net.set("is_client", false)
	net.set("in_game", false)

	# First start: the scene must actually replace the current screen.
	net.call("_begin_game_common", SANDBOX_SCENE, "sandbox", false, 0, 0, false)
	var first: Node = await _wait_for_scene(SANDBOX_SCENE, 30000)
	_check(first != null, "rematch: first sandbox start loaded")
	if first == null:
		_restore_network(net, old_host, old_client, old_in_game, old_room_state)
		return
	var first_id: int = first.get_instance_id()
	_check(net.get("in_game") == true, "rematch: session is in game after a start")

	# A repeated plain begin is the retry path: it must NOT reload the scene.
	net.call("_begin_game_common", SANDBOX_SCENE, "sandbox", false, 0, 0, false)
	for _frame in 20:
		await process_frame
	_check(current_scene != null
			and current_scene.get_instance_id() == first_id,
		"a plain repeated start keeps the scene instance (retry guard intact)")
	_check(str(net.get("_restart_scene_path")) == "",
		"a plain repeated start is not marked as a restart")

	# The rematch handler must force a fresh instance of the same scene.
	net.call("_net_restart_game", SANDBOX_SCENE, "sandbox", false, 0, 0)
	_check(str(net.get("_restart_scene_path")) == SANDBOX_SCENE,
		"the host marks a same-scene rematch as a pending restart")
	var second: Node = await _wait_for_scene(SANDBOX_SCENE, 30000)
	_check(second != null, "rematch: the forced reload completed")
	_check(second != null and second.get_instance_id() != first_id,
		"rematch: the live scene instance was replaced")
	_check(str(net.get("_restart_scene_path")) == "",
		"the restart marker clears once the new scene is ready")
	_check(net.get("in_game") == true, "rematch: the room is in game")
	# Room state is what a room browser / relay heartbeat advertises.
	net.call("set_room_state", "playing")
	_check(str(net.get("room_state")) == "playing",
		"rematch: the room state can return to playing")

	_restore_network(net, old_host, old_client, old_in_game, old_room_state)


func _restore_network(net: Node, host: bool, client: bool, in_game: bool,
		room_state: String) -> void:
	net.set("is_host", host)
	net.set("is_client", client)
	net.set("in_game", in_game)
	net.set("room_state", room_state)
	net.set("_restart_scene_path", "")
	net.set("_scene_load_path", "")
	paused = false
