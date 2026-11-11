class_name CartCollision
extends RefCounted
## Shared car-to-car and wall contact solver for the arcade driving model.
##
## The rule is simple: a contact may redirect a cart, but it must never erase
## its speed. Both helpers are static so the local controller, the AI and the
## host-side network resolver can share the exact same maths without adding
## another node to the scene tree.

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
## If an impulse would leave a previously moving cart parked, add a tiny
## equal/opposite separation impulse so the hit never reads as a dead stop.
const MIN_KEEP_SPEED: float = 0.35


static func resolve_pair(a: Node3D, b: Node3D, contact_point: Vector3,
		normal: Vector3, penetration: float, separate: bool = true) -> float:
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
	if separate and depth > 0.0:
		a.global_position -= n * (depth * inv_a / inv_sum)
		b.global_position += n * (depth * inv_b / inv_sum)
	var velocity_a: Vector3 = _body_velocity(a)
	var velocity_b: Vector3 = _body_velocity(b)
	var closing: float = (velocity_a - velocity_b).dot(n)
	if not is_finite(closing) or closing <= MIN_CLOSING_SPEED:
		return 0.0
	var impulse: float = (1.0 + RESTITUTION) * closing / inv_sum
	if not is_finite(impulse) or impulse <= 0.0:
		return 0.0
	var post_a: Vector3 = velocity_a - n * (impulse * inv_a)
	var post_b: Vector3 = velocity_b + n * (impulse * inv_b)
	# An unlucky mass ratio can leave the lighter cart with exactly zero speed.
	# That still conserves momentum, but it reads as a dead stop. Add a small
	# equal/opposite impulse along the normal so the pair separates and a
	# formerly moving cart keeps moving. Normal contacts never trigger this.
	var nudge_impulse: float = 0.0
	if closing > 1.0:
		if post_a.length() < MIN_KEEP_SPEED and velocity_a.length() > 1.0:
			nudge_impulse = maxf(nudge_impulse,
				(MIN_KEEP_SPEED + post_a.dot(n)) * mass_a)
		if post_b.length() < MIN_KEEP_SPEED and velocity_b.length() > 1.0:
			nudge_impulse = maxf(nudge_impulse,
				(MIN_KEEP_SPEED - post_b.dot(n)) * mass_b)
	impulse += maxf(nudge_impulse, 0.0)
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
	## CharacterBody or RigidBody exposes it directly.
	var remote_mode: Variant = body.get("remote_mode")
	if remote_mode is bool and bool(remote_mode) \
			and body.has_method("get_collision_velocity"):
		var net_velocity: Variant = body.call("get_collision_velocity")
		if net_velocity is Vector3 and (net_velocity as Vector3).is_finite():
			return net_velocity as Vector3
	var velocity: Variant = body.get("velocity")
	if velocity is Vector3:
		var body_velocity: Vector3 = velocity as Vector3
		return body_velocity if body_velocity.is_finite() else Vector3.ZERO
	var linear_velocity: Variant = body.get("linear_velocity")
	if linear_velocity is Vector3:
		var body_linear: Vector3 = linear_velocity as Vector3
		return body_linear if body_linear.is_finite() else Vector3.ZERO
	return Vector3.ZERO


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
	if body is RigidBody3D:
		# Applying at the contact point adds a physical spin; the linear part is
		# still exactly impulse / mass. Wake a sleeping prop so a parked crate
		# still reacts to a moving cart.
		var rigid: RigidBody3D = body as RigidBody3D
		if rigid.sleeping:
			rigid.sleeping = false
		rigid.apply_impulse(impulse, contact_point - rigid.global_position)
		return
	_set_body_velocity(body, _body_velocity(body) + impulse / _body_mass(body))
