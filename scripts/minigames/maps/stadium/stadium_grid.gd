extends RefCounted
## Canonical layout of the STADIUM CIRCUIT, as the authoring source of truth.
##
## Route (56 drivable cells, 857 m lap, difficulty EASY):
##   * grand start/finish & pit straight (P-P-E-G-P) at 0.0 m heading east
##   * multi-tier east climb (0.0 m -> 4.5 m -> 7.5 m -> 9.0 m) through sweeping
##     east S-bends (W) up onto a towering 9.0 m stadium sky-bridge
##   * 9.0 m south sky-bridge straight with a flat kicker jump J, plunging down
##     into the 0.0 m valley roller B
##   * flowing west infield hairpin valley (0.0 m) back onto the pit straight

const HEIGHT_STEP: float = 1.5

const GRID_ROWS: Array[String] = [
	"...................",
	"..RSPPEGPSSSSSSSW..",
	"..S.............S..",
	"..S.............S..",
	"..S.............S..",
	"..RSL.........WSR..",
	"....S.........S....",
	"....S.........S....",
	"..RSL.........LSR..",
	"..S.............S..",
	"..S.............S..",
	"..WSSBSSSSSSSJSSW..",
	"...................",
]

const HEIGHT_ROWS: Array[String] = [
	"...................",
	"..000000000000000..",
	"..0.............0..",
	"..0.............2..",
	"..0.............3..",
	"..000.........333..",
	"....0.........3....",
	"....0.........5....",
	"..000.........555..",
	"..0.............5..",
	"..0.............6..",
	"..000000124566666..",
	"...................",
]

const HIGHEST: float = 9.0
const LOWEST: float = 0.0
const LAP_LENGTH: int = 857


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
	return {"id": "stadium", "heights": height_rows(), "hoarding_density": 0.42}


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
