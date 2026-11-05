# class_name removed: would clash with the live script's global class
extends Node3D
## Modular audiovisual feedback for the cart: pooled skid marks, dust,
## speed streaks and audio hooks. Reads cart state; events are pushed in
## via on_collision() / on_landing() by the player script.

@export_group("Toggles")
@export var enable_skid_marks: bool = true
@export var enable_dust: bool = true
@export var enable_speed_feedback: bool = true
@export var enable_collision_feedback: bool = true
@export var enable_audio: bool = true

@export_group("Skid Marks")
@export var skid_spawn_spacing: float = 0.45 ## Meters travelled between skid quads.
@export var skid_min_speed: float = 4.0 ## Minimum speed (m/s) for skid marks.
@export var skid_sharp_steer: float = 0.65 ## |steer| above this counts as sharp at speed.
@export var skid_hard_brake_speed: float = 9.0 ## Speed above which hard braking lays marks.
@export var skid_lifetime: float = 4.0 ## Seconds until a mark fades out.
@export var wheel_offset: Vector2 = Vector2(0.62, 0.62) ## Rear wheel (x, z) offsets from the cart origin.

@export_group("Dust")
@export var dust_intensity: float = 0.8 ## 0-1: strength of continuous dust.
@export var dust_lifetime: float = 0.7 ## Dust particle lifetime (s).
@export var dust_high_speed_threshold: float = 11.0 ## Speed (m/s) that kicks up dust.
@export var dust_launch_speed_threshold: float = 6.0 ## Dust while accelerating below this speed.
@export var landing_burst_strength: float = 1.0 ## 0-1 landing dust burst strength.

@export_group("Speed Feedback")
@export var wind_speed_threshold: float = 12.0 ## Speed (m/s) where wind streaks start.
@export var wind_max_amount_ratio: float = 1.0 ## Max wind streak density (0-1).

var dust_active: bool = false ## For the debug HUD.
var speed_feedback_active: bool = false ## For the debug HUD.
var active_skid_marks: int = 0 ## For the debug HUD.

var _cart: CartPlayer
var _skid_pool: SkidMarkPool
var _dust: GPUParticles3D
var _dust_burst: GPUParticles3D
var _wind: GPUParticles3D
var _camera: Camera3D
var _skid_distance: float = 0.0
var _last_position: Vector3

@onready var _engine_audio: AudioStreamPlayer3D = $EngineAudio
@onready var _skid_audio: AudioStreamPlayer3D = $SkidAudio
@onready var _impact_audio: AudioStreamPlayer3D = $ImpactAudio
@onready var _thud_audio: AudioStreamPlayer3D = $ThudAudio


func _ready() -> void:
	add_to_group("cart_feedback")
	_cart = get_parent() as CartPlayer
	_skid_pool = $SkidPool as SkidMarkPool
	_dust = $Dust as GPUParticles3D
	_dust_burst = $DustBurst as GPUParticles3D
	_wind = $WindStreaks as GPUParticles3D
	_camera = get_viewport().get_camera_3d()
	if _skid_pool != null:
		_skid_pool.mark_lifetime = skid_lifetime
	_last_position = global_position


func _physics_process(delta: float) -> void:
	if _cart == null:
		return
	if _camera == null:
		_camera = get_viewport().get_camera_3d()
	var speed: float = _cart.velocity.length()
	var grounded: bool = _cart.is_on_floor()
	var drifting: bool = _cart.is_drifting
	var handbraking: bool = Input.is_action_pressed("handbrake")
	var steering: float = Input.get_axis("steer_right", "steer_left")
	var accelerating: bool = Input.is_action_pressed("accelerate")
	var braking: bool = Input.is_action_pressed("brake")
	_update_skid_marks(speed, grounded, drifting, handbraking, steering, braking, accelerating, delta)
	_update_dust(speed, grounded, drifting, handbraking, accelerating)
	_update_speed_feedback(speed)
	_update_audio(speed, grounded, drifting, handbraking)


func _update_skid_marks(speed: float, grounded: bool, drifting: bool, handbraking: bool,
		steering: float, braking: bool, accelerating: bool, delta: float) -> void:
	if _skid_pool == null:
		active_skid_marks = 0
		return
	var should_skid: bool = enable_skid_marks and grounded and speed > skid_min_speed
	if should_skid:
		var hard_braking: bool = braking and speed > skid_hard_brake_speed
		var sharp_turn: bool = absf(steering) > skid_sharp_steer and speed > skid_min_speed * 2.0
		should_skid = drifting or handbraking or hard_braking or sharp_turn
	if not should_skid:
		_skid_distance = 0.0
		active_skid_marks = _skid_pool.active_count()
		return
	var travelled: Vector3 = global_position - _last_position
	travelled.y = 0.0
	_skid_distance += travelled.length()
	if _skid_distance >= skid_spawn_spacing:
		_skid_distance = 0.0
		var travel_yaw: float = atan2(-_cart.velocity.x, -_cart.velocity.z)
		var right_dir: Vector3 = _cart.global_transform.basis.x
		var rear_center: Vector3 = global_position + _cart.global_transform.basis.z * wheel_offset.y
		for side in [-1.0, 1.0]:
			var pos: Vector3 = rear_center + right_dir * wheel_offset.x * side
			pos.y = global_position.y + 0.03
			_skid_pool.spawn_mark(pos, travel_yaw)
	_last_position = global_position
	active_skid_marks = _skid_pool.active_count()


func _update_dust(speed: float, grounded: bool, drifting: bool, handbraking: bool, accelerating: bool) -> void:
	dust_active = false
	if _dust == null:
		return
	if not (enable_dust and grounded):
		_dust.emitting = false
		return
	var launching: bool = accelerating and speed < dust_launch_speed_threshold
	var fast: bool = speed > dust_high_speed_threshold
	if drifting or handbraking or launching or fast:
		dust_active = true
		if not _dust.emitting:
			_dust.emitting = true
		var boost: float = 1.6 if (drifting or handbraking) else 1.0
		_dust.amount_ratio = clampf(dust_intensity * boost, 0.05, 1.0)
		_dust.lifetime = dust_lifetime
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
	var sliding: bool = grounded and (drifting or handbraking) and speed > skid_min_speed
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


func on_collision(impact_factor: float) -> void:
	## Called by the player when hitting something solid.
	if not enable_collision_feedback:
		return
	if _dust_burst != null and enable_dust:
		_dust_burst.amount_ratio = clampf(0.5 + impact_factor, 0.2, 1.0)
		_dust_burst.restart()
	if _impact_audio != null and enable_audio and _impact_audio.stream != null:
		_impact_audio.pitch_scale = randf_range(0.9, 1.1)
		_impact_audio.play()


func on_landing(fall_speed: float) -> void:
	## Called by the player on touchdown after a jump.
	if _dust_burst != null and enable_dust:
		_dust_burst.amount_ratio = clampf(landing_burst_strength * clampf(fall_speed * 0.15, 0.3, 1.0), 0.1, 1.0)
		_dust_burst.restart()
	if _thud_audio != null and enable_audio and _thud_audio.stream != null:
		_thud_audio.pitch_scale = randf_range(0.95, 1.05)
		_thud_audio.play()


func reset_feedback() -> void:
	## Clears every effect and audio state (used by the cart reset).
	if _skid_pool != null:
		_skid_pool.clear_marks()
	if _dust != null:
		_dust.emitting = false
	if _dust_burst != null:
		_dust_burst.emitting = false
	if _wind != null:
		_wind.emitting = false
	if _skid_audio != null:
		_skid_audio.stream_paused = true
	_skid_distance = 0.0
	dust_active = false
	speed_feedback_active = false
	active_skid_marks = 0
