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
## `tiles`, `tile_at`, `cell_at`, `surface_at`, `half_width_at`, `gap_length`,
## `height_at`, `plan_distance`.
##
## Map contract (see also scripts/minigames/tile_kit.gd):
##   maps/<id>_theme.gd :  static func build(race: Node3D, spline) -> void
## The theme dresses the map with tile_kit.* and returns nothing. This engine
## owns the road, its colliders and the spline.
##
## Elevation is opt-in: a map may carry per-cell heights (`heights` grid or a
## smooth `elevation` profile, read from the theme dictionary or from its
## registry preset). The spline points, the road pieces and the road colliders
## then all follow the slope, a raised straight gets the kit's bridge support
## and jump/bump cells keep their wedge and hump. A grid without height data is
## built exactly as before, so every existing map stays flat.
##
## On an elevated grid a rigid pitched slab cannot join a neighbour: a Kenney
## corner is a quarter annulus, so pitching it makes its exit edge slope across
## the lane. Every road vertex is instead warped onto the tile's own entry/exit
## heights, which makes both edge rows of a seam identical; the same warped top
## triangles become the road collider. `KENNEY SEAMS` / `KENNEY DRIVE` print the
## measured gap, height step and normal jump once per circuit at boot, and the
## loop closure error, so a broken lap is visible without driving it.
##
## Jump/bump tiles keep the modular wedge, but now sit on a solid base with
## outer side walls and a painted lip, and a merged trackside detail pass (kerb
## line, advertising hoardings, corner markers, no colliders) dresses the walls
## for every circuit.
##
## Clearance helpers (`clearance_path`, `plan_clearance`) walk the real road
## edge geometry at a constant lateral distance and return a path a barrier or a
## terrain bank can follow without ever being placed on the racing surface, even
## around the inside of an 8 m corner. tile_kit.barrier_line and
## tile_kit.terrain_banks are built on them.
##
## Wiring (the race scene, not this file, does it once per race):
##   _spline = KenneyTiles.build(self, TrackDefs.grid_of(preset),
##       {"id": TrackDefs.theme_id_of(preset)})
## then grass_race hands that returned spline to the preset's theme build().
## Until that call exists the race keeps sampling the old TrackSpline and the
## grid engine is only exercised by the headless harness.
##
## Every road cell collides on CollisionLayers.WORLD with a box (tilted on an
## elevated grid), and jump/bump cells get a real wedge/hump concave shape
## instead of a box so a kart drives up the slope it sees.
##
## Z-FIGHTING LADDER (mirrored from tile_kit.gd, which owns the policy):
## ground -0.020 m, road 0.000 m, decal +0.012 m, prop +0.024 m. Road pieces
## stay on ROAD_SURFACE, the crossing's second arm moves up to Z_DECAL instead of a
## magic number, and a deferred TileKit audit finishes the map once the theme
## has added its props.

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
## Stacking rungs shared with tile_kit.gd; keep the two ladders identical.
const Z_GROUND: float = -0.020
const Z_ROAD: float = 0.000
const Z_DECAL: float = 0.012
const Z_PROP: float = 0.024
## The Kenney lane plane rides this far above the spline. The race's legacy
## dirt ribbon sits at +0.04, so the tiled road wins the visible surface and its
## watertight collider owns the floor; keep this in sync with TileCatalog.
const ROAD_SURFACE: float = TileCatalog.ROAD_SURFACE

## Watertight seam budget. A shared road edge must match in plan and height to
## within this many metres; the boot report prints the measured maximum.
const SEAM_TOLERANCE: float = 0.005
## A ramp/jump tile is a solid structure: base block, two outer walls and a
## painted lip band. The walls sit outside the 11.04 m lane, so they can never
## catch a cart on the join, and they carry no collider (detail only).
const RAMP_BASE_DEPTH: float = 0.62
const RAMP_WALL_LATERAL: float = ROAD_HALF + 0.96
const RAMP_WALL_THICKNESS: float = 0.36
const RAMP_WALL_LIFT: float = 0.45
const RAMP_LIP_HEIGHT: float = 0.65
const RAMP_LIP_BAND: float = 0.54

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

## Cached visible top-surface profiles of the jump/bump pieces, keyed by
## "tile_char:rows". Measured once from the GLB so the collider follows the art.
static var _ramp_profiles: Dictionary = {}


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

	## Plan-view bucket edge, in metres, for the nearest-point index below.
	const BUCKET_SIZE: float = 16.0

	var _count: int = 0
	## Plan-view segment buckets: Vector2i(x/z cell) -> PackedInt32Array of
	## segment indices whose plan footprint touches that cell. Nearest-point
	## queries are on every prop-clearance path and one `clearance_path()` asks
	## thousands of them, so a straight scan of the whole centreline per query
	## (93 us on the 402-sample Glacier lap) dominated map build time.
	var _buckets: Dictionary = {}
	var _bucket_low: Vector2i = Vector2i.ZERO
	var _bucket_high: Vector2i = Vector2i.ZERO
	## Scratch register for the shared nearest-point search, so plan_distance()
	## can answer without allocating a Dictionary per query.
	var _found_sq: float = INF
	var _found_s: float = 0.0
	var _found_distance: float = INF
	var _found_point: Vector3 = Vector3.ZERO

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
		_build_buckets()


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
		_search(world_position, false)
		return {"s": _found_s, "distance": _found_distance,
			"point": _found_point}


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
		_search(world_position, true)
		return _found_distance


	## Nearest centreline point in plan view: {s, distance, point}.
	func plan_closest(world_position: Vector3) -> Dictionary:
		_search(world_position, true)
		return {"s": _found_s, "distance": _found_distance,
			"point": _found_point}


	# ----------------------------------------------------------------------
	# nearest-point index
	# ----------------------------------------------------------------------


	## Registers every centreline segment in each plan bucket its bounding box
	## touches. Built once per spline; the steady-state query path only reads it.
	func _build_buckets() -> void:
		if _count < 2:
			return
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		for index in _count:
			var point: Vector3 = points[index]
			low.x = minf(low.x, point.x)
			low.y = minf(low.y, point.z)
			high.x = maxf(high.x, point.x)
			high.y = maxf(high.y, point.z)
		_bucket_low = Vector2i(int(floor(low.x / BUCKET_SIZE)),
			int(floor(low.y / BUCKET_SIZE)))
		_bucket_high = Vector2i(int(floor(high.x / BUCKET_SIZE)),
			int(floor(high.y / BUCKET_SIZE)))
		for index in _count:
			var a: Vector3 = points[index]
			var b: Vector3 = points[(index + 1) % _count]
			var min_x: int = int(floor(minf(a.x, b.x) / BUCKET_SIZE))
			var max_x: int = int(floor(maxf(a.x, b.x) / BUCKET_SIZE))
			var min_z: int = int(floor(minf(a.z, b.z) / BUCKET_SIZE))
			var max_z: int = int(floor(maxf(a.z, b.z) / BUCKET_SIZE))
			for cell_x in range(min_x, max_x + 1):
				for cell_z in range(min_z, max_z + 1):
					var key := Vector2i(cell_x, cell_z)
					var bucket: PackedInt32Array = _buckets.get(key,
						PackedInt32Array())
					bucket.append(index)
					_buckets[key] = bucket


	## Single nearest-centreline search shared by closest(), plan_closest() and
	## plan_distance(). Writes {_found_s, _found_distance, _found_point}.
	##
	## `plan_only` measures in plan view (the clearance contract); otherwise the
	## true 3D distance is used. The result is exact: the ring walk only stops
	## once every bucket it has not visited is provably farther away than the
	## best match in the register.
	func _search(world_position: Vector3, plan_only: bool) -> void:
		_found_sq = INF
		_found_s = 0.0
		_found_distance = INF
		_found_point = Vector3.ZERO
		if _count == 0:
			return
		if _buckets.is_empty():
			_scan_whole_polyline(world_position, plan_only)
			return
		var centre := Vector2i(int(floor(world_position.x / BUCKET_SIZE)),
			int(floor(world_position.z / BUCKET_SIZE)))
		# First ring that can hold a bucket, and the last one that can: a ring is
		# a Chebyshev distance, so these are exact bounds on the occupied square.
		var ring: int = 0
		if centre.x < _bucket_low.x:
			ring = _bucket_low.x - centre.x
		elif centre.x > _bucket_high.x:
			ring = centre.x - _bucket_high.x
		if centre.y < _bucket_low.y:
			ring = maxi(ring, _bucket_low.y - centre.y)
		elif centre.y > _bucket_high.y:
			ring = maxi(ring, centre.y - _bucket_high.y)
		var last_ring: int = maxi(
			maxi(absi(centre.x - _bucket_low.x), absi(centre.x - _bucket_high.x)),
			maxi(absi(centre.y - _bucket_low.y), absi(centre.y - _bucket_high.y)))
		while ring <= last_ring:
			var candidates := PackedInt32Array()
			_ring_indices(centre, ring, candidates)
			for index in candidates:
				_evaluate_segment(index, world_position, plan_only)
			# A bucket on a later ring is at least this far from the probe cell.
			if _found_sq < INF:
				var margin: float = float(maxi(ring - 1, 0)) * BUCKET_SIZE
				if _found_distance <= margin:
					return
			ring += 1
		# Defensive net: if the index somehow saw nothing, answer exactly.
		if _found_sq == INF:
			_scan_whole_polyline(world_position, plan_only)


	## Appends every bucket index on the square ring `ring` around `centre`.
	func _ring_indices(centre: Vector2i, ring: int,
			out: PackedInt32Array) -> void:
		var first_x: int = centre.x - ring
		var last_x: int = centre.x + ring
		var first_z: int = centre.y - ring
		var last_z: int = centre.y + ring
		if ring == 0:
			_append_bucket(centre, out)
			return
		for cell_x in range(first_x, last_x + 1):
			_append_bucket(Vector2i(cell_x, first_z), out)
			_append_bucket(Vector2i(cell_x, last_z), out)
		for cell_z in range(first_z + 1, last_z):
			_append_bucket(Vector2i(first_x, cell_z), out)
			_append_bucket(Vector2i(last_x, cell_z), out)


	func _append_bucket(key: Vector2i, out: PackedInt32Array) -> void:
		if not _buckets.has(key):
			return
		out.append_array(_buckets[key] as PackedInt32Array)


	## Folds one centreline segment into the scratch register. A long segment can
	## appear in more than one visited bucket, so re-testing it is harmless.
	func _evaluate_segment(index: int, world_position: Vector3,
			plan_only: bool) -> void:
		var a: Vector3 = points[index]
		var b: Vector3 = points[(index + 1) % _count]
		if plan_only:
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
			if d_sq < _found_sq:
				_found_sq = d_sq
				_found_distance = sqrt(d_sq)
				_found_point = Vector3(candidate.x, world_position.y,
					candidate.y)
				_found_s = wrap_distance(cumulative[index]
					+ sqrt(length_sq) * t)
			return
		var chord: Vector3 = b - a
		var chord_sq: float = chord.length_squared()
		var t3: float = 0.0
		if chord_sq > 0.000001:
			t3 = clampf((world_position - a).dot(chord) / chord_sq, 0.0, 1.0)
		var point: Vector3 = a + chord * t3
		var distance_sq: float = world_position.distance_squared_to(point)
		if distance_sq < _found_sq:
			_found_sq = distance_sq
			_found_distance = sqrt(distance_sq)
			_found_point = point
			_found_s = wrap_distance(cumulative[index] + sqrt(chord_sq) * t3)


	## Whole-polyline scan used only when the bucket index is unavailable.
	func _scan_whole_polyline(world_position: Vector3, plan_only: bool) -> void:
		for index in _count:
			_evaluate_segment(index, world_position, plan_only)


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
	var theme_id: String = _theme_id(theme)
	spline.set_meta("theme", theme_id)
	## A diagnostic build (a synthetic elevation profile, a probe) is not a
	## shipped track, so the seam report must not hand it a racing verdict.
	spline.set_meta("seam_diagnostic", bool(theme.get("diagnostic", false)))
	var road_audit: Dictionary = _build_road(parent, tiles, heights, spline)
	_build_road_collision(parent, tiles, heights,
		road_audit.get("faces", PackedVector3Array()) as PackedVector3Array)
	_report_seams(spline, tiles, heights,
		road_audit.get("tile_tris", []) as Array)
	_schedule_prop_audit(parent)
	_schedule_track_detail(parent, spline, theme, theme_id)

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


## One deferred material/shape audit per scene root. The grid engine builds the
## road before the theme dresses the map, so the audit waits one frame: by then
## every theme prop exists and the whole map can be swept once. The lazy load
## avoids a parse-time cycle (tile_kit preloads this file).
static func _schedule_prop_audit(parent: Node3D) -> void:
	if parent == null:
		return
	var script: Script = load("res://scripts/minigames/tile_kit.gd") as Script
	if script == null or not script.has_method("schedule_prop_audit"):
		return
	script.call("schedule_prop_audit", parent)


## Adds the shared trackside detail pass (painted kerb line, advertising
## hoardings, corner markers) once per race. The lazy load avoids a parse-time
## cycle because tile_kit preloads this file. A theme can opt out by setting
## `kenney_skip_track_detail` on the race root before build().
static func _schedule_track_detail(parent: Node3D, spline: GridSpline,
		theme: Variant, theme_id: String) -> void:
	if parent == null or spline == null:
		return
	if bool(parent.get_meta("kenney_skip_track_detail", false)):
		return
	var script: Script = load("res://scripts/minigames/tile_kit.gd") as Script
	if script == null or not script.has_method("dress_track"):
		return
	var opts: Variant = theme_id
	if theme is Dictionary and (theme as Dictionary).has("hoarding_density"):
		opts = {
			"id": theme_id,
			"hoarding_density": float((theme as Dictionary)["hoarding_density"]),
		}
	script.call("dress_track", parent, spline, opts)


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
#   "elevation": Array of {at, height} lap fractions (a smooth profile).
# A straight cell whose deck is at least BRIDGE_MIN_HEIGHT high automatically
# gets the kit's bridge piece under it, so a raised road reads as a bridge.
# A flat grid (no data, or all zeros) keeps the old flat pipeline untouched.


## Normalised height data: {cells: Dictionary[Vector2i, float], profile: Array,
## step: float, max_height: float, flat: bool}.
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
#
# A flat grid keeps the historical MultiMesh path: every piece sits on the
# lattice, the lane plane is on ROAD_SURFACE and the box colliders share exact edge
# heights. An elevated grid cannot use rigid pitched slabs: a Kenney corner is
# a quarter annulus on a 1x1 footprint, and pitching it about local X makes the
# exit edge slope across the lane. Instead every road vertex is warped to the
# spline height under its own plan position, so adjacent pieces evaluate the
# same spline point on the shared edge and the road is watertight by
# construction. The same warped top triangles become the road collider.
#
# All road geometry is merged by material into one MeshInstance3D, so an
# elevated map costs the same handful of draw calls as the flat MultiMesh path.

## Merged material groups for the elevated road, keyed by material instance id.
static var _road_material_cache: StandardMaterial3D = null
static var _ramp_detail_material_cache: StandardMaterial3D = null


## Builds the road visuals and returns {faces, tile_tris}. `faces` is the
## world-space triangle soup of the drivable top and becomes the elevated road
## collider; `tile_tris` keeps one list per tile for the seam report.
static func _build_road(parent: Node3D, tiles: Array[Dictionary],
		heights: Dictionary, spline: GridSpline) -> Dictionary:
	var holder := Node3D.new()
	holder.name = HOLDER_NAME
	parent.add_child(holder)
	var elevated: bool = not bool(heights.get("flat", true))
	var supports: Array = []
	var ramp_batches: Dictionary = {}
	var faces := PackedVector3Array()
	var tile_tris: Array = []
	if not elevated:
		var batches: Dictionary = {}
		for tile: Dictionary in tiles:
			var tile_char: String = str(tile["tile"])
			var center: Vector3 = _cell_center(tile["cell"])
			var yaw: float = float(tile["yaw"])
			var deck: Vector3 = center + Vector3.UP * (float(tile.get("height", 0.0))
				+ ROAD_SURFACE)
			var model: String = _tile_model(tile)
			var scale: Vector3 = _tile_scale(tile)
			_add_batch(batches, model, _fit_tile(model, deck, yaw, scale, 0.0))
			if tile_char == "C":
				_add_batch(batches, TileCatalog.road_model("S"),
					_fit_tile(TileCatalog.road_model("S"),
						deck + Vector3.UP * Z_DECAL, yaw + PI * 0.5,
						Vector3.ONE * TILE_SIZE, 0.0))
			_collect_support(supports, tile)
		for model: String in batches:
			_batch_model(holder, model, batches[model] as Array, "Road_" + model,
				false)
		_build_ramp_structures(holder, tiles, heights)
		_build_bridge_supports(holder, supports)
		return {"faces": faces, "tile_tris": tile_tris}

	var groups: Dictionary = {}
	for index in tiles.size():
		var tile: Dictionary = tiles[index]
		var tile_char: String = str(tile["tile"])
		var center: Vector3 = _cell_center(tile["cell"])
		var yaw: float = float(tile["yaw"])
		var deck: Vector3 = center + Vector3.UP * (float(tile.get("height", 0.0))
			+ ROAD_SURFACE)
		var model: String = _tile_model(tile)
		var scale: Vector3 = _tile_scale(tile)
		if tile_char == "J" or tile_char == "B":
			# Ramps keep the kit wedge: only their lane plane follows the deck.
			# They own a purpose-built concave collider, so they are not warped
			# into the road soup.
			var ramp_deck: Vector3 = center + Vector3.UP * (
				float(tile.get("height_in", 0.0)) + ROAD_SURFACE)
			_add_batch(ramp_batches, model,
				_fit_tile(model, ramp_deck, yaw, scale, 0.0))
			_collect_support(supports, tile)
			tile_tris.append([])
			continue
		var base: Transform3D = _fit_tile(model, deck, yaw, scale, 0.0)
		var tris: Array = []
		_append_deformed_tile(groups, tris, tile, index, model, base, deck,
			spline, tiles.size())
		if tile_char == "C":
			var cross_model: String = TileCatalog.road_model("S")
			var cross_base: Transform3D = _fit_tile(cross_model,
				deck + Vector3.UP * Z_DECAL, yaw + PI * 0.5,
				Vector3.ONE * TILE_SIZE, 0.0)
			var cross_tris: Array = []
			_append_deformed_tile(groups, cross_tris, tile, index, cross_model,
				cross_base, deck, spline, tiles.size())
		_collect_support(supports, tile)
		tile_tris.append(tris)
		for tri: Dictionary in tris:
			faces.append(tri["a"] as Vector3)
			faces.append(tri["b"] as Vector3)
			faces.append(tri["c"] as Vector3)
	for model: String in ramp_batches:
		_batch_model(holder, model, ramp_batches[model] as Array,
			"Ramp_" + model, false)
	var mesh := ArrayMesh.new()
	for key: Variant in groups:
		var group: Dictionary = groups[key] as Dictionary
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = group["verts"]
		arrays[Mesh.ARRAY_NORMAL] = group["normals"]
		arrays[Mesh.ARRAY_TEX_UV] = group["uvs"]
		arrays[Mesh.ARRAY_COLOR] = group["colors"]
		var surface: int = mesh.get_surface_count()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(surface, group["material"] as Material)
	if mesh.get_surface_count() > 0:
		var instance := MeshInstance3D.new()
		instance.name = "Road"
		instance.mesh = mesh
		instance.cast_shadow = \
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(instance)
	_build_ramp_structures(holder, tiles, heights)
	_build_bridge_supports(holder, supports)
	return {"faces": faces, "tile_tris": tile_tris}


static func _tile_model(tile: Dictionary) -> String:
	if bool(tile["start"]) and _is_straight_char(str(tile["tile"])):
		return TileCatalog.START_MODEL
	return TileCatalog.road_model(str(tile["tile"]))


static func _tile_scale(tile: Dictionary) -> Vector3:
	if _tile_model(tile) == TileCatalog.START_MODEL:
		return Vector3.ONE * TILE_SIZE
	return TileCatalog.road_scale(str(tile["tile"])) * TILE_SIZE


static func _collect_support(supports: Array, tile: Dictionary) -> void:
	if float(tile.get("height", 0.0)) < BRIDGE_MIN_HEIGHT \
			or not _is_straight_char(str(tile["tile"])):
		return
	# The support must stay under the *lowest* point of a sloped deck, or its
	# flat top would poke through the road surface and become an invisible wall.
	var rise: float = absf(float(tile.get("height_out", 0.0)) \
		- float(tile.get("height_in", 0.0)))
	var support_height: float = maxf(float(tile.get("height", 0.0))
		+ ROAD_SURFACE - rise * 0.5 - 0.05, 0.01)
	supports.append({
		"deck": _cell_center(tile["cell"]) \
			+ Vector3.UP * (float(tile.get("height", 0.0)) + ROAD_SURFACE),
		"yaw": float(tile["yaw"]),
		"height": support_height,
	})


## Warps one fitted road piece onto the spline surface and appends its triangles
## to the merged material groups. Every vertex is shifted by the height
## difference between the spline under its plan position and the tile's deck;
## the lane plane stays at ROAD_SURFACE and both sides of a seam evaluate the same
## spline point.
static func _append_deformed_tile(groups: Dictionary, tris: Array,
		tile: Dictionary, tile_index: int, model: String, base: Transform3D,
		deck: Vector3, spline: GridSpline, tile_count: int) -> void:
	var info: Dictionary = TileCatalog.model_info(model)
	if not bool(info.get("ok", false)):
		return
	for part: Dictionary in info["parts"] as Array:
		var mesh: Mesh = part["mesh"] as Mesh
		if mesh == null:
			continue
		var part_xform: Transform3D = base * (part["transform"] as Transform3D)
		for surface in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(surface)
			if arrays.is_empty():
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] \
				as PackedVector3Array
			if verts.is_empty():
				continue
			var uvs := PackedVector2Array()
			if arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array:
				uvs = arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array
			var colors := PackedColorArray()
			if arrays[Mesh.ARRAY_COLOR] is PackedColorArray:
				colors = arrays[Mesh.ARRAY_COLOR] as PackedColorArray
			var indices := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
				indices = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
			# Godot's front faces are clockwise, so a cross product would point
			# into the slab. The imported vertex normals are the truth; transform
			# them with the placement basis and keep them for shading.
			var source_normals := PackedVector3Array()
			if arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array:
				source_normals = arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
			var normal_basis: Basis = part_xform.basis.inverse().transposed()
			var material: Material = mesh.surface_get_material(surface)
			if material == null:
				material = _road_material()
			var group: Dictionary = _geometry_group(groups, material)
			var group_verts: PackedVector3Array = group["verts"] \
				as PackedVector3Array
			var group_normals: PackedVector3Array = group["normals"] \
				as PackedVector3Array
			var group_uvs: PackedVector2Array = group["uvs"] \
				as PackedVector2Array
			var group_colors: PackedColorArray = group["colors"] \
				as PackedColorArray
			var tri_count: int = indices.size() / 3 if not indices.is_empty() \
				else verts.size() / 3
			for tri_index in tri_count:
				var i0: int = indices[tri_index * 3] \
					if not indices.is_empty() else tri_index * 3
				var i1: int = indices[tri_index * 3 + 1] \
					if not indices.is_empty() else tri_index * 3 + 1
				var i2: int = indices[tri_index * 3 + 2] \
					if not indices.is_empty() else tri_index * 3 + 2
				if i0 >= verts.size() or i1 >= verts.size() \
						or i2 >= verts.size():
					continue
				var a: Vector3 = part_xform * verts[i0]
				var b: Vector3 = part_xform * verts[i1]
				var c: Vector3 = part_xform * verts[i2]
				a.y += _road_delta(spline, tile, tile_index, tile_count,
					a.x, a.z, deck.y)
				b.y += _road_delta(spline, tile, tile_index, tile_count,
					b.x, b.z, deck.y)
				c.y += _road_delta(spline, tile, tile_index, tile_count,
					c.x, c.z, deck.y)
				var edge_a: Vector3 = (b - a).cross(c - a)
				if edge_a.length_squared() < 0.0000001:
					continue
				var na: Vector3 = _surface_normal(source_normals, i0,
					normal_basis)
				var nb: Vector3 = _surface_normal(source_normals, i1,
					normal_basis)
				var nc: Vector3 = _surface_normal(source_normals, i2,
					normal_basis)
				var face_normal: Vector3 = (na + nb + nc).normalized()
				if face_normal.length_squared() < 0.5:
					face_normal = edge_a.normalized() if edge_a.y >= 0.0 \
						else -edge_a.normalized()
				var geo_normal: Vector3 = edge_a.normalized()
				if geo_normal.y < 0.0:
					geo_normal = -geo_normal
				group_verts.append(a)
				group_verts.append(b)
				group_verts.append(c)
				group_normals.append(na)
				group_normals.append(nb)
				group_normals.append(nc)
				group_uvs.append(_uv_at(uvs, i0))
				group_uvs.append(_uv_at(uvs, i1))
				group_uvs.append(_uv_at(uvs, i2))
				var color_a: Color = _color_at(colors, i0)
				var color_b: Color = _color_at(colors, i1)
				var color_c: Color = _color_at(colors, i2)
				group_colors.append(color_a)
				group_colors.append(color_b)
				group_colors.append(color_c)
				if face_normal.y > 0.15:
					tris.append({"a": a, "b": b, "c": c, "n": geo_normal})
			group["verts"] = group_verts
			group["normals"] = group_normals
			group["uvs"] = group_uvs
			group["colors"] = group_colors


static func _uv_at(uvs: PackedVector2Array, index: int) -> Vector2:
	return uvs[index] if index < uvs.size() else Vector2.ZERO


static func _color_at(colors: PackedColorArray, index: int) -> Color:
	return colors[index] if index < colors.size() else Color.WHITE


## Transforms one authored vertex normal into world space. A missing normal is
## treated as up so a simple custom mesh still contributes a drivable top.
static func _surface_normal(source: PackedVector3Array, index: int,
		basis: Basis) -> Vector3:
	if index < source.size():
		var normal: Vector3 = basis * source[index]
		if normal.length_squared() > 0.0000001:
			return normal.normalized()
	return Vector3.UP


static func _geometry_group(groups: Dictionary, material: Material) -> Dictionary:
	var key: int = material.get_instance_id()
	if groups.has(key):
		return groups[key] as Dictionary
	var group: Dictionary = {
		"material": material,
		"verts": PackedVector3Array(),
		"normals": PackedVector3Array(),
		"uvs": PackedVector2Array(),
		"colors": PackedColorArray(),
	}
	groups[key] = group
	return group


## Height difference from a fitted tile's deck to the warp at (x, z). The warp
## uses the tile's own entry/exit geometry, not a nearest-point search: the
## entry edge is exactly h_in across its whole row, the exit edge exactly h_out,
## and the lane twists between them. That is what makes the shared edge rows of
## two neighbouring tiles identical to the millimetre.
static func _road_delta(_spline: GridSpline, tile: Dictionary,
		_tile_index: int, _tile_count: int, x: float, z: float,
		deck_y: float) -> float:
	var center: Vector3 = _cell_center(tile["cell"])
	var entry: int = int(tile.get("entry", EDGE_N))
	var exit: int = int(tile.get("exit", EDGE_S))
	var h_in: float = float(tile.get("height_in", 0.0))
	var h_out: float = float(tile.get("height_out", 0.0))
	var t: float = 0.0
	if _opposite(entry) == exit:
		var din: Vector3 = -_edge_3d(entry)
		var along: float = (x - center.x) * din.x + (z - center.z) * din.z
		t = clampf((along + HALF_TILE) / TILE_SIZE, 0.0, 1.0)
	else:
		var corner: Vector3 = center + _edge_3d(entry) * HALF_TILE \
			+ _edge_3d(exit) * HALF_TILE
		var p_in: Vector3 = center + _edge_3d(entry) * HALF_TILE
		var p_out: Vector3 = center + _edge_3d(exit) * HALF_TILE
		var start_angle: float = atan2(p_in.z - corner.z,
			p_in.x - corner.x)
		var end_angle: float = atan2(p_out.z - corner.z, p_out.x - corner.x)
		var sweep: float = angle_difference(start_angle, end_angle)
		if absf(sweep) > 0.0001:
			var angle: float = atan2(z - corner.z, x - corner.x)
			t = clampf(angle_difference(start_angle, angle) / sweep, 0.0, 1.0)
	return lerpf(h_in, h_out, t) + ROAD_SURFACE - deck_y


## The shared ramp/base/lip material: flat cartoon shading with vertex colours.
static func _ramp_detail_material() -> StandardMaterial3D:
	if _ramp_detail_material_cache != null:
		return _ramp_detail_material_cache
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.roughness = 1.0
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ramp_detail_material_cache = material
	return material


static func _road_material() -> StandardMaterial3D:
	if _road_material_cache != null:
		return _road_material_cache
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("4b4f55")
	material.roughness = 1.0
	material.metallic = 0.0
	_road_material_cache = material
	return material


## Solid base, outer side walls and painted lip for every jump/bump tile. The
## structures sit outside the 11.04 m lane and carry no collider, so a cart can
## never catch on them where the ramp meets the road.
static func _build_ramp_structures(holder: Node3D, tiles: Array[Dictionary],
		heights: Dictionary) -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var found: int = 0
	for tile: Dictionary in tiles:
		var tile_char: String = str(tile["tile"])
		if tile_char != "J" and tile_char != "B":
			continue
		found += 1
		var center: Vector3 = _cell_center(tile["cell"])
		var deck: Vector3 = center + Vector3.UP * (
			float(tile.get("height_in", 0.0)) + ROAD_SURFACE)
		var frame := Transform3D(Basis(Vector3.UP, float(tile["yaw"])), deck)
		var base_color := Color("3c4048") if tile_char == "J" \
			else Color("5c4c3c")
		_append_colored_box(verts, normals, colors,
			Transform3D(frame.basis, deck + Vector3.DOWN
				* (RAMP_BASE_DEPTH * 0.5 + 0.02)),
			Vector3(TILE_SIZE - 0.2, RAMP_BASE_DEPTH, TILE_SIZE - 0.2),
			base_color)
		if tile_char == "B":
			var rail_x: float = RAMP_WALL_LATERAL
			for side: float in [-1.0, 1.0]:
				_append_colored_box(verts, normals, colors,
					Transform3D(frame.basis, deck + Vector3.UP * 0.16
						+ frame.basis * Vector3(rail_x * side, 0.0, 0.0)),
					Vector3(RAMP_WALL_THICKNESS, 0.32, TILE_SIZE - 0.6),
					Color("e8c34a"))
			continue
		var ramp_height: float = ramp_top_height("J")
		var wall_color := Color("e8c34a")
		for side: float in [-1.0, 1.0]:
			_append_ramp_wall(verts, normals, colors, frame,
				RAMP_WALL_LATERAL * side, side, ramp_height, wall_color)
		_append_lip(verts, normals, colors, frame, ramp_height)
	if found == 0 or verts.is_empty():
		return
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _ramp_detail_material())
	var instance := MeshInstance3D.new()
	instance.name = "RampDetail"
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(instance)


## One triangular outer wall along a ramp: low at the entry edge, rising to the
## crest, with a thickness so it reads as a built structure from every angle.
static func _append_ramp_wall(verts: PackedVector3Array,
		normals: PackedVector3Array, colors: PackedColorArray,
		frame: Transform3D, lateral: float, side: float, ramp_height: float,
		color: Color) -> void:
	var inner: float = lateral
	var outer: float = lateral + RAMP_WALL_THICKNESS * side
	var bottom: float = -RAMP_BASE_DEPTH
	var top_entry: float = RAMP_WALL_LIFT
	var top_exit: float = ramp_height + RAMP_WALL_LIFT
	var entry_z: float = HALF_TILE
	var exit_z: float = -HALF_TILE
	var points: Array[Vector3] = [
		Vector3(inner, bottom, entry_z),
		Vector3(inner, bottom, exit_z),
		Vector3(inner, top_entry, entry_z),
		Vector3(inner, top_exit, exit_z),
		Vector3(outer, bottom, entry_z),
		Vector3(outer, bottom, exit_z),
		Vector3(outer, top_entry, entry_z),
		Vector3(outer, top_exit, exit_z),
	]
	_append_frame_quad(verts, normals, colors, frame,
		points[0], points[1], points[3], points[2], color, Vector3(-side, 0, 0))
	_append_frame_quad(verts, normals, colors, frame,
		points[4], points[6], points[7], points[5],
		color.darkened(0.18), Vector3(side, 0, 0))
	_append_frame_quad(verts, normals, colors, frame,
		points[2], points[3], points[7], points[6], color, Vector3.UP)
	_append_frame_quad(verts, normals, colors, frame,
		points[0], points[2], points[6], points[4],
		color.darkened(0.12), Vector3(0, 0, 1))
	_append_frame_quad(verts, normals, colors, frame,
		points[1], points[5], points[7], points[3],
		color.darkened(0.12), Vector3(0, 0, -1))


## Bright painted band on the ramp surface plus the vertical lip face below it.
static func _append_lip(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, frame: Transform3D,
		ramp_height: float) -> void:
	var entry_z: float = -HALF_TILE + RAMP_LIP_BAND
	var exit_z: float = -HALF_TILE
	var entry_y: float = ramp_height * (HALF_TILE - entry_z) / TILE_SIZE
	var exit_y: float = ramp_height
	var lip_color := Color("fff6e3")
	var edge_color := Color("c23a2c")
	_append_frame_quad(verts, normals, colors, frame,
		Vector3(-ROAD_HALF, entry_y + Z_DECAL, entry_z),
		Vector3(ROAD_HALF, entry_y + Z_DECAL, entry_z),
		Vector3(ROAD_HALF, exit_y + Z_DECAL, exit_z),
		Vector3(-ROAD_HALF, exit_y + Z_DECAL, exit_z), lip_color,
		Vector3.UP)
	_append_frame_quad(verts, normals, colors, frame,
		Vector3(-ROAD_HALF, exit_y - RAMP_LIP_HEIGHT, exit_z + 0.01),
		Vector3(ROAD_HALF, exit_y - RAMP_LIP_HEIGHT, exit_z + 0.01),
		Vector3(ROAD_HALF, exit_y, exit_z + 0.01),
		Vector3(-ROAD_HALF, exit_y, exit_z + 0.01), edge_color,
		Vector3(0, 0, 1))


static func _append_frame_quad(verts: PackedVector3Array,
		normals: PackedVector3Array, colors: PackedColorArray,
		frame: Transform3D, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		color: Color, outward: Vector3 = Vector3.ZERO) -> void:
	var wa: Vector3 = frame * a
	var wb: Vector3 = frame * b
	var wc: Vector3 = frame * c
	var wd: Vector3 = frame * d
	var normal: Vector3 = (wb - wa).cross(wc - wa)
	if normal.length_squared() > 0.0000001:
		normal = normal.normalized()
	else:
		normal = Vector3.UP
	if outward != Vector3.ZERO \
			and normal.dot((frame.basis * outward).normalized()) < 0.0:
		normal = -normal
	_append_tri(verts, normals, colors, wa, wb, wc, normal, color)
	_append_tri(verts, normals, colors, wa, wc, wd, normal, color)


static func _append_tri(verts: PackedVector3Array,
		normals: PackedVector3Array, colors: PackedColorArray,
		a: Vector3, b: Vector3, c: Vector3, normal: Vector3,
		color: Color) -> void:
	for point: Vector3 in [a, b, c]:
		verts.append(point)
		normals.append(normal)
		colors.append(color)


static func _append_colored_box(verts: PackedVector3Array,
		normals: PackedVector3Array, colors: PackedColorArray,
		xform: Transform3D, size: Vector3, color: Color) -> void:
	var half: Vector3 = size * 0.5
	var corners: Array[Vector3] = []
	for x: float in [-1.0, 1.0]:
		for y: float in [-1.0, 1.0]:
			for z: float in [-1.0, 1.0]:
				corners.append(xform * Vector3(half.x * x, half.y * y,
					half.z * z))
	# Corners are ordered x-major, then y, then z: 0=(-,-,-), 1=(-,-,+),
	# 2=(-,+,-), 3=(-,+,+), 4=(+,-,-), 5=(+,-,+), 6=(+,+,-), 7=(+,+,+).
	# Every quad is wound so its face normal points out of the box.
	_append_face(verts, normals, colors, corners[0], corners[1], corners[3],
		corners[2], color.darkened(0.10))
	_append_face(verts, normals, colors, corners[4], corners[6], corners[7],
		corners[5], color.darkened(0.06))
	_append_face(verts, normals, colors, corners[0], corners[4], corners[5],
		corners[1], color.darkened(0.16))
	_append_face(verts, normals, colors, corners[2], corners[3], corners[7],
		corners[6], color.darkened(0.16))
	_append_face(verts, normals, colors, corners[0], corners[2], corners[6],
		corners[4], color.darkened(0.20))
	_append_face(verts, normals, colors, corners[1], corners[5], corners[7],
		corners[3], color)


static func _append_face(verts: PackedVector3Array,
		normals: PackedVector3Array, colors: PackedColorArray,
		a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	var normal: Vector3 = (b - a).cross(c - a)
	if normal.length_squared() > 0.0000001:
		normal = normal.normalized()
	else:
		normal = Vector3.UP
	_append_tri(verts, normals, colors, a, b, c, normal, color)
	_append_tri(verts, normals, colors, a, c, d, normal, color)


## Elevated straight cells get the kit's bridge piece under the deck, squashed
## to the deck height, so a raised road reads as a bridge over the terrain
## instead of a floating slab. The top stops 5 cm under the lane so the bridge
## deck can never z-fight the road surface. Purely visual.
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
		var height: float = maxf(float(entry.get("height", deck.y - 0.05)), 0.01)
		var scale := Vector3(TILE_SIZE,
			height / maxf(aabb.size.y, 0.001), TILE_SIZE)
		var base := Vector3(deck.x, 0.0, deck.z)
		transforms.append(_fit_transform(BRIDGE_MODEL, base, float(entry["yaw"]),
			scale))
	_batch_model(holder, BRIDGE_MODEL, transforms, "BridgeSupports", true)


## Places a road piece so its authored lane plane (local Y = 0) sits on `at`.
## Pitch is applied about that lane plane, and the piece is stretched along
## travel just enough that a pitched straight keeps its 16 m plan footprint, so
## its two edge rows land exactly on the neighbouring tiles' rows.
static func _fit_tile(model: String, at: Vector3, yaw: float, scale: Vector3,
		pitch: float) -> Transform3D:
	var info: Dictionary = TileCatalog.model_info(model)
	if not bool(info.get("ok", false)):
		return Transform3D(Basis(Vector3.UP, yaw).scaled(scale), at)
	var center: Vector2 = info["center"]
	var stretch: Vector3 = scale
	if absf(pitch) > 0.0001:
		stretch.z /= maxf(cos(pitch), 0.10)
	var basis: Basis = Basis(Vector3.UP, yaw) * Basis(Vector3(1.0, 0.0, 0.0),
		pitch) * Basis.IDENTITY.scaled(stretch)
	var pivot := Vector3(center.x, 0.0, center.y)
	return Transform3D(basis, at - basis * pivot)


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


## Road colliders. A flat grid keeps one tilted box per cell, all sharing the
## same deck plane. An elevated grid uses the exact warped top triangles from
## the visual pass as one concave surface, so the collider and the road the
## player sees are the same watertight mesh; ramp/jump tiles keep their own
## concave wedge because they are deliberately non-flat.
static func _build_road_collision(parent: Node3D,
		tiles: Array[Dictionary], heights: Dictionary = {},
		top_faces: PackedVector3Array = PackedVector3Array()) -> void:
	var holder: Node3D = parent.get_node_or_null(HOLDER_NAME) as Node3D
	if holder == null:
		return
	var elevated: bool = not bool(heights.get("flat", true))
	var body := StaticBody3D.new()
	body.name = "RoadCollision"
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = 0
	holder.add_child(body)
	var ramp_faces := PackedVector3Array()
	for tile: Dictionary in tiles:
		var tile_char: String = str(tile["tile"])
		var center: Vector3 = _cell_center(tile["cell"])
		var deck: Vector3 = center + Vector3.UP * (float(tile.get("height", 0.0))
			+ ROAD_SURFACE)
		if tile_char == "J" or tile_char == "B":
			_append_ramp_faces(ramp_faces, tile, tile_char == "B")
		elif not elevated:
			_add_box_shape(body, _tilted_box(deck, float(tile["yaw"]), 0.0,
				Vector3(TILE_SIZE, ROAD_THICKNESS, TILE_SIZE)),
				Vector3(TILE_SIZE, ROAD_THICKNESS, TILE_SIZE))
		if float(tile.get("height", 0.0)) >= BRIDGE_MIN_HEIGHT \
				and _is_straight_char(tile_char):
			# A raised deck is a hill: the space under it is solid terrain. The
			# fill stops below the low edge of a sloped deck so it can never
			# protrude through the racing surface.
			var rise: float = absf(float(tile.get("height_out", 0.0)) \
				- float(tile.get("height_in", 0.0)))
			var fill: float = maxf(float(tile.get("height", 0.0))
				+ ROAD_SURFACE - rise * 0.5 - 0.05, 0.01)
			_add_box_shape(body, Transform3D(Basis.IDENTITY,
				Vector3(center.x, fill * 0.5, center.z)),
				Vector3(TILE_SIZE, fill, TILE_SIZE))
	if not top_faces.is_empty():
		var road_shape := ConcavePolygonShape3D.new()
		road_shape.set_faces(top_faces)
		road_shape.backface_collision = true
		var road_collision := CollisionShape3D.new()
		road_collision.name = "RoadSurface"
		road_collision.shape = road_shape
		body.add_child(road_collision)
	if not ramp_faces.is_empty():
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(ramp_faces)
		shape.backface_collision = true
		var collision := CollisionShape3D.new()
		collision.name = "Ramps"
		collision.shape = shape
		body.add_child(collision)


## Measures the built road at every shared tile edge and prints one line per
## circuit. The two edge rows are sampled at the same lateral positions from
## each adjacent tile's warped top triangles, so a step, hole or normal kink is
## visible in the boot log instead of hiding until a kart reaches the corner.
static func _report_seams(spline: GridSpline, tiles: Array[Dictionary],
		heights: Dictionary, tile_tris: Array) -> void:
	var theme: String = str(spline.get_meta("theme", "grid"))
	var elevated: bool = not bool(heights.get("flat", true))
	var closure: float = 0.0
	if not tiles.is_empty():
		var last: Dictionary = tiles[tiles.size() - 1]
		var last_seg: PackedVector3Array = _segment_points(
			_cell_center(last["cell"]), int(last["entry"]), int(last["exit"]),
			str(last["tile"]), float(last.get("height_in", 0.0)),
			float(last.get("height_out", 0.0)))
		closure = spline.points[0].distance_to(last_seg[last_seg.size() - 1])
	var max_gap: float = 0.0
	var max_step: float = 0.0
	var max_normal: float = 0.0
	var max_offset: float = 0.0
	var samples: int = 0
	var misses: int = 0
	if elevated and tile_tris.size() == tiles.size():
		for index in tiles.size():
			var tile: Dictionary = tiles[index]
			var next: Dictionary = tiles[(index + 1) % tiles.size()]
			if _is_ramp(str(tile["tile"])) or _is_ramp(str(next["tile"])):
				continue
			var p: Vector3 = spline.points[int(tile["to_index"])] \
				if index < tiles.size() - 1 else spline.points[0]
			var travel: Vector3 = _edge_3d(int(tile["exit"]))
			var right: Vector3 = travel.cross(Vector3.UP).normalized()
			var expected_y: float = p.y + ROAD_SURFACE
			for step in 13:
				var lateral: float = -ROAD_HALF * 0.96 \
					+ (ROAD_HALF * 1.92) * float(step) / 12.0
				var q: Vector3 = p + right * lateral
				var a: Dictionary = _sample_top(tile_tris[index] as Array, q)
				var b: Dictionary = _sample_top(
					tile_tris[(index + 1) % tiles.size()] as Array, q)
				samples += 1
				if not bool(a["hit"]) or not bool(b["hit"]):
					misses += 1
					max_gap = maxf(max_gap, maxf(float(a["gap"]),
						float(b["gap"])))
					continue
				var ya: float = float(a["y"])
				var yb: float = float(b["y"])
				max_step = maxf(max_step, absf(ya - yb))
				max_offset = maxf(max_offset,
					maxf(absf(ya - expected_y), absf(yb - expected_y)))
				var na: Vector3 = a["n"]
				var nb: Vector3 = b["n"]
				max_normal = maxf(max_normal,
					rad_to_deg(acos(clampf(na.dot(nb), -1.0, 1.0))))
	var watertight: bool = max_gap <= SEAM_TOLERANCE \
		and max_step <= SEAM_TOLERANCE \
		and max_offset <= SEAM_TOLERANCE \
		and max_normal <= 30.0 \
		and closure <= SEAM_TOLERANCE and misses == 0
	print("KENNEY SEAMS %s: gap %.1f mm, height step %.1f mm, normal jump %.1f deg, deck offset %.1f mm, closure %.1f mm, %d/%d samples -> %s" % [
		theme, max_gap * 1000.0, max_step * 1000.0, max_normal,
		max_offset * 1000.0, closure * 1000.0, samples - misses, samples,
		"WATERTIGHT" if watertight else "LEAKY"])
	var diagnostic: bool = bool(spline.get_meta("seam_diagnostic", false))
	print("KENNEY DRIVE %s: %s" % [
		theme,
		"(diagnostic profile, not a shipped track)"
		if diagnostic else
		"YES" if watertight else "NO (fix the seam metrics before racing)"])
	# Publish the numbers for probes and the race HUD/debug tools.
	spline.set_meta("seam_gap", max_gap)
	spline.set_meta("seam_step", max_step)
	spline.set_meta("seam_normal", max_normal)
	spline.set_meta("seam_offset", max_offset)
	spline.set_meta("seam_closure", closure)
	spline.set_meta("seam_watertight", watertight)


static func _is_ramp(tile_char: String) -> bool:
	return tile_char == "J" or tile_char == "B"


## Topmost upward-facing triangle of one tile at plan point `q`.
## Returns {hit, y, n, gap}; a miss reports the plan distance to the nearest
## triangle edge so the boot log can say how wide the hole is.
static func _sample_top(tris: Array, q: Vector3) -> Dictionary:
	var best_y: float = -INF
	var best_normal := Vector3.UP
	for tri: Dictionary in tris:
		var a: Vector3 = tri["a"]
		var b: Vector3 = tri["b"]
		var c: Vector3 = tri["c"]
		var bary: Vector3 = _plan_barycentric(a, b, c, q)
		if bary.x < -0.0001 or bary.y < -0.0001 or bary.z < -0.0001:
			continue
		var y: float = bary.x * a.y + bary.y * b.y + bary.z * c.y
		if y > best_y:
			best_y = y
			best_normal = tri["n"]
	if best_y > -INF:
		return {"hit": true, "y": best_y, "n": best_normal, "gap": 0.0}
	var best_gap: float = INF
	for tri: Dictionary in tris:
		var a: Vector3 = tri["a"]
		var b: Vector3 = tri["b"]
		var c: Vector3 = tri["c"]
		best_gap = minf(best_gap, _plan_segment_distance(q, a, b))
		best_gap = minf(best_gap, _plan_segment_distance(q, b, c))
		best_gap = minf(best_gap, _plan_segment_distance(q, c, a))
	return {"hit": false, "y": 0.0, "n": Vector3.UP,
		"gap": 0.0 if best_gap == INF else best_gap}


static func _plan_barycentric(a: Vector3, b: Vector3, c: Vector3,
		q: Vector3) -> Vector3:
	var v0 := Vector2(b.x - a.x, b.z - a.z)
	var v1 := Vector2(c.x - a.x, c.z - a.z)
	var v2 := Vector2(q.x - a.x, q.z - a.z)
	var den: float = v0.x * v1.y - v0.y * v1.x
	if absf(den) < 0.0000001:
		return Vector3(-1.0, -1.0, -1.0)
	var u: float = (v2.x * v1.y - v2.y * v1.x) / den
	var v: float = (v0.x * v2.y - v0.y * v2.x) / den
	return Vector3(1.0 - u - v, u, v)


static func _plan_segment_distance(q: Vector3, a: Vector3,
		b: Vector3) -> float:
	var qp := Vector2(q.x, q.z)
	var ap := Vector2(a.x, a.z)
	var bp := Vector2(b.x, b.z)
	var ab: Vector2 = bp - ap
	var length_sq: float = ab.length_squared()
	var t: float = 0.0 if length_sq < 0.000001 \
		else clampf((qp - ap).dot(ab) / length_sq, 0.0, 1.0)
	return qp.distance_to(ap + ab * t)


## A box whose top face passes through `deck`, pitched along the tile travel.
static func _tilted_box(deck: Vector3, yaw: float, pitch: float,
		size: Vector3) -> Transform3D:
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3(1.0, 0.0, 0.0), pitch)
	return Transform3D(basis, deck + basis * Vector3.DOWN * (size.y * 0.5))


## Jump cells get a wedge that rises to the exit; bump cells get a hump. The
## collider is built from the *measured* top surface of the Kenney piece, not
## from a hand-typed height, so the kart always drives the slope it sees. The
## old version multiplied a model AABB by a scale that belonged to a different
## piece: on Glacier Pass the collider rose 0.68 m over a visible 2.86 m kicker
## and karts drove straight through the mesh. The strip spans the whole piece
## width for the same reason: the visible ramp is 22 m wide, so a kart on the
## verge must not fall through the shoulder either.
##
## `heights` are metres above the tile's lane deck, entry row first (model +Z)
## and exit row last (model -Z, the direction of travel).
static func _append_ramp_faces(faces: PackedVector3Array, tile: Dictionary,
		hump: bool) -> void:
	var profile: Dictionary = _ramp_surface_profile("B" if hump else "J")
	if not bool(profile.get("ok", false)):
		return
	var heights: PackedFloat32Array = profile["heights"] as PackedFloat32Array
	var half_length: float = float(profile["half_length"])
	var half_width: float = float(profile["half_width"])
	if heights.size() < 2 or half_length <= 0.0 or half_width <= 0.0:
		return
	var rows: int = heights.size() - 1
	var center: Vector3 = _cell_center(tile["cell"])
	var din: Vector3 = -_edge_3d(int(tile["entry"]))
	var right: Vector3 = din.cross(Vector3.UP).normalized()
	var lane: Vector3 = center + Vector3.UP * (float(tile.get("height_in", 0.0))
		+ ROAD_SURFACE)
	# Row points, entry to exit, along the whole piece width.
	var left: Array[Vector3] = []
	var right_edge: Array[Vector3] = []
	var left_deck: Array[Vector3] = []
	var right_deck: Array[Vector3] = []
	for row in rows + 1:
		var along: float = -half_length + 2.0 * half_length * float(row) \
			/ float(rows)
		var top: float = heights[row]
		var at: Vector3 = lane + din * along
		left.append(at - right * half_width + Vector3.UP * top)
		right_edge.append(at + right * half_width + Vector3.UP * top)
		left_deck.append(at - right * half_width)
		right_deck.append(at + right * half_width)
	for row in rows:
		# Top surface strip.
		_tri(faces, left[row], right_edge[row], right_edge[row + 1])
		_tri(faces, left[row], right_edge[row + 1], left[row + 1])
		# Side faces, so the ramp is a solid wedge and a kart cannot cut into it
		# from the shoulder at deck height.
		_tri(faces, left[row], left[row + 1], left_deck[row + 1])
		_tri(faces, left[row], left_deck[row + 1], left_deck[row])
		_tri(faces, right_edge[row], right_deck[row + 1],
			right_edge[row + 1])
		_tri(faces, right_edge[row], right_deck[row], right_deck[row + 1])
	if not hump:
		# The visible kicker ends in a vertical lip at the exit edge: close the
		# wedge down to the deck so the kart never wedges under the crest.
		_tri(faces, left[rows], right_edge[rows], right_deck[rows])
		_tri(faces, left[rows], right_deck[rows], left_deck[rows])


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


## Visible crest height of a jump/bump piece above its lane deck, in metres.
##
## Measured from the GLB's top surface (not from the AABB: the AABB of the
## walled kicker includes the side-wall lip) so a theme that launches a kart
## over the crest uses exactly the height the collider and the mesh carry.
static func ramp_top_height(tile_char: String = "J") -> float:
	var profile: Dictionary = _ramp_surface_profile(tile_char)
	if not bool(profile.get("ok", false)):
		return 0.0
	var heights: PackedFloat32Array = profile["heights"] as PackedFloat32Array
	return heights[heights.size() - 1] if not heights.is_empty() else 0.0


## Top surface profile of a jump/bump piece, sampled from its mesh once.
##
## Returns {ok, half_length, half_width, heights}. `heights[row]` is metres
## above the lane plane, the entry row (model +Z) first and the exit row (model
## -Z, the direction of travel) last. The collider builder and the ramp-detail
## pass both read this, so the painted lip, the wedge and the art cannot drift
## apart again.
static func _ramp_surface_profile(tile_char: String, rows: int = 10) -> Dictionary:
	var cache_key: String = "%s:%d" % [tile_char, rows]
	if _ramp_profiles.has(cache_key):
		return _ramp_profiles[cache_key] as Dictionary
	var out: Dictionary = {"ok": false, "half_length": 0.0, "half_width": 0.0,
		"heights": PackedFloat32Array()}
	_ramp_profiles[cache_key] = out
	var model: String = TileCatalog.road_model(tile_char)
	var scale: Vector3 = TileCatalog.road_scale(tile_char) * TILE_SIZE
	var info: Dictionary = TileCatalog.model_info(model)
	if not bool(info.get("ok", false)) or scale.z <= 0.0 or scale.y <= 0.0:
		return out
	var aabb: AABB = info["aabb"]
	var center: Vector2 = info["center"]
	var tris := PackedVector3Array()
	for part: Dictionary in info["parts"] as Array:
		var mesh: Mesh = part["mesh"] as Mesh
		var part_xform: Transform3D = part["transform"]
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(surface)
			if arrays.is_empty():
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
				indices = arrays[Mesh.ARRAY_INDEX]
			var tri_count: int = indices.size() / 3 if not indices.is_empty() \
				else verts.size() / 3
			for tri in tri_count:
				var i0: int = indices[tri * 3] if not indices.is_empty() \
					else tri * 3
				var i1: int = indices[tri * 3 + 1] \
					if not indices.is_empty() else tri * 3 + 1
				var i2: int = indices[tri * 3 + 2] \
					if not indices.is_empty() else tri * 3 + 2
				tris.append(part_xform * verts[i0])
				tris.append(part_xform * verts[i1])
				tris.append(part_xform * verts[i2])
	if tris.is_empty():
		return out
	var half_length: float = aabb.size.z * absf(scale.z) * 0.5
	var half_width: float = aabb.size.x * absf(scale.x) * 0.5
	var heights := PackedFloat32Array()
	heights.resize(rows + 1)
	for row in rows + 1:
		# Travel is local -Z, so a row `along` metres forward of the tile centre
		# is at model z = centre - along / scale.z.
		var along: float = -half_length + 2.0 * half_length * float(row) \
			/ float(rows)
		var model_z: float = center.y - along / scale.z
		var top: float = _model_plan_top(tris, Vector3(center.x, 0.0, model_z))
		heights[row] = maxf(top, 0.0) * scale.y
	out["ok"] = true
	out["half_length"] = half_length
	out["half_width"] = half_width
	out["heights"] = heights
	_ramp_profiles[cache_key] = out
	return out


## Highest model-space triangle y under a model-space plan point.
static func _model_plan_top(tris: PackedVector3Array, q: Vector3) -> float:
	var best: float = -INF
	var index: int = 0
	var count: int = tris.size() / 3
	while index < count:
		var a: Vector3 = tris[index * 3]
		var b: Vector3 = tris[index * 3 + 1]
		var c: Vector3 = tris[index * 3 + 2]
		index += 1
		var bary: Vector3 = _plan_barycentric(a, b, c, q)
		if bary.x < -0.001 or bary.y < -0.001 or bary.z < -0.001:
			continue
		best = maxf(best, bary.x * a.y + bary.y * b.y + bary.z * c.y)
	return best


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
