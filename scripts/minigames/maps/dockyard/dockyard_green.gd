extends RefCounted
## Green edge for the Dockyard Quay theme.
##
## The treeline is deliberately outside the catch fence: it gives the quay a
## horizon and hides the edge of the ground apron without ever putting a trunk
## on the racing surface. The Kenney nature kit is the only foliage source; each
## model is batched by TileKit.trees, which also rejects anything inside the
## barrier line and adds a WORLD collider to every trunk, bush and rock.
##
## On a grid map the trees take the free outer lattice cells, then one extra
## lattice ring outside the parsed rows for depth. On the legacy spline they
## take snapped slots beyond the fence ring.

const TileKit := preload("res://scripts/minigames/tile_kit.gd")
const TileCatalog := preload("res://scripts/minigames/tiles/tile_catalog.gd")

const TREE_COUNT: int = 44
const BUSH_COUNT: int = 12
## Legacy spline bands: behind the fence ring at lateral 30 m.
const ARC_TREE_LATERAL: float = -40.0
const ARC_BUSH_LATERAL: float = -35.0
const ARC_TREE_CLEAR: float = 24.0
const ARC_BUSH_CLEAR: float = 22.0


## Builds the treeline and underbrush, returning {objects, draws, trees}.
static func build(parent: Node3D, spline: RefCounted,
		plan: RefCounted) -> Dictionary:
	var stats: Dictionary = {"objects": 0, "draws": 0, "trees": 0}
	if parent == null or spline == null or plan == null:
		return stats
	var tree_points: Array[Vector3] = []
	var bush_points: Array[Vector3] = []
	if plan.is_grid():
		tree_points = plan.tree_points(TREE_COUNT)
		bush_points = plan.tree_points(BUSH_COUNT)
	else:
		var slots: Array = plan.arc_slots(10.0, ARC_TREE_LATERAL, false,
			ARC_TREE_CLEAR)
		for slot: Variant in slots:
			if tree_points.size() >= TREE_COUNT:
				break
			if slot is Vector3:
				tree_points.append(slot)
		var bush_slots: Array = plan.arc_slots(14.0, ARC_BUSH_LATERAL, false,
			ARC_BUSH_CLEAR)
		for slot: Variant in bush_slots:
			if bush_points.size() >= BUSH_COUNT:
				break
			if slot is Vector3:
				bush_points.append(slot)
	var entries: Array = []
	for index in tree_points.size():
		var kind: String = str(TileCatalog.TREE_MODELS[
			index % TileCatalog.TREE_MODELS.size()])
		entries.append({
			"position": tree_points[index],
			"kind": kind,
			"scale": 0.92 + 0.08 * float(index % 4),
		})
	for index in bush_points.size():
		var kind: String = str(TileCatalog.BUSH_MODELS[
			index % TileCatalog.BUSH_MODELS.size()])
		entries.append({
			"position": bush_points[index],
			"kind": kind,
			"scale": 0.55 + 0.06 * float(index % 3),
		})
	if entries.is_empty():
		return stats
	var placed: int = TileKit.trees(parent, entries, spline)
	if placed <= 0:
		return stats
	stats["objects"] = int(stats["objects"]) + placed
	stats["trees"] = int(stats["trees"]) + placed
	stats["draws"] = int(stats["draws"]) + _model_draws(entries)
	return stats


static func _model_draws(entries: Array) -> int:
	var models: Dictionary = {}
	for entry: Variant in entries:
		if entry is Dictionary:
			models[str((entry as Dictionary).get("kind", "tree_default"))] = true
	return models.size()
