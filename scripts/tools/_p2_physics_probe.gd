extends Node
## Phase-2 WS2 physics probe (headless): ramp collision vs visible mesh, cart
## phase-through, chasm launch, stadium seating orientation, vehicle grounding
## and the local/remote cartoon flex.
##
## It must run as a scene (not --script) because the cart controller references
## the GameSettings/Network autoloads, exactly like driving_smoke.tscn.
##
##   Godot_v4.7.2-stable_win64_console.exe --headless --path godot_project \
##       res://scripts/tools/_p2_physics_probe.tscn
##
## `P2_MODE` selects one mode (default `ramp`):
##   ramp     builds Glacier Pass, measures every J ramp's visible surface
##            against its collider, then drives three mass classes over each
##            ramp and asserts none of them pass through the mesh.
##   chasm    drives the same three masses into the scripted glacier chasm
##            launch and asserts they clear the 17.35 m gap.
##   stadium  measures the grandstand's seating direction from the GLB and
##            asserts every bowl tier, camera crane, floodlight, sign and flag
##            faces the circuit. The placed-instance audit only runs windowed:
##            Godot's headless dummy renderer returns identity for
##            `MultiMesh.get_instance_transform`, so batched transforms cannot
##            be read back headlessly (the maths audit still gates headless).
##   ground   measures each vehicle's visual ground contact (the hover bug).
##   flex     measures local squash/roll and the same flex on a remote ghost,
##            and proves the ghost visual never writes its physics velocity.
##   maps     audits all five racing maps and nine party arenas: mirrored /
##            inside-out transforms, non-finite poses, invalid colliders,
##            static bodies off the WORLD layer and holes in the road collider.
##            `P2_MAP_ONLY=<id>` or `P2_MAP_ONLY=arenas` narrows the run.
##   profile  prints the measured top-surface profile of the kit models.
##   models   prints the measured AABB/part tree of the kit models.
##   mmcheck  isolation check: MultiMesh transform readback needs a real
##            renderer.
##
## Exit code is the failure count.

const TrackDefs := preload("res://scripts/minigames/track_defs.gd")
const KenneyTiles := preload("res://scripts/minigames/tiles/kenney_tiles.gd")
const TileCatalog := preload("res://scripts/minigames/tiles/tile_catalog.gd")
const GlacierCourse := preload("res://scripts/minigames/maps/glacier/glacier_course.gd")
const GlacierTheme := preload("res://scripts/minigames/maps/glacier_theme.gd")
const GlacierChasm := preload("res://scripts/minigames/maps/glacier/glacier_chasm.gd")
const StadiumTheme := preload("res://scripts/minigames/maps/stadium_theme.gd")
const StadiumGrid := preload("res://scripts/minigames/maps/stadium/stadium_grid.gd")
const StadiumLayout := preload("res://scripts/minigames/maps/stadium/stadium_layout.gd")
const StadiumProps := preload("res://scripts/minigames/maps/stadium/stadium_props.gd")
const StadiumBowl := preload("res://scripts/minigames/maps/stadium/stadium_bowl.gd")
const CargoRushTheme := preload("res://scripts/minigames/cargo_rush_theme.gd")
const KnockoutMaps := preload("res://scripts/minigames/knockout_maps.gd")
const BombTagMaps := preload("res://scripts/minigames/bomb_tag_maps.gd")
const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")
const CartScene := preload("res://scenes/player/cart_player.tscn")

var _failures: int = 0
## World-space triangle soup of a batched road model, built once per mode run.
var _model_tris: Dictionary = {}


class Host extends Node3D:
	## The race scene carries the preset the theme reads. Mirrors glacier_selftest.
	var _preset: Dictionary = {}
	## The chasm controller looks these up; keeping a real cart here lets the
	## scripted chasm launch run in probe mode.
	var _cart: Node3D = null
	var _rivals: Array = []
	## Race-controller surface the chasm's setback/toast path reads.
	var spline: RefCounted = null
	var _unwrapped: float = 0.0
	var _prev_s: float = 0.0
	var _skip_progress: bool = false
	var _off_timer: float = 0.0
	var _air_time: float = 0.0
	var _fall_speed: float = 0.0
	var toasts: Array[String] = []

	func _toast(text: String, _duration: float = 1.5) -> void:
		toasts.append(text)

	func _safe_respawn_transform(distance: float) -> Transform3D:
		if spline == null:
			return Transform3D(Basis.IDENTITY, Vector3.UP * 0.1)
		var f: Dictionary = spline.sample(distance) as Dictionary
		var forward: Vector3 = f["forward"] as Vector3
		return Transform3D(Basis(Vector3.UP, atan2(-forward.x, -forward.z)),
			(f["position"] as Vector3) + Vector3.UP * 0.1)

	func _track_transform(distance: float, lateral: float,
			height: float) -> Transform3D:
		if spline == null:
			return Transform3D(Basis.IDENTITY, Vector3.UP * 0.1)
		var f: Dictionary = spline.sample(distance) as Dictionary
		var forward: Vector3 = f["forward"] as Vector3
		var right: Vector3 = f["right"] as Vector3
		return Transform3D(Basis(Vector3.UP, atan2(-forward.x, -forward.z)),
			(f["position"] as Vector3) + right * lateral
				+ Vector3.UP * (height + 0.1))


func _ready() -> void:
	var mode: String = OS.get_environment("P2_MODE")
	if mode == "":
		mode = "ramp"
	_run.call_deferred(mode)


func _run(mode: String) -> void:
	await get_tree().process_frame
	match mode:
		"mmcheck":
			_mode_mmcheck()
		"profile":
			_mode_profile()
		"models":
			_mode_models()
		"stadium":
			_mode_stadium()
		"ground":
			await _mode_ground()
		"flex":
			await _mode_flex()
		"maps":
			await _mode_maps()
		"chasm":
			await _mode_chasm()
		_:
			await _mode_ramp()
	print("P2 PROBE [%s]: %s" % [
		mode, "PASS" if _failures == 0 else "%d FAILURE(S)" % _failures])
	get_tree().quit(clampi(_failures, 0, 255))


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  OK   " + message)
		return
	_failures += 1
	push_error("P2 PROBE FAIL: " + message)
	print("  FAIL " + message)


func _mode_mmcheck() -> void:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = BoxMesh.new()
	multi.instance_count = 2
	var t0 := Transform3D(Basis(Vector3.UP, 0.5), Vector3(100.0, 13.5, 33.0))
	var t1 := Transform3D(Basis(Vector3.UP, -0.5), Vector3(200.0, 9.0, 143.0))
	multi.set_instance_transform(0, t0)
	multi.set_instance_transform(1, t1)
	print("MM READBACK0 ", multi.get_instance_transform(0))
	print("MM READBACK1 ", multi.get_instance_transform(1))


func _mode_profile() -> void:
	for model: String in ["roadRampWall", "roadBump", "grandStand",
			"grandStandCovered", "grandStandAwning"]:
		_profile_model(model)


## Prints the visible top-surface profile of a kit model along its own +Z axis,
## at its plan centre. This is how the seating orientation and the exact ramp
## crest height are measured instead of guessed.
func _profile_model(model: String) -> void:
	var info: Dictionary = TileCatalog.model_info(model)
	if not bool(info.get("ok", false)):
		print("PROFILE %-20s MISSING" % model)
		return
	var aabb: AABB = info["aabb"]
	var center: Vector2 = info["center"]
	var tris := PackedVector3Array()
	for part: Dictionary in info["parts"] as Array:
		var mesh: Mesh = part["mesh"] as Mesh
		var xform: Transform3D = part["transform"]
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(surface)
			if arrays.is_empty():
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
				indices = arrays[Mesh.ARRAY_INDEX]
			var tri_count: int = indices.size() / 3 if not indices.is_empty() \
				else verts.size() / 3
			for tri in tri_count:
				var i0: int = indices[tri * 3] if not indices.is_empty() \
					else tri * 3
				var i1: int = indices[tri * 3 + 1] \
					if not indices.is_empty() else tri * 3 + 1
				var i2: int = indices[tri * 3 + 2] \
					if not indices.is_empty() else tri * 3 + 2
				tris.append(xform * verts[i0])
				tris.append(xform * verts[i1])
				tris.append(xform * verts[i2])
	print("PROFILE %-20s aabb %s center2d %s" % [model, str(aabb),
		str(center)])
	var steps: int = 10
	for step in steps + 1:
		var z: float = aabb.position.z + aabb.size.z * float(step) \
			/ float(steps)
		var top: float = _plan_top_z(tris, Vector3(center.x, 0.0, z))
		print("    z %+.3f top %+.3f" % [z - center.y, top])
	# Lateral cross-section at the mid and forward plan rows: tells whether the
	# drivable surface is flat across the lane and where the model side walls are.
	for row: float in [0.5, 0.03]:
		var line := "    x @ z%+.2f: " % (aabb.position.z
			+ aabb.size.z * row - center.y)
		for step in 8:
			var x: float = aabb.position.x + aabb.size.x * float(step) / 7.0
			var top: float = _plan_top_z(tris, Vector3(x, 0.0,
				aabb.position.z + aabb.size.z * row))
			line += "%+.3f:%+.3f " % [x - center.x, top]
		print(line)


## Highest triangle y at a model-space plan point over a triangle soup.
func _plan_top_z(tris: PackedVector3Array, q: Vector3) -> float:
	var best: float = -INF
	var index: int = 0
	while index + 2 < tris.size():
		var a: Vector3 = tris[index]
		var b: Vector3 = tris[index + 1]
		var c: Vector3 = tris[index + 2]
		index += 3
		var bary: Vector3 = _plan_bary(a, b, c, q)
		if bary.x < -0.001 or bary.y < -0.001 or bary.z < -0.001:
			continue
		best = maxf(best, bary.x * a.y + bary.y * b.y + bary.z * c.y)
	return best


# --------------------------------------------------------------------------
# models
# --------------------------------------------------------------------------


func _mode_models() -> void:
	for model: String in [
			"roadRamp", "roadRampLong", "roadRampWall", "roadBump",
			"grandStand", "grandStandCovered", "grandStandAwning"]:
		var info: Dictionary = TileCatalog.model_info(model)
		if not bool(info.get("ok", false)):
			print("%-20s MISSING" % model)
			continue
		var aabb: AABB = info["aabb"]
		var parts: Array = info["parts"] as Array
		print("%-20s size %s pos %s center2d %s parts %d" % [
			model, str(aabb.size), str(aabb.position), str(info["center"]),
			parts.size()])
		_dump_parts(model, parts)


func _dump_parts(model: String, parts: Array) -> void:
	for index in parts.size():
		var part: Dictionary = parts[index]
		var mesh: Mesh = part["mesh"] as Mesh
		if mesh == null:
			continue
		print("    part %d: aabb %s xform %s" % [
			index, str(mesh.get_aabb()),
			str(part["transform"] as Transform3D)])
	var packed: PackedScene = load(str(TileCatalog.model_info(model)["path"])) \
		as PackedScene
	if packed == null:
		return
	var node: Node = packed.instantiate()
	_dump_tree(node, "")
	node.free()


func _dump_tree(node: Node, indent: String) -> void:
	var extra: String = ""
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			extra = " mesh_aabb=%s" % str(mi.mesh.get_aabb())
	if node is Node3D:
		extra += " pos=%s" % str((node as Node3D).position.snapped(
			Vector3.ONE * 0.001))
	print("      %s%s <%s>%s" % [indent, str(node.name), node.get_class(), extra])
	for child: Node in node.get_children():
		_dump_tree(child, indent + "  ")


# --------------------------------------------------------------------------
# glacier ramps
# --------------------------------------------------------------------------


func _build_glacier() -> Array:
	var host := Host.new()
	host.name = "P2Glacier"
	var preset: Dictionary = TrackDefs.get_preset("glacier").duplicate(true)
	preset.merge(GlacierCourse.preset_fields(), true)
	host._preset = preset
	add_child(host)
	var theme: Dictionary = {"id": "glacier"}
	theme.merge(GlacierCourse.preset_fields(), true)
	var spline: RefCounted = KenneyTiles.build(host, GlacierCourse.grid(), theme)
	if spline == null:
		_check(false, "glacier grid did not build")
		return []
	GlacierTheme.build(host, spline)
	# Physics shapes only register on the next physics tick, so a ray query
	# issued in the same frame as the build would see an empty world.
	await get_tree().physics_frame
	await get_tree().physics_frame
	return [host, spline]


func _debug_ramp_nodes(host: Node) -> void:
	for node: Node in _descendants(host):
		var mmi := node as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null:
			continue
		if not str(mmi.name).contains("Ramp"):
			continue
		print("  DEBUG node %s instances %d fmt %d mesh %s parent %s" % [
			str(mmi.name), mmi.multimesh.instance_count,
			int(mmi.multimesh.transform_format), str(mmi.multimesh.mesh),
			str(mmi.get_parent().name)])
		for inst in mmi.multimesh.instance_count:
			print("  DEBUG   xf[%d] %s" % [inst, str(
				mmi.multimesh.get_instance_transform(inst))])


func _debug_collision(host: Node) -> void:
	var grid: Node = host.get_node_or_null("KenneyGrid")
	print("  DEBUG KenneyGrid %s children %d" % [str(grid),
		grid.get_child_count() if grid != null else -1])
	for node: Node in _descendants(host):
		var body := node as StaticBody3D
		if body == null:
			continue
		if not str(body.name).begins_with("RoadCollision"):
			continue
		print("  DEBUG body %s shapes %d" % [str(body.name),
			body.get_child_count()])
		for child: Node in body.get_children():
			var cs := child as CollisionShape3D
			if cs == null:
				continue
			var extra: String = ""
			if cs.shape is ConcavePolygonShape3D:
				var faces: PackedVector3Array = \
					(cs.shape as ConcavePolygonShape3D).get_faces()
				var low := Vector3(INF, INF, INF)
				var high := Vector3(-INF, -INF, -INF)
				for point: Vector3 in faces:
					low = low.min(point)
					high = high.max(point)
				extra = " faces %d aabb %s..%s" % [faces.size() / 3,
					str(low), str(high)]
			print("    DEBUG shape %s %s%s" % [str(cs.name),
				cs.shape.get_class() if cs.shape != null else "null", extra])
	var space: PhysicsDirectSpaceState3D = get_tree().root.get_world_3d() \
		.direct_space_state
	print("  DEBUG bodies_in_world:") 
	for probe_point: Vector3 in [Vector3(275.0, 40.0, 33.0),
			Vector3(275.0, 40.0, 30.0), Vector3(200.0, 40.0, 33.0)]:
		var query := PhysicsRayQueryParameters3D.create(probe_point,
			probe_point - Vector3.UP * 60.0)
		query.collide_with_areas = false
		var hit: Dictionary = space.intersect_ray(query)
		print("  DEBUG ray %s -> %s" % [str(probe_point),
			str(hit.get("position", "MISS")) + " " + str(hit.get("collider", ""))])


func _ramp_tiles(spline: RefCounted) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var tiles: Array = spline.get("tiles") as Array
	for index in tiles.size():
		var tile: Dictionary = tiles[index] as Dictionary
		if str(tile.get("tile", "")) != "J":
			continue
		found.append(tile)
	return found


## World plan sampling frame of one ramp tile. Returns {center, fw, right,
## half, deck_y, yaw}.
func _ramp_frame(tile: Dictionary) -> Dictionary:
	var half: float = TileCatalog.TILE_SIZE * 0.5
	var cell: Vector2i = tile["cell"] as Vector2i
	var center := Vector3((float(cell.x) + 0.5) * TileCatalog.TILE_SIZE, 0.0,
		(float(cell.y) + 0.5) * TileCatalog.TILE_SIZE)
	var yaw: float = float(tile["yaw"])
	var fw: Vector3 = Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, -1.0)
	var right: Vector3 = fw.cross(Vector3.UP).normalized()
	var deck_y: float = float(tile.get("height_in", 0.0)) \
		+ TileCatalog.ROAD_SURFACE
	return {"center": center + Vector3.UP * deck_y, "fw": fw, "right": right,
		"half": half, "deck_y": deck_y, "yaw": yaw,
		"plan_center": center}


## World-space triangles of the visible J ramp pieces, reconstructed with the
## engine's own placement maths. Headless runs use Godot's dummy renderer, whose
## MultiMesh transform readback always returns identity, so the batch transforms
## cannot be read from the scene; `_fit_tile` is the exact function the road
## builder used, so this is the same mesh the player sees.
func _placed_ramp_tris(tiles: Array[Dictionary]) -> Array:
	var model: String = TileCatalog.road_model("J")
	var info: Dictionary = TileCatalog.model_info(model)
	var out: Array = []
	if not bool(info.get("ok", false)):
		return out
	for tile: Dictionary in tiles:
		var frame: Dictionary = _ramp_frame(tile)
		var plan_center: Vector3 = frame["plan_center"] as Vector3
		# The ramp piece sits on its entry deck, one ROAD_SURFACE above it.
		var ramp_deck: Vector3 = plan_center + Vector3.UP * (
			float(tile.get("height_in", 0.0)) + TileCatalog.ROAD_SURFACE)
		var scale: Vector3 = KenneyTiles._tile_scale(tile)
		var place: Transform3D = KenneyTiles._fit_tile(model, ramp_deck,
			float(tile["yaw"]), scale, 0.0)
		for part: Dictionary in info["parts"] as Array:
			var mesh: Mesh = part["mesh"] as Mesh
			if mesh == null:
				continue
			var part_xform: Transform3D = place * (part["transform"] as Transform3D)
			for surface in mesh.get_surface_count():
				var arrays: Array = mesh.surface_get_arrays(surface)
				if arrays.is_empty():
					continue
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices := PackedInt32Array()
				if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
					indices = arrays[Mesh.ARRAY_INDEX]
				var tri_count: int = indices.size() / 3 \
					if not indices.is_empty() else verts.size() / 3
				for tri in tri_count:
					var i0: int = indices[tri * 3] if not indices.is_empty() \
						else tri * 3
					var i1: int = indices[tri * 3 + 1] \
						if not indices.is_empty() else tri * 3 + 1
					var i2: int = indices[tri * 3 + 2] \
						if not indices.is_empty() else tri * 3 + 2
					out.append([part_xform * verts[i0],
						part_xform * verts[i1], part_xform * verts[i2]])
	return out


## Highest visible triangle under a world plan point, over every MultiMesh the
## road builder emitted for `model`. Returns {hit, y, n}.
func _visual_top(host: Node, model: String, q: Vector3) -> Dictionary:
	var best_y: float = -INF
	var best_n := Vector3.UP
	for node: Node in _descendants(host):
		var mmi := node as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null:
			continue
		if not str(mmi.name).contains(model):
			continue
		var mesh: Mesh = mmi.multimesh.mesh
		if mesh == null:
			continue
		var surfaced: Array = []
		for surface in mesh.get_surface_count():
			surfaced.append(mesh.surface_get_arrays(surface))
		for inst in mmi.multimesh.instance_count:
			var xf: Transform3D = mmi.multimesh.get_instance_transform(inst)
			for arrays: Array in surfaced:
				if arrays.is_empty():
					continue
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices := PackedInt32Array()
				if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
					indices = arrays[Mesh.ARRAY_INDEX]
				var tri_count: int = indices.size() / 3 \
					if not indices.is_empty() else verts.size() / 3
				for tri in tri_count:
					var i0: int = indices[tri * 3] if not indices.is_empty() \
						else tri * 3
					var i1: int = indices[tri * 3 + 1] \
						if not indices.is_empty() else tri * 3 + 1
					var i2: int = indices[tri * 3 + 2] \
						if not indices.is_empty() else tri * 3 + 2
					var a: Vector3 = xf * verts[i0]
					var b: Vector3 = xf * verts[i1]
					var c: Vector3 = xf * verts[i2]
					var bary: Vector3 = _plan_bary(a, b, c, q)
					if bary.x < -0.001 or bary.y < -0.001 or bary.z < -0.001:
						continue
					var y: float = bary.x * a.y + bary.y * b.y + bary.z * c.y
					if y > best_y:
						best_y = y
						var n: Vector3 = (b - a).cross(c - a)
						if n.length_squared() > 0.000001:
							best_n = n.normalized()
	return {"hit": best_y > -INF, "y": best_y, "n": best_n}


## Highest triangle under a world plan point from a collected triangle soup.
func _tris_top(tris: Array, q: Vector3) -> Dictionary:
	var best_y: float = -INF
	var best_n := Vector3.UP
	for entry: Array in tris:
		var bary: Vector3 = _plan_bary(entry[0], entry[1], entry[2], q)
		if bary.x < -0.001 or bary.y < -0.001 or bary.z < -0.001:
			continue
		var y: float = bary.x * (entry[0] as Vector3).y \
			+ bary.y * (entry[1] as Vector3).y \
			+ bary.z * (entry[2] as Vector3).y
		if y > best_y:
			best_y = y
			var n: Vector3 = ((entry[1] as Vector3) - (entry[0] as Vector3)) \
				.cross((entry[2] as Vector3) - (entry[0] as Vector3))
			if n.length_squared() > 0.000001:
				best_n = n.normalized()
	return {"hit": best_y > -INF, "y": best_y, "n": best_n}


func _plan_bary(a: Vector3, b: Vector3, c: Vector3, q: Vector3) -> Vector3:
	var v0 := Vector2(b.x - a.x, b.z - a.z)
	var v1 := Vector2(c.x - a.x, c.z - a.z)
	var v2 := Vector2(q.x - a.x, q.z - a.z)
	var den: float = v0.x * v1.y - v0.y * v1.x
	if absf(den) < 0.0000001:
		return Vector3(-1.0, -1.0, -1.0)
	var u: float = (v2.x * v1.y - v2.y * v1.x) / den
	var v: float = (v0.x * v2.y - v0.y * v2.x) / den
	return Vector3(1.0 - u - v, u, v)


## Collider top at a plan point: raycast the physics world from above.
func _collider_top(q: Vector3) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = get_tree().root.get_world_3d() \
		.direct_space_state
	var from: Vector3 = q + Vector3.UP * 30.0
	var query := PhysicsRayQueryParameters3D.create(from, q - Vector3.UP * 30.0)
	query.collide_with_areas = false
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return {"hit": false, "y": -INF, "n": Vector3.UP}
	return {"hit": true, "y": (hit["position"] as Vector3).y,
		"n": hit.get("normal", Vector3.UP) as Vector3}


func _mode_ramp() -> void:
	var built: Array = await _build_glacier()
	if built.is_empty():
		return
	var host: Node = built[0]
	var spline: RefCounted = built[1]
	var tiles: Array[Dictionary] = _ramp_tiles(spline)
	print("P2 RAMP: %d J ramp tile(s) on Glacier Pass, lap %.0f m" % [
		tiles.size(), float(spline.get("total_length"))])
	if OS.get_environment("P2_DEBUG") == "1":
		_debug_ramp_nodes(host)
		_debug_collision(host)
		for tile: Dictionary in tiles:
			print("  DEBUG tile %s yaw %.3f frame %s" % [
				str(tile["cell"]), float(tile["yaw"]),
				str(_ramp_frame(tile))])
	_check(not tiles.is_empty(), "glacier route has jump ramps")
	var ramp_model: String = TileCatalog.road_model("J")
	var ramp_tris: Array = _placed_ramp_tris(tiles)
	print("P2 RAMP: %d visible triangle(s) across %d %s piece(s)" % [
		ramp_tris.size(), tiles.size(), ramp_model])
	_check(not ramp_tris.is_empty(), "the J ramp mesh is reconstructible")
	# 1. Geometry: the visible ramp mesh vs the physics collider at the same plan
	#    points. A cart can only follow the collider, so any mismatch makes it
	#    drive through the visible ramp.
	for tile: Dictionary in tiles:
		var frame: Dictionary = _ramp_frame(tile)
		var center: Vector3 = frame["center"]
		var fw: Vector3 = frame["fw"]
		var half: float = float(frame["half"])
		var deck_y: float = float(frame["deck_y"])
		var worst: float = 0.0
		var worst_at: float = 0.0
		var visual_crest: float = -INF
		var collider_crest: float = -INF
		var misses: int = 0
		for step in 45:
			var along: float = -half + 0.3 + float(step) / 44.0 \
				* (half * 2.0 - 0.6)
			var q: Vector3 = center + fw * along
			var vis: Dictionary = _tris_top(ramp_tris, q)
			var col: Dictionary = _collider_top(q)
			if not bool(vis["hit"]) or not bool(col["hit"]):
				misses += 1
				continue
			visual_crest = maxf(visual_crest, float(vis["y"]))
			collider_crest = maxf(collider_crest, float(col["y"]))
			var step_m: float = float(col["y"]) - float(vis["y"])
			if absf(step_m) > absf(worst):
				worst = step_m
				worst_at = along
		print("  ramp %s: visible crest %+.3f m, collider crest %+.3f m " \
			% [str(tile["cell"]), visual_crest - deck_y, collider_crest - deck_y]
			+ "over deck, worst surface mismatch %+.3f m at along %+.1f m " \
			% [worst, worst_at]
			+ "(%.0f%% fix), misses %d" % [
				100.0 * collider_crest / maxf(visual_crest, 0.001), misses])
		_check(misses == 0, "ramp %s: every lane sample has mesh and collider"
			% str(tile["cell"]))
		_check(absf(worst) <= 0.08,
			"ramp %s visible/collider surface match (worst %+.3f m)"
			% [str(tile["cell"]), worst])

	# 2. Dynamic: drive three masses over each ramp and assert the cart never
	#    sinks more than a tolerance under the visible surface while on it.
	await _drive_ramp_sweep(host, ramp_tris, tiles)
	host.queue_free()
	await get_tree().process_frame


func _drive_ramp_sweep(host: Node, ramp_tris: Array,
		tiles: Array[Dictionary]) -> void:
	var masses: Array[String] = ["shopping_cart", "sports", "truck"]
	for tile: Dictionary in tiles:
		var frame: Dictionary = _ramp_frame(tile)
		var center: Vector3 = frame["center"]
		var fw: Vector3 = frame["fw"]
		var half: float = float(frame["half"])
		var deck_y: float = float(frame["deck_y"])
		var plan_center: Vector3 = frame["plan_center"]
		for vehicle_id: String in masses:
			var start: Vector3 = plan_center - fw * (half + 40.0)
			start.y = deck_y + 0.02
			var cart: CartPlayer = CartScene.instantiate() as CartPlayer
			cart.ai_mode = true
			cart.position = start
			# The cart's local -Z is its forward.
			cart.rotation.y = atan2(-fw.x, -fw.z)
			host.add_child(cart)
			cart.reapply_vehicle(vehicle_id)
			cart.velocity = fw * 24.0
			cart.set_ai_controls(1.0, 0.0, 0.0)
			var min_clearance: float = INF
			var worst_along: float = -999.0
			var climbed: bool = false
			var peak_height: float = -INF
			var max_speed: float = 0.0
			for index in 300:
				await get_tree().physics_frame
				if not is_instance_valid(cart):
					break
				var pos: Vector3 = cart.global_position
				var rel_plan := Vector3(pos.x - plan_center.x, 0.0,
					pos.z - plan_center.z)
				var along: float = rel_plan.dot(fw)
				max_speed = maxf(max_speed,
					Vector2(cart.velocity.x, cart.velocity.z).length())
				if along < -half + 0.5 or along > half - 0.1:
					continue
				var q: Vector3 = Vector3(center.x, 0.0, center.z) + fw * along
				var vis: Dictionary = _tris_top(ramp_tris, q)
				if not bool(vis["hit"]):
					continue
				# Clearance of the cart origin above the visible ramp surface.
				# Negative means the cart is inside the visible mesh: the
				# phase-through the owner reported.
				var clearance: float = pos.y - float(vis["y"])
				if clearance < min_clearance:
					min_clearance = clearance
					worst_along = along
				peak_height = maxf(peak_height, pos.y - deck_y)
				if pos.y > deck_y + 0.35:
					climbed = true
			print("  drive %-14s: peak %.1f m/s, min visual clearance %+.3f m " \
				% [vehicle_id, max_speed, min_clearance]
				+ "at along %+.1f m, peak height %+.2f m, climbed %s" % [
					worst_along, peak_height,
					"yes" if climbed else "NO"])
			_check(min_clearance >= -0.30,
				"%s does not phase through the ramp (min clearance %+.3f m)"
				% [vehicle_id, min_clearance])
			_check(climbed, "%s actually climbs the ramp surface" % vehicle_id)
			cart.queue_free()
			await get_tree().process_frame


# --------------------------------------------------------------------------
# glacier chasm ballistic launch
# --------------------------------------------------------------------------


## End-to-end launch check: drives the three mass classes up each chasm ramp at
## their weight-balanced takeoff speed and asserts the scripted launch still
## clears the 17.35 m gap after the ramp collider was corrected to the visible
## 2.86 m crest. Runs the real GlacierChasm controller against a stub race host.
func _mode_chasm() -> void:
	var built: Array = await _build_glacier()
	if built.is_empty():
		return
	var host: Host = built[0] as Host
	var spline: RefCounted = built[1]
	host.spline = spline
	var chasm: Node = host.get_node_or_null("GlacierDressing/GlacierChasms")
	_check(chasm != null, "glacier chasm controller exists")
	if chasm == null:
		return
	var sites: Array = chasm.get("_chasm_sites") as Array
	_check(sites.size() == 2, "both chasm jump sites discovered (%d)"
		% sites.size())
	var masses: Array[String] = ["shopping_cart", "sports", "truck"]
	for site: Dictionary in sites:
		var lip: Vector3 = site["lip_pos"] as Vector3
		var fw: Vector3 = site["forward"] as Vector3
		var deck_y: float = float(site["deck_y"])
		for vehicle_id: String in masses:
			var cart: CartPlayer = CartScene.instantiate() as CartPlayer
			cart.ai_mode = true
			cart.position = lip - fw * 46.0 + Vector3.UP * 0.15
			cart.rotation.y = atan2(-fw.x, -fw.z)
			host.add_child(cart)
			cart.reapply_vehicle(vehicle_id)
			host._cart = cart
			var takeoff_speed: float = GlacierChasm.required_speed_for(cart)
			cart.velocity = fw * takeoff_speed * 1.15
			cart.set_ai_controls(1.0, 0.0, 0.0)
			var crossed: bool = false
			var landed: bool = false
			var fell: bool = false
			var setback: bool = false
			var min_y_in_gap: float = INF
			var peak_along: float = -INF
			for index in 300:
				await get_tree().physics_frame
				if not is_instance_valid(cart):
					break
				var pos: Vector3 = cart.global_position
				var rel: Vector3 = pos - lip
				var along: float = rel.x * fw.x + rel.z * fw.z
				peak_along = maxf(peak_along, along)
				if along > GlacierChasm.GAP_END_M + 1.0:
					crossed = true
					if cart.is_on_floor():
						landed = true
				elif along >= GlacierChasm.GAP_START_M - 0.3 \
						and along <= GlacierChasm.GAP_END_M + 0.8:
					min_y_in_gap = minf(min_y_in_gap, pos.y - deck_y)
					if pos.y < deck_y - 1.15:
						fell = true
				if index > 4 and peak_along > 5.0 and along < -25.0:
					# The controller teleported the kart back to the approach:
					# the fall/setback path ran.
					setback = true
					break
			print("  chasm %s %-14s: takeoff %.1f m/s, crossed %s, " \
				% [str(site["index"]), vehicle_id, takeoff_speed,
					"yes" if crossed else "NO"]
				+ "landed %s, fell %s, setback %s, peak along %+.1f m, " \
				% ["yes" if landed else "NO", "yes" if fell else "no",
					"yes" if setback else "no", peak_along]
				+ "min y in gap %+.2f m" % min_y_in_gap)
			_check(crossed, "%s crosses chasm %d" % [vehicle_id,
				int(site["index"])])
			_check(not fell and not setback,
				"%s keeps the scripted launch over chasm %d" % [vehicle_id,
					int(site["index"])])
			host._cart = null
			cart.queue_free()
			await get_tree().process_frame
	_check(not (host.toasts as Array).is_empty(),
		"the leap toast fired (launch path taken)")
	host.queue_free()
	await get_tree().process_frame


# --------------------------------------------------------------------------
# cartoon flex (local + remote ghost)
# --------------------------------------------------------------------------


func _mode_flex() -> void:
	_add_flat_ground(400.0)
	# 1. Local cart: throttle stretch and corner body roll must be visible on
	#    the visual mesh, not just in the spring scratch state.
	var local: CartPlayer = CartScene.instantiate() as CartPlayer
	local.ai_mode = true
	local.position = Vector3(-60.0, 0.1, 0.0)
	add_child(local)
	local.reapply_vehicle("sports")
	var mesh: Node3D = local.get_node("MeshRoot") as Node3D
	local.set_ai_controls(1.0, 0.0, 0.0)
	var max_stretch: float = 1.0
	for index in 40:
		await get_tree().physics_frame
		max_stretch = maxf(max_stretch, mesh.scale.z)
	local.set_ai_controls(1.0, 0.0, 1.0)
	var max_roll: float = 0.0
	for index in 60:
		await get_tree().physics_frame
		max_roll = maxf(max_roll, absf(mesh.rotation.z))
	var speed: float = Vector2(local.velocity.x, local.velocity.z).length()
	print("P2 FLEX local : %.1f m/s, max stretch %.4f, max body roll %.4f rad"
		% [speed, max_stretch, max_roll])
	_check(max_stretch > 1.004, "local throttle stretch shows on the mesh")
	_check(max_roll > 0.02, "local corner body roll shows on the mesh")
	local.queue_free()
	await get_tree().process_frame

	# 2. Remote ghost: the same cartoon flex has to appear from replicated state
	#    alone, and it must never write the physics body.
	var ghost: CartPlayer = CartScene.instantiate() as CartPlayer
	ghost.position = Vector3(60.0, 0.1, 0.0)
	add_child(ghost)
	ghost.setup_remote(7)
	ghost.set_vehicle_id("sports")
	var ghost_mesh: Node3D = ghost.get_node("MeshRoot") as Node3D
	var sample_pos := Vector3(120.0, 0.0, 0.0)
	var sample_yaw: float = 0.0
	var sample_ms: int = 0
	var ghost_roll: float = 0.0
	var ghost_squash: float = 0.0
	for index in 90:
		var speed_now: float = 15.0
		var yaw_step: float = 0.0
		if index < 15:
			speed_now = 15.0 * float(index) / 14.0
		elif index < 60:
			yaw_step = 0.05
		elif index < 75:
			speed_now = 15.0 * (1.0 - float(index - 60) / 14.0)
		sample_yaw = wrapf(sample_yaw + yaw_step, -PI, PI)
		var heading: Vector3 = Vector3(-sin(sample_yaw), 0.0,
			-cos(sample_yaw))
		var replicated_velocity: Vector3 = heading * speed_now
		sample_pos += replicated_velocity * (1.0 / 60.0)
		sample_ms += 16
		ghost.set_net_state(sample_pos, sample_yaw, sample_ms,
			replicated_velocity)
		await get_tree().physics_frame
		ghost_roll = maxf(ghost_roll, absf(ghost_mesh.rotation.z))
		ghost_squash = maxf(ghost_squash, absf(ghost_mesh.scale.y - 1.0))
	var ghost_velocity: float = ghost.velocity.length()
	print("P2 FLEX remote: max body roll %.4f rad, max squash %.4f, " \
		% [ghost_roll, ghost_squash]
		+ "physics velocity %.5f m/s" % ghost_velocity)
	_check(ghost_roll > 0.02,
		"remote ghost body roll derived from replicated state")
	_check(ghost_squash > 0.001,
		"remote ghost squash/stretch derived from replicated state")
	_check(ghost_velocity < 0.0001,
		"remote ghost flex never writes the physics velocity")
	ghost.queue_free()
	await get_tree().process_frame
	_clear_probe_children()


func _add_flat_ground(size: float) -> StaticBody3D:
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	ground.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, 1.0, size)
	shape_node.shape = box
	ground.add_child(shape_node)
	ground.position.y = -0.5
	add_child(ground)
	return ground


func _clear_probe_children() -> void:
	for child: Node in get_children():
		child.queue_free()


# --------------------------------------------------------------------------
# every map: geometry / collider audit
# --------------------------------------------------------------------------


## Audits all five racing maps and the nine party arenas for the defects a
## player actually sees: mirrored (inside-out) transforms, non-finite poses,
## invalid colliders, static bodies off the WORLD layer, and holes in the road
## collider. A negative determinant is the one way a correctly wound Kenney GLB
## can be rendered inside-out, so it is checked on every node transform.
func _mode_maps() -> void:
	var map_ids: Array[String] = ["stadium", "meadow", "canyon", "dockyard",
		"glacier"]
	var only: String = OS.get_environment("P2_MAP_ONLY")
	for map_id: String in map_ids:
		if only != "" and only != "arenas" and only != map_id:
			continue
		await _audit_racing_map(map_id)
	# Party arenas are built by their mode modules; they are audit-only here
	# (their files are outside the WS2 write scope) but a defect found is
	# reported.
	var arenas: Array[Array] = [
		["cargo_rush", "harbour"], ["cargo_rush", "farmyard"],
		["cargo_rush", "snowfield"], ["knockout", "ko_rooftop"],
		["knockout", "ko_foundry"], ["knockout", "ko_iceberg"],
		["bomb_tag", "bt_plaza"], ["bomb_tag", "bt_labyrinth"],
		["bomb_tag", "bt_ferries"],
	]
	for entry: Array in arenas:
		if only != "" and only != "arenas":
			continue
		await _audit_arena(str(entry[0]), str(entry[1]))


func _audit_racing_map(map_id: String) -> void:
	var preset: Dictionary = TrackDefs.get_preset(map_id).duplicate(true)
	var host := Host.new()
	host.name = "Audit_" + map_id
	host._preset = preset
	add_child(host)
	var theme_id: String = TrackDefs.theme_id_of(preset)
	var spline: RefCounted = KenneyTiles.build(host,
		TrackDefs.grid_of(preset), {"id": theme_id})
	if spline == null:
		_check(false, "%s grid builds" % map_id)
		host.queue_free()
		return
	var theme_path: String = TrackDefs.theme_path_of(preset)
	var theme_script: Script = load(theme_path) as Script
	if theme_script == null:
		_check(false, "%s theme loads (%s)" % [map_id, theme_path])
		host.queue_free()
		return
	var theme_instance: Object = theme_script.new()
	theme_instance.call("build", host, spline)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var report: Dictionary = _audit_scene(host, spline)
	_check_report(map_id, report, true)
	host.queue_free()
	await get_tree().process_frame


func _audit_arena(mode_id: String, arena_id: String) -> void:
	var host := Node3D.new()
	host.name = "Audit_%s_%s" % [mode_id, arena_id]
	add_child(host)
	match mode_id:
		"cargo_rush":
			CargoRushTheme.build_arena(host, arena_id)
		"knockout":
			KnockoutMaps.build_arena(host, arena_id)
		_:
			BombTagMaps.build_arena(host, arena_id)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var report: Dictionary = _audit_scene(host, null)
	_check_report("%s/%s" % [mode_id, arena_id], report, false)
	host.queue_free()
	await get_tree().process_frame


func _check_report(label: String, report: Dictionary, want_coverage: bool) -> void:
	print("P2 MAP %-22s nodes %5d draws %4d mirrored %d nonfinite %d " \
		% [label, int(report["nodes"]), int(report["draw_nodes"]),
			int(report["mirrored"]), int(report["nonfinite"])]
		+ "bodies %4d no-WORLD %d bad-shapes %d" % [
			int(report["bodies"]), int(report["bodies_no_layer"]),
			int(report["bad_shapes"])])
	if want_coverage:
		print("P2 MAP %-22s road collider coverage %.1f%% (%d/%d samples, " \
			% [label, float(report["coverage"]) * 100.0,
				int(report["samples"]) - int(report["misses"]),
				int(report["samples"])]
			+ "%.2f m worst, %d overhead)" % [float(report["max_error"]),
				int(report["overhead"])])
		for line: Variant in report["miss_detail"] as Array:
			print("P2 MAP %-22s   miss: %s" % [label, str(line)])
	_check(int(report["mirrored"]) == 0,
		"%s has no mirrored (inside-out) transforms [%s]" % [label,
			", ".join(report["mirrored_names"] as Array)])
	_check(int(report["nonfinite"]) == 0,
		"%s has no non-finite / degenerate node transforms" % label)
	_check(int(report["bad_shapes"]) == 0,
		"%s has no invalid collision shapes" % label)
	_check(int(report["bodies_no_layer"]) == 0,
		"%s keeps every static body on the WORLD layer" % label)
	if want_coverage:
		_check(float(report["coverage"]) >= 0.95,
			"%s road collider covers the lap (%.1f%%)" % [label,
				float(report["coverage"]) * 100.0])


func _audit_scene(root: Node, spline: Variant) -> Dictionary:
	var report: Dictionary = {
		"nodes": 0, "draw_nodes": 0, "mirrored": 0, "mirrored_names": [],
		"nonfinite": 0, "bodies": 0, "bodies_no_layer": 0,
		"shapes": 0, "bad_shapes": 0, "overhead": 0, "coverage": 1.0,
		"samples": 0, "misses": 0, "max_error": 0.0, "miss_detail": [],
	}
	_audit_walk(root, Transform3D.IDENTITY, report)
	if spline is RefCounted:
		_audit_road_coverage(spline as RefCounted, report)
	return report


func _audit_walk(node: Node, parent_xform: Transform3D,
		report: Dictionary) -> void:
	var here: Transform3D = parent_xform
	if node is Node3D:
		here = parent_xform * (node as Node3D).transform
		report["nodes"] = int(report["nodes"]) + 1
		if not here.origin.is_finite() \
				or absf(here.basis.determinant()) < 0.0000001 \
				or not here.basis.x.is_finite() \
				or not here.basis.y.is_finite() \
				or not here.basis.z.is_finite():
			report["nonfinite"] = int(report["nonfinite"]) + 1
		if here.basis.determinant() < -0.0000001:
			report["mirrored"] = int(report["mirrored"]) + 1
			var names: Array = report["mirrored_names"] as Array
			if names.size() < 6:
				names.append(str(node.get_path()))
	if node is MultiMeshInstance3D or node is MeshInstance3D:
		report["draw_nodes"] = int(report["draw_nodes"]) + 1
	if node is StaticBody3D:
		var body := node as StaticBody3D
		report["bodies"] = int(report["bodies"]) + 1
		if (body.collision_layer & CollisionLayers.WORLD) == 0:
			report["bodies_no_layer"] = int(report["bodies_no_layer"]) + 1
		var valid_shapes: int = 0
		for child: Node in body.get_children():
			var cs := child as CollisionShape3D
			if cs == null:
				continue
			report["shapes"] = int(report["shapes"]) + 1
			if _shape_invalid(cs):
				report["bad_shapes"] = int(report["bad_shapes"]) + 1
			else:
				valid_shapes += 1
		if valid_shapes == 0:
			report["bad_shapes"] = int(report["bad_shapes"]) + 1
	for child: Node in node.get_children():
		_audit_walk(child, here, report)


func _shape_invalid(cs: CollisionShape3D) -> bool:
	if cs.shape == null:
		return true
	var box := cs.shape as BoxShape3D
	if box != null:
		return not (box.size.is_finite() and box.size.x > 0.001 \
			and box.size.y > 0.001 and box.size.z > 0.001)
	var sphere := cs.shape as SphereShape3D
	if sphere != null:
		return not (is_finite(sphere.radius) and sphere.radius > 0.001)
	var capsule := cs.shape as CapsuleShape3D
	if capsule != null:
		return not (is_finite(capsule.radius) and capsule.radius > 0.001 \
			and is_finite(capsule.height) and capsule.height > 0.001)
	var concave := cs.shape as ConcavePolygonShape3D
	if concave != null:
		return concave.get_faces().size() < 3
	var cylinder := cs.shape as CylinderShape3D
	if cylinder != null:
		return not (is_finite(cylinder.radius) and cylinder.radius > 0.001 \
			and is_finite(cylinder.height) and cylinder.height > 0.001)
	return false


## Samples the lap centreline and casts down: every sample that is not a ramp or
## bump must land on road collision at the expected deck height. A miss is a
## hole in the world collider.
func _audit_road_coverage(spline: RefCounted, report: Dictionary) -> void:
	var space: PhysicsDirectSpaceState3D = get_tree().root.get_world_3d() \
		.direct_space_state
	var total: float = maxf(float(spline.get("total_length")), 1.0)
	var count: int = 96
	var samples: int = 0
	var misses: int = 0
	var overhead: int = 0
	var max_error: float = 0.0
	for index in count:
		var distance: float = total * float(index) / float(count)
		var frame: Dictionary = spline.call("sample", distance) as Dictionary
		var position: Vector3 = frame["position"] as Vector3
		if spline.has_method("tile_at"):
			var tile: Variant = spline.call("tile_at", distance)
			if tile is Dictionary:
				var tile_char: String = str((tile as Dictionary).get("tile", ""))
				if tile_char == "J" or tile_char == "B":
					continue
		samples += 1
		var tile_char: String = "?"
		var tile: Variant = spline.call("tile_at", distance) \
			if spline.has_method("tile_at") else null
		if tile is Dictionary:
			tile_char = str((tile as Dictionary).get("tile", "?"))
		var from: Vector3 = position + Vector3.UP * 24.0
		var query := PhysicsRayQueryParameters3D.create(from,
			from - Vector3.UP * 48.0)
		query.collide_with_areas = false
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			misses += 1
			_note_miss(report, distance, tile_char, position, -INF, "no collider")
			continue
		var hit_y: float = (hit["position"] as Vector3).y
		var expected: float = position.y + TileCatalog.ROAD_SURFACE
		if hit_y > expected + 2.5:
			# A gantry beam or a footbridge deck over the road: allowed.
			overhead += 1
			continue
		var error: float = absf(hit_y - expected)
		max_error = maxf(max_error, error)
		# The audit looks for HOLES. Mid-corner the six-chord spline sample and
		# the warped tile-top collider legitimately differ by up to half the
		# 1.5 m per-cell height step (measured worst 0.40 m on meadow), so only a
		# larger discrepancy counts as a miss.
		if error > 0.50:
			misses += 1
			_note_miss(report, distance, tile_char, position, hit_y,
				"height error %.2f m" % error)
	report["samples"] = samples
	report["misses"] = misses
	report["overhead"] = overhead
	report["max_error"] = max_error
	if samples > 0:
		report["coverage"] = 1.0 - float(misses) / float(samples)


func _note_miss(report: Dictionary, distance: float, tile_char: String,
		expected_point: Vector3, hit_y: float, why: String) -> void:
	var detail: Array = report["miss_detail"] as Array
	if detail.size() >= 8:
		return
	detail.append("s=%.0f tile %s at %s -> %s (hit y %s)" % [
		distance, tile_char, str(expected_point), why,
		"miss" if hit_y == -INF else "%.2f" % hit_y])


# --------------------------------------------------------------------------
# stadium seating
# --------------------------------------------------------------------------


func _mode_stadium() -> void:
	var host := Host.new()
	host.name = "P2Stadium"
	var preset: Dictionary = TrackDefs.get_preset("stadium").duplicate(true)
	host._preset = preset
	add_child(host)
	var spline: RefCounted = KenneyTiles.build(host,
		StadiumGrid.grid_rows(), StadiumGrid.theme_dict())
	if spline == null:
		_check(false, "stadium grid did not build")
		return
	StadiumTheme.build(host, spline)
	# The seating direction is a measured fact of the art, not a guess: the
	# grandstand rows step DOWN toward local +Z.
	var facing: Vector3 = _stand_open_face()
	print("P2 STADIUM: grandStand seating opens toward local %s" % str(facing))
	_check(facing.z > 0.9, "grandstand front is local +Z (measured)")
	_check_stand_orientation_math(spline, facing)
	# Headless runs cannot read MultiMesh instance transforms back (the dummy
	# renderer returns identity), so the placed-instance audit needs a windowed
	# run. The maths audit above still gates the headless suite.
	if DisplayServer.get_name() != "headless":
		_check_stand_instances(host, spline, facing)
	host.queue_free()
	await get_tree().process_frame


## Checks the bowl's own stand-yaw contract against the track geometry: a stand
## placed on the clearance ring must turn its open front toward the centreline.
## This is the exact `ring_stand_yaw` + `ring_run` pair stadium_bowl.gd uses.
func _check_stand_orientation_math(spline: RefCounted, facing: Vector3) -> void:
	var plan: Dictionary = StadiumLayout.analyse(spline)
	if plan.is_empty():
		_check(false, "stadium layout analysis is usable")
		return
	var outside: float = float(plan["outside"])
	var ring: Dictionary = StadiumProps.ring(spline, outside,
		StadiumBowl.STAND_LATERAL)
	var sites: Array = StadiumProps.ring_run(ring, 0.0, float(plan["total"]),
		StadiumBowl.STAND_BAY)
	var checked: int = 0
	var facing_track: int = 0
	var facing_away: int = 0
	var worst: float = 1.0
	for site: Dictionary in sites:
		var point: Vector3 = site["position"] as Vector3
		if not StadiumProps.site_ok(spline, point, StadiumBowl.STAND_REACH):
			continue
		if not StadiumProps.side_ok(spline, point, outside):
			continue
		var yaw: float = StadiumBowl.ring_stand_yaw(site, outside)
		var face: Vector3 = Basis(Vector3.UP, yaw) * facing
		face.y = 0.0
		if face.length_squared() < 0.0001:
			continue
		face = face.normalized()
		var hit: Dictionary = spline.plan_closest(point)
		var to_track: Vector3 = (hit["point"] as Vector3) - point
		to_track.y = 0.0
		if to_track.length_squared() < 0.01:
			continue
		to_track = to_track.normalized()
		checked += 1
		var dot: float = face.dot(to_track)
		worst = minf(worst, dot)
		if dot >= 0.25:
			facing_track += 1
		elif dot <= -0.25:
			facing_away += 1
	print("P2 STADIUM: %d ring stand site(s): %d face the track, %d face " \
		% [checked, facing_track, facing_away]
		+ "away, worst dot %+.2f" % worst)
	_check(checked > 0, "stadium ring yields stand sites")
	_check(facing_away == 0 and facing_track >= checked - 2,
		"every ring stand faces the track")


## Windowed-only: audit the MultiMesh instances the theme actually placed.
func _check_stand_instances(host: Node, spline: RefCounted,
		facing: Vector3) -> void:
	var stands: int = 0
	var facing_track: int = 0
	var facing_away: int = 0
	for node: Node in _descendants(host):
		var mmi := node as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null:
			continue
		if not str(mmi.name).begins_with("Stand_"):
			continue
		for inst in mmi.multimesh.instance_count:
			var xf: Transform3D = mmi.multimesh.get_instance_transform(inst)
			var up: Vector3 = xf.basis.y.normalized()
			if up.dot(Vector3.UP) < 0.5:
				_check(false, "stand instance is upside down / rolled at %s"
					% str(xf.origin))
			var face: Vector3 = (xf.basis * facing)
			face.y = 0.0
			if face.length_squared() < 0.0001:
				continue
			face = face.normalized()
			var hit: Dictionary = spline.plan_closest(xf.origin)
			var to_track: Vector3 = (hit["point"] as Vector3) - xf.origin
			to_track.y = 0.0
			if to_track.length_squared() < 0.01:
				continue
			to_track = to_track.normalized()
			stands += 1
			var dot: float = face.dot(to_track)
			if dot >= 0.25:
				facing_track += 1
			elif dot <= -0.25:
				facing_away += 1
			if stands <= 6:
				print("  stand %2d at %s face %s to-track %s dot %+.2f" % [
					stands, str(xf.origin.snapped(Vector3.ONE * 0.1)),
					str(face.snapped(Vector3.ONE * 0.01)),
					str(to_track.snapped(Vector3.ONE * 0.01)), dot])
	print("P2 STADIUM: %d placed stand instance(s), %d face the track, " \
		% [stands, facing_track] + "%d face away" % facing_away)
	_check(stands > 0, "stadium builds stand instances")
	_check(facing_away == 0 and facing_track >= stands - 3,
		"every placed stand faces the track")


## Local plan direction a grandstand's seating opens toward, measured from the
## GLB: the seat tiers step DOWN toward the open front, so the front is the end
## of the model where the top surface is lowest.
func _stand_open_face() -> Vector3:
	for model: String in ["grandStand", "grandStandCovered", "grandStandAwning"]:
		var info: Dictionary = TileCatalog.model_info(model)
		if not bool(info.get("ok", false)):
			return Vector3.FORWARD
		var tris := PackedVector3Array()
		for part: Dictionary in info["parts"] as Array:
			var mesh: Mesh = part["mesh"] as Mesh
			var xform: Transform3D = part["transform"]
			if mesh == null:
				continue
			for surface in mesh.get_surface_count():
				var arrays: Array = mesh.surface_get_arrays(surface)
				if arrays.is_empty():
					continue
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices := PackedInt32Array()
				if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
					indices = arrays[Mesh.ARRAY_INDEX]
				var tri_count: int = indices.size() / 3 \
					if not indices.is_empty() else verts.size() / 3
				for tri in tri_count:
					var i0: int = indices[tri * 3] if not indices.is_empty() \
						else tri * 3
					var i1: int = indices[tri * 3 + 1] \
						if not indices.is_empty() else tri * 3 + 1
					var i2: int = indices[tri * 3 + 2] \
						if not indices.is_empty() else tri * 3 + 2
					tris.append(xform * verts[i0])
					tris.append(xform * verts[i1])
					tris.append(xform * verts[i2])
		var aabb: AABB = info["aabb"]
		var center: Vector2 = info["center"]
		var back: float = _plan_top_z(tris, Vector3(center.x, 0.0,
			aabb.position.z + aabb.size.z * 0.12))
		var front: float = _plan_top_z(tris, Vector3(center.x, 0.0,
			aabb.position.z + aabb.size.z * 0.88))
		print("P2 STADIUM: %-18s back-row top %.3f, front-row top %.3f" % [
			model, back, front])
		if absf(front - back) < 0.01:
			continue
		# Seating descends toward the open front: the low end is the face.
		return Vector3(0.0, 0.0, 1.0 if front < back else -1.0)
	return Vector3.FORWARD


func _collect_mesh_boxes(node: Node, xform: Transform3D, out: Array) -> void:
	var local: Transform3D = xform
	if node is Node3D:
		local = xform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			out.append({"aabb": local * mi.mesh.get_aabb()})
	for child: Node in node.get_children():
		_collect_mesh_boxes(child, local, out)


# --------------------------------------------------------------------------
# vehicle grounding
# --------------------------------------------------------------------------


func _mode_ground() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	ground.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	shape_node.shape = box
	ground.add_child(shape_node)
	ground.position.y = -0.5
	add_child(ground)
	var ids: Array[String] = ["shopping_cart", "sedan", "sports", "race_car",
		"van", "truck", "taxi", "police"]
	for vehicle_id: String in ids:
		var cart: CartPlayer = CartScene.instantiate() as CartPlayer
		cart.ai_mode = true
		cart.position = Vector3(0.0, 0.5, 0.0)
		add_child(cart)
		cart.reapply_vehicle(vehicle_id)
		for index in 30:
			await get_tree().physics_frame
		var origin_y: float = cart.global_position.y
		var model: Node = cart.get_node_or_null("MeshRoot")
		var bottom: float = INF
		if model is Node3D:
			bottom = _node_visual_bottom(model as Node3D, Transform3D.IDENTITY)
		print("  %-14s origin y %.3f, visual bottom %.3f (gap %+.3f m)" % [
			vehicle_id, origin_y, bottom, bottom - origin_y])
		_check(is_finite(bottom) and absf(bottom - origin_y) <= 0.09,
			"%s sits on the ground (visual gap %+.3f m)"
			% [vehicle_id, bottom - origin_y])
		cart.queue_free()
		await get_tree().process_frame
	ground.queue_free()
	await get_tree().process_frame


## Lowest point of every mesh under a vehicle visual node, in the node's parent
## space. `base` is the accumulated parent transform.
func _node_visual_bottom(node: Node3D, base: Transform3D) -> float:
	var here: Transform3D = base
	var lowest: float = INF
	if node != null:
		here = base * node.transform
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.mesh != null:
				var local: Transform3D = here * mi.transform
				var aabb: AABB = mi.mesh.get_aabb()
				for corner_index in 8:
					var corner := aabb.position + Vector3(
						aabb.size.x * float(corner_index & 1),
						aabb.size.y * float((corner_index >> 1) & 1),
						aabb.size.z * float((corner_index >> 2) & 1))
					lowest = minf(lowest, (local * corner).y)
		if child is Node3D:
			lowest = minf(lowest, _node_visual_bottom(child as Node3D, here))
	return lowest


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------


static func _descendants(root_node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in root_node.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found
