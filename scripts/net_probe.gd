extends Node
## Dev-only LAN connection probe. Run two processes:
##   godot --headless --path . res://scenes/dev/net_probe.tscn -- host
##   godot --headless --path . res://scenes/dev/net_probe.tscn -- client

var _role: String = "host"
var _elapsed: float = 0.0
var _joined: bool = false
var _start_race: bool = false
var _start_sent: bool = false


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_role = args[0]
	if args.size() > 2 and args[2] == "start":
		_start_race = true
	Network.host_started.connect(_on_host_started)
	Network.host_failed.connect(func(reason: String) -> void: print("PROBE host_failed=", reason))
	Network.join_succeeded.connect(_on_joined)
	Network.join_failed.connect(func(reason: String) -> void: print("PROBE join_failed=", reason); _done(1))
	Network.join_status_changed.connect(func(text: String) -> void: print("PROBE status=", text))
	Network.peers_changed.connect(_on_peers)
	Network.names_changed.connect(_on_names)
	if _role == "host":
		var mode: String = "lan"
		if args.size() > 1:
			mode = args[1]
		Network.set_local_name("HOSTP")
		Network.host_game(mode)
	else:
		Network.set_local_name("CLIENTP")
		var code: String = FileAccess.get_file_as_string("user://join_code.txt").strip_edges()
		print("PROBE joining ", code)
		Network.join_game(code)


func _on_host_started(code: String) -> void:
	print("PROBE host_started code=", code,
		" mode=", Network.connection_mode,
		" state=", Network.room_state,
		" relay=", Network.relay_active)
	var file: FileAccess = FileAccess.open("user://join_code.txt", FileAccess.WRITE)
	file.store_string(code)
	file.close()


func _on_joined() -> void:
	_joined = true
	print("PROBE joined id=", multiplayer.get_unique_id(), " peers=", multiplayer.get_peers())


func _on_peers() -> void:
	print("PROBE peers=", multiplayer.get_peers(), " names=", Network.player_names)
	if _role == "host" and _start_race and not _start_sent and not multiplayer.get_peers().is_empty():
		_start_sent = true
		await get_tree().create_timer(2.0).timeout
		print("PROBE starting race")
		Network.start_game(Network.RACE_SCENE, GameSettings.GAME_MINIGAMES)


func _on_names() -> void:
	print("PROBE names=", Network.player_names)


func _process(delta: float) -> void:
	_elapsed += delta
	if _joined and _elapsed > 25.0:
		_done(0)
	elif _elapsed > 40.0:
		print("PROBE timeout role=", _role, " active=", Network.is_session_active())
		_done(1)


func _done(code: int) -> void:
	print("PROBE done role=", _role, " code=", code)
	get_tree().quit(code)
