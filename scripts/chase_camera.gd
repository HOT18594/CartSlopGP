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
@export var max_fov: float = 88.0 ## Hard FOV ceiling; speed + boost + punches never exceed it.
@export var fov_speed_multiplier: float = 12.0 ## Extra FOV degrees at full speed.
@export var camera_distance: float = 6.5 ## Boom length at rest (m).
@export var max_camera_distance: float = 8.0 ## Boom length cap (m).
@export var speed_distance_multiplier: float = 1.2 ## Extra boom length at full speed (m).
@export var camera_height: float = 1.4 ## Boom pivot height (m).
@export var speed_height_drop: float = 0.3 ## Pivot lowering at full speed (m).

@export_group("Shake")
@export var shake_decay: float = 6.5 ## Trauma decay speed (higher = shorter shake).
@export var shake_max_offset: float = 0.16 ## Max view shake at full trauma (m).
@export var impact_shake_scale: float = 1.0 ## Multiplier on every add_shake() request.

@export_group("Feel")
@export var bank_strength: float = 0.032 ## Camera roll into corners (radians at full slip).
@export var vertical_lag: float = 0.06 ## Camera height lag against vertical speed.
@export var vertical_lag_max: float = 0.45 ## Max height lag while jumping/falling (m).
@export var fov_punch_decay: float = 7.0 ## How fast a punch_fov() kick fades (higher = snappier).

var current_fov: float = 70.0 ## Live FOV, for the debug HUD.

var _cart: CartPlayer
var _camera: Camera3D
var _base_pitch: float = 0.0
var _yaw_smooth: float = 0.0
var _speed_smooth: float = 0.0
var _trauma: float = 0.0 ## 0-1 impact energy; actual shake is trauma squared.
var _shake_time: float = 0.0
var _fov_punch: float = 0.0 ## Transient FOV offset added by punch_fov().
var _lag_z: float = 0.0
var _roll: float = 0.0


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
	current_fov = base_fov


func _process(delta: float) -> void:
	if _cart == null or _camera == null:
		return
	var speed: float = _cart.velocity.length()
	_speed_smooth = lerpf(_speed_smooth, speed, 1.0 - exp(-3.0 * delta))
	var ref_speed: float = maxf(_cart.max_speed, 0.1)
	var speed_frac: float = clampf(_speed_smooth / ref_speed, 0.0, 1.0)
	_update_yaw(delta)
	var motion_scale: float = 0.2 if GameSettings.reduce_motion else 1.0
	var roll_scale: float = 0.35 if GameSettings.reduce_motion else 1.0
	var shake_scale: float = clampf(GameSettings.camera_shake, 0.0, 1.5) * motion_scale
	# Speed response: wider FOV, longer boom, slightly lower pivot. The boost
	# kick and any punch_fov() offset are clamped by the same max_fov ceiling.
	_fov_punch = lerpf(_fov_punch, 0.0, 1.0 - exp(-fov_punch_decay * delta))
	var boost_fov: float = _cart.boost_visual * _cart.boost_fov_bonus * motion_scale
	var target_fov: float = minf(base_fov + fov_speed_multiplier * speed_frac + boost_fov, max_fov)
	target_fov = clampf(target_fov + _fov_punch * motion_scale, base_fov - 10.0, max_fov)
	current_fov = lerpf(current_fov, target_fov, 1.0 - exp(-4.0 * delta))
	_camera.fov = current_fov
	# Position lag: folded into the boom length so the SpringArm keeps
	# placing the camera and its collision keeps working.
	var accel_proxy: float = clampf((speed - _speed_smooth) * 0.15, -0.2, position_lag)
	_lag_z = lerpf(_lag_z, accel_proxy, 1.0 - exp(-5.0 * delta))
	var target_length: float = minf(camera_distance + speed_distance_multiplier * speed_frac, max_camera_distance) + _lag_z
	spring_length = lerpf(spring_length, target_length, 1.0 - exp(-4.0 * delta))
	var vertical_target: float = camera_height - speed_height_drop * speed_frac 		+ clampf(-_cart.velocity.y * vertical_lag, -vertical_lag_max, vertical_lag_max)
	position.y = lerpf(position.y, vertical_target, 1.0 - exp(-5.0 * delta))

	# Bank into drifts and steering for a softer, more dynamic chase cam.
	var lateral_speed: float = _cart.velocity.dot(_cart.global_transform.basis.x)
	var steer: float = _cart.steer_smoothed
	var speed_frac_roll: float = clampf(_speed_smooth / maxf(_cart.max_speed, 0.1), 0.0, 1.0)
	var roll_target: float = -(clampf(-lateral_speed / 9.0, -1.0, 1.0) * bank_strength) 		- steer * bank_strength * 0.45 * speed_frac_roll
	roll_target = clampf(roll_target * roll_scale, -bank_strength, bank_strength)
	_roll = lerpf(_roll, roll_target, 1.0 - exp(-4.5 * delta))
	# Trauma-squared shake: light taps barely register, big hits punch hard.
	# Applied as view offsets, never as transforms, so it cannot fight the
	# SpringArm's child placement.
	_trauma *= exp(-shake_decay * delta)
	_shake_time += delta
	if _trauma < 0.004:
		_trauma = 0.0
	var shake_strength: float = _trauma * _trauma * shake_scale
	var roll_applied: float = clampf(_roll, -0.04, 0.04)
	if shake_strength > 0.0001:
		# Layered sine noise instead of per-frame random: smooth, no jitter.
		var noise_x: float = sin(_shake_time * 41.0) * sin(_shake_time * 17.3 + 1.7)
		var noise_y: float = cos(_shake_time * 37.7 + 0.4) * sin(_shake_time * 13.1)
		var noise_z: float = sin(_shake_time * 29.3 + 2.1) * cos(_shake_time * 11.7)
		_camera.h_offset = noise_x * shake_max_offset * shake_strength
		_camera.v_offset = noise_y * shake_max_offset * shake_strength
		roll_applied = clampf(roll_applied + noise_z * 0.02 * shake_strength, -0.07, 0.07)
	else:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
	_camera.rotation.z = roll_applied


func _update_yaw(delta: float) -> void:
	var body_yaw: float = _cart.global_rotation.y
	var target_yaw: float = body_yaw
	var vel_h: Vector3 = Vector3(_cart.velocity.x, 0.0, _cart.velocity.z)
	if vel_h.length() > 2.0 and look_ahead_strength > 0.0:
		var vel_yaw: float = atan2(-vel_h.x, -vel_h.z)
		target_yaw = lerp_angle(body_yaw, vel_yaw, clampf(look_ahead_strength, 0.0, 1.0))
	var steer_input: float = _cart.steer_smoothed
	var ground_scale: float = 1.0 if _cart.is_on_floor() else 0.18
	var speed_scale: float = clampf(_cart.velocity.length() / 7.0, 0.0, 1.0)
	target_yaw += steer_input * steer_look_ahead_strength * ground_scale * speed_scale
	_yaw_smooth = lerp_angle(_yaw_smooth, target_yaw, 1.0 - exp(-smoothing_speed * delta))
	rotation = Vector3(_base_pitch, wrapf(_yaw_smooth - body_yaw, -PI, PI), 0.0)


func add_shake(amount: float) -> void:
	## Called by the cart on impacts and hard landings. `amount` is trauma in
	## 0-1 units; the visible shake is trauma squared, so small taps stay subtle.
	if amount <= 0.0:
		return
	_trauma = clampf(_trauma + amount * impact_shake_scale, 0.0, 1.0)


func punch_fov(degrees: float) -> void:
	## Transient FOV kick (positive = zoom out, negative = punch in). It decays
	## and is clamped to max_fov by _process, so it can never break the ceiling.
	_fov_punch = clampf(_fov_punch + degrees, -12.0, 12.0)


func reset_camera() -> void:
	## Snap everything back to defaults (used by the cart's reset).
	_trauma = 0.0
	_fov_punch = 0.0
	_lag_z = 0.0
	_roll = 0.0
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
