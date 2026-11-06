extends Node
## Dev-only driver: join the LAN race room and verify the forced vehicle, the
## tag colour relay and the ping table on the client side.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Wrong on purpose: the host's truck must override this choice.
	GameSettings.minigame_vehicle = "shopping_cart"
	Network.set_local_tag_color("4cd964")
	Network.join_succeeded.connect(func() -> void: print("SYNC_CLIENT_JOINED"))
	Network.join_failed.connect(func(reason: String) -> void:
		print("SYNC_CLIENT_FAILED=", reason)
		get_tree().quit(1))
	for i in 120:
		if FileAccess.file_exists("user://sync_host_ready.txt"):
			break
		await get_tree().create_timer(0.25).timeout
	Network.join_lan_room({
		"host": "127.0.0.1",
		"port": 8910,
		"state": "lobby",
	})
	_after_join()
	await get_tree().create_timer(100.0).timeout
	print("SYNC_CLIENT_WATCHDOG")
	get_tree().quit(2)


func _after_join() -> void:
	for i in 30:
		await get_tree().create_timer(1.0).timeout
		var cart := get_tree().get_first_node_in_group("player") as CartPlayer
		var scene := get_tree().current_scene
		var scene_name: String = scene.scene_file_path.get_file() if scene != null else "none"
		if i % 5 == 0:
			print("SYNC_HB t=%d paused=%s scene=%s speed=%.1f ping1=%s" % [
				i, get_tree().paused, scene_name,
				cart.max_speed if cart != null else -1.0,
				Network.ping_table.get(1, -1)])
		if i >= 24:
			break
	var scene := get_tree().current_scene
	var race_ok: bool = scene != null and scene.scene_file_path == Network.RACE_SCENE
	var cart := get_tree().get_first_node_in_group("player") as CartPlayer
	# The host drives a truck (max_speed 18); the client picked the shopping
	# cart (19). After the forced-vehicle RPC the local cart must be a truck.
	var vehicle_ok: bool = cart != null and is_equal_approx(cart.max_speed, 18.0)
	var color_ok: bool = Network.color_of(1) == Color("ff9f43")
	var ping_ok: bool = Network.ping_table.has(1)
	print("SYNC_CLIENT race=%s vehicle=%s speed=%s color=%s pingtable=%s" % [
		race_ok, vehicle_ok, cart.max_speed if cart != null else -1.0, color_ok, ping_ok])
	get_tree().quit(0 if (race_ok and vehicle_ok and color_ok) else 1)
