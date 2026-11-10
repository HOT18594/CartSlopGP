class_name CartPlayer
extends CharacterBody3D

const VehicleCatalog := preload("res://scripts/vehicles/vehicle_catalog.gd")
const VehicleVisual := preload("res://scripts/vehicles/vehicle_visual.gd")
const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")
const REFERENCE_MASS: float = 1200.0 ## Mass at which `engine_power` is quoted.
## A sender clock is its own process uptime, so a single absurd stamp must not
## permanently reject every later packet. A backwards jump larger than this is
## treated as a clock reset and re-baselined; normal reordering stays rejected.
const NET_CLOCK_RESET_MS: int = 60_000

signal net_push_requested(prop: Node, direction: Vector3, kick: float)
signal horn_requested()

enum CartState { DRIVING, AIRBORNE_TUMBLE, CRASHED, RECOVERY }
const STATE_NAMES: PackedStringArray = ["DRIVING", "AIRBORNE", "CRASHED", "RECOVERY"]
## Arcade cart controller with four-point terrain support, slope-aware driving,
## dynamic weight transfer, oriented compound collision shapes and air tumble.

const SUSPENSION_PIVOT_HEIGHT: float = 0.32
## Everything under the park sits below this. A cart that gets under the
## heightfield must be recovered, not left driving on the safety net at y=-5.
const FALL_RESET_HEIGHT: float = -4.0

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
@export_group("Steering Feel")
@export var steer_attack: float = 7.0 ## How fast digital/keyboard steering reaches lock.
@export var steer_release: float = 12.0 ## How fast it returns to centre.
@export var steer_curve: float = 1.35 ## >1 gives finer control near centre, full lock at the edge.
@export var air_control_strength: float = 0.25 ## Steering authority while airborne (0-1).
@export var gravity: float = 22.0 ## Downward acceleration (m/s^2).
@export var extra_fall_gravity: float = 1.6 ## Gravity multiplier while falling, for snappy landings.

@export_group("Collision Recoil")
@export var impact_speed_loss: float = 0.35 ## Fraction of impact speed lost on a hit (0-1).
@export var impact_recoil: float = 0.32 ## Fraction of impact speed bounced away from the surface.
@export var max_recoil_speed: float = 3.0 ## Cap on the recoil impulse (m/s).
@export var min_impact_speed: float = 2.5 ## Impacts slower than this are ignored (m/s).
@export var impact_cooldown: float = 0.12 ## Seconds between impact effects.
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

@export_group("Drift Mini-Turbo")
@export var drift_boost_min_charge: float = 0.55 ## Seconds of committed drift before a mini-turbo.
@export var drift_boost_duration: float = 0.85 ## Seconds the mini-turbo lasts.
@export var drift_boost_kick: float = 2.5 ## Instant forward speed (m/s) when the mini-turbo fires.
@export var drift_boost_speed_multiplier: float = 1.22 ## Top speed multiplier during a mini-turbo.
@export var drift_boost_accel_multiplier: float = 1.15 ## Acceleration multiplier during a mini-turbo.
@export var drift_boost_slip_threshold: float = 2.0 ## Sideways speed (m/s) that counts as charging.
@export var drift_boost_fov_punch: float = 2.5 ## Camera FOV kick when the mini-turbo fires.

@export_group("Impact Feel")
@export var crash_hit_stop: float = 0.09 ## Crash hit-stop in seconds (single player only).
@export var heavy_impact_hit_stop_min: float = 0.035 ## Shortest heavy-impact hit-stop (s).
@export var heavy_impact_hit_stop_max: float = 0.09 ## Longest heavy-impact hit-stop (s).
@export var heavy_impact_threshold: float = 0.5 ## Impact fraction of top speed that counts as heavy.
@export var hit_stop_time_scale: float = 0.05 ## World speed during hit-stop (1.0 = disabled).

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
var remote_peer_id: int = 0
var net_position: Vector3 = Vector3.ZERO
var net_yaw: float = 0.0
var net_velocity: Vector3 = Vector3.ZERO
## False while a finished or stale cart must not be an obstacle. Solid ghosts
## use the GHOST collision layer so local carts cannot drive through them.
var contact_enabled: bool = true
## Permanent for the rest of the race: a crossed cart is never solid again.
var race_finished: bool = false

## Remote snapshot pipeline. Two timestamped samples give a velocity estimate;
## the newest sample is then extrapolated briefly so a dropped or late packet
## glides instead of freezing the ghost and snapping on the next one.
var _net_sample_position: Vector3 = Vector3.ZERO
var _net_sample_yaw: float = 0.0
var _net_sample_ms: int = 0
var _net_sample_prev_position: Vector3 = Vector3.ZERO
var _net_sample_prev_yaw: float = 0.0
var _net_sample_prev_ms: int = 0
var _net_last_receive_ms: int = 0
var _net_has_sample: bool = false

# AI carts run this exact controller with virtual inputs instead of device input.
var ai_mode: bool = false
var ai_throttle: float = 0.0
var ai_brake: float = 0.0
var ai_steer: float = 0.0
var ai_boost: bool = false
var ai_handbrake: bool = false

var _boost_exhausted: bool = false
var _profile_mass: float = REFERENCE_MASS
var _profile_width: float = 1.50
var _profile_length: float = 2.26
var _profile_height: float = 1.70
var _profile_contact_radius: float = 1.25
var _profile_push_scale: float = 1.0
var _base_stats: Dictionary = {} ## Pristine export values for vehicle re-application.

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
var _input_locked_now: bool = false
var _impact_timer: float = 0.0
## True while the last contact was another cart's roof. CharacterBody treats
## that top face as floor, but accelerating along it is not real ground.
var _cart_roof_contact: bool = false
var steer_smoothed: float = 0.0
var _reverse_hold: float = 0.0
var _squash_impulse: float = 0.0
var _stretch_impulse: float = 0.0
var _was_on_floor: bool = true
var _push_cooldowns: Dictionary[int, float] = {}
var _pushable_spawn_transforms: Dictionary[int, Transform3D] = {}

# Drift mini-turbo state.
var _drift_charge: float = 0.0
var _drift_charging: bool = false
var _mini_boost_timer: float = 0.0
var _manual_boost_active: bool = false
var _boost_toggle_on: bool = false
var _handbrake_toggle_on: bool = false

# Hit-stop state. Engine.time_scale is global, so a token invalidates pending
# restore callbacks when the cart resets or a newer hit-stop replaces them.
var _hit_stop_token: int = 0
var _hit_stop_restore_scale: float = 1.0

@onready var _mesh_root: Node3D = $MeshRoot
@onready var _camera_rig: ChaseCamera = $CameraArm
@onready var _feedback: CartFeedback = $Feedback
@onready var _push_sensor: Area3D = $PushSensor

var _collision_shapes: Array[CollisionShape3D] = []
var _collision_rest_transforms: Array[Transform3D] = []
var _collision_base_transforms: Array[Transform3D] = []
var _collision_base: Dictionary = {}
var _push_shape_base: Vector3 = Vector3.ZERO
var _wheel_query: PhysicsRayQueryParameters3D
var _wheel_offsets: Array[Vector3] = [
	Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _has_collision_basis: bool = false


func _ready() -> void:
	floor_snap_length = 0.75
	add_to_group("player")
	_wheel_query = PhysicsRayQueryParameters3D.new()
	_wheel_query.collision_mask = CollisionLayers.WORLD
	_wheel_query.collide_with_areas = false
	_wheel_query.exclude = [get_rid()]
	if ai_mode and _push_sensor != null:
		# Rivals never push props; the Area3D would monitor every prop for the
		# whole race. The cart keeps its solid body, only the sensor goes away.
		_push_sensor.monitoring = false
		_push_sensor.queue_free()
		_push_sensor = null
	for child in get_children():
		if child is CollisionShape3D:
			var collision_shape := child as CollisionShape3D
			_collision_shapes.append(collision_shape)
			_collision_rest_transforms.append(collision_shape.transform)
			_collision_base_transforms.append(collision_shape.transform)
			if collision_shape.shape is BoxShape3D:
				_collision_base[collision_shape.get_instance_id()] = \
					(collision_shape.shape as BoxShape3D).size
			elif collision_shape.shape is SphereShape3D:
				_collision_base[collision_shape.get_instance_id()] = \
					(collision_shape.shape as SphereShape3D).radius
			elif collision_shape.shape is CapsuleShape3D:
				var capsule := collision_shape.shape as CapsuleShape3D
				_collision_base[collision_shape.get_instance_id()] = \
					Vector2(capsule.radius, capsule.height)
	var spawn_point: Node3D = get_tree().get_first_node_in_group("spawn_point") as Node3D
	if spawn_point != null:
		_spawn_transform = spawn_point.global_transform
	else:
		_spawn_transform = global_transform
	_capture_base_stats()
	var entry: Dictionary = _apply_vehicle_visual()
	_apply_vehicle_stats(entry)
	if _feedback != null:
		_feedback.apply_vehicle_profile(entry)
	if _push_sensor != null:
		_push_sensor.body_entered.connect(_on_push_sensor_body_entered)
		var push_collision := _push_sensor.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if push_collision != null and push_collision.shape is BoxShape3D:
			_push_shape_base = (push_collision.shape as BoxShape3D).size
			# _apply_vehicle_stats() ran before the base size existed, so the
			# sensor was skipped. Resize it once now for the initial car.
			_resize_collision(entry)
	call_deferred("_collect_pushables")


func set_spawn_transform(spawn_transform: Transform3D) -> void:
	## Multiplayer spawns carts on a grid, not on the single-player marker.
	_spawn_transform = spawn_transform


func _capture_base_stats() -> void:
	## Keep the pristine export values so another vehicle can be applied later
	## without compounding the per-vehicle multipliers.
	_base_stats = {
		"max_speed": max_speed,
		"acceleration": acceleration,
		"lateral_grip": lateral_grip,
		"drift_grip": drift_grip,
		"steering_speed": steering_speed,
		"brake_power": brake_power,
	}


func setup_remote(peer_id: int) -> void:
	## Turn this cart into an interpolated ghost for another player.
	remote_mode = true
	remote_peer_id = peer_id
	name = "Remote_%d" % peer_id
	remove_from_group("player")
	add_to_group("remote_player")
	# Ghosts are solid to every local cart (GHOST layer) so players cannot
	# drive through each other between state packets. The ghost itself never
	# runs physics: it is placed by _update_remote_state and its mask stays 0,
	# so it is never pushed by the world. The host's OBB resolver still owns
	# the momentum exchange and the final separation.
	collision_layer = CollisionLayers.GHOST
	collision_mask = 0
	set_physics_process(true)
	set_process(false)
	contact_enabled = true
	race_finished = false
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
	_net_sample_position = global_position
	_net_sample_yaw = rotation.y
	_net_sample_prev_position = global_position
	_net_sample_prev_yaw = rotation.y
	_net_sample_ms = Time.get_ticks_msec()
	_net_sample_prev_ms = _net_sample_ms
	_net_last_receive_ms = _net_sample_ms
	_net_has_sample = false


func set_net_state(position: Vector3, yaw: float, sent_ms: int,
		velocity: Vector3 = Vector3.ZERO) -> bool:
	## Accept a remote state packet. Returns false for stale or invalid input,
	## so an out-of-order datagram can never drag the ghost backwards.
	if not position.is_finite() or not is_finite(yaw) or not velocity.is_finite():
		return false
	if position.length_squared() > 5000.0 * 5000.0:
		return false
	if sent_ms < 0:
		return false
	if _net_has_sample and sent_ms <= _net_sample_ms:
		# A single spoofed 9e9 stamp used to make every later packet look
		# stale, freezing this ghost forever. A huge backwards jump is a clock
		# reset or a new sender process, not ordinary reordering: accept it as
		# a fresh baseline instead of poisoning the stream.
		if _net_sample_ms - sent_ms <= NET_CLOCK_RESET_MS:
			return false
		_net_has_sample = false
	var now: int = Time.get_ticks_msec()
	var snap: bool = not _net_has_sample
	if _net_has_sample:
		var jump: float = position.distance_squared_to(global_position)
		# A big correction after a real gap is a respawn or a scene warp, not
		# normal movement. Snap once instead of gliding through the world.
		if jump > 64.0 and now - _net_last_receive_ms > 300:
			snap = true
		_net_sample_prev_position = _net_sample_position
		_net_sample_prev_yaw = _net_sample_yaw
		_net_sample_prev_ms = _net_sample_ms
	else:
		_net_sample_prev_position = position
		_net_sample_prev_yaw = yaw
		_net_sample_prev_ms = sent_ms
	_net_sample_position = position
	_net_sample_yaw = yaw
	_net_sample_ms = sent_ms
	_net_last_receive_ms = now
	_net_has_sample = true
	net_position = position
	net_yaw = yaw
	# Sender velocity is far less noisy than differencing 20 Hz positions and is
	# what the host OBB resolver needs for a correct impact impulse.
	net_velocity = velocity.limit_length(60.0)
	if snap:
		global_position = position
		rotation.y = yaw
		reset_physics_interpolation()
	contact_enabled = not race_finished
	return true


func mark_race_finished() -> void:
	## Called once when a remote cart crosses the line. A finished cart keeps
	## streaming state, so this must stay sticky across later packets.
	race_finished = true
	contact_enabled = false
	collision_layer = 0


func setup_ai(vehicle_id: String) -> void:
	## AI uses the same physical controller and catalog stats as a human. Only
	## the input source and collision layer differ so every cart can see it.
	ai_mode = true
	remove_from_group("player")
	add_to_group("ai_player")
	collision_layer = CollisionLayers.GHOST
	collision_mask = CollisionLayers.WORLD | CollisionLayers.PLAYER | CollisionLayers.GHOST
	reapply_vehicle(vehicle_id)
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


func set_ai_controls(throttle: float, brake: float, steer: float,
		boost: bool = false, handbrake: bool = false) -> void:
	ai_throttle = clampf(throttle, 0.0, 1.0)
	ai_brake = clampf(brake, 0.0, 1.0)
	ai_steer = clampf(steer, -1.0, 1.0)
	ai_boost = boost
	ai_handbrake = handbrake


func _update_remote_state(delta: float) -> void:
	if not _net_has_sample:
		return
	var now: int = Time.get_ticks_msec()
	# Cap prediction at 100 ms; 250 ms at 45 m/s was an 11 m overshoot.
	var sample_seconds: float = maxf(float(_net_sample_ms - _net_sample_prev_ms), 1.0) / 1000.0
	var velocity: Vector3 = net_velocity
	if velocity.length_squared() < 0.01:
		velocity = (_net_sample_position - _net_sample_prev_position) / sample_seconds
	if not velocity.is_finite():
		velocity = Vector3.ZERO
	velocity = velocity.limit_length(45.0)
	var yaw_delta: float = wrapf(_net_sample_yaw - _net_sample_prev_yaw, -PI, PI)
	var yaw_rate: float = clampf(yaw_delta / sample_seconds, -8.0, 8.0)
	var age_ms: int = maxi(now - _net_last_receive_ms, 0)
	var predict_ms: float = clampf(float(age_ms), 0.0, 100.0)
	var target: Vector3 = _net_sample_position + velocity * (predict_ms / 1000.0)
	var target_yaw: float = _net_sample_yaw + yaw_rate * (predict_ms / 1000.0)
	if age_ms > 250:
		# Stale ghost: freeze and stop being a contact target. Keeping it solid
		# made a disconnected peer a permanent invisible wall.
		target = _net_sample_position
		target_yaw = _net_sample_yaw
		velocity = Vector3.ZERO
		contact_enabled = false
	else:
		contact_enabled = not race_finished
	collision_layer = 0 if (not contact_enabled) or race_finished \
		else CollisionLayers.GHOST
	var blend: float = 1.0 - exp(-16.0 * delta)
	global_position = global_position.lerp(target, blend)
	rotation.y = lerp_angle(rotation.y, target_yaw, blend)
	net_velocity = velocity


func set_vehicle_id(vehicle_id: String) -> void:
	## Rebuild the visual for a remote player's chosen vehicle and remember its
	## mass so car-to-car impacts use the right inertia.
	var entry: Dictionary = VehicleCatalog.find(vehicle_id)
	if entry.is_empty():
		return
	_profile_mass = maxf(float(entry.get("mass", REFERENCE_MASS)), 1.0)
	# The host's OBB resolver reads these extents for every ghost. Without
	# refreshing them here a remote truck was resolved as the default 1.5 x
	# 2.26 body, so its bumper passed through cars and it could shove cars it
	# was not touching.
	_apply_vehicle_dimensions(entry)
	_apply_vehicle_visual_for(entry)
	_resize_collision(entry)


func reapply_vehicle(vehicle_id: String) -> void:
	## Switch this LOCAL cart to another catalog vehicle at runtime. Used when
	## the race host assigns one car to everyone. Rebuilds visuals, collider,
	## derived stats and feedback (audio/skid width) from pristine values.
	var entry: Dictionary = VehicleCatalog.find(vehicle_id)
	if entry.is_empty():
		return
	_apply_vehicle_stats(entry)
	_apply_vehicle_visual_for(entry)
	if _feedback != null:
		_feedback.apply_vehicle_profile(entry)


func get_mass() -> float:
	return _profile_mass


func get_collision_extents() -> Dictionary:
	return {
		"width": _profile_width,
		"length": _profile_length,
		"height": _profile_height,
		"contact_radius": _profile_contact_radius,
	}

func _apply_vehicle_dimensions(entry: Dictionary) -> void:
	## Footprint used for OBB car-vs-car contacts. Shared by local/AI carts and
	## remote ghosts (which never run _apply_vehicle_stats).
	_profile_width = maxf(float(entry.get("width", 1.50)), 0.5)
	_profile_length = maxf(float(entry.get("length", 2.26)), 1.0)
	_profile_height = maxf(float(entry.get("height", 1.70)), 0.8)
	_profile_contact_radius = maxf(_profile_width, _profile_length) * 0.5


func get_collision_velocity() -> Vector3:
	return net_velocity if remote_mode else velocity


func honk() -> void:
	## Play this cart's horn locally. Remote peers call this through their
	## scene's horn RPC, so everyone hears the same short honk.
	if _feedback != null:
		_feedback.on_horn()


func apply_vehicle_bump(normal: Vector3, push: float) -> void:
	if remote_mode or not normal.is_finite() or not is_finite(push):
		return
	push = clampf(push, 0.0, 8.0)
	if push <= 0.0 or normal.length_squared() < 0.0001:
		return
	velocity += normal.normalized() * push
	# Also nudge the visible pose so the hit reads immediately.
	_susp_vel += minf(push * 0.035, 0.35)


func apply_vehicle_impulse(impulse: Vector3) -> void:
	## Host-resolved momentum impulse for a two-body car collision.
	if remote_mode or not impulse.is_finite():
		return
	impulse = impulse.limit_length(6.5)
	if impulse.length() < 0.01:
		return
	velocity += impulse
	_impact_timer = maxf(_impact_timer, 0.08)
	_susp_vel += minf(impulse.length() * 0.03, 0.30)
	var strength: float = impulse.length()
	if _camera_rig != null:
		_camera_rig.add_shake(clampf(strength * 0.06, 0.05, 0.4))
	if strength >= 3.0:
		_trigger_hit_stop(lerpf(0.035, 0.06, clampf((strength - 3.0) / 3.5, 0.0, 1.0)))
	if _feedback != null:
		_feedback.on_collision(clampf(strength / maxf(max_speed, 1.0), 0.15, 0.85))


@rpc("authority", "reliable")
func _net_apply_car_impulse(impulse: Vector3) -> void:
	## Sent from the host's local cart; its path matches every client's local
	## cart, so the correction lands on the cart that actually owns the physics.
	if remote_mode or not impulse.is_finite():
		return
	apply_vehicle_impulse(impulse.limit_length(6.5))


@rpc("authority", "reliable")
func _net_apply_car_bump(normal: Vector3, push: float) -> void:
	if remote_mode or not normal.is_finite() or not is_finite(push):
		return
	apply_vehicle_bump(normal.normalized(), clampf(push, 0.0, 8.0))


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
	## than the 1.15 t sports car despite a bigger engine. Restores the pristine
	## values first, so calling this twice never stacks multipliers.
	if entry.is_empty():
		return
	if _base_stats.is_empty():
		_capture_base_stats()
	max_speed = float(_base_stats["max_speed"])
	acceleration = float(_base_stats["acceleration"])
	lateral_grip = float(_base_stats["lateral_grip"])
	drift_grip = float(_base_stats["drift_grip"])
	steering_speed = float(_base_stats["steering_speed"])
	brake_power = float(_base_stats["brake_power"])
	_profile_mass = maxf(float(entry.get("mass", REFERENCE_MASS)), 1.0)
	_apply_vehicle_dimensions(entry)
	wheelbase = maxf(float(entry.get("wheelbase", wheelbase)), 0.7)
	wheel_half_track = maxf(float(entry.get("track", wheel_half_track * 2.0)) * 0.5, 0.3)
	_cache_wheel_offsets()
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
	_resize_collision(entry)


func _resize_collision(entry: Dictionary) -> void:
	## The cart scene has one collider; scale it to the catalog length so a
	## box truck genuinely takes up more road than a shopping cart. Width grows
	## with the square root so heavy vehicles do not become absurdly wide.
	if _collision_shapes.is_empty():
		return
	var length: float = float(entry.get("length", 2.26))
	var width: float = float(entry.get("width", 1.50))
	var height: float = float(entry.get("height", 1.70))
	# Base compound collider: 2.26 m bumper-to-bumper, 1.506 m wide, 1.70 m tall.
	var z_scale: float = clampf(length / 2.26, 0.68, 1.55)
	var x_scale: float = clampf(width / 1.506, 0.55, 1.35)
	var y_scale: float = clampf(height / 1.70, 0.55, 1.35)
	for index in _collision_shapes.size():
		var node: CollisionShape3D = _collision_shapes[index]
		if node == null:
			continue
		var key: int = node.get_instance_id()
		if not _collision_base.has(key):
			continue
		var base_value: Variant = _collision_base[key]
		if base_value is Vector3:
			var base_size: Vector3 = base_value as Vector3
			var box := BoxShape3D.new()
			box.size = Vector3(base_size.x * x_scale, base_size.y * y_scale,
				base_size.z * z_scale)
			node.shape = box
		elif base_value is Vector2:
			# Horizontal body capsule: local Y runs along the car length
			# (the node is rotated 90 degrees around X).
			var base_capsule: Vector2 = base_value as Vector2
			var capsule := CapsuleShape3D.new()
			capsule.radius = base_capsule.x * (x_scale + y_scale) * 0.5
			capsule.height = base_capsule.y * z_scale
			node.shape = capsule
		else:
			var sphere := SphereShape3D.new()
			sphere.radius = float(base_value) * y_scale
			node.shape = sphere
		var rest: Transform3D = _collision_base_transforms[index]
		rest.origin.x *= x_scale
		rest.origin.y *= y_scale
		rest.origin.z *= z_scale
		_collision_rest_transforms[index] = rest
		node.transform = rest
	if _push_sensor != null and _push_shape_base != Vector3.ZERO:
		var push_collision := _push_sensor.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if push_collision != null:
			var push_box := BoxShape3D.new()
			push_box.size = Vector3(_push_shape_base.x * x_scale, _push_shape_base.y,
				_push_shape_base.z * z_scale)
			push_collision.shape = push_box


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
	if remote_mode:
		_update_remote_state(delta)
		return
	_impact_timer = maxf(_impact_timer - delta, 0.0)
	_frame_start_velocity = velocity
	_input_locked_now = false if ai_mode else Network.input_locked
	var boost_held: bool = ai_boost if ai_mode else not _input_locked_now and _read_boost_held()
	var handbrake_held: bool = ai_handbrake if ai_mode else not _input_locked_now and _read_handbrake_held()
	_update_boost(delta, boost_held)
	var raw_steer: float = ai_steer if ai_mode else 0.0 if _input_locked_now else Input.get_axis("steer_right", "steer_left")
	var shaped_steer: float = signf(raw_steer) * pow(absf(raw_steer), steer_curve)
	var steer_rate: float = steer_attack if absf(shaped_steer) > absf(steer_smoothed) \
		else steer_release
	steer_smoothed = move_toward(steer_smoothed, shaped_steer, steer_rate * delta)
	var steer_input: float = steer_smoothed
	if current_state == CartState.CRASHED:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, friction * delta)
		velocity.y -= gravity * delta
	elif current_state == CartState.RECOVERY:
		velocity.y -= gravity * delta
	else:
		_update_drive(delta, handbrake_held)
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
	if global_position.y < FALL_RESET_HEIGHT:
		_reset_cart()
		return
	if not ai_mode and not _input_locked_now and Input.is_action_just_pressed("reset_cart"):
		_reset_cart()
	if not ai_mode and not _input_locked_now and Input.is_action_just_pressed("horn"):
		honk()
		if Network.is_session_active():
			horn_requested.emit()
	_was_on_floor = is_on_floor()
	current_state_name = STATE_NAMES[current_state]


func _update_drive(delta: float, handbrake_held: bool) -> void:
	## Drive along the actual support plane so uphill speed becomes launch speed.
	# A cart roof is a flat CharacterBody floor, but it is not terrain: let the
	# cart slide off instead of accelerating along another vehicle.
	var grounded: bool = is_on_floor() and not _cart_roof_contact
	var normal: Vector3 = get_floor_normal() if grounded else Vector3.UP
	var forward_dir: Vector3 = -global_transform.basis.z
	var right_dir: Vector3 = global_transform.basis.x
	if grounded:
		# Keep the drive direction horizontal. Projecting it onto a steep dome
		# normal bent the kart around the slope, which read as being shoved
		# sideways. move_and_slide still follows the support plane.
		forward_dir = Vector3(forward_dir.x, 0.0, forward_dir.z).normalized()
		right_dir = Vector3(right_dir.x, 0.0, right_dir.z).normalized()
	var fwd_speed: float = velocity.dot(forward_dir)
	var lat_speed: float = velocity.dot(right_dir)
	# A mini-turbo is a smaller, free boost; a held boost keeps the full values.
	var speed_mult: float = 1.0
	var accel_mult: float = 1.0
	if boost_active:
		if _mini_boost_timer > 0.0 and not _manual_boost_active:
			speed_mult = drift_boost_speed_multiplier
			accel_mult = drift_boost_accel_multiplier
		else:
			speed_mult = boost_speed_multiplier
			accel_mult = boost_acceleration_multiplier
	var eff_max_speed: float = max_speed * speed_mult
	var eff_accel: float = acceleration * accel_mult
	# Analog triggers: get_action_strength is 0..1 for both keys and pads, so a
	# half-pulled trigger gives half throttle instead of binary on/off.
	var throttle: float = ai_throttle if ai_mode else 0.0 if _input_locked_now else Input.get_action_strength("accelerate")
	var braking: float = ai_brake if ai_mode else 0.0 if _input_locked_now else Input.get_action_strength("brake")
	if braking > 0.05 and fwd_speed <= 0.5:
		_reverse_hold += delta
	else:
		_reverse_hold = 0.0
	if braking > 0.05 and fwd_speed > 0.5:
		# Brake wins over throttle. Holding both should slow the kart, not
		# cancel out and keep it accelerating.
		fwd_speed = move_toward(fwd_speed, 0.0, brake_power * braking * delta)
	elif throttle > 0.05:
		var accel_scale: float = clampf(1.0 - fwd_speed / maxf(eff_max_speed, 0.001), 0.25, 1.0)
		fwd_speed = move_toward(fwd_speed, eff_max_speed,
			eff_accel * accel_scale * throttle * delta)
	elif braking > 0.05 and _reverse_hold >= 0.12:
		fwd_speed = move_toward(fwd_speed, -reverse_speed,
			acceleration * 0.6 * braking * delta)
	else:
		fwd_speed = move_toward(fwd_speed, 0.0, friction * delta)
	if grounded and throttle > 0.05:
		# Arcade slope assist: a steep dome should be climbable, not turn the
		# kart sideways or stall it against the face. Only add uphill force
		# while the driver is actually on the throttle.
		var grade: float = clampf(-normal.dot(forward_dir), 0.0, 1.0)
		fwd_speed += grade * gravity * 0.85 * delta
	# Charge the mini-turbo from the actual pre-grip slip, then release it.
	# The returned kick is folded into fwd_speed so the velocity rebuild below
	# cannot discard it.
	fwd_speed += _update_drift_boost(delta, grounded, lat_speed, handbrake_held)
	var grip: float = lateral_grip
	if grounded and handbrake_held:
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


func _read_boost_held() -> bool:
	## Honour the accessibility/gameplay toggle: hold-to-boost or press-to-latch.
	if not GameSettings.boost_toggle:
		return Input.is_action_pressed("boost")
	if Input.is_action_just_pressed("boost"):
		_boost_toggle_on = not _boost_toggle_on
	return _boost_toggle_on


func _read_handbrake_held() -> bool:
	if not GameSettings.drift_toggle:
		return Input.is_action_pressed("handbrake")
	if Input.is_action_just_pressed("handbrake"):
		_handbrake_toggle_on = not _handbrake_toggle_on
	return _handbrake_toggle_on


func _update_drift_boost(delta: float, grounded: bool, lat_speed: float,
		handbrake_held: bool) -> float:
	## Charge while grounded, sliding sideways with the handbrake held. Releasing
	## after drift_boost_min_charge seconds fires a short, free mini-turbo and
	## returns the instant forward kick for the caller to apply to fwd_speed.
	var charging: bool = grounded and handbrake_held \
		and absf(lat_speed) >= drift_boost_slip_threshold \
		and current_state == CartState.DRIVING
	if charging:
		_drift_charge += delta
		_drift_charging = true
		return 0.0
	if not _drift_charging:
		return 0.0
	_drift_charging = false
	var kick: float = 0.0
	if _drift_charge >= drift_boost_min_charge and current_state == CartState.DRIVING:
		_mini_boost_timer = maxf(_mini_boost_timer, drift_boost_duration)
		var forward_dir: Vector3 = -global_transform.basis.z
		var fwd_speed: float = velocity.dot(forward_dir)
		var cap: float = max_speed * drift_boost_speed_multiplier
		if fwd_speed < cap:
			kick = minf(drift_boost_kick, cap - fwd_speed)
		if _camera_rig != null:
			_camera_rig.punch_fov(drift_boost_fov_punch)
		if _feedback != null:
			_feedback.on_drift_reward(_drift_charge / maxf(drift_boost_min_charge, 0.001))
	_drift_charge = 0.0
	return kick


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
	_cart_roof_contact = false
	if _impact_timer > 0.0:
		return
	var handled: Dictionary = {}
	for i in get_slide_collision_count():
		var collision: KinematicCollision3D = get_slide_collision(i)
		# Knocking a cone or crate around should never slow the kart down.
		var hit: Object = collision.get_collider()
		if hit is Node and (hit as Node).is_in_group("pushable"):
			continue
		if hit is Object:
			var hit_id: int = hit.get_instance_id()
			if handled.has(hit_id):
				continue
			handled[hit_id] = true
		var normal: Vector3 = collision.get_normal()
		var other_mass: float = 0.0
		var other_velocity: Vector3 = Vector3.ZERO
		var other_vehicle: bool = false
		if hit is CartPlayer:
			if (hit as CartPlayer).remote_mode and Network.is_session_active():
				# The host's two-body solver owns online player contact. Applying
				# local recoil as well would make the host cart bounce twice.
				continue
			# Offline/AI pairs resolve once, on the lower instance id. Without
			# this both carts apply the same impulse and ~63% of momentum
			# disappears in a rear-end.
			if get_instance_id() > (hit as CartPlayer).get_instance_id():
				continue
			other_vehicle = true
			other_mass = (hit as CartPlayer).get_mass()
			other_velocity = (hit as CartPlayer).get_collision_velocity()
		elif hit is Node and (hit as Node).has_meta("vehicle_mass"):
			other_vehicle = true
			other_mass = float((hit as Node).get_meta("vehicle_mass"))
			other_velocity = (hit as Node).get_meta("vehicle_velocity", Vector3.ZERO)
		if normal.y > 0.6 and not other_vehicle:
			continue
		if other_vehicle and normal.y > 0.6:
			# Standing on a roof: keep the horizontal separation response but
			# do not treat the other cart as drivable ground next frame.
			_cart_roof_contact = true
		if other_vehicle:
			# A chassis can present an upward contact when a cart climbs its bumper.
			# Separate vehicles horizontally instead of treating that as a floor.
			var planar_normal := Vector3(normal.x, 0.0, normal.z)
			if planar_normal.length_squared() < 0.01 and hit is Node3D:
				planar_normal = global_position - (hit as Node3D).global_position
				planar_normal.y = 0.0
			if planar_normal.length_squared() > 0.001:
				normal = planar_normal.normalized()
		var impact_speed: float = maxf(-(_prev_velocity - other_velocity).dot(normal), 0.0)
		if impact_speed < (0.05 if other_vehicle else min_impact_speed):
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
		# Even a slow shove needs a separating response; otherwise the engine
		# simply presses one cart into an immovable bot every frame.
		var contact_speed: float = maxf(impact_speed, 0.35) if other_vehicle else impact_speed
		var recoil: float = contact_speed * impact_recoil * recoil_scale \
			* (1.0 + own_share if other_vehicle else 1.0)
		velocity += normal * minf(recoil, max_recoil_speed * maxf(recoil_scale, 1.0)
			* (1.0 + own_share if other_vehicle else 1.0))
		if other_vehicle:
			# A physical AI is a real second body, not an offset on a rail. Both
			# carts receive a comparable momentum change; the heavier vehicle
			# transfers more momentum to the lighter one.
			var other_push: float = contact_speed * 0.78 * (own_mass / total_mass)
			if hit is CartPlayer:
				(hit as CartPlayer).apply_vehicle_impulse(-normal * other_push)
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
			_camera_rig.add_shake((0.10 + 0.45 * impact_factor) * shake_scale \
				* (1.15 if other_vehicle else 1.0))
		if impact_factor >= heavy_impact_threshold:
			var heavy: float = clampf((impact_factor - heavy_impact_threshold) \
				/ maxf(1.0 - heavy_impact_threshold, 0.001), 0.0, 1.0)
			_trigger_hit_stop(lerpf(heavy_impact_hit_stop_min,
				heavy_impact_hit_stop_max, heavy))
		if _feedback != null:
			_feedback.on_collision(impact_factor)
		# Keep scanning: a car bump must not hide a wall contact in the same
		# frame. Duplicate compound-shape contacts are deduped above.
		continue


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


func _update_boost(delta: float, held: bool) -> void:
	_pad_burst_timer = maxf(_pad_burst_timer - delta, 0.0)
	_mini_boost_timer = maxf(_mini_boost_timer - delta, 0.0)
	if not held:
		_boost_exhausted = false
	var want_boost: bool = held \
		and current_state == CartState.DRIVING \
		and is_on_floor() \
		and boost_amount > 0.0 \
		and not _boost_exhausted
	if boost_amount <= 0.0:
		_boost_exhausted = true
		_boost_toggle_on = false
	if want_boost:
		_boost_regen_timer = boost_regen_delay
		boost_amount = maxf(boost_amount - boost_drain_per_second * delta, 0.0)
		boost_active = true
		_manual_boost_active = true
	elif _pad_burst_timer > 0.0:
		boost_active = true
		_manual_boost_active = true
	else:
		# A drift mini-turbo is free: the meter keeps regenerating through it.
		_manual_boost_active = false
		boost_active = _mini_boost_timer > 0.0
		if _boost_regen_timer > 0.0:
			_boost_regen_timer = maxf(_boost_regen_timer - delta, 0.0)
		else:
			boost_amount = minf(boost_amount + boost_regen_per_second * delta, max_boost)
	boost_visual = lerpf(boost_visual, 1.0 if boost_active else 0.0, 1.0 - exp(-6.0 * delta))
	# The pad has its own whoosh; don't stack the manual-boost sound on top.
	if boost_active and not _was_boosting and _feedback != null and _pad_burst_timer <= 0.0:
		_feedback.on_boost_started()
	_was_boosting = boost_active


func _trigger_hit_stop(seconds: float) -> void:
	## Brief world freeze on a big hit. Never in multiplayer: every peer must
	## simulate at the same speed, so only single-player gets the crunch.
	if remote_mode or Network.is_session_active() or seconds <= 0.0:
		return
	# Engine.time_scale is global; only the primary local cart may own it.
	if get_tree().get_first_node_in_group("player") != self:
		return
	if _hit_stop_token == 0:
		_hit_stop_restore_scale = Engine.time_scale
	_hit_stop_token += 1
	var token: int = _hit_stop_token
	Engine.time_scale = clampf(hit_stop_time_scale, 0.01, 1.0)
	# ignore_time_scale keeps the restore timer ticking in real time.
	var timer: SceneTreeTimer = get_tree().create_timer(seconds, true, false, true)
	timer.timeout.connect(_finish_hit_stop.bind(token))


func _finish_hit_stop(token: int) -> void:
	if token != _hit_stop_token:
		return
	Engine.time_scale = _hit_stop_restore_scale
	_hit_stop_token = 0


func _cancel_hit_stop() -> void:
	## Reset and scene exit must never leave the whole game in slow motion.
	if _hit_stop_token == 0:
		return
	_hit_stop_token += 1
	Engine.time_scale = _hit_stop_restore_scale
	_hit_stop_token = 0


func _exit_tree() -> void:
	_cancel_hit_stop()


func on_boost_pad(burst_speed: float) -> void:
	var forward_dir: Vector3 = -global_transform.basis.z
	var fwd_speed: float = velocity.dot(forward_dir)
	var cap: float = max_speed * boost_speed_multiplier
	if fwd_speed < cap:
		velocity += forward_dir * minf(burst_speed, cap - fwd_speed)
	_pad_burst_timer = 0.6


func _update_tumble(steer_input: float, delta: float) -> void:
	if global_position.y < FALL_RESET_HEIGHT:
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
	_manual_boost_active = false
	_boost_toggle_on = false
	_handbrake_toggle_on = false
	_drift_charge = 0.0
	_drift_charging = false
	_mini_boost_timer = 0.0
	_pad_burst_timer = 0.0
	velocity *= 0.5
	if not is_on_floor():
		global_position.y += 0.4
	if _camera_rig != null:
		_camera_rig.add_shake(0.8)
		_camera_rig.punch_fov(-3.0)
	_trigger_hit_stop(crash_hit_stop)
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
			_camera_rig.add_shake(clampf(fall_speed * 0.055, 0.0, 0.55))
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
	var accelerating: bool = ai_throttle > 0.05 if ai_mode else Input.is_action_pressed("accelerate")
	var braking_now: bool = ai_brake > 0.05 if ai_mode else Input.is_action_pressed("brake")
	if accelerating:
		accel_stretch = 1.0 - speed_frac
	elif braking_now:
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
	## Keep the solid body upright. The capsule and wheel spheres already slide
	## over curved terrain; rotating them with the visual mesh would only add
	## unwanted contact normals. The visual chassis still tilts with the slope.
	if _has_collision_basis:
		return
	_has_collision_basis = true
	for i in _collision_shapes.size():
		if i < _collision_rest_transforms.size():
			_collision_shapes[i].transform = _collision_rest_transforms[i]


func _cache_wheel_offsets() -> void:
	var half_track: float = wheel_half_track
	var half_base: float = wheelbase * 0.5
	_wheel_offsets[0] = Vector3(-half_track, 0.0, -half_base)
	_wheel_offsets[1] = Vector3(half_track, 0.0, -half_base)
	_wheel_offsets[2] = Vector3(-half_track, 0.0, half_base)
	_wheel_offsets[3] = Vector3(half_track, 0.0, half_base)


func _sample_wheel_supports() -> void:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var base: Vector3 = global_position
	var normal_sum: Vector3 = Vector3.ZERO
	_support_count = 0
	for i in 4:
		var origin: Vector3 = base + global_transform.basis * _wheel_offsets[i] + Vector3.UP * ground_probe_height
		_wheel_query.from = origin
		_wheel_query.to = origin + Vector3.DOWN * ground_probe_length
		var hit: Dictionary = space_state.intersect_ray(_wheel_query)
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


func _normal_tilt(normal: Vector3) -> Vector2:
	var local_normal: Vector3 = (global_transform.basis.inverse() * normal).normalized()
	return Vector2(atan2(local_normal.z, maxf(local_normal.y, 0.01)), -atan2(local_normal.x, maxf(local_normal.y, 0.01)))


func _update_ground_tilt(delta: float) -> void:
	_sample_wheel_supports()
	var front_h: float = 0.0
	var front_n: float = 0.0
	var rear_h: float = 0.0
	var rear_n: float = 0.0
	var left_h: float = 0.0
	var left_n: float = 0.0
	var right_h: float = 0.0
	var right_n: float = 0.0
	for i in 4:
		if not _ground_support[i]:
			continue
		var h: float = _ground_heights[i]
		if i == 0 or i == 1:
			front_h += h
			front_n += 1.0
		if i == 2 or i == 3:
			rear_h += h
			rear_n += 1.0
		if i == 0 or i == 2:
			left_h += h
			left_n += 1.0
		if i == 1 or i == 3:
			right_h += h
			right_n += 1.0
	var target_pitch: float = _slope_pitch
	var target_roll: float = _slope_roll
	var response: float = air_tilt_smooth_speed
	var grounded: bool = is_on_floor() and current_state == CartState.DRIVING
	if grounded:
		response = slope_smooth_speed
		var normal_tilt: Vector2 = _normal_tilt(_ground_normal)
		target_pitch = normal_tilt.x * slope_follow_strength
		target_roll = normal_tilt.y * slope_follow_strength
		if front_n > 0.0 and rear_n > 0.0:
			target_pitch = atan2(front_h / front_n - rear_h / rear_n,
				wheelbase) * slope_follow_strength
		elif rear_n > 0.0 and front_n == 0.0:
			target_pitch -= ledge_tip_amount
			response = ledge_tip_smooth_speed
		elif front_n > 0.0 and rear_n == 0.0:
			target_pitch += ledge_tip_amount * 0.8
			response = ledge_tip_smooth_speed
		if left_n > 0.0 and right_n > 0.0:
			target_roll = atan2(right_h / right_n - left_h / left_n,
				wheel_half_track * 2.0) * slope_follow_strength
		elif right_n > 0.0 and left_n == 0.0:
			target_roll += ledge_tip_amount * 0.7
			response = ledge_tip_smooth_speed
		elif left_n > 0.0 and right_n == 0.0:
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


func reset_for_respawn() -> void:
	## Clear tumble/boost/crash state without teleporting to the grid spawn.
	## A remote/AI respawn must not teleport the whole park's props back.
	var keep: Transform3D = global_transform
	_reset_cart(false)
	global_transform = keep
	contact_enabled = true
	collision_layer = 0 if remote_mode else (CollisionLayers.GHOST if ai_mode else CollisionLayers.PLAYER)
	reset_physics_interpolation()


func _reset_cart(restore_props: bool = true) -> void:
	velocity = Vector3.ZERO
	global_transform = _spawn_transform
	reset_physics_interpolation()
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
	_boost_toggle_on = false
	_handbrake_toggle_on = false
	_drift_charge = 0.0
	_drift_charging = false
	_mini_boost_timer = 0.0
	_manual_boost_active = false
	_cancel_hit_stop()
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
	if not (Network.is_session_active() and not Network.is_host) and restore_props:
		_restore_pushables()
