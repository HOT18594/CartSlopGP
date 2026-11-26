extends SceneTree
## Headless audio-graph probe for the music manager (WS3 audio polish).
##
## The music layer is presentation-only, so the regular suites never touch it.
## This probe drives the real `Music` autoload through every handoff the game
## performs and asserts the properties the polish work is supposed to guarantee:
##
##   1. BOOT        one track fades in from silence and settles at the level.
##   2. SPARE DECK  a track change that lands mid-crossfade keeps every audible
##                  deck playing (no hard stop) thanks to the third deck.
##   3. SETTLE      after the crossfade only the new track is audible and every
##                  retired deck is silent and stopped.
##   4. STOP        `stop_music()` fades to silence instead of cutting.
##   5. PAUSE       the tree pause muffle ducks the Music bus and sweeps the
##                  low-pass down, then recovers smoothly on unpause.
##   6. TRANSITION  `transition_to_scene()` holds the destination track while the
##                  scene loads (a long load cannot bounce back to the old
##                  screen's track) and releases the hold when the scene lands.
##
## Run with:
##   Godot_v4.7.2-stable_win64_console.exe --headless --path godot_project \
##       --script res://scripts/effects/audio_fade_probe.gd
##
## Exit code = number of failed assertions.

const MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"
const RACE_SCENE: String = "res://scenes/minigames/grass_race.tscn"
const MUSIC_LEVEL_DB: float = -6.5
const SILENT_DB: float = -72.0
const FADE_SETTLE: float = 1.6

var _failures: int = 0
var _music: Node


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	print("AUDIO_FAIL %s" % message)


func _run() -> void:
	await process_frame
	await process_frame
	_music = root.get_node_or_null("Music")
	if _music == null:
		print("AUDIO FAIL: Music autoload missing")
		quit(1)
		return
	print("AUDIO: %s" % str(_music.call("track_for_path", MENU_SCENE)))
	await _test_boot()
	await _test_interrupted_crossfade()
	await _test_stop_fade()
	await _test_pause_muffle()
	await _test_scene_transition()
	print("AUDIO: %d failure(s)" % _failures)
	print("AUDIO: %s" % ("PASS" if _failures == 0 else "FAIL"))
	quit(0 if _failures == 0 else _failures)


# --------------------------------------------------------------------------
# 1. boot fade-in
# --------------------------------------------------------------------------


func _test_boot() -> void:
	_music.call("play_track", "menu_loop", 0.6)
	await create_timer(0.12).timeout
	var decks: Array = _music.get("_players")
	_check(decks.size() == 3, "deck pool is %d, expected 3" % decks.size())
	var active: int = int(_music.get("_active"))
	var player: AudioStreamPlayer = decks[active] as AudioStreamPlayer
	_check(player.playing, "boot: the new track is not playing")
	var early_db: float = player.volume_db
	_check(early_db < MUSIC_LEVEL_DB + 3.0,
		"boot: first frame jumps to %.1f dB (no fade-in)" % early_db)
	await create_timer(FADE_SETTLE).timeout
	var settled_db: float = player.volume_db
	_check(absf(settled_db - MUSIC_LEVEL_DB) < 1.5,
		"boot: settled at %.1f dB, expected %.1f" % [settled_db, MUSIC_LEVEL_DB])
	_check(_playing_decks() == 1,
		"boot: %d decks audible after the fade (expected 1)" % _playing_decks())
	print("AUDIO_BOOT: faded %.1f -> %.1f dB" % [early_db, settled_db])


# --------------------------------------------------------------------------
# 2./3. interrupted crossfade + settle
# --------------------------------------------------------------------------


func _test_interrupted_crossfade() -> void:
	# Start a slow crossfade, interrupt it halfway, then interrupt it again.
	_music.call("play_track", "race_loop", 1.6)
	await create_timer(0.25).timeout
	_music.call("play_track", "cargo_loop", 1.6)
	await create_timer(0.20).timeout
	_music.call("play_track", "knockout_loop", 1.6)
	await create_timer(0.10).timeout
	# The outgoing decks must still be audible at this instant: a two-deck
	# implementation hard-stopped one of them here (the click this probe guards).
	var audible_now: int = _playing_decks()
	_check(audible_now >= 2,
		"interrupt: only %d deck(s) playing after two mid-fade track changes"
		% audible_now)
	var retiring: Array = _music.get("_retiring")
	_check(retiring.size() >= 1,
		"interrupt: no deck was retired for a graceful fade-out")
	print("AUDIO_INTERRUPT: %d decks audible, %d retiring" % [audible_now, retiring.size()])
	await create_timer(3.2).timeout
	_check(_playing_decks() == 1,
		"settle: %d decks audible after the crossfades" % _playing_decks())
	var leftover: Array = _music.get("_retiring")
	_check(leftover.is_empty(), "settle: retiring list did not drain")
	var decks: Array = _music.get("_players")
	var active: int = int(_music.get("_active"))
	for index in decks.size():
		var player: AudioStreamPlayer = decks[index] as AudioStreamPlayer
		if index == active:
			continue
		_check(not player.playing or player.volume_db <= SILENT_DB + 1.0,
			"settle: idle deck %d is audible at %.1f dB" % [index, player.volume_db])


# --------------------------------------------------------------------------
# 4. stop fade
# --------------------------------------------------------------------------


func _test_stop_fade() -> void:
	_music.call("play_track", "sandbox_loop", 0.8)
	await create_timer(0.4).timeout
	_music.call("stop_music", 0.5)
	await create_timer(0.15).timeout
	_check(_playing_decks() >= 1, "stop: music hard-stopped instead of fading")
	# The crossfade that was in flight when stop_music() ran retires its other
	# deck over RETIRE_FADE_SEC, so allow the longest envelope to finish.
	await create_timer(1.5).timeout
	_check(_playing_decks() == 0, "stop: %d deck(s) still playing after the fade"
		% _playing_decks())
	print("AUDIO_STOP: faded to silence")


# --------------------------------------------------------------------------
# 5. pause muffle
# --------------------------------------------------------------------------


func _test_pause_muffle() -> void:
	_music.call("play_track", "menu_loop", 0.5)
	await create_timer(0.7).timeout
	paused = true
	await create_timer(0.6).timeout
	var duck: float = float(_music.get("_duck_db"))
	var lowpass: AudioEffectLowPassFilter = _music.get("_lowpass") as AudioEffectLowPassFilter
	var cutoff: float = lowpass.cutoff_hz if lowpass != null else 0.0
	_check(duck < -1.0, "pause: music was not ducked (%.2f dB)" % duck)
	_check(cutoff < 4000.0, "pause: low-pass did not sweep down (%.0f Hz)" % cutoff)
	print("AUDIO_PAUSE: duck %.2f dB, low-pass %.0f Hz" % [duck, cutoff])
	paused = false
	await create_timer(0.9).timeout
	duck = float(_music.get("_duck_db"))
	_check(absf(duck) < 1.0, "unpause: duck did not recover (%.2f dB)" % duck)


# --------------------------------------------------------------------------
# 6. scene transition hold
# --------------------------------------------------------------------------


func _test_scene_transition() -> void:
	var menu: Node = _instantiate_scene(MENU_SCENE)
	if menu == null:
		_check(false, "transition: could not instantiate the menu scene")
		return
	root.add_child(menu)
	current_scene = menu
	await process_frame
	await process_frame
	_music.call("play_track", "menu_loop", 0.4)
	await create_timer(0.9).timeout
	_music.call("transition_to_scene", RACE_SCENE)
	await create_timer(0.4).timeout
	_check(str(_music.get("_transition_target_track")) == "race_loop",
		"transition: destination track hold was dropped early")
	var race: Node = _instantiate_scene(RACE_SCENE)
	if race == null:
		_check(false, "transition: could not instantiate the race scene")
		menu.queue_free()
		return
	current_scene = null
	menu.queue_free()
	root.add_child(race)
	current_scene = race
	await process_frame
	await process_frame
	await create_timer(0.3).timeout
	_check(str(_music.get("_transition_target_track")) == "",
		"transition: hold did not release when the scene landed")
	_check(str(_music.get("current_track")) == "race_loop",
		"transition: current track is '%s', expected race_loop"
		% str(_music.get("current_track")))
	# `transition_to_scene()` pre-blends during the load, so the crossfade is
	# still completing when the scene appears; wait it out before demanding one
	# audible deck.
	await create_timer(2.8).timeout
	_check(_playing_decks() == 1,
		"transition: %d decks playing after the crossfade" % _playing_decks())
	print("AUDIO_TRANSITION: %s, %d deck(s)" % [
		str(_music.get("current_track")), _playing_decks()])


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------


func _instantiate_scene(path: String) -> Node:
	if not ResourceLoader.exists(path):
		return null
	var packed: PackedScene = load(path) as PackedScene
	return packed.instantiate() if packed != null else null


func _playing_decks() -> int:
	var decks: Array = _music.get("_players")
	var playing: int = 0
	for raw: Variant in decks:
		var player: AudioStreamPlayer = raw as AudioStreamPlayer
		if player != null and player.playing and player.volume_db > SILENT_DB + 1.0:
			playing += 1
	return playing
