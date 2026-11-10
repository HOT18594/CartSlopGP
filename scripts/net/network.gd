extends Node
## Multiplayer session manager.
##
## There are exactly two ways to start a multiplayer world:
##   1. HOST LAN  - this PC is the server; players on the same Wi-Fi find it.
##   2. HOST PI   - this PC registers with the Cart Slop Pi, which returns a
##                  5-letter room code. Clients join with that code only.
## Joining never accepts an IP address or a hand-built address code. A room
## join always goes through the Pi server (or the LAN host that advertises
## itself as a server).

signal host_started(code: String)
signal host_failed(reason: String)
signal join_status_changed(text: String)
signal join_succeeded()
signal join_failed(reason: String)
signal session_ended(reason: String)
signal peers_changed()
signal names_changed()
signal latency_changed(ms: int)
signal code_updated(code: String)
signal session_config_changed()
signal server_status_changed(online: bool, detail: String)
signal tag_colors_changed()
signal ping_table_changed()

const DEFAULT_PORT: int = 8910
const PORT_RANGE: int = 40
const MAX_PLAYERS: int = 8
const GAME_SCENE: String = "res://scenes/sandbox/sandbox.tscn"
const RACE_SCENE: String = "res://scenes/minigames/grass_race.tscn"
const LOBBY_SCENE: String = "res://scenes/ui/lobby_menu.tscn"
const MINIGAMES_SCENE: String = "res://scenes/ui/minigames_menu.tscn"
const PING_INTERVAL: float = 2.0
const RELAY_DISCOVERY_PORT: int = 42778
const LAN_ROOM_PORT: int = 42779
const RELAY_HEARTBEAT_INTERVAL: float = 20.0
const DISCOVERY_TIMEOUT_MS: int = 1200
const RELAY_HTTP_TIMEOUT: float = 4.0
## Built-in relay address, used for internet joins when LAN discovery finds
## nothing. It is never shown to the player and never typed into a field;
## CARTSLOP_RELAY can point a build at a different relay for testing.
const DEFAULT_RELAY_SERVER: String = "68.204.45.1:42777"
const ROOM_CODE_ALPHABET: String = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const ALLOWED_SCENES: Array[String] = [GAME_SCENE, RACE_SCENE]
const MAX_BOT_COUNT: int = 5
const MAX_LOBBY_ENTRIES: int = 200
const MAX_HTTP_BODY: int = 1024 * 1024
const RelayTunnel := preload("res://scripts/net/relay_tunnel.gd")

# A reliable scene-start message can land before the client has finished
# changing scenes. Retry for any peer that has not announced ready, but keep
# the retry bounded: a peer stuck in the lobby must not be spammed forever.
const SCENE_RETRY_INTERVAL: float = 5.0
const SCENE_RETRY_MAX: int = 6
const WORLD_BOUND_SQ: float = 5000.0 * 5000.0

var is_host: bool = false
var is_client: bool = false
var in_game: bool = false
var join_code: String = ""
var local_address: String = ""
var public_address: String = ""
var port: int = DEFAULT_PORT
var latency_ms: int = 0
var last_error: String = ""
var connection_mode: String = "pi" ## "lan" (this PC) or "pi" (room service).
var player_names: Dictionary = {} ## peer id -> sanitized display name
var player_colors: Dictionary = {} ## peer id -> name tag Color
var ping_table: Dictionary = {} ## peer id -> that peer's ping to the server (ms)
var join_pending: bool = false
var room_state: String = "lobby" ## "lobby" | "playing" | "finished"
## Host's room discovery setting. Private rooms are joinable by code only;
## public rooms appear in the browser and can be joined with one click.
var room_public: bool = false
## Set while a multiplayer pause menu is open so the live world cannot keep
## driving/boosting from mouse or keyboard input behind the menu.
var input_locked: bool = false
var server_online: bool = false
var server_detail: String = "checking"
## Peers that have loaded the current gameplay scene. Gameplay RPCs are only
## sent to these peers; otherwise a peer still in the lobby makes Godot log
## "Node not found: Sandbox" for every 20 Hz state packet.
var scene_ready_peers: Dictionary = {}
## Peers that deliberately returned to the lobby. The host must not keep
## forcing them back into a race they chose to leave.
var _left_scene_peers: Dictionary = {}
var _scene_sync_timer: float = 0.0
var _scene_load_path: String = ""
## Pair key -> last resting-separation impulse time. Prevents a stale ghost
## from being pushed every physics tick while it rests against the host cart.
var _separation_ms: Dictionary = {}
var relay_base: String = ""
var relay_lan_ip: String = ""
var relay_token: String = ""
var relay_port: int = 0
var relay_lan_host: String = ""
var relay_public_host: String = ""
var relay_active: bool = false
var relay_room_code: String = ""
## Optional relay address (hostname, IP, or URL) used for internet joins.
var relay_server_url: String = ""
var relay_server_host: String = ""
var relay_server_http_port: int = 42777
var relay_base_public: bool = false
var relay_tunnel_token: String = ""
var relay_tunnel_port: int = 0
var relay_tunnel_active: bool = false
var _relay_tunnel: Node = null
var _lan_listener: PacketPeerUDP = null
var _relay_forced: bool = false

## Host-chosen configuration, broadcast with _net_begin_game so every peer
## loads the same world with the same bots. Clients never write these locally.
var game_scene: String = GAME_SCENE
var session_mode: String = GameSettings.GAME_SANDBOX
var session_bots: bool = false
var session_bot_count: int = 0
var session_minigame: String = "meadow_loop"
var race_standings: Array[Dictionary] = [] ## peer id/name/time/place, filled by the race.

var _peer: ENetMultiplayerPeer
var _host_ticket: int = 0
var _join_ticket: int = 0
var _ping_timer: float = 0.0
var _join_started_ms: int = 0
var _relay_heartbeat: float = 0.0
var _relay_busy: bool = false
var _heartbeat_failures: int = 0
## Shared seed for a race's bot field, generated by the host and sent with
## _net_begin_game so every peer builds the same names, cars and placements.
var race_seed: int = 0

## Bounded, idempotent scene-start retries.
var _scene_retry_counts: Dictionary = {} ## peer id -> retry count



func _rpc_sender() -> int:
	## RPCs can still be queued when a peer is tearing down; never dereference
	## a null multiplayer peer.
	return multiplayer.get_remote_sender_id() if multiplayer.multiplayer_peer != null else 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# There is no user-configurable server address. Tests may call
	# set_relay_server() explicitly, but saved legacy values are ignored.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
	_poll_lan_listener()
	_relay_heartbeat_tick(delta)
	if join_pending and Time.get_ticks_msec() - _join_started_ms > 12000:
		join_pending = false
		leave()
		join_failed.emit("Connection timed out. The room may have closed, or the server is unreachable.")
		return
	if not is_session_active() or not is_connected_to_server():
		return
	_scene_sync_timer += delta
	if is_host and in_game and _scene_sync_timer >= SCENE_RETRY_INTERVAL:
		_scene_sync_timer = 0.0
		_host_retry_scene_start()
	_ping_timer += delta
	if _ping_timer >= PING_INTERVAL:
		_ping_timer = 0.0
		if not is_host:
			rpc_id(1, "_net_ping", Time.get_ticks_msec())


func _host_retry_scene_start() -> void:
	## Re-send the current game start to peers that have not announced scene
	## readiness yet. Each peer gets a fixed retry budget; after that we stop
	## and leave it to a fresh ready RPC or a reconnect. This keeps a peer that
	## is still in the lobby from being pounded by reliable packets forever.
	for peer_id: int in multiplayer.get_peers():
		if scene_ready_peers.has(peer_id):
			_scene_retry_counts.erase(peer_id)
			continue
		if _left_scene_peers.has(peer_id):
			# The player chose to go back to the lobby. Forcing the race back
			# onto them would yank them out of the menu every five seconds.
			continue
		var attempts: int = int(_scene_retry_counts.get(peer_id, 0))
		if attempts >= SCENE_RETRY_MAX:
			continue
		_scene_retry_counts[peer_id] = attempts + 1
		rpc_id(peer_id, "_net_begin_game", game_scene, session_mode,
			session_bots, session_bot_count, race_seed)


func is_session_active() -> bool:
	return is_host or is_client


func clear_scene_ready() -> void:
	scene_ready_peers.clear()
	_left_scene_peers.clear()
	_scene_retry_counts.clear()
	_separation_ms.clear()
	_scene_load_path = ""
	if is_host:
		scene_ready_peers[1] = true


func is_scene_ready(peer_id: int) -> bool:
	return scene_ready_peers.has(peer_id)


func mark_peer_scene_ready(peer_id: int) -> void:
	if is_host and peer_id > 0:
		scene_ready_peers[peer_id] = true
		_left_scene_peers.erase(peer_id)


func _cart_extents(cart: Node) -> Dictionary:
	if cart.has_method("get_collision_extents"):
		return cart.call("get_collision_extents")
	return {"width": 1.50, "length": 2.26, "height": 1.70}


func _obb_contact(offset: Vector3, yaw_a: float, yaw_b: float,
		ext_a: Dictionary, ext_b: Dictionary) -> Dictionary:
	## 2D oriented-box overlap on the ground plane. The old fixed 2.40 m
	## circle fired at empty air beside a sedan and let trucks interpenetrate.
	var half_a := Vector2(float(ext_a.get("width", 1.5)) * 0.5,
		float(ext_a.get("length", 2.26)) * 0.5)
	var half_b := Vector2(float(ext_b.get("width", 1.5)) * 0.5,
		float(ext_b.get("length", 2.26)) * 0.5)
	var a_right: Vector3 = Basis(Vector3.UP, yaw_a) * Vector3.RIGHT
	var a_forward: Vector3 = Basis(Vector3.UP, yaw_a) * Vector3.FORWARD
	var b_right: Vector3 = Basis(Vector3.UP, yaw_b) * Vector3.RIGHT
	var b_forward: Vector3 = Basis(Vector3.UP, yaw_b) * Vector3.FORWARD
	var axes: Array[Vector3] = [a_right, a_forward, b_right, b_forward]
	var min_overlap: float = INF
	var best_axis: Vector3 = Vector3.ZERO
	for axis: Vector3 in axes:
		var radius_a: float = (absf(axis.dot(a_right)) * half_a.x
			+ absf(axis.dot(a_forward)) * half_a.y)
		var radius_b: float = (absf(axis.dot(b_right)) * half_b.x
			+ absf(axis.dot(b_forward)) * half_b.y)
		var distance: float = absf(offset.dot(axis))
		var overlap: float = radius_a + radius_b - distance
		if overlap <= 0.0:
			return {}
		if overlap < min_overlap:
			min_overlap = overlap
			best_axis = axis if offset.dot(axis) >= 0.0 else -axis
	if min_overlap == INF or best_axis.length_squared() < 0.001:
		return {}
	return {"normal": best_axis.normalized(), "penetration": min_overlap}


func resolve_car_collisions(local_cart: Node, remotes: Dictionary) -> void:
	## The host resolves every contact each physics tick. Momentum handles the
	## impact; a bounded separation impulse handles resting contact and pushing.
	if not is_host or local_cart == null:
		return
	var host_id: int = multiplayer.get_unique_id()
	var pairs: Array = []
	if remotes.size() > 0:
		for peer_id: Variant in remotes.keys():
			pairs.append([host_id, local_cart, int(peer_id), remotes[peer_id]])
	var ids: Array = remotes.keys()
	ids.sort()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			pairs.append([int(ids[i]), remotes[ids[i]], int(ids[j]), remotes[ids[j]]])
	for pair: Array in pairs:
		var id_a: int = int(pair[0])
		var cart_a: Node = pair[1]
		var id_b: int = int(pair[2])
		var cart_b: Node = pair[3]
		if cart_a == null or cart_b == null:
			continue
		# A finished cart is not an obstacle. Ghosts keep contact_enabled=true
		# even though their body layer is 0; the host solver owns that contact.
		if cart_a.get("contact_enabled") == false:
			continue
		if cart_b.get("contact_enabled") == false:
			continue
		if id_a != host_id and not is_scene_ready(id_a):
			continue
		if id_b != host_id and not is_scene_ready(id_b):
			continue
		var pos_a: Vector3 = cart_a.global_position
		var pos_b: Vector3 = cart_b.global_position
		# A peer can send NaN/Inf or an absurd coordinate. Reject it before it
		# can corrupt the lobby.
		if not pos_a.is_finite() or not pos_b.is_finite():
			continue
		if pos_a.length_squared() > WORLD_BOUND_SQ or pos_b.length_squared() > WORLD_BOUND_SQ:
			continue
		var ext_a: Dictionary = _cart_extents(cart_a)
		var ext_b: Dictionary = _cart_extents(cart_b)
		var contact_height: float = maxf(
			float(ext_a.get("height", 1.70)),
			float(ext_b.get("height", 1.70)))
		if absf(pos_b.y - pos_a.y) > contact_height * 0.95:
			continue
		var offset: Vector3 = pos_b - pos_a
		offset.y = 0.0
		var contact: Dictionary = _obb_contact(
			offset, cart_a.global_rotation.y, cart_b.global_rotation.y,
			ext_a, ext_b)
		if contact.is_empty():
			continue
		var normal: Vector3 = contact["normal"]
		var penetration: float = float(contact["penetration"])
		var vel_a: Vector3 = cart_a.call("get_collision_velocity")
		var vel_b: Vector3 = cart_b.call("get_collision_velocity")
		if not vel_a.is_finite() or not vel_b.is_finite():
			continue
		var relative: Vector3 = vel_a - vel_b
		var closing: float = maxf(relative.dot(normal), 0.0)
		if not is_finite(closing):
			continue
		var pair_key: String = "%d:%d" % [mini(id_a, id_b), maxi(id_a, id_b)]
		var now_ms: int = Time.get_ticks_msec()
		if closing < 0.08:
			# Resting overlap is positional, not an impact. Only correct it in
			# small, rate-limited steps; the old per-tick impulse made a ghost
			# resting near a wall visibly vibrate and shove the local cart.
			if penetration < 0.03:
				continue
			if now_ms - int(_separation_ms.get(pair_key, -1000)) < 120:
				continue
			_separation_ms[pair_key] = now_ms
		elif closing < 0.015:
			continue
		var mass_a: float = maxf(float(cart_a.call("get_mass")), 1.0)
		var mass_b: float = maxf(float(cart_b.call("get_mass")), 1.0)
		var inv_a: float = 1.0 / mass_a
		var inv_b: float = 1.0 / mass_b
		var impact_impulse: float = 1.18 * closing / (inv_a + inv_b)
		var separation_speed: float = clampf(penetration * 5.0, 0.0, 1.2)
		var normal_impulse: float = impact_impulse + separation_speed / (inv_a + inv_b)
		var impulse_a: Vector3 = -normal * normal_impulse
		var impulse_b: Vector3 = normal * normal_impulse
		# Coulomb friction only applies to a real impact. Separation must not
		# erase sideways sliding when two carts are grinding along together.
		if closing > 0.02:
			var tangent: Vector3 = relative - normal * relative.dot(normal)
			var tangent_speed: float = tangent.length()
			if tangent_speed > 0.02:
				var tangent_dir: Vector3 = tangent / tangent_speed
				var tangent_impulse: float = minf(tangent_speed / (inv_a + inv_b),
					0.24 * impact_impulse)
				impulse_a -= tangent_dir * tangent_impulse
				impulse_b += tangent_dir * tangent_impulse
		# Ghosts are solid bodies now, so the physics step already supplies the
		# positional separation. The solver only adds the momentum exchange;
		# keep it light or a contact bounces twice.
		var delta_a: Vector3 = (impulse_a / mass_a * 0.50).limit_length(4.5)
		var delta_b: Vector3 = (impulse_b / mass_b * 0.50).limit_length(4.5)
		if id_a == host_id:
			cart_a.call("apply_vehicle_impulse", delta_a)
		else:
			local_cart.rpc_id(id_a, "_net_apply_car_impulse", delta_a)
		if id_b == host_id:
			cart_b.call("apply_vehicle_impulse", delta_b)
		else:
			local_cart.rpc_id(id_b, "_net_apply_car_impulse", delta_b)


func notify_scene_ready() -> void:
	## Called by every gameplay scene after its networking setup.
	if not is_session_active() or multiplayer.multiplayer_peer == null:
		return
	if is_host:
		scene_ready_peers[1] = true
	else:
		# The host is by definition in the gameplay scene that just loaded.
		# Readiness is announced with the scene's existing reliable ready RPC
		# (`_net_client_ready` / `_net_race_ready`) so older clients and hosts
		# remain compatible.
		scene_ready_peers[1] = true
	_scene_load_path = ""




func is_connected_to_server() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() \
		== MultiplayerPeer.CONNECTION_CONNECTED


func peer_count() -> int:
	if not is_session_active():
		return 0
	return multiplayer.get_peers().size() + 1


# --------------------------------------------------------------------------
# hosting


func host_game(mode: String = "pi") -> void:
	leave()
	_host_ticket += 1
	var ticket: int = _host_ticket
	connection_mode = "lan" if mode == "lan" else "pi"
	GameSettings.set_connection_preference(connection_mode)
	SceneLoader.begin_task("OPENING A ROOM", "Starting the server...")
	await get_tree().process_frame
	if ticket != _host_ticket:
		SceneLoader.end_task()
		return
	local_address = _local_ip()
	var bound_port: int = _open_server()
	if bound_port <= 0:
		SceneLoader.end_task()
		host_failed.emit("Could not open a game port. Close any other copy and try again.")
		return
	port = bound_port
	is_host = true
	in_game = false
	room_state = "lobby"
	join_code = ""
	public_address = ""
	session_mode = GameSettings.multiplayer_mode
	session_bots = GameSettings.bots_enabled
	session_bot_count = GameSettings.effective_bot_count()
	room_public = GameSettings.room_public
	player_names[1] = GameSettings.player_name
	player_colors[1] = GameSettings.tag_color()
	ping_table[1] = 0

	if connection_mode == "lan":
		# The host PC is the server. No internet, no Pi, no code to type.
		_start_lan_listener()
		if _lan_listener == null:
			_abort_host("Could not start LAN discovery. Close another copy and try again.")
			return
		SceneLoader.end_task()
		host_started.emit("")
		peers_changed.emit()
		return

	# Pi mode: the server allocates the short room code. There is no direct
	# public-IP / UPnP fallback any more.
	SceneLoader.task_message("Connecting to the Cart Slop server...")
	var found: bool = await _discover_relay()
	if ticket != _host_ticket:
		SceneLoader.end_task()
		return
	if not found:
		_abort_host("Cart Slop server is offline. Check the internet, or host a LAN room.")
		return
	SceneLoader.task_message("Creating your room...")
	var registered: bool = false
	for attempt in 2:
		if await _register_relay(port):
			registered = true
			break
		if ticket != _host_ticket:
			return
		await get_tree().create_timer(0.6).timeout
		if ticket != _host_ticket:
			return
	if ticket != _host_ticket:
		return
	if not registered:
		_abort_host("The server could not create a room. Try again in a moment.")
		return
	relay_active = true
	join_code = relay_room_code
	if join_code == "":
		_abort_host("The server did not return a room code.")
		return
	SceneLoader.end_task()
	host_started.emit(join_code)
	peers_changed.emit()


func _abort_host(reason: String) -> void:
	leave()
	SceneLoader.end_task()
	host_failed.emit(reason)


func _discover_relay() -> bool:
	## A manually configured public server wins; otherwise UDP broadcast to
	## the Pi's discovery port (no DNS/.local dependency).
	if relay_base != "":
		return true
	if relay_server_url != "":
		relay_base = relay_server_url
		relay_base_public = true
		return true
	var udp := PacketPeerUDP.new()
	var lan_ip: String = _local_ip()
	if udp.bind(0, lan_ip) != OK and udp.bind(0) != OK:
		return false
	udp.set_broadcast_enabled(true)
	var targets: PackedStringArray = ["255.255.255.255"]
	if _valid_ip(lan_ip):
		var parts: PackedStringArray = lan_ip.split(".")
		if parts.size() == 4:
			targets.append("%s.%s.%s.255" % [parts[0], parts[1], parts[2]])
	for target: String in targets:
		udp.set_dest_address(target, RELAY_DISCOVERY_PORT)
		udp.put_packet("CARTSLOP_DISCOVER".to_utf8_buffer())
	var deadline: int = Time.get_ticks_msec() + DISCOVERY_TIMEOUT_MS
	var next_nudge: int = Time.get_ticks_msec() + 450
	while Time.get_ticks_msec() < deadline:
		while udp.get_available_packet_count() > 0:
			var text: String = udp.get_packet().get_string_from_utf8()
			var parsed: Variant = JSON.parse_string(text)
			if parsed is Dictionary and str((parsed as Dictionary).get("service", "")) == "cartslop":
				var reply_ip: String = str((parsed as Dictionary).get("lan_ip", ""))
				var http_port: int = int((parsed as Dictionary).get("http_port", 42777))
				# A discovery reply is only useful for a LAN Pi. Ignore a
				# spoofed public/invalid address instead of sending the room
				# registration there.
				if not _is_private_ipv4(reply_ip):
					continue
				if http_port <= 0 or http_port > 65535:
					continue
				relay_lan_ip = reply_ip
				relay_base = "http://%s:%d" % [reply_ip, http_port]
				relay_base_public = false
				udp.close()
				return true
		var now: int = Time.get_ticks_msec()
		if now >= next_nudge:
			# UDP is lossy. One lost broadcast must not make the Pi look
			# offline and push the player onto the public fallback.
			next_nudge = now + 450
			for target: String in targets:
				udp.set_dest_address(target, RELAY_DISCOVERY_PORT)
				udp.put_packet("CARTSLOP_DISCOVER".to_utf8_buffer())
		await get_tree().process_frame
	udp.close()
	# No LAN answer. Try the built-in relay once; this is what lets a player on
	# a restrictive network use a short room code through the online relay.
	if _use_default_public_relay():
		var probe: Dictionary = await _relay_get("/api/status", 3.0)
		if not probe.is_empty():
			return true
		_clear_default_public_relay()
	return false


func _use_default_public_relay() -> bool:
	var text: String = OS.get_environment("CARTSLOP_RELAY").strip_edges()
	if text == "":
		text = DEFAULT_RELAY_SERVER.strip_edges()
	if text == "":
		return false
	var secure: bool = text.to_lower().begins_with("https://")
	var rest: String = text.trim_prefix("https://").trim_prefix("http://").trim_suffix("/")
	var host: String = rest.get_slice("/", 0)
	var port: int = 42777
	if host.contains(":"):
		var parts: PackedStringArray = host.split(":")
		host = parts[0]
		port = int(parts[1]) if parts.size() > 1 else 42777
	if host == "" or port <= 0:
		return false
	relay_server_host = host
	relay_server_http_port = port
	relay_server_url = ("https://" if secure else "http://") + host + ":" + str(port)
	relay_base = relay_server_url
	relay_base_public = true
	return true


func _clear_default_public_relay() -> void:
	_invalidate_relay_route()


func _invalidate_relay_route() -> void:
	## The cached route points at a server that just failed. Drop it so the
	## next attempt rediscovers instead of retrying a dead address for every
	## browse/join click. A user-forced server is kept and re-resolved.
	relay_base = ""
	if not _relay_forced:
		relay_server_url = ""
		relay_server_host = ""
	relay_base_public = false


# --------------------------------------------------------------------------
# LAN room discovery (host advertises itself; no typed IP, no Pi required)


func _start_lan_listener() -> void:
	_stop_lan_listener()
	var udp := PacketPeerUDP.new()
	if udp.bind(LAN_ROOM_PORT) != OK:
		last_error = "lan_discovery_unavailable"
		return
	udp.set_broadcast_enabled(true)
	_lan_listener = udp


func _stop_lan_listener() -> void:
	if _lan_listener != null:
		_lan_listener.close()
		_lan_listener = null


func _poll_lan_listener() -> void:
	if _lan_listener == null:
		return
	while _lan_listener.get_available_packet_count() > 0:
		var packet: PackedByteArray = _lan_listener.get_packet()
		var sender: String = _lan_listener.get_packet_ip()
		var sender_port: int = _lan_listener.get_packet_port()
		var parsed: Variant = JSON.parse_string(packet.get_string_from_utf8())
		if not (parsed is Dictionary):
			continue
		var request: Dictionary = parsed as Dictionary
		if str(request.get("service", "")) != "cartslop-lan" \
				or str(request.get("want", "")) != "rooms":
			continue
		if sender == "" or sender_port <= 0:
			continue
		# Only answer a real LAN peer. Replying to a spoofed public source
		# would turn the discovery socket into a small UDP reflector.
		if not _is_private_ipv4(sender):
			continue
		# Private LAN rooms do not answer discovery at all. The host flips the
		# ROOM setting to PUBLIC when friends are ready to join.
		if not room_public:
			continue
		var reply: Dictionary = {
			"service": "cartslop-lan",
			"name": GameSettings.player_name,
			# The joining client must connect back to THIS host, not to itself.
			"host": local_address if _valid_ip(local_address) else _local_ip(),
			"port": port,
			"players": peer_count(),
			"mode": session_mode,
			"state": room_state,
			"version": str(ProjectSettings.get_setting("application/config/version", "")),
		}
		_lan_listener.set_dest_address(sender, sender_port)
		_lan_listener.put_packet(JSON.stringify(reply).to_utf8_buffer())


func scan_lan_rooms(timeout: float = 1.4) -> Array:
	## Broadcast a request and collect host replies. Returns rooms discovered
	## on the local network. Nothing here is typed by the player.
	var udp := PacketPeerUDP.new()
	if udp.bind(0) != OK:
		return []
	udp.set_broadcast_enabled(true)
	var targets: PackedStringArray = ["255.255.255.255"]
	var lan_ip: String = _local_ip()
	if _valid_ip(lan_ip):
		var parts: PackedStringArray = lan_ip.split(".")
		if parts.size() == 4:
			targets.append("%s.%s.%s.255" % [parts[0], parts[1], parts[2]])
	var request: PackedByteArray = JSON.stringify({
		"service": "cartslop-lan",
		"want": "rooms",
	}).to_utf8_buffer()
	for target: String in targets:
		udp.set_dest_address(target, LAN_ROOM_PORT)
		udp.put_packet(request)
	var found: Dictionary = {}
	var deadline: int = Time.get_ticks_msec() + int(maxf(timeout, 0.4) * 1000.0)
	var next_nudge: int = 0
	while Time.get_ticks_msec() < deadline:
		while udp.get_available_packet_count() > 0:
			var packet: PackedByteArray = udp.get_packet()
			var parsed: Variant = JSON.parse_string(packet.get_string_from_utf8())
			if not (parsed is Dictionary):
				continue
			var room: Dictionary = parsed as Dictionary
			if str(room.get("service", "")) != "cartslop-lan":
				continue
			var host: String = str(room.get("host", ""))
			var open_port: int = int(room.get("port", 0))
			if not _is_private_ipv4(host) or open_port <= 0:
				continue
			found["%s:%d" % [host, open_port]] = {
				"name": GameSettings.sanitize_name(str(room.get("name", "HOST"))),
				"host": host,
				"port": open_port,
				"players": maxi(int(room.get("players", 1)), 1),
				"mode": str(room.get("mode", GameSettings.GAME_SANDBOX)),
				"state": str(room.get("state", "lobby")),
			}
		var now: int = Time.get_ticks_msec()
		if now >= next_nudge:
			next_nudge = now + 450
			for target: String in targets:
				udp.set_dest_address(target, LAN_ROOM_PORT)
				udp.put_packet(request)
		await get_tree().process_frame
	udp.close()
	return found.values()


func join_lan_room(room: Dictionary) -> void:
	var host: String = str(room.get("host", "")).strip_edges()
	var open_port: int = int(room.get("port", 0))
	if not _is_private_ipv4(host) or open_port <= 0:
		join_failed.emit("That LAN room is no longer available. Scan again.")
		return
	if str(room.get("state", "lobby")) != "lobby":
		join_failed.emit("That LAN room has already started.")
		return
	join_status_changed.emit("Joining the LAN room...")
	_connect_to(host, open_port, "lan")


func _relay_post(path: String, payload: Dictionary) -> Dictionary:
	if relay_base == "":
		return {}
	var http := HTTPRequest.new()
	http.timeout = 6.0
	http.body_size_limit = MAX_HTTP_BODY
	add_child(http)
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var error: Error = http.request(relay_base + path, headers,
		HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		http.queue_free()
		return {}
	var response: Array = await http.request_completed
	http.queue_free()
	if int(response[1]) != 200:
		return {}
	var parsed: Variant = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


func _relay_get(path: String, timeout: float = RELAY_HTTP_TIMEOUT) -> Dictionary:
	if relay_base == "":
		return {}
	var http := HTTPRequest.new()
	http.timeout = timeout
	http.body_size_limit = MAX_HTTP_BODY
	add_child(http)
	var error: Error = http.request(relay_base + path, [], HTTPClient.METHOD_GET)
	if error != OK:
		http.queue_free()
		return {}
	var response: Array = await http.request_completed
	http.queue_free()
	if int(response[1]) != 200:
		return {}
	var parsed: Variant = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


func fetch_lobbies() -> Array:
	if not await _discover_relay():
		server_online = false
		server_status_changed.emit(false, "offline")
		return []
	var response: Dictionary = await _relay_get("/api/lobbies", 4.0)
	server_online = not response.is_empty()
	if not server_online:
		_invalidate_relay_route()
	server_status_changed.emit(server_online, "online" if server_online else "offline")
	var lobbies: Variant = response.get("lobbies", [])
	if not (lobbies is Array):
		return []
	var open: Array = []
	for entry: Variant in lobbies as Array:
		if open.size() >= MAX_LOBBY_ENTRIES:
			break
		if entry is Dictionary and str((entry as Dictionary).get("state", "lobby")) == "lobby":
			open.append(entry)
	return open


func _register_relay(local_port: int) -> bool:
	var response: Dictionary = await _relay_post("/api/register", {
		"name": GameSettings.player_name,
		"local_port": local_port,
		"local_ip": local_address,
		"tunnel": true,
		"public": room_public,
	})
	if response.is_empty():
		return false
	relay_token = str(response.get("token", ""))
	relay_room_code = str(response.get("room_code", ""))
	relay_port = int(response.get("relay_port", 0))
	relay_lan_host = str(response.get("lan_host", relay_lan_ip))
	relay_public_host = str(response.get("public_host", ""))
	relay_tunnel_token = str(response.get("tunnel_token", ""))
	relay_tunnel_port = int(response.get("tunnel_port", 0))
	if relay_base_public and relay_server_host != "":
		# A hostname/tunnel is the address clients actually used.
		relay_public_host = relay_server_host
	_relay_heartbeat = 0.0
	if relay_token != "" and relay_port > 0 and relay_tunnel_token != "" \
			and relay_tunnel_port > 0:
		_start_relay_tunnel()
	return relay_token != "" and relay_port > 0


func _start_relay_tunnel() -> void:
	if _relay_tunnel != null:
		return
	var host: String = relay_lan_host
	if host == "" and relay_base_public:
		host = relay_server_host
	if relay_base_public and relay_lan_host != "" and not _same_subnet_24(relay_lan_host, _local_ip()):
		host = relay_server_host
	if host == "":
		host = relay_lan_ip
	if host == "":
		return
	_relay_tunnel = RelayTunnel.new()
	add_child(_relay_tunnel)
	_relay_tunnel.configure(host, relay_tunnel_port, relay_tunnel_token, port)
	_relay_tunnel.tunnel_ready.connect(func() -> void:
		relay_tunnel_active = true)
	_relay_tunnel.tunnel_lost.connect(func() -> void:
		relay_tunnel_active = false)
	_relay_tunnel.start()


func _relay_heartbeat_tick(delta: float) -> void:
	if not relay_active or not is_host or _relay_busy or relay_token == "":
		return
	_relay_heartbeat += delta
	if _relay_heartbeat < RELAY_HEARTBEAT_INTERVAL:
		return
	_relay_heartbeat = 0.0
	_relay_busy = true
	var response: Dictionary = await _relay_post("/api/heartbeat", {
		"token": relay_token,
		"state": room_state,
		"players": peer_count(),
		"public": room_public,
	})
	_relay_busy = false
	if not is_host or not relay_active:
		return
	if response.is_empty() or response.get("ok") != true:
		# A single transient timeout is not fatal, but a Pi restart or an
		# expired lobby makes every later heartbeat return 404. Without this
		# the lobby kept showing a code that could never be joined.
		_heartbeat_failures += 1
		if _heartbeat_failures >= 2:
			_on_relay_room_lost()
		return
	_heartbeat_failures = 0


func _on_relay_room_lost() -> void:
	if not is_host or not relay_active:
		return
	var was_in_game: bool = in_game
	leave()
	session_ended.emit("The room expired on the game server. Host a new room.")
	if was_in_game:
		SceneLoader.go_to(LOBBY_SCENE, "ROOM LOST",
			"The game server lost this room. Host a new one.")


func set_room_state(state: String) -> void:
	var next: String = state if state in ["lobby", "playing", "finished"] else "lobby"
	if next == room_state:
		return
	room_state = next
	_push_room_state()


func set_room_public(value: bool) -> void:
	## Host only. Updates the live room immediately: online rooms are pushed to
	## the Pi, LAN rooms stop (or start) answering discovery broadcasts.
	if not is_host or room_public == value:
		return
	room_public = value
	if relay_active:
		_relay_heartbeat = RELAY_HEARTBEAT_INTERVAL
		_push_room_state()


func _push_room_state() -> void:
	## Host -> Pi only. Pause never calls this: the room keeps its current
	## server state while a client or host is looking at a menu.
	if not is_host or not relay_active or relay_token == "" or relay_base == "":
		return
	var base: String = relay_base
	var body: Dictionary = {
		"token": relay_token,
		"state": room_state,
		"players": peer_count(),
		"public": room_public,
	}
	var http := HTTPRequest.new()
	http.timeout = 3.0
	add_child(http)
	http.request_completed.connect(func(_r: int, _c: int, _h: PackedStringArray,
			_b: PackedByteArray) -> void: http.queue_free())
	var error: Error = http.request(base + "/api/heartbeat", ["Content-Type: application/json"],
		HTTPClient.METHOD_POST, JSON.stringify(body))
	if error != OK:
		http.queue_free()


func _relay_unregister_async(token: String, base: String) -> void:
	if token == "" or base == "":
		return
	var http := HTTPRequest.new()
	http.timeout = 3.0
	add_child(http)
	http.request_completed.connect(func(_r: int, _c: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		http.queue_free())
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var error: Error = http.request(base + "/api/unregister", headers, HTTPClient.METHOD_POST,
		JSON.stringify({"token": token}))
	if error != OK:
		http.queue_free()


func _open_server() -> int:
	for offset in PORT_RANGE:
		var candidate: int = DEFAULT_PORT + offset
		var peer := ENetMultiplayerPeer.new()
		# ENet's max_clients excludes the host, so allow 7 clients for 8 total.
		if peer.create_server(candidate, MAX_PLAYERS - 1) == OK:
			_peer = peer
			multiplayer.multiplayer_peer = _peer
			return candidate
	return 0


func _local_ip() -> String:
	## Pick the most likely physical LAN adapter. VPNs, Hyper-V, WSL, Docker and
	## VirtualBox adapters often sort first, and their address is not reachable
	## from the player's friend.
	var best: String = ""
	var best_score: int = -1000
	var interfaces: Array = IP.get_local_interfaces()
	for iface: Dictionary in interfaces:
		var label: String = (str(iface.get("name", "")) + " " + str(iface.get("friendly", ""))).to_lower()
		var score: int = 0
		if label.contains("wi-fi") or label.contains("wifi") or label.contains("wireless") or label.contains("wlan"):
			score += 30
		elif label.contains("ethernet") or label.contains("eth"):
			score += 20
		for bad: String in ["virtual", "vmware", "vbox", "hyper-v", "vethernet", "wsl",
				"docker", "tailscale", "zerotier", "vpn", "warp", "cloudflare",
				"loopback", "bluetooth"]:
			if label.contains(bad):
				score -= 100
				break
		for value: Variant in iface.get("addresses", []) as Array:
			var address: String = str(value)
			if not _valid_ip(address) or address.begins_with("127.") or address.begins_with("169.254."):
				continue
			if score > best_score:
				best = address
				best_score = score
	if best != "":
		return best
	for address: String in IP.get_local_addresses():
		if address.begins_with("127.") or address.contains(":"):
			continue
		if address.begins_with("192.168.") or address.begins_with("10.") or address.begins_with("172."):
			return address
	return "127.0.0.1"


func _is_public_ipv4(text: String) -> bool:
	if not _valid_ip(text):
		return false
	if text.begins_with("10.") or text.begins_with("127.") or text.begins_with("169.254."):
		return false
	if text.begins_with("192.168."):
		return false
	if text.begins_with("172."):
		var second: int = int(text.split(".")[1])
		if second >= 16 and second <= 31:
			return false
	if _is_cgnat_ipv4(text):
		return false
	return true


func _is_cgnat_ipv4(text: String) -> bool:
	## RFC 6598 shared address space (carrier-grade NAT).
	if not _valid_ip(text) or not text.begins_with("100."):
		return false
	var second: int = int(text.split(".")[1])
	return second >= 64 and second <= 127


# --------------------------------------------------------------------------
# joining


func set_relay_server(raw: String) -> void:
	## Accepts "1.2.3.4", "1.2.3.4:42777", "cartslop.example.com",
	## or a full http(s) URL. Empty means "use LAN discovery".
	var text: String = raw.strip_edges()
	_relay_forced = text != ""
	GameSettings.set_relay_server(text)
	relay_server_url = ""
	relay_server_host = ""
	relay_server_http_port = 42777
	var was_public: bool = relay_base_public
	relay_base_public = false
	if text == "":
		if was_public:
			relay_base = ""
		return
	var secure: bool = text.begins_with("https://")
	var rest: String = text.trim_prefix("https://").trim_prefix("http://").trim_suffix("/")
	var host: String = rest.get_slice("/", 0)
	var http_port: int = 42777
	if host.contains(":"):
		var parts: PackedStringArray = host.split(":")
		host = parts[0]
		http_port = int(parts[1]) if parts.size() > 1 else 42777
	if host == "":
		return
	relay_server_host = host
	relay_server_http_port = http_port if http_port > 0 else 42777
	relay_server_url = ("https://" if secure else "http://") + relay_server_host \
		+ ":" + str(relay_server_http_port)
	relay_base = relay_server_url
	relay_base_public = true


func set_local_name(raw_name: String) -> void:
	GameSettings.set_player_name(raw_name)
	if is_session_active():
		rpc("_net_set_name", multiplayer.get_unique_id(), GameSettings.player_name)


func name_of(peer_id: int) -> String:
	return str(player_names.get(peer_id, "PLAYER %d" % peer_id))


func color_of(peer_id: int) -> Color:
	## A peer's chosen name tag colour; white when unknown (e.g. solo rivals).
	return player_colors.get(peer_id, Color.WHITE)


func set_local_tag_color(hex: String) -> void:
	## Persist locally, then announce to the session so every label updates.
	GameSettings.set_player_tag_color(hex)
	if is_session_active():
		rpc("_net_set_tag_color", multiplayer.get_unique_id(), GameSettings.player_tag_color)
	tag_colors_changed.emit()


func join_public_room(room: Dictionary) -> void:
	## Join a room picked from the public browser. No code is shown or typed:
	## the fresh /api/lobbies row already carries the relay address.
	if join_pending or is_session_active():
		return
	_join_ticket += 1
	var ticket: int = _join_ticket
	join_pending = true
	_join_started_ms = Time.get_ticks_msec()
	if str(room.get("state", "lobby")).strip_edges().to_lower() != "lobby":
		join_pending = false
		join_failed.emit("That room has already started.")
		return
	if room.has("public") and not bool(room.get("public")):
		join_pending = false
		join_failed.emit("That room is private. Ask the host for the code.")
		return
	# A row can be minutes old: the host may have switched to PRIVATE or
	# started the race since the browser fetched it. Re-check the live list.
	var listing: Array = await fetch_lobbies()
	if ticket != _join_ticket or not join_pending:
		return
	var live_row: Dictionary = {}
	for entry: Variant in listing:
		if not (entry is Dictionary):
			continue
		var row: Dictionary = entry as Dictionary
		if int(row.get("relay_port", 0)) == int(room.get("relay_port", 0)) \
				and str(row.get("name", "")) == str(room.get("name", "")):
			live_row = row
			break
	if live_row.is_empty():
		join_pending = false
		join_failed.emit("That room is no longer public. Ask the host for the code.")
		return
	room = live_row
	var host: String = ""
	if relay_base_public:
		host = relay_server_host
		if host == "":
			host = str(room.get("public_host", ""))
	if host == "":
		host = str(room.get("lan_host", ""))
	var relay_port: int = int(room.get("relay_port", 0))
	if host == "" or relay_port <= 0:
		join_pending = false
		join_failed.emit("That room is not accepting players yet. Try again.")
		return
	set_meta("last_join_code", "")
	join_status_changed.emit("Joining the room...")
	_connect_to(host, relay_port, "pi")


func join_game(raw_code: String) -> void:
	## Only a 5-letter room code from the Pi is accepted. Never an IP address,
	## hostname, port, or hand-built 14-character address code.
	if join_pending or is_session_active():
		return
	_join_ticket += 1
	var ticket: int = _join_ticket
	join_pending = true
	_join_started_ms = Time.get_ticks_msec()
	var text: String = raw_code.strip_edges().to_upper().replace(" ", "").replace("-", "")
	if not _valid_room_code(text):
		join_pending = false
		join_failed.emit("Enter the 5-letter room code from the host. IP addresses are not used.")
		return
	join_status_changed.emit("Connecting to the Cart Slop server...")
	if not await _discover_relay():
		if ticket != _join_ticket:
			return
		join_pending = false
		# A code join that cannot reach the service must flip the lobby into
		# its offline state, not just print a line inside the JOIN card.
		server_online = false
		server_detail = "offline"
		server_status_changed.emit(false, "offline")
		join_failed.emit("The Cart Slop server is offline. Check the internet, or join a LAN room.")
		return
	if ticket != _join_ticket or not join_pending:
		return
	join_status_changed.emit("Finding room %s..." % text)
	var room: Dictionary = await _relay_get("/api/room/" + text, 4.0)
	if ticket != _join_ticket or not join_pending:
		return
	if room.is_empty():
		join_pending = false
		# A 404 can be a typo, but an empty result after a network failure
		# would otherwise keep retrying the same dead route.
		_invalidate_relay_route()
		join_failed.emit("Room %s was not found. Ask the host for a fresh code." % text)
		return
	var state: String = str(room.get("state", "lobby")).to_lower()
	if state != "lobby":
		join_pending = false
		join_failed.emit("That room has already started. Ask the host to return to the lobby.")
		return
	var host: String = str(room.get("lan_host", ""))
	if relay_base_public:
		# The client reached the Pi at its public address; the relay lives there.
		host = relay_server_host if relay_server_host != "" else str(room.get("public_host", ""))
		if host == "":
			host = str(room.get("lan_host", ""))
	var relay_port: int = int(room.get("relay_port", 0))
	if host == "" or relay_port <= 0:
		join_pending = false
		join_failed.emit("That room is not accepting players yet. Try again.")
		return
	if ticket != _join_ticket or not join_pending:
		return
	_connect_to(host, relay_port, "pi")


func _connect_to(connect_ip: String, connect_port: int, mode: String) -> void:
	leave()
	if not _valid_ip(connect_ip):
		connect_ip = IP.resolve_hostname(connect_ip)
		if connect_ip == "":
			join_pending = false
			join_failed.emit("Could not find that room.")
			return
	if connect_port <= 0 or connect_port > 65535:
		join_pending = false
		join_failed.emit("That room is not accepting players yet.")
		return
	join_status_changed.emit("Connecting to the room...")
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(connect_ip, connect_port)
	if error != OK:
		join_pending = false
		join_failed.emit("Could not start the connection. Try again.")
		return
	_peer = peer
	multiplayer.multiplayer_peer = peer
	connection_mode = "lan" if mode == "lan" else "pi"
	is_client = true
	in_game = false
	room_state = "lobby"
	join_pending = true
	_join_started_ms = Time.get_ticks_msec()
	player_names.clear()


func leave() -> void:
	_host_ticket += 1 ## Cancels an in-flight host_game() await chain.
	_join_ticket += 1 ## Cancels an in-flight join_game() await chain.
	_stop_lan_listener()
	clear_scene_ready()
	room_state = "lobby"
	if relay_active and relay_token != "":
		_relay_unregister_async(relay_token, relay_base)
	if _peer != null:
		_peer.close()
	if multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer != _peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	_peer = null
	is_host = false
	is_client = false
	in_game = false
	join_pending = false
	join_code = ""
	relay_active = false
	relay_token = ""
	relay_port = 0
	relay_lan_host = ""
	relay_public_host = ""
	relay_room_code = ""
	relay_base = ""
	_heartbeat_failures = 0
	if not _relay_forced:
		relay_server_url = ""
		relay_server_host = ""
	relay_base_public = false
	relay_tunnel_active = false
	relay_tunnel_token = ""
	relay_tunnel_port = 0
	if _relay_tunnel != null:
		_relay_tunnel.stop()
		_relay_tunnel.queue_free()
		_relay_tunnel = null
	public_address = ""
	latency_ms = 0
	last_error = ""
	player_names.clear()
	player_colors.clear()
	ping_table.clear()
	race_standings.clear()


# --------------------------------------------------------------------------
# session config (host -> everyone, while still in the lobby)


func configure_session(mode: String, bots: bool, count: int) -> void:
	if not is_host:
		return
	session_mode = mode
	session_bots = bots
	session_bot_count = count
	session_minigame = GameSettings.selected_minigame
	rpc("_net_session_config", mode, bots, count)


@rpc("authority", "call_local", "reliable")
func _net_session_config(mode: String, bots: bool, count: int) -> void:
	if mode != GameSettings.GAME_SANDBOX and mode != GameSettings.GAME_MINIGAMES:
		return
	count = clampi(count, 0, MAX_BOT_COUNT)
	session_mode = mode
	session_bots = bots
	session_bot_count = count
	if is_host:
		GameSettings.set_session_config(GameSettings.MODE_MULTIPLAYER, mode, bots, count)
	session_config_changed.emit()


func is_lan() -> bool:
	return connection_mode == "lan"


# --------------------------------------------------------------------------
# session flow


func start_game(scene_path: String = "", mode: String = "") -> void:
	## Host-only. Picks the scene from the host's session mode when omitted,
	## then pushes the exact configuration to every peer before loading.
	if not is_host:
		return
	var target: String = scene_path
	var chosen_mode: String = mode
	if chosen_mode == "":
		chosen_mode = GameSettings.multiplayer_mode
	if target == "":
		target = RACE_SCENE if chosen_mode == GameSettings.GAME_MINIGAMES else GAME_SCENE
	in_game = true
	game_scene = target
	session_mode = chosen_mode
	session_bots = GameSettings.bots_enabled
	session_bot_count = GameSettings.effective_bot_count()
	session_minigame = GameSettings.selected_minigame
	race_seed = Time.get_ticks_msec()
	clear_scene_ready()
	set_room_state("playing")
	rpc("_net_begin_game", target, chosen_mode, session_bots, session_bot_count, race_seed)


@rpc("authority", "call_local", "reliable")
func _net_begin_game(scene_path: String, mode: String, bots: bool, count: int,
		seed_value: int = 0) -> void:
	# A malicious host must not be able to load an arbitrary scene or spawn
	# billions of bots on a joining client.
	if scene_path not in ALLOWED_SCENES:
		return
	if mode != GameSettings.GAME_SANDBOX and mode != GameSettings.GAME_MINIGAMES:
		return
	count = clampi(count, 0, MAX_BOT_COUNT)
	var current: Node = get_tree().current_scene
	if current != null and current.scene_file_path == scene_path and in_game:
		# The first ready RPC can reach the host before its scene exists. On a
		# retry, announce through the loaded scene again so it can mark this peer
		# ready and resend the vehicle table.
		notify_scene_ready()
		if not is_host:
			if scene_path == GAME_SCENE:
				current.rpc_id(1, "_net_client_ready", GameSettings.selected_vehicle)
			elif scene_path == RACE_SCENE:
				current.rpc_id(1, "_net_race_ready", GameSettings.minigame_vehicle)
		return
	if _scene_load_path == scene_path:
		# A previous retry already asked SceneLoader for this scene. It may
		# still be streaming; queueing it again would load the scene twice.
		return
	_scene_load_path = scene_path
	in_game = true
	game_scene = scene_path
	session_mode = mode
	session_bots = bots
	session_bot_count = count
	if seed_value != 0:
		race_seed = seed_value
	# The host's session config stays in Network.* on clients. Only the host
	# writes its own persisted settings; otherwise a client's later volume/
	# name save would silently persist the host's mode and bot count.
	if is_host:
		GameSettings.set_session_config(GameSettings.MODE_MULTIPLAYER, mode, bots, count)
	var title: String = "STARTING RACE" if mode == GameSettings.GAME_MINIGAMES else "STARTING SANDBOX"
	SceneLoader.go_to(scene_path, title, "Syncing players...")


func return_to_lobby(reason: String = "") -> void:
	if is_session_active():
		leave()
	session_ended.emit(reason)
	SceneLoader.go_to(LOBBY_SCENE, "MULTIPLAYER")


func return_to_lobby_keep_session() -> void:
	## Used after a race result. The host brings everyone back to the lobby;
	## a client waits in its own lobby while the connection stays open.
	clear_scene_ready()
	if not is_session_active():
		SceneLoader.go_to(LOBBY_SCENE, "MULTIPLAYER")
		return
	if is_host:
		in_game = false
		set_room_state("lobby")
		rpc("_net_return_lobby")
	else:
		# Tell the host we left the race scene so it stops sending cart-state
		# RPCs to a node that no longer exists.
		rpc_id(1, "_net_client_left_scene")
		SceneLoader.go_to(LOBBY_SCENE, "MULTIPLAYER")


@rpc("any_peer", "call_remote", "reliable")
func _net_client_left_scene() -> void:
	var sender: int = _rpc_sender()
	if sender <= 1:
		return
	scene_ready_peers.erase(sender)
	_left_scene_peers[sender] = true
	_scene_retry_counts.erase(sender)


@rpc("authority", "call_local", "reliable")
func _net_return_lobby() -> void:
	in_game = false
	SceneLoader.go_to(LOBBY_SCENE, "MULTIPLAYER")


# --------------------------------------------------------------------------
# signals


func _on_peer_connected(id: int) -> void:
	# A reconnect can reuse a peer id after a long session; never inherit the
	# previous occupant's retry budget or throttle stamps.
	_scene_retry_counts.erase(id)
	_left_scene_peers.erase(id)
	_name_stamp.erase(id)
	_ping_stamp.erase(id)
	_color_stamp.erase(id)
	_ping_request_stamp.erase(id)
	if is_host and in_game and game_scene == RACE_SCENE:
		# Meadow Loop does not support joining mid-race: a peer that arrives
		# after the start would sit on a frozen WAITING screen. Drop it
		# instead of force-loading a race it can never join.
		if _peer != null:
			_peer.disconnect_peer(id)
		return
	peers_changed.emit()
	_push_room_state()
	if is_host:
		# Send the existing name/colour table to the newcomer. Without this a
		# client only learns colours from peers who change them later.
		for peer_id: int in player_names:
			rpc_id(id, "_net_set_name", peer_id, str(player_names[peer_id]))
		for peer_id: int in player_colors:
			var color: Color = player_colors[peer_id]
			rpc_id(id, "_net_set_tag_color", peer_id, color.to_html(false))
		if in_game:
			rpc_id(id, "_net_begin_game", game_scene, session_mode,
				session_bots, session_bot_count, race_seed)
	if is_session_active():
		# Re-announce our name so the newcomer (and everyone) has it.
		rpc("_net_set_name", multiplayer.get_unique_id(), GameSettings.player_name)


var _name_stamp: Dictionary = {}
var _ping_stamp: Dictionary = {}
var _color_stamp: Dictionary = {}
var _ping_request_stamp: Dictionary = {}


@rpc("any_peer", "call_local", "reliable")
func _net_set_name(peer_id: int, raw_name: String) -> void:
	var sender: int = _rpc_sender()
	# Host relays client names so every client sees the whole player list.
	if sender != 0 and sender != 1 and peer_id != sender:
		return
	# One reliable name change per peer every 2 s. Without this a client can
	# flood a large string and make the host rebroadcast it to every peer.
	if sender > 1:
		var now: int = Time.get_ticks_msec()
		if now - int(_name_stamp.get(sender, -10000)) < 2000:
			return
		_name_stamp[sender] = now
	var clean: String = GameSettings.sanitize_name(raw_name)
	player_names[peer_id] = clean
	names_changed.emit()
	# Rebroadcast the sanitized value, never the raw attacker string.
	if is_host and sender != 0 and sender != 1:
		rpc("_net_set_name", peer_id, clean)


@rpc("any_peer", "call_local", "reliable")
func _net_set_tag_color(peer_id: int, raw_hex: String) -> void:
	## Same relay pattern as names: a peer speaks for itself, host relays.
	var sender: int = _rpc_sender()
	if sender != 0 and sender != 1 and peer_id != sender:
		return
	var clean: String = str(raw_hex).strip_edges().trim_prefix("#").to_lower()
	if clean.length() != 6:
		return
	for character: String in clean:
		if not ("0123456789abcdef".contains(character)):
			return
	# Colours are reliable RPCs that the host rebroadcasts to every peer.
	# Throttle them exactly like names so one client cannot amplify a flood.
	if sender > 1:
		var now: int = Time.get_ticks_msec()
		if now - int(_color_stamp.get(sender, -10000)) < 2000:
			return
		_color_stamp[sender] = now
	player_colors[peer_id] = Color(clean)
	tag_colors_changed.emit()
	if is_host and sender != 0 and sender != 1:
		rpc("_net_set_tag_color", peer_id, clean)


func _on_peer_disconnected(id: int) -> void:
	scene_ready_peers.erase(id)
	_scene_retry_counts.erase(id)
	_left_scene_peers.erase(id)
	player_names.erase(id)
	player_colors.erase(id)
	ping_table.erase(id)
	_name_stamp.erase(id)
	_ping_stamp.erase(id)
	_color_stamp.erase(id)
	_ping_request_stamp.erase(id)
	peers_changed.emit()
	names_changed.emit()
	tag_colors_changed.emit()
	ping_table_changed.emit()
	_push_room_state()
	if is_host and is_session_active():
		_broadcast_ping_table()


func _on_connected_to_server() -> void:
	is_client = true
	join_pending = false
	clear_scene_ready()
	rpc("_net_set_name", multiplayer.get_unique_id(), GameSettings.player_name)
	rpc("_net_set_tag_color", multiplayer.get_unique_id(), GameSettings.player_tag_color)
	join_status_changed.emit("Connected. Waiting for the host to start...")
	join_succeeded.emit()
	peers_changed.emit()


func _on_connection_failed() -> void:
	var reason: String = "Could not reach that host. Check the code and that the host is online."
	leave()
	join_failed.emit(reason)


func _on_server_disconnected() -> void:
	in_game = false
	var was_client: bool = is_client
	leave()
	if was_client:
		session_ended.emit("The host ended the session.")
		var current: Node = get_tree().current_scene
		# Reloading the lobby wipes the reason from the fresh instance's
		# status label. If we are already there, let _on_session_ended show it.
		if current == null or current.scene_file_path != LOBBY_SCENE:
			SceneLoader.go_to(LOBBY_SCENE, "SESSION ENDED", "The host disconnected.")


# --------------------------------------------------------------------------
# ping


@rpc("any_peer", "unreliable")
func _net_ping(stamp: int) -> void:
	var sender: int = _rpc_sender()
	if sender <= 0 or not multiplayer.is_server():
		return
	# Unreliable pings are cheap, but a client can still use them to make the
	# host reply at line rate. One per 0.5 s is plenty for a 2 s ping cycle.
	var now: int = Time.get_ticks_msec()
	if now - int(_ping_request_stamp.get(sender, -10000)) < 500:
		return
	_ping_request_stamp[sender] = now
	rpc_id(sender, "_net_pong", stamp)


@rpc("authority", "unreliable")
func _net_pong(stamp: int) -> void:
	latency_ms = Time.get_ticks_msec() - stamp
	latency_changed.emit(latency_ms)
	# Publish our own RTT so the host can build the Minecraft-style ping table
	# every player sees when holding Tab.
	ping_table[multiplayer.get_unique_id()] = latency_ms
	ping_table_changed.emit()
	rpc_id(1, "_net_report_ping", latency_ms)


@rpc("any_peer", "unreliable")
func _net_report_ping(ms: int) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = _rpc_sender()
	if sender <= 1:
		return
	# One report per 2 s per peer: each one makes the host send a reliable
	# table to every client, so an unthrottled peer can amplify a packet into
	# a lobby-wide broadcast storm.
	var now: int = Time.get_ticks_msec()
	if now - int(_ping_stamp.get(sender, -10000)) < 2000:
		return
	_ping_stamp[sender] = now
	ping_table[sender] = clampi(ms, 0, 5000)
	_broadcast_ping_table()


func _broadcast_ping_table() -> void:
	## Host-only: relay everyone's reported ping so clients can show it too.
	if not is_host or not is_session_active():
		return
	ping_table[1] = 0
	rpc("_net_ping_table", ping_table)


@rpc("authority", "reliable")
func _net_ping_table(table: Dictionary) -> void:
	var clean: Dictionary = {}
	for key: Variant in table.keys():
		var id: int = int(key)
		if id <= 0 or id > 4096:
			continue
		var value: Variant = table[key]
		if not (value is int or value is float):
			continue
		clean[id] = clampi(int(value), 0, 5000)
		if clean.size() >= 64:
			break
	ping_table = clean
	ping_table_changed.emit()


# --------------------------------------------------------------------------
# helpers


static func encode_address(ip: String, udp_port: int) -> String:
	## 12 hex chars for ip:port plus a 2-char checksum -> 14 chars total.
	var parts: PackedStringArray = ip.split(".")
	if parts.size() != 4:
		return ""
	var bytes: Array[int] = []
	for part: String in parts:
		bytes.append(clampi(int(part), 0, 255))
	bytes.append((udp_port >> 8) & 0xFF)
	bytes.append(udp_port & 0xFF)
	var checksum: int = 0
	for value: int in bytes:
		checksum = (checksum + value) & 0xFF
	var out: String = ""
	for value: int in bytes:
		out += "%02X" % value
	return out + "%02X" % checksum


static func decode_address(raw: String) -> Dictionary:
	var text: String = raw.strip_edges().to_upper().replace(" ", "")
	if text == "":
		return {}
	if text.contains(":"):
		var bits: PackedStringArray = text.split(":")
		if bits.size() != 2:
			return {}
		var typed_port: int = int(bits[1])
		if typed_port <= 0 or typed_port > 65535:
			return {}
		return {"ip": bits[0], "port": typed_port}
	if text.length() != 14:
		return {}
	for character in text:
		if not ("0123456789ABCDEF".contains(character)):
			return {}
	var checksum: int = 0
	for index in 6:
		checksum = (checksum + text.substr(index * 2, 2).hex_to_int()) & 0xFF
	if checksum != text.substr(12, 2).hex_to_int():
		return {}
	var ip: String = "%d.%d.%d.%d" % [
		text.substr(0, 2).hex_to_int(),
		text.substr(2, 2).hex_to_int(),
		text.substr(4, 2).hex_to_int(),
		text.substr(6, 2).hex_to_int(),
	]
	var udp_port: int = text.substr(8, 4).hex_to_int()
	if udp_port <= 0:
		return {}
	return {"ip": ip, "port": udp_port}


func _same_subnet_24(left: String, right: String) -> bool:
	if not _valid_ip(left) or not _valid_ip(right):
		return false
	return left.substr(0, left.rfind(".")) == right.substr(0, right.rfind("."))


func _valid_ip(text: String) -> bool:
	var parts: PackedStringArray = text.strip_edges().split(".")
	if parts.size() != 4:
		return false
	for part: String in parts:
		if part == "" or not part.is_valid_int():
			return false
		var value: int = int(part)
		if value < 0 or value > 255:
			return false
	return true


func _valid_room_code(text: String) -> bool:
	if text.length() != 5:
		return false
	for character: String in text:
		if not ROOM_CODE_ALPHABET.contains(character):
			return false
	return true


func _is_private_ipv4(text: String) -> bool:
	if not _valid_ip(text):
		return false
	if text.begins_with("10.") or text.begins_with("192.168.") or text.begins_with("127."):
		return true
	if text.begins_with("172."):
		var second: int = int(text.split(".")[1])
		return second >= 16 and second <= 31
	return false


func probe_server() -> bool:
	## Used by the lobby to show PI SERVER ONLINE/OFFLINE and to disable room
	## hosting/joining when there is nothing to connect to.
	if is_host or is_client or join_pending:
		# A live session owns the relay route. Re-probing here used to clear
		# it on a slow /api/status and silently stop heartbeats.
		server_online = true
		server_detail = "online"
		return true
	var ticket: int = _host_ticket + _join_ticket
	var found: bool = await _discover_relay()
	if ticket != _host_ticket + _join_ticket or is_host or is_client or join_pending:
		# Host or join started while the probe was in flight. Never clear the
		# relay route underneath it.
		return true
	if not found:
		server_online = false
		server_detail = "offline"
		server_status_changed.emit(false, "offline")
		return false
	var status: Dictionary = await _relay_get("/api/status", 3.0)
	if ticket != _host_ticket + _join_ticket or is_host or is_client or join_pending:
		return true
	server_online = not status.is_empty()
	server_detail = "online" if server_online else "offline"
	if not server_online:
		# Force the next attempt to rediscover instead of reusing a dead route.
		# A user-forced server is kept; only the resolved route is cleared.
		_invalidate_relay_route()
	server_status_changed.emit(server_online, server_detail)
	return server_online


func participants() -> Array[int]:
	## Everyone in the session, including us, in a stable order.
	var ids: Array[int] = [multiplayer.get_unique_id()]
	for peer_id: int in multiplayer.get_peers():
		ids.append(peer_id)
	ids.sort()
	return ids


func spawn_position(peer_id: int) -> Vector3:
	## Deterministic starting grid: five columns, then a row further back.
	var index: int = maxi(participants().find(peer_id), 0)
	var column: int = index % 5
	var row: int = index / 5
	return Vector3(-6.0 + column * 3.0, 0.25, 64.0 - row * 4.0)
