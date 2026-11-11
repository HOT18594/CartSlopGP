extends RefCounted
## Route math shared by the trackside builders.
##
## Wraps the race spline so every prop can be placed by arc length and lateral
## offset, finds the corners and straights worth dressing, and rejects spots
## where another part of the loop, a landmark clearing or the racing surface is
## in the way.

const MeadowLandmarks := preload("res://scripts/minigames/meadow_landmarks.gd")

## Track half width. Mirrors grass_race.ROAD_HALF so nothing lands on the road.
const ROAD_HALF: float = 5.5
## Barrier bodies sit ROAD_HALF + 0.5 m out; props outside this can never be hit.
const BARRIER_OFFSET: float = 0.5


## World position `lateral` metres right of the centreline at arc length `s`.
static func at(spline: RefCounted, distance: float, lateral: float,
		height: float = 0.0) -> Vector3:
	var sample: Dictionary = spline.sample(distance)
	return sample["position"] + (sample["right"] as Vector3) * lateral \
		+ Vector3.UP * height


## Transform whose local -Z runs along the track, for boards faced by traffic.
static func transform_at(spline: RefCounted, distance: float, lateral: float,
		height: float = 0.0) -> Transform3D:
	var sample: Dictionary = spline.sample(distance)
	var point: Vector3 = sample["position"] + (sample["right"] as Vector3) * lateral \
		+ Vector3.UP * height
	return Transform3D(Basis(Vector3.UP, spline.yaw_at(distance)), point)


## Yaw that turns a prop's local -Z towards the track from `lateral` metres out.
## Local +X ends up running along the track, so wide props stay parallel to it.
static func facing_yaw(spline: RefCounted, distance: float, lateral: float) -> float:
	var base: float = spline.yaw_at(distance)
	return base + (PI * 0.5 if lateral > 0.0 else -PI * 0.5)


## The tightest bends, spaced apart, each tagged with which side is outside.
static func corners(spline: RefCounted, max_count: int,
		min_curve: float = 0.14, spacing: float = 55.0) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var total: float = spline.total_length
	var d: float = 20.0
	while d < total - 20.0:
		var curve: float = angle_difference(spline.yaw_at(d - 7.0),
			spline.yaw_at(d + 7.0))
		if absf(curve) > min_curve:
			candidates.append({"d": d, "curve": curve,
				"outside": 1.0 if curve > 0.0 else -1.0})
		d += 8.0
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return absf(float(a["curve"])) > absf(float(b["curve"])))
	var chosen: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		var ok: bool = true
		for other: Dictionary in chosen:
			if absf(fposmod(float(candidate["d"]) - float(other["d"]), total)) < spacing:
				ok = false
				break
		if ok:
			chosen.append(candidate)
		if chosen.size() >= max_count:
			break
	return chosen


## The flattest sections of the loop, as {d, length} runs of the requested
## length. Meadow Loop is a wobbly ellipse with no true straights, so "straight"
## means the lowest average curvature - which is where fences and hoardings
## read best from the chase camera.
static func straights(spline: RefCounted, max_count: int,
		length: float = 40.0) -> Array[Dictionary]:
	var total: float = spline.total_length
	var candidates: Array[Dictionary] = []
	var d: float = 0.0
	while d < total:
		candidates.append({"d": d, "curve": absf(angle_difference(
			spline.yaw_at(d - 10.0), spline.yaw_at(d + 10.0)))})
		d += 4.0
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["curve"]) < float(b["curve"]))
	var found: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		var ok: bool = true
		for other: Dictionary in found:
			if absf(fposmod(float(candidate["d"]) - float(other["d"]), total)) \
					< length + 12.0:
				ok = false
				break
		if ok:
			found.append({"d": float(candidate["d"]), "length": length})
		if found.size() >= max_count:
			break
	return found


## True when `point` is at least `radius` from every part of the loop except the
## `exclude_span` metres of arc length either side of `exclude_s`.
static func clear_of_track(spline: RefCounted, point: Vector3, radius: float,
		exclude_s: float = 0.0, exclude_span: float = 0.0) -> bool:
	var total: float = spline.total_length
	var radius_sq: float = radius * radius
	var points: PackedVector3Array = spline.points
	var cumulative: PackedFloat32Array = spline.cumulative
	for i in points.size():
		if exclude_span > 0.0:
			var delta: float = absf(fposmod(cumulative[i] - exclude_s + total * 0.5,
				total) - total * 0.5)
			if delta < exclude_span:
				continue
		if point.distance_squared_to(points[i]) < radius_sq:
			return false
	return true


## True when `point` is open ground: away from the loop and off the hand-placed
## landmark clearings.
static func free_ground(spline: RefCounted, point: Vector3, radius: float) -> bool:
	if MeadowLandmarks.is_clearing(spline, point):
		return false
	return clear_of_track(spline, point, radius)


## True when a prop `half_length` along the track and `half_depth` across it can
## stand at `lateral` without touching the road, another piece of the loop or a
## landmark clearing.
static func spot_ok(spline: RefCounted, distance: float, lateral: float,
		half_length: float, half_depth: float,
		margin: float = 0.9) -> bool:
	if absf(lateral) < ROAD_HALF + half_depth + margin:
		return false
	var span: float = half_length + 2.0
	for step in 5:
		var offset: float = -half_length + 2.0 * half_length * float(step) / 4.0
		var point: Vector3 = at(spline, distance + offset, lateral)
		if MeadowLandmarks.is_clearing(spline, point):
			return false
		if not clear_of_track(spline, point, half_depth + 1.5, distance, span):
			return false
	return true
