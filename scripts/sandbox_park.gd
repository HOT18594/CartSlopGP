extends Node3D
## Cartoon TEST FACILITY for the sandbox, rebuilt on the Kenney 16 m tile grid.
##
## The facility is authored around ONE axis: the start grid faces -Z, straight
## down the paddock, through the pit gate and onto the handling loop's first
## tile. Everything that faces the player is placed against that axis:
##   - behind the grid (+Z): a raised spectator terrace with the covered
##     grandstand on it, flanked by the park's south fence;
##   - west of the grid: the pit block, its open bays facing the service-yard
##     pit lane, with the kit tents parked behind the block;
##   - in front (-Z): the tarmac link, the pit gate and the loop's armco;
##   - east: the skidpad, now reached over the terrace's drive-up ramp.
## `_audit_facility` prints the spawn transform and the loop's first tile each
## boot and errors if the two ever disagree again (they are read from the live
## scene's SpawnPoint marker, not from a copy of the numbers).
##
## The five zones keep the destinations the sandbox bots already drive to:
##   - PADDOCK: painted apron, six grid slots (the multiplayer contract),
##     four enterable pit-garage bays, the raised terrace with the covered
##     grandstand, the pit lane service yard (cone line, tents behind the
##     block) and the pit gate's banner towers.
##   - HANDLING LOOP: a five-by-three grid oval of roadStraight/roadCornerSmall
##     pieces, 178 m of cartoon tarmac, a checkered start band at the pit gate
##     and a red barrier ring with one 16 m gate - the armco the bots expect.
##   - SKIDPAD: a 28 m painted circle inscribed in a 2x2 tile concrete pad.
##   - JUMP LANE: a full-tile roadRamp and a two-cell roadRampLong in one line,
##     with a checkered launch band.
##   - OFF-ROAD: a dirt block with the cone slalom, the lower-grip zone and a
##     grass berm on the outfield beside it.
##
## The racing kit ships no trailer, so the service yard is dressed with the kit's
## own tents and cones instead, and every kit unit is scaled by PROP_SCALE (16 m)
## rather than by raw model units.
##
## The ground is ONE flat collision slab. Kit road pieces carry their own thin
## WORLD colliders (flush with the visible deck); ramps get convex wedges that
## match the slope. Every barrier, building, light, flag, billboard, tent, tyre
## stack and tree the kit adds is solid on CollisionLayers.WORLD, and every
## solid carries a real shape instead of trusting the GLB (the Kenney exports
## ship without colliders).
##
## Clearance is an invariant, not a suggestion. The perimeter wall and the loop
## armco are both placed by TileKit.barrier_line, which walks the true road edge
## and asserts BARRIER_CLEARANCE; `_audit_clearance` then measures every solid
## collider sample against the loop centreline and the jump lane and errors if
## anything reaches the tarmac.
##
## Pushables keep the "pushable" group and the PROP/SOLID_PROP layers sandbox.gd
## syncs. The dirt Area3D keeps the `surface_grip` contract (lower grip on dirt,
## restored on exit) and now excludes the raised terrace.

const TileKit := preload("res://scripts/minigames/tile_kit.gd")
const TileCatalog := preload("res://scripts/minigames/tiles/tile_catalog.gd")
const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")
const BOOST_PAD_SCENE := preload("res://scenes/track/boost_pad.tscn")
const PYLON_SCENE := preload("res://assets/models/kenney_racing_kit/Models/GLTF format/pylon.glb")
const CRATE_SCENE := preload("res://assets/models/kenney_car-kit/Models/GLB format/box.glb")
const TITLE_FONT_RES: Font = preload("res://assets/ui/fonts/LuckiestGuy-Regular.ttf")

# Grid. TILE is the race maps' measured 16 m module.
const TILE: float = TileCatalog.TILE_SIZE
const HALF_TILE: float = TILE * 0.5
const ROAD_TOP: float = 0.045
const ZONE_Y: float = 0.015
const PAINT_Y: float = 0.03

# World boundary: barriers stand outside the expanded +/-72 m perimeter.
const FIELD: float = 80.0
const BARRIER_IN: float = 8.0
const PERIMETER_HALF: float = FIELD - BARRIER_IN
const CORNER_RADIUS: float = 16.0
const ENTRY_GAP: float = 16.0

# Authored spawn: grid slot 5 (index 4), facing -Z. sandbox.tscn's SpawnPoint is
# the single source of truth; this mirrors it for tooling and cold builds.
const SPAWN_POINT := Vector3(0.0, 0.25, 13.0)
# Loop entry: the pit gate. sandbox_bot.gd drives to the same plan point
# (LOOP_GATE) and expects the only opening in the loop's armco to be here.
const LOOP_GATE := Vector2(0.0, -6.0)
const LOOP_GATE_WIDTH: float = 16.0

# Zone rectangles in world x/z, every edge a multiple of the 16 m tile.
const PADDOCK := Rect2(-32.0, -16.0, 64.0, 32.0)
const YARD := Rect2(-48.0, -12.0, 32.0, 12.0)

# Pit garages: two open kit pitsGarage modules on the paddock's west edge.
# The GLB measures 1.00 x 0.70 x 1.09 model units, so at PROP_SCALE each module
# is 16 m wide, 11.2 m tall and 17.44 m deep. A ray scan of the open facade
# gives two 0.3728-unit bays (5.965 m) either side of a 0.0848-unit centre pier
# (1.357 m) and 0.0848-unit side walls. The kit opens toward +Z; PI turns the
# bays onto the service yard instead of the dirt at the paddock's south edge.
const PIT_GARAGE_CELLS: Array[Vector2i] = [Vector2i(-3, 0), Vector2i(-2, 0)]
const PIT_GARAGE_YAW: float = PI
const GARAGE_HALF_WIDTH: float = 8.0
const GARAGE_HALF_DEPTH: float = 8.72
## The facade is 1.44 m behind the roof lip, the kit's own front overhang.
const GARAGE_FACADE_INSET: float = 7.28
const GARAGE_WALL: float = 1.357
const GARAGE_PIER_HALF: float = 0.678
const GARAGE_BAY_OUTER: float = 6.643
const GARAGE_BAY_WIDTH: float = GARAGE_BAY_OUTER - GARAGE_PIER_HALF
const GARAGE_HEIGHT: float = 11.2
## Lintel underside measured at 0.385 model units: a cart passes under it.
const GARAGE_OPENING_TOP: float = 6.16
const GARAGE_ROOF_UNDERSIDE: float = 10.4
## Clearance contract. The cart's collision profile is 1.50 m wide
## (player_cart.gd) and its largest push envelope is 2.0 m
## (cart_player.tscn), so every bay must stay 2.5 x 2.0 = 5.0 m clear.
const CART_BODY_WIDTH: float = 2.0
const BAY_MIN_CLEARANCE: float = CART_BODY_WIDTH * 2.5
const SKID_BLOCK := Rect2(32.0, -4.0, 38.0, 40.0)
const SKID_CENTRE := Vector2(48.0, 16.0)
const SKID_RADIUS: float = 14.5
const DIRT := Rect2(-32.0, 16.0, 64.0, 52.0)
const DIRT_GRIP: float = 0.72

# Raised spectator terrace behind the start grid, with a drive-up ramp on its
# skidpad side. It is the park's "raised pad" elevation feature.
const RAISED_PAD := Rect2(12.0, 16.0, 20.0, 14.0)
const PAD_TOP: float = 0.7
const PAD_RAMP: float = 2.0
# Covered grandstand on the terrace, facing the grid (-Z).
const STAND_CELL := Vector2(22.0, 23.0)
const STAND_SCALE: float = 0.8
# Grass berm in the south-east outfield, the park's small hill.
const BERM_CENTRE := Vector2(44.0, 52.0)
const BERM_RADIUS: float = 7.0
const BERM_HEIGHT: float = 1.55

# Handling loop: 5 x 3 ring of 16 m cells centred on the old lap centre. The ring
# starts at the paddock-side straight so LOOP_RING[0] IS the start/finish tile,
# and it runs +X (the direction a kart turns onto when it leaves the pit gate).
const LOOP_CELL_X: float = -32.0
const LOOP_CELL_Z: float = -54.0
const LOOP_CENTRE := Vector2(0.0, -38.0)
const LOOP_RING: Array[Vector2i] = [
	Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(4, 1),
	Vector2i(4, 0), Vector2i(3, 0), Vector2i(2, 0), Vector2i(1, 0),
	Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2),
]
## Loop AABB grown by this much: outside it a prop is provably clear, so the
## clearance audit can skip the spline walk.
const LOOP_AUDIT_PAD: float = 14.0

# Jump lane: one tile wide, centred on the bots' staging line at x = -56,
# extended across the expanded 72 m park with boost strips and twin kickers.
const JUMP_X: float = -56.0
const JUMP_LANE_Z0: float = 56.0
const JUMP_LANE_Z1: float = -56.0
const JUMP_PIECES: Array[Dictionary] = [
	{"model": "roadStraight", "z": 56.0, "flat": true, "yscale": 1.0},
	{"model": "roadStraight", "z": 40.0, "flat": true, "yscale": 1.0},
	{"model": "roadRamp", "z": 24.0, "flat": false, "yscale": 0.65},
	{"model": "roadStraight", "z": 8.0, "flat": true, "yscale": 1.0},
	{"model": "roadStraight", "z": -8.0, "flat": true, "yscale": 1.0},
	{"model": "roadRamp", "z": -24.0, "flat": false, "yscale": 0.78},
	{"model": "roadStraight", "z": -40.0, "flat": true, "yscale": 1.0},
	{"model": "roadStraight", "z": -56.0, "flat": true, "yscale": 1.0},
]

# The multiplayer grid contract: sandbox.gd mirrors these centres and parks the
# local cart on slot 5 (index 4) at (0, 13). They are a 9 m minor lattice inside
# the paddock, deliberately kept so grid slots and spawns agree.
const GRID_SLOTS: Array[Vector2] = [
	Vector2(-9.0, 5.0), Vector2(0.0, 5.0), Vector2(9.0, 5.0),
	Vector2(-9.0, 13.0), Vector2(0.0, 13.0), Vector2(9.0, 13.0),
]
const GRID_HALF := Vector2(2.1, 2.7)

# Clearance audit. A solid may never come inside SOLID_LIMIT of a racing
# centreline; the kit's own run-off furniture (tyre stacks at ROAD_HALF + 2 m)
# is reported separately as "tight" rather than as a failure.
const SOLID_LIMIT: float = TileCatalog.ROAD_HALF + 1.0
## Bodies that ARE the racing surface, so they are not audited against it.
const SOLID_SKIP: Array[String] = [
	"GroundPlane", "LoopRoadCollision", "JumpLaneCollision",
]
## Static cones in the service yard use the same cartoon cone as the pushables.
const CONE_SCALE: float = TILE * 0.45

# Cartoon palette. Flat vertex colours only: no scans, no normal maps.
const GRASS_A := Color("7bd34f")
const GRASS_B := Color("6cc143")
const OUTFIELD := Color("58ab3f")
const APRON := Color("f4ead2")
const PIT_PAD_TINT := Color("d9d2c0")
const CONCRETE := Color("c9d3d8")
const PAD_CONCRETE := Color("c8c3b6")
const PAD_WALL := Color("a8a294")
const SKID_TARMAC := Color("3f9fd1")
const DIRT_TAN := Color("d9a066")
const DIRT_ALT := Color("caa06b")
const TARMAC := Color("4a4e69")
const PAINT_CREAM := Color("fff6e3")
const PAINT_YELLOW := Color("ffd22e")
const PAINT_PINK := Color("f26ca7")
const PAINT_BLUE := Color("45b6f0")
const PAINT_ORANGE := Color("ff9f45")
const PAINT_DARK := Color("1e1b3a")


## One merged, flat pavement or paint layer.
##
## Every triangle is forced to face up, so a zone builder never has to reason
## about winding: it hands over points and gets a drivable slab back. All pieces
## for one surface share this buffer, which is why the whole ground and every
## painted zone cost one draw call each.
##
## "Face up" means the Godot front face, and Godot's front faces are CLOCKWISE
## seen from the front. An up-facing triangle therefore has its right-hand cross
## product pointing DOWN (-Y); the engine's own primitives agree (a PlaneMesh's
## up faces have cross.y < 0). Winding them the other way passes the boot audits
## but is back-face culled by every camera above the park, so the whole layer
## silently disappears and the sky's ground colour shows through instead.
class SurfaceBuf:
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()

	## Adds one up-facing triangle, re-winding it when the front face points
	## down instead of up (Godot front faces are clockwise from the front, so
	## an up-facing triangle's right-hand normal is -Y).
	func tri(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
		if (b - a).cross(c - a).y > 0.0:
			var swap: Vector3 = b
			b = c
			c = swap
		var base: int = verts.size()
		for point: Vector3 in [a, b, c]:
			verts.append(point)
			normals.append(Vector3.UP)
			colors.append(color)
		indices.append(base)
		indices.append(base + 1)
		indices.append(base + 2)

	## Adds one up-facing quad as two triangles.
	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3,
			color: Color) -> void:
		tri(a, b, c, color)
		tri(a, c, d, color)

	## Adds an axis-aligned rectangle at height `y`.
	func rect(area: Rect2, y: float, color: Color) -> void:
		var x0: float = area.position.x
		var z0: float = area.position.y
		var x1: float = area.end.x
		var z1: float = area.end.y
		quad(Vector3(x0, y, z0), Vector3(x0, y, z1), Vector3(x1, y, z1),
			Vector3(x1, y, z0), color)

	## Adds a filled circle at height `y`.
	func disc(centre: Vector2, radius: float, segments: int, y: float,
			color: Color) -> void:
		var count: int = maxi(segments, 8)
		for i in count:
			var a0: float = TAU * float(i) / float(count)
			var a1: float = TAU * float(i + 1) / float(count)
			tri(Vector3(centre.x, y, centre.y),
				Vector3(centre.x + cos(a0) * radius, y,
					centre.y + sin(a0) * radius),
				Vector3(centre.x + cos(a1) * radius, y,
					centre.y + sin(a1) * radius), color)

	## Adds a flat annulus at height `y`.
	func ring(centre: Vector2, r_in: float, r_out: float, segments: int,
			y: float, color: Color) -> void:
		arc(centre, r_in, r_out, 0.0, TAU, segments, y, color)

	## Adds a flat annular arc from `from_angle` to `to_angle`, in radians.
	func arc(centre: Vector2, r_in: float, r_out: float, from_angle: float,
			to_angle: float, segments: int, y: float, color: Color) -> void:
		var count: int = maxi(segments, 2)
		for i in count:
			var a0: float = lerpf(from_angle, to_angle,
				float(i) / float(count))
			var a1: float = lerpf(from_angle, to_angle,
				float(i + 1) / float(count))
			var c0: float = cos(a0)
			var s0: float = sin(a0)
			var c1: float = cos(a1)
			var s1: float = sin(a1)
			quad(Vector3(centre.x + c0 * r_in, y, centre.y + s0 * r_in),
				Vector3(centre.x + c0 * r_out, y, centre.y + s0 * r_out),
				Vector3(centre.x + c1 * r_out, y, centre.y + s1 * r_out),
				Vector3(centre.x + c1 * r_in, y, centre.y + s1 * r_in), color)

	## Adds a flat line of `width` metres between two ground points.
	func line(from: Vector2, to: Vector2, width: float, y: float,
			color: Color) -> void:
		var direction: Vector2 = to - from
		if direction.length_squared() < 0.000001:
			return
		direction = direction.normalized()
		var offset: Vector2 = Vector2(-direction.y, direction.x) * (width * 0.5)
		quad(Vector3(from.x - offset.x, y, from.y - offset.y),
			Vector3(from.x + offset.x, y, from.y + offset.y),
			Vector3(to.x + offset.x, y, to.y + offset.y),
			Vector3(to.x - offset.x, y, to.y - offset.y), color)

	## Adds the four sides of a rectangle in one colour.
	func outline(area: Rect2, width: float, y: float, color: Color) -> void:
		var a: Vector2 = area.position
		var b := Vector2(area.end.x, area.position.y)
		var c: Vector2 = area.end
		var d := Vector2(area.position.x, area.end.y)
		line(a, b, width, y, color)
		line(b, c, width, y, color)
		line(c, d, width, y, color)
		line(d, a, width, y, color)


## One merged, solid vertex-colour layer for raised terrain (the spectator
## terrace, its ramp and the berm).
##
## Unlike SurfaceBuf this keeps real slopes: every triangle carries the normal
## its vertices produce, and each quad is wound so its Godot front face points
## along the outward direction the builder names. That is what makes a berm read
## as a hill instead of as flat paint.
##
## Same convention as SurfaceBuf: a Godot front face is clockwise seen from the
## front, so its right-hand cross product points AWAY from the viewer, i.e. into
## the solid. Lighting normals are therefore the negated cross product.
class SolidBuf:
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()

	## Adds one quad, re-wound until its Godot front face points along `outward`.
	func face(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color,
			outward: Vector3) -> void:
		var normal: Vector3 = (b - a).cross(c - a)
		if normal.dot(outward) > 0.0:
			var swap: Vector3 = b
			b = d
			d = swap
		_triangle(a, b, c, color)
		_triangle(a, c, d, color)

	## Adds one triangle whose front face points along `outward`.
	func tri_face(a: Vector3, b: Vector3, c: Vector3, color: Color,
			outward: Vector3) -> void:
		if (b - a).cross(c - a).dot(outward) > 0.0:
			var swap: Vector3 = b
			b = c
			c = swap
		_triangle(a, b, c, color)

	## Appends a shaded triangle from its own surface normal.
	func _triangle(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
		# The right-hand cross product points into the solid for a clockwise
		# (Godot front-facing) winding, so the visible side's normal is its
		# negation.
		var normal: Vector3 = -(b - a).cross(c - a)
		normal = normal.normalized() if normal.length_squared() > 0.0000001 \
			else Vector3.UP
		var base: int = verts.size()
		for point: Vector3 in [a, b, c]:
			verts.append(point)
			normals.append(normal)
			colors.append(color)
		indices.append(base)
		indices.append(base + 1)
		indices.append(base + 2)


## Closed polyline with the small spline surface the dressing helpers need
## (`total_length`, `sample`, `closest`). Distances are metres, the y is 0.
class RingSpline:
	extends RefCounted

	var points: PackedVector3Array = PackedVector3Array()
	var cumulative: PackedFloat32Array = PackedFloat32Array()
	var total_length: float = 0.0
	var _count: int = 0

	func _init(path: PackedVector3Array) -> void:
		points = path
		_count = points.size()
		if _count < 2:
			return
		cumulative.resize(_count)
		var travelled: float = 0.0
		for i in _count:
			cumulative[i] = travelled
			travelled += points[i].distance_to(points[(i + 1) % _count])
		total_length = travelled

	## Returns {position, forward, right} at arc length `distance`.
	func sample(distance: float) -> Dictionary:
		if _count < 2:
			return {"position": Vector3.ZERO, "forward": Vector3.FORWARD,
				"right": Vector3.RIGHT}
		var s: float = fposmod(distance, maxf(total_length, 0.001))
		var index: int = _segment_at(s)
		var next: int = (index + 1) % _count
		var seg_start: float = cumulative[index]
		var seg_length: float = total_length - seg_start if next == 0 \
			else cumulative[next] - seg_start
		var t: float = clampf((s - seg_start) / maxf(seg_length, 0.0001), 0.0, 1.0)
		var a: Vector3 = points[index]
		var b: Vector3 = points[next]
		var forward: Vector3 = (b - a).normalized()
		return {"position": a.lerp(b, t), "forward": forward,
			"right": forward.cross(Vector3.UP).normalized()}

	## Nearest point on the polyline. Returns {s, distance, point}.
	func closest(world_position: Vector3) -> Dictionary:
		var best_sq: float = INF
		var best_s: float = 0.0
		var best_point: Vector3 = Vector3.ZERO
		for i in _count:
			var a: Vector3 = points[i]
			var b: Vector3 = points[(i + 1) % _count]
			var ab: Vector3 = b - a
			var length_sq: float = ab.length_squared()
			var t: float = 0.0
			if length_sq > 0.000001:
				t = clampf((world_position - a).dot(ab) / length_sq, 0.0, 1.0)
			var candidate: Vector3 = a + ab * t
			var d_sq: float = world_position.distance_squared_to(candidate)
			if d_sq < best_sq:
				best_sq = d_sq
				best_point = candidate
				best_s = fposmod(cumulative[i] + sqrt(length_sq) * t,
					maxf(total_length, 0.001))
		return {"s": best_s, "distance": sqrt(best_sq), "point": best_point}

	func _segment_at(s: float) -> int:
		var low: int = 0
		var high: int = _count - 1
		while low < high:
			var mid: int = (low + high + 1) / 2
			if cumulative[mid] <= s:
				low = mid
			else:
				high = mid - 1
		return low


var _rng := RandomNumberGenerator.new()
var _font: Font

var _ground: SurfaceBuf = SurfaceBuf.new()
var _paint: SurfaceBuf = SurfaceBuf.new()
var _solid: SolidBuf = SolidBuf.new()
var _loop_spline: RingSpline
var _perimeter_spline: RingSpline
var _perimeter_barriers: Node3D
var _loop_barriers: Node3D
var _vertex_mat: StandardMaterial3D
var _prop_material: PhysicsMaterial
var _grip_before: Dictionary = {}
var _dirt_rects: Array[Rect2] = []
var _flat_materials: Dictionary = {}


func _ready() -> void:
	_rng.seed = 90421
	_font = TITLE_FONT_RES
	_vertex_mat = _make_vertex_material()
	_ground_plane()
	_zone_paint()
	_raised_pad()
	_drift_bowl()
	_berm()
	_paddock()
	_handling_loop()
	_jump_lane()
	_dressing()
	_zone_signs()
	_pushable_props()
	_grip_zone()
	_commit_layers()
	_audit_facility()
	preload("res://scripts/minigames/scenery/ambient_world.gd").build_arena(self, "sandbox", 112.0)
	if OS.get_environment("CART_DEBUG_PARK") == "1":
		_report_stats()
		_bot_probe.call_deferred()


# --------------------------------------------------------------------------
# materials and flat surfaces


## One shared, unlit-looking vertex-colour material for ground, paint and props.
func _make_vertex_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return mat


## Flat two-tone grass checker over the park and a matching outfield apron.
## This is the one ground mesh and the one flat collision plane.
func _ground_plane() -> void:
	var cell: float = 8.0
	for ix in 28:
		for iz in 28:
			var tint: Color = GRASS_A if (ix + iz) % 2 == 0 else GRASS_B
			_ground.rect(Rect2(-112.0 + float(ix) * cell,
				-112.0 + float(iz) * cell, cell, cell), 0.0, tint)
	var outer: float = 600.0
	var inner: float = 112.0
	_ground.rect(Rect2(-outer, -outer, outer * 2.0, outer - inner), -0.02,
		OUTFIELD)
	_ground.rect(Rect2(-outer, inner, outer * 2.0, outer - inner), -0.02,
		OUTFIELD)
	_ground.rect(Rect2(-outer, -inner, outer - inner, inner * 2.0), -0.02,
		OUTFIELD)
	_ground.rect(Rect2(inner, -inner, outer - inner, inner * 2.0), -0.02,
		OUTFIELD)
	var body := StaticBody3D.new()
	body.name = "GroundPlane"
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = 0
	var box := BoxShape3D.new()
	box.size = Vector3(outer * 2.0, 2.0, outer * 2.0)
	var collision := CollisionShape3D.new()
	collision.shape = box
	collision.position = Vector3(0.0, -1.0, 0.0)
	body.add_child(collision)
	add_child(body)


## Painted zones: paddock apron, service yard, skid block, dirt block, the pit
## gate lane and the terrace base.
func _zone_paint() -> void:
	# Paddock apron and its bold outline.
	_paint.rect(PADDOCK, ZONE_Y, APRON)
	_paint.outline(PADDOCK.grow(-0.9), 0.5, PAINT_Y, PAINT_DARK)
	_paint.outline(PADDOCK.grow(-1.8), 0.22, PAINT_Y, PAINT_YELLOW)
	# Service yard in front of the pit block, west of the paddock.
	_paint.rect(YARD, ZONE_Y + 0.002, PIT_PAD_TINT)
	_paint.outline(YARD.grow(-0.7), 0.4, PAINT_Y + 0.002, PAINT_YELLOW)
	# Pit gate lane: apron -> gate -> loop's first tile. This is the one line the
	# player's spawn points down.
	_paint.rect(Rect2(-9.0, -14.0, 18.0, 14.0), ZONE_Y + 0.004, TARMAC)
	_paint.line(Vector2(-8.6, -1.0), Vector2(-8.6, -13.0), 0.26,
		PAINT_Y + 0.004, PAINT_BLUE)
	_paint.line(Vector2(8.6, -1.0), Vector2(8.6, -13.0), 0.26,
		PAINT_Y + 0.004, PAINT_BLUE)
	for chevron in 3:
		var z: float = -4.5 - float(chevron) * 3.0
		_paint.line(Vector2(-4.0, z + 1.6), Vector2(0.0, z), 0.34,
			PAINT_Y + 0.004, PAINT_CREAM)
		_paint.line(Vector2(4.0, z + 1.6), Vector2(0.0, z), 0.34,
			PAINT_Y + 0.004, PAINT_CREAM)
	# Checkered start line on the apron, right in front of the grid.
	for i in 16:
		var shade: Color = PAINT_CREAM if i % 2 == 0 else PAINT_DARK
		_paint.rect(Rect2(-9.0 + float(i) * 1.125, -0.6, 1.125, 1.2),
			PAINT_Y + 0.005, shade)
	# Terrace base outline under the raised pad.
	_paint.outline(Rect2(RAISED_PAD.position - Vector2(1.2, 1.2),
		RAISED_PAD.size + Vector2(2.4, 2.4)), 0.3, PAINT_Y, PAINT_YELLOW)
	# Skid block: concrete pad with the painted 28 m circle.
	_paint.rect(SKID_BLOCK, ZONE_Y + 0.003, CONCRETE)
	_paint.disc(SKID_CENTRE, SKID_RADIUS, 64, ZONE_Y + 0.008, SKID_TARMAC)
	_paint.ring(SKID_CENTRE, SKID_RADIUS - 0.9, SKID_RADIUS - 0.35, 64,
		PAINT_Y, PAINT_CREAM)
	_paint.ring(SKID_CENTRE, 6.4, 6.9, 56, PAINT_Y, PAINT_YELLOW)
	_paint.disc(SKID_CENTRE, 1.6, 24, PAINT_Y, PAINT_PINK)
	for i in 4:
		var angle: float = TAU * float(i) / 4.0 + PI * 0.25
		var direction := Vector2(cos(angle), sin(angle))
		_paint.line(SKID_CENTRE + direction * 6.9,
			SKID_CENTRE + direction * (SKID_RADIUS - 0.9), 0.3, PAINT_Y,
			PAINT_CREAM)
	for i in 10:
		var x0: float = SKID_CENTRE.x - SKID_RADIUS + float(i) \
			* (SKID_RADIUS * 2.0 / 10.0)
		_paint.rect(Rect2(x0, SKID_CENTRE.y - 0.6,
			SKID_RADIUS * 2.0 / 10.0, 1.2), PAINT_Y,
			PAINT_CREAM if i % 2 == 0 else PAINT_DARK)
	# Dirt block with dashed edges and a gate at the slalom entry.
	_paint.rect(DIRT, ZONE_Y + 0.002, DIRT_TAN)
	_paint.outline(DIRT.grow(-0.8), 0.4, PAINT_Y, DIRT_ALT)
	for i in 10:
		var z: float = DIRT.position.y + 4.0 + float(i) * 4.5
		_paint.rect(Rect2(DIRT.position.x + 1.2, z, 1.8, 0.3), PAINT_Y,
			PAINT_CREAM)
		_paint.rect(Rect2(DIRT.end.x - 3.0, z, 1.8, 0.3), PAINT_Y,
			PAINT_CREAM)
	_paint.line(Vector2(-12.0, 24.0), Vector2(-8.0, 24.0), 0.4, PAINT_Y,
		PAINT_CREAM)
	_paint.line(Vector2(8.0, 24.0), Vector2(12.0, 24.0), 0.4, PAINT_Y,
		PAINT_CREAM)
	# Dirt service lane through the perimeter gap in the south fence.
	_paint.rect(Rect2(16.0, 68.0, 16.0, 44.0), ZONE_Y + 0.002, DIRT_TAN)
	_paint.line(Vector2(16.8, 68.0), Vector2(16.8, 112.0), 0.3, PAINT_Y,
		PAINT_CREAM)
	_paint.line(Vector2(31.2, 68.0), Vector2(31.2, 112.0), 0.3, PAINT_Y,
		PAINT_CREAM)
	# Six painted grid slots on the paddock.
	for i in GRID_SLOTS.size():
		_paint_slot(GRID_SLOTS[i], PAINT_CREAM)
	# Launch band, boost chevrons and landing distance stripes on the jump lane.
	for i in 8:
		var shade: Color = PAINT_CREAM if i % 2 == 0 else PAINT_DARK
		_paint.rect(Rect2(JUMP_X - 5.5 + float(i) * 1.375, 58.0, 1.375, 1.0),
			ROAD_TOP + 0.010, shade)
	for chevron in 4:
		var cz: float = 52.0 - float(chevron) * 3.5
		_paint.line(Vector2(JUMP_X - 3.2, cz + 1.4), Vector2(JUMP_X, cz), 0.36,
			ROAD_TOP + 0.010, PAINT_BLUE)
		_paint.line(Vector2(JUMP_X + 3.2, cz + 1.4), Vector2(JUMP_X, cz), 0.36,
			ROAD_TOP + 0.010, PAINT_BLUE)
	for target_z: float in [6.0, 0.0, -38.0, -46.0, -54.0]:
		_paint.line(Vector2(JUMP_X - 4.8, target_z),
			Vector2(JUMP_X + 4.8, target_z), 0.38, ROAD_TOP + 0.010,
			PAINT_YELLOW)
	_paint.disc(Vector2(JUMP_X, -48.0), 2.2, 20, ROAD_TOP + 0.012, PAINT_PINK)
	_skid_marks()


## Rubber laid down on the skidpad: three long diagonal scrubs plus two rings
## of scrubbed arcs, all painted above the white circle so the pad reads as used.
func _skid_marks() -> void:
	var y: float = PAINT_Y + 0.004
	var rubber: Color = Color("2a2f45")
	for i in 3:
		var angle: float = PI * 0.25 + TAU * float(i) / 3.0
		var direction := Vector2(cos(angle), sin(angle))
		_paint.line(SKID_CENTRE + direction * 2.6,
			SKID_CENTRE + direction * (SKID_RADIUS - 1.2), 0.34, y, rubber)
	for i in 6:
		var start: float = TAU * float(i) / 6.0 + 0.22
		var span: float = 0.55 + 0.18 * float(i % 3)
		var radius: float = 4.5 + float(i % 2) * 1.6
		_paint.arc(SKID_CENTRE, radius, radius + 0.55, start, start + span,
			10, y, rubber)


## Painted border of one start-grid slot.
func _paint_slot(centre: Vector2, color: Color) -> void:
	_paint.line(centre + Vector2(-GRID_HALF.x, -GRID_HALF.y),
		centre + Vector2(GRID_HALF.x, -GRID_HALF.y), 0.2, PAINT_Y + 0.004,
		color)
	_paint.line(centre + Vector2(-GRID_HALF.x, GRID_HALF.y),
		centre + Vector2(GRID_HALF.x, GRID_HALF.y), 0.2, PAINT_Y + 0.004,
		color)
	_paint.line(centre + Vector2(-GRID_HALF.x, -GRID_HALF.y),
		centre + Vector2(-GRID_HALF.x, GRID_HALF.y), 0.2, PAINT_Y + 0.004,
		color)
	_paint.line(centre + Vector2(GRID_HALF.x, -GRID_HALF.y),
		centre + Vector2(GRID_HALF.x, GRID_HALF.y), 0.2, PAINT_Y + 0.004,
		color)


# --------------------------------------------------------------------------
# elevation


## Raised spectator terrace: a 0.7 m concrete pad with a drive-up ramp on its
## skidpad side. One merged mesh, one box collider plus a ramp wedge on WORLD.
func _raised_pad() -> void:
	var x0: float = RAISED_PAD.position.x
	var z0: float = RAISED_PAD.position.y
	var x1: float = RAISED_PAD.end.x
	var z1: float = RAISED_PAD.end.y
	var top: float = PAD_TOP
	# Deck, then a painted lip so the step reads from the grid.
	_solid.face(Vector3(x0, top, z0), Vector3(x0, top, z1),
		Vector3(x1, top, z1), Vector3(x1, top, z0), PAD_CONCRETE, Vector3.UP)
	_solid.face(Vector3(x0 + 0.45, top + 0.006, z0 + 0.45),
		Vector3(x0 + 0.45, top + 0.006, z1 - 0.45),
		Vector3(x1 - 0.45, top + 0.006, z1 - 0.45),
		Vector3(x1 - 0.45, top + 0.006, z0 + 0.45), PAINT_YELLOW, Vector3.UP)
	# Three vertical walls; the east face is the ramp.
	_solid.face(Vector3(x0, 0.0, z0), Vector3(x0, top, z0),
		Vector3(x1, top, z0), Vector3(x1, 0.0, z0), PAD_WALL,
		Vector3(0.0, 0.0, -1.0))
	_solid.face(Vector3(x0, 0.0, z1), Vector3(x1, 0.0, z1),
		Vector3(x1, top, z1), Vector3(x0, top, z1), PAD_WALL,
		Vector3(0.0, 0.0, 1.0))
	_solid.face(Vector3(x0, 0.0, z0), Vector3(x0, 0.0, z1),
		Vector3(x0, top, z1), Vector3(x0, top, z0), PAD_WALL,
		Vector3(-1.0, 0.0, 0.0))
	var ramp_x: float = x1 + PAD_RAMP
	_solid.face(Vector3(x1, top, z1), Vector3(ramp_x, 0.0, z1),
		Vector3(ramp_x, 0.0, z0), Vector3(x1, top, z0), CONCRETE,
		Vector3(1.0, 0.6, 0.0))
	_solid.tri_face(Vector3(x1, top, z0), Vector3(ramp_x, 0.0, z0),
		Vector3(x1, 0.0, z0), PAD_WALL, Vector3(0.0, 0.0, -1.0))
	_solid.tri_face(Vector3(x1, top, z1), Vector3(ramp_x, 0.0, z1),
		Vector3(x1, 0.0, z1), PAD_WALL, Vector3(0.0, 0.0, 1.0))
	var body := _static_body("RaisedPadCollision")
	_add_box_shape(body, Transform3D(Basis.IDENTITY,
		Vector3((x0 + x1) * 0.5, top * 0.5, (z0 + z1) * 0.5)),
		Vector3(x1 - x0, top, z1 - z0))
	_add_wedge_shape(body, Vector3(x1, 0.0, z0), Vector3(ramp_x, 0.0, z1),
		top)


## Raised banked drift bowl around the north, east and south perimeter of the
## skidpad. Leaves the west paddock side flat and wide open while giving
## drifting karts a smooth ~16 degree banked rim to rail around.
func _drift_bowl() -> void:
	var centre: Vector2 = SKID_CENTRE
	var r_in: float = SKID_RADIUS
	var r_crest: float = SKID_RADIUS + 3.6
	var r_lip: float = SKID_RADIUS + 4.4
	var r_out: float = SKID_RADIUS + 5.8
	var h_crest: float = 1.05
	var from_angle: float = -PI * 0.65
	var to_angle: float = PI * 0.65
	var segments: int = 16
	var body := _static_body("DriftBowlCollision")

	for seg in segments:
		var a0: float = lerpf(from_angle, to_angle,
			float(seg) / float(segments))
		var a1: float = lerpf(from_angle, to_angle,
			float(seg + 1) / float(segments))
		var c0: float = cos(a0)
		var s0: float = sin(a0)
		var c1: float = cos(a1)
		var s1: float = sin(a1)
		var mid: float = (a0 + a1) * 0.5
		var radial := Vector3(cos(mid), 0.0, sin(mid))

		var p0_in := Vector3(centre.x + c0 * r_in, ZONE_Y + 0.005,
			centre.y + s0 * r_in)
		var p1_in := Vector3(centre.x + c1 * r_in, ZONE_Y + 0.005,
			centre.y + s1 * r_in)
		var p0_crest := Vector3(centre.x + c0 * r_crest, h_crest,
			centre.y + s0 * r_crest)
		var p1_crest := Vector3(centre.x + c1 * r_crest, h_crest,
			centre.y + s1 * r_crest)
		var p0_lip := Vector3(centre.x + c0 * r_lip, h_crest,
			centre.y + s0 * r_lip)
		var p1_lip := Vector3(centre.x + c1 * r_lip, h_crest,
			centre.y + s1 * r_lip)
		var p0_out := Vector3(centre.x + c0 * r_out, 0.0,
			centre.y + s0 * r_out)
		var p1_out := Vector3(centre.x + c1 * r_out, 0.0,
			centre.y + s1 * r_out)

		var bank_col: Color = SKID_TARMAC.darkened(0.08) if seg % 2 == 0 \
			else SKID_TARMAC.lightened(0.06)
		var lip_col: Color = PAINT_YELLOW if seg % 2 == 0 else PAINT_CREAM
		_solid.face(p0_in, p0_crest, p1_crest, p1_in, bank_col,
			Vector3.UP - radial * 0.35)
		_solid.face(p0_crest, p0_lip, p1_lip, p1_crest, lip_col, Vector3.UP)
		_solid.face(p0_lip, p0_out, p1_out, p1_lip, PAD_WALL,
			Vector3.UP + radial * 0.65)

		var wedge := ConvexPolygonShape3D.new()
		wedge.points = PackedVector3Array([
			Vector3(p0_in.x, 0.0, p0_in.z),
			Vector3(p1_in.x, 0.0, p1_in.z),
			p0_crest, p1_crest, p0_lip, p1_lip, p0_out, p1_out,
		])
		var collision := CollisionShape3D.new()
		collision.shape = wedge
		body.add_child(collision)

	# Smooth end caps at both ends of the arc.
	for end_angle: float in [from_angle, to_angle]:
		var ce: float = cos(end_angle)
		var se: float = sin(end_angle)
		var tangent_sign: float = -1.0 if end_angle < 0.0 else 1.0
		var outward := Vector3(-se * tangent_sign, 0.0, ce * tangent_sign)
		var e_in := Vector3(centre.x + ce * r_in, 0.0, centre.y + se * r_in)
		var e_crest := Vector3(centre.x + ce * r_crest, h_crest,
			centre.y + se * r_crest)
		var e_lip := Vector3(centre.x + ce * r_lip, h_crest,
			centre.y + se * r_lip)
		var e_out := Vector3(centre.x + ce * r_out, 0.0, centre.y + se * r_out)
		_solid.face(e_in, e_crest, e_lip, e_out, PAD_WALL, outward)


## Faceted grass berm: four colour bands on a lathe profile, one convex collider
## so a kart rolls over it instead of clipping through it.
func _berm() -> void:
	var centre: Vector2 = BERM_CENTRE
	var segments: int = 14
	var rings: Array[Dictionary] = [
		{"radius": BERM_RADIUS, "y": 0.0, "color": OUTFIELD},
		{"radius": BERM_RADIUS * 0.76, "y": BERM_HEIGHT * 0.46,
			"color": GRASS_B},
		{"radius": BERM_RADIUS * 0.45, "y": BERM_HEIGHT * 0.82,
			"color": GRASS_A},
		{"radius": BERM_RADIUS * 0.18, "y": BERM_HEIGHT, "color": GRASS_B},
	]
	for band in rings.size() - 1:
		var inner: Dictionary = rings[band]
		var outer: Dictionary = rings[band + 1]
		for segment in segments:
			var a0: float = TAU * float(segment) / float(segments)
			var a1: float = TAU * float(segment + 1) / float(segments)
			var p0_in := Vector3(centre.x + cos(a0) * float(inner["radius"]),
				float(inner["y"]), centre.y + sin(a0) * float(inner["radius"]))
			var p0_out := Vector3(centre.x + cos(a0) * float(outer["radius"]),
				float(outer["y"]), centre.y + sin(a0) * float(outer["radius"]))
			var p1_out := Vector3(centre.x + cos(a1) * float(outer["radius"]),
				float(outer["y"]), centre.y + sin(a1) * float(outer["radius"]))
			var p1_in := Vector3(centre.x + cos(a1) * float(inner["radius"]),
				float(inner["y"]), centre.y + sin(a1) * float(inner["radius"]))
			var mid: float = (a0 + a1) * 0.5
			var outward := Vector3(cos(mid), 0.55, sin(mid))
			_solid.face(p0_in, p0_out, p1_out, p1_in,
				outer["color"] as Color, outward)
	var top: Dictionary = rings[rings.size() - 1]
	var apex := Vector3(centre.x, float(top["y"]) + 0.02, centre.y)
	for segment in segments:
		var a0: float = TAU * float(segment) / float(segments)
		var a1: float = TAU * float(segment + 1) / float(segments)
		var p0 := Vector3(centre.x + cos(a0) * float(top["radius"]),
			float(top["y"]), centre.y + sin(a0) * float(top["radius"]))
		var p1 := Vector3(centre.x + cos(a1) * float(top["radius"]),
			float(top["y"]), centre.y + sin(a1) * float(top["radius"]))
		_solid.tri_face(p0, p1, apex, top["color"] as Color, Vector3.UP)
	var points := PackedVector3Array()
	for ring: Dictionary in rings:
		for segment in segments:
			var angle: float = TAU * float(segment) / float(segments)
			points.append(Vector3(centre.x + cos(angle) * float(ring["radius"]),
				float(ring["y"]), centre.y + sin(angle) * float(ring["radius"])))
	points.append(apex)
	var body := _static_body("BermCollision")
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)


# --------------------------------------------------------------------------
# paddock


## Paddock furniture: six numbered slots, the open pit garages and their sign.
func _paddock() -> void:
	for i in GRID_SLOTS.size():
		_grid_number(i + 1, GRID_SLOTS[i])
	# Pit block on the paddock's west edge, its bays opening onto the service
	# yard. Cell row 0 keeps the block 13.7 m clear of the loop's armco; the old
	# row (-1) clipped the wall's inner corner by 0.2 m.
	_pit_garage()
	_wall_label("PADDOCK", Vector3(-15.6, 6.6, 8.0), PI * 0.5, 128, 0.009)


## Two open kit pit garages whose bays are genuinely driveable.
##
## The kit's pitsGarage GLB is already the open variant, but the shared
## TileKit.pit_building helper wrapped each whole module in one 16 x 11.2 x 16 m
## box, so both 5.97 m openings had an invisible wall across them. This builds
## the block from the OPEN model and authors the collision as its real shell:
## side walls, rear wall, centre pier, roof slab and the lintel above each bay.
## The bay volume itself (floor to 6.16 m, 5.97 m wide, 14.64 m deep) is free.
##
## The modules are turned 180 degrees so the bays face the service yard / pit
## lane rather than the dirt at the paddock's south edge. The kit's roof lip
## still overhangs the mouths by 1.44 m at 11.2 m, well above the 1.87 m chase
## camera, so entering a bay does not push the camera down.
func _pit_garage() -> void:
	var info: Dictionary = TileCatalog.model_info(TileCatalog.PIT_GARAGE)
	if not bool(info.get("ok", false)):
		push_warning("sandbox_park: missing kit model " + TileCatalog.PIT_GARAGE)
		return
	var packed: PackedScene = load(str(info["path"])) as PackedScene
	if packed == null:
		return
	var body := _static_body("PitGarageCollision")
	for index in PIT_GARAGE_CELLS.size():
		var cell: Vector2i = PIT_GARAGE_CELLS[index]
		var at := Vector3((float(cell.x) + 0.5) * TILE, 0.0,
			(float(cell.y) + 0.5) * TILE)
		var node: Node3D = packed.instantiate() as Node3D
		if node == null:
			continue
		node.name = "PitGarage%d" % (index + 1)
		node.transform = _fit_model(TileCatalog.PIT_GARAGE, at,
			PIT_GARAGE_YAW, Vector3.ONE * TileCatalog.PROP_SCALE)
		add_child(node)
		_garage_shell(body, at)
		_garage_floor(at)
	_audit_garage_bays()


## World-space collision shell of one garage module. `at` is the module's
## footprint centre, so the measured 1.36 m walls, 1.36 m centre pier and
## 16 x 17.44 m roof slab land exactly on the kit mesh.
func _garage_shell(body: StaticBody3D, at: Vector3) -> void:
	var front: float = at.z - GARAGE_FACADE_INSET
	var back: float = at.z + GARAGE_HALF_DEPTH
	var rear: float = back - GARAGE_WALL
	var mid_y: float = GARAGE_HEIGHT * 0.5
	# Outer side walls, from the facade back to the rear outer face.
	for side_sign: float in [-1.0, 1.0]:
		_add_box_shape(body, Transform3D(Basis.IDENTITY, Vector3(
			at.x + side_sign * (GARAGE_BAY_OUTER + GARAGE_WALL * 0.5),
			mid_y, (front + back) * 0.5)),
			Vector3(GARAGE_WALL, GARAGE_HEIGHT, back - front))
	# Rear wall and the centre pier between the two bays.
	_add_box_shape(body, Transform3D(Basis.IDENTITY, Vector3(at.x, mid_y,
		(rear + back) * 0.5)), Vector3(GARAGE_HALF_WIDTH * 2.0,
		GARAGE_HEIGHT, GARAGE_WALL))
	_add_box_shape(body, Transform3D(Basis.IDENTITY, Vector3(at.x, mid_y,
		front + GARAGE_WALL * 0.5)), Vector3(GARAGE_PIER_HALF * 2.0,
		GARAGE_HEIGHT, GARAGE_WALL))
	# Roof slab, including the kit's 1.44 m lip over the bay mouths.
	_add_box_shape(body, Transform3D(Basis.IDENTITY, Vector3(at.x,
		(GARAGE_ROOF_UNDERSIDE + GARAGE_HEIGHT) * 0.5, at.z)),
		Vector3(GARAGE_HALF_WIDTH * 2.0,
			GARAGE_HEIGHT - GARAGE_ROOF_UNDERSIDE, GARAGE_HALF_DEPTH * 2.0))
	# Lintel over each bay. It starts at 6.16 m, so it never touches a cart or
	# the chase camera, but it keeps the visible facade above the opening solid.
	for bay_sign: float in [-1.0, 1.0]:
		var bay_mid: float = at.x + bay_sign * (GARAGE_PIER_HALF
			+ GARAGE_BAY_WIDTH * 0.5)
		_add_box_shape(body, Transform3D(Basis.IDENTITY, Vector3(bay_mid,
			(GARAGE_OPENING_TOP + GARAGE_HEIGHT) * 0.5, front + 0.2)),
			Vector3(GARAGE_BAY_WIDTH,
				GARAGE_HEIGHT - GARAGE_OPENING_TOP, 0.4))


## Painted bay floor and threshold, flush with the service yard's apron.
## Physics is the park's one ground slab at y = 0 everywhere, so the garage has
## no lip to climb; the paint uses the yard's layer so the two read as one slab.
func _garage_floor(at: Vector3) -> void:
	var front: float = at.z - GARAGE_FACADE_INSET
	var inner_back: float = at.z + GARAGE_HALF_DEPTH - GARAGE_WALL
	_paint.rect(Rect2(at.x - GARAGE_BAY_OUTER, front,
		GARAGE_BAY_OUTER * 2.0, inner_back - front), ZONE_Y + 0.002,
		PAD_CONCRETE)
	_paint.rect(Rect2(at.x - GARAGE_HALF_WIDTH, 0.0,
		GARAGE_HALF_WIDTH * 2.0, front), ZONE_Y + 0.002, PIT_PAD_TINT)


## Publishes the measured bay clearance and fails the boot if the cart no longer
## has its 2.5x margin. Called once, after both modules are built.
func _audit_garage_bays() -> void:
	var ratio: float = GARAGE_BAY_WIDTH / CART_BODY_WIDTH
	var overhang: float = GARAGE_HALF_DEPTH - GARAGE_FACADE_INSET
	print("PIT GARAGE modules=%d bays=%d opening=%.2f m cart=%.2f m clearance=%.2fx (need %.1fx) roof=%.1f m lip=%.2f m -> %s" % [
		PIT_GARAGE_CELLS.size(), PIT_GARAGE_CELLS.size() * 2,
		GARAGE_BAY_WIDTH, CART_BODY_WIDTH, ratio,
		BAY_MIN_CLEARANCE / CART_BODY_WIDTH, GARAGE_HEIGHT, overhang,
		"CLEARS" if ratio >= BAY_MIN_CLEARANCE / CART_BODY_WIDTH else "TOO NARROW"])
	if GARAGE_BAY_WIDTH < BAY_MIN_CLEARANCE:
		push_error("sandbox_park: pit garage bays are %.2f m, under the %.2f m cart-clearance contract." % [
			GARAGE_BAY_WIDTH, BAY_MIN_CLEARANCE])


## Big painted grid number, lying flat and readable from the south.
func _grid_number(number: int, centre: Vector2) -> void:
	var label := Label3D.new()
	label.name = "GridNumber%d" % number
	label.text = str(number)
	label.font = _font
	label.font_size = 128
	label.pixel_size = 0.011
	label.outline_size = 12
	label.outline_modulate = PAINT_DARK
	label.modulate = PAINT_CREAM
	label.position = Vector3(centre.x, PAINT_Y + 0.012, centre.y - 1.9)
	label.rotation.x = -PI * 0.5
	add_child(label)


# --------------------------------------------------------------------------
# handling loop


## Five-by-three grid oval of kit road pieces, its colliders, armco and spline.
func _handling_loop() -> void:
	_loop_spline = RingSpline.new(_loop_path())
	var batches: Dictionary = {}
	var body := _static_body("LoopRoadCollision")
	for i in LOOP_RING.size():
		var cell: Vector2i = LOOP_RING[i]
		var prev: Vector2i = LOOP_RING[(i - 1 + LOOP_RING.size())
			% LOOP_RING.size()]
		var next: Vector2i = LOOP_RING[(i + 1) % LOOP_RING.size()]
		var din := Vector2i(cell.x - prev.x, cell.y - prev.y)
		var dout := Vector2i(next.x - cell.x, next.y - cell.y)
		var at: Vector3 = _loop_cell_centre(cell)
		var model: String = "roadCornerSmall" if din != dout else "roadStraight"
		var yaw: float = _ring_yaw(din, dout)
		var xform: Transform3D = _fit_road(model, at, yaw,
			Vector3.ONE * TILE, true)
		if not batches.has(model):
			batches[model] = []
		(batches[model] as Array).append(xform)
		_add_road_box(body, at, Vector3(TILE, 0.3, TILE))
	for model: String in batches:
		_batch_road("LoopRoad", model, batches[model] as Array)
	_loop_start_band()
	_loop_markings()
	_loop_barrier()
	_loop_dressing()


## Painted circuit markings: a dashed centreline all the way round, skipped
## across the start band, and a pink apex dot in each of the four corner cells.
func _loop_markings() -> void:
	if _loop_spline == null:
		return
	var y: float = ROAD_TOP + 0.010
	var total: float = _loop_spline.total_length
	var start: float = _nearest_distance(_loop_spline, _gate_point())
	var step: float = 6.0
	var dash: float = 2.4
	var travelled: float = dash * 0.5
	while travelled + dash < total:
		var from: float = fposmod(travelled, total)
		var to: float = fposmod(travelled + dash, total)
		# Leave the chequered start band clear instead of painting under it.
		var offset: float = fposmod(from - start + total * 0.5, total) \
			- total * 0.5
		if absf(offset) > 2.0:
			var a: Vector3 = _loop_spline.sample(from)["position"] as Vector3
			var b: Vector3 = _loop_spline.sample(to)["position"] as Vector3
			_paint.line(Vector2(a.x, a.z), Vector2(b.x, b.z), 0.22, y,
				PAINT_CREAM)
		travelled += step
	for i in LOOP_RING.size():
		var cell: Vector2i = LOOP_RING[i]
		var prev: Vector2i = LOOP_RING[(i - 1 + LOOP_RING.size())
			% LOOP_RING.size()]
		var next: Vector2i = LOOP_RING[(i + 1) % LOOP_RING.size()]
		var din := Vector2i(cell.x - prev.x, cell.y - prev.y)
		var dout := Vector2i(next.x - cell.x, next.y - cell.y)
		if din == dout:
			continue
		var centre: Vector3 = _loop_cell_centre(cell)
		_paint.disc(Vector2(centre.x, centre.z), 1.2, 16, y + 0.002,
			PAINT_PINK)


## World centre of one local loop cell.
func _loop_cell_centre(cell: Vector2i) -> Vector3:
	return Vector3(LOOP_CELL_X + float(cell.x) * TILE, 0.0,
		LOOP_CELL_Z + float(cell.y) * TILE)


## Closed centreline of the ring, sampled edge-midpoint to edge-midpoint.
func _loop_path() -> PackedVector3Array:
	var path := PackedVector3Array()
	for i in LOOP_RING.size():
		var cell: Vector2i = LOOP_RING[i]
		var prev: Vector2i = LOOP_RING[(i - 1 + LOOP_RING.size())
			% LOOP_RING.size()]
		var next: Vector2i = LOOP_RING[(i + 1) % LOOP_RING.size()]
		var din := Vector2i(cell.x - prev.x, cell.y - prev.y)
		var dout := Vector2i(next.x - cell.x, next.y - cell.y)
		var centre: Vector3 = _loop_cell_centre(cell)
		var din3 := Vector3(float(din.x), 0.0, float(din.y))
		var dout3 := Vector3(float(dout.x), 0.0, float(dout.y))
		var p_in: Vector3 = centre - din3 * HALF_TILE
		var p_out: Vector3 = centre + dout3 * HALF_TILE
		if din == dout:
			_append_straight(path, p_in, p_out)
			continue
		var corner: Vector3 = p_in + dout3 * HALF_TILE
		var a0: float = atan2(p_in.z - corner.z, p_in.x - corner.x)
		var a1: float = atan2(p_out.z - corner.z, p_out.x - corner.x)
		var delta: float = angle_difference(a0, a1)
		for step in 7:
			var t: float = float(step) / 6.0
			var angle: float = a0 + delta * t
			_append_point(path, Vector3(corner.x + cos(angle) * HALF_TILE, 0.0,
				corner.z + sin(angle) * HALF_TILE))
	if path.size() > 1 \
			and path[0].distance_to(path[path.size() - 1]) < 0.05:
		path.remove_at(path.size() - 1)
	return path


func _append_straight(path: PackedVector3Array, from: Vector3,
		to: Vector3) -> void:
	for step in 5:
		var t: float = float(step) / 4.0
		_append_point(path, from.lerp(to, t))


func _append_point(path: PackedVector3Array, point: Vector3) -> void:
	if path.is_empty() or path[path.size() - 1].distance_to(point) > 0.01:
		path.append(point)


## Yaw that aligns a road piece with a ring cell's travel direction.
func _ring_yaw(din: Vector2i, dout: Vector2i) -> float:
	if din == dout:
		return atan2(-float(din.x), -float(din.y))
	var right := Vector2i(-din.y, din.x)
	if dout == right:
		return atan2(-float(din.x), -float(din.y))
	return atan2(float(din.y), -float(din.x))


## Travel direction (plan) of the loop's first tile, as the audit reports it.
func _loop_first_direction() -> Vector2:
	var cell: Vector2i = LOOP_RING[0]
	var prev: Vector2i = LOOP_RING[LOOP_RING.size() - 1]
	return Vector2(float(cell.x - prev.x), float(cell.y - prev.y))


## Checkered start/finish band across the loop at the pit gate.
func _loop_start_band() -> void:
	if _loop_spline == null:
		return
	var distance: float = _nearest_distance(_loop_spline, _gate_point())
	var before: Dictionary = _loop_spline.sample(distance - 1.4)
	var after: Dictionary = _loop_spline.sample(distance + 1.4)
	var pb: Vector3 = before["position"]
	var pa: Vector3 = after["position"]
	var rb: Vector3 = before["right"]
	var ra: Vector3 = after["right"]
	var half: float = TileCatalog.ROAD_HALF
	for i in 12:
		var t0: float = -half + 2.0 * half * float(i) / 12.0
		var t1: float = -half + 2.0 * half * float(i + 1) / 12.0
		var shade: Color = PAINT_CREAM if i % 2 == 0 else PAINT_DARK
		_paint.quad(pb + rb * t0 + Vector3.UP * (ROAD_TOP + 0.012),
			pb + rb * t1 + Vector3.UP * (ROAD_TOP + 0.012),
			pa + ra * t1 + Vector3.UP * (ROAD_TOP + 0.012),
			pa + ra * t0 + Vector3.UP * (ROAD_TOP + 0.012), shade)


## Red armco round the whole loop, open for 16 m at the pit gate. The run is
## placed on the true road edge at BARRIER_CLEARANCE, so no piece can reach the
## racing surface even on the 8 m corner arcs. The ring travels +X along the
## paddock-side straight, so the kit's "right of travel" IS the outside here -
## passing -1 (the old ring's side) would drop the whole wall into the infield.
func _loop_barrier() -> void:
	if _loop_spline == null:
		return
	var gate: float = _nearest_distance(_loop_spline, _gate_point())
	var half_gap: float = LOOP_GATE_WIDTH * 0.5
	_loop_barriers = _holder("LoopBarriers")
	TileKit.barrier_line(_loop_barriers, _loop_spline, gate + half_gap,
		gate - half_gap, 1.0, "barrierRed")


## Cartoon tyre stacks, backstretch speed-trap gantry + boost pad, north
## spectator stands and the pit-gate banner towers on the loop.
func _loop_dressing() -> void:
	var anchors: Array[Vector2] = [
		Vector2(-24.0, -54.0), Vector2(24.0, -54.0),
		Vector2(-32.0, -38.0), Vector2(32.0, -38.0), Vector2(-22.0, -22.0),
		Vector2(22.0, -22.0),
	]
	for anchor: Vector2 in anchors:
		var distance: float = _nearest_distance(_loop_spline, anchor)
		TileKit.tyre_stack(self, _loop_spline, distance, 1.0)
	_spawn_boost_pad("LoopBoostPad", Vector3(0.0, ROAD_TOP + 0.02, -54.0),
		PI * 0.5)
	_loop_gantry()
	_gate_towers()


## Overhead backstretch gantry spanning z = -54 with piers 10.5 m clear of the
## road centreline and two north spectator stands watching the speed trap.
func _loop_gantry() -> void:
	var body := _static_body("LoopGantryCollision")
	for side_z: float in [-64.5, -43.5]:
		_sign_box(self, "GantryPier", Vector3(0.0, 2.8, side_z),
			Vector3(1.1, 5.6, 1.1), Color("3c4257"))
		_add_box_shape(body, Transform3D(Basis.IDENTITY,
			Vector3(0.0, 2.8, side_z)), Vector3(1.1, 5.6, 1.1))
	_sign_box(self, "GantryBeam", Vector3(0.0, 5.4, -54.0),
		Vector3(1.4, 1.1, 22.2), PAINT_DARK)
	_sign_box(self, "GantryPlateE", Vector3(0.74, 5.4, -54.0),
		Vector3(0.10, 0.86, 11.6), PAINT_YELLOW)
	_sign_box(self, "GantryPlateW", Vector3(-0.74, 5.4, -54.0),
		Vector3(0.10, 0.86, 11.6), PAINT_YELLOW)
	_wall_label("SPEED TRAP", Vector3(0.82, 5.4, -54.0), PI * 0.5, 84, 0.010)
	_wall_label("SLOP GP", Vector3(-0.82, 5.4, -54.0), -PI * 0.5, 84, 0.010)
	for sx: float in [-20.0, 20.0]:
		_kit_solid("grandStand", Vector3(sx, 0.0, -67.5), PI,
			TileCatalog.PROP_SCALE * 0.55, body)


## Two kit banner towers framing the pit gate, outside the armco's outer face and
## far enough out that they never pinch the 16 m opening.
func _gate_towers() -> void:
	var body := _static_body("GateTowers")
	_kit_solid("bannerTowerRed", Vector3(-17.0, 0.0, -8.5), 0.0,
		TileCatalog.sign_scale("bannerTower"), body)
	_kit_solid("bannerTowerGreen", Vector3(17.0, 0.0, -8.5), 0.0,
		TileCatalog.sign_scale("bannerTower"), body)


# --------------------------------------------------------------------------
# jump lane


## Extended jump lane with boost strips and twin kickers on one line.
func _jump_lane() -> void:
	var body := _static_body("JumpLaneCollision")
	var batches: Dictionary = {}
	for piece: Dictionary in JUMP_PIECES:
		var model: String = str(piece["model"])
		var scale := Vector3(TILE, TILE * float(piece["yscale"]), TILE)
		var at := Vector3(JUMP_X, 0.0, float(piece["z"]))
		var xform: Transform3D = _fit_road(model, at, 0.0, scale,
			bool(piece["flat"]))
		if not batches.has(model):
			batches[model] = []
		(batches[model] as Array).append(xform)
		if bool(piece["flat"]):
			_add_road_box(body, at, Vector3(TILE, 0.3, TILE))
		else:
			_add_ramp_collider(body, at, scale, model)
	for model: String in batches:
		_batch_road("JumpLane", model, batches[model] as Array)
	_spawn_boost_pad("JumpBoostApproach",
		Vector3(JUMP_X, ROAD_TOP + 0.02, 43.0), 0.0)
	_spawn_boost_pad("JumpBoostMid",
		Vector3(JUMP_X, ROAD_TOP + 0.02, -5.0), 0.0)


func _spawn_boost_pad(node_name: String, at: Vector3, yaw: float) -> void:
	if BOOST_PAD_SCENE == null:
		return
	var pad: Node3D = BOOST_PAD_SCENE.instantiate() as Node3D
	if pad == null:
		return
	pad.name = node_name
	pad.transform = Transform3D(Basis(Vector3.UP, yaw), at)
	add_child(pad)


# --------------------------------------------------------------------------
# perimeter and kit dressing


## Park boundary: rounded-rect spline, barrierLine run with one south entry gap,
## the terrace stand, lights, flags, signage, tents, foliage and the berm view.
func _dressing() -> void:
	_perimeter_spline = RingSpline.new(_perimeter_path())
	_barrier_line()
	_grandstand()
	_lights()
	_signage()
	_flags()
	_yard()
	_trees()


## Sampled rounded-rectangle path inset so the kit barriers land outside +/-64.
func _perimeter_path() -> PackedVector3Array:
	var path := PackedVector3Array()
	var half: float = PERIMETER_HALF
	var corner: float = half - CORNER_RADIUS
	_append_line(path, Vector2(0.0, half), Vector2(corner, half))
	_append_arc(path, Vector2(corner, corner), CORNER_RADIUS, PI * 0.5, 0.0)
	_append_line(path, Vector2(half, corner), Vector2(half, -corner))
	_append_arc(path, Vector2(corner, -corner), CORNER_RADIUS, 0.0, -PI * 0.5)
	_append_line(path, Vector2(corner, -half), Vector2(-corner, -half))
	_append_arc(path, Vector2(-corner, -corner), CORNER_RADIUS, -PI * 0.5,
		-PI)
	_append_line(path, Vector2(-half, -corner), Vector2(-half, corner))
	_append_arc(path, Vector2(-corner, corner), CORNER_RADIUS, PI, PI * 0.5)
	_append_line(path, Vector2(-corner, half), Vector2(0.0, half))
	if path.size() > 1 \
			and path[0].distance_to(path[path.size() - 1]) < 0.05:
		path.remove_at(path.size() - 1)
	return path


func _append_line(path: PackedVector3Array, from: Vector2, to: Vector2) -> void:
	_append_point(path, Vector3(from.x, 0.0, from.y))
	var span: float = from.distance_to(to)
	var steps: int = maxi(int(ceil(span / 2.0)), 1)
	for step in range(1, steps + 1):
		var point: Vector2 = from.lerp(to, float(step) / float(steps))
		_append_point(path, Vector3(point.x, 0.0, point.y))


func _append_arc(path: PackedVector3Array, centre: Vector2, radius: float,
		from_angle: float, to_angle: float) -> void:
	var span: float = absf(to_angle - from_angle) * radius
	var steps: int = maxi(int(ceil(span / 2.0)), 2)
	for step in range(1, steps + 1):
		var angle: float = lerpf(from_angle, to_angle,
			float(step) / float(steps))
		_append_point(path, Vector3(centre.x + cos(angle) * radius, 0.0,
			centre.y + sin(angle) * radius))


## Barrier wall around the whole park, missing one 16 m gate on the south side.
func _barrier_line() -> void:
	var gap: float = _nearest_distance(_perimeter_spline, Vector2(24.0,
		PERIMETER_HALF))
	var half_gap: float = ENTRY_GAP * 0.5
	var frame: Dictionary = _perimeter_spline.sample(0.0)
	var side: float = 1.0
	var right: Vector3 = frame["right"]
	var point: Vector3 = frame["position"]
	if (point + right * BARRIER_IN).length_squared() \
			< point.length_squared():
		side = -1.0
	_perimeter_barriers = _holder("PerimeterBarriers")
	TileKit.barrier_line(_perimeter_barriers, _perimeter_spline, gap + half_gap,
		gap - half_gap, side, "barrierRed")


## One grouping node for a barrier run, so the clearance audit can measure that
## run alone instead of every wall in the park.
func _holder(node_name: String) -> Node3D:
	var holder := Node3D.new()
	holder.name = node_name
	add_child(holder)
	return holder


## Covered grandstand on the terrace, behind the start grid and facing it.
func _grandstand() -> void:
	var model: String = TileCatalog.GRANDSTAND_COVERED
	var info: Dictionary = TileCatalog.model_info(model)
	if not bool(info.get("ok", false)):
		return
	var packed: PackedScene = load(str(info["path"])) as PackedScene
	if packed == null:
		return
	var node: Node3D = packed.instantiate() as Node3D
	if node == null:
		return
	# One kit unit is PROP_SCALE metres; STAND_SCALE keeps the 16 m model on the
	# terrace's 20 x 14 m deck.
	var stand_scale: float = TileCatalog.PROP_SCALE * STAND_SCALE
	node.name = "Grandstand"
	node.transform = _fit_model(model,
		Vector3(STAND_CELL.x, PAD_TOP, STAND_CELL.y), 0.0,
		Vector3.ONE * stand_scale)
	add_child(node)
	var size: Vector3 = (info["aabb"] as AABB).size * stand_scale
	var body := _static_body("GrandstandCollision")
	_add_box_shape(body, Transform3D(Basis.IDENTITY,
		Vector3(STAND_CELL.x, PAD_TOP + size.y * 0.5, STAND_CELL.y)),
		Vector3(size.x, size.y, size.z))
	if OS.get_environment("CART_DEBUG_PARK") == "1":
		print("KIT SOLID %s at (%.1f, %.1f) size=(%.1f, %.1f, %.1f)" % [
			model, STAND_CELL.x, STAND_CELL.y, size.x, size.y, size.z])
	_wall_label("CART SLOP GP", Vector3(STAND_CELL.x,
		PAD_TOP + size.y * 0.52, STAND_CELL.y - size.z * 0.5 - 0.3), PI, 112,
		0.012)


## Six tall floodlights on the grass, clear of tarmac, drift bowl and jump lane.
func _lights() -> void:
	TileKit.lights(self, [
		Vector3(-66.0, 0.0, 64.0), Vector3(64.0, 0.0, 62.0),
		Vector3(64.0, 0.0, -14.0), Vector3(-66.0, 0.0, -64.0),
		Vector3(-40.0, 0.0, 64.0), Vector3(44.0, 0.0, -64.0),
	])


## Billboards on the three zone approaches plus two paddock banner towers.
func _signage() -> void:
	TileKit.signage(self, [
		{"position": Vector3(40.0, 0.0, 40.0), "kind": "billboard",
			"yaw": PI},
		{"position": Vector3(-40.0, 0.0, 40.0), "kind": "billboard",
			"yaw": PI * 0.5},
		{"position": Vector3(56.0, 0.0, -40.0), "kind": "billboard",
			"yaw": -PI * 0.5},
		{"position": Vector3(24.0, 0.0, 8.0), "kind": "bannerTowerGreen",
			"yaw": 0.0},
	])
	_billboard_label("HANDLING LOOP", Vector3(56.0, 0.0, -40.0), -PI * 0.5)
	_billboard_label("SKIDPAD", Vector3(40.0, 0.0, 40.0), PI)
	_billboard_label("SLALOM", Vector3(-40.0, 0.0, 40.0), PI * 0.5)


## Text standing just in front of a kit billboard's face.
func _billboard_label(text: String, at: Vector3, yaw: float) -> void:
	var label := Label3D.new()
	label.name = "Billboard_" + text.replace(" ", "")
	label.text = text
	label.font = _font
	label.font_size = 96
	label.pixel_size = 0.01
	label.outline_size = 14
	label.outline_modulate = PAINT_DARK
	label.modulate = PAINT_CREAM
	var facing := Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, 1.0)
	label.position = at + Vector3.UP * 5.6 + facing * 0.6
	label.rotation.y = yaw
	add_child(label)


## Flags on the paddock's north corners, on the 16 m kit lattice.
func _flags() -> void:
	TileKit.flags(self, [
		{"position": Vector3(-8.0, 0.0, -8.0), "kind": "flagRed",
			"yaw": 0.0},
		{"position": Vector3(8.0, 0.0, -8.0), "kind": "flagCheckersSmall",
			"yaw": 0.0},
		{"position": Vector3(24.0, 0.0, -8.0), "kind": "flagCheckers",
			"yaw": 0.0},
		{"position": Vector3(24.0, 0.0, 8.0), "kind": "flagGreen",
			"yaw": 0.0},
	])


## Service yard: kit tents parked behind the pit block plus a cone line along
## the yard's loop side, so the pit lane in front of the four bays stays clear.
## A kit unit is 16 m, so the tents are scaled to 8-11 m to sit south of the
## block without touching its rear wall.
func _yard() -> void:
	var body := _static_body("YardProps")
	_kit_solid("tent", Vector3(-42.0, 0.0, 21.5), 0.0,
		TileCatalog.PROP_SCALE * 0.55, body)
	_kit_solid("tentLong", Vector3(-30.0, 0.0, 21.5), 0.0,
		TileCatalog.PROP_SCALE * 0.35, body)
	_kit_solid("tentClosed", Vector3(-19.0, 0.0, 21.5), 0.0,
		TileCatalog.PROP_SCALE * 0.50, body)
	_cone_row(body, Vector2(-46.0, -11.5), Vector2(-19.0, -11.5), 6)


## A row of static cones: one MultiMesh for the visuals, one box each on WORLD.
func _cone_row(body: StaticBody3D, from: Vector2, to: Vector2,
		count: int) -> void:
	var transforms: Array = []
	for index in count:
		var t: float = float(index) / float(maxi(count - 1, 1))
		var at := Vector3(lerpf(from.x, to.x, t), 0.0, lerpf(from.y, to.y, t))
		transforms.append(_fit_model("pylon", at, 0.0,
			Vector3.ONE * CONE_SCALE))
		_add_box_shape(body, Transform3D(Basis.IDENTITY,
			at + Vector3.UP * 0.3), Vector3(0.55, 0.6, 0.55))
	_batch_road("YardCones", "pylon", transforms)


## Cartoon tree line outside the expanded 80 m barriers, plus east grass clumps.
func _trees() -> void:
	var spots: Array = []
	for x: float in [-104.0, -88.0, -56.0, -24.0, 8.0, 40.0, 72.0, 104.0]:
		# The dirt service lane leaves the south fence at x = 24; keep it clear.
		if x > 8.0 and x < 40.0:
			spots.append(Vector3(x, 0.0, -88.0))
			spots.append(Vector3(x, 0.0, -104.0))
			continue
		spots.append(Vector3(x, 0.0, 88.0))
		spots.append(Vector3(x, 0.0, 104.0))
		spots.append(Vector3(x, 0.0, -88.0))
		spots.append(Vector3(x, 0.0, -104.0))
	for z: float in [-72.0, -40.0, -8.0, 24.0, 56.0]:
		spots.append(Vector3(-92.0, 0.0, z))
		spots.append(Vector3(92.0, 0.0, z))
	for spot: Vector3 in [Vector3(56.0, 0.0, -56.0), Vector3(56.0, 0.0, -24.0),
			Vector3(56.0, 0.0, 56.0)]:
		spots.append(spot)
	TileKit.trees(self, spots, _loop_spline)


## Small text panel standing on a kit building's face.
func _wall_label(text: String, at: Vector3, yaw: float, font_size: int,
		pixel_size: float) -> void:
	var label := Label3D.new()
	label.name = "WallSign_" + text.replace(" ", "")
	label.text = text
	label.font = _font
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.outline_size = 14
	label.outline_modulate = PAINT_DARK
	label.modulate = PAINT_CREAM
	label.position = at
	label.rotation.y = yaw
	add_child(label)


# --------------------------------------------------------------------------
# zone signage and hints


## The five zones: entrance sign pose plus the line the HUD toast shows the
## first time a kart reaches that zone. `at` is plan (x, z); `yaw` turns the
## sign face toward the approach, since a Label3D lies in XY and faces +Z.
const ZONES: Array[Dictionary] = [
	{"id": "PADDOCK", "at": Vector2(12.5, -13.0), "yaw": PI,
		"hint": "Six grid slots, open pit garages and smashable crate stacks."},
	{"id": "HANDLING LOOP", "at": Vector2(12.5, -30.0), "yaw": 0.0,
		"hint": "178 m oval with a speed-trap boost stretch on the north straight."},
	{"id": "SKIDPAD", "at": Vector2(36.0, 28.0), "yaw": -PI * 0.5,
		"hint": "Banked drift bowl. Rail the outer rim to hold continuous drifts."},
	{"id": "JUMP LANE", "at": Vector2(-46.0, 56.0), "yaw": 0.0,
		"hint": "Boost strip into twin kickers. Line up square and send it."},
	{"id": "OFF-ROAD", "at": Vector2(13.5, 33.0), "yaw": PI,
		"hint": "Dirt slalom and crate pyramids. Grip drops here—slide through."},
]
## Sign furniture. Detail only: the post and panel carry no collider, so a
## marker can stand at the tight jump-lane edge (10 m from that centreline)
## without ever reaching tarmac or tripping the clearance audit.
const SIGN_PANEL: Vector3 = Vector3(3.2, 1.15, 0.18)
const SIGN_PLATE: Vector3 = Vector3(2.98, 0.92, 0.08)
const SIGN_POST_HEIGHT: float = 3.2
const SIGN_POST_COLOR: Color = Color("8a8578")


## One sign per zone entrance, all five sharing the same build.
func _zone_signs() -> void:
	for zone: Dictionary in ZONES:
		_zone_sign(str(zone["id"]), zone["at"] as Vector2,
			float(zone["yaw"]))


## Post, dark backer, cream plate and the zone name, all facing `yaw`.
func _zone_sign(zone: String, at: Vector2, yaw: float) -> void:
	var root := Node3D.new()
	root.name = "ZoneSign_" + zone.replace(" ", "")
	root.position = Vector3(at.x, 0.0, at.y)
	root.rotation.y = yaw
	add_child(root)
	_sign_box(root, "Post", Vector3(0.0, SIGN_POST_HEIGHT * 0.5, 0.0),
		Vector3(0.32, SIGN_POST_HEIGHT, 0.32), SIGN_POST_COLOR)
	_sign_box(root, "Backer", Vector3(0.0, SIGN_POST_HEIGHT, 0.0),
		SIGN_PANEL, PAINT_DARK)
	_sign_box(root, "Plate", Vector3(0.0, SIGN_POST_HEIGHT, 0.10),
		SIGN_PLATE, PAINT_CREAM)
	var label := Label3D.new()
	label.name = "ZoneName"
	label.text = zone
	label.font = _font
	label.font_size = 48
	label.pixel_size = 0.0068
	label.outline_size = 6
	label.outline_modulate = PAINT_CREAM
	label.modulate = PAINT_DARK
	label.position = Vector3(0.0, SIGN_POST_HEIGHT, 0.15)
	root.add_child(label)


## One flat-shaded box part of a sign.
func _sign_box(parent: Node3D, part: String, at: Vector3, size: Vector3,
		color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.name = part
	instance.mesh = mesh
	instance.material_override = _flat_material(color)
	instance.position = at
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(instance)


## One cached cartoon material: flat colour, no specular, no metallic.
func _flat_material(color: Color) -> StandardMaterial3D:
	var key: String = color.to_html()
	if _flat_materials.has(key):
		return _flat_materials[key] as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_flat_materials[key] = material
	return material


## Zone id at a world point, or "" on the grass. The HUD reads this once per
## probe, so it is plain rectangle and circle tests plus one spline distance.
func zone_at(at: Vector3) -> String:
	var plan := Vector2(at.x, at.z)
	# The terrace is part of the paddock's furniture, not the dirt.
	if RAISED_PAD.has_point(plan):
		return ""
	if plan.x >= JUMP_X - HALF_TILE and plan.x <= JUMP_X + HALF_TILE \
			and plan.y >= JUMP_LANE_Z1 - HALF_TILE \
			and plan.y <= JUMP_LANE_Z0 + HALF_TILE:
		return "JUMP LANE"
	if SKID_BLOCK.has_point(plan):
		return "SKIDPAD"
	if PADDOCK.has_point(plan):
		return "PADDOCK"
	if DIRT.has_point(plan):
		return "OFF-ROAD"
	if _loop_spline != null \
			and TileKit.spline_distance(_loop_spline, at) <= HALF_TILE:
		return "HANDLING LOOP"
	return ""


## The one-line hint for a zone id, or "" when the id is unknown.
func zone_hint(zone: String) -> String:
	for entry: Dictionary in ZONES:
		if str(entry["id"]) == zone:
			return str(entry["hint"])
	return ""


# --------------------------------------------------------------------------
# pushable props


## Pushables the sandbox syncs: a ten-pylon slalom and three smashable crate
## pyramids placed clear of every grid slot, pit bay and racing lane.
func _pushable_props() -> void:
	for i in 4:
		var z: float = 24.0 + float(i) * 8.0
		_pylon("SlalomPylonL%d" % (i + 1), Vector3(-8.0, ZONE_Y, z))
		_pylon("SlalomPylonR%d" % (i + 1), Vector3(8.0, ZONE_Y, z))
	_pylon("SlalomPylonL5", Vector3(-8.0, ZONE_Y, 56.0))
	_pylon("SlalomPylonR5", Vector3(8.0, ZONE_Y, 56.0))
	_crate_pyramid("PaddockCrate", Vector3(22.5, ZONE_Y, 5.0), 0.0)
	_crate_pyramid("DirtCrateW", Vector3(-22.0, ZONE_Y, 40.0), 0.25)
	_crate_pyramid("DirtCrateE", Vector3(22.0, ZONE_Y, 42.0), -0.25)


## Six-crate smashable pyramid (3 base, 2 middle, 1 apex).
func _crate_pyramid(prefix: String, base_at: Vector3, yaw: float) -> void:
	var step_x: float = 0.74
	var step_y: float = 0.72
	var basis := Basis(Vector3.UP, yaw)
	var serial: int = 1
	for i in 3:
		var offset: Vector3 = basis * Vector3((float(i) - 1.0) * step_x, 0.0, 0.0)
		_crate("%s%d" % [prefix, serial], base_at + offset, yaw)
		serial += 1
	for i in 2:
		var offset: Vector3 = basis * Vector3((float(i) - 0.5) * step_x, step_y, 0.0)
		_crate("%s%d" % [prefix, serial], base_at + offset, yaw)
		serial += 1
	_crate("%s%d" % [prefix, serial], base_at + Vector3.UP * (step_y * 2.0), yaw)


## One light racing-kit pylon (PROP layer, as the sandbox contract expects).
func _pylon(prop_name: String, at: Vector3) -> void:
	var body := RigidBody3D.new()
	body.name = prop_name
	body.add_to_group("pushable")
	body.collision_layer = CollisionLayers.PROP
	body.collision_mask = CollisionLayers.WORLD | CollisionLayers.PROP
	body.mass = 0.35
	# Fast karts cross a 0.12 m cone in one tick; continuous detection keeps the
	# hit, which is what leaves the slalom knocked over instead of untouched.
	body.continuous_cd = true
	body.physics_material_override = _prop_physics()
	body.position = at + Vector3.UP * 0.02
	_prop_visual(body, PYLON_SCENE, "pylon", CONE_SCALE)
	var shape := CylinderShape3D.new()
	shape.height = 0.86
	shape.radius = 0.36
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0.0, 0.43, 0.0)
	body.add_child(collision)
	add_child(body)


## One pushable pit crate (SOLID_PROP, so it also blocks and tumbles on hit).
func _crate(prop_name: String, at: Vector3, yaw: float = 0.0) -> void:
	var body := RigidBody3D.new()
	body.name = prop_name
	body.add_to_group("pushable")
	body.collision_layer = CollisionLayers.PROP | CollisionLayers.SOLID_PROP
	body.collision_mask = CollisionLayers.WORLD | CollisionLayers.PROP
	body.mass = 0.55
	body.continuous_cd = true
	body.physics_material_override = _prop_physics()
	body.position = at + Vector3.UP * 0.02
	body.rotation.y = yaw
	var model: Node3D = CRATE_SCENE.instantiate() as Node3D
	if model != null:
		model.name = "Model"
		body.add_child(model)
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.67, 0.71, 0.67)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0.0, 0.36, 0.0)
	body.add_child(collision)
	add_child(body)


## Instantiates a kit GLB on a pushable body, base centred on the body origin.
func _prop_visual(body: Node3D, packed: PackedScene, model: String,
		scale: float) -> Node3D:
	if packed == null:
		return null
	var node: Node3D = packed.instantiate() as Node3D
	if node == null:
		return null
	var info: Dictionary = TileCatalog.model_info(model)
	if bool(info.get("ok", false)):
		node.transform = _fit_model(model, Vector3.ZERO, 0.0,
			Vector3.ONE * scale)
	body.add_child(node)
	node.name = "Model"
	return node


## Shared physics material for every pushable prop.
func _prop_physics() -> PhysicsMaterial:
	if _prop_material != null:
		return _prop_material
	var mat := PhysicsMaterial.new()
	mat.friction = 0.9
	mat.bounce = 0.15
	_prop_material = mat
	return mat


# --------------------------------------------------------------------------
# surface grip


## Area over the dirt that drops a kart's surface_grip while it stays inside.
## The raised terrace is carved out, so concrete is not reported as dirt.
func _grip_zone() -> void:
	var area := Area3D.new()
	area.name = "DirtGripZone"
	area.collision_layer = 0
	area.collision_mask = CollisionLayers.PLAYER | CollisionLayers.GHOST
	_dirt_rects = [
		Rect2(DIRT.position.x, DIRT.position.y,
			RAISED_PAD.position.x - DIRT.position.x, DIRT.size.y),
		Rect2(RAISED_PAD.position.x, RAISED_PAD.end.y,
			DIRT.end.x - RAISED_PAD.position.x,
			DIRT.end.y - RAISED_PAD.end.y),
	]
	for rect: Rect2 in _dirt_rects:
		var box := BoxShape3D.new()
		box.size = Vector3(rect.size.x, 4.0, rect.size.y)
		var collision := CollisionShape3D.new()
		collision.shape = box
		collision.position = Vector3(rect.get_center().x, 2.0,
			rect.get_center().y)
		area.add_child(collision)
	area.body_entered.connect(_on_dirt_entered)
	area.body_exited.connect(_on_dirt_exited)
	add_child(area)


## Applies the dirt grip while a kart is on the strip.
func _on_dirt_entered(body: Node3D) -> void:
	if not (body.is_in_group("player") or body.is_in_group("ai_player")):
		return
	var id: int = body.get_instance_id()
	_prune_grip()
	# The area is two carved rectangles, so a kart straddling their seam raises
	# the signal twice. Saving the grip again there stored 0.72 as the "dry"
	# value, and the kart kept the dirt grip for the rest of the session.
	if not _grip_before.has(id):
		var grip: float = _surface_grip_of(body)
		if grip < 0.0:
			return
		_grip_before[id] = grip
	body.set("surface_grip", DIRT_GRIP)


## Restores the grip a kart had before it entered the dirt.
func _on_dirt_exited(body: Node3D) -> void:
	_prune_grip()
	if not is_instance_valid(body):
		return
	var id: int = body.get_instance_id()
	if not _grip_before.has(id):
		return
	# Leaving one rectangle is not leaving the dirt: a kart on the seam keeps
	# the low grip until it is clear of every rectangle.
	if _on_dirt(body.global_position):
		return
	body.set("surface_grip", float(_grip_before[id]))
	_grip_before.erase(id)


## True when a plan point is inside any dirt rectangle. The small grow keeps a
## kart sitting exactly on an edge from flickering the grip between frames.
func _on_dirt(at: Vector3) -> bool:
	var plan := Vector2(at.x, at.z)
	for rect: Rect2 in _dirt_rects:
		if rect.grow(0.05).has_point(plan):
			return true
	return false


## Drops saved grips for bodies that left the world while on the strip.
func _prune_grip() -> void:
	for id: int in _grip_before.keys():
		if not is_instance_id_valid(id):
			_grip_before.erase(id)


## Reads the kart's grip property through the property list, so this script
## never has to reference the CartPlayer class on a cold headless boot.
func _surface_grip_of(body: Node3D) -> float:
	for property in body.get_property_list():
		if str(property.get("name", "")) == "surface_grip":
			return float(body.get("surface_grip"))
	return -1.0


# --------------------------------------------------------------------------
# geometry helpers


## Commits the merged ground, paint and raised-terrain meshes.
func _commit_layers() -> void:
	_add_merged("Ground", _ground, _vertex_mat, false)
	_add_merged("PaintedZones", _paint, _vertex_mat, false)
	_add_solid("RaisedTerrain", _solid, _vertex_mat)


## Adds one SurfaceBuf as a single-surface mesh under this node.
func _add_merged(node_name: String, buffer: SurfaceBuf, material: Material,
		shadows: bool) -> MeshInstance3D:
	if buffer.indices.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = buffer.verts
	arrays[Mesh.ARRAY_NORMAL] = buffer.normals
	arrays[Mesh.ARRAY_COLOR] = buffer.colors
	arrays[Mesh.ARRAY_INDEX] = buffer.indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
		if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


## Adds one SolidBuf (sloped, shaded terrain) as a single-surface mesh.
func _add_solid(node_name: String, buffer: SolidBuf,
		material: Material) -> MeshInstance3D:
	if buffer.indices.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = buffer.verts
	arrays[Mesh.ARRAY_NORMAL] = buffer.normals
	arrays[Mesh.ARRAY_COLOR] = buffer.colors
	arrays[Mesh.ARRAY_INDEX] = buffer.indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(instance)
	return instance


## Places a kit model by its measured footprint centre and deck height.
## Kenney flat road pieces (`roadStraight`, `roadCornerSmall`) put their asphalt
## deck at local Y = 0 while `aabb.end.y = +0.01` is kerb height, so lifting by
## ROAD_TOP directly seats the asphalt cleanly at +0.045 m above the Y = 0 grass.
func _fit_road(model: String, at: Vector3, yaw: float, scale: Vector3,
		flat: bool) -> Transform3D:
	var info: Dictionary = TileCatalog.model_info(model)
	if not bool(info.get("ok", false)):
		return Transform3D(Basis(Vector3.UP, yaw).scaled(scale), at)
	var centre: Vector2 = info["center"]
	var aabb: AABB = info["aabb"]
	var yaw_basis := Basis(Vector3.UP, yaw)
	var basis: Basis = yaw_basis * Basis.IDENTITY.scaled(scale)
	var centre_m := Vector3(centre.x * scale.x, 0.0, centre.y * scale.z)
	var lift: float = ROAD_TOP
	if not flat:
		lift = ROAD_TOP - (aabb.position.y + 0.02) * scale.y
	return Transform3D(basis,
		at - yaw_basis * centre_m + Vector3.UP * lift)


## Places a kit model upright with its footprint base on the local origin.
func _fit_model(model: String, at: Vector3, yaw: float,
		scale: Vector3) -> Transform3D:
	var info: Dictionary = TileCatalog.model_info(model)
	if not bool(info.get("ok", false)):
		return Transform3D(Basis(Vector3.UP, yaw).scaled(scale), at)
	var centre: Vector2 = info["center"]
	var aabb: AABB = info["aabb"]
	var yaw_basis := Basis(Vector3.UP, yaw)
	var basis: Basis = yaw_basis * Basis.IDENTITY.scaled(scale)
	var centre_m := Vector3(centre.x * scale.x, 0.0, centre.y * scale.z)
	var lift: float = -aabb.position.y * scale.y
	return Transform3D(basis,
		at - yaw_basis * centre_m + Vector3.UP * lift)


## One unique kit GLB (tent, tower, terrace stand) plus a box collider sized from
## its own measured footprint, so the prop is solid without trusting the export.
func _kit_solid(model: String, at: Vector3, yaw: float, scale: float,
		body: StaticBody3D) -> Node3D:
	var info: Dictionary = TileCatalog.model_info(model)
	if not bool(info.get("ok", false)):
		return null
	var packed: PackedScene = load(str(info["path"])) as PackedScene
	if packed == null:
		return null
	var node: Node3D = packed.instantiate() as Node3D
	if node == null:
		return null
	node.name = "Kit_" + model
	node.transform = _fit_model(model, at, yaw, Vector3.ONE * scale)
	add_child(node)
	var size: Vector3 = (info["aabb"] as AABB).size * scale
	_add_box_shape(body, Transform3D(Basis(Vector3.UP, yaw),
		at + Vector3.UP * (size.y * 0.5)), size)
	if OS.get_environment("CART_DEBUG_PARK") == "1":
		print("KIT SOLID %s at (%.1f, %.1f) size=(%.1f, %.1f, %.1f)" % [
			model, at.x, at.z, size.x, size.y, size.z])
	return node


## One MultiMesh per GLB part for a set of world transforms.
func _batch_road(prefix: String, model: String, transforms: Array) -> void:
	if transforms.is_empty():
		return
	var info: Dictionary = TileCatalog.model_info(model)
	if not bool(info.get("ok", false)):
		return
	var parts: Array = info["parts"]
	for part_index in parts.size():
		var part: Dictionary = parts[part_index]
		var mesh: Mesh = part["mesh"] as Mesh
		var local: Transform3D = part["transform"]
		if mesh == null:
			continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = transforms.size()
		for index in transforms.size():
			multi.set_instance_transform(index,
				(transforms[index] as Transform3D) * local)
		var instance := MultiMeshInstance3D.new()
		instance.name = "%s_%s_%d" % [prefix, model, part_index] \
			if parts.size() > 1 else "%s_%s" % [prefix, model]
		instance.multimesh = multi
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)


## One WORLD body for a set of thin road-deck boxes.
func _static_body(node_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = 0
	add_child(body)
	return body


## Adds a flat road-deck collider whose top sits at ROAD_TOP.
func _add_road_box(body: StaticBody3D, at: Vector3,
		size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(at.x, ROAD_TOP - size.y * 0.5, at.z)
	body.add_child(collision)


## Adds one world-space box collider to a body.
func _add_box_shape(body: StaticBody3D, xform: Transform3D,
		size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = xform
	body.add_child(collision)


## Adds the convex wedge of a roadRamp piece, rising toward -Z.
func _add_ramp_collider(body: StaticBody3D, at: Vector3, scale: Vector3,
		model: String) -> void:
	var info: Dictionary = TileCatalog.model_info(model)
	if not bool(info.get("ok", false)):
		return
	var aabb: AABB = info["aabb"]
	var half_len: float = aabb.size.z * scale.z * 0.5
	var half_w: float = aabb.size.x * scale.x * 0.5 - 0.2
	var lip: float = ROAD_TOP + (aabb.end.y - (aabb.position.y + 0.02)) \
		* scale.y
	var z_toe: float = at.z + half_len
	var z_lip: float = at.z - half_len
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([
		Vector3(at.x - half_w, ROAD_TOP, z_toe),
		Vector3(at.x + half_w, ROAD_TOP, z_toe),
		Vector3(at.x - half_w, 0.0, z_toe),
		Vector3(at.x + half_w, 0.0, z_toe),
		Vector3(at.x + half_w, lip, z_lip),
		Vector3(at.x - half_w, lip, z_lip),
		Vector3(at.x - half_w, 0.0, z_lip),
		Vector3(at.x + half_w, 0.0, z_lip),
	])
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)


## Adds a terrace ramp wedge: level at the deck from `high_x`, dropping to 0 at
## `toe`, spanning `from_z`..`to_z`.
func _add_wedge_shape(body: StaticBody3D, high: Vector3, toe: Vector3,
		height: float) -> void:
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([
		Vector3(high.x, 0.0, high.z), Vector3(toe.x, 0.0, high.z),
		Vector3(high.x, height, high.z),
		Vector3(high.x, 0.0, toe.z), Vector3(toe.x, 0.0, toe.z),
		Vector3(high.x, height, toe.z),
	])
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)


## Arc-length position on a spline nearest a world x/z point.
func _nearest_distance(spline: RingSpline, at: Vector2) -> float:
	if spline == null:
		return 0.0
	var hit: Dictionary = spline.closest(Vector3(at.x, 0.0, at.y))
	return float(hit.get("s", 0.0))


# --------------------------------------------------------------------------
# invariants


## Publishes the two invariants this facility must hold on every boot.
##
## 1. The authored spawn looks down the paddock at the loop's first tile, with
##    the grandstand behind it. Both come from the live scene marker, so a scene
##    edit that flips the spawn fails here instead of shipping.
## 2. No solid prop reaches the tarmac. Every WORLD collider sample is measured
##    against the loop centreline and the jump lane; anything inside
##    SOLID_LIMIT of a racing centreline is an error.
func _audit_facility() -> void:
	var spawn: Transform3D = _spawn_transform()
	var forward: Vector3 = -spawn.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var spawn_flat := Vector3(spawn.origin.x, 0.0, spawn.origin.z)
	var gate_point: Vector2 = _gate_point()
	var gate := Vector3(gate_point.x, 0.0, gate_point.y)
	var to_gate: Vector3 = (gate - spawn_flat).normalized()
	var tile0: Vector3 = _loop_cell_centre(LOOP_RING[0])
	var to_tile: Vector3 = tile0 - spawn_flat
	to_tile.y = 0.0
	to_tile = to_tile.normalized()
	var gate_dot: float = forward.dot(to_gate)
	var tile_dot: float = forward.dot(to_tile)
	var first: Vector2 = _loop_first_direction()
	var stand := Vector3(STAND_CELL.x, PAD_TOP, STAND_CELL.y)
	var stand_gap: float = (stand - spawn.origin).dot(forward)
	print("SANDBOX FACING spawn=(%.2f, %.2f, %.2f) forward=(%.2f, %.2f, %.2f) gate=(%.1f, %.1f) gate_dot=%.3f | loop tile0=%s centre=(%.1f, %.1f) travel=(%.0f, %.0f) tile_dot=%.3f | stand=(%.1f, %.1f) behind=%.1f m" % [
		spawn.origin.x, spawn.origin.y, spawn.origin.z,
		forward.x, forward.y, forward.z, gate_point.x, gate_point.y, gate_dot,
		LOOP_RING[0], tile0.x, tile0.z, first.x, first.y, tile_dot,
		stand.x, stand.z, -stand_gap])
	if gate_dot < 0.95 or tile_dot < 0.90 or stand_gap > -4.0:
		push_error("sandbox_park: the paddock faces the wrong way (gate_dot=%.3f tile_dot=%.3f stand_behind=%.1f m). The spawn must look down the paddock at the loop with the grandstand behind it." % [
			gate_dot, tile_dot, -stand_gap])
	_audit_clearance()


## The spawn marker from the live sandbox scene, or the authored fallback.
func _spawn_transform() -> Transform3D:
	var marker: Node3D = get_tree().get_first_node_in_group("spawn_point") \
		as Node3D
	if marker != null:
		return marker.global_transform
	return Transform3D(Basis.IDENTITY, SPAWN_POINT)


## The pit gate from the live sandbox scene, or the authored fallback. The scene
## marker and the bots' LOOP_GATE are the same plan point.
func _gate_point() -> Vector2:
	var marker: Node3D = get_tree().get_first_node_in_group("loop_gate") \
		as Node3D
	if marker != null:
		return Vector2(marker.global_position.x, marker.global_position.z)
	return LOOP_GATE


## Measures every solid collider sample against the racing surfaces and reports
## the closest approach, plus how many pieces sit between the road edge and the
## barrier clearance (the kit's own run-off furniture).
func _audit_clearance() -> void:
	var closest: float = INF
	var closest_name: String = ""
	var solids: int = 0
	var shapes: int = 0
	var tight: int = 0
	var offenders: int = 0
	for child: Node in _solid_bodies():
		var body_name: String = String(child.name)
		var found: bool = false
		for part: Node in child.get_children():
			var collision := part as CollisionShape3D
			if collision == null or collision.shape == null:
				continue
			shapes += 1
			found = true
			var distance: float = INF
			for point: Vector3 in _shape_points(collision.shape,
					collision.global_transform):
				distance = minf(distance, _road_distance(point))
			if distance < closest:
				closest = distance
				closest_name = body_name
			if distance < TileKit.BARRIER_CLEARANCE - 0.02:
				tight += 1
			if distance < SOLID_LIMIT:
				offenders += 1
		if found:
			solids += 1
	if closest == INF:
		closest = 0.0
	print("SOLID CLEARANCE solids=%d shapes=%d closest=%.2f m at %s (hard limit %.2f, barrier clearance %.2f) tight=%d offenders=%d -> %s" % [
		solids, shapes, closest, closest_name if closest_name != "" else "-",
		SOLID_LIMIT, TileKit.BARRIER_CLEARANCE, tight, offenders,
		"CLEARS" if offenders == 0 else "ON THE ROAD"])
	if offenders > 0:
		push_error("sandbox_park: %d solid collider(s) inside %.2f m of a racing centreline (closest %.2f m at %s)." % [
			offenders, SOLID_LIMIT, closest, closest_name])


## Every solid body under the park, barrier holders included, minus the bodies
## that ARE the racing surface.
func _solid_bodies() -> Array[Node]:
	var bodies: Array[Node] = []
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child: Node in node.get_children():
			if SOLID_SKIP.has(String(child.name)):
				continue
			if child is StaticBody3D or child is RigidBody3D:
				bodies.append(child)
				continue
			stack.append(child)
	return bodies


## Plan distance from a world point to the nearest racing surface.
func _road_distance(point: Vector3) -> float:
	var best: float = _segment_distance(point,
		Vector3(JUMP_X, 0.0, JUMP_LANE_Z0), Vector3(JUMP_X, 0.0, JUMP_LANE_Z1))
	if _loop_spline == null:
		return best
	var pad: float = LOOP_AUDIT_PAD
	var box := Rect2(-32.0 - pad, LOOP_CELL_Z - pad, 64.0 + pad * 2.0,
		32.0 + pad * 2.0)
	var flat := Vector2(point.x, point.z)
	if not box.has_point(flat):
		# Outside the loop's grown bounds: the spline is provably further away
		# than the padding, so the box distance is a safe lower bound.
		return minf(best, pad + Vector2(flat.x - clampf(flat.x, box.position.x,
			box.end.x), flat.y - clampf(flat.y, box.position.y,
			box.end.y)).length())
	return minf(best, TileKit.spline_distance(_loop_spline, point))


## Plan distance from a world point to a line segment.
func _segment_distance(point: Vector3, from: Vector3, to: Vector3) -> float:
	var flat := Vector2(point.x, point.z)
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	var ab: Vector2 = b - a
	var t: float = 0.0
	if ab.length_squared() > 0.000001:
		t = clampf((flat - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return flat.distance_to(a + ab * t)


## World sample points of one collision shape, for the clearance audit.
func _shape_points(shape: Shape3D, xform: Transform3D) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var box := shape as BoxShape3D
	if box != null:
		var half: Vector3 = box.size * 0.5
		for ix: float in [-1.0, 1.0]:
			for iy: float in [-1.0, 1.0]:
				for iz: float in [-1.0, 1.0]:
					points.append(xform * Vector3(half.x * ix, half.y * iy,
						half.z * iz))
		return points
	var cylinder := shape as CylinderShape3D
	if cylinder != null:
		for ix: float in [-1.0, 1.0]:
			for iy: float in [-1.0, 1.0]:
				for iz: float in [-1.0, 1.0]:
					points.append(xform * Vector3(cylinder.radius * ix,
						cylinder.height * 0.5 * iy, cylinder.radius * iz))
		return points
	var sphere := shape as SphereShape3D
	if sphere != null:
		for axis: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP,
				Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
			points.append(xform * (axis * sphere.radius))
		return points
	var convex := shape as ConvexPolygonShape3D
	if convex != null:
		for point: Vector3 in convex.points:
			points.append(xform * point)
		return points
	points.append(xform.origin)
	return points


# --------------------------------------------------------------------------
# diagnostics


## One-line park census, enabled with CART_DEBUG_PARK=1 for rebuild audits.
func _report_stats() -> void:
	var meshes: int = 0
	var multimeshes: int = 0
	var surfaces: int = 0
	var labels: int = 0
	var bodies: int = 0
	var colliders: int = 0
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is MeshInstance3D:
			var mesh: Mesh = (node as MeshInstance3D).mesh
			if mesh != null:
				meshes += 1
				surfaces += mesh.get_surface_count()
		elif node is MultiMeshInstance3D:
			var multi: MultiMesh = (node as MultiMeshInstance3D).multimesh
			if multi != null and multi.mesh != null:
				multimeshes += 1
				surfaces += multi.mesh.get_surface_count()
		elif node is Label3D:
			labels += 1
		elif node is StaticBody3D or node is RigidBody3D:
			bodies += 1
		elif node is CollisionShape3D:
			colliders += 1
	print("SANDBOX PARK STATS nodes=%d mesh=%d multimesh=%d surfaces=%d labels=%d draw_calls=%d bodies=%d colliders=%d pushable=%d" % [
		get_tree().get_node_count(), meshes, multimeshes, surfaces, labels,
		surfaces + labels, bodies, colliders,
		get_tree().get_nodes_in_group("pushable").size()])
	var gpu: int = int(RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	print("SANDBOX PARK GPU draw_calls=%d (0 under the headless dummy renderer)" % gpu)
	var signs: Array[String] = []
	for zone: Dictionary in ZONES:
		var sign_node: Node = get_node_or_null(
			"ZoneSign_" + str(zone["id"]).replace(" ", ""))
		signs.append("%s:%s" % [str(zone["id"]),
			"ok" if sign_node != null else "MISSING"])
	print("SANDBOX ZONES signs=%s spawn=%s" % [", ".join(signs),
		zone_at(_spawn_transform().origin)])
	TileKit.assert_barrier_clearance(_perimeter_barriers, _perimeter_spline,
		"PERIMETER")
	TileKit.assert_barrier_clearance(_loop_barriers, _loop_spline, "LOOP")


## Debug-only bot sanity probe. CART_DEBUG_PARK=1 prints how far each free-roam
## bot drove in 12 simulated seconds, which is the contract
## pi_setup/tests/sandbox_bot_sim.gd enforces. Deferred so sandbox.gd has already
## spawned the bots, and counted in physics frames so a headless soak measures
## the same window as the test.
func _bot_probe() -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var carts: Array[Node] = get_tree().get_nodes_in_group("ai_player")
	if carts.is_empty():
		print("BOT TRAVEL carts=0 (bots are opt-in; enable them in settings to run the free-roam probe)")
		return
	var from: Array[Vector3] = []
	for cart: Node in carts:
		from.append((cart as Node3D).global_position)
	var start: int = Engine.get_physics_frames()
	while Engine.get_physics_frames() - start < 720:
		await get_tree().process_frame
		if not is_inside_tree():
			return
	for index in mini(carts.size(), from.size()):
		var cart: Node = carts[index]
		if not is_instance_valid(cart):
			continue
		var drove: float = (cart as Node3D).global_position.distance_to(
			from[index])
		print("BOT TRAVEL bot=%d drove=%.1f m in 12 s" % [index, drove])
	print("BOT TRAVEL carts=%d" % carts.size())
	var root: Node = get_parent()
	var bots: Array = []
	if root != null and root.get("_bots") is Array:
		bots = root.get("_bots")
	for index in bots.size():
		var bot: Variant = bots[index]
		print("BOT STATE %d dest=%s drove=%.0f m stuck=%.2f stranded=%.2f zones=%d" % [
			index, str(bot.get("destination_name")),
			float(bot.get("distance_driven")), float(bot.get("stuck")),
			float(bot.get("stranded")), int(bot.get("distinct_zones"))])
