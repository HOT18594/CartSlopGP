extends RefCounted
## Authoritative route and terrain data for the Dockyard Quay circuit.
##
## The map is a two-level quay loop, 38 drivable cells at 16 m (567 m):
##
##   * the north quay and the raised upper wharf sit on the 3.0 m deck, so the
##     start straight, the east side and the west wharf read as a working quay
##     above the water;
##   * the waist is split: two 16 m legs 32 m apart (columns 5 and 7) carry the
##     traffic in opposite directions at 3.0 m and 1.5 m, and the C at (7,5)
##     paints the knot where the two levels meet;
##   * the south side steps down through a 1.5 m shelf into a 0 m sunken
##     container lane, with a J loading kicker on its floor and a B hump on the
##     west wharf below the start;
##   * two 180 switchbacks with 16 m legs (the quay hairpins) turn the two waist
##     legs back on each other at the top and the bottom of the waist, the
##     tightest corners the 16 m grid allows.
##
## The engine forbids revisiting a cell, so a literal crossing cannot be
## traversed twice; the C is a junction paint cell on the raised leg and the
## height split plus the 32 m waist carries the two-level read.
##
## Heights are one digit per cell at HEIGHT_STEP metres, read as the deck at the
## cell's entry edge. Every step is one digit and sits on a straight cell (1.5 m
## over 16 m is a 5.4 degree grade), so corner spans stay level, which keeps the
## engine's warped road, its collider and the barrier ring through a turn level
## too. The kart tiles repeat the next cell's digit, so the kit's rigid ramp
## wedge can never float. Decks run 0.0 m (sunken lane) to 3.0 m (wharf top): a
## 3.0 m range that reads as a quay, not a flat pad.
##
## Integration: the registry in scripts/minigames/track_defs.gd routes `grid`
## and `heights` through this module (TrackDefs.grid_of / heights_of), so the
## race always builds the tables below. `preset_fields()` is only for tools that
## build a preset by hand.

## One character per 16 m cell, 12 columns x 10 rows, drawn top-down. The B on
## row 6 is the wharf hump, the J on row 8 the loading kicker in the trench.
const GRID_ROWS: Array[String] = [
	"XXXXXXXXXXXX",
	"XXRSPESSSRXX",
	"XXSXXXXXXSXX",
	"XXSXXXXXXSXX",
	"XXRSSLXLSRXX",
	"XXXXXSXCXXXX",
	"XXRSBLXLSRXX",
	"XXSXXXXXXSXX",
	"XXRSSJSSSRXX",
	"XXXXXXXXXXXX",
]

## Road height per cell, one digit per cell in 1.5 m steps ('.' = flat). The
## digit is the deck at the cell's entry edge: 1 = 1.5 m, 2 = 3.0 m. The wharf
## tops sit on digit 2, the waist shelf on digit 1 and the sunken container lane
## on digit 0. Every height change sits on a straight cell, so the corner spans
## are level and the barrier pieces through them stay level too.
const HEIGHT_ROWS: Array[String] = [
	"............",
	"..11222222..",
	"..1......2..",
	"..1......2..",
	"..1222.122..",
	".....2.1....",
	"..1122.111..",
	"..0......1..",
	"..00000111..",
	"............",
]

## Lap length in metres at one cell per straight and a quarter arc per corner.
const LAP_LENGTH: int = 567
## Heights are 1.5 m per digit, mirroring KenneyTiles.HEIGHT_STEP.
const HEIGHT_STEP: float = 1.5
## Start/finish cell (column, row): the first straight on the pit straight.
const START_CELL: Vector2i = Vector2i(3, 1)
## Grip sectors: the middle of the lap keeps the theme's painted wet sector,
## which lands on the sunken container lane (lap fractions ~0.45..0.63).
const SURFACES: Array[Dictionary] = [
	{"kind": "normal", "from": 0.0, "to": 0.30},
	{"kind": "wet", "from": 0.30, "to": 0.58},
	{"kind": "normal", "from": 0.58, "to": 1.0},
]


## The grid as the engine and the registry both read it.
static func grid_rows() -> PackedStringArray:
	var rows := PackedStringArray()
	for row: String in GRID_ROWS:
		rows.append(row)
	return rows


## Per-cell elevation, one digit row per grid row.
static func heights() -> PackedStringArray:
	var rows := PackedStringArray()
	for row: String in HEIGHT_ROWS:
		rows.append(row)
	return rows


## The preset keys a hand-merged dockyard entry would carry. No `elevation`
## placeholder is shipped: a smooth profile would silently draw a different hill
## if the height table were ever dropped, so `heights` is the only elevation
## source for this map.
static func preset_fields() -> Dictionary:
	var surface_copy: Array[Dictionary] = []
	for band: Dictionary in SURFACES:
		surface_copy.append(band.duplicate())
	return {
		"grid": grid_rows(),
		"heights": heights(),
		"surfaces": surface_copy,
		"lap_length": LAP_LENGTH,
	}


## Number of drivable cells in the authored grid.
static func tile_count() -> int:
	var count: int = 0
	for row: String in GRID_ROWS:
		for glyph: String in row:
			if glyph != "X" and glyph != ".":
				count += 1
	return count


## Highest authored deck, in metres.
static func highest() -> float:
	var top: int = 0
	for row: String in HEIGHT_ROWS:
		for glyph: String in row:
			if glyph.is_valid_int():
				top = maxi(top, glyph.to_int())
	return float(top) * HEIGHT_STEP


## True when `rows` is the authored layout, so a theme can report registry
## drift instead of silently dressing a stale map.
static func matches(rows: PackedStringArray) -> bool:
	if rows.size() != GRID_ROWS.size():
		return false
	for index in GRID_ROWS.size():
		if rows[index] != GRID_ROWS[index]:
			return false
	return true


## First mismatching registry row, for the build report. Empty when it matches.
static func mismatch(rows: PackedStringArray) -> String:
	if rows.is_empty():
		return "registry has no dockyard grid"
	if rows.size() != GRID_ROWS.size():
		return "registry has %d rows, layout wants %d" % [rows.size(),
			GRID_ROWS.size()]
	for index in GRID_ROWS.size():
		if rows[index] != GRID_ROWS[index]:
			return "row %d differs" % (index + 1)
	return ""
