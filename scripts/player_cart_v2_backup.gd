# class_name removed: would clash with the live script global class
extends CharacterBody3D
## Arcade cart controller v2: velocity-based driving with momentum, drift,
## air control, collision recoil, and visual squash & stretch.
##
## Inputs (project input map): accelerate, brake, steer_left, steer_right,
## handbrake, reset_cart.

@export_group("Speed")
@export var max_speed: float = 18.0 ## Fastest forward speed (m/s).
@export var reverse_speed: float = 7.0 ## Fastest reverse speed (m/s).
@export var acceleration: float = 16.0 ## Base speed gain per second (m/s^2), tapers near top speed.
@export var brake_power: float = 26.0 ## Speed removed per second while braking (m/s^2).
@export var friction: float = 6.0 ## Speed lost per second when coasting (m/s^2).
@export var min_turn_speed: float = 3.0 ## Speed (m/s) at which steering reaches full authority.

@export_group("Grip & Drift")
@export var lateral_grip: float = 10.0 ## How fast sideways slip is cancelled (m/s^2).
@export var drift_grip: float = 2.5 ## Lateral grip while the handbrake is held (m/s^2).
@export var drift_detection_threshold: float = 2.0 ## Sideways speed (m/s) that counts as drifting.
@export var landing_stability_strength: float = 0.6 ## Fraction of sideways speed removed on landing (0-1).

@export_group("Steering & Air")
@export var steering_speed: float = 2.6 ## Max yaw rate (radians/second).
@export var high_speed_steering_scale: float = 0.65 ## Steering multiplier at top speed (0-1).
@export var air_control_strength: float = 0.35 ## Steering authority while airborne (0-1).
@export var gravity: float = 22.0 ## Downward acceleration (m/s^2).
@export var extra_fall_gravity: float = 1.6 ## Gravity multiplier while falling, for snappy landings.

@export_group("Collision Recoil")
@export var impact_speed_loss: float = 0.35 ## Fraction of impact speed lost on a hit (0-1).
@export var impact_recoil: float = 0.45 ## Fraction of impact speed bounced away from the surface.
@export var max_recoil_speed: float = 3.0 ## Cap on the recoil impulse (m/s).
@export var min_impact_speed: float = 2.5 ## Impacts slower than this are ignored (m/s).
@export var impact_cooldown: float = 0.25 ## Seconds between impact effects.

@export_group("Visual Squash & Stretch")
@export var squash_amount: float = 0.08 ## Max visual scale deviation (0.08 = 8%).
@export var squash_smooth_speed: float = 9.0 ## How fast the mesh returns to normal.
@export var mesh_tilt_amount: float = 0.09 ## Lean into turns (radians).
@export var mesh_pitch_amount: float = 0.05 ## Nose up/down under throttle/brake (radians).

var is_drifting: bool = false ## True while sliding sideways on the ground (for the HUD).

var _spawn_transform: Transform3D = Transform3D.IDENTITY
var _prev_velocity: Vector3 = Vector3.ZERO
var _impact_timer: float = 0.0
var _squash_impulse: float = 0.0 ## Landing/impact squash (0-1).
var _stretch_impulse: float = 0.0 ## Ramp launch stretch (0-1).
var _was_on_floor: bool = true

@onready var _mesh_root: Node3D = $MeshRoot
@onready var _camera_rig: ChaseCamera = $CameraArm


func _ready() -> void:
	add_to_group("player")
	var spawn_point: Node3D = get_tree().get_first_node_in_group("spawn_point") as Node3D
	if spawn_point != null:
		_spawn_transform = spawn_point.global_transform
	else:
		_spawn_transform = global_transform


func _physics_process(delta: float) -> void:
	_impact_timer = maxf(_impact_timer - delta, 0.0)
	var steer_input: float = Input.get_axis("steer_right", "steer_left")
	_prev_velocity = velocity
	_update_drive(delta)
	_apply_steering(steer_input, delta)
	velocity.y -= gravity * (extra_fall_gravity if velocity.y < 0.0 else 1.0) * delta
	move_and_slide()
	_process_collisions()
	_process_landing_and_launch()
	_update_visuals(steer_input, delta)
	if Input.is_action_just_pressed("reset_cart"):
		_reset_cart()
	_was_on_floor = is_on_floor()


func _update_drive(delta: float) -> void:
	## Engine, brake, handbrake and grip, all in the cart's local frame.
	var forward_dir: Vector3 = -global_transform.basis.z
	var right_dir: Vector3 = global_transform.basis.x
	var fwd_speed: float = velocity.dot(forward_dir)
	var lat_speed: float = velocity.dot(right_dir)
	if Input.is_action_pressed("accelerate"):
		# Acceleration tapers near top speed: strong launch, gentle finish.
		var accel_scale: float = clampf(1.0 - fwd_speed / max_speed, 0.25, 1.0)
		fwd_speed = move_toward(fwd_speed, max_speed, acceleration * accel_scale * delta)
	elif Input.is_action_pressed("brake"):
		if fwd_speed > 0.5:
			fwd_speed = move_toward(fwd_speed, 0.0, brake_power * delta)
		else:
			fwd_speed = move_toward(fwd_speed, -reverse_speed, acceleration * 0.6 * delta)
	else:
		# No input: keep rolling momentum, decay slowly.
		fwd_speed = move_toward(fwd_speed, 0.0, friction * delta)
	var grip: float = lateral_grip
	if Input.is_action_pressed("handbrake"):
		grip = drift_grip
		fwd_speed = move_toward(fwd_speed, 0.0, brake_power * 0.4 * delta)
	if not is_on_floor():
		grip *= 0.25 # Loose in the air so drifts carry through jumps.
	lat_speed = move_toward(lat_speed, 0.0, grip * delta)
	velocity = forward_dir * fwd_speed + right_dir * lat_speed + Vector3.UP * velocity.y
	is_drifting = is_on_floor() and absf(lat_speed) > drift_detection_threshold


func _apply_steering(steer_input: float, delta: float) -> void:
	## Speed-sensitive yaw; inverts in reverse, reduced authority in the air.
	var forward_dir: Vector3 = -global_transform.basis.z
	var fwd_speed: float = velocity.dot(forward_dir)
	var speed_frac: float = clampf(absf(fwd_speed) / max_speed, 0.0, 1.0)
	var start_factor: float = clampf(absf(fwd_speed) / min_turn_speed, 0.0, 1.0)
	var high_speed_factor: float = lerpf(1.0, high_speed_steering_scale, speed_frac)
	var authority: float = start_factor * high_speed_factor
	if not is_on_floor():
		authority *= air_control_strength
	rotate_y(steer_input * steering_speed * authority * signf(fwd_speed) * delta)


func _process_collisions() -> void:
	## Recoil + feedback when ramming something solid. Subtle by design.
	if _impact_timer > 0.0:
		return
	for i in get_slide_collision_count():
		var collision: KinematicCollision3D = get_slide_collision(i)
		var normal: Vector3 = collision.get_normal()
		if normal.y > 0.7:
			continue # Floor contact, not a wall hit.
		var impact_speed: float = -_prev_velocity.dot(normal)
		if impact_speed < min_impact_speed:
			continue
		var impact_factor: float = clampf(impact_speed / max_speed, 0.0, 1.0)
		# Small bounce away from the surface, capped so it never launches.
		velocity += normal * minf(impact_speed * impact_recoil, max_recoil_speed)
		# Shed some forward speed.
		var forward_dir: Vector3 = -global_transform.basis.z
		var right_dir: Vector3 = global_transform.basis.x
		var fwd_speed: float = velocity.dot(forward_dir)
		var lat_speed: float = velocity.dot(right_dir)
		var loss: float = impact_speed * impact_speed_loss
		if fwd_speed > 0.0:
			fwd_speed = maxf(fwd_speed - loss, 0.0)
		else:
			fwd_speed = minf(fwd_speed + loss, 0.0)
		velocity = forward_dir * fwd_speed + right_dir * lat_speed + Vector3.UP * velocity.y
		_impact_timer = impact_cooldown
		_squash_impulse = maxf(_squash_impulse, clampf(impact_factor * 1.2, 0.3, 1.0))
		if _camera_rig != null:
			_camera_rig.add_shake(0.15 + 0.5 * impact_factor)
		break # One impact per cooldown is enough.


func _process_landing_and_launch() -> void:
	## Squash on landing (plus a grip assist), stretch when leaving ramps.
	var just_landed: bool = (not _was_on_floor) and is_on_floor()
	var just_launched: bool = _was_on_floor and (not is_on_floor())
	if just_landed:
		var fall_speed: float = maxf(-_prev_velocity.y, 0.0)
		_squash_impulse = maxf(_squash_impulse, clampf(fall_speed * 0.12, 0.15, 1.0))
		if _camera_rig != null:
			_camera_rig.add_shake(clampf(fall_speed * 0.03, 0.0, 0.3))
		# Stability assist: bleed some sideways speed on touchdown.
		var forward_dir: Vector3 = -global_transform.basis.z
		var right_dir: Vector3 = global_transform.basis.x
		var lat_speed: float = velocity.dot(right_dir)
		lat_speed *= 1.0 - landing_stability_strength
		velocity = forward_dir * velocity.dot(forward_dir) + right_dir * lat_speed + Vector3.UP * velocity.y
	elif just_launched and _prev_velocity.y > 2.0:
		_stretch_impulse = maxf(_stretch_impulse, clampf(_prev_velocity.y * 0.1, 0.2, 1.0))


func _update_visuals(steer_input: float, delta: float) -> void:
	## Squash & stretch on MeshRoot only - the collider is never touched.
	var forward_dir: Vector3 = -global_transform.basis.z
	var fwd_speed: float = velocity.dot(forward_dir)
	var speed_frac: float = clampf(absf(fwd_speed) / max_speed, 0.0, 1.0)
	_squash_impulse = move_toward(_squash_impulse, 0.0, 2.5 * delta)
	_stretch_impulse = move_toward(_stretch_impulse, 0.0, 2.5 * delta)
	var accel_stretch: float = 0.0
	var brake_squash: float = 0.0
	if Input.is_action_pressed("accelerate"):
		accel_stretch = 1.0 - speed_frac # Strongest at launch.
	elif Input.is_action_pressed("brake"):
		brake_squash = speed_frac
	var stretch: float = (accel_stretch * 0.6 + _stretch_impulse) * squash_amount
	var squash: float = (brake_squash * 0.6 + _squash_impulse) * squash_amount
	var target_scale: Vector3 = Vector3(
		1.0 - stretch * 0.4 + squash * 0.5,
		1.0 - stretch * 0.3 - squash,
		1.0 + stretch - squash * 0.5)
	target_scale = target_scale.clamp(
		Vector3.ONE * (1.0 - squash_amount), Vector3.ONE * (1.0 + squash_amount))
	var blend: float = 1.0 - exp(-squash_smooth_speed * delta)
	_mesh_root.scale = _mesh_root.scale.lerp(target_scale, blend)
	var target_roll: float = steer_input * mesh_tilt_amount * clampf(fwd_speed / max_speed, -1.0, 1.0)
	var target_pitch: float = 0.0
	if Input.is_action_pressed("accelerate"):
		target_pitch = -mesh_pitch_amount * speed_frac # Nose up.
	elif Input.is_action_pressed("brake"):
		target_pitch = mesh_pitch_amount * speed_frac # Nose down.
	var lean_blend: float = 1.0 - exp(-10.0 * delta)
	_mesh_root.rotation.z = lerpf(_mesh_root.rotation.z, target_roll, lean_blend)
	_mesh_root.rotation.x = lerpf(_mesh_root.rotation.x, target_pitch, lean_blend)


func _reset_cart() -> void:
	## Full reset: position, motion, visual warp, camera state.
	velocity = Vector3.ZERO
	global_transform = _spawn_transform
	_mesh_root.scale = Vector3.ONE
	_mesh_root.rotation = Vector3.ZERO
	_squash_impulse = 0.0
	_stretch_impulse = 0.0
	_impact_timer = 0.0
	is_drifting = false
	if _camera_rig != null:
		_camera_rig.reset_camera()
