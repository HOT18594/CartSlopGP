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
@export var max_fov: float = 82.0 ## FOV ceiling.
@export var fov_speed_multiplier: float = 12.0 ## Extra FOV degrees at full speed.
@export var camera_distance: float = 6.5 ## Boom length at rest (m).
@export var max_camera_distance: float = 8.0 ## Boom length cap (m).
@export var speed_distance_multiplier: float = 1.2 ## Extra boom length at full speed (m).
@export var camera_height: float = 1.4 ## Boom pivot height (m).
@export var speed_height_drop: float = 0.3 ## Pivot lowering at full speed (m).

@export_group("Shake")
@export var shake_decay: float = 5.5 ## Shake decay speed (higher = shorter shake).
@export var shake_max_offset: float = 0.14 ## Max view shake (m). Kept small and smooth.

var current_fov: float = 70.0 ## Live FOV, for the debug HUD.

var _cart: CartPlayer
var _camera: Camera3D
var _base_pitch: float = 0.0
var _yaw_smooth: float = 0.0
var _speed_smooth: float = 0.0
var _shake: float = 0.0
var _lag_z: float = 0.0


func _ready() -> void:
	add_to_group("camera_rig")
	_cart = get_parent() as CartPlayer
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
	# Speed response: wider FOV, longer boom, slightly lower pivot.
	current_fov = lerpf(current_fov, minf(base_fov + fov_speed_multiplier * speed_frac, max_fov) + _cart.boost_visual * _cart.boost_fov_bonus, 1.0 - exp(-4.0 * delta))
	_camera.fov = current_fov
	# Position lag: folded into the boom length so the SpringArm keeps
	# placing the camera and its collision keeps working.
	var accel_proxy: float = clampf((speed - _speed_smooth) * 0.15, -0.2, position_lag)
	_lag_z = lerpf(_lag_z, accel_proxy, 1.0 - exp(-5.0 * delta))
	var target_length: float = minf(camera_distance + speed_distance_multiplier * speed_frac, max_camera_distance) + _lag_z
	spring_length = lerpf(spring_length, target_length, 1.0 - exp(-4.0 * delta))
	position.y = lerpf(position.y, camera_height - speed_height_drop * speed_frac, 1.0 - exp(-4.0 * delta))
	# Shake: decays smoothly; applied as view offsets, never as transforms,
	# so it cannot fight the SpringArm's child placement.
	_shake *= exp(-shake_decay * delta)
	if _shake < 0.005:
		_shake = 0.0
	if _shake > 0.0:
		_camera.h_offset = randf_range(-1.0, 1.0) * shake_max_offset * _shake
		_camera.v_offset = randf_range(-1.0, 1.0) * shake_max_offset * _shake
	else:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0


func _update_yaw(delta: float) -> void:
	var body_yaw: float = _cart.global_rotation.y
	var target_yaw: float = body_yaw
	var vel_h: Vector3 = Vector3(_cart.velocity.x, 0.0, _cart.velocity.z)
	if vel_h.length() > 2.0 and look_ahead_strength > 0.0:
		var vel_yaw: float = atan2(-vel_h.x, -vel_h.z)
		target_yaw = lerp_angle(body_yaw, vel_yaw, clampf(look_ahead_strength, 0.0, 1.0))
	var steer_input: float = Input.get_axis("steer_right", "steer_left")
	target_yaw += steer_input * steer_look_ahead_strength
	_yaw_smooth = lerp_angle(_yaw_smooth, target_yaw, 1.0 - exp(-smoothing_speed * delta))
	rotation = Vector3(_base_pitch, wrapf(_yaw_smooth - body_yaw, -PI, PI), 0.0)


func add_shake(amount: float) -> void:
	## Called by the cart on impacts and hard landings.
	_shake = minf(_shake + amount, 1.0)


func reset_camera() -> void:
	## Snap everything back to defaults (used by the cart's reset).
	_shake = 0.0
	_lag_z = 0.0
	if _cart != null:
		_yaw_smooth = _cart.global_rotation.y
		_speed_smooth = _cart.velocity.length()
	rotation = Vector3(_base_pitch, 0.0, 0.0)
	if _camera != null:
		_camera.fov = base_fov
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
	current_fov = base_fov
	spring_length = camera_distance
	position.y = camera_height
