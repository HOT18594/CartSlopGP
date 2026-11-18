extends RefCounted
## Authoritative course and elevation data for REDWOOD VALLEY (`meadow`).
##
## Route (58 drivable cells, 889 m lap, difficulty MEDIUM):
##   * start/finish straight at 0.0 m through a sunlit redwood clearing
##   * mountain switchbacks climbing to a 9.0 m cliff-top redwood overlook
##   * plunge down onto a 4.5 m bridge viaduct ('C') spanning the turquoise river
##   * fast west forest S-curves along a "dirt" (0.86 grip) woodland trail with
##     flat B rollers and flat J log-kicker jump

const HEIGHT_STEP: float = 1.5
const LAP_LENGTH: int = 889
const HIGHEST: float = 9.0
const START_CELL: Vector2i = Vector2i(3, 1)

const GRID_ROWS: Array[String] = [
	"..................",
	"..WSSSSPSSSSSSSW..",
	"..S............S..",
	"..J............S..",
	"..S............S..",
	"..RSL..........S..",
	"....S........WSR..",
	"....S........S....",
	"....S........S....",
	"..RSL........LSR..",
	"..S............S..",
	"..B............S..",
	"..S............S..",
	"..WSSSSCSSSSSSSW..",
	"..................",
]

const HEIGHT_ROWS: Array[String] = [
	"..................",
	"..00000000000000..",
	"..0............0..",
	"..0............2..",
	"..0............4..",
	"..000..........6..",
	"....0........666..",
	"....0........6....",
	"....0........6....",
	"..000........666..",
	"..0............6..",
	"..0............4..",
	"..0............3..",
	"..00123333333333..",
	"..................",
]

const SURFACES: Array[Dictionary] = [
	{"kind": "normal", "from": 0.0, "to": 0.72},
	{"kind": "dirt", "from": 0.72, "to": 0.93},
	{"kind": "normal", "from": 0.93, "to": 1.0},
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
