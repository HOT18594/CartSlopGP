extends RefCounted
## Authoritative route data for the Glacier Pass high-alpine cliffside circuit.
##
## Route (90 drivable cells, ~1923 m lap, difficulty EXPERT):
##   * 13.5 m high-cliff summit pass along the northern rock wall with speed
##     crest B and Broken Cliff Chasm Jump #1 (J at (12,1) leaping over (13,1))
##   * upper cliff ledge step-out (13.5 m -> 9.0 m) into the Mid-Mountain
##     Glacial Shelf and Broken Cliff Chasm Jump #2 (J at (19,6) leaping over (18,6))
##   * upper ice switchback descent (9.0 m -> 3.0 m, grip = 0.45) cut into the
##     eastern glacier face under the dual-cable alpine gondola line
##   * lower ice valley & frozen turquoise tarn loop (1.5 m, grip = 0.45) past
##     the snow-roofed ski lodge village and crystalline ice arches
##   * western cliffside switchback climb (1.5 m -> 6.0 m -> 9.0 m -> 13.5 m)
##     ascending the sheer slate-and-snow mountain face back to the summit!

const GRID: PackedStringArray = [
	"XXXXXXXXXXXXXXXXXXXXXXXXX",
	"XXWSSSSBSSSSJSSSSWXXXXXXX",
	"XXSXXXXXXXXXXXXXXSXXXXXXX",
	"XXSXXXXXXXXXXXXXXLSSSSWXX",
	"XXSXXXXXXXXXXXXXXXXXXXSXX",
	"XXSXXXXXXXXXXXXXXXXXXXSXX",
	"XXRSLXXXXXXXXXXXWSSJSSRXX",
	"XXXXSXXXXXXXXXXXSXXXXXXXX",
	"XXXXSXXXXXXXXXXXSXXXXXXXX",
	"XXXXSXXXXXXXXXXXSXXXXXXXX",
	"XXRSLXXXXXXXXXXXLSSSSSWXX",
	"XXSXXXXXXXXXXXXXXXXXXXSXX",
	"XXSXXXXXXXXXXXXXXXXXXXSXX",
	"XXSXXXXXXXXXXXXXXXXXXXSXX",
	"XXWSSSSSSWXXXXXWSSSSSSWXX",
	"XXXXXXXXXSXXXXXSXXXXXXXXX",
	"XXXXXXXXXWSSBSSWXXXXXXXXX",
	"XXXXXXXXXXXXXXXXXXXXXXXXX",
]

const HEIGHTS: PackedStringArray = [
	".........................",
	"..9999999999999999.......",
	"..9..............9.......",
	"..9..............998777..",
	"..8...................7..",
	"..7...................6..",
	"..666...........6666666..",
	"....6...........6........",
	"....5...........5........",
	"....4...........4........",
	"..444...........4443222..",
	"..4...................2..",
	"..3...................2..",
	"..2...................1..",
	"..11111111.....11111111..",
	".........1.....1.........",
	".........1111111.........",
	".........................",
]

const ELEVATION: Array[Dictionary] = [
	{"at": 0.0, "height": 13.5},
	{"at": 0.17, "height": 13.5},
	{"at": 0.27, "height": 9.0},
	{"at": 0.36, "height": 9.0},
	{"at": 0.49, "height": 3.0},
	{"at": 0.56, "height": 1.5},
	{"at": 0.77, "height": 1.5},
	{"at": 0.86, "height": 6.0},
	{"at": 0.93, "height": 9.0},
	{"at": 0.98, "height": 13.5},
]

const SURFACES: Array[Dictionary] = [
	{"kind": "normal", "from": 0.0, "to": 0.24},
	{"kind": "ice", "from": 0.24, "to": 0.42},
	{"kind": "normal", "from": 0.42, "to": 0.52},
	{"kind": "ice", "from": 0.52, "to": 0.76},
	{"kind": "normal", "from": 0.76, "to": 1.0},
]

const START_CELL: Vector2i = Vector2i(3, 1)
const HEIGHT_STEP: float = 1.5
const LAP_LENGTH: int = 1923


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
	return "%d drivable cells, ~%d m, summit %.1f m, base %.1f m, %.1f m of climb, two cliff chasm jumps, two ice sectors" % [
		drivable, LAP_LENGTH, float(highest) * HEIGHT_STEP,
		float(lowest) * HEIGHT_STEP,
		float(highest - lowest) * HEIGHT_STEP]
