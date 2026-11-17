class_name CartCollision
extends RefCounted
## Shared car-to-car and wall contact solver for the arcade driving model.
##
## The rule is simple: a contact may redirect a cart, but it must never erase
## its speed. Both helpers are static so the local controller, the AI and the
## host-side network resolver can share the exact same maths without adding
## another node to the scene tree.
##
## Ownership rule for multiplayer (kept here so every caller sees it):
## - car-vs-car momentum is host-authoritative in a session; this solver is the
##   single impulse implementation the host and every client use, so both sides
##   agree on the exchange and the receiver only adds the host's delta-v once;
## - solid props are static obstacles on every peer (a client freezes its prop
##   bodies at the host's pose), so cart-vs-prop contact is resolved by each
##   peer's own physics against the same shape. Only a pushed prop's motion is
##   host-authoritative and it never travels through this solver.

## Mass used when a body does not expose get_mass(). Matches the cart reference.
const DEFAULT_MASS: float = 1200.0
## Bounciness of a car-to-car impulse. Low enough to feel weighty, high enough
## that a rear-end shove always separates the pair.
const RESTITUTION: float = 0.35
## Bounciness of a wall or solid-prop hit. Walls keep the slide and only give a
## small push back instead of stopping the kart dead.
const WALL_RESTITUTION: float = 0.30
const MIN_NORMAL_LENGTH_SQ: float = 0.0001
const MIN_CLOSING_SPEED: float = 0.001
## A contact speed above this is corruption, not driving: no cart in the game
## can move faster than a boost cap of ~26 m/s plus a fall. Reading a bad body
## velocity (NaN, 1e30) into the impulse maths would turn one contact into a
## teleport, so both the read and the written result are bounded here.
const MAX_BODY_SPEED: float = 64.0
## Positional correction is only applied when the caller owns separation.
## Keep a corrupt penetration from teleporting a body across the map.
const MAX_SEPARATION_DEPTH: float = 2.5


static func resolve_pair(a: Node3D, b: Node3D, contact_point: Vector3,
		normal: Vector3, penetration: float, separate: bool = true,
		closing_override: float = -1.0) -> float:
	## Resolve one car-to-car contact for the pair.
	##
	## `normal` points from `a` toward `b` and `penetration` is the overlap
	## depth. Both bodies receive an equal and opposite elastic impulse, so the
	## pair conserves momentum. Positional correction is split by inverse mass:
	## a light kart yields most of the overlap while a heavy truck barely moves.
	## No velocity is ever zeroed; the impulse only redirects it.
	## `separate` is false when the physics engine already owns positional
	## separation this tick (the normal case: move_and_slide has just resolved
	## the same pair). Only one owner may move positions, or the pair visibly
	## double-separates and jitters.
	## Returns the scalar impulse magnitude that was applied to each body (0
	## when the contact was ignored), so a network caller can send exactly the
	## same delta-v it applied locally instead of inferring it from velocities.
	##
	## `closing_override` lets a caller that owns the contact feed in the
	## approach speed it measured BEFORE its own move_and_slide ran. A
	## CharacterBody pair has already been separated by the engine by the time
	## the slide collisions are read, so the live velocities say "not
	## approaching" and the exchange would silently vanish on a head-on hit.
	## Pass a value <= 0 to measure from the live velocities instead.
	if a == null or b == null or a == b:
		return 0.0
	var normal_length_sq: float = normal.length_squared()
	if not normal.is_finite() or normal_length_sq < MIN_NORMAL_LENGTH_SQ:
		return 0.0
	var n: Vector3 = normal / sqrt(normal_length_sq)
	if not contact_point.is_finite():
		contact_point = (a.global_position + b.global_position) * 0.5
	var mass_a: float = _body_mass(a)
	var mass_b: float = _body_mass(b)
	var inv_a: float = 1.0 / mass_a
	var inv_b: float = 1.0 / mass_b
	var inv_sum: float = inv_a + inv_b
	if not is_finite(inv_sum) or inv_sum <= 0.0:
		return 0.0
	var depth: float = penetration if is_finite(penetration) else 0.0
	depth = clampf(depth, 0.0, MAX_SEPARATION_DEPTH)
	if separate and depth > 0.0:
		a.global_position -= n * (depth * inv_a / inv_sum)
		b.global_position += n * (depth * inv_b / inv_sum)
	var velocity_a: Vector3 = _body_velocity(a)
	var velocity_b: Vector3 = _body_velocity(b)
	var closing: float = (velocity_a - velocity_b).dot(n)
	if is_finite(closing_override) and closing_override > MIN_CLOSING_SPEED:
		# Trust the caller's pre-move measurement over the engine-separated
		# velocities, but never past the corruption ceiling.
		closing = minf(closing_override, MAX_BODY_SPEED)
	if not is_finite(closing) or closing <= MIN_CLOSING_SPEED:
		return 0.0
	# Standard restitution impulse along the contact normal. The pair leaves
	# the contact at RESTITUTION * closing, so a hit separates without any
	# extra shove. A light cart can only ever put
	# (1 + RESTITUTION) * closing * m_light / (m_light + m_heavy) into a heavy
	# one, which is the mass-ratio bound. Do not add a "keep moving" nudge on
	# top of this: an extra equal/opposite impulse is not bounded by
	# restitution, and it can reverse a cart that the main exchange only
	# slowed (the harness now asserts the exact bound and zero momentum error).
	var impulse: float = (1.0 + RESTITUTION) * closing / inv_sum
	if not is_finite(impulse) or impulse <= 0.0:
		return 0.0
	_apply_impulse(a, -n * impulse, contact_point)
	_apply_impulse(b, n * impulse, contact_point)
	return impulse


static func soften_wall_hit(body: Node3D, normal: Vector3,
		impact_speed: float) -> Vector3:
	## Return the velocity a cart should carry after clipping a wall or prop.
	##
	## Tangential speed is preserved and the normal component is reflected at
	## `WALL_RESTITUTION` (0.30). `impact_speed` covers the usual case where
	## move_and_slide already removed the inward component before this runs, so
	## a head-on hit bounces gently instead of reading as a dead stop.
	if body == null:
		return Vector3.ZERO
	var velocity: Vector3 = _body_velocity(body)
	if not velocity.is_finite():
		return Vector3.ZERO
	var normal_length_sq: float = normal.length_squared()
	if not normal.is_finite() or normal_length_sq < MIN_NORMAL_LENGTH_SQ:
		return velocity
	var n: Vector3 = normal / sqrt(normal_length_sq)
	var normal_speed: float = velocity.dot(n)
	if normal_speed > 0.01:
		return velocity
	var tangent: Vector3 = velocity - n * normal_speed
	var measured: float = impact_speed if is_finite(impact_speed) else 0.0
	var approach: float = maxf(-normal_speed, measured)
	if approach <= 0.0:
		return velocity
	var result: Vector3 = tangent + n * (approach * WALL_RESTITUTION)
	# A contact normal that points downward (the underside of a crate, an
	# overhang) must not turn a wall scrape into a downward launch. Terrain is
	# a heightfield with no thickness, so gaining downward speed from a side
	# contact can punch the kart through it before the next sweep resolves.
	# Keep the incoming vertical speed as a floor; never add downward motion.
	result.y = maxf(result.y, velocity.y)
	return result if result.is_finite() else velocity


static func _body_mass(body: Node3D) -> float:
	## Prefer the vehicle's catalog mass. A rigid prop exposes its real mass
	## directly; plain nodes fall back to a reference car so the pair is never
	## divided by zero.
	if body.has_method("get_mass"):
		var mass_value: Variant = body.call("get_mass")
		if mass_value is float or mass_value is int:
			var mass: float = float(mass_value)
			if is_finite(mass) and mass > 0.0:
				return mass
	if body is RigidBody3D:
		var rigid_mass: float = (body as RigidBody3D).mass
		if is_finite(rigid_mass) and rigid_mass > 0.0:
			return rigid_mass
	return DEFAULT_MASS


static func _body_velocity(body: Node3D) -> Vector3:
	## Remote ghosts keep their authoritative motion in net_velocity; a local
	## CharacterBody or RigidBody exposes it directly. Every read is bounded, so
	## a single corrupt body velocity can never decide an absurd impulse.
	var remote_mode: Variant = body.get("remote_mode")
	if remote_mode is bool and bool(remote_mode) \
			and body.has_method("get_collision_velocity"):
		var net_velocity: Variant = body.call("get_collision_velocity")
		if net_velocity is Vector3:
			return _bounded_velocity(net_velocity as Vector3)
	var velocity: Variant = body.get("velocity")
	if velocity is Vector3:
		return _bounded_velocity(velocity as Vector3)
	var linear_velocity: Variant = body.get("linear_velocity")
	if linear_velocity is Vector3:
		return _bounded_velocity(linear_velocity as Vector3)
	return Vector3.ZERO


static func _bounded_velocity(value: Vector3) -> Vector3:
	if not value.is_finite():
		return Vector3.ZERO
	return value.limit_length(MAX_BODY_SPEED)


static func _set_body_velocity(body: Node3D, value: Vector3) -> void:
	if not value.is_finite():
		return
	var velocity: Variant = body.get("velocity")
	if velocity is Vector3:
		body.set("velocity", value)
		return
	var linear_velocity: Variant = body.get("linear_velocity")
	if linear_velocity is Vector3:
		body.set("linear_velocity", value)


static func _apply_impulse(body: Node3D, impulse: Vector3,
		contact_point: Vector3) -> void:
	if not impulse.is_finite() or impulse.length_squared() < 0.000001:
		return
	var mass: float = _body_mass(body)
	if not is_finite(mass) or mass <= 0.0:
		return
	var delta: Vector3 = impulse / mass
	if not delta.is_finite():
		return
	if body is RigidBody3D:
		# Applying at the contact point adds a physical spin; the linear part is
		# still exactly impulse / mass. Wake a sleeping prop so a parked crate
		# still reacts to a moving cart.
		var rigid: RigidBody3D = body as RigidBody3D
		if rigid.sleeping:
			rigid.sleeping = false
		rigid.apply_impulse(impulse, contact_point - rigid.global_position)
		var rigid_velocity: Vector3 = rigid.linear_velocity
		if rigid_velocity.is_finite() and rigid_velocity.length_squared() \
				> MAX_BODY_SPEED * MAX_BODY_SPEED:
			rigid.linear_velocity = rigid_velocity.limit_length(MAX_BODY_SPEED)
		return
	var next_velocity: Vector3 = _body_velocity(body) + delta
	if not next_velocity.is_finite():
		return
	_set_body_velocity(body, next_velocity.limit_length(MAX_BODY_SPEED))
