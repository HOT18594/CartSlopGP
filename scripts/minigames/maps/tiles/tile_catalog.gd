extends RefCounted
## Modular tile library for the tile-based race maps.
##
## A tile is one unit of track: it owns a footprint on the 26 m cell lattice,
## an entry point, an exit point, the quarter-turn heading change between them
## and the local centreline polyline that joins them. TileLayout places tiles by
## grid cell plus rotation and concatenates those polylines into the single
## closed centreline the race controller, the bots and the server contract all
## sample.
##
## Every tile's local frame has its entry at (-CELL/2, 0) heading +X, so a chain
## only has to add the rotated exit point to the running entry. Path points are
## Vector3: x/z are the plan position in metres, y is the tile's local height
## bump (a jump crest; zero everywhere else).
##
## Tiles declare their road surface (normal / wet / ice), how wide the road is
## at each end and which decoration hooks they own. TileRoad and TileFurniture
## read that data; no tile builds nodes itself, which keeps the library cheap to
## unit-test and impossible to leak into the scene graph.

const CELL: float = 26.0
const HALF_CELL: float = CELL * 0.5
## Mirrors grass_race.ROAD_HALF and RaceAI's racing width.
const ROAD_HALF: float = 5.5
const ROAD_Y: float = 0.04
## Target spacing of the generated centreline, in metres.
const SAMPLE_STEP: float = 2.0

const TILE_STRAIGHT: String = "straight"
const TILE_LONG: String = "long"
const TILE_CORNER: String = "corner"
const TILE_SWEEPER: String = "sweeper"
const TILE_CHICANE: String = "chicane"
const TILE_HAIRPIN: String = "hairpin"
const TILE_SPLIT: String = "split"
const TILE_JUMP: String = "jump"
const TILE_START: String = "start"
const TILE_PIT: String = "pit"

## Tile ids in library order. Used by the menu/diagnostics, never by gameplay.
const TILE_IDS: PackedStringArray = [
	TILE_STRAIGHT, TILE_LONG, TILE_CORNER, TILE_SWEEPER, TILE_CHICANE,
	TILE_HAIRPIN, TILE_SPLIT, TILE_JUMP, TILE_START, TILE_PIT,
]

static var _defs: Dictionary = {}


## Every tile definition keyed by id. Built once, then shared.
static func defs() -> Dictionary:
	if not _defs.is_empty():
		return _defs
	_defs = {
		TILE_STRAIGHT: _make(TILE_STRAIGHT, "STRAIGHT", Vector2i(1, 1),
			_line(-HALF_CELL, 0.0, HALF_CELL, 0.0, 8), Vector2(HALF_CELL, 0.0),
			0, 5.5, PackedStringArray(["billboard"])),
		TILE_LONG: _make(TILE_LONG, "LONG STRAIGHT", Vector2i(2, 1),
			_line(-HALF_CELL, 0.0, 3.0 * HALF_CELL, 0.0, 18),
			Vector2(3.0 * HALF_CELL, 0.0), 0, 5.5,
			PackedStringArray(["billboard", "floodlight"])),
		TILE_CORNER: _make(TILE_CORNER, "90 CORNER", Vector2i(1, 1),
			_arc(-HALF_CELL, HALF_CELL, HALF_CELL, -PI * 0.5, 0.0, 14),
			Vector2(0.0, HALF_CELL), 1, 5.5,
			PackedStringArray(["tyres", "marshal"])),
		TILE_SWEEPER: _make(TILE_SWEEPER, "WIDE SWEEPER", Vector2i(2, 2),
			_arc(-HALF_CELL, 3.0 * HALF_CELL, 3.0 * HALF_CELL, -PI * 0.5, 0.0, 30),
			Vector2(2.0 * HALF_CELL, 3.0 * HALF_CELL), 1, 5.5,
			PackedStringArray(["tyres", "marshal", "floodlight"])),
		TILE_CHICANE: _make(TILE_CHICANE, "CHICANE", Vector2i(2, 1),
			_chicane(4.0 * HALF_CELL, 3.2, 34), Vector2(3.0 * HALF_CELL, 0.0), 0,
			5.5, PackedStringArray(["billboard", "tyres"])),
		TILE_HAIRPIN: _make(TILE_HAIRPIN, "HAIRPIN", Vector2i(1, 1),
			_arc(-HALF_CELL, HALF_CELL, HALF_CELL, -PI * 0.5, PI * 0.5, 34),
			Vector2(-HALF_CELL, 2.0 * HALF_CELL), 2, 5.5,
			PackedStringArray(["tyres", "marshal"])),
		TILE_SPLIT: _make(TILE_SPLIT, "SPLIT / MERGE", Vector2i(2, 1),
			_line(-HALF_CELL, 0.0, 3.0 * HALF_CELL, 0.0, 18),
			Vector2(3.0 * HALF_CELL, 0.0), 0, 5.5,
			PackedStringArray(["split", "billboard"])),
		TILE_JUMP: _make(TILE_JUMP, "JUMP STRAIGHT", Vector2i(2, 1),
			_jump(4.0 * HALF_CELL, 1.95, 36), Vector2(3.0 * HALF_CELL, 0.0), 0,
			5.5, PackedStringArray(["jump", "floodlight"])),
		TILE_START: _make(TILE_START, "START / FINISH", Vector2i(1, 1),
			_line(-HALF_CELL, 0.0, HALF_CELL, 0.0, 8), Vector2(HALF_CELL, 0.0),
			0, 5.5, PackedStringArray(["start", "billboard"])),
		TILE_PIT: _make(TILE_PIT, "PIT STRAIGHT", Vector2i(2, 1),
			_line(-HALF_CELL, 0.0, 3.0 * HALF_CELL, 0.0, 18),
			Vector2(3.0 * HALF_CELL, 0.0), 0, 5.5,
			PackedStringArray(["pit", "floodlight", "marshal"])),
	}
	return _defs


static func _make(id: String, display: String, footprint: Vector2i,
		path: PackedVector3Array, exit: Vector2, turn: int, width: float,
		hooks: PackedStringArray) -> Dictionary:
	var length: float = 0.0
	for i in range(1, path.size()):
		length += Vector2(path[i].x - path[i - 1].x,
			path[i].z - path[i - 1].z).length()
	return {
		"id": id,
		"name": display,
		"footprint": footprint,
		"path": path,
		"exit": exit,
		"turn": turn,
		"length": length,
		"width": width,
		"surface": "normal",
		"hooks": hooks,
		"jump": id == TILE_JUMP,
		"split": id == TILE_SPLIT,
		"pit_side": 1.0,
	}


## Definition for `id`, or the plain straight when the id is unknown.
static func get_tile(id: String) -> Dictionary:
	var all: Dictionary = defs()
	if all.has(id):
		return all[id]
	return all[TILE_STRAIGHT]


## True when `id` names a tile in the library.
static func has_tile(id: String) -> bool:
	return defs().has(id)


## The left-hand variant of a right-hand tile: mirrored in local Z, with the
## exit turn reflected. The footprint is unchanged.
static func mirrored(tile: Dictionary) -> Dictionary:
	var path: PackedVector3Array = tile["path"] as PackedVector3Array
	var out := PackedVector3Array()
	out.resize(path.size())
	for i in path.size():
		out[i] = Vector3(path[i].x, path[i].y, -path[i].z)
	var exit: Vector2 = tile["exit"] as Vector2
	var copy: Dictionary = tile.duplicate(true)
	copy["path"] = out
	copy["exit"] = Vector2(exit.x, -exit.y)
	copy["turn"] = (4 - int(tile["turn"])) % 4
	copy["mirrored"] = true
	return copy


## Rotation of a plan-space point by `quarter_turns` counter-clockwise steps.
static func rotated(point: Vector2, quarter_turns: int) -> Vector2:
	var x: float = point.x
	var z: float = point.y
	for _i in posmod(quarter_turns, 4):
		var next_x: float = -z
		z = x
		x = next_x
	return Vector2(x, z)


## Half width of a tile's road at local fraction `t` in 0..1. A split tile
## widens to 9.5 m either side of the centreline so the two painted islands
## have a lane on each side; every other tile stays at ROAD_HALF.
static func half_width_at(tile: Dictionary, t: float) -> float:
	if not bool(tile.get("split", false)):
		return float(tile["width"])
	var ramp: float = smoothstep(0.0, 0.16, t) * (1.0 - smoothstep(0.84, 1.0, t))
	return float(tile["width"]) + 4.0 * ramp


## Local height bump at `t` in 0..1 for a tile. Only the jump tile carries one;
## every other tile returns 0.0, which is what keeps tile joints seamless.
static func bump_at(tile: Dictionary, t: float) -> float:
	if not bool(tile.get("jump", false)):
		return 0.0
	var path: PackedVector3Array = tile["path"] as PackedVector3Array
	if path.size() < 2:
		return 0.0
	var scaled: float = clampf(t, 0.0, 1.0) * float(path.size() - 1)
	var index: int = clampi(int(floor(scaled)), 0, path.size() - 2)
	var local: float = scaled - float(index)
	return lerpf(path[index].y, path[index + 1].y, local)


# --------------------------------------------------------------------------
# path generators


static func _line(x0: float, z0: float, x1: float, z1: float,
		count: int) -> PackedVector3Array:
	var points := PackedVector3Array()
	var steps: int = maxi(count, 1)
	for i in steps + 1:
		var t: float = float(i) / float(steps)
		points.append(Vector3(lerpf(x0, x1, t), 0.0, lerpf(z0, z1, t)))
	return points


static func _arc(cx: float, cz: float, radius: float, from_angle: float,
		to_angle: float, count: int) -> PackedVector3Array:
	var points := PackedVector3Array()
	var steps: int = maxi(count, 2)
	for i in steps + 1:
		var angle: float = lerpf(from_angle, to_angle, float(i) / float(steps))
		points.append(Vector3(cx + radius * cos(angle), 0.0,
			cz + radius * sin(angle)))
	return points


## S-shaped lane change that starts and ends exactly on the centreline with a
## zero heading change, so it joins a straight tile without a kink.
static func _chicane(length: float, amplitude: float,
		count: int) -> PackedVector3Array:
	var points := PackedVector3Array()
	var steps: int = maxi(count, 4)
	for i in steps + 1:
		var t: float = float(i) / float(steps)
		var envelope: float = smoothstep(0.0, 0.20, t) \
			* (1.0 - smoothstep(0.80, 1.0, t))
		var z: float = amplitude * sin(TAU * t) * envelope
		points.append(Vector3(-HALF_CELL + length * t, 0.0, z))
	return points


## Straight with a kicker: a ramp, a short flat crest and a landing slope. The
## bump returns to zero inside the tile so the next tile's road lines up.
static func _jump(length: float, height: float,
		count: int) -> PackedVector3Array:
	var points := PackedVector3Array()
	var steps: int = maxi(count, 8)
	var ramp_in: float = 0.16
	var crest_in: float = 0.34
	var crest_out: float = 0.52
	var ramp_out: float = 0.76
	for i in steps + 1:
		var t: float = float(i) / float(steps)
		var bump: float = 0.0
		if t >= ramp_in and t < crest_in:
			bump = height * smoothstep(ramp_in, crest_in, t)
		elif t >= crest_in and t <= crest_out:
			bump = height
		elif t > crest_out and t <= ramp_out:
			bump = height * (1.0 - smoothstep(crest_out, ramp_out, t))
		points.append(Vector3(-HALF_CELL + length * t, bump, 0.0))
	return points
