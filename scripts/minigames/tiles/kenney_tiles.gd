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

	var tiles: Array[Dictionary] = _make_tiles(best, grid)
	var points: PackedVector3Array = _build_points(tiles, best)
	if points.size() < 8:
		push_error("KenneyTiles: the grid flattened to %d spline points; a lap needs at least 8. Is the loop only one or two cells long?" % points.size())
		return null

	var spline := GridSpline.new(points, tiles, ROAD_HALF)
	var gap: Dictionary = best.get("gap", {})
	if bool(gap.get("ok", false)):
		spline.gap_length = float(gap.get("length", 0.0))
	if not spline.is_closed():
		push_error("KenneyTiles: the grid produced a degenerate lap (%.1f m, %d points). Every loop needs at least four cells." % [
			spline.total_length, points.size()])
		return null

	_fill_tile_distances(spline)
	_build_road(parent, tiles)
	_build_road_collision(parent, tiles)

	var theme_id: String = _theme_id(theme)
	parent.set_meta("kenney_spline", spline)
	parent.set_meta("kenney_grid_stats", {
		"theme": theme_id,
		"tiles": tiles.size(),
		"length": spline.total_length,
		"gap": spline.gap_length,
		"rows": height,
		"cols": width,
		"start_cell": start,
	})
	print("KENNEY GRID %s: %d tiles, %.1f m lap, %d rows x %d cols%s" % [
		theme_id, tiles.size(), spline.total_length, height, width,
		"" if spline.gap_length <= 0.0 \
			else " (closed a %.1f m gap)" % spline.gap_length])
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
	return {"ok": true, "length": length, "from": from, "to": to}


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


static func _make_tiles(best: Dictionary, grid: Dictionary) -> Array[Dictionary]:
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
		best: Dictionary) -> PackedVector3Array:
	var points := PackedVector3Array()
	for index in tiles.size():
		var tile: Dictionary = tiles[index]
		var center: Vector3 = _cell_center(tile["cell"])
		var entry: int = int(tile["entry"])
		var exit: int = int(tile["exit"])
		var local: PackedVector3Array = _segment_points(center, entry, exit,
			str(tile["tile"]))
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
		var steps: int = maxi(int(ceil(from.distance_to(to) / CLOSE_STEP)), 2)
		for step in range(1, steps + 1):
			_append_point(points, from.lerp(to, float(step) / float(steps)))
	if points.size() > 1 \
			and points[0].distance_to(points[points.size() - 1]) < 0.05:
		points.remove_at(points.size() - 1)
	return points


static func _segment_points(center: Vector3, entry: int, exit: int,
		tile: String) -> PackedVector3Array:
	var local := PackedVector3Array()
	var p_in: Vector3 = center + _edge_3d(entry) * HALF_TILE
	var p_out: Vector3 = center + _edge_3d(exit) * HALF_TILE
	if _opposite(entry) == exit:
		for step in STRAIGHT_STEPS + 1:
			local.append(p_in.lerp(p_out, float(step) / float(STRAIGHT_STEPS)))
		return local
	if tile == "W":
		for step in WIDE_STEPS + 1:
			var t: float = float(step) / float(WIDE_STEPS)
			var a: Vector3 = p_in.lerp(center, t)
			var b: Vector3 = center.lerp(p_out, t)
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
		local.append(Vector3(corner.x + cos(angle) * HALF_TILE, center.y,
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


static func _build_road(parent: Node3D, tiles: Array[Dictionary]) -> void:
	var holder := Node3D.new()
	holder.name = HOLDER_NAME
	parent.add_child(holder)
	var batches: Dictionary = {}
	for tile: Dictionary in tiles:
		var tile_char: String = str(tile["tile"])
		var center: Vector3 = _cell_center(tile["cell"])
		var yaw: float = float(tile["yaw"])
		var model: String = TileCatalog.START_MODEL \
			if bool(tile["start"]) and _is_straight_char(tile_char) \
			else TileCatalog.road_model(tile_char)
		var scale: Vector3 = TileCatalog.road_scale(tile_char) * TILE_SIZE
		if model == TileCatalog.START_MODEL:
			scale = Vector3.ONE * TILE_SIZE
		_add_batch(batches, model, _fit_transform(model, center, yaw, scale))
		if tile_char == "C":
			# Two straights crossing on the same cell: the read of a junction
			# without a 2x2 piece that would spill into the neighbours. The
			# cross arm is lifted 12 mm so the two coplanar verge slabs cannot
			# z-fight in the overlap.
			_add_batch(batches, TileCatalog.road_model("S"),
				_fit_transform(TileCatalog.road_model("S"),
					center + Vector3.UP * 0.012, yaw + PI * 0.5,
					Vector3.ONE * TILE_SIZE))
	for model: String in batches:
		_batch_model(holder, model, batches[model] as Array, "Road_" + model,
			false)


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
		tiles: Array[Dictionary]) -> void:
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
		if tile_char == "J" or tile_char == "B":
			_append_ramp_faces(ramp_faces, tile, tile_char == "B")
		else:
			_add_box_shape(body, Transform3D(Basis.IDENTITY,
				center + Vector3.DOWN * (ROAD_THICKNESS * 0.5)),
				Vector3(TILE_SIZE, ROAD_THICKNESS, TILE_SIZE))
	if not ramp_faces.is_empty():
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(ramp_faces)
		shape.backface_collision = true
		var collision := CollisionShape3D.new()
		collision.name = "Ramps"
		collision.shape = shape
		body.add_child(collision)


## Jump cells get a wedge that rises to the exit; bump cells get a hump. Both
## match the visible Kenney road piece, so the kart drives the slope it sees.
static func _append_ramp_faces(faces: PackedVector3Array, tile: Dictionary,
		hump: bool) -> void:
	var center: Vector3 = _cell_center(tile["cell"])
	var din: Vector3 = -_edge_3d(int(tile["entry"]))
	var right: Vector3 = din.cross(Vector3.UP).normalized()
	var entry_center: Vector3 = center - din * HALF_TILE
	var exit_center: Vector3 = center + din * HALF_TILE
	var e_l: Vector3 = entry_center - right * ROAD_HALF
	var e_r: Vector3 = entry_center + right * ROAD_HALF
	var x_l: Vector3 = exit_center - right * ROAD_HALF
	var x_r: Vector3 = exit_center + right * ROAD_HALF
	var height: float = _bump_face_height() if hump else _ramp_face_height()
	if hump:
		var m_l: Vector3 = center - right * ROAD_HALF + Vector3.UP * height
		var m_r: Vector3 = center + right * ROAD_HALF + Vector3.UP * height
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
