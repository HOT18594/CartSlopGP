extends RefCounted
## Closed Catmull-Rom centreline for the Meadow Loop race track.
##
## The loop is generated from a radial "wobbly ellipse" so it always winds but
## can never self-intersect. Everything downstream (road ribbon, barriers,
## checkpoints, rivals, scenery rejection) samples this one spline.

const CONTROL_POINTS: int = 24
const SAMPLES_PER_SEGMENT: int = 20
const BASE_RADIUS: float = 64.0
const LOBE_A: float = 0.24
const LOBE_B: float = 0.045
const LOBE_C: float = 0.022
const LOBE_D: float = 0.09
const STRETCH_X: float = 1.25
const STRETCH_Z: float = 1.05

var points: PackedVector3Array = PackedVector3Array()
var cumulative: PackedFloat32Array = PackedFloat32Array() ## Arc length up to point i.
var total_length: float = 0.0
var _count: int = 0


func _init() -> void:
	var controls: Array[Vector3] = []
	for i in CONTROL_POINTS:
		var angle: float = TAU * float(i) / float(CONTROL_POINTS)
		var radius: float = BASE_RADIUS * (1.0
			+ LOBE_A * sin(3.0 * angle + 0.4)
			+ LOBE_B * cos(5.0 * angle - 0.3)
			+ LOBE_C * sin(6.0 * angle + 1.1)
			+ LOBE_D * sin(2.0 * angle + 0.9))
		controls.append(Vector3(
			radius * cos(angle) * STRETCH_X, 0.0,
			radius * sin(angle) * STRETCH_Z))

	for i in CONTROL_POINTS:
		var p0: Vector3 = controls[(i - 1 + CONTROL_POINTS) % CONTROL_POINTS]
		var p1: Vector3 = controls[i]
		var p2: Vector3 = controls[(i + 1) % CONTROL_POINTS]
		var p3: Vector3 = controls[(i + 2) % CONTROL_POINTS]
		for j in SAMPLES_PER_SEGMENT:
			var t: float = float(j) / float(SAMPLES_PER_SEGMENT)
			points.append(_catmull_rom(p0, p1, p2, p3, t))

	_count = points.size()
	cumulative.resize(_count)
	var travelled: float = 0.0
	for i in _count:
		cumulative[i] = travelled
		travelled += points[i].distance_to(points[(i + 1) % _count])
	total_length = travelled


func _catmull_rom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * ((2.0 * p1)
		+ (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


func wrap_distance(distance: float) -> float:
	return fposmod(distance, total_length)


## Returns {position, forward, right} at arc length `distance`.
func sample(distance: float) -> Dictionary:
	var s: float = wrap_distance(distance)
	var index: int = _segment_at(s)
	var next: int = (index + 1) % _count
	var seg_start: float = cumulative[index]
	var seg_length: float = (cumulative[next] if next > 0 else total_length) - seg_start
	if next == 0:
		seg_length = total_length - seg_start
	var t: float = clampf((s - seg_start) / maxf(seg_length, 0.0001), 0.0, 1.0)
	var a: Vector3 = points[index]
	var b: Vector3 = points[next]
	var forward: Vector3 = (b - a).normalized()
	return {
		"position": a.lerp(b, t),
		"forward": forward,
		"right": forward.cross(Vector3.UP).normalized(),
	}


func _segment_at(s: float) -> int:
	# Binary search over the cumulative arc-length table.
	var low: int = 0
	var high: int = _count - 1
	while low < high:
		var mid: int = (low + high + 1) / 2
		if cumulative[mid] <= s:
			low = mid
		else:
			high = mid - 1
	return low


## Nearest point on the polyline. Returns {s, distance, point}.
var _last_index: int = 0


func closest(world_position: Vector3) -> Dictionary:
	## Local search first: the kart moves less than a metre per frame, so
	## scanning the whole 480-segment loop every frame was wasted work. If the
	## nearest point is far away (respawn, teleport, first call), fall back to
	## the full scan so lap logic can never get stuck in the wrong sector.
	var window: int = 24
	var result: Dictionary
	# The local window cannot wrap across the start/finish seam. Near either
	# end of the loop, scan the whole spline; otherwise a lap boundary can be
	# missed and the race never counts the final lap.
	if _last_index < window or _last_index > _count - 1 - window:
		result = _scan(world_position, 0, _count - 1)
	else:
		result = _scan(world_position, _last_index - window, _last_index + window)
		if float(result["distance"]) > 25.0:
			result = _scan(world_position, 0, _count - 1)
	_last_index = int(result["index"])
	return {"s": result["s"], "distance": result["distance"], "point": result["point"]}


func _scan(world_position: Vector3, start: int, end: int) -> Dictionary:
	var best_sq: float = INF
	var best_s: float = 0.0
	var best_point: Vector3 = Vector3.ZERO
	var best_index: int = start
	for i in range(start, end + 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[(i + 1) % _count]
		var ab: Vector3 = b - a
		var length_sq: float = ab.length_squared()
		var t: float = 0.0
		if length_sq > 0.000001:
			t = clampf((world_position - a).dot(ab) / length_sq, 0.0, 1.0)
		var candidate: Vector3 = a + ab * t
		var d_sq: float = world_position.distance_squared_to(candidate)
		if d_sq < best_sq:
			best_sq = d_sq
			best_point = candidate
			best_index = i
			var seg_length: float = sqrt(length_sq)
			best_s = wrap_distance(cumulative[i] + seg_length * t)
	return {"s": best_s, "distance": sqrt(best_sq), "point": best_point,
		"index": best_index}


func yaw_at(distance: float) -> float:
	var f: Vector3 = sample(distance)["forward"]
	return atan2(-f.x, -f.z)


## Signed turning rate (radians per metre) near `distance`. Positive means the
## track bends one way, negative the other; near zero is a straight. Bots use
## this to brake before corners and obstacles use it to find straights.
func curvature_at(distance: float, window: float = 6.0) -> float:
	var yaw_a: float = yaw_at(distance - window)
	var yaw_b: float = yaw_at(distance + window)
	var delta: float = wrapf(yaw_b - yaw_a, -PI, PI)
	return delta / (window * 2.0)
