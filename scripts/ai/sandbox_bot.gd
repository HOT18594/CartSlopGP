extends RefCounted
## Free-roam driver for the sandbox AI carts.
##
## One bot owns the virtual inputs of one CartPlayer. It follows a moving target
## around the park's open verge, steers around world geometry and props with a
## few short raycasts, keeps its distance from the other carts, manages speed and
## boost, squares up to ramps, and reverses itself out when it gets pinned.
##
## The owning scene keeps the cart and the respawn threshold. This object keeps
## every personality field (skill, radius, phase, boost_bias) and reuses a single
## ray query, so a physics tick allocates nothing of its own.

const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")

## A kart has to go around the world, solid props and other carts. Cones sit on
## the non-blocking PROP layer, so driving through one is intentionally allowed.
const OBSTACLE_MASK: int = CollisionLayers.WORLD | CollisionLayers.SOLID_PROP \
	| CollisionLayers.PLAYER | CollisionLayers.GHOST
## Terrain, ramps and raised track bodies only. Props are avoided as obstacles;
## they must not read as a ramp in the ground probe.
const GROUND_MASK: int = CollisionLayers.WORLD

## The ring road is 52-58 m out. The verge just outside it stays clear of the
## mesa, highline, bowl, pond and slalom furniture all the way to the wall.
const LANE_MIN: float = 55.0
const LANE_MAX: float = 61.0
## Keep the moving target off the perimeter wall after an avoidance nudge.
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

var cart: CartPlayer
var skill: float = 0.8
var radius: float = 55.0
var radius_offset: float = 0.0
var phase: float = 0.0
var boost_bias: float = 0.7
var path_style: int = 0
## Seconds spent below STUCK_SPEED and outside the park, read by the owner for
## the hard respawn.
var stuck: float = 0.0
var stranded: float = 0.0

var _ray: PhysicsRayQueryParameters3D
var _exclude: Array[RID] = []
var _probe_timer: float = 0.0
var _ground_grade: float = 0.0
var _ramp_timer: float = 0.0
var _cliff_timer: float = 0.0
var _reverse_timer: float = 0.0
var _reverse_steer: float = 0.0
var _reverse_cooldown: float = 0.0
var _avoid_side: float = 0.0
var _avoid_hold: float = 0.0
var _lane: float = 56.0
var _last_steer: float = 0.0


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
	_ray = PhysicsRayQueryParameters3D.new()
	_ray.collide_with_areas = false
	_ray.collide_with_bodies = true
	_exclude.append(cart.get_rid())
	_ray.exclude = _exclude
	_lane = _desired_lane(0.0)


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
	if pos.y < -3.0 or Vector2(pos.x, pos.z).length() > 80.0:
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
	_lane = _desired_lane(time)
	var look: float = clampf(6.5 + speed * 0.55, 7.0, 17.0) \
		* lerpf(1.12, 0.92, clampf(skill, 0.0, 1.12))
	var here_angle: float = atan2(pos.z, pos.x)
	var target_angle: float = here_angle + look / _lane
	var target := Vector3(cos(target_angle) * _lane, pos.y,
		sin(target_angle) * _lane)
	var target_speed: float = cart.max_speed \
		* lerpf(0.62, 0.92, clampf(skill, 0.0, 1.12))
	var space: PhysicsDirectSpaceState3D = cart.get_world_3d().direct_space_state
	var avoid: float = 0.0
	var path_clear: float = 99.0
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
				# Dead ahead: pass on whichever side the lane target wants.
				side = -signf((target - pos).dot(right))
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
				lane_side = -signf((target - pos).dot(right))
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
	# ---- ramp awareness: aim straight down the ramp, then carry the speed over ----
	if _ramp_timer > 0.0:
		target = pos + forward * look
	target += right * (-avoid * 3.0)
	target.x = clampf(target.x, -PARK_LIMIT, PARK_LIMIT)
	target.z = clampf(target.z, -PARK_LIMIT, PARK_LIMIT)
	var local_target: Vector3 = cart.to_local(target)
	var steer: float = clampf(atan2(-local_target.x, -local_target.z) * 2.1,
		-1.0, 1.0)
	steer += sin(time * 1.1 + phase) * (1.06 - clampf(skill, 0.0, 1.06)) * 0.10
	if _ramp_timer > 0.0:
		steer *= 0.45
	steer = clampf(steer + avoid * 0.45, -1.0, 1.0)
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
	if _ramp_timer > 0.0:
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
		brake = maxf(brake, clampf((3.2 - path_clear) / 3.2, 0.0, 0.8))
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
	## Same lane-slot recovery the sandbox always used: keep the bot's line, sit
	## it on the real ground and clear every recovery timer.
	if not is_instance_valid(cart):
		return
	var at: Vector3 = cart.global_position
	var angle: float = atan2(at.z, at.x) + 0.12
	var slot := Vector3(cos(angle) * _lane, 0.0, sin(angle) * _lane)
	slot.y = _ground_height(slot) + 0.12
	cart.global_position = slot
	cart.rotation = Vector3(0.0, PI - angle, 0.0)
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


func _desired_lane(time: float) -> float:
	## The moving line: every bot drifts across the open verge band at its own
	## rate, so a pack spreads out instead of orbiting on one radius.
	var wander: float = sin(time * 0.21 + phase) \
		* lerpf(2.0, 0.7, clampf(skill, 0.0, 1.12))
	if path_style == 1:
		wander += sin(time * 0.13 + phase * 1.7) * 1.6
	elif path_style == 2:
		wander += sin(time * 0.37 + phase * 0.6) * 1.2
	return clampf(56.0 + (radius - 53.0) * 0.55 + radius_offset * 0.30 + wander,
		LANE_MIN, LANE_MAX)


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
