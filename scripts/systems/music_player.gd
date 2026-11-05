extends Node
## Optional background music with crossfades.
##
## Drop MP3s into `res://assets/audio/music/` using the names documented in
## that folder's README. If a track is missing the game stays silent instead of
## erroring, so builds work before the music is added.

const MUSIC_DIR: String = "res://assets/audio/music/"
const MENU_TRACK: String = "menu_loop"
const SANDBOX_TRACK: String = "sandbox_loop"
const RACE_TRACK: String = "race_loop"
const POLL_INTERVAL: float = 0.5
const FADE_TIME: float = 1.4

var current_track: String = ""

var _players: Array[AudioStreamPlayer] = []
var _active: int = 0
var _tween: Tween
var _poll: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for _index in 2:
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		player.volume_db = -60.0
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		_players.append(player)


func _process(delta: float) -> void:
	_poll += delta
	if _poll < POLL_INTERVAL:
		return
	_poll = 0.0
	var wanted: String = _track_for_current_scene()
	if wanted != current_track:
		play_track(wanted)


func _track_for_current_scene() -> String:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return ""
	var path: String = scene.scene_file_path
	if path.ends_with("driving_test.tscn"):
		return SANDBOX_TRACK
	if path.ends_with("grass_race.tscn") or path.ends_with("meadow_lobby.tscn"):
		return RACE_TRACK
	if path.contains("/ui/"):
		return MENU_TRACK
	return ""


func play_menu() -> void:
	play_track(MENU_TRACK)


func play_sandbox() -> void:
	play_track(SANDBOX_TRACK)


func stop_music(fade: float = FADE_TIME) -> void:
	current_track = ""
	_fade_out(_players[_active], fade)


func play_track(track_name: String, fade: float = FADE_TIME) -> void:
	if track_name == current_track:
		return
	current_track = track_name

	if _tween != null and _tween.is_valid():
		_tween.kill()

	var old: AudioStreamPlayer = _players[_active]
	if track_name == "":
		_fade_out(old, fade)
		return

	var stream: AudioStream = _load_stream(track_name)
	if stream == null:
		# No MP3 yet: fade out rather than blasting the previous context's music.
		_fade_out(old, fade)
		return

	var next_index: int = 1 - _active
	var next: AudioStreamPlayer = _players[next_index]
	next.stop()
	next.stream = stream
	next.volume_db = -60.0
	next.play()
	_active = next_index

	_tween = create_tween().set_parallel(true)
	if old.playing:
		_tween.tween_property(old, "volume_db", -60.0, fade)
	_tween.tween_property(next, "volume_db", 0.0, fade)
	_tween.chain().tween_callback(old.stop)


func _load_stream(track_name: String) -> AudioStream:
	var path: String = MUSIC_DIR + track_name + ".mp3"
	if not ResourceLoader.exists(path):
		return null
	var stream: AudioStream = load(path) as AudioStream
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	return stream


func _fade_out(player: AudioStreamPlayer, fade: float) -> void:
	if not player.playing:
		return
	_tween = create_tween()
	_tween.tween_property(player, "volume_db", -60.0, fade)
	_tween.tween_callback(player.stop)
