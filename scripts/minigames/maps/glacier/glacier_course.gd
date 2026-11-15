extends RefCounted
## Authoritative route data for the Glacier Pass alpine circuit.
##
## The circuit is a two-level alpine pass instead of the flat ring the map
## shipped with:
##
##   * a 9.0 m summit plateau on the start/finish straight, with a bump and a
##     crest ramp right after the line, and a J kicker at the summit lip so the
##     car launches as the deck falls away into the first sweeper;
##   * a fast descent off the summit down the east side (9.0 -> 7.5 -> 6.0 ->
##     4.5 -> 3.0 -> 1.5 m, one 1.5 m step per cell) with the ice section on it;
##   * a lower return leg at the base (1.5 m) that runs beneath the summit on
##     the far side of the map, with a 3.0 m crest on its east corner, a hairpin
##     at its west end (two 90 degree corners 32 m apart, the tightest 180 the
##     16 m grid allows) and the crossing tile (C) at the waist of the eight,
##     where the climbing leg and the descending leg pass each other 32 m apart
##     at different heights so the crossing paint reads as the knot;
##   * a long summit climb back up the west side, thirteen cells of one-digit
##     staircase from 1.5 m to 9.0 m, and the pit-lane apron and garage block
##     laid beside the base straight by glacier_layout.
##
## Why the crossing is paint and not a second drivable arm: KenneyTiles traces
## one closed cell loop and refuses a grid where a cell is entered twice (it
## reports "the path loops back on itself"). A literal figure-of-eight needs the
## crossing cell traversed twice, so the engine cannot express it. The C tile
## paints the cross at the waist and the heights separate the two legs, which is
## the closest honest reading of an eight on this grid.
##
## Heights are one digit per cell at HEIGHT_STEP metres, read as the deck at the
## cell's entry edge. A step is never more than one digit and every step sits on
## a straight cell, so the B/J cells repeat the next cell's digit and the
## engine's warped road and collider stay watertight; the kit's rigid ramp wedge
## can never float. The decks run 1.5 m (base) to 9.0 m (summit): a 7.5 m range
## that reads as a pass, not a plateau.
##
## Integration: the registry in scripts/minigames/track_defs.gd routes `grid` and
## `heights` through this module (TrackDefs.grid_of / heights_of), so the race
## always builds the tables below. `preset_fields()` is only for tools that
## build a preset by hand. Nothing here builds nodes: it is data plus the legend.

## 14 columns x 12 rows, one character per 16 m cell, drawn top-down.
##   S straight  L/R corner  W wide sweeper  C crossing (paint)
##   B bump      J jump ramp  P pit straight  X empty
## The J on row 1 is the summit-lip kicker at the east end of the start straight.
const GRID: PackedStringArray = [
	"XXXXXXXXXXXXXX",
	"XXXRSBSSSSSJWX",
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
## digit is the deck height at the cell's entry edge: the summit plateau is
## digit 6 (9.0 m), the base is digit 1 (1.5 m).
##
## Every height change sits on a straight cell, so every corner span is level:
## that is both the smoothest line into a turn and what keeps the barrier ring
## level through it, because a barrier piece tilted along a slope leans a few
## centimetres further in on the inside of a bend. One digit per 16 m straight
## is a 5.4 degree grade, so the whole 7.5 m drop and climb stay drivable. The B
## and J tiles repeat the next cell's digit, which keeps the kit's rigid ramp
## wedge on the same plane as the warped road at both of its seams.
const HEIGHTS: PackedStringArray = [
	"..............",
	"...6666666666.",
	"...5........6.",
	"...4........5.",
	"...44433.2344.",
	".......3.2....",
	".......3.1....",
	".......2.112..",
	"....1122...2..",
	"....1......1..",
	"....11111111..",
	"..............",
]

## Smooth fallback profile, used only when a preset merges `elevation` without
## `heights`. Cell heights always win whenever both are present.
const ELEVATION: Array[Dictionary] = [
	{"at": 0.0, "height": 9.0},
	{"at": 0.19, "height": 9.0},
	{"at": 0.33, "height": 1.5},
	{"at": 0.41, "height": 3.0},
	{"at": 0.46, "height": 1.5},
	{"at": 0.72, "height": 1.5},
	{"at": 0.96, "height": 9.0},
]

## Grip spans. The ice sits on the fast descent (lap fractions 0.17-0.33 are the
## cells from the summit lip down to the base) so the slippery section is a
## downhill, which is where an ice map wants it.
const SURFACES: Array[Dictionary] = [
	{"kind": "normal", "from": 0.0, "to": 0.14},
	{"kind": "ice", "from": 0.14, "to": 0.33},
	{"kind": "normal", "from": 0.33, "to": 1.0},
]

## First cell of the lap, which KenneyTiles also picks on its own (the first
## straight in row-major order). Kept explicit so the spec is self-contained.
const START_CELL: Vector2i = Vector2i(4, 1)

## Metres per height digit, mirroring KenneyTiles.HEIGHT_STEP.
const HEIGHT_STEP: float = 1.5
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


## Registry fields for a hand-built glacier preset. The race already routes
## `grid` and `heights` through TrackDefs.grid_of / heights_of, so merging these
## is only needed by a tool that builds a preset by itself.
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
## The per-cell heights win; the profile only matters if they are ever dropped.
static func theme_dict() -> Dictionary:
	return {"id": "glacier", "heights": heights(),
		"elevation": elevation()}


## One-line description of the route, for build logs and the verification
## harness. The summit and base are measured from HEIGHTS, so the line can never
## disagree with the table the engine builds.
static func summary() -> String:
	var drivable: int = 0
	for row: String in GRID:
		for index in row.length():
			if row[index] != "X":
				drivable += 1
	var lowest: int = 9
	var highest: int = 0
	for row: String in HEIGHTS:
		for index in row.length():
			var glyph: String = row[index]
			if not glyph.is_valid_int():
				continue
			lowest = mini(lowest, glyph.to_int())
			highest = maxi(highest, glyph.to_int())
	return "%d drivable cells, ~%d m, summit %.1f m, base %.1f m, %d m of climb, crossing at the waist, base hairpin" % [
		drivable, LAP_LENGTH, float(highest) * HEIGHT_STEP,
		float(lowest) * HEIGHT_STEP,
		float(highest - lowest) * HEIGHT_STEP]
