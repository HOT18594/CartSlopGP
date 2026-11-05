extends Node
## Persisted player settings shared by every menu scene.
## Volumes are 0-1 linear; they are converted to dB when applied.

signal changed

const SETTINGS_PATH: String = "user://settings.cfg"
const SFX_BUS: String = "SFX"

@export_range(0.0, 1.0, 0.01) var master_volume: float = 0.8
@export_range(0.0, 1.0, 0.01) var sfx_volume: float = 0.85
@export var fullscreen: bool = false
@export var custom_cursor: bool = true

@export_group("Sandbox")
@export var selected_vehicle: String = "shopping_cart" ## Vehicle id from the catalog.
@export var player_name: String = "PLAYER" ## Name shown in multiplayer lobbies.
@export_range(0, 2) var minigame_difficulty: int = 1
@export_range(3, 7, 2) var minigame_rounds: int = 3
@export var minigame_vehicle: String = "shopping_cart"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_sfx_bus()
	load_settings()
	apply_all()


func _ensure_sfx_bus() -> void:
	## The prototype only ships a Master bus; add SFX once at runtime.
	if AudioServer.get_bus_index(SFX_BUS) != -1:
		return
	AudioServer.add_bus()
	var index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, SFX_BUS)
	AudioServer.set_bus_send(index, "Master")


func apply_all() -> void:
	_apply_bus("Master", master_volume)
	_apply_bus(SFX_BUS, sfx_volume)
	apply_fullscreen()
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


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_bus("Master", master_volume)
	save_settings()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_bus(SFX_BUS, sfx_volume)
	save_settings()


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


func set_minigame_options(difficulty: int, rounds: int, vehicle_id: String) -> void:
	minigame_difficulty = clampi(difficulty, 0, 2)
	minigame_rounds = clampi(rounds, 3, 7)
	minigame_vehicle = vehicle_id
	save_settings()


static func sanitize_name(raw_name: String) -> String:
	## Keep names short, printable and free of control characters.
	var cleaned: String = ""
	for character in raw_name.strip_edges():
		var code: int = character.unicode_at(0)
		if code == 10 or code == 9 or code == 13:
			cleaned += " "
		elif code >= 32:
			cleaned += character
	cleaned = cleaned.strip_edges()
	if cleaned.length() > 16:
		cleaned = cleaned.substr(0, 16).strip_edges()
	return cleaned if cleaned != "" else "PLAYER"


func set_selected_vehicle(vehicle_id: String) -> void:
	selected_vehicle = vehicle_id
	save_settings()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	master_volume = float(config.get_value("audio", "master", master_volume))
	sfx_volume = float(config.get_value("audio", "sfx", sfx_volume))
	fullscreen = bool(config.get_value("video", "fullscreen", fullscreen))
	custom_cursor = bool(config.get_value("ui", "custom_cursor", custom_cursor))
	selected_vehicle = str(config.get_value("gameplay", "vehicle", selected_vehicle))
	player_name = str(config.get_value("gameplay", "player_name", player_name))
	minigame_difficulty = int(config.get_value("gameplay", "minigame_difficulty", minigame_difficulty))
	minigame_rounds = int(config.get_value("gameplay", "minigame_rounds", minigame_rounds))
	minigame_vehicle = str(config.get_value("gameplay", "minigame_vehicle", minigame_vehicle))


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master", master_volume)
	config.set_value("audio", "sfx", sfx_volume)
	config.set_value("video", "fullscreen", fullscreen)
	config.set_value("ui", "custom_cursor", custom_cursor)
	config.set_value("gameplay", "vehicle", selected_vehicle)
	config.set_value("gameplay", "player_name", player_name)
	config.set_value("gameplay", "minigame_difficulty", minigame_difficulty)
	config.set_value("gameplay", "minigame_rounds", minigame_rounds)
	config.set_value("gameplay", "minigame_vehicle", minigame_vehicle)
	config.save(SETTINGS_PATH)
