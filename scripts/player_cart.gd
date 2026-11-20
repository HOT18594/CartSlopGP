class_name CartPlayer
extends CharacterBody3D

const VehicleCatalog := preload("res://scripts/vehicles/vehicle_catalog.gd")
const VehicleVisual := preload("res://scripts/vehicles/vehicle_visual.gd")
const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")
const CartCollisionSystem := preload("res://scripts/systems/cart_collision.gd")
const REFERENCE_MASS: float = 1200.0 ## Mass at which `engine_power` is quoted.
## Collider reference box that the catalog length/width/height are divided by.
## These are NOT the scene shape dimensions: the body capsule is 2.0 m long and
## 1.36 m wide, so keeping the reference deliberately larger leaves ~13% of
## anti-snag margin around the art. The tuning was done against this margin, so
## do not "correct" it to the shape size without retuning the bump feel.
const COLLIDER_REFERENCE_LENGTH: float = 2.26
const COLLIDER_REFERENCE_WIDTH: float = 1.506
const COLLIDER_REFERENCE_HEIGHT: float = 1.70
## AI and remote bot carts have no tag colour, so they cycle a fixed palette by
## their field index. The peer id offset matches grass_race.gd's bot ghosts.
const BOT_PEER_BASE: int = 1000
const BOT_TINTS: Array[Color] = [
	Color("f2545b"), Color("4fbf52"), Color("45b6f0"),
	Color("ff9f43"), Color("f26ca7"), Color("38d6f0"),
]
## A bump only ever adds a shove; these bounds keep it from turning into a
## launch and from taking steering away for longer than it reads on screen.
const BUMP_MAX_IMPULSE: float = 9.0
const BUMP_MIN_DURATION: float = 0.12
const BUMP_MAX_DURATION: float = 0.22
const BUMP_DEFAULT_DURATION: float = 0.18
const BUMP_STEER_AUTHORITY: float = 0.78
## A steady stream of contact bumps must not re-arm the steering penalty
## forever. One chain may last BUMP_MAX_DURATION, then it needs a
## BUMP_CHAIN_QUIET quiet gap before another bump can open a new one.
const BUMP_CHAIN_QUIET: float = 0.25
## Suspension hop, committed drift and 3-tier mini-turbo tuning constants.
const HOP_COYOTE_TIME: float = 0.10 ## Floor coyote grace (s) for initiating a drift hop over crests.
const HOP_MIN_SPEED: float = 3.5 ## Minimum forward speed (m/s) to trigger a drift hop.
const HOP_INITIAL_VEL: float = 4.45 ## Initial upward mesh velocity (m/s) peaking ~0.20 m over ~0.18 s.
const HOP_GRAVITY: float = 49.5 ## Return gravity (m/s^2) pulling the visual hop offset back to 0.
const DRIFT_LOCK_STEER: float = 0.18 ## Stick deflection required to lock committed drift direction.
const DRIFT_LOCK_SPEED: float = 4.5 ## Forward speed (m/s) required to lock committed drift direction.
const DRIFT_COMMITTED_SLIP_DRAG: float = 0.14 ## Low forward scrub while holding a committed drift.
const DRIFT_CARVE_RATE: float = 11.5 ## Rate (1/s) at which horizontal velocity aligns to the drift slip angle.
const DRIFT_SLIP_ANGLE_MIN_DEG: float = 16.0 ## Outward slip angle (deg) when counter-steering wide.
const DRIFT_SLIP_ANGLE_MAX_DEG: float = 26.0 ## Outward slip angle (deg) when steering deep into the apex.
const DRIFT_COYOTE_GRACE: float = 0.18 ## Grace window (s) preserving drift charge over bumps or brief low slip.
const DRIFT_TIER_1_TIME: float = 0.48 ## Weighted charge time (s) for Tier 1 (Cyan) mini-turbo.
const DRIFT_TIER_2_TIME: float = 1.15 ## Weighted charge time (s) for Tier 2 (Orange) super mini-turbo.
const DRIFT_TIER_3_TIME: float = 1.95 ## Weighted charge time (s) for Tier 3 (Magenta) ultra mini-turbo.
const DRIFT_TIER_DURATIONS: Array[float] = [0.0, 0.70, 1.10, 1.55]
const DRIFT_TIER_KICKS: Array[float] = [0.0, 2.8, 4.4, 6.0]
const DRIFT_TIER_SPEED_MULTS: Array[float] = [1.0, 1.18, 1.26, 1.34]
const DRIFT_TIER_ACCEL_MULTS: Array[float] = [1.0, 1.18, 1.22, 1.28]
const AI_CHICANE_STEER_THRESHOLD: float = -0.35 ## Counter-steer level where AI prepares to switch drift side.
const AI_CHICANE_HOLD_TIME: float = 0.22 ## Hold time (s) before AI releases and re-locks drift in chicanes.
const BOOST_COYOTE_AIR_TIME: float = 0.16 ## Air-time grace (s) keeping manual boost alive over micro-bumps.
const BOOST_IGNITE_KICK: float = 2.0 ## Instant forward kick (m/s) when manual boost ignites.
const BOOST_IGNITE_COOLDOWN: float = 0.45 ## Cooldown (s) preventing tap-spamming manual boost kicks.
const MAX_AIR_BANK_RAD: float = 0.314159 ## Max upright air roll bank (~18 deg) on jumps.
## A sender clock is its own process uptime, so a single absurd stamp must not
## permanently reject every later packet. A backwards jump larger than this is
## treated as a clock reset and re-baselined; normal reordering stays rejected.
const NET_CLOCK_RESET_MS: int = 60_000
## A peer that joins but never streams a state must not stay solid at its
## spawn point. Give the first packet a generous grace, then drop the body.
const GHOST_STREAM_TIMEOUT_MS: int = 1500
## How long a ghost that HAD streamed state stays solid at its last received
## pose while packets are late. 250 ms used to make a real player intangible
## during ordinary jitter - the phase-through the owner complained about. The
## ghost freezes (no prediction) but keeps the GHOST layer for this window.
const GHOST_STALE_SOLID_MS: int = GHOST_STREAM_TIMEOUT_MS
## A ghost is placed by script, not by move_and_slide, so a large interpolation
## step could jump it to the far side of a solid cart in one tick. Steps longer
## than this are sliced and tested against PLAYER/GHOST bodies. Steady 60 Hz
## motion stays well under the slice size, so a normal race pays nothing.
const GHOST_MAX_STEP: float = 1.1
## Single-tick travel guard. move_and_slide() already sweeps each collider
## (measured: no pass-through through a 0.12 m wall, a 0.67 m crate or a 2.26 m
## cart at 26.3 m/s at both 60 Hz and 20 Hz). This cap only catches a corrupted
## solver/network velocity that would move more than a body length per tick -
## a distance no collision response is designed around.
const MAX_SINGLE_TICK_TRAVEL: float = 2.0
## A finite but hostile/desynced network impulse must still land inside one
## believable hit. The gameplay speed clamp then trims the horizontal result.
const MAX_NET_IMPULSE: float = 64.0
const MAX_NET_VERTICAL_IMPULSE: float = 8.0
const WORLD_BOUND_SQ: float = 5000.0 * 5000.0

signal net_push_requested(prop: Node, direction: Vector3, kick: float)
signal horn_requested()
signal drift_tier_reached(tier: int)
signal drift_boost_fired(tier: int)

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
@export var brake_power: float = 34.0 ## Speed removed per second while braking (m/s^2).
@export var brake_lateral_grip: float = 16.0 ## Sideways bite while braking, so a stop also kills a slide.
@export var friction: float = 6.0 ## Speed lost per second when coasting (m/s^2).
@export var min_turn_speed: float = 2.2 ## Speed (m/s) at which steering reaches full authority.

@export_group("Grip & Drift")
@export var lateral_grip: float = 13.5 ## How fast sideways slip is cancelled (m/s^2).
@export var drift_grip: float = 2.5 ## Lateral grip while the handbrake is held (m/s^2).
@export var slip_drag: float = 0.9 ## Forward speed lost per second per m/s of lateral slide.
@export var drift_detection_threshold: float = 2.0 ## Sideways speed (m/s) that counts as drifting.
@export var landing_stability_strength: float = 0.6 ## Fraction of sideways speed removed on landing (0-1).
@export var slip_grip_falloff_start: float = 3.5 ## Sideways speed (m/s) where lateral grip starts to saturate.
@export var slip_grip_falloff_end: float = 10.0 ## Sideways speed (m/s) where grip falloff bottoms out.
@export var slip_grip_falloff_min: float = 0.45 ## Fraction of lateral grip left at full slide (0-1).

@export_group("Surface")
@export_range(0.05, 2.0, 0.01) var surface_grip: float = 1.0 ## Grip multiplier from the surface under the cart (1.0 = dry road).

@export_group("Steering & Air")
@export var steering_speed: float = 2.9 ## Max yaw rate (radians/second).
@export var high_speed_steering_scale: float = 0.86 ## Steering multiplier at top speed (0-1).
@export_group("Steering Feel")
@export var steer_attack: float = 18.0 ## How fast digital/keyboard steering reaches lock.
@export var steer_release: float = 21.0 ## How fast it returns to centre.
@export var steer_curve: float = 1.15 ## >1 gives finer control near centre, full lock at the edge.
@export var weight_transfer_steering: float = 0.14 ## Turn-in gain under braking (no throttle understeer penalty).
@export var air_control_strength: float = 0.65 ## Responsive yaw steering authority while airborne (0-1).
@export var gravity: float = 22.0 ## Downward acceleration (m/s^2).
@export var extra_fall_gravity: float = 1.6 ## Gravity multiplier while falling, for snappy landings.

@export_group("Collision Recoil")
@export var impact_speed_loss: float = 0.35 ## Fraction of impact speed lost on a legacy vehicle hit (0-1).
@export var impact_recoil: float = 0.32 ## Fraction of impact speed bounced away from a legacy vehicle.
@export var max_recoil_speed: float = 3.0 ## Cap on the legacy vehicle recoil impulse (m/s).
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
@export var drift_boost_min_charge: float = 0.48 ## Seconds of committed drift before a Tier 1 mini-turbo.
@export var drift_boost_duration: float = 0.70 ## Seconds a Tier 1 mini-turbo lasts.
@export var drift_boost_kick: float = 2.8 ## Instant forward speed (m/s) when a Tier 1 mini-turbo fires.
@export var drift_boost_speed_multiplier: float = 1.18 ## Top speed multiplier during a Tier 1 mini-turbo.
@export var drift_boost_accel_multiplier: float = 1.18 ## Acceleration multiplier during a Tier 1 mini-turbo.
@export var drift_boost_slip_threshold: float = 2.0 ## Sideways speed (m/s) that counts as charging.
@export var drift_boost_fov_punch: float = 4.0 ## Camera FOV kick when a Tier 1 mini-turbo fires.

@export_group("Impact Feel")
@export var crash_hit_stop: float = 0.09 ## Crash hit-stop in seconds (single player only).
@export var heavy_impact_hit_stop_min: float = 0.035 ## Shortest heavy-impact hit-stop (s).
@export var heavy_impact_hit_stop_max: float = 0.09 ## Longest heavy-impact hit-stop (s).
@export var heavy_impact_threshold: float = 0.5 ## Impact fraction of top speed that counts as heavy.
@export var hit_stop_time_scale: float = 0.05 ## World speed during hit-stop (1.0 = disabled).

@export_group("Airborne & Crash")
@export var enable_air_tumble: bool = true ## Airborne flight attitude stabilization and inverted crash check.
@export var air_tumble_strength: float = 1.0 ## Flight attitude scale (0-2).
@export var airborne_time_threshold: float = 0.25 ## Air time (s) before entering the airborne flight state.
@export var upside_down_dot_threshold: float = 0.05 ## Landing up-alignment below this (genuinely inverted) = crash.
@export var crash_cooldown: float = 0.65 ## Seconds of stunned sliding after an inverted crash.
@export var auto_flip_duration: float = 0.25 ## Seconds to flip upright during recovery.

@export_group("Suspension & Terrain")
@export var slope_follow_strength: float = 1.0 ## 0-1: how strongly the chassis follows the support plane.
@export var slope_smooth_speed: float = 12.0 ## How quickly grounded suspension follows terrain.
@export var slope_gravity_scale: float = 0.30 ## Share of gravity pulling along the four-point support plane.
@export var slope_lateral_gravity_scale: float = 0.15 ## Camber pull across the four-point support plane.
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
## The catalog id currently on the mesh, kept so a tag-colour change can rebuild
## only the paint without re-reading the selection.
var _current_vehicle_id: String = ""

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
## Last finite, in-bounds pose. A corrupt body transform is recovered here
## instead of being fed to move_and_slide or the wheel raycasts.
var _last_safe_position: Vector3 = Vector3.ZERO
var _last_safe_yaw: float = 0.0
var _frame_start_velocity: Vector3 = Vector3.ZERO
var _prev_velocity: Vector3 = Vector3.ZERO
var _input_locked_now: bool = false
var _impact_timer: float = 0.0
## Seconds of reduced steering left from the last network/prop bump.
var _bump_timer: float = 0.0
## Wall-clock deadline for `_bump_timer`. A timer that only decrements in
## _physics_process can freeze at its last value when the race ends and physics
## is switched off; the deadline guarantees the penalty still expires.
var _bump_expire_ms: int = 0
## Wall-clock end of the current bump chain (see _arm_bump_penalty). Kept
## separate from the penalty deadline so repeated contacts cannot re-arm it.
var _bump_chain_end_ms: int = 0
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

# Hop, committed drift and 3-tier mini-turbo state.
var _drift_charge: float = 0.0
var _drift_charging: bool = false
var _drift_grace_timer: float = 0.0
var _drift_dir: int = 0 ## +1 = committed left drift, -1 = committed right drift, 0 = none.
var _last_emitted_drift_tier: int = 0
var _active_mini_boost_tier: int = 0
var _mini_boost_speed_mult: float = 1.18
var _mini_boost_accel_mult: float = 1.18
var _ai_chicane_timer: float = 0.0
var _hop_offset: float = 0.0
var _hop_vel: float = 0.0
var _hop_active: bool = false
var _was_handbraking: bool = false
var _was_manual_boosting: bool = false
var _boost_kick_cooldown: float = 0.0
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
	_last_safe_position = global_position
	_last_safe_yaw = rotation.y
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
	# Once its owner streams state, a ghost is solid to every local cart (GHOST
	# layer) so players cannot drive through each other between packets. The
	# ghost itself never runs physics: it is placed by _update_remote_state and
	# its mask stays 0, so it is never pushed by the world. The host's OBB
	# resolver owns the momentum exchange and the final separation.
	# A ghost is not an obstacle until its owner streams a state. A peer that
	# connects and then stalls in the loading screen used to leave a solid,
	# invisible cart parked at its spawn for the whole race.
	collision_layer = 0
	collision_mask = 0
	set_physics_process(true)
	set_process(false)
	contact_enabled = false
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
	if position.length_squared() > WORLD_BOUND_SQ:
		return false
	if sent_ms < 0:
		return false
	# Keep the ghost's heading finite and small: yaw is used by the host OBB
	# resolver and by lerp_angle, and an absurd-but-finite heading must not
	# wind up in either.
	yaw = wrapf(yaw, -PI, PI)
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
		rotation.y = wrapf(yaw, -PI, PI)
		reset_physics_interpolation()
	contact_enabled = not race_finished
	# Publish solidity with the packet instead of waiting for the next
	# interpolation tick, so a freshly arrived ghost is solid immediately.
	collision_layer = CollisionLayers.GHOST if contact_enabled else 0
	return true


func mark_race_finished() -> void:
	## Called once when a remote cart crosses the line. A finished cart keeps
	## streaming state, so this must stay sticky across later packets.
	race_finished = true
	contact_enabled = false
	collision_layer = 0
	# A finished cart no longer gets guaranteed physics ticks, so clear the
	# steering penalty here rather than leaving it frozen for a reuse/reset.
	_bump_timer = 0.0
	_bump_expire_ms = 0
	_bump_chain_end_ms = 0


func setup_ai(vehicle_id: String) -> void:
	## AI uses the same physical controller and catalog stats as a human. Only
	## the input source and collision layer differ so every cart can see it.
	ai_mode = true
	remove_from_group("player")
	add_to_group("ai_player")
	collision_layer = CollisionLayers.GHOST
	collision_mask = (CollisionLayers.WORLD | CollisionLayers.PLAYER
		| CollisionLayers.GHOST | CollisionLayers.SOLID_PROP)
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
	var now: int = Time.get_ticks_msec()
	if not _net_has_sample:
		# A peer that connected but has not streamed yet is not an obstacle;
		# after the grace period stop pretending it is a parked kart.
		if now - _net_last_receive_ms > GHOST_STREAM_TIMEOUT_MS:
			contact_enabled = false
			collision_layer = 0
		return
	if not _net_sample_position.is_finite():
		# Only a corrupt pipeline can get here (set_net_state validates), but a
		# bad stored sample must never move the ghost or keep it solid.
		_net_has_sample = false
		contact_enabled = false
		collision_layer = 0
		return
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
	# Cap prediction at 100 ms; 250 ms at 45 m/s was an 11 m overshoot.
	var predict_ms: float = clampf(float(age_ms), 0.0, 100.0)
	var target: Vector3 = _net_sample_position + velocity * (predict_ms / 1000.0)
	var target_yaw: float = _net_sample_yaw + yaw_rate * (predict_ms / 1000.0)
	if not target.is_finite() or not is_finite(target_yaw):
		target = _net_sample_position
		target_yaw = _net_sample_yaw
		velocity = Vector3.ZERO
	var stale: bool = age_ms > 250
	if stale:
		# Late packet: freeze the ghost at its last authoritative pose instead
		# of extrapolating, but keep it SOLID until the stream timeout. The
		# host owns the momentum exchange; a client must never phase through a
		# peer because its local prediction ran out of data.
		target = _net_sample_position
		target_yaw = _net_sample_yaw
		velocity = Vector3.ZERO
	contact_enabled = not race_finished and age_ms <= GHOST_STALE_SOLID_MS
	collision_layer = 0 if not contact_enabled else CollisionLayers.GHOST
	if not global_position.is_finite():
		# A NaN pose must not survive into the next interpolation or the layer
		# bookkeeping that makes the ghost solid.
		global_position = target
		rotation.y = target_yaw
		reset_physics_interpolation()
		return
	var blend: float = 1.0 - exp(-16.0 * delta)
	# The ghost is script-placed, so a big prediction correction could hop it
	# straight through a local cart. Slice only the long steps; normal motion
	# takes the cheap single-lerp path.
	_move_ghost_towards(target, blend)
	rotation.y = lerp_angle(rotation.y, target_yaw, blend)
	net_velocity = velocity


func _move_ghost_towards(target: Vector3, blend: float) -> void:
	var current: Vector3 = global_position
	var next: Vector3 = current.lerp(target, blend)
	if not next.is_finite():
		return
	var motion: Vector3 = next - current
	var distance: float = motion.length()
	if distance <= GHOST_MAX_STEP:
		global_position = next
		return
	var steps: int = mini(int(ceil(distance / GHOST_MAX_STEP)), 12)
	var slice: Vector3 = motion / float(steps)
	# A ghost keeps mask 0 so the world can never push it. Borrow the cart
	# layers for the slice test only: this is a client-side visual guarantee
	# that the ghost never teleports through another player between packets;
	# the host still owns the actual impulse.
	var saved_mask: int = collision_mask
	collision_mask = CollisionLayers.PLAYER | CollisionLayers.GHOST
	for i in steps:
		if test_move(global_transform, slice):
			break
		global_position += slice
	collision_mask = saved_mask


func set_vehicle_id(vehicle_id: String) -> void:
	## Rebuild the visual for a remote player's chosen vehicle and remember its
	## mass so car-to-car impacts use the right inertia. The mass must come
	## from the composed entry, not the bare chassis: a racing ghost carries
	## the session's stat build (the host relays it with the map id), and
	## without it the host resolved that client's contacts 72-144 kg light.
	var entry: Dictionary = VehicleCatalog.find(vehicle_id)
	if entry.is_empty():
		return
	var visual: Dictionary = _visual_entry(entry)
	_current_vehicle_id = str(entry.get("id", ""))
	_profile_mass = maxf(float(visual.get("mass", REFERENCE_MASS)), 1.0)
	# The host's OBB resolver reads these extents for every ghost. Without
	# refreshing them here a remote truck was resolved as the default 1.5 x
	# 2.26 body, so its bumper passed through cars and it could shove cars it
	# was not touching.
	_apply_vehicle_dimensions(visual)
	_apply_vehicle_visual_for(visual)
	_resize_collision(visual)


func reapply_vehicle(vehicle_id: String) -> void:
	## Switch this LOCAL cart to another catalog vehicle at runtime. Used when
	## the race host assigns one car to everyone. Rebuilds visuals, collider,
	## derived stats and feedback (audio/skid width) from pristine values.
	var base: Dictionary = VehicleCatalog.find(vehicle_id)
	if base.is_empty():
		return
	_current_vehicle_id = str(base.get("id", ""))
	var entry: Dictionary = _visual_entry(base)
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


func get_drift_tier() -> int:
	## Current mini-turbo tier (0..3) reached by `_drift_charge`.
	if _drift_charge >= DRIFT_TIER_3_TIME:
		return 3
	if _drift_charge >= DRIFT_TIER_2_TIME:
		return 2
	if _drift_charge >= DRIFT_TIER_1_TIME:
		return 1
	return 0


func get_drift_charge_ratio() -> float:
	## Overall 0.0..1.0 drift charge ratio toward Tier 3 (`DRIFT_TIER_3_TIME = 1.95s`).
	## Tier 1 unlocks at ~0.246 (`0.48 / 1.95`), Tier 2 at ~0.590 (`1.15 / 1.95`),
	## and Tier 3 at `1.0`.
	return clampf(_drift_charge / DRIFT_TIER_3_TIME, 0.0, 1.0)


func get_drift_direction() -> int:
	## Committed drift direction: `+1` left, `-1` right, `0` none.
	return _drift_dir


func get_active_drift_boost_tier() -> int:
	## Tier (1..3) of the currently burning drift mini-turbo, or `0` if inactive.
	return _active_mini_boost_tier if _mini_boost_timer > 0.0 else 0


func is_handbraking() -> bool:
	## Effective handbrake state respecting AI, remote ghosts, input lock, pause
	## and `GameSettings.drift_toggle`.
	if remote_mode or current_state == CartState.CRASHED or current_state == CartState.RECOVERY:
		return false
	if ai_mode:
		return ai_handbrake
	if _input_locked_now or Network.input_locked:
		return false
	if is_inside_tree() and get_tree().paused:
		return false
	if GameSettings.drift_toggle:
		return _handbrake_toggle_on
	return Input.is_action_pressed("handbrake")


func get_throttle_input() -> float:
	## Effective 0.0..1.0 forward throttle respecting AI, remote ghosts, input
	## lock and pause.
	if remote_mode or current_state == CartState.CRASHED or current_state == CartState.RECOVERY:
		return 0.0
	if ai_mode:
		return clampf(ai_throttle, 0.0, 1.0)
	if _input_locked_now or Network.input_locked:
		return 0.0
	if is_inside_tree() and get_tree().paused:
		return 0.0
	return clampf(Input.get_action_strength("accelerate"), 0.0, 1.0)


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
	if not velocity.is_finite():
		velocity = Vector3.ZERO
	# Also nudge the visible pose so the hit reads immediately.
	_susp_vel += minf(push * 0.035, 0.35)


func apply_vehicle_impulse(impulse: Vector3) -> void:
	## Host-resolved momentum impulse for a two-body car collision.
	if remote_mode or not is_inside_tree() or not impulse.is_finite():
		return
	if impulse.length_squared() < 0.0001:
		return
	# The shared solver already scaled the impulse by mass and turned it into a
	# delta-v, so the gameplay cap must not truncate heavy hits. This is not a
	# gameplay cap: it only stops a corrupt/desynced value from moving the body
	# further in one tick than any collider can be swept across. The horizontal
	# clamp below keeps the same top speed the local controller enforces.
	impulse = impulse.limit_length(MAX_NET_IMPULSE)
	impulse.y = clampf(impulse.y, -MAX_NET_VERTICAL_IMPULSE,
		MAX_NET_VERTICAL_IMPULSE)
	if impulse.length_squared() < 0.0001:
		return
	velocity += impulse
	if not velocity.is_finite():
		velocity = Vector3.ZERO
	_clamp_horizontal_speed()
	_impact_timer = maxf(_impact_timer, 0.08)
	_susp_vel += minf(impulse.length() * 0.03, 0.30)
	var strength: float = impulse.length()
	if _camera_rig != null:
		_camera_rig.add_shake(clampf(strength * 0.06, 0.05, 0.4))
	if strength >= 3.0:
		_trigger_hit_stop(lerpf(0.035, 0.06, clampf((strength - 3.0) / 3.5, 0.0, 1.0)))
	if _feedback != null:
		_feedback.on_collision(clampf(strength / maxf(max_speed, 1.0), 0.15, 0.85))


func apply_bump(impulse: Vector3, duration: float) -> void:
	## Short, forgiving shove used by network car contact and prop bumps.
	## It only ever adds velocity: a bump must never stop the kart dead, spin it
	## or flip it. Steering authority is briefly softened so the hit reads
	## without taking the wheel away for long.
	if remote_mode or not impulse.is_finite():
		return
	var kick: Vector3 = impulse.limit_length(BUMP_MAX_IMPULSE)
	# Keep a bump from becoming a launch or a tumble trigger.
	kick.y = clampf(kick.y, -1.0, 1.2)
	if kick.length_squared() < 0.0001:
		return
	var before: Vector2 = Vector2(velocity.x, velocity.z)
	var before_speed: float = before.length()
	velocity += kick
	if not velocity.is_finite():
		velocity = Vector3.ZERO
	# If the impulse cancelled almost all forward motion, keep a residual along
	# the old heading. This is the difference between a bump and a handbrake.
	var after: Vector2 = Vector2(velocity.x, velocity.z)
	if before_speed > 0.5 and after.length() < before_speed * 0.25:
		var heading: Vector2 = before / before_speed
		velocity.x = heading.x * before_speed * 0.25
		velocity.z = heading.y * before_speed * 0.25
	var hold: float = duration if is_finite(duration) and duration > 0.0 \
		else BUMP_DEFAULT_DURATION
	hold = clampf(hold, BUMP_MIN_DURATION, BUMP_MAX_DURATION)
	_arm_bump_penalty(hold)
	_impact_timer = maxf(_impact_timer, 0.08)
	var strength: float = kick.length()
	_susp_vel += minf(strength * 0.03, 0.30)
	_squash_impulse = maxf(_squash_impulse, clampf(strength * 0.08, 0.12, 0.5))
	if _camera_rig != null:
		_camera_rig.add_shake(clampf(strength * 0.05, 0.04, 0.30))
	if _feedback != null:
		_feedback.on_collision(clampf(strength / maxf(max_speed, 1.0), 0.12, 0.7))


func _arm_bump_penalty(hold: float) -> void:
	## Start or extend the reduced-steering window without letting a repeated
	## contact turn it into a lockout loop. The old rule ("take the longer of
	## the remaining penalty and this bump") was re-armed every tick by a
	## resting contact, so the penalty never decayed. A chain now has a hard
	## wall-clock end at BUMP_MAX_DURATION and then needs BUMP_CHAIN_QUIET
	## before it can open again; a second hit inside the chain never extends it
	## beyond that end.
	var now_ms: int = Time.get_ticks_msec()
	if _bump_timer <= 0.0 or now_ms >= _bump_expire_ms:
		_bump_expire_ms = 0
	if now_ms >= _bump_chain_end_ms + int(round(BUMP_CHAIN_QUIET * 1000.0)):
		_bump_chain_end_ms = now_ms + int(round(BUMP_MAX_DURATION * 1000.0))
	var end_ms: int = mini(now_ms + int(round(hold * 1000.0)), _bump_chain_end_ms)
	if end_ms <= now_ms:
		return
	_bump_expire_ms = maxi(_bump_expire_ms, end_ms)
	_bump_timer = maxf(_bump_timer,
		float(_bump_expire_ms - now_ms) / 1000.0)


@rpc("authority", "reliable")
func _net_apply_car_impulse(impulse: Vector3) -> void:
	## Sent from the host's local cart; its path matches every client's local
	## cart, so the correction lands on the cart that actually owns the physics.
	## Symmetric by construction: the host applied the very same delta-v to its
	## own body from the shared solver, and the client's local _process_collisions
	## skips remote carts, so the local physics step never adds a second impulse.
	if remote_mode or not is_inside_tree() or not impulse.is_finite():
		return
	# apply_vehicle_impulse() is the single entry point; it bounds the value and
	# the shared solver already owns the impulse scale.
	apply_vehicle_impulse(impulse)


@rpc("authority", "reliable")
func _net_apply_car_bump(normal: Vector3, push: float) -> void:
	if remote_mode or not normal.is_finite() or not is_finite(push):
		return
	# apply_vehicle_bump() already normalises and bounds the shove.
	apply_vehicle_bump(normal, push)


func _apply_vehicle_visual() -> Dictionary:
	## Swap the placeholder kart for the vehicle picked in the selector.
	var base: Dictionary = VehicleCatalog.find(GameSettings.selected_vehicle)
	if base.is_empty() and GameSettings.racing_scene_active():
		base = VehicleCatalog.racing_find(GameSettings.racing_vehicle_id())
	if base.is_empty() and GameSettings.racing_scene_active() \
			and Network.is_session_active():
		# Last resort for a corrupt save: the host's racing pick travelled with
		# the session config, so use it instead of dropping to the sandbox kart.
		base = VehicleCatalog.racing_find(Network.session_racing_car_id)
	if base.is_empty():
		base = VehicleCatalog.find(VehicleCatalog.DEFAULT_ID)
	if base.is_empty() or _mesh_root == null:
		return base
	_current_vehicle_id = str(base.get("id", ""))
	var entry: Dictionary = _visual_entry(base)
	_apply_vehicle_visual_for(entry)
	return entry


func _visual_entry(base: Dictionary) -> Dictionary:
	## Turn a catalog chassis into the entry this cart actually renders. Racing
	## choices (including the Shopping Cart inside a racing scene) are composed
	## with the active stat build; sandbox, cargo and minigame carts keep their
	## untouched catalog entry. Body paint is always the factory livery.
	var vehicle_id: String = str(base.get("id", ""))
	var compose_in_race: bool = VehicleCatalog.is_racing_id(vehicle_id) \
		or (GameSettings.racing_scene_active() and VehicleCatalog.is_racing_choice(vehicle_id))
	if not compose_in_race:
		return base
	return VehicleCatalog.compose_racing_entry(vehicle_id, _racing_allocation())


func _racing_allocation() -> Dictionary:
	## The local human player always runs their own saved Racing Garage build
	## instead of being overwritten by the host's session build. AI bots and
	## remote ghosts fall back to the session build when present.
	if not ai_mode and not remote_mode:
		return GameSettings.racing_allocation()
	if Network.is_session_active() \
			and not Network.session_racing_allocation.is_empty():
		return Network.session_racing_allocation
	return GameSettings.racing_allocation()


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
	## Soften extreme catalog steering multipliers: trucks remain weighty without
	## becoming unable to clear an ordinary corner at racing speed.
	steering_speed *= sqrt(maxf(float(entry.get("steering", 1.0)), 0.25))
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
	# Base compound collider: see COLLIDER_REFERENCE_* above for why the
	# divisors are larger than the scene capsule.
	var z_scale: float = clampf(length / COLLIDER_REFERENCE_LENGTH, 0.68, 1.55)
	var x_scale: float = clampf(width / COLLIDER_REFERENCE_WIDTH, 0.55, 1.35)
	var y_scale: float = clampf(height / COLLIDER_REFERENCE_HEIGHT, 0.55, 1.35)
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
	_has_collision_basis = false
	_update_collision_shapes()
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
	_sanitize_local_state()
	_impact_timer = maxf(_impact_timer - delta, 0.0)
	# The bump penalty is both decremented and bounded by a wall-clock
	# deadline. If physics stops (race finished, scene change, node paused)
	# the deadline still expires the stale lockout instead of freezing it.
	if _bump_timer > 0.0 and Time.get_ticks_msec() >= _bump_expire_ms:
		_bump_timer = 0.0
	_bump_timer = maxf(_bump_timer - delta, 0.0)
	# Guard the whole tick, not just the post-contact state: _update_drive
	# decomposes velocity and would spread one NaN into every component.
	if not velocity.is_finite():
		velocity = Vector3.ZERO
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
		_drift_dir = 0
		_was_handbraking = false
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, friction * delta)
		velocity.y -= gravity * delta
	elif current_state == CartState.RECOVERY:
		_drift_dir = 0
		_was_handbraking = false
		velocity.y -= gravity * delta
	else:
		_update_hop_and_drift_lock(delta, handbrake_held, raw_steer)
		_apply_steering(steer_input, raw_steer, handbrake_held, delta)
		_update_drive(delta, handbrake_held, raw_steer)
		velocity.y -= gravity * (extra_fall_gravity if velocity.y < 0.0 else 1.0) * delta
		_was_handbraking = handbrake_held
	_prev_velocity = velocity
	# move_and_slide() sweeps the compound body along this tick's motion, so a
	# 20 Hz step longer than the thinnest collider still cannot tunnel. The two
	# guards here only bound a corrupt solver/network velocity to a believable
	# single-tick distance before the sweep runs.
	_clamp_horizontal_speed()
	_limit_single_tick_travel(delta)
	floor_snap_length = 0.0 if velocity.y > 1.5 else 0.75
	move_and_slide()
	_clamp_horizontal_speed()
	_process_collisions()
	# A malformed impulse must never leave NaN/Inf in the body. Every later
	# frame (move_and_slide included) would consume it and poison the cart.
	if not velocity.is_finite():
		velocity = _prev_velocity if _prev_velocity.is_finite() else Vector3.ZERO
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


func _update_hop_and_drift_lock(delta: float, handbrake_held: bool,
		raw_steer: float) -> void:
	## Initiate a crisp visual suspension hop on handbrake rising edge and lock
	## `_drift_dir` (+1 left, -1 right) once steering commits at speed.
	var grounded_or_coyote: bool = (is_on_floor() and not _cart_roof_contact) \
		or _air_time <= HOP_COYOTE_TIME
	var forward_dir: Vector3 = -global_transform.basis.z
	forward_dir.y = 0.0
	if forward_dir.length_squared() > 0.0001:
		forward_dir = forward_dir.normalized()
	else:
		forward_dir = Vector3.FORWARD
	var fwd_speed: float = velocity.dot(forward_dir)
	if handbrake_held and not _was_handbraking and grounded_or_coyote \
			and fwd_speed > HOP_MIN_SPEED and _hop_offset <= 0.02:
		_hop_vel = HOP_INITIAL_VEL
		_hop_active = true
		_stretch_impulse = maxf(_stretch_impulse, 0.35)
	if not handbrake_held:
		return
	if _drift_dir == 0:
		if grounded_or_coyote and absf(raw_steer) > DRIFT_LOCK_STEER \
				and fwd_speed > DRIFT_LOCK_SPEED:
			_drift_dir = 1 if raw_steer > 0.0 else -1
			_ai_chicane_timer = 0.0
	elif ai_mode:
		if raw_steer * float(_drift_dir) < AI_CHICANE_STEER_THRESHOLD:
			_ai_chicane_timer += delta
			if _ai_chicane_timer > AI_CHICANE_HOLD_TIME:
				var chicane_kick: float = _release_drift_charge(fwd_speed)
				if chicane_kick > 0.0:
					velocity += forward_dir * chicane_kick
				_drift_dir = 1 if raw_steer > 0.0 else -1
				_ai_chicane_timer = 0.0
		else:
			_ai_chicane_timer = 0.0


func _update_drive(delta: float, handbrake_held: bool, raw_steer: float) -> void:
	## Drive along the actual support plane so uphill speed becomes launch speed,
	## and carve fast committed drift arcs without foot-braking on handbrake.
	# A cart roof is a flat CharacterBody floor, but it is not terrain: let the
	# cart slide off instead of accelerating along another vehicle. An external
	# vertical launch (blast shockwave, Smash knockback, Juke hop) also detaches
	# immediately so planar ground projection never wipes out velocity.y.
	var grounded: bool = is_on_floor() and not _cart_roof_contact and velocity.y <= 1.5
	var grip_scale: float = clampf(surface_grip, 0.0, 2.0)
	# Decouple longitudinal drive traction from lateral surface_grip so slick
	# surfaces like ice (0.40-0.45) stay fast and lively instead of feeling muddy.
	var drive_traction: float = lerpf(0.78, 1.0, clampf(surface_grip, 0.0, 1.0))
	if surface_grip > 1.0:
		drive_traction = lerpf(1.0, minf(surface_grip, 1.25), 0.5)
	var normal: Vector3 = get_floor_normal() if grounded else Vector3.UP
	if grounded and _support_count > 0 and _ground_normal.length_squared() > 0.01:
		normal = _ground_normal
	var forward_dir: Vector3 = -global_transform.basis.z
	var right_dir: Vector3 = global_transform.basis.x
	if grounded:
		## Keep the velocity tangent to the actual ramp. Rebuilding it on a
		## horizontal plane here used to erase the upward component at the lip.
		var flat_forward: Vector3 = Vector3(forward_dir.x, 0.0, forward_dir.z).normalized()
		forward_dir = flat_forward.slide(normal).normalized()
		right_dir = forward_dir.cross(normal).normalized()
	var fwd_speed: float = velocity.dot(forward_dir)
	var lat_speed: float = velocity.dot(right_dir)
	var speed_mult: float = 1.0
	var accel_mult: float = 1.0
	if boost_active:
		if _mini_boost_timer > 0.0 and not _manual_boost_active:
			speed_mult = _mini_boost_speed_mult
			accel_mult = _mini_boost_accel_mult
		elif _mini_boost_timer > 0.0 and _manual_boost_active:
			speed_mult = maxf(boost_speed_multiplier, _mini_boost_speed_mult)
			accel_mult = maxf(boost_acceleration_multiplier, _mini_boost_accel_mult)
		else:
			speed_mult = boost_speed_multiplier
			accel_mult = boost_acceleration_multiplier
	var eff_max_speed: float = max_speed * speed_mult
	var eff_accel: float = acceleration * accel_mult * drive_traction
	var throttle: float = ai_throttle if ai_mode else 0.0 if _input_locked_now else Input.get_action_strength("accelerate")
	var braking: float = ai_brake if ai_mode else 0.0 if _input_locked_now else Input.get_action_strength("brake")
	if braking > 0.05 and fwd_speed <= 0.5:
		_reverse_hold += delta
	else:
		_reverse_hold = 0.0

	var in_committed_drift: bool = grounded and handbrake_held \
		and _drift_dir != 0 and fwd_speed > 2.0
	if in_committed_drift:
		var planar_vel: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
		var planar_speed: float = planar_vel.length()
		if braking > 0.05:
			planar_speed = move_toward(planar_speed, 0.0,
				brake_power * braking * delta * grip_scale)
		elif throttle > 0.05:
			var drift_ratio: float = clampf(planar_speed / maxf(eff_max_speed, 0.1), 0.0, 1.0)
			var drift_accel_scale: float = clampf(1.0 - pow(drift_ratio, 2.2), 0.35, 1.0)
			planar_speed = move_toward(planar_speed, eff_max_speed,
				eff_accel * drift_accel_scale * throttle * delta)
		else:
			planar_speed = move_toward(planar_speed, 0.0,
				friction * 0.65 * delta * grip_scale)
		var travel_dir: Vector3 = planar_vel / planar_speed if planar_speed > 0.05 else forward_dir
		if throttle > 0.05:
			var drift_grade: float = clampf(-normal.dot(travel_dir), 0.0, 1.0)
			planar_speed += drift_grade * gravity * 0.85 * delta
		planar_speed += gravity * normal.dot(travel_dir) * slope_gravity_scale * delta
		planar_speed = maxf(planar_speed, 0.0)

		var into_turn: float = clampf(raw_steer * float(_drift_dir), -1.0, 1.0)
		var base_slip_deg: float = lerpf(DRIFT_SLIP_ANGLE_MIN_DEG,
			DRIFT_SLIP_ANGLE_MAX_DEG, (into_turn + 1.0) * 0.5)
		var slick_scale: float = clampf(1.0 / maxf(surface_grip, 0.45), 0.85, 1.55)
		var target_slip_rad: float = deg_to_rad(clampf(base_slip_deg * slick_scale, 12.0, 38.0))
		var target_vel_dir: Vector3 = (
			forward_dir * cos(target_slip_rad)
			+ right_dir * (float(_drift_dir) * sin(target_slip_rad))
		).normalized()
		var cur_yaw: float = atan2(travel_dir.x, travel_dir.z)
		var tgt_yaw: float = atan2(target_vel_dir.x, target_vel_dir.z)
		var carve_blend: float = 1.0 - exp(-DRIFT_CARVE_RATE * clampf(grip_scale, 0.45, 1.25) * delta)
		var new_yaw: float = lerp_angle(cur_yaw, tgt_yaw, carve_blend)
		var carved_dir: Vector3 = Vector3(sin(new_yaw), 0.0, cos(new_yaw))
		var raw_lat: float = (carved_dir * planar_speed).dot(right_dir)
		if absf(raw_lat) > drift_detection_threshold:
			planar_speed = move_toward(planar_speed, 0.0,
				DRIFT_COMMITTED_SLIP_DRAG * absf(raw_lat) * delta)
		var carved_vel: Vector3 = carved_dir * planar_speed
		fwd_speed = carved_vel.dot(forward_dir)
		lat_speed = carved_vel.dot(right_dir) \
			+ gravity * normal.dot(right_dir) * slope_lateral_gravity_scale * delta
		fwd_speed += _update_drift_boost(delta, grounded, fwd_speed, lat_speed,
			handbrake_held, raw_steer)
		if planar_speed <= 2.0:
			_drift_dir = 0
		velocity = forward_dir * fwd_speed + right_dir * lat_speed
	else:
		if braking > 0.05 and fwd_speed > 0.5:
			# Brake wins over throttle. Holding both should slow the kart, not
			# cancel out and keep it accelerating.
			fwd_speed = move_toward(fwd_speed, 0.0,
				brake_power * braking * delta * grip_scale)
			lat_speed = move_toward(lat_speed, 0.0,
				brake_lateral_grip * braking * delta * grip_scale)
		elif throttle > 0.05:
			var speed_ratio: float = clampf(fwd_speed / maxf(eff_max_speed, 0.1), 0.0, 1.0)
			var accel_scale: float = clampf(1.0 - pow(speed_ratio, 2.2), 0.35, 1.0)
			fwd_speed = move_toward(fwd_speed, eff_max_speed,
				eff_accel * accel_scale * throttle * delta)
		elif braking > 0.05 and _reverse_hold >= 0.12:
			fwd_speed = move_toward(fwd_speed, -reverse_speed,
				acceleration * 0.6 * drive_traction * braking * delta)
		else:
			fwd_speed = move_toward(fwd_speed, 0.0, friction * delta * grip_scale)
		if grounded and throttle > 0.05:
			var grade: float = clampf(-normal.dot(forward_dir), 0.0, 1.0)
			fwd_speed += grade * gravity * 0.85 * delta
		if grounded:
			fwd_speed += gravity * normal.dot(forward_dir) * slope_gravity_scale * delta
			lat_speed += gravity * normal.dot(right_dir) * slope_lateral_gravity_scale * delta
		var release_kick: float = _update_drift_boost(delta, grounded, fwd_speed,
			lat_speed, handbrake_held, raw_steer)
		fwd_speed += release_kick
		var grip: float = lateral_grip * grip_scale
		if grounded and handbrake_held:
			# Handbrake lowers lateral grip for drift initiation without applying
			# any foot-brake deceleration.
			grip = drift_grip * grip_scale
		elif grounded and _mini_boost_timer > 0.0:
			# Crisp hook-up when rocketing out of an apex on a mini-turbo.
			grip *= 1.45
		if grounded and not handbrake_held:
			var steering_bite: float = clampf(absf(fwd_speed) / maxf(max_speed, 1.0), 0.0, 1.0)
			grip *= 1.0 + absf(raw_steer) * steering_bite * 0.30
			# Tires must supply the centripetal force demanded by the current yaw
			# rate. A flat grip cap made fast carts rotate in place while their
			# velocity kept going straight, especially with heavy vehicles.
			var speed_fraction: float = clampf(absf(fwd_speed) / maxf(max_speed, 0.001), 0.0, 1.0)
			var steering_authority: float = lerpf(1.0, high_speed_steering_scale, speed_fraction)
			var cornering_demand: float = absf(steer_smoothed * steering_speed
				* steering_authority * fwd_speed)
			grip = maxf(grip, cornering_demand * 0.94 * grip_scale)
		if not grounded:
			grip *= 0.25
		else:
			var active_slip_drag: float = DRIFT_COMMITTED_SLIP_DRAG if handbrake_held else slip_drag
			if absf(lat_speed) > drift_detection_threshold:
				fwd_speed = move_toward(fwd_speed, 0.0,
					active_slip_drag * absf(lat_speed) * delta)
			var slip_speed: float = absf(lat_speed)
			var slip_t: float = clampf((slip_speed - slip_grip_falloff_start)
				/ maxf(slip_grip_falloff_end - slip_grip_falloff_start, 0.001), 0.0, 1.0)
			grip *= lerpf(1.0, clampf(slip_grip_falloff_min, 0.0, 1.0), slip_t * slip_t)
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


func _update_drift_boost(delta: float, grounded: bool, fwd_speed: float,
		lat_speed: float, handbrake_held: bool, raw_steer: float) -> float:
	## 3-tier drift mini-turbo with 0.18s coyote grace over bumps or momentary
	## low slip, counter-steer weighted charge rate, and mid-air release support.
	if handbrake_held:
		var can_charge: bool = grounded \
			and current_state == CartState.DRIVING \
			and fwd_speed > 3.5 \
			and (_drift_dir != 0 or absf(lat_speed) >= drift_boost_slip_threshold)
		if can_charge:
			var charge_rate: float = 1.0
			if _drift_dir != 0:
				var into_turn: float = clampf(raw_steer * float(_drift_dir), -1.0, 1.0)
				charge_rate = lerpf(0.85, 1.35, (into_turn + 1.0) * 0.5)
			_drift_charge += delta * charge_rate
			_drift_charging = true
			_drift_grace_timer = DRIFT_COYOTE_GRACE
			var reached_tier: int = get_drift_tier()
			while _last_emitted_drift_tier < reached_tier:
				_last_emitted_drift_tier += 1
				drift_tier_reached.emit(_last_emitted_drift_tier)
			return 0.0
		if _drift_charging:
			_drift_grace_timer -= delta
			if _drift_grace_timer <= 0.0:
				_drift_charge = 0.0
				_drift_charging = false
				_drift_grace_timer = 0.0
				_last_emitted_drift_tier = 0
				if grounded:
					_drift_dir = 0
		return 0.0

	# Handbrake released: fire any earned tier (including mid-air releases!).
	var kick: float = _release_drift_charge(fwd_speed)
	_drift_dir = 0
	_ai_chicane_timer = 0.0
	return kick


func _release_drift_charge(fwd_speed: float) -> float:
	var kick: float = 0.0
	var tier: int = get_drift_tier()
	var can_award: bool = _drift_charging \
		and tier >= 1 \
		and current_state != CartState.CRASHED \
		and current_state != CartState.RECOVERY
	if can_award:
		var duration: float = DRIFT_TIER_DURATIONS[tier]
		var tier_kick: float = DRIFT_TIER_KICKS[tier]
		var tier_speed_mult: float = DRIFT_TIER_SPEED_MULTS[tier]
		var tier_accel_mult: float = DRIFT_TIER_ACCEL_MULTS[tier]
		_active_mini_boost_tier = tier
		_mini_boost_speed_mult = tier_speed_mult
		_mini_boost_accel_mult = tier_accel_mult
		_mini_boost_timer = maxf(_mini_boost_timer, duration)
		boost_active = true
		_was_boosting = true
		var cap: float = max_speed * tier_speed_mult
		if fwd_speed < cap:
			kick = minf(tier_kick, cap - fwd_speed)
		drift_boost_fired.emit(tier)
		# If CartFeedback is absent (e.g. isolated unit test), still punch camera FOV directly.
		if _feedback == null and _camera_rig != null:
			_camera_rig.punch_fov(drift_boost_fov_punch + float(tier - 1) * 2.0)
	_drift_charge = 0.0
	_drift_charging = false
	_drift_grace_timer = 0.0
	_last_emitted_drift_tier = 0
	return kick


func _apply_steering(steer_input: float, raw_steer: float,
		handbrake_held: bool, delta: float) -> void:
	var forward_dir: Vector3 = -global_transform.basis.z
	var fwd_speed: float = velocity.dot(forward_dir)
	var planar_speed: float = Vector2(velocity.x, velocity.z).length()
	var speed_ref: float = maxf(absf(fwd_speed), planar_speed if not is_on_floor() else 0.0)
	var speed_frac: float = clampf(speed_ref / maxf(max_speed, 0.001), 0.0, 1.0)
	var start_factor: float = clampf(speed_ref / min_turn_speed, 0.0, 1.0)
	var high_speed_factor: float = lerpf(1.0, high_speed_steering_scale, speed_frac)
	var authority: float = start_factor * high_speed_factor
	# Weight transfer sharpens turn-in under braking without penalising throttle.
	var weight_transfer: float = clampf(_longitudinal_accel / maxf(gravity, 0.001),
		-1.0, 1.0)
	authority *= clampf(1.0 - weight_transfer * weight_transfer_steering, 0.96, 1.25)
	if _bump_timer > 0.0:
		authority *= BUMP_STEER_AUTHORITY
	if not is_on_floor():
		authority *= air_control_strength
	if _drift_dir != 0 and handbrake_held and fwd_speed > 1.5:
		var into_turn: float = clampf(raw_steer * float(_drift_dir), -1.0, 1.0)
		var drift_yaw_scale: float = lerpf(0.45, 1.38, (into_turn + 1.0) * 0.5)
		rotate_y(float(_drift_dir) * steering_speed * authority * drift_yaw_scale * delta)
		return
	var dir_sign: float = signf(fwd_speed)
	if not is_on_floor() and absf(dir_sign) < 0.01 and planar_speed > 0.5:
		dir_sign = 1.0
	var yaw_step: float = steer_input * steering_speed * authority * dir_sign * delta
	rotate_y(yaw_step)
	if not is_on_floor() and absf(yaw_step) > 0.0001:
		var horiz_vel: Vector3 = Vector3(velocity.x, 0.0, velocity.z).rotated(Vector3.UP, yaw_step * 0.28)
		velocity.x = horiz_vel.x
		velocity.z = horiz_vel.z


func _process_collisions() -> void:
	## Solid hits keep tangent speed, add a small bounce and kick the
	## suspension in the direction of the actual contact normal.
	_cart_roof_contact = false
	# The cooldown absorbs repeated hits from the SAME shove; it must not
	# suppress physics. Returning here used to drop every contact for 0.12 s
	# after one hit, so a cart that had just tapped a rival lost its wall
	# response too, and a pair only exchanged momentum on the side whose timer
	# had already expired (the timers are per cart, not per pair).
	var feedback_ready: bool = _impact_timer <= 0.0
	var handled: Dictionary = {}
	for i in get_slide_collision_count():
		var collision: KinematicCollision3D = get_slide_collision(i)
		var hit: Object = collision.get_collider()
		var hit_node: Node = hit as Node
		# Cones are launched by the push sensor and must never slow the kart.
		# Solid crates do block it, but only softly (see below).
		var solid_prop: bool = false
		if hit_node != null and hit_node.is_in_group("pushable"):
			solid_prop = _is_solid_prop(hit_node)
			if not solid_prop:
				continue
		var normal: Vector3 = collision.get_normal()
		if not normal.is_finite():
			continue
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
		elif solid_prop and hit is RigidBody3D:
			# A launched crate can hit a stationary kart too; use its motion so
			# the softening response reads in both directions.
			other_velocity = (hit as RigidBody3D).linear_velocity
		elif hit_node != null and hit_node.has_meta("vehicle_mass"):
			other_vehicle = true
			other_mass = float(hit_node.get_meta("vehicle_mass"))
			other_velocity = hit_node.get_meta("vehicle_velocity", Vector3.ZERO)
		# A legacy meta-bodied vehicle can carry a hand-written mass/velocity;
		# a corrupt value must not reach the impulse maths or the visual spring
		# state through impact_speed (a NaN there used to stick in _base_pitch).
		if not is_finite(other_mass) or other_mass < 0.0:
			other_mass = 0.0
		if not other_velocity.is_finite():
			other_velocity = Vector3.ZERO
		if normal.y > 0.6 and not other_vehicle:
			continue
		if other_vehicle and normal.y > 0.6:
			# Standing on a roof: keep the horizontal separation response but
			# do not treat the other cart as drivable ground next frame.
			_cart_roof_contact = true
		if other_vehicle:
			var hit_id: int = hit.get_instance_id()
			if handled.has(hit_id):
				continue
			handled[hit_id] = true
			# A chassis can present an upward contact when a cart climbs its bumper.
			# Separate vehicles horizontally instead of treating that as a floor.
			var planar_normal := Vector3(normal.x, 0.0, normal.z)
			if planar_normal.length_squared() < 0.01 and hit is Node3D:
				planar_normal = global_position - (hit as Node3D).global_position
				planar_normal.y = 0.0
			if planar_normal.length_squared() > 0.001:
				normal = planar_normal.normalized()
		var impact_speed: float = maxf(-(_prev_velocity - other_velocity).dot(normal), 0.0)
		if not is_finite(impact_speed):
			continue
		if impact_speed < (0.05 if other_vehicle else min_impact_speed):
			continue
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
		if not other_vehicle:
			# Walls and solid crates: keep the slide and replace the harsh stop
			# with a small bounce. This is the forgiving arcade wall response.
			velocity = CartCollisionSystem.soften_wall_hit(self, normal, impact_speed)
		elif hit is CartPlayer:
			# Momentum-conserving two-body impulse. A heavy truck shoves a light
			# kart aside and both keep their speed instead of dying on contact.
			var pair_normal: Vector3 = -normal
			# The physics engine already separated this pair during
			# move_and_slide. The shared solver must only exchange momentum
			# here, or the pair double-separates and visibly jitters. It is
			# also given the pre-move closing speed: the live velocities have
			# already been flattened by that separation, so a head-on hit
			# would otherwise exchange almost nothing.
			CartCollisionSystem.resolve_pair(self, hit as CartPlayer,
				collision.get_position(), pair_normal, collision.get_depth(), false,
				impact_speed)
		else:
			# Legacy meta-bodied vehicle (minigame bots): keep the old momentum
			# exchange so their protocol does not change.
			var contact_speed: float = maxf(impact_speed, 0.35)
			var recoil: float = contact_speed * impact_recoil * recoil_scale \
				* (1.0 + own_share)
			velocity += normal * minf(recoil, max_recoil_speed * maxf(recoil_scale, 1.0)
				* (1.0 + own_share))
			var other_push: float = contact_speed * 0.78 * (own_mass / total_mass)
			if hit_node.has_meta("bump_velocity"):
				var bump: Vector3 = hit_node.get_meta("bump_velocity", Vector3.ZERO)
				hit_node.set_meta("bump_velocity", bump - normal * other_push)
			var loss: float = impact_speed * impact_speed_loss * loss_scale
			var planar: Vector3 = Vector3(velocity.x, 0.0, velocity.z).move_toward(
				Vector3.ZERO, loss)
			velocity.x = planar.x
			velocity.z = planar.z
		if feedback_ready:
			_give_impact_feedback(normal, impact_factor, other_vehicle, shake_scale)
		# Keep scanning: a car bump must not hide a wall contact in the same
		# frame. Only vehicle pairs are deduped; distinct world normals all count.
		continue


func _give_impact_feedback(normal: Vector3, impact_factor: float,
		other_vehicle: bool, shake_scale: float) -> void:
	## Visual and audio reaction to one contact: body tilt, suspension, camera
	## shake, hit-stop and the feedback layer. Split out of _process_collisions
	## so the impact cooldown can gate the reaction without gating the physics.
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


func _is_solid_prop(node: Node) -> bool:
	## Solid-prop rule in a session (same rule on host and client): crates
	## advertise SOLID_PROP, so they are STATIC obstacles in every peer's own
	## physics world. A client freezes them at the host's authoritative pose;
	## both sides resolve cart-vs-crate with the identical shape, so a client
	## can never disagree with the host about driving through one. Only the
	## crate's pushed motion comes from the host's prop sync - never the pass-
	## through test. Cones stay on PROP and never block the kart.
	var body: CollisionObject3D = node as CollisionObject3D
	return body != null and (body.collision_layer & CollisionLayers.SOLID_PROP) != 0


func _on_push_sensor_body_entered(body: Node3D) -> void:
	var prop := body as RigidBody3D
	if prop == null or not prop.is_in_group("pushable"):
		return
	_push_prop(prop)


func _push_prop(prop: RigidBody3D) -> void:
	## The sensor pops pushables away with an upward, spinning impulse. Cones
	## are non-blocking, but crates are also SOLID_PROP and still stop the kart
	## through the normal physics contact; the push only moves them.
	## A client sends the request and lets the host own the resulting motion,
	## but its own crate stays a solid static obstacle until that sync arrives.
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
	var top_mult: float = maxf(boost_speed_multiplier, _mini_boost_speed_mult)
	var cap: float = max_speed * top_mult + 2.0
	var horizontal := Vector2(velocity.x, velocity.z)
	if horizontal.length() > cap:
		horizontal = horizontal.normalized() * cap
		velocity.x = horizontal.x
		velocity.z = horizontal.y


func _sanitize_local_state() -> void:
	## Reject a corrupt body pose before it can reach move_and_slide, the wheel
	## raycasts or the host's contact list. A bad remote value is stopped at the
	## RPC boundary too; this is the last line of defence for the local body.
	var current: Vector3 = global_position
	if not current.is_finite() or current.length_squared() > WORLD_BOUND_SQ:
		var recovery: Vector3 = _last_safe_position
		if not recovery.is_finite() or recovery.length_squared() > WORLD_BOUND_SQ:
			recovery = _spawn_transform.origin
		global_position = recovery
		velocity = Vector3.ZERO
		_frame_start_velocity = Vector3.ZERO
		_prev_velocity = Vector3.ZERO
		reset_physics_interpolation()
	else:
		_last_safe_position = current
	if not is_finite(rotation.y):
		rotation.y = _last_safe_yaw
	else:
		_last_safe_yaw = rotation.y


func _limit_single_tick_travel(delta: float) -> void:
	## Bound one tick's motion to less than a cart length. The physics engine
	## already sweeps, so this never fires in normal play (26.3 m/s is 0.44 m at
	## 60 Hz); it exists so a finite-but-corrupt 200 m/s solver value cannot
	## cover a whole prop in one move_and_slide call.
	if not is_finite(delta) or delta <= 0.0:
		return
	var max_speed_now: float = MAX_SINGLE_TICK_TRAVEL / delta
	var speed_sq: float = velocity.length_squared()
	if not is_finite(speed_sq):
		velocity = Vector3.ZERO
		return
	if speed_sq > max_speed_now * max_speed_now:
		velocity = velocity * (max_speed_now / sqrt(speed_sq))


func _update_boost(delta: float, held: bool) -> void:
	_pad_burst_timer = maxf(_pad_burst_timer - delta, 0.0)
	_mini_boost_timer = maxf(_mini_boost_timer - delta, 0.0)
	_boost_kick_cooldown = maxf(_boost_kick_cooldown - delta, 0.0)
	if _mini_boost_timer <= 0.0:
		_active_mini_boost_tier = 0
		_mini_boost_speed_mult = drift_boost_speed_multiplier
		_mini_boost_accel_mult = drift_boost_accel_multiplier
	if not held:
		_boost_exhausted = false
	var grounded_for_boost: bool = is_on_floor() or _air_time < BOOST_COYOTE_AIR_TIME
	var state_allows_boost: bool = current_state == CartState.DRIVING \
		or (current_state == CartState.AIRBORNE_TUMBLE and _air_time < BOOST_COYOTE_AIR_TIME)
	var want_boost: bool = held \
		and state_allows_boost \
		and grounded_for_boost \
		and boost_amount > 0.0 \
		and not _boost_exhausted
	if boost_amount <= 0.0:
		_boost_exhausted = true
		_boost_toggle_on = false
	if want_boost:
		if not _was_manual_boosting:
			if _boost_kick_cooldown <= 0.0:
				_boost_kick_cooldown = BOOST_IGNITE_COOLDOWN
				var forward_dir: Vector3 = -global_transform.basis.z
				forward_dir.y = 0.0
				if forward_dir.length_squared() > 0.0001:
					forward_dir = forward_dir.normalized()
					var fwd_speed: float = velocity.dot(forward_dir)
					var cap: float = max_speed * boost_speed_multiplier
					if fwd_speed < cap:
						velocity += forward_dir * minf(BOOST_IGNITE_KICK, cap - fwd_speed)
			if _feedback != null and _pad_burst_timer <= 0.0:
				_feedback.on_boost_started()
			elif _feedback == null and _camera_rig != null and _pad_burst_timer <= 0.0:
				_camera_rig.punch_fov(4.5)
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
	_was_manual_boosting = want_boost
	boost_visual = lerpf(boost_visual, 1.0 if boost_active else 0.0, 1.0 - exp(-6.0 * delta))
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
	# Never leave a penalized state behind if this node is removed/reused.
	_bump_timer = 0.0
	_bump_expire_ms = 0
	_bump_chain_end_ms = 0


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
		# Gently auto-stabilize toward upright on jumps (<= 18 deg bank, slight
		# flight nose-arc) instead of barrel-rolling into a ramp crash. If an
		# external force genuinely inverted the chassis, let it stay inverted long
		# enough for _land_from_tumble() to register an inverted crash.
		var up_align_now: float = cos(_tumble_pitch) * cos(_tumble_roll)
		if up_align_now >= upside_down_dot_threshold:
			var horiz_speed: float = Vector2(velocity.x, velocity.z).length()
			var flight_arc_pitch: float = clampf(
				atan2(velocity.y, maxf(horiz_speed, 4.0)) * 0.38, -0.24, 0.22)
			var target_air_roll: float = clampf(
				-steer_input * MAX_AIR_BANK_RAD * 0.85,
				-MAX_AIR_BANK_RAD, MAX_AIR_BANK_RAD)
			var stab_blend: float = 1.0 - exp(-6.0 * delta)
			_tumble_pitch = lerp_angle(_tumble_pitch, flight_arc_pitch, stab_blend)
			_tumble_roll = lerp_angle(_tumble_roll, target_air_roll, stab_blend)
		else:
			_tumble_pitch = wrapf(_tumble_pitch + _tumble_pitch_rate * delta, -PI, PI)
			_tumble_roll = wrapf(_tumble_roll + _tumble_roll_rate * delta, -PI, PI)


func _enter_tumble(steer_input: float, speed: float) -> void:
	current_state = CartState.AIRBORNE_TUMBLE
	_tumble_pitch_rate = 0.0
	_tumble_roll_rate = 0.0
	var horiz_speed: float = maxf(speed, 4.0)
	_tumble_pitch = clampf(atan2(velocity.y, horiz_speed) * 0.22, -0.20, 0.18)
	_tumble_roll = clampf(-steer_input * MAX_AIR_BANK_RAD * 0.5,
		-MAX_AIR_BANK_RAD, MAX_AIR_BANK_RAD)


func _land_from_tumble() -> void:
	var chassis_up: Vector3 = (global_transform.basis
		* Basis.from_euler(Vector3(_tumble_pitch, 0.0, _tumble_roll))).y.normalized()
	var up_alignment: float = chassis_up.dot(Vector3.UP)
	if up_alignment < upside_down_dot_threshold:
		_enter_crashed(up_alignment)
	else:
		current_state = CartState.DRIVING


func _enter_crashed(up_dot: float) -> void:
	current_state = CartState.CRASHED
	is_drifting = false
	slide_amount = 0.0
	_crash_timer = crash_cooldown
	boost_active = false
	_manual_boost_active = false
	_was_manual_boosting = false
	_boost_toggle_on = false
	_handbrake_toggle_on = false
	_was_handbraking = false
	_drift_charge = 0.0
	_drift_charging = false
	_drift_grace_timer = 0.0
	_drift_dir = 0
	_last_emitted_drift_tier = 0
	_active_mini_boost_tier = 0
	_ai_chicane_timer = 0.0
	_hop_offset = 0.0
	_hop_vel = 0.0
	_hop_active = false
	_mini_boost_timer = 0.0
	_pad_burst_timer = 0.0
	_bump_timer = 0.0
	_bump_expire_ms = 0
	_bump_chain_end_ms = 0
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
		var launch_speed: float = Vector2(velocity.x, velocity.z).length()
		## A modest lip kick makes a fast ramp readable and rewarding without
		## turning low-speed bumps into uncontrolled launches.
		velocity.y += clampf((launch_speed - 7.0) * 0.075, 0.0, 1.5)
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
	var accelerating: bool = false
	var braking_now: bool = false
	if not remote_mode:
		if ai_mode:
			accelerating = ai_throttle > 0.05
			braking_now = ai_brake > 0.05
		elif not _input_locked_now and not Network.input_locked:
			accelerating = Input.is_action_pressed("accelerate")
			braking_now = Input.is_action_pressed("brake")
	if accelerating:
		accel_stretch = 1.0 - speed_frac
	elif braking_now:
		brake_squash = speed_frac
	if _hop_active or _hop_offset > 0.0 or _hop_vel > 0.0:
		_hop_offset += _hop_vel * delta
		_hop_vel -= HOP_GRAVITY * delta
		if _hop_offset <= 0.0 and _hop_vel <= 0.0:
			_hop_offset = 0.0
			_hop_vel = 0.0
			if _hop_active:
				_hop_active = false
				_squash_impulse = maxf(_squash_impulse, 0.24)
				_susp_vel -= 0.14
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
	_mesh_root.position.y = SUSPENSION_PIVOT_HEIGHT + _susp_pos + _hop_offset
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
	## Four-point terrain probe. These rays only shape the visual/gravity
	## support plane; the solid body still moves with the swept capsule, so a
	## ramp can never be tunnelled. Guard the ray origins anyway: a NaN origin
	## would make the physics server reject the query every tick.
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var base: Vector3 = global_position
	var normal_sum: Vector3 = Vector3.ZERO
	_support_count = 0
	if not base.is_finite() \
			or absf(global_transform.basis.determinant()) < 0.0001:
		_ground_normal = Vector3.UP
		for i in 4:
			_ground_support[i] = false
			_ground_heights[i] = 0.0
		return
	for i in 4:
		var origin: Vector3 = base + global_transform.basis * _wheel_offsets[i] + Vector3.UP * ground_probe_height
		if not origin.is_finite():
			_ground_support[i] = false
			_ground_heights[i] = 0.0
			continue
		_wheel_query.from = origin
		_wheel_query.to = origin + Vector3.DOWN * ground_probe_length
		var hit: Dictionary = space_state.intersect_ray(_wheel_query)
		_ground_support[i] = false
		_ground_heights[i] = 0.0
		if hit.is_empty():
			continue
		var normal: Vector3 = hit.normal as Vector3
		if not normal.is_finite() or normal.y < 0.45:
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


func reset_at(spawn_transform: Transform3D, restore_props: bool = false) -> void:
	## Full race-start reset at a given grid transform, granting full boost.
	_spawn_transform = spawn_transform
	_reset_cart(restore_props)


func reset_for_respawn() -> void:
	## Clear tumble/boost/crash state without teleporting to the grid spawn.
	## Preserves existing boost (minimum 25%) instead of refilling to 100%, so
	## driving off-track cannot be exploited for a free full boost bar.
	var keep: Transform3D = global_transform
	var preserved_boost: float = clampf(maxf(boost_amount, max_boost * 0.25), 0.0, max_boost)
	_reset_cart(false)
	boost_amount = preserved_boost
	global_transform = keep
	_last_safe_position = keep.origin
	_last_safe_yaw = keep.basis.get_euler().y
	# Respawn revives a racing cart, never a finished one: a crossed cart must
	# stay intangible for the rest of the race.
	contact_enabled = not race_finished
	collision_layer = 0 if race_finished or remote_mode \
		else (CollisionLayers.GHOST if ai_mode else CollisionLayers.PLAYER)
	reset_physics_interpolation()


func _reset_cart(restore_props: bool = true) -> void:
	velocity = Vector3.ZERO
	global_transform = _spawn_transform
	_last_safe_position = global_transform.origin
	_last_safe_yaw = global_transform.basis.get_euler().y
	reset_physics_interpolation()
	_mesh_root.scale = Vector3.ONE
	_mesh_root.rotation = Vector3.ZERO
	_mesh_root.position = Vector3(0.0, SUSPENSION_PIVOT_HEIGHT, 0.0)
	_squash_impulse = 0.0
	_stretch_impulse = 0.0
	_impact_timer = 0.0
	_bump_timer = 0.0
	_bump_expire_ms = 0
	_bump_chain_end_ms = 0
	is_drifting = false
	slide_amount = 0.0
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
	_was_manual_boosting = false
	_boost_kick_cooldown = 0.0
	_boost_exhausted = false
	_boost_toggle_on = false
	_handbrake_toggle_on = false
	_was_handbraking = false
	_drift_charge = 0.0
	_drift_charging = false
	_drift_grace_timer = 0.0
	_drift_dir = 0
	_last_emitted_drift_tier = 0
	_active_mini_boost_tier = 0
	_mini_boost_speed_mult = drift_boost_speed_multiplier
	_mini_boost_accel_mult = drift_boost_accel_multiplier
	_ai_chicane_timer = 0.0
	_hop_offset = 0.0
	_hop_vel = 0.0
	_hop_active = false
	_mini_boost_timer = 0.0
	_manual_boost_active = false
	_cancel_hit_stop()
	_air_time = 0.0
	_tumble_pitch = 0.0
	_tumble_roll = 0.0
	_tumble_pitch_rate = 0.0
	_tumble_roll_rate = 0.0
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
	_has_collision_basis = false
	_update_collision_shapes()
	if _camera_rig != null:
		_camera_rig.reset_camera()
	if _feedback != null:
		_feedback.reset_feedback()
	# Props are host-authoritative in a session; a client reset must not snap
	# frozen bodies around locally.
	if not (Network.is_session_active() and not Network.is_host) and restore_props:
		_restore_pushables()
