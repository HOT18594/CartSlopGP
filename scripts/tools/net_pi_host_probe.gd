extends Node
## Temporary diagnostic: open a real Pi room and print the code, then hold it
## open so an external curl/PowerShell probe can inspect /api/room/<code>.
## Run: godot --headless --path godot_project res://scripts/tools/net_pi_host_probe.tscn

func _ready() -> void:
	Network.host_started.connect(_on_started)
	Network.host_failed.connect(func(reason: String) -> void:
		print("PI_HOST_PROBE failed: " + reason)
		get_tree().quit(2))
	print("PI_HOST_PROBE hosting...")
	Network.host_game("pi")


func _on_started(code: String) -> void:
	print("PI_HOST_PROBE code=%s relay_base=%s public=%s lan_ip=%s" % [
		code, Network.relay_base, str(Network.relay_base_public),
		Network.relay_lan_ip])
	print("PI_HOST_PROBE local_ip=%s port=%d" % [Network.local_address, Network.port])
	var timer := get_tree().create_timer(45.0)
	timer.timeout.connect(func() -> void:
		print("PI_HOST_PROBE done")
		Network.leave()
		get_tree().quit(0))
