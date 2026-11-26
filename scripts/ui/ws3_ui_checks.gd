extends SceneTree
## WS3 Phase-3 headless acceptance checks (0.8.7).
##
## Covers the three visible deliverables of this workstream without a window:
##   1. END SCREEN host/non-host action sets — every mode's host card keeps its
##      navigation, every multiplayer client card resolves to exactly
##      [LEAVE LOBBY] + the animated "Waiting for host..." status, and the
##      shared dark-slanted Cancel/Leave confirm gate works (Cancel never
##      leaves, Leave runs the callback exactly once, host MAIN MENU is gated,
##      solo MAIN MENU is not). Authoritative standings rows are compared
##      host-vs-client to prove the data contract is untouched.
##   2. EMOTE overlay — strict text-only rendering: zero child nodes (so no
##      left bar, no parallelogram plate, no background plate), randomized
##      spawn positions inside the safe margins, bounded upward/wiggle motion,
##      reduced-motion static behaviour, lifetime expiry and invalid-id reject.
##   3. MAP PREVIEW — black-slanted geometry (real skew + parallelogram), idle
##      motion that actually moves but stays inside its declared bounds, hover
##      reaction, reduced-motion freeze, slanted fallback + texture paths.
##
## Optional live-scene phase (CART_WS3_LIVE_MODES=1) boots the real mode scenes
## and forces a multiplayer-client result card, proving all four mode scripts
## route through the shared action-set API (the slow 3D boot is why it is opt-in).
## The in-room lobby phase is always on (Phase B integration is final): it proves
## lobby_menu.gd uses the text-only LobbyEmoteOverlay + LobbyMapPreview modules,
## keeps WS4's autonomous hover-independent backdrop and roster, and that the
## confirm gate's ESC/Pause isolation (WS5P3-14) is real.
##
## Exit code = number of failures. Run from the workspace root:
##   downloads/godot_editor/Godot_v4.7.2-stable_win64_console.exe --headless \
##     --path godot_project --script res://scripts/ui/ws3_ui_checks.gd

const LobbyReactions := preload("res://scripts/ui/lobby_reactions.gd")
const LobbyEmoteOverlay := preload("res://scripts/ui/lobby_emote_overlay.gd")
const LobbyMapPreview := preload("res://scripts/ui/lobby_map_preview.gd")
const RESULT_SCREEN_SCRIPT := "res://scripts/ui/result_screen.gd"
const LOBBY_SCENE := "res://scenes/ui/lobby_menu.tscn"
const NETWORK_SCRIPT := "res://scripts/net/network.gd"
const PREVIEW_TEXTURE := "res://assets/ui/art/preview_stadium.png"
const DESIGN_SIZE := Vector2(1280.0, 720.0)
const WAITING_BASE := "Waiting for host"
const HOST_ONLY_LABELS: Array[String] = [
	"BACK TO LOBBY", "MAIN MENU", "RACE AGAIN", "PLAY AGAIN", "BACK TO MODES",
]
const MODE_SCRIPTS: Array[String] = [
	"res://scripts/minigames/grass_race.gd",
	"res://scripts/minigames/cargo_rush.gd",
	"res://scripts/minigames/knockout.gd",
	"res://scripts/minigames/bomb_tag.gd",
]
const LIVE_CASES: Array[Dictionary] = [
	{"id": "cargo_rush", "path": "res://scenes/minigames/cargo_rush.tscn",
		"method": "_build_result_card", "primary": "PLAY AGAIN"},
	{"id": "knockout", "path": "res://scenes/minigames/knockout.tscn",
		"method": "_build_result_card", "primary": "PLAY AGAIN"},
	{"id": "bomb_tag", "path": "res://scenes/minigames/bomb_tag.tscn",
		"method": "_build_result_card", "primary": "PLAY AGAIN"},
]

var _failures: int = 0
var _checks: int = 0
var _result_script: GDScript = null


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	print("%s  %s" % ["OK  " if condition else "FAIL", message])
	if not condition:
		_failures += 1
		push_error("WS3_CHECKS: " + message)


func _new_result_helper() -> RefCounted:
	## Loaded at runtime, not `preload`ed: a tool main-loop script is compiled
	## before autoload globals exist, and result_screen.gd's dialog uses them.
	if _result_script == null:
		_result_script = load(RESULT_SCREEN_SCRIPT) as GDScript
	if _result_script == null:
		return null
	return _result_script.new() as RefCounted


func _run() -> void:
	_check(_new_result_helper() != null,
		"result_screen.gd loads as the shared end-screen builder")
	print("--- result action sets (host vs non-host)")
	await _test_result_action_sets()
	print("--- leave / main-menu confirm gate")
	await _test_confirm_gate()
	print("--- confirm gate ESC / Pause isolation (WS5P3-14)")
	await _test_pause_gate_isolation()
	print("--- waiting-for-host animation")
	await _test_waiting_animation()
	print("--- text-only emote overlay")
	await _test_emote_overlay()
	print("--- slanted map preview")
	await _test_map_preview()
	print("--- reaction sync contract (unchanged)")
	await _test_sync_contract()
	print("--- mode script wiring")
	_test_mode_script_wiring()
	print("--- lobby integration")
	await _test_lobby_integration()
	if OS.get_environment("CART_WS3_LIVE_MODES") == "1":
		print("--- live mode result cards (multiplayer client)")
		await _test_live_mode_cards()
	print("WS3_CHECKS: %d checks, %d failures" % [_checks, _failures])
	print("WS3_CHECKS: %s" % ("PASS" if _failures == 0 else "FAIL"))
	quit(0 if _failures == 0 else _failures)


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------


func _game_settings() -> Node:
	return root.get_node_or_null("GameSettings")


func _set_reduce_motion(value: bool) -> void:
	var settings: Node = _game_settings()
	if settings != null:
		settings.set("reduce_motion", value)


func _make_host(size: Vector2 = DESIGN_SIZE) -> Control:
	var host := Control.new()
	host.size = size
	root.add_child(host)
	return host


func _audit_card(helper: RefCounted, host: Control, mode: String,
		multiplayer: bool, is_host: bool) -> Dictionary:
	return helper.call("build_audit_card", host, {
		"mode": mode, "multiplayer": multiplayer, "is_host": is_host,
	}) as Dictionary


func _free_card(host: Control, card: Dictionary) -> void:
	var card_root: Node = card.get("root") as Node
	if card_root != null and is_instance_valid(card_root):
		host.remove_child(card_root)
		card_root.free()


func _row_texts(card: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var rows: VBoxContainer = card.get("standings_rows") as VBoxContainer
	if rows == null:
		return out
	for row: Node in rows.get_children():
		var labels: Variant = row.get_meta("labels", [])
		if labels is Array:
			for label: Variant in labels as Array:
				if label is Label:
					out.append((label as Label).text)
	return out


func _button_texts(node: Node, out: Array[String]) -> void:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	if node is Button:
		out.append((node as Button).text)
	for child: Node in node.get_children():
		_button_texts(child, out)


func _all_rects_inside(rects: Array, safe: Rect2, slack: float = 0.75) -> bool:
	var grown: Rect2 = safe.grow(slack)
	for raw: Variant in rects:
		if not grown.encloses(raw as Rect2):
			return false
	return true


func _points_inside(points: PackedVector2Array, bounds: Rect2,
		slack: float = 1.5) -> bool:
	var grown: Rect2 = bounds.grow(slack)
	for point: Vector2 in points:
		if not grown.has_point(point):
			return false
	return true


# --------------------------------------------------------------------------
# 1. result action sets
# --------------------------------------------------------------------------


func _test_result_action_sets() -> void:
	var helper: RefCounted = _new_result_helper()
	if helper == null:
		_check(false, "result_screen.gd helper unavailable")
		return
	var host: Control = _make_host()
	var modes: Array[String] = ["racing", "cargo_rush", "knockout", "bomb_tag"]
	for mode: String in modes:
		var primary: String = "PLAY AGAIN" if mode != "racing" else "RACE AGAIN"
		# --- solo -----------------------------------------------------------
		var solo_card: Dictionary = _audit_card(helper, host, mode, false, false)
		await process_frame
		var solo_actions: Array = helper.call("action_set", solo_card)
		_check(solo_actions == [primary, "BACK TO MODES", "MAIN MENU"],
			"%s solo action set changed: %s" % [mode, str(solo_actions)])
		# --- multiplayer host ----------------------------------------------
		var host_card: Dictionary = _audit_card(helper, host, mode, true, true)
		await process_frame
		var host_actions: Array = helper.call("action_set", host_card)
		_check(host_actions == [primary, "BACK TO LOBBY", "MAIN MENU"],
			"%s host action set changed: %s" % [mode, str(host_actions)])
		_check(str(helper.call("waiting_text", host_card)) == "",
			"%s host card must not show the client waiting status" % mode)
		# --- multiplayer non-host -------------------------------------------
		var client_card: Dictionary = _audit_card(helper, host, mode, true, false)
		await process_frame
		var client_actions: Array = helper.call("action_set", client_card)
		_check(client_actions == ["LEAVE LOBBY"],
			"%s client action set must be [LEAVE LOBBY], got %s"
				% [mode, str(client_actions)])
		var waiting: String = str(helper.call("waiting_text", client_card))
		_check(waiting.begins_with(WAITING_BASE),
			"%s client waiting status missing (got '%s')" % [mode, waiting])
		_check(client_card.get("primary") == null
			and client_card.get("secondary") == null
			and client_card.get("tertiary") == null,
			"%s client card must not build host-only buttons" % mode)
		var texts: Array[String] = []
		_button_texts(client_card["root"] as Node, texts)
		var leaked: Array[String] = []
		for label: String in texts:
			if HOST_ONLY_LABELS.has(label):
				leaked.append(label)
		_check(leaked.is_empty(),
			"%s client card leaked host-only labels: %s"
				% [mode, str(leaked)])
		# Authoritative standings data must be identical for host and client.
		_check(_row_texts(host_card) == _row_texts(client_card),
			"%s host/client standings rows differ" % mode)
		_free_card(host, solo_card)
		_free_card(host, host_card)
		_free_card(host, client_card)
		await process_frame
	host.queue_free()
	await process_frame


# --------------------------------------------------------------------------
# 2. confirm gate
# --------------------------------------------------------------------------


func _test_confirm_gate() -> void:
	var helper: RefCounted = _new_result_helper()
	if helper == null:
		_check(false, "result_screen.gd helper unavailable")
		return
	var host: Control = _make_host()
	# --- client LEAVE LOBBY gate -------------------------------------------
	var leave_calls: Array = []
	var client_card: Dictionary = helper.call("build", host, {
		"name": "ClientCard",
		"title": "RACE COMPLETE",
		"subtitle": "TEST",
		"multiplayer": true,
		"is_host": false,
		"primary_text": "RACE AGAIN",
		"secondary_text": "BACK TO LOBBY",
		"tertiary_text": "MAIN MENU",
		"on_leave": func() -> void: leave_calls.append("leave"),
		"on_tertiary": func() -> void: leave_calls.append("menu"),
		"confirm_main_menu": true,
		"standings_columns": [],
	}) as Dictionary
	helper.call("present", client_card)
	await process_frame
	_check(helper.call("action_set", client_card) == ["LEAVE LOBBY"],
		"client card must drop host-only actions even when authored")
	_check((client_card["leave"] as Button).text == "LEAVE LOBBY",
		"client leave action defaults to the LEAVE LOBBY label")
	_check(not bool(helper.call("confirm_visible", client_card)),
		"confirm gate starts closed")
	_check((client_card["confirm"] as Node).has_method("request_close"),
		"confirm dialog exposes request_close (MenuNav ESC path)")
	helper.call("request_leave", client_card)
	await process_frame
	var state: Dictionary = helper.call("confirm_state", client_card) as Dictionary
	_check(bool(state.get("visible", false)),
		"LEAVE LOBBY opens the dark-slanted confirm gate")
	_check(str(state.get("question", "")) == "Leave lobby and return to Main Menu?",
		"confirm question copy is wrong: '%s'" % state.get("question"))
	_check((state.get("buttons", []) as Array) == ["Cancel", "Leave"],
		"confirm buttons must be [Cancel, Leave], got %s"
			% str(state.get("buttons")))
	_check(leave_calls.is_empty(),
		"opening the gate must not leave immediately")
	var outside: Array[String] = helper.call("audit_outside", client_card,
		DESIGN_SIZE) as Array[String]
	_check(outside.is_empty(),
		"open confirm dialog escapes the 1280x720 design box: %s"
			% str(outside))
	helper.call("confirm_cancel", client_card)
	await process_frame
	_check(not bool(helper.call("confirm_visible", client_card)),
		"Cancel closes the gate")
	_check(leave_calls.is_empty(), "Cancel must not leave the lobby")
	helper.call("request_leave", client_card)
	await process_frame
	_check(bool(helper.call("confirm_visible", client_card)),
		"gate re-opens on a second attempt")
	helper.call("confirm_accept", client_card)
	await process_frame
	_check(not bool(helper.call("confirm_visible", client_card)),
		"Leave closes the gate")
	_check(leave_calls == ["leave"],
		"Leave runs the leave callback exactly once (got %s)" % str(leave_calls))
	# ESC equivalent through the MenuNav fallback hook.
	helper.call("request_leave", client_card)
	await process_frame
	(client_card["confirm"] as Node).call("request_close")
	await process_frame
	_check(not bool(helper.call("confirm_visible", client_card)),
		"request_close (ESC path) cancels the gate")
	_free_card(host, client_card)
	await process_frame

	# --- host MAIN MENU gate (live session) --------------------------------
	var menu_calls: Array = []
	var host_card: Dictionary = helper.call("build", host, {
		"name": "HostCard",
		"title": "RACE COMPLETE",
		"subtitle": "TEST",
		"multiplayer": true,
		"is_host": true,
		"primary_text": "RACE AGAIN",
		"secondary_text": "BACK TO LOBBY",
		"tertiary_text": "MAIN MENU",
		"on_primary": Callable(),
		"on_secondary": Callable(),
		"on_tertiary": func() -> void: menu_calls.append("menu"),
		"confirm_main_menu": true,
		"standings_columns": [],
	}) as Dictionary
	helper.call("present", host_card)
	await process_frame
	(host_card["tertiary"] as Button).pressed.emit()
	await process_frame
	_check(bool(helper.call("confirm_visible", host_card)),
		"host MAIN MENU in a live session opens the confirm gate")
	_check(menu_calls.is_empty(), "host MAIN MENU must wait for confirmation")
	helper.call("confirm_accept", host_card)
	await process_frame
	_check(menu_calls == ["menu"],
		"confirmed host MAIN MENU runs its callback once (got %s)"
			% str(menu_calls))
	# BACK TO LOBBY is NOT gated: only leaving the session is destructive.
	var back_calls: Array = []
	var back_card: Dictionary = helper.call("build", host, {
		"name": "HostBackCard",
		"title": "RACE COMPLETE",
		"subtitle": "TEST",
		"multiplayer": true,
		"is_host": true,
		"primary_text": "",
		"secondary_text": "BACK TO LOBBY",
		"on_secondary": func() -> void: back_calls.append("back"),
		"tertiary_text": "",
		"confirm_main_menu": true,
		"standings_columns": [],
	}) as Dictionary
	helper.call("present", back_card)
	await process_frame
	(back_card["secondary"] as Button).pressed.emit()
	await process_frame
	_check(back_calls == ["back"] and not bool(
		helper.call("confirm_visible", back_card)),
		"BACK TO LOBBY stays ungated for the host")
	_free_card(host, back_card)
	await process_frame
	_free_card(host, host_card)
	await process_frame

	# --- solo MAIN MENU is NOT gated ---------------------------------------
	var solo_calls: Array = []
	var solo_card: Dictionary = helper.call("build", host, {
		"name": "SoloCard",
		"title": "RACE COMPLETE",
		"subtitle": "TEST",
		"multiplayer": false,
		"is_host": false,
		"primary_text": "RACE AGAIN",
		"secondary_text": "BACK TO MODES",
		"tertiary_text": "MAIN MENU",
		"on_primary": Callable(),
		"on_secondary": Callable(),
		"on_tertiary": func() -> void: solo_calls.append("menu"),
		"confirm_main_menu": false,
		"standings_columns": [],
	}) as Dictionary
	helper.call("present", solo_card)
	await process_frame
	(solo_card["tertiary"] as Button).pressed.emit()
	await process_frame
	_check(solo_calls == ["menu"], "solo MAIN MENU is not gated")
	_check(not bool(helper.call("confirm_visible", solo_card)),
		"solo card never opens the confirm gate")
	_free_card(host, solo_card)
	host.queue_free()
	await process_frame


# --------------------------------------------------------------------------
# 2b. WS5P3-14: confirm gate owns ESC — PauseMenu can never open behind it
# --------------------------------------------------------------------------


func _test_pause_gate_isolation() -> void:
	var helper: RefCounted = _new_result_helper()
	if helper == null:
		_check(false, "result_screen.gd helper unavailable")
		return
	# A real PauseMenu instance under a controlled current_scene, exactly like a
	# match scene: result card and pause menu are siblings in the scene.
	var scene := Control.new()
	scene.name = "Ws3PauseGateScene"
	scene.size = DESIGN_SIZE
	root.add_child(scene)
	current_scene = scene
	var pause_scene: PackedScene = load("res://scenes/ui/pause_menu.tscn") \
		as PackedScene
	if pause_scene == null:
		_check(false, "pause_menu.tscn missing")
		current_scene = null
		scene.queue_free()
		await process_frame
		return
	var pause_layer: Node = pause_scene.instantiate()
	pause_layer.name = "PauseMenu"
	scene.add_child(pause_layer)
	await process_frame
	await process_frame
	var pause_root: Node = scene.get_node_or_null("PauseMenu/Root")
	_check(pause_root != null,
		"pause menu Control resolves (PauseMenu/Root) for the ESC isolation test")
	if pause_root == null:
		current_scene = null
		scene.queue_free()
		await process_frame
		return
	_check(pause_root.has_method("set_input_suspended")
		and pause_root.has_method("is_input_suspended"),
		"pause_menu.gd exposes the set_input_suspended / is_input_suspended API")
	var card_host := Control.new()
	card_host.name = "CardHost"
	card_host.size = DESIGN_SIZE
	scene.add_child(card_host)
	var leave_calls: Array = []
	var card: Dictionary = helper.call("build", card_host, {
		"name": "PauseGateClientCard",
		"title": "RACE COMPLETE",
		"subtitle": "TEST",
		"multiplayer": true,
		"is_host": false,
		"primary_text": "RACE AGAIN",
		"secondary_text": "BACK TO LOBBY",
		"tertiary_text": "MAIN MENU",
		"on_leave": func() -> void: leave_calls.append("leave"),
		"standings_columns": [],
	}) as Dictionary
	helper.call("present", card)
	await process_frame
	helper.call("request_leave", card)
	await process_frame
	await process_frame
	_check(bool(helper.call("confirm_visible", card)),
		"confirm gate opens for the ESC isolation test")
	var iso: Dictionary = helper.call("pause_isolation", card) as Dictionary
	_check(bool(iso.get("resolved", false)),
		"confirm gate resolved the scene PauseMenu/Root node")
	_check(not bool(iso.get("processing", true)),
		"confirm gate disabled PauseMenu unhandled input")
	_check(bool(iso.get("api_suspended", false)),
		"confirm gate engaged PauseMenu.set_input_suspended(true)")
	# 1. A direct ESC to the pause root must be refused while the gate is open,
	#    even though the node still exists and is fully initialised.
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	pause_root.call("_unhandled_input", esc)
	await process_frame
	_check(not bool(pause_root.get("_is_open")),
		"ESC cannot OPEN PAUSE behind the confirm gate (WS5P3-14)")
	# 2. The same ESC through the real viewport dispatch cancels the dialog and
	#    still never opens Pause.
	root.push_input(esc)
	await process_frame
	await process_frame
	_check(not bool(helper.call("confirm_visible", card)),
		"ESC cancels the confirm dialog through normal input dispatch")
	_check(not bool(pause_root.get("_is_open")),
		"ESC through the viewport never opens Pause behind the gate")
	_check(leave_calls.is_empty(), "ESC-cancelled gate must not leave the lobby")
	var after: Dictionary = helper.call("pause_isolation", card) as Dictionary
	_check(bool(after.get("processing", false)),
		"confirm gate restored PauseMenu unhandled input on close")
	_check(not bool(after.get("api_suspended", true)),
		"confirm gate released PauseMenu.set_input_suspended on close")
	# 3. Positive control: with the gate closed the same ESC does open Pause.
	pause_root.call("_unhandled_input", esc)
	await process_frame
	_check(bool(pause_root.get("_is_open")),
		"ESC opens Pause again once the confirm gate is closed")
	if bool(pause_root.get("_is_open")):
		pause_root.call("close")
	await process_frame
	# 4. API unit proof: suspension refuses ESC even if unhandled processing was
	#    re-enabled by something else, so the isolation is not dispatch-order luck.
	pause_root.call("set_input_suspended", true)
	pause_root.set_process_unhandled_input(true)
	pause_root.call("_unhandled_input", esc)
	await process_frame
	_check(not bool(pause_root.get("_is_open")),
		"set_input_suspended(true) blocks ESC independent of the processing flag")
	pause_root.call("set_input_suspended", false)
	_check(not bool(pause_root.call("is_input_suspended")),
		"set_input_suspended(false) clears the ESC suspension")
	current_scene = null
	scene.queue_free()
	await process_frame
	await process_frame


# --------------------------------------------------------------------------
# 3. waiting-for-host dots
# --------------------------------------------------------------------------


func _test_waiting_animation() -> void:
	var helper: RefCounted = _new_result_helper()
	if helper == null:
		_check(false, "result_screen.gd helper unavailable")
		return
	var host: Control = _make_host()
	var card: Dictionary = _audit_card(helper, host, "racing", true, false)
	var first: String = str(helper.call("waiting_text", card))
	_check(first.begins_with(WAITING_BASE),
		"waiting text starts with '%s' (got '%s')" % [WAITING_BASE, first])
	var timer: Node = (card["root"] as Node).get_node_or_null("WaitingDotsTimer")
	_check(timer != null, "waiting dots are driven by a timer")
	var seen: Dictionary = {}
	for _sample in 14:
		await create_timer(0.11).timeout
		var text: String = str(helper.call("waiting_text", card))
		_check_silent(text.begins_with(WAITING_BASE),
			"waiting sample lost its label: '%s'" % text)
		var dots: int = text.length() - WAITING_BASE.length()
		seen[dots] = true
	_check(seen.size() >= 2,
		"waiting dots animate through multiple states (saw %s)"
			% str(seen.keys()))
	var clean: bool = true
	for dots: int in seen.keys():
		if dots < 1 or dots > 3:
			clean = false
	_check(clean, "waiting dots stay within 1..3 (saw %s)" % str(seen.keys()))
	_free_card(host, card)
	await process_frame

	# Reduce Motion: a static "Waiting for host..." and no timer.
	_set_reduce_motion(true)
	var reduced_card: Dictionary = _audit_card(helper, host, "racing", true, false)
	var reduced_text: String = str(helper.call("waiting_text", reduced_card))
	_check(reduced_text == WAITING_BASE + "...",
		"reduce-motion waiting text is static with three dots (got '%s')"
			% reduced_text)
	_check((reduced_card["root"] as Node).get_node_or_null(
		"WaitingDotsTimer") == null,
		"reduce-motion waiting status starts no dots timer")
	await create_timer(0.7).timeout
	_check(str(helper.call("waiting_text", reduced_card)) == reduced_text,
		"reduce-motion waiting text does not animate")
	_set_reduce_motion(false)
	_free_card(host, reduced_card)
	host.queue_free()
	await process_frame


func _check_silent(condition: bool, message: String) -> void:
	## For per-sample assertions: count a failure once without spamming OK lines.
	if not condition:
		_check(false, message)


# --------------------------------------------------------------------------
# 4. text-only emote overlay
# --------------------------------------------------------------------------


func _test_emote_overlay() -> void:
	var host: Control = _make_host(Vector2(900.0, 500.0))
	var overlay: Control = LobbyEmoteOverlay.new() as Control
	overlay.name = "EmoteOverlay"
	overlay.size = Vector2(900.0, 500.0)
	host.add_child(overlay)
	await process_frame
	# Strict spec: the renderer owns NO chrome at all. Zero children means no
	# left bar, no parallelogram plate and no background container.
	_check(overlay.get_child_count() == 0,
		"emote overlay owns zero child nodes (no bar/background chrome)")
	_check_source_is_text_only()
	overlay.call("set_spawn_seed", 424242)
	var ids: Array[String] = []
	for entry: Dictionary in LobbyReactions.REACTIONS:
		ids.append(str(entry.get("id", "")))
	for index in 6:
		var pushed: bool = bool(overlay.call("push", index + 2,
			ids[index % ids.size()], "PLAYER %d" % (index + 1), "4cd964"))
		_check_silent(pushed, "reaction %d was rejected" % index)
	_check(int(overlay.call("bubble_count")) == 6,
		"six reactions create six emotes (got %d)"
			% int(overlay.call("bubble_count")))
	var safe: Rect2 = overlay.call("safe_rect") as Rect2
	var rects: Array = overlay.call("debug_rects") as Array
	_check(_all_rects_inside(rects, safe),
		"every emote spawns inside the safe margins %s (rects %s)"
			% [str(safe), str(rects)])
	var xs: Dictionary = {}
	for raw: Variant in rects:
		xs[roundi((raw as Rect2).get_center().x)] = true
	_check(xs.size() >= 4,
		"emote spawn x is randomized across the overlay (got %d distinct)"
			% xs.size())
	# Data payload must be text-only: no rect/background/bar styling fields.
	var payload_ok: bool = true
	for bubble: Dictionary in overlay.call("debug_bubbles") as Array:
		var keys: Array = (bubble as Dictionary).keys()
		keys.sort()
		if keys != ["age", "label", "name", "peer", "pos", "rect"]:
			payload_ok = false
	_check(payload_ok, "emote payload carries only text fields")
	var first_bubbles: Array = overlay.call("debug_bubbles") as Array
	var first_pos: Vector2 = (first_bubbles[0] as Dictionary)["pos"] as Vector2
	await create_timer(0.5).timeout
	var later_bubbles: Array = overlay.call("debug_bubbles") as Array
	var later_pos: Vector2 = (later_bubbles[0] as Dictionary)["pos"] as Vector2
	_check(later_pos.y < first_pos.y - 2.0,
		"emote floats upward (%.1f -> %.1f)" % [first_pos.y, later_pos.y])
	_check(absf(later_pos.x - first_pos.x) > 0.05,
		"emote sways horizontally (%.1f -> %.1f)"
			% [first_pos.x, later_pos.x])
	_check(_all_rects_inside(overlay.call("debug_rects") as Array, safe),
		"emotes stay inside the safe margins while floating")
	# Reduce Motion: same spawn, no rise/sway.
	_set_reduce_motion(true)
	overlay.call("clear")
	overlay.call("push", 9, "gg", "REDUCED", "ffd22e")
	await process_frame
	var reduced_before: Vector2 = ((overlay.call("debug_bubbles") as Array)[0]
		as Dictionary)["pos"] as Vector2
	await create_timer(0.45).timeout
	var reduced_after: Vector2 = ((overlay.call("debug_bubbles") as Array)[0]
		as Dictionary)["pos"] as Vector2
	_check(reduced_before.distance_to(reduced_after) < 0.01,
		"reduce motion pins the emote (%.2f px drift)"
			% reduced_before.distance_to(reduced_after))
	_set_reduce_motion(false)
	# Invalid ids never render; lifetime expiry clears the overlay.
	_check(not bool(overlay.call("push", 9, "not-a-reaction", "X", "ffffff")),
		"unknown reaction ids are rejected by the renderer")
	overlay.call("clear")
	_check(int(overlay.call("bubble_count")) == 0, "clear() empties the overlay")
	overlay.call("push", 9, "honk", "LAST", "ff922b")
	await create_timer(LobbyReactions.BUBBLE_LIFETIME + 0.45).timeout
	_check(int(overlay.call("bubble_count")) == 0,
		"emotes expire after their lifetime")
	overlay.call("clear")
	host.queue_free()
	await process_frame


func _check_source_is_text_only() -> void:
	## Structural proof of "no boxy chrome": the overlay script must not build
	## Panel/ColorRect/TextureRect containers or draw bubble polygons at all.
	var file: FileAccess = FileAccess.open(
		"res://scripts/ui/lobby_emote_overlay.gd", FileAccess.READ)
	if file == null:
		_check(false, "emote overlay script missing")
		return
	var source: String = file.get_as_text()
	_check(not source.contains("ColorRect.new") and not source.contains("Panel.new")
		and not source.contains("PanelContainer.new")
		and not source.contains("TextureRect.new"),
		"emote overlay source creates no bar/plate/background nodes")
	_check(not source.contains("_bubble_poly") and not source.contains(
		"draw_colored_polygon"),
		"emote overlay source draws no bubble polygon chrome")


# --------------------------------------------------------------------------
# 5. slanted map preview
# --------------------------------------------------------------------------


func _test_map_preview() -> void:
	var host: Control = _make_host(Vector2(720.0, 400.0))
	var preview: Control = LobbyMapPreview.new() as Control
	preview.name = "MapPreview"
	preview.size = Vector2(720.0, 400.0)
	host.add_child(preview)
	await process_frame
	var base: PackedVector2Array = preview.call("base_points") as PackedVector2Array
	_check(base.size() == 4, "preview plate has four corners")
	if base.size() == 4:
		var skew: float = base[0].x - base[3].x
		var right_skew: float = base[1].x - base[2].x
		_check(skew >= 8.0, "preview plate is visibly slanted (%.1f px)" % skew)
		_check(absf(skew - right_skew) < 0.5,
			"preview plate is a true parallelogram (%.2f vs %.2f)"
				% [skew, right_skew])
	var bounds: Rect2 = preview.call("content_bounds") as Rect2
	_check(_points_inside(base, bounds), "static preview plate fits its bounds")
	var band: Rect2 = preview.call("title_band_rect") as Rect2
	_check(band.size.y >= 100.0 and band.size.y <= 400.0,
		"preview reserves a title scrim band (%.0f px)" % band.size.y)
	_check(bounds.encloses(band), "title scrim band sits inside the preview")
	# Live motion: it must actually animate, but only inside its declared limits.
	var first_points: PackedVector2Array = preview.call("frame_points") \
		as PackedVector2Array
	await create_timer(0.7).timeout
	var later_points: PackedVector2Array = preview.call("frame_points") \
		as PackedVector2Array
	var moved: float = 0.0
	for index in mini(first_points.size(), later_points.size()):
		moved = maxf(moved, first_points[index].distance_to(later_points[index]))
	_check(moved > 0.25, "preview has live idle motion (moved %.2f px)" % moved)
	var info: Dictionary = preview.call("motion_info") as Dictionary
	var limits: Dictionary = preview.call("motion_bounds") as Dictionary
	_check(absf(float(info.get("sway_px", 0.0)))
		<= float(limits.get("max_sway_px", 0.0)) + 0.01,
		"preview sway stays inside its bound")
	_check(absf(float(info.get("tilt_px", 0.0)))
		<= float(limits.get("max_tilt_px", 0.0)) + 0.01,
		"preview tilt stays inside its bound")
	_check(_points_inside(later_points, bounds),
		"animated preview plate never leaves its bounds")
	# Hover reacts (bounded float/glow, no layout change).
	preview.call("set_hover", true)
	await create_timer(0.6).timeout
	_check(float((preview.call("motion_info") as Dictionary).get("hover", 0.0))
		> 0.3, "preview reacts to hover")
	_check(_points_inside(preview.call("frame_points") as PackedVector2Array,
		bounds), "hover preview plate stays inside its bounds")
	preview.call("set_hover", false)
	# Reduce Motion freezes the geometry but keeps it slanted.
	_set_reduce_motion(true)
	await process_frame
	var frozen_a: PackedVector2Array = preview.call("frame_points") \
		as PackedVector2Array
	await create_timer(0.5).timeout
	var frozen_b: PackedVector2Array = preview.call("frame_points") \
		as PackedVector2Array
	var drift: float = 0.0
	for index in mini(frozen_a.size(), frozen_b.size()):
		drift = maxf(drift, frozen_a[index].distance_to(frozen_b[index]))
	_check(drift < 0.01, "reduce motion freezes preview motion (%.2f px)" % drift)
	_check(frozen_b.size() == 4 and frozen_b[0].x - frozen_b[3].x >= 8.0,
		"reduce-motion preview stays slanted")
	_set_reduce_motion(false)
	# Texture + fallback paths both render without errors.
	preview.call("set_texture", load(PREVIEW_TEXTURE) as Texture2D)
	_check(preview.call("get_preview_texture") != null,
		"preview accepts a map screenshot")
	preview.call("set_accent", Color("38d6f0"))
	await process_frame
	preview.call("set_texture", null)
	await process_frame
	var fallback_points: PackedVector2Array = preview.call("base_points") \
		as PackedVector2Array
	_check(fallback_points.size() == 4,
		"fallback preview still draws a slanted plate")
	preview.call("set_phase_radians", 1.25)
	await process_frame
	host.queue_free()
	await process_frame


# --------------------------------------------------------------------------
# 6. reaction sync contract: catalog + RPC block untouched by this redesign
# --------------------------------------------------------------------------


func _test_sync_contract() -> void:
	var network: Node = root.get_node_or_null("Network")
	_check(network != null, "Network autoload present")
	if network == null:
		return
	_check(network.has_method("send_lobby_reaction"),
		"Network keeps send_lobby_reaction (outbound emote entry point)")
	_check(network.has_method("_net_request_lobby_reaction")
		and network.has_method("_net_lobby_reaction"),
		"Network keeps both reliable host-relay RPCs")
	var net_script: GDScript = load(NETWORK_SCRIPT) as GDScript
	var net_source: String = ""
	var net_file: FileAccess = FileAccess.open(NETWORK_SCRIPT, FileAccess.READ)
	if net_file != null:
		net_source = net_file.get_as_text()
	_check(net_source.contains(
		"@rpc(\"any_peer\", \"call_remote\", \"reliable\")\nfunc _net_request_lobby_reaction")
		and net_source.contains(
			"@rpc(\"authority\", \"call_remote\", \"reliable\")\nfunc _net_lobby_reaction")
		and net_source.contains(
			"@rpc(\"authority\", \"call_remote\", \"reliable\")\nfunc _net_lobby_reaction"),
		"host-relayed reaction RPCs keep their reliable/authority annotations")
	var constants: Dictionary = net_script.get_script_constant_map()
	_check(constants.has("REACTION_COOLDOWN_MS")
		and constants.has("REACTION_WINDOW_MS")
		and constants.has("REACTION_WINDOW_CAP"),
		"host relay throttle constants still exist")
	_check(int(constants.get("REACTION_COOLDOWN_MS", 0)) > 0
		and int(constants.get("REACTION_WINDOW_CAP", 0)) >= 2,
		"host relay throttle values stay sane")
	_check(LobbyReactions.REACTIONS.size() == 5,
		"reaction catalog keeps five emotes (got %d)"
			% LobbyReactions.REACTIONS.size())
	for expected_id: String in ["gg", "start", "heart", "slop", "honk"]:
		_check(LobbyReactions.is_valid(expected_id),
			"reaction id '%s' still in the catalog" % expected_id)


# --------------------------------------------------------------------------
# 7. mode scripts route through the shared action-set API
# --------------------------------------------------------------------------


func _test_mode_script_wiring() -> void:
	var result_source: String = ""
	var result_file: FileAccess = FileAccess.open(
		"res://scripts/ui/result_screen.gd", FileAccess.READ)
	if result_file != null:
		result_source = result_file.get_as_text()
	_check(result_source.contains("multiplayer and not is_host"),
		"result_screen.gd owns the canonical non-host action set")
	for path: String in MODE_SCRIPTS:
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			_check(false, "mode script missing: %s" % path)
			continue
		var source: String = file.get_as_text()
		var name: String = path.get_file()
		_check(source.contains("\"confirm_main_menu\": _multiplayer"),
			"%s gates MAIN MENU through the shared action set" % name)
		_check(source.contains("\"on_leave\":"),
			"%s wires the client LEAVE LOBBY callback" % name)
		_check(source.contains("\"is_host\": _is_host"),
			"%s still passes host state to the shared card" % name)


# --------------------------------------------------------------------------
# 8. in-room lobby integration (Phase B, final)
# --------------------------------------------------------------------------


func _lobby_source() -> String:
	return FileAccess.get_file_as_string("res://scripts/ui/lobby_menu.gd")


func _code_only(source: String) -> String:
	## Strip full-line comments so a historical note mentioning the retired
	## hover driver is not mistaken for live wiring.
	var kept: PackedStringArray = PackedStringArray()
	for line: String in source.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		kept.append(line)
	return "\n".join(kept)


func _test_lobby_integration() -> void:
	# --- static integration proof -----------------------------------------
	var source: String = _lobby_source()
	_check(source.contains(
		"const LobbyEmoteOverlay := preload(\"res://scripts/ui/lobby_emote_overlay.gd\")"),
		"lobby_menu.gd preloads the text-only LobbyEmoteOverlay module")
	_check(source.contains(
		"const LobbyMapPreview := preload(\"res://scripts/ui/lobby_map_preview.gd\")"),
		"lobby_menu.gd preloads the slanted LobbyMapPreview module")
	_check(not source.contains("_ReactionBubbles"),
		"legacy _ReactionBubbles bubble class is gone from lobby_menu.gd")
	_check(not source.contains("_lobby_preview_tex")
		and not source.contains("_lobby_preview_fallback")
		and not source.contains("para_mat")
		and not source.contains("parallelogram_clip"),
		"legacy un-slanted preview texture/shader stack is gone")
	# WS4 correction must stay intact: the backdrop is self-running, never
	# hover/focus driven.
	var code: String = _code_only(source)
	_check(not code.contains("menu_hover_backdrop")
		and not code.contains("MenuHoverBackdrop")
		and not code.contains("hover_art")
		and not code.contains("focus_art")
		and not code.contains("crossfade_to"),
		"lobby_menu.gd has no hover/focus backdrop wiring (WS4 correction kept)")
	_check(source.contains("func _setup_independent_backdrop"),
		"independent auto-shuffling lobby backdrop setup is still present")
	_check(source.contains("func audit_room_state"),
		"lobby room audit hook is still present")

	# --- live lobby instance ----------------------------------------------
	var lobby: Node = (load(LOBBY_SCENE) as PackedScene).instantiate()
	root.add_child(lobby)
	current_scene = lobby
	await process_frame
	await process_frame
	await create_timer(0.35).timeout
	_check(lobby.has_method("audit_room_state"),
		"lobby_menu.gd loads and exposes audit_room_state")
	if not lobby.has_method("audit_room_state"):
		current_scene = null
		lobby.queue_free()
		await process_frame
		return
	lobby.call("audit_room_state")
	await create_timer(0.3).timeout

	# 1. Text-only emote overlay, seeded through the synced reaction signal path.
	var bubbles: Node = lobby.get("_bubbles") as Node
	_check(bubbles != null, "lobby built its reaction overlay")
	if bubbles != null:
		_check(bubbles.get_script() == LobbyEmoteOverlay,
			"lobby uses the new text-only LobbyEmoteOverlay module")
		_check(bubbles.get_child_count() == 0,
			"lobby emote overlay owns no bar/background nodes")
		_check((bubbles as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"lobby emote overlay never steals a reaction-button click")
		var live: Array = bubbles.get("_bubbles") as Array
		_check(live.size() == 2,
			"audit_room_state seeded two synced emotes (got %d)" % live.size())
		if bubbles.get_script() == LobbyEmoteOverlay:
			_check(int(bubbles.call("bubble_count")) == live.size(),
				"emote overlay counts match the synced reactions")
			var safe: Rect2 = bubbles.call("safe_rect") as Rect2
			var rects: Array = bubbles.call("debug_rects") as Array
			_check(rects.size() == live.size() and not rects.is_empty(),
				"in-room emotes expose their spawn rects")
			_check(_all_rects_inside(rects, safe),
				"in-room emote spawns stay inside the safe margins %s (rects %s)"
					% [str(safe), str(rects)])
			if rects.size() >= 2:
				var x0: float = (rects[0] as Rect2).get_center().x
				var x1: float = (rects[1] as Rect2).get_center().x
				_check(absf(x1 - x0) > 1.0,
					"in-room emote spawn positions are randomized (%.1f vs %.1f)"
						% [x0, x1])
			# A rejected reaction id must not add chrome or crash the renderer.
			lobby.call("_on_lobby_reaction", 7, "not-a-reaction", "X", "ffffff")
			await process_frame
			_check(int(bubbles.call("bubble_count")) == live.size(),
				"unknown synced reaction ids are ignored by the in-room overlay")
	var bar: Node = lobby.get("_reaction_bar") as Node
	_check(bar != null and bar.visible,
		"footer reaction bar stays visible in the room")
	var buttons: Array = lobby.get("_reaction_buttons") as Array
	_check(buttons.size() == LobbyReactions.REACTIONS.size(),
		"footer keeps one focusable button per reaction")
	for raw_button: Variant in buttons:
		var reaction_button := raw_button as Button
		if reaction_button != null and reaction_button.text.strip_edges() == "":
			_check(false, "footer reaction button lost its label")
			break

	# 2. Slanted map-preview card in the room preview stack.
	var preview: Node = lobby.get("_map_preview") as Node
	_check(preview != null, "lobby map preview module is wired in")
	if preview != null:
		_check(preview.get_script() == LobbyMapPreview,
			"lobby map preview uses the slanted LobbyMapPreview module")
		var base: PackedVector2Array = preview.call("base_points") \
			as PackedVector2Array
		_check(base.size() == 4 and base[0].x - base[3].x >= 8.0,
			"lobby map preview renders a visibly slanted plate")
		var bounds: Rect2 = preview.call("content_bounds") as Rect2
		var frame_points: PackedVector2Array = preview.call("frame_points") \
			as PackedVector2Array
		_check(_points_inside(frame_points, bounds),
			"in-room preview motion paints inside the card bounds")
		var info: Dictionary = preview.call("motion_info") as Dictionary
		var limits: Dictionary = preview.call("motion_bounds") as Dictionary
		_check(absf(float(info.get("sway_px", 0.0)))
			<= float(limits.get("max_sway_px", 0.0)) + 0.01
			and absf(float(info.get("tilt_px", 0.0)))
			<= float(limits.get("max_tilt_px", 0.0)) + 0.01,
			"lobby preview motion stays inside its bounds")
		var title: Label = lobby.get("_lobby_map_title") as Label
		var chip: Label = lobby.get("_lobby_mode_chip_label") as Label
		var stack: Control = preview.get_parent() as Control
		_check(title != null and title.is_visible_in_tree() and title.text != "",
			"map title stays present and visible above the preview")
		_check(chip != null and chip.is_visible_in_tree() and chip.text != "",
			"mode chip stays present and visible above the preview")
		if title != null and stack != null:
			_check(stack.get_global_rect().grow(3.0).encloses(
				title.get_global_rect()),
				"map title is not clipped by the animated preview card")
		if preview is CanvasItem:
			_check((preview as CanvasItem).get_index() == 0,
				"preview card sits at the bottom of the room preview stack")

	# 3. WS4 backdrop stays autonomous and hover/focus independent.
	var background: Node = lobby.get_node_or_null("Background")
	_check(background != null, "lobby keeps its independent MenuBackground")
	var art: Node = null
	if background != null:
		var found: Variant = lobby.call("_find_art_backdrop", background)
		art = found as Node
	_check(art != null, "lobby backdrop exposes the self-timed ArtBackdrop")
	if art != null:
		_check(bool(art.get("auto_advance")),
			"lobby backdrop auto-advance is ON")
		var names: PackedStringArray = art.call("slide_names") as PackedStringArray
		_check(names.size() >= 2,
			"lobby backdrop cycles a multi-plate pool (got %d)" % names.size())
		var hero_only: bool = not names.is_empty()
		for file_name: String in names:
			if not file_name.begins_with("bg_hero_"):
				hero_only = false
		_check(hero_only, "lobby backdrop pool is the bg_hero_* key-art set (%s)"
			% str(names))
		var slide_min: float = float(art.get("slide_seconds_min"))
		var slide_max: float = float(art.get("slide_seconds_max"))
		_check(slide_min >= 8.0 and slide_max <= 12.0 and slide_max > slide_min,
			"lobby backdrop cadence is the 8-12 s band (%.1f-%.1f s)"
				% [slide_min, slide_max])
		# Freeze the cadence, then synthesize hover AND focus over the room
		# controls; the slide index/name must not move and auto-advance stays on.
		art.set("slide_seconds_min", 600.0)
		art.set("slide_seconds_max", 600.0)
		art.call("reset_schedule")
		var index_before: int = int(art.call("current_index"))
		var name_before: String = str(art.call("current_slide_name"))
		for key: String in ["_leave_button", "_start_button", "_map_button",
				"_change_mode_button", "_room_bots_pill"]:
			var control := lobby.get(key) as Control
			if control == null:
				continue
			control.grab_focus()
			control.mouse_entered.emit()
			control.mouse_exited.emit()
		for raw_button: Variant in buttons:
			var reaction_button := raw_button as Button
			if reaction_button != null:
				reaction_button.grab_focus()
				reaction_button.mouse_entered.emit()
				reaction_button.mouse_exited.emit()
		if preview != null:
			preview.call("set_hover", true)
		await process_frame
		await process_frame
		_check(int(art.call("current_index")) == index_before
			and str(art.call("current_slide_name")) == name_before,
			"synthetic hover/focus leaves the lobby backdrop slide untouched")
		_check(bool(art.get("auto_advance")),
			"synthetic hover/focus never pauses the lobby slideshow")
		if preview != null:
			preview.call("set_hover", false)

	current_scene = null
	lobby.queue_free()
	await process_frame


# --------------------------------------------------------------------------
# 9. optional live-scene proof (CART_WS3_LIVE_MODES=1, slow: boots 3D scenes)
# --------------------------------------------------------------------------


func _test_live_mode_cards() -> void:
	for case: Dictionary in LIVE_CASES:
		var path: String = str(case["path"])
		if not ResourceLoader.exists(path):
			_check(false, "%s scene missing" % case["id"])
			continue
		var instance: Node = (load(path) as PackedScene).instantiate()
		root.add_child(instance)
		current_scene = instance
		await create_timer(2.4).timeout
		var method_name: String = str(case["method"])
		if not instance.has_method(method_name):
			_check(false, "%s missing %s" % [case["id"], method_name])
			instance.queue_free()
			await process_frame
			continue
		var old_root: Node = instance.get("_result_root") as Node
		if old_root != null and is_instance_valid(old_root):
			old_root.queue_free()
			instance.set("_result_root", null)
		# Force the multiplayer-client branch, then rebuild the shared card only.
		instance.set("_multiplayer", true)
		instance.set("_is_host", false)
		instance.call(method_name)
		await process_frame
		var card: Dictionary = instance.get("_result_card") as Dictionary
		var helper: RefCounted = instance.get("_result_ui") as RefCounted
		if card.is_empty() or helper == null:
			_check(false, "%s did not build a result card" % case["id"])
			instance.queue_free()
			await process_frame
			continue
		# The card is built hidden; present it exactly like the mode's own
		# result path does before the action set becomes visible/auditable.
		helper.call("present", card)
		await process_frame
		var actions: Array = helper.call("action_set", card)
		_check(actions == ["LEAVE LOBBY"],
			"%s live client card action set is %s" % [case["id"], str(actions)])
		_check(str(helper.call("waiting_text", card)).begins_with(WAITING_BASE),
			"%s live client card shows the waiting status" % case["id"])
		# The confirm gate must own ESC: the scene PauseMenu's ESC handler is
		# suspended while the dialog is open and restored when it closes, through
		# the pause menu's own WS5P3-14 suspension API.
		var pause_menu: Node = instance.get_node_or_null("PauseMenu/Root")
		if pause_menu != null and pause_menu.has_method("_unhandled_input"):
			helper.call("request_leave", card)
			await process_frame
			var isolation: Dictionary = helper.call("pause_isolation", card) \
				as Dictionary
			_check(bool(isolation.get("resolved", false)),
				"%s confirm gate resolves the live PauseMenu/Root"
					% case["id"])
			_check(not pause_menu.is_processing_unhandled_input(),
				"%s confirm gate suspends the PauseMenu ESC handler"
					% case["id"])
			if pause_menu.has_method("is_input_suspended"):
				_check(bool(pause_menu.call("is_input_suspended")),
					"%s confirm gate engages PauseMenu.set_input_suspended"
						% case["id"])
			# ESC sent straight to the pause root must be refused while open.
			var esc := InputEventAction.new()
			esc.action = "ui_cancel"
			esc.pressed = true
			pause_menu.call("_unhandled_input", esc)
			await process_frame
			_check(not bool(pause_menu.get("_is_open")),
				"%s ESC cannot open Pause behind the live confirm gate"
					% case["id"])
			helper.call("confirm_cancel", card)
			await process_frame
			_check(pause_menu.is_processing_unhandled_input(),
				"%s confirm gate restores the PauseMenu ESC handler"
					% case["id"])
			if pause_menu.has_method("is_input_suspended"):
				_check(not bool(pause_menu.call("is_input_suspended")),
					"%s confirm gate releases PauseMenu.set_input_suspended"
						% case["id"])
		instance.queue_free()
		await process_frame
		await process_frame
	current_scene = null
