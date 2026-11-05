extends Node
## Peer-to-peer session manager (ENet over UDP).
##
## Hosting: opens a port, tries UPnP so the router forwards it, and builds a
## short join code from the reachable address. Joining: the code is decoded and
## the client connects straight to the host. No server or account is involved.
##
## Join code = 12 hex chars: 4 IP octets + 2 port bytes (e.g. CB00710522CE).
## A plain "ip:port" string is also accepted.

signal host_started(code: String)
signal host_failed(reason: String)
signal join_status_changed(text: String)
signal join_succeeded()
signal join_failed(reason: String)
signal session_ended(reason: String)
signal peers_changed()
signal latency_changed(ms: int)
signal code_updated(code: String)

const DEFAULT_PORT: int = 8910
const PORT_RANGE: int = 40
const MAX_PLAYERS: int = 8
const GAME_SCENE: String = "res://scenes/dev/driving_test.tscn"
const LOBBY_SCENE: String = "res://scenes/ui/lobby_menu.tscn"
const PING_INTERVAL: float = 2.0

var is_host: bool = false
var is_client: bool = false
var in_game: bool = false
var join_code: String = ""
var local_address: String = ""
var public_address: String = ""
var port: int = DEFAULT_PORT
var latency_ms: int = 0
var last_error: String = ""

var _peer: ENetMultiplayerPeer
var _upnp: UPNP
var _ping_timer: float = 0.0
var _ip_request: HTTPRequest


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
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


func host_game() -> void:
	leave()
	_upnp = UPNP.new()
	local_address = _local_ip()
	var bound_port: int = _open_server()
	if bound_port <= 0:
		host_failed.emit("Could not open a UDP port.")
		return
	port = bound_port
	is_host = true
	in_game = false
	join_code = encode_address(local_address, port)
	public_address = ""
	host_started.emit(join_code)
	peers_changed.emit()
	# Router mapping and public IP are best-effort: LAN play works without them.
	_try_upnp(port)
	_request_public_ip()


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
	for address: String in IP.get_local_addresses():
		if address.begins_with("127.") or address.contains(":"):
			continue
		if address.begins_with("192.168.") or address.begins_with("10.") or address.begins_with("172."):
			return address
	return "127.0.0.1"


func _try_upnp(udp_port: int) -> void:
	## 1.5 s worst case; turns a LAN-only host into an internet-hosted one when
	## the router supports UPnP.
	if _upnp == null:
		return
	var discover_error: Error = _upnp.discover(1500, 2, "InternetGatewayDevice")
	if discover_error != OK:
		last_error = "upnp_unavailable"
		return
	var gateway: UPNPDevice = _upnp.get_gateway()
	if gateway == null or not gateway.is_valid_gateway():
		last_error = "upnp_no_gateway"
		return
	var mapping_error: Error = _upnp.add_port_mapping(udp_port, udp_port, "Cart Slop GP", "UDP", 0)
	if mapping_error != OK:
		last_error = "upnp_mapping_failed"
		return
	var external: String = _upnp.get_external_ip()
	if external != "" and external != "0.0.0.0":
		public_address = external
		join_code = encode_address(external, udp_port)
		code_updated.emit(join_code)


func _request_public_ip() -> void:
	if _ip_request != null:
		return
	_ip_request = HTTPRequest.new()
	_ip_request.timeout = 4.0
	add_child(_ip_request)
	_ip_request.request_completed.connect(_on_ip_resolved, CONNECT_ONE_SHOT)
	if _ip_request.request("https://api.ipify.org") != OK:
		_ip_request.queue_free()
		_ip_request = null


func _on_ip_resolved(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var text: String = body.get_string_from_utf8().strip_edges()
	if code == 200 and text.count(".") == 3:
		public_address = text
		# Keep the UPnP code if it already used a public address.
		if join_code == encode_address(local_address, port):
			join_code = encode_address(text, port)
			code_updated.emit(join_code)
	if is_instance_valid(_ip_request):
		_ip_request.queue_free()
		_ip_request = null


# --------------------------------------------------------------------------
# joining


func join_game(raw_code: String) -> void:
	var address: Dictionary = decode_address(raw_code)
	if address.is_empty():
		join_failed.emit("That code does not look right.")
		return
	leave()
	join_status_changed.emit("Connecting to %s:%d..." % [address["ip"], address["port"]])
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(str(address["ip"]), int(address["port"]))
	if error != OK:
		join_failed.emit("Could not start the connection.")
		return
	_peer = peer
	multiplayer.multiplayer_peer = peer
	is_client = true
	in_game = false


func leave() -> void:
	if _peer != null:
		_peer.close()
	if multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer != _peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	_peer = null
	is_host = false
	is_client = false
	in_game = false
	join_code = ""
	public_address = ""
	latency_ms = 0
	last_error = ""


# --------------------------------------------------------------------------
# session flow


func start_game() -> void:
	if not is_host:
		return
	in_game = true
	rpc("_net_begin_game")


@rpc("authority", "call_local", "reliable")
func _net_begin_game() -> void:
	in_game = true
	get_tree().change_scene_to_file(GAME_SCENE)


func return_to_lobby(reason: String = "") -> void:
	if is_session_active():
		leave()
	session_ended.emit(reason)
	get_tree().change_scene_to_file(LOBBY_SCENE)


# --------------------------------------------------------------------------
# signals


func _on_peer_connected(id: int) -> void:
	peers_changed.emit()
	if is_host and in_game:
		rpc_id(id, "_net_begin_game")


func _on_peer_disconnected(_id: int) -> void:
	peers_changed.emit()


func _on_connected_to_server() -> void:
	is_client = true
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
		get_tree().change_scene_to_file(LOBBY_SCENE)


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
	var parts: PackedStringArray = ip.split(".")
	if parts.size() != 4:
		return ""
	var out: String = ""
	for part: String in parts:
		out += "%02X" % clampi(int(part), 0, 255)
	out += "%04X" % clampi(udp_port, 0, 65535)
	return out


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
	if text.length() != 12:
		return {}
	for character in text:
		if not ("0123456789ABCDEF".contains(character)):
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
