extends RefCounted
## STADIUM CIRCUIT: a compact cartoon arena inside a bowl of grandstands.
##
## Entry point, called by grass_race once per race:
##
##   static func build(race: Node3D, spline) -> void
##
## KenneyTiles owns the road, the road colliders and the closed centreline. This
## theme only dresses the bowl, and every piece goes through
## scripts/minigames/tile_kit.gd: repeated stands, barriers, trees and lights
## batch into a handful of MultiMeshes and every solid prop carries a collider
## on CollisionLayers.WORLD.
##
## Outside in, the bowl is a two-cell Kenney tree band with eight floodlights, a
## continuous red/white barrier line on both edges of the lap, a grandstand run
## down each long straight with a covered stand on every corner, billboards and
## pylons on the two open sides, a flag line and banner towers along the pit
## straight, six pit garages on its infield side, a start gantry over the line
## and tyre stacks at the two fastest corners.
##
## No photo texture is referenced: the art is the flat Kenney racing and nature
## kits only. The build is idempotent, so a scene reload cannot double the bowl.

const TrackDefs := preload("res://scripts/minigames/track_defs.gd")
const StadiumLayout := preload("res://scripts/minigames/maps/stadium/stadium_layout.gd")

const THEME_ID: String = "stadium"
const HOLDER_NAME: String = "StadiumDressing"
const META_STATS: String = "stadium_dressing_stats"


## Builds the whole stadium dressing under `race`. `spline` is the grid spline
## KenneyTiles.build returned, or the legacy TrackSpline while the race scene is
## still being wired; the layout scales the grid lap onto either.
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
		push_warning("StadiumTheme: no ASCII grid for the '%s' map." % THEME_ID)
		return
	var holder := Node3D.new()
	holder.name = HOLDER_NAME
	race.add_child(holder)
	var stats: Dictionary = StadiumLayout.build(holder, track, rows)
	print("STADIUM CIRCUIT: %d objects, ~%d draw nodes, %d barrier pieces, %d stands, %d garages, %d trees, %d lights, %d signs, %d flags, %d tyres, %.0f m lap" % [
		int(stats.get("objects", 0)), int(stats.get("draws", 0)),
		int(stats.get("barriers", 0)), int(stats.get("stands", 0)),
		int(stats.get("pit", 0)), int(stats.get("trees", 0)),
		int(stats.get("lights", 0)), int(stats.get("signage", 0)),
		int(stats.get("flags", 0)), int(stats.get("tyres", 0)),
		float(stats.get("lap", 0.0))])
	race.set_meta(META_STATS, stats)
