extends RefCounted
## Authoritative route and terrain data for the Dockyard Quay circuit.
##
## The map the theme was built around is a pinched figure-of-eight quay loop,
## 38 drivable cells at 16 m (about 567 m):
##
##   * a crossing ('C') at the east waist of the eight, where the raised upper
##     leg and the low return leg pass 32 m apart at different heights: the C
##     paints the knot, which is the closest an engine that traces one closed
##     cell loop can honestly get to a true self-crossing;
##   * a split waist: the two neck legs at columns 5 and 7 (32 m apart) carry
##     the traffic in opposite directions, one at 0 m and one at 3.0 m, so the
##     map reads as two loops joined by a split lane rather than one ring;
##   * a tight quay hairpin at the bottom-west corner: two 8 m corners 16 m
##     apart, the tightest 180 the 16 m grid allows, right on the quay edge;
##   * a jump ramp ('J') on the low bottom straight, dressed by the theme as a
##     loading-dock kicker;
##   * raised wharf terrain: the east waist and upper lobe climb to 3.0 m in
##     1.5 m steps (a 9 percent grade), while the bottom lobe stays at 0 m in
##     the container trench.
##
## The engine forbids revisiting a cell, so a literal crossing cannot be
## traversed twice; the C is a junction paint cell on the raised leg and the
## height split plus the 32 m waist carries the figure-of-eight read.
##
## Integration: the registry in scripts/minigames/track_defs.gd is what
## grass_race reads when it builds the road. `preset_fields()` returns exactly
## the keys to merge into the dockyard preset:
##
##   {"grid": ..., "heights": ..., "lap_length": 567}
##
## The theme reads the grid stats the engine stores on the race root, so it
## measures the layout that was actually built even if the registry merge is
## still pending. Nothing here builds nodes: this is data plus the legend.

## One character per 16 m cell, 12 columns x 10 rows, drawn top-down.
const GRID_ROWS: Array[String] = [
	"XXXXXXXXXXXX",
	"XXRSPESSSRXX",
	"XXSXXXXXXSXX",
	"XXSXXXXXXSXX",
	"XXRSSLXLSRXX",
	"XXXXXSXCXXXX",
	"XXRSSLXLSRXX",
	"XXSXXXXXXSXX",
	"XXRSSJSSSRXX",
	"XXXXXXXXXXXX",
]

## Road height per cell, one digit per cell in 1.5 m steps ('.' = flat).
## The upper lobe climbs to 3.0 m, the bottom lobe stays in the trench at 0 m,
## and every shared edge steps by at most one digit (9.4 percent grade).
const HEIGHT_ROWS: Array[String] = [
	"............",
	"..11122222..",
	"..1......2..",
	"..1......2..",
	"..1111.222..",
	".....1.2....",
	"..1111.222..",
	"..0......1..",
	"..00000000..",
	"............",
]

## Lap length in metres at one cell per straight and a quarter arc per corner.
const LAP_LENGTH: int = 567
## Heights are 1.5 m per digit, mirroring KenneyTiles.HEIGHT_STEP.
const HEIGHT_STEP: float = 1.5
## Start/finish cell (column, row): the first straight on the pit straight.
const START_CELL: Vector2i = Vector2i(3, 1)
## Grip sectors: the middle of the lap keeps the theme's painted wet sector.
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


## The preset keys to merge into the dockyard registry entry.
static func preset_fields() -> Dictionary:
	var surface_copy: Array[Dictionary] = []
	for band: Dictionary in SURFACES:
		surface_copy.append(band.duplicate())
	return {
		"grid": grid_rows(),
		"heights": heights(),
		"elevation": [{"at": 0.0, "height": 0.0}],
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
