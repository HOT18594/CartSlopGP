extends RefCounted
## Authoritative route data for the Glacier Pass alpine circuit.
##
## The circuit is a pinched figure-of-eight pass instead of the flat ring the
## map shipped with:
##
##   * a summit plateau (6.0 m) on the start/finish straight, with a bump and a
##     crest ramp right after the line so the first thing a driver meets is a
##     kicker over the summit lip, then a landing slope off it;
##   * a long descent off the summit down the east side (6.0 -> 4.5 -> 3.0 ->
##     1.5 m) with the ice section on it;
##   * a lower return leg at the base (1.5 m) that runs beneath the summit on
##     the far side of the map, with a hairpin at its west end (two 90 degree
##     corners 32 m apart, the tightest 180 the 16 m grid allows);
##   * a crossing tile (C) at the waist of the eight, where the climbing leg and
##     the descending leg pass each other 32 m apart at different heights, so
##     the crossing paint reads as the knot of the eight;
##   * a summit climb back up the west side, and a split-style pit-lane apron
##     and garage block laid beside the base straight by glacier_layout.
##
## Why the crossing is paint and not a second drivable arm: KenneyTiles traces
## one closed cell loop and refuses a grid where a cell is entered twice (it
## reports "the path loops back on itself"). A literal figure-of-eight needs the
## crossing cell traversed twice, so the engine cannot express it. The C tile
## paints the cross at the waist and the heights separate the two legs, which is
## the closest honest reading of an eight on this grid.
##
## Integration: the grid, heights and surfaces live in the map registry
## (scripts/minigames/track_defs.gd) because that is what grass_race reads when
## it builds the road. `preset_fields()` returns exactly the keys to merge into
## the glacier preset:
##
##   {
##       "grid": GlacierCourse.grid(), "heights": GlacierCourse.heights(),
##       "elevation": GlacierCourse.elevation(),
##       "surfaces": GlacierCourse.surfaces(),
##       "start": GlacierCourse.START_CELL, "lap_length": 695,
##   }
##
## Nothing here builds nodes: it is data plus the grid legend, so the registry
## stays the single place a lap is authored.

## 14 columns x 12 rows, one character per 16 m cell, drawn top-down.
##   S straight  L/R corner  W wide sweeper  C crossing (paint)
##   B bump      J jump ramp  P pit straight  X empty
const GRID: PackedStringArray = [
	"XXXXXXXXXXXXXX",
	"XXXRSBSJSSSSWX",
	"XXXSXXXXXXXXSX",
	"XXXSXXXXXXXXSX",
	"XXXRSSSLXLSSRX",
	"XXXXXXXSXSXXXX",
	"XXXXXXXCXSXXXX",
	"XXXXXXXSXLSRXX",
	"XXXXRSSLXXXSXX",
	"XXXXSXXXXXXSXX",
	"XXXXRSSSSSSRXX",
	"XXXXXXXXXXXXXX",
]

## Road height per cell, one digit per cell in 1.5 m steps ('.' = flat). The
## digit is the deck height at the cell's entry edge; the summit plateau is
## digit 4 (6.0 m) and the base is digit 1 (1.5 m).
##
## Every corner cell carries the same digit as the cell it leads into. The
## clearance path around the inside of a 1-cell corner is a mitre between the
## two neighbouring straights, so the corner's own height span is never walked;
## matching the two makes that skipped span zero and keeps the wall level
## instead of tilted into the lane. All the climbing therefore happens on
## straights, and every step between two cells that share an edge is at most one
## digit, so no grade exceeds 1.5 m / 16 m = 9.4 percent.
const HEIGHTS: PackedStringArray = [
	"..............",
	"...4444443321.",
	"...4........1.",
	"...4........1.",
	"...44444.1111.",
	".......4.1....",
	".......3.1....",
	".......2.111..",
	"....1112...1..",
	"....1......1..",
	"....11111111..",
	"..............",
]

## Smooth fallback profile, used only when the registry merges `elevation`
## without `heights`. Cell heights win whenever both are present.
const ELEVATION: Array[Dictionary] = [
	{"at": 0.0, "height": 6.0},
	{"at": 0.20, "height": 6.0},
	{"at": 0.36, "height": 1.5},
	{"at": 0.72, "height": 1.5},
	{"at": 0.90, "height": 6.0},
]

## Grip spans. The ice sits on the long descent (lap fractions 0.14-0.33 are the
## cells from the summit lip down to the waist) so the slippery section is a
## downhill, which is where an ice map wants it.
const SURFACES: Array[Dictionary] = [
	{"kind": "normal", "from": 0.0, "to": 0.14},
	{"kind": "ice", "from": 0.14, "to": 0.33},
	{"kind": "normal", "from": 0.33, "to": 1.0},
]

## First cell of the lap, which KenneyTiles also picks on its own (the first
## straight in row-major order). Kept explicit so the spec is self-contained.
const START_CELL: Vector2i = Vector2i(4, 1)

## Approximate lap length in metres: 46 cells, twelve 8 m radius corners.
const LAP_LENGTH: int = 695


## The authored grid rows.
static func grid() -> PackedStringArray:
	return GRID


## The authored per-cell height rows.
static func heights() -> PackedStringArray:
	return HEIGHTS


## The smooth fallback elevation profile.
static func elevation() -> Array[Dictionary]:
	var copy: Array[Dictionary] = []
	for entry: Dictionary in ELEVATION:
		copy.append(entry.duplicate())
	return copy


## The grip spans.
static func surfaces() -> Array[Dictionary]:
	var copy: Array[Dictionary] = []
	for entry: Dictionary in SURFACES:
		copy.append(entry.duplicate())
	return copy


## Registry fields for the glacier preset. Merging these is the whole
## integration: grass_race builds the road from `grid` and KenneyTiles reads
## `heights` per cell when the preset carries it.
static func preset_fields() -> Dictionary:
	return {
		"grid": grid(),
		"heights": heights(),
		"elevation": elevation(),
		"surfaces": surfaces(),
		"start": START_CELL,
		"lap_length": LAP_LENGTH,
	}


## The KenneyTiles theme dictionary for this course, which is what a builder
## that has the grid already can pass to get the same elevation:
##   {"id": "glacier", "heights": [...], "elevation": [...]}
static func theme_dict() -> Dictionary:
	return {"id": "glacier", "heights": heights(),
		"elevation": elevation()}


## One-line description of the route, for build logs and the verification
## harness.
static func summary() -> String:
	var drivable: int = 0
	for row: String in GRID:
		for index in row.length():
			if row[index] != "X":
				drivable += 1
	return "%d drivable cells, ~%d m, summit 6.0 m, base 1.5 m, crossing at the waist, base hairpin" % [
		drivable, LAP_LENGTH]
