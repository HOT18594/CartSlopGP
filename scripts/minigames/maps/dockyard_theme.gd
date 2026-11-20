extends RefCounted
## Dockyard Quay: technical cartoon quay circuit through a container yard.
##
## The map is one of the Kenney grid circuits in track_defs.gd. KenneyTiles
## builds the road, its colliders and the 16 m grid spline; grass_race then calls
## this file with that spline, and the theme dresses the quay around it:
##
##   ground      flat concrete apron, expansion-joint grid, painted quay lines,
##               painted puddle field for the wet sector
##   yard        container blocks with service gaps, a sunken container lane,
##               pit garages/offices, a raised wharf deck, quay cranes, catch
##               fence, bollards, mooring clutter
##   circuit     full-lap barrier ring on both edges, hairpin stands, tyres,
##               light gantries, billboards, banner towers, flags, floodlights
##   green       palms and mixed treeline on the rings beyond the fence
##
## Every prop is placed through scripts/minigames/tile_kit.gd (or the thin
## DockyardParts adapter over its measured batching), so placements keep the
## engine's quarter-tile / half-metre grid snap and every solid piece has a
## WORLD collider. Only Kenney racing/nature kit art is used; no texture is
## referenced here at all, so the pass stays flat and cartoon.
##
## The build is idempotent. At the end it asserts the owner's invariant - every
## barrier piece clears the racing surface - and prints the measured counts.
##
## The authored route and per-cell wharf heights live in dockyard_grid.gd. The
## registry preset in track_defs.gd must carry the same grid and heights (merge
## DockyardGrid.preset_fields()); the theme warns when it has drifted.

const TileKit := preload("res://scripts/minigames/tile_kit.gd")
const TrackDefs := preload("res://scripts/minigames/track_defs.gd")
const DockyardGrid := preload("res://scripts/minigames/maps/dockyard/dockyard_grid.gd")
const DockyardPlan := preload("res://scripts/minigames/maps/dockyard/dockyard_plan.gd")
const DockyardGround := preload("res://scripts/minigames/maps/dockyard/dockyard_ground.gd")
const DockyardYard := preload("res://scripts/minigames/maps/dockyard/dockyard_yard.gd")
const DockyardCircuit := preload("res://scripts/minigames/maps/dockyard/dockyard_circuit.gd")
const DockyardGreen := preload("res://scripts/minigames/maps/dockyard/dockyard_green.gd")
const AmbientWorld := preload("res://scripts/minigames/scenery/ambient_world.gd")

const HOLDER_NAME: String = "DockyardTheme"


## Entry point the race controller calls. Idempotent: a second call on the same
## race finds the holder and does nothing, so a reload can never double the map.
static func build(race: Node3D, spline) -> void:
	if race == null or spline == null:
		return
	if race.has_node(HOLDER_NAME):
		return
	var meadow_ground: Node3D = race.get_node_or_null("MeadowGround") as Node3D
	if meadow_ground != null:
		meadow_ground.visible = false
	TileKit.dress_track(race, spline, {
		"id": "dockyard",
		"hoarding_density": 0.32,
	})
	var grid_stats: Dictionary = race.get_meta("kenney_grid_stats", {})
	var plan: RefCounted = DockyardPlan.new(spline,
		int(grid_stats.get("cols", 0)), int(grid_stats.get("rows", 0)))
	if plan == null:
		return
	var preset: Dictionary = TrackDefs.get_preset("dockyard")
	var drift: String = DockyardGrid.mismatch(TrackDefs.grid_of(preset))
	if drift != "":
		push_warning("DockyardTheme: the registry grid is not the authored quay layout (%s); merge DockyardGrid.preset_fields() into track_defs.gd." % drift)
	elif not preset.has("heights"):
		push_warning("DockyardTheme: the registry grid has no wharf heights; merge DockyardGrid.preset_fields() into track_defs.gd.")
	var holder := Node3D.new()
	holder.name = HOLDER_NAME
	race.add_child(holder)
	var totals: Dictionary = {
		"objects": 0, "draws": 0, "barriers": 0, "containers": 0,
		"signs": 0, "stands": 0, "gantries": 0, "flags": 0, "lights": 0,
		"tyres": 0, "trees": 0, "pit_bays": 0, "fence": 0, "paint": 0,
		"puddles": 0, "cranes": 0, "bollards": 0, "mooring": 0, "wharf": 0,
	}
	_merge(totals, DockyardGround.build(holder, spline, plan))
	# The yard builds the catch fence; clear the fence cells under the hairpin
	# stands first so the two one-off systems cannot clip into each other.
	DockyardCircuit.reserve_stand_ring(spline, plan)
	# The yard fills the working apron first; the circuit then takes the quay
	# edge and the rings beyond it. Both passes claim cells through the plan, so
	# no floodlight, sign or container can land on top of another.
	_merge(totals, DockyardYard.build(holder, spline, plan))
	_merge(totals, DockyardCircuit.build(holder, spline, plan))
	_merge(totals, DockyardGreen.build(holder, spline, plan))
	AmbientWorld.build_track(holder, spline, "dockyard")
	# The barrier ring is the owner-facing invariant. Assert it against every
	# collider the theme just emitted, not just against the path that built it.
	TileKit.assert_barrier_clearance(holder, spline, "dockyard quay")
	var measured_draws: int = _geometry_count(holder)
	var layout: String = "GRID" if plan.is_grid() else "SPLINE"
	print("DOCKYARD QUAY %s: %d objects, %d draws (%d batched), %.0f m lap, %d barriers, %d containers, %d cranes, %d bollards, %d/%d paint/puddles, %d signs, %d trees" % [
		layout, int(totals["objects"]), measured_draws,
		int(totals["draws"]), float(spline.total_length),
		int(totals["barriers"]), int(totals["containers"]),
		int(totals["cranes"]), int(totals["bollards"]),
		int(totals["paint"]), int(totals["puddles"]),
		int(totals["signs"]), int(totals["trees"])])
	race.set_meta("dockyard_stats", totals)
	race.set_meta("dockyard_draws", measured_draws)


static func _merge(totals: Dictionary, stats: Dictionary) -> void:
	for key: Variant in stats:
		var value: Variant = stats[key]
		if not (value is int) and not (value is float):
			continue
		totals[key] = int(totals.get(key, 0)) + int(value)


## One GeometryInstance3D is one draw unit in this kit. Counting the real nodes
## catches both MultiMesh batches and the one-off Kenney models, so the budget
## report is measured and not an estimate.
static func _geometry_count(node: Node) -> int:
	var count: int = 1 if node is GeometryInstance3D else 0
	for child: Node in node.get_children():
		count += _geometry_count(child)
	return count
