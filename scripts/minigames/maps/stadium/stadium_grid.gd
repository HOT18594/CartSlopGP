extends RefCounted
## Canonical layout of the STADIUM CIRCUIT, as the authoring source of truth.
##
## The registry preset in scripts/minigames/track_defs.gd routes its grid AND its
## heights through this module (TrackDefs.grid_of / heights_of), so the two can
## never drift; the headless probe and the race scene both rebuild this layout
## from the two tables below. A stale inline copy in the registry is ignored.
##
## Route (40 drivable cells, 599 m at one 16 m cell per straight and a quarter
## arc per corner):
##
##   start/finish on the 4.5 m north straight, heading east
##   -> C crossover cell where the pit lane splits off the main straight
##   -> the rim climbs one step to a 6.0 m crest on the eastern side, with a J
##      kicker on it so the car launches off the lip; the descent begins on the
##      straight after the corner, not through it
##   -> the banked east descent: 6.0 -> 4.5 -> 3.0 -> 1.5 m in one-digit steps
##   -> a 1.5 m shelf around the south-east infield, then a step down into the
##      low 0 m valley under the footbridge, with the valley's own J kicker
##   -> the south straight and the two waist corners hold the valley floor
##   -> the west staircase climbs back: 1.5 m, 3.0 m, then 4.5 m over the line
##
## Character legend: S straight, L/R corner, C crossing, W wide sweeper,
## B bump, J jump ramp, P/E/G pit cells, X empty. The engine requires every
## drivable cell to sit on ONE closed lap and forbids a self-crossing path, so
## the crossover is the kit's junction cell (a crossing slab on the main
## straight where the pit lane branches) rather than a true figure-of-eight.
##
## Heights are one digit per cell at HEIGHT_STEP metres, read as the deck height
## at the cell's entry edge; the engine ramps each tile to the next cell's digit
## and warps the road, its collider and the spline onto that slope, so a shared
## seam is exact by construction. Every step is one digit and sits on a straight
## cell: 1.5 m over 16 m is a 5.4 degree grade, and the corner spans stay level,
## which keeps the barrier pieces through a turn level as well (a barrier piece
## tilted along a slope leans a few centimetres further in on the inside of a
## bend). The decks run 0.0 m (valley floor) to 6.0 m (the eastern rim), a 6.0 m
## range that reads as a bowl rather than a flat ring. Jump and bump cells
## repeat the next cell's digit, so the kit's rigid ramp wedge and its warped
## neighbours can never disagree at the seam.

## Metres per height digit, mirroring KenneyTiles.HEIGHT_STEP.
const HEIGHT_STEP: float = 1.5

## The map, one string per 16 m grid row (14 columns x 12 rows). The J on row 2
## is the crest kicker on the raised eastern rim.
const GRID_ROWS: Array[String] = [
	"..............",
	"..............",
	"..RSSCSSSSJR..",
	"..S........S..",
	"..RL.......S..",
	"...S.......S..",
	"..RL...LSL.S..",
	"..S....S.S.S..",
	"..S....S.S.S..",
	"..RSSJSR.RSR..",
	"..............",
	"..............",
]

## Per-cell heights, one digit row per grid row, '.' for ground level. The digit
## is the deck at the cell's entry edge: 1 = 1.5 m, 2 = 3.0 m, 3 = 4.5 m,
## 4 = 6.0 m. Every height change sits on a straight cell, so the corner spans are
## level and the barrier pieces through them stay level too.
const HEIGHT_ROWS: Array[String] = [
	"..............",
	"..............",
	"..3333344444..",
	"..2........4..",
	"..22.......3..",
	"...1.......3..",
	"..11...011.2..",
	"..0....0.1.2..",
	"..0....0.1.1..",
	"..000000.111..",
	"..............",
	"..............",
]

## Highest and lowest road deck the layout asks for, in metres. Used by the
## theme's build report so a regression in the height table is visible.
const HIGHEST: float = 6.0
const LOWEST: float = 0.0


## The grid as the engine and the registry both read it.
static func grid_rows() -> PackedStringArray:
	var rows := PackedStringArray()
	for row: String in GRID_ROWS:
		rows.append(row)
	return rows


## The height grid in the same shape (PackedStringArray is what the engine's
## height reader accepts).
static func height_rows() -> PackedStringArray:
	var rows := PackedStringArray()
	for row: String in HEIGHT_ROWS:
		rows.append(row)
	return rows


## The theme dictionary the engine needs to build this layout directly. The race
## scene routes the same two tables through TrackDefs, so this is only for a
## probe or a tool that builds the bowls without a race scene.
static func theme_dict() -> Dictionary:
	return {"id": "stadium", "heights": height_rows()}


## The preset fields a hand-merged registry entry would carry. The race already
## routes `grid` and `heights` through TrackDefs.grid_of / heights_of, so this is
## a fallback for older saves and tools; `lap_length` is the measured centreline
## length (599 m) that the menu card shows.
static func registry_preset_patch() -> Dictionary:
	return {"grid": grid_rows(), "heights": height_rows(),
		"elevation": [{"at": 0.0, "height": 0.0}], "lap_length": 599}


## Index of the first row where `built` differs from the canonical grid, or -1
## when they match. Rows are compared as typed strings so a width change shows
## up as a mismatch rather than a silent shift.
static func mismatch_row(built: PackedStringArray) -> int:
	for index in mini(built.size(), GRID_ROWS.size()):
		if built[index] != GRID_ROWS[index]:
			return index
	if built.size() != GRID_ROWS.size():
		return mini(built.size(), GRID_ROWS.size())
	return -1


## True when a grid row string is only the empty-cell characters the engine
## treats as X, so a border row never counts as a tile.
static func is_empty_row(row: String) -> bool:
	for index in row.length():
		if "SLRCWBJPEG".contains(row[index]):
			return false
	return true
