extends RefCounted
## Authoritative course and elevation data for SUNSET CANYON (`canyon`).
##
## Route (64 drivable cells, 985 m lap, difficulty MEDIUM):
##   * start/finish straight perched high on a 12.0 m red-rock mesa rim skyway
##     with flat rim-lip jump J #1
##   * dramatic terraced switchback descent (12.0 m -> 9.0 -> 6.0 -> 3.0 -> 0.0 m)
##     past towering sandstone buttes and under red-rock canyon arches
##   * dusty canyon floor ("dirt" 0.86 grip) + turquoise desert oasis splash
##     ("wet" 0.80 grip) with flat oasis jump J #2
##   * 9-cell west cliffside climb back up to the 12.0 m mesa rim skyway

const HEIGHT_STEP: float = 1.5
const LAP_LENGTH: int = 985
const HIGHEST: float = 12.0
const START_CELL: Vector2i = Vector2i(3, 1)

const GRID_ROWS: Array[String] = [
	"...................",
	"..WSSPSSSJSSSSSSW..",
	"..S.............S..",
	"..S.............S..",
	"..S.............S..",
	"..S.........WSSSR..",
	"..S.........S......",
	"..S.........S......",
	"..S.........S......",
	"..S.........LSSSR..",
	"..S.............S..",
	"..S.............S..",
	"..WSSSL.....WSSSR..",
	"......S.....S......",
	"......S.....S......",
	"......WSSJSSW......",
	"...................",
]

const HEIGHT_ROWS: Array[String] = [
	"...................",
	"..888888888888888..",
	"..8.............8..",
	"..7.............6..",
	"..6.............4..",
	"..5.........44444..",
	"..4.........4......",
	"..3.........2......",
	"..2.........0......",
	"..1.........00000..",
	"..0.............0..",
	"..0.............0..",
	"..00000.....00000..",
	"......0.....0......",
	"......0.....0......",
	"......0000000......",
	"...................",
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
