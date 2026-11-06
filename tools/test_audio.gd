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

	print("AUDIO TESTS: %s" % ("all passed" if _failures == 0 else "%d failure(s)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


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
