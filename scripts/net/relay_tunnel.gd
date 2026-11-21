extends Node
## Host-side TCP tunnel to the Cart Slop Pi relay.
##
## Windows Firewall blocks inbound UDP for the exported game, so the Pi cannot
## reliably connect straight to the host's ENet server. Instead the host opens
## an outbound TCP connection to the Pi, and a tiny local UDP proxy gives each
## remote client its own loopback socket. ENet sees normal distinct peers.
##
## macOS notes (why the code looks like this):
##  * Outgoing TCP is the one direction macOS Local Network privacy never
##    blocks, so this tunnel is the reliable path; the loopback UDP proxy all
##    happens on 127.0.0.1, which is not a local-network operation.
##  * A Mac that sleeps with the lid closed leaves a TCP socket that can report
##    STATUS_CONNECTED forever while nothing reaches the Pi. reconnect() is
##    called by Network after wake detection.
##  * A slow Wi-Fi handshake can take longer than the retry delay; reconnecting
##    while the socket is still CONNECTING abandons a working handshake, so the
##    connect has its own CONNECT_TIMEOUT and the retry timer only runs after a
##    definite failure.
##  * put_data() can write a partial frame. The Pi's reader is strictly
##    length-prefixed, so every byte goes through a user-space queue flushed
##    with put_partial_data(); a partial write must never corrupt the stream.

signal tunnel_ready()
signal tunnel_lost(reason: String)

const RECONNECT_DELAY: float = 2.0
const RECONNECT_JITTER: float = 0.5
const RX_MAX: int = 256 * 1024
const TX_FLUSH_BUDGET: int = 64 * 1024
## A TCP handshake can outlive the retry delay on slow/roaming links.
const CONNECT_TIMEOUT: float = 10.0
## Refuse to buffer an unbounded amount of data for a stalled Pi.
const TX_QUEUE_MAX: int = 512 * 1024

var _host: String = ""
var _port: int = 0
var _token: String = ""
var _enet_port: int = 0
var _tcp := StreamPeerTCP.new()
var _rx := PackedByteArray()
var _line := ""
var _tx := PackedByteArray()
var _awaiting_ok: bool = false
var _ready: bool = false
var _hello_sent: bool = false
var _retry: float = 0.0
var _retry_attempt: int = 0
var _loss_reason: String = ""
var _connect_deadline_ms: int = 0
var _sockets: Dictionary = {} ## client id -> PacketPeerUDP
var _socket_seen: Dictionary = {} ## client id -> Time.get_ticks_msec() of last activity


func configure(host: String, port: int, token: String, enet_port: int) -> void:
	_host = host
	_port = port
	_token = token
	_enet_port = enet_port


func start() -> void:
	_reset_transport()
	_tcp.disconnect_from_host()
	_tcp = StreamPeerTCP.new()
	_retry_attempt = 0
	_retry = _next_retry_delay()
	_connect()


func stop() -> void:
	_host = ""
	_port = 0
	_token = ""
	_reset_transport()
	for id: int in _sockets:
		var udp: PacketPeerUDP = _sockets[id]
		if udp != null:
			udp.close()
	_sockets.clear()
	_socket_seen.clear()
	_tcp.disconnect_from_host()
	_tcp = StreamPeerTCP.new()


func is_ready() -> bool:
	return _ready


func reconnect() -> void:
	## Force a brand-new handshake. Used after sleep/wake or a network switch,
	## where the old socket can be half-open and never report an error on its
	## own (macOS laptops are the common case).
	if _host == "" or _port <= 0:
		return
	_reset_transport()
	_tcp.disconnect_from_host()
	_tcp = StreamPeerTCP.new()
	_retry = 0.0
	_connect()


func _reset_transport() -> void:
	_ready = false
	_hello_sent = false
	_awaiting_ok = false
	_loss_reason = ""
	_rx = PackedByteArray()
	_line = ""
	_tx = PackedByteArray()
	_connect_deadline_ms = 0


func _next_retry_delay() -> float:
	return RECONNECT_DELAY * (1.0 - RECONNECT_JITTER * 0.5 + randf() * RECONNECT_JITTER) * pow(1.5, float(mini(_retry_attempt, 6)))


func _connect() -> void:
	_tcp = StreamPeerTCP.new()
	# Nagle would add latency to the 20 Hz ENet frames we relay.
	_tcp.set_no_delay(true)
	var error: Error = _tcp.connect_to_host(_host, _port)
	if error != OK:
		_retry_attempt += 1
		_retry = _next_retry_delay()
		_connect_deadline_ms = 0
		_loss_reason = "connect_failed"
		tunnel_lost.emit(_loss_reason)
		return
	_connect_deadline_ms = Time.get_ticks_msec() + int(CONNECT_TIMEOUT * 1000.0)


func _process(delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	if not _ready:
		var state: int = _tcp.get_status()
		if state == StreamPeerTCP.STATUS_CONNECTING:
			# Give the handshake its full deadline: reconnecting underneath a
			# slow macOS Wi-Fi association used to abandon a working connect.
			if _connect_deadline_ms > 0 and now > _connect_deadline_ms:
				_tcp.disconnect_from_host()
				_tcp = StreamPeerTCP.new()
				_connect_deadline_ms = 0
				_retry_attempt += 1
				_retry = _next_retry_delay()
		else:
			_connect_deadline_ms = 0
			_retry -= delta
			if _retry <= 0.0 and _host != "" and _port > 0:
				_retry_attempt += 1
				_retry = _next_retry_delay()
				_connect()
				return
	_tcp.poll()
	var status: int = _tcp.get_status()
	if status != StreamPeerTCP.STATUS_CONNECTED:
		if _ready:
			_loss_reason = "tcp_dropped"
			tunnel_lost.emit(_loss_reason)
		_ready = false
		_hello_sent = false
		_awaiting_ok = false
		_rx = PackedByteArray()
		_line = ""
		_tx = PackedByteArray()
		# Do NOT close the per-client loopback sockets here. The Pi keeps its
		# client table (and ids) across a brief TCP tunnel drop, so preserving
		# the same loopback source ports lets ENet resume without re-handshaking
		# every peer. Idle sockets are reaped below; start()/stop() clear all.
		return
	_connect_deadline_ms = 0

	if not _hello_sent:
		_hello_sent = true
		_awaiting_ok = true
		_queue_tx(("TOKEN %s\n" % _token).to_utf8_buffer())

	var available: int = _tcp.get_available_bytes()
	if available > 0:
		var result: Array = _tcp.get_data(available)
		if int(result[0]) == OK:
			_rx.append_array(result[1] as PackedByteArray)
			if _rx.size() > RX_MAX:
				_drop_link(true, "rx_overflow")
				return

	if _awaiting_ok:
		var newline: int = _find_byte(_rx, 10)
		if newline < 0:
			_flush_tx()
			return
		var line_bytes: PackedByteArray = _rx.slice(0, newline)
		_rx = _rx.slice(newline + 1)
		var text: String = line_bytes.get_string_from_utf8().strip_edges()
		_awaiting_ok = false
		if text != "OK":
			# A rejected (rotated/expired) token used to fall straight back to
			# "not _hello_sent", which re-sent TOKEN every frame at 60 Hz. Drop
			# the link so the normal _retry backoff owns the next attempt.
			_drop_link(true, "token_rejected")
			return
		_ready = true
		_retry_attempt = 0
		tunnel_ready.emit()

	while _rx.size() >= 8:
		var client_id: int = _read_u32(_rx, 0)
		var length: int = _read_u32(_rx, 4)
		if length > 65535:
			_drop_link(true, "bad_frame")
			return
		if _rx.size() < 8 + length:
			if _rx.size() > RX_MAX:
				_drop_link(true, "rx_overflow")
				return
			break
		var payload: PackedByteArray = _rx.slice(8, 8 + length)
		_rx = _rx.slice(8 + length)
		if not _is_allowed_client(client_id):
			continue
		var udp: PacketPeerUDP = _socket_for(client_id)
		if udp != null:
			udp.put_packet(payload)

	for id: int in _sockets:
		var udp: PacketPeerUDP = _sockets[id]
		if udp == null:
			continue
		while udp.get_available_packet_count() > 0:
			_send_frame(id, udp.get_packet())
	_flush_tx()
	# Reap loopback sockets for clients the Pi has long since dropped. Without
	# this every join/leave leaves one UDP fd behind for the process lifetime.
	if _ready:
		for id: int in _sockets.keys():
			if now - int(_socket_seen.get(id, now)) <= 120000:
				continue
			var stale: PacketPeerUDP = _sockets[id]
			if stale != null:
				stale.close()
			_sockets.erase(id)
			_socket_seen.erase(id)


func _drop_link(force_reconnect: bool = false, reason: String = "dropped") -> void:
	## Tear the TCP side down without touching the loopback sockets. The retry
	## timer (or an explicit reconnect) owns the next attempt.
	var was_ready: bool = _ready
	_ready = false
	_hello_sent = false
	_awaiting_ok = false
	_rx = PackedByteArray()
	_line = ""
	_tx = PackedByteArray()
	_tcp.disconnect_from_host()
	_tcp = StreamPeerTCP.new()
	_retry_attempt += 1
	_retry = _next_retry_delay()
	_connect_deadline_ms = 0
	_loss_reason = reason
	if force_reconnect or was_ready:
		tunnel_lost.emit(_loss_reason)


func _is_allowed_client(client_id: int) -> bool:
	## Validate a Pi relay client_id (sequential 1..MAX_RELAY_CLIENTS assigned
	## by the Pi UDP relay, NOT a Godot ENet 32-bit peer ID). Cap total distinct
	## virtual UDP sockets so a malformed stream cannot allocate unbounded ports.
	if client_id <= 0 or client_id > 4096:
		return false
	if _sockets.has(client_id):
		return true
	return _sockets.size() < 32


func _socket_for(client_id: int) -> PacketPeerUDP:
	if _sockets.has(client_id):
		_socket_seen[client_id] = Time.get_ticks_msec()
		return _sockets[client_id] as PacketPeerUDP
	var udp := PacketPeerUDP.new()
	# 127.0.0.1 is loopback, not a local-network address under macOS 15 Local
	# Network privacy, so this proxy never needs a permission prompt.
	if udp.bind(0, "127.0.0.1") != OK:
		return null
	if udp.connect_to_host("127.0.0.1", _enet_port) != OK:
		udp.close()
		return null
	_sockets[client_id] = udp
	_socket_seen[client_id] = Time.get_ticks_msec()
	return udp


func _send_frame(client_id: int, payload: PackedByteArray) -> void:
	if not _ready or payload.size() > 65535:
		return
	var frame := PackedByteArray()
	_append_u32(frame, client_id)
	_append_u32(frame, payload.size())
	frame.append_array(payload)
	_socket_seen[client_id] = Time.get_ticks_msec()
	_queue_tx(frame)


func _queue_tx(frame: PackedByteArray) -> void:
	if _tx.size() + frame.size() > TX_QUEUE_MAX:
		# The Pi stopped reading. Drop the link rather than buffer forever or
		# emit a partial frame that would desynchronise its length-prefixed
		# reader.
		_drop_link(true, "tx_overflow")
		return
	_tx.append_array(frame)


func _flush_tx() -> void:
	if _tx.is_empty() or _tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	# put_partial_data() is the only honest write API here: put_data() may
	# accept fewer bytes than asked, and a partial frame corrupts the stream.
	var budget: int = TX_FLUSH_BUDGET
	while not _tx.is_empty() and budget > 0:
		var result: Array = _tcp.put_partial_data(_tx)
		if int(result[0]) != OK:
			_drop_link(true, "tx_error")
			return
		var sent: int = int(result[1])
		if sent <= 0:
			break
		_tx = _tx.slice(sent)
		budget -= sent


func _find_byte(data: PackedByteArray, value: int) -> int:
	for index in data.size():
		if int(data[index]) == value:
			return index
	return -1


func _read_u32(data: PackedByteArray, offset: int) -> int:
	return (int(data[offset]) << 24) | (int(data[offset + 1]) << 16) \
		| (int(data[offset + 2]) << 8) | int(data[offset + 3])


func _append_u32(data: PackedByteArray, value: int) -> void:
	data.append((value >> 24) & 0xFF)
	data.append((value >> 16) & 0xFF)
	data.append((value >> 8) & 0xFF)
	data.append(value & 0xFF)
