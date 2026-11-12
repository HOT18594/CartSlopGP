extends RefCounted
## Free-roam driver for the sandbox AI carts.
##
## One bot owns the virtual inputs of one CartPlayer. Instead of orbiting the
## ring road it explores the park: it picks landmark or open-ground destinations
## (start gate, pond, paddocks, drift pad, bowl, ramps), wanders between them,
## commits to the occasional ramp run and keeps its distance from other carts.
## A few short raycasts see obstacles and ramps; the ground probe runs at 10 Hz.
##
## The owning scene keeps the cart and the respawn threshold. This object keeps
## every personality field (skill, ramp appetite, boost bias) and reuses a single
## ray query, so a physics tick allocates nothing of its own.

const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")

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

## Destination kinds: open-ground landmark versus a two-point ramp run.
const DEST_OPEN: int = 0
const DEST_RAMP: int = 1
## How close (metres) counts as reaching a destination or a ramp entry.
const ARRIVE_RADIUS: float = 6.5
## A bot that hovers close to a waypoint without crossing the arrival radius for
## this long accepts it. Prevents a fast kart from orbiting a small target.
const NEAR_ACCEPT_TIME: float = 5.0
## Abandon an unreachable destination after this long (seconds).
const DEST_TIMEOUT: float = 30.0

## Big solid features the route helper steers around when a landmark leg points
## straight through one. Bowl and drift pad are drivable and deliberately absent.
const NO_GO_CENTERS: Array[Vector2] = [
	Vector2(34.0, -16.0), Vector2(12.0, -40.0), Vector2(18.0, -16.0),
	Vector2(-54.0, -54.0),
]
const NO_GO_RADII: Array[float] = [18.0, 17.0, 8.0, 15.0]

## Open-ground destinations around SLOP YARD, copied from the sandbox park
## layout. Weights keep the field exploring the whole park and bias it toward
## open ground; ramps are drawn only by the per-bot ramp appetite.
const DESTINATIONS: Array[Dictionary] = [
	{"name": "start gate", "entry": Vector3(0.0, 0.0, 57.0),
		"launch": Vector3.ZERO, "kind": DEST_OPEN, "weight": 1.15},
	{"name": "east apron", "entry": Vector3(24.0, 0.0, 46.0),
		"launch": Vector3.ZERO, "kind": DEST_OPEN, "weight": 0.95},
	{"name": "paddock", "entry": Vector3(49.0, 0.0, 39.0),
		"launch": Vector3.ZERO, "kind": DEST_OPEN, "weight": 1.05},
	{"name": "north paddock", "entry": Vector3(-44.0, 0.0, 52.0),
		"launch": Vector3.ZERO, "kind": DEST_OPEN, "weight": 0.90},
	{"name": "pond shore", "entry": Vector3(-42.0, 0.0, -42.0),
		"launch": Vector3.ZERO, "kind": DEST_OPEN, "weight": 1.10},
	{"name": "pond dock", "entry": Vector3(-56.0, 0.0, -38.0),
		"launch": Vector3.ZERO, "kind": DEST_OPEN, "weight": 0.80},
	{"name": "drift pad", "entry": Vector3(-28.0, 0.0, -28.0),
		"launch": Vector3.ZERO, "kind": DEST_OPEN, "weight": 1.15},
	{"name": "bowl rim", "entry": Vector3(-20.0, 0.0, 16.0),
		"launch": Vector3.ZERO, "kind": DEST_OPEN, "weight": 0.90},
	{"name": "east field", "entry": Vector3(48.0, 0.0, 5.0),
		"launch": Vector3.ZERO, "kind": DEST_OPEN, "weight": 1.05},
	{"name": "south field", "entry": Vector3(35.0, 0.0, -45.0),
		"launch": Vector3.ZERO, "kind": DEST_OPEN, "weight": 1.00},
	{"name": "west field", "entry": Vector3(-45.0, 0.0, 0.0),
		"launch": Vector3.ZERO, "kind": DEST_OPEN, "weight": 1.00},
	{"name": "jump lane", "entry": Vector3(0.0, 0.0, 22.0),
		"launch": Vector3(0.0, 0.0, -4.0), "kind": DEST_RAMP, "weight": 1.10},
	{"name": "mesa ramp", "entry": Vector3(34.0, 0.0, 22.0),
		"launch": Vector3(34.0, 0.0, -10.0), "kind": DEST_RAMP, "weight": 0.55},
	{"name": "highline ramp", "entry": Vector3(12.0, 0.0, -18.0),
		"launch": Vector3(12.0, 0.0, -38.0), "kind": DEST_RAMP, "weight": 0.40},
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
var _avoid_side: float = 0.0
var _avoid_hold: float = 0.0
var _last_steer: float = 0.0
var _ramp_chance: float = 0.12
var _wander_amp: float = 1.8
var _wander_rate: float = 0.55
var _wander_phase: float = 0.0
var _dest_index: int = -1
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
	_probe_timer -= delta
	if _probe_timer <= 0.0:
		_probe_timer = PROBE_INTERVAL
		_sample_ground(pos, forward, speed)
	_ramp_timer = maxf(_ramp_timer - delta, 0.0)
	_cliff_timer = maxf(_cliff_timer - delta, 0.0)
	_avoid_hold = maxf(_avoid_hold - delta, 0.0)
	_reverse_cooldown = maxf(_reverse_cooldown - delta, 0.0)
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
		cart.set_ai_controls(0.45, 0.0, 0.0, false)
		return
	# ---- destination: arrive, launch a ramp, or pick the next landmark ----
	if _dest_index < 0:
		_pick_destination()
	_dest_timer += delta
	var to_dest: Vector3 = _dest_target - pos
	to_dest.y = 0.0
	var dest_dist: float = to_dest.length()
	if dest_dist < 16.0:
		_near_timer += delta
	else:
		_near_timer = 0.0
	if dest_dist < ARRIVE_RADIUS or _near_timer > NEAR_ACCEPT_TIME \
			or _dest_timer > DEST_TIMEOUT:
		_advance_destination()
		_near_timer = 0.0
		to_dest = _dest_target - pos
		to_dest.y = 0.0
		dest_dist = to_dest.length()
	var look: float = clampf(6.5 + speed * 0.55, 7.0, 17.0) \
		* lerpf(1.12, 0.92, clampf(skill, 0.0, 1.12))
	var direction: Vector3 = to_dest / dest_dist if dest_dist > 0.1 \
		else Vector3.FORWARD
	# Wander sideways of the destination leg, finishing the leg on line.
	var target: Vector3 = _dest_target
	if dest_dist > look:
		target = pos + direction * look
		if _dest_phase == 0:
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
	# A committed ramp run steers less around obstacles, but still sees walls.
	var avoid_scale: float = 1.0 if _dest_phase == 0 else 0.45
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
	avoid = clampf(avoid, -1.0, 1.0)
	if _avoid_hold > 0.0:
		avoid = clampf(avoid + _avoid_side * 0.35 * (_avoid_hold / 0.35),
			-1.0, 1.0)
	# ---- ramp awareness: aim straight down a detected slope, then carry speed ----
	if _ramp_timer > 0.0 and _dest_phase == 0:
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
	if _ramp_timer > 0.0 or _dest_phase == 1:
		target_speed = maxf(target_speed,
			cart.max_speed * lerpf(0.70, 0.90, clampf(skill, 0.0, 1.12)))
	target_speed = maxf(target_speed, 4.0)
	var throttle: float = 0.0
	var brake: float = 0.0
	if speed < target_speed:
		throttle = clampf(0.7 + skill * 0.3, 0.0, 1.0)
	if speed > target_speed + 0.7:
		brake = clampf((speed - target_speed) / 4.0, 0.0, 0.85)
	if path_clear < 3.2 and speed > STUCK_SPEED:
		brake = maxf(brake, clampf((3.2 - path_clear) / 3.2, 0.0, 0.8) * avoid_scale)
	if brake > 0.0:
		throttle = 0.0
	# ---- boost: only on a straight with a genuinely clear path ahead ----
	var boost: bool = path_clear > 14.0 and absf(steer) < 0.30 \
		and absf(avoid) < 0.30 and grade < 0.12 and _cliff_timer <= 0.0 \
		and speed > cart.max_speed * 0.55 and cart.boost_amount > 25.0 \
		and boost_bias > 0.52
	cart.set_ai_controls(throttle, brake, steer, boost)
	_last_steer = steer


func respawn() -> void:
	## Put the bot back on the ground just short of its current destination,
	## facing it, and clear every recovery counter.
	if not is_instance_valid(cart):
		return
	var anchor: Vector3 = _dest_target
	if anchor == Vector3.ZERO:
		anchor = Vector3(cos(phase) * radius, 0.0, sin(phase) * radius)
	var flat := Vector3(anchor.x, 0.0, anchor.z)
	var inward: Vector3 = -flat
	if inward.length_squared() < 1.0:
		inward = Vector3(1.0, 0.0, 0.0)
	var slot: Vector3 = flat + inward.normalized() * 9.0
	slot.x = clampf(slot.x, -PARK_LIMIT, PARK_LIMIT)
	slot.z = clampf(slot.z, -PARK_LIMIT, PARK_LIMIT)
	slot.y = _ground_height(slot) + 0.12
	var facing: Vector3 = flat - slot
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
	_ramp_timer = 0.0
	_cliff_timer = 0.0
	_avoid_hold = 0.0
	_last_steer = 0.0
	_dest_phase = 0
	_dest_timer = 0.0
	_near_timer = 0.0
	_dest_target = _via_target if _via_active else _dest_entry


func _advance_destination() -> void:
	## Reach the current waypoint. A route detour first returns to the landmark
	## leg; a ramp destination first switches to its launch point. Only the final
	## waypoint is counted as visited.
	if _via_active:
		_via_active = false
		_dest_target = _dest_entry
		_dest_timer = 0.0
		_near_timer = 0.0
		return
	if _dest_phase == 0 and _ramp_launch != Vector3.ZERO:
		_dest_phase = 1
		_dest_target = _ramp_launch
		_dest_timer = 0.0
		_near_timer = 0.0
		_ramp_timer = maxf(_ramp_timer, 0.9)
		return
	if _dest_index >= 0:
		_record_visit()
	_pick_destination()


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
	## Weighted random landmark pick with a per-bot appetite for ramp runs. The
	## previous destination is skipped so the bots keep moving across the park.
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
	var entry_point: Vector3 = entry["entry"]
	var launch_point: Vector3 = entry["launch"]
	_dest_entry = entry_point
	_ramp_launch = launch_point
	_dest_phase = 0
	_dest_timer = 0.0
	_near_timer = 0.0
	destination_name = str(entry["name"])
	# A landmark across the mesa/highline/pond needs a detour waypoint first.
	var via: Vector3 = _route_via(_cart_position(), entry_point)
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
	## One cheap detour point when the straight landmark leg would cut through a
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
	## One down-probe at a speed-scaled lookahead. A moderate rise is a ramp and
	## earns a straight, committed approach; a near-vertical rise is a hill face
	## worth slowing for.
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
	## Floor height under a respawn slot. Mirrors the sandbox spawn probe: start
	## above the tallest park feature so a slot on the mesa/highline skirt finds
	## the real surface instead of falling back to y=0.
	var space: PhysicsDirectSpaceState3D = cart.get_world_3d().direct_space_state
	_ray.from = at + Vector3.UP * 12.0
	_ray.to = at + Vector3.DOWN * 30.0
	_ray.collision_mask = GROUND_MASK
	var hit: Dictionary = space.intersect_ray(_ray)
	if hit.is_empty():
		return 0.0
	return (hit["position"] as Vector3).y + 0.001
