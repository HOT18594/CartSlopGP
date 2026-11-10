extends Node
## Persisted player settings shared by every menu scene.
## Volumes are 0-1 linear; they are converted to dB when applied.

signal changed
signal session_changed

const SETTINGS_PATH: String = "user://settings.cfg"
const SFX_BUS: String = "SFX"
const MUSIC_BUS: String = "Music"
## Driving actions whose InputMap deadzone follows the stick_deadzone setting.
const DRIVING_ACTIONS: Array[StringName] = [
	&"accelerate", &"brake", &"steer_left", &"steer_right",
	&"handbrake", &"boost", &"reset_cart",
]

const MODE_SINGLE: int = 0
const MODE_MULTIPLAYER: int = 1
const GAME_SANDBOX: String = "sandbox"
const GAME_MINIGAMES: String = "minigames"
const CONN_LAN: String = "lan"
const CONN_PI: String = "pi"
## Kept as an alias for older saved settings and scripts.
const CONN_ONLINE: String = CONN_PI

@export_range(0.0, 1.0, 0.01) var master_volume: float = 0.8
@export_range(0.0, 1.0, 0.01) var music_volume: float = 0.75
@export_range(0.0, 1.0, 0.01) var sfx_volume: float = 0.85
@export var fullscreen: bool = false
@export var custom_cursor: bool = true
## 0 = PERFORMANCE, 1 = BALANCED, 2 = QUALITY. The preset sets the maximum
## 3D render scale; dynamic resolution may lower it to hold 60 fps.
@export_range(0, 2) var quality_preset: int = 1
@export var dynamic_resolution: bool = true

const QUALITY_PERFORMANCE: int = 0
const QUALITY_BALANCED: int = 1
const QUALITY_QUALITY: int = 2
const QUALITY_NAMES: PackedStringArray = ["PERFORMANCE", "BALANCED", "QUALITY"]
const QUALITY_SCALES: PackedFloat32Array = [0.72, 0.92, 1.0]

@export_group("Camera & HUD")
@export_range(0.0, 1.5, 0.01) var camera_shake: float = 1.0 ## 0 = off, 1.5 = extra punchy.
@export var reduce_motion: bool = false ## Damps shake, camera roll and FOV kicks.
## Read by the HUD owner (`hud.gd`); this script only stores and exposes it.
@export_range(0.75, 1.5, 0.05) var hud_scale: float = 1.0

@export_group("Controls")
@export_range(0.0, 0.4, 0.01) var stick_deadzone: float = 0.12 ## Analogue stick deadzone for driving.
@export var boost_toggle: bool = false ## Press to latch boost instead of holding it.
@export var drift_toggle: bool = false ## Press to latch the handbrake instead of holding it.

@export_group("HUD")
@export var show_fps: bool = false ## Read by the HUD owner; off by default.

@export_group("Sandbox")
@export var selected_vehicle: String = "shopping_cart" ## Vehicle id from the catalog.
@export var player_name: String = "PLAYER" ## Name shown in multiplayer lobbies.
@export_range(0, 2) var minigame_difficulty: int = 1
@export_range(3, 7, 2) var minigame_rounds: int = 3
@export var minigame_vehicle: String = "shopping_cart"
@export var player_tag_color: String = "ffd22e" ## Name tag colour, RRGGBB hex.

@export_group("Session")
@export var play_mode: int = MODE_SINGLE ## MODE_SINGLE or MODE_MULTIPLAYER.
@export var multiplayer_mode: String = GAME_SANDBOX ## GAME_SANDBOX or GAME_MINIGAMES.
@export var connection_preference: String = CONN_PI ## CONN_LAN (this PC) or CONN_PI.
@export var relay_server: String = "" ## Optional relay address for internet joins.
@export var selected_minigame: String = "meadow_loop" ## Map chosen for the next race.
@export var bots_enabled: bool = false ## OFF by default - bots are strictly opt-in.
@export_range(0, 5) var bot_count: int = 3 ## How many AI carts to add when enabled.
## Online/LAN room discovery. Public rooms appear in the browser and can be
## joined with one click; private rooms are joinable only with the code.
@export var room_public: bool = true

## Set before opening the vehicle screen so its confirm/back returns to the
## right menu (lobby, minigame picker, etc.). Memory only.
var vehicle_return_scene: String = ""
var vehicle_return_title: String = "PLAY"
var vehicle_edit_minigame: bool = false
var _resolution_scale: float = 1.0
var _quality_timer: float = 0.0
var _quality_warmup: float = 5.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_sfx_bus()
	_ensure_music_bus()
	load_settings()
	apply_all()
	# InputSetup (the next autoload) writes its own deadzones in _ready, so the
	# saved deadzone is re-applied once every autoload has finished booting.
	call_deferred("apply_input_settings")
	# Music creates its players in its own _ready; route them once they exist.
	call_deferred("_route_music_players")
	call_deferred("apply_quality")


func _process(delta: float) -> void:
	## A small dynamic-resolution governor. It only lowers the 3D render scale
	## (UI stays native) and never exceeds the selected preset. It backs off
	## slowly so the image does not breathe between frames.
	if not dynamic_resolution or quality_preset == QUALITY_QUALITY:
		return
	if _quality_warmup > 0.0:
		_quality_warmup = maxf(_quality_warmup - delta, 0.0)
		return
	_quality_timer += delta
	if _quality_timer < 3.0:
		return
	_quality_timer = 0.0
	var fps: float = Engine.get_frames_per_second()
	var ceiling: float = preset_scale()
	if fps < 45.0 and _resolution_scale > 0.85:
		_resolution_scale = maxf(0.85, _resolution_scale - 0.02)
	elif fps > 58.5 and _resolution_scale < ceiling:
		_resolution_scale = minf(ceiling, _resolution_scale + 0.02)
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.scaling_3d_scale = _resolution_scale


func _ensure_sfx_bus() -> void:
	## The prototype only ships a Master bus; add SFX once at runtime.
	if AudioServer.get_bus_index(SFX_BUS) != -1:
		return
	AudioServer.add_bus()
	var index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, SFX_BUS)
	AudioServer.set_bus_send(index, "Master")


func _ensure_music_bus() -> void:
	## The Music autoload hard-codes the Master bus, so give it a dedicated bus
	## here and move its players onto it. This keeps the Music slider independent
	## from Master and SFX without touching music_player.gd.
	if AudioServer.get_bus_index(MUSIC_BUS) != -1:
		return
	AudioServer.add_bus()
	var index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, MUSIC_BUS)
	AudioServer.set_bus_send(index, "Master")


func _route_music_players() -> void:
	if AudioServer.get_bus_index(MUSIC_BUS) == -1:
		return
	var music: Node = get_node_or_null("/root/Music")
	if music == null:
		return
	for child: Node in music.get_children():
		if child is AudioStreamPlayer:
			(child as AudioStreamPlayer).bus = MUSIC_BUS


func apply_all() -> void:
	_apply_bus("Master", master_volume)
	_apply_bus(MUSIC_BUS, music_volume)
	_apply_bus(SFX_BUS, sfx_volume)
	apply_fullscreen()
	apply_quality()
	_apply_driving_deadzones()
	changed.emit()


func _apply_driving_deadzones() -> void:
	var zone: float = clampf(stick_deadzone, 0.0, 0.4)
	for action: StringName in DRIVING_ACTIONS:
		if InputMap.has_action(action):
			InputMap.action_set_deadzone(action, zone)


func apply_input_settings() -> void:
	## Re-applies the saved analogue deadzone to every driving action. Called at
	## boot after InputSetup and whenever the deadzone setting changes.
	_apply_driving_deadzones()
	changed.emit()


func _apply_bus(bus_name: String, value: float) -> void:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_mute(index, value <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.001)))


func apply_fullscreen() -> void:
	var mode: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen \
		else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)


func quality_name() -> String:
	return QUALITY_NAMES[clampi(quality_preset, 0, QUALITY_NAMES.size() - 1)]


func preset_scale() -> float:
	return QUALITY_SCALES[clampi(quality_preset, 0, QUALITY_SCALES.size() - 1)]


func apply_quality() -> void:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	_resolution_scale = preset_scale()
	viewport.scaling_3d_scale = _resolution_scale
	_quality_timer = 0.0
	_quality_warmup = 5.0


func set_quality_preset(value: int) -> void:
	quality_preset = clampi(value, 0, 2)
	dynamic_resolution = quality_preset != QUALITY_QUALITY
	apply_quality()
	save_settings()
	changed.emit()


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_bus("Master", master_volume)
	save_settings()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_bus(SFX_BUS, sfx_volume)
	save_settings()


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_bus(MUSIC_BUS, music_volume)
	save_settings()
	changed.emit()


func set_camera_shake(value: float) -> void:
	camera_shake = clampf(value, 0.0, 1.5)
	save_settings()
	changed.emit()


func set_reduce_motion(value: bool) -> void:
	reduce_motion = value
	save_settings()
	changed.emit()


func set_hud_scale(value: float) -> void:
	hud_scale = clampf(value, 0.75, 1.5)
	save_settings()
	changed.emit()


func set_stick_deadzone(value: float) -> void:
	stick_deadzone = clampf(value, 0.0, 0.4)
	save_settings()
	apply_input_settings()


func set_boost_toggle(value: bool) -> void:
	boost_toggle = value
	save_settings()
	changed.emit()


func set_drift_toggle(value: bool) -> void:
	drift_toggle = value
	save_settings()
	changed.emit()


func set_show_fps(value: bool) -> void:
	show_fps = value
	save_settings()
	changed.emit()


func reset_to_defaults() -> void:
	## Restores only the settings exposed on the settings screen. Vehicle,
	## player name, session config and minigame options are deliberately kept.
	master_volume = 0.8
	music_volume = 0.75
	sfx_volume = 0.85
	fullscreen = false
	custom_cursor = true
	quality_preset = QUALITY_BALANCED
	dynamic_resolution = true
	camera_shake = 1.0
	reduce_motion = false
	hud_scale = 1.0
	stick_deadzone = 0.12
	boost_toggle = false
	drift_toggle = false
	show_fps = false
	save_settings()
	apply_all()


func set_fullscreen(value: bool) -> void:
	fullscreen = value
	apply_fullscreen()
	save_settings()


func set_custom_cursor(value: bool) -> void:
	custom_cursor = value
	save_settings()
	changed.emit()


func set_player_name(raw_name: String) -> void:
	player_name = sanitize_name(raw_name)
	save_settings()


func set_player_tag_color(hex: String) -> void:
	## Accepts "RRGGBB" (or "#RRGGBB"); anything else keeps the old colour.
	var clean: String = hex.strip_edges().trim_prefix("#").to_lower()
	if not _valid_hex6(clean):
		return
	player_tag_color = clean
	save_settings()


func tag_color() -> Color:
	## The local player's tag colour as a Color; falls back to yellow.
	var color: Color = Color.from_string(player_tag_color, Color("ffd22e"))
	return color if color.a > 0.0 and player_tag_color.length() == 6 else Color("ffd22e")


func set_minigame_options(difficulty: int, rounds: int, vehicle_id: String) -> void:
	minigame_difficulty = clampi(difficulty, 0, 2)
	minigame_rounds = clampi(rounds, 3, 7)
	minigame_vehicle = vehicle_id
	save_settings()


# --------------------------------------------------------------------------
# session config (shared by single player and multiplayer)


func set_play_mode(mode: int) -> void:
	play_mode = MODE_MULTIPLAYER if mode == MODE_MULTIPLAYER else MODE_SINGLE
	save_settings()
	session_changed.emit()


func set_multiplayer_mode(mode: String) -> void:
	multiplayer_mode = GAME_MINIGAMES if mode == GAME_MINIGAMES else GAME_SANDBOX
	save_settings()
	session_changed.emit()


func set_connection_preference(mode: String) -> void:
	connection_preference = CONN_LAN if mode == CONN_LAN else CONN_PI
	save_settings()


func set_relay_server(raw: String) -> void:
	relay_server = raw.strip_edges()
	save_settings()


func set_selected_minigame(id: String) -> void:
	selected_minigame = id if id == "meadow_loop" else "meadow_loop"
	save_settings()


func minigame_name(id: String = "") -> String:
	var key: String = id if id != "" else selected_minigame
	match key:
		"meadow_loop":
			return "MEADOW LOOP"
		_:
			return "MEADOW LOOP"


func set_bots_enabled(enabled: bool) -> void:
	bots_enabled = enabled
	save_settings()
	session_changed.emit()


func set_bot_count(count: int) -> void:
	bot_count = clampi(count, 0, 5)
	save_settings()
	session_changed.emit()


func effective_bot_count() -> int:
	## The single number every scene should use. Zero when bots are off.
	return clampi(bot_count, 0, 5) if bots_enabled else 0


func set_ai_difficulty(value: int) -> void:
	minigame_difficulty = clampi(value, 0, 2)
	save_settings()
	changed.emit()


func ai_difficulty_name() -> String:
	return ["EASY", "NORMAL", "HARD"][clampi(minigame_difficulty, 0, 2)]


func set_bot_total(total: int) -> void:
	## One-click pill value: 0 = NO BOTS, 1..5 = that many AI carts.
	bot_count = clampi(total, 0, 5)
	bots_enabled = bot_count > 0
	save_settings()
	session_changed.emit()


func set_room_public(value: bool) -> void:
	room_public = value
	save_settings()
	session_changed.emit()


func set_session_config(mode: int, game: String, bots: bool, count: int) -> void:
	## Used by Network so every peer runs the host's exact configuration.
	play_mode = MODE_MULTIPLAYER if mode == MODE_MULTIPLAYER else MODE_SINGLE
	multiplayer_mode = GAME_MINIGAMES if game == GAME_MINIGAMES else GAME_SANDBOX
	bots_enabled = bots
	bot_count = clampi(count, 0, 5)
	session_changed.emit()


static func sanitize_name(raw_name: String) -> String:
	## Keep names short, printable and free of control characters. Also strips
	## zero-width and bidi-override code points, which can be used to make one
	## player look like another in the lobby list.
	var cleaned: String = ""
	for character in raw_name.strip_edges():
		var code: int = character.unicode_at(0)
		if code == 10 or code == 9 or code == 13:
			cleaned += " "
		elif code < 32:
			continue
		elif code >= 0x7F and code <= 0x9F:
			continue
		elif code >= 0x200B and code <= 0x200F:
			continue
		elif code == 0xFEFF or code == 0x180E or code == 0x2028 or code == 0x2029:
			# BOM / Mongolian vowel separator / line+paragraph separators can
			# hide a leading "[HOST]" or split a fixed-height player row.
			continue
		elif code >= 0x202A and code <= 0x202E:
			continue
		elif code >= 0x2066 and code <= 0x2069:
			continue
		else:
			cleaned += character
	cleaned = cleaned.strip_edges()
	# The [HOST] badge is drawn from the peer id; a name must never fake it.
	if cleaned.to_upper().begins_with("[HOST]"):
		cleaned = cleaned.substr(6).strip_edges()
	if cleaned.length() > 16:
		cleaned = cleaned.substr(0, 16).strip_edges()
	return cleaned if cleaned != "" else "PLAYER"


func set_selected_vehicle(vehicle_id: String) -> void:
	selected_vehicle = vehicle_id
	save_settings()


static func _cfg_num(config: ConfigFile, section: String, key: String,
		fallback: float, low: float, high: float) -> float:
	## Read a numeric setting without ever feeding a string/array/object to
	## float(). Missing keys, wrong types and NaN/Inf all fall back to the
	## current (default) value, then clamp into the exported range.
	var value: Variant = config.get_value(section, key, fallback)
	var kind: int = typeof(value)
	if kind != TYPE_FLOAT and kind != TYPE_INT:
		return clampf(fallback, low, high)
	var number: float = float(value)
	if not is_finite(number):
		return clampf(fallback, low, high)
	return clampf(number, low, high)


static func _cfg_int(config: ConfigFile, section: String, key: String,
		fallback: int, low: int, high: int) -> int:
	var value: Variant = config.get_value(section, key, fallback)
	var kind: int = typeof(value)
	if kind != TYPE_FLOAT and kind != TYPE_INT:
		return clampi(fallback, low, high)
	return clampi(int(value), low, high)


static func _cfg_bool(config: ConfigFile, section: String, key: String,
		fallback: bool) -> bool:
	## Older or hand-edited configs sometimes stored bools as strings. In
	## GDScript bool("false") is true, so parse the shapes we understand and
	## never let a corrupt value silently flip a setting.
	var value: Variant = config.get_value(section, key, fallback)
	var kind: int = typeof(value)
	if kind == TYPE_BOOL:
		return bool(value)
	if kind == TYPE_INT or kind == TYPE_FLOAT:
		return value != 0
	if kind == TYPE_STRING:
		var text: String = str(value).strip_edges().to_lower()
		return text == "true" or text == "1" or text == "yes" or text == "on"
	return fallback


static func _cfg_str(config: ConfigFile, section: String, key: String,
		fallback: String) -> String:
	var value: Variant = config.get_value(section, key, fallback)
	return str(value) if typeof(value) == TYPE_STRING else fallback


static func _valid_hex6(text: String) -> bool:
	if text.length() != 6:
		return false
	for character: String in text:
		if not "0123456789abcdef".contains(character):
			return false
	return true


func load_settings() -> void:
	## Defensive by design: a truncated, hand-edited or older settings.cfg must
	## never crash boot or put an out-of-range value into the live settings.
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	master_volume = _cfg_num(config, "audio", "master", master_volume, 0.0, 1.0)
	music_volume = _cfg_num(config, "audio", "music", music_volume, 0.0, 1.0)
	sfx_volume = _cfg_num(config, "audio", "sfx", sfx_volume, 0.0, 1.0)
	fullscreen = _cfg_bool(config, "video", "fullscreen", fullscreen)
	quality_preset = _cfg_int(config, "video", "quality", quality_preset, 0, 2)
	dynamic_resolution = _cfg_bool(config, "video", "dynamic_resolution", dynamic_resolution)
	camera_shake = _cfg_num(config, "video", "camera_shake", camera_shake, 0.0, 1.5)
	hud_scale = _cfg_num(config, "video", "hud_scale", hud_scale, 0.75, 1.5)
	reduce_motion = _cfg_bool(config, "video", "reduce_motion", reduce_motion)
	show_fps = _cfg_bool(config, "ui", "show_fps", show_fps)
	custom_cursor = _cfg_bool(config, "ui", "custom_cursor", custom_cursor)
	boost_toggle = _cfg_bool(config, "gameplay", "boost_toggle", boost_toggle)
	drift_toggle = _cfg_bool(config, "gameplay", "drift_toggle", drift_toggle)
	stick_deadzone = _cfg_num(config, "gameplay", "stick_deadzone", stick_deadzone, 0.0, 0.4)
	selected_vehicle = _cfg_str(config, "gameplay", "vehicle", selected_vehicle)
	player_name = sanitize_name(_cfg_str(config, "gameplay", "player_name", player_name))
	minigame_difficulty = _cfg_int(config, "gameplay", "minigame_difficulty", minigame_difficulty, 0, 2)
	minigame_rounds = _cfg_int(config, "gameplay", "minigame_rounds", minigame_rounds, 3, 7)
	minigame_vehicle = _cfg_str(config, "gameplay", "minigame_vehicle", minigame_vehicle)
	var tag: String = _cfg_str(config, "gameplay", "tag_color", player_tag_color)
	tag = tag.strip_edges().trim_prefix("#").to_lower()
	if _valid_hex6(tag):
		player_tag_color = tag
	play_mode = _cfg_int(config, "session", "play_mode", play_mode, MODE_SINGLE, MODE_MULTIPLAYER)
	if play_mode != MODE_SINGLE and play_mode != MODE_MULTIPLAYER:
		play_mode = MODE_SINGLE
	multiplayer_mode = _cfg_str(config, "session", "multiplayer_mode", multiplayer_mode)
	if multiplayer_mode != GAME_MINIGAMES and multiplayer_mode != GAME_SANDBOX:
		multiplayer_mode = GAME_SANDBOX
	connection_preference = _cfg_str(config, "session", "connection", connection_preference).to_lower()
	if connection_preference == "online":
		connection_preference = CONN_PI
	if connection_preference != CONN_LAN and connection_preference != CONN_PI:
		connection_preference = CONN_PI
	relay_server = _cfg_str(config, "session", "relay_server", relay_server).strip_edges()
	# Only Meadow Loop ever shipped; drop invented events from older builds.
	selected_minigame = "meadow_loop"
	bots_enabled = _cfg_bool(config, "session", "bots_enabled", bots_enabled)
	bot_count = _cfg_int(config, "session", "bot_count", bot_count, 0, 5)
	room_public = _cfg_bool(config, "session", "room_public", room_public)


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master", master_volume)
	config.set_value("audio", "music", music_volume)
	config.set_value("audio", "sfx", sfx_volume)
	config.set_value("video", "fullscreen", fullscreen)
	config.set_value("video", "quality", quality_preset)
	config.set_value("video", "dynamic_resolution", dynamic_resolution)
	config.set_value("video", "camera_shake", camera_shake)
	config.set_value("video", "hud_scale", hud_scale)
	config.set_value("video", "reduce_motion", reduce_motion)
	config.set_value("ui", "show_fps", show_fps)
	config.set_value("gameplay", "boost_toggle", boost_toggle)
	config.set_value("gameplay", "drift_toggle", drift_toggle)
	config.set_value("gameplay", "stick_deadzone", stick_deadzone)
	config.set_value("ui", "custom_cursor", custom_cursor)
	config.set_value("gameplay", "vehicle", selected_vehicle)
	config.set_value("gameplay", "player_name", player_name)
	config.set_value("gameplay", "minigame_difficulty", minigame_difficulty)
	config.set_value("gameplay", "minigame_rounds", minigame_rounds)
	config.set_value("gameplay", "minigame_vehicle", minigame_vehicle)
	config.set_value("gameplay", "tag_color", player_tag_color)
	config.set_value("session", "play_mode", play_mode)
	config.set_value("session", "multiplayer_mode", multiplayer_mode)
	config.set_value("session", "connection", connection_preference)
	config.set_value("session", "relay_server", relay_server)
	config.set_value("session", "selected_minigame", selected_minigame)
	config.set_value("session", "bots_enabled", bots_enabled)
	config.set_value("session", "bot_count", bot_count)
	config.set_value("session", "room_public", room_public)
	var error: Error = config.save(SETTINGS_PATH)
	if error != OK:
		# A read-only user:// (or a full disk) must not look like success.
		push_warning("GameSettings: could not write settings.cfg (%d)" % error)
