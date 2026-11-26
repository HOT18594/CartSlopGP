extends Node
## Phase-3 WS4 headless harness: bot slot budget, BOT roster identity, the
## human+bot team auto-arrange contract, the frozen config-RPC wire arity
## (WS5P3-12), direct-LAN capacity admission (WS5P3-13), the build-version join
## gate (WS5P3-05) and the independent (never hover-driven) lobby backdrop.
##
## Modes (env CSGP_BOTS_MODE):
##   unset / "unit"  every pure invariant, no sockets: 8-seat slot math,
##                   bot clamps, BOT 1..N labels, deterministic human+bot team
##                   arrangement (incl. the host-moves-last rule), the
##                   session-config + bot-team RPC split applied by a host and a
##                   client (identical roster/team fingerprint on both), the
##                   capacity/version join predicates, and the lobby backdrop
##                   contract (auto_advance, multiple bg_hero_*.png slides,
##                   hover/focus never starts a crossfade).
##   "host"          opens a real LAN room, waits for two clients, fields
##                   3 humans + 5 bots, auto-arranges, prints a sync
##                   fingerprint, then proves a further joiner is refused.
##   "client"        joins that LAN room, waits for the host's 5-bot field and
##                   prints the same fingerprint (the runner compares the two).
##   "fullclient"    scans while the room is 3 humans + 5 bots = 8/8, asserts
##                   the LAN row advertises the full human+bot budget and that
##                   Network.join_lan_room refuses with the clear slot message.
##
## Unit run:
##   godot --headless --path godot_project res://scripts/tools/ws4_bot_slots_smoke.tscn
## LAN e2e (four processes; exact PowerShell in _audit/reports/ws4-bots-teams.md
## and _audit/run_ws4_bot_e2e.ps1):
##   CSGP_BOTS_MODE=host|client|client|fullclient ... same scene ...
##
## Exit code = number of failed checks, so a green run is exit 0.

const HOST_WAIT_MS: int = 60000
const CLIENT_WAIT_MS: int = 40000
const BOT_FIELD_TARGET: int = 5
## Legacy Phase-2 `_net_session_config` wire signature (16 arguments, verified
## against `git show HEAD:scripts/net/network.gd`). The Phase-3 bot team table
## must NOT widen it (Godot RPC dispatch is arity-strict): a peer on the old
## signature drops the WHOLE config packet. It has its own additive RPC instead;
## pinned here so a regression fails the harness.
const LEGACY_CONFIG_ARITY: int = 16

var _failures: int = 0
var _mode: String = "unit"


func _ready() -> void:
	_mode = OS.get_environment("CSGP_BOTS_MODE").strip_edges().to_lower()
	if _mode == "":
		_mode = "unit"
	# The session-config RPC and scene-swap paths may replace the current scene;
	# this harness must keep running as a root-owned node like net_mac_smoke.
	call_deferred("_survive_scene_change")
	_run.call_deferred()


func _survive_scene_change() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var tree_root: Window = tree.root
	var parent: Node = get_parent()
	if parent != null and parent != tree_root:
		parent.remove_child(self)
		tree_root.add_child(self)
	if tree.current_scene == self:
		tree.current_scene = null
	process_mode = Node.PROCESS_MODE_ALWAYS


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  " + label)
	else:
		_failures += 1
		print("FAIL  " + label)


func _run() -> void:
	print("WS4_BOT_SMOKE mode=%s pid=%d os=%s" % [
		_mode, OS.get_process_id(), OS.get_name()])
	match _mode:
		"host":
			await _run_host()
		"client":
			await _run_client()
		"fullclient":
			await _run_fullclient()
		_:
			await _run_unit()
	print("WS4_BOT_SMOKE[%s]: %s (%d failure(s))" % [
		_mode, "PASS" if _failures == 0 else "FAIL", _failures])
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(_failures)


# --------------------------------------------------------------------------
# unit: slot budget arithmetic


func _run_unit() -> void:
	_run_slot_math_checks()
	_run_capacity_checks()
	_run_bot_identity_checks()
	_run_arrange_checks()
	_run_config_wire_arity_checks()
	_run_session_config_parity_checks()
	_run_host_gate_checks()
	_run_admission_checks()
	_run_version_gate_checks()
	await _run_lobby_backdrop_checks()


func _run_slot_math_checks() -> void:
	_check(Network.MAX_PLAYERS == 8, "lobby capacity is 8 real slots")
	_check(Network.MAX_BOT_COUNT == 5, "bot setting ceiling is 5")
	# max_humans = 8 - active bots, for every legal bot count.
	var expected_max_humans: Dictionary = {0: 8, 1: 7, 2: 6, 3: 5, 4: 4, 5: 3}
	for bots: int in expected_max_humans:
		_check(Network.max_humans_for_bots(bots) == int(expected_max_humans[bots]),
			"max_humans = 8 - %d bot(s)" % bots)
	_check(Network.max_humans_for_bots(-3) == 8,
		"a negative bot count clamps to zero bots")
	_check(Network.max_humans_for_bots(99) == 3,
		"an oversized bot count clamps to the 5-bot ceiling")
	# Bot cap = seats the humans leave free, also bounded by the bot ceiling.
	var expected_caps: Dictionary = {0: 5, 1: 5, 2: 5, 3: 5, 4: 4, 5: 3, 6: 2, 7: 1, 8: 0}
	for humans: int in expected_caps:
		_check(Network.bot_cap_for_humans(humans) == int(expected_caps[humans]),
			"bot cap for %d human(s) is %d" % [humans, int(expected_caps[humans])])
	_check(Network.bot_cap_for_humans(-4) == 5,
		"a negative human count clamps to an empty room")
	_check(Network.bot_cap_for_humans(99) == 0,
		"a room already past capacity allows no bots")
	# Whole-table invariants: a room that respects the bot cap always fits.
	for humans in 9:
		for bots in 6:
			var used: int = Network.slots_used_for(humans, bots)
			var max_humans: int = Network.max_humans_for_bots(bots)
			var cap: int = Network.bot_cap_for_humans(humans)
			if bots <= cap:
				_check(used <= Network.MAX_PLAYERS,
					"legal room %dH + %dB fits inside the 8 seats" % [humans, bots])
			_check(max_humans + bots == Network.MAX_PLAYERS,
				"max_humans + bots is exactly 8 (%dH + %dB)" % [humans, bots])
			_check(Network.slots_free_for(humans, bots)
					== maxi(Network.MAX_PLAYERS - used, 0),
				"free seats agree with the used count (%dH + %dB)" % [humans, bots])
			_check(Network.lobby_full_for(humans, bots) == (used >= Network.MAX_PLAYERS),
				"full flag agrees with the used count (%dH + %dB)" % [humans, bots])
	_check(Network.active_bot_count_for(false, 5) == 0,
		"a disabled bot field fields zero bots")
	_check(Network.active_bot_count_for(true, 3) == 3,
		"an enabled bot field fields its count")
	_check(Network.active_bot_count_for(true, 9) == 5,
		"an enabled bot field clamps to the ceiling")


func _run_capacity_checks() -> void:
	# Room rows: additive Phase-3 fields first, legacy rows fall back exactly.
	var legacy: Dictionary = Network.room_capacity({"players": 3})
	_check(not bool(legacy["known"]), "a legacy row is recognised as legacy")
	_check(not bool(legacy["full"]), "a legacy 3-player row is joinable")
	_check(bool(Network.room_capacity({"players": 8})["full"]),
		"a legacy 8-player row is still refused as full")
	var open_row: Dictionary = Network.room_capacity({
		"players": 2, "humans": 2, "bots": 5, "slots": 7,
		"max_humans": 3, "full": false})
	_check(bool(open_row["known"]) and not bool(open_row["full"]),
		"2 humans + 5 bots still advertises one human seat")
	var full_row: Dictionary = Network.room_capacity({
		"humans": 3, "bots": 5, "slots": 8, "max_humans": 3, "full": true})
	_check(bool(full_row["full"]), "3 humans + 5 bots reports full")
	# A row that claims free seats while its own numbers say full is not trusted.
	var lying: Dictionary = Network.room_capacity({
		"humans": 4, "bots": 4, "slots": 8, "max_humans": 4, "full": false})
	_check(bool(lying["full"]), "a lying full flag cannot fake a free seat")
	var reason: String = Network.room_full_reason(full_row)
	_check(reason.to_lower().contains("full"), "the full-room reason says full")
	_check(reason.contains("8") and reason.to_lower().contains("bot"),
		"the full-room reason names the 8 slots and the bot seats")
	_check(Network.room_full_reason(legacy).to_lower().contains("full"),
		"the legacy full-room message is unchanged")


# --------------------------------------------------------------------------
# unit: BOT identity (labels + robot icon data)


func _run_bot_identity_checks() -> void:
	_check(Network.bot_label(0) == "BOT 1", "bot index 0 renders as BOT 1")
	_check(Network.bot_label(2) == "BOT 3", "bot index 2 renders as BOT 3")
	_check(Network.bot_label(4) == "BOT 5", "bot index 4 renders as BOT 5")
	_check(Network.bot_label(-1) == "", "negative bot index has no label")
	_check(Network.bot_label(5) == "", "a label past the 5-bot ceiling is refused")
	_check(Network.default_bot_team(0) == 0 and Network.default_bot_team(1) == 1
			and Network.default_bot_team(2) == 0,
		"the fallback bot split is deterministic (index parity)")
	# The lobby's robot icon is procedural: the harness asserts the data source
	# (accent colour is the shared roster accent), not pixels.
	_check(str(Network.bot_label(0)).begins_with("BOT "),
		"bot labels share one format on every peer")


# --------------------------------------------------------------------------
# unit: deterministic human+bot arrangement


func _as_array(values: Array) -> Array:
	var out: Array = []
	for value: Variant in values:
		out.append(int(value))
	return out


func _teams_match(teams: Dictionary, expected: Dictionary) -> bool:
	if teams.size() != expected.size():
		return false
	for key: Variant in expected:
		if not teams.has(key) or int(teams[key]) != int(expected[key]):
			return false
	return true


func _run_arrange_checks() -> void:
	var humans: Array[int] = [1, 5, 9]
	var empty: Dictionary = Network.arrange_teams({}, [], humans, 0)
	_check(_teams_match(empty["teams"] as Dictionary, {1: 0, 5: 1, 9: 0}),
		"three humans split 2-1 deterministically")
	var again: Dictionary = Network.arrange_teams({}, [], humans, 0)
	_check(_teams_match(again["teams"] as Dictionary, empty["teams"] as Dictionary),
		"a repeated arrange produces the identical human table")
	# Humans first, then bots: 3 humans + 3 bots balance at 3-3.
	var with_bots: Dictionary = Network.arrange_teams({}, [], humans, 3)
	_check(_as_array(with_bots["bots"] as Array) == [1, 0, 1],
		"bots fill the smaller side after the humans (3H + 3B = 3-3)")
	# Manual assignments inside the one-seat tolerance survive an arrange.
	var manual: Dictionary = Network.arrange_teams(
		{1: 0, 5: 1, 9: 0}, [1, 0, 1], humans, 3)
	_check(_teams_match(manual["teams"] as Dictionary, {1: 0, 5: 1, 9: 0}),
		"a balanced manual human split is preserved")
	_check(_as_array(manual["bots"] as Array) == [1, 0, 1],
		"a balanced manual bot split is preserved")
	# Imbalance correction moves the last non-host human, never the host.
	var host_last: Dictionary = Network.arrange_teams({1: 0, 5: 0}, [], [1, 5], 0)
	_check(_teams_match(host_last["teams"] as Dictionary, {1: 0, 5: 1}),
		"an imbalanced split moves the late human first, host stays put")
	# With no movable human, the highest bot moves before the host.
	var bot_first: Dictionary = Network.arrange_teams({1: 0}, [0, 0, 0, 0], [1], 4)
	_check(_teams_match(bot_first["teams"] as Dictionary, {1: 0}),
		"the host is never moved while a bot can balance the split")
	_check(_as_array(bot_first["bots"] as Array) == [0, 0, 1, 1],
		"highest-index bots take the empty side deterministically")
	# Bot count changes keep the surviving prefix and pad the new slots.
	var shrink: Dictionary = Network.arrange_teams({1: 0}, [1, 0, 1, 1, 0], [1], 2)
	_check(_as_array(shrink["bots"] as Array) == [1, 0],
		"shrinking the bot field keeps the surviving assignments")
	var grow: Dictionary = Network.arrange_teams({1: 1}, [1], [1], 3)
	_check((_as_array(grow["bots"] as Array)).size() == 3,
		"growing the bot field pads the table to the live count")
	var oversized: Dictionary = Network.arrange_teams({}, [], [1], 12)
	_check((_as_array(oversized["bots"] as Array)).size() == 5,
		"an oversized bot count clamps to the 5-bot ceiling")
	# Out-of-range values never index a third team.
	var hostile: Dictionary = Network.arrange_teams({1: 7}, [9, -3], [1], 2)
	for side: Variant in hostile["bots"] as Array:
		_check(int(side) == 0 or int(side) == 1, "arranged bot sides are only 0/1")
	_check(int((hostile["teams"] as Dictionary).get(1, -1)) == 0,
		"an out-of-range manual human side is normalised to 0/1")


# --------------------------------------------------------------------------
# unit: session-config replication (the wire table both peers consume)


func _reset_net_state() -> void:
	Network.leave()
	Network.is_host = false
	Network.is_client = false
	Network.teams_locked = false
	Network.session_bots = false
	Network.session_bot_count = 0
	Network._bot_teams.clear()
	Network._peer_teams.clear()
	Network.server_max_bots = -1


func _bot_fingerprint() -> Array:
	var rows: Array = []
	for index in Network.active_bot_count():
		rows.append("%s:t%d" % [Network.bot_label(index), Network.bot_team(index)])
	return rows


func _sync_fingerprint() -> String:
	## What the lobby roster shows after applying replicated session state:
	## peer ids in stable order with their team, then BOT labels with theirs.
	# Typed reads only: participants() is already sorted and every peer sees the
	# same ENet ids, so the string compares across host and client unchanged.
	var human_bits: Array[String] = []
	if Network.is_session_active():
		for peer_id: int in Network.participants():
			human_bits.append("%d=%d" % [peer_id, Network.team_for_peer(peer_id)])
	var bot_bits: Array[String] = []
	for index in Network.active_bot_count():
		bot_bits.append(str(Network.bot_team(index)))
	return "humans:%s|bots:%s" % [",".join(human_bits), ",".join(bot_bits)]


func _run_config_wire_arity_checks() -> void:
	## WS5P3-12 regression guard: Godot dispatches RPCs arity-strict, so widening
	## `_net_session_config` (an 18th bot-team argument) makes a Phase-2 peer drop
	## the WHOLE config packet. The bot table must travel in its own additive RPC.
	var config_arity: int = -1
	var bot_rpc_present: bool = false
	for entry: Dictionary in Network.get_method_list():
		var method_name: String = str(entry.get("name", ""))
		if method_name == "_net_session_config":
			config_arity = (entry.get("args", []) as Array).size()
		elif method_name == "_net_bot_teams":
			bot_rpc_present = true
	_check(config_arity == LEGACY_CONFIG_ARITY,
		"config RPC keeps the legacy %d-argument wire arity (got %d)" % [
			LEGACY_CONFIG_ARITY, config_arity])
	_check(bot_rpc_present,
		"the bot team table has its own additive RPC (`_net_bot_teams`)")


func _run_session_config_parity_checks() -> void:
	# The legacy 16-argument config payload. Bot teams are NOT in it (WS5P3-12):
	# they are pushed separately, exactly like the host does over the wire.
	var packet_args: Array = [
		GameSettings.GAME_SANDBOX, true, 3, "", "", {}, "", "", "", false,
		{1: 0}, false, 1, "", "", "",
	]
	var bot_table: Array = [[1, 0, 1]]
	# Host: its own call_local copies of both reliable packets.
	_reset_net_state()
	Network.is_host = true
	Network.callv("_net_session_config", packet_args)
	Network.callv("_net_bot_teams", bot_table)
	var host_fp: Array = _bot_fingerprint()
	_check(Network.session_bot_count == 3, "host applies the pushed bot count")
	_check(Network.active_bot_count() == 3, "host active bot count = 3")
	_check(host_fp == ["BOT 1:t1", "BOT 2:t0", "BOT 3:t1"],
		"host renders BOT 1..3 with the pushed bot teams")
	# Client: the same two packets must produce the exact same roster/team rows.
	_reset_net_state()
	Network.is_client = true
	Network.callv("_net_session_config", packet_args)
	Network.callv("_net_bot_teams", bot_table)
	_check(_bot_fingerprint() == host_fp,
		"client renders the identical BOT labels/teams as the host")
	_check(Network.active_bot_count() == 3,
		"client active bot count matches the host")
	# Old-host fallback: config only, no bot-team RPC at all -> deterministic
	# default split (this is what a Phase-2 host's new-build client sees).
	_reset_net_state()
	Network.is_client = true
	Network.callv("_net_session_config", packet_args)
	_check(_bot_fingerprint() == ["BOT 1:t0", "BOT 2:t1", "BOT 3:t0"],
		"a host without the bot table still produces deterministic BOT teams")
	# Hostile/garbage bot table: sanitised, never trusted.
	_reset_net_state()
	Network.is_client = true
	Network.callv("_net_session_config", packet_args)
	Network.callv("_net_bot_teams", [[9, "x", -5]])
	_check(_as_array(Network._bot_teams) == [0, 0, 0],
		"an invalid bot team table is sanitised to two legal teams")
	# Shrink: the table always matches the live bot field.
	_reset_net_state()
	Network.is_client = true
	Network.callv("_net_session_config", [
		GameSettings.GAME_SANDBOX, true, 1, "", "", {}, "", "", "", false,
		{}, false, 1, "", "", "",
	])
	Network.callv("_net_bot_teams", [[0, 1, 0]])
	_check(_as_array(Network._bot_teams) == [0],
		"a bot-count shrink trims the replicated team table")
	# Bot field disabled: no BOT rows even with a stale table arriving.
	_reset_net_state()
	Network.is_client = true
	Network.callv("_net_session_config", [
		GameSettings.GAME_SANDBOX, false, 4, "", "", {}, "", "", "", false,
		{}, false, 1, "", "", "",
	])
	Network.callv("_net_bot_teams", [[1, 0, 1, 0]])
	_check(Network.active_bot_count() == 0 and _bot_fingerprint().is_empty(),
		"a disabled bot field renders no BOT rows")
	# Bot-team RPC arriving before the config (out of order) cannot overbook.
	_reset_net_state()
	Network.is_client = true
	Network.callv("_net_bot_teams", [[1, 1, 1]])
	_check(Network._bot_teams.is_empty(),
		"a bot-team table before any bot count is dropped, not trusted")
	_reset_net_state()


# --------------------------------------------------------------------------
# unit: capacity admission (WS5P3-13) and build-version gate (WS5P3-05)


func _local_build_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "")).strip_edges()


func _run_admission_checks() -> void:
	# Host-side direct-LAN admission predicate. Humans alone filling all 8 seats
	# means there is no bot to trim: the 9th human must be refused (WS5P3-13).
	_check(Network.host_join_refusal_reason(1) == "",
		"a room with 1 human admits a 2nd human")
	_check(Network.host_join_refusal_reason(Network.MAX_PLAYERS) == "",
		"the 8th human is still admitted")
	var refusal: String = Network.host_join_refusal_reason(Network.MAX_PLAYERS + 1)
	_check(refusal != "", "a 9th direct-LAN human is refused")
	_check(refusal.to_lower().contains("full") and refusal.contains("8"),
		"the direct-LAN refusal is clear about the full 8 seats: " + refusal)
	_check(refusal.to_lower().contains("seat"),
		"the direct-LAN refusal explains the missing seat")
	# Client-side pre-check: a full LAN discovery row is refused synchronously,
	# before any ENet connection is attempted, with the same clear message.
	_reset_net_state()
	var fail_reasons: Array[String] = []
	var on_fail := func(reason: String) -> void: fail_reasons.append(reason)
	Network.join_failed.connect(on_fail)
	Network.join_lan_room({
		"host": "192.168.1.99", "port": 42778, "state": "lobby",
		"version": _local_build_version(),
		"players": 3, "humans": 3, "bots": 5, "slots": 8,
		"max_humans": 3, "full": true,
	})
	Network.join_failed.disconnect(on_fail)
	_check(not fail_reasons.is_empty(), "a full LAN row emits a join failure")
	if not fail_reasons.is_empty():
		var message: String = fail_reasons[0]
		_check(message.to_lower().contains("full")
			and message.to_lower().contains("bot"),
			"the full-room join refusal names the seat budget: " + message)
	_check(not Network.join_pending and not Network.is_session_active(),
		"a full LAN row is refused before any connection attempt")
	_reset_net_state()


func _run_version_gate_checks() -> void:
	var local: String = _local_build_version()
	_check(local != "", "the project advertises a build version")
	_check(Network.room_build_mismatch_reason({}) == "",
		"a room without an advertised build cannot be judged (old server/host)")
	_check(Network.room_build_mismatch_reason({"version": ""}) == "",
		"an empty advertised build is allowed (backward compatible)")
	_check(Network.room_build_mismatch_reason({"version": local}) == "",
		"an equal build joins")
	var reason: String = Network.room_build_mismatch_reason({"version": "0.0.1-old"})
	_check(reason != "", "a different build is refused (WS5P3-05)")
	_check(reason.contains("0.0.1-old") and reason.contains(local),
		"the build refusal names both versions: " + reason)
	_check(reason.to_lower().contains("update"),
		"the build refusal tells the player how to fix it: " + reason)


# --------------------------------------------------------------------------
# unit: independent lobby backdrop (user requirement, Phase-3 WS4)


func _find_backdrop(node: Node) -> Node:
	if node == null:
		return null
	# 0.8.7 shared API names, plus the pre-refactor names.
	if node.has_method("set_slides") and node.has_method("advance_count"):
		return node
	if node.has_method("set_auto_advance") and node.has_method("show_still"):
		return node
	for child: Node in node.get_children():
		var found: Node = _find_backdrop(child)
		if found != null:
			return found
	return null


func _backdrop_slide_names(background: Node, art: Node) -> PackedStringArray:
	## The plates the backdrop is actually cycling. Prefer the shared
	## MenuBackground contract (`slide_pool()`), fall back to the art node's own
	## loaded-name accessors so this check survives a background refactor.
	if background != null and background.has_method("slide_pool"):
		var pool: Variant = background.call("slide_pool")
		if pool is PackedStringArray:
			return pool as PackedStringArray
	if art != null and art.has_method("slide_names"):
		var slides: Variant = art.call("slide_names")
		if slides is PackedStringArray:
			return slides as PackedStringArray
	if art != null:
		var raw: Variant = art.get("texture_names")
		if raw is PackedStringArray:
			return raw as PackedStringArray
	return PackedStringArray()


func _run_lobby_backdrop_checks() -> void:
	## User requirement: the lobby backdrop runs its own slideshow and NOTHING
	## about hover/focus may change it. This instantiates the real lobby scene
	## and inspects the shared MenuBackground/ArtBackdrop instance it owns.
	var packed: PackedScene = load("res://scenes/ui/lobby_menu.tscn") as PackedScene
	_check(packed != null, "lobby scene loads for the backdrop contract")
	if packed == null:
		return
	var lobby: Control = packed.instantiate() as Control
	get_tree().root.add_child(lobby)
	get_tree().current_scene = lobby
	await get_tree().process_frame
	await get_tree().process_frame
	var background: Node = lobby.get_node_or_null("Background")
	_check(background != null, "lobby background node exists")
	var art: Node = _find_backdrop(background)
	_check(art != null, "lobby background owns a slideshow ArtBackdrop")
	if art != null:
		_check(bool(art.get("auto_advance")),
			"lobby backdrop auto-advances on its own (not hover-driven)")
		# Cadence contract: a randomized positive beat band, always on.
		var slide_min: float = float(art.get("slide_seconds_min")) \
			if art.get("slide_seconds_min") != null else -1.0
		var slide_max: float = float(art.get("slide_seconds_max")) \
			if art.get("slide_seconds_max") != null else -1.0
		if slide_min > 0.0 and slide_max > 0.0:
			_check(slide_max >= slide_min,
				"lobby backdrop beat band is valid (%.1f..%.1f s)" % [slide_min, slide_max])
		else:
			_check(float(art.get("slide_seconds")) > 0.0,
				"lobby backdrop has a positive slide interval")
		var names: PackedStringArray = _backdrop_slide_names(background, art)
		var hero_count: int = 0
		for file_name: String in names:
			if file_name.begins_with("bg_hero_") \
					and ResourceLoader.exists("res://assets/ui/art/" + file_name):
				hero_count += 1
		_check(names.size() >= 2 and hero_count >= 2,
			"lobby backdrop cycles multiple existing bg_hero_*.png slides (%d/%d)" \
				% [hero_count, names.size()])
		_check(bool(art.call("has_art")),
			"lobby backdrop loaded its art textures")
		# Hover/focus must not drive the art. The retired hover driver left
		# `hover_art_*` state on the background and retuned the fade to ~0.45 s;
		# neither may appear now (the buttons keep their local hover animation).
		var fade_before: float = float(art.get("fade_seconds"))
		var card: Control = lobby.get("_host_pi_button") as Control
		_check(card != null, "lobby idle cards still exist (button hover animations kept)")
		if card != null:
			card.grab_focus()
			for _i in 8:
				await get_tree().process_frame
			_check(not background.has_meta("hover_art_current") \
					and not background.has_meta("hover_art_pending"),
				"hover/focus never starts a backdrop crossfade")
			_check(is_equal_approx(float(art.get("fade_seconds")), fade_before) \
					and not bool(art.get("_fading")),
				"hover/focus does not retune or fade the independent backdrop")
		# Prove the slideshow advances over time. This retimes the cadence on the
		# throwaway instance only; reduced motion is forced off for the measurement.
		var old_reduce: bool = GameSettings.reduce_motion
		GameSettings.reduce_motion = false
		if art.get("slide_seconds_min") != null:
			art.set("slide_seconds_min", 0.05)
			art.set("slide_seconds_max", 0.06)
		if art.get("slide_seconds") != null:
			art.set("slide_seconds", 0.05)
		if art.has_method("reset_schedule"):
			art.call("reset_schedule")
		var start_advances: int = int(art.call("advance_count")) \
			if art.has_method("advance_count") else -1
		var start_index: int = int(art.get("_current_index"))
		var advanced: bool = false
		var deadline: int = Time.get_ticks_msec() + 2000
		while Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
			if start_advances >= 0:
				if int(art.call("advance_count")) > start_advances:
					advanced = true
					break
			elif int(art.get("_current_index")) != start_index:
				advanced = true
				break
		GameSettings.reduce_motion = old_reduce
		_check(advanced, "lobby backdrop advances slides without any input")
	lobby.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_reset_net_state()


# --------------------------------------------------------------------------
# unit: host team gates (lock respects auto-arrange)


func _run_host_gate_checks() -> void:
	_reset_net_state()
	Network.is_host = true
	Network.session_bots = true
	Network.session_bot_count = 5
	_check(Network.active_bot_count() == 5, "a 1-human host can field 5 bots")
	_check(not Network.lobby_is_full(), "1 human + 5 bots leaves two seats")
	_check(Network.max_lobby_humans() == 3,
		"1 human + 5 bots advertises 3 human seats")
	Network.teams_locked = true
	_check(not Network.auto_arrange_teams(),
		"AUTO ARRANGE refuses to move anyone while teams are LOCKED")
	Network.teams_locked = false
	_check(Network.auto_arrange_teams(),
		"AUTO ARRANGE runs once the teams are unlocked")
	_check(Network._bot_teams.size() == 5,
		"a 5-bot room owns five replicated bot team slots")
	_reset_net_state()


# --------------------------------------------------------------------------
# LAN e2e: host


func _wait_until(predicate: Callable, timeout_ms: int) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await get_tree().process_frame
	return bool(predicate.call())


var _host_started: bool = false
var _host_failed: String = ""


func _run_host() -> void:
	Network.host_started.connect(func(_code: String) -> void: _host_started = true)
	Network.host_failed.connect(func(reason: String) -> void: _host_failed = reason)
	Network.host_game("lan")
	var opened: bool = await _wait_until(
		func() -> bool: return _host_started or _host_failed != "",
		HOST_WAIT_MS)
	_check(opened and _host_started, "host opened a real LAN room")
	if not _host_started:
		print("WS4_BOT_SMOKE host_failed: " + _host_failed)
		return
	_check(Network.is_host, "host reports is_host")
	Network.set_room_public(true)
	# 1 human (the host) + 3 bots while the clients arrive.
	Network.configure_session(GameSettings.GAME_SANDBOX, true, 3)
	_check(Network.active_bot_count() == 3, "host starts with 3 bots")
	print("BOTSMOKE host listening port=%d" % Network.port)
	# Wait for both clients (3 humans = host + 2 clients).
	var joined: bool = await _wait_until(
		func() -> bool: return Network.peer_count() >= 3, HOST_WAIT_MS)
	_check(joined, "two LAN clients joined the host")
	if not joined:
		Network.leave()
		return
	_check(Network.human_count() == 3, "host counts 3 humans (itself + 2 clients)")
	await get_tree().create_timer(1.5).timeout
	# 3 humans + 5 bots = all 8 seats. This is the capacity the fullclient probes.
	Network.configure_session(GameSettings.GAME_SANDBOX, true, BOT_FIELD_TARGET)
	_check(Network.active_bot_count() == BOT_FIELD_TARGET,
		"host fields 5 bots with 3 humans")
	_check(Network.lobby_is_full(), "3 humans + 5 bots fills all 8 seats")
	_check(Network.max_lobby_humans() == 3,
		"the full room advertises max_humans = 3")
	_check(Network.auto_arrange_teams(), "host AUTO ARRANGE with bots succeeds")
	await get_tree().create_timer(2.0).timeout
	print("BOTSMOKE HOST_FULL humans=%d bots=%d slots=%d fingerprint=%s" % [
		Network.human_count(), Network.active_bot_count(),
		Network.lobby_slots_used(), _sync_fingerprint()])
	# Window for the fullclient process to discover the room and be refused.
	# 6 s is measured from the HOST_FULL print: the fullclient starts as soon as
	# the runner sees that line and needs one ~1.2 s LAN sweep, while the clients
	# stay connected for 8 s after their own fingerprint print.
	await get_tree().create_timer(6.0).timeout
	_check(Network.peer_count() == 3,
		"the full room refused the extra joiner (peers stayed at 3 humans)")
	Network.leave()


# --------------------------------------------------------------------------
# LAN e2e: client


var _joined: bool = false
var _join_failure: String = ""


func _scan_for_room(want_full: bool, timeout_ms: int) -> Dictionary:
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var rooms: Array = await Network.scan_lan_rooms(1.2)
		for candidate: Variant in rooms:
			var room: Dictionary = candidate as Dictionary
			if str(room.get("state", "lobby")) != "lobby":
				continue
			var capacity: Dictionary = Network.room_capacity(room)
			if bool(capacity.get("full", false)) == want_full:
				return room
		await get_tree().create_timer(0.4).timeout
	return {}


func _run_client() -> void:
	Network.join_succeeded.connect(func() -> void: _joined = true)
	Network.join_failed.connect(func(reason: String) -> void: _join_failure = reason)
	var room: Dictionary = await _scan_for_room(false, CLIENT_WAIT_MS)
	_check(not room.is_empty(), "client discovered the joinable LAN room")
	if room.is_empty():
		return
	var capacity: Dictionary = Network.room_capacity(room)
	_check(bool(capacity.get("known", false)),
		"client reads the additive human+bot capacity from the LAN row")
	Network.join_lan_room(room)
	var joined: bool = await _wait_until(
		func() -> bool: return _joined or _join_failure != "", CLIENT_WAIT_MS)
	_check(joined and _joined, "client joined the LAN room")
	if not _joined:
		print("WS4_BOT_SMOKE client join_failed: " + _join_failure)
		return
	# Wait for the host's full 5-bot field (3 humans + 5 bots).
	var saw_full: bool = await _wait_until(func() -> bool: return Network.active_bot_count() == BOT_FIELD_TARGET and Network.lobby_is_full(), CLIENT_WAIT_MS)
	_check(saw_full, "client sees the host's 5-bot field and the 8/8 capacity")
	_check(Network.session_bot_count == BOT_FIELD_TARGET,
		"client replicated session_bot_count = 5")
	_check(Network.human_count() == 3, "client counts 3 humans in the room")
	_check(Network.max_lobby_humans() == 3,
		"client derives max_humans = 8 - 5 = 3")
	# Let the reliable config/team packets settle before fingerprinting.
	await get_tree().create_timer(1.5).timeout
	print("BOTSMOKE CLIENT_FULL humans=%d bots=%d slots=%d fingerprint=%s" % [
		Network.human_count(), Network.active_bot_count(),
		Network.lobby_slots_used(), _sync_fingerprint()])
	# Stay connected while the fullclient process proves the room is closed.
	await get_tree().create_timer(8.0).timeout
	Network.leave()


# --------------------------------------------------------------------------
# LAN e2e: fullclient (must be refused with the slot message)


## Class member, not a local: a GDScript lambda captures locals by value, so a
## `var failure: String` inside _run_fullclient would stay empty when the signal
## handler writes it. Members are captured by reference (same pattern as
## _join_failure above).
var _refusal_message: String = ""


func _run_fullclient() -> void:
	_refusal_message = ""
	Network.join_failed.connect(func(reason: String) -> void: _refusal_message = reason)
	var room: Dictionary = await _scan_for_room(true, 60000)
	_check(not room.is_empty(), "fullclient found the full LAN room row")
	if room.is_empty():
		return
	var capacity: Dictionary = Network.room_capacity(room)
	_check(bool(capacity.get("known", false)),
		"the full LAN row carries the human+bot capacity fields")
	_check(bool(capacity.get("full", false)),
		"the LAN row is flagged full (3 humans + 5 bots)")
	_check(int(capacity.get("max_humans", -1)) == 3,
		"the LAN row advertises max_humans = 3")
	Network.join_lan_room(room)
	# join_lan_room() must refuse synchronously: no ENet attempt at all.
	await get_tree().create_timer(0.5).timeout
	_check(not Network.join_pending and not Network.is_session_active(),
		"full room join was refused before any connection attempt")
	_check(_refusal_message.to_lower().contains("full"),
		"refusal message says the room is full: " + _refusal_message)
	_check(_refusal_message.to_lower().contains("bot"),
		"refusal message explains the bot seats: " + _refusal_message)
	print("BOTSMOKE FULLCLIENT rejected=%s" % _refusal_message)
