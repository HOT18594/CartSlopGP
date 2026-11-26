extends Node
## Background music manager with equal-power crossfades, seamless DJ-style
## self-loop blending, transitional warmth filtering, and pause muffling.
##
## Drop OGG Vorbis (or MP3/WAV) files into `res://assets/audio/music/` using
## the track names below. Missing tracks stay silent or fall back cleanly so
## builds work even if optional mode tracks are not yet installed.

const MUSIC_DIR: String = "res://assets/audio/music/"
const MENU_TRACK: String = "menu_loop"
const SANDBOX_TRACK: String = "sandbox_loop"
const RACE_TRACK: String = "race_loop"
const KNOCKOUT_TRACK: String = "knockout_loop"
const CARGO_TRACK: String = "cargo_loop"
const BOMB_TAG_TRACK: String = "bomb_tag_loop"

const POLL_INTERVAL: float = 0.15
const FADE_TIME: float = 2.0 ## Smooth equal-power crossfade between tracks.
const BOOT_FADE_IN: float = 1.4 ## Gentle initial bloom on startup.
const LOOP_BLEND_SEC: float = 4.0 ## Overlap crossfade when a song wraps around.
const MUSIC_LEVEL_DB: float = -6.5 ## Balanced headroom under SFX and engines.
const SILENT_DB: float = -72.0
## A three-deck pool: two decks for the audible crossfade, one spare so a track
## change that arrives mid-fade never has to hard-stop the outgoing stream. The
## spare deck is what removes the click when menus are clicked through quickly.
const DECK_COUNT: int = 3
## A pre-blended destination track holds while its scene loads. This is a safety
## cap only: the hold normally ends when the target scene becomes current.
const TRANSITION_LOCK_MAX: float = 12.0
## Retired decks (interrupted crossfades) fade out over this window so no
## stream is ever cut while it is still audible.
const RETIRE_FADE_SEC: float = 0.9

const FILTER_OPEN_HZ: float = 20500.0
const FILTER_TRANSITION_HZ: float = 4600.0
const FILTER_PAUSE_HZ: float = 1450.0
const PAUSE_DUCK_DB: float = -4.5

var current_track: String = ""

var _players: Array[AudioStreamPlayer] = []
var _active: int = 0
var _poll: float = 0.0

## Equal-power crossfade state driven smoothly in _process() so deck levels,
## self-loop wraps, and filter sweeps never fight or snap.
var _xfading: bool = false
var _xfade_elapsed: float = 0.0
var _xfade_duration: float = FADE_TIME
var _xfade_from: int = -1
var _xfade_to: int = -1
var _xfade_is_loop: bool = false
var _xfade_has_outgoing: bool = false
var _fading_out_only: bool = false
## Linear gain the outgoing deck had when this crossfade began (1.0 for a fresh
## swap). Re-entering a fade from a partly faded deck therefore starts from the
## current level instead of jumping back to full volume.
var _xfade_out_start_gain: float = 1.0
## Decks from an interrupted crossfade. Each keeps fading to silence on its own
## envelope instead of being stopped mid-note by the next `play_track()`.
var _retiring: Array[Dictionary] = []

## Remember menu playback offset so returning from races feels fresh rather
## than hearing the first 5 seconds of the menu theme every time.
var _saved_positions: Dictionary = {}

## Low-pass filter on the Music bus for buttery transitions & pause muffling.
var _lowpass: AudioEffectLowPassFilter
var _filter_hz: float = FILTER_OPEN_HZ
var _duck_db: float = 0.0
var _transition_target_track: String = ""
var _transition_target_scene: String = ""
var _transition_lock_timer: float = 0.0


func _enter_tree() -> void:
	_ensure_music_bus()
	_reroute_players()


func _ready() -> void:
	_ensure_music_bus()
	_ensure_music_filter()
	process_mode = Node.PROCESS_MODE_ALWAYS
	for _index in DECK_COUNT:
		var player := AudioStreamPlayer.new()
		player.bus = "Music"
		player.volume_db = SILENT_DB
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		_players.append(player)
	_reroute_players()


func _ensure_music_bus() -> void:
	if AudioServer.get_bus_index("Music") != -1:
		return
	AudioServer.add_bus()
	var index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, "Music")
	AudioServer.set_bus_send(index, "Master")


func _ensure_music_filter() -> void:
	var bus_idx: int = AudioServer.get_bus_index("Music")
	if bus_idx == -1:
		return
	for i in AudioServer.get_bus_effect_count(bus_idx):
		var fx: AudioEffect = AudioServer.get_bus_effect(bus_idx, i)
		if fx is AudioEffectLowPassFilter:
			_lowpass = fx as AudioEffectLowPassFilter
			return
	_lowpass = AudioEffectLowPassFilter.new()
	_lowpass.cutoff_hz = FILTER_OPEN_HZ
	_lowpass.resonance = 0.52
	_lowpass.db = AudioEffectFilter.FILTER_12DB
	AudioServer.add_bus_effect(bus_idx, _lowpass)


func _reroute_players() -> void:
	if AudioServer.get_bus_index("Music") == -1:
		return
	for player: AudioStreamPlayer in _players:
		if is_instance_valid(player):
			player.bus = "Music"


func _process(delta: float) -> void:
	var dt: float = minf(delta, 0.1)
	_update_transition_hold(dt)

	_update_crossfade(dt)
	_update_loop_blend()
	_update_bus_filter_and_duck(dt)

	_poll += dt
	if _poll < POLL_INTERVAL:
		return
	_poll = 0.0

	# While a scene transition is actively pre-blending the target scene's music,
	# let that transition hold instead of bouncing back to the outgoing scene.
	if _transition_lock_timer > 0.0 and _transition_target_track != "":
		return

	# change_scene_to_file() leaves current_scene null for a moment. That is a
	# transition, not a scene that wants silence.
	if get_tree().current_scene == null:
		return
	var wanted: String = _track_for_current_scene()
	if wanted != current_track:
		play_track(wanted)


func _current_scene_path() -> String:
	var tree: SceneTree = get_tree()
	if tree == null or tree.current_scene == null:
		return ""
	return tree.current_scene.scene_file_path


func _update_transition_hold(dt: float) -> void:
	## The hold normally ends the moment the destination scene becomes current,
	## so a long load can never outlive the lock and bounce back to the outgoing
	## screen's track. TRANSITION_LOCK_MAX is only a safety net for a load that
	## fails outright.
	if _transition_target_scene != "" \
			and _current_scene_path() == _transition_target_scene:
		_transition_target_scene = ""
		_transition_target_track = ""
		_transition_lock_timer = 0.0
		return
	if _transition_lock_timer > 0.0:
		_transition_lock_timer = maxf(_transition_lock_timer - dt, 0.0)
		if _transition_lock_timer <= 0.0:
			_transition_target_track = ""
			_transition_target_scene = ""


func _track_for_current_scene() -> String:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return ""
	return track_for_path(scene.scene_file_path)


## Pure scene-path mapping, kept separate so tests can check every screen.
func track_for_path(path: String) -> String:
	if path.ends_with("sandbox.tscn"):
		return SANDBOX_TRACK
	if path.ends_with("knockout.tscn"):
		return KNOCKOUT_TRACK if _track_exists(KNOCKOUT_TRACK) else RACE_TRACK
	if path.ends_with("cargo_rush.tscn"):
		return CARGO_TRACK if _track_exists(CARGO_TRACK) else RACE_TRACK
	if path.ends_with("bomb_tag.tscn"):
		return BOMB_TAG_TRACK if _track_exists(BOMB_TAG_TRACK) else RACE_TRACK
	if path.ends_with("grass_race.tscn") or path.ends_with("meadow_lobby.tscn"):
		return RACE_TRACK
	if path.contains("/ui/"):
		return MENU_TRACK
	return ""


## Called by SceneLoader right as a transition begins so the next mode's track
## starts blending during the loading screen and blooms in as the world appears.
func transition_to_scene(scene_path: String) -> void:
	var wanted: String = track_for_path(scene_path)
	if wanted == "" or wanted == current_track:
		return
	_transition_target_track = wanted
	_transition_target_scene = scene_path
	_transition_lock_timer = TRANSITION_LOCK_MAX
	play_track(wanted, FADE_TIME + 0.4)


func _track_exists(track_name: String) -> bool:
	for ext: String in [".ogg", ".mp3", ".wav"]:
		if ResourceLoader.exists(MUSIC_DIR + track_name + ext):
			return true
	return false


func play_menu() -> void:
	play_track(MENU_TRACK)


func play_sandbox() -> void:
	play_track(SANDBOX_TRACK)


func stop_music(fade: float = FADE_TIME) -> void:
	_remember_active_position()
	current_track = ""
	if _players.is_empty():
		return
	var active_player: AudioStreamPlayer = _players[_active]
	if not active_player.playing:
		return
	# A crossfade already in flight has a second audible deck: retire it on its
	# own envelope so this stop can never cut it mid-note.
	if _xfading and _xfade_from != -1 and _xfade_from != _active:
		_retire_deck(_xfade_from)
	_xfading = true
	_fading_out_only = true
	_xfade_is_loop = false
	_xfade_elapsed = 0.0
	_xfade_duration = maxf(fade, 0.08)
	_xfade_from = _active
	_xfade_to = -1
	_xfade_has_outgoing = true
	_xfade_out_start_gain = _current_deck_gain(_active)


func play_track(track_name: String, fade: float = FADE_TIME) -> void:
	if track_name == current_track:
		return
	_remember_active_position()
	var prev_track: String = current_track
	current_track = track_name
	if _players.size() < 2:
		return

	var old_index: int = _active
	var old: AudioStreamPlayer = _players[old_index]
	if track_name == "":
		stop_music(fade)
		return

	var stream: AudioStream = _load_stream(track_name)
	if stream == null:
		stop_music(fade)
		return

	# An interrupted crossfade leaves the previous outgoing deck playing. Let it
	# finish fading on a spare deck instead of stopping it mid-note, then pick a
	# free deck for the new track.
	if _xfading and _xfade_from != -1 and _xfade_from != old_index:
		_retire_deck(_xfade_from)
	var next_index: int = _free_deck(old_index)
	var next: AudioStreamPlayer = _players[next_index]
	next.stop()
	next.stream = stream
	next.volume_db = SILENT_DB

	# Resume menu track smoothly from where we left off so returning to menus
	# feels continuous and never replays the opening bars endlessly.
	var start_pos: float = 0.0
	if track_name == MENU_TRACK and _saved_positions.has(MENU_TRACK):
		var saved: float = float(_saved_positions[MENU_TRACK])
		var length: float = _stream_length(stream)
		if length > LOOP_BLEND_SEC * 2.5 and saved > 1.0 and saved < length - LOOP_BLEND_SEC - 4.0:
			start_pos = saved

	next.play(start_pos)
	_active = next_index

	var had_outgoing: bool = old.playing and prev_track != "" and old_index != next_index
	var dur: float = fade if had_outgoing else minf(fade, BOOT_FADE_IN)
	_xfading = true
	_fading_out_only = false
	_xfade_is_loop = false
	_xfade_elapsed = 0.0
	_xfade_duration = maxf(dur, 0.08)
	_xfade_from = old_index if had_outgoing else -1
	_xfade_to = next_index
	_xfade_has_outgoing = had_outgoing
	_xfade_out_start_gain = _current_deck_gain(old_index) if had_outgoing else 0.0


func _current_deck_gain(index: int) -> float:
	## Linear gain of a deck relative to the current music level, clamped to
	## 0..1 so re-entering a fade from a partly faded stream starts where it is.
	if index < 0 or index >= _players.size():
		return 0.0
	var peak_db: float = MUSIC_LEVEL_DB + _duck_db
	var gain: float = db_to_linear(_players[index].volume_db - peak_db)
	return clampf(gain, 0.0, 1.0)


func _free_deck(avoid: int) -> int:
	## First deck that is neither the outgoing deck, the audible target, a
	## mid-fade deck nor a retiring deck. With DECK_COUNT = 3 that is normally
	## the spare, which is why fast menu clicks never hard-stop a stream.
	var busy: Dictionary = {}
	busy[avoid] = true
	if _xfading:
		if _xfade_from != -1:
			busy[_xfade_from] = true
		if _xfade_to != -1:
			busy[_xfade_to] = true
	for item: Dictionary in _retiring:
		busy[int(item.get("player", -1))] = true
	for index in _players.size():
		if not busy.has(index):
			return index
	# Rapid track spam can occupy every deck. Reuse the quietest one: it is the
	# least audible cut possible, and it is already near silence.
	var quietest: int = -1
	var quietest_db: float = INF
	for index in _players.size():
		if index == avoid:
			continue
		var level: float = _players[index].volume_db
		if level < quietest_db:
			quietest_db = level
			quietest = index
	if quietest == -1:
		quietest = (avoid + 1) % _players.size()
	for item_index in range(_retiring.size() - 1, -1, -1):
		if int(_retiring[item_index].get("player", -1)) == quietest:
			_retiring.remove_at(item_index)
	_players[quietest].stop()
	_players[quietest].volume_db = SILENT_DB
	return quietest


func _retire_deck(index: int) -> void:
	## Hands one deck to the retiring list: it fades to silence over
	## RETIRE_FADE_SEC and is then stopped, so no stream is ever cut while
	## audible.
	if index < 0 or index >= _players.size():
		return
	for item: Dictionary in _retiring:
		if int(item.get("player", -1)) == index:
			return
	var player: AudioStreamPlayer = _players[index]
	if not player.playing:
		player.volume_db = SILENT_DB
		return
	_retiring.append({
		"player": index,
		"start_db": player.volume_db,
		"elapsed": 0.0,
		"duration": RETIRE_FADE_SEC,
	})


func _update_retiring(dt: float) -> void:
	for index in range(_retiring.size() - 1, -1, -1):
		var item: Dictionary = _retiring[index]
		var player_index: int = int(item.get("player", -1))
		if player_index < 0 or player_index >= _players.size():
			_retiring.remove_at(index)
			continue
		var player: AudioStreamPlayer = _players[player_index]
		var duration: float = maxf(float(item.get("duration", RETIRE_FADE_SEC)), 0.05)
		item["elapsed"] = float(item.get("elapsed", 0.0)) + dt
		var t: float = clampf(float(item["elapsed"]) / duration, 0.0, 1.0)
		var smooth: float = t * t * (3.0 - 2.0 * t)
		var start_db: float = float(item.get("start_db", SILENT_DB))
		if is_instance_valid(player) and player.playing:
			player.volume_db = lerpf(start_db, SILENT_DB, smooth)
		if not is_instance_valid(player) or not player.playing or t >= 1.0:
			if is_instance_valid(player):
				player.stop()
				player.volume_db = SILENT_DB
			_retiring.remove_at(index)


func _trigger_self_loop_blend() -> void:
	if _players.size() < 2 or current_track == "":
		return
	var old_index: int = _active
	var old: AudioStreamPlayer = _players[old_index]
	if old.stream == null or not old.playing:
		return

	var next_index: int = _free_deck(old_index)
	var next: AudioStreamPlayer = _players[next_index]
	next.stop()
	next.stream = old.stream
	next.volume_db = SILENT_DB
	next.play(0.0)
	_active = next_index

	_xfading = true
	_fading_out_only = false
	_xfade_is_loop = true
	_xfade_elapsed = 0.0
	_xfade_duration = LOOP_BLEND_SEC
	_xfade_from = old_index
	_xfade_to = next_index
	_xfade_has_outgoing = true
	_xfade_out_start_gain = 1.0


func _update_crossfade(dt: float) -> void:
	if _players.size() < 2:
		return
	# Retired decks keep fading even when no primary crossfade is running.
	_update_retiring(dt)
	var target_db: float = MUSIC_LEVEL_DB + _duck_db
	if not _xfading:
		var active_p: AudioStreamPlayer = _players[_active]
		if active_p.playing:
			active_p.volume_db = target_db
		return

	_xfade_elapsed += dt
	var t: float = clampf(_xfade_elapsed / _xfade_duration, 0.0, 1.0)
	# Smoothstep S-curve into equal-power sin/cos gains for velvety loudness continuity.
	var s: float = t * t * (3.0 - 2.0 * t)
	var angle: float = s * (PI * 0.5)
	var out_gain: float = cos(angle)
	var in_gain: float = sin(angle)

	if _xfade_from != -1:
		var out_p: AudioStreamPlayer = _players[_xfade_from]
		if out_p.playing:
			# Start from the gain the outgoing deck actually had: a fade that was
			# interrupted mid-way must not jump back to full volume.
			var shaped: float = clampf(_xfade_out_start_gain * out_gain, 0.0, 1.0)
			out_p.volume_db = _gain_to_db(shaped, target_db)

	if not _fading_out_only and _xfade_to != -1:
		var in_p: AudioStreamPlayer = _players[_xfade_to]
		if in_p.playing:
			in_p.volume_db = _gain_to_db(in_gain, target_db)

	if t >= 1.0:
		if _xfade_from != -1 and _xfade_from != _active:
			_players[_xfade_from].stop()
			_players[_xfade_from].volume_db = SILENT_DB
		if _fading_out_only and _xfade_from != -1:
			_players[_xfade_from].stop()
			_players[_xfade_from].volume_db = SILENT_DB
		elif _xfade_to != -1:
			_players[_xfade_to].volume_db = target_db
		_xfading = false
		_fading_out_only = false
		_xfade_is_loop = false
		_xfade_from = -1
		_xfade_to = -1
		_xfade_out_start_gain = 0.0


func _update_loop_blend() -> void:
	if _xfading or _players.size() < 2 or current_track == "":
		return
	var active_p: AudioStreamPlayer = _players[_active]
	if not active_p.playing or active_p.stream == null:
		return
	var length: float = _stream_length(active_p.stream)
	if length <= LOOP_BLEND_SEC * 2.5:
		return
	var pos: float = active_p.get_playback_position()
	if pos >= length - LOOP_BLEND_SEC:
		_trigger_self_loop_blend()


func _update_bus_filter_and_duck(dt: float) -> void:
	var paused: bool = get_tree().paused
	var target_hz: float = FILTER_OPEN_HZ
	var target_duck: float = 0.0

	if paused:
		target_hz = FILTER_PAUSE_HZ
		target_duck = PAUSE_DUCK_DB
	elif _xfading and not _xfade_is_loop and _xfade_has_outgoing:
		# Gentle warm low-pass dip across the midpoint of a track swap so two
		# different keys/tempos melt together without jarring high-end clash.
		var t: float = clampf(_xfade_elapsed / _xfade_duration, 0.0, 1.0)
		var dip: float = sin(t * PI) # 0 -> 1 at midpoint -> 0 at end
		target_hz = lerpf(FILTER_OPEN_HZ, FILTER_TRANSITION_HZ, dip * 0.85)

	var hz_rate: float = 1.0 - exp(-dt * (7.0 if paused else 4.5))
	var duck_rate: float = 1.0 - exp(-dt * 6.5)
	_filter_hz = lerpf(_filter_hz, target_hz, hz_rate)
	_duck_db = lerpf(_duck_db, target_duck, duck_rate)

	if _lowpass != null:
		_lowpass.cutoff_hz = clampf(_filter_hz, 400.0, FILTER_OPEN_HZ)


func _gain_to_db(gain: float, peak_db: float) -> float:
	if gain <= 0.0003:
		return SILENT_DB
	return maxf(SILENT_DB, peak_db + linear_to_db(gain))


func _remember_active_position() -> void:
	if current_track == "" or _players.is_empty():
		return
	var p: AudioStreamPlayer = _players[_active]
	if is_instance_valid(p) and p.playing:
		_saved_positions[current_track] = p.get_playback_position()


func _stream_length(stream: AudioStream) -> float:
	if stream == null:
		return 0.0
	return stream.get_length()


func _load_stream(track_name: String) -> AudioStream:
	# Prefer OGG Vorbis (clean streaming & small footprint), also accept MP3/WAV.
	for ext: String in [".ogg", ".mp3", ".wav"]:
		var path: String = MUSIC_DIR + track_name + ext
		if not ResourceLoader.exists(path):
			continue
		var stream: AudioStream = load(path) as AudioStream
		if stream == null:
			continue
		# Long songs use our smooth DJ-style overlap crossfade instead of a hard
		# jump back to 0:00; short loops still enable native stream looping.
		var use_native_loop: bool = _stream_length(stream) <= LOOP_BLEND_SEC * 2.5
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = use_native_loop
		elif stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = use_native_loop
		elif stream is AudioStreamWAV:
			(stream as AudioStreamWAV).loop_mode = (
				AudioStreamWAV.LOOP_FORWARD if use_native_loop
				else AudioStreamWAV.LOOP_DISABLED
			)
		return stream
	return null
