extends RefCounted
## Canonical layout of the STADIUM CIRCUIT, as the authoring source of truth.
##
## Route (70 drivable cells, 1486 m lap, difficulty EASY):
##   * grand start/finish & pit straight (P-P-E-G-P) at 0.0 m heading east
##   * sweeping east technical S-bend climbing up onto a 9.0 m open sky-bridge
##   * 9.0 m south sky-bridge straight with flat kicker jump J plunging down
##     into the 0.0 m open stadium valley roller B
##   * wide west infield S-chicane back onto the pit straight

const HEIGHT_STEP: float = 1.5

const GRID_ROWS: Array[String] = [
	".......................",
	"..RSPEGPSSSSSSSSSSSSW..",
	"..S.................S..",
	"..S.................S..",
	"..S.................S..",
	"..RSL............WSSR..",
	"....S............S.....",
	"....S............LSSW..",
	"....S...............S..",
	"..RSL...............S..",
	"..S.................S..",
	"..S.................S..",
	"..S.................S..",
	"..WSSSSBSSSSSSSJSSSSW..",
	".......................",
]

const HEIGHT_ROWS: Array[String] = [
	".......................",
	"..0000000000000000000..",
	"..0.................0..",
	"..0.................1..",
	"..0.................2..",
	"..000............3222..",
	"....0............4.....",
	"....0............4455..",
	"....0...............5..",
	"..000...............6..",
	"..0.................6..",
	"..0.................6..",
	"..0.................6..",
	"..0000000123456666666..",
	".......................",
]

const HIGHEST: float = 9.0
const LOWEST: float = 0.0
const LAP_LENGTH: int = 1486


static func grid_rows() -> PackedStringArray:
	var rows := PackedStringArray()
	for row: String in GRID_ROWS:
		rows.append(row)
	return rows


static func height_rows() -> PackedStringArray:
	var rows := PackedStringArray()
	for row: String in HEIGHT_ROWS:
		rows.append(row)
	return rows


static func theme_dict() -> Dictionary:
	return {"id": "stadium", "heights": height_rows(), "hoarding_density": 0.0}


static func registry_preset_patch() -> Dictionary:
	return {
		"grid": grid_rows(),
		"heights": height_rows(),
		"elevation": [{"at": 0.0, "height": 0.0}],
		"lap_length": LAP_LENGTH,
	}


static func mismatch_row(built: PackedStringArray) -> int:
	for index in mini(built.size(), GRID_ROWS.size()):
		if built[index] != GRID_ROWS[index]:
			return index
	if built.size() != GRID_ROWS.size():
		return mini(built.size(), GRID_ROWS.size())
	return -1


static func is_empty_row(row: String) -> bool:
	for index in row.length():
		if "SLRCWBJPEG".contains(row[index]):
			return false
	return true
