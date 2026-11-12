extends RefCounted
## Circuit furniture: the visible language of a race track.
##
## Every piece is placed from CircuitLayout's one plan, so kerbs only run along
## corner edges, armco only lines the straights, tyre walls only sit at the
## fast corners and the two grandstands only stand on the two straightest
## sweeps of the lap. Nothing here is on the racing line: the closest prop is
## the kerb lip, which is a drive-over slope, and the armco sits outside the
## race controller's barrier line.
##
## Repeats use RacingKit's MultiMeshes (tyres, crowd) and merged vertex-coloured
## meshes (armco, pit wall, garages); every solid piece carries a WORLD
## collider. The only props without a body are people and paint, which are not
## things a cart can drive through.

const RaceKit := preload("res://scripts/minigames/racing_kit.gd")
const SceneryKit := preload("res://scripts/minigames/scenery/scenery_kit.gd")
const PropBatch := preload("res://scripts/minigames/scenery/prop_batch.gd")
const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")
const CircuitLayout := preload("res://scripts/minigames/maps/circuit/circuit_layout.gd")
const CircuitGround := preload("res://scripts/minigames/maps/circuit/circuit_ground.gd")

const KERB_RED := Color("c23a2c")
const CREAM := Color("fff6e3")
const CONCRETE := Color("b9b4a8")
const STEEL := Color("4a5560")
const DARK := Color("2f2a26")
const CIRCUIT_RED := Color("c9553f")
const PIT_BLUE := Color("2e86ab")
const PIT_SHIRTS: Array[Color] = [
	Color("e4572e"), Color("f6c945"), Color("3fa34d"), Color("f3f0e6"),
	Color("2e86ab"), Color("b84a9c"),
]
const PIT_SKINS: Array[Color] = [
	Color("f2c9a0"), Color("d9a06b"), Color("a86b3f"), Color("7a4a2b"),
]

## Lateral offsets mirrored from RacingKit / grass_race.
const ROAD_HALF: float = 5.5
const STAND_LATERAL: float = ROAD_HALF + 10.0
const TYRE_LATERAL: float = ROAD_HALF + 1.9
const BOARD_LATERAL: float = ROAD_HALF + 3.2
const BARRIER_RUN: float = 21.0

## Pit complex, on the inside of the start straight.
const PIT_WALL_LATERAL: float = 6.95
const PIT_WALL_HEIGHT: float = 1.05
const GARAGE_LATERAL: float = 18.1
const GARAGE_DEPTH: float = 4.8
const GARAGE_HEIGHT: float = 3.3
const GARAGE_STEP: float = 6.0


## Builds every trackside prop under `holder` and returns what was placed.
static func build(holder: Node3D, spline: RefCounted,
		plan: Dictionary) -> Dictionary:
	var stats: Dictionary = {
		"kerbs": 0, "barriers": 0, "tyre_walls": 0, "stands": 0,
		"floodlights": 0, "boards": 0, "pit_bays": 0,
	}
	# Stands and the pit complex claim their ground first; the smaller props
	# then avoid them instead of the other way round.
	var stands: Array[Dictionary] = _grandstands(holder, spline, plan)
	stats["stands"] = stands.size()
	stats["kerbs"] = _kerbs(holder, spline, plan)
	stats["barriers"] = _barriers(holder, spline, plan)
	var walls: Array[Dictionary] = _tyre_walls(holder, spline, plan, stands)
	stats["tyre_walls"] = walls.size()
	_start_gantry(holder, spline, plan)
	stats["boards"] = _distance_boards(holder, spline, plan, walls)
	stats["floodlights"] = _floodlights(holder, spline, plan, stands)
	stats["pit_bays"] = _pit_complex(holder, spline)
	return stats


# --------------------------------------------------------------------------
# kerbs, armco and tyre walls


## Kerbs on the inside and outside edge of every numbered corner only.
static func _kerbs(holder: Node3D, spline: RefCounted, plan: Dictionary) -> int:
	var runs: int = 0
	for corner: Dictionary in plan["corners"]:
		var outside: float = float(corner["outside"])
		for side: float in [outside, -outside]:
			RaceKit.kerbs(holder, spline, float(corner["from"]),
				float(corner["to"]), side, KERB_RED)
			runs += 1
	return runs


## Armco down both edges of the straights. The inside of the pit straight is
## left to the solid pit wall instead of stacking two barriers in one place.
static func _barriers(holder: Node3D, spline: RefCounted,
		plan: Dictionary) -> int:
	var total: float = float(plan["total"])
	var runs: int = 0
	for straight: Dictionary in plan["straights"]:
		var centre: float = float(straight["distance"])
		for side: float in [-1.0, 1.0]:
			if side > 0.0 and CircuitGround.in_lane(spline, centre,
					BARRIER_RUN):
				continue
			var from: float = fposmod(centre - BARRIER_RUN, total)
			var to: float = fposmod(centre + BARRIER_RUN, total)
			RaceKit.barriers(holder, spline, from, to, side)
			runs += 1
	return runs


## Tyre walls on the outside of the two fastest corners: the ones taken with
## the largest radius, where a mistake carries the most speed. Returns the
## placed walls so the boards can keep clear of them.
static func _tyre_walls(holder: Node3D, spline: RefCounted,
		plan: Dictionary, stands: Array[Dictionary]) -> Array[Dictionary]:
	var total: float = float(plan["total"])
	var ranked: Array[Dictionary] = []
	for corner: Dictionary in plan["corners"]:
		ranked.append(corner)
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["radius"]) > float(b["radius"]))
	var walls: Array[Dictionary] = []
	for corner: Dictionary in ranked:
		if walls.size() >= 2:
			break
		var distance: float = float(corner["distance"]) + 9.0
		var side: float = float(corner["outside"])
		if side > 0.0 and CircuitGround.in_lane(spline, distance, 12.0):
			continue
		if _near_stand(stands, distance, total, 28.0):
			continue
		if not CircuitLayout.spot_ok(spline, distance, side * TYRE_LATERAL,
				8.0, 2.6):
			continue
		RaceKit.tyre_wall(holder, spline, distance, side, 14.0)
		walls.append({"distance": distance, "side": side, "half": 7.2})
	return walls


# --------------------------------------------------------------------------
# grandstands, gantry and signage


## The two grandstands, on the two straightest sweeps of the lap. The outside
## of the loop is preferred (the infield is the paddock); the infield side is
## only used when it is clear of the pit complex.
static func _grandstands(holder: Node3D, spline: RefCounted,
		plan: Dictionary) -> Array[Dictionary]:
	var stands: Array[Dictionary] = []
	var total: float = float(plan["total"])
	var candidates: Array[Dictionary] = []
	for straight: Dictionary in plan["straights"]:
		candidates.append(straight)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["rank"]) < int(b["rank"]))
	for straight: Dictionary in candidates:
		if stands.size() >= 2:
			break
		var base: float = float(straight["distance"])
		var placed: bool = false
		for shift: float in [0.0, -8.0, 8.0]:
			if placed:
				break
			for side: float in [-1.0, 1.0]:
				if side > 0.0 and CircuitGround.in_lane(spline, base + shift,
						14.0):
					continue
				var distance: float = fposmod(base + shift, total)
				if not CircuitLayout.spot_ok(spline, distance,
						side * STAND_LATERAL, 9.0, 8.5):
					continue
				if _near_stand(stands, distance, total, 30.0):
					continue
				RaceKit.grandstand(holder, spline, distance, side)
				stands.append({"distance": distance, "side": side})
				placed = true
				break
	return stands


static func _start_gantry(holder: Node3D, spline: RefCounted,
		plan: Dictionary) -> void:
	# The race controller draws its own low START/FINISH beam at arc 0. The
	# gantry straddles the line 2.4 m earlier so the two structures never
	# interpenetrate and the banner stays readable from the grid.
	RaceKit.start_gantry(holder, spline, fposmod(-2.4, float(plan["total"])))


## One board per corner, 44 m out on the outside of the approach, carrying the
## corner number instead of a distance. A board that would stand in a tyre
## wall is moved a further 12 m back up the straight instead of being dropped.
static func _distance_boards(holder: Node3D, spline: RefCounted,
		plan: Dictionary, walls: Array[Dictionary]) -> int:
	var total: float = float(plan["total"])
	var boards: int = 0
	for corner: Dictionary in plan["corners"]:
		var distance: float = 0.0
		var side: float = 0.0
		var clear: bool = false
		for offset: float in [-44.0, -56.0, -32.0]:
			distance = fposmod(float(corner["distance"]) + offset, total)
			side = CircuitLayout.bend_side(spline, distance)
			if side > 0.0 and CircuitGround.in_lane(spline, distance, 10.0):
				continue
			if _near_wall(walls, distance, side, total):
				continue
			if not CircuitLayout.spot_ok(spline, distance,
					side * BOARD_LATERAL, 1.8, 3.0):
				continue
			clear = true
			break
		if not clear:
			continue
		RaceKit.distance_board(holder, spline, distance,
			str(corner["index"]))
		boards += 1
	return boards


# --------------------------------------------------------------------------
# floodlights


## Light towers on the outside of the four tightest corners and down the
## straights, plus two over the paddock. `RacingKit.floodlight` draws the head
## as emissive geometry instead of a real light, so the poles cost no dynamic
## lighting and stay cheap enough for the web build.
static func _floodlights(holder: Node3D, spline: RefCounted, plan: Dictionary,
		stands: Array[Dictionary]) -> int:
	var total: float = float(plan["total"])
	var spots: Array[Dictionary] = []
	var lane: Array[float] = CircuitGround.lane_span(spline)
	for fraction: float in [0.22, 0.76]:
		spots.append({"distance": lane[0] + lane[1] * fraction,
			"lateral": CircuitGround.PADDOCK_OUTER - 1.0, "paddock": true})
	for straight: Dictionary in plan["straights"]:
		spots.append({"distance": float(straight["distance"]),
			"lateral": -19.0, "paddock": false})
	var corners: Array[Dictionary] = []
	for corner: Dictionary in plan["corners"]:
		corners.append(corner)
	corners.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["radius"]) < float(b["radius"]))
	for i in mini(corners.size(), 4):
		var corner: Dictionary = corners[i]
		spots.append({"distance": float(corner["distance"]) + 4.0,
			"lateral": float(corner["outside"]) * 19.0, "paddock": false})
	var placed: Array[Dictionary] = []
	var lights: int = 0
	for spot: Dictionary in spots:
		if lights >= 8:
			break
		var distance: float = fposmod(float(spot["distance"]), total)
		var lateral: float = float(spot["lateral"])
		var side: float = signf(lateral)
		if not bool(spot["paddock"]):
			if lateral > 0.0 and CircuitGround.in_lane(spline, distance, 16.0):
				continue
			if _near_stand(stands, distance, total, 24.0):
				continue
		var crowded: bool = false
		for other: Dictionary in placed:
			if float(other["side"]) == side and CircuitLayout.arc_gap(distance,
					float(other["distance"]), total) < 20.0:
				crowded = true
				break
		if crowded:
			continue
		if not CircuitLayout.spot_ok(spline, distance, lateral, 2.0, 3.2):
			continue
		RaceKit.floodlight(holder,
			CircuitLayout.at(spline, distance, lateral, 0.0))
		placed.append({"distance": distance, "side": side})
		lights += 1
	return lights


# --------------------------------------------------------------------------
# pit complex


## The pit wall, garage block and crew that turn the concrete strip into a
## working service lane.
static func _pit_complex(holder: Node3D, spline: RefCounted) -> int:
	var lane: Array[float] = CircuitGround.lane_span(spline)
	var vertex: Material = RaceKit.palette()["vertex"] as Material
	_pit_wall(holder, spline, lane[0], lane[1], vertex)
	var bays: int = _garages(holder, spline, lane[0], lane[1], vertex)
	_pit_crew(holder, spline, lane[0], lane[1],
		RaceKit.palette()["instance"] as Material)
	return bays


static func _pit_wall(holder: Node3D, spline: RefCounted, lane_from: float,
		lane_length: float, material: Material) -> void:
	var step: float = 5.0
	var count: int = maxi(int(floor((lane_length - 4.0) / step)), 1)
	var body := _solid(holder, "PitWallBody")
	var batch := PropBatch.new()
	for i in count:
		var distance: float = lane_from + 2.0 + (float(i) + 0.5) * step
		var root: Transform3D = CircuitLayout.transform_at(spline, distance,
			PIT_WALL_LATERAL)
		var length: float = step + 0.12
		batch.add_box(root * Transform3D(Basis.IDENTITY,
			Vector3(0.0, PIT_WALL_HEIGHT * 0.5, 0.0)),
			Vector3(0.34, PIT_WALL_HEIGHT, length), CONCRETE)
		batch.add_box(root * Transform3D(Basis.IDENTITY,
			Vector3(0.0, PIT_WALL_HEIGHT + 0.06, 0.0)),
			Vector3(0.44, 0.12, length), CREAM)
		if i % 2 == 0:
			# One thin red band on the track-facing face, like a timing line.
			batch.add_box(root * Transform3D(Basis.IDENTITY,
				Vector3(-0.19, 0.80, 0.0)),
				Vector3(0.04, 0.24, length * 0.55), CIRCUIT_RED)
		_box_shape(body, root * Transform3D(Basis.IDENTITY,
			Vector3(0.0, PIT_WALL_HEIGHT * 0.5, 0.0)),
			Vector3(0.42, PIT_WALL_HEIGHT, length))
	_merged(holder, batch, "PitWallDetail", material)


static func _garages(holder: Node3D, spline: RefCounted, lane_from: float,
		lane_length: float, material: Material) -> int:
	var count: int = maxi(int(floor((lane_length - 12.0) / GARAGE_STEP)), 1)
	var body := _solid(holder, "PitGarageBody")
	var batch := PropBatch.new()
	for i in count:
		var distance: float = lane_from + 8.0 + (float(i) + 0.5) * GARAGE_STEP
		var root: Transform3D = CircuitLayout.transform_at(spline, distance,
			GARAGE_LATERAL)
		# A garage module: shell, roof, door, awning. Modules overlap by a few
		# centimetres so a bending pit lane never opens a gap between bays.
		batch.add_box(root * Transform3D(Basis.IDENTITY,
			Vector3(0.0, GARAGE_HEIGHT * 0.5, 0.0)),
			Vector3(GARAGE_DEPTH, GARAGE_HEIGHT, GARAGE_STEP + 0.25),
			CONCRETE.darkened(0.06))
		batch.add_box(root * Transform3D(Basis.IDENTITY,
			Vector3(0.0, GARAGE_HEIGHT + 0.11, 0.0)),
			Vector3(GARAGE_DEPTH + 0.8, 0.22, GARAGE_STEP + 0.3), STEEL)
		batch.add_box(root * Transform3D(Basis.IDENTITY,
			Vector3(-GARAGE_DEPTH * 0.5 - 0.05, 1.25, 0.0)),
			Vector3(0.08, 2.5, 3.3), DARK)
		batch.add_box(root * Transform3D(Basis.IDENTITY,
			Vector3(-GARAGE_DEPTH * 0.5 - 0.07, 2.62, 0.0)),
			Vector3(0.10, 0.26, 3.6), CREAM)
		var awning: Color = CIRCUIT_RED
		if i % 3 == 1:
			awning = PIT_BLUE
		elif i % 3 == 2:
			awning = CREAM
		batch.add_box(root * Transform3D(Basis.IDENTITY,
			Vector3(-GARAGE_DEPTH * 0.5 - 0.75, 3.16, 0.0)),
			Vector3(1.6, 0.14, GARAGE_STEP + 0.1), awning)
		_box_shape(body, root * Transform3D(Basis.IDENTITY,
			Vector3(0.0, GARAGE_HEIGHT * 0.5, 0.0)),
			Vector3(GARAGE_DEPTH, GARAGE_HEIGHT, GARAGE_STEP + 0.25))
	_merged(holder, batch, "PitGarageDetail", material)
	return count


## Pit crew figures waiting in the lane. Two MultiMeshes for every person on
## the apron; people are decoration and carry no body.
static func _pit_crew(holder: Node3D, spline: RefCounted, lane_from: float,
		lane_length: float, material: Material) -> void:
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.22
	body_mesh.height = 0.92
	body_mesh.radial_segments = 6
	body_mesh.rings = 2
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.17
	head_mesh.height = 0.34
	head_mesh.radial_segments = 5
	head_mesh.rings = 2
	var rng := RandomNumberGenerator.new()
	rng.seed = 4409
	var bodies: Array = []
	var heads: Array = []
	var shirts: Array = []
	var skins: Array = []
	var count: int = maxi(int((lane_length - 16.0) / 7.0), 1)
	for i in count:
		var distance: float = lane_from + 12.0 + float(i) * 7.0
		var lateral: float = rng.randf_range(11.4, 14.1)
		var basis := Basis(Vector3.UP, spline.yaw_at(distance)
			+ rng.randf_range(-2.8, 2.8))
		var point: Vector3 = CircuitLayout.at(spline, distance, lateral, 0.0)
		bodies.append(Transform3D(basis, point + Vector3.UP * 0.46))
		heads.append(Transform3D(basis, point + Vector3.UP * 0.95))
		shirts.append(PIT_SHIRTS[rng.randi_range(0, PIT_SHIRTS.size() - 1)])
		skins.append(PIT_SKINS[rng.randi_range(0, PIT_SKINS.size() - 1)])
	if bodies.is_empty():
		return
	var body_view := SceneryKit.multimesh(body_mesh, material, bodies,
		"PitCrew", false, shirts)
	SceneryKit.set_view(body_view, 0.0, 160.0)
	holder.add_child(body_view)
	var head_view := SceneryKit.multimesh(head_mesh, material, heads,
		"PitCrewHeads", false, skins)
	SceneryKit.set_view(head_view, 0.0, 160.0)
	holder.add_child(head_view)


# --------------------------------------------------------------------------
# helpers


static func _near_stand(stands: Array[Dictionary], distance: float,
		total: float, margin: float) -> bool:
	for stand: Dictionary in stands:
		if CircuitLayout.arc_gap(distance, float(stand["distance"]),
				total) < margin:
			return true
	return false


static func _near_wall(walls: Array[Dictionary], distance: float, side: float,
		total: float) -> bool:
	for wall: Dictionary in walls:
		if signf(float(wall["side"])) != side:
			continue
		if CircuitLayout.arc_gap(distance, float(wall["distance"]),
				total) < float(wall["half"]) + 2.5:
			return true
	return false


static func _solid(parent: Node3D, node_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = 0
	parent.add_child(body)
	return body


static func _box_shape(body: StaticBody3D, xform: Transform3D,
		size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = xform
	body.add_child(collision)


static func _merged(parent: Node3D, batch: RefCounted, node_name: String,
		material: Material) -> void:
	var mesh: ArrayMesh = batch.build()
	if mesh == null:
		return
	var visual := MeshInstance3D.new()
	visual.name = node_name
	visual.mesh = mesh
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(visual)
