# class_name removed: would clash with the live script's global class
extends Node3D
## Modular audiovisual feedback for the cart: skid ribbons, smoke plumes,
## wind streaks and audio hooks. Reads cart state; impact/landing events
## are pushed in by the player script.

@export_group("Toggles")
@export var enable_skid_marks: bool = true
@export var enable_dust: bool = true
@export var enable_speed_feedback: bool = true
@export var enable_collision_feedback: bool = true
@export var enable_audio: bool = true

@export_group("Skid Marks")
@export var skid_min_speed: float = 4.0 ## Minimum speed (m/s) for skid marks.
@export var skid_sharp_steer: float = 0.7 ## |steer| above this counts as sharp at speed.
@export var skid_hard_brake_speed: float = 9.0 ## Speed above which hard braking lays marks.
@export var wheel_offset: Vector2 = Vector2(0.62, 0.62) ## Rear wheel (x, z) offsets from the cart origin.

@export_group("Smoke")
@export var smoke_intensity: float = 0.85 ## 0-1: density of drift smoke.
@export var smoke_lifetime: float = 1.4 ## Drift smoke lifetime (s).
@export var launch_dust_speed: float = 3.5 ## Only wisp below this speed when launching.
@export var landing_burst_strength: float = 1.0 ## 0-1 landing smoke burst strength.

@export_group("Speed Feedback")
@export var wind_speed_threshold: float = 12.0 ## Speed (m/s) where wind streaks start.
@export var wind_max_amount_ratio: float = 1.0 ## Max wind streak density (0-1).

var dust_active: bool = false ## For the debug HUD.
var speed_feedback_active: bool = false ## For the debug HUD.
var active_skid_marks: int = 0 ## For the debug HUD (ribbon samples).

var _cart: CartPlayer
var _dust: GPUParticles3D
var _dust_burst: GPUParticles3D
var _wind: GPUParticles3D
var _camera: Camera3D

@onready var _trail_left: SkidTrail = $SkidTrailLeft
@onready var _trail_right: SkidTrail = $SkidTrailRight
@onready var _engine_audio: AudioStreamPlayer3D = $EngineAudio
@onready var _skid_audio: AudioStreamPlayer3D = $SkidAudio
@onready var _impact_audio: AudioStreamPlayer3D = $ImpactAudio
@onready var _thud_audio: AudioStreamPlayer3D = $ThudAudio


func _ready() -> void:
	add_to_group("cart_feedback")
	_cart = get_parent() as CartPlayer
	_dust = $Dust as GPUParticles3D
	_dust_burst = $DustBurst as GPUParticles3D
	_wind = $WindStreaks as GPUParticles3D
	_camera = get_viewport().get_camera_3d()
	if _cart != null:
		if _trail_left != null:
			_trail_left.set_excluded_body(_cart.get_rid())
		if _trail_right != null:
			_trail_right.set_excluded_body(_cart.get_rid())


func _physics_process(_delta: float) -> void:
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
	_update_skid_marks(speed, grounded, drifting, handbraking, steering, braking)
	_update_smoke(speed, grounded, drifting, handbraking, accelerating)
	_update_speed_feedback(speed)
	_update_audio(speed, grounded, drifting, handbraking)


func _update_skid_marks(speed: float, grounded: bool, drifting: bool, handbraking: bool,
		steering: float, braking: bool) -> void:
	if _trail_left == null or _trail_right == null:
		active_skid_marks = 0
		return
	var should_skid: bool = enable_skid_marks and grounded and speed > skid_min_speed
	if should_skid:
		var hard_braking: bool = braking and speed > skid_hard_brake_speed
		var sharp_turn: bool = absf(steering) > skid_sharp_steer and speed > skid_min_speed * 2.0
		should_skid = drifting or handbraking or hard_braking or sharp_turn
	if not should_skid:
		_trail_left.break_trail()
		_trail_right.break_trail()
		active_skid_marks = _trail_left.point_count() + _trail_right.point_count()
		return
	# World-space samples at the rear wheel contact points.
	var body: Transform3D = _cart.global_transform
	var base: Vector3 = global_position + body.basis.z * wheel_offset.y
	var left: Vector3 = base - body.basis.x * wheel_offset.x
	var right: Vector3 = base + body.basis.x * wheel_offset.x
	_trail_left.add_sample(left)
	_trail_right.add_sample(right)
	active_skid_marks = _trail_left.point_count() + _trail_right.point_count()


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
	## Called by the player when hitting something solid: crash smoke + sound.
	if not enable_collision_feedback:
		return
	if _dust_burst != null and enable_dust:
		_dust_burst.amount_ratio = clampf(0.6 + impact_factor * 0.5, 0.3, 1.0)
		_dust_burst.restart()
	if _impact_audio != null and enable_audio and _impact_audio.stream != null:
		_impact_audio.pitch_scale = randf_range(0.9, 1.1)
		_impact_audio.play()


func on_landing(fall_speed: float) -> void:
	## Called by the player on touchdown after a jump: landing puff + thud.
	if _dust_burst != null and enable_dust:
		_dust_burst.amount_ratio = clampf(landing_burst_strength * clampf(fall_speed * 0.12, 0.35, 1.0), 0.2, 1.0)
		_dust_burst.restart()
	if _thud_audio != null and enable_audio and _thud_audio.stream != null:
		_thud_audio.pitch_scale = randf_range(0.95, 1.05)
		_thud_audio.play()


func reset_feedback() -> void:
	## Clears every effect and audio state (used by the cart reset).
	if _trail_left != null:
		_trail_left.clear_trail()
	if _trail_right != null:
		_trail_right.clear_trail()
	if _dust != null:
		_dust.emitting = false
	if _dust_burst != null:
		_dust_burst.emitting = false
	if _wind != null:
		_wind.emitting = false
	if _skid_audio != null:
		_skid_audio.stream_paused = true
	dust_active = false
	speed_feedback_active = false
	active_skid_marks = 0
