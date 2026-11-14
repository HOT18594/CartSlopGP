extends RefCounted
class_name KenneyTiles
## Grid tile engine for the Kenney cartoon race maps.
##
## A map is an ASCII grid, one character per 16 m cell, drawn top-down:
##
##   S straight        L corner turning left    R corner turning right
##   C crossing        W wide sweeper           B bump
##   J jump ramp       P pit straight           E pit entry
##   G pit garage      X empty (no tile)
##
## The builder derives every piece's rotation from its grid neighbours, so a map
## author only types characters. A lap is a single closed loop; when the typed
## grid leaves a short gap (up to two and a half cells) the builder closes it by
## following the path and warns. A grid that cannot be closed fails loudly with
## the 1-based row and column of the offending tile.
##
## The returned spline is a RefCounted with the TrackSpline public surface
## (`points`, `cumulative`, `total_length`, `wrap_distance`, `sample`, `closest`,
## `yaw_at`, `curvature_at`), so bots, lap logic, surfaces and the server
## contract keep working without knowing a grid was involved. Extra helpers:
## `tiles`, `tile_at`, `cell_at`, `surface_at`, `half_width_at`, `gap_length`.
##
## Map contract (see also scripts/minigames/tile_kit.gd):
##   maps/<id>_theme.gd :  static func build(race: Node3D, spline) -> void
## The theme dresses the map with tile_kit.* and returns nothing. This engine
## owns the road, its colliders and the spline. Tiles are flat: the Kenney kit
## is planar, so ramps and bumps are props with their own ramp colliders.
##
## Wiring (the race scene, not this file, does it once per race):
##   _spline = KenneyTiles.build(self, TrackDefs.grid_of(preset),
##       {"id": TrackDefs.theme_id_of(preset)})
## then grass_race hands that returned spline to the preset's theme build().
## Until that call exists the race keeps sampling the old TrackSpline and the
## grid engine is only exercised by the headless harness.
##
## Every road cell collides on CollisionLayers.WORLD with a box, and jump/bump
## cells get a real wedge/hump concave shape instead of a box so a kart drives
## up the slope it sees.

const TileCatalog := preload("res://scripts/minigames/tiles/tile_catalog.gd")
const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")

## Metres per ASCII cell. Measured from the kit's 1.0-unit module, with the
## 0.69027-unit lane scaled to the game's established 11 m road.
const TILE_SIZE: float = TileCatalog.TILE_SIZE
const ROAD_HALF: float = TileCatalog.ROAD_HALF
const HALF_TILE: float = TILE_SIZE * 0.5

const HOLDER_NAME: String = "KenneyGrid"
const TILE_CHARS: String = "SLRCWBJPEGX"

const EDGE_N: int = 0
const EDGE_E: int = 1
const EDGE_S: int = 2
const EDGE_W: int = 3

## Spline sampling. Straight cells get four segments, corners six, W eight.
const STRAIGHT_STEPS: int = 4
const CORNER_STEPS: int = 6
const WIDE_STEPS: int = 8
const CLOSE_STEP: float = 4.0
const ROAD_THICKNESS: float = 0.4

## Clearance sampling. A barrier path is walked along the real road edge in
## steps this small, so a chord across a corner can never cut onto the surface.
const CLEARANCE_STEP: float = 0.75
## Height data. A `heights` grid uses one digit per cell, each worth this many
## metres; a cell without data is flat (the historical behaviour).
const HEIGHT_STEP: float = 1.5
const HEIGHT_CHARS: String = "0123456789"
## An elevated straight cell at least this high gets the kit's bridge support
## under its deck, so a raised road reads as a bridge and not as a floating slab.
const BRIDGE_MIN_HEIGHT: float = 2.0
const BRIDGE_MODEL: String = "roadStraightBridge"
## Height data key on the race root, so prop helpers can follow the terrain.
const HEIGHTS_META: String = "kenney_heights"

static var _ramp_height: float = -1.0
static var _bump_height: float = -1.0


## Closed centreline derived from a traced grid lap. Mirrors TrackSpline.
class GridSpline:
	extends RefCounted

	var points: PackedVector3Array = PackedVector3Array()
	var cumulative: PackedFloat32Array = PackedFloat32Array()
	var total_length: float = 0.0
	## {cell, row, col, tile, entry, exit, yaw, start, from, to}
	var tiles: Array[Dictionary] = []
	var road_half: float = 0.0
	## Length of the synthetic straight added to close a short gap. Zero on a
	## grid that was already closed.
	var gap_length: float = 0.0
	## Per-cell road heights in metres, empty on a flat grid. Prop helpers read
	## this to sit on the terrain instead of at world zero.
	var heights: Dictionary = {}

	var _count: int = 0

	func _init(pts: PackedVector3Array, tile_list: Array,
			half_width: float) -> void:
		points = pts
		road_half = half_width
		for entry: Variant in tile_list:
			if entry is Dictionary:
				tiles.append(entry as Dictionary)
		_count = points.size()
		if _count == 0:
			return
		cumulative.resize(_count)
		var travelled: float = 0.0
		for i in _count:
			cumulative[i] = travelled
			travelled += points[i].distance_to(points[(i + 1) % _count])
		total_length = travelled


	## A lap needs enough samples and a positive length to be usable.
	func is_closed() -> bool:
		return total_length > 1.0 and _count > 8


	func wrap_distance(distance: float) -> float:
		if total_length <= 0.0:
			return distance
		return fposmod(distance, total_length)


	## Returns {position, forward, right} at arc length `distance`.
	func sample(distance: float) -> Dictionary:
		if _count < 2:
			return {"position": Vector3.ZERO, "forward": Vector3.FORWARD,
				"right": Vector3.RIGHT}
		var s: float = wrap_distance(distance)
		var index: int = _segment_at(s)
		var next: int = (index + 1) % _count
		var seg_start: float = cumulative[index]
		var seg_length: float = total_length - seg_start if next == 0 \
			else cumulative[next] - seg_start
		var t: float = clampf((s - seg_start) / maxf(seg_length, 0.0001), 0.0, 1.0)
		var a: Vector3 = points[index]
		var b: Vector3 = points[next]
		var forward: Vector3 = (b - a).normalized()
		return {
			"position": a.lerp(b, t),
			"forward": forward,
			"right": forward.cross(Vector3.UP).normalized(),
		}


	## Nearest point on the polyline. Returns {s, distance, point}.
	func closest(world_position: Vector3) -> Dictionary:
		var best_sq: float = INF
		var best_s: float = 0.0
		var best_point: Vector3 = Vector3.ZERO
		for i in _count:
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
				best_s = wrap_distance(cumulative[i] + sqrt(length_sq) * t)
		return {"s": best_s, "distance": sqrt(best_sq), "point": best_point}


	func yaw_at(distance: float) -> float:
		var forward: Vector3 = sample(distance)["forward"]
		return atan2(-forward.x, -forward.z)


	func curvature_at(distance: float, window: float = 6.0) -> float:
		var yaw_a: float = yaw_at(distance - window)
		var yaw_b: float = yaw_at(distance + window)
		return wrapf(yaw_b - yaw_a, -PI, PI) / (window * 2.0)


	## Placed tile that owns an arc-length position.
	func tile_at(distance: float) -> Dictionary:
		if tiles.is_empty():
			return {}
		var s: float = wrap_distance(distance)
		for tile: Dictionary in tiles:
			if s >= float(tile.get("from", 0.0)) \
					and s < float(tile.get("to", total_length)):
				return tile
		return tiles[tiles.size() - 1]


	func cell_at(distance: float) -> Vector2i:
		var tile: Dictionary = tile_at(distance)
		if tile.is_empty():
			return Vector2i.ZERO
		return tile["cell"]


	## The grid maps are dry tarmac; themes own grip variation at registry level.
	func surface_at(_distance: float) -> String:
		return "normal"


	func half_width_at(_distance: float) -> float:
		return road_half


	## Road height at an arc length, in metres. Zero on a flat grid; on an
	## elevated grid the road, the road colliders and the spline all carry it.
	func height_at(distance: float) -> float:
		if _count < 2:
			return 0.0
		return sample(distance)["position"].y


	## Plan (top-down) distance from a world point to the centreline. Barrels,
	## barriers and props measure clearance against this: a prop beside a raised
	## road section is still on the racing surface if its plan distance is small.
	func plan_distance(world_position: Vector3) -> float:
		return float(plan_closest(world_position)["distance"])


	## Nearest centreline point in plan view: {s, distance, point}.
	func plan_closest(world_position: Vector3) -> Dictionary:
		var best_sq: float = INF
		var best_s: float = 0.0
		var best_point: Vector3 = Vector3.ZERO
		for i in _count:
			var a: Vector3 = points[i]
			var b: Vector3 = points[(i + 1) % _count]
			var ab := Vector2(b.x - a.x, b.z - a.z)
			var ap := Vector2(world_position.x - a.x, world_position.z - a.z)
			var length_sq: float = ab.length_squared()
			var t: float = 0.0
			if length_sq > 0.000001:
				t = clampf(ap.dot(ab) / length_sq, 0.0, 1.0)
			var candidate := Vector2(a.x, a.z) + ab * t
			var dx: float = world_position.x - candidate.x
			var dz: float = world_position.z - candidate.y
			var d_sq: float = dx * dx + dz * dz
			if d_sq < best_sq:
				best_sq = d_sq
				best_point = Vector3(candidate.x, world_position.y, candidate.y)
				best_s = wrap_distance(cumulative[i] + sqrt(length_sq) * t)
		return {"s": best_s, "distance": sqrt(best_sq), "point": best_point}


	func _segment_at(s: float) -> int:
		var low: int = 0
		var high: int = _count - 1
		while low < high:
			var mid: int = (low + high + 1) / 2
			if cumulative[mid] <= s:
				low = mid
			else:
				high = mid - 1
		return low


# --------------------------------------------------------------------------
# build


## Builds the whole grid map under `parent` and returns its GridSpline.
## `rows` is drawn top-down; `theme` is a theme id string or a dictionary with
## `id` and optional `start` (Vector2i(column, row) or [row, column]).
static func build(parent: Node3D, rows: PackedStringArray,
		theme: Variant = null) -> RefCounted:
	if parent == null:
		push_error("KenneyTiles: build() needs a parent Node3D.")
		return null
	if rows.is_empty():
		push_error("KenneyTiles: the grid has no rows.")
		return null
	if parent.has_node(HOLDER_NAME):
		var cached: Variant = parent.get_meta("kenney_spline", null)
		if cached is RefCounted:
			return cached as RefCounted
		push_error("KenneyTiles: %s already exists on the parent but carries no spline." % HOLDER_NAME)
		return null

	var parsed: Dictionary = _parse(rows)
	if not bool(parsed.get("ok", false)):
		return null
	var grid: Dictionary = parsed["grid"]
	var width: int = int(parsed["width"])
	var height: int = int(parsed["height"])
	# Height data is optional. On a grid with no `heights` the spec is flat and
	# every placement below is byte-for-byte the historical flat pipeline.
	var heights: Dictionary = _height_spec(theme, width, height)

	var connections: Dictionary = {}
	var errors: Array[String] = []
	var warnings: Array[String] = []
	_build_connections(grid, connections, errors, warnings)
	if not errors.is_empty():
		for message: String in errors:
			push_error("KenneyTiles: " + message)
		return null

	var start: Vector2i = _start_cell(grid, theme)
	var best: Dictionary = _best_walk(grid, connections, start)
	if not bool(best.get("ok", false)):
		push_error("KenneyTiles: " + str(best.get("error", "cannot trace a lap.")))
		return null
	var walk_warnings: Array = best.get("warnings", [])
	for text: String in walk_warnings:
		push_warning("KenneyTiles: " + text)
	for text: String in warnings:
		push_warning("KenneyTiles: " + text)

	var unvisited: Vector2i = _first_unvisited(grid, best["cells"] as Array)
	if unvisited.x >= 0:
		push_error("KenneyTiles: %s: tile '%s' is not part of the closed lap. Every S/L/R/C/W/B/J/P/E/G cell must sit on the loop; use X for decoration." % [
			_where(unvisited), str(grid[unvisited])])
		return null
	if not bool(best.get("closed", false)) \
			and not bool(best.get("closable", false)):
		push_error("KenneyTiles: the grid is not a closed loop. The path stops at %s (open %s edge); it cannot reach the start cell %s. Add the missing cells or mark the gap with X." % [
			_where(best.get("open_cell", start)),
			_edge_name(int(best.get("open_exit", EDGE_N))),
			_where(start)])
		return null

	var tiles: Array[Dictionary] = _make_tiles(best, grid, heights)
	var points: PackedVector3Array = _build_points(tiles, best, heights)
	if points.size() < 8:
		push_error("KenneyTiles: the grid flattened to %d spline points; a lap needs at least 8. Is the loop only one or two cells long?" % points.size())
		return null

	var spline := GridSpline.new(points, tiles, ROAD_HALF)
	spline.heights = heights.get("cells", {}) as Dictionary
	var gap: Dictionary = best.get("gap", {})
	if bool(gap.get("ok", false)):
		spline.gap_length = float(gap.get("length", 0.0))
	if not spline.is_closed():
		push_error("KenneyTiles: the grid produced a degenerate lap (%.1f m, %d points). Every loop needs at least four cells." % [
			spline.total_length, points.size()])
		return null

	_fill_tile_distances(spline)
	_build_road(parent, tiles, heights)
	_build_road_collision(parent, tiles, heights)

	var theme_id: String = _theme_id(theme)
	parent.set_meta("kenney_spline", spline)
	parent.set_meta(HEIGHTS_META, heights)
	parent.set_meta("kenney_grid_stats", {
		"theme": theme_id,
		"tiles": tiles.size(),
		"length": spline.total_length,
		"gap": spline.gap_length,
		"rows": height,
		"cols": width,
		"start_cell": start,
		"max_height": float(heights.get("max_height", 0.0)),
	})
	print("KENNEY GRID %s: %d tiles, %.1f m lap, %d rows x %d cols%s%s" % [
		theme_id, tiles.size(), spline.total_length, height, width,
		"" if spline.gap_length <= 0.0 \
			else " (closed a %.1f m gap)" % spline.gap_length,
		"" if float(heights.get("max_height", 0.0)) <= 0.001 \
			else ", elevation to %.1f m" % float(heights.get("max_height", 0.0))])
	return spline


## ASCII character of every placed tile, in lap order. Diagnostics helper.
static func grid_summary(spline: RefCounted) -> String:
	if spline == null:
		return ""
	var text := PackedStringArray()
	for tile: Dictionary in spline.get("tiles") as Array:
		text.append(str(tile.get("tile", "X")))
	return "".join(text)


# --------------------------------------------------------------------------
# parsing


static func _parse(rows: PackedStringArray) -> Dictionary:
	var grid: Dictionary = {}
	var width: int = 0
	for row_index in rows.size():
		var line: String = rows[row_index]
		width = maxi(width, line.length())
		for col in line.length():
			var raw: String = line[col].to_upper()
			if raw == " " or raw == "." or raw == "_" or raw == "-":
				raw = "X"
			if not TILE_CHARS.contains(raw):
				push_error("KenneyTiles: row %d, column %d: unknown tile character '%s'. Use S, L, R, C, W, B, J, P, E, G or X." % [
					row_index + 1, col + 1, raw])
				return {"ok": false}
			if raw != "X":
				grid[Vector2i(col, row_index)] = raw
	if grid.is_empty():
		push_error("KenneyTiles: the grid has no drivable tiles; every cell was X.")
		return {"ok": false}
	return {"ok": true, "grid": grid, "width": width, "height": rows.size()}


static func _where(cell: Vector2i) -> String:
	return "row %d, column %d" % [cell.y + 1, cell.x + 1]


# --------------------------------------------------------------------------
# elevation
#
# Terrain is opt-in and per road cell. The theme dictionary (or, because the
# race scene passes only the theme id, the registry preset of that id) may carry
#   "heights":  Dictionary {Vector2i | "col,row": metres},
#               PackedStringArray/Array one row per grid row with '.' for flat
#               and '0'..'9' for digit * `height_step` metres, or
#               a flat row-major Array/PackedFloat32Array of metres,
#   "height_step": metres per digit (default HEIGHT_STEP),
#   "bridges": cells that get a bridge support under an elevated deck,
#   "elevation": Array of {at, height} lap fractions (a smooth profile).
# A flat grid (no data, or all zeros) keeps the old flat pipeline untouched.


## Normalised height data: {cells: Dictionary[Vector2i, float], bridges:
## Dictionary[Vector2i, bool], profile: Array, max_height: float, flat: bool}.
static func _height_spec(theme: Variant, width: int, height: int) -> Dictionary:
	var spec: Dictionary = {
		"cells": {}, "profile": [], "step": HEIGHT_STEP,
		"max_height": 0.0, "flat": true,
	}
	var data: Dictionary = {}
	if theme is Dictionary:
		data = theme as Dictionary
	var source: Dictionary = data
	if not data.has("heights") and not data.has("elevation"):
		source = _preset_for(_theme_id(theme))
		if source.is_empty():
			source = data
	var step: float = maxf(float(source.get("height_step",
		data.get("height_step", HEIGHT_STEP))), 0.1)
	spec["step"] = step
	var raw: Variant = source.get("heights", null)
	if raw is Dictionary:
		for key: Variant in raw as Dictionary:
			var cell: Vector2i = _cell_key(key)
			if cell.x >= 0:
				(spec["cells"] as Dictionary)[cell] = float((raw as Dictionary)[key])
	elif raw is PackedStringArray or raw is Array:
		_read_height_rows(spec, raw, width, height, step)
	var profile: Variant = source.get("elevation", null)
	if profile is Array:
		for entry: Variant in profile as Array:
			if not (entry is Dictionary):
				continue
			var point: Dictionary = entry as Dictionary
			(spec["profile"] as Array).append({
				"at": clampf(float(point.get("at", 0.0)), 0.0, 1.0),
				"height": float(point.get("height", 0.0)),
			})
	var maximum: float = 0.0
	for cell: Vector2i in spec["cells"] as Dictionary:
		maximum = maxf(maximum, absf(float((spec["cells"] as Dictionary)[cell])))
	for point: Dictionary in spec["profile"] as Array:
		maximum = maxf(maximum, absf(float(point["height"])))
	spec["max_height"] = maximum
	spec["flat"] = maximum < 0.001
	return spec


## Reads a digit-row or flat-number height grid into `spec.cells`.
static func _read_height_rows(spec: Dictionary, raw: Variant, width: int,
		height: int, step: float) -> void:
	var rows: PackedStringArray = PackedStringArray()
	if raw is PackedStringArray:
		rows = raw as PackedStringArray
	elif raw is Array:
		var array: Array = raw as Array
		var text: bool = not array.is_empty()
		for entry: Variant in array:
			if not (entry is String):
				text = false
				break
		if text:
			for entry: Variant in array:
				rows.append(str(entry))
		else:
			# Flat row-major metres.
			for index in mini(array.size(), width * height):
				(spec["cells"] as Dictionary)[Vector2i(index % width,
					index / width)] = float(array[index])
			return
	for row_index in rows.size():
		var line: String = rows[row_index]
		for col in line.length():
			var glyph: String = line[col]
			var digit: int = HEIGHT_CHARS.find(glyph)
			if digit < 0:
				continue
			(spec["cells"] as Dictionary)[Vector2i(col, row_index)] = \
				float(digit) * step


## A cell key from Vector2i, "col,row" text or [col, row]. x < 0 means invalid.
static func _cell_key(raw: Variant) -> Vector2i:
	if raw is Vector2i:
		return raw as Vector2i
	if raw is String:
		var parts: PackedStringArray = str(raw).split(",", false, 2)
		if parts.size() == 2 and parts[0].strip_edges().is_valid_int() \
				and parts[1].strip_edges().is_valid_int():
			return Vector2i(parts[0].strip_edges().to_int(),
				parts[1].strip_edges().to_int())
		return Vector2i(-1, -1)
	if raw is Array and (raw as Array).size() >= 2:
		var coords: Array = raw as Array
		return Vector2i(int(coords[0]), int(coords[1]))
	if raw is Vector2:
		var point: Vector2 = raw as Vector2
		return Vector2i(int(point.x), int(point.y))
	return Vector2i(-1, -1)


## The registry preset for a theme id, loaded lazily so a broken registry can
## never stop this engine from parsing.
static func _preset_for(theme_id: String) -> Dictionary:
	var path: String = "res://scripts/minigames/track_defs.gd"
	if theme_id == "" or not ResourceLoader.exists(path):
		return {}
	var script: Script = load(path) as Script
	if script == null or not script.has_method("get_preset"):
		return {}
	var preset: Variant = script.call("get_preset", theme_id)
	if preset is Dictionary:
		return preset as Dictionary
	return {}


## Height a lap fraction, from the smooth `elevation` profile.
static func _profile_height(profile: Array, fraction: float) -> float:
	if profile.is_empty():
		return 0.0
	var wrapped: float = fposmod(fraction, 1.0)
	var before: Dictionary = profile[profile.size() - 1]
	var after: Dictionary = profile[0]
	for index in profile.size():
		var current: Dictionary = profile[index]
		var next: Dictionary = profile[(index + 1) % profile.size()]
		var from_at: float = float(current["at"])
		var to_at: float = float(next["at"]) if index + 1 < profile.size() \
			else float(next["at"]) + 1.0
		if wrapped >= from_at and wrapped <= to_at:
			before = current
			after = next
			break
	var span: float = float(after["at"]) - float(before["at"])
	if span <= 0.0:
		return float(before["height"])
	var t: float = clampf((wrapped - float(before["at"])) / span, 0.0, 1.0)
	return lerpf(float(before["height"]), float(after["height"]), t)


## Applies entry/exit heights to every tile in lap order. A `heights` grid keeps
## the road continuous because each tile's exit is the next cell's entry.
static func _tile_heights(tiles: Array[Dictionary], heights: Dictionary) -> void:
	var cells: Dictionary = heights.get("cells", {}) as Dictionary
	var profile: Array = heights.get("profile", []) as Array
	var count: int = tiles.size()
	for index in count:
		var tile: Dictionary = tiles[index]
		var cell: Vector2i = tile["cell"]
		var next: Dictionary = tiles[(index + 1) % count]
		var h_in: float = float(cells.get(cell, 0.0))
		var h_out: float = float(cells.get(next["cell"], 0.0))
		if not profile.is_empty() and cells.is_empty():
			h_in = _profile_height(profile, float(index) / float(maxi(count, 1)))
			h_out = _profile_height(profile,
				float(index + 1) / float(maxi(count, 1)))
		tile["height_in"] = h_in
		tile["height_out"] = h_out
		tile["height"] = (h_in + h_out) * 0.5


## Pitch of one road tile, in radians, from its entry-to-exit rise.
static func _tile_pitch(tile: Dictionary) -> float:
	var rise: float = float(tile.get("height_out", 0.0)) \
		- float(tile.get("height_in", 0.0))
	if absf(rise) < 0.0001:
		return 0.0
	var run: float = _tile_run(tile)
	if run < 0.01:
		return 0.0
	return atan2(rise, run)


## Horizontal distance between a tile's two edge midpoints: a full cell for a
## straight, the chord of the quarter arc for a corner.
static func _tile_run(tile: Dictionary) -> float:
	if _opposite(int(tile.get("entry", EDGE_N))) == int(tile.get("exit", EDGE_S)):
		return TILE_SIZE
	return HALF_TILE * sqrt(2.0)


# --------------------------------------------------------------------------
# connections
#
# A tile is a mapping from entry edge to exit edge. Edges are world cardinal
# directions: N = -Z, E = +X, S = +Z, W = -X. A straight pairs opposite edges;
# a corner pairs adjacent edges. Rotations are derived from this mapping, never
# from the model's export pivot.


static func _build_connections(grid: Dictionary, connections: Dictionary,
		errors: Array[String], warnings: Array[String]) -> void:
	for cell: Vector2i in grid:
		var tile: String = str(grid[cell])
		var neighbours: Array[int] = []
		for edge in 4:
			if grid.has(cell + _edge_step(edge)):
				neighbours.append(edge)
		var pairs: Array = []
		match tile:
			"S", "P", "E", "G", "B", "J":
				pairs = _straight_pairs(cell, tile, neighbours, errors)
			"L", "R", "W":
				pairs = _corner_pairs(cell, tile, neighbours, errors)
			"C":
				pairs = _crossing_pairs(cell, neighbours, errors, warnings)
			_:
				errors.append("%s: unsupported tile '%s'." % [_where(cell), tile])
		connections[cell] = pairs


static func _straight_pairs(cell: Vector2i, tile: String,
		neighbours: Array[int], errors: Array[String]) -> Array:
	if neighbours.size() == 2 and neighbours[0] == _opposite(neighbours[1]):
		return [[neighbours[0], neighbours[1]]]
	if neighbours.size() == 1:
		return [[neighbours[0], _opposite(neighbours[0])]]
	if neighbours.is_empty():
		errors.append("%s: isolated straight tile '%s'; it has no neighbour to join." % [
			_where(cell), tile])
		return []
	errors.append("%s: straight tile '%s' needs neighbours on opposite edges, found %s. Use L or R for a corner." % [
		_where(cell), tile, _edge_names(neighbours)])
	return []


static func _corner_pairs(cell: Vector2i, tile: String,
		neighbours: Array[int], errors: Array[String]) -> Array:
	if neighbours.size() == 2 and neighbours[0] != _opposite(neighbours[1]):
		return [[neighbours[0], neighbours[1]]]
	if neighbours.size() == 1 and tile != "W":
		var entry: int = neighbours[0]
		var din: Vector2i = -_edge_step(entry)
		var dout: Vector2i = _right_turn(din) if tile == "R" \
			else _left_turn(din)
		return [[entry, _edge_for(dout)]]
	if neighbours.size() == 2:
		errors.append("%s: corner tile '%s' needs two adjacent neighbours, found opposite edges. Use S for a straight." % [
			_where(cell), tile])
		return []
	errors.append("%s: corner tile '%s' needs exactly two adjacent neighbours, found %s." % [
		_where(cell), tile, _edge_names(neighbours)])
	return []


static func _crossing_pairs(cell: Vector2i, neighbours: Array[int],
		errors: Array[String], warnings: Array[String]) -> Array:
	var pairs: Array = []
	if neighbours.has(EDGE_N) and neighbours.has(EDGE_S):
		pairs.append([EDGE_N, EDGE_S])
	if neighbours.has(EDGE_E) and neighbours.has(EDGE_W):
		pairs.append([EDGE_E, EDGE_W])
	if not pairs.is_empty():
		if neighbours.size() == 3:
			warnings.append("%s: crossing 'C' has a dead-end arm; only the two through arms are raced." % _where(cell))
		return pairs
	if neighbours.size() == 2 and neighbours[0] != _opposite(neighbours[1]):
		return [[neighbours[0], neighbours[1]]]
	if neighbours.size() == 1:
		return [[neighbours[0], _opposite(neighbours[0])]]
	errors.append("%s: crossing tile 'C' needs two or four path neighbours, found %s." % [
		_where(cell), _edge_names(neighbours)])
	return []


static func _exit_for(pairs: Array, entry: int) -> int:
	for pair: Array in pairs:
		if int(pair[0]) == entry:
			return int(pair[1])
		if int(pair[1]) == entry:
			return int(pair[0])
	return -1


# --------------------------------------------------------------------------
# tracing


static func _start_cell(grid: Dictionary, theme: Variant) -> Vector2i:
	if theme is Dictionary:
		var raw: Variant = (theme as Dictionary).get("start", null)
		if raw is Vector2i:
			var wanted: Vector2i = raw
			if grid.has(wanted):
				return wanted
		elif raw is Array and (raw as Array).size() >= 2:
			var coords: Array = raw as Array
			var wanted := Vector2i(int(coords[1]), int(coords[0]))
			if grid.has(wanted):
				return wanted
	var first: Vector2i = Vector2i(-1, -1)
	var first_straight: Vector2i = Vector2i(-1, -1)
	for cell: Vector2i in grid:
		if first.x < 0 or cell.y < first.y \
				or (cell.y == first.y and cell.x < first.x):
			first = cell
		if first_straight.x < 0 \
				and str(grid[cell]) in ["S", "P", "E", "G", "B", "J", "C"]:
			first_straight = cell
		elif first_straight.x >= 0 and str(grid[cell]) in ["S", "P", "E", "G", "B", "J", "C"]:
			if cell.y < first_straight.y \
					or (cell.y == first_straight.y and cell.x < first_straight.x):
				first_straight = cell
	if first_straight.x >= 0:
		return first_straight
	return first


static func _best_walk(grid: Dictionary, connections: Dictionary,
		start: Vector2i) -> Dictionary:
	var pairs: Array = connections.get(start, [])
	if pairs.is_empty():
		return {"ok": false, "error": "%s: the start cell has no connection." % _where(start)}
	var first_error: String = ""
	var best: Dictionary = {}
	for pair_index in pairs.size():
		var pair: Array = pairs[pair_index]
		for direction in 2:
			var entry: int = int(pair[direction])
			var result: Dictionary = _walk(grid, connections, start, entry)
			if not bool(result.get("ok", false)):
				if first_error == "":
					first_error = str(result.get("error", ""))
				continue
			result = _score(result, grid, start)
			if best.is_empty() or int(result["score"]) > int(best["score"]):
				best = result
	if best.is_empty():
		return {"ok": false, "error": first_error if first_error != "" \
			else "cannot trace a lap from %s." % _where(start)}
	return best


static func _walk(grid: Dictionary, connections: Dictionary, start: Vector2i,
		start_entry: int) -> Dictionary:
	var cells: Array[Vector2i] = []
	var entries: Array[int] = []
	var exits: Array[int] = []
	var seen: Dictionary = {}
	var result: Dictionary = {
		"ok": true,
		"closed": false,
		"cells": cells,
		"entries": entries,
		"exits": exits,
		"open_cell": Vector2i(-1, -1),
		"open_exit": -1,
		"error": "",
	}
	var cell: Vector2i = start
	var entry: int = start_entry
	var guard: int = grid.size() * 4 + 16
	for _step in guard:
		var pair: Array = connections.get(cell, [])
		var exit: int = _exit_for(pair, entry)
		if exit < 0:
			result["ok"] = false
			result["error"] = "%s: cannot enter from the %s edge; the tile does not connect there." % [
				_where(cell), _edge_name(entry)]
			return result
		cells.append(cell)
		entries.append(entry)
		exits.append(exit)
		seen[cell] = true
		var next: Vector2i = cell + _edge_step(exit)
		var next_entry: int = _opposite(exit)
		if next == start:
			if next_entry == start_entry:
				result["closed"] = true
				return result
			result["ok"] = false
			result["error"] = "%s: the lap returns to the start from the %s edge, but the start enters from the %s edge." % [
				_where(cell), _edge_name(exit), _edge_name(start_entry)]
			return result
		if not grid.has(next):
			result["open_cell"] = cell
			result["open_exit"] = exit
			return result
		if seen.has(next):
			result["ok"] = false
			result["error"] = "%s: the path loops back on itself before closing; this grid is not one single loop." % _where(next)
			return result
		if _exit_for(connections.get(next, []), next_entry) < 0:
			result["ok"] = false
			result["error"] = "%s: the path leaves %s toward %s, but that tile does not connect back." % [
				_where(next), _where(cell), _edge_name(exit)]
			return result
		cell = next
		entry = next_entry
	result["ok"] = false
	result["error"] = "%s: the path did not close within %d steps; check the grid for a branch." % [
		_where(start), guard]
	return result


static func _score(result: Dictionary, grid: Dictionary,
		start: Vector2i) -> Dictionary:
	var cells: Array = result["cells"]
	var entries: Array = result["entries"]
	var exits: Array = result["exits"]
	var warnings: Array[String] = []
	var mismatches: int = 0
	for index in cells.size():
		var tile: String = str(grid[cells[index]])
		if tile != "L" and tile != "R":
			continue
		var din: Vector2i = -_edge_step(int(entries[index]))
		var dout: Vector2i = _edge_step(int(exits[index]))
		if din == -dout:
			continue
		var turn_right: bool = dout == _right_turn(din)
		if (tile == "R" and not turn_right) or (tile == "L" and turn_right):
			mismatches += 1
			warnings.append("%s: corner says '%s' but the lap turns %s here. The shape wins; use %s to silence this." % [
				_where(cells[index]), tile, "right" if turn_right else "left",
				"R" if turn_right else "L"])
	var gap: Dictionary = {}
	var closable: bool = false
	if not bool(result["closed"]):
		gap = _gap_info(result, start)
		closable = bool(gap.get("ok", false))
		if closable:
			warnings.append("the grid does not close at %s; closing it along the path with a %.1f m straight." % [
				_where(result["open_cell"]), float(gap["length"])])
		elif result["open_cell"] != Vector2i(-1, -1):
			warnings.append("the grid does not close: the path stops at %s and cannot reach the start at %s." % [
				_where(result["open_cell"]), _where(start)])
	var score: int = 0
	if bool(result["closed"]):
		score += 200000
	elif closable:
		score += 100000 - int(float(gap["length"]) * 10.0)
	score += cells.size() * 1000
	score -= mismatches * 20
	result["score"] = score
	result["mismatches"] = mismatches
	result["closable"] = closable
	result["gap"] = gap
	result["warnings"] = warnings
	return result


## A short gap (up to two and a half cells) can be closed by following the
## traced direction. Anything longer, or a gap that faces backwards, is an
## authoring error and fails in build() with the open cell's row and column.
static func _gap_info(result: Dictionary, start: Vector2i) -> Dictionary:
	var open_cell: Vector2i = result["open_cell"]
	var open_exit: int = int(result["open_exit"])
	if open_cell.x < 0 or open_exit < 0:
		return {"ok": false, "length": INF}
	var entries: Array = result["entries"]
	if entries.is_empty():
		return {"ok": false, "length": INF}
	var start_entry: int = int(entries[0])
	var from: Vector3 = _cell_center(open_cell) + _edge_3d(open_exit) * HALF_TILE
	var to: Vector3 = _cell_center(start) + _edge_3d(start_entry) * HALF_TILE
	var delta: Vector3 = to - from
	var length: float = delta.length()
	if length <= 0.01 or length > TILE_SIZE * 2.5:
		return {"ok": false, "length": length}
	var head: Vector3 = _edge_3d(open_exit)
	if delta.normalized().dot(head) < 0.1:
		return {"ok": false, "length": length}
	return {"ok": true, "length": length, "from": from, "to": to,
		"from_cell": open_cell, "to_cell": start}


static func _first_unvisited(grid: Dictionary, cells: Array) -> Vector2i:
	var visited: Dictionary = {}
	for cell: Vector2i in cells:
		visited[cell] = true
	for cell: Vector2i in grid:
		if not visited.has(cell):
			return cell
	return Vector2i(-1, -1)


# --------------------------------------------------------------------------
# tiles and spline


static func _make_tiles(best: Dictionary, grid: Dictionary,
		heights: Dictionary = {}) -> Array[Dictionary]:
	var tiles: Array[Dictionary] = []
	var cells: Array = best["cells"] as Array
	var entries: Array = best["entries"] as Array
	var exits: Array = best["exits"] as Array
	for index in cells.size():
		var cell: Vector2i = cells[index]
		var tile: String = str(grid[cell])
		var entry: int = int(entries[index])
		var exit: int = int(exits[index])
		var din: Vector3 = -_edge_3d(entry)
		var dout: Vector3 = _edge_3d(exit)
		tiles.append({
			"cell": cell,
			"row": cell.y,
			"col": cell.x,
			"tile": tile,
			"entry": entry,
			"exit": exit,
			"yaw": _tile_yaw(tile, din, dout),
			"start": index == 0,
		})
	_tile_heights(tiles, heights)
	return tiles


## Yaw that aligns a road piece with the lap. Kenney corner pieces are authored
## as right-hand corners (entry through +Z, exit through +X); a left corner uses
## the same symmetric arc traversed the other way.
static func _tile_yaw(tile: String, din: Vector3, dout: Vector3) -> float:
	if tile == "L" or tile == "R" or tile == "W":
		if dout.is_equal_approx(_right_of(din)):
			return atan2(-din.x, -din.z)
		return atan2(din.z, -din.x)
	return atan2(-din.x, -din.z)


## True for the tile kinds that run straight through a cell.
static func _is_straight_char(tile: String) -> bool:
	return tile == "S" or tile == "P" or tile == "E" or tile == "G" \
		or tile == "B" or tile == "J" or tile == "C"


static func _build_points(tiles: Array[Dictionary],
		best: Dictionary, heights: Dictionary = {}) -> PackedVector3Array:
	var points := PackedVector3Array()
	for index in tiles.size():
		var tile: Dictionary = tiles[index]
		var center: Vector3 = _cell_center(tile["cell"])
		var entry: int = int(tile["entry"])
		var exit: int = int(tile["exit"])
		var local: PackedVector3Array = _segment_points(center, entry, exit,
			str(tile["tile"]), float(tile.get("height_in", 0.0)),
			float(tile.get("height_out", 0.0)))
		var from_index: int = (points.size() - 1) if index > 0 else 0
		var start_at: int = 1 if index > 0 else 0
		for point_index in range(start_at, local.size()):
			_append_point(points, local[point_index])
		tile["from_index"] = maxi(from_index, 0)
		tile["to_index"] = points.size() - 1
	var gap: Dictionary = best.get("gap", {})
	if bool(gap.get("ok", false)):
		var from: Vector3 = gap["from"]
		var to: Vector3 = gap["to"]
		from.y = _cell_road_height(heights, gap.get("from_cell", Vector2i.ZERO))
		to.y = _cell_road_height(heights, gap.get("to_cell", Vector2i.ZERO))
		var steps: int = maxi(int(ceil(from.distance_to(to) / CLOSE_STEP)), 2)
		for step in range(1, steps + 1):
			_append_point(points, from.lerp(to, float(step) / float(steps)))
	if points.size() > 1 \
			and points[0].distance_to(points[points.size() - 1]) < 0.05:
		points.remove_at(points.size() - 1)
	return points


## Height of a cell's road deck in metres, 0 for a flat or unknown cell.
static func _cell_road_height(heights: Dictionary, cell: Vector2i) -> float:
	var cells: Dictionary = heights.get("cells", {}) as Dictionary
	return float(cells.get(cell, 0.0))


static func _segment_points(center: Vector3, entry: int, exit: int,
		tile: String, h_in: float = 0.0,
		h_out: float = 0.0) -> PackedVector3Array:
	var local := PackedVector3Array()
	var p_in: Vector3 = center + _edge_3d(entry) * HALF_TILE \
		+ Vector3.UP * h_in
	var p_out: Vector3 = center + _edge_3d(exit) * HALF_TILE \
		+ Vector3.UP * h_out
	if _opposite(entry) == exit:
		for step in STRAIGHT_STEPS + 1:
			local.append(p_in.lerp(p_out, float(step) / float(STRAIGHT_STEPS)))
		return local
	if tile == "W":
		var flat_center: Vector3 = center + Vector3.UP * ((h_in + h_out) * 0.5)
		for step in WIDE_STEPS + 1:
			var t: float = float(step) / float(WIDE_STEPS)
			var a: Vector3 = p_in.lerp(flat_center, t)
			var b: Vector3 = flat_center.lerp(p_out, t)
			local.append(a.lerp(b, t))
		return local
	var corner: Vector3 = center + _edge_3d(entry) * HALF_TILE \
		+ _edge_3d(exit) * HALF_TILE
	var start_angle: float = atan2(p_in.z - corner.z, p_in.x - corner.x)
	var end_angle: float = atan2(p_out.z - corner.z, p_out.x - corner.x)
	var delta: float = angle_difference(start_angle, end_angle)
	for step in CORNER_STEPS + 1:
		var angle: float = start_angle + delta \
			* float(step) / float(CORNER_STEPS)
		local.append(Vector3(corner.x + cos(angle) * HALF_TILE,
			lerpf(h_in, h_out, float(step) / float(CORNER_STEPS)),
			corner.z + sin(angle) * HALF_TILE))
	return local


static func _append_point(points: PackedVector3Array, point: Vector3) -> void:
	if points.is_empty() \
			or points[points.size() - 1].distance_to(point) > 0.001:
		points.append(point)


static func _fill_tile_distances(spline: GridSpline) -> void:
	var last_index: int = spline.points.size() - 1
	for tile: Dictionary in spline.tiles:
		var from_index: int = clampi(int(tile.get("from_index", 0)), 0, last_index)
		var to_index: int = clampi(int(tile.get("to_index", from_index)), 0,
			last_index)
		tile["from"] = spline.cumulative[from_index]
		tile["to"] = spline.total_length if to_index >= last_index \
			else spline.cumulative[to_index]


# --------------------------------------------------------------------------
# visuals


static func _build_road(parent: Node3D, tiles: Array[Dictionary],
		heights: Dictionary = {}) -> void:
	var holder := Node3D.new()
	holder.name = HOLDER_NAME
	parent.add_child(holder)
	var batches: Dictionary = {}
	var supports: Array = []
	for tile: Dictionary in tiles:
		var tile_char: String = str(tile["tile"])
		var center: Vector3 = _cell_center(tile["cell"])
		var yaw: float = float(tile["yaw"])
		var deck: Vector3 = center + Vector3.UP * float(tile.get("height", 0.0))
		var pitch: float = _tile_pitch(tile)
		var model: String = TileCatalog.START_MODEL \
			if bool(tile["start"]) and _is_straight_char(tile_char) \
			else TileCatalog.road_model(tile_char)
		var scale: Vector3 = TileCatalog.road_scale(tile_char) * TILE_SIZE
		if model == TileCatalog.START_MODEL:
			scale = Vector3.ONE * TILE_SIZE
		_add_batch(batches, model, _fit_tile(model, deck, yaw, scale, pitch))
		if tile_char == "C":
			# Two straights crossing on the same cell: the read of a junction
			# without a 2x2 piece that would spill into the neighbours. The
			# cross arm is lifted 12 mm so the two coplanar verge slabs cannot
			# z-fight in the overlap.
			_add_batch(batches, TileCatalog.road_model("S"),
				_fit_tile(TileCatalog.road_model("S"),
					deck + Vector3.UP * 0.012, yaw + PI * 0.5,
					Vector3.ONE * TILE_SIZE, pitch))
		if float(tile.get("height", 0.0)) >= BRIDGE_MIN_HEIGHT \
				and _is_straight_char(tile_char):
			supports.append({"deck": deck, "yaw": yaw})
	for model: String in batches:
		_batch_model(holder, model, batches[model] as Array, "Road_" + model,
			false)
	_build_bridge_supports(holder, supports)


## Elevated straight cells get the kit's bridge piece under the deck, squashed
## to the deck height, so a raised road reads as a bridge over the terrain
## instead of a floating slab. Purely visual; the road collider owns the deck.
static func _build_bridge_supports(holder: Node3D, decks: Array) -> void:
	if decks.is_empty():
		return
	var info: Dictionary = TileCatalog.model_info(BRIDGE_MODEL)
	if not bool(info.get("ok", false)):
		return
	var aabb: AABB = info["aabb"]
	if aabb.size.y <= 0.001 or aabb.size.x > 1.2 or aabb.size.z > 1.2:
		return
	var transforms: Array = []
	for entry: Dictionary in decks:
		var deck: Vector3 = entry["deck"]
		var height: float = float(deck.y)
		var scale := Vector3(TILE_SIZE,
			height / maxf(aabb.size.y, 0.001), TILE_SIZE)
		var base := Vector3(deck.x, 0.0, deck.z)
		transforms.append(_fit_transform(BRIDGE_MODEL, base, float(entry["yaw"]),
			scale))
	_batch_model(holder, BRIDGE_MODEL, transforms, "BridgeSupports", true)


## Places a road piece at `at` and tilts it along its travel direction. The tilt
## axis is the model's local X (Kenney road pieces run along local -Z), so a
## sloped cell reads as a ramp between its two edge heights.
static func _fit_tile(model: String, at: Vector3, yaw: float, scale: Vector3,
		pitch: float) -> Transform3D:
	var xform: Transform3D = _fit_transform(model, at, yaw, scale)
	if absf(pitch) < 0.0001:
		return xform
	var axis: Vector3 = Basis(Vector3.UP, yaw) * Vector3(1.0, 0.0, 0.0)
	var turn := Basis(axis, pitch)
	return Transform3D(turn * xform.basis, at + turn * (xform.origin - at))


static func _fit_transform(model: String, at: Vector3, yaw: float,
		scale: Vector3) -> Transform3D:
	var info: Dictionary = TileCatalog.model_info(model)
	if not bool(info.get("ok", false)):
		return Transform3D(Basis(Vector3.UP, yaw).scaled(scale), at)
	var center: Vector2 = info["center"]
	var aabb: AABB = info["aabb"]
	var yaw_basis := Basis(Vector3.UP, yaw)
	var basis: Basis = yaw_basis * Basis.IDENTITY.scaled(scale)
	var center_m := Vector3(center.x * scale.x, 0.0, center.y * scale.z)
	var lift: float = -aabb.position.y * scale.y
	return Transform3D(basis,
		at - yaw_basis * center_m + Vector3.UP * lift)


static func _add_batch(batches: Dictionary, model: String,
		xform: Transform3D) -> void:
	if not batches.has(model):
		batches[model] = []
	(batches[model] as Array).append(xform)


## One MultiMesh per mesh part, shared by every instance of `model`.
static func _batch_model(parent: Node3D, model: String, transforms: Array,
		node_name: String, cast_shadow: bool) -> void:
	if transforms.is_empty():
		return
	var info: Dictionary = TileCatalog.model_info(model)
	if not bool(info.get("ok", false)):
		return
	var parts: Array = info["parts"]
	for part_index in parts.size():
		var part: Dictionary = parts[part_index]
		var mesh: Mesh = part["mesh"] as Mesh
		var local: Transform3D = part["transform"]
		if mesh == null:
			continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = transforms.size()
		for index in transforms.size():
			var world: Transform3D = transforms[index]
			multi.set_instance_transform(index, world * local)
		var instance := MultiMeshInstance3D.new()
		instance.name = node_name if parts.size() == 1 \
			else "%s_%d" % [node_name, part_index]
		instance.multimesh = multi
		instance.cast_shadow = \
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(instance)


# --------------------------------------------------------------------------
# road colliders


static func _build_road_collision(parent: Node3D,
		tiles: Array[Dictionary], heights: Dictionary = {}) -> void:
	var holder: Node3D = parent.get_node_or_null(HOLDER_NAME) as Node3D
	if holder == null:
		return
	var body := StaticBody3D.new()
	body.name = "RoadCollision"
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = 0
	holder.add_child(body)
	var ramp_faces := PackedVector3Array()
	for tile: Dictionary in tiles:
		var tile_char: String = str(tile["tile"])
		var center: Vector3 = _cell_center(tile["cell"])
		var deck: Vector3 = center + Vector3.UP * float(tile.get("height", 0.0))
		var pitch: float = _tile_pitch(tile)
		if tile_char == "J" or tile_char == "B":
			_append_ramp_faces(ramp_faces, tile, tile_char == "B")
		else:
			# The box follows the same tilt as the visible slab, so a kart on a
			# hill drives the plane it sees rather than a flat staircase.
			_add_box_shape(body, _tilted_box(deck, float(tile["yaw"]), pitch,
				Vector3(TILE_SIZE, ROAD_THICKNESS, TILE_SIZE)),
				Vector3(TILE_SIZE, ROAD_THICKNESS, TILE_SIZE))
		if float(tile.get("height", 0.0)) >= BRIDGE_MIN_HEIGHT \
				and _is_straight_char(tile_char):
			# A raised deck is a hill: the space under it is solid terrain.
			_add_box_shape(body, Transform3D(Basis.IDENTITY,
				Vector3(center.x, float(tile.get("height", 0.0)) * 0.5,
					center.z)),
				Vector3(TILE_SIZE, float(tile.get("height", 0.0)),
					TILE_SIZE))
	if not ramp_faces.is_empty():
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(ramp_faces)
		shape.backface_collision = true
		var collision := CollisionShape3D.new()
		collision.name = "Ramps"
		collision.shape = shape
		body.add_child(collision)


## A box whose top face passes through `deck`, pitched along the tile travel.
static func _tilted_box(deck: Vector3, yaw: float, pitch: float,
		size: Vector3) -> Transform3D:
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3(1.0, 0.0, 0.0), pitch)
	return Transform3D(basis, deck + basis * Vector3.DOWN * (size.y * 0.5))


## Jump cells get a wedge that rises to the exit; bump cells get a hump. Both
## match the visible Kenney road piece, so the kart drives the slope it sees.
## The entry and exit rows take the tile's two deck heights, so ramps and jumps
## work on an elevated grid as well as on the flat fallback.
static func _append_ramp_faces(faces: PackedVector3Array, tile: Dictionary,
		hump: bool) -> void:
	var center: Vector3 = _cell_center(tile["cell"])
	var din: Vector3 = -_edge_3d(int(tile["entry"]))
	var right: Vector3 = din.cross(Vector3.UP).normalized()
	var entry_center: Vector3 = center - din * HALF_TILE \
		+ Vector3.UP * float(tile.get("height_in", 0.0))
	var exit_center: Vector3 = center + din * HALF_TILE \
		+ Vector3.UP * float(tile.get("height_out", 0.0))
	var e_l: Vector3 = entry_center - right * ROAD_HALF
	var e_r: Vector3 = entry_center + right * ROAD_HALF
	var x_l: Vector3 = exit_center - right * ROAD_HALF
	var x_r: Vector3 = exit_center + right * ROAD_HALF
	var height: float = _bump_face_height() if hump else _ramp_face_height()
	var mid: Vector3 = entry_center.lerp(exit_center, 0.5)
	if hump:
		var m_l: Vector3 = mid - right * ROAD_HALF + Vector3.UP * height
		var m_r: Vector3 = mid + right * ROAD_HALF + Vector3.UP * height
		_tri(faces, e_l, e_r, m_r)
		_tri(faces, e_l, m_r, m_l)
		_tri(faces, m_l, m_r, x_r)
		_tri(faces, m_l, x_r, x_l)
		_tri(faces, e_l, m_l, x_l)
		_tri(faces, e_r, x_r, m_r)
	else:
		var t_l: Vector3 = x_l + Vector3.UP * height
		var t_r: Vector3 = x_r + Vector3.UP * height
		_tri(faces, e_l, e_r, t_r)
		_tri(faces, e_l, t_r, t_l)
		_tri(faces, e_l, t_l, x_l)
		_tri(faces, e_r, x_r, t_r)
		_tri(faces, x_l, x_r, t_r)
		_tri(faces, x_l, t_r, t_l)


static func _tri(faces: PackedVector3Array, a: Vector3, b: Vector3,
		c: Vector3) -> void:
	faces.append(a)
	faces.append(b)
	faces.append(c)


static func _add_box_shape(body: StaticBody3D, xform: Transform3D,
		size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = xform
	body.add_child(collision)


static func _ramp_face_height() -> float:
	if _ramp_height < 0.0:
		_ramp_height = _model_height("roadRamp") * 0.6
	return _ramp_height


static func _bump_face_height() -> float:
	if _bump_height < 0.0:
		_bump_height = _model_height("roadBump") * 0.35
	return _bump_height


static func _model_height(model: String) -> float:
	var info: Dictionary = TileCatalog.model_info(model)
	if not bool(info.get("ok", false)):
		return 0.0
	var aabb: AABB = info["aabb"]
	return aabb.size.y * TILE_SIZE


# --------------------------------------------------------------------------
# clearance paths
#
# A prop that must stay a fixed distance from the racing surface cannot simply
# be offset from the spline: on the inside of an 8 m corner the offset folds
# across the corner point and lands on the road. These helpers instead walk the
# real tile edge geometry, join the folded inside corners with a mitre between
# the two neighbouring edges, and then re-project every point so nothing can
# ever be closer than the requested lateral distance. tile_kit.barrier_line and
# tile_kit.terrain_banks both build on this.


## Plan distance from a world point to the centreline of any spline, using the
## grid spline's exact plan helper when it has one.
static func plan_clearance(spline: RefCounted, point: Vector3) -> float:
	if spline == null:
		return INF
	if spline.has_method("plan_distance"):
		return float(spline.call("plan_distance", point))
	var hit: Dictionary = spline.call("closest", point)
	return float(hit.get("distance", INF))


static func _plan_closest(spline: RefCounted, point: Vector3) -> Dictionary:
	if spline.has_method("plan_closest"):
		return spline.call("plan_closest", point) as Dictionary
	var hit: Dictionary = spline.call("closest", point)
	return hit


## A constant-clearance path around the whole lap that follows the true road
## edge. `lateral` is the plan distance from the centreline; the returned points
## are what a barrier's inner face or a bank's inner edge should touch.
##
## Straights are lines at that lateral, the outside of a corner is a concentric
## arc and the inside of a corner is a mitre: no chord, no fold and no barrier
## on the racing surface. The result is closed (last point equals first) and
## carries the lap arc length each point came from, so a caller can map a run's
## [from, to] range onto it.
##
## Returns {ok, points, distances, lengths, total_length, lateral}.
static func clearance_path(spline: RefCounted, side: float, lateral: float,
		step: float = CLEARANCE_STEP) -> Dictionary:
	if spline == null:
		return _empty_path(lateral)
	# A non-grid spline has no "tiles" property at all; casting null to Array
	# raises "Invalid cast" at runtime, so fall back to the polyline path.
	var tiles_value: Variant = spline.get("tiles")
	var tiles: Array = tiles_value if tiles_value is Array else []
	if tiles.is_empty() or not spline.has_method("plan_distance"):
		return _polyline_clearance_path(spline, side, lateral, step)
	var sign_dir: float = 1.0 if side >= 0.0 else -1.0
	var pieces: Array[Dictionary] = []
	for tile: Dictionary in tiles:
		var piece: Dictionary = _clearance_piece(tile, sign_dir, lateral)
		if not piece.is_empty():
			pieces.append(piece)
	if pieces.size() < 2:
		return _empty_path(lateral)
	var points := PackedVector3Array()
	var distances := PackedFloat32Array()
	var previous: Dictionary = pieces[pieces.size() - 1]
	for index in pieces.size():
		var piece: Dictionary = pieces[index]
		if not points.is_empty():
			_join_clearance_pieces(points, distances, previous, piece)
		_append_piece_samples(points, distances, piece, step)
		previous = piece
	if points.size() < 2:
		return _empty_path(lateral)
	# Close the ring across the start/finish seam. The seam join is only needed
	# when the last tile folds (an inside corner just before the line).
	var total: float = maxf(float(spline.get("total_length")), 0.001)
	var first_piece: Dictionary = pieces[0]
	var seam_distance: float = total
	if points[points.size() - 1].distance_to(first_piece["start"] as Vector3) > 0.05:
		var seam: Variant = _piece_intersection(previous, first_piece)
		if seam is Vector3:
			_append_path_point(points, distances, seam as Vector3,
				seam_distance)
	var first_point: Vector3 = points[0]
	_append_path_point(points, distances, first_point, total)
	# Safety net: re-project anything the mitre could not place, so the
	# invariant holds even on a grid with adjacent corners.
	for index in points.size():
		var point: Vector3 = points[index]
		point = _push_to_clearance(spline, point, lateral)
		points[index] = point
	var lengths := PackedFloat32Array()
	lengths.resize(points.size())
	var travelled: float = 0.0
	if points.size() > 0:
		lengths[0] = 0.0
	for index in range(1, points.size()):
		travelled += points[index - 1].distance_to(points[index])
		lengths[index] = travelled
	return {"ok": points.size() >= 4 and travelled > 1.0,
		"points": points, "distances": distances, "lengths": lengths,
		"total_length": travelled, "lateral": lateral}


static func _empty_path(lateral: float) -> Dictionary:
	return {"ok": false, "points": PackedVector3Array(),
		"distances": PackedFloat32Array(), "lengths": PackedFloat32Array(),
		"total_length": 0.0, "lateral": lateral}


## One tile's contribution to a clearance path, or an empty dictionary on the
## inside of a corner where an offset would fold onto the road.
static func _clearance_piece(tile: Dictionary, side: float,
		lateral: float) -> Dictionary:
	var center: Vector3 = _cell_center(tile["cell"])
	var entry: int = int(tile["entry"])
	var exit: int = int(tile["exit"])
	var h_in: float = float(tile.get("height_in", 0.0))
	var h_out: float = float(tile.get("height_out", 0.0))
	var distance_in: float = float(tile.get("from", 0.0))
	var distance_out: float = float(tile.get("to", distance_in))
	var din: Vector3 = -_edge_3d(entry)
	var right: Vector3 = din.cross(Vector3.UP).normalized()
	var p_in: Vector3 = center + _edge_3d(entry) * HALF_TILE
	var p_out: Vector3 = center + _edge_3d(exit) * HALF_TILE
	if _opposite(entry) == exit:
		var a: Vector3 = p_in + right * (lateral * side) + Vector3.UP * h_in
		var b: Vector3 = p_out + right * (lateral * side) + Vector3.UP * h_out
		return {"kind": "line", "start": a, "end": b,
			"distance_in": distance_in, "distance_out": distance_out,
			"length": a.distance_to(b), "height_in": h_in, "height_out": h_out}
	var dout: Vector3 = _edge_3d(exit)
	var turn_right: bool = dout.is_equal_approx(_right_of(din))
	var inside: bool = (side >= 0.0) == turn_right
	var radius: float = HALF_TILE + lateral if not inside \
		else HALF_TILE - lateral
	if radius <= ROAD_HALF + 0.01:
		# The requested clearance does not fit inside this corner; the joining
		# mitre between the neighbouring edges is the correct path.
		return {}
	var corner: Vector3 = center + _edge_3d(entry) * HALF_TILE \
		+ _edge_3d(exit) * HALF_TILE
	var entry_angle: float = atan2(p_in.z - corner.z, p_in.x - corner.x)
	var exit_angle: float = atan2(p_out.z - corner.z, p_out.x - corner.x)
	var sweep: float = angle_difference(entry_angle, exit_angle)
	return _arc_piece(corner, radius, entry_angle, sweep, h_in, h_out,
		distance_in, distance_out)


static func _arc_piece(centre: Vector3, radius: float, start_angle: float,
		sweep: float, h_in: float, h_out: float, distance_in: float,
		distance_out: float) -> Dictionary:
	var start: Vector3 = centre + Vector3(cos(start_angle), 0.0,
		sin(start_angle)) * radius
	start.y = h_in
	var end_angle: float = start_angle + sweep
	var end: Vector3 = centre + Vector3(cos(end_angle), 0.0,
		sin(end_angle)) * radius
	end.y = h_out
	return {"kind": "arc", "start": start, "end": end,
		"centre": centre, "radius": radius, "start_angle": start_angle,
		"sweep": sweep, "length": absf(sweep) * radius,
		"height_in": h_in, "height_out": h_out,
		"distance_in": distance_in, "distance_out": distance_out}


## Appends a piece's samples to the path, skipping the first one because the
## join (or the previous piece's last sample) already placed it.
static func _append_piece_samples(points: PackedVector3Array,
		distances: PackedFloat32Array, piece: Dictionary,
		step: float) -> void:
	var length: float = maxf(float(piece.get("length", 0.0)), 0.01)
	var count: int = maxi(int(ceil(length / maxf(step, 0.05))), 1)
	for index in count + 1:
		var t: float = float(index) / float(count)
		var point: Vector3
		if str(piece["kind"]) == "line":
			point = (piece["start"] as Vector3).lerp(piece["end"] as Vector3, t)
		else:
			var angle: float = float(piece["start_angle"]) \
				+ float(piece["sweep"]) * t
			point = (piece["centre"] as Vector3) + Vector3(cos(angle), 0.0,
				sin(angle)) * float(piece["radius"])
			point.y = lerpf(float(piece["height_in"]),
				float(piece["height_out"]), t)
		if index == 0 and not points.is_empty():
			continue
		var distance: float = lerpf(float(piece["distance_in"]),
			float(piece["distance_out"]), t)
		_append_path_point(points, distances, point, distance)


static func _append_path_point(points: PackedVector3Array,
		distances: PackedFloat32Array, point: Vector3,
		distance: float) -> void:
	if not points.is_empty() \
			and points[points.size() - 1].distance_to(point) < 0.001:
		return
	points.append(point)
	distances.append(distance)


## Joins two consecutive pieces. When the tile between them folded, the two
## supporting curves are intersected to make a mitre at the corner; when they
## already touch, nothing is added.
static func _join_clearance_pieces(points: PackedVector3Array,
		distances: PackedFloat32Array, previous: Dictionary,
		current: Dictionary) -> void:
	var gap: float = (previous["end"] as Vector3).distance_to(
		current["start"] as Vector3)
	if gap < 0.05:
		return
	var joint: Variant = _piece_intersection(previous, current)
	if not (joint is Vector3):
		return
	var distance: float = (float(previous["distance_out"]) \
		+ float(current["distance_in"])) * 0.5
	_append_path_point(points, distances, joint as Vector3, distance)


## Intersection of two piece support curves, or null when they are parallel.
static func _piece_intersection(a: Dictionary, b: Dictionary) -> Variant:
	var a_arc: bool = str(a["kind"]) == "arc"
	var b_arc: bool = str(b["kind"]) == "arc"
	var candidates: Array[Vector3] = []
	if not a_arc and not b_arc:
		candidates = _line_intersections(a["start"], a["end"], b["start"],
			b["end"])
	elif a_arc and not b_arc:
		candidates = _line_circle_points(b["start"], b["end"], a["centre"],
			float(a["radius"]))
	elif not a_arc and b_arc:
		candidates = _line_circle_points(a["start"], a["end"], b["centre"],
			float(b["radius"]))
	else:
		candidates = _circle_intersections(a["centre"], float(a["radius"]),
			b["centre"], float(b["radius"]))
	if candidates.is_empty():
		return null
	var wanted: Vector3 = ((a["end"] as Vector3) + (b["start"] as Vector3)) * 0.5
	var best: Vector3 = candidates[0]
	var best_distance: float = INF
	for candidate: Vector3 in candidates:
		var distance: float = Vector2(candidate.x - wanted.x,
			candidate.z - wanted.z).length()
		if distance < best_distance:
			best_distance = distance
			best = candidate
	best.y = ((a["end"] as Vector3).y + (b["start"] as Vector3).y) * 0.5
	return best


static func _line_intersections(a0: Vector3, a1: Vector3, b0: Vector3,
		b1: Vector3) -> Array[Vector3]:
	var r := Vector2(a1.x - a0.x, a1.z - a0.z)
	var s := Vector2(b1.x - b0.x, b1.z - b0.z)
	var denominator: float = r.cross(s)
	if absf(denominator) < 0.0001:
		return []
	var t: float = Vector2(b0.x - a0.x, b0.z - a0.z).cross(s) / denominator
	return [Vector3(a0.x + r.x * t, 0.0, a0.z + r.y * t)]


static func _line_circle_points(line_a: Vector3, line_b: Vector3,
		centre: Vector3, radius: float) -> Array[Vector3]:
	var d := Vector2(line_b.x - line_a.x, line_b.z - line_a.z)
	var f := Vector2(line_a.x - centre.x, line_a.z - centre.z)
	var a: float = d.dot(d)
	var b: float = 2.0 * f.dot(d)
	var c: float = f.dot(f) - radius * radius
	var discriminant: float = b * b - 4.0 * a * c
	if a < 0.000001 or discriminant < 0.0:
		return []
	var root: float = sqrt(discriminant)
	var out: Array[Vector3] = []
	for t: float in [(-b - root) / (2.0 * a), (-b + root) / (2.0 * a)]:
		out.append(Vector3(line_a.x + d.x * t, 0.0, line_a.z + d.y * t))
	return out


static func _circle_intersections(c0: Vector3, r0: float, c1: Vector3,
		r1: float) -> Array[Vector3]:
	var offset := Vector2(c1.x - c0.x, c1.z - c0.z)
	var distance: float = offset.length()
	if distance < 0.0001 or distance > r0 + r1 or distance < absf(r0 - r1):
		return []
	var along: float = (r0 * r0 - r1 * r1 + distance * distance) \
		/ (2.0 * distance)
	var height: float = sqrt(maxf(r0 * r0 - along * along, 0.0))
	var direction: Vector2 = offset / distance
	var base: Vector2 = Vector2(c0.x, c0.z) + direction * along
	var normal := Vector2(-direction.y, direction.x)
	return [Vector3(base.x + normal.x * height, 0.0, base.y + normal.y * height),
		Vector3(base.x - normal.x * height, 0.0, base.y - normal.y * height)]


## Legacy/free-form splines have no tiles: offset the sampled centreline and
## project each point back out until it clears. Slower, and only used when a
## non-grid spline is handed to a kit helper.
static func _polyline_clearance_path(spline: RefCounted, side: float,
		lateral: float, step: float) -> Dictionary:
	if not spline.has_method("sample") or spline.get("total_length") == null:
		return _empty_path(lateral)
	var total: float = float(spline.get("total_length"))
	if total <= 1.0:
		return _empty_path(lateral)
	var sign_dir: float = 1.0 if side >= 0.0 else -1.0
	var count: int = maxi(int(ceil(total / maxf(step, 0.05))), 8)
	var points := PackedVector3Array()
	var distances := PackedFloat32Array()
	for index in count + 1:
		var distance: float = total * float(index) / float(count)
		var frame: Dictionary = spline.call("sample", distance)
		var point: Vector3 = (frame["position"] as Vector3) \
			+ (frame["right"] as Vector3) * (lateral * sign_dir)
		point = _push_to_clearance(spline, point, lateral)
		_append_path_point(points, distances, point, distance)
	var lengths := PackedFloat32Array()
	lengths.resize(points.size())
	var travelled: float = 0.0
	for index in range(1, points.size()):
		travelled += points[index - 1].distance_to(points[index])
		lengths[index] = travelled
	return {"ok": points.size() >= 4, "points": points,
		"distances": distances, "lengths": lengths,
		"total_length": travelled, "lateral": lateral}


## Moves a point outward until its plan distance to the centreline is at least
## `lateral`, never sideways into the road. This is the hard guarantee behind
## BARRIER_CLEARANCE: no sampled path point can end up on the racing surface.
static func _push_to_clearance(spline: RefCounted, point: Vector3,
		lateral: float) -> Vector3:
	var current: Vector3 = point
	for _attempt in 5:
		var hit: Dictionary = _plan_closest(spline, current)
		var distance: float = float(hit.get("distance", INF))
		if distance >= lateral - 0.005 or distance == INF:
			return current
		var nearest: Vector3 = hit.get("point", current) as Vector3
		var away := Vector3(current.x - nearest.x, 0.0, current.z - nearest.z)
		if away.length() < 0.001:
			away = Vector3.RIGHT
		current += away.normalized() * (lateral - distance + 0.01)
	return current


# --------------------------------------------------------------------------
# grid maths


static func _cell_center(cell: Vector2i) -> Vector3:
	return Vector3((float(cell.x) + 0.5) * TILE_SIZE, 0.0,
		(float(cell.y) + 0.5) * TILE_SIZE)


static func _edge_step(edge: int) -> Vector2i:
	match edge:
		EDGE_N:
			return Vector2i(0, -1)
		EDGE_E:
			return Vector2i(1, 0)
		EDGE_S:
			return Vector2i(0, 1)
		_:
			return Vector2i(-1, 0)


static func _edge_3d(edge: int) -> Vector3:
	match edge:
		EDGE_N:
			return Vector3(0.0, 0.0, -1.0)
		EDGE_E:
			return Vector3(1.0, 0.0, 0.0)
		EDGE_S:
			return Vector3(0.0, 0.0, 1.0)
		_:
			return Vector3(-1.0, 0.0, 0.0)


static func _edge_for(direction: Vector2i) -> int:
	if direction == Vector2i(0, -1):
		return EDGE_N
	if direction == Vector2i(1, 0):
		return EDGE_E
	if direction == Vector2i(0, 1):
		return EDGE_S
	return EDGE_W


static func _opposite(edge: int) -> int:
	return (edge + 2) % 4


static func _right_turn(direction: Vector2i) -> Vector2i:
	return Vector2i(-direction.y, direction.x)


static func _left_turn(direction: Vector2i) -> Vector2i:
	return Vector2i(direction.y, -direction.x)


static func _right_of(direction: Vector3) -> Vector3:
	return direction.cross(Vector3.UP).normalized()


static func _edge_name(edge: int) -> String:
	match edge:
		EDGE_N:
			return "north"
		EDGE_E:
			return "east"
		EDGE_S:
			return "south"
		_:
			return "west"


static func _edge_names(edges: Array[int]) -> String:
	var names := PackedStringArray()
	for edge: int in edges:
		names.append(_edge_name(edge))
	if names.is_empty():
		return "none"
	return ", ".join(names)


static func _theme_id(theme: Variant) -> String:
	if theme is String:
		return str(theme)
	if theme is Dictionary:
		return str((theme as Dictionary).get("id", "grid"))
	return "grid"
