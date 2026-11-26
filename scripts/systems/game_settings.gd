extends Node
## Persisted player settings shared by every menu scene.
## Volumes are 0-1 linear; they are converted to dB when applied.

signal changed
signal session_changed

const SETTINGS_PATH: String = "user://settings.cfg"
## Staging file for the atomic save (WS5-06). ConfigFile.save() truncates its
## target in place, so a crash or power loss inside a write could leave a
## partial settings.cfg and lose every setting. The real save is written here
## first and renamed over SETTINGS_PATH in one directory entry operation.
const SETTINGS_TMP_PATH: String = "user://settings.cfg.tmp"
## A damaged save is copied here before the defaults are written back. The player
## keeps a recoverable copy of the old file instead of losing it to the next
## save, and support can inspect what was actually on disk.
const CORRUPT_BACKUP_PATH: String = "user://settings.corrupt.cfg"
## A save is a synchronous file write and a slider drag fires value_changed
## dozens of times per second, so continuous changes are coalesced into one
## write. Discrete choices still save immediately.
const SAVE_DEBOUNCE_SECONDS: float = 0.4
const SFX_BUS: String = "SFX"
const MUSIC_BUS: String = "Music"
## Saved-schema marker. A save without it was written before versioning and
## gets the one-time vehicle migration in load_settings(); the marker is then
## written immediately, so the migration can never run twice. A choice saved
## after that (including a deliberate racing chassis) is honoured as-is.
##   1 = the layout before the shopping cart became the default everywhere.
##   2 = every vehicle slot resolved to the stock cart once; marker persisted.
const SETTINGS_VERSION: int = 2
## Read the marker defensively: a hand-edited or future value must never look
## like an old save or crash the loader.
const SETTINGS_VERSION_MAX: int = 1_000_000
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
const TrackDefs := preload("res://scripts/minigames/track_defs.gd")
const VehicleCatalog := preload("res://scripts/vehicles/vehicle_catalog.gd")

## The scene whose rules make the racing class active. Kept as a constant so
## any future racing scene only needs the list extended, not the checks copied.
const RACING_SCENES: PackedStringArray = [
	"res://scenes/minigames/grass_race.tscn",
]
## Hand-built events that are not races. Even in a MINIGAMES session they keep
## the sandbox roster, so the minigame_vehicle getter must not hand them a race
## car just because the session mode is GAME_MINIGAMES.
const NON_RACING_SCENES: PackedStringArray = [
	"res://scenes/minigames/cargo_rush.tscn",
	"res://scenes/minigames/knockout.tscn",
	"res://scenes/minigames/bomb_tag.tscn",
	"res://scenes/minigames/meadow_lobby.tscn",
]

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

@export_group("Comfort")
## Pause a SOLO game when the window loses focus (Alt-Tab, browser tab blur).
## Multiplayer never auto-pauses: there the world keeps running for everyone
## else, so the pause menu only locks local input instead. Read by the shared
## pause menu (WS5-04); on by default because losing a race to an Alt-Tab is
## worse than one extra key press.
@export var pause_on_focus_loss: bool = true

@export_group("Sandbox")
## Vehicle id from the catalog. The stock shopping cart is the default for
## every channel; a saved id is honoured only while it still names a vehicle.
@export var selected_vehicle: String = VehicleCatalog.DEFAULT_ID
@export var player_name: String = "PLAYER" ## Name shown in multiplayer lobbies.
@export_range(0, 2) var minigame_difficulty: int = 1
@export_range(3, 7, 2) var minigame_rounds: int = 3
## Racing-class build. Kept apart from the sandbox and minigame cars so picking
## a race car never changes what SANDBOX or CARGO RUSH spawns. The stock shopping
## cart is the default pick; the four Kenney chassis remain selectable.
var racing_vehicle: String = VehicleCatalog.DEFAULT_RACING_ID
var racing_build: Dictionary = {} ## Four allocation keys; empty = balanced default.
@export var racer_color: String = "e63946" ## Custom PRO RACER paint hex (RRGGBB).


func racer_color_value() -> Color:
	return Color.from_string(racer_color, Color("e63946"))


func set_racer_color(hex: String) -> void:
	var clean: String = hex.strip_edges().trim_prefix("#").to_lower()
	if clean.length() == 6 and clean.is_valid_hex_number(false):
		racer_color = clean
		save_settings()
		changed.emit()
## Backing store for the exported minigame car. The property below resolves to
## the racing pick only while a racing scene or racing garage is active, which
## is how grass_race.gd reuses its existing `minigame_vehicle` read without a
## second vehicle channel, while cargo_rush.gd keeps seeing the normal car.
var _minigame_vehicle: String = VehicleCatalog.DEFAULT_ID
## grass_race.gd temporarily writes the racing pick into selected_vehicle while
## it runs. A settings save from the pause menu must still persist the SANDBOX
## choice, so keep the last authoritative sandbox pick here.
var _sandbox_vehicle: String = VehicleCatalog.DEFAULT_ID

@export var minigame_vehicle: String = VehicleCatalog.DEFAULT_ID:
	get:
		if racing_mode_active():
			return racing_vehicle_id()
		return _minigame_vehicle
	set(value):
		_minigame_vehicle = sanitize_vehicle_id(value)
@export var player_tag_color: String = "ffd22e" ## Name tag colour, RRGGBB hex.

@export_group("Session")
@export var play_mode: int = MODE_SINGLE ## MODE_SINGLE or MODE_MULTIPLAYER.
@export var multiplayer_mode: String = GAME_SANDBOX ## GAME_SANDBOX or GAME_MINIGAMES.
@export var connection_preference: String = CONN_PI ## CONN_LAN (this PC) or CONN_PI.
@export var relay_server: String = "" ## Optional relay address for internet joins.
@export var selected_minigame: String = "meadow_loop" ## Legacy minigame/arena theme id.
## Map chosen for the next race. Registry id from TrackDefs (race maps only).
@export var selected_map: String = TrackDefs.DEFAULT_ID

@export var bots_enabled: bool = false ## OFF by default - bots are strictly opt-in.
@export_range(0, 5) var bot_count: int = 3 ## How many AI carts to add when enabled.
## Online/LAN room discovery. Public rooms appear in the browser and can be
## joined with one click; private rooms are joinable only with the code.
@export var room_public: bool = true
## Multiplayer vehicle policy: "pick_own" (everyone drives their own Garage car
## & tune) or "shared" (everyone drives the host's car).
@export var multiplayer_vehicle_mode: String = "pick_own"

## Set before opening the vehicle screen so its confirm/back returns to the
## right menu (lobby, minigame picker, etc.). Memory only.
var vehicle_return_scene: String = ""
var vehicle_return_title: String = "PLAY"
var vehicle_edit_minigame: bool = false
var _resolution_scale: float = 1.0
var _quality_timer: float = 0.0
var _quality_warmup: float = 5.0
## Last legacy minigame id seen at load/save. A direct write from the old map
## picker is detected by comparing against it.
var _legacy_minigame_seen: String = ""
## Coalesced-save state. _save_pending means "the file on disk is stale".
var _save_pending: bool = false
var _save_countdown: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Baseline before load_settings(): a first run has no config file and must
	# not treat the untouched legacy default as a fresh map-picker write.
	_legacy_minigame_seen = selected_minigame
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


func _notification(what: int) -> void:
	## A slider dragged and then followed by ALT+F4, a browser tab pause or an
	## editor stop must still reach disk, so flush the coalesced save here too.
	## APPLICATION_FOCUS_OUT also covers Alt-Tab and a tab hidden by the browser,
	## where a close request may never arrive (WS5-09).
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED, \
				NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_PREDELETE:
			flush_settings()


func _exit_tree() -> void:
	flush_settings()


func _process(delta: float) -> void:
	## A pending coalesced save is flushed even when the dynamic-resolution
	## governor is switched off, so the early return must come after it.
	_tick_save(delta)
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
	var floor_scale: float = maxf(0.65, ceiling - 0.16)
	if fps < 45.0 and _resolution_scale > floor_scale:
		_resolution_scale = maxf(floor_scale, _resolution_scale - 0.02)
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
	_queue_save()
	changed.emit()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_bus(SFX_BUS, sfx_volume)
	_queue_save()
	changed.emit()


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_bus(MUSIC_BUS, music_volume)
	_queue_save()
	changed.emit()


func set_camera_shake(value: float) -> void:
	camera_shake = clampf(value, 0.0, 1.5)
	_queue_save()
	changed.emit()


func set_reduce_motion(value: bool) -> void:
	reduce_motion = value
	save_settings()
	changed.emit()


func set_hud_scale(value: float) -> void:
	hud_scale = clampf(value, 0.75, 1.5)
	_queue_save()
	changed.emit()


func set_stick_deadzone(value: float) -> void:
	stick_deadzone = clampf(value, 0.0, 0.4)
	_queue_save()
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


func set_pause_on_focus_loss(value: bool) -> void:
	pause_on_focus_loss = value
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
	pause_on_focus_loss = true
	save_settings()
	apply_all()


func set_fullscreen(value: bool) -> void:
	fullscreen = value
	apply_fullscreen()
	save_settings()
	changed.emit()


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
	var key: String = raw.strip_edges()
	if key == "" or key.length() > 255:
		return
	if not _is_valid_relay_server(key):
		return
	relay_server = key
	save_settings()


static func _is_valid_relay_server(key: String) -> bool:
	if key.contains(" ") or key.contains("\t") or key.contains("\n"):
		return false
	if key.contains("://"):
		return false
	var host: String = key
	var path: String = ""
	var slash: int = key.find("/")
	if slash >= 0:
		host = key.substr(0, slash)
		path = key.substr(slash)
		if path.contains(" "):
			return false
		if path.length() > 128:
			return false
	if host == "":
		return false
	var port: String = ""
	var bracket_close: int = host.find("]")
	if host.begins_with("["):
		if bracket_close <= 1:
			return false
		var after: String = host.substr(bracket_close + 1)
		if after != "" and not after.begins_with(":"):
			return false
		if after.begins_with(":"):
			port = after.substr(1)
		host = host.substr(0, bracket_close + 1)
	elif host.count(":") > 1:
		return false
	elif host.contains(":"):
		var parts: PackedStringArray = host.split(":")
		if parts.size() != 2:
			return false
		host = parts[0]
		port = parts[1]
	if port != "":
		if not port.is_valid_int():
			return false
		var port_num: int = int(port)
		if port_num <= 0 or port_num > 65535:
			return false
	if host == "":
		return false
	if host.begins_with("[") and host.ends_with("]"):
		var inner: String = host.substr(1, host.length() - 2)
		return inner != "" and not inner.contains(" ")
	if _is_valid_ipv4(host):
		return true
	return _is_valid_hostname(host)


static func _is_valid_ipv4(host: String) -> bool:
	var parts: PackedStringArray = host.split(".")
	if parts.size() != 4:
		return false
	for part: String in parts:
		if part == "" or not part.is_valid_int():
			return false
		if part.length() > 1 and part.begins_with("0"):
			pass
		var num: int = int(part)
		if num < 0 or num > 255:
			return false
		for c: String in part:
			if not c.is_valid_int():
				return false
	return true


static func _is_valid_hostname(host: String) -> bool:
	if host.length() > 253 or host == "":
		return false
	if host.begins_with(".") or host.ends_with(".") or host.begins_with("-") or host.ends_with("-"):
		return false
	if host.contains("..") or host.contains("--"):
		pass
	for label: String in host.split("."):
		if label == "" or label.length() > 63:
			return false
		if label.begins_with("-") or label.ends_with("-"):
			return false
		for c: String in label:
			var code: int = c.unicode_at(0)
			var ok: bool = (code >= 48 and code <= 57) \
				or (code >= 65 and code <= 90) \
				or (code >= 97 and code <= 122) \
				or code == 45 or code == 95
			if not ok:
				return false
	return true


func set_selected_minigame(id: String) -> void:
	## Legacy minigame/arena selection. Only registry ids survive: empty,
	## oversized or unknown ids fall back to `meadow_loop` like load_settings.
	var key: String = id.strip_edges()
	if key == "" or key.length() > 64:
		selected_minigame = "meadow_loop"
	elif TrackDefs.has_theme_id(key) or TrackDefs.has_theme_id(key.to_lower()):
		selected_minigame = key
	elif not TrackDefs.get_minigame(key).is_empty() \
			or not TrackDefs.get_minigame(key.to_lower()).is_empty():
		selected_minigame = key
	elif map_id_or_empty(key) != "":
		selected_minigame = key
	elif TrackDefs.all_ids().has(key) or TrackDefs.all_ids().has(key.to_lower()):
		selected_minigame = key
	else:
		selected_minigame = "meadow_loop"
	save_settings()


func set_selected_map(id: String) -> void:
	## Clamp to a real race map from TrackDefs. The legacy `meadow_loop` id
	## resolves to `circuit`, and an invented id falls back to the default map.
	## The legacy selected_minigame (cargo arena theme) is deliberately kept
	## separate, so picking a map never overwrites a minigame's theme.
	selected_map = sanitize_map_id(id)
	save_settings()


func minigame_name(id: String = "") -> String:
	## Display name straight from the registry, so a new map needs no edit here.
	var key: String = id if id != "" else selected_map
	return str(TrackDefs.get_preset(key).get("name", "RACE"))


static func sanitize_map_id(raw: String) -> String:
	## Only ids that exist in TrackDefs survive. get_preset() returns race maps
	## only and maps the legacy `meadow_loop` alias to `circuit`, so a cargo
	## theme, an invented id or a smuggled scene path falls back to the default.
	return str(TrackDefs.get_preset(raw).get("id", TrackDefs.DEFAULT_ID))


static func map_id_or_empty(raw: String) -> String:
	## The registry id when `raw` names a race map (legacy aliases included),
	## or "" for a cargo theme, a minigame id or an unknown value.
	var key: String = raw.strip_edges()
	for _hop in TrackDefs.LEGACY_IDS.size() + 1:
		if not TrackDefs.LEGACY_IDS.has(key):
			break
		var next: String = str(TrackDefs.LEGACY_IDS[key])
		if next == key:
			break
		key = next
	for preset: Dictionary in TrackDefs.PRESETS:
		if TrackDefs.is_map(preset) and str(preset.get("id", "")) == key:
			return key
	return ""


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


func set_multiplayer_vehicle_mode(mode: String) -> void:
	multiplayer_vehicle_mode = "shared" if mode == "shared" else "pick_own"
	save_settings()
	session_changed.emit()


func vehicle_for_channel(channel: String) -> String:
	match channel:
		"racing":
			return racing_vehicle_id()
		"minigame":
			return sanitize_vehicle_id(_minigame_vehicle)
		_:
			return sanitize_vehicle_id(_sandbox_vehicle)


func set_session_config(mode: int, game: String, bots: bool, count: int,
		map_id: String = "") -> void:
	## Used by Network so every peer runs the host's exact configuration. The
	## map is adopted only when the caller supplies one, so older call sites
	## keep their current selection.
	play_mode = MODE_MULTIPLAYER if mode == MODE_MULTIPLAYER else MODE_SINGLE
	multiplayer_mode = GAME_MINIGAMES if game == GAME_MINIGAMES else GAME_SANDBOX
	bots_enabled = bots
	bot_count = clampi(count, 0, 5)
	if map_id != "":
		selected_map = sanitize_map_id(map_id)
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


static func sanitize_vehicle_id(raw: String) -> String:
	## Any id that still exists in the catalog is honoured, including legacy
	## racer color variants normalized to "race_car". An unset, blank or removed
	## id opens on the shopping cart, which is the game's default everywhere.
	var key: String = VehicleCatalog.normalize_id(raw.strip_edges())
	if key != "" and not VehicleCatalog.find(key).is_empty():
		return key
	return VehicleCatalog.DEFAULT_ID


static func sanitize_racing_vehicle_id(raw: String) -> String:
	## A racing pick survives only when it is a curated racing choice (including
	## legacy racer color variants normalized to "race_car"). Corrupt or blank
	## ids fall back to the cart instead of silently becoming a race car.
	var key: String = VehicleCatalog.normalize_id(raw.strip_edges())
	if VehicleCatalog.is_racing_choice(key):
		return key
	return VehicleCatalog.DEFAULT_RACING_ID


func set_selected_vehicle(vehicle_id: String) -> void:
	selected_vehicle = sanitize_vehicle_id(vehicle_id)
	_sandbox_vehicle = selected_vehicle
	save_settings()


# --------------------------------------------------------------------------
# racing class


func _current_scene_path() -> String:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return ""
	return tree.current_scene.scene_file_path


func racing_scene_active() -> bool:
	## True while a scene whose rules are racing is current. grass_race.gd reads
	## minigame_vehicle from _enter_tree, before the first physics tick, so this
	## has to work from the scene path alone.
	return RACING_SCENES.has(_current_scene_path())


func racing_mode_active() -> bool:
	## Whether the vehicle picker should offer the racing class instead of the
	## sandbox roster. A live race wins; a live cargo arena always loses. The
	## multiplayer MINIGAMES lobby always starts a race, and the single-player
	## MINIGAMES garage restores either a race map or a cargo theme.
	if racing_scene_active():
		return true
	if NON_RACING_SCENES.has(_current_scene_path()):
		return false
	if play_mode == MODE_MULTIPLAYER:
		return multiplayer_mode == GAME_MINIGAMES
	if vehicle_edit_minigame:
		return not TrackDefs.has_theme_id(selected_minigame)
	return false


func racing_vehicle_id() -> String:
	## Always a legal racing pick, even after a corrupt or older save: the stock
	## shopping cart unless the player deliberately kept a Kenney chassis.
	return sanitize_racing_vehicle_id(racing_vehicle)


func racing_allocation() -> Dictionary:
	## The live four-stat build. An untouched install gets the balanced default
	## rather than an all-zero car.
	if racing_build.is_empty():
		return VehicleCatalog.default_allocation()
	return VehicleCatalog.sanitize_allocation(racing_build)


func set_racing_vehicle(vehicle_id: String) -> void:
	## The cart default is a valid racing pick; every other non-chassis id is
	## rejected so a bad caller can never remove the cart fallback.
	racing_vehicle = sanitize_racing_vehicle_id(vehicle_id)
	save_settings()


func set_racing_allocation(allocation: Dictionary) -> void:
	## Saves the build only, never the car currently selected for SANDBOX or a
	## non-racing minigame. Old saves simply fall back to the balanced default.
	racing_build = VehicleCatalog.sanitize_allocation(allocation)
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
	## Same contract as _cfg_num(), for integer ranges. A NaN/Inf float is
	## rejected before int() rather than relying on an undefined cast.
	var value: Variant = config.get_value(section, key, fallback)
	var kind: int = typeof(value)
	if kind != TYPE_FLOAT and kind != TYPE_INT:
		return clampi(fallback, low, high)
	var number: float = float(value)
	if not is_finite(number):
		return clampi(fallback, low, high)
	return clampi(int(number), low, high)


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
	## A save interrupted before its rename is recovered first (WS5-06).
	recover_staged_settings(SETTINGS_PATH, SETTINGS_TMP_PATH)
	var config := ConfigFile.new()
	var error: Error = config.load(SETTINGS_PATH)
	if error == ERR_FILE_NOT_FOUND or error == ERR_FILE_CANT_OPEN:
		# First run (or an unreadable user:// that no retry can fix) starts on
		# the exported defaults; there is nothing to recover or migrate.
		return
	if error != OK:
		# A truncated/hand-edited file used to fall through as "all defaults"
		# and then be overwritten by the next save, silently destroying whatever
		# the player had. Keep a copy, then write a clean default save so the
		# next boot is valid.
		_recover_corrupt_settings(error)
		return
	master_volume = _cfg_num(config, "audio", "master", master_volume, 0.0, 1.0)
	music_volume = _cfg_num(config, "audio", "music", music_volume, 0.0, 1.0)
	sfx_volume = _cfg_num(config, "audio", "sfx", sfx_volume, 0.0, 1.0)
	fullscreen = _cfg_bool(config, "video", "fullscreen", fullscreen)
	quality_preset = _cfg_int(config, "video", "quality", quality_preset, 0, 2)
	dynamic_resolution = _cfg_bool(config, "video", "dynamic_resolution", dynamic_resolution)
	if quality_preset == QUALITY_QUALITY:
		# The governor and the top preset are one switch (see
		# set_quality_preset); a hand-edited save must not leave them at odds.
		dynamic_resolution = false
	camera_shake = _cfg_num(config, "video", "camera_shake", camera_shake, 0.0, 1.5)
	hud_scale = _cfg_num(config, "video", "hud_scale", hud_scale, 0.75, 1.5)
	reduce_motion = _cfg_bool(config, "video", "reduce_motion", reduce_motion)
	show_fps = _cfg_bool(config, "ui", "show_fps", show_fps)
	custom_cursor = _cfg_bool(config, "ui", "custom_cursor", custom_cursor)
	boost_toggle = _cfg_bool(config, "gameplay", "boost_toggle", boost_toggle)
	drift_toggle = _cfg_bool(config, "gameplay", "drift_toggle", drift_toggle)
	stick_deadzone = _cfg_num(config, "gameplay", "stick_deadzone", stick_deadzone, 0.0, 0.4)
	# Missing in older saves: the documented default (auto-pause on) applies.
	pause_on_focus_loss = _cfg_bool(config, "gameplay", "pause_on_focus_loss",
		pause_on_focus_loss)
	selected_vehicle = sanitize_vehicle_id(
		_cfg_str(config, "gameplay", "vehicle", selected_vehicle))
	_sandbox_vehicle = selected_vehicle
	player_name = sanitize_name(_cfg_str(config, "gameplay", "player_name", player_name))
	minigame_difficulty = _cfg_int(config, "gameplay", "minigame_difficulty", minigame_difficulty, 0, 2)
	minigame_rounds = _cfg_int(config, "gameplay", "minigame_rounds", minigame_rounds, 3, 7)
	# The property setter validates this against the catalog, so an old save
	# naming a real vehicle is kept and a removed id opens on the cart.
	minigame_vehicle = _cfg_str(config, "gameplay", "minigame_vehicle", _minigame_vehicle)
	# Racing class is a separate save block. A missing block (every save made
	# before this feature) opens on the stock shopping cart. A block naming a
	# real Kenney chassis survives; anything else falls back to the cart.
	var saved_racing: String = _cfg_str(config, "racing", "vehicle",
		VehicleCatalog.DEFAULT_RACING_ID)
	racing_vehicle = sanitize_racing_vehicle_id(saved_racing)
	racing_build = {}
	var saved_build: Variant = config.get_value("racing", "allocation", {})
	if saved_build is Dictionary and not (saved_build as Dictionary).is_empty():
		racing_build = VehicleCatalog.sanitize_allocation(saved_build as Dictionary)
	var tag: String = _cfg_str(config, "gameplay", "tag_color", player_tag_color)
	tag = tag.strip_edges().trim_prefix("#").to_lower()
	if _valid_hex6(tag):
		player_tag_color = tag
	play_mode = _cfg_int(config, "session", "play_mode", play_mode, MODE_SINGLE, MODE_MULTIPLAYER)
	# _cfg_int() already clamps to MODE_SINGLE..MODE_MULTIPLAYER, so the old
	# follow-up "if play_mode is neither" guard could never run. Removed as
	# dead logic rather than kept as false reassurance.
	multiplayer_mode = _cfg_str(config, "session", "multiplayer_mode", multiplayer_mode)
	if multiplayer_mode != GAME_MINIGAMES and multiplayer_mode != GAME_SANDBOX:
		multiplayer_mode = GAME_SANDBOX
	connection_preference = _cfg_str(config, "session", "connection", connection_preference).to_lower()
	if connection_preference == "online":
		connection_preference = CONN_PI
	if connection_preference != CONN_LAN and connection_preference != CONN_PI:
		connection_preference = CONN_PI
	# A relay address is a host name plus an optional path, never free text:
	# strip it and cap it so a hand-edited save cannot smuggle a huge string
	# into every save and every room advertisement.
	relay_server = _cfg_str(config, "session", "relay_server", relay_server).strip_edges()
	if relay_server.length() > 255:
		relay_server = relay_server.substr(0, 255)
	# The legacy id is a registry key, not free text. An empty or oversized
	# value falls back to the shipped default instead of becoming the cargo
	# theme id that every later save would then persist.
	var saved_minigame: String = _cfg_str(config, "session", "selected_minigame",
		selected_minigame).strip_edges()
	selected_minigame = saved_minigame if (saved_minigame != "" and saved_minigame.length() <= 64) \
		else "meadow_loop"
	_legacy_minigame_seen = selected_minigame
	# Map ids come from the registry. Older saves only have the legacy key;
	# accept it only when it names a race map, never a cargo arena theme.
	var saved_map: String = map_id_or_empty(
		_cfg_str(config, "session", "selected_map", ""))
	if saved_map == "":
		saved_map = map_id_or_empty(selected_minigame)
	selected_map = saved_map if saved_map != "" else TrackDefs.DEFAULT_ID
	bots_enabled = _cfg_bool(config, "session", "bots_enabled", bots_enabled)
	bot_count = _cfg_int(config, "session", "bot_count", bot_count, 0, 5)
	room_public = _cfg_bool(config, "session", "room_public", room_public)
	var saved_vm: String = _cfg_str(config, "session", "vehicle_mode", multiplayer_vehicle_mode).strip_edges().to_lower()
	multiplayer_vehicle_mode = "shared" if saved_vm == "shared" else "pick_own"
	var saved_racer_col: String = _cfg_str(config, "racing", "racer_color", racer_color).strip_edges().trim_prefix("#").to_lower()
	if saved_racer_col.length() == 6 and saved_racer_col.is_valid_hex_number(false):
		racer_color = saved_racer_col
	# ---- ONE-TIME migration, deliberately last ----
	# A save written before the marker may still name a racing chassis
	# (race_car_red) in any vehicle slot, and that stale pick used to survive
	# forever. Resolve every slot to the stock shopping cart once, then write
	# the marker straight away so it never re-applies - even if the player
	# quits before changing anything else. Every unrelated key was already
	# loaded above and is written back unchanged.
	if _migrate_legacy_vehicle(config):
		save_settings()


static func saved_settings_version(config: ConfigFile) -> int:
	## 0 means the file predates the marker (or is missing); a newer save keeps
	## its higher number and is never treated as old.
	if config == null:
		return 0
	return _cfg_int(config, "meta", "version", 0, 0, SETTINGS_VERSION_MAX)


func _migrate_legacy_vehicle(config: ConfigFile) -> bool:
	## ONE-TIME vehicle migration for pre-marker saves. The shopping cart is the
	## intended default everywhere now, so a persisted racing car id (for
	## example race_car_red) is resolved to it exactly once. A deliberate pick
	## saved afterwards carries the marker and is never overwritten. Returns
	## true when the caller must persist the marker.
	if saved_settings_version(config) >= SETTINGS_VERSION:
		return false
	selected_vehicle = VehicleCatalog.DEFAULT_ID
	_sandbox_vehicle = VehicleCatalog.DEFAULT_ID
	_minigame_vehicle = VehicleCatalog.DEFAULT_ID
	racing_vehicle = VehicleCatalog.DEFAULT_RACING_ID
	return true


func _absorb_legacy_map_choice() -> void:
	## The old map picker writes its choice straight into selected_minigame.
	## When that field changed and now names a race map, adopt it into the
	## dedicated map field; cargo theme ids and unchanged values are ignored.
	if selected_minigame == _legacy_minigame_seen:
		return
	_legacy_minigame_seen = selected_minigame
	var legacy_map: String = map_id_or_empty(selected_minigame)
	if legacy_map != "":
		selected_map = legacy_map


func save_settings() -> void:
	# A full save supersedes any coalesced one that was waiting.
	_save_pending = false
	_save_countdown = 0.0
	_absorb_legacy_map_choice()
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
	config.set_value("gameplay", "pause_on_focus_loss", pause_on_focus_loss)
	config.set_value("ui", "custom_cursor", custom_cursor)
	# Always persist the last authoritative sandbox pick. grass_race.gd and
	# cargo_rush.gd both swap selected_vehicle for their own scene, and a save
	# from their pause menu must not make that swap the SANDBOX car.
	config.set_value("gameplay", "vehicle", _sandbox_vehicle)
	config.set_value("gameplay", "player_name", player_name)
	config.set_value("gameplay", "minigame_difficulty", minigame_difficulty)
	config.set_value("gameplay", "minigame_rounds", minigame_rounds)
	config.set_value("gameplay", "minigame_vehicle", _minigame_vehicle)
	config.set_value("racing", "vehicle", racing_vehicle_id())
	config.set_value("racing", "allocation", racing_allocation())
	config.set_value("racing", "racer_color", racer_color)
	config.set_value("gameplay", "tag_color", player_tag_color)
	config.set_value("session", "play_mode", play_mode)
	config.set_value("session", "multiplayer_mode", multiplayer_mode)
	config.set_value("session", "connection", connection_preference)
	config.set_value("session", "relay_server", relay_server)
	config.set_value("session", "selected_map", selected_map)
	config.set_value("session", "selected_minigame", selected_minigame)
	config.set_value("session", "bots_enabled", bots_enabled)
	config.set_value("session", "bot_count", bot_count)
	config.set_value("session", "room_public", room_public)
	config.set_value("session", "vehicle_mode", multiplayer_vehicle_mode)
	# The schema marker is part of the save, not a one-off: every later write
	# keeps it, which is what makes the vehicle migration above one-time.
	config.set_value("meta", "version", SETTINGS_VERSION)
	var error: Error = commit_config_atomic(config, SETTINGS_PATH, SETTINGS_TMP_PATH)
	if error != OK:
		# A read-only user:// (or a full disk) must not look like success.
		push_warning("GameSettings: could not write settings.cfg (%d)" % error)


static func commit_config_atomic(config: ConfigFile, final_path: String,
		tmp_path: String) -> Error:
	## Atomic save helper (WS5-06): write the complete file to `tmp_path`, flush	## it, then rename it over `final_path`. A crash can then only leave the old
	## complete file (plus a temp) or, depending on the filesystem's rename
	## implementation, the complete temp with the final name missing - which
	## recover_staged_settings() adopts on the next boot. Never a partial file
	## under the live name.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_path))
	var write_error: Error = config.save(tmp_path)
	if write_error != OK:
		return write_error
	# Godot exposes no fsync; flush via a read handle so the staged bytes leave
	# the process before the rename. The rename is the durability guarantee.
	var staged: FileAccess = FileAccess.open(tmp_path, FileAccess.READ)
	if staged != null:
		staged.flush()
		staged.close()
	var from_abs: String = ProjectSettings.globalize_path(tmp_path)
	var to_abs: String = ProjectSettings.globalize_path(final_path)
	var rename_error: Error = DirAccess.rename_absolute(from_abs, to_abs)
	if rename_error == OK:
		return OK
	# A filesystem that refuses the rename gets the old in-place write rather
	# than losing the player's settings entirely; the temp is cleaned up.
	var fallback_error: Error = config.save(final_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_path))
	return fallback_error


static func recover_staged_settings(final_path: String, tmp_path: String) -> bool:
	## Crash recovery for the atomic save. The live file always wins when it
	## exists; the staged copy is adopted only when the rename never completed
	## and the live name is missing. Returns true when a staged save was adopted.
	var final_exists: bool = FileAccess.file_exists(final_path)
	var tmp_exists: bool = FileAccess.file_exists(tmp_path)
	if not tmp_exists:
		return false
	var from_abs: String = ProjectSettings.globalize_path(tmp_path)
	if final_exists:
		# Leftovers from a save that did not reach the rename: discard.
		DirAccess.remove_absolute(from_abs)
		return false
	var to_abs: String = ProjectSettings.globalize_path(final_path)
	if DirAccess.rename_absolute(from_abs, to_abs) == OK:
		return true
	push_warning("GameSettings: could not recover the staged settings save")
	return false


func _recover_corrupt_settings(error: Error) -> void:
	## A damaged save must not be overwritten silently. Keep the unreadable file
	## for recovery, then write a valid default save so the next boot is clean.
	push_warning("GameSettings: settings.cfg is unreadable (%d); keeping a copy and writing defaults" % error)
	var backup_error: Error = DirAccess.copy_absolute(SETTINGS_PATH, CORRUPT_BACKUP_PATH)
	if backup_error != OK:
		push_warning("GameSettings: could not keep %s (%d)" % [CORRUPT_BACKUP_PATH, backup_error])
	save_settings()


# --------------------------------------------------------------------------
# coalesced saving


func _queue_save() -> void:
	## Slider-driven settings fire value_changed dozens of times per second and
	## every save is a synchronous ConfigFile write. Mark the file dirty and let
	## _tick_save() write it once, instead of one write per input event.
	_save_pending = true
	_save_countdown = SAVE_DEBOUNCE_SECONDS


func _tick_save(delta: float) -> void:
	if not _save_pending:
		return
	_save_countdown = maxf(_save_countdown - delta, 0.0)
	if _save_countdown <= 0.0:
		flush_settings()


func flush_settings() -> void:
	## Writes a pending coalesced save right now. Called from _process(), the
	## close/pause notifications and _exit_tree(), so a slider change is never
	## lost when the game closes inside the debounce window.
	if not _save_pending:
		return
	save_settings()


func has_pending_save() -> bool:
	## True while a coalesced write is still waiting. Lets a test or a settings
	## screen prove the debounce never drops the last change.
	return _save_pending


# --------------------------------------------------------------------------
# readable summary


func settings_summary_lines() -> PackedStringArray:
	## Readable snapshot for a settings/about card. Every value is the already
	## clamped value the game applies, so the summary can never disagree with
	## the audio, input or HUD layer.
	var lines: PackedStringArray = PackedStringArray()
	lines.append("AUDIO    master %d%%  music %d%%  sfx %d%%"
		% [_percent(master_volume), _percent(music_volume), _percent(sfx_volume)])
	lines.append("VIDEO    %s  %s  HUD %d%%  shake x%.2f"
		% [quality_name(), "dynamic" if dynamic_resolution else "fixed",
			roundi(clampf(hud_scale, 0.75, 1.5) * 100.0), clampf(camera_shake, 0.0, 1.5)])
	lines.append("COMFORT  reduce motion %s  FPS %s"
		% [_on_off(reduce_motion), _on_off(show_fps)])
	lines.append("CONTROLS deadzone %d%%  boost %s  drift %s"
		% [_percent(stick_deadzone), _hold_or_toggle(boost_toggle),
			_hold_or_toggle(drift_toggle)])
	lines.append("PLAY     %s  bots %d  %s  %s"
		% ["multiplayer" if play_mode == MODE_MULTIPLAYER else "single",
			effective_bot_count(), ai_difficulty_name(), _vehicle_label()])
	return lines


func settings_summary() -> String:
	## One string the UI can drop straight into an autowrapped label.
	return "\n".join(settings_summary_lines())


func _vehicle_label() -> String:
	## Catalog display name, or the bare id when the catalog has no entry, so an
	## old save can never render an empty field.
	var entry: Dictionary = VehicleCatalog.find(_sandbox_vehicle)
	var label: String = str(entry.get("name", "")).strip_edges()
	return label if label != "" else _sandbox_vehicle


static func _percent(ratio: float) -> int:
	return roundi(clampf(ratio, 0.0, 1.0) * 100.0)


static func _on_off(value: bool) -> String:
	return "ON" if value else "OFF"


static func _hold_or_toggle(value: bool) -> String:
	return "toggle" if value else "hold"
