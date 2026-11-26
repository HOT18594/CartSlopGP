extends RefCounted
## Registry of every selectable race map and minigame.
##
## A race map is a Kenney grid map: `grid` is the ASCII tile layout drawn
## top-down on a 22 m lattice (see scripts/minigames/tiles/kenney_tiles.gd) and
## `theme_id` names the cartoon theme that dresses it. The engine turns the
## characters into a closed centreline, the road meshes and the road colliders;
## the theme adds barriers, stands, lights, signage, water and foliage.
##
## Grid legend: S straight, L left corner, R right corner, C crossing, W wide
## sweeper, B bump, J jump ramp, P pit straight, E pit entry, G pit garage,
## X / . empty. A cell is 22 m (TILE_SIZE 22.0, ROAD_HALF ~7.59 m). Every drivable cell must be on one closed loop.

const KIND_MAP: String = "map"
const KIND_MINIGAME: String = "minigame"
const DEFAULT_ID: String = "stadium"

## Grip multiplier applied by CartPlayer.surface_grip and RaceAI for each
## surface kind. 1.0 leaves dry-road handling untouched.
const SURFACE_GRIPS: Dictionary = {
	"normal": 1.0,
	"dirt": 0.86,
	"wet": 0.80,
	"ice": 0.45,
}

## Folder the map themes live in.
const THEME_ROOT: String = "res://scripts/minigames/maps/"

const StadiumGrid := preload("res://scripts/minigames/maps/stadium/stadium_grid.gd")
const MeadowGrid := preload("res://scripts/minigames/maps/meadow/meadow_grid.gd")
const CanyonGrid := preload("res://scripts/minigames/maps/canyon/canyon_grid.gd")
const DockyardGrid := preload("res://scripts/minigames/maps/dockyard/dockyard_grid.gd")
const GlacierCourse := preload("res://scripts/minigames/maps/glacier/glacier_course.gd")

const PRESETS: Array[Dictionary] = [
	{
		"id": "stadium",
		"kind": KIND_MAP,
		"name": "STADIUM CIRCUIT",
		"desc": "Open grand prix arena circuit: wide sweeping pit straight, technical S-bends climbing to a 9.0 m sky-bridge, kicker jump and lush infield park.",
		"tagline": "Wide open grand prix straights, sky-bridge jump and terraced arena vistas.",
		"lap_length": 1486,
		"difficulty": "EASY",
		"preview": "preview_stadium.png",
		"theme": THEME_ROOT + "stadium_theme.gd",
		"theme_id": "stadium",
		"grid": [
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
		],
		"heights": [
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
		],
		"elevation": [
			{"at": 0.0, "height": 0.0},
		],
		"surfaces": [
			{"kind": "normal", "from": 0.0, "to": 1.0},
		],
		"palette": {
			"ground": Color("6fae4a"), "sky": Color("bfe9ff"),
			"haze": Color("cfe8d4"), "kerb": Color("c23a2c"),
		},
	},
	{
		"id": "meadow",
		"kind": KIND_MAP,
		"name": "REDWOOD VALLEY",
		"desc": "Open redwood valley & alpine meadow circuit: wildflower sweepers climbing to a 9.0 m mountain overlook, stone river viaduct, waterwheel mill and forest dirt trail.",
		"tagline": "Open redwood meadows, river bridge viaduct, waterfall cove and dirt trail.",
		"lap_length": 1443,
		"difficulty": "MEDIUM",
		"preview": "preview_meadow.png",
		"theme": THEME_ROOT + "meadow_theme.gd",
		"theme_id": "meadow",
		"grid": [
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
		],
		"heights": [
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
		],
		"elevation": [
			{"at": 0.0, "height": 0.0},
		],
		"surfaces": [
			{"kind": "normal", "from": 0.0, "to": 0.72},
			{"kind": "dirt", "from": 0.72, "to": 0.93},
			{"kind": "normal", "from": 0.93, "to": 1.0},
		],
		"palette": {
			"ground": Color("68ab48"), "sky": Color("aee6f8"),
			"haze": Color("cfe9d8"), "kerb": Color("c9562c"),
		},
	},
	{
		"id": "canyon",
		"kind": KIND_MAP,
		"name": "SUNSET CANYON",
		"desc": "Open red-rock mesa & desert oasis canyon: wide 12.0 m mesa rim skyway, sculpted natural stone arches, palm-lined spring oasis and desert switchbacks.",
		"tagline": "Open 12 m mesa skyway, sculpted stone arches and palm oasis.",
		"lap_length": 1620,
		"difficulty": "MEDIUM",
		"preview": "preview_canyon.png",
		"theme": THEME_ROOT + "canyon_theme.gd",
		"theme_id": "canyon",
		"grid": [
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
		],
		"heights": [
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
		],
		"elevation": [
			{"at": 0.0, "height": 12.0},
		],
		"surfaces": [
			{"kind": "normal", "from": 0.0, "to": 0.40},
			{"kind": "dirt", "from": 0.40, "to": 0.61},
			{"kind": "wet", "from": 0.61, "to": 0.72},
			{"kind": "dirt", "from": 0.72, "to": 0.85},
			{"kind": "normal", "from": 0.85, "to": 1.0},
		],
		"palette": {
			"ground": Color("d97a46"), "sky": Color("ffb978"),
			"haze": Color("f6bf8a"), "kerb": Color("e59449"),
		},
	},
	{
		"id": "dockyard",
		"kind": KIND_MAP,
		"name": "DOCKYARD QUAY",
		"desc": "Open multi-level container port: 7.5 m crane-deck overpass, harbourside chicane, colourful container yard, wet seawall straight past bobbing cargo ships and lighthouse.",
		"tagline": "Open 7.5 m crane-deck overpass, harbour chicane and seaside cargo ships.",
		"lap_length": 1529,
		"difficulty": "HARD",
		"preview": "preview_dockyard.png",
		"theme": THEME_ROOT + "dockyard_theme.gd",
		"theme_id": "dockyard",
		"grid": [
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
		],
		"heights": [
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
		],
		"elevation": [
			{"at": 0.0, "height": 7.5},
		],
		"surfaces": [
			{"kind": "normal", "from": 0.0, "to": 0.46},
			{"kind": "wet", "from": 0.46, "to": 0.72},
			{"kind": "normal", "from": 0.72, "to": 1.0},
		],
		"palette": {
			"ground": Color("7d8b93"), "sky": Color("a8d8f2"),
			"haze": Color("a8d4e8"), "kerb": Color("e8c34a"),
		},
	},
	{
		"id": "glacier",
		"kind": KIND_MAP,
		"name": "GLACIER PASS",
		"desc": "High-alpine cliffside switchbacks & broken glacier chasm jumps: 13.5 m sheer mountain pass, weight-balanced cliff leaps, giant glowing turquoise ice crystals, warm lantern guardrails, overhead gondolas and Northern Lights.",
		"tagline": "13.5 m cliffside mountain pass, broken glacier chasm jumps, glowing crystals & aurora skies.",
		"lap_length": 1923,
		"difficulty": "EXPERT",
		"preview": "preview_glacier.png",
		"theme": THEME_ROOT + "glacier_theme.gd",
		"theme_id": "glacier",
		"grid": [
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
		],
		"heights": [
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
		],
		"elevation": [
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
		],
		"surfaces": [
			{"kind": "normal", "from": 0.0, "to": 0.24},
			{"kind": "ice", "from": 0.24, "to": 0.42},
			{"kind": "normal", "from": 0.42, "to": 0.52},
			{"kind": "ice", "from": 0.52, "to": 0.76},
			{"kind": "normal", "from": 0.76, "to": 1.0},
		],
		"palette": {
			"ground": Color("cfe6f7"), "sky": Color("0b163c"),
			"haze": Color("1e3563"), "kerb": Color("2a86b8"),
		},
	},
	{
		"id": "cargo_rush",
		"kind": KIND_MINIGAME,
		"name": "DELIVER",
		"desc": "Two-team 2 minute scramble: scoop up cargo crates across bridges, hilltops and ice bowls and deliver them into your team pad.",
		"game": "DELIVER",
		"preview": "preview_cargo_rush.png",
		"scene": "res://scenes/minigames/cargo_rush.tscn",
		"hint": "2 TEAMS · 2 MIN",
		"default_theme": "harbour",
		"themes": [
			{
				"id": "harbour",
				"name": "HARBOUR OVERPASS",
				"desc": "Raised steel bridge over twin water trenches and container lanes.",
				"preview": "preview_harbour.png",
			},
			{
				"id": "farmyard",
				"name": "WINDMILL HILLS",
				"desc": "Central hilltop plateau flanked by mud trenches and timber shortcuts.",
				"preview": "preview_farmyard.png",
			},
			{
				"id": "snowfield",
				"name": "GLACIER BOWL",
				"desc": "Sunken slick-ice rink surrounded by four inward snow-berm jump ramps.",
				"preview": "preview_snowfield.png",
			},
		],
	},
	{
		"id": "knockout",
		"kind": KIND_MINIGAME,
		"name": "KNOCKOUT",
		"desc": "Smash rivals off collapsing stages as knockback % climbs.",
		"game": "KNOCKOUT",
		"preview": "preview_knockout.png",
		"scene": "res://scenes/minigames/knockout.tscn",
		"hint": "2-8 PLAYERS · 3 ROUNDS",
		"default_theme": "ko_rooftop",
		"themes": [
			{
				"id": "ko_rooftop",
				"name": "SKYTOP HELIPAD",
				"desc": "Octagonal skyscraper pad with a central dome and dropping outer sectors.",
				"preview": "preview_ko_rooftop.png",
			},
			{
				"id": "ko_foundry",
				"name": "MOLTEN FOUNDRY",
				"desc": "Twin smelter islands linked by narrow bridges over a central lava pit.",
				"preview": "preview_ko_foundry.png",
			},
			{
				"id": "ko_iceberg",
				"name": "FRACTURED ICEBERG",
				"desc": "Slick arctic ice sheet with corner kickers and calving outer shelves.",
				"preview": "preview_ko_iceberg.png",
			},
		],
	},
	{
		"id": "bomb_tag",
		"kind": KIND_MINIGAME,
		"name": "BLAST TAG",
		"desc": "Ram rivals to pass the ticking Mega-Bomb before the fuse blows!",
		"game": "BLAST TAG",
		"preview": "preview_bomb_tag.png",
		"scene": "res://scenes/minigames/bomb_tag.tscn",
		"hint": "2-8 PLAYERS · 2 MIN",
		"default_theme": "bt_plaza",
		"themes": [
			{
				"id": "bt_plaza",
				"name": "TERRACE PLAZA",
				"desc": "Three-tier rooftop plaza with switchback ramps and underpass juke tunnels.",
				"preview": "preview_bt_plaza.png",
			},
			{
				"id": "bt_labyrinth",
				"name": "CANYON LABYRINTH",
				"desc": "Sandstone pillar corridors with a high mesa jump-bridge over the crossroad.",
				"preview": "preview_bt_labyrinth.png",
			},
			{
				"id": "bt_ferries",
				"name": "TWIN FERRIES",
				"desc": "Dual moored cargo barges connected by bridges and water-gap jump ramps.",
				"preview": "preview_bt_ferries.png",
			},
		],
	},
]

## Legacy ids that still resolve to a race map, so old saves keep working.
const LEGACY_IDS: Dictionary = {
	"meadow_loop": "meadow",
	"circuit": "stadium",
	"alpine": "glacier",
	"alpine_slide": "glacier",
}


## Public resolver mapping legacy map ids (`meadow_loop`, `circuit`, `alpine`,
## `alpine_slide`) onto their current canonical id.
static func resolve_id(id: String) -> String:
	return _resolve(id)


## Every preset id in registry order.
static func all_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for preset: Dictionary in PRESETS:
		ids.append(str(preset.get("id", DEFAULT_ID)))
	return ids


static func kind_of(preset: Dictionary) -> String:
	return str(preset.get("kind", KIND_MAP))


static func is_map(preset: Dictionary) -> bool:
	return kind_of(preset) == KIND_MAP


static func is_minigame(preset: Dictionary) -> bool:
	return kind_of(preset) == KIND_MINIGAME


static func _course_of(id: String) -> Dictionary:
	match id:
		"stadium":
			return {
				"grid": StadiumGrid.grid_rows(),
				"heights": StadiumGrid.height_rows(),
			}
		"meadow":
			return {
				"grid": MeadowGrid.grid_rows(),
				"heights": MeadowGrid.heights(),
				"surfaces": MeadowGrid.surfaces(),
			}
		"canyon":
			return {
				"grid": CanyonGrid.grid_rows(),
				"heights": CanyonGrid.heights(),
				"surfaces": CanyonGrid.surfaces(),
			}
		"dockyard":
			return {
				"grid": DockyardGrid.grid_rows(),
				"heights": DockyardGrid.heights(),
				"surfaces": DockyardGrid.surfaces(),
			}
		"glacier":
			return {
				"grid": GlacierCourse.grid(),
				"heights": GlacierCourse.heights(),
				"surfaces": GlacierCourse.surfaces(),
			}
	return {}


static func heights_of(preset: Dictionary) -> PackedStringArray:
	var routed: Variant = _course_of(str(preset.get("id", ""))).get("heights")
	if routed is PackedStringArray:
		return routed as PackedStringArray
	var raw: Variant = preset.get("heights", PackedStringArray())
	if raw is PackedStringArray:
		return raw as PackedStringArray
	if raw is Array:
		var rows := PackedStringArray()
		for row: Variant in raw as Array:
			rows.append(str(row))
		return rows
	return PackedStringArray()


static func grid_of(preset: Dictionary) -> PackedStringArray:
	var routed: Variant = _course_of(str(preset.get("id", ""))).get("grid")
	if routed is PackedStringArray:
		return routed as PackedStringArray
	var raw: Variant = preset.get("grid", PackedStringArray())
	if raw is PackedStringArray:
		return raw as PackedStringArray
	if raw is Array:
		var rows := PackedStringArray()
		for row: Variant in raw as Array:
			rows.append(str(row))
		return rows
	return PackedStringArray()


static func theme_id_of(preset: Dictionary) -> String:
	return str(preset.get("theme_id", preset.get("id", DEFAULT_ID)))


static func theme_path_of(preset: Dictionary) -> String:
	if is_minigame(preset):
		return ""
	return str(preset.get("theme", THEME_ROOT + theme_id_of(preset) + "_theme.gd"))


static func theme_ids(preset: Dictionary) -> PackedStringArray:
	var ids := PackedStringArray()
	var raw: Variant = preset.get("themes", [])
	if not (raw is Array):
		return ids
	for entry: Variant in raw as Array:
		if entry is Dictionary:
			var id: String = str((entry as Dictionary).get("id", ""))
			if id != "":
				ids.append(id)
		else:
			ids.append(str(entry))
	return ids


static func theme_names(preset: Dictionary) -> PackedStringArray:
	var names := PackedStringArray()
	var raw: Variant = preset.get("themes", [])
	if not (raw is Array):
		return names
	for entry: Variant in raw as Array:
		if entry is Dictionary:
			var theme: Dictionary = entry as Dictionary
			var id: String = str(theme.get("id", ""))
			names.append(str(theme.get("name", id)))
		else:
			names.append(str(entry))
	return names


static func default_theme(preset: Dictionary) -> String:
	var ids: PackedStringArray = theme_ids(preset)
	var wanted: String = str(preset.get("default_theme", ""))
	if ids.has(wanted):
		return wanted
	return ids[0] if not ids.is_empty() else ""


static func has_theme_id(id: String) -> bool:
	for preset: Dictionary in PRESETS:
		if theme_ids(preset).has(id):
			return true
	return false


## Returns the KIND_MINIGAME preset owning `theme_id` (or matching a minigame
## preset id directly), or `{}` when `theme_id` belongs to no minigame.
static func minigame_for_theme(theme_id: String) -> Dictionary:
	var clean: String = theme_id.strip_edges().to_lower()
	if clean == "":
		return {}
	for preset: Dictionary in PRESETS:
		if not is_minigame(preset):
			continue
		if theme_ids(preset).has(clean):
			return preset
		if str(preset.get("id", "")) == clean:
			return preset
	return {}


## Returns the scene path for the minigame owning `theme_id`, or `""` if none.
static func scene_for_minigame_theme(theme_id: String) -> String:
	var preset: Dictionary = minigame_for_theme(theme_id)
	if preset.is_empty():
		return ""
	return str(preset.get("scene", ""))


## Returns the theme dictionary inside `preset["themes"]` matching `theme_id`,
## or `{}` if not found.
static func theme_entry(preset: Dictionary, theme_id: String) -> Dictionary:
	var raw: Variant = preset.get("themes", [])
	if not (raw is Array):
		return {}
	for entry: Variant in raw as Array:
		if entry is Dictionary:
			var theme: Dictionary = entry as Dictionary
			if str(theme.get("id", "")) == theme_id:
				return theme
	return {}


## Returns a KIND_MINIGAME preset by preset id (`cargo_rush`, `knockout`,
## `bomb_tag`), or `{}` if not found.
static func get_minigame(id: String) -> Dictionary:
	var clean: String = id.strip_edges().to_lower()
	for preset: Dictionary in PRESETS:
		if is_minigame(preset) and str(preset.get("id", "")) == clean:
			return preset
	return {}


static func _resolve(id: String) -> String:
	var key: String = id
	for _hop in LEGACY_IDS.size() + 1:
		if not LEGACY_IDS.has(key):
			return key
		var next: String = str(LEGACY_IDS[key])
		if next == key:
			return key
		key = next
	return key


static func _with_course(preset: Dictionary) -> Dictionary:
	var course: Dictionary = _course_of(str(preset.get("id", "")))
	if course.is_empty():
		return preset
	var merged: Dictionary = preset.duplicate(true)
	for key: String in course:
		merged[key] = course[key]
	return merged


static func get_preset(id: String) -> Dictionary:
	var key: String = _resolve(id)
	for preset: Dictionary in PRESETS:
		if is_map(preset) and str(preset.get("id", "")) == key:
			return _with_course(preset)
	for preset: Dictionary in PRESETS:
		if is_map(preset):
			return _with_course(preset)
	return _with_course(PRESETS[0])


static func index_of(id: String) -> int:
	var key: String = _resolve(id)
	for index in PRESETS.size():
		if str(PRESETS[index].get("id", "")) == key:
			return index
	for index in PRESETS.size():
		if theme_ids(PRESETS[index]).has(key):
			return index
	return 0


static func surface_at(preset: Dictionary, lap_fraction: float) -> String:
	var fraction: float = fposmod(lap_fraction, 1.0)
	var raw: Variant = preset.get("surfaces", [])
	if not (raw is Array):
		return "normal"
	var surfaces: Array = raw as Array
	for entry: Variant in surfaces:
		if not (entry is Dictionary):
			continue
		var span: Dictionary = entry as Dictionary
		var from: float = clampf(float(span.get("from", 0.0)), 0.0, 1.0)
		var to: float = clampf(float(span.get("to", 1.0)), 0.0, 1.0)
		var inside: bool = (fraction >= from and fraction < to) if from <= to \
			else (fraction >= from or fraction < to)
		if not inside:
			continue
		var kind: String = str(span.get("kind", "normal")).to_lower()
		return kind if SURFACE_GRIPS.has(kind) else "normal"
	return "normal"


static func surface_grip(kind: String) -> float:
	return float(SURFACE_GRIPS.get(kind, 1.0))


static func grip_at(preset: Dictionary, lap_fraction: float) -> float:
	return surface_grip(surface_at(preset, lap_fraction))
