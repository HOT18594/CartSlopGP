extends RefCounted
## Dockyard Quay: technical cartoon quay loop through a container yard.
##
## The map is one of the Kenney grid circuits in track_defs.gd. KenneyTiles
## builds the road, its colliders and the 16 m grid spline; grass_race then calls
## this file with that spline, and the theme dresses the quay around it:
##
##   ground      flat concrete apron, expansion-joint grid, wet sector ribbon
##   yard        container stacks, pit garages, offices, quay catch fence
##   circuit     barriers, hairpin grandstands, tyres, gantries, lights,
##               billboards, banner towers, pylons, flags
##   green       treeline and underbrush beyond the fence
##
## Every prop is placed through scripts/minigames/tile_kit.gd (or the thin
## DockyardParts adapter over its measured batching), so placements keep the
## engine's quarter-tile / half-metre grid snap and every solid piece has a
## WORLD collider. Only Kenney racing/nature kit art is used; no texture is
## referenced here at all, so the pass stays flat and cartoon.

const DockyardPlan := preload("res://scripts/minigames/maps/dockyard/dockyard_plan.gd")
const DockyardGround := preload("res://scripts/minigames/maps/dockyard/dockyard_ground.gd")
const DockyardYard := preload("res://scripts/minigames/maps/dockyard/dockyard_yard.gd")
const DockyardCircuit := preload("res://scripts/minigames/maps/dockyard/dockyard_circuit.gd")
const DockyardGreen := preload("res://scripts/minigames/maps/dockyard/dockyard_green.gd")

const HOLDER_NAME: String = "DockyardTheme"


## Entry point the race controller calls. Idempotent: a second call on the same
## race finds the holder and does nothing, so a reload can never double the map.
static func build(race: Node3D, spline) -> void:
	if race == null or spline == null:
		return
	if race.has_node(HOLDER_NAME):
		return
	var plan: RefCounted = DockyardPlan.new(spline)
	if plan == null:
		return
	var holder := Node3D.new()
	holder.name = HOLDER_NAME
	race.add_child(holder)
	var totals: Dictionary = {
		"objects": 0, "draws": 0, "barriers": 0, "containers": 0,
		"signs": 0, "stands": 0, "gantries": 0, "flags": 0, "lights": 0,
		"tyres": 0, "trees": 0, "pit_bays": 0, "fence": 0,
	}
	_merge(totals, DockyardGround.build(holder, spline, plan))
	# The yard builds the catch fence; clear the fence cells under the hairpin
	# stands first so the two one-off systems cannot clip into each other.
	DockyardCircuit.reserve_stand_ring(spline, plan)
	_merge(totals, DockyardYard.build(holder, spline, plan))
	_merge(totals, DockyardCircuit.build(holder, spline, plan))
	_merge(totals, DockyardGreen.build(holder, spline, plan))
	var objects: int = int(totals["objects"])
	var draws: int = int(totals["draws"])
	var layout: String = "GRID" if plan.is_grid() else "SPLINE"
	print("DOCKYARD QUAY %s: %d objects, ~%d draws, %.0f m lap, %d barriers, %d containers, %d signs, %d trees" % [
		layout, objects, draws, float(spline.total_length),
		int(totals["barriers"]), int(totals["containers"]),
		int(totals["signs"]), int(totals["trees"])])
	race.set_meta("dockyard_stats", totals)


static func _merge(totals: Dictionary, stats: Dictionary) -> void:
	for key: Variant in stats:
		var value: Variant = stats[key]
		if not (value is int) and not (value is float):
			continue
		totals[key] = int(totals.get(key, 0)) + int(value)
