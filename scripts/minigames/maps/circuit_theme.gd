extends RefCounted
## Race-circuit theme for the default map.
##
## The circuit is a tile map now: the layout, road, kerbs, barriers, fencing,
## grandstands, pit complex, signage, floodlights, trees and haze are all built
## by the tile library under scripts/minigames/maps/tiles/. This file keeps the
## original map-theme hook working (grass_race still calls `build(race, spline)`)
## and forwards to the stadium theme, so nothing that loads this path breaks.
##
## The build is idempotent; a second call with the holder already present is a
## no-op, so a scene reload can never double the props.

const TileBuild := preload("res://scripts/minigames/maps/tiles/tile_build.gd")


## Builds the whole circuit theme under `race`. `spline` is the race scene's
## TrackSpline; the signature is the map-theme hook the race controller calls.
static func build(race: Node3D, spline) -> void:
	TileBuild.run(race, spline, "stadium")
