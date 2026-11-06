extends Node
## Dev-only driver: LAN-host a race and verify the v0.7.0 sync features.
## Lives under /root so scene changes cannot kill the coroutine.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Fresh runs must not see a stale ready-flag.
	var stale: String = "user://sync_host_ready.txt"
	if FileAccess.file_exists(stale):
		DirAccess.remove_absolute(stale)
	GameSettings.minigame_vehicle = "truck"
	Network.host_started.connect(_on_host)
	Network.host_failed.connect(func(reason: String) -> void:
		print("SYNC_HOST_FAILED=", reason)
		get_tree().quit(1))
	Network.host_game("lan")
	await get_tree().create_timer(100.0).timeout
	print("SYNC_HOST_WATCHDOG")
	get_tree().quit(2)


func _on_host(_code: String) -> void:
	print("SYNC_HOST_READY")
	var flag := FileAccess.open("user://sync_host_ready.txt", FileAccess.WRITE)
	if flag != null:
		flag.store_string("ready")
		flag.close()
	for i in 80:
		if Network.peer_count() > 1:
			break
		await get_tree().create_timer(0.5).timeout
	print("SYNC_HOST_PEERS=", Network.peer_count())
	if Network.peer_count() <= 1:
		get_tree().quit(1)
		return
	# Distinct tag colour for the host; the client wears green.
	Network.set_local_tag_color("ff9f43")
	Network.start_game(Network.RACE_SCENE, GameSettings.GAME_MINIGAMES)
	# Hold the room open until the client has printed its own verdict and
	# disconnected (or the cap hits); quitting early would yank the client
	# back to the lobby mid-test and fake a failure.
	var saw_color: bool = false
	for i in 60:
		await get_tree().create_timer(1.0).timeout
		var scene := get_tree().current_scene
		var scene_name: String = scene.scene_file_path.get_file() if scene != null else "none"
		for peer_id: int in Network.player_colors:
			if peer_id != 1 and Network.color_of(peer_id) == Color("4cd964"):
				saw_color = true
		if i % 5 == 0:
			print("SYNC_HB t=%d paused=%s scene=%s ready_peers=%d" % [
				i, get_tree().paused, scene_name, Network.scene_ready_peers.size()])
		if i >= 22 and Network.peer_count() <= 1:
			break
	var scene := get_tree().current_scene
	var race_ok: bool = scene != null and scene.scene_file_path == Network.RACE_SCENE
	var vehicle_ok: bool = scene != null and str(scene.get("_race_vehicle")) == "truck"
	var color_ok: bool = saw_color
	var ping_ok: bool = Network.ping_table.has(1)
	print("SYNC_HOST race=%s vehicle=%s color=%s pingtable=%s" % [
		race_ok, vehicle_ok, color_ok, ping_ok])
	get_tree().quit(0 if (race_ok and vehicle_ok and color_ok) else 1)
