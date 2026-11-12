extends RefCounted
## Route analysis shared by every part of the circuit theme.
##
## MEADOW LOOP is a wobbly ellipse: there is no true straight line anywhere on
## it, so hunting for tangent runs only finds a handful of four-metre pockets.
## The theme therefore treats a corner as a local apex of heading change and a
## "straight" as the window with the least total heading change over 44 m.
##
## Kerbs, distance boards, tyre walls, armco, grandstands, the pit complex and
## the floodlights all read this one plan, so they never disagree about where
## turn 4 is, which side is its outside, or which sections count as the
## straights a grandstand may stand on.
##
## Distances are arc length in metres. A corner's `from`/`to` are wrapped into
## 0..total_length but keep a positive spacing, which is exactly what
## RacingKit.kerbs() and RacingKit.barriers() expect.

## Arc-length spacing of the analysis samples, in metres.
const STEP: float = 2.0
## Heading change is measured across `WINDOW` metres either side of a sample.
const WINDOW: float = 6.0
## Minimum turn (radians over 2 * WINDOW metres) for a sample to seed a corner.
const CORNER_TURN: float = 0.22
## Two apexes closer than this are one corner, so their kerbs never overlap.
const CORNER_SPACING: float = 38.0
## A kerb run reaches this far either side of its apex.
const KERB_REACH: float = 14.0
## Length of the window used to score straights.
const STRAIGHT_LENGTH: float = 44.0
## Candidate straights must be at least this far apart, in metres of arc.
const STRAIGHT_GAP: float = 74.0
## How many straights the theme dresses.
const STRAIGHT_COUNT: int = 3


## Everything the theme needs: the lap length, the corners in lap order and the
## straights in arc order (each carries the `rank` of how flat it is, best 0).
static func analyse(spline: RefCounted) -> Dictionary:
	var total: float = maxf(spline.total_length, 1.0)
	var count: int = maxi(int(ceil(total / STEP)), 1)
	var turn: PackedFloat32Array = PackedFloat32Array()
	turn.resize(count)
	for i in count:
		turn[i] = _turn(spline, float(i) * STEP)
	var corners: Array[Dictionary] = _corners(turn, total)
	var straights: Array[Dictionary] = _straights(turn, corners, total)
	return {"total": total, "corners": corners, "straights": straights}


## Signed heading change across the analysis window. Positive is a left-hand
## bend and negative a right-hand bend, matching RacingKit's outside-side rule.
static func _turn(spline: RefCounted, distance: float) -> float:
	return angle_difference(spline.yaw_at(distance - WINDOW),
		spline.yaw_at(distance + WINDOW))


## True when the road bends left at `distance`, which puts the outside of the
## corner on the right. Used to match the placement RacingKit picks itself.
static func bend_side(spline: RefCounted, distance: float) -> float:
	return 1.0 if _turn(spline, distance) >= 0.0 else -1.0


static func _corners(turn: PackedFloat32Array, total: float) -> Array[Dictionary]:
	# Seed every sample that is already turning hard, then take the sharpest
	# apexes first. Greedy selection with a minimum spacing turns the long
	# swerve of this loop into distinct numbered corners instead of one
	# 200-metre "corner" that would paint kerbs along half the lap.
	var candidates: Array[Dictionary] = []
	for i in turn.size():
		if absf(turn[i]) < CORNER_TURN:
			continue
		candidates.append({"distance": float(i) * STEP, "turn": turn[i]})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return absf(float(a["turn"])) > absf(float(b["turn"])))
	var chosen: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		var clear: bool = true
		for other: Dictionary in chosen:
			if arc_gap(float(candidate["distance"]), float(other["distance"]),
					total) < CORNER_SPACING:
				clear = false
				break
		if clear:
			chosen.append(candidate)
	chosen.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["distance"]) < float(b["distance"]))
	var corners: Array[Dictionary] = []
	for i in chosen.size():
		var distance: float = float(chosen[i]["distance"])
		var turn_value: float = float(chosen[i]["turn"])
		var reach: float = minf(KERB_REACH, CORNER_SPACING * 0.5 - 2.0)
		corners.append({
			"index": i + 1,
			"distance": distance,
			"from": fposmod(distance - reach, total),
			"to": fposmod(distance + reach, total),
			"turn": turn_value,
			"outside": 1.0 if turn_value > 0.0 else -1.0,
			"radius": (WINDOW * 2.0) / maxf(absf(turn_value), 0.0001),
		})
	return corners


static func _straights(turn: PackedFloat32Array, corners: Array[Dictionary],
		total: float) -> Array[Dictionary]:
	# Total heading change over a fixed window: the lowest score is the
	# straightest stretch of the lap. Because this map never runs dead straight,
	# "longest straight" really means "least bendy sweep", which is still where
	# a grandstand reads as a grandstand rather than a set of stairs on a bend.
	var half: int = maxi(int(round(STRAIGHT_LENGTH / STEP)), 1) / 2
	var candidates: Array[Dictionary] = []
	for i in turn.size():
		var score: float = 0.0
		for offset in range(-half, half + 1):
			score += absf(turn[posmod(i + offset, turn.size())])
		candidates.append({"distance": float(i) * STEP, "score": score})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) < float(b["score"]))
	var chosen: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		var distance: float = float(candidate["distance"])
		var clear: bool = true
		for other: Dictionary in chosen:
			if arc_gap(distance, float(other["distance"]), total) < STRAIGHT_GAP:
				clear = false
				break
		if not clear:
			continue
		for corner: Dictionary in corners:
			# A stand needs a clean run, not a kerb under its front row.
			if arc_gap(distance, float(corner["distance"]), total) < 12.0:
				clear = false
				break
		if not clear:
			continue
		chosen.append({"distance": distance, "score": float(candidate["score"]),
			"rank": chosen.size()})
		if chosen.size() >= STRAIGHT_COUNT:
			break
	chosen.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["distance"]) < float(b["distance"]))
	return chosen


## Shortest distance between two arc-length positions, honouring the wrap.
static func arc_gap(a: float, b: float, total: float) -> float:
	var safe_total: float = maxf(total, 0.001)
	return absf(fposmod(a - b + safe_total * 0.5, safe_total) - safe_total * 0.5)


## World position `lateral` metres to the right of the centreline.
static func at(spline: RefCounted, distance: float, lateral: float,
		height: float = 0.0) -> Vector3:
	var frame: Dictionary = spline.sample(distance)
	return ((frame["position"] as Vector3)
		+ (frame["right"] as Vector3) * lateral + Vector3.UP * height)


## Track-aligned transform: local -Z runs along the track, +X to the right.
static func transform_at(spline: RefCounted, distance: float, lateral: float,
		height: float = 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, spline.yaw_at(distance)),
		at(spline, distance, lateral, height))


## True when no part of the loop is within `radius` of `point`. Points placed
## more than `radius` out from their own centreline can use this directly.
static func clearance(spline: RefCounted, point: Vector3, radius: float) -> bool:
	var radius_sq: float = radius * radius
	var points: PackedVector3Array = spline.points
	for i in points.size():
		if point.distance_squared_to(points[i]) < radius_sq:
			return false
	return true


## True when a prop `half_length` long along the track and `radius` deep can
## stand at `lateral` without another part of the loop passing through it.
static func spot_ok(spline: RefCounted, distance: float, lateral: float,
		half_length: float, radius: float) -> bool:
	for step in 5:
		var offset: float = -half_length + 2.0 * half_length * float(step) / 4.0
		var point: Vector3 = at(spline, distance + offset, lateral)
		if not clearance(spline, point, radius):
			return false
	return true
