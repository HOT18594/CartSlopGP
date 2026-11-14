extends RefCounted
## Grid bookkeeping for the Dockyard Quay theme.
##
## The Kenney grid spline reports every placed tile, so the theme never guesses
## where the track is: this plan turns those tiles into cell centres, free verge
## cells, straight runs and corner distances. A cell is (column, row) and its
## centre sits at ((col + 0.5) * TILE, 0, (row + 0.5) * TILE), which is the same
## lattice TileKit snaps to.
##
## grass_race still hands the old TrackSpline on maps that have not been wired
## to the grid engine yet. That spline has no `tiles` array, so the plan switches
## to arc-length slots snapped to the same 16 m lattice. Both paths place every
## prop on the lattice; only the source of the hinge points differs.

const TileKit := preload("res://scripts/minigames/tile_kit.gd")
const TrackDefs := preload("res://scripts/minigames/track_defs.gd")

const TILE: float = TileKit.TILE_SIZE
## A lattice prop must stay this far from the centreline. One cell of verge
## keeps the fence, signs and tree line clear of the barrier run.
const VERGE_CLEAR: float = TILE * 0.85
## Grid roads are painted on the kit's 0.02-unit slab, which the engine lifts to
## its measured top; the legacy ribbon sits at grass_race's ROAD_Y.
const GRID_ROAD_TOP: float = 0.33
const SPLINE_ROAD_TOP: float = 0.05

var spline: RefCounted
var total: float = 0.0
var grid: bool = false
var cols: int = 0
var rows: int = 0

var _track_cells: Dictionary = {}
var _used_cells: Dictionary = {}
var _tile_list: Array[Dictionary] = []
var _track_low: Vector2i = Vector2i(999999, 999999)
var _track_high: Vector2i = Vector2i(-1, -1)
var _straights: Array[Dictionary] = []
var _corners: Array[Dictionary] = []
var _centre: Vector3 = Vector3.ZERO
var _grid_cols: int = 0
var _grid_rows: int = 0


## `grid_cols` / `grid_rows` are the known ASCII dimensions from the grid stats
## on the race root. They keep the plan correct when the layout file is newer
## than the registry copy: the engine built a 12 x 10 grid, so the plan must
## measure that grid, not whatever the registry still says.
func _init(track_spline: RefCounted, grid_cols: int = 0,
		grid_rows: int = 0) -> void:
	spline = track_spline
	_grid_cols = grid_cols
	_grid_rows = grid_rows
	if spline == null:
		return
	total = maxf(float(spline.get("total_length")), 0.001)
	_read_tiles()
	_centre = _bounds_centre()
	_straights = _find_straights()
	_corners = _find_corners()


# --------------------------------------------------------------------------
# cells


## True when the spline came from KenneyTiles and every backing point is a
## placed ASCII cell.
func is_grid() -> bool:
	return grid


## Tile character the lap uses at `cell`, or "X" when the cell is not a tile.
func tile_char(cell: Vector2i) -> String:
	for tile: Dictionary in _tile_list:
		if tile.get("cell", Vector2i(-1, -1)) == cell:
			return str(tile.get("tile", "X"))
	return "X"


## Cells carrying `kind`, in lap order. Used by the theme to react to the grid:
## a crossing ('C'), a jump ramp ('J') or a corner change the dressing without a
## hard-coded coordinate anywhere.
func tile_cells(kind: String) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for tile: Dictionary in _tile_list:
		if str(tile.get("tile", "X")) == kind:
			cells.append(tile.get("cell", Vector2i(-1, -1)) as Vector2i)
	return cells


## Placed tile at a lap distance, or an empty dictionary.
func tile_at(distance: float) -> Dictionary:
	for tile: Dictionary in _tile_list:
		if distance >= float(tile.get("from", 0.0)) \
				and distance < float(tile.get("to", 0.0)):
			return tile
	return {}


## Lap arc distance at the middle of the placed tile on `cell`. Returns -1.0
## when the cell is not part of the lap.
func tile_distance(cell: Vector2i) -> float:
	for tile: Dictionary in _tile_list:
		if tile.get("cell", Vector2i(-1, -1)) != cell:
			continue
		var from: float = float(tile.get("from", 0.0))
		var to: float = float(tile.get("to", from))
		return fposmod(from + fposmod(to - from, total) * 0.5, total)
	return -1.0


## Road deck height of a placed cell, in metres. Zero on a flat grid.
func cell_road_height(cell: Vector2i) -> float:
	var heights: Variant = spline.get("heights")
	if heights is Dictionary:
		return float((heights as Dictionary).get(cell, 0.0))
	return 0.0


## Highest road deck on the lap, in metres. Zero on a flat grid.
func max_road_height() -> float:
	var highest: float = 0.0
	for tile: Dictionary in _tile_list:
		highest = maxf(highest, float(tile.get("height", 0.0)))
	return highest


## Road deck height nearest a world point, in metres. Props beside a raised
## section climb with it instead of floating at world zero.
func road_height_at(point: Vector3) -> float:
	if spline == null:
		return 0.0
	var hit: Dictionary = spline.closest(point)
	var surface: Vector3 = hit.get("point", Vector3.ZERO) as Vector3
	return surface.y


## Free off-track cells, nearest the plan centre first. The planning bucket the
## yard, quay and treeline all draw from.
func free_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for row in rows:
		for col in cols:
			var cell := Vector2i(col, row)
			if is_free(cell):
				cells.append(cell)
	var centre := _centre
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return cell_point(a).distance_squared_to(centre) \
			< cell_point(b).distance_squared_to(centre))
	return cells


## Centre of a lattice cell, exactly where the tile engine puts a road piece.
func cell_point(cell: Vector2i) -> Vector3:
	return Vector3((float(cell.x) + 0.5) * TILE, 0.0,
		(float(cell.y) + 0.5) * TILE)


## True when the cell is inside the parsed ASCII grid.
func in_grid(cell: Vector2i) -> bool:
	return grid and cell.x >= 0 and cell.y >= 0 \
		and cell.x < cols and cell.y < rows


## True when a drivable tile occupies the cell.
func is_track(cell: Vector2i) -> bool:
	return _track_cells.has(cell)


## True when the cell is a free, off-track lattice cell of the parsed grid.
func is_free(cell: Vector2i) -> bool:
	return in_grid(cell) and not _track_cells.has(cell) \
		and not _used_cells.has(cell)


## Claims an off-track cell. Returns false when it is a tile, already dressed
## or outside the parsed grid, so callers can pack a run without half overlaps.
func take(cell: Vector2i) -> bool:
	if not is_free(cell):
		return false
	_used_cells[cell] = true
	return true


## Claims a cell unconditionally, including the lattice rings outside the
## parsed grid. Used by the mooring clutter so the treeline cannot grow through
## a beached canoe.
func mark(cell: Vector2i) -> void:
	_used_cells[cell] = true


## True when a cell is already claimed, including the rings outside the grid.
func is_used(cell: Vector2i) -> bool:
	return _used_cells.has(cell)


## True for the outermost lattice ring. The yard leaves it free for the quay
## edge furniture (floodlights, signs, offices, wharf) instead of burying it in
## container blocks.
func is_outer_band(cell: Vector2i) -> bool:
	if not grid:
		return false
	return cell.x == 0 or cell.y == 0 or cell.x == cols - 1 \
		or cell.y == rows - 1


## True for the ring the catch fence occupies (one cell outside the track box).
func is_ring_cell(cell: Vector2i) -> bool:
	return _is_ring_cell(cell)


## Claims the cell containing a world point. Used by the legacy spline path,
## where prop positions come from arc length rather than an ASCII cell.
func take_point(point: Vector3, clearance: float = VERGE_CLEAR) -> bool:
	var cell := Vector2i(int(floor(point.x / TILE)),
		int(floor(point.z / TILE)))
	if _used_cells.has(cell):
		return false
	if grid and (not in_grid(cell) or _track_cells.has(cell)):
		return false
	if TileKit.spline_distance(spline, point) < clearance:
		return false
	_used_cells[cell] = true
	return true


## Claims only the fence-ring cells within `radius` of `cell`. A one-off
## grandstand placed by arc distance uses this to clear the two fence pieces it
## overlaps without taking the outer verge cells the signage needs.
func reserve_ring_area(cell: Vector2i, radius: int = 1) -> void:
	for row in range(cell.y - radius, cell.y + radius + 1):
		for col in range(cell.x - radius, cell.x + radius + 1):
			var probe := Vector2i(col, row)
			if _is_ring_cell(probe):
				_used_cells[probe] = true


## True for the ring the catch fence occupies: one cell outside the box the
## track cells actually span, clipped to the parsed grid. Deriving it from the
## track bounds keeps the fence beside the road when the layout file puts tiles
## on a different row than the old fixed ring.
func _is_ring_cell(cell: Vector2i) -> bool:
	if not grid or _track_high.x < 0:
		return false
	var top: int = maxi(_track_low.y - 1, 0)
	var bottom: int = mini(_track_high.y + 1, rows - 1)
	var left: int = maxi(_track_low.x - 1, 0)
	var right: int = mini(_track_high.x + 1, cols - 1)
	if cell.y == top or cell.y == bottom:
		return cell.x >= left and cell.x <= right
	if cell.x == left or cell.x == right:
		return cell.y >= top and cell.y <= bottom
	return false


## Claims and returns the centres of up to `limit` free candidate cells.
func take_cells(candidates: Array, limit: int = 0) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for entry: Variant in candidates:
		if limit > 0 and points.size() >= limit:
			break
		if not (entry is Vector2i):
			continue
		var cell: Vector2i = entry
		if take(cell):
			points.append(cell_point(cell))
	return points


## Cells on the fence line: the ring one cell outside the loop's bounding box
## edges. Empty on the legacy spline path.
func ring_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not grid or cols < 5 or rows < 5 or _track_high.x < 0:
		return cells
	var top: int = maxi(_track_low.y - 1, 0)
	var bottom: int = mini(_track_high.y + 1, rows - 1)
	var left: int = maxi(_track_low.x - 1, 0)
	var right: int = mini(_track_high.x + 1, cols - 1)
	for col in range(left + 1, right):
		cells.append(Vector2i(col, top))
		cells.append(Vector2i(col, bottom))
	for row in range(top + 1, bottom):
		cells.append(Vector2i(left, row))
		cells.append(Vector2i(right, row))
	return cells


## Outermost lattice cells of the parsed grid: the band the quay signs,
## floodlights and first tree row share.
func outer_band_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not grid:
		return cells
	for col in cols:
		cells.append(Vector2i(col, 0))
		cells.append(Vector2i(col, rows - 1))
	for row in range(1, rows - 1):
		cells.append(Vector2i(0, row))
		cells.append(Vector2i(cols - 1, row))
	return cells


## One more lattice ring outside the parsed grid, so the treeline gains depth
## without crowding the fence. The ground apron covers this ring.
func beyond_band_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not grid:
		return cells
	for col in range(-1, cols + 1):
		cells.append(Vector2i(col, -1))
		cells.append(Vector2i(col, rows))
	for row in rows:
		cells.append(Vector2i(-1, row))
		cells.append(Vector2i(cols, row))
	return cells


## Two more lattice rings outside the parsed grid. The apron plane is 2200 m, so
## the horizon can hold a dense treeline without new ground.
func far_band_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not grid:
		return cells
	for ring in range(2, 4):
		for col in range(-ring, cols + ring):
			cells.append(Vector2i(col, -ring))
			cells.append(Vector2i(col, rows - 1 + ring))
		for row in range(-ring + 1, rows - 1 + ring):
			cells.append(Vector2i(-ring, row))
			cells.append(Vector2i(cols - 1 + ring, row))
	return cells


## Claims up to `limit` tree cells, outer ring first and further rings second.
func tree_points(limit: int) -> Array[Vector3]:
	var candidates: Array[Vector2i] = outer_band_cells()
	candidates.append_array(beyond_band_cells())
	candidates.append_array(far_band_cells())
	var points: Array[Vector3] = []
	for cell: Vector2i in candidates:
		if points.size() >= limit:
			break
		if _track_cells.has(cell) or _used_cells.has(cell):
			continue
		var point: Vector3 = cell_point(cell)
		if TileKit.spline_distance(spline, point) < VERGE_CLEAR:
			continue
		_used_cells[cell] = true
		points.append(point)
	return points


# --------------------------------------------------------------------------
# runs and corners


## Straight-through runs of the lap, in lap order, as {from, to, length}.
## Grid tiles give the exact edges; the legacy spline is scanned for the flattest
## stretches so the yard and gantries still land on something road-like.
func straight_runs() -> Array[Dictionary]:
	return _straights.duplicate(true)


## The corner tiles (or the tightest bends on the legacy spline), scored by how
## far they sit from the circuit centre so the four hairpins win over the chicane.
## Returns at most `count` entries as {distance, curve}.
func major_corners(count: int) -> Array[Dictionary]:
	var ranked: Array[Dictionary] = []
	for corner: Dictionary in _corners:
		var frame: Dictionary = spline.sample(float(corner["distance"]))
		var point: Vector3 = frame["position"]
		ranked.append({
			"distance": float(corner["distance"]),
			"curve": float(corner["curve"]),
			"score": point.distance_to(_centre),
		})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"]))
	var picked: Array[Dictionary] = []
	for corner: Dictionary in ranked:
		if picked.size() >= count:
			break
		var clear: bool = true
		for other: Dictionary in picked:
			var gap: float = absf(fposmod(
				float(corner["distance"]) - float(other["distance"]) + total * 0.5,
				total) - total * 0.5)
			if gap < 24.0:
				clear = false
				break
		if clear:
			picked.append(corner)
	return picked


# --------------------------------------------------------------------------
# arc helpers (legacy spline path)


## Snapped lattice slots along the lap, `lateral` metres to either side of the
## centreline. Every point is claimed before it is returned, so small-scale
## dressing and the treeline can share one lap without stacking props.
func arc_slots(spacing: float, lateral: float, both_sides: bool = true,
		clearance: float = VERGE_CLEAR) -> Array[Vector3]:
	var points: Array[Vector3] = []
	if spline == null or total <= 0.0:
		return points
	var step: float = maxf(spacing, 1.0)
	var sides: Array[float] = [1.0]
	if both_sides:
		sides.append(-1.0)
	var distance: float = step * 0.5
	while distance < total:
		var frame: Dictionary = spline.sample(distance)
		var base: Vector3 = frame["position"]
		var right: Vector3 = frame["right"]
		for side: float in sides:
			var raw: Vector3 = base + right * (lateral * side)
			var point: Vector3 = TileKit._snap_point(raw)
			if take_point(point, clearance):
				points.append(point)
		distance += step
	return points


## Yaw that maps a model's local +X (its long axis) onto the track forward.
func across_yaw(distance: float) -> float:
	var forward: Vector3 = spline.sample(distance)["forward"]
	return atan2(-forward.z, forward.x)


## Yaw that maps a road piece's local -Z (travel) onto the track forward.
func along_yaw(distance: float) -> float:
	var forward: Vector3 = spline.sample(distance)["forward"]
	return atan2(-forward.x, -forward.z)


## Signed turning rate, positive for a left-hander. The outside of a corner is
## +1 for a positive curve and -1 for a negative one, matching the old kit.
func curve_at(distance: float) -> float:
	var before: float = float(spline.yaw_at(distance - 8.0))
	var after: float = float(spline.yaw_at(distance + 8.0))
	return wrapf(after - before, -PI, PI)


## Height of the visible road surface. The wet patch and its puddles sit on it.
func road_surface_y() -> float:
	return GRID_ROAD_TOP if grid else SPLINE_ROAD_TOP


## Centre of the circuit in world space.
func centre() -> Vector3:
	return _centre


# --------------------------------------------------------------------------
# internals


func _read_tiles() -> void:
	var raw: Variant = spline.get("tiles")
	if not (raw is Array) or (raw as Array).is_empty():
		return
	grid = true
	for entry: Variant in raw as Array:
		if not (entry is Dictionary):
			continue
		var tile: Dictionary = entry as Dictionary
		var raw_cell: Variant = tile.get("cell", Vector2i(-1, -1))
		if not (raw_cell is Vector2i):
			continue
		var cell: Vector2i = raw_cell
		if cell.x < 0 or cell.y < 0:
			continue
		_tile_list.append(tile)
		_track_cells[cell] = true
		_track_low.x = mini(_track_low.x, cell.x)
		_track_low.y = mini(_track_low.y, cell.y)
		_track_high.x = maxi(_track_high.x, cell.x)
		_track_high.y = maxi(_track_high.y, cell.y)
		cols = maxi(cols, cell.x + 1)
		rows = maxi(rows, cell.y + 1)
	# The parsed tiles only reach the outermost track column and row; the grid's
	# empty border is what the signs and treeline use, so take the real ASCII
	# size from the grid stats when the caller has them, then from the registry.
	if _grid_cols > 0 and _grid_rows > 0:
		cols = _grid_cols
		rows = _grid_rows
	else:
		var preset: Dictionary = TrackDefs.get_preset("dockyard")
		var rows_text: PackedStringArray = TrackDefs.grid_of(preset)
		if not rows_text.is_empty():
			rows = rows_text.size()
			for line: String in rows_text:
				cols = maxi(cols, line.length())
	if cols <= 0 or rows <= 0:
		# A spline with tiles but no usable cells is not a grid map.
		grid = false


func _bounds_centre() -> Vector3:
	if grid:
		return Vector3(float(cols) * TILE * 0.5, 0.0,
			float(rows) * TILE * 0.5)
	var raw: Variant = spline.get("points")
	if raw is PackedVector3Array:
		var points: PackedVector3Array = raw
		if not points.is_empty():
			var low: Vector3 = points[0]
			var high: Vector3 = points[0]
			for point: Vector3 in points:
				low = low.min(point)
				high = high.max(point)
			var centre := (low + high) * 0.5
			centre.y = 0.0
			return centre
	return Vector3.ZERO


func _is_straight_tile(tile: Dictionary) -> bool:
	var entry: int = int(tile.get("entry", 0))
	var exit: int = int(tile.get("exit", 0))
	return (entry + 2) % 4 == exit


func _find_straights() -> Array[Dictionary]:
	var runs: Array[Dictionary] = []
	if grid:
		var current: Dictionary = {}
		for tile: Dictionary in _tile_list:
			var from: float = float(tile.get("from", 0.0))
			var to: float = float(tile.get("to", from))
			if _is_straight_tile(tile):
				if current.is_empty():
					current = {"from": from, "to": to, "cells": []}
				current["to"] = to
				(current["cells"] as Array).append(tile.get("cell", Vector2i(-1, -1)))
			elif not current.is_empty():
				runs.append(current)
				current = {}
		if not current.is_empty():
			runs.append(current)
		_merge_seam(runs)
	else:
		runs = _scan_straights()
	var result: Array[Dictionary] = []
	for run: Dictionary in runs:
		var span: float = fposmod(float(run["to"]) - float(run["from"]), total)
		if span < TILE * 0.5:
			continue
		result.append({
			"from": float(run["from"]),
			"to": float(run["to"]),
			"length": span,
			"cells": (run.get("cells", []) as Array).duplicate(),
		})
	return result


func _merge_seam(runs: Array[Dictionary]) -> void:
	if runs.size() < 2:
		return
	var first: Dictionary = runs[0]
	var last: Dictionary = runs[runs.size() - 1]
	if float(first["from"]) > 0.5:
		return
	if float(last["to"]) < total - 0.5:
		return
	first["from"] = float(last["from"])
	var seam_cells: Array = (last.get("cells", []) as Array).duplicate()
	seam_cells.append_array(first.get("cells", []) as Array)
	first["cells"] = seam_cells
	runs.remove_at(runs.size() - 1)


func _scan_straights() -> Array[Dictionary]:
	var runs: Array[Dictionary] = []
	var step: float = 8.0
	var distance: float = 0.0
	var start: float = -1.0
	while distance < total:
		var flat: bool = absf(float(spline.curvature_at(distance, 10.0))) < 0.010
		if flat and start < 0.0:
			start = distance
		elif not flat and start >= 0.0:
			runs.append({"from": start, "to": distance})
			start = -1.0
		distance += step
	if start >= 0.0:
		runs.append({"from": start, "to": total})
	if runs.is_empty():
		# A wobbly circuit still needs one yard stretch: take the flattest 96 m.
		var best_distance: float = 0.0
		var best_curve: float = INF
		distance = 0.0
		while distance < total:
			var curve: float = absf(float(spline.curvature_at(distance, 10.0)))
			if curve < best_curve:
				best_curve = curve
				best_distance = distance
			distance += step
		var half: float = minf(total * 0.18, 48.0)
		runs.append({
			"from": fposmod(best_distance - half, total),
			"to": fposmod(best_distance + half, total),
		})
	_merge_seam(runs)
	return runs


func _find_corners() -> Array[Dictionary]:
	var corners: Array[Dictionary] = []
	if grid:
		var raw: Variant = spline.get("tiles")
		if raw is Array:
			for entry: Variant in raw as Array:
				if not (entry is Dictionary):
					continue
				var tile: Dictionary = entry as Dictionary
				var tile_char: String = str(tile.get("tile", "X"))
				if tile_char != "L" and tile_char != "R" and tile_char != "W":
					continue
				var from: float = float(tile.get("from", 0.0))
				var to: float = float(tile.get("to", from))
				var mid: float = from + fposmod(to - from, total) * 0.5
				corners.append({
					"distance": mid,
					"curve": curve_at(mid),
				})
	else:
		corners = _scan_corners()
	return corners


func _scan_corners() -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var distance: float = 12.0
	while distance < total - 12.0:
		var curve: float = curve_at(distance)
		if absf(curve) > 0.14:
			candidates.append({"distance": distance, "curve": curve})
		distance += 8.0
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return absf(float(a["curve"])) > absf(float(b["curve"])))
	var picked: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		var clear: bool = true
		for other: Dictionary in picked:
			var gap: float = absf(fposmod(
				float(candidate["distance"]) - float(other["distance"]) + total * 0.5,
				total) - total * 0.5)
			if gap < 55.0:
				clear = false
				break
		if clear:
			picked.append(candidate)
		if picked.size() >= 4:
			break
	return picked
