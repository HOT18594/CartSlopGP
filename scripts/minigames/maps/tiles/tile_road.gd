extends RefCounted
## Road surface, kerbs, barriers, catch fencing and paint for a tile map.
##
## Everything here is merged: the tarmac, the two shoulders, the kerbs, the armco,
## the catch fence, the tyre walls, the paint and the wet/ice sheen are each one
## mesh (plus a WORLD collision body) for the whole lap. A 500 m tile circuit
## therefore costs a handful of draw calls instead of one node per prop, which is
## what makes the density affordable.
##
## The road follows the derived centreline exactly, including the elevation
## profile and a jump tile's crest, so the kart drives on the surface it sees.
## The shoulder drops away below the ground plane, which hides the seam between
## an elevated tile and the flat world plane without a terrain mesh.

const TileCatalog := preload("res://scripts/minigames/maps/tiles/tile_catalog.gd")
const RaceKit := preload("res://scripts/minigames/racing_kit.gd")
const SceneryKit := preload("res://scripts/minigames/scenery/scenery_kit.gd")
const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")

## Metres per texture repeat along the road and the shoulder.
const UV_SCALE: float = 6.0
const SHOULDER_OUT: float = 6.0
const SHOULDER_DROP: float = 2.6
## Visible armco and catch fence, measured from the centreline. Both sit outside
## the race controller's invisible wall at ROAD_HALF + 0.5 so they never pinch
## the racing surface.
const BARRIER_LATERAL: float = 6.65
const FENCE_LATERAL: float = 8.9
const TYRE_LATERAL: float = 8.1
const PAINT_Y: float = TileCatalog.ROAD_Y + 0.018
const WHITE := Color("f4f1e6")
const DARK_PAINT := Color("2f2a26")


## Builds every track surface and returns what was placed.
static func build(parent: Node3D, spline: RefCounted, layout: RefCounted,
		palette: Dictionary) -> Dictionary:
	var stats: Dictionary = {
		"draws": 0, "kerb_runs": 0, "barrier_runs": 0, "fence_runs": 0,
		"tyre_walls": 0, "tyre_stacks": 0, "paint_pieces": 0,
	}
	if parent == null or spline == null or layout == null:
		return stats
	_road(parent, spline, layout, palette["road"] as Material, stats)
	_shoulders(parent, spline, layout, palette["shoulder"] as Material, stats)
	_kerbs(parent, spline, layout, palette, stats)
	_armco(parent, spline, layout, stats)
	_fence(parent, spline, layout, stats)
	_tyre_walls(parent, spline, layout, stats)
	_paint(parent, spline, layout, stats)
	_sheens(parent, spline, layout, palette, stats)
	return stats


# --------------------------------------------------------------------------
# driving surface


## One asphalt ribbon with baked UVs and a solid concave driving surface.
static func _road(parent: Node3D, spline: RefCounted, layout: RefCounted,
		material: Material, stats: Dictionary) -> void:
	var points: PackedVector3Array = spline.points
	var count: int = points.size()
	if count < 3:
		return
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var faces := PackedVector3Array()
	for i in count:
		var frame: Dictionary = spline.sample(spline.cumulative[i])
		var centre: Vector3 = points[i] + Vector3.UP * TileCatalog.ROAD_Y
		var right: Vector3 = frame["right"]
		var half: float = layout.half_width_at(spline.cumulative[i])
		verts.append(centre - right * half)
		verts.append(centre + right * half)
		norms.append(Vector3.UP)
		norms.append(Vector3.UP)
		var v: float = spline.cumulative[i] / UV_SCALE
		uvs.append(Vector2(0.0, v))
		uvs.append(Vector2(1.0, v))
	for i in count:
		var a: int = i * 2
		var b: int = ((i + 1) % count) * 2
		indices.append(a)
		indices.append(b)
		indices.append(a + 1)
		indices.append(a + 1)
		indices.append(b)
		indices.append(b + 1)
		faces.append_array([verts[a], verts[b], verts[a + 1],
			verts[a + 1], verts[b], verts[b + 1]])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var visual := MeshInstance3D.new()
	visual.name = "TileRoad"
	visual.mesh = mesh
	visual.material_override = material
	parent.add_child(visual)
	stats["draws"] = int(stats["draws"]) + 1
	_add_collision(parent, "TileRoadCollision", faces, false)


## Grass (or concrete/snow) banks outside the kerb line. The outer edge sits
## below the ground plane, so an elevated tile's bank disappears into the world
## instead of leaving a floating edge.
static func _shoulders(parent: Node3D, spline: RefCounted, layout: RefCounted,
		material: Material, stats: Dictionary) -> void:
	var points: PackedVector3Array = spline.points
	var count: int = points.size()
	if count < 3:
		return
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var faces := PackedVector3Array()
	for side: float in [-1.0, 1.0]:
		var base: int = verts.size()
		for i in count:
			var frame: Dictionary = spline.sample(spline.cumulative[i])
			var right: Vector3 = frame["right"]
			var half: float = layout.half_width_at(spline.cumulative[i])
			var inner: Vector3 = points[i] + right * (half * side) \
				+ Vector3.UP * (TileCatalog.ROAD_Y - 0.02)
			# The outer edge always meets the flat world plane, so an elevated
			# tile becomes a banked berm instead of a floating ribbon.
			var outer: Vector3 = points[i] + right * ((half + SHOULDER_OUT) * side) \
				+ Vector3.UP * -0.06
			verts.append(inner)
			verts.append(outer)
			norms.append(Vector3.UP)
			norms.append(Vector3.UP)
			var v: float = spline.cumulative[i] / UV_SCALE
			uvs.append(Vector2(0.0, v))
			uvs.append(Vector2(SHOULDER_OUT / UV_SCALE, v))
		for i in count:
			var a: int = base + i * 2
			var b: int = base + ((i + 1) % count) * 2
			if side > 0.0:
				indices.append_array([a, b, a + 1, a + 1, b, b + 1])
				faces.append_array([verts[a], verts[b], verts[a + 1],
					verts[a + 1], verts[b], verts[b + 1]])
			else:
				indices.append_array([a, a + 1, b, a + 1, b + 1, b])
				faces.append_array([verts[a], verts[a + 1], verts[b],
					verts[a + 1], verts[b + 1], verts[b]])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var visual := MeshInstance3D.new()
	visual.name = "TileShoulders"
	visual.mesh = mesh
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(visual)
	stats["draws"] = int(stats["draws"]) + 1
	_add_collision(parent, "TileShoulderCollision", faces, false)


# --------------------------------------------------------------------------
# edges


## Kerbs on both edges of every tile that is not a split apron.
static func _kerbs(parent: Node3D, spline: RefCounted, layout: RefCounted,
		palette: Dictionary, stats: Dictionary) -> void:
	var runs: Array = []
	for tile: Dictionary in layout.tiles:
		if bool(tile.get("split", false)):
			continue
		if float(tile["span"]) <= 2.5:
			continue
		var from_distance: float = float(tile["from"]) + 1.0
		var to_distance: float = float(tile["from"]) + float(tile["span"]) - 1.0
		for side: float in [-1.0, 1.0]:
			runs.append({"from": from_distance, "to": to_distance, "side": side,
				"width": float(tile["width"])})
	RaceKit.kerb_ribbon(parent, spline, runs, palette["kerb"] as Color)
	stats["kerb_runs"] = int(stats["kerb_runs"]) + runs.size()
	stats["draws"] = int(stats["draws"]) + 1


## Armco down the straights and along the inside of every corner; the outside of
## a corner is left to the tyre wall.
static func _armco(parent: Node3D, spline: RefCounted, layout: RefCounted,
		stats: Dictionary) -> void:
	var runs: Array = []
	for tile: Dictionary in layout.tiles:
		var outside: float = float(tile["outside"])
		var pit_side: float = 0.0
		var hooks: PackedStringArray = tile["hooks"] as PackedStringArray
		if hooks.has("pit"):
			pit_side = float(tile["pit_side"])
		var sides: Array[float] = []
		if outside != 0.0:
			sides.append(-outside)
		else:
			sides.append(-1.0)
			sides.append(1.0)
		for side: float in sides:
			if pit_side != 0.0 and side == pit_side:
				continue
			runs.append({"from": float(tile["from"]),
				"to": float(tile["from"]) + float(tile["span"]),
				"side": side, "lateral": BARRIER_LATERAL})
	var pieces: int = RaceKit.armco_runs(parent, spline, runs)
	stats["barrier_runs"] = int(stats["barrier_runs"]) + runs.size()
	stats["pieces"] = int(stats.get("pieces", 0)) + pieces
	stats["draws"] = int(stats["draws"]) + 1

## Catch fencing on both sides of the whole lap: the read that says "circuit"
## from the cockpit.
static func _fence(parent: Node3D, spline: RefCounted, layout: RefCounted,
		stats: Dictionary) -> void:
	var runs: Array = []
	for side: float in [-1.0, 1.0]:
		runs.append({"from": 0.0, "to": spline.total_length, "side": side,
			"lateral": FENCE_LATERAL})
	var pieces: int = RaceKit.catch_fence(parent, spline, runs, 3.2, FENCE_LATERAL)
	stats["fence_runs"] = int(stats["fence_runs"]) + runs.size()
	stats["pieces"] = int(stats.get("pieces", 0)) + pieces
	stats["draws"] = int(stats["draws"]) + 1


static func _tyre_walls(parent: Node3D, spline: RefCounted, layout: RefCounted,
		stats: Dictionary) -> void:
	var walls: Array = []
	for anchor: Dictionary in layout.anchors:
		if str(anchor["kind"]) != "tyres":
			continue
		walls.append({
			"distance": float(anchor["distance"]),
			"side": float(anchor["side"]),
			"length": 15.0,
			"lateral": TYRE_LATERAL,
		})
	if walls.is_empty():
		return
	var stacks: int = RaceKit.tyre_walls(parent, spline, walls)
	stats["tyre_walls"] = int(stats["tyre_walls"]) + walls.size()
	stats["tyre_stacks"] = int(stats["tyre_stacks"]) + stacks
	stats["draws"] = int(stats["draws"]) + 1


# --------------------------------------------------------------------------
# paint


## Start grid, pit-lane markings and the split/merge hatching in one unshaded
## mesh. Paint is not solid, so it carries no collision.
static func _paint(parent: Node3D, spline: RefCounted, layout: RefCounted,
		stats: Dictionary) -> void:
	var verts := PackedVector3Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	var pieces: int = 0
	pieces += _start_grid(spline, verts, colours, indices)
	for anchor: Dictionary in layout.anchors:
		match str(anchor["kind"]):
			"pit":
				pieces += _pit_paint(spline, layout, anchor, verts, colours, indices)
			"split":
				pieces += _split_paint(spline, layout, anchor, verts, colours, indices)
	if indices.is_empty():
		return
	var mesh: ArrayMesh = SceneryKit.mesh_from(verts, colours, indices, false)
	if mesh == null:
		return
	var paint := MeshInstance3D.new()
	paint.name = "TilePaint"
	paint.mesh = mesh
	paint.material_override = _paint_material()
	paint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(paint)
	stats["paint_pieces"] = int(stats["paint_pieces"]) + pieces
	stats["draws"] = int(stats["draws"]) + 1


static func _start_grid(spline: RefCounted, verts: PackedVector3Array,
		colours: PackedColorArray, indices: PackedInt32Array) -> int:
	# Two columns of four grid slots behind the line. The player spawns at 8 m;
	# the boxes are only paint, so a kart can roll over them.
	var pieces: int = 0
	for row in 4:
		for column in 2:
			var distance: float = 4.0 + float(row) * 7.0
			var lateral: float = -2.8 if column == 0 else 2.8
			_paint_box(spline, distance, 5.4, lateral - 1.5, lateral + 1.5,
				0.16, WHITE, verts, colours, indices)
			pieces += 1
	return pieces


static func _pit_paint(spline: RefCounted, layout: RefCounted,
		anchor: Dictionary, verts: PackedVector3Array,
		colours: PackedColorArray, indices: PackedInt32Array) -> int:
	var from_distance: float = float(anchor["distance"])
	var span: float = float(anchor["length"])
	var side: float = float(anchor["side"]) if float(anchor["side"]) != 0.0 else 1.0
	var inner: float = TileCatalog.ROAD_HALF + 0.55
	var outer: float = TileCatalog.ROAD_HALF + 7.4
	var pieces: int = 0
	_paint_strip(spline, from_distance + 1.0, from_distance + span - 1.0,
		inner * side, 0.15, WHITE, verts, colours, indices)
	_paint_strip(spline, from_distance + 1.0, from_distance + span - 1.0,
		outer * side, 0.18, Color("e8c34a"), verts, colours, indices)
	var cursor: float = 4.0
	while cursor < span - 3.0:
		_paint_strip(spline, from_distance + cursor,
			from_distance + minf(cursor + 2.4, span - 1.0),
			(TileCatalog.ROAD_HALF + 3.4) * side, 0.12, WHITE, verts, colours,
			indices)
		pieces += 1
		cursor += 7.0
	for bay in 4:
		var distance: float = from_distance + 10.0 + float(bay) * 12.0
		if distance > from_distance + span - 4.0:
			break
		_paint_box(spline, distance, 5.0, inner + 0.4, inner + 3.6, 0.12, WHITE,
			verts, colours, indices)
		pieces += 1
	return pieces


static func _split_paint(spline: RefCounted, layout: RefCounted,
		anchor: Dictionary, verts: PackedVector3Array,
		colours: PackedColorArray, indices: PackedInt32Array) -> int:
	# Two hatched islands on the widened apron, one either side of the racing
	# line. The centreline stays in the middle lane, so the islands never block
	# the ideal line: they are paint and the karts can cross them.
	var from_distance: float = float(anchor["distance"])
	var span: float = float(anchor["length"])
	var pieces: int = 0
	var start: float = from_distance + span * 0.18
	var end: float = from_distance + span * 0.82
	for side: float in [-1.0, 1.0]:
		var low: float = 3.1 * side
		var high: float = 5.9 * side
		_paint_strip(spline, start, end, low, 0.14, WHITE, verts, colours, indices)
		_paint_strip(spline, start, end, high, 0.14, WHITE, verts, colours, indices)
		var cursor: float = start + 1.5
		while cursor < end - 1.0:
			_paint_strip(spline, cursor, cursor + 0.5, (low + high) * 0.5,
				absf(high - low) * 0.8, Color("c9c3b4"), verts, colours, indices)
			cursor += 2.2
		pieces += 1
	return pieces


static func _paint_strip(spline: RefCounted, from_distance: float,
		to_distance: float, lateral: float, width: float, colour: Color,
		verts: PackedVector3Array, colours: PackedColorArray,
		indices: PackedInt32Array) -> void:
	var span: float = to_distance - from_distance
	if span <= 0.01:
		return
	var steps: int = maxi(int(ceil(span / 2.0)), 1)
	var step: float = span / float(steps)
	var low: float = lateral - width * 0.5
	var high: float = lateral + width * 0.5
	for i in steps:
		var f0: Dictionary = spline.sample(from_distance + step * float(i))
		var f1: Dictionary = spline.sample(from_distance + step * float(i + 1))
		var p0: Vector3 = (f0["position"] as Vector3) + Vector3.UP * PAINT_Y
		var p1: Vector3 = (f1["position"] as Vector3) + Vector3.UP * PAINT_Y
		var r0: Vector3 = f0["right"]
		var r1: Vector3 = f1["right"]
		_add_quad(verts, colours, indices, p0 + r0 * low, p0 + r0 * high,
			p1 + r1 * low, p1 + r1 * high, colour)


static func _paint_box(spline: RefCounted, distance: float, length: float,
		lateral_a: float, lateral_b: float, line: float, colour: Color,
		verts: PackedVector3Array, colours: PackedColorArray,
		indices: PackedInt32Array) -> void:
	var half: float = length * 0.5
	_paint_strip(spline, distance - half, distance + half, lateral_a, line,
		colour, verts, colours, indices)
	_paint_strip(spline, distance - half, distance + half, lateral_b, line,
		colour, verts, colours, indices)
	_cross_strip(spline, distance - half, lateral_a, lateral_b, line, colour,
		verts, colours, indices)
	_cross_strip(spline, distance + half, lateral_a, lateral_b, line, colour,
		verts, colours, indices)


static func _cross_strip(spline: RefCounted, distance: float, lateral_a: float,
		lateral_b: float, width: float, colour: Color,
		verts: PackedVector3Array, colours: PackedColorArray,
		indices: PackedInt32Array) -> void:
	var frame: Dictionary = spline.sample(distance)
	var point: Vector3 = (frame["position"] as Vector3) + Vector3.UP * PAINT_Y
	var right: Vector3 = frame["right"]
	var forward: Vector3 = frame["forward"]
	var low: float = minf(lateral_a, lateral_b)
	var high: float = maxf(lateral_a, lateral_b)
	var half: float = width * 0.5
	_add_quad(verts, colours, indices,
		point + right * low - forward * half,
		point + right * high - forward * half,
		point + right * low + forward * half,
		point + right * high + forward * half, colour)


## Wet and ice sheens over the road, so a slippery tile reads from the cockpit as
## well as from the grip model.
static func _sheens(parent: Node3D, spline: RefCounted, layout: RefCounted,
		palette: Dictionary, stats: Dictionary) -> void:
	var kinds: Array[String] = ["wet", "ice"]
	for kind: String in kinds:
		var verts := PackedVector3Array()
		var colours := PackedColorArray()
		var indices := PackedInt32Array()
		for span: Dictionary in layout.surfaces:
			if str(span["kind"]) != kind:
				continue
			var from_fraction: float = float(span["from"])
			var to_fraction: float = float(span["to"])
			var from_distance: float = from_fraction * spline.total_length
			var span_length: float = to_fraction * spline.total_length - from_distance
			if span_length <= 0.0:
				span_length += spline.total_length
			_add_sheen(spline, layout, from_distance, span_length, kind,
				palette, verts, colours, indices)
		if indices.is_empty():
			continue
		var mesh: ArrayMesh = SceneryKit.mesh_from(verts, colours, indices, false)
		if mesh == null:
			continue
		var visual := MeshInstance3D.new()
		visual.name = "TileSheen_" + kind
		visual.mesh = mesh
		visual.material_override = _sheen_material()
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(visual)
		stats["draws"] = int(stats["draws"]) + 1


static func _add_sheen(spline: RefCounted, layout: RefCounted,
		from_distance: float, span: float, kind: String, palette: Dictionary,
		verts: PackedVector3Array, colours: PackedColorArray,
		indices: PackedInt32Array) -> void:
	var colour: Color = palette["wet_sheen"] if kind == "wet" \
		else palette["ice_sheen"]
	if colour.a <= 0.01:
		return
	var steps: int = maxi(int(ceil(span / 2.0)), 1)
	var step: float = span / float(steps)
	for i in steps:
		var s0: float = from_distance + step * float(i)
		var s1: float = s0 + step
		var f0: Dictionary = spline.sample(s0)
		var f1: Dictionary = spline.sample(s1)
		var half0: float = layout.half_width_at(s0) + 0.2
		var half1: float = layout.half_width_at(s1) + 0.2
		var p0: Vector3 = (f0["position"] as Vector3) + Vector3.UP * (PAINT_Y + 0.004)
		var p1: Vector3 = (f1["position"] as Vector3) + Vector3.UP * (PAINT_Y + 0.004)
		var r0: Vector3 = f0["right"]
		var r1: Vector3 = f1["right"]
		_add_quad(verts, colours, indices, p0 - r0 * half0, p0 + r0 * half0,
			p1 - r1 * half1, p1 + r1 * half1, colour)


# --------------------------------------------------------------------------
# helpers


static func _add_quad(verts: PackedVector3Array, colours: PackedColorArray,
		indices: PackedInt32Array, low0: Vector3, high0: Vector3,
		low1: Vector3, high1: Vector3, colour: Color) -> void:
	var base: int = verts.size()
	for vertex: Vector3 in [low0, high0, low1, high1]:
		verts.append(vertex)
		colours.append(colour)
	indices.append(base)
	indices.append(base + 2)
	indices.append(base + 1)
	indices.append(base + 1)
	indices.append(base + 2)
	indices.append(base + 3)


static func _add_collision(parent: Node3D, node_name: String,
		faces: PackedVector3Array, backface: bool) -> void:
	if faces.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = backface
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)


static func _paint_material() -> Material:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


static func _sheen_material() -> Material:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.15
	mat.metallic = 0.0
	return mat
