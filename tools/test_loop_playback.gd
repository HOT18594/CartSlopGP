extends Node

func _ready() -> void:
	var stream: AudioStream = load("res://assets/audio/sfx/engine/engine_loop.wav")
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = maxi(int(wav.get_length() * wav.mix_rate), 1)
	var player := AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	player.play()
	for i in 180:
		await get_tree().process_frame
	print("LOOP_PLAYBACK playing=%s pos=%.2f len=%.2f" % [
		player.playing, player.get_playback_position(), stream.get_length()])
	var ok: bool = player.playing and player.get_playback_position() > 0.5
	print("LOOP_PLAYBACK: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
