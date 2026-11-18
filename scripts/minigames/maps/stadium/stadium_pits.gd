extends RefCounted
## Pit lane, paddock and start complex of the STADIUM CIRCUIT.
##
## The pit complex sits on the infield of the start straight, which is where a
## kart comes out of the last corner: pit wall at the road-side edge, then a
## service lane of flat Kenney pit-straight slabs that splits off the main
## straight and merges back into it, then a row of garage doors, an office pair
## and the paddock tents behind. The split is decorative tarmac (no collider:
## the ground carries it), everything solid behind it is on WORLD.
##
## The start gantry is the kit's overhead-light truss over the line, with banner
## towers at either end of the start box, so the countdown in grass_race still
## happens under a real stadium structure.
##
## The race scene's own start-light rig stands a few metres further down the
## straight; this module never puts anything over the racing surface, so the two
## read as one start box instead of fighting for the same space.

const Props := preload("res://scripts/minigames/maps/stadium/stadium_props.gd")
const TileKit := preload("res://scripts/minigames/tile_kit.gd")
const TileCatalog := preload("res://scripts/minigames/tiles/tile_catalog.gd")

const PIT_TILE: String = "roadPitStraight"
const PIT_SPLIT: String = "roadStraight"
const GARAGE: String = "pitsGarage"
const GARAGE_CLOSED: String = "pitsGarageClosed"
const GARAGE_CORNER: String = "pitsGarageCorner"
const OFFICE: String = "pitsOffice"
const OFFICE_ROOF: String = "pitsOfficeRoof"
const PIT_RAIL: String = "railDouble"
const TENT: String = "tent"
const TENT_CLOSED: String = "tentClosed"
const TENT_LONG: String = "tentLong"
const TENT_ROOF: String = "tentRoof"
const TIMING: String = "radarEquipment"
const BANNER_RED: String = "bannerTowerRed"
const BANNER_GREEN: String = "bannerTowerGreen"

## Metres from the centreline, on the infield side of the start straight.
const PIT_WALL_LATERAL: float = 18.6
const PIT_LANE_LATERAL: float = 28.0
const PIT_SPLIT_LATERAL: float = 20.0
const GARAGE_LATERAL: float = 43.0
const OFFICE_LATERAL: float = 56.0
const PADDOCK_LATERAL: float = 60.0
const TOWER_LATERAL: float = 12.4
const BOARD_LATERAL: float = 13.2

## Pitch of the pieces along the straight, and how many the complex holds.
const BAY: float = 16.0
const GARAGES: int = 8
const PIT_RAIL_PIECES: int = 8
const TENTS: int = 5
const PADDOCK_SPREAD: float = 6.0


## Builds the start box, the pit lane and the paddock. `stats` receives the
## counts; the last straight run of the lap is used if the start run is short.
static func build(holder: Node3D, spline: RefCounted, plan: Dictionary,
		stats: Dictionary) -> void:
	if holder == null or spline == null:
		return
	_pit_lane(holder, spline, plan, stats)
	_start_box(holder, spline, plan, stats)
	_paddock(holder, spline, plan, stats)


## Run of the pit complex: the straight the start line is on. It is the longest
## straight when the grid starts on one, which the stadium grid does.
static func _pit_run(plan: Dictionary) -> Dictionary:
	var run: Dictionary = plan["start_straight"]
	if float(run.get("length", 0.0)) < BAY * 3.0:
		run = plan["longest"]
	return run


## Pit wall, pit lane slabs, garage row and offices.
static func _pit_lane(holder: Node3D, spline: RefCounted, plan: Dictionary,
		stats: Dictionary) -> void:
	var inside: float = float(plan["inside"])
	var run: Dictionary = _pit_run(plan)
	var from: float = float(run["from"])
	var to: float = float(run["to"])
	var length: float = maxf(to - from, BAY)

	# The pit wall runs the length of the lane on the road side: a double rail
	# on WORLD, so it is solid and reads as a wall with a fence on top.
	var wall_transforms: Array = []
	var wall_spots: Array[Dictionary] = []
	for index in PIT_RAIL_PIECES:
		var lap: float = from + length * (float(index) + 0.5) \
			/ float(PIT_RAIL_PIECES)
		var point: Vector3 = Props.deck_point(spline, lap,
			PIT_WALL_LATERAL * inside)
		if not Props.site_ok(spline, point, 1.0):
			continue
		var yaw: float = Props.along_yaw(spline, lap)
		wall_transforms.append(Props.fit(PIT_RAIL, point, yaw,
			Vector3.ONE * Props.PROP_SCALE))
		wall_spots.append({"point": point, "yaw": yaw})
	if not wall_transforms.is_empty():
		var wall_body := Props.body(holder, "PitWall")
		for spot: Dictionary in wall_spots:
			Props.model_body(wall_body, PIT_RAIL, spot["point"],
				float(spot["yaw"]), Vector3.ONE * Props.PROP_SCALE)
		stats["draws"] = int(stats.get("draws", 0)) + Props.batch(holder,
			PIT_RAIL, wall_transforms, "PitWallBatch", true)
		stats["pit_wall"] = int(stats.get("pit_wall", 0)) \
			+ wall_transforms.size()

	# The service lane itself: flat kit pit-straight slabs at grade, split off
	# the main straight at both ends so it reads as a lane and not a terrace.
	var lane: Array = []
	var splits: Array = []
	for index in GARAGES:
		var lap: float = from + length * (float(index) + 0.5) \
			/ float(GARAGES)
		var point: Vector3 = Props.deck_point(spline, lap,
			PIT_LANE_LATERAL * inside)
		if not Props.site_ok(spline, point, 8.0):
			continue
		lane.append(Props.fit(PIT_TILE, point, Props.along_yaw(spline, lap),
			Vector3.ONE * Props.PROP_SCALE))
	for entry: float in [from - 8.0, to + 8.0]:
		var point: Vector3 = Props.deck_point(spline, entry,
			PIT_SPLIT_LATERAL * inside)
		if not Props.site_ok(spline, point, 8.0):
			continue
		splits.append(Props.fit(PIT_SPLIT, point,
			Props.along_yaw(spline, entry) + 0.32,
			Vector3.ONE * Props.PROP_SCALE))
	stats["draws"] = int(stats.get("draws", 0)) + Props.batch(holder,
		PIT_TILE, lane, "PitLaneSlabs", false)
	stats["draws"] = int(stats.get("draws", 0)) + Props.batch(holder,
		PIT_SPLIT, splits, "PitLaneSplits", false)

	# The garage row: eight doors facing the lane, one closed, one corner piece
	# at each end, plus the office block and its roof behind them.
	var garages: Dictionary = {}
	var garage_body := Props.body(holder, "PitGarages")
	for index in GARAGES:
		var lap: float = from + length * (float(index) + 0.5) \
			/ float(GARAGES)
		var point: Vector3 = Props.deck_point(spline, lap,
			GARAGE_LATERAL * inside)
		if not Props.site_ok(spline, point, 11.9):
			continue
		var yaw: float = Props.along_yaw(spline, lap) + PI
		var model: String = GARAGE
		if index == 0 or index == GARAGES - 1:
			model = GARAGE_CORNER
		elif index == GARAGES - 2:
			model = GARAGE_CLOSED
		if not garages.has(model):
			garages[model] = []
		(garages[model] as Array).append(Props.fit(model, point, yaw,
			Vector3.ONE * Props.PROP_SCALE))
		Props.model_body(garage_body, model, point, yaw,
			Vector3.ONE * Props.PROP_SCALE)
		stats["pit"] = int(stats.get("pit", 0)) + 1
	for model: String in garages:
		stats["draws"] = int(stats.get("draws", 0)) + Props.batch(holder,
			model, garages[model] as Array, "Garage_" + model, true)

	var offices: Array = []
	var office_body := Props.body(holder, "PitOffices")
	for index in 2:
		var lap: float = from + length * (0.25 + 0.5 * float(index))
		var point: Vector3 = Props.deck_point(spline, lap,
			OFFICE_LATERAL * inside)
		if not Props.site_ok(spline, point, 11.9):
			continue
		var yaw: float = Props.along_yaw(spline, lap) + PI
		offices.append(Props.fit(OFFICE, point, yaw,
			Vector3.ONE * Props.PROP_SCALE))
		Props.model_body(office_body, OFFICE, point, yaw,
			Vector3.ONE * Props.PROP_SCALE)
	if office_body.get_child_count() == 0:
		office_body.free()
	stats["draws"] = int(stats.get("draws", 0)) \
		+ Props.batch(holder, OFFICE, offices, "PitOfficeRow", true)


## Start gantry over the line plus the banner towers and sponsor boards that
## frame the start box. The gantry is the kit's overhead-light truss, so the
## start reads as a lit stadium structure rather than a bare beam.
static func _start_box(holder: Node3D, spline: RefCounted, plan: Dictionary,
		stats: Dictionary) -> void:
	var inside: float = float(plan["inside"])
	var outside: float = float(plan["outside"])
	var start: float = float(plan["start_distance"])
	stats["gantry"] = int(stats.get("gantry", 0)) \
		+ TileKit.gantry(holder, spline, 0.0)
	stats["draws"] = int(stats.get("draws", 0)) \
		+ Props.part_count(TileCatalog.LIGHT_GANTRY)
	var batches: Dictionary = {}
	var body := Props.body(holder, "StartBox")
	for side: float in [-1.0, 1.0]:
		var lateral: float = TOWER_LATERAL * (outside if side < 0.0 else inside)
		var point: Vector3 = Props.deck_point(spline, start + 6.0, lateral)
		_start_piece(batches, body, spline, BANNER_RED, point,
			Props.face_track_yaw(spline, point))
	# One green tower marks the pit exit at the end of the lane.
	var run: Dictionary = _pit_run(plan)
	var exit_point: Vector3 = Props.deck_point(spline,
		float(run["to"]) + 10.0, TOWER_LATERAL * inside)
	_start_piece(batches, body, spline, BANNER_GREEN, exit_point,
		Props.face_track_yaw(spline, exit_point))
	# Sponsor boards face the start box from the infield edge of the lane.
	for index in 4:
		var lap: float = start + 20.0 + float(index) * 28.0
		var point: Vector3 = Props.deck_point(spline, lap,
			BOARD_LATERAL * inside)
		_start_piece(batches, body, spline, "billboardLow", point,
			Props.face_track_yaw(spline, point))
	var placed: int = 0
	for kind: String in batches:
		var model: String = _sign_model(kind)
		var transforms: Array = batches[kind] as Array
		placed += transforms.size()
		stats["draws"] = int(stats.get("draws", 0)) + Props.batch(holder,
			model, transforms, "Start_" + model, true)
	stats["signage"] = int(stats.get("signage", 0)) + placed


## Queues one start-box piece in its batch.
static func _start_piece(batches: Dictionary, body_node: StaticBody3D,
		spline: RefCounted, kind: String, point: Vector3, yaw: float) -> void:
	var model: String = _sign_model(kind)
	var scale: float = TileCatalog.sign_scale(kind)
	if not Props.site_ok(spline, point,
			Props.half_extent(model, Vector3.ONE * scale)):
		return
	if not batches.has(kind):
		batches[kind] = []
	(batches[kind] as Array).append(Props.fit(model, point, yaw,
		Vector3.ONE * scale))
	Props.model_body(body_node, model, point, yaw, Vector3.ONE * scale)


static func _sign_model(kind: String) -> String:
	match kind:
		"bannerTower", "bannerTowerRed":
			return TileCatalog.BANNER_TOWER
		"bannerTowerGreen":
			return TileCatalog.BANNER_TOWER_GREEN
		_:
			return TileCatalog.BILLBOARD_LOW


## The paddock: a tent cluster behind the garages, plus the timing dish. It is
## what a paddock looks like from the grandstand: awnings, trailers and a dish.
static func _paddock(holder: Node3D, spline: RefCounted, plan: Dictionary,
		stats: Dictionary) -> void:
	var inside: float = float(plan["inside"])
	var run: Dictionary = _pit_run(plan)
	var from: float = float(run["from"])
	var length: float = maxf(float(run["to"]) - from, BAY)
	var tents: Dictionary = {}
	var body := Props.body(holder, "Paddock")
	var kinds: Array[String] = [TENT, TENT_CLOSED, TENT_LONG, TENT, TENT_ROOF,
		TENT_CLOSED]
	for index in TENTS:
		var lap: float = from + length * (0.06 + 0.40 * float(index)
			/ float(maxi(TENTS - 1, 1)))
		var row: float = PADDOCK_LATERAL + PADDOCK_SPREAD \
			* float(index % 2)
		var point: Vector3 = Props.deck_point(spline, lap, row * inside)
		if not Props.site_ok(spline, point, 11.4):
			continue
		var yaw: float = Props.along_yaw(spline, lap) + PI
		var model: String = kinds[index % kinds.size()]
		if not tents.has(model):
			tents[model] = []
		(tents[model] as Array).append(Props.fit(model, point, yaw,
			Vector3.ONE * Props.PROP_SCALE))
		Props.model_body(body, model, point, yaw,
			Vector3.ONE * Props.PROP_SCALE)
		stats["paddock"] = int(stats.get("paddock", 0)) + 1
	for model: String in tents:
		stats["draws"] = int(stats.get("draws", 0)) + Props.batch(holder,
			model, tents[model] as Array, "Paddock_" + model, true)
	var dish_point: Vector3 = Props.deck_point(spline,
		from + length * 0.5, (PADDOCK_LATERAL - 8.0) * inside)
	if not Props.site_ok(spline, dish_point, 5.0):
		if body.get_child_count() == 0:
			body.free()
		return
	var dish_yaw: float = Props.face_track_yaw(spline, dish_point)
	var dish: Array = [Props.fit(TIMING, dish_point, dish_yaw,
		Vector3.ONE * Props.PROP_SCALE)]
	Props.model_body(body, TIMING, dish_point, dish_yaw,
		Vector3.ONE * Props.PROP_SCALE)
	stats["draws"] = int(stats.get("draws", 0)) \
		+ Props.batch(holder, TIMING, dish, "PaddockTiming", true)
