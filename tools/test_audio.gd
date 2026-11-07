extends Node
## Dev-only: validates the shipped audio graph without needing speakers.

var _failures: int = 0


func _ready() -> void:
	print("SFX_BUS=", AudioServer.get_bus_index("SFX"))
	_expect(AudioServer.get_bus_index("SFX") >= 0, "SFX bus exists")

	var cart: Node = load("res://scenes/player/cart_player.tscn").instantiate()
	add_child(cart)
	for i in 4:
		await get_tree().process_frame
	var feedback: Node = cart.get_node("Feedback")
	var missing: Array = feedback.get("missing_audio")
	_expect(missing.is_empty(), "CartFeedback has no missing streams: %s" % str(missing))

	for name in ["EngineAudio", "SkidAudio", "ImpactLightAudio", "ImpactHeavyAudio",
			"CrashAudio", "ThudAudio", "BoostStartAudio", "BoostLoopAudio"]:
		var player: AudioStreamPlayer3D = feedback.get_node(name) as AudioStreamPlayer3D
		_expect(player != null and player.stream != null, name + " has a stream")
		if player != null:
			_expect(player.bus == "SFX", name + " uses SFX")

	var engine: AudioStreamPlayer3D = feedback.get_node("EngineAudio")
	var skid: AudioStreamPlayer3D = feedback.get_node("SkidAudio")
	_expect(_is_looped(engine.stream), "engine loop is looped")
	_expect(_is_looped(skid.stream), "skid loop is looped")

	var pad: Node = load("res://scenes/track/boost_pad.tscn").instantiate()
	add_child(pad)
	await get_tree().process_frame
	_expect(pad.get("pad_sound") != null, "boost pad has a sound")

	for path in [
		"res://assets/audio/ambience/forest_ambience.mp3",
		"res://assets/audio/sfx/race/countdown_beep.wav",
		"res://assets/audio/sfx/race/countdown_go.wav",
		"res://assets/audio/sfx/race/lap_chime.wav",
		"res://assets/audio/sfx/race/finish_fanfare.wav",
		"res://assets/audio/sfx/ui/ui_click.wav",
		"res://assets/audio/sfx/ui/ui_hover.wav",
		"res://assets/audio/sfx/impacts/metal_light_0.ogg",
		"res://assets/audio/sfx/impacts/metal_heavy_0.ogg",
		"res://assets/audio/sfx/impacts/metal_crash_0.ogg",
	]:
		var stream: AudioStream = load(path) as AudioStream
		_expect(stream != null and stream.get_length() > 0.0, path + " loads")

	await _check_music()

	print("AUDIO TESTS: %s" % ("all passed" if _failures == 0 else "%d failure(s)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _check_music() -> void:
	print("[music]")
	var music: Node = Music
	_expect(music != null, "Music autoload exists")
	if music == null:
		return
	# Stop the autoload from switching tracks to match this test scene.
	music.set_process(false)

	var constants: Dictionary = music.get_script().get_script_constant_map()
	var level: float = float(constants.get("MUSIC_LEVEL_DB", 0.0))
	_expect(level < 0.0 and level > -20.0,
		"music sits below full volume (%.1f dB)" % level)

	for track in ["menu_loop", "sandbox_loop", "race_loop"]:
		var stream: AudioStream = music.call("_load_stream", track) as AudioStream
		_expect(stream != null and stream.get_length() > 5.0,
			track + " imports with real audio")
		_expect(stream != null and _is_looped(stream), track + " is looped")

	var expected: Dictionary = {
		"res://scenes/ui/main_menu.tscn": "menu_loop",
		"res://scenes/ui/settings_menu.tscn": "menu_loop",
		"res://scenes/minigames/grass_race.tscn": "race_loop",
		"res://scenes/minigames/meadow_lobby.tscn": "race_loop",
		"res://scenes/dev/driving_test.tscn": "sandbox_loop",
		"res://scenes/dev/something_else.tscn": "",
	}
	for path: String in expected:
		var got: String = str(music.call("track_for_path", path))
		_expect(got == str(expected[path]),
			"%s -> %s (got %s)" % [path.get_file(), str(expected[path]), got])

	# Playback: the active player must fade up to the music level, not 0 dB.
	music.call("play_track", "race_loop")
	# Headless frames run far faster than real time, so wait on the clock, not
	# on a frame count, for the 1.4 s crossfade to finish.
	await get_tree().create_timer(1.9).timeout
	var players: Array = music.get("_players")
	var active: int = int(music.get("_active"))
	var player: AudioStreamPlayer = players[active] as AudioStreamPlayer
	_expect(player.playing, "race_loop is playing")
	_expect(absf(player.volume_db - level) < 1.0,
		"race_loop faded to %.1f dB (got %.1f)" % [level, player.volume_db])
	_expect(_is_looped(player.stream), "playing stream is looped")
	music.call("stop_music", 0.05)
	for i in 10:
		await get_tree().process_frame
	_expect(not player.playing, "stop_music stops the player")


func _is_looped(stream: AudioStream) -> bool:
	if stream is AudioStreamWAV:
		return (stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED
	if stream is AudioStreamMP3:
		return (stream as AudioStreamMP3).loop
	return false


func _expect(value: bool, label: String) -> void:
	if value:
		print("  ok   ", label)
	else:
		_failures += 1
		printerr("  FAIL ", label)
