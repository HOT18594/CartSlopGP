extends Node

func _ready() -> void:
	var used: bool = Network.call("_use_default_public_relay")
	print("PUBLIC_FALLBACK used=%s host=%s base=%s default=%s" % [
		used, Network.relay_server_host, Network.relay_base, Network.DEFAULT_RELAY_SERVER])
	Network.call("_clear_default_public_relay")
	var ok: bool = used and Network.DEFAULT_RELAY_SERVER == "68.204.45.1:42777" \
		and Network.relay_server_host == ""
	print("PUBLIC_FALLBACK: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
