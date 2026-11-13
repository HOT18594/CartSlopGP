extends RefCounted
## Entry point for a tile map's theme.
##
## grass_race loads the preset's `theme` script, which calls this with its theme
## id. The build is idempotent (a second call finds the holder and returns), so
## a scene reload can never double the props.
##
## The pass order matters: road first (it owns the driving surface and the
## kerbs), then furniture (stands and posts avoid each other through the
## layout's clearance tests), then the horizon, which also tunes the depth fog.
## The printout is the density measurement the rebuild brief asks for: tile
## count, object count, lap length, surface spans and an estimated draw count.

const TileRoad := preload("res://scripts/minigames/maps/tiles/tile_road.gd")
const TileFurniture := preload("res://scripts/minigames/maps/tiles/tile_furniture.gd")
const TileHaze := preload("res://scripts/minigames/maps/tiles/tile_haze.gd")
const TileTheme := preload("res://scripts/minigames/maps/tiles/tile_theme.gd")

const HOLDER_NAME: String = "TileMapTheme"


## Builds the whole tile map theme under `race`. `spline` is the race scene's
## TrackSpline, which carries the derived TileLayout for a tile preset.
static func run(race: Node3D, spline: RefCounted, theme_id: String) -> void:
	if race == null or spline == null:
		return
	if race.has_node(HOLDER_NAME):
		return
	var layout: RefCounted = spline.get("layout") as RefCounted
	if layout == null:
		push_warning("TileBuild: no tile layout on the spline for theme " + theme_id)
		return
	var palette: Dictionary = TileTheme.resolve(theme_id)
	var map_name: String = "CART SLOP GP"
	if race.has_method("race_title"):
		map_name = str(race.call("race_title"))
	palette["map_name"] = map_name
	var holder := Node3D.new()
	holder.name = HOLDER_NAME
	race.add_child(holder)
	var road: Dictionary = TileRoad.build(holder, spline, layout, palette)
	var furniture: Dictionary = TileFurniture.build(holder, spline, layout, palette)
	var bands: int = TileHaze.build(race, palette)
	var objects: int = int(road.get("pieces", 0)) \
		+ int(road.get("tyre_stacks", 0)) + int(furniture.get("objects", 0))
	var draws: int = int(road.get("draws", 0)) + int(furniture.get("draws", 0)) \
		+ bands + 2
	var spans := PackedStringArray()
	for span: Dictionary in layout.surfaces:
		spans.append("%s %.0f-%.0f%%" % [str(span["kind"]),
			float(span["from"]) * 100.0, float(span["to"]) * 100.0])
	if spans.is_empty():
		spans.append("normal 0-100%")
	print("TILE MAP %s: %d tiles, %d objects, %.1f m lap, ~%d draws, %d stands" % [
		map_name, layout.tiles.size(), objects, spline.total_length, draws,
		int(furniture.get("grandstands", 0))])
	print("TILE MAP %s: surfaces %s | kerbs %d, armco %d, fence %d, tyres %d, lights %d, trees %d" % [
		map_name, ", ".join(spans), int(road.get("kerb_runs", 0)),
		int(road.get("barrier_runs", 0)), int(road.get("fence_runs", 0)),
		int(road.get("tyre_walls", 0)), int(furniture.get("floodlights", 0)),
		int(furniture.get("trees", 0))])
	race.set_meta("tile_map_stats", {
		"tiles": layout.tiles.size(),
		"objects": objects,
		"draws": draws,
		"length": spline.total_length,
		"surfaces": layout.surfaces,
	})
