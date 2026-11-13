extends RefCounted
class_name KenneyTileCatalog
## Measured data layer for the Kenney grid tile engine.
##
## Every road piece in assets/models/kenney_racing_kit is authored on a 1.0
## model-unit module: roadStraight is 1x1, roadStraightLong is 1x2,
## roadCornerSmall is 1x1 and roadCornerLarge is 2x2. The drivable lane on every
## piece is 0.69027 units wide, its centre sits 0.15 units into the footprint
## and each connector is the midpoint of a footprint edge. That is the grid
## contract the engine trusts; the model origin is an arbitrary export pivot and
## is never used for placement.
##
## One model unit is scaled to TILE_SIZE metres. At 16 m the measured lane is
## 11.04 m wide, which keeps the existing race handling (track_spline/grass_race
## used ROAD_HALF = 5.5 m) and makes the Kenney props read at stadium scale:
## a grandstand is ~14 m tall, a floodlight ~13 m and a barrier ~2.1 m.
##
## Measured footprints (kit units, from each GLB's world AABB) decide which
## pieces can live in one 1x1 ASCII cell:
##   roadStraight 1x1, roadStraightArrow 1x1, roadCornerSmall 1x1,
##   roadRamp 1x1, roadPitStraight 1x1, roadPitGarage 1x1.
##   roadStraightLong 1x2, roadBump 1x2, roadRampLong 1x2, roadPitStraightLong
##   1x2, roadEnd 1x1.5, roadCurved 1.5x2, roadCrossing 2x2, roadCornerLarge
##   2x2, roadCornerLarger 3x3, roadPitEntry 2x2, roadSplit 3x2.
## The long and 2x2 pieces are measured but never placed on the 1-cell ASCII
## grid: they would half-overlap the neighbouring cells and break the rule that
## every visual sits on a tile. B and J compress their long piece into one cell;
## E uses the 1x1 pit straight because the 2x2 pit entry would halve the lane
## width; C is two 1x1 straights crossing on one cell.
##
## Nothing in this file builds nodes. It only measures GLBs once and caches the
## result, so the engine and the prop kit can share the same footprint data.
## Measured fact used by the colliders: every racing kit and nature kit GLB
## ships with zero CollisionShape3D nodes, so KenneyTiles and TileKit add every
## WORLD collider themselves instead of assuming the model carries one.
##
## Contract for the map agents (do not change without updating every map):
##   maps/<id>_theme.gd :  static func build(race: Node3D, spline) -> void
## The theme asks tile_kit.* for dressing and returns nothing. KenneyTiles.build
## owns the road, the spline and the road colliders.

const RACING_ROOT: String = "res://assets/models/kenney_racing_kit/Models/GLTF format/"
const NATURE_ROOT: String = "res://assets/models/kenney_nature_kit/Models/GLTF format/"

## Metres per model unit. Measured module is 1.0 unit, lane 0.69027 units.
const TILE_SIZE: float = 16.0
## Measured drivable lane width of every racing road piece, in model units.
const ROAD_LANE_UNITS: float = 0.69027
## Half width of the drivable lane in metres.
const ROAD_HALF: float = TILE_SIZE * ROAD_LANE_UNITS * 0.5
## Half a tile: the radius the 1-cell corner pieces are authored with.
const HALF_TILE: float = TILE_SIZE * 0.5

## Prop scale for the racing kit: same unit-to-metre ratio as the road.
const PROP_SCALE: float = TILE_SIZE
## Nature pieces are trees and bushes; 0.45 keeps them ~12 m next to the road.
const NATURE_SCALE: float = TILE_SIZE * 0.45
## Trackside distances snap to a quarter tile, lateral offsets to half a metre.
const SNAP_STEP: float = TILE_SIZE * 0.25
const LATERAL_STEP: float = 0.5

## Road tiles keyed by their ASCII character. `model` is the GLB stem, `scale`
## is the extra local scale applied before the unit-to-metre scale.
const ROAD_MODELS: Dictionary = {
	"S": {"model": "roadStraight", "scale": Vector3.ONE},
	"L": {"model": "roadCornerSmall", "scale": Vector3.ONE},
	"R": {"model": "roadCornerSmall", "scale": Vector3.ONE},
	"W": {"model": "roadCornerSmall", "scale": Vector3.ONE},
	"C": {"model": "roadStraight", "scale": Vector3.ONE},
	"B": {"model": "roadBump", "scale": Vector3(1.0, 0.35, 0.5)},
	"J": {"model": "roadRamp", "scale": Vector3(1.0, 0.6, 1.0)},
	"P": {"model": "roadPitStraight", "scale": Vector3.ONE},
	"E": {"model": "roadPitStraight", "scale": Vector3.ONE},
	"G": {"model": "roadPitGarage", "scale": Vector3.ONE},
}

## The first tile of a lap wears start/finish paint instead of plain tarmac.
const START_MODEL: String = "roadStraightArrow"

## Barrier runs. `length` is the piece length in model units; the lattice step
## is always its metric length so a run stays a closed wall.
const BARRIER_SPECS: Dictionary = {
	"barrierRed": {"model": "barrierRed", "length": 0.25, "height": 0.1312,
		"depth": 0.123},
	"barrierWhite": {"model": "barrierWhite", "length": 0.25, "height": 0.1312,
		"depth": 0.123},
	"barrierWall": {"model": "barrierWall", "length": 1.0, "height": 0.1312,
		"depth": 0.123},
}

## Repeated trackside props. `model` is the racing kit stem, `scale` is metres
## per model unit (PROP_SCALE unless the piece is deliberately oversized).
const GRANDSTAND_OPEN: String = "grandStand"
const GRANDSTAND_COVERED: String = "grandStandCovered"
const LIGHT_POST: String = "lightPostLarge"
const LIGHT_GANTRY: String = "overheadLights"
const BILLBOARD: String = "billboard"
const BILLBOARD_LOW: String = "billboardLow"
const PYLON: String = "pylon"
const BANNER_TOWER: String = "bannerTowerRed"
const BANNER_TOWER_GREEN: String = "bannerTowerGreen"
const PIT_GARAGE: String = "pitsGarage"
const PIT_GARAGE_CLOSED: String = "pitsGarageClosed"
const PIT_OFFICE: String = "pitsOfficeRoof"
const SIGN_SCALES: Dictionary = {
	"billboard": 0.60,
	"billboardLow": 0.60,
	"pylon": 1.0,
	"bannerTower": 0.55,
	"bannerTowerRed": 0.55,
	"bannerTowerGreen": 0.55,
}

## Flags and foliage. Nature stems live under the nature kit root.
const FLAG_MODELS: Array[String] = [
	"flagRed", "flagGreen", "flagCheckers", "flagCheckersSmall",
]
const TREE_MODELS: Array[String] = [
	"tree_default", "tree_oak", "tree_pineTallA", "tree_cone", "tree_fat",
	"tree_detailed", "tree_palm",
]
const BUSH_MODELS: Array[String] = [
	"plant_bush", "plant_bushLarge", "plant_flatShort", "rock_largeA",
]

static var _cache: Dictionary = {}


## Measured AABB of a GLB, plus the mesh parts needed to MultiMesh it.
## The dictionary is {ok, path, aabb, center: Vector2, size: Vector3,
## parts: Array[{mesh, transform}]}. The AABB is expressed in the GLB's own
## space (node offsets included, which is what the engine places every piece
## by); `center` is its plan-view centre, the footprint pivot.
static func model_info(model: String, nature: bool = false) -> Dictionary:
	var path: String = (NATURE_ROOT if nature else RACING_ROOT) + model + ".glb"
	if _cache.has(path):
		return _cache[path] as Dictionary
	var info: Dictionary = {"ok": false, "path": path}
	if not ResourceLoader.exists(path):
		push_warning("KenneyTileCatalog: missing model " + path)
		_cache[path] = info
		return info
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		push_warning("KenneyTileCatalog: cannot load " + path)
		_cache[path] = info
		return info
	var root: Node = packed.instantiate()
	var aabb: AABB = _aabb(root, Transform3D.IDENTITY)
	var parts: Array = []
	_collect_parts(root, Transform3D.IDENTITY, parts)
	root.free()
	info["ok"] = true
	info["aabb"] = aabb
	info["center"] = Vector2(
		(aabb.position.x + aabb.end.x) * 0.5,
		(aabb.position.z + aabb.end.z) * 0.5)
	info["size"] = aabb.size
	info["parts"] = parts
	_cache[path] = info
	return info


## Road model stem for an ASCII tile character. Unknown characters fall back to
## the plain straight so a diagnostic build still shows a track.
static func road_model(tile: String) -> String:
	var spec: Variant = ROAD_MODELS.get(tile, null)
	if spec is Dictionary:
		return str((spec as Dictionary).get("model", "roadStraight"))
	return "roadStraight"


## Extra local scale for an ASCII tile character.
static func road_scale(tile: String) -> Vector3:
	var spec: Variant = ROAD_MODELS.get(tile, null)
	if spec is Dictionary:
		var value: Variant = (spec as Dictionary).get("scale", Vector3.ONE)
		if value is Vector3:
			var scale: Vector3 = value
			return scale
	return Vector3.ONE


## Barrier spec for a run kind, or the red barrier when the kind is unknown.
static func barrier_spec(kind: String) -> Dictionary:
	var spec: Variant = BARRIER_SPECS.get(kind, null)
	if spec is Dictionary:
		return spec as Dictionary
	push_warning("KenneyTileCatalog: unknown barrier kind '%s', using barrierRed"
		% kind)
	return BARRIER_SPECS["barrierRed"] as Dictionary


## Metres per model unit for a signage kind.
static func sign_scale(kind: String) -> float:
	return float(SIGN_SCALES.get(kind, 1.0)) * PROP_SCALE


## Safe array element: returns `fallback` when `index` is out of range.
static func pick(options: Array, index: int, fallback: String) -> String:
	if options.is_empty():
		return fallback
	return str(options[posmod(index, options.size())])


# --------------------------------------------------------------------------
# measurement


static func _aabb(node: Node, xform: Transform3D) -> AABB:
	var local: Transform3D = xform
	if node is Node3D:
		local = xform * (node as Node3D).transform
	var result := AABB()
	var found: bool = false
	if node is MeshInstance3D:
		var instance: MeshInstance3D = node as MeshInstance3D
		if instance.mesh != null:
			result = local * instance.mesh.get_aabb()
			found = true
	for child: Node in node.get_children():
		var child_box: AABB = _aabb(child, local)
		if child is MeshInstance3D:
			result = result.merge(child_box) if found else child_box
			found = true
	return result


static func _collect_parts(node: Node, xform: Transform3D, parts: Array) -> void:
	var local: Transform3D = xform
	if node is Node3D:
		local = xform * (node as Node3D).transform
	if node is MeshInstance3D:
		var instance: MeshInstance3D = node as MeshInstance3D
		if instance.mesh != null:
			parts.append({"mesh": instance.mesh, "transform": local})
	for child: Node in node.get_children():
		_collect_parts(child, local, parts)
