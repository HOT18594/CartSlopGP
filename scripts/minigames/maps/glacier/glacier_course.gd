extends RefCounted
## Authoritative route data for the Glacier Pass alpine circuit.
##
## Route (84 drivable cells, 1794 m lap, difficulty EXPERT):
##   * 13.5 m open high-alpine summit ridge on the north straight with bump B
##     and flat crest jump J launching toward the summit overlook
##   * upper ice sector #1 (0.21..0.38, grip = 0.45) descending 13.5 m -> 3.0 m
##     down terraced mountain switchbacks framed by jagged alpine peaks
##   * lower ice sector #2 (0.46..0.70, grip = 0.45) sweeping along the snow
##     valley past crystalline ice arches, ski chalets & frozen alpine tarn
##   * base switchback & alpine climb back through waist bridge 'C' to summit

const GRID: PackedStringArray = [
	"XXXXXXXXXXXXXXXXXXXXXXX",
	"XXWSSBSSSSSSSSSSSSSJWXX",
	"XXSXXXXXXXXXXXXXXXXXSXX",
	"XXSXXXXXXXXXXXXXXXXXSXX",
	"XXSXXXXXXXXXXXXXXXXXSXX",
	"XXRSSSSSLXXXXXLSSSSSRXX",
	"XXXXXXXXSXXXXXSXXXXXXXX",
	"XXXXXXXXCXXXXXSXXXXXXXX",
	"XXXXXXXXSXXXXXLSSSSSRXX",
	"XXXRSSSSLXXXXXXXXXXXSXX",
	"XXXSXXXXXXXXXXXXXXXXSXX",
	"XXXSXXXXXXXXXXXXXXXXSXX",
	"XXXSXXXXXXXXXXXXXXXXSXX",
	"XXXSXXXXXXXXXXXXXXXXSXX",
	"XXXWSSSSSSBSSSSSSSSSWXX",
	"XXXXXXXXXXXXXXXXXXXXXXX",
]

const HEIGHTS: PackedStringArray = [
	".......................",
	"..9999999999999999999..",
	"..9.................9..",
	"..8.................8..",
	"..7.................7..",
	"..7766655.....4445566..",
	"........5.....4........",
	"........4.....3........",
	"........3.....2222222..",
	"...222333...........2..",
	"...2................2..",
	"...1................1..",
	"...1................1..",
	"...1................1..",
	"...111111111111111111..",
	".......................",
]

const ELEVATION: Array[Dictionary] = [
	{"at": 0.0, "height": 13.5},
	{"at": 0.21, "height": 13.5},
	{"at": 0.37, "height": 3.0},
	{"at": 0.49, "height": 1.5},
	{"at": 0.75, "height": 1.5},
	{"at": 0.97, "height": 13.5},
]

const SURFACES: Array[Dictionary] = [
	{"kind": "normal", "from": 0.0, "to": 0.21},
	{"kind": "ice", "from": 0.21, "to": 0.38},
	{"kind": "normal", "from": 0.38, "to": 0.46},
	{"kind": "ice", "from": 0.46, "to": 0.70},
	{"kind": "normal", "from": 0.70, "to": 1.0},
]

const START_CELL: Vector2i = Vector2i(3, 1)
const HEIGHT_STEP: float = 1.5
const LAP_LENGTH: int = 1794


static func grid() -> PackedStringArray:
	return GRID


static func heights() -> PackedStringArray:
	return HEIGHTS


static func elevation() -> Array[Dictionary]:
	var copy: Array[Dictionary] = []
	for entry: Dictionary in ELEVATION:
		copy.append(entry.duplicate())
	return copy


static func surfaces() -> Array[Dictionary]:
	var copy: Array[Dictionary] = []
	for entry: Dictionary in SURFACES:
		copy.append(entry.duplicate())
	return copy


static func preset_fields() -> Dictionary:
	return {
		"grid": grid(),
		"heights": heights(),
		"elevation": elevation(),
		"surfaces": surfaces(),
		"start": START_CELL,
		"lap_length": LAP_LENGTH,
	}


static func theme_dict() -> Dictionary:
	return {
		"id": "glacier",
		"heights": heights(),
		"elevation": elevation(),
		"hoarding_density": 0.0,
	}


static func summary() -> String:
	var drivable: int = 0
	for row: String in GRID:
		for index in row.length():
			if row[index] != "X":
				drivable += 1
	var lowest: int = 9
	var highest: int = 0
	for row: String in HEIGHTS:
		for index in row.length():
			var glyph: String = row[index]
			if not glyph.is_valid_int():
				continue
			lowest = mini(lowest, glyph.to_int())
			highest = maxi(highest, glyph.to_int())
	return "%d drivable cells, ~%d m, summit %.1f m, base %.1f m, %.1f m of climb, two ice sectors" % [
		drivable, LAP_LENGTH, float(highest) * HEIGHT_STEP,
		float(lowest) * HEIGHT_STEP,
		float(highest - lowest) * HEIGHT_STEP]
