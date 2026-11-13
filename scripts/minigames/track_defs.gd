extends RefCounted
## Registry of every selectable race map and minigame.
##
## A race map is a Kenney grid map: `grid` is the ASCII tile layout drawn
## top-down on a 16 m lattice (see scripts/minigames/tiles/kenney_tiles.gd) and
## `theme_id` names the cartoon theme that dresses it. The engine turns the
## characters into a closed centreline, the road meshes and the road colliders;
## the theme adds barriers, stands, lights, signage and foliage.
##
## Grid legend: S straight, L left corner, R right corner, C crossing, W wide
## sweeper, B bump, J jump ramp, P pit straight, E pit entry, G pit garage,
## X empty. A cell is 16 m. Every drivable cell must be on one closed loop.
##
## Theme contract (created by the map agents, not this file):
##   # res://scripts/minigames/maps/<id>_theme.gd
##   static func build(race: Node3D, spline) -> void
## The theme calls tile_kit.* for dressing and returns nothing. The race scene
## builds the grid once with
##   KenneyTiles.build(race, TrackDefs.grid_of(preset),
##       {"id": TrackDefs.theme_id_of(preset)})
## and hands the returned grid spline to that build() call.
##
## `kind` is `map` for a grid circuit and `minigame` for a hand-built scene. A
## minigame also carries the `scene` the menu loads and its selectable theme
## variants; the chosen theme id is kept in GameSettings.selected_minigame, the
## exact field cargo_rush.gd reads.
##
## `surfaces` is an array of {kind, from, to} lap-fraction spans used by the
## registry-level grip model and the menu accent. The grid engine is dry tarmac;
## a map that wants ice or wet sections lists them here. Kinds are `normal`,
## `wet` and `ice`.
##
## `preview` is the menu image under res://assets/ui/minigames/. `palette` is
## the flat cartoon palette the theme reads (ground, sky, haze); it never names
## a texture.

const KIND_MAP: String = "map"
const KIND_MINIGAME: String = "minigame"
const DEFAULT_ID: String = "stadium"

## Grip multiplier applied by CartPlayer.surface_grip for each surface kind.
## 1.0 leaves the dry-road handling untouched.
const SURFACE_GRIPS: Dictionary = {
	"normal": 1.0,
	"wet": 0.80,
	"ice": 0.40,
}

## Folder the map agents put their theme scripts in.
const THEME_ROOT: String = "res://scripts/minigames/maps/"

const PRESETS: Array[Dictionary] = [
	{
		"id": "stadium",
		"kind": KIND_MAP,
		"name": "STADIUM CIRCUIT",
		"desc": "Tight cartoon stadium loop on a 16 m grid: pit straight, two long straights, a crossing and four kerbed corners. Grandstands, catch fencing and floodlights on every side.",
		"preview": "meadow_loop.png",
		"theme": THEME_ROOT + "stadium_theme.gd",
		"theme_id": "stadium",
		"grid": [
			"XXXXXXXXXXXX",
			"XRSSPEEGSSRX",
			"XSXXXXXXXXSX",
			"XBXXXXXXXXJX",
			"XSXXXXXXXXSX",
			"XSXXXXXXXXSX",
			"XRSSCSJBSSRX",
			"XXXXXXXXXXXX",
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
		"id": "dockyard",
		"kind": KIND_MAP,
		"name": "DOCKYARD QUAY",
		"desc": "Technical cartoon quay loop: an inset chicane, a wet middle sector and a long container-yard straight. Flat concrete, tyre walls and floodlights over the water.",
		"preview": "meadow_loop.png",
		"theme": THEME_ROOT + "dockyard_theme.gd",
		"theme_id": "dockyard",
		"grid": [
			"XXXXXXXXXXXXXXX",
			"XXXXXXXXXXXXXXX",
			"XXRSSRXXRSSSRXX",
			"XXSXXLSSLXXXSXX",
			"XXSXXXXXXXXXSXX",
			"XXSXXXXXXXXXSXX",
			"XXSXXXXXXXXXSXX",
			"XXRSSSSSSSSSRXX",
			"XXXXXXXXXXXXXXX",
			"XXXXXXXXXXXXXXX",
		],
		"elevation": [
			{"at": 0.0, "height": 0.0},
		],
		"surfaces": [
			{"kind": "normal", "from": 0.0, "to": 0.30},
			{"kind": "wet", "from": 0.30, "to": 0.58},
			{"kind": "normal", "from": 0.58, "to": 1.0},
		],
		"palette": {
			"ground": Color("7d8b93"), "sky": Color("c4d6dd"),
			"haze": Color("aebfc7"), "kerb": Color("e8c34a"),
		},
	},
	{
		"id": "glacier",
		"kind": KIND_MAP,
		"name": "GLACIER PASS",
		"desc": "Fast cartoon alpine loop: two wide sweepers, long straights, a bump and a big crest jump. Snow banks, pines and cold flat haze beyond the catch fence.",
		"preview": "meadow_loop.png",
		"theme": THEME_ROOT + "glacier_theme.gd",
		"theme_id": "glacier",
		"grid": [
			"XXXXXXXXXXXXXX",
			"XWSSSJSSSSPPWX",
			"XSXXXXXXXXXXSX",
			"XSXXXXXXXXXXSX",
			"XSXXXXXXXXXXSX",
			"XSXXXXXXXXXXSX",
			"XRSBSSSSBSSSRX",
			"XXXXXXXXXXXXXX",
		],
		"elevation": [
			{"at": 0.0, "height": 0.0},
		],
		"surfaces": [
			{"kind": "normal", "from": 0.0, "to": 0.28},
			{"kind": "ice", "from": 0.28, "to": 0.52},
			{"kind": "normal", "from": 0.52, "to": 0.66},
			{"kind": "ice", "from": 0.66, "to": 0.80},
			{"kind": "normal", "from": 0.80, "to": 1.0},
		],
		"palette": {
			"ground": Color("e8f1f7"), "sky": Color("e6f2fa"),
			"haze": Color("dbe8ef"), "kerb": Color("2e86ab"),
		},
	},
	{
		"id": "cargo_rush",
		"kind": KIND_MINIGAME,
		"name": "CARGO RUSH",
		"desc": "Two-team 90 second scramble: shove cargo crates into your delivery pad.",
		"preview": "cargo_rush.png",
		# Not a grid map: the menu loads this scene directly, and the chosen
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
## Chains are resolved until they land on a live preset id.
const LEGACY_IDS: Dictionary = {
	"meadow_loop": "circuit",
	"circuit": "stadium",
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


## True when `preset` is a grid race map that the tile engine can build.
static func is_map(preset: Dictionary) -> bool:
	return kind_of(preset) == KIND_MAP


## True when `preset` is a hand-built minigame scene.
static func is_minigame(preset: Dictionary) -> bool:
	return kind_of(preset) == KIND_MINIGAME


## ASCII grid rows for a grid map, or an empty array for a minigame.
static func grid_of(preset: Dictionary) -> PackedStringArray:
	var raw: Variant = preset.get("grid", PackedStringArray())
	if raw is PackedStringArray:
		return raw as PackedStringArray
	if raw is Array:
		var rows := PackedStringArray()
		for row: Variant in raw as Array:
			rows.append(str(row))
		return rows
	return PackedStringArray()


## Cartoon theme id a grid map's theme script reads. Falls back to the map id.
static func theme_id_of(preset: Dictionary) -> String:
	return str(preset.get("theme_id", preset.get("id", DEFAULT_ID)))


## Path of the theme script grass_race loads for a map. Empty for a minigame.
static func theme_path_of(preset: Dictionary) -> String:
	if is_minigame(preset):
		return ""
	return str(preset.get("theme", THEME_ROOT + theme_id_of(preset) + "_theme.gd"))


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


## Follows LEGACY_IDS until the id stops changing.
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


## The race map for `id`, or the first map when the id is unknown. Legacy ids
## (`meadow_loop`, `circuit`, `alpine`) map to their replacement so old saves
## keep working. Minigames and their theme ids are never returned here:
## grass_race must not try to build a grid from the cargo arena's theme.
static func get_preset(id: String) -> Dictionary:
	var key: String = _resolve(id)
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
	var key: String = _resolve(id)
	for index in PRESETS.size():
		if str(PRESETS[index].get("id", "")) == key:
			return index
	for index in PRESETS.size():
		if theme_ids(PRESETS[index]).has(key):
			return index
	return 0


## Surface kind at a lap fraction. `lap_fraction` may be any real value; it is
## wrapped into 0..1. Spans that cross the start line are supported. The grid
## engine is dry tarmac; wet and ice sections are declared here and the race
## reads them through grip_at().
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
