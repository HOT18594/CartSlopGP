extends RefCounted
## Dockyard quay theme: worn concrete apron, wet asphalt, container yards and
## warehouses. The technical quay loop uses this palette.
##
## The tile builders own the geometry; this file only names the theme. The
## `build(race, spline)` hook is what grass_race calls for a map preset.

const TileBuild := preload("res://scripts/minigames/maps/tiles/tile_build.gd")


static func build(race: Node3D, spline) -> void:
	TileBuild.run(race, spline, "dockyard")
