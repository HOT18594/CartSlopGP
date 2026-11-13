extends RefCounted
## Trackside dressing for the STADIUM CIRCUIT grid map.
##
## Every prop is placed through scripts/minigames/tile_kit.gd, which batches the
## repeated models into MultiMeshes and gives every solid piece a collider on
## CollisionLayers.WORLD. This module builds no mesh and no shape of its own.
##
## Positions come from the map's ASCII grid instead of hard-coded world points.
## `_trace_lap` walks the grid once to give every tile its arc position, then
## that walk is scaled onto the spline the race handed us: on the grid spline
## the scale is 1.0 and a stand lands exactly on the cell the tile engine built,
## while on the legacy TrackSpline the same fractions spread the same props
## around the loop, so a half-wired race scene still reads as a stadium.
##
## Lattice props (pit garages, banner towers, flags, billboards, pylons, lights
## and trees) are snapped to the nearest 16 m cell after the lateral offset, so
## nothing free-floats between tiles. `claimed` reserves a cell for the first
## structure that asks for it, which is what keeps a flag pole out of a
## grandstand and a tree out of a floodlight.

const TileKit := preload("res://scripts/minigames/tile_kit.gd")

## Metres per ASCII cell, mirroring KenneyTiles.TILE_SIZE.
const CELL: float = TileKit.TILE_SIZE
## Clearance a snapped lattice cell needs from the centreline, in metres. Half a
## cell plus the barrier line is wider than the barrier's outer face, so a prop
## can never reach the racing surface.
const TRACK_CLEARANCE: float = TileKit.ROAD_HALF + CELL * 0.5
## Lateral offset of a lattice prop: one whole cell, so the snapped prop sits on
## the cell that shares an edge with the track cell.
const PROP_OFFSET: float = CELL

const BARRIER_KIND: String = "barrierRed"
const START_TOWER: String = "bannerTowerRed"
const BILLBOARD: String = "billboard"
const PYLON: String = "pylon"
const FLAG_KINDS: Array[String] = ["flagRed", "flagGreen", "flagCheckers"]
const TREE_KINDS: Array[String] = [
	"tree_oak", "tree_default", "tree_pineTallA", "tree_cone", "tree_fat",
]

const CORNER_CHARS: String = "RLW"
const STRAIGHT_CHARS: String = "SPEGBJC"
const PIT_CHARS: String = "PEG"

## How many cells deep the tree band rings the bowl's plan.
const RING_DEPTH: int = 3
## How many cells outside the plan the floodlights stand.
const LIGHT_INSET: int = 2
## Tyre stacks either side of a fast corner's apex, in metres.
const TYRE_OFFSETS: Array[float] = [-4.0, 0.0, 4.0]
## Tree scale range. The band should read as a wood, not a line of clones.
const TREE_SCALE_MIN: float = 0.85
const TREE_SCALE_MAX: float = 1.15

## Centreline samples used for the outside sign and the plan bounds.
const SAMPLE_POINTS: int = 96

const INVALID_CELL: Vector2i = Vector2i(-999999, -999999)


## Builds the whole bowl under `holder` and returns the object/draw statistics.
## `rows` is the map's ASCII grid, so the layout follows a grid edit.
static func build(holder: Node3D, spline: RefCounted,
		rows: PackedStringArray) -> Dictionary:
	var stats: Dictionary = {
		"barriers": 0, "stands": 0, "gantry": 0, "pit": 0, "signage": 0,
		"flags": 0, "lights": 0, "tyres": 0, "trees": 0, "objects": 0,
		"draws": 0, "lap": 0.0,
	}
	if holder == null or spline == null:
		return stats
	var cells: Dictionary = _read_grid(rows)
	var lap: Dictionary = _trace_lap(cells)
	if lap.is_empty():
		push_warning("StadiumLayout: the grid is not one closed lap; only the barrier ring was built.")
	var scale: float = _lap_scale(spline, lap)
	var outside: float = _outside_side(spline)
	var inside: float = -outside
	var claimed: Dictionary = {}
	var bounds: Rect2i = _plan_bounds(spline)
	var runs: Array = _stand_runs(lap)
	var pit: Dictionary = _pit_run(lap, scale)

	# The ring first: it defines the edge no other prop may cross.
	stats["barriers"] = _barrier_ring(holder, spline)
	# Structures claim their cells before the small props.
	stats["stands"] = _grandstands(holder, spline, lap, scale, outside, claimed)
	stats["gantry"] = TileKit.gantry(holder, spline, 0.0)
	stats["pit"] = _pit_building(holder, spline, pit, inside, claimed)
	stats["signage"] = _signage(holder, spline, lap, runs, pit, scale, outside,
		inside, claimed)
	stats["flags"] = _flags(holder, spline, lap, scale, inside, claimed)
	stats["lights"] = _lights(holder, bounds, claimed)
	stats["tyres"] = _tyre_walls(holder, spline, lap, scale, outside)
	# Foliage last, on the cells nobody claimed.
	stats["trees"] = _tree_band(holder, spline, bounds, claimed)

	stats["lap"] = float(spline.total_length)
	var objects: int = 0
	for key: String in ["barriers", "stands", "gantry", "pit", "signage",
			"flags", "lights", "tyres", "trees"]:
		objects += int(stats.get(key, 0))
	stats["objects"] = objects
	stats["draws"] = count_geometry(holder)
	return stats


## Every GeometryInstance3D the theme added is one draw unit in this kit: the
## MultiMesh batches hold one node per mesh part.
static func count_geometry(node: Node) -> int:
	var count: int = 1 if node is GeometryInstance3D else 0
	for child: Node in node.get_children():
		count += count_geometry(child)
	return count


# --------------------------------------------------------------------------
# barrier ring


## Two runs per side. A full-lap span snaps to a near-zero arc inside TileKit,
## so the ring is split half a tile before the line and the short second run
## carries the wall across the start/finish.
static func _barrier_ring(holder: Node3D, spline: RefCounted) -> int:
	var total: float = maxf(float(spline.total_length), 1.0)
	var seam: float = fposmod(round((total - CELL * 0.5) / TileKit.SNAP_STEP) \
		* TileKit.SNAP_STEP, total)
	if seam < CELL:
		seam = fposmod(round(total * 0.5 / TileKit.SNAP_STEP) \
			* TileKit.SNAP_STEP, total)
	var placed: int = 0
	for side: float in [-1.0, 1.0]:
		placed += TileKit.barrier_line(holder, spline, 0.0, seam, side,
			BARRIER_KIND)
		placed += TileKit.barrier_line(holder, spline, seam, total, side,
			BARRIER_KIND)
	return placed


# --------------------------------------------------------------------------
# stands


## An open stand on every cell of the two longest straights and a covered stand
## on the apex of all four corners: the bowl that gives the map its name.
static func _grandstands(holder: Node3D, spline: RefCounted, lap: Dictionary,
		scale: float, outside: float, claimed: Dictionary) -> int:
	var placed: int = 0
	for cell: Vector2i in _stand_cells(lap):
		placed += TileKit.grandstand(holder, spline,
			_lap_distance(lap, cell, scale), outside, false)
		claimed[cell] = true
	for cell: Vector2i in _corners(lap):
		placed += TileKit.grandstand(holder, spline,
			_lap_distance(lap, cell, scale), outside, true)
		claimed[cell] = true
	return placed


## Cells of the two longest straight runs. One run is the pit straight, the
## other is the back straight; they are the two sides the bowl faces.
static func _stand_cells(lap: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for group: Array in _stand_runs(lap):
		for cell: Vector2i in group:
			if not cells.has(cell):
				cells.append(cell)
	return cells


## Straight cells grouped by row and by column. The two biggest groups win, so
## an edited grid moves the runs without touching this file.
static func _stand_runs(lap: Dictionary) -> Array:
	var order: Array = lap.get("order", [])
	var chars: Dictionary = lap.get("chars", {})
	var rows: Dictionary = {}
	var columns: Dictionary = {}
	for cell: Vector2i in order:
		if CORNER_CHARS.contains(str(chars.get(cell, "X"))):
			continue
		if not rows.has(cell.y):
			rows[cell.y] = []
		(rows[cell.y] as Array).append(cell)
		if not columns.has(cell.x):
			columns[cell.x] = []
		(columns[cell.x] as Array).append(cell)
	var groups: Array = []
	for row: int in rows:
		groups.append(rows[row])
	for column: int in columns:
		groups.append(columns[column])
	# The two biggest groups, picked without sort_custom(): a hand-rolled
	# comparison keeps the build free of lambdas that could outlive it.
	var first: int = -1
	var second: int = -1
	for index in groups.size():
		var size: int = (groups[index] as Array).size()
		if first < 0 or size > (groups[first] as Array).size():
			second = first
			first = index
		elif second < 0 or size > (groups[second] as Array).size():
			second = index
	var runs: Array = []
	for index: int in [first, second]:
		if index < 0:
			continue
		var group: Array = groups[index]
		_sort_cells(lap, group)
		runs.append(group)
	return runs


## Insertion sort of `cells` by lap distance, in place. The groups are a handful
## of cells, so this costs nothing and needs no Callable.
static func _sort_cells(lap: Dictionary, cells: Array) -> void:
	for index in range(1, cells.size()):
		var cell: Vector2i = cells[index]
		var distance: float = _lap_distance(lap, cell, 1.0)
		var probe: int = index - 1
		while probe >= 0 \
				and _lap_distance(lap, cells[probe] as Vector2i, 1.0) > distance:
			cells[probe + 1] = cells[probe]
			probe -= 1
		cells[probe + 1] = cell


## The straight run the pit lane is not on. The infield pylon line uses it so a
## pylon never lands in the pit building.
static func _back_run(lap: Dictionary, runs: Array) -> Array:
	if runs.is_empty():
		return []
	var chars: Dictionary = lap.get("chars", {})
	var main: int = 0
	for index in runs.size():
		for cell: Vector2i in runs[index] as Array:
			if PIT_CHARS.contains(str(chars.get(cell, "X"))):
				main = index
				break
	return runs[(main + 1) % runs.size()] as Array


## Corner cells in lap order.
static func _corners(lap: Dictionary) -> Array[Vector2i]:
	var corners: Array[Vector2i] = []
	var chars: Dictionary = lap.get("chars", {})
	for cell: Vector2i in lap.get("order", []) as Array:
		if CORNER_CHARS.contains(str(chars.get(cell, "X"))):
			corners.append(cell)
	return corners


# --------------------------------------------------------------------------
# pit building


## Arc distances of the pit complex. The pit cells (P, E, G) get one garage each
## with one more at either end, and the banner towers stand a further cell out.
## Garages sit one cell to the inside of the pit lane.
static func _pit_run(lap: Dictionary, scale: float) -> Dictionary:
	var run: Dictionary = {"garages": [], "towers": []}
	var pit: Array[Vector2i] = []
	var chars: Dictionary = lap.get("chars", {})
	for cell: Vector2i in lap.get("order", []) as Array:
		if PIT_CHARS.contains(str(chars.get(cell, "X"))):
			pit.append(cell)
	if pit.is_empty():
		return run
	var first: float = _lap_distance(lap, pit[0], scale)
	var last: float = _lap_distance(lap, pit[pit.size() - 1], scale)
	var garages: Array = [first - CELL * scale]
	for cell: Vector2i in pit:
		garages.append(_lap_distance(lap, cell, scale))
	garages.append(last + CELL * scale)
	run["garages"] = garages
	run["towers"] = [first - CELL * 2.0 * scale, last + CELL * 2.0 * scale]
	return run


## The garage block itself. TileKit.pit_building batches all six garages into one
## MultiMesh and gives each its own WORLD box.
static func _pit_building(holder: Node3D, spline: RefCounted, pit: Dictionary,
		inside: float, claimed: Dictionary) -> int:
	var positions: Array = []
	for distance: float in pit.get("garages", []):
		var cell: Vector2i = _prop_cell(spline, distance, inside, claimed)
		if cell == INVALID_CELL:
			continue
		positions.append(_cell_point(cell))
	if positions.is_empty():
		return 0
	return TileKit.pit_building(holder, positions)


# --------------------------------------------------------------------------
# signage and flags


## Billboards and pylons on the two open side straights, a pylon line inside the
## back straight and one banner tower at each end of the pit building. One
## TileKit.signage call batches them into three MultiMeshes.
static func _signage(holder: Node3D, spline: RefCounted, lap: Dictionary,
		runs: Array, pit: Dictionary, scale: float, outside: float,
		inside: float, claimed: Dictionary) -> int:
	var entries: Array = []
	for distance: float in pit.get("towers", []):
		var cell: Vector2i = _prop_cell(spline, distance, inside, claimed)
		if cell == INVALID_CELL:
			continue
		var point: Vector3 = _cell_point(cell)
		entries.append({"position": point, "kind": START_TOWER,
			"yaw": _face_track(spline, point)})
	var side: Array[Vector2i] = _side_cells(lap)
	for index in side.size():
		var cell: Vector2i = _prop_cell(spline,
			_lap_distance(lap, side[index], scale), outside, claimed)
		if cell == INVALID_CELL:
			continue
		var point: Vector3 = _cell_point(cell)
		entries.append({
			"position": point,
			"kind": BILLBOARD if index % 2 == 0 else PYLON,
			"yaw": _face_track(spline, point),
		})
	var back: Array = _back_run(lap, runs)
	var pylons: int = 0
	for index in range(2, back.size(), 2):
		if pylons >= 3:
			break
		var probe: Vector2i = back[index]
		var cell: Vector2i = _prop_cell(spline,
			_lap_distance(lap, probe, scale), inside, claimed)
		if cell == INVALID_CELL:
			continue
		entries.append({"position": _cell_point(cell), "kind": PYLON,
			"yaw": 0.0})
		pylons += 1
	if entries.is_empty():
		return 0
	return TileKit.signage(holder, entries)


## The straight cells the two grandstand runs do not cover: the short sides of
## the bowl. The flag line and the side signage live here.
static func _side_cells(lap: Dictionary) -> Array[Vector2i]:
	var runs: Array[Vector2i] = _stand_cells(lap)
	var chars: Dictionary = lap.get("chars", {})
	var side: Array[Vector2i] = []
	for cell: Vector2i in lap.get("order", []) as Array:
		if CORNER_CHARS.contains(str(chars.get(cell, "X"))):
			continue
		if runs.has(cell):
			continue
		side.append(cell)
	return side


## One flag pole per cell down the infield edge of both short sides: the fence
## reads as dressed from every seat in the bowl.
static func _flags(holder: Node3D, spline: RefCounted, lap: Dictionary,
		scale: float, inside: float, claimed: Dictionary) -> int:
	var entries: Array = []
	var side: Array[Vector2i] = _side_cells(lap)
	for index in side.size():
		var cell: Vector2i = _prop_cell(spline,
			_lap_distance(lap, side[index], scale), inside, claimed)
		if cell == INVALID_CELL:
			continue
		entries.append({"position": _cell_point(cell),
			"kind": FLAG_KINDS[index % FLAG_KINDS.size()], "yaw": 0.0})
	if entries.is_empty():
		return 0
	return TileKit.flags(holder, entries)


# --------------------------------------------------------------------------
# floodlights and foliage


## Eight floodlights on the lattice outside the bowl: one at each outer corner
## of the plan and one at the middle of each long side. TileKit.lights batches
## the posts into one MultiMesh and gives each a cylinder on WORLD.
static func _lights(holder: Node3D, bounds: Rect2i,
		claimed: Dictionary) -> int:
	var min_col: int = bounds.position.x
	var max_col: int = bounds.position.x + bounds.size.x - 1
	var min_row: int = bounds.position.y
	var max_row: int = bounds.position.y + bounds.size.y - 1
	var left: int = min_col - LIGHT_INSET
	var right: int = max_col + LIGHT_INSET
	var top: int = min_row - LIGHT_INSET
	var bottom: int = max_row + LIGHT_INSET
	var cells: Array[Vector2i] = [
		Vector2i(left, top), Vector2i(right, top),
		Vector2i(left, bottom), Vector2i(right, bottom),
		Vector2i(left, min_row + 3), Vector2i(left, max_row - 2),
		Vector2i(right, min_row + 3), Vector2i(right, max_row - 2),
	]
	var positions: Array = []
	for cell: Vector2i in cells:
		if claimed.has(cell):
			continue
		claimed[cell] = true
		positions.append(_cell_point(cell))
	if positions.is_empty():
		return 0
	return TileKit.lights(holder, positions)


## The tree band: every lattice cell in a ring two cells deep outside the bowl's
## plan, minus the cells a structure claimed. The band starts outside the plan,
## which already includes the grandstand offset, so a tree can never grow inside
## the barrier ring while the horizon still fills.
static func _tree_band(holder: Node3D, spline: RefCounted, bounds: Rect2i,
		claimed: Dictionary) -> int:
	var min_col: int = bounds.position.x - RING_DEPTH
	var max_col: int = bounds.position.x + bounds.size.x - 1 + RING_DEPTH
	var min_row: int = bounds.position.y - RING_DEPTH
	var max_row: int = bounds.position.y + bounds.size.y - 1 + RING_DEPTH
	var entries: Array = []
	for row in range(min_row, max_row + 1):
		for col in range(min_col, max_col + 1):
			var cell := Vector2i(col, row)
			if bounds.has_point(cell) or claimed.has(cell):
				continue
			var hash: int = _cell_hash(cell)
			entries.append({
				"position": _cell_point(cell),
				"kind": TREE_KINDS[posmod(hash, TREE_KINDS.size())],
				"scale": TREE_SCALE_MIN + (TREE_SCALE_MAX - TREE_SCALE_MIN) \
					* float((hash >> 4) % 100) / 100.0,
			})
	if entries.is_empty():
		return 0
	return TileKit.trees(holder, entries, spline)


# --------------------------------------------------------------------------
# tyres


## Tyre walls at the two fastest corners, i.e. the corners that close the two
## longest straights. Three stacks spaced either side of the apex.
static func _tyre_walls(holder: Node3D, spline: RefCounted, lap: Dictionary,
		scale: float, outside: float) -> int:
	var placed: int = 0
	for cell: Vector2i in _fast_corners(lap):
		var apex: float = _lap_distance(lap, cell, scale)
		for offset: float in TYRE_OFFSETS:
			placed += TileKit.tyre_stack(holder, spline, apex + offset, outside)
	return placed


## The corners with the longest straight before them. The grid's two long
## straights end in exactly two of them, which is what makes them the fast ones.
static func _fast_corners(lap: Dictionary) -> Array[Vector2i]:
	var order: Array = lap.get("order", [])
	var chars: Dictionary = lap.get("chars", {})
	var lengths: Dictionary = lap.get("length", {})
	var corners: Array[Vector2i] = []
	var approaches: Array[float] = []
	var run: float = 0.0
	for cell: Vector2i in order:
		if CORNER_CHARS.contains(str(chars.get(cell, "X"))):
			corners.append(cell)
			approaches.append(run)
			run = 0.0
		else:
			run += float(lengths.get(cell, CELL))
	var first: int = -1
	var second: int = -1
	for index in corners.size():
		if first < 0 or approaches[index] > approaches[first]:
			second = first
			first = index
		elif second < 0 or approaches[index] > approaches[second]:
			second = index
	var fastest: Array[Vector2i] = []
	for index: int in [first, second]:
		if index >= 0:
			fastest.append(corners[index])
	return fastest


# --------------------------------------------------------------------------
# grid tracing


## ASCII cells of the map keyed by (column, row). Characters are normalised the
## way KenneyTiles parses them; X means there is no tile.
static func _read_grid(rows: PackedStringArray) -> Dictionary:
	var cells: Dictionary = {}
	for row in rows.size():
		var line: String = rows[row]
		for col in line.length():
			var char: String = line[col].to_upper()
			if char == "X" or char == " " or char == "." or char == "-" \
					or char == "_":
				continue
			cells[Vector2i(col, row)] = char
	return cells


## Walks the ASCII grid once into lap order. `entry` and `anchor` are arc
## distances on the grid's own lattice (`anchor` is the tile centre of a
## straight and the apex of a corner), and `total` is the lap length they add up
## to. An empty dictionary means the grid is not a single closed loop.
static func _trace_lap(cells: Dictionary) -> Dictionary:
	if cells.is_empty():
		return {}
	var start: Vector2i = _start_cell(cells)
	if start == INVALID_CELL:
		return {}
	var best: Dictionary = {}
	for heading: Vector2i in [Vector2i(1, 0), Vector2i(0, 1),
			Vector2i(-1, 0), Vector2i(0, -1)]:
		var walk: Dictionary = _walk(cells, start, heading)
		if walk.is_empty():
			continue
		if best.is_empty() or float(walk["total"]) > float(best["total"]):
			best = walk
	return best


## Follows one heading from `start` until the walk closes. A tile that runs off
## the grid or reaches a cell twice fails the walk.
static func _walk(cells: Dictionary, start: Vector2i,
		heading: Vector2i) -> Dictionary:
	var order: Array[Vector2i] = []
	var entry: Dictionary = {}
	var anchor: Dictionary = {}
	var lengths: Dictionary = {}
	var chars: Dictionary = {}
	var travelled: float = 0.0
	var cell: Vector2i = start
	var direction: Vector2i = heading
	for _step in cells.size() * 2 + 8:
		if not cells.has(cell) or entry.has(cell):
			return {}
		var char: String = str(cells[cell])
		var length: float = _tile_length(char)
		order.append(cell)
		chars[cell] = char
		entry[cell] = travelled
		anchor[cell] = travelled + length * 0.5
		lengths[cell] = length
		travelled += length
		direction = _exit_heading(char, direction)
		cell += direction
		if cell == start:
			if order.size() < 8:
				return {}
			return {"order": order, "entry": entry, "anchor": anchor,
				"length": lengths, "chars": chars, "total": travelled}
	return {}


## First straight tile in row-major order, which is the cell KenneyTiles starts
## its lap from, so the theme's phase matches the engine's.
static func _start_cell(cells: Dictionary) -> Vector2i:
	var best: Vector2i = INVALID_CELL
	for cell: Vector2i in cells:
		if not STRAIGHT_CHARS.contains(str(cells[cell])):
			continue
		if best == INVALID_CELL or cell.y < best.y \
				or (cell.y == best.y and cell.x < best.x):
			best = cell
	if best != INVALID_CELL:
		return best
	for cell: Vector2i in cells:
		if best == INVALID_CELL or cell.y < best.y \
				or (cell.y == best.y and cell.x < best.x):
			best = cell
	return best


## Heading a tile sends the lap out on. A corner turns onto the side its
## character names; every straight-through tile keeps the heading.
static func _exit_heading(char: String, heading: Vector2i) -> Vector2i:
	match char:
		"R", "W":
			return Vector2i(-heading.y, heading.x)
		"L":
			return Vector2i(heading.y, -heading.x)
		_:
			return heading


## Arc length one tile adds to the lap, in metres. A corner is a quarter circle
## of half a cell; every straight-through piece crosses a whole cell.
static func _tile_length(char: String) -> float:
	if CORNER_CHARS.contains(char):
		return CELL * PI * 0.25
	return CELL


## The grid's lap length scaled onto the spline's. 1.0 on the grid spline, whose
## lap length is exactly the sum of the tile lengths, and the proportional
## factor on the legacy TrackSpline.
static func _lap_scale(spline: RefCounted, lap: Dictionary) -> float:
	if lap.is_empty():
		return 0.0
	var grid_total: float = maxf(float(lap.get("total", 1.0)), 1.0)
	return maxf(float(spline.total_length), 1.0) / grid_total


static func _lap_distance(lap: Dictionary, cell: Vector2i,
		scale: float) -> float:
	var anchors: Dictionary = lap.get("anchor", {})
	return float(anchors.get(cell, 0.0)) * scale


# --------------------------------------------------------------------------
# placement


## Cell a lattice prop lands on: one whole cell to `side` of the centreline at
## the tile's arc position, snapped to the nearest cell. INVALID_CELL when that
## cell touches the racing surface or a structure already claimed it.
static func _prop_cell(spline: RefCounted, distance: float, side: float,
		claimed: Dictionary) -> Vector2i:
	var point: Vector3 = _sample_point(spline, distance, PROP_OFFSET * side)
	var cell: Vector2i = _cell_of(point)
	if claimed.has(cell):
		return INVALID_CELL
	if TileKit.spline_distance(spline, _cell_point(cell)) < TRACK_CLEARANCE:
		return INVALID_CELL
	claimed[cell] = true
	return cell


static func _sample_point(spline: RefCounted, distance: float,
		lateral: float) -> Vector3:
	var frame: Dictionary = spline.sample(distance)
	var position: Vector3 = frame["position"]
	var right: Vector3 = frame["right"]
	var point: Vector3 = position + right * lateral
	point.y = 0.0
	return point


## Nearest cell centre. Mirrors TileKit's own snap so a prop this module names
## and the prop TileKit places are the same point on the lattice.
static func _cell_of(point: Vector3) -> Vector2i:
	return Vector2i(int(floor(point.x / CELL)), int(floor(point.z / CELL)))


static func _cell_point(cell: Vector2i) -> Vector3:
	return Vector3((float(cell.x) + 0.5) * CELL, 0.0,
		(float(cell.y) + 0.5) * CELL)


## +1 when the outside of the lap is the right-hand side, -1 when it is the
## left. Both grid and legacy loops are authored clockwise, where the outside is
## the left, but the sign is measured from the loop so a mirrored layout still
## dresses outside its barrier.
static func _outside_side(spline: RefCounted) -> float:
	var total: float = maxf(float(spline.total_length), 1.0)
	var previous: Vector3 = spline.sample(0.0)["position"]
	var area: float = 0.0
	for index in range(1, SAMPLE_POINTS + 1):
		var point: Vector3 = spline.sample(
			total * float(index) / float(SAMPLE_POINTS))["position"]
		area += previous.x * point.z - point.x * previous.z
		previous = point
	# +x then +z is clockwise seen from above in Godot's +Z-down top view; a
	# clockwise lap turns right into the infield, so its outside is its left.
	return -1.0 if area > 0.0 else 1.0


## Cell rectangle the bowl occupies: the centreline's plan bounds grown by the
## grandstand offset, so the stands, the lights and the tree band all key off one
## rectangle instead of hard-coded columns.
static func _plan_bounds(spline: RefCounted) -> Rect2i:
	var total: float = maxf(float(spline.total_length), 1.0)
	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF
	for index in SAMPLE_POINTS:
		var point: Vector3 = spline.sample(
			total * float(index) / float(SAMPLE_POINTS))["position"]
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
		min_z = minf(min_z, point.z)
		max_z = maxf(max_z, point.z)
	var margin: float = TileKit.STAND_OFFSET
	var min_col: int = int(floor((min_x - margin) / CELL))
	var max_col: int = int(floor((max_x + margin) / CELL))
	var min_row: int = int(floor((min_z - margin) / CELL))
	var max_row: int = int(floor((max_z + margin) / CELL))
	return Rect2i(min_col, min_row, max_col - min_col + 1,
		max_row - min_row + 1)


## Yaw that turns a sign's panel towards the centreline. Signs read from both
## sides, so this only decides which face the chase camera sees first.
static func _face_track(spline: RefCounted, point: Vector3) -> float:
	var hit: Dictionary = spline.closest(point)
	var target: Vector3 = hit.get("point", Vector3.ZERO)
	var delta: Vector3 = target - point
	if delta.length_squared() < 0.01:
		return 0.0
	return atan2(delta.x, delta.z)


## Stable per-cell seed for the tree kind and scale. The band must look the
## same on every build, so the variation may not use a random generator.
static func _cell_hash(cell: Vector2i) -> int:
	return absi((cell.x * 73856093) ^ (cell.y * 19349663))
