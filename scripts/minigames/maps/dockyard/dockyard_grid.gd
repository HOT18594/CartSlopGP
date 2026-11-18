extends RefCounted
## Authoritative route and terrain data for the Dockyard Quay circuit.
##
## Route (58 drivable cells, 888 m lap, difficulty HARD):
##   * elevated 7.5 m north crane-deck overpass start/pit straight (P-E)
##   * multi-tier container port descent through the east port cross-road ('C')
##     at (12, 6) onto the 0.0 m harbour seawall
##   * wet quayside straight (0.80 grip) beside the ocean basin & moored cargo
##     ship, with flat 'J' dock jump at (8, 11)
##   * technical west harbourside chicane with flat 'B' bump at (4, 8) climbing
##     back onto the 7.5 m crane-deck overpass

const GRID_ROWS: Array[String] = [
	"XXXXXXXXXXXXXXXXXX",
	"XXRSPESSSSSSSSSWXX",
	"XXSXXXXXXXXXXXXSXX",
	"XXSXXXXXXXXXXXXSXX",
	"XXSXXXXXXXXXXXXSXX",
	"XXRSSLXXXXXXLSSRXX",
	"XXXXXSXXXXXXCXXXXX",
	"XXXXXSXXXXXXSXXXXX",
	"XXRSBLXXXXXXLSSRXX",
	"XXSXXXXXXXXXXXXSXX",
	"XXSXXXXXXXXXXXXSXX",
	"XXWSSSSSJSSSSSSWXX",
	"XXXXXXXXXXXXXXXXXX",
]

const HEIGHT_ROWS: Array[String] = [
	"..................",
	"..55555555555555..",
	"..5............5..",
	"..5............4..",
	"..3............3..",
	"..3333......2233..",
	".....3......2.....",
	".....1......2.....",
	"..1111......2222..",
	"..1............2..",
	"..0............0..",
	"..00000000000000..",
	"..................",
]

const LAP_LENGTH: int = 888
const HEIGHT_STEP: float = 1.5
const START_CELL: Vector2i = Vector2i(3, 1)

const SURFACES: Array[Dictionary] = [
	{"kind": "normal", "from": 0.0, "to": 0.49},
	{"kind": "wet", "from": 0.49, "to": 0.73},
	{"kind": "normal", "from": 0.73, "to": 1.0},
]


static func grid_rows() -> PackedStringArray:
	var rows := PackedStringArray()
	for row: String in GRID_ROWS:
		rows.append(row)
	return rows


static func surfaces() -> Array[Dictionary]:
	var copy: Array[Dictionary] = []
	for band: Dictionary in SURFACES:
		copy.append(band.duplicate())
	return copy


static func heights() -> PackedStringArray:
	var rows := PackedStringArray()
	for row: String in HEIGHT_ROWS:
		rows.append(row)
	return rows


static func preset_fields() -> Dictionary:
	return {
		"grid": grid_rows(),
		"heights": heights(),
		"surfaces": surfaces(),
		"lap_length": LAP_LENGTH,
	}


static func tile_count() -> int:
	var count: int = 0
	for row: String in GRID_ROWS:
		for glyph: String in row:
			if glyph != "X" and glyph != ".":
				count += 1
	return count


static func highest() -> float:
	var top: int = 0
	for row: String in HEIGHT_ROWS:
		for glyph: String in row:
			if glyph.is_valid_int():
				top = maxi(top, glyph.to_int())
	return float(top) * HEIGHT_STEP


static func matches(rows: PackedStringArray) -> bool:
	if rows.size() != GRID_ROWS.size():
		return false
	for index in GRID_ROWS.size():
		if rows[index] != GRID_ROWS[index]:
			return false
	return true


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
