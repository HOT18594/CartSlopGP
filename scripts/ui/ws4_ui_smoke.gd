extends SceneTree
## WS4 headless smoke test: loading-bar weighting/monotonicity and the lobby
## reaction rate limiter + relay plumbing.
##
## Exit code = number of failures (same contract as the other suites).
## Run from the workspace root:
##   downloads/godot_editor/Godot_v4.7.2-stable_win64_console.exe --headless \
##     --path godot_project --script res://scripts/ui/ws4_ui_smoke.gd

const SCENE_LOADER_SCRIPT := "res://scripts/systems/scene_loader.gd"
const LOADING_LAYER_SCENE := "res://scenes/ui/scene_loader.tscn"
const LOBBY_SCENE := "res://scenes/ui/lobby_menu.tscn"
const NETWORK_SCRIPT := "res://scripts/net/network.gd"
const LobbyReactions := preload("res://scripts/ui/lobby_reactions.gd")
const ART_DIR := "res://assets/ui/art/"
const MENU_SCRIPT_DIR := "res://scripts/ui/"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	print("%s  %s" % ["OK  " if condition else "FAIL", message])
	if not condition:
		_failures += 1
		push_error("WS4_SMOKE: " + message)


func _run() -> void:
	var mode: String = OS.get_environment("CSGP_REACTION_MODE").strip_edges().to_lower()
	if mode == "host":
		await _run_reaction_room_host()
		quit(0 if _failures == 0 else _failures)
		return
	if mode == "client":
		await _run_reaction_room_client()
		quit(0 if _failures == 0 else _failures)
		return
	await _test_phase_weights()
	await _test_loading_screen_monotonic()
	await _test_reaction_catalog()
	await _test_reaction_limiter()
	await _test_network_reaction_contract()
	await _test_menu_backgrounds()
	await _test_lobby_reaction_wiring()
	await _test_real_scene_load()
	print("WS4_SMOKE: %d checks, %d failures" % [_checks, _failures])
	print("WS4_SMOKE: %s" % ("PASS" if _failures == 0 else "FAIL"))
	quit(0 if _failures == 0 else _failures)


func _test_phase_weights() -> void:
	print("--- loading phase weights")
	var script: GDScript = load(SCENE_LOADER_SCRIPT) as GDScript
	var consts: Dictionary = script.get_script_constant_map()
	var stream_start: float = float(consts["LOAD_PHASE_START"])
	var stream_end: float = float(consts["LOAD_PHASE_END"])
	var instantiate_start: float = float(consts["INSTANTIATE_START"])
	var warmup_start: float = float(consts["WARMUP_START"])
	var warmup_end: float = float(consts["WARMUP_END"])
	_check(stream_start >= 0.0 and stream_start < stream_end,
		"streaming phase has a positive span")
	_check(stream_end < instantiate_start and instantiate_start <= warmup_start
			and warmup_start < warmup_end and warmup_end < 1.0,
		"phases are ordered and never terminal (stream %.2f..%.2f, warm %.2f..%.2f)"
			% [stream_start, stream_end, warmup_start, warmup_end])

	var loader: Node = root.get_node_or_null("SceneLoader")
	_check(loader != null, "SceneLoader autoload present")
	if loader == null:
		return
	var previous: float = -1.0
	var monotonic: bool = true
	for step in 41:
		var ratio: float = float(step) / 40.0
		var value: float = float(loader.call("progress_for_stream", ratio))
		if value < previous - 0.0001:
			monotonic = false
		previous = value
	_check(monotonic, "streaming weighting is monotonic")
	_check(absf(float(loader.call("progress_for_stream", 0.0)) - stream_start) < 0.0001,
		"stream 0%% maps to the phase start")
	_check(absf(float(loader.call("progress_for_stream", 1.0)) - stream_end) < 0.0001,
		"stream 100%% maps to the phase end, not 100%% of the bar")
	_check(absf(float(loader.call("progress_for_warmup", 0.0)) - warmup_start) < 0.0001,
		"warm-up starts at WARMUP_START")
	_check(absf(float(loader.call("progress_for_warmup", 1.0)) - warmup_end) < 0.0001,
		"warm-up ends below 100%% (terminal 100 is explicit)")
	_check(float(loader.call("progress_for_warmup", 1.0)) < 1.0,
		"a warm-up frame can never report a fake 100%")


func _test_loading_screen_monotonic() -> void:
	print("--- loading screen progress")
	var layer: Node = (load(LOADING_LAYER_SCENE) as PackedScene).instantiate()
	root.add_child(layer)
	await process_frame
	var screen: Control = layer.get_node_or_null("UI") as Control
	_check(screen != null, "loading screen UI present")
	if screen == null:
		layer.queue_free()
		return
	screen.call("set_progress", 0.0, true)
	_check(is_equal_approx(float(screen.get("progress")), 0.0),
		"explicit terminal-zero reset zeroes the bar")
	screen.call("set_progress", 0.45, true)
	_check(is_equal_approx(float(screen.get("progress")), 0.45),
		"immediate progress applies")
	screen.call("set_progress", 0.30, true)
	_check(is_equal_approx(float(screen.get("progress")), 0.45),
		"a stale lower value cannot move the bar backwards")
	screen.call("set_progress", 0.80)
	screen.call("set_progress", 0.60)
	_check(float(screen.get("progress")) >= 0.80,
		"damped progress also enforces a monotonic floor")
	screen.call("set_progress", 1.0, true)
	_check(is_equal_approx(float(screen.get("progress")), 1.0),
		"terminal 100% is reachable")
	_check(is_equal_approx(float(screen.call("_fill_ratio")), 1.0),
		"terminal 100% fills the drawn bar")
	screen.call("set_progress", 0.0, true)
	_check(is_equal_approx(float(screen.get("progress")), 0.0),
		"the next load starts from zero")
	layer.queue_free()
	await process_frame


func _test_reaction_catalog() -> void:
	print("--- reaction catalog")
	var reactions: Array = LobbyReactions.REACTIONS
	_check(reactions.size() >= 3 and reactions.size() <= 5,
		"catalog keeps 3-5 reactions (got %d)" % reactions.size())
	var seen: Dictionary = {}
	var labels_ok: bool = true
	var colors_ok: bool = true
	for entry: Dictionary in reactions:
		var id: String = str(entry.get("id", ""))
		var label: String = str(entry.get("label", ""))
		seen[id] = true
		if id == "" or label == "" or label.length() > 10:
			labels_ok = false
		var hex: String = str(entry.get("accent", ""))
		if hex.length() != 6 or not Color.html_is_valid(hex):
			colors_ok = false
	_check(seen.size() == reactions.size(), "reaction ids are unique")
	_check(labels_ok, "every reaction has a short label")
	_check(colors_ok, "every reaction has a valid accent colour")
	_check(LobbyReactions.is_valid(LobbyReactions.ID_GG), "GG reaction is valid")
	_check(not LobbyReactions.is_valid("GG"), "catalog lookup is case-sensitive")
	_check(not LobbyReactions.is_valid("nonsense"), "unknown ids are rejected")
	_check(LobbyReactions.label_for(LobbyReactions.ID_START) == "START!",
		"label lookup returns the catalog label")
	_check(LobbyReactions.accent_for(LobbyReactions.ID_GG)
		== Color("4cd964"), "accent lookup returns the catalog colour")


func _test_reaction_limiter() -> void:
	print("--- reaction limiter")
	_check(LobbyReactions.can_send(1000, -1), "first press is always allowed")
	_check(not LobbyReactions.can_send(1500, 1000),
		"press inside the cooldown is rejected")
	_check(LobbyReactions.can_send(1000 + LobbyReactions.COOLDOWN_MS, 1000),
		"press at the cooldown boundary is allowed")
	_check(LobbyReactions.can_send(1000, 5000),
		"a backwards clock is treated as ready (never a lockout)")

	var pending: Array = []
	for press in 6:
		LobbyReactions.push_pending(pending, LobbyReactions.ID_GG, 1000 + press)
	_check(pending.size() == LobbyReactions.PENDING_CAP,
		"pending queue is capped at %d (got %d)"
			% [LobbyReactions.PENDING_CAP, pending.size()])
	var next_id: String = LobbyReactions.next_pending(pending, 1100)
	_check(next_id == LobbyReactions.ID_GG, "oldest buffered reaction is popped first")
	_check(not LobbyReactions.push_pending([], "bogus", 1000),
		"invalid ids never enter the queue")
	var stale: Array = []
	LobbyReactions.push_pending(stale, LobbyReactions.ID_SLOP, 1000)
	LobbyReactions.prune_pending(stale, 1000 + LobbyReactions.PENDING_MAX_AGE_MS + 1)
	_check(stale.is_empty(), "stale buffered presses are dropped instead of sent late")


func _test_network_reaction_contract() -> void:
	print("--- network reaction contract")
	var net_script: GDScript = load(NETWORK_SCRIPT) as GDScript
	var consts: Dictionary = net_script.get_script_constant_map()
	var cooldown: int = int(consts["REACTION_COOLDOWN_MS"])
	var window_ms: int = int(consts["REACTION_WINDOW_MS"])
	var window_cap: int = int(consts["REACTION_WINDOW_CAP"])
	_check(cooldown > 0 and window_ms > 0 and window_cap > 0
			and window_cap >= 2, "host throttle constants are sane")
	_check(cooldown <= window_ms, "cooldown fits inside the amplification window")

	var network: Node = root.get_node_or_null("Network")
	_check(network != null, "Network autoload present")
	if network == null:
		return
	network.call("reaction_throttle_reset")
	_check(bool(network.call("_reaction_allowed", 1, 1000)) == false,
		"host itself is not relayed through the request path")
	_check(bool(network.call("_reaction_allowed", 2, 1000)),
		"first client reaction is accepted")
	_check(not bool(network.call("_reaction_allowed", 2, 1000 + cooldown / 2)),
		"repeat inside the cooldown is rejected")
	_check(bool(network.call("_reaction_allowed", 2, 1000 + cooldown)),
		"repeat after the cooldown is accepted")
	var accepted: int = 0
	var stamp: int = 1000
	for step in window_cap + 6:
		stamp += cooldown
		if bool(network.call("_reaction_allowed", 3, stamp)):
			accepted += 1
	_check(accepted <= window_cap,
		"per-peer window cap blocks amplification (%d accepted, cap %d)"
			% [accepted, window_cap])
	_check(accepted == window_cap,
		"window cap is exactly %d relays" % window_cap)
	network.call("reaction_throttle_reset")

	_check(str(network.call("sanitize_reaction_id", "GG")) == "gg",
		"reaction ids are normalised to lowercase")
	_check(str(network.call("sanitize_reaction_id", "gg!")) == "",
		"punctuation is rejected from the RPC payload")
	_check(str(network.call("sanitize_reaction_id", "aaaaaaaaaaaaaaaaaaaa")) == "",
		"overlong ids are rejected")
	_check(str(network.call("sanitize_reaction_id", "")) == "",
		"empty ids are rejected")

	# Offline-safety: with no session the call must still succeed and emit the
	# local bubble exactly once (no RPC attempted, no error).
	var received: Array = []
	var on_reaction := func(peer_id: int, reaction_id: String, peer_name: String,
			color_hex: String) -> void:
		received.append({"peer": peer_id, "id": reaction_id,
			"name": peer_name, "color": color_hex})
	network.lobby_reaction_received.connect(on_reaction)
	_check(bool(network.call("send_lobby_reaction", "gg")),
		"offline send_lobby_reaction reports success")
	_check(received.size() == 1, "offline send emits one local bubble (got %d)"
		% received.size())
	if received.size() > 0:
		var first: Dictionary = received[0] as Dictionary
		_check(int(first["peer"]) == 0, "offline bubble is tagged as local (peer 0)")
		_check(str(first["id"]) == "gg", "offline bubble carries the sanitized id")
	_check(not bool(network.call("send_lobby_reaction", "not-a-reaction")),
		"invalid offline reaction returns false without erroring")


func _test_menu_backgrounds() -> void:
	print("--- autonomous menu backdrops (no hover/focus coupling)")
	# 0.8.7 correction: hover/focus no longer drives any menu background. Every
	# menu owns a self-timed ArtBackdrop slideshow (randomized 8-12 s beat,
	# shuffled order, smooth crossfade); button hover animation stays local.
	# Static proof: no menu script references the retired hover driver and the
	# helper module is gone.
	for script_name: String in ["main_menu", "play_menu", "minigames_menu"]:
		var source: String = FileAccess.get_file_as_string(MENU_SCRIPT_DIR + script_name + ".gd")
		_check(not source.contains("menu_hover_backdrop")
				and not source.contains("MenuHoverBackdrop")
				and not source.contains("hover_art")
				and not source.contains("focus_art"),
			"%s.gd has no hover/focus backdrop wiring" % script_name)
		_check(not source.contains("crossfade_to"),
			"%s.gd never calls crossfade_to()" % script_name)
	_check(not ResourceLoader.exists("res://scripts/ui/menu_hover_backdrop.gd"),
		"menu_hover_backdrop.gd was deleted once nothing referenced it")

	# 1. Main menu: all four hero key arts, autonomous shuffled 8-12 s crossfades.
	var menu: Node = (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame
	var background: Control = menu.get_node_or_null("Background") as Control
	_check(background != null, "main menu found its MenuBackground")
	if background == null:
		menu.queue_free()
		await process_frame
		return
	var art: Node = background.call("art_backdrop_node") as Node
	_check(art != null, "main menu reached the self-timed ArtBackdrop")
	if art == null:
		menu.queue_free()
		await process_frame
		return
	_check(bool(art.get("auto_advance")), "main menu auto-advance is ON")
	_check(bool(art.get("shuffle")), "main menu slide order is shuffled")
	var menu_names: PackedStringArray = art.call("slide_names")
	_check(menu_names.size() == 4,
		"main menu cycles all four hero plates (got %d: %s)"
			% [menu_names.size(), str(menu_names)])
	var all_hero: bool = not menu_names.is_empty()
	for file_name: String in menu_names:
		if not file_name.begins_with("bg_hero_"):
			all_hero = false
	_check(all_hero, "every main-menu plate is a bg_hero_* key art")
	var slide_min: float = float(art.get("slide_seconds_min"))
	var slide_max: float = float(art.get("slide_seconds_max"))
	_check(slide_min >= 8.0 and slide_max <= 12.0 and slide_max > slide_min,
		"main-menu cadence is the 8-12 s band (%.1f-%.1f s)" % [slide_min, slide_max])
	_check(float(art.get("fade_seconds")) >= 0.2,
		"main-menu slide crossfade is smooth (%.2f s)" % float(art.get("fade_seconds")))
	_check(not menu.has_method("_setup_hover_backdrop"),
		"main menu no longer has a hover-backdrop setup step")

	# Hover/focus independence: freeze the cadence, then synthesize focus + mouse
	# enter/exit over every hero tile and dock card. The slide index and name must
	# not move and auto_advance must stay on.
	art.set("slide_seconds_min", 600.0)
	art.set("slide_seconds_max", 600.0)
	art.call("reset_schedule")
	var index_before: int = int(art.call("current_index"))
	var name_before: String = str(art.call("current_slide_name"))
	var hero_buttons: Array = menu.call("hero_option_buttons")
	for raw: Variant in hero_buttons:
		var button := raw as Button
		if button == null:
			continue
		button.grab_focus()
		button.mouse_entered.emit()
		button.mouse_exited.emit()
	var dock: Control = menu.get("_dock_bar") as Control
	if dock != null:
		for child: Node in dock.get_children():
			if child is Button:
				(child as Button).grab_focus()
				(child as Button).mouse_entered.emit()
				(child as Button).mouse_exited.emit()
	await process_frame
	await process_frame
	_check(int(art.call("current_index")) == index_before
			and str(art.call("current_slide_name")) == name_before,
		"synthetic hover/focus leaves the backdrop slide untouched (%s)" % name_before)
	_check(bool(art.get("auto_advance")),
		"synthetic hover/focus never pauses the slideshow")

	# It really advances by itself, in a shuffled order with no immediate repeat.
	art.set("fade_seconds", 0.03)
	art.set("slide_seconds_min", 0.05)
	art.set("slide_seconds_max", 0.07)
	art.call("reset_schedule")
	var seen: Array[String] = [str(art.call("current_slide_name"))]
	var deadline: int = Time.get_ticks_msec() + 5000
	while seen.size() < 5 and Time.get_ticks_msec() < deadline:
		await process_frame
		var now: String = str(art.call("current_slide_name"))
		if now != "" and now != seen[seen.size() - 1]:
			seen.append(now)
	_check(seen.size() >= 5,
		"backdrop advanced on its own (%d crossfades sampled)" % (seen.size() - 1))
	var no_repeat: bool = true
	for i in range(1, seen.size()):
		if seen[i] == seen[i - 1]:
			no_repeat = false
	_check(no_repeat, "shuffled order never shows the same plate twice in a row (%s)"
		% str(seen))
	var distinct: Dictionary = {}
	for file_name: String in seen:
		distinct[file_name] = true
	_check(distinct.size() >= 3,
		"shuffled order uses multiple plates in one cycle (got %d)" % distinct.size())

	# Reduced motion is respected: no automatic crossfade, no Ken Burns drift.
	var settings: Node = root.get_node_or_null("GameSettings")
	if settings != null:
		var previous: bool = bool(settings.get("reduce_motion"))
		settings.set("reduce_motion", true)
		await process_frame
		await process_frame
		var held_advances: int = int(art.call("advance_count"))
		var held_name: String = str(art.call("current_slide_name"))
		await create_timer(0.25).timeout
		_check(int(art.call("advance_count")) == held_advances
				and str(art.call("current_slide_name")) == held_name,
			"reduced motion holds the backdrop still")
		_check(not bool(art.call("ken_burns_active")),
			"reduced motion disables backdrop Ken Burns")
		_check(bool(art.get("auto_advance")),
			"reduced motion never re-enables hover/focus coupling")
		settings.set("reduce_motion", previous)
	menu.queue_free()
	await process_frame

	# 2. Play menu = its two hero plates; minigames select = its mode art pool.
	#    Both keep the autonomous slideshow ON and have no hover wiring.
	var pools: Dictionary = {
		"res://scenes/ui/play_menu.tscn": 2,
		"res://scenes/ui/minigames_menu.tscn": 5,
	}
	for path: String in pools:
		var screen: Node = (load(path) as PackedScene).instantiate()
		root.add_child(screen)
		await process_frame
		await process_frame
		var screen_bg: Control = screen.get_node_or_null("Background") as Control
		_check(screen_bg != null, "%s has a MenuBackground" % path.get_file())
		if screen_bg != null:
			var screen_art: Node = screen_bg.call("art_backdrop_node") as Node
			_check(screen_art != null and bool(screen_art.get("auto_advance")),
				"%s keeps the autonomous slideshow ON" % path.get_file())
			if screen_art != null:
				var pool: PackedStringArray = screen_art.call("slide_names")
				var expected: int = int(pools[path])
				_check(pool.size() == expected,
					"%s slideshow pool has %d plates (got %d: %s)"
						% [path.get_file(), expected, pool.size(), str(pool)])
				var all_exist: bool = not pool.is_empty()
				for file_name: String in pool:
					if not ResourceLoader.exists(ART_DIR + file_name):
						all_exist = false
				_check(all_exist,
					"%s every slideshow plate resolves to a real art file"
						% path.get_file())
		screen.queue_free()
		await process_frame


func _test_lobby_reaction_wiring() -> void:
	print("--- lobby reaction wiring")
	var lobby: Node = (load(LOBBY_SCENE) as PackedScene).instantiate()
	root.add_child(lobby)
	await process_frame
	await process_frame
	var bar: Node = lobby.get("_reaction_bar")
	var bubbles: Node = lobby.get("_bubbles")
	var buttons: Array = lobby.get("_reaction_buttons")
	_check(bar != null, "reaction bar was built")
	_check(bubbles != null, "reaction bubble overlay was built")
	_check(buttons.size() == LobbyReactions.REACTIONS.size(),
		"one focusable button per reaction (got %d)" % buttons.size())
	_check(bar != null and not bar.visible,
		"reactions are hidden on the idle lobby screen")
	lobby.call("_set_state", "host")
	await process_frame
	_check(bar != null and bar.visible,
		"reactions appear once the player is in a room")
	lobby.call("_on_lobby_reaction", 2, "gg", "AUDIT HOST", "4cd964")
	await process_frame
	var bubble_list: Array = bubbles.get("_bubbles") if bubbles != null else []
	_check(bubble_list.size() == 1, "a synced reaction creates one bubble")
	lobby.call("_on_lobby_reaction", 3, "not-a-reaction", "X", "ffffff")
	_check(bubble_list.size() == 1, "unknown reaction ids are ignored by the renderer")
	var lobby_background: Control = lobby.get_node_or_null("Background") as Control
	_check(lobby_background != null, "lobby has its MenuBackground")
	if lobby_background != null:
		var lobby_art: Node = lobby_background.call("art_backdrop_node") as Node
		_check(lobby_art != null and bool(lobby_art.get("auto_advance")),
			"lobby keeps the autonomous backdrop slideshow ON")
		var lobby_pool: PackedStringArray = lobby_art.call("slide_names") \
			if lobby_art != null else PackedStringArray()
		_check(lobby_pool.size() >= 2,
			"lobby backdrop cycles a multi-plate pool (got %d)" % lobby_pool.size())
	lobby.queue_free()
	await process_frame
	print("--- done")


# --------------------------------------------------------------------------
# Optional end-to-end loading check (WS4_LOAD_TEST=1): drives the real
# SceneLoader through a heavy overlay scene and samples the HUD bar value every
# frame. Proves the weighting is monotonic and that 100% only appears at the
# very end, after the new scene has been instantiated and warmed up.


func _test_real_scene_load() -> void:
	if OS.get_environment("WS4_LOAD_TEST") != "1":
		return
	print("--- real scene load (sandbox)")
	var loader: Node = root.get_node_or_null("SceneLoader")
	_check(loader != null, "SceneLoader autoload present for the load test")
	if loader == null:
		return
	var ui: Control = loader.get_node_or_null("UI") as Control
	_check(ui != null, "loading overlay UI present for the load test")
	if ui == null:
		return
	var samples: Array[float] = []
	var first_full_at: int = -1
	var deadline: int = Time.get_ticks_msec() + 20000
	loader.call("go_to", "res://scenes/sandbox/sandbox.tscn", "WS4 LOAD", "warming up")
	while Time.get_ticks_msec() < deadline:
		if not bool(loader.call("is_busy")) and samples.size() > 4:
			break
		var value: float = float(ui.get("progress"))
		if first_full_at < 0 and value >= 0.999:
			first_full_at = samples.size()
		samples.append(value)
		await process_frame
	var monotonic: bool = true
	var previous: float = -1.0
	var full_samples: int = 0
	for value: float in samples:
		if value < previous - 0.0001:
			monotonic = false
		if value >= 0.999:
			full_samples += 1
		previous = value
	_check(samples.size() >= 6, "real load produced enough progress samples (%d)"
		% samples.size())
	_check(monotonic, "real load progress is monotonic across all phases")
	_check(not samples.is_empty() and samples[0] < 0.5,
		"real load starts in the streaming phase, not near 100%")
	_check(first_full_at >= 0, "real load eventually reports 100%")
	var full_is_late: bool = first_full_at >= int(float(samples.size()) * 0.7)
	_check(full_is_late, "100%% only appears at the end (%d of %d samples)"
		% [first_full_at, samples.size()])
	_check(full_samples <= 60, "100%% is held briefly for the fade, not stalled (%d frames)"
		% full_samples)
	var end_ok: bool = first_full_at >= 0 and first_full_at > samples.size() / 2
	_check(end_ok, "the last third of the load is the only place 100%% appears")
	_check(not bool(loader.call("is_busy")), "real load finished (bar not stalled busy)")
	var final_scene: String = str(loader.call("current_scene_path"))
	_check(final_scene.ends_with("sandbox.tscn"),
		"the requested scene is live when the bar finishes")
	print("    samples=%d first_full=%d tail=%s" % [samples.size(), first_full_at,
		str(samples.slice(maxi(samples.size() - 8, 0)))])


# --------------------------------------------------------------------------
# Two-process LAN reaction relay test (real ENet RPCs over loopback).
#
#   CSGP_REACTION_MODE=host   ...ws4_ui_smoke.gd   (opens a LAN room)
#   CSGP_REACTION_MODE=client ...ws4_ui_smoke.gd   (joins it)
#
# The host asserts it receives the client's reaction through
# `lobby_reaction_received` (i.e. the reliable request RPC reached the host and
# was sanitised/relayed), and the client asserts it receives the host's relayed
# reaction. The client also mashes five reactions at once so the host-side
# throttle is exercised over a real socket, not just as a pure function.

const SYNC_WAIT_MS: int = 25000


func _run_reaction_room_host() -> void:
	print("--- reaction relay host")
	var network: Node = root.get_node_or_null("Network")
	_check(network != null, "Network autoload present")
	if network == null:
		return
	var received: Array = []
	var on_reaction := func(peer_id: int, reaction_id: String, peer_name: String,
			color_hex: String) -> void:
		received.append({"peer": peer_id, "id": reaction_id,
			"name": peer_name, "color": color_hex})
	network.lobby_reaction_received.connect(on_reaction)
	var host_ready: Array = []
	network.host_started.connect(func(_code: String) -> void: host_ready.append(true))
	network.host_game("lan")
	var deadline: int = Time.get_ticks_msec() + SYNC_WAIT_MS
	while host_ready.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not host_ready.is_empty(), "host opened a LAN room")
	var peers_deadline: int = Time.get_ticks_msec() + SYNC_WAIT_MS
	while int(network.peer_count()) < 2 and Time.get_ticks_msec() < peers_deadline:
		await process_frame
	_check(int(network.peer_count()) >= 2, "a LAN client joined the host")
	# Wait for the client's reactions (it sends "gg", then mashes four more).
	var reaction_deadline: int = Time.get_ticks_msec() + 9000
	while received.is_empty() and Time.get_ticks_msec() < reaction_deadline:
		await process_frame
	var client_received: int = 0
	for entry: Dictionary in received:
		if int(entry["peer"]) > 1:
			client_received += 1
	_check(received.size() >= 1, "host received a reaction from the client RPC")
	_check(client_received >= 1, "host attributes the reaction to the client peer id")
	if received.size() > 0:
		var first: Dictionary = received[0] as Dictionary
		_check(str(first["id"]) == "gg", "host received the sanitized reaction id")
		_check(str(first["name"]) != "", "host attached the sender name to the relay")
	_check(received.size() <= 3,
		"host throttle limited a five-press burst (got %d relays)" % received.size())
	# Relay direction: host -> clients. The client asserts it renders this one.
	network.send_lobby_reaction("honk")
	await create_timer(2.5).timeout
	network.leave()
	await process_frame
	print("WS4_SYNC host: %d checks, %d failures" % [_checks, _failures])
	print("WS4_SYNC host: %s" % ("PASS" if _failures == 0 else "FAIL"))


func _run_reaction_room_client() -> void:
	print("--- reaction relay client")
	var network: Node = root.get_node_or_null("Network")
	_check(network != null, "Network autoload present")
	if network == null:
		return
	var received: Array = []
	var on_reaction := func(peer_id: int, reaction_id: String, peer_name: String,
			color_hex: String) -> void:
		received.append({"peer": peer_id, "id": reaction_id,
			"name": peer_name, "color": color_hex})
	network.lobby_reaction_received.connect(on_reaction)
	var joined: Array = []
	var join_failures: Array = []
	network.join_succeeded.connect(func() -> void: joined.append(true))
	network.join_failed.connect(func(reason: String) -> void: join_failures.append(reason))
	var rooms: Array = []
	var scan_deadline: int = Time.get_ticks_msec() + SYNC_WAIT_MS
	while rooms.is_empty() and Time.get_ticks_msec() < scan_deadline:
		rooms = await network.scan_lan_rooms(1.4)
		if rooms.is_empty():
			await create_timer(0.4).timeout
	_check(not rooms.is_empty(), "client discovered the LAN room")
	if rooms.is_empty():
		return
	network.join_lan_room(rooms[0])
	var join_deadline: int = Time.get_ticks_msec() + SYNC_WAIT_MS
	while joined.is_empty() and join_failures.is_empty() \
			and Time.get_ticks_msec() < join_deadline:
		await process_frame
	_check(not joined.is_empty(), "client joined the LAN room")
	if joined.is_empty():
		return
	await create_timer(0.8).timeout
	# One clean reaction for the host assertion, then a five-press burst that
	# the host-side throttle must cap.
	network.send_lobby_reaction("gg")
	await create_timer(0.5).timeout
	for press in 5:
		network.send_lobby_reaction("slop")
		await create_timer(0.06).timeout
	# Host relays its own reaction ("honk") to every client.
	var host_reaction_deadline: int = Time.get_ticks_msec() + 9000
	var saw_host_honk: bool = false
	while Time.get_ticks_msec() < host_reaction_deadline and not saw_host_honk:
		for entry: Dictionary in received:
			if int(entry["peer"]) == 1 and str(entry["id"]) == "honk":
				saw_host_honk = true
		await process_frame
	_check(saw_host_honk, "client received the host's relayed reaction")
	_check(received.size() >= 1, "client rendered at least one relayed bubble")
	network.leave()
	await process_frame
	print("WS4_SYNC client: %d checks, %d failures" % [_checks, _failures])
	print("WS4_SYNC client: %s" % ("PASS" if _failures == 0 else "FAIL"))

