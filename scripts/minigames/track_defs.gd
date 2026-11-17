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
##   var theme := {"id": TrackDefs.theme_id_of(preset)}
##   theme["heights"] = TrackDefs.heights_of(preset)
##   KenneyTiles.build(race, TrackDefs.grid_of(preset), theme)
## and hands the returned grid spline to that build() call. `grid_of` and
## `heights_of` route both fields through the same map module, and get_preset()
## overlays that routed course on the preset it returns, so a race, a probe, a
## preview or a theme that reads the preset all build the same elevated map. The
## inline `grid`/`elevation` a preset still carries is only a fallback for older
## saves and unknown ids, and the routed course's `surfaces` replace the inline
## grip spans the same way.
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
##
## Menu fields: `tagline` is the one-line blurb on a map card, `lap_length` the
## built centreline length in metres (measured with KenneyTiles.build) and
## `difficulty` the short tag shown beside it. A minigame may carry `game`, the
## game name its card is listed under (the cargo arena is DELIVER).

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
		"tagline": "Tight stadium loop with a crossing and four kerbed corners.",
		"lap_length": 434,
		"difficulty": "MEDIUM",
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
		"tagline": "Quay loop with an inset chicane and a wet middle sector.",
		"lap_length": 484,
		"difficulty": "HARD",
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
		"tagline": "Alpine crest with two wide sweepers, a bump and ice.",
		"lap_length": 499,
		"difficulty": "EXPERT",
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
		# The games list names the card DELIVER; the arena keeps its own name.
		"game": "DELIVER",
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


## Course modules: each grid map authors its ASCII layout AND its per-cell height
## table in its own file, and the accessors below route both through that one
## module. They are preloaded here rather than referenced by path so a broken
## course fails at parse time with the file that owns it.
const StadiumGrid := preload("res://scripts/minigames/maps/stadium/stadium_grid.gd")
const DockyardGrid := preload("res://scripts/minigames/maps/dockyard/dockyard_grid.gd")
const GlacierCourse := preload("res://scripts/minigames/maps/glacier/glacier_course.gd")


## A routed course as {"grid": PackedStringArray, "heights": PackedStringArray,
## "surfaces": Array}, or an empty dictionary for an id no module owns. One
## lookup feeds the grid accessor, the heights accessor, the grip spans and
## get_preset(), so the layout, its terrain and its surface sectors can never be
## read from two different modules. A module that authors no grip sectors omits
## the key and the preset's own `surfaces` stays in force.
static func _course_of(id: String) -> Dictionary:
	match id:
		"stadium":
			return {"grid": StadiumGrid.grid_rows(),
				"heights": StadiumGrid.height_rows()}
		"dockyard":
			return {"grid": DockyardGrid.grid_rows(),
				"heights": DockyardGrid.heights(),
				"surfaces": DockyardGrid.surfaces()}
		"glacier":
			return {"grid": GlacierCourse.grid(),
				"heights": GlacierCourse.heights(),
				"surfaces": GlacierCourse.surfaces()}
	return {}


static func heights_of(preset: Dictionary) -> PackedStringArray:
	## Per-cell road heights authored beside each course, one digit per cell at
	## HEIGHT_STEP metres. Empty means flat. Routed by the same map id as
	## grid_of, so a preset can never pair one map's layout with another's
	## terrain; a preset that carries its own `heights` still works for ids the
	## registry does not route.
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
	## Each map authors its course in its own module; the registry grid is only a
	## fallback for older saves and for the menu. Without this dispatch the race
	## silently builds the stale layout.
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


## The registry view of a map preset, with the routed course laid over it: the
## module's `grid`, `heights` and (when it authors them) `surfaces` replace the
## stale inline fallback, so every caller of get_preset() (the race, a theme that
## checks for a height table, a probe or a preview) builds the same elevated
## course with the same grip sectors. A minigame, or an id no module owns, is
## returned unchanged.
static func _with_course(preset: Dictionary) -> Dictionary:
	var course: Dictionary = _course_of(str(preset.get("id", "")))
	if course.is_empty():
		return preset
	var merged: Dictionary = preset.duplicate(true)
	for key: String in course:
		merged[key] = course[key]
	return merged


## The race map for `id`, or the first map when the id is unknown. Legacy ids
## (`meadow_loop`, `circuit`, `alpine`) map to their replacement so old saves
## keep working. Minigames and their theme ids are never returned here:
## grass_race must not try to build a grid from the cargo arena's theme.
static func get_preset(id: String) -> Dictionary:
	var key: String = _resolve(id)
	for preset: Dictionary in PRESETS:
		if is_map(preset) and str(preset.get("id", "")) == key:
			return _with_course(preset)
	for preset: Dictionary in PRESETS:
		if is_map(preset):
			return _with_course(preset)
	return _with_course(PRESETS[0])


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
