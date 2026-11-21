extends RefCounted
## Authoritative course and elevation data for REDWOOD VALLEY (`meadow`).
##
## Route (68 drivable cells, 1443 m lap, difficulty MEDIUM):
##   * sunlit open redwood meadow straight & sweeping north bends at 0.0 m
##   * forested switchback climb up onto a 9.0 m alpine overlook terrace
##   * sweeping descent onto the 4.5 m stone river viaduct ('C') over rapids
##   * fast west dirt trail ('dirt', 0.86 grip) with B rollers & flat J log-jump

const HEIGHT_STEP: float = 1.5
const LAP_LENGTH: int = 1443
const HIGHEST: float = 9.0
const START_CELL: Vector2i = Vector2i(6, 1)

const GRID_ROWS: Array[String] = [
	"......................",
	"..WSSSPSSSSSSSSSSSSW..",
	"..S................S..",
	"..J................S..",
	"..S................S..",
	"..RSL............WSR..",
	"....S............S....",
	"....S............S....",
	"....S............LSW..",
	"....S..............S..",
	"..RSL..............S..",
	"..S................S..",
	"..B................S..",
	"..S................S..",
	"..WSSSSSSCSSSSSSSSSW..",
	"......................",
]

const HEIGHT_ROWS: Array[String] = [
	"......................",
	"..000000000000000000..",
	"..0................1..",
	"..0................2..",
	"..0................3..",
	"..000............554..",
	"....0............6....",
	"....0............6....",
	"....0............666..",
	"....0..............5..",
	"..000..............4..",
	"..0................4..",
	"..0................3..",
	"..0................3..",
	"..001122333333333333..",
	"......................",
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
