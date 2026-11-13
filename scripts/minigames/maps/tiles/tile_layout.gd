extends RefCounted
## Places the tile library on the 26 m cell lattice and derives the closed
## centreline every other system samples.
##
## A map is authored as an ordered list of tile entries: `id`, optional
## `mirror`, optional `hooks`/`surface` overrides and the grid `at`/`rot` the
## tile was placed on. The placement itself is chained from the previous tile's
## exit, so a map can never silently open a gap between two tiles; an authored
## `at`/`rot` pair is validated against the chain and reported when it drifts.
##
## The derived tables mirror TrackSpline's public contract - `points`,
## `cumulative`, `total_length`, a closed loop - and add the tile-level data the
## road, kerb, barrier and decoration builders need: per-sample half width,
## per-sample surface kind and the decoration anchors each tile's hooks asked
## for. Surface spans are derived from the tiles, so a wet or ice section can
## never drift away from the tile that actually carries it.

const TileCatalog := preload("res://scripts/minigames/maps/tiles/tile_catalog.gd")

## Decoration anchors every corner tile emits automatically.
const CORNER_TYRE_AT: float = 0.74
const CORNER_MARSHAL_AT: float = 0.16

var tiles: Array[Dictionary] = []
var points: PackedVector3Array = PackedVector3Array()
var cumulative: PackedFloat32Array = PackedFloat32Array()
var total_length: float = 0.0
var bounds: Rect2 = Rect2()
## Per-sample data, parallel to `points`.
var sample_surface: PackedStringArray = PackedStringArray()
var sample_width: PackedFloat32Array = PackedFloat32Array()
var sample_tile: PackedInt32Array = PackedInt32Array()
## Derived lap-fraction spans: {kind, from, to}.
var surfaces: Array[Dictionary] = []
## Decoration hooks in arc order: {kind, distance, side, lateral, length}.
var anchors: Array[Dictionary] = []

var _plan: PackedVector2Array = PackedVector2Array()
var _bump: PackedFloat32Array = PackedFloat32Array()
var _tile_ranges: Array[Vector2i] = []


func _init(preset: Dictionary = {}) -> void:
	var entries: Array = preset.get("tiles", [])
	if entries.is_empty():
		return
	_place(entries)
	_build_points(preset)
	_build_surfaces()
	_build_anchors()


# --------------------------------------------------------------------------
# placement


## Chains every authored entry, deriving its grid cell and rotation.
func _place(entries: Array) -> void:
	var entry := Vector2(TileCatalog.HALF_CELL, 0.0)
	var heading: int = 0
	var entry_local := Vector2(-TileCatalog.HALF_CELL, 0.0)
	for index in entries.size():
		var spec: Dictionary = entries[index] as Dictionary
		var tile_id: String = str(spec.get("id", TileCatalog.TILE_STRAIGHT))
		var base: Dictionary = TileCatalog.get_tile(tile_id)
		var tile: Dictionary = TileCatalog.mirrored(base) \
			if bool(spec.get("mirror", false)) else base.duplicate(true)
		tile["index"] = index
		# A placement may override the decoration hooks or the surface it
		# carries; that is how a map says "this straight is the wet one".
		if spec.has("hooks"):
			tile["hooks"] = PackedStringArray(spec["hooks"] as Array)
		if spec.has("surface"):
			tile["surface"] = str(spec["surface"])
		var origin: Vector2 = entry - TileCatalog.rotated(entry_local, heading)
		var cell := Vector2i(roundi(origin.x / TileCatalog.CELL),
			roundi(origin.y / TileCatalog.CELL))
		# An authored grid coordinate must agree with the chain. When it does
		# not the chain wins, so the layout stays closed; the warning names the
		# tile so a broken authoring edit is easy to find.
		if spec.has("at") or spec.has("rot"):
			var wanted_cell: Vector2i = cell
			var wanted_rot: int = heading
			if spec.has("at"):
				var raw: Variant = spec["at"]
				if raw is Vector2i:
					wanted_cell = raw
				elif raw is Array and (raw as Array).size() >= 2:
					var coords: Array = raw as Array
					wanted_cell = Vector2i(int(coords[0]), int(coords[1]))
			if spec.has("rot"):
				wanted_rot = int(spec["rot"])
			if wanted_cell != cell or posmod(wanted_rot, 4) != heading:
				push_warning("TileLayout: tile %d (%s) authored at %s/%d but the chain places it at %s/%d" % [
					index, tile_id, wanted_cell, posmod(wanted_rot, 4), cell, heading])
		tile["cell"] = cell
		tile["rot"] = heading
		tile["origin"] = origin
		tile["outside"] = 0.0
		tiles.append(tile)
		entry = origin + TileCatalog.rotated(tile["exit"] as Vector2, heading)
		heading = posmod(heading + int(tile["turn"]), 4)


# --------------------------------------------------------------------------
# centreline


## Concatenates the placed tiles into one closed, evenly sampled centreline.
func _build_points(preset: Dictionary) -> void:
	var profile: Array = []
	var raw_profile: Variant = preset.get("elevation", [])
	if raw_profile is Array:
		profile = raw_profile as Array
	var plan := PackedVector2Array()
	var bumps := PackedFloat32Array()
	var owner := PackedInt32Array()
	var widths := PackedFloat32Array()
	var kinds := PackedStringArray()
	var ranges: Array[Vector2i] = []
	for index in tiles.size():
		var tile: Dictionary = tiles[index]
		var origin: Vector2 = tile["origin"]
		var heading: int = int(tile["rot"])
		var path: PackedVector3Array = tile["path"] as PackedVector3Array
		var start_index: int = plan.size()
		var last_tile: bool = index == tiles.size() - 1
		for i in path.size():
			# The first point of every tile after the first repeats the previous
			# tile's exit, and the last tile's exit repeats point 0: dropping
			# both keeps the loop free of zero-length segments.
			if index > 0 and i == 0:
				continue
			if last_tile and i == path.size() - 1:
				continue
			var local := Vector2(path[i].x, path[i].z)
			plan.append(origin + TileCatalog.rotated(local, heading))
			bumps.append(path[i].y)
			owner.append(index)
			var t: float = float(i) / float(maxi(path.size() - 1, 1))
			widths.append(TileCatalog.half_width_at(tile, t))
			kinds.append(str(tile.get("surface", "normal")))
		ranges.append(Vector2i(start_index, plan.size() - 1))
	_tile_ranges = ranges
	var count: int = plan.size()
	if count < 3:
		return
	_plan = plan
	_bump = bumps
	cumulative.resize(count)
	var travelled: float = 0.0
	for i in count:
		cumulative[i] = travelled
		travelled += plan[i].distance_to(plan[(i + 1) % count])
	total_length = travelled
	sample_width = widths
	sample_surface = kinds
	sample_tile = owner
	points.resize(count)
	for i in count:
		var fraction: float = cumulative[i] / maxf(total_length, 0.001)
		points[i] = Vector3(plan[i].x,
			_profile_height(profile, fraction) + bumps[i], plan[i].y)
	for index in tiles.size():
		var tile: Dictionary = tiles[index]
		var range_i: Vector2i = _tile_ranges[index]
		tile["from"] = cumulative[range_i.x] if range_i.x < count else 0.0
		tile["to"] = (cumulative[range_i.y] if range_i.y < count else total_length)
		var span: float = float(tile["to"]) - float(tile["from"])
		if span <= 0.0:
			span += total_length
		tile["span"] = span
		tile["outside"] = _outside_side(float(tile["from"]) + 2.0,
			float(tile["from"]) + maxf(span - 2.0, 2.0))
	# Plan-view bounds, padded by the road so the ground and haze can be sized.
	var min_x: float = INF
	var min_z: float = INF
	var max_x: float = -INF
	var max_z: float = -INF
	for p: Vector2 in plan:
		min_x = minf(min_x, p.x)
		min_z = minf(min_z, p.y)
		max_x = maxf(max_x, p.x)
		max_z = maxf(max_z, p.y)
	bounds = Rect2(Vector2(min_x, min_z), Vector2(max_x - min_x, max_z - min_z))


## Smoothstep-joined periodic elevation profile, in metres.
func _profile_height(profile: Array, fraction: float) -> float:
	if profile.is_empty():
		return 0.0
	if profile.size() == 1:
		var only: Variant = profile[0]
		return float((only as Dictionary).get("height", 0.0)) \
			if only is Dictionary else 0.0
	var f: float = fposmod(fraction, 1.0)
	var count: int = profile.size()
	for i in count:
		var a: Variant = profile[i]
		var b: Variant = profile[(i + 1) % count]
		if not (a is Dictionary) or not (b is Dictionary):
			continue
		var a_data: Dictionary = a as Dictionary
		var b_data: Dictionary = b as Dictionary
		var a_at: float = fposmod(float(a_data.get("at", 0.0)), 1.0)
		var b_at: float = fposmod(float(b_data.get("at", 1.0)), 1.0)
		var span: float = b_at - a_at
		if span <= 0.0:
			span += 1.0
		var local: float = f - a_at
		if local < 0.0:
			local += 1.0
		if local > span:
			continue
		var t: float = local / maxf(span, 0.0001)
		t = t * t * (3.0 - 2.0 * t)
		return lerpf(float(a_data.get("height", 0.0)),
			float(b_data.get("height", 0.0)), t)
	return 0.0


## Signed side that lies outside the bend near `from_distance`: +1 is the right
## edge, -1 the left edge, 0 when the tile runs straight.
func _outside_side(from_distance: float, to_distance: float) -> float:
	var before: float = _yaw_at(from_distance)
	var after: float = _yaw_at(to_distance)
	var delta: float = angle_difference(before, after)
	if absf(delta) < 0.06:
		return 0.0
	return 1.0 if delta > 0.0 else -1.0


func _yaw_at(distance: float) -> float:
	var index: int = _sample_index(distance)
	var next: int = (index + 1) % points.size()
	var forward: Vector3 = points[next] - points[index]
	return atan2(-forward.x, -forward.z)


# --------------------------------------------------------------------------
# lookups


func is_closed() -> bool:
	return total_length > 1.0 and points.size() > 8


func _sample_index(distance: float) -> int:
	var count: int = cumulative.size()
	if count <= 0:
		return 0
	var target: float = fposmod(distance, maxf(total_length, 0.001))
	var low: int = 0
	var high: int = count - 1
	while low < high:
		var mid: int = (low + high + 1) / 2
		if cumulative[mid] <= target:
			low = mid
		else:
			high = mid - 1
	return low


## Surface kind (normal / wet / ice) at an arc-length position.
func surface_at(distance: float) -> String:
	if sample_surface.is_empty():
		return "normal"
	return sample_surface[_sample_index(distance)]


## Road half width at an arc-length position.
func half_width_at(distance: float) -> float:
	if sample_width.is_empty():
		return TileCatalog.ROAD_HALF
	return sample_width[_sample_index(distance)]


## The placed tile that owns an arc-length position.
func tile_at(distance: float) -> Dictionary:
	if sample_tile.is_empty():
		return {}
	return tiles[clampi(sample_tile[_sample_index(distance)], 0, tiles.size() - 1)]


## Derive the lap-fraction surface spans, merging neighbouring equal kinds and
## folding a run that crosses the start line back onto the front.
func _build_surfaces() -> void:
	surfaces.clear()
	if tiles.is_empty() or total_length <= 0.0:
		return
	var runs: Array[Dictionary] = []
	for tile: Dictionary in tiles:
		var kind: String = str(tile.get("surface", "normal"))
		var from: float = float(tile["from"]) / total_length
		var to: float = float(tile["to"]) / total_length
		if to < from:
			to += 1.0
		if not runs.is_empty() and str(runs[runs.size() - 1]["kind"]) == kind:
			runs[runs.size() - 1]["to"] = to
		else:
			runs.append({"kind": kind, "from": from, "to": to})
	if runs.size() > 1 and str(runs[0]["kind"]) == str(runs[runs.size() - 1]["kind"]):
		runs[0]["from"] = float(runs[runs.size() - 1]["from"]) - 1.0
		runs.remove_at(runs.size() - 1)
	for run: Dictionary in runs:
		surfaces.append({"kind": str(run["kind"]),
			"from": fposmod(float(run["from"]), 1.0),
			"to": fposmod(float(run["to"]), 1.0)})


## True when no part of the centreline is within `radius` of `point`.
func clearance(point: Vector3, radius: float) -> bool:
	var radius_sq: float = radius * radius
	var plan_point := Vector2(point.x, point.z)
	for p: Vector2 in _plan:
		if plan_point.distance_squared_to(p) < radius_sq:
			return false
	return true


## True when a prop `half_length` long and `radius` deep can stand at `lateral`
## beside `distance` without another part of the loop running through it.
func spot_ok(distance: float, lateral: float, half_length: float,
		radius: float) -> bool:
	if absf(lateral) < TileCatalog.ROAD_HALF + radius:
		return false
	for step in 5:
		var offset: float = -half_length + 2.0 * half_length * float(step) / 4.0
		var index: int = _sample_index(distance + offset)
		var point: Vector3 = points[index]
		var forward: Vector3 = points[(index + 1) % points.size()] - point
		var right: Vector3 = forward.cross(Vector3.UP).normalized()
		if not clearance(point + right * lateral, radius):
			return false
	return true


# --------------------------------------------------------------------------
# decoration anchors


## Turns each tile's hooks into world-space decoration requests. The furniture
## builder decides what fits; the layout only says where a piece belongs.
func _build_anchors() -> void:
	anchors.clear()
	for index in tiles.size():
		var tile: Dictionary = tiles[index]
		var from: float = float(tile["from"])
		var span: float = float(tile["span"])
		var outside: float = float(tile["outside"])
		var side: float = outside if outside != 0.0 \
			else (1.0 if index % 2 == 0 else -1.0)
		var hooks: PackedStringArray = tile["hooks"] as PackedStringArray
		for hook: String in hooks:
			match hook:
				"start":
					_add_anchor("gantry", from + span * 0.5, 0.0, 0.0, 0.0)
				"pit":
					_add_anchor("pit", from, 0.0, float(tile["pit_side"]), span)
				"grandstand":
					_add_anchor("grandstand", from + span * 0.5, side * 17.5,
						side, 26.0)
				"tyres":
					if outside != 0.0:
						_add_anchor("tyres", from + span * CORNER_TYRE_AT,
							outside * 7.9, outside, 14.0)
				"marshal":
					_add_anchor("marshal", from + span * CORNER_MARSHAL_AT,
						side * 13.0, side, 0.0)
				"billboard":
					_add_anchor("billboard", from + span * 0.34,
						side * 9.4, side, 4.6)
					_add_anchor("billboard", from + span * 0.74,
						-side * 9.4, -side, 4.6)
				"floodlight":
					_add_anchor("floodlight", from + span * 0.5,
						side * 20.0, side, 0.0)
				"jump":
					_add_anchor("jump", from + span * 0.5, 0.0, 0.0, span)
				"split":
					_add_anchor("split", from, 0.0, 0.0, span)
				"containers":
					_add_anchor("containers", from + span * 0.5,
						side * 21.0, side, 18.0)
				"snowbank":
					_add_anchor("snowbank", from + span * 0.5,
						side * 16.0, side, 20.0)
				_:
					pass
	# Two extra marshals per map and one floodlight per three tiles keep the
	# trackside busy without a per-tile cost on short corners.
	if tiles.size() >= 4:
		var quarter: float = total_length * 0.25
		_add_anchor("marshal", quarter, 12.0, 1.0, 0.0)
		_add_anchor("marshal", total_length * 0.75, -12.0, -1.0, 0.0)
	for index in tiles.size():
		if index % 3 != 1:
			continue
		var tile: Dictionary = tiles[index]
		var side: float = float(tile["outside"])
		if side == 0.0:
			side = 1.0 if index % 2 == 0 else -1.0
		_add_anchor("floodlight", float(tile["from"]) + float(tile["span"]) * 0.5,
			side * 20.0, side, 0.0)


func _add_anchor(kind: String, distance: float, lateral: float, side: float,
		length: float) -> void:
	anchors.append({
		"kind": kind,
		"distance": fposmod(distance, maxf(total_length, 0.001)),
		"lateral": lateral,
		"side": side,
		"length": length,
	})


## Total decoration pieces the anchors ask for, for the density printout.
func anchor_count(kind: String) -> int:
	var count: int = 0
	for anchor: Dictionary in anchors:
		if str(anchor["kind"]) == kind:
			count += 1
	return count
