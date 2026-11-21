extends RefCounted
## Authoritative route and terrain data for the Dockyard Quay circuit.
##
## Route (72 drivable cells, ~1510 m lap, difficulty HARD):
##   * elevated 7.5 m north crane-deck overpass start/pit straight (P-E)
##   * multi-tier container port descent through the east port cross-road ('C')
##     onto the open harbour seawall
##   * wet quayside straight (0.80 grip) beside the ocean basin & bobbing cargo
##     ships, with flat 'J' dock jump
##   * technical west harbourside chicane with flat 'B' bump climbing
##     back onto the 7.5 m crane-deck overpass

const GRID_ROWS: Array[String] = [
	"XXXXXXXXXXXXXXXXXXXXXX",
	"XXRSPESSSSSSSSSSSSSWXX",
	"XXSXXXXXXXXXXXXXXXXSXX",
	"XXSXXXXXXXXXXXXXXXXSXX",
	"XXSXXXXXXXXXXXXXXXXSXX",
	"XXRSSSLXXXXXXXXLSSSRXX",
	"XXXXXXSXXXXXXXXCXXXXXX",
	"XXXXXXSXXXXXXXXSXXXXXX",
	"XXRSBSLXXXXXXXXLSSSRXX",
	"XXSXXXXXXXXXXXXXXXXSXX",
	"XXSXXXXXXXXXXXXXXXXSXX",
	"XXSXXXXXXXXXXXXXXXXSXX",
	"XXWSSSSSSSJSSSSSSSSWXX",
	"XXXXXXXXXXXXXXXXXXXXXX",
]

const HEIGHT_ROWS: Array[String] = [
	"......................",
	"..555555555555555555..",
	"..5................5..",
	"..4................4..",
	"..3................3..",
	"..33333........22233..",
	"......3........2......",
	"......2........2......",
	"..11111........22222..",
	"..1................1..",
	"..0................1..",
	"..0................0..",
	"..000000000000000000..",
	"......................",
]

const LAP_LENGTH: int = 1529
const HEIGHT_STEP: float = 1.5
const START_CELL: Vector2i = Vector2i(3, 1)

const SURFACES: Array[Dictionary] = [
	{"kind": "normal", "from": 0.0, "to": 0.46},
	{"kind": "wet", "from": 0.46, "to": 0.72},
	{"kind": "normal", "from": 0.72, "to": 1.0},
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
