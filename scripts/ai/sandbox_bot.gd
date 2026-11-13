extends RefCounted
## Free-roam driver for the sandbox AI carts.
##
## One bot owns the virtual inputs of one CartPlayer. It works the five-zone
## test facility: the paddock grid, the handling loop (driven as a circuit),
## the skidpad, the jump lane and the dirt slalom. Destinations are weighted
## toward the loop and the dirt so the field spreads out instead of parking in
## the paddock. A few short raycasts see obstacles and ramps; the ground probe
## runs at 10 Hz.
##
## The owning scene keeps the cart and the respawn threshold. This object keeps
## every personality field (skill, ramp appetite, boost bias) and reuses a single
## ray query, so a physics tick allocates nothing of its own.

const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")
const TrackSpline := preload("res://scripts/minigames/track_spline.gd")

## A kart has to go around the world, solid props and other carts. Cones sit on
## the non-blocking PROP layer, so driving through one is intentionally allowed.
const OBSTACLE_MASK: int = CollisionLayers.WORLD | CollisionLayers.SOLID_PROP \
	| CollisionLayers.PLAYER | CollisionLayers.GHOST
## Terrain, ramps and raised track bodies only. Props are avoided as obstacles;
## they must not read as a ramp in the ground probe.
const GROUND_MASK: int = CollisionLayers.WORLD

## Keep every destination and every steer target inside the perimeter wall.
const PARK_LIMIT: float = 64.0
## Ground lookahead is re-probed at 10 Hz, not every tick.
const PROBE_INTERVAL: float = 0.1
const STUCK_SPEED: float = 1.5
const STUCK_DELAY: float = 1.0
const REVERSE_TIME: float = 1.5
const RESPAWN_STUCK: float = 4.0
## Grade (rise / distance) that reads as a drive-up ramp, and the point where it
## is simply a hill face to go around.
const RAMP_GRADE_MIN: float = 0.06
const RAMP_GRADE_MAX: float = 0.62

## Facility layout, mirrored from sandbox_park.gd. These are plain numbers so
## this driver never needs the park node at runtime; keep them in sync with the
## five-zone builder.
const PADDOCK_RECT := Rect2(-32.0, 0.0, 54.0, 20.0)
const DIRT_RECT := Rect2(-26.0, 24.0, 52.0, 38.0)
const SKID_CENTRE := Vector2(50.0, 12.0)
const SKID_RADIUS: float = 13.0
const LOOP_CENTRE := Vector2(0.0, -38.0)
## Same TrackSpline preset the park uses for the 158 m handling loop.
const LOOP_PRESET: Dictionary = {
	"control_points": 20,
	"samples_per_segment": 10,
	"base_radius": 26.0,
	"lobe_a": 0.08,
	"lobe_b": 0.02,
	"lobe_c": 0.012,
	"lobe_d": 0.04,
	"stretch_x": 1.15,
	"stretch_z": 0.70,
	"elevation": [],
}
const LOOP_SAMPLES: int = 48
## Wider than the lookahead spacing keeps the line moving; the target always
## sits further away than this when it is picked, so it cannot rapid-fire.
const LOOP_ARRIVE: float = 10.5
## Accept the gap a little early, so a queue at the entry does not stall a bot
## one metre outside the arrival circle.
const LOOP_JOIN_RADIUS: float = 8.5
## The first circuit target is one full lookahead along the ring, further away
## than LOOP_ARRIVE so a fresh lap cannot rapid-fire the whole ring.
const LOOP_START_LOOKAHEAD: int = 4
const LOOP_LAPS: int = 2
## Drive a couple of metres inside the centreline, away from the outside armco.
const LOOP_INSET: float = 2.0
## A circuit bot this far from its inside line has left the road (or the
## barrier); reset it to the paved gap instead of grinding along the armco.
const LOOP_RESET_DISTANCE: float = 8.0
## No new ring point for this long means a bot is beached or orbiting.
const LOOP_STALL_TIME: float = 6.0
## Race pace on the loop. The oval is tighter than the open field, so boosting
## or running the skill ceiling there just grinds the armco.
const LOOP_SPEED_CAP: float = 0.68
## Paved link gate between the paddock and the loop's armco gap.
const LOOP_GATE := Vector3(0.0, 0.0, -6.0)
const LANE_X: float = -52.0
const LANE_HALF: float = 4.5
const LANE_START_Z: float = 32.0
const LANE_END_Z: float = -44.0
const JUMP_ENTRY := Vector3(-52.0, 0.0, 34.0)
const JUMP_LAUNCH := Vector3(-52.0, 0.0, -18.0)
## Straight-line run-up from the far side of the lane, clear of the pit block.
const JUMP_RUNUP := Vector3(-42.0, 0.0, 56.0)
## After the landing, shed speed before committing to the next line.
const LANDING_SETTLE: float = 1.6
## And leave the west lane via the paddock side, clear of the loop armco.
const JUMP_EXIT := Vector3(-34.0, 0.0, 30.0)
## Gentle slalom line down the dirt, clear of the cone rows at x=-8 and x=+8.
## The lateral swing is small enough for the reduced dirt grip at speed.
const WEAVE_POINTS: Array[Vector3] = [
	Vector3(0.0, 0.0, 28.0), Vector3(4.0, 0.0, 38.0),
	Vector3(-4.0, 0.0, 48.0), Vector3(0.0, 0.0, 58.0),
]
## Live steering clearance around a paddock tyre stack.
const TYRE_CLEAR: float = 3.2

## Zone ids for the per-bot exploration counters.
const ZONE_PADDOCK: int = 0
const ZONE_LOOP: int = 1
const ZONE_SKIDPAD: int = 2
const ZONE_JUMP: int = 3
const ZONE_DIRT: int = 4

## Destination kinds: point, two-point ramp run, circuit and slalom.
const DEST_OPEN: int = 0
const DEST_RAMP: int = 1
const DEST_LOOP: int = 2
const DEST_WEAVE: int = 3
## How close (metres) counts as reaching a destination or a ramp entry.
const ARRIVE_RADIUS: float = 6.5
## Slalom points sit closer together, so they need a tighter arrival test.
const WEAVE_ARRIVE_RADIUS: float = 5.0
## A point that has fallen behind the kart is passed even if the wide line
## missed the arrival circle; this is what keeps the slalom moving.
const WEAVE_PASS_RADIUS: float = 15.0
## A bot that hovers close to a waypoint without crossing the arrival radius for
## this long accepts it. Prevents a fast kart from orbiting a small target.
const NEAR_ACCEPT_TIME: float = 5.0
## Abandon an unreachable destination after this long (seconds).
const DEST_TIMEOUT: float = 30.0

## Solid facility furniture the route helper steers around when a landmark leg
## points straight through one. Track furniture is avoided live by the rays.
const NO_GO_CENTERS: Array[Vector2] = [
	Vector2(-28.5, 8.0),
	Vector2(-22.2, 4.0), Vector2(-22.2, 8.0), Vector2(-22.2, 12.0),
	Vector2(18.5, 1.5), Vector2(18.5, 5.5), Vector2(8.5, 18.5),
	Vector2(13.0, 18.5), Vector2(-19.0, 1.5), Vector2(-15.0, 1.5),
	Vector2(-38.0, -4.0), Vector2(28.0, -4.0), Vector2(-30.0, 23.5),
	Vector2(28.0, 23.5), Vector2(42.5, 26.8), Vector2(57.5, 26.8),
	Vector2(36.5, 19.5), Vector2(-43.5, 10.0),
]
const NO_GO_RADII: Array[float] = [
	10.0,
	1.8, 1.8, 1.8,
	1.2, 1.2, 1.2, 1.2, 1.2, 1.2,
	1.0, 1.0, 1.0, 1.0, 1.2, 1.2, 1.0, 1.0,
]
## Paddock tyre stacks, for live clearance as well as route planning.
const TYRE_STACKS: Array[Vector2] = [
	Vector2(18.5, 1.5), Vector2(18.5, 5.5), Vector2(8.5, 18.5),
	Vector2(13.0, 18.5), Vector2(-19.0, 1.5), Vector2(-15.0, 1.5),
]

## Destinations in the rebuilt facility. The loop and the dirt carry most of the
## weight, so the field spreads out instead of clustering in the paddock;
## ramps are drawn only by the per-bot ramp appetite.
const DESTINATIONS: Array[Dictionary] = [
	{"name": "paddock grid", "entry": Vector3(0.0, 0.0, 9.0),
		"launch": Vector3.ZERO, "kind": DEST_OPEN, "weight": 0.30},
	{"name": "handling loop", "entry": Vector3(0.0, 0.0, -20.0),
		"launch": Vector3.ZERO, "kind": DEST_LOOP, "weight": 3.40},
	{"name": "skidpad", "entry": Vector3(50.0, 0.0, 12.0),
		"launch": Vector3.ZERO, "kind": DEST_OPEN, "weight": 1.20},
	{"name": "jump lane", "entry": JUMP_ENTRY,
		"launch": JUMP_LAUNCH, "kind": DEST_RAMP, "weight": 0.85},
	{"name": "dirt strip", "entry": Vector3(0.0, 0.0, 44.0),
		"launch": Vector3.ZERO, "kind": DEST_OPEN, "weight": 1.60},
	{"name": "cone slalom", "entry": Vector3(0.0, 0.0, 28.0),
		"launch": Vector3.ZERO, "kind": DEST_WEAVE, "weight": 2.10},
]

var cart: CartPlayer
var skill: float = 0.8
## Ring radius and offset are kept for spawn/respawn compatibility; driving is
## destination-driven now.
var radius: float = 55.0
var radius_offset: float = 0.0
var phase: float = 0.0
var boost_bias: float = 0.7
## Personality slot: 0 cruiser, 1 drifter, 2 ramp hunter.
var path_style: int = 0
## Seconds spent below STUCK_SPEED and outside the park, read by the owner for
## the hard respawn.
var stuck: float = 0.0
var stranded: float = 0.0

## Current destination (for diagnostics) and lifetime exploration counters.
var destination_name: String = ""
var destinations_visited: int = 0
var distinct_destinations: int = 0
## Distinct destinations ever selected, including the one in progress.
var destinations_used: int = 0
## Per-destination arrival counts; sized once, so a tick allocates nothing.
var visit_counts: PackedInt32Array = PackedInt32Array()
## Facility diagnostics: metres driven and the number of distinct zones seen.
var distance_driven: float = 0.0
var distinct_zones: int = 0

var _ray: PhysicsRayQueryParameters3D
var _exclude: Array[RID] = []
var _rng := RandomNumberGenerator.new()
var _probe_timer: float = 0.0
var _ground_grade: float = 0.0
var _ramp_timer: float = 0.0
var _cliff_timer: float = 0.0
var _reverse_timer: float = 0.0
var _reverse_steer: float = 0.0
var _reverse_cooldown: float = 0.0
var _settle_timer: float = 0.0
var _landing_brake: bool = false
var _post_jump_exit: bool = false
var _avoid_side: float = 0.0
var _avoid_hold: float = 0.0
var _last_steer: float = 0.0
var _ramp_chance: float = 0.12
var _wander_amp: float = 1.8
var _wander_rate: float = 0.55
var _wander_phase: float = 0.0
var _dest_index: int = -1
var _dest_kind: int = DEST_OPEN
var _dest_target: Vector3 = Vector3.ZERO
var _dest_entry: Vector3 = Vector3.ZERO
var _ramp_launch: Vector3 = Vector3.ZERO
var _dest_phase: int = 0
var _dest_timer: float = 0.0
var _near_timer: float = 0.0
var _via_target: Vector3 = Vector3.ZERO
var _via_active: bool = false
var _visited_mask: int = 0
var _used_mask: int = 0
var _zone_mask: int = 0
## Last sampled cart position, for the distance counter and respawn bookkeeping.
var _last_position: Vector3 = Vector3.ZERO
## Pre-sampled handling loop, so the circuit costs no spline work per tick.
var _loop_points: PackedVector3Array = PackedVector3Array()
var _loop_spacing: PackedFloat32Array = PackedFloat32Array()
var _loop_length: float = 0.0
var _loop_entry_index: int = 0
var _loop_join_index: int = 0
var _loop_index: int = 0
var _loop_distance: float = 0.0
var _loop_last_distance: float = 0.0
var _loop_stall: float = 0.0
var _loop_laps: int = 0
var _loop_active: bool = false
var _loop_exit: bool = false
var _weave_index: int = 0


func setup(p_cart: CartPlayer, index: int, rng: RandomNumberGenerator,
		difficulty: int) -> void:
	## Bind this driver to one cart and roll its personality. Called once, so the
	## ray query and its exclude list live for as long as the bot does.
	cart = p_cart
	radius = 53.0 + float(index % 3) * 1.8
	path_style = index % 3
	match path_style:
		0:
			radius_offset = -4.0
		1:
			radius_offset = 0.0
		_:
			radius_offset = 4.0
	var level: int = clampi(difficulty, 0, 2)
	var skill_lo: Array[float] = [0.60, 0.72, 0.86]
	var skill_hi: Array[float] = [0.80, 1.00, 1.12]
	skill = rng.randf_range(skill_lo[level], skill_hi[level])
	boost_bias = rng.randf_range(0.45, 1.0)
	phase = rng.randf() * TAU
	_ramp_chance = [0.10, 0.16, 0.30][path_style]
	_rng.seed = rng.randi()
	visit_counts.resize(DESTINATIONS.size())
	_build_loop()
	# Spread the field across the 18 m gap instead of funnelling every bot onto
	# the same three square metres of tarmac.
	_loop_join_index = (_loop_entry_index + index % 3 - 1 + LOOP_SAMPLES) \
		% LOOP_SAMPLES
	_last_position = p_cart.global_position
	_ray = PhysicsRayQueryParameters3D.new()
	_ray.collide_with_areas = false
	_ray.collide_with_bodies = true
	_exclude.append(cart.get_rid())
	_ray.exclude = _exclude
	_pick_destination()


func tick(delta: float, time: float, traffic: Array[CartPlayer]) -> void:
	## Drive one physics frame. `traffic` is the scene's live cart list (the local
	## player first, then every bot) and is reused, never rebuilt here.
	if not is_instance_valid(cart):
		return
	var xf: Transform3D = cart.global_transform
	var pos: Vector3 = xf.origin
	var forward: Vector3 = -xf.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.0001 \
		else Vector3.FORWARD
	var right: Vector3 = xf.basis.x
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 0.0001 else Vector3.RIGHT
	var planar_speed: float = Vector2(cart.velocity.x, cart.velocity.z).length()
	var speed: float = maxf(cart.velocity.dot(forward), 0.0)
	var grounded: bool = cart.is_on_floor()
	var grade: float = 0.0
	if grounded:
		grade = clampf(-cart.get_floor_normal().dot(forward), -0.9, 0.9)
	_update_diagnostics(pos)
	_probe_timer -= delta
	if _probe_timer <= 0.0:
		_probe_timer = PROBE_INTERVAL
		_sample_ground(pos, forward, speed)
	_ramp_timer = maxf(_ramp_timer - delta, 0.0)
	_cliff_timer = maxf(_cliff_timer - delta, 0.0)
	_avoid_hold = maxf(_avoid_hold - delta, 0.0)
	_reverse_cooldown = maxf(_reverse_cooldown - delta, 0.0)
	_settle_timer = maxf(_settle_timer - delta, 0.0)
	if grounded and _landing_brake and _settle_timer <= 0.0:
		_landing_brake = false
	if grounded and planar_speed < STUCK_SPEED:
		stuck += delta
	else:
		stuck = maxf(stuck - delta * 2.0, 0.0)
	if pos.y < -3.0 or absf(pos.x) > PARK_LIMIT + 6.0 \
			or absf(pos.z) > PARK_LIMIT + 6.0:
		stranded += delta
	else:
		stranded = 0.0
	# ---- stuck recovery: reverse with opposite steer before the hard reset ----
	if _reverse_timer > 0.0:
		_reverse_timer -= delta
		if _reverse_timer <= 0.0 or planar_speed > STUCK_SPEED + 0.5:
			_reverse_timer = 0.0
			_reverse_cooldown = 1.0
		else:
			cart.set_ai_controls(0.0, 1.0, _reverse_steer, false)
			_last_steer = _reverse_steer
			return
	if stuck >= STUCK_DELAY and stuck < RESPAWN_STUCK and _reverse_cooldown <= 0.0:
		_reverse_timer = REVERSE_TIME
		var direction: float = _last_steer
		if absf(direction) < 0.12:
			direction = 1.0 if sin(time * 1.7 + phase) >= 0.0 else -1.0
		_reverse_steer = clampf(-direction, -1.0, 1.0)
		cart.set_ai_controls(0.0, 1.0, _reverse_steer, false)
		_last_steer = _reverse_steer
		return
	# ---- airborne: keep the wheel straight until the tyres are back down ----
	if not grounded:
		# A kicker can throw the kart far past its landing marker, so the run is
		# settled in the air; the landing brake stays primed until touchdown.
		if _landing_brake:
			_settle_timer = LANDING_SETTLE
		if _dest_kind == DEST_RAMP and _dest_phase == 1 \
				and pos.z < _ramp_launch.z - 8.0:
			_landing_brake = true
			_settle_timer = LANDING_SETTLE
			_post_jump_exit = true
			_record_visit()
			_pick_destination()
		cart.set_ai_controls(0.45, 0.0, 0.0, false)
		return
	# ---- destination: circuit, slalom, ramp run or open landmark ----
	if _dest_index < 0:
		_pick_destination()
	_dest_timer += delta
	if _loop_active:
		_update_loop(pos, delta)
	else:
		var to_goal: Vector3 = _dest_target - pos
		to_goal.y = 0.0
		var goal_dist: float = to_goal.length()
		if goal_dist < 16.0:
			_near_timer += delta
		else:
			_near_timer = 0.0
		var arrive: float = ARRIVE_RADIUS
		if _dest_kind == DEST_WEAVE:
			arrive = WEAVE_ARRIVE_RADIUS
		elif _dest_kind == DEST_LOOP:
			arrive = LOOP_JOIN_RADIUS
		var near_accept: float = NEAR_ACCEPT_TIME
		if _dest_kind == DEST_LOOP:
			# A queue at the gap must not hold a bot outside the arrival circle.
			near_accept = 2.5
		var passed: bool = false
		if _dest_kind == DEST_WEAVE and to_goal.dot(forward) < 0.0:
			passed = goal_dist <= WEAVE_PASS_RADIUS
		elif _dest_kind == DEST_RAMP and _dest_phase == 1:
			passed = pos.z < _ramp_launch.z - 8.0
		if goal_dist < arrive or passed or _near_timer > near_accept \
				or _dest_timer > DEST_TIMEOUT:
			_advance_destination()
			_near_timer = 0.0
	var to_dest: Vector3 = _dest_target - pos
	to_dest.y = 0.0
	var dest_dist: float = to_dest.length()
	var look: float = clampf(6.5 + speed * 0.55, 7.0, 17.0) \
		* lerpf(1.12, 0.92, clampf(skill, 0.0, 1.12))
	var direction: Vector3 = to_dest / dest_dist if dest_dist > 0.1 \
		else Vector3.FORWARD
	# Wander sideways of the destination leg, finishing the leg on line. The
	# circuit, slalom and kicker runs keep the authored line instead.
	var target: Vector3 = _dest_target
	if dest_dist > look:
		target = pos + direction * look
		if _dest_phase == 0 and _dest_kind == DEST_OPEN and not _loop_active:
			var side_dir := Vector3(-direction.z, 0.0, direction.x)
			var wander: float = sin(time * _wander_rate + _wander_phase) \
				* _wander_amp
			target += side_dir * wander
	var target_speed: float = cart.max_speed \
		* lerpf(0.62, 0.92, clampf(skill, 0.0, 1.12))
	if dest_dist < 20.0 and _dest_phase == 0:
		# Arrive, do not orbit: shed speed well before the waypoint.
		target_speed *= lerpf(0.42, 1.0, clampf(dest_dist / 20.0, 0.0, 1.0))
	var space: PhysicsDirectSpaceState3D = cart.get_world_3d().direct_space_state
	var avoid: float = 0.0
	var path_clear: float = 99.0
	var tyre_gap: float = 99.0
	# A committed ramp run steers less around obstacles, but still sees walls.
	var avoid_scale: float = 1.0 if _dest_phase == 0 else 0.45
	if _dest_kind == DEST_RAMP and _dest_phase == 1:
		avoid_scale = 0.18
	# ---- forward obstacle ray: crates, tyre stacks, walls, carts, hill faces ----
	var ray_len: float = clampf(4.5 + speed * 0.5, 5.5, 12.0)
	var origin: Vector3 = pos + Vector3.UP * 0.55 + forward * 0.85
	_ray.collision_mask = OBSTACLE_MASK
	_ray.from = origin
	_ray.to = origin + forward * ray_len
	var hit: Dictionary = space.intersect_ray(_ray)
	if not hit.is_empty():
		var hit_position: Vector3 = hit["position"]
		var hit_normal: Vector3 = hit["normal"]
		var hit_dist: float = origin.distance_to(hit_position)
		if hit_normal.y > 0.88:
			# A gentle face is a ramp or a hill toe: drive it instead of dodging.
			_ramp_timer = maxf(_ramp_timer, 0.55)
		else:
			var side: float = signf((hit_position - pos).dot(right))
			if absf(side) < 0.35:
				# Dead ahead: pass on whichever side the destination wants.
				side = -signf((_dest_target - pos).dot(right))
				if side == 0.0:
					side = -1.0
			avoid += side * clampf(1.0 - hit_dist / ray_len, 0.2, 1.0)
			_avoid_side = signf(side)
			_avoid_hold = 0.35
			path_clear = hit_dist
	# ---- two short whiskers see around the bumper before the obstacle is ahead ----
	var whisker_len: float = clampf(3.0 + speed * 0.22, 3.5, 7.0)
	var whisker_origin: Vector3 = pos + Vector3.UP * 0.45 + forward * 0.5
	_ray.from = whisker_origin
	_ray.to = whisker_origin + forward.rotated(Vector3.UP, 0.4) * whisker_len
	hit = space.intersect_ray(_ray)
	if not hit.is_empty() and (hit["normal"] as Vector3).y <= 0.88:
		var left_dist: float = whisker_origin.distance_to(hit["position"] as Vector3)
		avoid -= clampf(1.0 - left_dist / whisker_len, 0.15, 1.0) * 0.75
		_avoid_side = -1.0
		_avoid_hold = 0.3
	_ray.to = whisker_origin + forward.rotated(Vector3.UP, -0.4) * whisker_len
	hit = space.intersect_ray(_ray)
	if not hit.is_empty() and (hit["normal"] as Vector3).y <= 0.88:
		var right_dist: float = whisker_origin.distance_to(hit["position"] as Vector3)
		avoid += clampf(1.0 - right_dist / whisker_len, 0.15, 1.0) * 0.75
		_avoid_side = 1.0
		_avoid_hold = 0.3
	# ---- separation from the player and the other bots ----
	for other: CartPlayer in traffic:
		if other == cart or not is_instance_valid(other):
			continue
		var offset: Vector3 = other.global_position - pos
		offset.y = 0.0
		var gap: float = offset.length()
		if gap < 0.05 or gap > 10.0:
			continue
		var ahead: float = offset.dot(forward)
		if ahead < -3.0:
			continue
		var lane_side: float = offset.dot(right)
		var closeness: float = 1.0 - gap / 10.0
		if ahead > 0.0 and absf(lane_side) < 2.9:
			if absf(lane_side) < 0.2:
				lane_side = -signf((_dest_target - pos).dot(right))
				if lane_side == 0.0:
					lane_side = -1.0
			avoid += signf(lane_side) * closeness * 0.95
			if ahead < 5.5:
				var other_speed: float = maxf(
					other.get_collision_velocity().dot(forward), 0.0)
				target_speed = minf(target_speed,
					other_speed + maxf(ahead - 2.4, 0.0) * 0.6)
		elif absf(lane_side) < 3.4 and gap < 4.2:
			avoid += signf(lane_side) * closeness * 0.55
	# ---- explicit clearance around the paddock tyre stacks ----
	var flat_right := Vector2(right.x, right.z)
	for tyre: Vector2 in TYRE_STACKS:
		var offset: Vector2 = Vector2(pos.x, pos.z) - tyre
		var gap: float = offset.length()
		if gap >= TYRE_CLEAR or gap < 0.01:
			continue
		var side: float = -signf(offset.dot(flat_right))
		if absf(side) < 0.2:
			side = 1.0 if sin(time * 1.3 + phase) >= 0.0 else -1.0
		avoid += side * clampf(1.0 - gap / TYRE_CLEAR, 0.15, 0.9)
		path_clear = minf(path_clear, gap)
		tyre_gap = minf(tyre_gap, gap)
	avoid = clampf(avoid, -1.0, 1.0)
	if _avoid_hold > 0.0:
		avoid = clampf(avoid + _avoid_side * 0.35 * (_avoid_hold / 0.35),
			-1.0, 1.0)
	# ---- ramp awareness: aim straight down the kicker lane / detected slope ----
	if _dest_kind == DEST_RAMP and _dest_phase == 1:
		# Line the kart up on the lane centreline, not on whatever heading it
		# happened to arrive with, so both kickers are taken square.
		target = Vector3(LANE_X, 0.0, pos.z - look * 1.3)
	elif _ramp_timer > 0.0 and _dest_phase == 0:
		target = pos + forward * look
	target += right * (-avoid * 3.0 * avoid_scale)
	target.x = clampf(target.x, -PARK_LIMIT, PARK_LIMIT)
	target.z = clampf(target.z, -PARK_LIMIT, PARK_LIMIT)
	var local_target: Vector3 = cart.to_local(target)
	var steer: float = clampf(atan2(-local_target.x, -local_target.z) * 2.1,
		-1.0, 1.0)
	steer += sin(time * 1.1 + phase) * (1.06 - clampf(skill, 0.0, 1.06)) * 0.10
	if _ramp_timer > 0.0 or _dest_phase == 1:
		steer *= 0.45
	steer = clampf(steer + avoid * 0.45 * avoid_scale, -1.0, 1.0)
	# ---- speed: brake for heading error, lift on slopes, floor on ramps ----
	target_speed *= clampf(1.0 - absf(steer) * 0.42 - absf(avoid) * 0.16,
		0.34, 1.0)
	if grade > 0.05:
		target_speed *= lerpf(1.0, 0.76, clampf(grade * 1.6, 0.0, 1.0))
	elif grade < -0.08:
		target_speed *= lerpf(1.0, 0.72, clampf(-grade * 1.4, 0.0, 1.0))
	if _cliff_timer > 0.0:
		target_speed *= 0.6
	elif _ground_grade < -0.35:
		target_speed *= 0.82
	if _dest_kind == DEST_RAMP and (_ramp_timer > 0.0 or _dest_phase == 1):
		target_speed = maxf(target_speed,
			cart.max_speed * lerpf(0.70, 0.90, clampf(skill, 0.0, 1.12)))
	# Skidpad and dirt are low-grip work: slow down before the kart steps out.
	target_speed = minf(target_speed, cart.max_speed * _zone_speed_cap(pos))
	if _loop_active:
		target_speed = minf(target_speed, cart.max_speed * LOOP_SPEED_CAP)
	if _settle_timer > 0.0:
		target_speed = minf(target_speed, cart.max_speed * 0.45)
	target_speed = maxf(target_speed, 4.0)
	var throttle: float = 0.0
	var brake: float = 0.0
	if speed < target_speed:
		throttle = clampf(0.7 + skill * 0.3, 0.0, 1.0)
	if speed > target_speed + 0.7:
		brake = clampf((speed - target_speed) / 4.0, 0.0, 0.85)
	if path_clear < 3.2 and speed > STUCK_SPEED:
		brake = maxf(brake, clampf((3.2 - path_clear) / 3.2, 0.0, 0.8) * avoid_scale)
	if tyre_gap < TYRE_CLEAR:
		# Crawl past a tyre stack instead of pinning the nose against it.
		target_speed = minf(target_speed, cart.max_speed * 0.35)
		if speed > target_speed:
			brake = maxf(brake, 0.55)
	if brake > 0.0:
		throttle = 0.0
	# ---- boost: only on the open track, straight, with a genuinely clear path ----
	var boost: bool = path_clear > 14.0 and absf(steer) < 0.30 \
		and absf(avoid) < 0.30 and grade < 0.12 and _cliff_timer <= 0.0 \
		and speed > cart.max_speed * 0.55 and cart.boost_amount > 25.0 \
		and boost_bias > 0.52 and _zone_speed_cap(pos) > 0.9 and not _loop_active
	cart.set_ai_controls(throttle, brake, steer, boost)
	_last_steer = steer


func respawn() -> void:
	## Put the bot back on the ground just short of its current goal, facing it,
	## and clear every recovery counter. A circuit restarts from its approach.
	if not is_instance_valid(cart):
		return
	var anchor: Vector3 = _dest_target
	if _loop_active and _loop_index >= 0 and _loop_index < _loop_points.size():
		anchor = _loop_points[_loop_index]
	if anchor == Vector3.ZERO:
		anchor = Vector3(cos(phase) * radius, 0.0, sin(phase) * radius)
	var here: Vector3 = cart.global_position
	if _dest_kind == DEST_LOOP and _dest_entry == _loop_points[_loop_join_index]:
		# A circuit always respawns at the paved gap, never on the far side of
		# the armco where the next ring point would be unreachable.
		anchor = _loop_points[_loop_join_index]
		here = Vector3(LOOP_GATE.x, 0.0, LOOP_GATE.z + 10.0)
	var approach: Vector3 = here - anchor
	approach.y = 0.0
	if approach.length_squared() < 1.0:
		approach = Vector3.FORWARD
	var setback: float = 9.0
	if _dest_kind == DEST_LOOP:
		# Inside the join radius: the next tick begins the circuit instead of
		# respawning short of the gap and jamming there again.
		setback = 6.0
	var slot: Vector3 = Vector3(anchor.x, 0.0, anchor.z) \
		+ approach.normalized() * setback
	slot.x = clampf(slot.x, -PARK_LIMIT, PARK_LIMIT)
	slot.z = clampf(slot.z, -PARK_LIMIT, PARK_LIMIT)
	slot.y = _ground_height(slot) + 0.12
	var facing: Vector3 = Vector3(anchor.x, 0.0, anchor.z) - slot
	facing.y = 0.0
	var yaw: float = 0.0
	if facing.length_squared() > 0.01:
		yaw = atan2(-facing.x, -facing.z)
	cart.global_position = slot
	cart.rotation = Vector3(0.0, yaw, 0.0)
	cart.set_spawn_transform(cart.global_transform)
	cart.reset_for_respawn()
	cart.velocity = Vector3.ZERO
	stuck = 0.0
	stranded = 0.0
	_reverse_timer = 0.0
	_reverse_cooldown = 0.0
	_settle_timer = 0.0
	_landing_brake = false
	_post_jump_exit = false
	_ramp_timer = 0.0
	_cliff_timer = 0.0
	_avoid_hold = 0.0
	_last_steer = 0.0
	_loop_active = false
	_loop_exit = false
	_loop_laps = 0
	_loop_distance = 0.0
	_loop_last_distance = 0.0
	_loop_stall = 0.0
	_weave_index = 0
	_dest_phase = 0
	_dest_timer = 0.0
	_near_timer = 0.0
	_dest_target = _via_target if _via_active else _dest_entry
	_last_position = slot


func _advance_destination() -> void:
	## Reach the current waypoint. A route detour first returns to the landmark
	## leg, a circuit starts its laps and a slalom walks its own points. Only the
	## final point of a destination is counted as visited.
	if _via_active:
		_via_active = false
		_dest_target = _dest_entry
		_dest_timer = 0.0
		_near_timer = 0.0
		return
	# Cargo Rush overrides the target for its own goals; only a real facility
	# loop entry starts a circuit.
	if _dest_kind == DEST_LOOP \
			and _dest_entry == _loop_points[_loop_join_index]:
		if _dest_phase == 0:
			_begin_loop()
			return
		_finish_loop()
		return
	if _dest_kind == DEST_WEAVE:
		if _dest_phase == 0:
			_dest_phase = 1
			_weave_index = 1
			_dest_target = WEAVE_POINTS[_weave_index]
			_dest_timer = 0.0
			_near_timer = 0.0
			return
		if _weave_index < WEAVE_POINTS.size() - 1:
			_weave_index += 1
			_dest_target = WEAVE_POINTS[_weave_index]
			_dest_timer = 0.0
			_near_timer = 0.0
			return
	if _dest_phase == 0 and _ramp_launch != Vector3.ZERO:
		if _dest_kind == DEST_RAMP:
			var heading: Vector3 = -cart.global_transform.basis.z
			heading.y = 0.0
			if heading.z > 0.15 and _cart_position().z > JUMP_ENTRY.z:
				# Still turned around after the staging loop: hold the entry
				# until the nose is pointing down the lane.
				_dest_target = JUMP_ENTRY
				_dest_timer = 0.0
				_near_timer = 0.0
				return
		_dest_phase = 1
		_dest_target = _ramp_launch
		_dest_timer = 0.0
		_near_timer = 0.0
		_ramp_timer = maxf(_ramp_timer, 0.9)
		return
	if _dest_kind == DEST_RAMP and _dest_phase == 1:
		_settle_timer = LANDING_SETTLE
		_landing_brake = true
		_post_jump_exit = true
	if _dest_index >= 0:
		_record_visit()
	_pick_destination()


func _begin_loop() -> void:
	## Start the circuit at the armco gap and target the first lookahead point.
	_loop_active = true
	_loop_exit = false
	_dest_phase = 1
	_loop_laps = 0
	_loop_index = (_loop_join_index + LOOP_START_LOOKAHEAD) \
		% _loop_points.size()
	_loop_distance = 0.0
	for step in LOOP_START_LOOKAHEAD:
		_loop_distance += _loop_spacing[(_loop_join_index + step)
			% _loop_spacing.size()]
	_loop_last_distance = _loop_distance
	_loop_stall = 0.0
	_dest_target = _loop_points[_loop_index]
	_dest_timer = 0.0
	_near_timer = 0.0


func _update_loop(pos: Vector3, delta: float) -> void:
	## Follow the pre-sampled ring one waypoint at a time. Arc length, not frame
	## time, owns the lap boundary, so the circuit stays deterministic.
	if _dest_timer > DEST_TIMEOUT * 4.0:
		_finish_loop()
		return
	if _loop_stall > LOOP_STALL_TIME:
		respawn()
		return
	if _loop_distance > _loop_last_distance + 0.001:
		_loop_last_distance = _loop_distance
		_loop_stall = 0.0
	else:
		_loop_stall += delta
	var nearest_sq: float = INF
	for i in _loop_points.size():
		var dx: float = pos.x - _loop_points[i].x
		var dz: float = pos.z - _loop_points[i].z
		var dist_sq: float = dx * dx + dz * dz
		if dist_sq < nearest_sq:
			nearest_sq = dist_sq
	if nearest_sq > LOOP_RESET_DISTANCE * LOOP_RESET_DISTANCE:
		# Off the road and probably against the armco: recover at the gap rather
		# than drive along the barrier for the rest of the session.
		respawn()
		return
	var point: Vector3 = _loop_points[_loop_index]
	var offset: Vector2 = Vector2(point.x - pos.x, point.z - pos.z)
	if offset.length_squared() <= LOOP_ARRIVE * LOOP_ARRIVE:
		_loop_distance += _loop_spacing[_loop_index]
		_loop_index = (_loop_index + 1) % _loop_points.size()
		if _loop_distance >= _loop_length:
			_loop_distance -= _loop_length
			_loop_last_distance = _loop_distance
			_loop_stall = 0.0
			_loop_laps += 1
			if _loop_laps >= LOOP_LAPS:
				_loop_exit = true
		_dest_target = _loop_points[_loop_index]
	var entry: Vector3 = _loop_points[_loop_join_index]
	if _loop_exit and pos.distance_squared_to(entry) <= LOOP_ARRIVE * LOOP_ARRIVE:
		_finish_loop()


func _finish_loop() -> void:
	## Leave the circuit once its last lap is done, through the paved gap.
	_loop_active = false
	_loop_exit = false
	_dest_phase = 0
	_loop_laps = 0
	_loop_distance = 0.0
	_loop_last_distance = 0.0
	_loop_stall = 0.0
	if _dest_index >= 0:
		_record_visit()
	_pick_destination()


func _build_loop() -> void:
	## Sample the spline the park drives exactly once. A circuit tick is then a
	## couple of vector comparisons and never touches TrackSpline again.
	var spline := TrackSpline.new(LOOP_PRESET)
	var total: float = spline.total_length
	_loop_points.resize(LOOP_SAMPLES)
	for i in LOOP_SAMPLES:
		var frame: Dictionary = spline.sample(total * float(i)
			/ float(LOOP_SAMPLES))
		var point: Vector3 = frame["position"]
		var inward: Vector3 = frame["right"]
		_loop_points[i] = point + Vector3(LOOP_CENTRE.x, 0.0, LOOP_CENTRE.y) \
			+ inward * LOOP_INSET
	_loop_spacing.resize(LOOP_SAMPLES)
	_loop_length = 0.0
	for i in LOOP_SAMPLES:
		var spacing: float = _loop_points[i].distance_to(
			_loop_points[(i + 1) % LOOP_SAMPLES])
		_loop_spacing[i] = spacing
		_loop_length += spacing
	# The gap sits on the ring point nearest the paddock link.
	var best: int = 0
	var best_sq: float = INF
	for i in LOOP_SAMPLES:
		var offset: Vector2 = Vector2(_loop_points[i].x, _loop_points[i].z)
		var dist_sq: float = offset.length_squared()
		if dist_sq < best_sq:
			best_sq = dist_sq
			best = i
	_loop_entry_index = best


func _update_diagnostics(pos: Vector3) -> void:
	## Per-tick, allocation-free diagnostics: metres driven and the five-zone
	## exploration mask. A teleport (respawn) is excluded from the distance.
	var step: float = pos.distance_to(_last_position)
	if step < 4.0:
		distance_driven += step
	_last_position = pos
	var zone: int = _zone_at(pos)
	if zone < 0:
		return
	var bit: int = 1 << zone
	if (_zone_mask & bit) == 0:
		_zone_mask |= bit
		distinct_zones += 1


func _zone_at(pos: Vector3) -> int:
	## Which facility zone a kart is in, or -1 on the grass. Plain rectangles and
	## one circle, so this adds no raycasts to a tick.
	if pos.x >= PADDOCK_RECT.position.x and pos.x <= PADDOCK_RECT.end.x \
			and pos.z >= PADDOCK_RECT.position.y \
			and pos.z <= PADDOCK_RECT.end.y:
		return ZONE_PADDOCK
	if pos.x >= DIRT_RECT.position.x and pos.x <= DIRT_RECT.end.x \
			and pos.z >= DIRT_RECT.position.y and pos.z <= DIRT_RECT.end.y:
		return ZONE_DIRT
	if pos.x >= LANE_X - LANE_HALF and pos.x <= LANE_X + LANE_HALF \
			and pos.z >= LANE_END_Z and pos.z <= LANE_START_Z:
		return ZONE_JUMP
	var skid_x: float = pos.x - SKID_CENTRE.x
	var skid_z: float = pos.z - SKID_CENTRE.y
	if skid_x * skid_x + skid_z * skid_z \
			<= (SKID_RADIUS + 2.0) * (SKID_RADIUS + 2.0):
		return ZONE_SKIDPAD
	if _on_loop_ring(pos):
		return ZONE_LOOP
	return -1


func _on_loop_ring(pos: Vector3) -> bool:
	## Cheap bounding test first; only a kart near the oval scans the 48 points.
	if pos.z > -10.0 or pos.z < -66.0 or absf(pos.x) > 38.0:
		return false
	for i in _loop_points.size():
		var dx: float = pos.x - _loop_points[i].x
		var dz: float = pos.z - _loop_points[i].z
		if dx * dx + dz * dz <= 100.0:
			return true
	return false


func _zone_speed_cap(pos: Vector3) -> float:
	## Speed ceiling per surface. Dirt is the park's only real grip drop; the
	## skidpad and paddock are slow-speed work areas. The kicker lane stays open
	## once a jump is committed.
	if pos.x >= DIRT_RECT.position.x and pos.x <= DIRT_RECT.end.x \
			and pos.z >= DIRT_RECT.position.y and pos.z <= DIRT_RECT.end.y:
		return 0.50
	var skid_x: float = pos.x - SKID_CENTRE.x
	var skid_z: float = pos.z - SKID_CENTRE.y
	if skid_x * skid_x + skid_z * skid_z \
			<= (SKID_RADIUS + 2.0) * (SKID_RADIUS + 2.0):
		return 0.55
	if pos.x >= LANE_X - LANE_HALF - 1.0 and pos.x <= LANE_X + LANE_HALF + 1.0 \
			and pos.z >= LANE_END_Z and pos.z <= LANE_START_Z + 6.0:
		if not (_dest_kind == DEST_RAMP and _dest_phase == 1):
			return 0.62
	if pos.x >= PADDOCK_RECT.position.x and pos.x <= PADDOCK_RECT.end.x \
			and pos.z >= PADDOCK_RECT.position.y \
			and pos.z <= PADDOCK_RECT.end.y:
		return 0.55
	return 1.0


func _record_visit() -> void:
	## Bounded diagnostics: one packed counter per destination and a bitmask for
	## the distinct count, both updated only when a destination is reached.
	if _dest_index < 0 or _dest_index >= visit_counts.size():
		return
	visit_counts[_dest_index] = visit_counts[_dest_index] + 1
	destinations_visited += 1
	var bit: int = 1 << _dest_index
	if (_visited_mask & bit) == 0:
		_visited_mask |= bit
		distinct_destinations += 1


func _pick_destination() -> void:
	## Weighted random facility pick with a per-bot appetite for the kickers. The
	## previous destination is skipped so the bots keep moving between zones.
	var want_ramp: bool = _rng.randf() < _ramp_chance
	var chosen: int = _weighted_pick(want_ramp, _dest_index)
	if chosen < 0:
		chosen = _weighted_pick(not want_ramp, _dest_index)
	if chosen < 0:
		return
	_dest_index = chosen
	var used_bit: int = 1 << chosen
	if (_used_mask & used_bit) == 0:
		_used_mask |= used_bit
		destinations_used += 1
	var entry: Dictionary = DESTINATIONS[chosen]
	_dest_kind = int(entry["kind"])
	var entry_point: Vector3 = entry["entry"]
	var launch_point: Vector3 = entry["launch"]
	if _dest_kind == DEST_LOOP:
		entry_point = _loop_points[_loop_join_index]
	elif _dest_kind == DEST_WEAVE:
		entry_point = WEAVE_POINTS[0]
	_dest_entry = entry_point
	_ramp_launch = launch_point
	_dest_phase = 0
	_dest_timer = 0.0
	_near_timer = 0.0
	_loop_active = false
	_loop_exit = false
	_loop_laps = 0
	_loop_distance = 0.0
	_loop_last_distance = 0.0
	_loop_stall = 0.0
	_weave_index = 0
	destination_name = str(entry["name"])
	# Pick one detour waypoint. The circuit enters and leaves through the paved
	# gap, and the kickers need a straight run-up before the lane.
	var here: Vector3 = _cart_position()
	var via: Vector3 = Vector3.ZERO
	if _dest_kind == DEST_LOOP:
		var gate_offset: Vector2 = Vector2(here.x - LOOP_GATE.x,
			here.z - LOOP_GATE.z)
		if gate_offset.length_squared() > 36.0:
			# The paved gap is the only opening in the armco: come in through it
			# instead of cutting a chord across the barrier.
			via = LOOP_GATE
	elif _dest_kind == DEST_RAMP:
		var lined_up: bool = here.z > JUMP_RUNUP.z - 10.0 \
			and absf(here.x - LANE_X) < 12.0
		if not lined_up:
			via = JUMP_RUNUP
	else:
		via = _route_via(here, entry_point)
	if _post_jump_exit and _dest_kind != DEST_RAMP:
		_post_jump_exit = false
		if here.z < 0.0:
			# Leave the lane to the north first: a direct line east or south
			# from the landing runs into the loop armco or the pit block.
			via = JUMP_EXIT
	_via_active = via != Vector3.ZERO
	_via_target = via
	_dest_target = via if _via_active else entry_point
	# Every leg gets its own wander rhythm, so the line never looks scripted.
	_wander_phase = _rng.randf() * TAU
	_wander_rate = _rng.randf_range(0.35, 0.9)
	_wander_amp = _rng.randf_range(0.9, 2.6) * (1.15 - skill * 0.25)


func _weighted_pick(ramp: bool, skip: int) -> int:
	## One weighted draw from the requested destination kind, never the last one.
	var total: float = 0.0
	for i in DESTINATIONS.size():
		if i == skip:
			continue
		var entry: Dictionary = DESTINATIONS[i]
		if bool(int(entry["kind"]) == DEST_RAMP) != ramp:
			continue
		total += float(entry["weight"])
	if total <= 0.0:
		return -1
	var roll: float = _rng.randf() * total
	for i in DESTINATIONS.size():
		if i == skip:
			continue
		var entry: Dictionary = DESTINATIONS[i]
		if bool(int(entry["kind"]) == DEST_RAMP) != ramp:
			continue
		roll -= float(entry["weight"])
		if roll <= 0.0:
			return i
	return -1


func _cart_position() -> Vector3:
	return cart.global_position if is_instance_valid(cart) else Vector3.ZERO


func _route_via(from: Vector3, to: Vector3) -> Vector3:
	## One cheap detour point when the straight seed leg would cut through a
	## solid feature. Runs only on a destination pick, never inside a tick loop.
	var flat_from := Vector2(from.x, from.z)
	var flat_to := Vector2(to.x, to.z)
	var leg: Vector2 = flat_to - flat_from
	var leg_length: float = leg.length()
	if leg_length < 12.0:
		return Vector3.ZERO
	var normal: Vector2 = Vector2(-leg.y, leg.x) / leg_length
	for i in NO_GO_CENTERS.size():
		var center: Vector2 = NO_GO_CENTERS[i]
		var radius: float = NO_GO_RADII[i]
		if flat_from.distance_to(center) < radius + 2.0 \
				or flat_to.distance_to(center) < radius + 2.0:
			continue
		var t: float = clampf((center - flat_from).dot(leg) / (leg_length * leg_length),
			0.0, 1.0)
		if (flat_from + leg * t).distance_to(center) >= radius + 3.0:
			continue
		var best_extra: float = INF
		var best: Vector3 = Vector3.ZERO
		var found: bool = false
		for side: float in [-1.0, 1.0]:
			var candidate: Vector2 = center + normal * ((radius + 8.0) * side)
			if absf(candidate.x) > PARK_LIMIT or absf(candidate.y) > PARK_LIMIT:
				continue
			var blocked: bool = false
			for j in NO_GO_CENTERS.size():
				if j == i:
					continue
				if candidate.distance_to(NO_GO_CENTERS[j]) < NO_GO_RADII[j] + 2.0:
					blocked = true
					break
			if blocked:
				continue
			var extra: float = flat_from.distance_to(candidate) \
				+ candidate.distance_to(flat_to) - leg_length
			if extra < best_extra:
				best_extra = extra
				best = Vector3(candidate.x, 0.0, candidate.y)
				found = true
		if found:
			return best
	return Vector3.ZERO


func _sample_ground(pos: Vector3, forward: Vector3, speed: float) -> void:
	## One down-probe at a speed-scaled lookahead. A moderate rise is a kicker and
	## earns a straight, committed approach; a near-vertical rise is a face to
	## slow for.
	var probe: float = clampf(4.5 + speed * 0.45, 5.5, 11.0)
	var origin: Vector3 = pos + forward * probe + Vector3.UP * 6.0
	_ray.from = origin
	_ray.to = origin + Vector3.DOWN * 14.0
	_ray.collision_mask = GROUND_MASK
	var space: PhysicsDirectSpaceState3D = cart.get_world_3d().direct_space_state
	var hit: Dictionary = space.intersect_ray(_ray)
	if hit.is_empty():
		_ground_grade = 0.0
		return
	var rise: float = (hit["position"] as Vector3).y - pos.y
	_ground_grade = rise / probe
	if _ground_grade >= RAMP_GRADE_MIN and _ground_grade <= RAMP_GRADE_MAX \
			and rise > 0.22:
		_ramp_timer = maxf(_ramp_timer, 0.65)
	elif _ground_grade > RAMP_GRADE_MAX:
		_cliff_timer = maxf(_cliff_timer, 0.4)


func _ground_height(at: Vector3) -> float:
	## Floor height under a respawn slot. Start above the tallest facility solid so
	## a slot on the apron or the kicker lane finds the real surface instead of
	## falling back to y=0.
	var space: PhysicsDirectSpaceState3D = cart.get_world_3d().direct_space_state
	_ray.from = at + Vector3.UP * 12.0
	_ray.to = at + Vector3.DOWN * 30.0
	_ray.collision_mask = GROUND_MASK
	var hit: Dictionary = space.intersect_ray(_ray)
	if hit.is_empty():
		return 0.0
	return (hit["position"] as Vector3).y + 0.001
