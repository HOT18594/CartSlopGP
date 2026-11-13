extends RefCounted
## Glacier alpine theme: snow banks, pines, cold asphalt and a big blue ice
## sheen over the slippery section. The fast alpine loop uses this palette.
##
## The tile builders own the geometry; this file only names the theme. The
## `build(race, spline)` hook is what grass_race calls for a map preset.

const TileBuild := preload("res://scripts/minigames/maps/tiles/tile_build.gd")


static func build(race: Node3D, spline) -> void:
	TileBuild.run(race, spline, "glacier")
