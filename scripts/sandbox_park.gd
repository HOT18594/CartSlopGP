extends Node3D
## Cartoon TEST FACILITY for the sandbox, rebuilt on the Kenney 16 m tile grid.
##
## The old park was a realistic heightfield with scanned textures and bespoke
## boxes. This version is flat, bold and built from the CC0 Kenney racing and
## nature kits, on the same 16 m module the race maps use. Every zone is a whole
## number of tiles, and every prop the kit places sits on a cell centre (or a
## cell edge for a two-cell piece), so nothing half-overlaps a neighbour.
##
## The five zones keep the destinations the sandbox bots already drive to:
##   - PADDOCK: painted apron, six grid slots (the multiplayer contract),
##     two kit pit garages, a grandstand, flags and floodlights.
##   - HANDLING LOOP: a five-by-three grid oval of roadStraight/roadCornerSmall
##     pieces, 178 m of cartoon tarmac with a start band and tyre stacks.
##   - SKIDPAD: a 28 m painted circle inscribed in a 2x2 tile concrete pad.
##   - JUMP LANE: a full-tile roadRamp and a two-cell roadRampLong in one line,
##     with a checkered launch band.
##   - OFF-ROAD: a dirt block with the cone slalom and the lower-grip zone.
##
## The ground is ONE flat collision slab. Kit road pieces carry their own thin
## WORLD colliders (flush with the visible deck); ramps get convex wedges that
## match the slope. Every barrier, building, light, flag, billboard, tyre stack
## and tree the kit adds is solid on CollisionLayers.WORLD, and every solid
## carries a real shape instead of trusting the GLB (the Kenney exports ship
## without colliders).
##
## The handling loop is the one lattice that is phase-shifted: its cell centres
## are anchored at (0, -38) so the oval lines up with the racing line the sandbox
## bots pre-compute from the old spline. It still uses the same 16 m tiles and
## the same quarter-tile rules as every other zone.
##
## Pushables keep the "pushable" group and the PROP/SOLID_PROP layers sandbox.gd
## syncs. The dirt Area3D keeps the `surface_grip` contract (lower grip on dirt,
## restored on exit).

const TileKit := preload("res://scripts/minigames/tile_kit.gd")
const TileCatalog := preload("res://scripts/minigames/tiles/tile_catalog.gd")
const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")

const PYLON_MODEL: String = "res://assets/models/kenney_racing_kit/Models/GLTF format/pylon.glb"
const CRATE_MODEL: String = "res://assets/models/kenney_car-kit/Models/GLB format/box.glb"
const TITLE_FONT: String = "res://assets/ui/fonts/LuckiestGuy-Regular.ttf"

# Grid. TILE is the race maps' measured 16 m module.
const TILE: float = TileCatalog.TILE_SIZE
const HALF_TILE: float = TILE * 0.5
const ROAD_TOP: float = 0.04
const ZONE_Y: float = 0.015
const PAINT_Y: float = 0.03

# World boundary: barriers stand on the tile edge at +/-64.
const FIELD: float = 64.0
const BARRIER_IN: float = 6.5
const PERIMETER_HALF: float = FIELD - BARRIER_IN
const CORNER_RADIUS: float = 16.0
const ENTRY_GAP: float = 16.0

# Zone rectangles in world x/z, every edge a multiple of the 16 m tile.
const PADDOCK := Rect2(-32.0, -16.0, 64.0, 32.0)
const PIT_PAD := Rect2(-48.0, -16.0, 32.0, 16.0)
const SKID_BLOCK := Rect2(32.0, 0.0, 32.0, 32.0)
const SKID_CENTRE := Vector2(48.0, 16.0)
const SKID_RADIUS: float = 14.0
const DIRT := Rect2(-32.0, 16.0, 64.0, 48.0)
const DIRT_GRIP: float = 0.72

# Handling loop: 5 x 3 ring of 16 m cells centred on the old lap centre.
const LOOP_CELL_X: float = -32.0
const LOOP_CELL_Z: float = -54.0
const LOOP_CENTRE := Vector2(0.0, -38.0)
const LOOP_RING: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
	Vector2i(4, 0), Vector2i(4, 1), Vector2i(4, 2), Vector2i(3, 2),
	Vector2i(2, 2), Vector2i(1, 2), Vector2i(0, 2), Vector2i(0, 1),
]

# Jump lane: one tile wide, centred on the bots' staging line at x = -52.
const JUMP_X: float = -56.0
const JUMP_PIECES: Array[Dictionary] = [
	{"model": "roadStraight", "z": 40.0, "flat": true, "yscale": 1.0},
	{"model": "roadRamp", "z": 24.0, "flat": false, "yscale": 0.60},
	{"model": "roadStraight", "z": 8.0, "flat": true, "yscale": 1.0},
	{"model": "roadRampLong", "z": -16.0, "flat": false, "yscale": 0.24},
]

# The multiplayer grid contract: sandbox.gd mirrors these centres and parks the
# local cart on slot 5 (index 4) at (0, 13). They are a 9 m minor lattice inside
# the paddock, deliberately kept so grid slots and spawns agree.
const GRID_SLOTS: Array[Vector2] = [
	Vector2(-9.0, 5.0), Vector2(0.0, 5.0), Vector2(9.0, 5.0),
	Vector2(-9.0, 13.0), Vector2(0.0, 13.0), Vector2(9.0, 13.0),
]
const GRID_HALF := Vector2(2.1, 2.7)

# Cartoon palette. Flat vertex colours only: no scans, no normal maps.
const GRASS_A := Color("7bd34f")
const GRASS_B := Color("6cc143")
const OUTFIELD := Color("58ab3f")
const APRON := Color("f4ead2")
const PIT_PAD_TINT := Color("d9d2c0")
const CONCRETE := Color("c9d3d8")
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
class SurfaceBuf:
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()

	## Adds one up-facing triangle; swaps two points when the winding is down.
	func tri(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
		if (b - a).cross(c - a).y < 0.0:
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
		var count: int = maxi(segments, 8)
		for i in count:
			var a0: float = TAU * float(i) / float(count)
			var a1: float = TAU * float(i + 1) / float(count)
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
var _loop_spline: RingSpline
var _perimeter_spline: RingSpline
var _vertex_mat: StandardMaterial3D
var _prop_material: PhysicsMaterial
var _grip_before: Dictionary = {}


func _ready() -> void:
	_rng.seed = 90421
	_font = load(TITLE_FONT) as Font
	_vertex_mat = _make_vertex_material()
	_ground_plane()
	_zone_paint()
	_paddock()
	_handling_loop()
	_jump_lane()
	_dressing()
	_pushable_props()
	_grip_zone()
	_commit_layers()
	if OS.get_environment("CART_DEBUG_PARK") == "1":
		_report_stats()


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
	for ix in 24:
		for iz in 24:
			var tint: Color = GRASS_A if (ix + iz) % 2 == 0 else GRASS_B
			_ground.rect(Rect2(-96.0 + float(ix) * cell,
				-96.0 + float(iz) * cell, cell, cell), 0.0, tint)
	var outer: float = 600.0
	var inner: float = 96.0
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


## Painted zones: paddock apron, pit pad, skid block, dirt block and links.
func _zone_paint() -> void:
	# Paddock apron and its bold outline.
	_paint.rect(PADDOCK, ZONE_Y, APRON)
	_paint.outline(PADDOCK.grow(-0.9), 0.5, PAINT_Y, PAINT_DARK)
	_paint.outline(PADDOCK.grow(-1.8), 0.22, PAINT_Y, PAINT_YELLOW)
	# Pit pad in front of the garages, west of the paddock.
	_paint.rect(PIT_PAD, ZONE_Y + 0.002, PIT_PAD_TINT)
	_paint.outline(PIT_PAD.grow(-0.7), 0.4, PAINT_Y + 0.002, PAINT_YELLOW)
	# Tarmac link from the paddock to the loop gate.
	_paint.rect(Rect2(-16.0, -16.0, 32.0, 16.0), ZONE_Y + 0.004, TARMAC)
	_paint.line(Vector2(-16.0, -15.0), Vector2(16.0, -15.0), 0.26,
		PAINT_Y + 0.004, PAINT_BLUE)
	_paint.line(Vector2(-15.0, -16.0), Vector2(-15.0, -9.0), 0.26,
		PAINT_Y + 0.004, PAINT_BLUE)
	_paint.line(Vector2(15.0, -16.0), Vector2(15.0, -9.0), 0.26,
		PAINT_Y + 0.004, PAINT_BLUE)
	# Paddock link to the jump lane: one grid cell at (-40, 8).
	_paint.rect(Rect2(-48.0, 0.0, 16.0, 16.0), ZONE_Y + 0.003, TARMAC)
	_paint.line(Vector2(-48.0, 0.8), Vector2(-32.0, 0.8), 0.26,
		PAINT_Y + 0.003, PAINT_CREAM)
	_paint.line(Vector2(-48.0, 15.2), Vector2(-32.0, 15.2), 0.26,
		PAINT_Y + 0.003, PAINT_CREAM)
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
	_paint.rect(Rect2(16.0, 64.0, 16.0, 32.0), ZONE_Y + 0.002, DIRT_TAN)
	_paint.line(Vector2(16.8, 64.0), Vector2(16.8, 96.0), 0.3, PAINT_Y,
		PAINT_CREAM)
	_paint.line(Vector2(31.2, 64.0), Vector2(31.2, 96.0), 0.3, PAINT_Y,
		PAINT_CREAM)
	# Six painted grid slots on the paddock.
	for i in GRID_SLOTS.size():
		_paint_slot(GRID_SLOTS[i], PAINT_CREAM)
	# Launch band just before the ramp toe.
	for i in 8:
		var shade: Color = PAINT_CREAM if i % 2 == 0 else PAINT_DARK
		_paint.rect(Rect2(JUMP_X - 5.5 + float(i) * 1.375, 44.0, 1.375, 1.0),
			ROAD_TOP + 0.008, shade)
	_paint.line(Vector2(JUMP_X - 5.7, 43.4), Vector2(JUMP_X + 5.7, 43.4),
		0.2, ROAD_TOP + 0.008, PAINT_ORANGE)
	_paint.line(Vector2(JUMP_X - 5.7, 45.6), Vector2(JUMP_X + 5.7, 45.6),
		0.2, ROAD_TOP + 0.008, PAINT_ORANGE)


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
# paddock


## Paddock furniture: six numbered slots, two kit garages and their sign.
func _paddock() -> void:
	for i in GRID_SLOTS.size():
		_grid_number(i + 1, GRID_SLOTS[i])
	TileKit.pit_building(self, [Vector2i(-3, -1), Vector2i(-2, -1)])
	_wall_label("PADDOCK", Vector3(-32.0, 7.4, 1.2), 0.0, 128, 0.0085)


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


## Five-by-three grid oval of kit road pieces, its colliders and its spline.
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
	_loop_dressing()


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


## Checkered start/finish band at the loop's paddock-side straight.
func _loop_start_band() -> void:
	if _loop_spline == null:
		return
	var distance: float = _nearest_distance(_loop_spline, Vector2(0.0, -22.0))
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


## Five cartoon tyre stacks on the outside of the loop, clear of the lane.
func _loop_dressing() -> void:
	var anchors: Array[Vector2] = [
		Vector2(-24.0, -54.0), Vector2(0.0, -54.0), Vector2(24.0, -54.0),
		Vector2(-32.0, -38.0), Vector2(32.0, -38.0),
	]
	for anchor: Vector2 in anchors:
		var distance: float = _nearest_distance(_loop_spline, anchor)
		TileKit.tyre_stack(self, _loop_spline, distance, -1.0)


# --------------------------------------------------------------------------
# jump lane


## One straight, one short kicker, one landing straight and one long kicker.
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


# --------------------------------------------------------------------------
# perimeter and kit dressing


## Park boundary: rounded-rect spline, barrierLine run with one south entry gap.
func _dressing() -> void:
	_perimeter_spline = RingSpline.new(_perimeter_path())
	_barrier_line()
	_grandstand()
	_lights()
	_flags()
	_billboards()
	_trees()


## Sampled rounded-rectangle path inset so the kit barriers land on +/-64.
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
	TileKit.barrier_line(self, _perimeter_spline, gap + half_gap,
		gap - half_gap, side, "barrierRed")


## Covered grandstand on the paddock side of the loop's south straight.
func _grandstand() -> void:
	if _loop_spline == null:
		return
	var distance: float = _nearest_distance(_loop_spline, Vector2(24.0, -22.0))
	var frame: Dictionary = _loop_spline.sample(distance)
	var right: Vector3 = frame["right"]
	var side: float = 1.0 if right.z > 0.0 else -1.0
	TileKit.grandstand(self, _loop_spline, distance, side, true)


## Four tall floodlights on the grass, clear of tarmac and buildings.
func _lights() -> void:
	TileKit.lights(self, [
		Vector3(-56.0, 0.0, 56.0), Vector3(56.0, 0.0, 56.0),
		Vector3(56.0, 0.0, -8.0), Vector3(-56.0, 0.0, -40.0),
	])


## Flags on the paddock corners and the dirt strip.
func _flags() -> void:
	TileKit.flags(self, [
		{"position": Vector3(-24.0, 0.0, 8.0), "kind": "flagCheckers",
			"yaw": 0.0},
		{"position": Vector3(24.0, 0.0, 8.0), "kind": "flagRed", "yaw": 0.0},
		{"position": Vector3(-24.0, 0.0, 24.0), "kind": "flagGreen",
			"yaw": 0.0},
		{"position": Vector3(24.0, 0.0, 24.0), "kind": "flagCheckersSmall",
			"yaw": 0.0},
	])


## Three billboards facing their zones, each with a readable cartoon label.
func _billboards() -> void:
	TileKit.signage(self, [
		{"position": Vector3(40.0, 0.0, 40.0), "kind": "billboard",
			"yaw": PI},
		{"position": Vector3(-40.0, 0.0, 40.0), "kind": "billboard",
			"yaw": PI * 0.5},
		{"position": Vector3(56.0, 0.0, -40.0), "kind": "billboard",
			"yaw": -PI * 0.5},
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


## Cartoon tree line outside the barriers on the 16 m grid.
func _trees() -> void:
	var spots: Array = []
	for x: float in [-88.0, -72.0, -40.0, -8.0, 24.0, 56.0, 88.0]:
		# The dirt service lane leaves the south fence at x = 24; keep it clear.
		if x > 8.0 and x < 40.0:
			spots.append(Vector3(x, 0.0, -72.0))
			spots.append(Vector3(x, 0.0, -88.0))
			continue
		spots.append(Vector3(x, 0.0, 72.0))
		spots.append(Vector3(x, 0.0, 88.0))
		spots.append(Vector3(x, 0.0, -72.0))
		spots.append(Vector3(x, 0.0, -88.0))
	for z: float in [-56.0, -24.0, 8.0, 40.0]:
		spots.append(Vector3(-88.0, 0.0, z))
		spots.append(Vector3(88.0, 0.0, z))
	TileKit.trees(self, spots, _loop_spline)


## Small text panel standing on the pit buildings' front face.
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
# pushable props


## Pushables the sandbox syncs: a ten-pylon slalom and four pit crates.
func _pushable_props() -> void:
	for i in 4:
		var z: float = 24.0 + float(i) * 8.0
		_pylon("SlalomPylonL%d" % (i + 1), Vector3(-8.0, ZONE_Y, z))
		_pylon("SlalomPylonR%d" % (i + 1), Vector3(8.0, ZONE_Y, z))
	_pylon("SlalomPylonL5", Vector3(-8.0, ZONE_Y, 56.0))
	_pylon("SlalomPylonR5", Vector3(8.0, ZONE_Y, 56.0))
	for i in 4:
		_crate("PaddockCrate%d" % (i + 1),
			Vector3(20.0 + float(i % 2), ZONE_Y, 3.0 + float(i / 2)))


## One light racing-kit pylon (PROP layer, as the sandbox contract expects).
func _pylon(prop_name: String, at: Vector3) -> void:
	var body := RigidBody3D.new()
	body.name = prop_name
	body.add_to_group("pushable")
	body.collision_layer = CollisionLayers.PROP
	body.collision_mask = CollisionLayers.WORLD | CollisionLayers.PROP
	body.mass = 0.35
	body.continuous_cd = false
	body.physics_material_override = _prop_physics()
	body.position = at + Vector3.UP * 0.02
	_prop_visual(body, PYLON_MODEL, TILE * 0.45)
	var shape := CylinderShape3D.new()
	shape.height = 0.86
	shape.radius = 0.36
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0.0, 0.43, 0.0)
	body.add_child(collision)
	add_child(body)


## One pushable pit crate (SOLID_PROP, so it also blocks the kart).
func _crate(prop_name: String, at: Vector3) -> void:
	var body := RigidBody3D.new()
	body.name = prop_name
	body.add_to_group("pushable")
	body.collision_layer = CollisionLayers.PROP | CollisionLayers.SOLID_PROP
	body.collision_mask = CollisionLayers.WORLD | CollisionLayers.PROP
	body.mass = 0.8
	body.continuous_cd = true
	body.physics_material_override = _prop_physics()
	body.position = at + Vector3.UP * 0.02
	var model: Node3D = (load(CRATE_MODEL) as PackedScene).instantiate() as Node3D
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
func _prop_visual(body: Node3D, path: String, scale: float) -> Node3D:
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return null
	var node: Node3D = packed.instantiate() as Node3D
	if node == null:
		return null
	var model: String = path.get_file().get_basename()
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
func _grip_zone() -> void:
	var area := Area3D.new()
	area.name = "DirtGripZone"
	area.collision_layer = 0
	area.collision_mask = CollisionLayers.PLAYER | CollisionLayers.GHOST
	var box := BoxShape3D.new()
	box.size = Vector3(DIRT.size.x, 4.0, DIRT.size.y)
	var collision := CollisionShape3D.new()
	collision.shape = box
	collision.position = Vector3(DIRT.get_center().x, 2.0,
		DIRT.get_center().y)
	area.add_child(collision)
	area.body_entered.connect(_on_dirt_entered)
	area.body_exited.connect(_on_dirt_exited)
	add_child(area)


## Applies the dirt grip while a kart is on the strip.
func _on_dirt_entered(body: Node3D) -> void:
	if not (body.is_in_group("player") or body.is_in_group("ai_player")):
		return
	var grip: float = _surface_grip_of(body)
	if grip < 0.0:
		return
	_grip_before[body.get_instance_id()] = grip
	body.set("surface_grip", DIRT_GRIP)


## Restores the grip a kart had before it entered the dirt.
func _on_dirt_exited(body: Node3D) -> void:
	if not is_instance_valid(body):
		return
	var id: int = body.get_instance_id()
	if not _grip_before.has(id):
		return
	body.set("surface_grip", float(_grip_before[id]))
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


## Commits the merged ground and paint meshes. One draw call each.
func _commit_layers() -> void:
	_add_merged("Ground", _ground, _vertex_mat, false)
	_add_merged("PaintedZones", _paint, _vertex_mat, false)


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


## Places a kit model by its measured footprint centre and deck height.
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
	var lift: float = ROAD_TOP - aabb.end.y * scale.y
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


## Arc-length position on a spline nearest a world x/z point.
func _nearest_distance(spline: RingSpline, at: Vector2) -> float:
	if spline == null:
		return 0.0
	var hit: Dictionary = spline.closest(Vector3(at.x, 0.0, at.y))
	return float(hit.get("s", 0.0))


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
