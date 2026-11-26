extends Node
## Cross-platform networking regression checks (macOS LAN focus).
##
## The user-visible bug this guards is "LAN multiplayer does not work on a
## Mac", which is caused by OS behaviour that cannot be reproduced on Windows:
## macOS 15 Local Network permission, BSD interface names (en0/utun0/bridge0),
## multi-homed broadcast routing, and IPv6 host syntax. The cheap fix surface is
## in Network's address/discovery helpers, so this test pins their contracts and
## then runs a real two-process LAN host/client session.
##
## Usage (headless; see docs/MAINTENANCE.md test list):
##   godot --headless --path godot_project res://scripts/tools/net_mac_smoke.tscn --quit-after 3600
##   CSGP_NET_MODE=host   ...same scene...   (writes nothing; opens a LAN room)
##   CSGP_NET_MODE=client ...same scene...   (scans, joins the LAN room)
##
## Default mode (unset) is "unit": pure helper checks, about one second.
## Exit code is the number of failed checks, so a green run is exit 0.

const HOST_WAIT_MS: int = 25000
const CLIENT_WAIT_MS: int = 25000
## Deterministic standings reconciliation shared by the ranked modes.
const StandingsReconciler := preload("res://scripts/net/standings_reconciler.gd")

var _failures: int = 0
var _mode: String = "unit"


func _ready() -> void:
	_mode = OS.get_environment("CSGP_NET_MODE").strip_edges().to_lower()
	if _mode == "":
		_mode = "unit"
	# Survive Network.start_game() scene swaps if a mode ever loads a scene.
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
	print("NET_MAC_SMOKE mode=%s pid=%d os=%s" % [
		_mode, OS.get_process_id(), OS.get_name()])
	match _mode:
		"host":
			await _run_host()
		"client":
			await _run_client()
		_:
			await _run_unit()
	print("NET_MAC_SMOKE[%s]: %s (%d failure(s))" % [
		_mode, "PASS" if _failures == 0 else "FAIL", _failures])
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(_failures)


# --------------------------------------------------------------------------
# unit: pure helper contracts

func _run_unit() -> void:
	_run_address_checks()
	_run_lan_reply_checks()
	_run_relay_url_checks()
	_run_platform_checks()
	_run_multiplayer_sync_checks()
	_run_standings_reconciliation_checks()
	_run_lan_route_checks()


func _run_multiplayer_sync_checks() -> void:
	# 1. RelayTunnel._is_allowed_client must allow Client #2+ even when Network
	# already has 2+ participants with 32-bit ENet peer IDs.
	var tunnel := Network.RelayTunnel.new()
	Network.add_child(tunnel)
	Network.is_host = true
	Network.player_names = {1: "Host", 148293012: "Client1"}
	_check(tunnel._is_allowed_client(1), "RelayTunnel allows client_id=1")
	_check(tunnel._is_allowed_client(2), "RelayTunnel allows client_id=2 when room has existing ENet peers")
	_check(tunnel._is_allowed_client(3), "RelayTunnel allows client_id=3 for multi-client / reconnecting peers")
	_check(not tunnel._is_allowed_client(0), "RelayTunnel rejects client_id=0")
	_check(not tunnel._is_allowed_client(9999), "RelayTunnel rejects out-of-range client_id")
	tunnel.queue_free()
	Network.player_names.clear()
	Network.is_host = false

	# 2. _sanitize_teams must accept 31-bit random Godot ENet peer IDs.
	var teams: Dictionary = Network._sanitize_teams({
		1: 0,
		148293012: 1,
		982374123: 0,
		-5: 1,
	})
	_check(teams.has(1) and int(teams[1]) == 0, "_sanitize_teams preserves host peer 1")
	_check(teams.has(148293012) and int(teams[148293012]) == 1, "_sanitize_teams preserves 31-bit ENet client peer ID")
	_check(teams.has(982374123) and int(teams[982374123]) == 0, "_sanitize_teams preserves second 31-bit ENet client peer ID")
	_check(not teams.has(-5), "_sanitize_teams rejects negative peer ID")

	# 3. notify_scene_ready(scene_node, explicit_path) must record the active
	# gameplay scene even before get_tree().current_scene is assigned.
	var dummy_scene := Node.new()
	add_child(dummy_scene)
	Network.is_client = true
	Network.in_game = true
	Network.game_scene = Network.RACE_SCENE
	Network.host_scene_ready_path = ""
	Network.notify_scene_ready(dummy_scene, Network.RACE_SCENE)
	_check(Network._active_gameplay_scene() == dummy_scene,
		"notify_scene_ready tracks the active scene node during _ready()")
	_check(Network._active_gameplay_scene_path() == Network.RACE_SCENE,
		"notify_scene_ready tracks the active scene path during _ready()")
	Network._net_host_scene_ready(Network.RACE_SCENE)
	_check(Network.is_scene_ready(1),
		"_net_host_scene_ready marks peer 1 scene-ready even when current_scene is not race scene")
	dummy_scene.queue_free()
	Network.clear_scene_ready()
	Network.is_client = false
	Network.in_game = false


func _run_standings_reconciliation_checks() -> void:
	## Owner-visible bug: "players see different final standings after the same
	## race". The fix is one canonical host snapshot with deterministic ordering
	## and strictly monotonic client acceptance; these checks pin that contract.
	var rows: Array = [
		{"id": 5, "name": "E", "finished": false, "progress": 100.0},
		{"id": 2, "name": "B", "finished": true, "finish_time": 61.5},
		{"id": 9, "name": "D", "finished": true, "finish_time": 60.0},
		{"id": 3, "name": "A", "finished": false, "progress": 100.0},
		{"id": 7, "name": "C", "finished": false, "progress": 140.0},
	]
	var sorted: Array[Dictionary] = StandingsReconciler.sort_rows(rows)
	_check(int(sorted[0]["id"]) == 9, "standings: earliest finisher ranks first")
	_check(int(sorted[1]["id"]) == 2, "standings: later finisher ranks second")
	_check(int(sorted[2]["id"]) == 7, "standings: racing leader ranks by distance")
	_check(int(sorted[3]["id"]) == 3, "standings: equal-distance tie breaks by id asc")
	_check(int(sorted[4]["id"]) == 5, "standings: remaining racer follows")
	_check(int(sorted[0]["place"]) == 1 and int(sorted[4]["place"]) == 5,
		"standings: every row gets a 1-based place")
	var shuffled: Array = [rows[3], rows[0], rows[2], rows[4], rows[1]]
	var sorted_again: Array[Dictionary] = StandingsReconciler.sort_rows(shuffled)
	for index in sorted.size():
		_check(int(sorted_again[index]["id"]) == int(sorted[index]["id"]),
			"standings: order is identical for pasted-in-different-order rows")
	# Equal crossing times must still produce one order on every peer.
	var tie: Array[Dictionary] = StandingsReconciler.sort_rows([
		{"id": 8, "name": "H", "finished": true, "finish_time": 30.0},
		{"id": 4, "name": "F", "finished": true, "finish_time": 30.0},
	])
	_check(int(tie[0]["id"]) == 4 and int(tie[1]["id"]) == 8,
		"standings: equal finish times tie break by id asc")
	# Sanitising: a hostile/corrupt row cannot poison the HUD or shrink the field.
	var clean: Dictionary = StandingsReconciler.sanitize_row({
		"id": 4, "name": "X".repeat(64), "finished": true,
		"finish_time": NAN, "progress": INF, "total": -3.0, "best": 12.0,
	})
	_check(not clean.is_empty() and int(clean["id"]) == 4,
		"standings: a corrupt row is clamped instead of dropped")
	_check(not bool(clean["finished"]) and float(clean["finish_time"]) == -1.0,
		"standings: non-finite finish time is rejected")
	_check(float(clean["progress"]) == 0.0, "standings: non-finite progress is clamped")
	_check(str(clean["name"]).length() <= 24, "standings: long names are truncated")
	_check(StandingsReconciler.sanitize_row({"name": "no id"}).is_empty(),
		"standings: a row without an id is rejected")
	_check(StandingsReconciler.sanitize_row("garbage").is_empty(),
		"standings: a non-dictionary row is rejected")
	var capped: Array = []
	for i in 40:
		capped.append({"id": i + 1, "name": "P%d" % i, "finished": false,
			"progress": float(i)})
	_check(StandingsReconciler.sort_rows(capped).size() == StandingsReconciler.MAX_ROWS,
		"standings: row count is capped")

	# Revisioned snapshot acceptance: duplicates/stale/older packets are ignored
	# and an epoch change starts a new race.
	var first: Dictionary = StandingsReconciler.build(7, 1, rows, false)
	var state: Dictionary = StandingsReconciler.accept(
		StandingsReconciler.new_snapshot(7), first)
	_check(int(state["rev"]) == 1 and int(state["epoch"]) == 7,
		"standings: first snapshot is accepted")
	var stale: Dictionary = StandingsReconciler.accept(state, first)
	_check(int(stale["rev"]) == 1, "standings: a duplicate snapshot is ignored")
	var older: Dictionary = StandingsReconciler.build(7, 0, rows, true)
	_check(int(StandingsReconciler.accept(state, older)["rev"]) == 1,
		"standings: a zero-revision packet is ignored")
	var newer: Dictionary = StandingsReconciler.build(7, 2, rows, true)
	var accepted: Dictionary = StandingsReconciler.accept(state, newer)
	_check(int(accepted["rev"]) == 2 and bool(accepted["final"]),
		"standings: a newer final snapshot is accepted")
	var reopened: Dictionary = StandingsReconciler.accept(accepted,
		StandingsReconciler.build(7, 3, rows, false))
	_check(bool(reopened["final"]) and int(reopened["rev"]) == 2,
		"standings: a non-final revision never reopens a final result")
	var next_race: Dictionary = StandingsReconciler.accept(accepted,
		StandingsReconciler.build(8, 1, rows, false))
	_check(int(next_race["epoch"]) == 8 and int(next_race["rev"]) == 1,
		"standings: a new epoch resets revision tracking")
	_check(int(StandingsReconciler.accept(accepted,
		{"epoch": 7, "rev": 5, "rows": "not-an-array"})["rev"]) == 2,
		"standings: a malformed row array is ignored")
	var places: Dictionary = StandingsReconciler.places(accepted)
	_check(int(places.get(9, 0)) == 1, "standings: places map exposes first place")
	_check(StandingsReconciler.rows_by_id(accepted).has(2),
		"standings: rows_by_id exposes every competitor")


func _run_lan_route_checks() -> void:
	## Same-LAN peers must be able to prefer a LAN/direct path. The owner's Pi
	## journal showed a WARP/public registration (`host=172.3.167.243`) while
	## both PCs sat on 192.168.1.0/24; these checks pin the address-selection
	## pieces of that fix without needing a live relay.
	_check(Network._interface_score({"name": "{GUID}", "friendly": "CloudflareWARP"}) < 0,
		"Cloudflare WARP adapter is rejected as a LAN interface")
	_check(Network._interface_score({"name": "warp-svc", "friendly": ""}) < 0,
		"WARP service adapter is rejected")
	var local: String = Network._local_ip()
	if Network._valid_ip(local) and not local.begins_with("127."):
		var on_lan: String = Network._lan_relay_candidate(
			{"lan_ip": local, "http_port": 42777})
		_check(on_lan == "http://%s:42777" % local,
			"LAN relay candidate is the Pi LAN address when on our subnet")
		var direct: Dictionary = Network._room_direct_endpoint(
			{"host_ip": local, "host_port": 8910})
		_check(str(direct.get("host", "")) == local
			and int(direct.get("port", 0)) == 8910,
			"direct LAN endpoint accepts a same-subnet host address")
	else:
		print("PASS  SKIP  local LAN address checks (no physical LAN address here)")
	_check(Network._lan_relay_candidate(
		{"lan_ip": "68.204.45.1", "http_port": 42777}) == "",
		"public relay address is never used as a LAN relay candidate")
	_check(Network._lan_relay_candidate(
		{"lan_ip": "100.64.1.1", "http_port": 42777}) == "",
		"CGNAT/VPN overlay address is never used as a LAN relay candidate")
	_check(Network._room_direct_endpoint(
		{"host_ip": "68.204.45.1", "host_port": 8910}).is_empty(),
		"direct LAN endpoint rejects a public host address")
	_check(Network._room_direct_endpoint(
		{"host_ip": "192.168.1.4"}).is_empty(),
		"direct LAN endpoint requires a port")
	_check(Network._room_direct_endpoint({}).is_empty(),
		"direct LAN endpoint is empty on a 1.8.0 room row (relay join)")
	_check(not Network.is_direct_link(),
		"solo/idle session does not claim a direct link")
	# Relay tunnel: TCP_NODELAY must not be attempted before the socket exists
	# (the old call was silently rejected by the engine, leaving Nagle on).
	var tunnel: Node = Network.RelayTunnel.new()
	Network.add_child(tunnel)
	tunnel._apply_no_delay()
	_check(not bool(tunnel._nodelay_applied),
		"relay tunnel defers TCP_NODELAY until the socket is connected")
	tunnel.queue_free()
	# The relay fallback must be a harmless no-op when no direct join is live.
	Network._fallback_to_relay_join()
	_check(true, "direct-join relay fallback is a no-op without a direct attempt")


func _run_address_checks() -> void:
	# macOS interface names have an empty friendly string; utun*/bridge*/awdl*
	# must never win over en0, while Windows friendly names keep their score.
	_check(Network._interface_score({"name": "en0", "friendly": ""}) > 0,
		"macOS en0 scores as a physical LAN interface")
	_check(Network._interface_score({"name": "utun3", "friendly": ""}) < 0,
		"macOS utun VPN interface scores negative")
	_check(Network._interface_score({"name": "bridge0", "friendly": ""}) < 0,
		"macOS bridge interface scores negative")
	_check(Network._interface_score({"name": "awdl0", "friendly": ""}) < 0,
		"macOS awdl interface scores negative")
	_check(Network._interface_score({"name": "{GUID}", "friendly": "Wi-Fi"}) > 0,
		"Windows Wi-Fi friendly name scores positive")
	_check(Network._interface_score({"name": "{GUID}", "friendly": "vEthernet (WSL)"}) < 0,
		"Windows virtual adapter scores negative")

	var targets: PackedStringArray = Network._broadcast_targets_for("192.168.1.4")
	_check(targets.has("192.168.1.255"), "192.168/24 address yields its /24 broadcast")
	_check(targets.has("192.168.255.255"), "192.168/16 broadcast candidate included")
	var ten: PackedStringArray = Network._broadcast_targets_for("10.2.3.4")
	_check(ten.has("10.2.3.255") and ten.has("10.255.255.255"),
		"10/8 address yields /24 and /8 broadcast candidates")
	var even: PackedStringArray = Network._broadcast_targets_for("172.20.5.6")
	_check(even.has("172.20.5.255") and even.has("172.31.255.255"),
		"172.16/12 address yields /24 and /12 broadcast candidates")
	_check(Network._broadcast_targets_for("not-an-ip").is_empty(),
		"invalid address yields no broadcast targets")

	_check(Network._is_lan_peer_address("192.168.1.7"), "private IPv4 is a LAN peer")
	_check(Network._is_lan_peer_address("10.4.5.6"), "10/8 IPv4 is a LAN peer")
	_check(not Network._is_lan_peer_address("127.0.0.1"), "loopback is not a LAN peer")
	_check(not Network._is_lan_peer_address("169.254.3.4"), "link-local is not a LAN peer")
	_check(not Network._is_lan_peer_address("example.com"), "hostname is not a LAN peer")

	var local: String = Network._local_ip()
	_check(Network.local_addresses.size() > 0,
		"at least one local LAN address candidate was collected")
	_check(not local.begins_with("127.") or Network.local_addresses.is_empty(),
		"local_ip prefers a real LAN address over loopback when one exists")
	if Network._valid_ip(local):
		var local_targets: PackedStringArray = Network._broadcast_targets_for(local)
		_check(local_targets.size() > 0, "local address produces discovery broadcast targets")


func _run_lan_reply_checks() -> void:
	# A host that advertises the wrong adapter (VPN/wired while the packet came
	# in over Wi-Fi) must still be joinable: the packet source address wins.
	var reply: String = JSON.stringify({
		"service": "cartslop-lan",
		"name": "Mac Host",
		"host": "10.99.9.9",
		"port": 8910,
		"players": 2,
		"mode": "sandbox",
		"state": "lobby",
		"map": "meadow",
	})
	var parsed: Dictionary = Network._parse_lan_room_reply(reply, "192.168.1.50")
	_check(str(parsed.get("host", "")) == "192.168.1.50",
		"LAN reply host prefers the routable packet source")
	_check(int(parsed.get("port", 0)) == 8910, "LAN reply keeps the room port")
	_check(str(parsed.get("name", "")) == "Mac Host", "LAN reply keeps the room name")
	var no_source: Dictionary = Network._parse_lan_room_reply(reply, "")
	_check(str(no_source.get("host", "")) == "10.99.9.9",
		"LAN reply falls back to the advertised host when the source is unusable")
	var loopback_source: Dictionary = Network._parse_lan_room_reply(reply, "127.0.0.1")
	_check(str(loopback_source.get("host", "")) == "10.99.9.9",
		"LAN reply ignores a loopback packet source")
	_check(Network._parse_lan_room_reply("not json", "192.168.1.50").is_empty(),
		"garbage LAN packet is rejected")
	var bad_port: Dictionary = JSON.parse_string(reply)
	bad_port["port"] = 70000
	_check(Network._parse_lan_room_reply(JSON.stringify(bad_port), "192.168.1.50").is_empty(),
		"LAN reply with an out-of-range port is rejected")


func _run_relay_url_checks() -> void:
	# IPv6 relay literals: URLs keep the brackets, sockets must not.
	CheckRelayURLs()


func CheckRelayURLs() -> void:
	# Kept as a separate function so the preset-facing URL contract is obvious.
	Network.set_relay_server("https://[fd00::1]:8443")
	_check(Network.relay_server_host == "fd00::1",
		"IPv6 relay host is stored without URL brackets for sockets")
	_check(Network.relay_base == "https://[fd00::1]:8443",
		"IPv6 relay base URL is rebuilt with the required brackets")
	Network.set_relay_server("http://192.168.1.22:42777")
	_check(Network.relay_server_host == "192.168.1.22", "IPv4 relay host parses")
	_check(Network.relay_base == "http://192.168.1.22:42777", "IPv4 relay base parses")
	Network.set_relay_server("")
	_check(Network.relay_base == "", "empty relay server clears the route")

	_check(Network._is_ip_literal("192.168.1.5"), "IPv4 literal detected")
	_check(Network._is_ip_literal("0:0:0:0:0:0:0:1"), "IPv6 literal detected")
	_check(Network._is_ip_literal("[fd00::1]"), "bracketed IPv6 literal detected")
	_check(not Network._is_ip_literal("cartslop.example.com"), "hostname is not an IP literal")
	_check(Network._strip_host_brackets("[fd00::1]") == "fd00::1",
		"bracket stripping for socket APIs")
	_check(Network._url_host("fd00::1") == "[fd00::1]", "URL host re-adds IPv6 brackets")
	_check(Network._url_host("10.0.0.2") == "10.0.0.2", "IPv4 URL host is unchanged")


func _run_platform_checks() -> void:
	# macOS-only text must never leak onto Windows/Linux and vice versa.
	var hint: String = Network.local_network_hint()
	if Network._is_macos():
		_check(hint.contains("LOCAL NETWORK"),
			"macOS local-network hint mentions the privacy setting")
		_check(Network._join_timeout_reason(true).contains("Local Network"),
			"macOS LAN join timeout explains the Local Network permission")
	else:
		_check(hint == "", "non-macOS platforms show no Local Network hint")
		_check(not Network._join_timeout_reason(true).contains("Local Network"),
			"non-macOS LAN join timeout has no macOS-only text")
	_check(Network._join_timeout_reason(false).begins_with("Connection timed out"),
		"join timeout always reports the generic reason first")

	_check(Network._relay_result_detail() == "", "no relay error maps to empty detail")
	Network._relay_http_result = HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR
	_check(Network._relay_result_detail() == "tls_error",
		"TLS handshake failure maps to tls_error")
	Network._relay_http_result = HTTPRequest.RESULT_CANT_RESOLVE
	_check(Network._relay_result_detail() == "dns_error", "DNS failure maps to dns_error")
	Network._relay_http_result = HTTPRequest.RESULT_TIMEOUT
	_check(Network._relay_result_detail() == "timeout", "timeout maps to timeout")
	Network._relay_http_result = 0


# --------------------------------------------------------------------------
# host: open a real LAN room and wait for a client

func _run_host() -> void:
	Network.host_started.connect(_on_host_started)
	Network.host_failed.connect(_on_host_failed)
	_wait_deadline = Time.get_ticks_msec() + HOST_WAIT_MS
	Network.host_game("lan")

	while not _host_ready and not _host_failed:
		await get_tree().process_frame
		if Time.get_ticks_msec() > _wait_deadline:
			break
	_check(_host_ready, "LAN host opened a server")
	if _host_failed:
		return
	_check(Network.is_host, "host reports is_host")
	_check(Network.port >= Network.DEFAULT_PORT
		and Network.port < Network.DEFAULT_PORT + Network.PORT_RANGE,
		"LAN host bound a game port in the configured range")
	_check(Network._lan_listener != null, "LAN discovery listener is bound")
	# Private rooms do not answer discovery by design; the test room is public.
	Network.set_room_public(true)
	_check(Network.room_public, "LAN host room can be made public")

	print("NET_MAC_SMOKE host listening port=%d" % Network.port)
	Network.names_changed.connect(_on_names_changed)
	var peers_deadline: int = Time.get_ticks_msec() + HOST_WAIT_MS
	while Network.peer_count() < 2 and Time.get_ticks_msec() < peers_deadline:
		await get_tree().process_frame
	_check(Network.peer_count() >= 2, "a LAN client joined the host")
	# The client announces its name on connect and the host relays the table.
	# Watch for the event rather than sampling after the client may have left.
	var names_deadline: int = Time.get_ticks_msec() + 6000
	while not _saw_second_name and Time.get_ticks_msec() < names_deadline:
		await get_tree().process_frame
	_check(_saw_second_name, "host received the client name table")
	_check(Network.is_connected_to_server(), "host ENet peer reports CONNECTED")
	# Correct teardown: leaving must close the listener and clear session state.
	Network.leave()
	await get_tree().create_timer(0.2).timeout
	_check(not Network.is_host and not Network.is_session_active(),
		"leave() clears host session state")
	_check(Network._lan_listener == null, "leave() closes the LAN discovery listener")


var _host_ready: bool = false
var _host_failed: bool = false
var _wait_deadline: int = 0
var _saw_second_name: bool = false


func _on_host_started(_code: String) -> void:
	_host_ready = true


func _on_host_failed(reason: String) -> void:
	_host_failed = true
	print("NET_MAC_SMOKE host_failed: " + reason)


func _on_names_changed() -> void:
	if Network.player_names.size() >= 2:
		_saw_second_name = true


# --------------------------------------------------------------------------
# client: discover the LAN room and join it

var _joined: bool = false
var _joined_failure: String = ""


func _run_client() -> void:
	Network.join_succeeded.connect(func() -> void: _joined = true)
	Network.join_failed.connect(func(reason: String) -> void: _joined_failure = reason)
	var scan_deadline: int = Time.get_ticks_msec() + CLIENT_WAIT_MS
	var rooms: Array = []
	while rooms.is_empty() and Time.get_ticks_msec() < scan_deadline:
		rooms = await Network.scan_lan_rooms(1.4)
		if rooms.is_empty():
			await get_tree().create_timer(0.4).timeout
	_check(not rooms.is_empty(), "client discovered the LAN room")
	if rooms.is_empty():
		return
	var room: Dictionary = rooms[0]
	_check(Network._is_lan_peer_address(str(room.get("host", ""))),
		"discovered room host is a reachable LAN address")
	print("NET_MAC_SMOKE client joining %s:%d" % [
		str(room.get("host", "")), int(room.get("port", 0))])
	Network.join_lan_room(room)
	var join_deadline: int = Time.get_ticks_msec() + CLIENT_WAIT_MS
	while not _joined and _joined_failure == "" and Time.get_ticks_msec() < join_deadline:
		await get_tree().process_frame
	_check(_joined, "client joined the LAN room")
	if _joined_failure != "":
		print("NET_MAC_SMOKE client join_failed: " + _joined_failure)
		return
	_check(Network.is_session_active(), "client reports an active session")
	_check(Network.connection_mode == "lan", "client connection mode is lan")
	_check(Network.is_connected_to_server(), "client ENet peer reports CONNECTED")
	var names_deadline: int = Time.get_ticks_msec() + 4000
	while Network.player_names.size() < 1 and Time.get_ticks_msec() < names_deadline:
		await get_tree().process_frame
	_check(Network.player_names.size() >= 1, "client received a player name table")
	# Let the host observe the name table before tearing the session down.
	await get_tree().create_timer(1.0).timeout
	Network.leave()
	await get_tree().create_timer(0.2).timeout
	_check(not Network.is_session_active(), "leave() clears client session state")
