extends Node
## Dev check: full loop through RelayTunnel and a fake local ENet socket.

const RelayTunnel := preload("res://scripts/net/relay_tunnel.gd")

var _tunnel: Node
var _game: PacketPeerUDP
var _client: PacketPeerUDP
var _token: String
var _tunnel_port: int
var _relay_port: int


func _ready() -> void:
	_token = OS.get_environment("TUNNEL_TOKEN")
	_tunnel_port = int(OS.get_environment("TUNNEL_PORT"))
	_relay_port = int(OS.get_environment("RELAY_PORT"))
	_game = PacketPeerUDP.new()
	if _game.bind(8910) != OK:
		print("GAME_BIND_FAIL")
		get_tree().quit(1)
		return
	_tunnel = RelayTunnel.new()
	add_child(_tunnel)
	_tunnel.tunnel_ready.connect(_on_ready)
	_tunnel.tunnel_lost.connect(func() -> void: print("TUNNEL_LOST"))
	_tunnel.configure("127.0.0.1", _tunnel_port, _token, 8910)
	_tunnel.start()
	await get_tree().create_timer(8.0).timeout
	print("TIMEOUT")
	get_tree().quit(1)


func _on_ready() -> void:
	print("TUNNEL_READY")
	_client = PacketPeerUDP.new()
	_client.bind(0)
	_client.set_dest_address("127.0.0.1", _relay_port)
	_client.put_packet("HELLO-FROM-CLIENT".to_utf8_buffer())
	for i in 40:
		await get_tree().create_timer(0.05).timeout
		if _game.get_available_packet_count() > 0:
			var data: PackedByteArray = _game.get_packet()
			var port: int = _game.get_packet_port()
			print("GAME_GOT=", data.get_string_from_utf8(), " PORT=", port)
			_game.set_dest_address("127.0.0.1", port)
			_game.put_packet("HELLO-FROM-HOST".to_utf8_buffer())
			for j in 40:
				await get_tree().create_timer(0.05).timeout
				if _client.get_available_packet_count() > 0:
					print("CLIENT_GOT=", _client.get_packet().get_string_from_utf8())
					get_tree().quit(0)
					return
			print("CLIENT_TIMEOUT")
			get_tree().quit(1)
			return
	print("GAME_TIMEOUT")
	get_tree().quit(1)
