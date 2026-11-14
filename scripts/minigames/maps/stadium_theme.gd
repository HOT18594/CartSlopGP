extends RefCounted
## STADIUM CIRCUIT: a compact cartoon arena inside a bowl of grandstands.
##
## Entry point, called by grass_race once per race:
##
##   static func build(race: Node3D, spline) -> void
##
## KenneyTiles owns the road, the road colliders, the per-cell elevation and the
## closed centreline. This theme only dresses the bowl, and every piece goes
## through scripts/minigames/maps/stadium/stadium_props.gd, which batches
## repeated models into MultiMeshes and gives every solid prop a collider on
## CollisionLayers.WORLD.
##
## Outside in, the bowl is a two-tier ring of grandstands with the covered main
## stand over the start/finish, catch fencing on the longest straight, a tyre
## wall and a marshal post at every corner, camera cranes and twelve
## floodlights, a pit lane with eight garage doors and a pit wall, a paddock of
## tents behind it, the start gantry over the line, cliff walls and a stone
## footbridge over the valley, and a tree band beyond the barrier ring only.
##
## No photo texture is referenced: the art is the flat Kenney racing and nature
## kits only. The build is idempotent, so a scene reload cannot double the bowl.
##
## The layout itself lives in stadium_grid.gd and the same strings sit in the
## registry preset; when the two drift, stadium_layout.gd prints the mismatching
## row instead of silently dressing a different circuit.

const TrackDefs := preload("res://scripts/minigames/track_defs.gd")
const StadiumLayout := preload("res://scripts/minigames/maps/stadium/stadium_layout.gd")
const StadiumGrid := preload("res://scripts/minigames/maps/stadium/stadium_grid.gd")

const THEME_ID: String = "stadium"
const HOLDER_NAME: String = "StadiumDressing"
const META_STATS: String = "stadium_dressing_stats"


## Builds the whole stadium dressing under `race`. `spline` is the grid spline
## KenneyTiles.build returned; the layout scales every feature off it, so the
## theme follows a registry grid edit without code changes.
static func build(race: Node3D, spline) -> void:
	if race == null:
		push_warning("StadiumTheme: build() needs the race root.")
		return
	if spline == null:
		push_warning("StadiumTheme: build() needs the race spline; nothing was dressed.")
		return
	if race.has_node(HOLDER_NAME):
		return
	var track: RefCounted = spline as RefCounted
	if track == null:
		push_warning("StadiumTheme: the spline is not a RefCounted; nothing was dressed.")
		return
	var preset: Dictionary = TrackDefs.get_preset(THEME_ID)
	var rows: PackedStringArray = TrackDefs.grid_of(preset)
	if rows.is_empty():
		rows = StadiumGrid.grid_rows()
	var holder := Node3D.new()
	holder.name = HOLDER_NAME
	race.add_child(holder)
	var stats: Dictionary = StadiumLayout.build(holder, track, rows)
	print("STADIUM CIRCUIT: %d objects, ~%d draw nodes, %d barrier pieces, %d stands, %d garages, %d tents, %d trees, %d lights, %d signs, %d flags, %d tyres, %d fences, %d marshals, %d cameras, %.0f m lap, %.1f m elevation" % [
		int(stats.get("objects", 0)), int(stats.get("draws", 0)),
		int(stats.get("barriers", 0)), int(stats.get("stands", 0)),
		int(stats.get("pit", 0)), int(stats.get("paddock", 0)),
		int(stats.get("trees", 0)), int(stats.get("lights", 0)),
		int(stats.get("signage", 0)), int(stats.get("flags", 0)),
		int(stats.get("tyres", 0)), int(stats.get("fences", 0)),
		int(stats.get("marshals", 0)), int(stats.get("cameras", 0)),
		float(stats.get("lap", 0.0)),
		float(stats.get("elevation", 0.0))])
	race.set_meta(META_STATS, stats)
