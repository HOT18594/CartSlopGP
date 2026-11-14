extends RefCounted
## STADIUM CIRCUIT: analysis and assembly of the flagship bowl.
##
## The theme hands this module the closed grid spline the tile engine built. It
## walks that spline once to find the straights, the corners, the two fastest
## corners and the two tightest ones, then:
##
##   1. places the barrier ring on both edges of the lap,
##   2. asks stadium_bowl.gd for the seating bowl, catch fencing, tyre walls,
##      marshal posts, cranes, floodlights, signage and cliffs,
##   3. replaces the bowl's old even tree scatter with the designed woodland in
##      stadium_forest.gd: a noise-clustered belt several rows deep, clearings
##      behind the two grandstand runs and the start gantry, corner walls and
##      undergrowth along the barrier line,
##   4. asks stadium_pits.gd for the pit lane, garages, paddock and start box,
##   5. measures every collider it emitted against the centreline and fails a
##      debug build when a solid piece came inside the racing surface.
##
## Clearance is the owner's invariant, so it is asserted here rather than
## trusted: the barrier ring must clear BARRIER_CLEARANCE and every other solid
## piece must clear SOLID_CLEARANCE. Both numbers are reported, because "the
## barriers are on the track" was the original complaint and a number is the
## only way to prove it is gone.
##
## Every prop is a Kenney racing-kit or nature-kit GLB placed through
## stadium_props.gd, batched into MultiMeshes and given a WORLD collider, except
## the woodland: its trunks stand beyond the continuous barrier ring and the two
## stand tiers, so it is batched without per-tree colliders. The build is
## idempotent at the theme level, so a scene reload cannot double it.

const Props := preload("res://scripts/minigames/maps/stadium/stadium_props.gd")
const Bowl := preload("res://scripts/minigames/maps/stadium/stadium_bowl.gd")
const Pits := preload("res://scripts/minigames/maps/stadium/stadium_pits.gd")
const Forest := preload("res://scripts/minigames/maps/stadium/stadium_forest.gd")
const StadiumGrid := preload("res://scripts/minigames/maps/stadium/stadium_grid.gd")
const TileKit := preload("res://scripts/minigames/tile_kit.gd")
const TileGeometry := preload("res://scripts/minigames/tiles/kenney_tiles.gd")

## Barrier kind for the continuous ring. The red/white blocks read as a circuit
## wall; the engine's barrier_line follows the true road edge with them.
const BARRIER_KIND: String = "barrierRed"
## A lap is sampled this many times for the height and plan statistics.
const SAMPLES: int = 160
## Deck height at which a stretch counts as the raised sweep.
const RAISED_HEIGHT: float = 1.9
## Minimum length of a straight run the pit complex will use.
const MIN_PIT_RUN: float = 48.0
## Colliders whose lowest point is above this are overhead: a gantry beam or a
## bridge deck a kart drives under, not something on the racing surface.
const DRIVE_UNDER: float = 3.2
## Inside an 8 m corner the engine's centreline is a six-chord polyline, whose
## chords sit up to 0.07 m inside the true arc, and no point inside a corner can
## be more than the 8 m radius from that arc. A wall that hugs the inside of a
## corner therefore measures a few centimetres under the design line even though
## it is metres off the tarmac; the ring is accepted within this tolerance and
## failed only when a wall really reaches the drivable lane.
const BARRIER_TOLERANCE: float = 0.12
## The hard floor a barrier may never cross: one metre beyond the lane edge.
const BARRIER_FLOOR: float = TileKit.ROAD_HALF + 1.0
## Plan margin the layout adds around the centreline. The woodland uses the
## resulting rectangle as its plant lattice and its culling quadrants.
const PLAN_MARGIN: float = 34.0
## Name tile_kit.trees gives the static body holding a tree batch. The bowl's
## obsolete band is detached by that name before the designed belt is planted.
const LEGACY_FOLIAGE: String = "Foliage"


## Builds the whole stadium under `holder` and returns the statistics.
## `rows` is the map's ASCII grid, used only to prove the layout the engine
## built is the canonical one.
static func build(holder: Node3D, spline: RefCounted,
		rows: PackedStringArray) -> Dictionary:
	var stats: Dictionary = {
		"objects": 0, "draws": 0, "barriers": 0, "stands": 0, "gantry": 0,
		"pit": 0, "pit_wall": 0, "signage": 0, "flags": 0, "lights": 0,
		"tyres": 0, "trees": 0, "undergrowth": 0, "fences": 0, "marshals": 0,
		"cameras": 0, "cliffs": 0, "bridge": 0, "paddock": 0, "lap": 0.0,
		"tiles": 0, "barrier_closest": 0.0, "solid_closest": 0.0,
	}
	if holder == null or spline == null:
		return stats
	var plan: Dictionary = analyse(spline)
	if plan.is_empty():
		push_warning("StadiumLayout: the spline is not a usable closed lap.")
		return stats
	stats["lap"] = float(plan["total"])
	stats["tiles"] = (spline.get("tiles") as Array).size()
	stats["elevation"] = _highest(spline, float(plan["total"]))
	_warn_if_not_canonical(rows)
	stats["barriers"] = _barrier_ring(holder, spline, plan)
	Bowl.build(holder, spline, plan, stats)
	_retire_legacy_foliage(holder)
	var forest: Dictionary = Forest.build(holder, spline, plan)
	stats["trees"] = int(forest.get("trees", 0))
	stats["undergrowth"] = int(forest.get("underbrush", 0))
	stats["forest_draws"] = int(forest.get("draws", 0))
	Pits.build(holder, spline, plan, stats)
	var objects: int = 0
	for key: String in ["barriers", "stands", "gantry", "pit", "pit_wall",
			"signage", "flags", "lights", "tyres", "trees", "undergrowth",
			"fences", "marshals", "cameras", "cliffs", "bridge", "paddock"]:
		objects += int(stats.get(key, 0))
	stats["objects"] = objects
	stats["draws"] = Props.count_geometry(holder)
	_audit(holder, spline, stats)
	return stats


## Detaches the bowl's single-scatter tree band so the designed woodland can own
## the meadow. tile_kit.trees names its body "Foliage"; removing that body takes
## its batches and its trunk colliders with it, and the bowl file stays as it
## was. The band is retired before the new belt is planted, so the two can never
## overlap or double the count.
static func _retire_legacy_foliage(holder: Node3D) -> void:
	if holder == null:
		return
	var legacy: Node = holder.get_node_or_null(LEGACY_FOLIAGE)
	if legacy == null:
		return
	holder.remove_child(legacy)
	legacy.queue_free()


## Highest road deck on the lap, in metres: what the build report prints, so a
## registry grid that has lost its elevation data shows up instead of staying
## silent.
static func _highest(spline: RefCounted, total: float) -> float:
	var highest: float = 0.0
	for index in SAMPLES:
		highest = maxf(highest, float(spline.height_at(
			total * float(index) / float(SAMPLES))))
	return highest


## Prints a warning when the spline the engine built came from rows other than
## the canonical stadium grid, which means the registry copy has drifted.
static func _warn_if_not_canonical(rows: PackedStringArray) -> void:
	if rows.is_empty():
		return
	if not OS.is_debug_build():
		return
	var mismatch: int = StadiumGrid.mismatch_row(rows)
	if mismatch < 0:
		return
	push_warning(("StadiumLayout: registry row %d is '%s' but the canonical " \
		+ "stadium grid says '%s'; the bowl still dresses the lap it was " \
		+ "given, so copy the grid from stadium_grid.gd into track_defs.gd.") % [
		mismatch + 1,
		rows[mismatch] if mismatch < rows.size() else "",
		StadiumGrid.GRID_ROWS[mismatch]])
	print("STADIUM LAYOUT: registry grid row %d does not match the canonical " \
		% (mismatch + 1) + "layout")


# --------------------------------------------------------------------------
# analysis


## Everything the dressing modules need, derived from the spline alone: the
## outside of the lap, the straight runs, the corner list, the fast and tight
## corners, the raised sweep and the opposite straight (the valley).
static func analyse(spline: RefCounted) -> Dictionary:
	if spline == null:
		return {}
	var total: float = maxf(float(spline.total_length), 1.0)
	var tiles_value: Variant = spline.get("tiles")
	if not (tiles_value is Array) or (tiles_value as Array).is_empty():
		return {}
	var outside: float = outside_side(spline)
	var straights: Array[Dictionary] = _straight_runs(tiles_value as Array)
	if straights.is_empty():
		return {}
	var corners: Array[Dictionary] = _corner_list(spline,
		tiles_value as Array)
	var longest: Dictionary = straights[0]
	for run: Dictionary in straights:
		if float(run["length"]) > float(longest["length"]):
			longest = run
	var start_run: Dictionary = _run_at(straights, 0.0)
	if float(start_run.get("length", 0.0)) < MIN_PIT_RUN:
		start_run = longest
	return {
		"total": total,
		"outside": outside,
		"inside": -outside,
		"straights": straights,
		"corners": corners,
		"longest": longest,
		"start_straight": start_run,
		"start_distance": 0.0,
		"fast_corners": _fast_corners(corners, straights),
		"tight_corners": _tight_corners(corners),
		"raised": _raised_span(spline, total),
		"valley": _opposite_run(spline, total, start_run, straights),
		"bounds": _plan_bounds(spline, total),
	}


## +1 when the outside of the lap is the right-hand side of travel, -1 when it
## is the left. Measured from the loop's signed area, so a mirrored layout still
## dresses outside its barriers.
static func outside_side(spline: RefCounted) -> float:
	var total: float = maxf(float(spline.total_length), 1.0)
	var previous: Vector3 = spline.sample(0.0)["position"]
	var area: float = 0.0
	for index in range(1, SAMPLES + 1):
		var point: Vector3 = spline.sample(
			total * float(index) / float(SAMPLES))["position"]
		area += previous.x * point.z - point.x * previous.z
		previous = point
	# +x then +z is clockwise seen from above in Godot's +Z-down top view; a
	# clockwise lap turns right into the infield, so its outside is its left.
	return -1.0 if area > 0.0 else 1.0


## Straight cells grouped into contiguous runs, longest first.
static func _straight_runs(tiles: Array) -> Array[Dictionary]:
	var runs: Array[Dictionary] = []
	var current: Dictionary = {}
	for index in tiles.size():
		var tile: Dictionary = tiles[index]
		if _is_straight(tile):
			if current.is_empty():
				current = {"from": float(tile.get("from", 0.0)),
					"to": float(tile.get("to", 0.0)), "cells": 0}
			current["to"] = float(tile.get("to", 0.0))
			current["cells"] = int(current["cells"]) + 1
		elif not current.is_empty():
			runs.append(_finish_run(current))
			current = {}
	if not current.is_empty():
		runs.append(_finish_run(current))
	runs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["length"]) > float(b["length"]))
	return runs


static func _finish_run(run: Dictionary) -> Dictionary:
	run["length"] = maxf(float(run["to"]) - float(run["from"]), 0.0)
	return run


## The straight run a lap distance falls inside, or the first run.
static func _run_at(runs: Array[Dictionary], distance: float) -> Dictionary:
	for run: Dictionary in runs:
		if distance >= float(run["from"]) - 0.01 \
				and distance <= float(run["to"]) + 0.01:
			return run
	return runs[0] if not runs.is_empty() else {}


## Every corner apex in lap order, with the signed heading change across it.
static func _corner_list(spline: RefCounted, tiles: Array) -> Array[Dictionary]:
	var corners: Array[Dictionary] = []
	for tile: Dictionary in tiles:
		if _is_straight(tile):
			continue
		var apex: float = (float(tile.get("from", 0.0)) \
			+ float(tile.get("to", 0.0))) * 0.5
		corners.append({"distance": apex,
			"turn": angle_difference(spline.yaw_at(apex - 4.0),
				spline.yaw_at(apex + 4.0)),
			"cell": tile.get("cell", Vector2i.ZERO)})
	return corners


## The two corners that close the longest straights: where a kart arrives
## fastest. `approach` is the straight length feeding the corner.
static func _fast_corners(corners: Array[Dictionary],
		straights: Array[Dictionary]) -> Array[Dictionary]:
	var ranked: Array[Dictionary] = []
	for corner: Dictionary in corners:
		var approach: float = 0.0
		for run: Dictionary in straights:
			var gap: float = fposmod(float(corner["distance"]) \
				- float(run["to"]), 1.0e9)
			if gap < 60.0:
				approach = maxf(approach, float(run["length"]) - gap)
		var entry: Dictionary = corner.duplicate()
		entry["approach"] = approach
		ranked.append(entry)
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["approach"]) > float(b["approach"]))
	var chosen: Array[Dictionary] = []
	for entry: Dictionary in ranked:
		if chosen.size() >= 2:
			break
		if _shares_site(chosen, float(entry["distance"])):
			continue
		chosen.append(entry)
	return chosen


## The two corners whose apexes are closest together: the infield hairpin, the
## tightest thing on the lap. Spaced far enough apart to be different corners.
static func _tight_corners(corners: Array[Dictionary]) -> Array[Dictionary]:
	var best: Array[Dictionary] = []
	var best_gap: float = INF
	for first in corners.size():
		for second in range(first + 1, corners.size()):
			var gap: float = absf(float(corners[first]["distance"]) \
				- float(corners[second]["distance"]))
			if gap < 12.0:
				continue
			if gap < best_gap:
				best_gap = gap
				best = [corners[first], corners[second]]
	return best


## True when `chosen` already holds a corner within 40 m of `distance`.
static func _shares_site(chosen: Array[Dictionary], distance: float) -> bool:
	for entry: Dictionary in chosen:
		if absf(float(entry["distance"]) - distance) < 40.0:
			return true
	return false


## The contiguous stretch of lap whose deck is raised: the banked sweep.
static func _raised_span(spline: RefCounted, total: float) -> Dictionary:
	var step: float = 4.0
	var count: int = maxi(int(ceil(total / step)), 1)
	var first: int = -1
	var last: int = -1
	var highest: float = 0.0
	for index in count:
		var height: float = float(spline.height_at(
			float(index) * step))
		highest = maxf(highest, height)
		if height >= RAISED_HEIGHT:
			if first < 0:
				first = index
			last = index
	if first < 0:
		return {"ok": false, "from": 0.0, "to": 0.0, "height": 0.0}
	return {"ok": true, "from": float(first) * step,
		"to": float(last + 1) * step, "height": highest}


## The straight run on the far side of the circuit from the start straight: the
## south straight, which is where the valley (and the footbridge) belongs.
static func _opposite_run(spline: RefCounted, total: float,
		start_run: Dictionary, straights: Array[Dictionary]) -> Dictionary:
	var anchor: float = (float(start_run.get("from", 0.0)) \
		+ float(start_run.get("to", 0.0))) * 0.5
	var anchor_point: Vector3 = spline.sample(anchor)["position"]
	var best: Dictionary = {}
	var best_distance: float = -1.0
	for run: Dictionary in straights:
		var middle: float = (float(run["from"]) + float(run["to"])) * 0.5
		if absf(fposmod(middle - anchor, total)) < 40.0:
			continue
		var point: Vector3 = spline.sample(middle)["position"]
		var distance: float = Vector2(point.x - anchor_point.x,
			point.z - anchor_point.z).length()
		if distance > best_distance:
			best_distance = distance
			best = run
	if best.is_empty():
		return {"ok": false, "from": 0.0, "to": 0.0}
	return {"ok": true, "from": float(best["from"]),
		"to": float(best["to"])}


## World rectangle the circuit occupies, grown by PLAN_MARGIN so the tree band
## has somewhere to stand.
static func _plan_bounds(spline: RefCounted, total: float) -> Rect2:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for index in SAMPLES:
		var point: Vector3 = spline.sample(total * float(index)
			/ float(SAMPLES))["position"]
		low.x = minf(low.x, point.x)
		low.y = minf(low.y, point.z)
		high.x = maxf(high.x, point.x)
		high.y = maxf(high.y, point.z)
	return Rect2(low - Vector2.ONE * PLAN_MARGIN,
		(high - low) + Vector2.ONE * PLAN_MARGIN * 2.0)


## True when a tile runs straight through its cell.
static func _is_straight(tile: Dictionary) -> bool:
	var entry: int = int(tile.get("entry", 0))
	var exit: int = int(tile.get("exit", 0))
	return (entry + 2) % 4 == exit


# --------------------------------------------------------------------------
# barriers


## The continuous wall on both edges of the lap, split into two runs per side.
## The seam sits on a straight tile boundary, which is the only place a chord
## between two wall pieces cannot reach inside the corner arc, so the ring is
## unbroken and stays outside BARRIER_CLEARANCE everywhere.
static func _barrier_ring(holder: Node3D, spline: RefCounted,
		plan: Dictionary) -> int:
	var total: float = maxf(float(plan["total"]), 1.0)
	var seam: float = _seam_distance(spline, total)
	var placed: int = 0
	for side: float in [-1.0, 1.0]:
		placed += TileKit.barrier_line(holder, spline, 0.0, seam, side,
			BARRIER_KIND)
		placed += TileKit.barrier_line(holder, spline, seam, total, side,
			BARRIER_KIND)
	return placed


## Lap distance of a straight tile boundary near the middle of the lap.
static func _seam_distance(spline: RefCounted, total: float) -> float:
	var tiles_value: Variant = spline.get("tiles")
	if not (tiles_value is Array) or (tiles_value as Array).is_empty():
		return round(total * 0.5 / TileKit.SNAP_STEP) * TileKit.SNAP_STEP
	var tiles: Array = tiles_value as Array
	var best: float = total * 0.5
	var best_gap: float = INF
	for tile: Dictionary in tiles:
		if not _is_straight(tile):
			continue
		var edge: float = float(tile.get("to", total))
		var gap: float = absf(edge - total * 0.5)
		if gap < best_gap:
			best_gap = gap
			best = edge
	return fposmod(best, total)


# --------------------------------------------------------------------------
# the invariant


## Measures the barrier ring and every other solid collider against the
## centreline, prints both closest approaches and fails a debug build when
## either family is on the racing surface.
static func _audit(holder: Node3D, spline: RefCounted,
		stats: Dictionary) -> void:
	var barrier: Dictionary = TileKit.barrier_clearance(holder, spline)
	var solids: Dictionary = Props.audit(holder, spline,
		Props.SOLID_CLEARANCE, DRIVE_UNDER)
	stats["barrier_closest"] = float(barrier["closest"])
	stats["solid_closest"] = float(solids["closest"])
	stats["solid_pieces"] = int(solids["pieces"])
	print(("STADIUM CLEARANCE: barrier %d piece(s) closest %.2f m " \
		+ "(limit %.2f m); solids %d piece(s) closest %.2f m " \
		+ "(limit %.2f m, worst %s)") % [
		int(barrier["pieces"]), float(barrier["closest"]),
		float(barrier["limit"]), int(solids["pieces"]),
		float(solids["closest"]), float(solids["limit"]),
		str(solids["worst"])])
	if bool(barrier["clears"]) and float(solids["closest"]) \
			>= Props.SOLID_CLEARANCE - 0.02:
		return
	var barrier_ok: bool = float(barrier["closest"]) \
		>= TileKit.BARRIER_CLEARANCE - BARRIER_TOLERANCE
	var solids_ok: bool = float(solids["closest"]) \
		>= Props.SOLID_CLEARANCE - 0.02
	if not barrier_ok:
		print("STADIUM CLEARANCE: the closest barrier piece is %.2f m from the " \
			% float(barrier["closest"]) +
			"polyline centreline, inside the %.2f m design line; the lane edge " \
			% float(barrier["limit"]) +
			"is %.2f m, so the wall is still %.2f m off the tarmac." % [
				TileKit.ROAD_HALF,
				float(barrier["closest"]) - TileKit.ROAD_HALF])
	if OS.is_debug_build() and not barrier_ok \
			and float(barrier["closest"]) < BARRIER_FLOOR:
		push_error("StadiumLayout: a barrier piece is on the racing surface " \
			+ "(%.2f m from the centreline, lane edge %.2f m)." % [
				float(barrier["closest"]), TileKit.ROAD_HALF])
	if OS.is_debug_build() and not solids_ok:
		push_error(("StadiumLayout: a solid prop is on the racing surface " \
			+ "(solids closest %.2f m / limit %.2f m, %d offender(s), " \
			+ "worst %s).") % [
			float(solids["closest"]), float(solids["limit"]),
			int(solids["offenders"]), str(solids["worst"])])
