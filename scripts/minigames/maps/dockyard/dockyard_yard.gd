extends RefCounted
## Industrial backdrop for the Dockyard Quay theme.
##
## The container yard, pit garages and quay fence are what make the map read as
## a working dock instead of a bare circuit. Everything is a Kenney racing kit
## piece: `pitsGarage` and `pitsOffice` for the pit complex, `roadPitGarage` for
## the flat pit apron, `barrierWall` blocks stacked two or three high for the
## container rows, and `fenceStraight` for the catch fence beyond the barriers.
##
## Grid maps hang the yard off exact cells (rows 3-6 of the infield plus the two
## outer columns). The legacy spline path finds the longest straight run and
## lays the same rows out on lattice slots along it, snapped to the same 16 m
## grid. Every model batch goes through Parts/TileKit, so the whole yard is a
## handful of draw calls, and every solid piece gets an explicit WORLD box.

const TileKit := preload("res://scripts/minigames/tile_kit.gd")
const Parts := preload("res://scripts/minigames/maps/dockyard/dockyard_parts.gd")

const PAD_MODEL: String = "roadPitGarage"
const GARAGE_MODEL: String = "pitsGarage"
const KIOSK_MODEL: String = "pitsOffice"
const OFFICE_MODEL: String = "pitsOfficeRoof"
const CONTAINER_MODEL: String = "barrierWall"
const FENCE_MODEL: String = "fenceStraight"

const PAD_SCALE: Vector3 = Vector3(TileKit.TILE_SIZE, TileKit.TILE_SIZE * 0.12,
	TileKit.TILE_SIZE)
## Container rows: 16 m blocks stacked on the cell lattice.
const CONTAINER_LEVELS: int = 2
const CONTAINER_COLLIDER_DEPTH: float = 1.97
## Pit and yard rows on the grid map.
const PIT_ROW: int = 5
const APRON_ROW: int = 6
const PIT_FIRST_COL: int = 4
const PIT_LAST_COL: int = 10
## Clearance for the legacy yard: far enough from the barrier run to drive past.
const ARC_CLEAR: float = 10.0


## Builds the yard, pit complex and fence, returning {objects, draws, ...}.
static func build(parent: Node3D, spline: RefCounted,
		plan: RefCounted) -> Dictionary:
	var stats: Dictionary = {
		"objects": 0, "draws": 0, "containers": 0, "pit_bays": 0,
		"fence": 0,
	}
	if parent == null or spline == null or plan == null:
		return stats
	if plan.is_grid():
		_grid_yard(parent, spline, plan, stats)
		_grid_fence(parent, plan, stats)
	else:
		_arc_yard(parent, spline, plan, stats)
		_arc_fence(parent, spline, plan, stats)
	return stats


# --------------------------------------------------------------------------
# grid yard


static func _grid_yard(parent: Node3D, _spline: RefCounted, plan: RefCounted,
		stats: Dictionary) -> void:
	_apron(parent, plan, stats)
	_garages(parent, plan, stats)
	_offices(parent, plan, stats)
	_containers(parent, plan, stats)


## Flat `roadPitGarage` pads in front of the garages, painted just above the
## concrete. They are markings, not solid props, so they carry no collider.
static func _apron(parent: Node3D, plan: RefCounted,
		stats: Dictionary) -> void:
	var transforms: Array = []
	for col in range(PIT_FIRST_COL, PIT_LAST_COL + 1):
		var cell := Vector2i(col, APRON_ROW)
		if not plan.take(cell):
			continue
		transforms.append(Parts.fit(PAD_MODEL, plan.cell_point(cell),
			0.0, PAD_SCALE))
	if transforms.is_empty():
		return
	stats["draws"] = int(stats["draws"]) \
		+ Parts.batch(parent, PAD_MODEL, transforms, "PitApron", false)
	stats["objects"] = int(stats["objects"]) + transforms.size()


## One row of garages on the grid. TileKit owns the batch and the colliders.
static func _garages(parent: Node3D, plan: RefCounted,
		stats: Dictionary) -> void:
	var cells: Array = []
	for col in range(PIT_FIRST_COL, PIT_LAST_COL + 1):
		var cell := Vector2i(col, PIT_ROW)
		if plan.take(cell):
			cells.append(cell)
	if cells.is_empty():
		return
	var placed: int = TileKit.pit_building(parent, cells)
	if placed <= 0:
		return
	stats["objects"] = int(stats["objects"]) + placed
	stats["pit_bays"] = int(stats["pit_bays"]) + placed
	stats["draws"] = int(stats["draws"]) \
		+ Parts.part_count(GARAGE_MODEL)


## Two office blocks behind the pit row and two small race-control kiosks at
## the apron ends. All three models are solid, so each gets a WORLD box.
static func _offices(parent: Node3D, plan: RefCounted,
		stats: Dictionary) -> void:
	var blocks: Array = []
	var block_points: Array = []
	for cell: Vector2i in [Vector2i(4, 0), Vector2i(10, 0)]:
		if not plan.take(cell):
			continue
		var point: Vector3 = plan.cell_point(cell)
		block_points.append(point)
		blocks.append(Parts.fit(OFFICE_MODEL, point, 0.0,
			Parts.PROP_SCALE))
	var kiosks: Array = []
	var kiosk_points: Array = []
	for cell: Vector2i in [Vector2i(3, APRON_ROW), Vector2i(11, APRON_ROW)]:
		if not plan.take(cell):
			continue
		var point: Vector3 = plan.cell_point(cell)
		kiosk_points.append(point)
		kiosks.append(Parts.fit(KIOSK_MODEL, point, 0.0,
			Parts.PROP_SCALE))
	_office_batch(parent, OFFICE_MODEL, blocks, block_points,
		[0.0, 0.0], "PitOffices", stats)
	_office_batch(parent, KIOSK_MODEL, kiosks, kiosk_points,
		[0.0, 0.0], "PitKiosks", stats)


static func _office_batch(parent: Node3D, model: String, transforms: Array,
		points: Array, yaws: Array, node_name: String,
		stats: Dictionary) -> void:
	if transforms.is_empty():
		return
	var body := Parts.body(parent, node_name + "Body")
	stats["draws"] = int(stats["draws"]) \
		+ Parts.batch(body, model, transforms, node_name, true)
	var size: Vector3 = Parts.size(model, Parts.PROP_SCALE)
	for index in points.size():
		var point: Vector3 = points[index]
		Parts.box(body, point + Vector3.UP * (size.y * 0.5),
			float(yaws[index]), size)
	stats["objects"] = int(stats["objects"]) + transforms.size()


## Stacked `barrierWall` blocks in the infield and along the outer columns.
## Two levels read as a container row; every third stack gets a third level for
## a broken skyline. One batch, one WORLD body, one box per block.
static func _containers(parent: Node3D, plan: RefCounted,
		stats: Dictionary) -> void:
	var placements: Array[Dictionary] = []
	for col: int in [3, 4, 9, 10, 11]:
		placements.append({"cell": Vector2i(col, 3), "yaw": 0.0})
		placements.append({"cell": Vector2i(col, 4), "yaw": 0.0})
	for row in range(3, 7):
		placements.append({"cell": Vector2i(0, row), "yaw": PI * 0.5})
		placements.append({"cell": Vector2i(plan.cols - 1, row),
			"yaw": PI * 0.5})
	var transforms: Array = []
	var colliders: Array[Dictionary] = []
	var piece_height: float = Parts.size(CONTAINER_MODEL,
		Parts.PROP_SCALE).y
	for entry: Dictionary in placements:
		var cell: Vector2i = entry["cell"]
		var yaw: float = float(entry["yaw"])
		if not plan.take(cell):
			continue
		var point: Vector3 = plan.cell_point(cell)
		var levels: int = CONTAINER_LEVELS
		if (cell.x + cell.y) % 3 == 0:
			levels += 1
		for level in levels:
			transforms.append(Parts.fit(CONTAINER_MODEL,
				point + Vector3.UP * (piece_height * float(level)), yaw,
				Parts.PROP_SCALE))
			colliders.append({
				"point": point + Vector3.UP
					* (piece_height * (float(level) + 0.5)),
				"yaw": yaw,
			})
	if transforms.is_empty():
		return
	var body := Parts.body(parent, "DockyardContainers")
	stats["draws"] = int(stats["draws"]) \
		+ Parts.batch(body, CONTAINER_MODEL, transforms, "ContainerStacks", true)
	var dimensions: Vector3 = Vector3(TileKit.TILE_SIZE, piece_height,
		CONTAINER_COLLIDER_DEPTH)
	for collider: Dictionary in colliders:
		Parts.box(body, collider["point"] as Vector3, float(collider["yaw"]),
			dimensions)
	stats["objects"] = int(stats["objects"]) + transforms.size()
	stats["containers"] = int(stats["containers"]) + transforms.size()


# --------------------------------------------------------------------------
# legacy yard


## Pit complex and container rows along the longest straight of a spline map.
static func _arc_yard(parent: Node3D, spline: RefCounted, plan: RefCounted,
		stats: Dictionary) -> void:
	var runs: Array = plan.straight_runs()
	if runs.is_empty():
		return
	var best: Dictionary = runs[0]
	for run: Dictionary in runs:
		if float(run["length"]) > float(best["length"]):
			best = run
	var span: float = float(best["length"])
	var middle: float = float(best["from"]) + span * 0.5
	# The free oval only has short flat stretches; the yard follows the spline
	# piece by piece, so a fixed 96 m complex still reads as one row and never
	# bunches on a corner.
	var step: float = TileKit.TILE_SIZE
	var pad_count: int = 5
	var pads: Array = []
	for index in pad_count:
		var distance: float = middle \
			+ (float(index) - float(pad_count - 1) * 0.5) * step
		var claimed: Variant = _claim_arc(plan, spline, distance,
			step * 1.125, ARC_CLEAR)
		if not (claimed is Vector3):
			continue
		pads.append(Parts.fit(PAD_MODEL, claimed, plan.along_yaw(distance),
			PAD_SCALE))
	if not pads.is_empty():
		stats["draws"] = int(stats["draws"]) \
			+ Parts.batch(parent, PAD_MODEL, pads, "PitApron", false)
		stats["objects"] = int(stats["objects"]) + pads.size()
	_arc_garages(parent, spline, plan, middle, stats)
	_arc_offices(parent, spline, plan, middle, stats)
	_arc_containers(parent, spline, plan, middle, stats)


static func _arc_garages(parent: Node3D, spline: RefCounted, plan: RefCounted,
		middle: float, stats: Dictionary) -> void:
	var count: int = 4
	var transforms: Array = []
	var points: Array = []
	var yaws: Array[float] = []
	for index in count:
		var distance: float = middle \
			+ (float(index) - float(count - 1) * 0.5) * TileKit.TILE_SIZE
		var claimed: Variant = _claim_arc(plan, spline, distance,
			TileKit.TILE_SIZE * 2.125, ARC_CLEAR)
		if not (claimed is Vector3):
			continue
		var point: Vector3 = claimed
		var yaw: float = plan.across_yaw(distance)
		points.append(point)
		transforms.append(Parts.fit(GARAGE_MODEL, point, yaw,
			Parts.PROP_SCALE))
		yaws.append(yaw)
	if transforms.is_empty():
		return
	var body := Parts.body(parent, "DockyardGarages")
	stats["draws"] = int(stats["draws"]) \
		+ Parts.batch(body, GARAGE_MODEL, transforms, "PitGarages", true)
	var size: Vector3 = Parts.size(GARAGE_MODEL, Parts.PROP_SCALE)
	var dimensions := Vector3(minf(size.x, TileKit.TILE_SIZE), size.y,
		minf(size.z, TileKit.TILE_SIZE))
	for index in transforms.size():
		var point: Vector3 = points[index]
		Parts.box(body, point + Vector3.UP * (size.y * 0.5),
			yaws[index], dimensions)
	stats["objects"] = int(stats["objects"]) + transforms.size()
	stats["pit_bays"] = int(stats["pit_bays"]) + transforms.size()


static func _arc_offices(parent: Node3D, spline: RefCounted, plan: RefCounted,
		middle: float, stats: Dictionary) -> void:
	var transforms: Array = []
	var points: Array = []
	var yaws: Array[float] = []
	for offset: float in [-40.0, 40.0]:
		var distance: float = middle + offset
		var claimed: Variant = _claim_arc(plan, spline, distance,
			-TileKit.TILE_SIZE * 3.1, ARC_CLEAR)
		if not (claimed is Vector3):
			continue
		var point: Vector3 = claimed
		var yaw: float = plan.across_yaw(distance)
		points.append(point)
		yaws.append(yaw)
		transforms.append(Parts.fit(OFFICE_MODEL, point, yaw,
			Parts.PROP_SCALE))
	_office_batch(parent, OFFICE_MODEL, transforms, points, yaws,
		"PitOffices", stats)


static func _arc_containers(parent: Node3D, spline: RefCounted,
		plan: RefCounted, middle: float, stats: Dictionary) -> void:
	var count: int = 5
	var piece_height: float = Parts.size(CONTAINER_MODEL,
		Parts.PROP_SCALE).y
	var transforms: Array = []
	var colliders: Array[Dictionary] = []
	for row in 2:
		for index in count:
			var distance: float = middle \
				+ (float(index) - float(count - 1) * 0.5) * TileKit.TILE_SIZE
			var lateral: float = TileKit.TILE_SIZE * (2.875 + float(row) * 0.875)
			var claimed: Variant = _claim_arc(plan, spline, distance, lateral,
				ARC_CLEAR)
			if not (claimed is Vector3):
				continue
			var point: Vector3 = claimed
			var yaw: float = plan.across_yaw(distance)
			for level in CONTAINER_LEVELS:
				transforms.append(Parts.fit(CONTAINER_MODEL,
					point + Vector3.UP * (piece_height * float(level)), yaw,
					Parts.PROP_SCALE))
				colliders.append({
					"point": point + Vector3.UP
						* (piece_height * (float(level) + 0.5)),
					"yaw": yaw,
				})
	if transforms.is_empty():
		return
	var body := Parts.body(parent, "DockyardContainers")
	stats["draws"] = int(stats["draws"]) \
		+ Parts.batch(body, CONTAINER_MODEL, transforms, "ContainerStacks", true)
	var dimensions: Vector3 = Vector3(TileKit.TILE_SIZE, piece_height,
		CONTAINER_COLLIDER_DEPTH)
	for collider: Dictionary in colliders:
		Parts.box(body, collider["point"] as Vector3, float(collider["yaw"]),
			dimensions)
	stats["objects"] = int(stats["objects"]) + transforms.size()
	stats["containers"] = int(stats["containers"]) + transforms.size()


# --------------------------------------------------------------------------
# fence


## Catch fence on the free cells of the quay ring. A cell claimed by a yard
## building is skipped, which reads as a service gate.
static func _grid_fence(parent: Node3D, plan: RefCounted,
		stats: Dictionary) -> void:
	var transforms: Array = []
	var points: Array = []
	var yaws: Array[float] = []
	for cell: Vector2i in plan.ring_cells():
		if not plan.take(cell):
			continue
		var horizontal: bool = cell.y == 1 or cell.y == plan.rows - 2
		var yaw: float = 0.0 if horizontal else PI * 0.5
		var point: Vector3 = plan.cell_point(cell)
		points.append(point)
		transforms.append(Parts.fit(FENCE_MODEL, point, yaw,
			Parts.PROP_SCALE))
		yaws.append(yaw)
	_fence_batch(parent, transforms, points, yaws, stats)


static func _arc_fence(parent: Node3D, spline: RefCounted, plan: RefCounted,
		stats: Dictionary) -> void:
	var transforms: Array = []
	var points: Array = []
	var yaws: Array[float] = []
	for point: Vector3 in plan.arc_slots(16.0, -30.0, false, 22.0):
		var hit: Dictionary = spline.closest(point)
		var yaw: float = plan.across_yaw(float(hit.get("s", 0.0)))
		points.append(point)
		transforms.append(Parts.fit(FENCE_MODEL, point, yaw,
			Parts.PROP_SCALE))
		yaws.append(yaw)
	_fence_batch(parent, transforms, points, yaws, stats)


static func _fence_batch(parent: Node3D, transforms: Array, points: Array,
		yaws: Array[float], stats: Dictionary) -> void:
	if transforms.is_empty():
		return
	var body := Parts.body(parent, "DockyardFence")
	stats["draws"] = int(stats["draws"]) \
		+ Parts.batch(body, FENCE_MODEL, transforms, "QuayFence", false)
	var size: Vector3 = Parts.size(FENCE_MODEL, Parts.PROP_SCALE)
	for index in points.size():
		var point: Vector3 = points[index]
		Parts.box(body, point + Vector3.UP * (size.y * 0.5),
			yaws[index], size)
	stats["objects"] = int(stats["objects"]) + transforms.size()
	stats["fence"] = int(stats["fence"]) + transforms.size()


# --------------------------------------------------------------------------
# helpers


## Snaps an arc-length point to the lattice and claims it, or null when another
## yard row or a stand already owns that cell.
static func _claim_arc(plan: RefCounted, spline: RefCounted, distance: float,
		lateral: float, clearance: float) -> Variant:
	var frame: Dictionary = spline.sample(distance)
	var raw: Vector3 = frame["position"] + frame["right"] * lateral
	var point: Vector3 = TileKit._snap_point(raw)
	if not plan.take_point(point, clearance):
		return null
	return point
