extends RefCounted
## Registry of every selectable race map and minigame.
##
## A race map is a tile map: `tiles` lists the modular track tiles in lap order,
## each with the grid cell and quarter-turn rotation it sits on, plus optional
## hook/surface overrides. TrackSpline turns that list into the closed centreline
## and the tile library (scripts/minigames/maps/tiles/) builds the road, kerbs,
## barriers, fencing, grandstands, signage, pit complex, foliage and haze from
## the same list. Editing a map is editing this array.
##
## `kind` is `map` for a tile circuit and `minigame` for a hand-built scene. A
## minigame also carries the `scene` the menu loads and its selectable theme
## variants; the chosen theme id is kept in GameSettings.selected_minigame, the
## exact field cargo_rush.gd reads.
##
## `elevation` is an array of {at, height} keys. `at` is a lap fraction in
## 0..1 and `height` is metres above the flat world plane. A single key (or an
## empty array) means a flat lap. A jump tile adds its own crest on top.
##
## `surfaces` is an array of {kind, from, to} spans, also in lap fractions, used
## by the menu accent. The live grip model derives its spans from the tiles
## themselves (TileLayout.surfaces), so a wet or ice section always matches the
## tile that carries it. Kinds are `normal`, `wet` and `ice`.
##
## `theme` is the script grass_race loads for the map's scenery pass, `ground`
## configures the world plane texture and `preview` is the menu image.

const KIND_MAP: String = "map"
const KIND_MINIGAME: String = "minigame"
const DEFAULT_ID: String = "circuit"

## Grip multiplier applied by CartPlayer.surface_grip for each surface kind.
## 1.0 leaves the dry-road handling untouched.
const SURFACE_GRIPS: Dictionary = {
	"normal": 1.0,
	"wet": 0.80,
	"ice": 0.40,
}

const TILE_THEME: String = "res://scripts/minigames/maps/tiles/"

const PRESETS: Array[Dictionary] = [
	{
		"id": "circuit",
		"kind": KIND_MAP,
		"name": "STADIUM CIRCUIT",
		"desc": "Tight stadium loop: pit straight, split apron, chicane and four kerbed corners. Grandstands, catch fencing and floodlights on every side.",
		"preview": "meadow_loop.png",
		"theme": TILE_THEME + "theme_stadium.gd",
		# 14 tiles on a 26 m grid, 156 x 81 m footprint, ~448 m lap.
		"tiles": [
			{"id": "start", "at": [1, 0], "rot": 0,
				"hooks": ["start", "grandstand"], "side": -1.0},
			{"id": "pit", "at": [2, 0], "rot": 0},
			{"id": "split", "at": [4, 0], "rot": 0},
			{"id": "corner", "at": [6, 0], "rot": 0, "hooks": ["grandstand"]},
			{"id": "straight", "at": [6, 1], "rot": 1},
			{"id": "straight", "at": [6, 2], "rot": 1},
			{"id": "corner", "at": [6, 3], "rot": 1, "hooks": ["grandstand"]},
			{"id": "chicane", "at": [5, 3], "rot": 2},
			{"id": "long", "at": [3, 3], "rot": 2, "hooks": ["grandstand"],
				"side": 1.0},
			{"id": "straight", "at": [1, 3], "rot": 2},
			{"id": "corner", "at": [0, 3], "rot": 2, "hooks": ["grandstand"]},
			{"id": "straight", "at": [0, 2], "rot": 3},
			{"id": "straight", "at": [0, 1], "rot": 3},
			{"id": "corner", "at": [0, 0], "rot": 3},
		],
		"elevation": [
			{"at": 0.0, "height": 0.0},
		],
		"surfaces": [
			{"kind": "normal", "from": 0.0, "to": 1.0},
		],
		"ground": {
			"diff": "grass_diff", "nor": "grass_nor", "rough": "grass_rough",
			"uv_scale": 140.0, "tint": Color(0.72, 0.88, 0.65),
			"detail": 0.10, "macro": 0.05,
		},
	},
	{
		"id": "dockyard",
		"kind": KIND_MAP,
		"name": "DOCKYARD QUAY",
		"desc": "Technical quay loop: hairpin, wet chicane, mirrored quay corner and container yards. Worn concrete, tyre walls and floodlights over the water.",
		"preview": "dockyard.png",
		"theme": TILE_THEME + "theme_dockyard.gd",
		# 15 tiles, 130 x 104 m footprint, ~437 m lap.
		"tiles": [
			{"id": "start", "at": [1, 0], "rot": 0,
				"hooks": ["start", "grandstand"], "side": -1.0},
			{"id": "pit", "at": [2, 0], "rot": 0},
			{"id": "straight", "at": [4, 0], "rot": 0},
			{"id": "hairpin", "at": [5, 0], "rot": 0},
			{"id": "chicane", "at": [4, 1], "rot": 2, "surface": "wet"},
			{"id": "corner", "at": [2, 1], "rot": 2, "mirror": true,
				"surface": "wet"},
			{"id": "straight", "at": [2, 2], "rot": 1, "surface": "wet",
				"hooks": ["grandstand"], "side": -1.0},
			{"id": "straight", "at": [2, 3], "rot": 1, "hooks": ["containers"],
				"side": 1.0},
			{"id": "corner", "at": [2, 4], "rot": 1, "hooks": ["grandstand"]},
			{"id": "straight", "at": [1, 4], "rot": 2},
			{"id": "corner", "at": [0, 4], "rot": 2},
			{"id": "straight", "at": [0, 3], "rot": 3},
			{"id": "straight", "at": [0, 2], "rot": 3, "hooks": ["grandstand"],
				"side": -1.0},
			{"id": "straight", "at": [0, 1], "rot": 3, "hooks": ["containers"],
				"side": -1.0},
			{"id": "corner", "at": [0, 0], "rot": 3},
		],
		"elevation": [
			{"at": 0.0, "height": 0.0},
		],
		"surfaces": [
			{"kind": "normal", "from": 0.0, "to": 0.33},
			{"kind": "wet", "from": 0.33, "to": 0.62},
			{"kind": "normal", "from": 0.62, "to": 1.0},
		],
		"ground": {
			"diff": "concrete_floor_worn_001_diff",
			"nor": "concrete_floor_worn_001_nor",
			"rough": "concrete_floor_worn_001_rough",
			"uv_scale": 120.0, "tint": Color(0.70, 0.70, 0.68),
			"detail": 0.12, "macro": 0.06,
		},
	},
	{
		"id": "glacier",
		"kind": KIND_MAP,
		"name": "GLACIER PASS",
		"desc": "Fast alpine loop: long straights, a wide ice sweeper and one big crest jump. Snow banks, pines and cold haze beyond the catch fence.",
		"preview": "glacier.png",
		"theme": TILE_THEME + "theme_glacier.gd",
		# 16 tiles, 182 x 104 m footprint, ~539 m lap.
		"tiles": [
			{"id": "start", "at": [1, 0], "rot": 0,
				"hooks": ["start", "grandstand"], "side": -1.0},
			{"id": "pit", "at": [2, 0], "rot": 0},
			{"id": "long", "at": [4, 0], "rot": 0, "hooks": ["grandstand"],
				"side": -1.0},
			{"id": "straight", "at": [6, 0], "rot": 0},
			{"id": "corner", "at": [7, 0], "rot": 0, "hooks": ["grandstand"]},
			{"id": "straight", "at": [7, 1], "rot": 1, "surface": "ice"},
			{"id": "straight", "at": [7, 2], "rot": 1, "surface": "ice"},
			{"id": "sweeper", "at": [7, 3], "rot": 1, "surface": "ice",
				"hooks": ["grandstand"]},
			{"id": "jump", "at": [5, 4], "rot": 2},
			{"id": "long", "at": [3, 4], "rot": 2, "surface": "ice",
				"hooks": ["grandstand"], "side": 1.0},
			{"id": "straight", "at": [1, 4], "rot": 2},
			{"id": "corner", "at": [0, 4], "rot": 2},
			{"id": "straight", "at": [0, 3], "rot": 3},
			{"id": "straight", "at": [0, 2], "rot": 3},
			{"id": "straight", "at": [0, 1], "rot": 3},
			{"id": "corner", "at": [0, 0], "rot": 3},
		],
		"elevation": [
			{"at": 0.0, "height": 0.0},
			{"at": 0.18, "height": 1.3},
			{"at": 0.36, "height": 0.5},
			{"at": 0.50, "height": 2.0},
			{"at": 0.64, "height": 3.2},
			{"at": 0.78, "height": 1.4},
			{"at": 0.90, "height": 2.8},
		],
		"surfaces": [
			{"kind": "normal", "from": 0.0, "to": 0.33},
			{"kind": "ice", "from": 0.33, "to": 0.54},
			{"kind": "normal", "from": 0.54, "to": 0.63},
			{"kind": "ice", "from": 0.63, "to": 0.73},
			{"kind": "normal", "from": 0.73, "to": 1.0},
		],
		"ground": {
			"diff": "snow_02_diff", "nor": "snow_02_nor",
			"rough": "snow_02_rough", "uv_scale": 160.0,
			"tint": Color(0.96, 0.98, 1.0), "detail": 0.08, "macro": 0.04,
		},
	},
	{
		"id": "cargo_rush",
		"kind": KIND_MINIGAME,
		"name": "CARGO RUSH",
		"desc": "Two-team 90 second scramble: shove cargo crates into your delivery pad.",
		"preview": "cargo_rush.png",
		# Not a tile map: the menu loads this scene directly, and the chosen
		# theme id travels in GameSettings.selected_minigame (cargo_rush.gd
		# resolves it with CargoTheme.resolve, online via session_minigame).
		"scene": "res://scenes/minigames/cargo_rush.tscn",
		"hint": "90 SECOND SCRAMBLE",
		"default_theme": "harbour",
		"themes": [
			# "harbour", not "dockyard": the Dockyard Quay race map owns that
			# id, and a cargo theme must never be read as a race map. The theme
			# registry resolves the alias back to the dockyard arena skin.
			{"id": "harbour", "name": "DOCKYARD"},
			{"id": "farmyard", "name": "FARMYARD"},
			{"id": "snowfield", "name": "SNOWFIELD"},
		],
	},
]

## Legacy ids that still resolve to a race map, so old saves keep working.
const LEGACY_IDS: Dictionary = {
	"meadow_loop": "circuit",
	"alpine": "glacier",
	"alpine_slide": "glacier",
}


## Every preset id in registry order.
static func all_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for preset: Dictionary in PRESETS:
		ids.append(str(preset.get("id", DEFAULT_ID)))
	return ids


## Registry kind of `preset`. Entries without a kind stay race maps, so old
## saves and any external preset dictionaries keep their meaning.
static func kind_of(preset: Dictionary) -> String:
	return str(preset.get("kind", KIND_MAP))


## True when `preset` is a tile race map that grass_race can build.
static func is_map(preset: Dictionary) -> bool:
	return kind_of(preset) == KIND_MAP


## True when `preset` is a hand-built minigame scene.
static func is_minigame(preset: Dictionary) -> bool:
	return kind_of(preset) == KIND_MINIGAME


## Selectable theme ids for a minigame, in menu order. Empty for a map.
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


## Display names for a minigame's theme variants, in `theme_ids()` order. The
## id is the fallback when an entry has no label.
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


## The theme id a minigame falls back to when nothing is stored yet.
static func default_theme(preset: Dictionary) -> String:
	var ids: PackedStringArray = theme_ids(preset)
	var wanted: String = str(preset.get("default_theme", ""))
	if ids.has(wanted):
		return wanted
	return ids[0] if not ids.is_empty() else ""


## True when `id` is one of the selectable minigame theme ids in the registry.
static func has_theme_id(id: String) -> bool:
	for preset: Dictionary in PRESETS:
		if theme_ids(preset).has(id):
			return true
	return false


## The race map for `id`, or the first map when the id is unknown. Legacy ids
## (`meadow_loop`, `alpine`) map to their replacement so old saves keep working.
## Minigames and their theme ids are never returned here: grass_race must not try
## to build a spline from the cargo arena's theme selection.
static func get_preset(id: String) -> Dictionary:
	var key: String = str(LEGACY_IDS.get(id, id))
	for preset: Dictionary in PRESETS:
		if is_map(preset) and str(preset.get("id", "")) == key:
			return preset
	for preset: Dictionary in PRESETS:
		if is_map(preset):
			return preset
	return PRESETS[0]


## Registry index for `id`, or 0 for an unknown/legacy id. A minigame theme id
## maps back to the card that owns it, which is how the menu restores the
## cargo rush selection from GameSettings.selected_minigame.
static func index_of(id: String) -> int:
	var key: String = str(LEGACY_IDS.get(id, id))
	for index in PRESETS.size():
		if str(PRESETS[index].get("id", "")) == key:
			return index
	for index in PRESETS.size():
		if theme_ids(PRESETS[index]).has(key):
			return index
	return 0


## Surface kind at a lap fraction. `lap_fraction` may be any real value; it is
## wrapped into 0..1. Spans that cross the start line are supported. This is the
## registry-level answer used by the menu and by anything without a spline; the
## race itself asks TileLayout so the spans can never drift from the tiles.
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


## Grip multiplier for a surface kind. Unknown kinds behave like dry road.
static func surface_grip(kind: String) -> float:
	return float(SURFACE_GRIPS.get(kind, 1.0))


## Convenience: grip multiplier at a lap fraction for `preset`.
static func grip_at(preset: Dictionary, lap_fraction: float) -> float:
	return surface_grip(surface_at(preset, lap_fraction))
