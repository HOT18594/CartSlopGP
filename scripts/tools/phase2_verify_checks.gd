extends SceneTree
## Phase-2 verification checks (p2-verify): pure, headless regression assertions
## for the second-pass fixes that otherwise only have an end-to-end path.
##
## Run from the workspace root:
##   Godot_v4.7.2-stable_win64_console.exe --headless --path godot_project \
##       --script res://scripts/tools/phase2_verify_checks.gd
##
## Exit code = number of failed checks. Nothing here boots a 3D scene.
##
## The atomic-save checks use a scratch directory **inside the workspace**
## (`_audit/logs/p2-verify/tmp/`), not `user://`: on this dev machine spawned
## Godot processes can only write inside the workspace (the documented
## `user://` read-only noise in AGENTS.md), and the save helper is path-agnostic
## so the tmp->rename logic is the same code either way. Files are cleaned up.

const LobbyReactions := preload("res://scripts/ui/lobby_reactions.gd")

var _failures: int = 0
var _checks: int = 0
var _test_dir: String = ""


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	_checks += 1
	print("%s  %s" % ["OK  " if condition else "FAIL", label])
	if not condition:
		_failures += 1
		push_error("P2_VERIFY: " + label)


func _run() -> void:
	# Autoload identifiers are not available at --script parse time, so scripts
	# that reference them are loaded at runtime and called on an instance (the
	# same pattern the shipped smoke tests use).
	var net: Node = root.get_node_or_null("Network")
	var gs: Node = root.get_node_or_null("GameSettings")
	var race_script: GDScript = load("res://scripts/minigames/grass_race.gd") as GDScript
	var menu_script: GDScript = load("res://scripts/ui/main_menu.gd") as GDScript
	var race: Node = race_script.new() if race_script != null else null
	var menu: Control = menu_script.new() if menu_script != null else null
	_test_dir = ProjectSettings.globalize_path("res://").simplify_path() \
		.path_join("../_audit/logs/p2-verify/tmp")
	DirAccess.make_dir_recursive_absolute(_test_dir)

	_check(net != null and gs != null, "autoloads: Network and GameSettings are live")
	if net != null and gs != null and race != null:
		_check_finish_ordering(race)
		_check_atomic_settings(gs)
		_check_reaction_contract(net)
	if menu != null:
		_check_web_build_helper(menu)
	_check_scoreboard_action()
	_cleanup_settings_test()
	if race != null:
		race.free()
	if menu != null:
		menu.free()
	print("P2_VERIFY: %d checks, %d failure(s)" % [_checks, _failures])
	print("P2_VERIFY: %s" % ("PASS" if _failures == 0 else "FAIL"))
	quit(0 if _failures == 0 else _failures)


# --------------------------------------------------------------------------
# WS5-02 close-finish ordering: the compensated crossing stamp must not depend
# on the arrival order of the reliable reports and must stay clamped.

func _check_finish_ordering(race: Node) -> void:
	# Two close finishes (4 ms apart) whose reports were processed in the
	# opposite order to the actual crossing: ordering must follow the reported
	# race clock, not packet arrival.
	var a: float = race.compensated_finish_time(61.300, 40.0, 62.00, -1.0)
	var b: float = race.compensated_finish_time(61.304, 40.0, 61.90, -1.0)
	_check(a < b, "finish order: reported clock beats reversed report arrival order")
	_check(is_equal_approx(a, 61.340), "finish order: one-way delay is added once (61.340)")
	_check(is_equal_approx(a, race.compensated_finish_time(61.300, 40.0, 62.00, -1.0)),
		"finish order: compensation is deterministic")
	# A report cannot beat the progress-latch observation by more than the slack
	# (a modified client must not be able to claim an impossible crossing).
	var slack: float = float(race.FINISH_PROGRESS_SLACK)
	var clamped_early: float = race.compensated_finish_time(50.0, 10.0, 70.0, 59.0)
	_check(clamped_early >= 59.0 - slack - 0.0001 and clamped_early <= 59.0 + slack + 0.0001,
		"finish order: provisional progress latch clamps an implausibly early report")
	# Without a provisional latch the report can never claim the future.
	var far: float = race.compensated_finish_time(99.0, 1000.0, 60.0, -1.0)
	_check(far <= 60.0 + 0.0001, "finish order: report time is bounded by the host clock")
	_check(far >= 0.0, "finish order: finish time is never negative")
	# A backwards/zero clock is sanitised, not propagated as infinity/NaN.
	var zero: float = race.compensated_finish_time(-5.0, -50.0, 12.0, -1.0)
	_check(is_finite(zero) and zero >= 0.0, "finish order: negative reported time sanitises")


# --------------------------------------------------------------------------
# WS5-06 atomic settings save: crash windows must never leave a partial live
# file, and a completed staged save must be adopted on the next boot.

func _settings_path(name: String) -> String:
	return _test_dir.path_join(name)


func _cleanup_settings_test() -> void:
	if _test_dir == "":
		return
	for name: String in ["p2_verify_settings.cfg", "p2_verify_settings.cfg.tmp"]:
		var path: String = _settings_path(name)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _write_config(path: String, value: int) -> Error:
	var config := ConfigFile.new()
	config.set_value("test", "value", value)
	return config.save(path)


func _read_value(path: String) -> int:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return -999
	return int(config.get_value("test", "value", -999))


func _check_atomic_settings(gs: Node) -> void:
	var final_path: String = _settings_path("p2_verify_settings.cfg")
	var tmp_path: String = _settings_path("p2_verify_settings.cfg.tmp")
	_cleanup_settings_test()
	# 1. A normal save commits through the staged file.
	var config := ConfigFile.new()
	config.set_value("test", "value", 42)
	var error: Error = gs.commit_config_atomic(config, final_path, tmp_path)
	_check(error == OK, "atomic save: commit_config_atomic returns OK")
	_check(FileAccess.file_exists(final_path), "atomic save: live file exists after save")
	_check(not FileAccess.file_exists(tmp_path), "atomic save: staging file is gone after save")
	_check(_read_value(final_path) == 42, "atomic save: committed value round-trips")
	# 2. A previous complete save is not lost when a new staged write is cut off
	# before the rename (simulate: old live file + stale staged copy).
	_write_config(tmp_path, 7)
	var adopted: bool = gs.recover_staged_settings(final_path, tmp_path)
	_check(not adopted, "atomic save: stale staged copy is discarded when the live file exists")
	_check(_read_value(final_path) == 42, "atomic save: live file survives a lost staged write")
	# 3. Crash between "staged write complete" and "rename": only the temp exists
	# on the next boot and must be adopted, never silently discarded.
	_cleanup_settings_test()
	var staged_error: Error = _write_config(tmp_path, 77)
	_check(staged_error == OK, "atomic save: staged config can be written for the recovery test")
	var recovered: bool = gs.recover_staged_settings(final_path, tmp_path)
	_check(recovered, "atomic save: completed staged save is adopted on boot")
	_check(FileAccess.file_exists(final_path) and not FileAccess.file_exists(tmp_path),
		"atomic save: recovery leaves exactly the live file")
	_check(_read_value(final_path) == 77, "atomic save: recovered value is the staged value")
	_cleanup_settings_test()


# --------------------------------------------------------------------------
# WS5-05 scoreboard control: the InputMap action exists for keyboard and pad.

func _check_scoreboard_action() -> void:
	var has_action: bool = InputMap.has_action(&"scoreboard")
	_check(has_action, "scoreboard: InputMap action exists")
	if not has_action:
		return
	var has_key: bool = false
	var has_pad: bool = false
	for event: InputEvent in InputMap.action_get_events(&"scoreboard"):
		if event is InputEventKey:
			var key := event as InputEventKey
			# InputSetup._key() binds the physical keycode; accept either field.
			if key.keycode == KEY_TAB or key.physical_keycode == KEY_TAB:
				has_key = true
		if event is InputEventJoypadButton \
				and (event as InputEventJoypadButton).button_index == JOY_BUTTON_BACK:
			has_pad = true
	_check(has_key, "scoreboard: Tab is bound")
	_check(has_pad, "scoreboard: gamepad Select/View is bound")


# --------------------------------------------------------------------------
# WS4 lobby reactions: catalog/limiter contract (the two-process sync path is
# covered separately by the reaction e2e run).

func _check_reaction_contract(net: Node) -> void:
	_check(net.sanitize_reaction_id("GG") == "gg", "reaction: ids are lowercased")
	_check(net.sanitize_reaction_id("bad id!") == "", "reaction: invalid ids are dropped")
	_check(net.sanitize_reaction_id("x".repeat(32)) == "",
		"reaction: over-length ids are dropped")
	_check(net.sanitize_reaction_id("gg_2") == "gg_2",
		"reaction: lowercase/digit/underscore tokens are allowed")
	var pending: Array = []
	LobbyReactions.push_pending(pending, "gg", 1000)
	_check(pending.size() == 1, "reaction: a press is buffered while cooling down")
	var now: int = 1000 + LobbyReactions.COOLDOWN_MS
	_check(not LobbyReactions.can_send(now - 1, 1000),
		"reaction: client cooldown blocks an instant re-send")
	_check(LobbyReactions.next_pending(pending, now) == "gg",
		"reaction: a buffered press is emitted after the cooldown")
	_check(LobbyReactions.can_send(5, 1000), "reaction: a backwards clock is treated as ready")


# --------------------------------------------------------------------------
# WS5-03 web dead-end guards: the forced-web helper the menu uses in tests.

func _check_web_build_helper(menu: Control) -> void:
	var previous: String = OS.get_environment(menu.WEB_FORCE_ENV)
	_check(menu.is_web_build() == OS.has_feature("web"),
		"web guard: default helper matches the real platform feature")
	OS.set_environment(menu.WEB_FORCE_ENV, "1")
	_check(menu.is_web_build(), "web guard: CSGP_FORCE_WEB=1 forces the web variant")
	if previous == "":
		OS.set_environment(menu.WEB_FORCE_ENV, "")
	else:
		OS.set_environment(menu.WEB_FORCE_ENV, previous)
	_check(not menu.is_web_build() or OS.has_feature("web"),
		"web guard: helper returns to the platform value")
