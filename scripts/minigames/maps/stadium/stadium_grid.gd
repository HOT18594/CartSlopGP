extends RefCounted
## Canonical layout of the STADIUM CIRCUIT, as the authoring source of truth.
##
## The registry preset in scripts/minigames/track_defs.gd carries the same two
## grids; this module keeps them next to the dressing code that reasons about
## them and lets the headless probe rebuild the map without a race scene. When
## the two ever drift, stadium_theme.gd prints the first mismatching row so the
## registry copy can be fixed in one paste.
##
## Route (40 drivable cells, 749 m at one 16 m cell per straight and a quarter
## arc per corner):
##
##   start/finish on the north straight, heading east
##   -> C crossover cell where the pit lane splits off the main straight
##   -> raised (4.5 m) eastern sweep, the banked crest of the bowl
##   -> a low 0 m valley across the south side, under the footbridge
##   -> the south hairpin: a 180 U into the infield, legs 32 m apart so a
##      continuous barrier fits between them
##   -> B bump and J jump ramp on the valley floor
##   -> the west chicane: a right-left jog of one cell
##   -> back up the western climb onto the start straight
##
## Character legend: S straight, L/R corner, C crossing, W wide sweeper,
## B bump, J jump ramp, P/E/G pit cells, X empty. The engine requires every
## drivable cell to sit on ONE closed lap and forbids a self-crossing path, so
## the crossover is the kit's junction cell (a crossing slab on the main
## straight where the pit lane branches) rather than a true figure-of-eight.
##
## Heights are one digit per cell at HEIGHT_STEP metres: 1 = 1.5 m, 2 = 3.0 m,
## 3 = 4.5 m. '.' is ground level. The plateau is the north/west half, the
## valley is the south side, and the drop between them is spread over one cell
## per 1.5 m so no road piece is pitched more than 11 degrees.

## Metres per height digit, mirroring KenneyTiles.HEIGHT_STEP.
const HEIGHT_STEP: float = 1.5

## The map, one string per 16 m grid row (14 columns x 12 rows).
const GRID_ROWS: Array[String] = [
	"..............",
	"..............",
	"..RSSCSSSSSR..",
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

## Per-cell heights, one digit row per grid row, '.' for ground level.
const HEIGHT_ROWS: Array[String] = [
	"..............",
	"..............",
	"..2222222333..",
	"..2........3..",
	"..22.......2..",
	"...2.......1..",
	"..22...000.0..",
	"..1....0.0.0..",
	"..1....0.0.0..",
	"..............",
	"..............",
	"..............",
]

## Highest and lowest road deck the layout asks for, in metres. Used by the
## theme's build report so a regression in the registry grid is visible.
const HIGHEST: float = 4.5
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


## The theme dictionary the engine needs to build this layout directly. The
## race scene passes only {"id": ...} and the engine then reads the registry
## preset; the probe and any tool can pass this instead.
static func theme_dict() -> Dictionary:
	return {"id": "stadium", "heights": height_rows()}


## The two fields the registry preset must carry for the race scene to build
## this layout. Copy them over the stadium entry's `grid` and `elevation`, and
## set `lap_length` to 599; until then the race keeps the old 28-tile loop and
## stadium_layout.gd prints the mismatching row on every boot.
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
