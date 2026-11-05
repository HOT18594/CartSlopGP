class_name CartPlayer
extends CharacterBody3D

const VehicleCatalog := preload("res://scripts/vehicles/vehicle_catalog.gd")
const VehicleVisual := preload("res://scripts/vehicles/vehicle_visual.gd")
const REFERENCE_MASS: float = 1200.0 ## Mass at which `engine_power` is quoted.

signal net_push_requested(prop: Node, direction: Vector3, kick: float)

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
@export var push_force: float = 5.5 ## Ram strength as the velocity change (m/s) given to a rammed prop at full cart speed.
@export var push_lift: float = 0.85 ## Upward share of the push - how high small props pop into the air.
@export var push_spin: float = 1.6 ## Random spin impulse applied to rammed props.

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

## Multiplayer ghost state (set by the sandbox when this cart is another peer).
var remote_mode: bool = false
var net_position: Vector3 = Vector3.ZERO
var net_yaw: float = 0.0
var net_velocity: Vector3 = Vector3.ZERO

var _boost_exhausted: bool = false
var _profile_mass: float = REFERENCE_MASS
var _profile_push_scale: float = 1.0

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
@onready var _push_sensor: Area3D = $PushSensor

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
	var entry: Dictionary = _apply_vehicle_visual()
	_apply_vehicle_stats(entry)
	if _feedback != null:
		_feedback.apply_vehicle_profile(entry)
	if _push_sensor != null:
		_push_sensor.body_entered.connect(_on_push_sensor_body_entered)
	call_deferred("_collect_pushables")


func set_spawn_transform(spawn_transform: Transform3D) -> void:
	## Multiplayer spawns carts on a grid, not on the single-player marker.
	_spawn_transform = spawn_transform


func setup_remote(peer_id: int) -> void:
	## Turn this cart into an interpolated ghost for another player.
	remote_mode = true
	name = "Remote_%d" % peer_id
	remove_from_group("player")
	add_to_group("remote_player")
	collision_layer = 8
	collision_mask = 0
	set_physics_process(false)
	set_process(true)
	if _push_sensor != null:
		_push_sensor.monitoring = false
	if _camera_rig != null:
		_camera_rig.set_process(false)
		_camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
		var camera := _camera_rig.get_node_or_null("Camera3D") as Camera3D
		if camera != null:
			camera.current = false
	if _feedback != null:
		_feedback.enable_audio = false
		_feedback.enable_dust = false
		_feedback.enable_speed_feedback = false
		_feedback.reset_feedback()
		_feedback.set_remote_mode(true)
	net_position = global_position
	net_yaw = rotation.y
	net_velocity = Vector3.ZERO


func _process(delta: float) -> void:
	if not remote_mode:
		return
	var before: Vector3 = global_position
	global_position = global_position.lerp(net_position, 1.0 - exp(-14.0 * delta))
	rotation.y = lerp_angle(rotation.y, net_yaw, 1.0 - exp(-14.0 * delta))
	if delta > 0.0001:
		net_velocity = (global_position - before) / delta


func set_vehicle_id(vehicle_id: String) -> void:
	## Rebuild the visual for a remote player's chosen vehicle and remember its
	## mass so car-to-car impacts use the right inertia.
	var entry: Dictionary = VehicleCatalog.find(vehicle_id)
	if entry.is_empty():
		return
	_profile_mass = maxf(float(entry.get("mass", REFERENCE_MASS)), 1.0)
	_apply_vehicle_visual_for(entry)


func get_mass() -> float:
	return _profile_mass


func get_collision_velocity() -> Vector3:
	return net_velocity if remote_mode else velocity


func apply_vehicle_bump(normal: Vector3, push: float) -> void:
	if remote_mode or push <= 0.0:
		return
	velocity += normal * push


func _apply_vehicle_visual() -> Dictionary:
	## Swap the placeholder kart for the vehicle picked in the selector.
	var entry: Dictionary = VehicleCatalog.find(GameSettings.selected_vehicle)
	if entry.is_empty():
		entry = VehicleCatalog.find(VehicleCatalog.DEFAULT_ID)
	if entry.is_empty() or _mesh_root == null:
		return entry
	_apply_vehicle_visual_for(entry)
	return entry


func _apply_vehicle_stats(entry: Dictionary) -> void:
	## Mass, top speed and engine power all come from the catalog. Engine cars
	## are quoted at REFERENCE_MASS, so a 3.2 t truck gets a much gentler launch
	## than the 1.15 t sports car despite a bigger engine.
	if entry.is_empty():
		return
	_profile_mass = maxf(float(entry.get("mass", REFERENCE_MASS)), 1.0)
	max_speed = float(entry.get("max_speed", max_speed))
	var engine_power: float = float(entry.get("engine_power", 0.0))
	if engine_power > 0.0:
		acceleration = engine_power * REFERENCE_MASS / _profile_mass
	else:
		acceleration = float(entry.get("push_accel", acceleration))
	var weight_ratio: float = clampf(_profile_mass / REFERENCE_MASS, 0.05, 3.0)
	lateral_grip *= float(entry.get("grip", 1.0))
	drift_grip *= lerpf(1.0, float(entry.get("grip", 1.0)), 0.5)
	steering_speed *= float(entry.get("steering", 1.0))
	brake_power *= clampf(pow(weight_ratio, -0.15), 0.85, 1.10)
	_profile_push_scale = float(entry.get("push_scale", 1.0))


func _apply_vehicle_visual_for(entry: Dictionary) -> void:
	if _mesh_root == null or entry.is_empty():
		return
	var existing: Node = _mesh_root.get_node_or_null("KartModel")
	if existing != null:
		_mesh_root.remove_child(existing)
		existing.queue_free()
	var holder: Node3D = VehicleVisual.build(entry)
	holder.name = "KartModel"
	holder.position = Vector3(0.0, -SUSPENSION_PIVOT_HEIGHT, 0.0)
	_mesh_root.add_child(holder)


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
	_clamp_horizontal_speed()
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
		var accel_scale: float = clampf(1.0 - fwd_speed / maxf(eff_max_speed, 0.001), 0.25, 1.0)
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
	var speed_frac: float = clampf(absf(fwd_speed) / maxf(max_speed, 0.001), 0.0, 1.0)
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
		# Knocking a cone or crate around should never slow the kart down.
		var hit: Object = collision.get_collider()
		if hit is Node and (hit as Node).is_in_group("pushable"):
			continue
		var normal: Vector3 = collision.get_normal()
		if normal.y > 0.6:
			continue
		var other_mass: float = 0.0
		var other_velocity: Vector3 = Vector3.ZERO
		var other_vehicle: bool = false
		if hit is CartPlayer:
			other_vehicle = true
			other_mass = (hit as CartPlayer).get_mass()
			other_velocity = (hit as CartPlayer).get_collision_velocity()
		elif hit is Node and (hit as Node).has_meta("vehicle_mass"):
			other_vehicle = true
			other_mass = float((hit as Node).get_meta("vehicle_mass"))
			other_velocity = (hit as Node).get_meta("vehicle_velocity", Vector3.ZERO)
		var impact_speed: float = -(_prev_velocity - other_velocity).dot(normal)
		if impact_speed < min_impact_speed:
			continue
		# Momentum exchange. For a car-to-car hit both bodies share the impulse;
		# for a wall, the wall is effectively infinite.
		var own_mass: float = maxf(_profile_mass, 1.0)
		var total_mass: float = maxf(own_mass + other_mass, 1.0)
		var own_share: float = other_mass / total_mass if other_vehicle else 0.5
		var weight_ratio: float = clampf(own_mass / REFERENCE_MASS, 0.05, 3.0)
		var recoil_scale: float = clampf(1.0 / sqrt(weight_ratio), 0.55, 1.8)
		var loss_scale: float = clampf(pow(weight_ratio, -0.35), 0.50, 1.60)
		if other_vehicle:
			loss_scale *= clampf(pow(maxf(other_mass, 1.0) / own_mass, 0.25), 0.7, 1.5)
		var shake_scale: float = clampf(1.0 / sqrt(weight_ratio), 0.65, 1.20)
		var impact_factor: float = clampf(impact_speed / maxf(max_speed, 0.001), 0.0, 1.0)
		var recoil: float = impact_speed * impact_recoil * recoil_scale \
			* (1.0 + own_share if other_vehicle else 1.0)
		velocity += normal * minf(recoil, max_recoil_speed * maxf(recoil_scale, 1.0)
			* (1.0 + own_share if other_vehicle else 1.0))
		if other_vehicle:
			var other_push: float = impact_speed * impact_recoil \
				* (own_mass / total_mass) * 1.25
			if hit is CartPlayer:
				(hit as CartPlayer).apply_vehicle_bump(-normal, other_push)
			elif hit is Node and (hit as Node).has_meta("bump_velocity"):
				var bump: Vector3 = (hit as Node).get_meta("bump_velocity", Vector3.ZERO)
				(hit as Node).set_meta("bump_velocity", bump - normal * other_push)
		var loss: float = impact_speed * impact_speed_loss * loss_scale
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
			_camera_rig.add_shake((0.08 + 0.30 * impact_factor) * shake_scale \
				* (1.15 if other_vehicle else 1.0))
		if _feedback != null:
			_feedback.on_collision(impact_factor)
		break


func _on_push_sensor_body_entered(body: Node3D) -> void:
	var prop := body as RigidBody3D
	if prop == null or not prop.is_in_group("pushable"):
		return
	_push_prop(prop)


func _push_prop(prop: RigidBody3D) -> void:
	## Props live on their own collision layer, so they never block the kart.
	## The sensor pops them away with an upward, spinning impulse instead.
	var id: int = prop.get_instance_id()
	var now_s: float = Time.get_ticks_msec() / 1000.0
	if now_s - float(_push_cooldowns.get(id, -10000.0)) < 0.12:
		return
	_push_cooldowns[id] = now_s
	if prop.sleeping:
		prop.sleeping = false
	var direction: Vector3 = prop.global_position - global_position
	direction.y = 0.0
	if direction.length() < 0.05:
		direction = -global_transform.basis.z
	direction = direction.normalized()
	var speed: float = Vector2(velocity.x, velocity.z).length()
	# Momentum transfer: the truck launches a crate much harder than the cart.
	var kick: float = push_force * _profile_push_scale * clampf(speed / 6.0, 0.25, 1.4)
	var impulse: Vector3 = direction * prop.mass * kick + Vector3.UP * prop.mass * kick * push_lift
	net_push_requested.emit(prop, direction, kick)
	if Network.is_session_active() and not Network.is_host:
		return # The host owns prop physics; it applies the request.
	prop.apply_central_impulse(impulse)
	var spin: Vector3 = Vector3(randf_range(-1.0, 1.0), randf_range(-0.5, 0.5), randf_range(-1.0, 1.0))
	prop.apply_torque_impulse(spin * prop.mass * push_spin)


func _clamp_horizontal_speed() -> void:
	## Safety net: never let an impact or physics recovery fling the kart.
	var cap: float = max_speed * boost_speed_multiplier + 2.0
	var horizontal := Vector2(velocity.x, velocity.z)
	if horizontal.length() > cap:
		horizontal = horizontal.normalized() * cap
		velocity.x = horizontal.x
		velocity.z = horizontal.y


func _update_boost(delta: float) -> void:
	_pad_burst_timer = maxf(_pad_burst_timer - delta, 0.0)
	if not Input.is_action_pressed("boost"):
		_boost_exhausted = false
	var want_boost: bool = Input.is_action_pressed("boost") \
		and current_state == CartState.DRIVING \
		and is_on_floor() \
		and boost_amount > 0.0 \
		and not _boost_exhausted
	if boost_amount <= 0.0:
		_boost_exhausted = true
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
			var t: float = 1.0 - clampf(_recover_timer / maxf(auto_flip_duration, 0.001), 0.0, 1.0)
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
	is_drifting = false
	slide_amount = 0.0
	_crash_timer = crash_cooldown
	boost_active = false
	velocity *= 0.5
	if not is_on_floor():
		global_position.y += 0.4
	if _camera_rig != null:
		_camera_rig.add_shake(0.5)
	if _feedback != null:
		_feedback.on_crash(clampf(1.0 - up_dot, 0.4, 1.0))


func _enter_recovery() -> void:
	current_state = CartState.RECOVERY
	is_drifting = false
	slide_amount = 0.0
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
			_camera_rig.add_shake(clampf(fall_speed * 0.012, 0.0, 0.16))
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
	var speed_frac: float = clampf(absf(fwd_speed) / maxf(max_speed, 0.001), 0.0, 1.0)
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
	target_roll -= steer_input * mesh_tilt_amount * 0.35 * clampf(fwd_speed / maxf(max_speed, 0.001), -1.0, 1.0)
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
			origin, origin + Vector3.DOWN * ground_probe_length, 1, [get_rid()])
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
	_boost_exhausted = false
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
	# Props are host-authoritative in a session; a client reset must not snap
	# frozen bodies around locally.
	if not (Network.is_session_active() and not Network.is_host):
		_restore_pushables()
