extends RefCounted
## Authoritative route data for the Glacier Pass alpine circuit.
##
## Route (68 drivable cells, 1,049 m lap, difficulty EXPERT):
##   * 13.5 m high-alpine summit ridge on the 15-cell north straight with bump B
##     and flat crest jump J launching into the sweeping summit bend
##   * upper ice sector #1 (0.21..0.38, grip = 0.45) descending 13.5 m -> 3.0 m
##     down the terraced east mountain switchbacks
##   * lower ice sector #2 (0.46..0.70, grip = 0.45) plunging onto the 1.5 m
##     glacier valley floor past the frozen turquoise alpine lake
##   * base switchback & epic 12.0 m west mountainside climb (1.5 m -> 13.5 m,
##     with 'C' waist knot) back up to the 13.5 m summit plateau

const GRID: PackedStringArray = [
	"XXXXXXXXXXXXXXXXXXX",
	"XXWSSBSSSSSSSSSJWXX",
	"XXSXXXXXXXXXXXXXSXX",
	"XXSXXXXXXXXXXXXXSXX",
	"XXSXXXXXXXXXXXXXSXX",
	"XXRSSSSLXXXLSSSSRXX",
	"XXXXXXXSXXXSXXXXXXX",
	"XXXXXXXCXXXSXXXXXXX",
	"XXXXXXXSXXXLSSSSRXX",
	"XXXRSSSLXXXXXXXXSXX",
	"XXXSXXXXXXXXXXXXSXX",
	"XXXSXXXXXXXXXXXXSXX",
	"XXXWSSSSSBSSSSSSWXX",
	"XXXXXXXXXXXXXXXXXXX",
]

const HEIGHTS: PackedStringArray = [
	"...................",
	"..999999999999999..",
	"..9.............9..",
	"..8.............7..",
	"..6.............6..",
	"..666544...444566..",
	".......4...4.......",
	".......3...2.......",
	".......2...222222..",
	"...11222........2..",
	"...1............1..",
	"...1............1..",
	"...11111111111111..",
	"...................",
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
const LAP_LENGTH: int = 1049


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
		"hoarding_density": 0.28,
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
