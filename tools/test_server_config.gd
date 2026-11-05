extends Node
## Dev check: public server URL parsing and HTTP lookup.


func _ready() -> void:
	Network.set_relay_server("127.0.0.1:42777")
	print("LOCAL_IP=", Network._local_ip())
	print("SERVER_URL=", Network.relay_server_url)
	print("SERVER_HOST=", Network.relay_server_host)
	print("SERVER_HTTP=", Network.relay_server_http_port)
	print("RELAl_BASE_PUBLIC=", Network.relay_base_public)
	var rooms: Array = await Network.fetch_lobbies()
	print("LOBBIES=", rooms.size())
	get_tree().quit(0)
