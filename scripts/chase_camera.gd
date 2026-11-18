class_name ChaseCamera
extends SpringArm3D
## Chase camera boom: yaw lag + lookahead, speed-based FOV/distance/height,
## smooth shake on impacts and landings. The Camera3D sits under this node.

@export_group("Smoothing")
@export var smoothing_speed: float = 5.0 ## How fast the boom yaw follows (higher = tighter).
@export var look_ahead_strength: float = 0.35 ## How much the camera leads toward the travel direction (0-1).
@export var steer_look_ahead_strength: float = 0.22 ## Extra yaw (radians) toward the steering direction.
@export var position_lag: float = 0.35 ## Max camera pull-back under acceleration (m).

@export_group("Speed Response")
@export var base_fov: float = 70.0 ## FOV at standstill.
@export var max_fov: float = 102.0 ## Hard FOV ceiling; speed + boost + punches never exceed it.
@export var fov_speed_multiplier: float = 13.5 ## Extra FOV degrees at full speed.
@export var camera_distance: float = 6.5 ## Boom length at rest (m).
@export var max_camera_distance: float = 8.0 ## Boom length cap (m).
@export var speed_distance_multiplier: float = 1.2 ## Extra boom length at full speed (m).
@export var camera_height: float = 1.4 ## Boom pivot height (m).
@export var speed_height_drop: float = 0.34 ## Pivot lowering at full speed (m).
@export var speed_pitch_lift: float = 0.048 ## Radians pitch flattens/tightens at top speed & boost.

@export_group("Shake")
@export var shake_decay: float = 6.5 ## Trauma decay speed (higher = shorter shake).
@export var shake_max_offset: float = 0.16 ## Max view shake at full trauma (m).
@export var impact_shake_scale: float = 1.0 ## Multiplier on every add_shake() request.

@export_group("Feel")
@export var bank_strength: float = 0.042 ## Camera roll into normal corners (radians).
@export var drift_bank_min: float = 0.080 ## Minimum camera roll into a committed drift (~4.6 deg).
@export var drift_bank_max: float = 0.105 ## Maximum camera roll into a committed drift (~6.0 deg).
@export var drift_peek_offset: float = 0.42 ## Horizontal framing peek (m) toward the inside of a drift.
@export var vertical_lag: float = 0.06 ## Camera height lag against vertical speed.
@export var vertical_lag_max: float = 0.45 ## Max height lag while jumping/falling (m).
@export var fov_punch_decay: float = 7.0 ## How fast a punch_fov() kick fades (higher = snappier).

var current_fov: float = 70.0 ## Live FOV, for the debug HUD.

var _cart: CartPlayer
var _camera: Camera3D
var _base_pitch: float = 0.0
var _pitch_offset: float = 0.0
var _yaw_smooth: float = 0.0
var _speed_smooth: float = 0.0
var _smoothed_fov: float = 70.0 ## Exponentially smoothed base+speed+boost FOV before punch.
var _trauma: float = 0.0 ## 0-1 impact energy; actual shake is trauma squared.
var _shake_time: float = 0.0
var _fov_punch: float = 0.0 ## Transient FOV offset added AFTER smoothing for frame-1 snap.
var _lag_z: float = 0.0
var _roll: float = 0.0
var _drift_h_offset: float = 0.0


func _ready() -> void:
	add_to_group("camera_rig")
	margin = 0.25
	_cart = get_parent() as CartPlayer
	if _cart != null:
		add_excluded_object(_cart.get_rid())
	_camera = get_node_or_null("Camera3D") as Camera3D
	_base_pitch = rotation.x
	_yaw_smooth = global_rotation.y
	if _cart != null:
		_speed_smooth = _cart.velocity.length()
	_smoothed_fov = base_fov
	current_fov = base_fov


func _process(delta: float) -> void:
	if _cart == null or _camera == null:
		return
	var speed: float = _cart.velocity.length()
	_speed_smooth = lerpf(_speed_smooth, speed, 1.0 - exp(-3.5 * delta))
	var ref_speed: float = maxf(_cart.max_speed, 0.1)
	var speed_frac: float = clampf(_speed_smooth / ref_speed, 0.0, 1.0)
	var motion_scale: float = 0.2 if GameSettings.reduce_motion else 1.0
	var roll_scale: float = 0.35 if GameSettings.reduce_motion else 1.0
	var shake_scale: float = clampf(GameSettings.camera_shake, 0.0, 1.5) * motion_scale
	_update_yaw(delta, speed_frac, motion_scale)

	# Speed response: smooth base+speed+boost FOV first, then add _fov_punch
	# AFTER smoothing so boost and mini-turbo FOV kicks snap immediately on frame 1!
	var boost_fov: float = _cart.boost_visual * _cart.boost_fov_bonus * motion_scale
	var target_fov: float = clampf(
		base_fov + fov_speed_multiplier * speed_frac + boost_fov, 60.0, max_fov)
	_smoothed_fov = lerpf(_smoothed_fov, target_fov, 1.0 - exp(-5.0 * delta))
	var effective_punch: float = _fov_punch * motion_scale
	_camera.fov = clampf(_smoothed_fov + effective_punch, 60.0, max_fov)
	current_fov = _camera.fov
	_fov_punch = lerpf(_fov_punch, 0.0, 1.0 - exp(-fov_punch_decay * delta))

	# Position lag: folded into the boom length so the SpringArm keeps
	# placing the camera and its collision keeps working.
	var accel_proxy: float = clampf((speed - _speed_smooth) * 0.15, -0.2, position_lag)
	_lag_z = lerpf(_lag_z, accel_proxy, 1.0 - exp(-5.0 * delta))
	var boost_tuck: float = _cart.boost_visual * 0.28 * motion_scale
	var target_length: float = clampf(
		camera_distance + speed_distance_multiplier * speed_frac - boost_tuck,
		camera_distance * 0.85, max_camera_distance) + _lag_z
	spring_length = lerpf(spring_length, target_length, 1.0 - exp(-4.5 * delta))
	var boost_drop: float = _cart.boost_visual * 0.10 * motion_scale
	var vertical_target: float = camera_height - speed_height_drop * speed_frac - boost_drop \
		+ clampf(-_cart.velocity.y * vertical_lag, -vertical_lag_max, vertical_lag_max)
	position.y = lerpf(position.y, vertical_target, 1.0 - exp(-5.5 * delta))

	# Drift Angle Peek & Bank: frame inside the apex (~+-0.42 m) and bank
	# heroically (4.5-6.0 deg / 0.08-0.105 rad) during a committed drift.
	var drift_dir: int = _cart.get_drift_direction()
	var grounded_drift: bool = drift_dir != 0 and (_cart.is_on_floor() or _cart.is_drifting)
	var peek_target: float = -float(drift_dir) * drift_peek_offset * motion_scale \
		if grounded_drift else 0.0
	_drift_h_offset = lerpf(_drift_h_offset, peek_target, 1.0 - exp(-6.0 * delta))

	var lateral_speed: float = _cart.velocity.dot(_cart.global_transform.basis.x)
	var steer: float = _cart.steer_smoothed
	var roll_target: float = 0.0
	if grounded_drift:
		var drift_bank_mag: float = lerpf(
			drift_bank_min, drift_bank_max, clampf(_cart.slide_amount, 0.0, 1.0))
		roll_target = float(drift_dir) * drift_bank_mag * roll_scale
	else:
		var normal_roll: float = steer * bank_strength * 0.65 * speed_frac \
			+ clampf(lateral_speed / 9.0, -1.0, 1.0) * bank_strength * 0.55
		roll_target = clampf(normal_roll * roll_scale, -bank_strength, bank_strength)
	_roll = lerpf(_roll, roll_target, 1.0 - exp(-6.5 * delta))

	# Trauma-squared shake: light taps barely register, big hits punch hard.
	_trauma *= exp(-shake_decay * delta)
	_shake_time += delta
	if _trauma < 0.004:
		_trauma = 0.0
	var shake_strength: float = _trauma * _trauma * shake_scale
	var roll_applied: float = clampf(_roll, -0.13, 0.13)
	if shake_strength > 0.0001:
		var noise_x: float = sin(_shake_time * 41.0) * sin(_shake_time * 17.3 + 1.7)
		var noise_y: float = cos(_shake_time * 37.7 + 0.4) * sin(_shake_time * 13.1)
		var noise_z: float = sin(_shake_time * 29.3 + 2.1) * cos(_shake_time * 11.7)
		_camera.h_offset = _drift_h_offset + noise_x * shake_max_offset * shake_strength
		_camera.v_offset = noise_y * shake_max_offset * shake_strength
		roll_applied = clampf(roll_applied + noise_z * 0.025 * shake_strength, -0.15, 0.15)
	else:
		_camera.h_offset = _drift_h_offset
		_camera.v_offset = 0.0
	_camera.rotation.z = roll_applied


func _update_yaw(delta: float, speed_frac: float, motion_scale: float) -> void:
	var body_yaw: float = _cart.global_rotation.y
	var target_yaw: float = body_yaw
	var vel_h: Vector3 = Vector3(_cart.velocity.x, 0.0, _cart.velocity.z)
	if vel_h.length() > 2.0 and look_ahead_strength > 0.0:
		var vel_yaw: float = atan2(-vel_h.x, -vel_h.z)
		target_yaw = lerp_angle(body_yaw, vel_yaw, clampf(look_ahead_strength, 0.0, 1.0))
	var steer_input: float = _cart.steer_smoothed
	var ground_scale: float = 1.0 if _cart.is_on_floor() else 0.18
	var speed_scale: float = clampf(_cart.velocity.length() / 7.0, 0.0, 1.0)
	var drift_dir: int = _cart.get_drift_direction()
	if drift_dir != 0 and _cart.is_on_floor():
		target_yaw += float(drift_dir) * steer_look_ahead_strength * 0.85 * speed_scale
	else:
		target_yaw += steer_input * steer_look_ahead_strength * ground_scale * speed_scale
	var dynamic_smooth: float = smoothing_speed + (_cart.boost_visual * 1.4 + speed_frac * 0.8)
	_yaw_smooth = lerp_angle(_yaw_smooth, target_yaw, 1.0 - exp(-dynamic_smooth * delta))
	var target_pitch_lift: float = (speed_frac * 0.65 + _cart.boost_visual * 0.35) \
		* speed_pitch_lift * motion_scale
	_pitch_offset = lerpf(_pitch_offset, target_pitch_lift, 1.0 - exp(-5.0 * delta))
	rotation = Vector3(_base_pitch + _pitch_offset, wrapf(_yaw_smooth - body_yaw, -PI, PI), 0.0)


func add_shake(amount: float) -> void:
	## Called by the cart on impacts and hard landings. `amount` is trauma in
	## 0-1 units; the visible shake is trauma squared, so small taps stay subtle.
	if amount <= 0.0:
		return
	_trauma = clampf(_trauma + amount * impact_shake_scale, 0.0, 1.0)


func punch_fov(degrees: float) -> void:
	## Transient FOV kick (positive = zoom out, negative = punch in). Applied
	## after smoothing so frame 1 snaps immediately, then decays to 0.
	_fov_punch = clampf(_fov_punch + degrees, -12.0, 14.0)


func reset_camera() -> void:
	## Snap everything back to defaults (used by the cart's reset).
	_trauma = 0.0
	_fov_punch = 0.0
	_lag_z = 0.0
	_roll = 0.0
	_drift_h_offset = 0.0
	_pitch_offset = 0.0
	_smoothed_fov = base_fov
	if _cart != null:
		_yaw_smooth = _cart.global_rotation.y
		_speed_smooth = _cart.velocity.length()
	rotation = Vector3(_base_pitch, 0.0, 0.0)
	if _camera != null:
		_camera.fov = base_fov
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
		_camera.rotation.z = 0.0
	current_fov = base_fov
	spring_length = camera_distance
	position.y = camera_height
