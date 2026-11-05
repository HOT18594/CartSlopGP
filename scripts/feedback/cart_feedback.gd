class_name CartFeedback
extends Node3D
## Modular audiovisual feedback for the cart: smoke plumes,
## wind streaks and audio hooks. Reads cart state; impact/landing events
## are pushed in by the player script.

@export_group("Toggles")
@export var enable_dust: bool = true
@export var enable_speed_feedback: bool = true
@export var enable_collision_feedback: bool = true
@export var enable_audio: bool = true

@export_group("Smoke")
@export var smoke_intensity: float = 0.85 ## 0-1: density of drift smoke.
@export var smoke_lifetime: float = 1.4 ## Drift smoke lifetime (s).
@export var launch_dust_speed: float = 3.5 ## Only wisp below this speed when launching.
@export var landing_burst_strength: float = 1.0 ## 0-1 landing smoke burst strength.

@export_group("Speed Feedback")
@export var wind_speed_threshold: float = 12.0 ## Speed (m/s) where wind streaks start.
@export var wind_max_amount_ratio: float = 1.0 ## Max wind streak density (0-1).

@export_group("Audio")
@export var slide_sound_min_speed: float = 4.0 ## Minimum speed (m/s) for the skid sound.
@export var crash_sound_volume: float = 0.8 ## Crash sound volume (0-1 linear).

var dust_active: bool = false ## For the debug HUD.
var speed_feedback_active: bool = false ## For the debug HUD.
var missing_audio: Array[String] = [] ## Streams that could not be loaded (for the HUD/report).

var _cart: CartPlayer
var _dust: GPUParticles3D
var _dust_burst: GPUParticles3D
var _wind: GPUParticles3D
var _camera: Camera3D

@onready var _engine_audio: AudioStreamPlayer3D = $EngineAudio
@onready var _skid_audio: AudioStreamPlayer3D = $SkidAudio
@onready var _impact_audio: AudioStreamPlayer3D = $ImpactAudio
@onready var _thud_audio: AudioStreamPlayer3D = $ThudAudio
@onready var _impact_light_audio: AudioStreamPlayer3D = $ImpactLightAudio
@onready var _impact_heavy_audio: AudioStreamPlayer3D = $ImpactHeavyAudio
@onready var _crash_audio: AudioStreamPlayer3D = $CrashAudio
@onready var _boost_start_audio: AudioStreamPlayer3D = $BoostStartAudio
@onready var _boost_loop_audio: AudioStreamPlayer3D = $BoostLoopAudio


func _ready() -> void:
	add_to_group("cart_feedback")
	_cart = get_parent() as CartPlayer
	_dust = $Dust as GPUParticles3D
	_dust_burst = $DustBurst as GPUParticles3D
	_wind = $WindStreaks as GPUParticles3D
	_camera = get_viewport().get_camera_3d()
	_load_audio()


func _load_audio() -> void:
	## Assign downloaded CC0 streams where present and fall back to the bundled
	## synthesized sounds; anything unavailable is logged, never fatal.
	_set_stream($EngineAudio, "res://assets/audio/sfx/engine/engine_loop.wav", "res://assets/audio/engine_loop.wav")
	_set_stream($SkidAudio, "res://assets/audio/sfx/skid/skid_loop.wav", "res://assets/audio/skid_loop.wav")
	_set_stream($ImpactLightAudio, "res://assets/audio/sfx/impacts/impact_light.ogg", "res://assets/audio/impact.wav")
	_set_stream($ImpactHeavyAudio, "res://assets/audio/sfx/impacts/impact_heavy.ogg", "res://assets/audio/impact.wav")
	_set_stream($CrashAudio, "res://assets/audio/sfx/impacts/crash_flip.ogg", "res://assets/audio/impact.wav")
	_set_stream($ThudAudio, "res://assets/audio/sfx/landing/landing_thud.ogg", "res://assets/audio/landing_thud.wav")
	_set_stream($BoostStartAudio, "res://assets/audio/sfx/boost/boost_start.ogg", "")
	_set_stream($BoostLoopAudio, "res://assets/audio/sfx/engine/engine_boost.wav", "")


func _set_stream(player: AudioStreamPlayer3D, primary: String, fallback: String) -> void:
	if player == null:
		return
	if ResourceLoader.exists(primary):
		player.stream = load(primary)
	elif fallback != "" and ResourceLoader.exists(fallback):
		player.stream = load(fallback)
	else:
		missing_audio.append(primary)
		push_warning("Missing audio: " + primary)


func _physics_process(_delta: float) -> void:
	if _cart == null:
		return
	if _camera == null:
		_camera = get_viewport().get_camera_3d()
	var speed: float = _cart.velocity.length()
	var grounded: bool = _cart.is_on_floor()
	var drifting: bool = _cart.is_drifting
	var handbraking: bool = Input.is_action_pressed("handbrake")
	var accelerating: bool = Input.is_action_pressed("accelerate")
	_update_smoke(speed, grounded, drifting, handbraking, accelerating)
	_update_speed_feedback(speed)
	_update_audio(speed, grounded, drifting, handbraking)


func _update_smoke(speed: float, grounded: bool, drifting: bool, handbraking: bool, accelerating: bool) -> void:
	dust_active = false
	if _dust == null:
		return
	if not (enable_dust and grounded):
		_dust.emitting = false
		return
	if drifting or handbraking:
		# Tire smoke while sliding - the only continuous smoke.
		dust_active = true
		_dust.emitting = true
		_dust.amount_ratio = clampf(smoke_intensity, 0.05, 1.0)
		_dust.lifetime = smoke_lifetime
	elif accelerating and speed < launch_dust_speed:
		# Very small wisp off the line, like real tire dust from a standing start.
		dust_active = true
		_dust.emitting = true
		_dust.amount_ratio = clampf(smoke_intensity * 0.15, 0.03, 0.25)
		_dust.lifetime = smoke_lifetime * 0.7
	else:
		_dust.emitting = false


func _update_speed_feedback(speed: float) -> void:
	speed_feedback_active = false
	if _wind == null:
		return
	if _camera != null:
		_wind.global_transform = _camera.global_transform
	if enable_speed_feedback and speed > wind_speed_threshold:
		speed_feedback_active = true
		_wind.emitting = true
		_wind.amount_ratio = clampf((speed - wind_speed_threshold) / 8.0, 0.2, wind_max_amount_ratio)
	else:
		_wind.emitting = false


func _update_audio(speed: float, grounded: bool, drifting: bool, handbraking: bool) -> void:
	var sliding: bool = grounded and (drifting or handbraking) and speed > slide_sound_min_speed
	if _engine_audio != null:
		var want_engine: bool = enable_audio and _engine_audio.stream != null
		if want_engine and not _engine_audio.playing:
			_engine_audio.play()
		_engine_audio.stream_paused = not want_engine
		if want_engine:
			_engine_audio.pitch_scale = 0.8 + clampf(speed / 18.0, 0.0, 1.0) * 0.7
	if _skid_audio != null:
		var want_skid: bool = enable_audio and sliding and _skid_audio.stream != null
		if want_skid and not _skid_audio.playing:
			_skid_audio.play()
		_skid_audio.stream_paused = not want_skid
		_skid_audio.volume_db = lerpf(-18.0, -8.0, clampf(_cart.slide_amount, 0.0, 1.0))
	var boosting: bool = _cart.boost_active or _cart.boost_visual > 0.5
	if _engine_audio != null:
		var base_pitch: float = 0.8 + clampf(speed / 18.0, 0.0, 1.0) * 0.7
		_engine_audio.pitch_scale = minf(base_pitch * (1.0 + 0.18 * _cart.boost_visual), 2.2)
	if _boost_loop_audio != null:
		var want_boost_loop: bool = enable_audio and boosting and _boost_loop_audio.stream != null
		if want_boost_loop and not _boost_loop_audio.playing:
			_boost_loop_audio.play()
		_boost_loop_audio.stream_paused = not want_boost_loop


func on_collision(impact_factor: float) -> void:
	## Called by the player when hitting something solid: crash smoke + sound.
	if not enable_collision_feedback:
		return
	if _dust_burst != null and enable_dust:
		_dust_burst.amount_ratio = clampf(0.6 + impact_factor * 0.5, 0.3, 1.0)
		_dust_burst.restart()
	var player: AudioStreamPlayer3D = _impact_heavy_audio if impact_factor > 0.55 else _impact_light_audio
	if player != null and player.stream == null:
		player = _impact_audio # Legacy synthesized fallback.
	if player != null and enable_audio and player.stream != null:
		player.pitch_scale = randf_range(0.9, 1.1)
		player.play()


func on_landing(fall_speed: float) -> void:
	## Called by the player on touchdown after a jump: landing puff + thud.
	if _dust_burst != null and enable_dust:
		_dust_burst.amount_ratio = clampf(landing_burst_strength * clampf(fall_speed * 0.12, 0.35, 1.0), 0.2, 1.0)
		_dust_burst.restart()
	if _thud_audio != null and enable_audio and _thud_audio.stream != null:
		_thud_audio.pitch_scale = randf_range(0.95, 1.05)
		_thud_audio.play()


func on_crash(intensity: float) -> void:
	## Called by the player when it lands badly: heavy burst + crash sound.
	if _dust_burst != null and enable_dust:
		_dust_burst.amount_ratio = 1.0
		_dust_burst.restart()
	if _crash_audio != null and enable_audio and _crash_audio.stream != null:
		_crash_audio.volume_db = linear_to_db(crash_sound_volume)
		_crash_audio.pitch_scale = randf_range(0.9, 1.05)
		_crash_audio.play()


func on_boost_started() -> void:
	## Called by the player on the rising edge of a boost.
	if _boost_start_audio != null and enable_audio and _boost_start_audio.stream != null:
		_boost_start_audio.pitch_scale = randf_range(0.95, 1.05)
		_boost_start_audio.play()


func reset_feedback() -> void:
	## Clears every effect and audio state (used by the cart reset).
	if _dust != null:
		_dust.emitting = false
	if _dust_burst != null:
		_dust_burst.emitting = false
	if _wind != null:
		_wind.emitting = false
	if _skid_audio != null:
		_skid_audio.stream_paused = true
	if _boost_loop_audio != null:
		_boost_loop_audio.stream_paused = true
	dust_active = false
	speed_feedback_active = false
