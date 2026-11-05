class_name CartPlayer
extends CharacterBody3D

enum CartState { DRIVING, AIRBORNE_TUMBLE, CRASHED, RECOVERY }
## Arcade cart controller with four-point terrain support, slope-aware driving,
## dynamic weight transfer, oriented compound collision shapes and air tumble.

const SUSPENSION_PIVOT_HEIGHT: float = 0.32

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
@export var air_control_strength: float = 0.25 ## Steering authority while airborne (0-1).
@export var gravity: float = 22.0 ## Downward acceleration (m/s^2).
@export var extra_fall_gravity: float = 1.6 ## Gravity multiplier while falling, for snappy landings.

@export_group("Collision Recoil")
@export var impact_speed_loss: float = 0.35 ## Fraction of impact speed lost on a hit (0-1).
@export var impact_recoil: float = 0.32 ## Fraction of impact speed bounced away from the surface.
@export var max_recoil_speed: float = 3.0 ## Cap on the recoil impulse (m/s).
@export var min_impact_speed: float = 2.5 ## Impacts slower than this are ignored (m/s).
@export var impact_cooldown: float = 0.25 ## Seconds between impact effects.
@export var impact_tilt_strength: float = 0.22 ## Angular suspension kick from a solid impact.

@export_group("Visual Squash & Stretch")
@export var squash_amount: float = 0.08 ## Max visual scale deviation (0.08 = 8%).
@export var squash_smooth_speed: float = 9.0 ## How fast the mesh returns to normal.
@export var mesh_tilt_amount: float = 0.14 ## Outward body roll from cornering and lateral acceleration.
@export var mesh_pitch_amount: float = 0.12 ## Nose lift/dive from acceleration and braking.

@export_group("Props")
@export var push_force: float = 4.0 ## Ram strength as the velocity change (m/s) given to a rammed prop at full cart speed.

@export_group("Boost")
@export var max_boost: float = 100.0 ## Boost meter capacity.
@export var boost_drain_per_second: float = 35.0 ## Meter drain while boosting.
@export var boost_regen_per_second: float = 12.0 ## Meter regen when not boosting.
@export var boost_regen_delay: float = 0.5 ## Seconds to wait after boosting before regen.
@export var boost_speed_multiplier: float = 1.35 ## Max speed multiplier while boosting.
@export var boost_acceleration_multiplier: float = 1.25 ## Acceleration multiplier while boosting.
@export var boost_fov_bonus: float = 6.0 ## Extra camera FOV while boosting.

@export_group("Airborne & Crash")
@export var enable_air_tumble: bool = true ## Simulated tumble on big airs.
@export var air_tumble_strength: float = 1.0 ## How violently the cart tumbles (0-2).
@export var airborne_time_threshold: float = 0.25 ## Air time (s) before a jump counts as a tumble.
@export var upside_down_dot_threshold: float = 0.35 ## Landing up-dot below this = crash.
@export var crash_cooldown: float = 1.2 ## Seconds of stunned sliding after a crash.
@export var auto_flip_duration: float = 0.6 ## Seconds to flip upright during recovery.

@export_group("Suspension & Terrain")
@export var slope_follow_strength: float = 1.0 ## 0-1: how strongly the chassis follows the support plane.
@export var slope_smooth_speed: float = 12.0 ## How quickly grounded suspension follows terrain.
@export var air_tilt_smooth_speed: float = 3.5 ## How quickly the chassis follows its flight arc.
@export var ledge_tip_amount: float = 0.68 ## Nose/downward tip when an axle loses support (radians).
@export var ledge_tip_smooth_speed: float = 5.5 ## Progressive tip response as wheels pass a ledge.
@export var wheel_half_track: float = 0.44 ## Half the distance between left and right wheel probes.
@export var wheelbase: float = 1.05 ## Distance between front and rear wheel probes.
@export var ground_probe_height: float = 0.5 ## Height above the cart origin to start support rays.
@export var ground_probe_length: float = 1.4 ## Downward support-ray length.
@export var suspension_stiffness: float = 75.0 ## Vertical and weight-transfer spring stiffness.
@export var suspension_damping: float = 10.0 ## Suspension spring damping.
@export var suspension_landing_dip: float = 0.35 ## Landing dip impulse scale.

var is_drifting: bool = false ## True while sliding sideways on the ground (for the HUD).
var current_state: CartState = CartState.DRIVING ## High-level state (for the HUD).
var current_state_name: String = "DRIVING" ## State name for the debug HUD.
var boost_amount: float = 100.0 ## Current boost meter (0..max_boost).
var boost_active: bool = false ## True while the boost is actually applied.
var boost_visual: float = 0.0 ## Smoothed 0-1 boost intensity for camera/audio.
var slide_amount: float = 0.0 ## 0-1 sideways-slide intensity (for the skid audio volume).

var _boost_regen_timer: float = 0.0
var _pad_burst_timer: float = 0.0
var _was_boosting: bool = false
var _air_time: float = 0.0
var _tumble_pitch: float = 0.0
var _tumble_roll: float = 0.0
var _tumble_pitch_rate: float = 0.0
var _tumble_roll_rate: float = 0.0
var _crash_timer: float = 0.0
var _recover_timer: float = 0.0
var _recover_from: Vector3 = Vector3.ZERO
var _base_pitch: float = 0.0
var _base_roll: float = 0.0
var _base_pitch_vel: float = 0.0
var _base_roll_vel: float = 0.0
var _longitudinal_accel: float = 0.0
var _lateral_accel: float = 0.0
var _slope_pitch: float = 0.0 ## Four-wheel support pitch, including ledge tip.
var _slope_roll: float = 0.0 ## Four-wheel support roll, including side drops.
var _susp_pos: float = 0.0
var _susp_vel: float = 0.0
var _support_count: int = 0
var _previous_support_count: int = 4
var _ground_normal: Vector3 = Vector3.UP
var _ground_support: Array[bool] = [false, false, false, false]
var _ground_heights: Array[float] = [0.0, 0.0, 0.0, 0.0]

var _spawn_transform: Transform3D = Transform3D.IDENTITY
var _frame_start_velocity: Vector3 = Vector3.ZERO
var _prev_velocity: Vector3 = Vector3.ZERO
var _impact_timer: float = 0.0
var _squash_impulse: float = 0.0
var _stretch_impulse: float = 0.0
var _was_on_floor: bool = true
var _push_cooldowns: Dictionary[int, float] = {}
var _pushable_spawn_transforms: Dictionary[int, Transform3D] = {}

@onready var _mesh_root: Node3D = $MeshRoot
@onready var _camera_rig: ChaseCamera = $CameraArm
@onready var _feedback: CartFeedback = $Feedback

var _collision_shapes: Array[CollisionShape3D] = []
var _collision_rest_transforms: Array[Transform3D] = []


func _ready() -> void:
	add_to_group("player")
	for child in get_children():
		if child is CollisionShape3D:
			_collision_shapes.append(child as CollisionShape3D)
			_collision_rest_transforms.append((child as CollisionShape3D).transform)
	var spawn_point: Node3D = get_tree().get_first_node_in_group("spawn_point") as Node3D
	if spawn_point != null:
		_spawn_transform = spawn_point.global_transform
	else:
		_spawn_transform = global_transform
	call_deferred("_collect_pushables")


func _collect_pushables() -> void:
	_pushable_spawn_transforms.clear()
	for node in get_tree().get_nodes_in_group("pushable"):
		var prop: Node3D = node as Node3D
		if prop != null:
			_pushable_spawn_transforms[prop.get_instance_id()] = prop.global_transform


func _physics_process(delta: float) -> void:
	_impact_timer = maxf(_impact_timer - delta, 0.0)
	_frame_start_velocity = velocity
	_update_boost(delta)
	var steer_input: float = Input.get_axis("steer_right", "steer_left")
	if current_state == CartState.CRASHED:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, friction * delta)
		velocity.y -= gravity * delta
	elif current_state == CartState.RECOVERY:
		velocity.y -= gravity * delta
	else:
		_update_drive(delta)
		_apply_steering(steer_input, delta)
		velocity.y -= gravity * (extra_fall_gravity if velocity.y < 0.0 else 1.0) * delta
	_prev_velocity = velocity
	move_and_slide()
	_push_pushables()
	_process_collisions()
	_process_landing_and_launch()
	_update_ground_tilt(delta)
	_update_tumble(steer_input, delta)
	_update_visuals(steer_input, delta)
	if global_position.y < -20.0:
		_reset_cart()
		return
	if Input.is_action_just_pressed("reset_cart"):
		_reset_cart()
	_was_on_floor = is_on_floor()
	current_state_name = CartState.keys()[current_state]


func _update_drive(delta: float) -> void:
	## Drive along the actual support plane so uphill speed becomes launch speed.
	var grounded: bool = is_on_floor()
	var normal: Vector3 = get_floor_normal() if grounded else Vector3.UP
	var forward_dir: Vector3 = -global_transform.basis.z
	var right_dir: Vector3 = global_transform.basis.x
	if grounded:
		forward_dir = (forward_dir - normal * forward_dir.dot(normal)).normalized()
		right_dir = (right_dir - normal * right_dir.dot(normal)).normalized()
	var fwd_speed: float = velocity.dot(forward_dir)
	var lat_speed: float = velocity.dot(right_dir)
	var eff_max_speed: float = max_speed * (boost_speed_multiplier if boost_active else 1.0)
	var eff_accel: float = acceleration * (boost_acceleration_multiplier if boost_active else 1.0)
	if Input.is_action_pressed("accelerate"):
		var accel_scale: float = clampf(1.0 - fwd_speed / eff_max_speed, 0.25, 1.0)
		fwd_speed = move_toward(fwd_speed, eff_max_speed, eff_accel * accel_scale * delta)
	elif Input.is_action_pressed("brake"):
		if fwd_speed > 0.5:
			fwd_speed = move_toward(fwd_speed, 0.0, brake_power * delta)
		else:
			fwd_speed = move_toward(fwd_speed, -reverse_speed, acceleration * 0.6 * delta)
	else:
		fwd_speed = move_toward(fwd_speed, 0.0, friction * delta)
	var grip: float = lateral_grip
	if Input.is_action_pressed("handbrake"):
		grip = drift_grip
		fwd_speed = move_toward(fwd_speed, 0.0, brake_power * 0.4 * delta)
	if not grounded:
		grip *= 0.25
	lat_speed = move_toward(lat_speed, 0.0, grip * delta)
	if grounded:
		velocity = forward_dir * fwd_speed + right_dir * lat_speed
	else:
		var flat_forward: Vector3 = -global_transform.basis.z
		var flat_right: Vector3 = global_transform.basis.x
		velocity = flat_forward * fwd_speed + flat_right * lat_speed + Vector3.UP * velocity.y
	is_drifting = grounded and absf(lat_speed) > drift_detection_threshold
	slide_amount = clampf(absf(lat_speed) / maxf(max_speed * 0.5, 0.1), 0.0, 1.0)


func _apply_steering(steer_input: float, delta: float) -> void:
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
	## Solid hits keep tangent speed, recoil away from the contact and kick the
	## suspension in the direction of the actual contact normal.
	if _impact_timer > 0.0:
		return
	for i in get_slide_collision_count():
		var collision: KinematicCollision3D = get_slide_collision(i)
		var normal: Vector3 = collision.get_normal()
		if normal.y > 0.6:
			continue
		var impact_speed: float = -_prev_velocity.dot(normal)
		if impact_speed < min_impact_speed:
			continue
		var impact_factor: float = clampf(impact_speed / max_speed, 0.0, 1.0)
		velocity += normal * minf(impact_speed * impact_recoil, max_recoil_speed)
		var loss: float = impact_speed * impact_speed_loss
		var planar: Vector3 = Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, loss)
		velocity.x = planar.x
		velocity.z = planar.z
		var local_normal: Vector3 = (global_transform.basis.inverse() * normal).normalized()
		_base_pitch_vel += local_normal.z * impact_factor * impact_tilt_strength * 12.0
		_base_roll_vel -= local_normal.x * impact_factor * impact_tilt_strength * 12.0
		_susp_vel -= impact_factor * 0.12
		_impact_timer = impact_cooldown
		_squash_impulse = maxf(_squash_impulse, clampf(impact_factor * 1.2, 0.3, 1.0))
		if _camera_rig != null:
			_camera_rig.add_shake(0.15 + 0.5 * impact_factor)
		if _feedback != null:
			_feedback.on_collision(impact_factor)
		break


func _push_pushables() -> void:
	## Off-center impulses transfer both momentum and spin instead of sliding
	## every prop straight ahead regardless of where the kart made contact.
	if push_force <= 0.0:
		return
	var push_speed: float = Vector2(_prev_velocity.x, _prev_velocity.z).length()
	var kick: float = push_force * clampf(push_speed / 8.0, 0.15, 1.0)
	var now_s: float = Time.get_ticks_msec() / 1000.0
	for i in get_slide_collision_count():
		var collision: KinematicCollision3D = get_slide_collision(i)
		var collider: Object = collision.get_collider()
		if collider == null or not (collider is RigidBody3D):
			continue
		var prop: RigidBody3D = collider as RigidBody3D
		var id := prop.get_instance_id()
		var last: float = float(_push_cooldowns.get(id, -10000.0))
		if now_s - last < 0.12:
			continue
		_push_cooldowns[id] = now_s
		if prop.sleeping:
			prop.sleeping = false
		var impulse: Vector3 = -collision.get_normal() * prop.mass * kick
		impulse.y = prop.mass * kick * 0.12
		var contact_offset: Vector3 = (collision.get_position() - prop.global_position).limit_length(1.0)
		prop.apply_impulse(impulse, contact_offset * 0.65)


func _update_boost(delta: float) -> void:
	_pad_burst_timer = maxf(_pad_burst_timer - delta, 0.0)
	var want_boost: bool = Input.is_action_pressed("boost") \
		and current_state == CartState.DRIVING \
		and is_on_floor() \
		and boost_amount > 0.0
	if want_boost:
		_boost_regen_timer = boost_regen_delay
		boost_amount = maxf(boost_amount - boost_drain_per_second * delta, 0.0)
		boost_active = true
	elif _pad_burst_timer > 0.0:
		boost_active = true
	else:
		boost_active = false
		if _boost_regen_timer > 0.0:
			_boost_regen_timer = maxf(_boost_regen_timer - delta, 0.0)
		else:
			boost_amount = minf(boost_amount + boost_regen_per_second * delta, max_boost)
	boost_visual = lerpf(boost_visual, 1.0 if boost_active else 0.0, 1.0 - exp(-6.0 * delta))
	if boost_active and not _was_boosting and _feedback != null:
		_feedback.on_boost_started()
	_was_boosting = boost_active


func on_boost_pad(burst_speed: float) -> void:
	var forward_dir: Vector3 = -global_transform.basis.z
	var fwd_speed: float = velocity.dot(forward_dir)
	var cap: float = max_speed * boost_speed_multiplier
	if fwd_speed < cap:
		velocity += forward_dir * minf(burst_speed, cap - fwd_speed)
	_pad_burst_timer = 0.6


func _update_tumble(steer_input: float, delta: float) -> void:
	if global_position.y < -20.0:
		_reset_cart()
		return
	match current_state:
		CartState.RECOVERY:
			_recover_timer -= delta
			var t: float = 1.0 - clampf(_recover_timer / auto_flip_duration, 0.0, 1.0)
			_tumble_pitch = lerpf(_recover_from.x, 0.0, t)
			_tumble_roll = lerpf(_recover_from.y, 0.0, t)
			if _recover_timer <= 0.0:
				_enter_driving()
			return
		CartState.CRASHED:
			_crash_timer -= delta
			if _crash_timer <= 0.0:
				_enter_recovery()
			return
	if is_on_floor():
		_air_time = 0.0
		if current_state == CartState.AIRBORNE_TUMBLE:
			_land_from_tumble()
		if absf(_tumble_pitch) > 0.001 or absf(_tumble_roll) > 0.001:
			_tumble_pitch = move_toward(_tumble_pitch, 0.0, 5.0 * delta)
			_tumble_roll = move_toward(_tumble_roll, 0.0, 5.0 * delta)
		return
	_air_time += delta
	if current_state == CartState.DRIVING and _air_time > airborne_time_threshold and enable_air_tumble:
		_enter_tumble(steer_input, velocity.length())
	if current_state == CartState.AIRBORNE_TUMBLE:
		_tumble_pitch = wrapf(_tumble_pitch + _tumble_pitch_rate * delta, -PI, PI)
		_tumble_roll = wrapf(_tumble_roll + _tumble_roll_rate * delta, -PI, PI)


func _enter_tumble(steer_input: float, speed: float) -> void:
	current_state = CartState.AIRBORNE_TUMBLE
	_tumble_pitch_rate = -air_tumble_strength * (0.5 + speed * 0.06)
	_tumble_roll_rate = steer_input * air_tumble_strength * 3.0


func _land_from_tumble() -> void:
	var tilt: Vector2 = Vector2(_tumble_pitch, _tumble_roll)
	var up_dot: float = cos(tilt.length())
	if up_dot <= upside_down_dot_threshold:
		_enter_crashed(up_dot)
	else:
		current_state = CartState.DRIVING


func _enter_crashed(up_dot: float) -> void:
	current_state = CartState.CRASHED
	_crash_timer = crash_cooldown
	boost_active = false
	velocity *= 0.5
	if not is_on_floor():
		global_position.y += 0.4
	if _camera_rig != null:
		_camera_rig.add_shake(0.8)
	if _feedback != null:
		_feedback.on_crash(clampf(1.0 - up_dot, 0.4, 1.0))


func _enter_recovery() -> void:
	current_state = CartState.RECOVERY
	_recover_timer = auto_flip_duration
	_recover_from = Vector3(_tumble_pitch, _tumble_roll, 0.0)
	velocity.x *= 0.4
	velocity.z *= 0.4
	velocity.y = 0.0
	if not is_on_floor():
		global_position.y += 0.3


func _enter_driving() -> void:
	current_state = CartState.DRIVING
	_tumble_pitch = 0.0
	_tumble_roll = 0.0


func _process_landing_and_launch() -> void:
	var just_landed: bool = (not _was_on_floor) and is_on_floor()
	var just_launched: bool = _was_on_floor and (not is_on_floor())
	if just_landed:
		var fall_speed: float = maxf(-_prev_velocity.y, 0.0)
		_squash_impulse = maxf(_squash_impulse, clampf(fall_speed * 0.12, 0.15, 1.0))
		_susp_vel -= clampf(fall_speed * suspension_landing_dip * 0.08, 0.06, 0.9)
		if _camera_rig != null:
			_camera_rig.add_shake(clampf(fall_speed * 0.03, 0.0, 0.3))
		if _feedback != null:
			_feedback.on_landing(fall_speed)
		var forward_dir: Vector3 = -global_transform.basis.z
		var right_dir: Vector3 = global_transform.basis.x
		var lat_speed: float = velocity.dot(right_dir)
		lat_speed *= 1.0 - landing_stability_strength
		velocity = forward_dir * velocity.dot(forward_dir) + right_dir * lat_speed + Vector3.UP * velocity.y
	elif just_launched and _prev_velocity.y > 1.0:
		_stretch_impulse = maxf(_stretch_impulse, clampf(_prev_velocity.y * 0.1, 0.2, 1.0))


func _update_visuals(steer_input: float, delta: float) -> void:
	## Acceleration, not just button state, drives weight transfer. The physical
	## collision root follows terrain/tumble; the smaller weight shift is visual.
	var forward_dir: Vector3 = -global_transform.basis.z
	var right_dir: Vector3 = global_transform.basis.x
	var fwd_speed: float = velocity.dot(forward_dir)
	var speed_frac: float = clampf(absf(fwd_speed) / max_speed, 0.0, 1.0)
	_squash_impulse = move_toward(_squash_impulse, 0.0, 2.5 * delta)
	_stretch_impulse = move_toward(_stretch_impulse, 0.0, 2.5 * delta)
	var accel_stretch: float = 0.0
	var brake_squash: float = 0.0
	if Input.is_action_pressed("accelerate"):
		accel_stretch = 1.0 - speed_frac
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
	var measured_accel: Vector3 = (velocity - _frame_start_velocity) / maxf(delta, 0.0001)
	_longitudinal_accel = lerpf(_longitudinal_accel, clampf(measured_accel.dot(forward_dir), -gravity, gravity), 1.0 - exp(-8.0 * delta))
	_lateral_accel = lerpf(_lateral_accel, clampf(measured_accel.dot(right_dir), -gravity, gravity), 1.0 - exp(-8.0 * delta))
	var target_pitch: float = _longitudinal_accel / gravity * mesh_pitch_amount
	var target_roll: float = _lateral_accel / gravity * mesh_tilt_amount
	target_roll -= steer_input * mesh_tilt_amount * 0.35 * clampf(fwd_speed / max_speed, -1.0, 1.0)
	if current_state != CartState.DRIVING or not is_on_floor():
		target_pitch = 0.0
		target_roll = 0.0
	_base_pitch_vel += ((target_pitch - _base_pitch) * suspension_stiffness - _base_pitch_vel * suspension_damping) * delta
	_base_roll_vel += ((target_roll - _base_roll) * suspension_stiffness - _base_roll_vel * suspension_damping) * delta
	_base_pitch = clampf(_base_pitch + _base_pitch_vel * delta, -0.32, 0.32)
	_base_roll = clampf(_base_roll + _base_roll_vel * delta, -0.36, 0.36)
	_susp_vel += (-_susp_pos * suspension_stiffness - _susp_vel * suspension_damping) * delta
	_susp_pos = clampf(_susp_pos + _susp_vel * delta, -0.12, 0.07)
	_mesh_root.position.y = SUSPENSION_PIVOT_HEIGHT + _susp_pos
	_mesh_root.rotation.z = _base_roll + _slope_roll + _tumble_roll
	_mesh_root.rotation.x = _base_pitch + _slope_pitch + _tumble_pitch
	_update_collision_shapes()


func _update_collision_shapes() -> void:
	var tilt_basis := Basis.from_euler(Vector3(_slope_pitch + _tumble_pitch, 0.0, _slope_roll + _tumble_roll))
	var pivot := Vector3(0.0, SUSPENSION_PIVOT_HEIGHT, 0.0)
	for i in _collision_shapes.size():
		var rest: Transform3D = _collision_rest_transforms[i]
		_collision_shapes[i].transform = Transform3D(
			tilt_basis * rest.basis, pivot + tilt_basis * (rest.origin - pivot))


func _sample_wheel_supports() -> void:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var base: Vector3 = global_position
	var normal_sum: Vector3 = Vector3.ZERO
	_support_count = 0
	var offsets: Array[Vector3] = [
		Vector3(-wheel_half_track, 0.0, -wheelbase * 0.5),
		Vector3(wheel_half_track, 0.0, -wheelbase * 0.5),
		Vector3(-wheel_half_track, 0.0, wheelbase * 0.5),
		Vector3(wheel_half_track, 0.0, wheelbase * 0.5)]
	for i in 4:
		var origin: Vector3 = base + global_transform.basis * offsets[i] + Vector3.UP * ground_probe_height
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			origin, origin + Vector3.DOWN * ground_probe_length, collision_mask, [get_rid()])
		query.collide_with_areas = false
		var hit: Dictionary = space_state.intersect_ray(query)
		_ground_support[i] = false
		_ground_heights[i] = 0.0
		if hit.is_empty():
			continue
		var normal: Vector3 = hit.normal as Vector3
		if normal.y < 0.45:
			continue
		_ground_support[i] = true
		_ground_heights[i] = (hit.position as Vector3).y - base.y
		normal_sum += normal
		_support_count += 1
	_ground_normal = normal_sum.normalized() if _support_count > 0 else Vector3.UP


func _support_pair(first: int, second: int) -> Vector2:
	var height_sum: float = 0.0
	var count: float = 0.0
	for index in [first, second]:
		if _ground_support[index]:
			height_sum += _ground_heights[index]
			count += 1.0
	return Vector2(height_sum / maxf(count, 1.0), count)


func _normal_tilt(normal: Vector3) -> Vector2:
	var local_normal: Vector3 = (global_transform.basis.inverse() * normal).normalized()
	return Vector2(atan2(local_normal.z, maxf(local_normal.y, 0.01)), -atan2(local_normal.x, maxf(local_normal.y, 0.01)))


func _update_ground_tilt(delta: float) -> void:
	_sample_wheel_supports()
	var target_pitch: float = _slope_pitch
	var target_roll: float = _slope_roll
	var response: float = air_tilt_smooth_speed
	var grounded: bool = is_on_floor() and current_state == CartState.DRIVING
	if grounded:
		response = slope_smooth_speed
		var front: Vector2 = _support_pair(0, 1)
		var rear: Vector2 = _support_pair(2, 3)
		var left: Vector2 = _support_pair(0, 2)
		var right: Vector2 = _support_pair(1, 3)
		var normal_tilt: Vector2 = _normal_tilt(_ground_normal)
		target_pitch = normal_tilt.x * slope_follow_strength
		target_roll = normal_tilt.y * slope_follow_strength
		if front.y > 0.0 and rear.y > 0.0:
			target_pitch = atan2(front.x - rear.x, wheelbase) * slope_follow_strength
		elif rear.y > 0.0 and front.y == 0.0:
			target_pitch -= ledge_tip_amount
			response = ledge_tip_smooth_speed
		elif front.y > 0.0 and rear.y == 0.0:
			target_pitch += ledge_tip_amount * 0.8
			response = ledge_tip_smooth_speed
		if left.y > 0.0 and right.y > 0.0:
			target_roll = atan2(right.x - left.x, wheel_half_track * 2.0) * slope_follow_strength
		elif right.y > 0.0 and left.y == 0.0:
			target_roll += ledge_tip_amount * 0.7
			response = ledge_tip_smooth_speed
		elif left.y > 0.0 and right.y == 0.0:
			target_roll -= ledge_tip_amount * 0.7
			response = ledge_tip_smooth_speed
		if _previous_support_count == 4 and _support_count < 4:
			_susp_vel -= 0.035 * float(4 - _support_count)
	elif current_state == CartState.DRIVING:
		var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
		if horizontal_speed > 1.0:
			target_pitch = clampf(atan2(velocity.y, horizontal_speed), -0.55, 0.55)
		target_roll = 0.0
	else:
		target_pitch = 0.0
		target_roll = 0.0
	var blend: float = 1.0 - exp(-response * delta)
	_slope_pitch = lerpf(_slope_pitch, clampf(target_pitch, -0.9, 0.9), blend)
	_slope_roll = lerpf(_slope_roll, clampf(target_roll, -0.75, 0.75), blend)
	_previous_support_count = _support_count


func _restore_pushables() -> void:
	for id: int in _pushable_spawn_transforms:
		var node: Object = instance_from_id(id)
		if node == null or not (node is RigidBody3D):
			continue
		var prop: RigidBody3D = node as RigidBody3D
		prop.global_transform = _pushable_spawn_transforms[id]
		prop.linear_velocity = Vector3.ZERO
		prop.angular_velocity = Vector3.ZERO
		prop.sleeping = false


func _reset_cart() -> void:
	velocity = Vector3.ZERO
	global_transform = _spawn_transform
	_mesh_root.scale = Vector3.ONE
	_mesh_root.rotation = Vector3.ZERO
	_mesh_root.position = Vector3(0.0, SUSPENSION_PIVOT_HEIGHT, 0.0)
	_squash_impulse = 0.0
	_stretch_impulse = 0.0
	_impact_timer = 0.0
	is_drifting = false
	_frame_start_velocity = Vector3.ZERO
	_prev_velocity = Vector3.ZERO
	_was_on_floor = true
	current_state = CartState.DRIVING
	boost_amount = max_boost
	boost_active = false
	boost_visual = 0.0
	_boost_regen_timer = 0.0
	_pad_burst_timer = 0.0
	_was_boosting = false
	_air_time = 0.0
	_tumble_pitch = 0.0
	_tumble_roll = 0.0
	_crash_timer = 0.0
	_recover_timer = 0.0
	_base_pitch = 0.0
	_base_roll = 0.0
	_base_pitch_vel = 0.0
	_base_roll_vel = 0.0
	_longitudinal_accel = 0.0
	_lateral_accel = 0.0
	_slope_pitch = 0.0
	_slope_roll = 0.0
	_susp_pos = 0.0
	_susp_vel = 0.0
	_support_count = 4
	_previous_support_count = 4
	for i in 4:
		_ground_support[i] = true
		_ground_heights[i] = 0.0
	_update_collision_shapes()
	if _camera_rig != null:
		_camera_rig.reset_camera()
	if _feedback != null:
		_feedback.reset_feedback()
	_restore_pushables()
