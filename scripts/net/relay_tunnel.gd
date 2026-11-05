extends Node
## Host-side TCP tunnel to the Cart Slop Pi relay.
##
## Windows Firewall blocks inbound UDP for the exported game, so the Pi cannot
## reliably connect straight to the host's ENet server. Instead the host opens
## an outbound TCP connection to the Pi, and a tiny local UDP proxy gives each
## remote client its own loopback socket. ENet sees normal distinct peers.

signal tunnel_ready()
signal tunnel_lost()

const RECONNECT_DELAY: float = 2.0

var _host: String = ""
var _port: int = 0
var _token: String = ""
var _enet_port: int = 0
var _tcp := StreamPeerTCP.new()
var _rx := PackedByteArray()
var _line := ""
var _awaiting_ok: bool = false
var _ready: bool = false
var _hello_sent: bool = false
var _retry: float = 0.0
var _sockets: Dictionary = {} ## client id -> PacketPeerUDP


func configure(host: String, port: int, token: String, enet_port: int) -> void:
	_host = host
	_port = port
	_token = token
	_enet_port = enet_port


func start() -> void:
	_ready = false
	_hello_sent = false
	_awaiting_ok = false
	_rx = PackedByteArray()
	_line = ""
	for id: int in _sockets:
		var udp: PacketPeerUDP = _sockets[id]
		if udp != null:
			udp.close()
	_sockets.clear()
	_tcp.disconnect_from_host()
	_tcp = StreamPeerTCP.new()
	_retry = RECONNECT_DELAY
	_connect()


func stop() -> void:
	_host = ""
	_port = 0
	_token = ""
	_ready = false
	_hello_sent = false
	_awaiting_ok = false
	_rx = PackedByteArray()
	_line = ""
	for id: int in _sockets:
		var udp: PacketPeerUDP = _sockets[id]
		if udp != null:
			udp.close()
	_sockets.clear()
	_tcp.disconnect_from_host()
	_tcp = StreamPeerTCP.new()


func is_ready() -> bool:
	return _ready


func _connect() -> void:
	_tcp = StreamPeerTCP.new()
	var error: Error = _tcp.connect_to_host(_host, _port)
	if error != OK:
		_retry = RECONNECT_DELAY
		tunnel_lost.emit()


func _process(delta: float) -> void:
	if not _ready:
		_retry -= delta
		if _retry <= 0.0 and _tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_retry = RECONNECT_DELAY
			if _host != "" and _port > 0:
				_connect()
	_tcp.poll()
	var status: int = _tcp.get_status()
	if status != StreamPeerTCP.STATUS_CONNECTED:
		if _ready:
			tunnel_lost.emit()
		_ready = false
		_hello_sent = false
		_awaiting_ok = false
		_rx = PackedByteArray()
		_line = ""
		for id: int in _sockets:
			var udp: PacketPeerUDP = _sockets[id]
			if udp != null:
				udp.close()
		_sockets.clear()
		return

	if not _hello_sent:
		_hello_sent = true
		_awaiting_ok = true
		_tcp.put_data(("TOKEN %s\n" % _token).to_utf8_buffer())

	var available: int = _tcp.get_available_bytes()
	if available > 0:
		var result: Array = _tcp.get_data(available)
		if int(result[0]) == OK:
			_rx.append_array(result[1] as PackedByteArray)

	if _awaiting_ok:
		var newline: int = _find_byte(_rx, 10)
		if newline < 0:
			return
		var line_bytes: PackedByteArray = _rx.slice(0, newline)
		_rx = _rx.slice(newline + 1)
		var text: String = line_bytes.get_string_from_utf8().strip_edges()
		_awaiting_ok = false
		if text != "OK":
			_hello_sent = false
			_retry = RECONNECT_DELAY
			return
		_ready = true
		tunnel_ready.emit()

	while _rx.size() >= 8:
		var client_id: int = _read_u32(_rx, 0)
		var length: int = _read_u32(_rx, 4)
		if length > 65535:
			stop()
			return
		if _rx.size() < 8 + length:
			break
		var payload: PackedByteArray = _rx.slice(8, 8 + length)
		_rx = _rx.slice(8 + length)
		var udp: PacketPeerUDP = _socket_for(client_id)
		if udp != null:
			udp.put_packet(payload)

	for id: int in _sockets:
		var udp: PacketPeerUDP = _sockets[id]
		if udp == null:
			continue
		while udp.get_available_packet_count() > 0:
			_send_frame(id, udp.get_packet())


func _socket_for(client_id: int) -> PacketPeerUDP:
	if _sockets.has(client_id):
		return _sockets[client_id] as PacketPeerUDP
	var udp := PacketPeerUDP.new()
	if udp.bind(0, "127.0.0.1") != OK:
		return null
	if udp.connect_to_host("127.0.0.1", _enet_port) != OK:
		udp.close()
		return null
	_sockets[client_id] = udp
	return udp


func _send_frame(client_id: int, payload: PackedByteArray) -> void:
	if not _ready or payload.size() > 65535:
		return
	var frame := PackedByteArray()
	_append_u32(frame, client_id)
	_append_u32(frame, payload.size())
	frame.append_array(payload)
	_tcp.put_data(frame)


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
