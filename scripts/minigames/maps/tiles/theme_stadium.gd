extends RefCounted
## Stadium circuit theme: dry asphalt, grass banks, red/white kerbs and the
## densest grandstand/trackside package of the three tile maps.
##
## The tile builders own the geometry; this file only names the theme. The
## `build(race, spline)` hook is what grass_race calls for a map preset.

const TileBuild := preload("res://scripts/minigames/maps/tiles/tile_build.gd")


static func build(race: Node3D, spline) -> void:
	TileBuild.run(race, spline, "stadium")
