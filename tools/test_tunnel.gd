extends Node
## Dev check: RelayTunnel handshake against a local cartslop_server.py.

const RelayTunnel := preload("res://scripts/net/relay_tunnel.gd")

var _tunnel: Node
var _ready_hit: bool = false


func _ready() -> void:
	var token: String = OS.get_environment("TUNNEL_TOKEN")
	var port: int = int(OS.get_environment("TUNNEL_PORT"))
	print("TOKEN_LEN=", token.length(), " PORT=", port)
	_tunnel = RelayTunnel.new()
	add_child(_tunnel)
	_tunnel.tunnel_ready.connect(func() -> void:
		_ready_hit = true
		print("TUNNEL_READY=true")
		get_tree().quit(0))
	_tunnel.tunnel_lost.connect(func() -> void:
		print("TUNNEL_LOST"))
	_tunnel.configure("127.0.0.1", port, token, 8910)
	_tunnel.start()
	await get_tree().create_timer(6.0).timeout
	print("TUNNEL_READY=", _ready_hit)
	get_tree().quit(0 if _ready_hit else 1)
