extends Node
## Dev check: UDP discovery against a locally running cartslop_server.py.


func _ready() -> void:
	var ok: bool = await Network._discover_relay()
	print("DISCOVERY_RESULT=", ok, " BASE=", Network.relay_base, " PUBLIC=", Network.relay_base_public)
	get_tree().quit(0 if ok else 1)
