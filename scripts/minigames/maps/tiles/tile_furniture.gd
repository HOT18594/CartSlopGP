extends RefCounted
## Trackside furniture for a tile map: the density layer.
##
## Everything here is driven by the decoration anchors TileLayout derives from
## the tile hooks, so a map's grandstands, floodlights, marshal posts, tyre
## walls, billboards, pit complex and jump dressing are authored in the tile
## list instead of being hand-placed in the scene. Big repeats are batched
## through RacingKit; the one-off pieces (pit wall, garages, marshal huts,
## containers, snow banks) are merged into one vertex-coloured mesh per group
## with a single WORLD collision body.
##
## Trees and underbrush are the only large scatter: they are chunked MultiMeshes
## with a visibility range, so the forest beyond the fence costs a handful of
## draw calls and can never be driven through (the fence is solid).

const RaceKit := preload("res://scripts/minigames/racing_kit.gd")
const SceneryKit := preload("res://scripts/minigames/scenery/scenery_kit.gd")
const PropBatch := preload("res://scripts/minigames/scenery/prop_batch.gd")
const FoliageBaker := preload("res://scripts/minigames/foliage_baker.gd")
const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")
const TileCatalog := preload("res://scripts/minigames/maps/tiles/tile_catalog.gd")

const TITLE_FONT: String = "res://assets/ui/fonts/LuckiestGuy-Regular.ttf"
const CREAM := Color("fff6e3")
const STEEL := Color("4a5560")
const CONCRETE := Color("b9b4a8")
const DARK := Color("2f2a26")
const MARSHAL_YELLOW := Color("f2c230")

const CROWD_SHIRTS: Array[Color] = [
	Color("e4572e"), Color("2e86ab"), Color("f6c945"), Color("3fa34d"),
	Color("b84a9c"), Color("f3f0e6"), Color("6c5b7b"), Color("e08e45"),
]
const SKIN_TONES: Array[Color] = [
	Color("f2c9a0"), Color("d9a06b"), Color("a86b3f"), Color("7a4a2b"),
	Color("e8b98a"),
]

## Lateral offsets, kept clear of the road edge, the armco and the catch fence.
const BOARD_LATERAL: float = 8.0
const MARSHAL_LATERAL: float = 12.4
const PIT_WALL_LATERAL: float = 6.95
const PIT_APRON_INNER: float = 6.5
const PIT_APRON_OUTER: float = 14.0
const GARAGE_LATERAL: float = 18.5


## Builds every piece the layout's anchors ask for and returns what was placed.
static func build(parent: Node3D, spline: RefCounted, layout: RefCounted,
		palette: Dictionary) -> Dictionary:
	var stats: Dictionary = {
		"draws": 0, "grandstands": 0, "floodlights": 0, "boards": 0,
		"marshal_posts": 0, "trees": 0, "underbrush": 0, "containers": 0,
		"snow_banks": 0, "pit_bays": 0, "jump_pieces": 0, "objects": 0,
	}
	if parent == null or spline == null or layout == null:
		return stats
	_grandstands(parent, spline, layout, palette, stats)
	_gantry(parent, spline, layout, stats)
	_floodlights(parent, spline, layout, stats)
	_billboards(parent, spline, layout, palette, stats)
	_corner_signs(parent, spline, layout, stats)
	_marshal_posts(parent, spline, layout, stats)
	_pit_complex(parent, spline, layout, palette, stats)
	_jump_dressing(parent, spline, layout, palette, stats)
	_trees(parent, spline, layout, palette, stats)
	match str(palette.get("extras", "")):
		"containers":
			_containers(parent, spline, layout, stats)
		"snow":
			_snow_banks(parent, spline, layout, stats)
	stats["objects"] = int(stats["objects"]) + int(stats["grandstands"]) \
		+ int(stats["floodlights"]) + int(stats["boards"]) \
		+ int(stats["marshal_posts"]) + int(stats["trees"]) \
		+ int(stats["underbrush"]) + int(stats["containers"]) \
		+ int(stats["snow_banks"]) + int(stats["pit_bays"]) \
		+ int(stats["jump_pieces"])
	return stats


# --------------------------------------------------------------------------
# grandstands


## Grandstand groups from the anchors, with a partner stand beside each one when
## the ground is clear. RaceKit owns the stand, its crowd and its colliders.
static func _grandstands(parent: Node3D, spline: RefCounted, layout: RefCounted,
		palette: Dictionary, stats: Dictionary) -> void:
	var placed: Array[float] = []
	var roof: Color = palette.get("stand_roof", Color("c9553f"))
	var seat: Color = palette.get("stand_seat", Color("8fa3b8"))
	for anchor: Dictionary in layout.anchors:
		if str(anchor["kind"]) != "grandstand":
			continue
		var distance: float = float(anchor["distance"])
		var lateral: float = float(anchor["lateral"])
		var side: float = signf(lateral)
		if side == 0.0:
			side = 1.0
		if not _clear_of_stands(placed, distance, spline.total_length, 30.0):
			continue
		if not layout.spot_ok(distance, lateral, 13.0, 7.5):
			continue
		RaceKit.grandstand(parent, spline, distance, side, roof, seat)
		placed.append(distance)
		stats["grandstands"] = int(stats["grandstands"]) + 1
		stats["draws"] = int(stats["draws"]) + 4
		# A second tier behind the first reads as a real grandstand group from
		# the cockpit; it is skipped when the ground behind is not clear.
		var partner: float = distance + 20.0
		if _clear_of_stands(placed, partner, spline.total_length, 18.0) \
				and layout.spot_ok(partner, lateral, 13.0, 7.5):
			RaceKit.grandstand(parent, spline, partner, side, roof, seat)
			placed.append(partner)
			stats["grandstands"] = int(stats["grandstands"]) + 1
			stats["draws"] = int(stats["draws"]) + 4


static func _clear_of_stands(placed: Array[float], distance: float, total: float,
		margin: float) -> bool:
	for other: float in placed:
		var gap: float = absf(fposmod(distance - other + total * 0.5, total) - total * 0.5)
		if gap < margin:
			return false
	return true


# --------------------------------------------------------------------------
# gantry and floodlights


static func _gantry(parent: Node3D, spline: RefCounted, layout: RefCounted,
		stats: Dictionary) -> void:
	for anchor: Dictionary in layout.anchors:
		if str(anchor["kind"]) != "gantry":
			continue
		RaceKit.start_gantry(parent, spline, float(anchor["distance"]))
		stats["draws"] = int(stats["draws"]) + 2
		return


static func _floodlights(parent: Node3D, spline: RefCounted,
		layout: RefCounted, stats: Dictionary) -> void:
	var spots: Array = []
	for anchor: Dictionary in layout.anchors:
		if str(anchor["kind"]) != "floodlight":
			continue
		var distance: float = float(anchor["distance"])
		var lateral: float = float(anchor["lateral"])
		if not layout.spot_ok(distance, lateral, 1.5, 2.4):
			continue
		spots.append(_at(spline, distance, lateral, 0.0))
	var placed: int = RaceKit.floodlight_batch(parent, spots)
	stats["floodlights"] = int(stats["floodlights"]) + placed
	stats["draws"] = int(stats["draws"]) + 2


# --------------------------------------------------------------------------
# signage


static func _billboards(parent: Node3D, spline: RefCounted, layout: RefCounted,
		palette: Dictionary, stats: Dictionary) -> void:
	var boards: Array = []
	for anchor: Dictionary in layout.anchors:
		if str(anchor["kind"]) != "billboard":
			continue
		var distance: float = float(anchor["distance"])
		var lateral: float = float(anchor["lateral"])
		if not layout.spot_ok(distance, lateral, 2.6, 1.2):
			continue
		boards.append({"distance": distance, "lateral": lateral, "width": 4.4})
	var placed: int = RaceKit.signage_batch(parent, spline, boards)
	stats["boards"] = int(stats["boards"]) + placed
	stats["draws"] = int(stats["draws"]) + 1
	# Lettering only on the first few boards: every Label3D is a draw call, and
	# a handful of readable sponsor names is enough at speed.
	var name: String = str(palette.get("map_name", "CART SLOP GP"))
	var texts: PackedStringArray = [name, "CART SLOP GP", "GO FAST", "SLOP"]
	for i in mini(boards.size(), 4):
		var board: Dictionary = boards[i]
		var root: Transform3D = _xform(spline, float(board["distance"]),
			float(board["lateral"]), 0.0)
		var label := Label3D.new()
		label.text = texts[i % texts.size()]
		label.font = load(TITLE_FONT)
		label.font_size = 64
		label.pixel_size = 0.008
		label.outline_size = 8
		label.outline_modulate = Color(0.12, 0.10, 0.20, 0.75)
		label.modulate = CREAM
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.transform = root * Transform3D(Basis.IDENTITY,
			Vector3(0.0, 1.60, -0.12))
		SceneryKit.set_view(label, 0.0, 150.0)
		parent.add_child(label)
		stats["draws"] = int(stats["draws"]) + 1


## Numbered boards on the outside of every corner, batched into one mesh with a
## label per corner.
static func _corner_signs(parent: Node3D, spline: RefCounted,
		layout: RefCounted, stats: Dictionary) -> void:
	var body := _solid(parent, "CornerSigns")
	var batch := PropBatch.new()
	var labels: Array[Dictionary] = []
	var index: int = 0
	for tile: Dictionary in layout.tiles:
		var outside: float = float(tile["outside"])
		if outside == 0.0:
			continue
		index += 1
		var distance: float = float(tile["from"]) + float(tile["span"]) * 0.5
		var lateral: float = outside * BOARD_LATERAL
		if not layout.spot_ok(distance, lateral, 2.2, 1.4):
			continue
		var root: Transform3D = _xform(spline, distance, lateral, 0.0)
		root = root.rotated_local(Vector3.UP, PI)
		batch.add_box(root * Transform3D(Basis.IDENTITY, Vector3(0.0, 1.30, 0.0)),
			Vector3(3.1, 1.1, 0.16), CREAM)
		batch.add_box(root * Transform3D(Basis.IDENTITY, Vector3(0.0, 1.92, 0.02)),
			Vector3(3.2, 0.18, 0.20), Color("c23a2c"))
		for post: float in [-1.25, 1.25]:
			batch.add_box(root * Transform3D(Basis.IDENTITY,
				Vector3(post, 0.60, 0.0)), Vector3(0.14, 1.2, 0.14), STEEL)
		_add_box_shape(body, root * Transform3D(Basis.IDENTITY,
			Vector3(0.0, 1.05, 0.0)), Vector3(3.2, 2.1, 0.3))
		labels.append({"index": index, "transform": root})
	_merged(body, batch, "CornerSignDetail")
	stats["boards"] = int(stats["boards"]) + labels.size()
	stats["draws"] = int(stats["draws"]) + 1
	for entry: Dictionary in labels:
		var label := Label3D.new()
		label.text = str(entry["index"])
		label.font = load(TITLE_FONT)
		label.font_size = 96
		label.pixel_size = 0.0075
		label.outline_size = 10
		label.outline_modulate = Color(0.12, 0.10, 0.20, 0.85)
		label.modulate = DARK
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.transform = (entry["transform"] as Transform3D) * Transform3D(
			Basis.IDENTITY, Vector3(0.0, 1.30, -0.10))
		SceneryKit.set_view(label, 0.0, 130.0)
		parent.add_child(label)
		stats["draws"] = int(stats["draws"]) + 1


# --------------------------------------------------------------------------
# marshal posts


## Small huts on the outside of the lap, each with a marshal, a flag and a fire
## extinguisher. One merged mesh and one body for every hut.
static func _marshal_posts(parent: Node3D, spline: RefCounted,
		layout: RefCounted, stats: Dictionary) -> void:
	var body := _solid(parent, "MarshalHuts")
	var batch := PropBatch.new()
	var figures: Dictionary = _figure_meshes()
	var bodies: Array = []
	var heads: Array = []
	var shirts: Array = []
	var skins: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7301
	var placed: int = 0
	for anchor: Dictionary in layout.anchors:
		if str(anchor["kind"]) != "marshal":
			continue
		var distance: float = float(anchor["distance"])
		var side: float = float(anchor["side"])
		if side == 0.0:
			side = 1.0
		var lateral: float = side * MARSHAL_LATERAL
		if not layout.spot_ok(distance, lateral, 1.6, 1.8):
			continue
		var root: Transform3D = _xform(spline, distance, lateral, 0.0)
		batch.add_box(root * Transform3D(Basis.IDENTITY, Vector3(0.0, 1.15, 0.0)),
			Vector3(2.4, 2.3, 2.0), CREAM)
		batch.add_box(root * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-12.0)),
			Vector3(0.0, 2.52, -0.18)), Vector3(2.9, 0.16, 2.7),
			Color("c9553f"))
		batch.add_box(root * Transform3D(Basis.IDENTITY, Vector3(-1.22, 1.6, 0.0)),
			Vector3(0.08, 0.62, 1.5), DARK)
		batch.add_box(root * Transform3D(Basis.IDENTITY, Vector3(1.7, 1.9, 0.5)),
			Vector3(0.09, 3.8, 0.09), STEEL)
		batch.add_box(root * Transform3D(Basis.IDENTITY, Vector3(1.7, 3.55, 0.82)),
			Vector3(0.04, 0.5, 0.62), MARSHAL_YELLOW)
		_add_box_shape(body, root * Transform3D(Basis.IDENTITY,
			Vector3(0.0, 1.15, 0.0)), Vector3(2.5, 2.4, 2.2))
		var figure: Transform3D = root * Transform3D(Basis.IDENTITY,
			Vector3(-1.05, 0.0, -0.5))
		bodies.append(figure * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.52, 0.0)))
		heads.append(figure * Transform3D(Basis.IDENTITY, Vector3(0.0, 1.12, 0.0)))
		shirts.append(MARSHAL_YELLOW)
		skins.append(SKIN_TONES[rng.randi_range(0, SKIN_TONES.size() - 1)])
		placed += 1
	_merged(body, batch, "MarshalHutDetail")
	stats["marshal_posts"] = int(stats["marshal_posts"]) + placed
	stats["draws"] = int(stats["draws"]) + 1
	if bodies.is_empty():
		return
	var body_view := SceneryKit.multimesh(figures["body"] as Mesh,
		figures["material"] as Material, bodies, "MarshalStaff", false, shirts)
	SceneryKit.set_view(body_view, 0.0, 160.0)
	parent.add_child(body_view)
	var head_view := SceneryKit.multimesh(figures["head"] as Mesh,
		figures["material"] as Material, heads, "MarshalStaffHeads", false, skins)
	SceneryKit.set_view(head_view, 0.0, 160.0)
	parent.add_child(head_view)
	stats["draws"] = int(stats["draws"]) + 2


static func _figure_meshes() -> Dictionary:
	var body := CapsuleMesh.new()
	body.radius = 0.22
	body.height = 0.92
	body.radial_segments = 6
	body.rings = 2
	var head := SphereMesh.new()
	head.radius = 0.17
	head.height = 0.34
	head.radial_segments = 5
	head.rings = 2
	return {"body": body, "head": head,
		"material": SceneryKit.instance_material(0.92)}


# --------------------------------------------------------------------------
# pit complex


## Concrete apron, pit wall, garages and crew for a pit straight.
static func _pit_complex(parent: Node3D, spline: RefCounted, layout: RefCounted,
		palette: Dictionary, stats: Dictionary) -> void:
	for anchor: Dictionary in layout.anchors:
		if str(anchor["kind"]) != "pit":
			continue
		var from_distance: float = float(anchor["distance"])
		var span: float = float(anchor["length"])
		var side: float = float(anchor["side"]) if float(anchor["side"]) != 0.0 \
			else 1.0
		var concrete: Material = palette.get("concrete", null) as Material
		_ribbon(parent, spline, from_distance + 1.0, from_distance + span - 1.0,
			PIT_APRON_INNER * side, PIT_APRON_OUTER * side,
			TileCatalog.ROAD_Y + 0.012, concrete, "PitApron")
		var body := _solid(parent, "PitFurniture")
		var batch := PropBatch.new()
		var bays: int = 0
		var step: float = 5.2
		var count: int = maxi(int(floor((span - 6.0) / step)), 1)
		for i in count:
			var distance: float = from_distance + 4.0 + (float(i) + 0.5) * step
			var wall: Transform3D = _xform(spline, distance,
				PIT_WALL_LATERAL * side, 0.0)
			batch.add_box(wall * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.52, 0.0)),
				Vector3(0.34, 1.04, step + 0.1), CONCRETE)
			batch.add_box(wall * Transform3D(Basis.IDENTITY, Vector3(0.0, 1.10, 0.0)),
				Vector3(0.46, 0.12, step + 0.14), CREAM)
			_add_box_shape(body, wall * Transform3D(Basis.IDENTITY,
				Vector3(0.0, 0.52, 0.0)), Vector3(0.44, 1.04, step + 0.1))
		var garage_step: float = 6.2
		var garage_count: int = maxi(int(floor((span - 10.0) / garage_step)), 1)
		for i in garage_count:
			var distance: float = from_distance + 7.0 \
				+ (float(i) + 0.5) * garage_step
			var bay: Transform3D = _xform(spline, distance,
				GARAGE_LATERAL * side, 0.0)
			batch.add_box(bay * Transform3D(Basis.IDENTITY, Vector3(0.0, 1.65, 0.0)),
				Vector3(5.0, 3.3, garage_step + 0.2), CONCRETE.darkened(0.06))
			batch.add_box(bay * Transform3D(Basis.IDENTITY, Vector3(0.0, 3.42, 0.0)),
				Vector3(5.6, 0.22, garage_step + 0.3), STEEL)
			batch.add_box(bay * Transform3D(Basis.IDENTITY,
				Vector3(-2.55, 1.25, 0.0)), Vector3(0.08, 2.5, 3.4), DARK)
			batch.add_box(bay * Transform3D(Basis.IDENTITY,
				Vector3(-2.62, 2.62, 0.0)), Vector3(0.10, 0.26, 3.7), CREAM)
			var awning: Color = palette.get("accent", Color("c9553f"))
			batch.add_box(bay * Transform3D(Basis.IDENTITY,
				Vector3(-3.35, 3.16, 0.0)), Vector3(1.6, 0.14, garage_step + 0.1),
				awning)
			_add_box_shape(body, bay * Transform3D(Basis.IDENTITY,
				Vector3(0.0, 1.65, 0.0)), Vector3(5.0, 3.3, garage_step + 0.2))
			bays += 1
		_merged(body, batch, "PitDetail")
		stats["pit_bays"] = int(stats["pit_bays"]) + bays
		stats["draws"] = int(stats["draws"]) + 2
		_pit_crew(parent, spline, from_distance, span, side, palette)
		stats["draws"] = int(stats["draws"]) + 2
		return


static func _pit_crew(parent: Node3D, spline: RefCounted, from_distance: float,
		span: float, side: float, palette: Dictionary) -> void:
	var figures: Dictionary = _figure_meshes()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4409
	var bodies: Array = []
	var heads: Array = []
	var shirts: Array = []
	var skins: Array = []
	var count: int = maxi(int((span - 8.0) / 5.0), 1)
	for i in count:
		var distance: float = from_distance + 5.0 + float(i) * 5.0
		var lateral: float = side * rng.randf_range(9.4, 12.0)
		var root: Transform3D = _xform(spline, distance, lateral, 0.0)
		var figure: Transform3D = root * Transform3D(
			Basis(Vector3.UP, rng.randf_range(-2.6, 2.6)), Vector3.ZERO)
		bodies.append(figure * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.46, 0.0)))
		heads.append(figure * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.95, 0.0)))
		shirts.append(CROWD_SHIRTS[rng.randi_range(0, CROWD_SHIRTS.size() - 1)])
		skins.append(SKIN_TONES[rng.randi_range(0, SKIN_TONES.size() - 1)])
	if bodies.is_empty():
		return
	var body_view := SceneryKit.multimesh(figures["body"] as Mesh,
		figures["material"] as Material, bodies, "PitCrew", false, shirts)
	SceneryKit.set_view(body_view, 0.0, 150.0)
	parent.add_child(body_view)
	var head_view := SceneryKit.multimesh(figures["head"] as Mesh,
		figures["material"] as Material, heads, "PitCrewHeads", false, skins)
	SceneryKit.set_view(head_view, 0.0, 150.0)
	parent.add_child(head_view)


## One paved strip with a solid WORLD face, used for the pit apron.
static func _ribbon(parent: Node3D, spline: RefCounted, from_distance: float,
		to_distance: float, lateral_a: float, lateral_b: float, height: float,
		material: Material, node_name: String) -> void:
	var span: float = to_distance - from_distance
	if span <= 0.01 or material == null:
		return
	var steps: int = maxi(int(ceil(span / 2.0)), 1)
	var step: float = span / float(steps)
	var low: float = minf(lateral_a, lateral_b)
	var high: float = maxf(lateral_a, lateral_b)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var faces := PackedVector3Array()
	for i in steps + 1:
		var s: float = from_distance + step * float(i)
		var frame: Dictionary = spline.sample(s)
		var base: Vector3 = (frame["position"] as Vector3) + Vector3.UP * height
		var right: Vector3 = frame["right"]
		verts.append(base + right * low)
		verts.append(base + right * high)
		norms.append(Vector3.UP)
		norms.append(Vector3.UP)
		uvs.append(Vector2(low / 6.0, s / 6.0))
		uvs.append(Vector2(high / 6.0, s / 6.0))
	for i in steps:
		var a: int = i * 2
		indices.append(a)
		indices.append(a + 2)
		indices.append(a + 1)
		indices.append(a + 1)
		indices.append(a + 2)
		indices.append(a + 3)
		faces.append_array([verts[a], verts[a + 2], verts[a + 1],
			verts[a + 1], verts[a + 2], verts[a + 3]])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var visual := MeshInstance3D.new()
	visual.name = node_name
	visual.mesh = mesh
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(visual)
	var body := _solid(parent, node_name + "Collision")
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = false
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)


# --------------------------------------------------------------------------
# jump dressing


## Chevron boards, edge banners and a landing arch around a jump tile.
static func _jump_dressing(parent: Node3D, spline: RefCounted,
		layout: RefCounted, palette: Dictionary, stats: Dictionary) -> void:
	for anchor: Dictionary in layout.anchors:
		if str(anchor["kind"]) != "jump":
			continue
		var distance: float = float(anchor["distance"])
		var span: float = float(anchor["length"])
		var body := _solid(parent, "JumpDressing")
		var batch := PropBatch.new()
		var accent: Color = palette.get("accent", Color("c9553f"))
		for side: float in [-1.0, 1.0]:
			var lateral: float = side * 8.2
			if not layout.spot_ok(distance, lateral, 3.0, 1.6):
				continue
			var root: Transform3D = _xform(spline, distance, lateral, 0.0)
			root = root.rotated_local(Vector3.UP, PI)
			batch.add_box(root * Transform3D(Basis.IDENTITY,
				Vector3(0.0, 2.0, 0.0)), Vector3(0.18, 4.0, 0.18), STEEL)
			batch.add_box(root * Transform3D(Basis.IDENTITY,
				Vector3(0.0, 3.6, -0.12)), Vector3(2.8, 0.9, 0.10), CREAM)
			batch.add_box(root * Transform3D(Basis.IDENTITY,
				Vector3(0.0, 4.12, -0.12)), Vector3(2.9, 0.18, 0.14), accent)
			for stripe in 4:
				batch.add_box(root * Transform3D(
					Basis(Vector3.BACK, deg_to_rad(30.0)),
					Vector3(-0.9 + float(stripe) * 0.6, 3.6, -0.20)),
					Vector3(0.16, 0.8, 0.06), DARK)
			_add_box_shape(body, root * Transform3D(Basis.IDENTITY,
				Vector3(0.0, 2.0, 0.0)), Vector3(0.5, 4.0, 0.5))
		# Edge banners along both sides of the ramp.
		for side: float in [-1.0, 1.0]:
			for i in 5:
				var d: float = distance - span * 0.42 + span * 0.84 * float(i) / 4.0
				var root: Transform3D = _xform(spline, d, side * 6.9, 0.0)
				batch.add_box(root * Transform3D(Basis.IDENTITY,
					Vector3(0.0, 0.62, 0.0)), Vector3(0.16, 1.24, 0.16), STEEL)
				batch.add_box(root * Transform3D(Basis.IDENTITY,
					Vector3(0.0, 1.20, 0.0)), Vector3(0.06, 0.34, 2.4),
					accent if i % 2 == 0 else CREAM)
				_add_box_shape(body, root * Transform3D(Basis.IDENTITY,
					Vector3(0.0, 0.62, 0.0)), Vector3(0.4, 1.24, 2.6))
		_merged(body, batch, "JumpDetail")
		var label := Label3D.new()
		label.text = "JUMP"
		label.font = load(TITLE_FONT)
		label.font_size = 96
		label.pixel_size = 0.012
		label.outline_size = 12
		label.outline_modulate = Color(0.12, 0.10, 0.20, 0.85)
		label.modulate = accent
		label.transform = _xform(spline, distance, 0.0, 3.2) * Transform3D(
			Basis.IDENTITY, Vector3.ZERO)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		SceneryKit.set_view(label, 0.0, 170.0)
		parent.add_child(label)
		stats["jump_pieces"] = int(stats["jump_pieces"]) + 1
		stats["draws"] = int(stats["draws"]) + 2
		return


# --------------------------------------------------------------------------
# foliage


## Trees and underbrush in the verge beyond the fence. Positions are rejected
## when another part of the loop is close, so a tree can never stand on a lane.
static func _trees(parent: Node3D, spline: RefCounted, layout: RefCounted,
		palette: Dictionary, stats: Dictionary) -> void:
	var models: PackedStringArray = palette.get("trees", PackedStringArray())
	var bushes: PackedStringArray = palette.get("bushes", PackedStringArray())
	if models.is_empty():
		return
	var material: Material = FoliageBaker.make_material()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(palette.get("id", "stadium"))) + 9137
	var buckets: Dictionary = {}
	var total: float = spline.total_length
	var cursor: float = 0.0
	while cursor < total:
		for side: float in [-1.0, 1.0]:
			if rng.randf() > 0.9:
				continue
			var lateral: float = side * rng.randf_range(12.5, 34.0)
			var distance: float = cursor + rng.randf_range(-3.0, 3.0)
			var point: Vector3 = _at(spline, distance, lateral, 0.0)
			if not layout.clearance(point, 6.5):
				continue
			var model: String = models[rng.randi_range(0, models.size() - 1)]
			if not buckets.has(model):
				buckets[model] = []
			var scale: float = rng.randf_range(0.85, 1.35)
			var basis: Basis = Basis(Vector3.UP, rng.randf() * TAU).scaled(
				Vector3.ONE * scale)
			(buckets[model] as Array).append(
				Transform3D(basis, point + Vector3.UP * 0.02))
			stats["trees"] = int(stats["trees"]) + 1
		cursor += 4.0
	for model: String in buckets:
		var baked: ArrayMesh = FoliageBaker.bake(model)
		if baked == null:
			continue
		parent.add_child(FoliageBaker.create_chunked_instances(
			baked, material, buckets[model], false, 230.0, [], 110.0))
		stats["draws"] = int(stats["draws"]) + 3
	# Low underbrush hugs the fence line and hides the base of the trees.
	if bushes.is_empty():
		return
	var bush_buckets: Dictionary = {}
	var bush_cursor: float = 0.0
	while bush_cursor < total:
		for side: float in [-1.0, 1.0]:
			if rng.randf() > 0.55:
				continue
			var lateral: float = side * rng.randf_range(10.2, 18.0)
			var point: Vector3 = _at(spline, bush_cursor, lateral, 0.0)
			if not layout.clearance(point, 6.0):
				continue
			var model: String = bushes[rng.randi_range(0, bushes.size() - 1)]
			if not bush_buckets.has(model):
				bush_buckets[model] = []
			var scale: float = rng.randf_range(0.9, 1.9)
			var basis: Basis = Basis(Vector3.UP, rng.randf() * TAU).scaled(
				Vector3.ONE * scale)
			(bush_buckets[model] as Array).append(
				Transform3D(basis, point + Vector3.UP * 0.02))
			stats["underbrush"] = int(stats["underbrush"]) + 1
		bush_cursor += 9.0
	for model: String in bush_buckets:
		var baked: ArrayMesh = FoliageBaker.bake(model)
		if baked == null:
			continue
		parent.add_child(FoliageBaker.create_chunked_instances(
			baked, material, bush_buckets[model], false, 120.0, [], 110.0))
		stats["draws"] = int(stats["draws"]) + 2


# --------------------------------------------------------------------------
# theme extras


## Shipping containers and warehouse shells for the dockyard quay.
static func _containers(parent: Node3D, spline: RefCounted,
		layout: RefCounted, stats: Dictionary) -> void:
	var body := _solid(parent, "QuayContainers")
	var batch := PropBatch.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5511
	var colours: Array[Color] = [
		Color("a94f42"), Color("2e86ab"), Color("3fa34d"), Color("c5a44f"),
		Color("6c5b7b"), Color("e08e45"),
	]
	var stacks: int = 0
	var anchors: Array = []
	for anchor: Dictionary in layout.anchors:
		if str(anchor["kind"]) == "containers":
			anchors.append(anchor)
	# One yard per anchor, plus a second row further out so the quay reads as a
	# working dock from the cockpit.
	for anchor: Dictionary in anchors:
		for row in 2:
			for slot in 3:
				var distance: float = float(anchor["distance"]) \
					+ (float(slot) - 1.0) * 6.4
				var lateral: float = float(anchor["lateral"]) \
					+ float(row) * 7.0 + rng.randf_range(-0.6, 0.6)
				var point: Vector3 = _at(spline, distance, lateral, 0.0)
				if not layout.clearance(point, 4.0):
					continue
				var root: Transform3D = _xform(spline, distance, lateral, 0.0)
				var levels: int = 1 + (1 if rng.randf() < 0.45 else 0)
				for level in levels:
					var colour: Color = colours[rng.randi_range(0, colours.size() - 1)]
					batch.add_box(root * Transform3D(Basis.IDENTITY,
						Vector3(0.0, 1.3 + float(level) * 2.62, 0.0)),
						Vector3(6.0, 2.55, 2.45), colour)
					batch.add_box(root * Transform3D(Basis.IDENTITY,
						Vector3(0.0, 2.62 + float(level) * 2.62, 0.0)),
						Vector3(6.05, 0.12, 2.5), colour.darkened(0.25))
					_add_box_shape(body, root * Transform3D(Basis.IDENTITY,
						Vector3(0.0, 1.3 + float(level) * 2.62, 0.0)),
						Vector3(6.0, 2.55, 2.45))
					stacks += 1
	_merged(body, batch, "ContainerDetail")
	stats["containers"] = int(stats["containers"]) + stacks
	stats["draws"] = int(stats["draws"]) + 1
	# Two warehouse shells close the horizon behind the yard.
	var shed := PropBatch.new()
	var shed_body := _solid(parent, "QuayWarehouses")
	for index in 2:
		var distance: float = spline.total_length * (0.18 + 0.5 * float(index))
		var side: float = -1.0 if index == 0 else 1.0
		var lateral: float = side * 30.0
		if not layout.spot_ok(distance, lateral, 14.0, 10.0):
			continue
		var root: Transform3D = _xform(spline, distance, lateral, 0.0)
		shed.add_box(root * Transform3D(Basis.IDENTITY, Vector3(0.0, 4.0, 0.0)),
			Vector3(24.0, 8.0, 12.0), CONCRETE.darkened(0.10))
		shed.add_box(root * Transform3D(Basis.IDENTITY, Vector3(0.0, 8.3, 0.0)),
			Vector3(25.0, 0.5, 13.0), STEEL)
		for bay in 4:
			shed.add_box(root * Transform3D(Basis.IDENTITY,
				Vector3(-7.5 + float(bay) * 5.0, 2.4, -6.05)),
				Vector3(3.4, 4.4, 0.12), DARK)
		_add_box_shape(shed_body, root * Transform3D(Basis.IDENTITY,
			Vector3(0.0, 4.0, 0.0)), Vector3(24.0, 8.0, 12.0))
	_merged(shed_body, shed, "WarehouseDetail")
	stats["draws"] = int(stats["draws"]) + 1


## Ploughed snow banks along the outside of the glacier loop, with marker poles.
static func _snow_banks(parent: Node3D, spline: RefCounted, layout: RefCounted,
		stats: Dictionary) -> void:
	var body := _solid(parent, "SnowBanks")
	var batch := PropBatch.new()
	var posts: Array = []
	var total: float = spline.total_length
	var cursor: float = 0.0
	var pieces: int = 0
	while cursor < total:
		for side: float in [-1.0, 1.0]:
			var lateral: float = side * 11.6
			var point: Vector3 = _at(spline, cursor, lateral, 0.0)
			if not layout.clearance(point, 6.0):
				continue
			var root: Transform3D = _xform(spline, cursor, lateral, 0.0)
			# A wedge bank: wide at the base, low enough to see over.
			batch.add_box(root * Transform3D(Basis(Vector3.BACK, deg_to_rad(-16.0)),
				Vector3(0.0, 0.55, 0.0)), Vector3(4.4, 1.5, 7.0),
				Color(0.93, 0.96, 1.0))
			batch.add_box(root * Transform3D(Basis.IDENTITY,
				Vector3(0.0, 0.10, 0.0)), Vector3(5.4, 0.3, 7.2),
				Color(0.86, 0.90, 0.96))
			_add_box_shape(body, root * Transform3D(Basis.IDENTITY,
				Vector3(0.0, 0.5, 0.0)), Vector3(4.4, 1.5, 7.0))
			posts.append(root * Transform3D(Basis.IDENTITY,
				Vector3(0.0, 1.0, 0.0)))
			pieces += 1
		cursor += 9.0
	_merged(body, batch, "SnowBankDetail")
	stats["snow_banks"] = int(stats["snow_banks"]) + pieces
	stats["draws"] = int(stats["draws"]) + 1
	if posts.is_empty():
		return
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.12, 2.0, 0.12)
	var marker := SceneryKit.multimesh(_box_to_array(post_mesh),
		SceneryKit.instance_material(0.9), posts, "SnowMarkerPosts", false)
	SceneryKit.set_view(marker, 0.0, 150.0)
	parent.add_child(marker)
	stats["draws"] = int(stats["draws"]) + 1


# --------------------------------------------------------------------------
# helpers


static func _at(spline: RefCounted, distance: float, lateral: float,
		height: float) -> Vector3:
	var frame: Dictionary = spline.sample(distance)
	return (frame["position"] as Vector3) + (frame["right"] as Vector3) * lateral \
		+ Vector3.UP * height


static func _xform(spline: RefCounted, distance: float, lateral: float,
		height: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, spline.yaw_at(distance)),
		_at(spline, distance, lateral, height))


static func _solid(parent: Node3D, node_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = 0
	parent.add_child(body)
	return body


static func _add_box_shape(body: StaticBody3D, xform: Transform3D,
		size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = xform
	body.add_child(collision)


static func _merged(root: Node3D, batch: PropBatch, node_name: String) -> void:
	var mesh: ArrayMesh = batch.build()
	if mesh == null:
		return
	var visual := MeshInstance3D.new()
	visual.name = node_name
	visual.mesh = mesh
	visual.material_override = SceneryKit.vertex_material()
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(visual)


static func _box_to_array(box: BoxMesh) -> ArrayMesh:
	var arrays: Array = box.surface_get_arrays(0)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
