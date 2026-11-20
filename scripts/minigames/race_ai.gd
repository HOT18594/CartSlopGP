extends RefCounted
## Reusable racing driver for the Meadow Loop rivals.

const TrackDefs := preload("res://scripts/minigames/track_defs.gd")
##
## The driver precomputes everything it can once: four distinct racing lines
## sampled from the track spline (inside-apex, outside-sweep, late-apex and a
## flat defensive line), a curvature-limited speed profile with a backward
## braking pass, and the corner tables the lookups need. Each bot is assigned
## one line by personality, then shifts off it dynamically to pass a slower
## cart, cover the inside when a faster cart is alongside, or take a wider
## entry after running off line.
##
## Per-driver quirks (braking point, throttle application, steering wobble and
## the occasional low-skill mistake) come from a deterministic seed, so two
## bots with the same skill still drive differently while a race seed stays
## reproducible.
##
## It owns no scene nodes. The caller keeps the cart and its progress
## bookkeeping, calls update(), then applies the public throttle / brake /
## steer / boost / drift fields with CartPlayer.set_ai_controls().
##
## The profile depends only on the track, the cart's top speed and the bot's
## fixed skill, so there is no rubber-banding: a fast human never slows a bot
## down and a slow one never speeds one up.

## Arc-length spacing of the precomputed line, curvature and speed samples.
const LINE_STEP: float = 2.5
## Largest racing-line offset toward a corner's inside, as a share of the
## usable half width (road half width minus EDGE_MARGIN).
const INSIDE_SHARE: float = 0.45
## How far the line keeps from the barrier so no sample is a wall hit.
const EDGE_MARGIN: float = 1.5
## Smoothing passes over the lateral offsets. Three passes at a 2.5 m step make
## the line continuous without rounding the apex away.
const LINE_SMOOTH_PASSES: int = 3
## Curvature (1/m) that earns the full inside offset; this loop peaks near 0.06.
const CURVE_FULL: float = 0.06

## Racing-line personalities. Every bot follows one as its base line.
const LINE_APEX: int = 0
## Wide on entry, tight through the middle, drifting wide on exit.
const LINE_SWEEP: int = 1
## Holds the outside longer, turns in later and squares the exit.
const LINE_LATE: int = 2
## Flat, central line that leaves room to cover the inside.
const LINE_DEFEND: int = 3
const LINE_COUNT: int = 4
const LINE_NAMES: PackedStringArray = [
	"inside-apex", "outside-sweep", "late-apex", "defensive",
]
## Gain on the second difference of the inside profile. That difference is
## negative at the apex and positive on entry/exit, which is exactly the
## outside-wide, apex-tight shape the sweep line wants.
const SWEEP_CURVE_GAIN: float = 7.0
## Arc-length shift (metres) that moves the apex point toward the exit.
const LATE_APEX_SHIFT: float = 7.5
## Share of the apex offset kept by the flat defensive line.
const DEFEND_SHARE: float = 0.55

## Dynamic line mode for the current tick.
enum LineMode { NORMAL, OVERTAKE, BLOCK, WIDE }

## Seconds a pass line is held, and how far (metres) it pulls across.
const OVERTAKE_TIME: float = 1.25
const OVERTAKE_BIAS: float = 2.7
## Seconds a blocking move is held, and how far it moves toward the attacker.
const BLOCK_TIME: float = 0.85
const BLOCK_BIAS: float = 1.1
## How far off the intended line counts as "off-line" (metres).
const OFFLINE_LIMIT: float = 1.4
## A low-skill mistake holds a wrong steering input this long.
const MISTAKE_TIME: float = 0.7
const MISTAKE_COOLDOWN: float = 7.0

## Lateral acceleration (m/s^2) the mid-skill bot carries through a corner.
const LAT_ACCEL: float = 11.5
## Deceleration (m/s^2) the backward braking pass plans with. The cart can brake
## harder; planning with less is what starts the braking early enough.
const BRAKE_DECEL: float = 9.0
## Slowest speed the profile ever asks for through a hairpin (m/s).
const MIN_CORNER_SPEED: float = 5.0
## The profile is sampled this many metres ahead so the throttle leads a little.
const SPEED_PREVIEW: float = 1.0

## Lookahead distance (metres) at a standstill and per m/s of speed.
const BASE_LOOKAHEAD: float = 4.5
const LOOKAHEAD_PER_SPEED: float = 0.55

## Under this speed with the throttle applied counts as stuck (m/s).
const STUCK_SPEED: float = 1.2
## Seconds of applied throttle under STUCK_SPEED before reversing out.
const STUCK_TRIGGER: float = 0.9
## Longest reverse manoeuvre (seconds).
const REVERSE_TIME: float = 1.2
## Seconds after a reverse before another recovery may start.
const RECOVERY_COOLDOWN: float = 0.8
## Space kept behind the cart before reversing (metres).
const REVERSE_CLEARANCE: float = 4.0

## Rivals and the player are avoided inside this distance ahead (metres).
const CART_AVOID_RANGE: float = 6.5
## Half the width of the corridor that counts as "roughly in the way" for carts.
const CART_AVOID_HALF_WIDTH: float = 2.4
## Same, for solid trackside bodies.
const OBSTACLE_AVOID_RANGE: float = 6.0
const OBSTACLE_HALF_WIDTH: float = 1.3
## Cap on the total lateral bias one avoidance pass may add (metres).
const AVOID_MAX_BIAS: float = 3.0

## Inputs produced by the last update(). The caller feeds them to the cart.
var throttle: float = 0.0
var brake: float = 0.0
var steer: float = 0.0
var boost: bool = false
var drift: bool = false

## Base racing line this driver was configured with (one of LINE_*).
var line_style: int = LINE_APEX
## Dynamic line mode for the current tick (one of LineMode).
var line_mode: int = LineMode.NORMAL
## How many times the dynamic line mode has changed. Diagnostics only.
var line_changes: int = 0

var _spline: RefCounted
var _preset: Dictionary = {}
var _count: int = 0
var _length: float = 1.0
var _step: float = 1.0
var _half_width: float = 5.5
var _usable: float = 4.0
var _centres: PackedVector3Array = PackedVector3Array()
var _rights: PackedVector3Array = PackedVector3Array()
var _offsets: PackedFloat32Array = PackedFloat32Array()
var _inside: PackedFloat32Array = PackedFloat32Array()
var _lines: Array[PackedFloat32Array] = []
var _active_line: PackedFloat32Array = PackedFloat32Array()
var _curvature: PackedFloat32Array = PackedFloat32Array()
var _speeds: PackedFloat32Array = PackedFloat32Array()
var _obstacles: PackedVector3Array = PackedVector3Array()

var _skill: float = 0.8
var _lane_bias: float = 0.0
var _boost_bias: float = 0.5
var _lookahead_scale: float = 1.0
var _steer_gain: float = 2.1
var _reaction: float = 9.0
var _lat_accel: float = LAT_ACCEL
var _brake_decel: float = BRAKE_DECEL
var _speed_cap: float = 19.0
var _phase: float = 0.0
var _aggression: float = 0.5
var _brake_lead: float = 0.0
var _throttle_gain: float = 1.0
var _exit_eagerness: float = 0.60
var _wobble_amp: float = 0.02
var _wobble_rate: float = 1.1
var _mistake_rate: float = 0.02

var _time: float = 0.0
var _mistake_time: float = 0.0
var _mistake_cooldown: float = 6.0
var _mistake_side: float = 0.0
var _overtake_offset: float = 0.0
var _overtake_timer: float = 0.0
var _block_offset: float = 0.0
var _block_timer: float = 0.0
## Avoidance scan results, kept as fields so a tick allocates nothing.
var _scan_slow_ahead: bool = false
var _scan_side: float = 0.0
var _scan_gap: float = INF
var _scan_speed: float = 0.0
var _scan_faster_side: float = 0.0
## Small deterministic LCG for personality quirks and mistakes.
var _rng_state: int = 1

var _stuck_time: float = 0.0
var _reverse_time: float = 0.0
var _reverse_steer: float = 0.0
var _recovery_cooldown: float = 0.0
var _avoid_speed_cap: float = INF
var _last_throttle: float = 0.0
var _last_steer: float = 0.0


func _init(spline: RefCounted, road_half: float = 5.5,
		preset: Dictionary = {}) -> void:
	## Build the racing line once, from the same spline the road is built from.
	_spline = spline
	_preset = preset
	_half_width = maxf(road_half, 1.0)
	_usable = maxf(_half_width - EDGE_MARGIN, 0.8)
	_build_line()


func set_preset(preset: Dictionary) -> void:
	## Update the track preset used for surface-grip braking in _build_speed_profile.
	_preset = preset
	var tuned: float = clampf(inverse_lerp(0.62, 1.12, _skill), 0.0, 1.0)
	_build_speed_profile(lerpf(0.86, 1.0, tuned))


func configure(skill: float, lane_bias: float, boost_bias: float,
		max_speed: float, personality: int = -1, phase: float = 0.0,
		aggression: float = 0.5, lookahead_trim: float = 1.0) -> void:
	## Bake this bot's personal limits once its vehicle (and top speed) is set.
	## Skill only varies margins, lookahead, reaction and the speed cap; it never
	## reads the player's position, so the field cannot rubber-band. Personality
	## picks the base racing line; phase, aggression and the lookahead trim give
	## two equally skilled drivers different lines and different inputs.
	_skill = clampf(skill, 0.3, 1.4)
	var tuned: float = clampf(inverse_lerp(0.62, 1.12, _skill), 0.0, 1.0)
	_lane_bias = clampf(lane_bias, -1.0, 1.0) * _usable * 0.16
	_boost_bias = clampf(boost_bias, 0.0, 1.0)
	_lookahead_scale = lerpf(0.84, 1.06, tuned) \
		* clampf(lookahead_trim, 0.82, 1.18)
	_steer_gain = lerpf(1.85, 2.45, tuned)
	_reaction = lerpf(6.5, 13.5, tuned)
	_lat_accel = lerpf(10.0, 15.0, tuned)
	_phase = phase
	_aggression = clampf(aggression, 0.0, 1.0)
	if personality >= 0:
		line_style = posmod(personality, LINE_COUNT)
	else:
		# Callers that only pass the original four arguments still get variety.
		line_style = posmod(int(absf(lane_bias) * 8.0 + _skill * 11.0),
			LINE_COUNT)
	if line_style < _lines.size():
		_active_line = _lines[line_style]
	else:
		_active_line = _offsets
	# Everything below is deterministic from the same personality inputs.
	_rng_state = 1 + posmod(line_style * 104729 + int(absf(phase) * 9973.0)
		+ int(absf(lane_bias) * 7919.0) + int(max_speed * 31.0), 0x7FFFFFFE)
	_brake_decel = lerpf(7.5, 10.0, tuned) * _rand_range(0.95, 1.05)
	_brake_lead = lerpf(1.6, -1.2, tuned) + _rand_range(-0.8, 0.8)
	_throttle_gain = _rand_range(0.90, 1.10)
	_exit_eagerness = _rand_range(0.52, 0.68)
	_wobble_amp = _rand_range(0.015, 0.035) + (1.0 - tuned) * 0.05
	_wobble_rate = _rand_range(0.7, 1.5)
	_mistake_rate = 0.004 + (1.0 - tuned) * 0.045
	_speed_cap = maxf(max_speed, 1.0) * lerpf(0.84, 1.0, tuned)
	_build_speed_profile(lerpf(0.86, 1.0, tuned))
	line_mode = LineMode.NORMAL
	_time = 0.0
	_overtake_timer = 0.0
	_block_timer = 0.0
	_mistake_time = 0.0
	_mistake_cooldown = _rand_range(6.0, 14.0)


func set_obstacles(points: PackedVector3Array) -> void:
	## Solid trackside bodies (hay-bale walls, apex tyre stacks) the line must
	## dodge. The caller owns the array; the packed copy is cheap and avoids a
	## per-frame physics query.
	_obstacles = points


func reset() -> void:
	## Clear recovery state after the owner respawns the cart. The base line and
	## the diagnostic counters stay; only the transient manoeuvres reset.
	_stuck_time = 0.0
	_reverse_time = 0.0
	_reverse_steer = 0.0
	_recovery_cooldown = 0.0
	_last_steer = 0.0
	_last_throttle = 0.0
	_overtake_timer = 0.0
	_block_timer = 0.0
	_mistake_time = 0.0
	line_mode = LineMode.NORMAL


func update(delta: float, node: CartPlayer, progress: float,
		others: Array[CartPlayer]) -> void:
	## Drive one physics frame for `node`. `progress` is the rival's unwrapped
	## arc length; `others` is the caller's reused cart list and may contain this
	## cart. Results land in the public input fields.
	throttle = 0.0
	brake = 0.0
	steer = _last_steer
	boost = false
	drift = false
	if node == null or not is_instance_valid(node) or _count == 0:
		return
	var transform: Transform3D = node.global_transform
	var forward: Vector3 = -transform.basis.z
	var right: Vector3 = transform.basis.x
	forward.y = 0.0
	right.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.0001 \
		else Vector3.FORWARD
	right = right.normalized() if right.length_squared() > 0.0001 \
		else forward.cross(Vector3.UP).normalized()
	var speed: float = maxf(node.velocity.dot(forward), 0.0)
	var max_speed: float = maxf(node.max_speed, 1.0)
	_recovery_cooldown = maxf(_recovery_cooldown - delta, 0.0)

	# ---- stuck recovery: reverse out with opposite lock, never into traffic ----
	if _reverse_time > 0.0:
		_reverse_time -= delta
		_stuck_time = 0.0
		if _reverse_time <= 0.0:
			_recovery_cooldown = RECOVERY_COOLDOWN
			_last_steer = 0.0
			_last_throttle = 0.0
			return
		brake = 1.0
		steer = _reverse_steer
		_last_steer = _reverse_steer
		_last_throttle = 0.0
		return
	var planar_speed: float = Vector2(node.velocity.x, node.velocity.z).length()
	if planar_speed < STUCK_SPEED and node.is_on_floor():
		_stuck_time += delta
	else:
		_stuck_time = maxf(_stuck_time - delta * 2.0, 0.0)
	if _stuck_time > STUCK_TRIGGER and _recovery_cooldown <= 0.0 \
			and _behind_clear(node, forward, right, others):
		_reverse_time = REVERSE_TIME
		_stuck_time = 0.0
		var direction: float = -_last_steer
		if absf(direction) < 0.25:
			direction = -1.0 if _last_steer >= 0.0 else 1.0
		_reverse_steer = clampf(direction, -1.0, 1.0)
		brake = 1.0
		steer = _reverse_steer
		_last_steer = _reverse_steer
		_last_throttle = 0.0
		return

	# ---- pure pursuit: aim at the chosen line a speed-scaled distance ahead ----
	var lookahead: float = clampf(BASE_LOOKAHEAD + speed * LOOKAHEAD_PER_SPEED,
		4.0, 22.0) * _lookahead_scale
	var aim: float = progress + lookahead
	var raw: float = fposmod(aim, _length) / _step
	var index: int = int(raw)
	if index >= _count:
		index = 0
	var next: int = (index + 1) % _count
	var blend: float = raw - float(index)
	var centre: Vector3 = _centres[index].lerp(_centres[next], blend)
	var line_right: Vector3 = _rights[index].lerp(_rights[next], blend).normalized()
	var line: PackedFloat32Array = _active_line \
		if _active_line.size() == _count else _offsets
	var line_offset: float = lerpf(line[index], line[next], blend)
	var here_offset: float = _line_at(progress, line)
	var here_raw: float = fposmod(progress, _length) / _step
	var here_index: int = int(here_raw)
	if here_index >= _count:
		here_index = 0
	var here_next: int = (here_index + 1) % _count
	var here_blend: float = here_raw - float(here_index)
	var here_centre: Vector3 = _centres[here_index].lerp(
		_centres[here_next], here_blend)
	var here_right: Vector3 = _rights[here_index].lerp(
		_rights[here_next], here_blend).normalized()
	var line_error: float = (node.global_position - here_centre).dot(here_right) \
		- here_offset
	var profile_speed: float = _speed_at(progress + SPEED_PREVIEW + _brake_lead)
	var target_speed: float = profile_speed
	var avoid: float = _avoidance(node, forward, right, others, line_offset, speed)
	target_speed = minf(profile_speed, _avoid_speed_cap)

	# ---- dynamic line: pass a slower cart, cover a faster one, widen off-line ----
	_time += delta
	_overtake_timer = maxf(_overtake_timer - delta, 0.0)
	_block_timer = maxf(_block_timer - delta, 0.0)
	var dynamic: float = 0.0
	var mode: int = LineMode.NORMAL
	if _overtake_timer <= 0.0 and _scan_slow_ahead \
			and speed > _scan_speed + 0.8 and _scan_gap < CART_AVOID_RANGE:
		var pass_side: float = -signf(_scan_side)
		if absf(_scan_side) < 0.4:
			# Dead astern: pull to the roomier side of the current line.
			pass_side = -1.0 if line_offset >= 0.0 else 1.0
		var wanted: float = clampf(
			line_offset + _scan_side + pass_side * OVERTAKE_BIAS,
			-_usable, _usable)
		_overtake_offset = wanted - line_offset
		_overtake_timer = OVERTAKE_TIME
	if _block_timer <= 0.0 and absf(_scan_faster_side) > 0.01 \
			and _aggression > 0.25:
		_block_offset = clampf(signf(_scan_faster_side) * BLOCK_BIAS
			* _aggression, -1.5, 1.5)
		_block_timer = BLOCK_TIME
	if _overtake_timer > 0.0:
		dynamic += _overtake_offset
		mode = LineMode.OVERTAKE
		# Keep enough drive to actually draw alongside; the lateral bias has
		# already opened the gap. The profile still caps the corner speed.
		if _scan_gap < CART_AVOID_RANGE:
			target_speed = maxf(target_speed,
				minf(profile_speed, _scan_speed + 2.5))
	elif _block_timer > 0.0:
		dynamic += _block_offset
		mode = LineMode.BLOCK
	# Hysteresis keeps a recovering kart from flickering in and out of WIDE.
	var offline_limit: float = OFFLINE_LIMIT * 0.6 \
		if line_mode == LineMode.WIDE else OFFLINE_LIMIT
	if mode == LineMode.NORMAL and absf(line_error) > offline_limit \
			and _lines.size() > LINE_SWEEP:
		# Ran wide or got pushed off: take the sweep line's wider entry and
		# ease back rather than snapping at the apex.
		var sweep: PackedFloat32Array = _lines[LINE_SWEEP]
		var wide: float = lerpf(sweep[index], sweep[next], blend)
		line_offset = lerpf(line_offset, wide, 0.4)
		dynamic -= clampf(line_error * 0.22, -1.2, 1.2)
		mode = LineMode.WIDE
	if mode != line_mode:
		line_mode = mode
		line_changes += 1
	var lateral: float = clampf(line_offset + _lane_bias + avoid + dynamic,
		-_usable, _usable)
	var target: Vector3 = centre + line_right * lateral
	var local_target: Vector3 = node.to_local(target)
	var desired_steer: float = atan2(-local_target.x, -local_target.z) * _steer_gain

	# ---- per-driver steering character and the occasional mistake ----
	_mistake_cooldown = maxf(_mistake_cooldown - delta, 0.0)
	desired_steer += sin(_time * _wobble_rate + _phase) * _wobble_amp
	if _mistake_time > 0.0:
		_mistake_time = maxf(_mistake_time - delta, 0.0)
		desired_steer += _mistake_side * 0.45 \
			* clampf(_mistake_time / MISTAKE_TIME, 0.0, 1.0)
	elif _mistake_cooldown <= 0.0 and _skill < 1.0 \
			and _randf01() < _mistake_rate * delta:
		_mistake_time = MISTAKE_TIME
		_mistake_cooldown = MISTAKE_COOLDOWN
		_mistake_side = -1.0 if _randf01() < 0.5 else 1.0

	# ---- speed: hold the profile; the backward pass already brakes early ----
	var speed_delta: float = target_speed - speed
	if speed_delta < -0.6:
		brake = clampf(-speed_delta / (4.0 + _brake_decel * 0.2), 0.0, 1.0)
	elif speed_delta < 0.3:
		throttle = 0.38 * _throttle_gain
	else:
		throttle = clampf((_exit_eagerness + speed_delta * 0.2)
			* _throttle_gain, 0.50, 1.0)
	if _mistake_time > 0.0:
		# A mistake costs drive as well as line discipline.
		throttle *= 0.62
	var rate: float = _reaction * (1.0 + 0.4 * clampf(speed / max_speed, 0.0, 1.0))
	steer = move_toward(_last_steer, clampf(desired_steer, -1.0, 1.0), rate * delta)

	# ---- boost and drift only where the profile already says it is safe ----
	if _boost_bias > 0.52 and speed > _speed_cap * 0.62 \
			and node.boost_amount > 24.0 and brake <= 0.0:
		if _speed_at(progress + 14.0) > _speed_cap * 0.80 \
				and _speed_at(progress + 28.0) > _speed_cap * 0.70:
			boost = true
	if _skill > 0.9 and speed > max_speed * 0.62 and brake <= 0.0:
		drift = absf(_curvature_at(progress + 5.0)) > 0.045 \
			and target_speed > speed * 0.72

	# ---- airborne: hold the heading and land nose-first ----
	if not node.is_on_floor():
		throttle = maxf(throttle, 0.35)
		brake = 0.0
		steer = clampf(steer * 0.35, -0.5, 0.5)
		boost = false
		drift = false
	_last_steer = steer
	_last_throttle = throttle


func _build_line() -> void:
	## Sample the spline, turn curvature into a signed inside offset, then derive
	## every personality line from that one profile. All four are smoothed so the
	## line is continuous from start/finish around.
	if _spline == null or _spline.total_length <= 0.1:
		return
	_count = maxi(int(ceil(_spline.total_length / LINE_STEP)), 8)
	_step = _spline.total_length / float(_count)
	_length = _spline.total_length
	_centres.resize(_count)
	_rights.resize(_count)
	_offsets.resize(_count)
	_inside.resize(_count)
	_curvature.resize(_count)
	for i in _count:
		var distance: float = float(i) * _step
		var frame: Dictionary = _spline.sample(distance)
		_centres[i] = frame["position"]
		_rights[i] = frame["right"]
		_curvature[i] = _spline.curvature_at(distance, 6.0)
	for i in _count:
		var strength: float = sqrt(clampf(absf(_curvature[i]) / CURVE_FULL,
			0.0, 1.0))
		# A positive curvature turns left, so the inside is the negative `right`
		# side. Strength keeps the line on the centreline through gentle bends.
		var inside: float = -signf(_curvature[i]) if strength > 0.02 else 0.0
		_inside[i] = inside * _usable * INSIDE_SHARE * strength
	_lines.clear()
	for style in LINE_COUNT:
		_lines.append(_smooth_offsets(_raw_line(style)))
	_offsets = _lines[LINE_APEX]
	_active_line = _offsets
	_build_speed_profile(0.8)


func _raw_line(style: int) -> PackedFloat32Array:
	## Build one unsmoothed lateral-offset curve from the shared inside profile.
	var line := PackedFloat32Array()
	line.resize(_count)
	var late_shift: int = maxi(int(round(LATE_APEX_SHIFT / _step)), 1)
	for i in _count:
		var value: float = _inside[i]
		match style:
			LINE_SWEEP:
				# Second difference of the inside profile: negative at the apex,
				# positive on entry and exit, so the line bows wide both sides.
				value = _inside[i] * 0.70 + _curve_second(i) * SWEEP_CURVE_GAIN
			LINE_LATE:
				value = _inside[(i - late_shift + _count) % _count]
			LINE_DEFEND:
				value = _inside[i] * DEFEND_SHARE
		line[i] = clampf(value, -_usable, _usable)
	return line


func _curve_second(index: int) -> float:
	## Wrap-around second difference of the inside offsets at one sample.
	var previous: float = _inside[(index - 1 + _count) % _count]
	var next: float = _inside[(index + 1) % _count]
	return previous - 2.0 * _inside[index] + next


func _smooth_offsets(source: PackedFloat32Array) -> PackedFloat32Array:
	## Wrap-around [0.25, 0.5, 0.25] smoothing, repeated for a continuous line.
	var current: PackedFloat32Array = source
	for _pass in LINE_SMOOTH_PASSES:
		var smoothed := PackedFloat32Array()
		smoothed.resize(_count)
		for i in _count:
			var previous: int = (i - 1 + _count) % _count
			var next: int = (i + 1) % _count
			smoothed[i] = current[previous] * 0.25 + current[i] * 0.5 \
				+ current[next] * 0.25
		current = smoothed
	return current


func _build_speed_profile(margin: float) -> void:
	## v = sqrt((lat_accel * grip) / curvature) per sample, capped by the cart
	## and skill, then a backward pass so each sample is slow enough to brake for
	## the next (including wet tarmac and glacier ice grip sectors).
	if _count <= 0:
		return
	_speeds.resize(_count)
	var total: float = maxf(_length, 0.001)
	var has_preset: bool = not _preset.is_empty()
	for i in _count:
		var curvature: float = absf(_curvature[i])
		var fraction: float = (float(i) * _step) / total
		var grip: float = clampf(TrackDefs.grip_at(_preset, fraction), 0.35, 1.2) \
			if has_preset else 1.0
		var corner_speed: float = _speed_cap
		if curvature > 0.0005:
			corner_speed = sqrt((_lat_accel * grip) / curvature)
		_speeds[i] = maxf(minf(corner_speed, _speed_cap) * margin,
			MIN_CORNER_SPEED)
	# Two passes settle the wrap-around at the start/finish seam.
	for _repetition in 2:
		for i in range(_count - 1, -1, -1):
			var next: int = (i + 1) % _count
			var fraction: float = (float(i) * _step) / total
			var grip: float = clampf(TrackDefs.grip_at(_preset, fraction), 0.35, 1.2) \
				if has_preset else 1.0
			var decel: float = _brake_decel * lerpf(1.0, grip, 0.55)
			var allowed: float = sqrt(_speeds[next] * _speeds[next]
				+ 2.0 * decel * _step)
			_speeds[i] = minf(_speeds[i], allowed)


func _speed_at(distance: float) -> float:
	## Curvature-limited speed at an arc length, linearly interpolated.
	if _count <= 0 or _speeds.size() != _count:
		return 0.0
	var raw: float = fposmod(distance, _length) / _step
	var index: int = int(raw)
	if index >= _count:
		index = 0
	return lerpf(_speeds[index], _speeds[(index + 1) % _count], raw - float(index))


func _curvature_at(distance: float) -> float:
	## Signed curvature at an arc length, linearly interpolated.
	if _count <= 0:
		return 0.0
	var raw: float = fposmod(distance, _length) / _step
	var index: int = int(raw)
	if index >= _count:
		index = 0
	return lerpf(_curvature[index], _curvature[(index + 1) % _count],
		raw - float(index))


func _line_at(distance: float, line: PackedFloat32Array) -> float:
	## Lateral offset of one racing line at an arc length, interpolated.
	if _count <= 0 or line.size() != _count:
		return 0.0
	var raw: float = fposmod(distance, _length) / _step
	var index: int = int(raw)
	if index >= _count:
		index = 0
	return lerpf(line[index], line[(index + 1) % _count], raw - float(index))


func _randf01() -> float:
	## Deterministic 0..1 draw from the personality LCG. No engine RNG state is
	## touched, so a seeded field replays exactly.
	_rng_state = (_rng_state * 1103515245 + 12345) & 0x7FFFFFFF
	return float(_rng_state) / float(0x7FFFFFFF)


func _rand_range(low: float, high: float) -> float:
	return low + (high - low) * _randf01()


func _avoidance(node: CartPlayer, forward: Vector3, right: Vector3,
		others: Array[CartPlayer], line_offset: float, speed: float) -> float:
	## Lateral bias away from anything close ahead, plus the scan the dynamic
	## line uses: nearest slower cart ahead and any faster cart alongside. The
	## caller clamps the final line offset to the usable width, so this can never
	## steer past the edge.
	_avoid_speed_cap = INF
	_scan_slow_ahead = false
	_scan_side = 0.0
	_scan_gap = INF
	_scan_speed = 0.0
	_scan_faster_side = 0.0
	var origin: Vector3 = node.global_position
	var bias: float = 0.0
	for other: CartPlayer in others:
		if other == null or other == node or not is_instance_valid(other):
			continue
		var offset: Vector3 = other.global_position - origin
		offset.y = 0.0
		var ahead: float = offset.dot(forward)
		if ahead < -2.5 or ahead > CART_AVOID_RANGE + 1.5:
			continue
		var side: float = offset.dot(right)
		var other_speed: float = maxf(
			other.get_collision_velocity().dot(forward), 0.0)
		if ahead > 0.3 and ahead < CART_AVOID_RANGE + 1.5 \
				and absf(side) < 3.0 and other_speed < speed - 0.6 \
				and ahead < _scan_gap:
			_scan_slow_ahead = true
			_scan_side = side
			_scan_gap = ahead
			_scan_speed = other_speed
		if ahead > -2.5 and ahead < 1.5 and absf(side) < 3.2 \
				and other_speed > speed + 1.2:
			_scan_faster_side = side if absf(side) > 0.15 \
				else (1.0 if line_offset <= 0.0 else -1.0)
		if ahead <= 0.0 or ahead > CART_AVOID_RANGE:
			continue
		if absf(side) > CART_AVOID_HALF_WIDTH:
			continue
		var push: float = -1.0 if side >= 0.0 else 1.0
		if absf(side) < 0.25:
			# Dead ahead: take the roomier side of the current racing line.
			push = -1.0 if line_offset >= 0.0 else 1.0
		bias += push * (CART_AVOID_HALF_WIDTH - absf(side) + 0.4)
		if ahead < 5.0:
			_avoid_speed_cap = minf(_avoid_speed_cap,
				other_speed + maxf(ahead - 1.8, 0.0) * 0.7)
	for i in _obstacles.size():
		var offset: Vector3 = _obstacles[i] - origin
		offset.y = 0.0
		var ahead: float = offset.dot(forward)
		if ahead <= 0.0 or ahead > OBSTACLE_AVOID_RANGE:
			continue
		var side: float = offset.dot(right)
		if absf(side) > OBSTACLE_HALF_WIDTH:
			continue
		var push: float = -1.0 if side >= 0.0 else 1.0
		if absf(side) < 0.2:
			push = -1.0 if line_offset >= 0.0 else 1.0
		bias += push * (OBSTACLE_HALF_WIDTH - absf(side) + 0.3)
	return clampf(bias, -AVOID_MAX_BIAS, AVOID_MAX_BIAS)


func _behind_clear(node: CartPlayer, forward: Vector3, right: Vector3,
		others: Array[CartPlayer]) -> bool:
	## True when reversing a couple of metres cannot back into another cart or a
	## trackside body. A blocked reverse is skipped; the owner's hard reset then
	## still has a chance to recover the kart.
	var origin: Vector3 = node.global_position
	for other: CartPlayer in others:
		if other == null or other == node or not is_instance_valid(other):
			continue
		var offset: Vector3 = other.global_position - origin
		offset.y = 0.0
		var behind: float = offset.dot(forward)
		if behind > 0.5 or behind < -REVERSE_CLEARANCE:
			continue
		if absf(offset.dot(right)) < 2.2:
			return false
	for i in _obstacles.size():
		var offset: Vector3 = _obstacles[i] - origin
		offset.y = 0.0
		var behind: float = offset.dot(forward)
		if behind >= 0.0 or behind < -REVERSE_CLEARANCE:
			continue
		if absf(offset.dot(right)) < 1.6:
			return false
	return true
