extends RefCounted
## Authoritative course and elevation data for SUNSET CANYON (`canyon`).
##
## Route (76 drivable cells, 1620 m lap, difficulty MEDIUM):
##   * start/finish straight perched high on an open 12.0 m red-rock mesa rim
##     skyway with flat rim-lip jump J #1
##   * sweeping multi-tier desert switchbacks descending past wind-carved spires
##     and natural sandstone arches
##   * dusty canyon floor ("dirt" 0.86 grip) + turquoise palm oasis splash
##     ("wet" 0.80 grip) with flat oasis kicker jump J #2
##   * dramatic west canyon wall climb back to the 12.0 m mesa skyway

const HEIGHT_STEP: float = 1.5
const LAP_LENGTH: int = 1620
const HIGHEST: float = 12.0
const START_CELL: Vector2i = Vector2i(5, 1)

const GRID_ROWS: Array[String] = [
	".......................",
	"..WSSPSSSJSSSSSSSSSSW..",
	"..S.................S..",
	"..S.................S..",
	"..S.................S..",
	"..S............WSSSSR..",
	"..S............S.......",
	"..S............S.......",
	"..S............S.......",
	"..S............LSSSSR..",
	"..S.................S..",
	"..S.................S..",
	"..WSSSSSL.....WSSSSSR..",
	"........S.....S........",
	"........S.....S........",
	"........S.....S........",
	"........WSSJSSW........",
	".......................",
]

const HEIGHT_ROWS: Array[String] = [
	".......................",
	"..8888888888888888888..",
	"..8.................8..",
	"..7.................7..",
	"..7.................6..",
	"..6............444455..",
	"..5............3.......",
	"..4............2.......",
	"..3............1.......",
	"..2............000000..",
	"..1.................0..",
	"..0.................0..",
	"..0000000.....0000000..",
	"........0.....0........",
	"........0.....0........",
	"........0.....0........",
	"........0000000........",
	".......................",
]

const SURFACES: Array[Dictionary] = [
	{"kind": "normal", "from": 0.0, "to": 0.40},
	{"kind": "dirt", "from": 0.40, "to": 0.61},
	{"kind": "wet", "from": 0.61, "to": 0.72},
	{"kind": "dirt", "from": 0.72, "to": 0.85},
	{"kind": "normal", "from": 0.85, "to": 1.0},
]


static func grid_rows() -> PackedStringArray:
	var rows := PackedStringArray()
	for row: String in GRID_ROWS:
		rows.append(row)
	return rows


static func heights() -> PackedStringArray:
	var rows := PackedStringArray()
	for row: String in HEIGHT_ROWS:
		rows.append(row)
	return rows


static func surfaces() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in SURFACES:
		out.append(entry.duplicate())
	return out


static func preset_fields() -> Dictionary:
	return {
		"grid": grid_rows(),
		"heights": heights(),
		"surfaces": surfaces(),
		"lap_length": LAP_LENGTH,
	}
