extends RefCounted
## Green edge for the Dockyard Quay theme.
##
## The dock's greenery is designed, not scattered. dockyard_forest.gd owns the
## work: a continuous belt of trees outside the catch fence, packed by value
## noise so it reads as stands with real clearings, a framed vista down the
## longest straight, open fronts at the four grandstands, a thicket behind the
## tightest corner, a few windswept trees between container rows inside the
## site, and four layers of undergrowth (fence brambles, a front scrub row,
## trunk clumps and yard-pocket skirts).
##
## This file stays the theme's entry point so dockyard_theme.gd keeps one call
## per pass, and so the legacy spline fallback the plan still supports is served
## by the same measured belt instead of a second code path.
##
## Every instance is batched through TileKit via DockyardParts; the belt costs
## one MultiMesh per species per side, and no tree is ever a scene node. Nothing
## is placed inside the barrier line: the forest module enforces a centreline
## clearance on every candidate before a trunk or a collider exists.

const DockyardForest := preload("res://scripts/minigames/maps/dockyard/dockyard_forest.gd")


## Builds the treeline, the scrub and the in-site trees, returning
## {objects, draws, trees, undergrowth, trunks, surfaces, clearings}.
static func build(parent: Node3D, spline: RefCounted,
		plan: RefCounted) -> Dictionary:
	return DockyardForest.build(parent, spline, plan)
