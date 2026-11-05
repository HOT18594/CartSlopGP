extends Node
## Peer-to-peer session manager (ENet over UDP).
##
## Hosting: opens a port, optionally asks the router (UPnP) for a mapping, and
## builds a 14-character join code from the reachable address plus a checksum.
## Joining: the code is validated and decoded, then the client connects
## straight to the host. No account, no game server.
##
## Code layout: 4 hex IP octets + 2 hex port bytes + 2 hex checksum, e.g.
## C0A80104 22CE 1F -> 192.168.1.4:8910 with checksum 0x1F.

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

const DEFAULT_PORT: int = 8910
const PORT_RANGE: int = 40
const MAX_PLAYERS: int = 8
const GAME_SCENE: String = "res://scenes/dev/driving_test.tscn"
const RACE_SCENE: String = "res://scenes/minigames/grass_race.tscn"
const LOBBY_SCENE: String = "res://scenes/ui/lobby_menu.tscn"
const MINIGAMES_SCENE: String = "res://scenes/ui/minigames_menu.tscn"
const PING_INTERVAL: float = 2.0
const RELAY_DISCOVERY_PORT: int = 42778
const RELAY_HEARTBEAT_INTERVAL: float = 20.0
const RelayTunnel := preload("res://scripts/net/relay_tunnel.gd")

var is_host: bool = false
var is_client: bool = false
var in_game: bool = false
var join_code: String = ""
var local_address: String = ""
var public_address: String = ""
var port: int = DEFAULT_PORT
var latency_ms: int = 0
var last_error: String = ""
var connection_mode: String = "online" ## "lan" or "online"
var custom_public_ip: String = ""
var player_names: Dictionary = {} ## peer id -> sanitized display name
var lan_code: String = "" ## Always-valid code for players on the same network.
var online_code: String = "" ## Public code, only when a route actually exists.
var upnp_mapped: bool = false ## True when the router accepted a port mapping.
var behind_cgnat: bool = false ## Router reports a carrier-shared address.
var join_pending: bool = false
var relay_base: String = ""
var relay_lan_ip: String = ""
var relay_token: String = ""
var relay_port: int = 0
var relay_lan_host: String = ""
var relay_public_host: String = ""
var relay_active: bool = false
var relay_room_code: String = ""
## Optional public Pi server address (hostname, IP, or URL) for internet joins.
var relay_server_url: String = ""
var relay_server_host: String = ""
var relay_server_http_port: int = 42777
var relay_base_public: bool = false
var relay_tunnel_token: String = ""
var relay_tunnel_port: int = 0
var relay_tunnel_active: bool = false
var _relay_tunnel: Node = null

## Host-chosen configuration, broadcast with _net_begin_game so every peer
## loads the same world with the same bots. Clients never write these locally.
var game_scene: String = GAME_SCENE
var session_mode: String = GameSettings.GAME_SANDBOX
var session_bots: bool = false
var session_bot_count: int = 0
var race_standings: Array[Dictionary] = [] ## peer id/name/time/place, filled by the race.

var _peer: ENetMultiplayerPeer
var _upnp: UPNP
var _host_ticket: int = 0
var _ping_timer: float = 0.0
var _join_started_ms: int = 0
var _relay_heartbeat: float = 0.0
var _relay_busy: bool = false
var _upnp_thread: Thread
var _upnp_result: Dictionary = {}
var _upnp_ticket: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if GameSettings.relay_server != "":
		set_relay_server(GameSettings.relay_server)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
	_poll_upnp_thread()
	_relay_heartbeat_tick(delta)
	if join_pending and Time.get_ticks_msec() - _join_started_ms > 12000:
		join_pending = false
		leave()
		join_failed.emit("Connection timed out. The host's port may be blocked, or the code is stale.")
		return
	if not is_session_active() or not is_connected_to_server():
		return
	_ping_timer += delta
	if _ping_timer >= PING_INTERVAL and not is_host:
		_ping_timer = 0.0
		rpc_id(1, "_net_ping", Time.get_ticks_msec())


func is_session_active() -> bool:
	return is_host or is_client


func is_connected_to_server() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() \
		== MultiplayerPeer.CONNECTION_CONNECTED


func peer_count() -> int:
	if not is_session_active():
		return 0
	return multiplayer.get_peers().size() + 1


# --------------------------------------------------------------------------
# hosting


func host_game(mode: String = "online") -> void:
	leave()
	_host_ticket += 1
	var ticket: int = _host_ticket
	connection_mode = "lan" if mode == "lan" else "online"
	GameSettings.connection_preference = connection_mode
	SceneLoader.begin_task("HOSTING A GAME", "Opening a port...")
	await get_tree().process_frame
	if ticket != _host_ticket:
		SceneLoader.end_task()
		return
	_upnp = UPNP.new()
	local_address = _local_ip()
	var bound_port: int = _open_server()
	if bound_port <= 0:
		SceneLoader.end_task()
		host_failed.emit("Could not open a UDP port.")
		return
	port = bound_port
	is_host = true
	in_game = false
	public_address = ""
	upnp_mapped = false
	behind_cgnat = false
	session_mode = GameSettings.multiplayer_mode
	session_bots = GameSettings.bots_enabled
	session_bot_count = GameSettings.effective_bot_count()
	lan_code = encode_address(local_address, port)
	online_code = ""
	join_code = lan_code
	player_names[1] = GameSettings.player_name

	if connection_mode == "online":
		SceneLoader.task_message("Looking for the Cart Slop server...")
		var found: bool = await _discover_relay()
		if ticket != _host_ticket:
			SceneLoader.end_task()
			return
		if found:
			SceneLoader.task_message("Registering with the Cart Slop server...")
			if await _register_relay(port):
				relay_active = true
				lan_code = encode_address(relay_lan_host, relay_port)
				if relay_public_host != "":
					online_code = encode_address(relay_public_host, relay_port)
				if relay_room_code != "":
					join_code = relay_room_code
				else:
					join_code = online_code if online_code != "" else lan_code
				public_address = relay_public_host if relay_public_host != "" else relay_lan_host
		if not relay_active:
			if _valid_ip(custom_public_ip):
				# The player says they forwarded the port (or uses a VPN address).
				public_address = custom_public_ip
				online_code = encode_address(public_address, port)
				join_code = online_code
			else:
				SceneLoader.task_message("Asking your router for a port (UPnP)...")
				var upnp_result: Dictionary = await _upnp_lookup(port)
				if ticket != _host_ticket:
					SceneLoader.end_task()
					leave()
					return
				behind_cgnat = bool(upnp_result.get("cgnet", false))
				var upnp_ip: String = str(upnp_result.get("ip", ""))
				if upnp_ip != "":
					upnp_mapped = true
					public_address = upnp_ip
					online_code = encode_address(public_address, port)
					join_code = online_code
				elif bool(upnp_result.get("mapped", false)) and not bool(upnp_result.get("cgnet", false)):
					# The router accepted the mapping but would not report its
					# external address; ask the public-IP service instead.
					var mapped_ip: String = await _public_ip_lookup()
					if mapped_ip != "":
						upnp_mapped = true
						public_address = mapped_ip
						online_code = encode_address(public_address, port)
						join_code = online_code
					else:
						public_address = ""
						join_code = lan_code
				else:
					# Mapping failed. A public IP alone is NOT reachable, so keep the
					# LAN code and show the public IP as a diagnostic only.
					SceneLoader.task_message("Router mapping failed - checking your public IP...")
					var public_ip: String = await _public_ip_lookup()
					if ticket != _host_ticket:
						SceneLoader.end_task()
						leave()
						return
					public_address = public_ip
					join_code = lan_code

	if ticket != _host_ticket:
		SceneLoader.end_task()
		leave()
		return
	SceneLoader.end_task()
	host_started.emit(join_code)
	peers_changed.emit()


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
	var deadline: int = Time.get_ticks_msec() + 1200
	while Time.get_ticks_msec() < deadline:
		while udp.get_available_packet_count() > 0:
			var text: String = udp.get_packet().get_string_from_utf8()
			var parsed: Variant = JSON.parse_string(text)
			if parsed is Dictionary and str((parsed as Dictionary).get("service", "")) == "cartslop":
				relay_lan_ip = str((parsed as Dictionary).get("lan_ip", ""))
				var http_port: int = int((parsed as Dictionary).get("http_port", 42777))
				if relay_lan_ip != "":
					relay_base = "http://%s:%d" % [relay_lan_ip, http_port]
					relay_base_public = false
					udp.close()
					return true
		await get_tree().process_frame
	udp.close()
	return false


func _relay_post(path: String, payload: Dictionary) -> Dictionary:
	if relay_base == "":
		return {}
	var http := HTTPRequest.new()
	http.timeout = 6.0
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


func _relay_get(path: String) -> Dictionary:
	if relay_base == "":
		return {}
	var http := HTTPRequest.new()
	http.timeout = 6.0
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
		return []
	var response: Dictionary = await _relay_get("/api/lobbies")
	var lobbies: Variant = response.get("lobbies", [])
	if lobbies is Array:
		return lobbies as Array
	return []


func _register_relay(local_port: int) -> bool:
	var response: Dictionary = await _relay_post("/api/register", {
		"name": GameSettings.player_name,
		"local_port": local_port,
		"local_ip": local_address,
		"tunnel": true,
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
	await _relay_post("/api/heartbeat", {"token": relay_token})
	_relay_busy = false


func _relay_unregister_async(token: String, base: String) -> void:
	if token == "" or base == "":
		return
	var http := HTTPRequest.new()
	http.timeout = 3.0
	add_child(http)
	http.request_completed.connect(func(_r: int, _c: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		http.queue_free())
	var headers: PackedStringArray = ["Content-Type: application/json"]
	http.request(base + "/api/unregister", headers, HTTPClient.METHOD_POST,
		JSON.stringify({"token": token}))


func _upnp_lookup(udp_port: int) -> Dictionary:
	## Runs discovery in a thread so the loading overlay keeps animating. Some
	## routers never answer, so the UI waits at most 6 seconds and keeps the
	## thread alive in the background; if it answers later we upgrade the code.
	var result: Dictionary = {"ip": "", "external": "", "cgnet": false, "mapped": false}
	var thread := Thread.new()
	if thread.start(_upnp_worker.bind(udp_port, result)) != OK:
		return result
	var deadline: int = Time.get_ticks_msec() + 6000
	while thread.is_alive() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if thread.is_alive():
		_upnp_thread = thread
		_upnp_result = result
		_upnp_ticket = _host_ticket
		return result
	thread.wait_to_finish()
	return result


func _poll_upnp_thread() -> void:
	if _upnp_thread == null or _upnp_thread.is_alive():
		return
	_upnp_thread.wait_to_finish()
	_upnp_thread = null
	var result: Dictionary = _upnp_result
	_upnp_result = {}
	if _upnp_ticket != _host_ticket or not is_host:
		return
	behind_cgnat = bool(result.get("cgnet", false))
	var ip: String = str(result.get("ip", ""))
	if ip == "" or online_code != "":
		return
	# The router finally answered after the overlay was dismissed.
	upnp_mapped = true
	public_address = ip
	online_code = encode_address(ip, port)
	join_code = online_code
	code_updated.emit(online_code)


func _upnp_worker(udp_port: int, result: Dictionary) -> void:
	var upnp := UPNP.new()
	var found: Error = upnp.discover(2000, 2, "InternetGatewayDevice")
	if found != OK:
		# Some IGDv2 routers only answer an unfiltered search.
		upnp = UPNP.new()
		found = upnp.discover(2000, 2, "")
	if found != OK:
		return
	var gateway: UPNPDevice = upnp.get_gateway()
	if gateway == null or not gateway.is_valid_gateway():
		return
	# Try a one-hour lease first, then permanent for routers that reject leases.
	var mapped: bool = false
	for duration: int in [3600, 0]:
		if upnp.add_port_mapping(udp_port, udp_port, "Cart Slop GP", "UDP", duration) == OK:
			mapped = true
			break
	if not mapped:
		return
	result["mapped"] = true
	var external: String = upnp.get_external_ip()
	result["external"] = external
	if external == "" or external == "0.0.0.0":
		return
	if _is_public_ipv4(external):
		result["ip"] = external
	elif _is_cgnat_ipv4(external):
		result["cgnet"] = true


func _public_ip_lookup() -> String:
	var http := HTTPRequest.new()
	http.timeout = 4.0
	add_child(http)
	if http.request("https://api.ipify.org") != OK:
		http.queue_free()
		return ""
	var response: Array = await http.request_completed
	http.queue_free()
	if int(response[1]) != 200:
		return ""
	var text: String = (response[3] as PackedByteArray).get_string_from_utf8().strip_edges()
	return text if _valid_ip(text) else ""


func _open_server() -> int:
	for offset in PORT_RANGE:
		var candidate: int = DEFAULT_PORT + offset
		var peer := ENetMultiplayerPeer.new()
		if peer.create_server(candidate, MAX_PLAYERS) == OK:
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


func has_online_route() -> bool:
	return online_code != ""


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


func set_custom_public_ip(address: String) -> void:
	custom_public_ip = address.strip_edges()


func set_relay_server(raw: String) -> void:
	## Accepts "1.2.3.4", "1.2.3.4:42777", "cartslop.example.com",
	## or a full http(s) URL. Empty means "use LAN discovery".
	var text: String = raw.strip_edges()
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


func join_game(raw_code: String) -> void:
	var text: String = raw_code.strip_edges()
	var address: Dictionary = decode_address(text)
	if address.is_empty():
		var short: String = text.to_upper().replace(" ", "")
		if short.length() < 4 or short.length() > 6:
			join_failed.emit("That code is not valid. Use a 5-character room code or an address.")
			return
		for character: String in short:
			if not "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".contains(character):
				join_failed.emit("Room codes use letters and numbers only.")
				return
		join_status_changed.emit("Looking up room %s..." % short)
		if not await _discover_relay():
			join_failed.emit("Lobby server not found. Use the full code or connect to the same Wi-Fi.")
			return
		var room: Dictionary = await _relay_get("/api/room/" + short)
		if room.is_empty():
			join_failed.emit("Room %s was not found. Ask the host for a fresh code." % short)
			return
		var host: String = str(room.get("lan_host", ""))
		if relay_base_public:
			# The client reached the Pi by a public address/hostname, so the
			# relay is on that same address; public_host is only a fallback.
			host = relay_server_host if relay_server_host != "" else str(room.get("public_host", ""))
			if host == "":
				host = str(room.get("lan_host", ""))
		var relay_port: int = int(room.get("relay_port", 0))
		if host == "" or relay_port <= 0:
			join_failed.emit("Room %s has no relay port." % short)
			return
		address = {"ip": host, "port": relay_port}
	leave()
	var connect_ip: String = str(address["ip"])
	if not _valid_ip(connect_ip):
		connect_ip = IP.resolve_hostname(connect_ip)
		if connect_ip == "":
			join_failed.emit("Could not resolve %s." % str(address["ip"]))
			return
	join_status_changed.emit("Connecting to %s:%d..." % [connect_ip, int(address["port"])])
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(connect_ip, int(address["port"]))
	if error != OK:
		join_failed.emit("Could not start the connection.")
		return
	_peer = peer
	multiplayer.multiplayer_peer = peer
	is_client = true
	in_game = false
	join_pending = true
	_join_started_ms = Time.get_ticks_msec()
	player_names.clear()


func leave() -> void:
	_host_ticket += 1 ## Cancels an in-flight host_game() await chain.
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
	lan_code = ""
	online_code = ""
	upnp_mapped = false
	behind_cgnat = false
	relay_active = false
	relay_token = ""
	relay_port = 0
	relay_lan_host = ""
	relay_public_host = ""
	relay_room_code = ""
	relay_base = ""
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
	race_standings.clear()


# --------------------------------------------------------------------------
# session config (host -> everyone, while still in the lobby)


func configure_session(mode: String, bots: bool, count: int) -> void:
	if not is_host:
		return
	session_mode = mode
	session_bots = bots
	session_bot_count = count
	rpc("_net_session_config", mode, bots, count)


@rpc("authority", "call_local", "reliable")
func _net_session_config(mode: String, bots: bool, count: int) -> void:
	session_mode = mode
	session_bots = bots
	session_bot_count = count
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
	rpc("_net_begin_game", target, chosen_mode, session_bots, session_bot_count)


@rpc("authority", "call_local", "reliable")
func _net_begin_game(scene_path: String, mode: String, bots: bool, count: int) -> void:
	in_game = true
	game_scene = scene_path
	session_mode = mode
	session_bots = bots
	session_bot_count = count
	# The host's settings win for this session; nothing is written to disk.
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
	if not is_session_active():
		SceneLoader.go_to(LOBBY_SCENE, "MULTIPLAYER")
		return
	if is_host:
		in_game = false
		rpc("_net_return_lobby")
	else:
		SceneLoader.go_to(LOBBY_SCENE, "MULTIPLAYER")


@rpc("authority", "call_local", "reliable")
func _net_return_lobby() -> void:
	in_game = false
	SceneLoader.go_to(LOBBY_SCENE, "MULTIPLAYER")


# --------------------------------------------------------------------------
# signals


func _on_peer_connected(id: int) -> void:
	peers_changed.emit()
	if is_host and in_game:
		rpc_id(id, "_net_begin_game", game_scene, session_mode,
			session_bots, session_bot_count)
	if is_session_active():
		# Re-announce our name so the newcomer (and everyone) has it.
		rpc("_net_set_name", multiplayer.get_unique_id(), GameSettings.player_name)


@rpc("any_peer", "call_local", "reliable")
func _net_set_name(peer_id: int, raw_name: String) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	# Host relays client names so every client sees the whole player list.
	if sender != 0 and sender != 1 and peer_id != sender:
		return
	player_names[peer_id] = GameSettings.sanitize_name(raw_name)
	names_changed.emit()
	if is_host and sender != 0 and sender != 1:
		rpc("_net_set_name", peer_id, raw_name)


func _on_peer_disconnected(id: int) -> void:
	player_names.erase(id)
	peers_changed.emit()
	names_changed.emit()


func _on_connected_to_server() -> void:
	is_client = true
	join_pending = false
	rpc("_net_set_name", multiplayer.get_unique_id(), GameSettings.player_name)
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
		SceneLoader.go_to(LOBBY_SCENE, "SESSION ENDED", "The host disconnected.")


# --------------------------------------------------------------------------
# ping


@rpc("any_peer", "unreliable")
func _net_ping(stamp: int) -> void:
	if multiplayer.is_server():
		rpc_id(multiplayer.get_remote_sender_id(), "_net_pong", stamp)


@rpc("authority", "unreliable")
func _net_pong(stamp: int) -> void:
	latency_ms = Time.get_ticks_msec() - stamp
	latency_changed.emit(latency_ms)


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
