extends RefCounted
## Pine forest and underbrush for Glacier Pass.
##
## The trees are the only thing that gives the pass depth, so they are packed
## hard: a band six cells deep around the loop's plan bounds, plus a frozen
## island in the infield, plus underbrush (bushes, small boulders, grass
## clumps) between the trunks. Every pine is a nature-kit GLB; every one is
## given a real trunk collider on CollisionLayers.WORLD, and every position is
## rejected when its plan distance to the racing centreline is inside the
## forest clearance, so a trunk can never stand in a lane.
##
## Draw calls stay low because the pines are batched per model: eight pine
## models and three underbrush models cost eleven MultiMeshes no matter how many
## instances they hold.

const GlacierProps := preload("res://scripts/minigames/maps/glacier/glacier_props.gd")
const TileCatalog := preload("res://scripts/minigames/tiles/tile_catalog.gd")

const TILE: float = TileCatalog.TILE_SIZE
const NATURE: float = TileCatalog.NATURE_SCALE

## Pine stems. Kenney's tall pines are 1.5 model units, so at NATURE_SCALE they
## stand 7-11 m, which is the alpine scale the crest jump wants beside it.
const PINE_MODELS: Array[String] = [
	"tree_pineTallA", "tree_pineTallB", "tree_pineTallC", "tree_pineTallD",
	"tree_pineSmallA", "tree_pineSmallB", "tree_pineRoundA", "tree_cone",
]
## Ground cover between the trunks.
const BRUSH_MODELS: Array[String] = [
	"plant_bushLarge", "plant_bushDetailed", "plant_flatShort",
]
const BRUSH_ROCKS: Array[String] = ["rock_smallA", "rock_smallE"]

## Cells of forest ringing the plan bounds.
const BAND: int = 6
## Percent of eligible band cells that grow a pine.
const BAND_DENSITY: int = 58
## The infield island starts this far from the centreline, so the pines never
## crowd the barriers, and grows this share of eligible cells.
const INFIELD_CLEARANCE: float = 27.0
const INFIELD_DENSITY: int = 34
## A trunk keeps at least this much plan distance from the centreline. It is
## the barrier clearance plus a full cell, so a fallen crown still clears the
## road and the wall.
const FOREST_CLEARANCE: float = 13.2
## Caps so a huge grid cannot blow the object budget.
const MAX_PINES: int = 210
const MAX_BRUSH: int = 70
const PINE_SCALE_MIN: float = 0.85
const PINE_SCALE_MAX: float = 1.25
const TRUNK_RADIUS: float = 0.95
const TRUNK_HEIGHT: float = 3.2
const SEED: int = 20261113
const INVALID_CELL: Vector2i = Vector2i(-999999, -999999)


## Builds the forest under `holder`. Returns {pines, brush, draws, objects}.
static func build(holder: Node3D, spline: RefCounted) -> Dictionary:
	var stats: Dictionary = {"pines": 0, "brush": 0, "draws": 0, "objects": 0}
	if holder == null or spline == null:
		return stats
	var tiles: Variant = spline.get("tiles")
	if not (tiles is Array) or (tiles as Array).is_empty():
		return stats
	var bounds: Rect2i = _plan_bounds(tiles as Array)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var pines: Array = []
	var positions: Array = []
	var brush: Array = []
	var brush_points: Array = []
	# 1. The band outside the loop's plan rectangle: the forest wall.
	for row in range(bounds.position.y - BAND,
			bounds.position.y + bounds.size.y + BAND):
		for col in range(bounds.position.x - BAND,
				bounds.position.x + bounds.size.x + BAND):
			var cell := Vector2i(col, row)
			if bounds.has_point(cell):
				continue
			_grow(cell, BAND_DENSITY, rng, spline, pines, positions, brush,
				brush_points, MAX_PINES - pines.size())
			if pines.size() >= MAX_PINES:
				break
		if pines.size() >= MAX_PINES:
			break
	# 2. The frozen island in the infield: fills the middle of a ring loop so
	# the chase camera never looks across a bare white field.
	if pines.size() < MAX_PINES:
		for row in range(bounds.position.y,
				bounds.position.y + bounds.size.y):
			for col in range(bounds.position.x,
					bounds.position.x + bounds.size.x):
				if pines.size() >= MAX_PINES:
					break
				_grow(Vector2i(col, row), INFIELD_DENSITY, rng, spline, pines,
					positions, brush, brush_points, MAX_PINES - pines.size())
	_flush(holder, spline, pines, positions, brush, brush_points)
	stats["pines"] = pines.size()
	stats["brush"] = brush.size()
	stats["objects"] = pines.size() + brush.size()
	stats["draws"] = _draw_estimate(pines, brush)
	return stats


## Grows one cell: at most one pine and one underbrush clump, both jittered
## inside the cell and both rejected when they would stand inside the forest
## clearance.
static func _grow(cell: Vector2i, density: int,
		rng: RandomNumberGenerator, spline: RefCounted, pines: Array,
		positions: Array, brush: Array, brush_points: Array,
		room: int) -> void:
	if room <= 0 or rng.randi_range(0, 99) >= density:
		return
	var lift := Vector3(float(rng.randf_range(-4.6, 4.6)), 0.0,
		float(rng.randf_range(-4.6, 4.6)))
	var point: Vector3 = _cell_point(cell) + lift
	if GlacierProps.clearance(spline, point) < FOREST_CLEARANCE:
		return
	var model: String = PINE_MODELS[rng.randi_range(0, PINE_MODELS.size() - 1)]
	var scale: float = NATURE * rng.randf_range(PINE_SCALE_MIN,
		PINE_SCALE_MAX)
	pines.append({"model": model,
		"transform": GlacierProps.fit(model, point, rng.randf_range(0.0, TAU),
			scale, true),
		"nature": true})
	positions.append(point)
	if room > 0 and rng.randi_range(0, 99) < 30:
		var shift := Vector3(rng.randf_range(-3.0, 3.0), 0.0,
			rng.randf_range(-3.0, 3.0))
		var clump: Vector3 = point + shift
		if GlacierProps.clearance(spline, clump) >= FOREST_CLEARANCE - 2.0:
			var is_rock: bool = rng.randi_range(0, 99) < 35
			var kind: String = BRUSH_ROCKS[rng.randi_range(0,
				BRUSH_ROCKS.size() - 1)] if is_rock \
				else BRUSH_MODELS[rng.randi_range(0, BRUSH_MODELS.size() - 1)]
			brush.append({"model": kind,
				"transform": GlacierProps.fit(kind, clump,
					rng.randf_range(0.0, TAU),
					NATURE * rng.randf_range(0.30, 0.55), true),
				"nature": true})
			brush_points.append(clump)


## Writes the two batches and the trunk colliders.
static func _flush(holder: Node3D, spline: RefCounted, pines: Array,
		positions: Array, brush: Array, brush_points: Array) -> void:
	if not pines.is_empty():
		var pine_body: StaticBody3D = GlacierProps.body(holder, "GlacierPines")
		GlacierProps.batch(holder, pines, "PineForest", false)
		for point: Variant in positions:
			GlacierProps.cylinder(pine_body, point as Vector3, TRUNK_RADIUS,
				TRUNK_HEIGHT)
		GlacierProps.assert_clearance("GlacierPines", positions, spline)
	if not brush.is_empty():
		var brush_body: StaticBody3D = GlacierProps.body(holder,
			"GlacierBrush")
		GlacierProps.batch(holder, brush, "Underbrush", false)
		for point: Variant in brush_points:
			GlacierProps.cylinder(brush_body, point as Vector3, 0.6, 0.9)


# --------------------------------------------------------------------------
# grid helpers
# --------------------------------------------------------------------------


## Plan bounds of the placed tiles, in cells.
static func _plan_bounds(tiles: Array) -> Rect2i:
	var min_col: int = 1 << 30
	var min_row: int = 1 << 30
	var max_col: int = -(1 << 30)
	var max_row: int = -(1 << 30)
	for entry: Variant in tiles:
		if not (entry is Dictionary):
			continue
		var cell: Variant = (entry as Dictionary).get("cell")
		if not (cell is Vector2i):
			continue
		var key: Vector2i = cell
		min_col = mini(min_col, key.x)
		min_row = mini(min_row, key.y)
		max_col = maxi(max_col, key.x)
		max_row = maxi(max_row, key.y)
	if min_col > max_col:
		return Rect2i(-BAND, -BAND, BAND * 2 + 1, BAND * 2 + 1)
	return Rect2i(min_col, min_row, max_col - min_col + 1,
		max_row - min_row + 1)


static func _cell_point(cell: Vector2i) -> Vector3:
	return Vector3((float(cell.x) + 0.5) * TILE, 0.0,
		(float(cell.y) + 0.5) * TILE)


## One batch per pine model and one per brush model.
static func _draw_estimate(pines: Array, brush: Array) -> int:
	var models: Dictionary = {}
	for entry: Variant in pines:
		models[str((entry as Dictionary)["model"])] = true
	for entry: Variant in brush:
		models[str((entry as Dictionary)["model"])] = true
	return models.size()
