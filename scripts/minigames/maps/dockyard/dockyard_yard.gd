extends RefCounted
## Industrial backdrop for the Dockyard Quay theme.
##
## The container yard, pit complex, quay fence and working cranes are what make
## the map read as a working dock instead of a bare circuit. Everything is a
## Kenney racing/nature kit piece: `barrierWall` blocks stacked two to four high
## for containers, `pitsGarage` / `pitsOfficeRoof` for the pit complex,
## `fenceStraight` for the catch fence, `bannerTowerRed` + `railDouble` +
## `lightRed` composed into quay cranes, `pylon` for bollards, and the nature
## kit's `canoe`, `log` and `pot_small` for mooring clutter.
##
## Placements are derived from the grid the engine actually built: the longest
## straight gets the pit row, the free lattice rows get container blocks with
## service gaps, the second-longest straight gets the sunken container lane, and
## the outer band gets the raised wharf, cranes and mooring props. Nothing is
## pinned to a hard-coded column/row, so a layout edit moves the yard with it.
##
## The packing reserves eight free infield cells as overgrown pockets and
## publishes them on the plan metadata, so the green pass can grow a windswept
## tree between container rows without a stack already standing there.
##
## Every solid piece sits behind the barrier line (Parts.SAFE_CLEARANCE) and
## carries a real WORLD collider. Repeated models are batched into MultiMeshes,
## so all of this detail costs only a handful of draw calls.

const TileKit := preload("res://scripts/minigames/tile_kit.gd")
const Parts := preload("res://scripts/minigames/maps/dockyard/dockyard_parts.gd")

const PAD_MODEL: String = "roadPitGarage"
const GARAGE_MODEL: String = "pitsGarage"
const KIOSK_MODEL: String = "pitsOffice"
const OFFICE_MODEL: String = "pitsOfficeRoof"
const CONTAINER_MODEL: String = "barrierWall"
const FENCE_MODEL: String = "fenceStraight"
const CRANE_MAST: String = "bannerTowerRed"
const CRANE_BOOM: String = "railDouble"
const CRANE_CAB: String = "lightRed"
const BOLLARD_MODEL: String = "pylon"
const DOCK_RAMP: String = "ramp"

const PAD_SCALE: Vector3 = Vector3(TileKit.TILE_SIZE, TileKit.TILE_SIZE * 0.12,
	TileKit.TILE_SIZE)
const PROP_SCALE: Vector3 = Parts.PROP_SCALE
## Container rows: two levels standard, three on the accented stacks.
const CONTAINER_LEVELS: int = 2
const CONTAINER_TALL: int = 3
const CONTAINER_CANYON: int = 4
const CONTAINER_COLLIDER_DEPTH: float = 1.97
## Minimum centre distance before the real box footprint is measured. A row of
## containers parallel to the road is only one metre deep towards it, so the
## exact box test below is the authority; this only skips the obvious cases.
const LATTICE_CLEARANCE: float = 13.0
## Off-lattice canyon walls: 11.5 m lateral puts the inner face at 10.5 m,
## outside the 9.0 m barrier face but close enough to read as a container lane.
const CANYON_LATERAL: float = 11.5
## Wharf deck height and the number of cells the raised quay occupies.
const WHARF_HEIGHT: float = 2.2
const WHARF_CELLS: int = 5
## One bollard every two cells, up to this many.
const BOLLARD_LIMIT: int = 44
## Service gap rhythm in the container rows: every fourth cell is left open.
const STACK_GAP: int = 4
const LATTICE_STACK_LIMIT: int = 46
## Overgrown yard pockets: free infield cells the container packing leaves alone
## so the forest pass can plant a windswept tree and scrub in them. Eight cells
## out of a packed yard read as accidental, which is exactly the dock look.
const TREE_ISLANDS: int = 8
const TREE_ISLAND_CLEARANCE: float = 15.0
const TREE_ISLAND_SPACING: float = 24.0
const TREE_ISLAND_META: String = "dockyard_tree_islands"
## Crane bases are published for the green pass: a boom reaches 11 m, so the
## treeline keeps a wider seat round these three cells than the other posts.
const CRANE_META: String = "dockyard_crane_bases"
## Cells that carry an actual catch-fence panel. A ring cell can also hold a
## container or a bollard, so the green pass only grows fence-foot brambles on
## the cells this list names.
const FENCE_META: String = "dockyard_fence_cells"


## Builds the yard, pit complex, wharf and fence, returning statistics.
static func build(parent: Node3D, spline: RefCounted,
		plan: RefCounted) -> Dictionary:
	var stats: Dictionary = {
		"objects": 0, "draws": 0, "containers": 0, "pit_bays": 0,
		"fence": 0, "cranes": 0, "bollards": 0, "mooring": 0, "wharf": 0,
		"loading": 0, "tree_islands": 0,
	}
	if parent == null or spline == null or plan == null:
		return stats
	if plan.is_grid():
		_grid_yard(parent, spline, plan, stats)
	else:
		_arc_yard(parent, spline, plan, stats)
		_arc_fence(parent, spline, plan, stats)
	return stats


# --------------------------------------------------------------------------
# grid yard


static func _grid_yard(parent: Node3D, spline: RefCounted, plan: RefCounted,
		stats: Dictionary) -> void:
	var containers: Array = []
	var container_boxes: Array[Dictionary] = []
	_pit_complex(parent, spline, plan, stats)
	_wharf(parent, spline, plan, containers, container_boxes, stats)
	_loading_docks(parent, spline, plan, containers, container_boxes, stats)
	# Reserve the overgrown pockets before the stacks are packed: a claimed cell
	# is skipped by every later pass, so these stay empty concrete for the trees.
	_tree_islands(plan, spline, stats)
	_grid_containers(parent, spline, plan, containers, container_boxes, stats)
	_canyon_containers(spline, plan, containers, container_boxes, stats)
	_emit_containers(parent, containers, container_boxes, stats)
	_cranes(parent, spline, plan, stats)
	_bollards(parent, spline, plan, stats)
	_mooring(parent, plan, stats)
	_grid_fence(parent, plan, stats)


## Claims a handful of free infield cells as overgrown pockets and publishes them
## on the plan metadata. The container packing skips a claimed cell and the
## circuit keeps its lights and flags off used cells, so an island stays empty
## concrete; dockyard_forest.gd reads the list back and plants one windswept tree
## and its scrub in each. Spacing and centreline clearance keep the pockets away
## from the barriers and from each other, so they read as separate accidents of
## the yard rather than a planted avenue.
static func _tree_islands(plan: RefCounted, spline: RefCounted,
		stats: Dictionary) -> void:
	var islands: Array[Vector2i] = []
	for cell: Vector2i in plan.free_cells():
		if islands.size() >= TREE_ISLANDS:
			break
		if plan.is_ring_cell(cell) or plan.is_outer_band(cell):
			continue
		var point: Vector3 = plan.cell_point(cell)
		if TileKit.spline_distance(spline, point) < TREE_ISLAND_CLEARANCE:
			continue
		var spaced: bool = true
		for other: Vector2i in islands:
			if plan.cell_point(other).distance_to(point) < TREE_ISLAND_SPACING:
				spaced = false
				break
		if not spaced:
			continue
		if plan.take(cell):
			islands.append(cell)
	plan.set_meta(TREE_ISLAND_META, islands)
	stats["tree_islands"] = islands.size()


## The pit complex on the inside of the longest straight: flat pads on the
## verge row, a garage row one cell further in, two offices on the outer band,
## two kiosks at the apron ends and a long warehouse behind the garages.
static func _pit_complex(parent: Node3D, spline: RefCounted, plan: RefCounted,
		stats: Dictionary) -> void:
	var runs: Array = plan.straight_runs()
	if runs.is_empty():
		return
	var best: Dictionary = runs[0]
	for run: Dictionary in runs:
		if float(run["length"]) > float(best["length"]):
			best = run
	var cells: Array = best.get("cells", []) as Array
	if cells.size() < 2:
		return
	var horizontal: bool = (cells[0] as Vector2i).y \
		== (cells[cells.size() - 1] as Vector2i).y
	var middle: Vector2i = cells[cells.size() / 2]
	var target: Vector3 = plan.cell_point(middle)
	var centre: Vector3 = plan.centre()
	var inward: int = 0
	if horizontal:
		inward = -1 if centre.z < target.z else 1
	else:
		inward = -1 if centre.x < target.x else 1
	var span: int = mini(cells.size(), 7)
	var first: int = maxi(0, (cells.size() - span) / 2)
	var pad_points: Array = []
	var garage_cells: Array = []
	var pad_cells: Array = []
	for index in range(first, first + span):
		var cell: Vector2i = cells[index]
		var step := Vector2i(0, inward) if horizontal else Vector2i(inward, 0)
		var pad_cell: Vector2i = cell + step
		var garage_cell: Vector2i = cell + step * 2
		if plan.take(pad_cell):
			pad_cells.append(pad_cell)
			pad_points.append(Parts.snap(plan.cell_point(pad_cell)))
		if plan.take(garage_cell):
			garage_cells.append(garage_cell)
	if not pad_points.is_empty():
		var transforms: Array = []
		for point: Vector3 in pad_points:
			transforms.append(Parts.fit(PAD_MODEL, point, 0.0, PAD_SCALE))
		stats["draws"] = int(stats["draws"]) \
			+ Parts.batch(parent, PAD_MODEL, transforms, "PitApron", false)
		stats["objects"] = int(stats["objects"]) + transforms.size()
	if not garage_cells.is_empty():
		var placed: int = TileKit.pit_building(parent, garage_cells)
		stats["objects"] = int(stats["objects"]) + placed
		stats["pit_bays"] = int(stats["pit_bays"]) + placed
		stats["draws"] = int(stats["draws"]) + Parts.part_count(GARAGE_MODEL)
	_offices(parent, plan, pad_cells, garage_cells, horizontal, inward, stats)


## Two roofed offices on the outer band near the pit, plus a kiosk at each end
## of the apron. Every block is solid: one WORLD box per building.
static func _offices(parent: Node3D, plan: RefCounted, pad_cells: Array,
		garage_cells: Array, horizontal: bool, inward: int,
		stats: Dictionary) -> void:
	var offices: Array = []
	var office_points: Array[Vector3] = []
	var candidates: Array[Vector2i] = plan.outer_band_cells()
	var edge: int = 0 if inward > 0 else plan.rows - 1
	if not horizontal:
		edge = 0 if inward > 0 else plan.cols - 1
	for cell: Vector2i in candidates:
		if offices.size() >= 2:
			break
		var on_edge: bool = cell.y == edge if horizontal else cell.x == edge
		if not on_edge:
			continue
		if not plan.take(cell):
			continue
		var point: Vector3 = plan.cell_point(cell)
		offices.append(Parts.fit(OFFICE_MODEL, point, 0.0, PROP_SCALE))
		office_points.append(point)
	var kiosks: Array = []
	var kiosk_points: Array[Vector3] = []
	for index: int in [0, pad_cells.size() - 1]:
		if index < 0 or index >= pad_cells.size():
			continue
		var anchor: Vector2i = pad_cells[index]
		var probe: Vector2i = Vector2i(-999, -999)
		var best: int = 999999
		for cell: Vector2i in plan.free_cells():
			var distance: int = absi(cell.x - anchor.x) + absi(cell.y - anchor.y)
			if distance > 4 or distance >= best:
				continue
			best = distance
			probe = cell
		if probe.x < 0 or not plan.take(probe):
			continue
		var point: Vector3 = plan.cell_point(probe)
		kiosks.append(Parts.fit(KIOSK_MODEL, point, 0.0, PROP_SCALE))
		kiosk_points.append(point)
	_building_batch(parent, OFFICE_MODEL, offices, office_points, 0.0,
		"PitOffices", stats)
	_building_batch(parent, KIOSK_MODEL, kiosks, kiosk_points, 0.0,
		"PitKiosks", stats)


## Batches a small office block and adds one box collider per building.
static func _building_batch(parent: Node3D, model: String, transforms: Array,
		points: Array, yaw: float, node_name: String,
		stats: Dictionary) -> void:
	if transforms.is_empty():
		return
	var body := Parts.body(parent, node_name + "Body")
	stats["draws"] = int(stats["draws"]) \
		+ Parts.batch(body, model, transforms, node_name, true)
	var size: Vector3 = Parts.size(model, PROP_SCALE)
	for point: Vector3 in points:
		Parts.box(body, point + Vector3.UP * (size.y * 0.5), yaw, size)
	stats["objects"] = int(stats["objects"]) + transforms.size()


## A raised quay deck along the outer band: pads at the wharf deck height, cargo
## rows standing on the deck surface, and one loading ramp at the end. The deck
## is solid on WORLD with a box per pad, so the whole thing can be climbed from
## the apron. Cargo is based on the pad's visible top, not on the deck height:
## a block planted at the deck height is buried in the 4 cm slab and its flanks
## fight the slab's.
static func _wharf(parent: Node3D, _spline: RefCounted, plan: RefCounted,
		containers: Array, container_boxes: Array[Dictionary],
		stats: Dictionary) -> void:
	var row: int = plan.rows - 1
	var candidates: Array[Vector2i] = []
	for cell: Vector2i in plan.free_cells():
		if cell.y != row:
			continue
		candidates.append(cell)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x)
	if candidates.size() < WHARF_CELLS:
		return
	var start: int = maxi(0, (candidates.size() - WHARF_CELLS) / 2)
	var cells: Array[Vector2i] = []
	for index in range(start, start + WHARF_CELLS):
		var cell: Vector2i = candidates[index]
		if plan.take(cell):
			cells.append(cell)
	if cells.is_empty():
		return
	var pads: Array = []
	var body := Parts.body(parent, "DockyardWharf")
	var piece_size: Vector3 = Parts.size(CONTAINER_MODEL, PROP_SCALE)
	var pad_height: float = Parts.size(PAD_MODEL, PAD_SCALE).y
	# The deck rises with the authored wharf terrain: on a flat grid it stays at
	# 2.2 m, on the raised quay layout it clears the 3 m upper lobe.
	var deck_height: float = maxf(WHARF_HEIGHT, plan.max_road_height() + 0.8)
	# The pad is only a few centimetres thick, so a container based at the deck
	# height would be buried in it and its side faces would fight the pad's.
	# Cargo stands on the pad's visible top, one rung up the layering ladder.
	var deck_top: float = deck_height + pad_height + Parts.LAYER_FOOT
	for cell: Vector2i in cells:
		var point: Vector3 = plan.cell_point(cell)
		pads.append(Parts.fit(PAD_MODEL, point + Vector3.UP * deck_height,
			0.0, PAD_SCALE))
		Parts.box(body, point + Vector3.UP * (deck_height * 0.5), 0.0,
			Vector3(TileKit.TILE_SIZE, deck_height, TileKit.TILE_SIZE))
		stats["wharf"] = int(stats["wharf"]) + 1
	stats["draws"] = int(stats["draws"]) \
		+ Parts.batch(body, PAD_MODEL, pads, "WharfDeck", false)
	stats["objects"] = int(stats["objects"]) + pads.size()
	# Cargo on top: two levels on three of the five pads, standing on the deck
	# surface. The old retaining row was planted half a block under the deck, so
	# its top was flush with the deck and its flanks fought the deck's sides.
	for index in [0, 2, 4]:
		if index >= cells.size():
			continue
		var point: Vector3 = plan.cell_point(cells[index]) \
			+ Vector3.UP * deck_top
		for level in 2:
			containers.append(Parts.fit(CONTAINER_MODEL,
				point + Vector3.UP * (piece_size.y * float(level)),
				0.0, PROP_SCALE))
			container_boxes.append({
				"point": point
					+ Vector3.UP * (piece_size.y * (float(level) + 0.5)),
				"yaw": 0.0,
				"size": Vector3(TileKit.TILE_SIZE, piece_size.y,
					piece_size.z),
			})
			stats["containers"] = int(stats["containers"]) + 1
	# A loading ramp at the seaward end gives the deck a way up and reads as a
	# freight apron from the chase camera. It stands clear of the deck columns:
	# a ramp placed on the cell edge itself cuts through the wharf's side.
	var ramp_scale: Vector3 = PROP_SCALE * 0.35
	var ramp_size: Vector3 = Parts.size(DOCK_RAMP, ramp_scale)
	var end_cell: Vector3 = plan.cell_point(cells[cells.size() - 1])
	var end: Vector3 = end_cell + Vector3(TileKit.TILE_SIZE * 0.5
		+ ramp_size.z * 0.5 + Parts.LAYER_APRON, 0.0, 0.0)
	var ramp_body := Parts.body(parent, "DockyardLoadingRamp")
	stats["draws"] = int(stats["draws"]) \
		+ Parts.batch(ramp_body, DOCK_RAMP, [Parts.fit(DOCK_RAMP, end, PI * 0.5,
			ramp_scale)], "LoadingRamp", true)
	Parts.box(ramp_body, end + Vector3.UP * (ramp_size.y * 0.5), PI * 0.5,
		ramp_size)
	stats["objects"] = int(stats["objects"]) + 1


## A loading dock beside every jump-ramp cell: a raised concrete platform, two
## container stacks and a kit loading ramp. The platform is 24 x 8 m at 15.5 m
## lateral, so its road-facing edge sits at 11.5 m, safely behind the barrier
## and the nine-metre no-prop line. It claims the lattice cells under it so no
## container row can grow through the deck.
static func _loading_docks(parent: Node3D, spline: RefCounted, plan: RefCounted,
		containers: Array, container_boxes: Array[Dictionary],
		stats: Dictionary) -> void:
	var cells: Array[Vector2i] = plan.tile_cells("J")
	if cells.is_empty():
		return
	# Cargo on the platform is drawn at 55 % so two stacks fit inside the 24 m
	# deck. At full size a 16 m container at +-6 m overlapped its neighbour by
	# four metres and hung off both ends of the platform.
	var piece_scale: Vector3 = PROP_SCALE * 0.55
	var piece_size: Vector3 = Parts.size(CONTAINER_MODEL, piece_scale)
	var deck: float = 1.3
	var deck_top: float = deck + Parts.LAYER_FOOT
	var decks: Array = []
	var ramps: Array = []
	var body := Parts.body(parent, "DockyardLoadingDock")
	for cell: Vector2i in cells:
		var distance: float = plan.tile_distance(cell)
		if distance < 0.0:
			continue
		var frame: Dictionary = spline.sample(distance)
		var forward: Vector3 = frame["forward"]
		# The platform slab is a local-X box: its long side must run along the
		# track, so use the across-track yaw. The ramp model is local-Z and uses
		# the along-track yaw.
		var platform_yaw: float = atan2(-forward.z, forward.x)
		var ramp_yaw: float = Parts.along_yaw(spline, distance)
		var chosen := Vector3.ZERO
		var found: bool = false
		for side: float in [-1.0, 1.0]:
			var point: Vector3 = frame["position"] \
				+ frame["right"] * (15.5 * side)
			if not _box_clears(spline, point, platform_yaw,
					Vector3(24.0, deck, 8.0)):
				continue
			if not _dock_cells_free(plan, point, platform_yaw):
				continue
			chosen = point
			found = true
			break
		if not found:
			continue
		decks.append(Transform3D(
			Basis(Vector3.UP, platform_yaw).scaled(Vector3(24.0, deck, 8.0)),
			chosen + Vector3.UP * (deck * 0.5)))
		Parts.box(body, chosen + Vector3.UP * (deck * 0.5), platform_yaw,
			Vector3(24.0, deck, 8.0))
		_mark_dock_cells(plan, chosen, platform_yaw)
		for along: float in [-6.5, 6.5]:
			var stack: Vector3 = chosen + forward * along \
				+ Vector3.UP * deck_top
			for level in 2:
				containers.append(Parts.fit(CONTAINER_MODEL,
					stack + Vector3.UP * (piece_size.y * float(level)),
					platform_yaw, piece_scale))
				container_boxes.append({
					"point": stack + Vector3.UP * (piece_size.y
						* (float(level) + 0.5)),
					"yaw": platform_yaw,
					"size": piece_size,
				})
				stats["containers"] = int(stats["containers"]) + 1
		var ramp_size: Vector3 = Parts.size(DOCK_RAMP, PROP_SCALE * 0.35)
		var ramp_point: Vector3 = chosen + forward \
			* (12.0 + ramp_size.z * 0.5 + Parts.LAYER_APRON)
		ramps.append(Parts.fit(DOCK_RAMP, ramp_point, ramp_yaw,
			PROP_SCALE * 0.35))
		Parts.box(body, ramp_point + Vector3.UP * (ramp_size.y * 0.5),
			ramp_yaw, ramp_size)
		stats["loading"] = int(stats["loading"]) + 1
	if decks.is_empty():
		body.free()
		return
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = box
	multi.instance_count = decks.size()
	for index in decks.size():
		multi.set_instance_transform(index, decks[index])
	var slabs := MultiMeshInstance3D.new()
	slabs.name = "LoadingDockDecks"
	slabs.multimesh = multi
	# One shared concrete material for every slab batch in the map.
	slabs.material_override = Parts.slab_material()
	parent.add_child(slabs)
	stats["draws"] = int(stats["draws"]) \
		+ Parts.batch(body, DOCK_RAMP, ramps, "LoadingRamps", true) + 1
	# One deck slab and one ramp are new objects; the container pieces on top
	# are counted once by _emit_containers.
	stats["objects"] = int(stats["objects"]) + decks.size() * 2


## True when the lattice cells under a loading dock are still unclaimed, so the
## platform never clips through a pit building or a container row.
static func _dock_cells_free(plan: RefCounted, point: Vector3,
		yaw: float) -> bool:
	var extent: Vector3 = Basis(Vector3.UP, yaw) \
		* Vector3(TileKit.TILE_SIZE, 0.0, TileKit.TILE_SIZE * 0.5)
	for cell_x: int in range(int(floor((point.x - absf(extent.x)) / 16.0)),
			int(floor((point.x + absf(extent.x)) / 16.0)) + 1):
		for cell_y: int in range(int(floor((point.z - absf(extent.z)) / 16.0)),
				int(floor((point.z + absf(extent.z)) / 16.0)) + 1):
			var cell := Vector2i(cell_x, cell_y)
			if plan.in_grid(cell) and not plan.is_track(cell) \
					and plan.is_used(cell):
				return false
	return true


## Claims the cells under a loading dock so the container packing skips them.
static func _mark_dock_cells(plan: RefCounted, point: Vector3,
		yaw: float) -> void:
	var extent: Vector3 = Basis(Vector3.UP, yaw) \
		* Vector3(TileKit.TILE_SIZE, 0.0, TileKit.TILE_SIZE * 0.5)
	for cell_x: int in range(int(floor((point.x - absf(extent.x)) / 16.0)),
			int(floor((point.x + absf(extent.x)) / 16.0)) + 1):
		for cell_y: int in range(int(floor((point.z - absf(extent.z)) / 16.0)),
				int(floor((point.z + absf(extent.z)) / 16.0)) + 1):
			var cell := Vector2i(cell_x, cell_y)
			if plan.in_grid(cell) and not plan.is_track(cell):
				plan.mark(cell)


## Container blocks on the free lattice rows and columns. Rows are packed with a
## service gap every fourth cell and columns fill the leftovers, so the yard
## reads as organised stacks with drive aisles instead of a solid wall.
static func _grid_containers(_parent: Node3D, spline: RefCounted,
		plan: RefCounted, containers: Array,
		container_boxes: Array[Dictionary], stats: Dictionary) -> void:
	var state: Dictionary = {"stacks": 0}
	var rows: Dictionary = {}
	for cell: Vector2i in plan.free_cells():
		if not rows.has(cell.y):
			rows[cell.y] = []
		(rows[cell.y] as Array).append(cell)
	var row_keys: Array = rows.keys()
	row_keys.sort()
	for key: int in row_keys:
		_pack_containers(plan, spline, rows[key] as Array, true, containers,
			container_boxes, state, stats)
	var columns: Dictionary = {}
	for cell: Vector2i in plan.free_cells():
		if not columns.has(cell.x):
			columns[cell.x] = []
		(columns[cell.x] as Array).append(cell)
	var column_keys: Array = columns.keys()
	column_keys.sort()
	for key: int in column_keys:
		_pack_containers(plan, spline, columns[key] as Array, false, containers,
			container_boxes, state, stats)


## Packs one sorted row or column of free cells. A stack only lands when its
## centre clears LATTICE_CLEARANCE and the cell is still free, so no block can
## reach the barrier line or another prop's cell.
static func _pack_containers(plan: RefCounted, spline: RefCounted,
		cells: Array, horizontal: bool, containers: Array,
		container_boxes: Array[Dictionary], state: Dictionary,
		stats: Dictionary) -> void:
	var run: Array[Vector2i] = []
	var previous: Vector2i = Vector2i(-999, -999)
	var runs: Array = []
	for cell: Vector2i in cells:
		if run.is_empty() or cell == previous + (Vector2i(1, 0) if horizontal \
				else Vector2i(0, 1)):
			run.append(cell)
		else:
			runs.append(run)
			run = [cell]
		previous = cell
	if not run.is_empty():
		runs.append(run)
	for group: Array in runs:
		if group.size() < 2:
			continue
		for index in group.size():
			if int(state["stacks"]) >= LATTICE_STACK_LIMIT:
				return
			if index % STACK_GAP == STACK_GAP - 1:
				continue
			var cell: Vector2i = group[index]
			if not plan.is_free(cell):
				continue
			var point: Vector3 = plan.cell_point(cell) \
				+ Vector3.UP * Parts.LAYER_FOOT
			if TileKit.spline_distance(spline, point) < LATTICE_CLEARANCE:
				continue
			var levels: int = CONTAINER_LEVELS
			if (cell.x + cell.y) % 3 == 0:
				levels = CONTAINER_TALL
			var yaw: float = 0.0 if horizontal else PI * 0.5
			var piece_height: float = Parts.size(CONTAINER_MODEL,
				PROP_SCALE).y
			var size := Vector3(TileKit.TILE_SIZE,
				piece_height * float(levels), CONTAINER_COLLIDER_DEPTH)
			if not _box_clears(spline, point
					+ Vector3.UP * (piece_height * float(levels) * 0.5),
					yaw, size):
				continue
			if not plan.take(cell):
				continue
			for level in levels:
				containers.append(Parts.fit(CONTAINER_MODEL,
					point + Vector3.UP * (piece_height * float(level)), yaw,
					PROP_SCALE))
			container_boxes.append({
				"point": point + Vector3.UP * (piece_height * float(levels)
					* 0.5),
				"yaw": yaw,
				"size": Vector3(TileKit.TILE_SIZE, piece_height * float(levels),
					CONTAINER_COLLIDER_DEPTH),
			})
			state["stacks"] = int(state["stacks"]) + 1
			stats["containers"] = int(stats["containers"]) + levels


## A sunken cargo lane along the second-longest straight: four-level container
## walls on both sides at 11.5 m, with a 16 m service opening every 48 m. The
## inner face clears the barrier by 1.5 m, so the lane is tight but legal.
static func _canyon_containers(spline: RefCounted, plan: RefCounted,
		containers: Array, container_boxes: Array[Dictionary],
		stats: Dictionary) -> void:
	var runs: Array = plan.straight_runs()
	if runs.is_empty():
		return
	var best: Dictionary = {}
	var longest: float = 0.0
	for run: Dictionary in runs:
		longest = maxf(longest, float(run["length"]))
	# Prefer a long run whose 11.5 m shoulders are both open. The top chicane
	# runs two strands 16 m apart, so a wall on one would sit 4.5 m from the
	# other; that candidate is rejected before it is built.
	for run: Dictionary in runs:
		var length: float = float(run["length"])
		if length < 40.0 or length >= longest - 0.1:
			continue
		var middle: float = float(run["from"]) + length * 0.5
		var clear: bool = true
		for side: float in [-1.0, 1.0]:
			var shoulder: Vector3 = Parts.side_point(spline, middle,
				CANYON_LATERAL * side)
			if TileKit.spline_distance(spline, shoulder) < CANYON_LATERAL:
				clear = false
				break
		if clear and (best.is_empty() or length > float(best["length"])):
			best = run
	if best.is_empty():
		return
	var span: float = float(best["length"])
	var from_distance: float = float(best["from"])
	var first: float = from_distance + TileKit.TILE_SIZE
	var last: float = from_distance + span - TileKit.TILE_SIZE
	var piece_height: float = Parts.size(CONTAINER_MODEL, PROP_SCALE).y
	var box_size := Vector3(TileKit.TILE_SIZE,
		piece_height * float(CONTAINER_CANYON), CONTAINER_COLLIDER_DEPTH)
	var distance: float = first
	var index: int = 0
	while distance <= last:
		if index % 3 != 2:
			for side: float in [-1.0, 1.0]:
				var point: Vector3 = Parts.side_point(spline, distance,
					CANYON_LATERAL * side)
				point.y = Parts.LAYER_FOOT
				var yaw: float = Parts.along_yaw(spline, distance)
				# Measure the real box, not just its centre: a long wall close
				# to a corner can turn its end towards the next strand.
				if not _box_clears(spline, point, yaw, box_size):
					continue
				for level in CONTAINER_CANYON:
					containers.append(Parts.fit(CONTAINER_MODEL,
						point + Vector3.UP * (piece_height * float(level)),
						yaw, PROP_SCALE))
				container_boxes.append({
					"point": point + Vector3.UP * (piece_height
						* float(CONTAINER_CANYON) * 0.5),
					"yaw": yaw, "size": box_size,
				})
				stats["containers"] = int(stats["containers"]) \
					+ CONTAINER_CANYON
		distance += TileKit.TILE_SIZE
		index += 1


## True when every sampled corner of a solid box clears the racing surface by
## Parts.SAFE_CLEARANCE. The static container walls are long, so measuring the
## centre alone is not enough near the corners.
static func _box_clears(spline: RefCounted, point: Vector3, yaw: float,
		size: Vector3) -> bool:
	var basis := Basis(Vector3.UP, yaw)
	for sample: Vector3 in TileKit.box_samples(size * 0.5):
		var world: Vector3 = point + basis * sample
		if TileKit.spline_distance(spline, world) < Parts.SAFE_CLEARANCE:
			return false
	return true


## One batch for every container, plus one collider per stack. Keeping the
## lattice, canyon and wharf stacks in the same array is what makes the detail
## fit the draw budget.
static func _emit_containers(parent: Node3D, containers: Array,
		container_boxes: Array[Dictionary], stats: Dictionary) -> void:
	if containers.is_empty():
		return
	var body := Parts.body(parent, "DockyardContainers")
	stats["draws"] = int(stats["draws"]) \
		+ Parts.batch(body, CONTAINER_MODEL, containers, "ContainerStacks", true)
	for entry: Dictionary in container_boxes:
		Parts.box(body, entry["point"] as Vector3, float(entry["yaw"]),
			entry["size"] as Vector3)
	stats["objects"] = int(stats["objects"]) + containers.size()


## Three quay cranes assembled from kit pieces: a banner-tower mast, a rail
## boom, a light cab and a counterweight block. Only the low mast and cab carry
## drive-into colliders; the boom is overhead but still has a solid shape so it
## is not a ghost.
static func _cranes(parent: Node3D, spline: RefCounted, plan: RefCounted,
		stats: Dictionary) -> void:
	var spots: Array[Vector2i] = []
	var candidates: Array[Vector2i] = plan.outer_band_cells()
	candidates.append_array(plan.beyond_band_cells())
	for cell: Vector2i in candidates:
		var point: Vector3 = plan.cell_point(cell)
		if TileKit.spline_distance(spline, point) < 30.0:
			continue
		var spaced: bool = true
		for other: Vector2i in spots:
			if (cell - other).length_squared() < 16:
				spaced = false
				break
		if not spaced:
			continue
		if plan.is_used(cell):
			continue
		if plan.in_grid(cell):
			if not plan.take(cell):
				continue
		else:
			plan.mark(cell)
		spots.append(cell)
		if spots.size() >= 3:
			break
	if spots.is_empty():
		return
	plan.set_meta(CRANE_META, spots)
	var masts: Array = []
	var booms: Array = []
	var cabs: Array = []
	var weights: Array = []
	var body := Parts.body(parent, "DockyardCranes")
	var centre: Vector3 = plan.centre()
	var mast_scale: Vector3 = PROP_SCALE
	var mast_size: Vector3 = Parts.size(CRANE_MAST, mast_scale)
	var boom_scale: Vector3 = Vector3(PROP_SCALE.x * 1.15,
		PROP_SCALE.y * 0.45, PROP_SCALE.z)
	var boom_size: Vector3 = Parts.size(CRANE_BOOM, boom_scale)
	var cab_scale: Vector3 = Vector3(PROP_SCALE.x * 1.2,
		PROP_SCALE.y * 0.35, PROP_SCALE.z * 1.2)
	var cab_size: Vector3 = Parts.size(CRANE_CAB, cab_scale)
	var weight_scale: Vector3 = PROP_SCALE * 0.45
	var weight_size: Vector3 = Parts.size(CONTAINER_MODEL, weight_scale)
	# Every crane part starts clear of the mast instead of running through it.
	# The mast is a square tower, so its reach along the boom is the rotated
	# half-width, not the flat one: at the old 38 m boom the arm crossed the
	# tower, the cab and the next crane's mast, which is where the yard's
	# z-clipping came from.
	var cab_offset: float = 0.0
	var weight_offset: float = 0.0
	for cell: Vector2i in spots:
		var point: Vector3 = plan.cell_point(cell) \
			+ Vector3.UP * Parts.LAYER_FOOT
		masts.append(Parts.fit(CRANE_MAST, point, 0.0, mast_scale))
		Parts.box(body, point + Vector3.UP * (mast_size.y * 0.5), 0.0,
			mast_size)
		var direction := Vector3(centre.x - point.x, 0.0, centre.z - point.z)
		if direction.length_squared() < 1.0:
			direction = Vector3.RIGHT
		direction = direction.normalized()
		var mast_reach: float = (absf(direction.x) + absf(direction.z)) \
			* mast_size.x * 0.5
		var boom_start: float = mast_reach + 0.2
		cab_offset = mast_reach + cab_size.z * 0.5 + 0.1
		weight_offset = mast_reach + weight_size.z * 0.5 + 0.15
		var boom_yaw: float = atan2(-direction.z, direction.x)
		var boom_point: Vector3 = point \
			+ direction * (boom_start + boom_size.x * 0.5) \
			+ Vector3.UP * (mast_size.y - 1.5)
		booms.append(Parts.fit(CRANE_BOOM, boom_point, boom_yaw, boom_scale))
		Parts.box(body, boom_point, boom_yaw, boom_size)
		var cab_point: Vector3 = point + direction * cab_offset \
			+ Vector3.UP * (mast_size.y - 5.0)
		cabs.append(Parts.fit(CRANE_CAB, cab_point, boom_yaw, cab_scale))
		Parts.box(body, cab_point, boom_yaw, cab_size)
		var weight_point: Vector3 = point - direction * weight_offset \
			+ Vector3.UP * (mast_size.y - 1.5)
		weights.append(Parts.fit(CONTAINER_MODEL, weight_point,
			boom_yaw + PI * 0.5, weight_scale))
		Parts.box(body, weight_point, boom_yaw + PI * 0.5, weight_size)
		stats["cranes"] = int(stats["cranes"]) + 1
	stats["draws"] = int(stats["draws"]) \
		+ Parts.batch(body, CRANE_MAST, masts, "CraneMasts", true) \
		+ Parts.batch(body, CRANE_BOOM, booms, "CraneBooms", true) \
		+ Parts.batch(body, CRANE_CAB, cabs, "CraneCabs", true) \
		+ Parts.batch(body, CONTAINER_MODEL, weights, "CraneWeights", true)
	stats["objects"] = int(stats["objects"]) + spots.size() * 4


## Bollards down the outer band and along the wharf edge: short pylon markers
## batched into one MultiMesh with a WORLD cylinder each.
static func _bollards(parent: Node3D, spline: RefCounted, plan: RefCounted,
		stats: Dictionary) -> void:
	var transforms: Array = []
	var spots: Array[Vector3] = []
	var candidates: Array[Vector2i] = plan.outer_band_cells()
	candidates.append_array(plan.beyond_band_cells())
	for cell: Vector2i in candidates:
		if spots.size() >= BOLLARD_LIMIT:
			break
		if (cell.x * 3 + cell.y) % 2 != 0:
			continue
		if plan.is_used(cell):
			continue
		var point: Vector3 = plan.cell_point(cell)
		if TileKit.spline_distance(spline, point) < 12.0:
			continue
		if plan.in_grid(cell):
			if not plan.take(cell):
				continue
		else:
			plan.mark(cell)
		spots.append(point)
		transforms.append(Parts.fit(BOLLARD_MODEL,
			point + Vector3.UP * Parts.LAYER_FOOT, 0.0, PROP_SCALE * 0.32))
	if transforms.is_empty():
		return
	var body := Parts.body(parent, "DockyardBollards")
	stats["draws"] = int(stats["draws"]) \
		+ Parts.batch(body, BOLLARD_MODEL, transforms, "QuayBollards", true)
	for point: Vector3 in spots:
		Parts.cylinder(body, point + Vector3.UP * Parts.LAYER_FOOT, 0.35,
			0.72)
	stats["objects"] = int(stats["objects"]) + transforms.size()
	stats["bollards"] = transforms.size()


## Morring clutter on the apron beyond the fence: canoes on trestles, timber
## piles and barrels. These are decoration on the far side of the catch fence,
## but each one still gets a real WORLD box.
static func _mooring(parent: Node3D, plan: RefCounted,
		stats: Dictionary) -> void:
	var entries: Array[Dictionary] = []
	var cells: Array[Vector2i] = plan.beyond_band_cells()
	var models: Array[String] = ["canoe", "log", "log_stack", "pot_small"]
	var index: int = 0
	for cell: Vector2i in cells:
		if entries.size() >= 28:
			break
		if (cell.x * 5 + cell.y) % 3 != 0:
			continue
		if plan.is_used(cell):
			continue
		var point: Vector3 = plan.cell_point(cell)
		var model: String = models[index % models.size()]
		var scale: float = TileKit.NATURE_SCALE * 0.45 \
			* (0.8 + 0.1 * float(index % 3))
		entries.append({
			"model": model, "point": point,
			"yaw": float(index) * 1.7,
			"scale": scale,
		})
		plan.mark(cell)
		index += 1
	if entries.is_empty():
		return
	var batches: Dictionary = {}
	for entry: Dictionary in entries:
		var model: String = str(entry["model"])
		if not batches.has(model):
			batches[model] = []
		(batches[model] as Array).append(Parts.fit_nature(model,
			(entry["point"] as Vector3) + Vector3.UP * Parts.LAYER_FOOT,
			float(entry["yaw"]), Vector3.ONE * float(entry["scale"])))
	var body := Parts.body(parent, "DockyardMooring")
	for model: String in batches:
		stats["draws"] = int(stats["draws"]) \
			+ Parts.batch_nature(body, model, batches[model] as Array,
				"Mooring_" + model, false)
	for entry: Dictionary in entries:
		var size: Vector3 = Parts.size_nature(str(entry["model"]),
			Vector3.ONE * float(entry["scale"]))
		Parts.box(body, (entry["point"] as Vector3) \
			+ Vector3.UP * (size.y * 0.5 + Parts.LAYER_FOOT),
			float(entry["yaw"]), size)
	stats["objects"] = int(stats["objects"]) + entries.size()
	stats["mooring"] = entries.size()


## Catch fence on the free cells of the quay ring, with a service gate every
## ninth panel. A cell claimed by a stand, office or wharf is skipped.
static func _grid_fence(parent: Node3D, plan: RefCounted,
		stats: Dictionary) -> void:
	var transforms: Array = []
	var points: Array[Vector3] = []
	var yaws: Array[float] = []
	var cells: Array[Vector2i] = []
	var index: int = 0
	for cell: Vector2i in plan.ring_cells():
		index += 1
		if index % 9 == 0:
			continue
		if not plan.take(cell):
			continue
		var horizontal: bool = cell.y == 1 or cell.y == plan.rows - 2
		var yaw: float = 0.0 if horizontal else PI * 0.5
		var point: Vector3 = plan.cell_point(cell)
		cells.append(cell)
		points.append(point)
		transforms.append(Parts.fit(FENCE_MODEL,
			point + Vector3.UP * Parts.LAYER_FOOT, yaw, PROP_SCALE))
		yaws.append(yaw)
	plan.set_meta(FENCE_META, cells)
	_fence_batch(parent, transforms, points, yaws, stats)


static func _fence_batch(parent: Node3D, transforms: Array, points: Array,
		yaws: Array[float], stats: Dictionary) -> void:
	if transforms.is_empty():
		return
	var body := Parts.body(parent, "DockyardFence")
	stats["draws"] = int(stats["draws"]) \
		+ Parts.batch(body, FENCE_MODEL, transforms, "QuayFence", false)
	var size: Vector3 = Parts.size(FENCE_MODEL, PROP_SCALE)
	for index in points.size():
		var point: Vector3 = points[index]
		Parts.box(body, point + Vector3.UP * (size.y * 0.5 + Parts.LAYER_FOOT),
			yaws[index], size)
	stats["objects"] = int(stats["objects"]) + transforms.size()
	stats["fence"] = int(stats["fence"]) + transforms.size()


# --------------------------------------------------------------------------
# legacy spline yard


## Pit complex and container rows along the longest straight of a spline map.
static func _arc_yard(parent: Node3D, spline: RefCounted, plan: RefCounted,
		stats: Dictionary) -> void:
	var runs: Array = plan.straight_runs()
	if runs.is_empty():
		return
	var best: Dictionary = runs[0]
	for run: Dictionary in runs:
		if float(run["length"]) > float(best["length"]):
			best = run
	var span: float = float(best["length"])
	var middle: float = float(best["from"]) + span * 0.5
	var step: float = TileKit.TILE_SIZE
	var pads: Array = []
	var pad_count: int = 5
	for index in pad_count:
		var distance: float = middle \
			+ (float(index) - float(pad_count - 1) * 0.5) * step
		var claimed: Variant = _claim_arc(plan, spline, distance,
			step * 1.125, 12.0)
		if claimed is Vector3:
			pads.append(Parts.fit(PAD_MODEL, claimed,
				plan.along_yaw(distance), PAD_SCALE))
	if not pads.is_empty():
		stats["draws"] = int(stats["draws"]) \
			+ Parts.batch(parent, PAD_MODEL, pads, "PitApron", false)
		stats["objects"] = int(stats["objects"]) + pads.size()
	var garages: Array = []
	var garage_points: Array[Vector3] = []
	for index in 4:
		var distance: float = middle \
			+ (float(index) - 1.5) * TileKit.TILE_SIZE
		var claimed: Variant = _claim_arc(plan, spline, distance,
			TileKit.TILE_SIZE * 2.125, 14.0)
		if not (claimed is Vector3):
			continue
		var point: Vector3 = claimed
		garages.append(Parts.fit(GARAGE_MODEL, point,
			plan.across_yaw(distance), PROP_SCALE))
		garage_points.append(point)
	var garage_body := Parts.body(parent, "DockyardGarages")
	if not garages.is_empty():
		stats["draws"] = int(stats["draws"]) \
			+ Parts.batch(garage_body, GARAGE_MODEL, garages, "PitGarages",
				true)
		var size: Vector3 = Parts.size(GARAGE_MODEL, PROP_SCALE)
		for index in garage_points.size():
			Parts.box(garage_body,
				garage_points[index] + Vector3.UP * (size.y * 0.5),
				plan.across_yaw(middle), size)
		stats["objects"] = int(stats["objects"]) + garages.size()
		stats["pit_bays"] = int(stats["pit_bays"]) + garages.size()
	var containers: Array = []
	var boxes: Array[Dictionary] = []
	var piece_height: float = Parts.size(CONTAINER_MODEL, PROP_SCALE).y
	for row in 2:
		for index in 5:
			var distance: float = middle \
				+ (float(index) - 2.0) * TileKit.TILE_SIZE
			var lateral: float = TileKit.TILE_SIZE * (2.875 + float(row) * 0.875)
			var claimed: Variant = _claim_arc(plan, spline, distance, lateral,
				14.0)
			if not (claimed is Vector3):
				continue
			var point: Vector3 = claimed
			var yaw: float = plan.across_yaw(distance)
			for level in CONTAINER_LEVELS:
				containers.append(Parts.fit(CONTAINER_MODEL,
					point + Vector3.UP * (piece_height * float(level)), yaw,
					PROP_SCALE))
			boxes.append({
				"point": point + Vector3.UP * (piece_height
					* float(CONTAINER_LEVELS) * 0.5),
				"yaw": yaw,
				"size": Vector3(TileKit.TILE_SIZE,
					piece_height * float(CONTAINER_LEVELS),
					CONTAINER_COLLIDER_DEPTH),
			})
			stats["containers"] = int(stats["containers"]) \
				+ CONTAINER_LEVELS
	_emit_containers(parent, containers, boxes, stats)


static func _arc_fence(parent: Node3D, spline: RefCounted, plan: RefCounted,
		stats: Dictionary) -> void:
	var transforms: Array = []
	var points: Array[Vector3] = []
	var yaws: Array[float] = []
	for point: Vector3 in plan.arc_slots(16.0, -30.0, false, 22.0):
		var hit: Dictionary = spline.closest(point)
		var yaw: float = plan.across_yaw(float(hit.get("s", 0.0)))
		points.append(point)
		transforms.append(Parts.fit(FENCE_MODEL, point, yaw, PROP_SCALE))
		yaws.append(yaw)
	_fence_batch(parent, transforms, points, yaws, stats)


# --------------------------------------------------------------------------
# helpers


## Snaps an arc-length point to the lattice and claims it, or null when another
## yard row or a stand already owns that cell.
static func _claim_arc(plan: RefCounted, spline: RefCounted, distance: float,
		lateral: float, clearance: float) -> Variant:
	var frame: Dictionary = spline.sample(distance)
	var raw: Vector3 = frame["position"] + frame["right"] * lateral
	var point: Vector3 = Parts.snap(raw)
	if not plan.take_point(point, clearance):
		return null
	return point
