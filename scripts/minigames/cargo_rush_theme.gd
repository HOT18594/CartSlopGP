extends RefCounted
## The three CARGO RUSH arena skins, chosen by theme id.
##
## A theme owns the ground scans, the yard dressing behind the walls, the
## present art and the grip rule of the arena. The footprint, the handling
## loop, the bases and every rule are identical for every theme, so a skin can
## never change the game - only how it looks and how much grip a kart gets.
##
## Textures are the CC0 Poly Haven scans already in the project. A source
## checkout that has not run the importer yet cannot load the JPGs, so every
## material falls back to a flat tint instead of spraying resource errors.
##
## Every solid piece built here (containers, bales, gift piles, trees, rocks,
## stumps) carries a real collider on CollisionLayers.WORLD. Ground hazards
## (ice, mud, wet patches) are floor markings, not props: they are visible
## discs that only change the karts' grip.

const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")
const SceneryKit := preload("res://scripts/minigames/scenery/scenery_kit.gd")
const PropBatch := preload("res://scripts/minigames/scenery/prop_batch.gd")
const FoliageBaker := preload("res://scripts/minigames/foliage_baker.gd")

const PBR_SHADER: String = "res://assets/materials/ground_pbr.gdshader"
const PBR_TEX: String = "res://assets/textures/polyhaven/"
const DEFAULT_ID: String = "dockyard"
const THEME_IDS: PackedStringArray = ["dockyard", "farmyard", "snowfield"]

## Ice: very low lateral grip plus the arena's own spin wobble.
const ICE_GRIP: float = 0.34
const ICE_SPIN: float = 2.4
## Soft mud: a noticeable slide without the spin.
const MUD_GRIP: float = 0.72
## Wet asphalt: the dockyard's only real drop.
const WET_GRIP: float = 0.84

## Present collider / pickup footprint, shared by every theme. A present never
## blocks a kart: it is picked up, not pushed, so it carries no body at all.
const PRESENT_EXTENTS: Vector3 = Vector3(0.92, 0.76, 0.92)

const THEMES: Dictionary = {
	"dockyard": {
		"id": "dockyard",
		"name": "DOCKYARD",
		"blurb": "WET CONCRETE",
		"teams": ["DOCK CREW", "HARBOUR RATS"],
		"sky_top": Color(0.16, 0.47, 0.70),
		"sky_horizon": Color(0.72, 0.85, 0.92),
		"ground_bottom": Color(0.15, 0.24, 0.29),
		"fog_color": Color(0.70, 0.82, 0.89),
		"fog_density": 0.0026,
		"floor": ["asphalt_01_diff", "asphalt_01_nor", "asphalt_01_rough"],
		"floor_tint": Color(0.78, 0.83, 0.88),
		"floor_uv": 0.20,
		"floor_detail": 0.12,
		"floor_macro": 0.04,
		"floor_roughness": 0.34,
		"apron": ["concrete_floor_worn_001_diff", "concrete_floor_worn_001_nor",
			"concrete_floor_worn_001_rough"],
		"apron_tint": Color(0.90, 0.90, 0.87),
		"apron_uv": 0.14,
		"apron_roughness": 0.42,
		"dirt": ["asphalt_02_diff", "asphalt_02_nor", "asphalt_02_rough"],
		"dirt_tint": Color(0.62, 0.58, 0.52),
		"dirt_uv": 0.26,
		"dirt_roughness": 0.88,
		"skid_tint": Color(0.30, 0.32, 0.34),
		"grip": 0.94,
		"present_kind": "parcel",
		"present_label": "SHRINK-WRAPPED PARCELS",
		"hazard_label": "WET PATCHES  ·  LIGHT SLIDE",
		"foliage_tint": Color(0.72, 0.82, 0.72),
		"bark_tint": Color(0.86, 0.80, 0.70),
		"hazard": {"kind": "wet", "grip": WET_GRIP, "spin": 0.0,
			"tint": Color(0.42, 0.52, 0.60), "spots": [
				Vector2(9.0, -10.0), Vector2(-14.0, -3.0)]},
		"yard": "containers",
	},
	"farmyard": {
		"id": "farmyard",
		"name": "FARMYARD",
		"blurb": "SOFT DIRT",
		"teams": ["PADDOCK POSSE", "BARN RAIDERS"],
		"sky_top": Color(0.23, 0.55, 0.78),
		"sky_horizon": Color(0.85, 0.89, 0.76),
		"ground_bottom": Color(0.32, 0.27, 0.16),
		"fog_color": Color(0.84, 0.86, 0.72),
		"fog_density": 0.0018,
		"floor": ["grass_diff", "grass_nor", "grass_rough"],
		"floor_tint": Color(0.86, 0.90, 0.72),
		"floor_uv": 0.18,
		"floor_detail": 0.16,
		"floor_macro": 0.05,
		"floor_roughness": 0.90,
		"apron": [],
		"dirt": ["dirt_diff", "dirt_nor", "dirt_rough"],
		"dirt_tint": Color(0.92, 0.84, 0.70),
		"dirt_uv": 0.22,
		"dirt_roughness": 0.94,
		"skid_tint": Color(0.52, 0.44, 0.30),
		"grip": 0.86,
		"present_kind": "basket",
		"present_label": "PRODUCE BASKETS",
		"hazard_label": "MUD PATCHES  ·  SOFT SLIDE",
		"foliage_tint": Color(0.88, 1.0, 0.74),
		"bark_tint": Color(1.0, 0.94, 0.84),
		"hazard": {"kind": "mud", "grip": MUD_GRIP, "spin": 0.0,
			"tint": Color(0.44, 0.34, 0.20), "spots": [
				Vector2(12.0, -8.0), Vector2(-10.0, -16.0)]},
		"yard": "bales",
	},
	"snowfield": {
		"id": "snowfield",
		"name": "SNOWFIELD",
		"blurb": "PACKED SNOW",
		"teams": ["YULECREW", "REINDEER"],
		"sky_top": Color(0.42, 0.63, 0.84),
		"sky_horizon": Color(0.90, 0.94, 0.99),
		"ground_bottom": Color(0.72, 0.80, 0.88),
		"fog_color": Color(0.88, 0.93, 0.98),
		"fog_density": 0.0030,
		"floor": ["snow_02_diff", "snow_02_nor", "snow_02_rough"],
		"floor_tint": Color(0.94, 0.97, 1.0),
		"floor_uv": 0.22,
		"floor_detail": 0.08,
		"floor_macro": 0.03,
		"floor_roughness": 0.55,
		"apron": [],
		"dirt": ["snow_02_diff", "snow_02_nor", "snow_02_rough"],
		"dirt_tint": Color(0.82, 0.88, 0.96),
		"dirt_uv": 0.20,
		"dirt_roughness": 0.60,
		"skid_tint": Color(0.66, 0.76, 0.86),
		"grip": 0.90,
		"present_kind": "gift",
		"present_label": "WRAPPED GIFTS",
		"hazard_label": "ICE PATCHES  ·  SPIN OUT",
		"foliage_tint": Color(0.90, 0.96, 1.0),
		"bark_tint": Color(0.84, 0.86, 0.90),
		"hazard": {"kind": "ice", "grip": ICE_GRIP, "spin": ICE_SPIN,
			"tint": Color(0.36, 0.58, 0.74), "spots": [
				Vector2(10.0, -12.0), Vector2(-13.0, -6.0)]},
		"yard": "gifts",
	},
}


## Every theme id in registry order.
static func ids() -> PackedStringArray:
	return THEME_IDS


## Map a loose id (menu selection, map id, env override) to a theme id.
static func resolve(id: String) -> String:
	var key: String = id.strip_edges().to_lower()
	match key:
		"dockyard", "dockyard_dash", "cargo_rush", "harbour", "harbor":
			return "dockyard"
		"farmyard", "farm", "meadow", "meadow_loop", "circuit":
			return "farmyard"
		"snowfield", "snow", "alpine", "alpine_slide":
			return "snowfield"
	return DEFAULT_ID


## The data block for `id`, never null.
static func get_theme(id: String) -> Dictionary:
	var key: String = resolve(id)
	var entry: Variant = THEMES.get(key, THEMES[DEFAULT_ID])
	return entry as Dictionary


## The two team names, always exactly two entries.
static func team_names(theme: Dictionary) -> PackedStringArray:
	var names := PackedStringArray()
	var raw: Variant = theme.get("teams", [])
	if raw is Array:
		for entry: Variant in raw as Array:
			names.append(str(entry))
	while names.size() < 2:
		names.append("CREW %d" % (names.size() + 1))
	return names


## Human label for what a present is in this theme.
static func present_label(theme: Dictionary) -> String:
	return str(theme.get("present_label", "PRESENTS"))


## Ground material for the arena floor (the asphalt/snow/grass outside the
## painted apron). Uses the Poly Haven scans when the importer has produced
## them, and a flat tint otherwise.
static func floor_material(theme: Dictionary) -> Material:
	var files: Array = _string_list(theme.get("floor", []))
	return _pbr_material(files, theme.get("floor_tint", Color.WHITE) as Color,
		float(theme.get("floor_uv", 1.0)),
		float(theme.get("floor_detail", 0.1)),
		float(theme.get("floor_macro", 0.04)),
		float(theme.get("floor_roughness", 0.7)))


## Worn-concrete apron laid over the playfield; null when the theme has none.
static func apron_material(theme: Dictionary) -> Material:
	var files: Array = _string_list(theme.get("apron", []))
	if files.is_empty():
		return null
	return _pbr_material(files, theme.get("apron_tint", Color.WHITE) as Color,
		float(theme.get("apron_uv", 0.2)), 0.12, 0.04,
		float(theme.get("apron_roughness", 0.5)))


## Surface of the dirt strip: the one piece of the layout that changes look and
## grip with the theme.
static func dirt_material(theme: Dictionary) -> Material:
	var files: Array = _string_list(theme.get("dirt", []))
	return _pbr_material(files, theme.get("dirt_tint", Color(0.6, 0.5, 0.35)),
		float(theme.get("dirt_uv", 0.22)), 0.14, 0.05,
		float(theme.get("dirt_roughness", 0.92)))


## Flat painted colour of the skidpad.
static func skid_material(theme: Dictionary) -> Material:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = theme.get("skid_tint", Color(0.32, 0.34, 0.36)) as Color
	mat.roughness = 0.82
	mat.metallic = 0.0
	return mat


## The present meshes for a theme, in cycle order.
static func present_meshes(theme: Dictionary) -> Array[Mesh]:
	match str(theme.get("present_kind", "parcel")):
		"basket":
			return _basket_meshes()
		"gift":
			return _gift_meshes()
	return _parcel_meshes()


## One shared vertex-coloured material for every present.
static func present_material(theme: Dictionary) -> Material:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.metallic = 0.0
	mat.roughness = 0.42 if str(theme.get("present_kind", "parcel")) == "gift" else 0.72
	# A soft self-glow keeps a present readable against snow and asphalt alike.
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.86, 0.52)
	mat.emission_energy_multiplier = 0.16
	return mat


## Warm gold used by the pickup ring and the pad spotlights.
static func accent() -> Color:
	return Color(1.0, 0.82, 0.28)


# --------------------------------------------------------------------------
# scenery

## Builds every solid piece of arena dressing under `root` and returns the grip
## hazard zones: [{centre: Vector3, radius: float, grip: float, spin: float}].
##
## `arena` carries the layout the theme must dress around:
##   half        - half the playfield width (the wall sits here)
##   loop_centre - centre of the handling loop
##   loop_extent - half extents of the loop in x/z
##   base_pads   - the two base centres
static func build_scenery(root: Node3D, theme: Dictionary, arena: Dictionary,
		stats: Dictionary) -> Array[Dictionary]:
	var hazards: Array[Dictionary] = []
	if root == null:
		return hazards
	var half: float = float(arena.get("half", 56.0))
	_scatter_nature(root, theme, half, stats)
	_build_yard(root, theme, half, stats)
	hazards = _build_hazards(root, theme, arena)
	return hazards


# --------------------------------------------------------------------------
# materials


static func _pbr_material(files: Array, tint: Color, uv_scale: float,
		detail: float, macro: float, roughness_min: float) -> Material:
	if files.size() < 3 or not ResourceLoader.exists(PBR_SHADER):
		return _flat_material(tint, maxf(roughness_min, 0.6))
	var diffuse: Texture2D = _texture(str(files[0]))
	var normal: Texture2D = _texture(str(files[1]))
	var rough: Texture2D = _texture(str(files[2]))
	if diffuse == null or normal == null or rough == null:
		return _flat_material(tint, maxf(roughness_min, 0.6))
	var mat := ShaderMaterial.new()
	mat.shader = load(PBR_SHADER) as Shader
	mat.set_shader_parameter("albedo_tex", diffuse)
	mat.set_shader_parameter("normal_tex", normal)
	mat.set_shader_parameter("rough_tex", rough)
	mat.set_shader_parameter("uv_scale", uv_scale)
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("detail_strength", detail)
	mat.set_shader_parameter("macro_variation", macro)
	mat.set_shader_parameter("roughness_min", roughness_min)
	return mat


static func _flat_material(tint: Color, roughness: float) -> Material:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.roughness = clampf(roughness, 0.2, 1.0)
	mat.metallic = 0.0
	return mat


static func _texture(name_without_extension: String) -> Texture2D:
	var path: String = PBR_TEX + name_without_extension + ".jpg"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func _string_list(raw: Variant) -> Array:
	var out: Array = []
	if raw is Array:
		for entry: Variant in raw as Array:
			out.append(str(entry))
	return out


# --------------------------------------------------------------------------
# nature ring beyond the wall

## One entry per baked model. `solid` pieces get a collider on the WORLD layer
## so nothing outside the fence is drive-through decoration either.
const NATURE_SPECS: Array[Dictionary] = [
	{"model": "tree_pineTallA", "count": 84, "min_scale": 1.30,
		"max_scale": 2.30, "solid": "trunk", "radius": 0.55, "height": 5.4},
	{"model": "plant_bushLarge", "count": 46, "min_scale": 1.10,
		"max_scale": 2.10, "solid": "none", "radius": 0.6, "height": 1.6},
	{"model": "rock_largeA", "count": 26, "min_scale": 1.00,
		"max_scale": 2.20, "solid": "box", "radius": 1.0, "height": 1.2},
	{"model": "rock_smallA", "count": 26, "min_scale": 0.90,
		"max_scale": 1.80, "solid": "box", "radius": 0.5, "height": 0.5},
	{"model": "stump_round", "count": 12, "min_scale": 1.00,
		"max_scale": 1.60, "solid": "trunk", "radius": 0.5, "height": 0.8},
	{"model": "log", "count": 8, "min_scale": 1.10,
		"max_scale": 1.90, "solid": "box", "radius": 0.8, "height": 0.7},
	{"model": "grass_large", "count": 70, "min_scale": 0.90,
		"max_scale": 1.80, "solid": "none", "radius": 0.4, "height": 0.6},
]


static func _scatter_nature(root: Node3D, theme: Dictionary, half: float,
		stats: Dictionary) -> void:
	## Trees, rocks and grass in a wide ring outside the wall. The ring starts
	## 7 m behind the fence, so every prop is visible from the cockpit but none
	## of it can ever be driven into - and each solid piece still carries a
	## collider, because a fence is not an excuse for drive-through scenery.
	var material: StandardMaterial3D = FoliageBaker.make_material()
	var solid := _solid_root(root, "NatureCollision")
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210 + int(half)
	var inner: float = half + 7.0
	var outer: float = half + 40.0
	var foliage: Color = theme.get("foliage_tint", Color(0.9, 1.0, 0.9)) as Color
	var bark: Color = theme.get("bark_tint", Color(1.0, 0.95, 0.88)) as Color
	for spec: Dictionary in NATURE_SPECS:
		var model: String = str(spec["model"])
		var mesh: ArrayMesh = FoliageBaker.bake(model)
		if mesh == null:
			continue
		var bounds: AABB = mesh.get_aabb()
		var sink: float = bounds.position.y
		var transforms: Array = []
		var colours: Array = []
		var is_tree: bool = model.begins_with("tree") or model.begins_with("plant")
		var count: int = int(spec["count"])
		for i in count:
			var spot: Vector2 = _ring_point(rng, inner, outer, half)
			var scale: float = rng.randf_range(float(spec["min_scale"]),
				float(spec["max_scale"]))
			var basis: Basis = Basis(Vector3.UP, rng.randf() * TAU) \
				.scaled(Vector3.ONE * scale)
			var position := Vector3(spot.x, -sink * scale - 0.05, spot.y)
			transforms.append(Transform3D(basis, position))
			var tint: Color = foliage if is_tree else bark
			var shade: float = rng.randf_range(0.82, 1.08)
			colours.append(Color(tint.r * shade, tint.g * shade,
				tint.b * shade))
			_add_nature_collider(solid, spec, Vector3(spot.x, 0.0, spot.y),
				scale)
		if transforms.is_empty():
			continue
		var instance: MultiMeshInstance3D = FoliageBaker.create_instances(
			mesh, material, transforms, false, colours)
		instance.name = "Nature_" + model
		SceneryKit.set_view(instance, 0.0, 320.0)
		root.add_child(instance)
		SceneryKit.bump(stats, "objects", transforms.size())
		SceneryKit.bump(stats, "draw_calls")
	SceneryKit.bump(stats, "solid_bodies")


static func _ring_point(rng: RandomNumberGenerator, inner: float,
		outer: float, half: float) -> Vector2:
	## Rejection-sample a square ring so the tree line is even on all four
	## sides instead of bunching at the corners.
	var limit: float = outer
	for _attempt in 8:
		var point := Vector2(rng.randf_range(-limit, limit),
			rng.randf_range(-limit, limit))
		if absf(point.x) < inner and absf(point.y) < inner:
			continue
		if absf(point.x) > limit or absf(point.y) > limit:
			continue
		return point
	var angle: float = rng.randf() * TAU
	var radius: float = rng.randf_range(inner, outer)
	return Vector2(cos(angle) * radius, sin(angle) * radius) \
		.clamp(Vector2(-outer, -outer), Vector2(outer, outer))


static func _add_nature_collider(body: StaticBody3D, spec: Dictionary,
		position: Vector3, scale: float) -> void:
	var kind: String = str(spec.get("solid", "none"))
	if kind == "none":
		return
	var radius: float = float(spec.get("radius", 0.5)) * scale
	var height: float = float(spec.get("height", 1.0)) * scale
	var collision := CollisionShape3D.new()
	if kind == "trunk":
		var shape := CylinderShape3D.new()
		shape.radius = maxf(radius, 0.2)
		shape.height = maxf(height, 0.6)
		collision.shape = shape
		collision.position = position + Vector3.UP * (shape.height * 0.5)
	else:
		var shape := BoxShape3D.new()
		shape.size = Vector3(radius * 2.0, maxf(height, 0.4), radius * 2.0)
		collision.shape = shape
		collision.position = position + Vector3.UP * (shape.size.y * 0.5)
	body.add_child(collision)


# --------------------------------------------------------------------------
# yard dressing inside the wall

static func _build_yard(root: Node3D, theme: Dictionary, half: float,
		stats: Dictionary) -> void:
	var body := _solid_root(root, "YardProps")
	match str(theme.get("yard", "containers")):
		"bales":
			_build_bales(root, body, half, stats)
		"gifts":
			_build_gift_piles(root, body, half, stats)
		_:
			_build_containers(root, body, half, stats)


static func _build_containers(root: Node3D, body: StaticBody3D, half: float,
		stats: Dictionary) -> void:
	## Two rows of shipping containers stacked against the side walls. They sit
	## 3.5 m inside the fence, behind the dirt strip and the jump lane, so the
	## playfield stays open while the horizon reads as a working dock.
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var transforms: Array = []
	var colours: Array = []
	var paints: Array[Color] = [
		Color(0.16, 0.42, 0.50), Color(0.56, 0.22, 0.18),
		Color(0.20, 0.32, 0.54), Color(0.30, 0.34, 0.36),
		Color(0.62, 0.38, 0.14), Color(0.18, 0.45, 0.38),
	]
	var side: float = half - 3.5
	for wall: float in [-1.0, 1.0]:
		for i in 6:
			var z: float = -30.0 + float(i) * 12.0
			var yaw: float = PI * 0.5
			var size := Vector3(11.0, 2.7, 4.4)
			var position := Vector3(wall * side, size.y * 0.5, z)
			transforms.append(Transform3D(Basis(Vector3.UP, yaw).scaled(size),
				position))
			colours.append(paints[(i + (1 if wall > 0.0 else 0)) % paints.size()])
			_add_box_collider(body, Transform3D(Basis(Vector3.UP, yaw), position),
				size)
		for i in 4:
			var x: float = -34.0 + float(i) * 22.0
			if absf(x) < 14.0:
				continue
			var size := Vector3(10.0, 2.7, 4.4)
			var position := Vector3(x, size.y * 0.5, wall * side)
			transforms.append(Transform3D(Basis.IDENTITY.scaled(size), position))
			colours.append(paints[(i + 2) % paints.size()])
			_add_box_collider(body, Transform3D(Basis.IDENTITY, position), size)
	if transforms.is_empty():
		return
	var instance := SceneryKit.multimesh(mesh,
		SceneryKit.instance_material(0.82), transforms, "ShippingContainers",
		false, colours)
	SceneryKit.set_view(instance, 0.0, 260.0)
	root.add_child(instance)
	SceneryKit.bump(stats, "objects", transforms.size())
	SceneryKit.bump(stats, "draw_calls")


static func _build_bales(root: Node3D, body: StaticBody3D, half: float,
		stats: Dictionary) -> void:
	## Round hay bales along the fence, with a few square bales stacked behind.
	var bale := CylinderMesh.new()
	bale.top_radius = 0.85
	bale.bottom_radius = 0.85
	bale.height = 1.55
	bale.radial_segments = 12
	bale.rings = 1
	var transforms: Array = []
	var colours: Array = []
	var side: float = half - 4.0
	var lying := Basis(Vector3(0.0, 0.0, 1.0), PI * 0.5)
	for wall: float in [-1.0, 1.0]:
		for i in 8:
			var z: float = -32.0 + float(i) * 9.0
			var position := Vector3(wall * side, 0.85, z)
			var yaw: float = 0.0 if i % 2 == 0 else PI * 0.5
			transforms.append(Transform3D(Basis(Vector3.UP, yaw) * lying,
				position))
			colours.append(Color(0.84, 0.73, 0.38) if i % 3 != 0
				else Color(0.72, 0.60, 0.28))
			_add_box_collider(body, Transform3D(Basis(Vector3.UP, yaw), position),
				Vector3(1.8, 1.7, 1.8))
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var stacks: Array = []
	var stack_colours: Array = []
	for wall: float in [-1.0, 1.0]:
		for i in 4:
			var x: float = -30.0 + float(i) * 20.0
			if absf(x) < 14.0:
				continue
			var size := Vector3(2.4, 1.25, 1.7)
			var base := Vector3(x, 0.0, wall * (half - 3.6))
			stacks.append(Transform3D(Basis.IDENTITY.scaled(size),
				base + Vector3.UP * (size.y * 0.5)))
			stacks.append(Transform3D(
				Basis(Vector3.UP, 0.16).scaled(size),
				base + Vector3.UP * (size.y * 1.5 + 0.02)))
			stack_colours.append(Color(0.78, 0.66, 0.32))
			stack_colours.append(Color(0.86, 0.74, 0.38))
			_add_box_collider(body, Transform3D(Basis.IDENTITY,
				base + Vector3.UP * (size.y * 0.5)), size)
			_add_box_collider(body, Transform3D(Basis.IDENTITY,
				base + Vector3.UP * (size.y * 1.5 + 0.02)), size)
	if not transforms.is_empty():
		var hay := SceneryKit.multimesh(bale,
			SceneryKit.instance_material(0.98), transforms, "RoundBales",
			false, colours)
		SceneryKit.set_view(hay, 0.0, 240.0)
		root.add_child(hay)
		SceneryKit.bump(stats, "objects", transforms.size())
		SceneryKit.bump(stats, "draw_calls")
	if not stacks.is_empty():
		var crates := SceneryKit.multimesh(box,
			SceneryKit.instance_material(0.95), stacks, "SquareBales",
			false, stack_colours)
		SceneryKit.set_view(crates, 0.0, 240.0)
		root.add_child(crates)
		SceneryKit.bump(stats, "objects", stacks.size())
		SceneryKit.bump(stats, "draw_calls")


static func _build_gift_piles(root: Node3D, body: StaticBody3D, half: float,
		stats: Dictionary) -> void:
	## Wrapped gift piles waiting for the race, stacked against the fence.
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var transforms: Array = []
	var colours: Array = []
	var wrappers: Array[Color] = [
		Color(0.86, 0.20, 0.24), Color(0.20, 0.48, 0.84),
		Color(0.22, 0.62, 0.38), Color(0.88, 0.62, 0.18),
		Color(0.62, 0.28, 0.72),
	]
	var side: float = half - 4.0
	var index: int = 0
	for wall: float in [-1.0, 1.0]:
		for i in 7:
			var z: float = -30.0 + float(i) * 10.0
			var base := Vector3(wall * side, 0.0, z)
			var size := Vector3(2.0, 1.35, 1.8) if i % 2 == 0 \
				else Vector3(1.5, 1.6, 1.5)
			var yaw: float = float(i) * 0.4
			transforms.append(Transform3D(Basis(Vector3.UP, yaw).scaled(size),
				base + Vector3.UP * (size.y * 0.5)))
			colours.append(wrappers[index % wrappers.size()])
			_add_box_collider(body, Transform3D(Basis(Vector3.UP, yaw),
				base + Vector3.UP * (size.y * 0.5)), size)
			index += 1
			if i % 2 == 0:
				var top := Vector3(1.2, 0.95, 1.1)
				transforms.append(Transform3D(
					Basis(Vector3.UP, yaw + 0.5).scaled(top),
					base + Vector3.UP * (size.y + top.y * 0.5)))
				colours.append(wrappers[index % wrappers.size()])
				_add_box_collider(body, Transform3D(Basis(Vector3.UP, yaw + 0.5),
					base + Vector3.UP * (size.y + top.y * 0.5)), top)
				index += 1
	if transforms.is_empty():
		return
	var instance := SceneryKit.multimesh(mesh,
		SceneryKit.instance_material(0.90), transforms, "GiftPiles",
		false, colours)
	SceneryKit.set_view(instance, 0.0, 240.0)
	root.add_child(instance)
	SceneryKit.bump(stats, "objects", transforms.size())
	SceneryKit.bump(stats, "draw_calls")


# --------------------------------------------------------------------------
# grip hazards

static func _build_hazards(root: Node3D, theme: Dictionary,
		arena: Dictionary) -> Array[Dictionary]:
	## Visible floor markings that change grip. They carry no collider: a wet
	## patch is not a prop, and a kart must be able to drive through it.
	var hazards: Array[Dictionary] = []
	var data: Dictionary = theme.get("hazard", {}) as Dictionary
	if data.is_empty():
		return hazards
	var centre: Vector3 = arena.get("loop_centre", Vector3.ZERO) as Vector3
	var radius: float = 5.4
	var grip: float = float(data.get("grip", 0.8))
	var spin: float = float(data.get("spin", 0.0))
	var tint: Color = data.get("tint", Color(0.4, 0.5, 0.6)) as Color
	var kind: String = str(data.get("kind", "wet"))
	var spots: Array = data.get("spots", []) as Array
	for raw: Variant in spots:
		if not (raw is Vector2):
			continue
		var offset: Vector2 = raw as Vector2
		var spot := Vector3(centre.x + offset.x, 0.0, centre.z + offset.y)
		_add_hazard_disc(root, spot, radius, tint, kind)
		hazards.append({
			"centre": spot,
			"radius": radius,
			"grip": grip,
			"spin": spin,
		})
	return hazards


static func _add_hazard_disc(root: Node3D, centre: Vector3, radius: float,
		tint: Color, kind: String) -> void:
	var rim := MeshInstance3D.new()
	rim.name = "HazardRim"
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.04
	disc.radial_segments = 28
	disc.rings = 1
	rim.mesh = disc
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint.darkened(0.18)
	mat.roughness = 0.08 if kind == "ice" else 0.35
	mat.metallic = 0.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.72
	if kind == "ice":
		mat.emission_enabled = true
		mat.emission = Color(0.16, 0.36, 0.50)
		mat.emission_energy_multiplier = 0.20
	rim.material_override = mat
	rim.position = centre + Vector3.UP * 0.035
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(rim)

	var sheen := MeshInstance3D.new()
	sheen.name = "HazardSheen"
	var inner := CylinderMesh.new()
	inner.top_radius = radius * 0.72
	inner.bottom_radius = radius * 0.72
	inner.height = 0.04
	inner.radial_segments = 24
	inner.rings = 1
	sheen.mesh = inner
	var sheen_mat := StandardMaterial3D.new()
	sheen_mat.albedo_color = Color(tint.r + 0.22, tint.g + 0.22, tint.b + 0.22,
		0.42)
	sheen_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sheen_mat.roughness = 0.06
	sheen_mat.metallic = 0.0
	sheen.material_override = sheen_mat
	sheen.position = centre + Vector3.UP * 0.06
	sheen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(sheen)


# --------------------------------------------------------------------------
# present meshes

static func _parcel_meshes() -> Array[Mesh]:
	## Shrink-wrapped parcel with two cross straps and a fragile label.
	var meshes: Array[Mesh] = []
	var kraft: Array[Color] = [Color(0.74, 0.58, 0.38), Color(0.66, 0.50, 0.32)]
	var tape: Array[Color] = [Color(0.94, 0.86, 0.56), Color(0.82, 0.30, 0.24)]
	for i in 2:
		var batch := PropBatch.new()
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3.ZERO),
			PRESENT_EXTENTS, kraft[i])
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3.ZERO),
			Vector3(0.16, PRESENT_EXTENTS.y + 0.03, PRESENT_EXTENTS.z + 0.03),
			tape[i])
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3.ZERO),
			Vector3(PRESENT_EXTENTS.x + 0.03, PRESENT_EXTENTS.y + 0.03, 0.16),
			tape[i])
		batch.add_box(Transform3D(Basis.IDENTITY,
			Vector3(0.0, 0.02, PRESENT_EXTENTS.z * 0.5 + 0.01)),
			Vector3(0.46, 0.26, 0.03), Color(0.95, 0.93, 0.86))
		meshes.append(batch.build())
	return meshes


static func _basket_meshes() -> Array[Mesh]:
	## Wicker basket with produce on top and a cloth band.
	var meshes: Array[Mesh] = []
	var wicker: Array[Color] = [Color(0.66, 0.46, 0.24), Color(0.58, 0.40, 0.20)]
	var produce: Array[Color] = [Color(0.30, 0.58, 0.22), Color(0.88, 0.44, 0.18)]
	for i in 2:
		var batch := PropBatch.new()
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3.ZERO),
			Vector3(PRESENT_EXTENTS.x, 0.50, PRESENT_EXTENTS.z), wicker[i])
		for side: float in [-1.0, 1.0]:
			batch.add_box(Transform3D(Basis.IDENTITY,
				Vector3(side * (PRESENT_EXTENTS.x * 0.5 - 0.03),
					0.10, 0.0)),
				Vector3(0.08, 0.46, PRESENT_EXTENTS.z + 0.02),
				wicker[i].darkened(0.14))
		# Three produce cylinders poking over the rim.
		for k in 3:
			var angle: float = TAU * float(k) / 3.0 + float(i) * 0.5
			batch.add_cylinder(Transform3D(Basis.IDENTITY,
				Vector3(cos(angle) * 0.22, 0.32, sin(angle) * 0.22)),
				0.16, 0.22, 8, produce[(k + i) % produce.size()])
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.12, 0.0)),
			Vector3(PRESENT_EXTENTS.x + 0.02, 0.10,
				PRESENT_EXTENTS.z + 0.02), Color(0.92, 0.84, 0.60))
		meshes.append(batch.build())
	return meshes


static func _gift_meshes() -> Array[Mesh]:
	## Wrapped gift box with a ribbon cross and a two-loop bow.
	var meshes: Array[Mesh] = []
	var paper: Array[Color] = [Color(0.84, 0.20, 0.24), Color(0.20, 0.46, 0.82),
		Color(0.24, 0.60, 0.36)]
	var ribbon: Array[Color] = [Color(0.98, 0.90, 0.42),
		Color(0.98, 0.90, 0.42), Color(0.94, 0.44, 0.56)]
	for i in 3:
		var batch := PropBatch.new()
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3.ZERO),
			PRESENT_EXTENTS, paper[i])
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3.ZERO),
			Vector3(0.18, PRESENT_EXTENTS.y + 0.02, PRESENT_EXTENTS.z + 0.02),
			ribbon[i])
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3.ZERO),
			Vector3(PRESENT_EXTENTS.x + 0.02, 0.18, PRESENT_EXTENTS.z + 0.02),
			ribbon[i])
		for side: float in [-1.0, 1.0]:
			batch.add_box(Transform3D(Basis(Vector3.UP, side * 0.5),
				Vector3(side * 0.15, PRESENT_EXTENTS.y * 0.5 + 0.09, 0.0)),
				Vector3(0.30, 0.13, 0.18), ribbon[i].darkened(0.10))
		meshes.append(batch.build())
	return meshes


# --------------------------------------------------------------------------
# helpers


static func _solid_root(root: Node3D, node_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = 0
	root.add_child(body)
	return body


static func _add_box_collider(body: StaticBody3D, xform: Transform3D,
		size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = xform
	body.add_child(collision)
