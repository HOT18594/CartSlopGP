extends RefCounted
## The three CARGO RUSH cartoon arena skins, chosen by theme id.
##
## A skin owns the palette, the grip rule and the flat ground markings of the
## arena. The footprint, the bases, the barrier ring, the prop layout and every
## rule are identical for every theme, so a skin can never change the game - only
## how it looks and how much grip a kart gets.
##
## Art is the CC0 Kenney kits only: racing kit barriers / stands / lights /
## flags, nature kit trees and rocks, car kit crate. The GLBs ship without
## collision, so every solid piece placed here gets a real WORLD collider built
## from its measured AABB. There are no photographic textures anywhere: floors
## and paint are flat colours, and the Kenney GLBs keep their own flat materials.
##
## Present art is a Kenney crate with a flat ribbon and bow. A present is a
## pickup, never a solid prop, so it carries no body at all.

const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")
const SceneryKit := preload("res://scripts/minigames/scenery/scenery_kit.gd")
const PropBatch := preload("res://scripts/minigames/scenery/prop_batch.gd")

const RACING_ROOT: String = "res://assets/models/kenney_racing_kit/Models/GLTF format/"
const NATURE_ROOT: String = "res://assets/models/kenney_nature_kit/Models/GLTF format/"
const CAR_ROOT: String = "res://assets/models/kenney_car-kit/Models/GLB format/"
const CRATE_MODEL: String = "box"

const DEFAULT_ID: String = "dockyard"
const THEME_IDS: PackedStringArray = ["dockyard", "farmyard", "snowfield"]

## Ice: very low lateral grip plus the arena's own spin wobble.
const ICE_GRIP: float = 0.34
const ICE_SPIN: float = 2.4
## Soft mud: a noticeable slide without the spin.
const MUD_GRIP: float = 0.72
## Wet paint: the dockyard's only real drop.
const WET_GRIP: float = 0.84

## Present art. Pickups never block a kart.
const CRATE_SCALE: float = 1.8
const HAZARD_RADIUS: float = 5.4

## Nature scale, matching the 16 m arena lattice.
const TREE_SCALE: float = 7.2
const BUSH_SCALE: float = 4.8
const ROCK_SCALE: float = 5.2

## Ambient wind for the arena dressing: a skin sets how hard the flags and
## banner towers sway. It is presentation only and never touches a rule.
const WIND_DEFAULT: float = 1.0

## Same layout for every skin: a 16 m lattice ring outside the barrier.
const TREE_RING: Array[Vector2] = [
	Vector2(-80.0, -80.0), Vector2(80.0, -80.0),
	Vector2(-80.0, 80.0), Vector2(80.0, 80.0),
	Vector2(-80.0, -48.0), Vector2(80.0, -48.0),
	Vector2(-80.0, 16.0), Vector2(80.0, 16.0),
	Vector2(-80.0, 48.0), Vector2(80.0, 48.0),
	Vector2(-64.0, -80.0), Vector2(-32.0, -80.0), Vector2(0.0, -80.0),
	Vector2(32.0, -80.0), Vector2(64.0, -80.0),
	Vector2(-64.0, 80.0), Vector2(-32.0, 80.0), Vector2(0.0, 80.0),
	Vector2(32.0, 80.0), Vector2(64.0, 80.0),
]
const BUSH_SPOTS: Array[Vector2] = [
	Vector2(-64.0, -32.0), Vector2(64.0, -32.0),
	Vector2(-64.0, 32.0), Vector2(64.0, 32.0),
	Vector2(-32.0, -64.0), Vector2(32.0, -64.0),
	Vector2(-32.0, 64.0), Vector2(32.0, 64.0),
]
const ROCK_SPOTS: Array[Vector2] = [
	Vector2(-64.0, -48.0), Vector2(64.0, -48.0),
	Vector2(-64.0, 48.0), Vector2(64.0, 48.0),
	Vector2(-48.0, -64.0), Vector2(48.0, -64.0),
	Vector2(-48.0, 64.0), Vector2(48.0, 64.0),
]

const THEMES: Dictionary = {
	"dockyard": {
		"id": "dockyard",
		"name": "DOCKYARD",
		"blurb": "WET PAINT",
		"teams": ["DOCK CREW", "HARBOUR RATS"],
		"sky_top": Color(0.16, 0.47, 0.70),
		"sky_horizon": Color(0.72, 0.85, 0.92),
		"ground_bottom": Color(0.15, 0.24, 0.29),
		"fog_color": Color(0.70, 0.82, 0.89),
		"fog_density": 0.0026,
		"ground": Color("3d6b7c"),
		"ground_alt": Color("46788a"),
		"paint": Color("f5ecd7"),
		"paint_alt": Color("e8c34a"),
		"grip": 0.94,
		"present_kind": "crate",
		"present_label": "SHRINK-WRAPPED CRATES",
		"present_accent": Color("f4c542"),
		"wind": 1.15,
		"hazard_label": "WET PATCHES  ·  LIGHT SLIDE",
		"tree_model": "tree_default",
		"tree_scale": 1.0,
		"hazard": {"kind": "wet", "grip": WET_GRIP, "spin": 0.0,
			"tint": Color(0.30, 0.50, 0.60), "spots": [
				Vector2(16.0, 32.0), Vector2(-16.0, -32.0)]},
	},
	"farmyard": {
		"id": "farmyard",
		"name": "FARMYARD",
		"blurb": "SOFT MUD",
		"teams": ["PADDOCK POSSE", "BARN RAIDERS"],
		"sky_top": Color(0.23, 0.55, 0.78),
		"sky_horizon": Color(0.85, 0.89, 0.76),
		"ground_bottom": Color(0.32, 0.27, 0.16),
		"fog_color": Color(0.84, 0.86, 0.72),
		"fog_density": 0.0018,
		"ground": Color("6f9a4a"),
		"ground_alt": Color("7ca855"),
		"paint": Color("f5ecd7"),
		"paint_alt": Color("f2b134"),
		"grip": 0.86,
		"present_kind": "crate",
		"present_label": "PRODUCE CRATES",
		"present_accent": Color("e4572e"),
		"wind": 0.72,
		"hazard_label": "MUD PATCHES  ·  SOFT SLIDE",
		"tree_model": "tree_oak",
		"tree_scale": 0.95,
		"hazard": {"kind": "mud", "grip": MUD_GRIP, "spin": 0.0,
			"tint": Color(0.44, 0.34, 0.20), "spots": [
				Vector2(16.0, 32.0), Vector2(-16.0, -32.0)]},
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
		"ground": Color("dfeef5"),
		"ground_alt": Color("c9e2ee"),
		"paint": Color("f7fbff"),
		"paint_alt": Color("2e86ab"),
		"grip": 0.90,
		"present_kind": "gift",
		"present_label": "WRAPPED GIFTS",
		"present_accent": Color("e23b4e"),
		"wind": 1.5,
		"hazard_label": "ICE PATCHES  ·  SPIN OUT",
		"tree_model": "tree_pineTallA",
		"tree_scale": 1.0,
		"hazard": {"kind": "ice", "grip": ICE_GRIP, "spin": ICE_SPIN,
			"tint": Color(0.36, 0.58, 0.74), "spots": [
				Vector2(16.0, 32.0), Vector2(-16.0, -32.0)]},
	},
}

static var _model_cache: Dictionary = {}
static var _paint_cache: Dictionary = {}


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


# --------------------------------------------------------------------------
# materials
#
# Floors and paint are flat StandardMaterial3D colours. Nothing here loads a
# photographic texture, which is what keeps the cartoon read consistent.

## Flat ground material for the arena floor.
static func floor_material(theme: Dictionary) -> Material:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = theme.get("ground", Color("3d6b7c")) as Color
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return mat


## Flat inner apron; the arena paints its own checkerboard over it, so this is
## only a fallback for callers that want a solid slab.
static func apron_material(theme: Dictionary) -> Material:
	return flat_material(theme.get("ground_alt", Color("46788a")) as Color)


## Flat colour of the dirt/yard strip. Kept for API compatibility.
static func dirt_material(theme: Dictionary) -> Material:
	return flat_material((theme.get("hazard", {}) as Dictionary)
		.get("tint", Color("6b4a2a")) as Color)


## Flat painted colour of the skidpad. Kept for API compatibility.
static func skid_material(theme: Dictionary) -> Material:
	return flat_material(theme.get("ground_alt", Color("c9e2ee")) as Color)


## One shared flat material per colour, so paint does not make a material per
## quad and every floor marking stays unlit and bold.
static func flat_material(colour: Color, unshaded: bool = true) -> StandardMaterial3D:
	var key: String = "%s/%s" % [colour.to_html(), str(unshaded)]
	if _paint_cache.has(key):
		return _paint_cache[key] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_paint_cache[key] = mat
	return mat


## The present meshes for a theme, in cycle order. Legacy accessor: the live
## mode instantiates the Kenney crate directly through build_present().
static func present_meshes(_theme: Dictionary) -> Array[Mesh]:
	var meshes: Array[Mesh] = []
	var info: Dictionary = model_info(CRATE_MODEL)
	if not bool(info.get("ok", false)):
		return meshes
	for part: Dictionary in info.get("parts", []) as Array:
		var mesh: Mesh = part.get("mesh") as Mesh
		if mesh != null:
			meshes.append(mesh)
	return meshes


## Legacy material accessor. The crate keeps its own Kenney texture.
static func present_material(_theme: Dictionary) -> Material:
	return flat_material(Color.WHITE)


## Warm gold used by the pickup ring and the pad spotlights.
static func accent() -> Color:
	return Color(1.0, 0.82, 0.28)


## The pickup ring colour: the present accent, brightened so it reads on grass,
## wet concrete and snow alike.
static func pickup_colour(theme: Dictionary) -> Color:
	var base: Color = theme.get("present_accent", accent()) as Color
	return base.lightened(0.22)


## The carrier glow/trail colour. Team colour is layered on by the arena; this
## is the neutral fallback for a carrier with no resolvable team.
static func carry_colour(theme: Dictionary) -> Color:
	return theme.get("present_accent", accent()) as Color


## How hard this skin's dressing sways. Presentation only.
static func wind(theme: Dictionary) -> float:
	return clampf(float(theme.get("wind", WIND_DEFAULT)), 0.0, 4.0)


# --------------------------------------------------------------------------
# present art

## Adds one Kenney crate plus a flat ribbon and bow under `root`.
static func build_present(root: Node3D, theme: Dictionary, index: int) -> void:
	if root == null:
		return
	var crate: Node3D = place_model(root, CRATE_MODEL, Vector3.ZERO,
		float(index) * 0.7, Vector3.ONE * CRATE_SCALE, "Crate")
	if crate == null:
		return
	var accent_colour: Color = theme.get("present_accent", accent()) as Color
	var batch := PropBatch.new()
	var height: float = CRATE_SCALE * 0.715
	var span: float = CRATE_SCALE * 0.715 + 0.06
	batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, height * 0.5, 0.0)),
		Vector3(0.17, height, span), accent_colour)
	batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, height * 0.5, 0.0)),
		Vector3(span, height, 0.17), accent_colour)
	batch.add_box(Transform3D(Basis(Vector3.UP, 0.0),
		Vector3(0.0, height + 0.05, 0.0)), Vector3(span * 0.9, 0.12, 0.14),
		accent_colour.darkened(0.12))
	for side: float in [-1.0, 1.0]:
		batch.add_box(Transform3D(Basis(Vector3.BACK, side * 0.42),
			Vector3(side * 0.18, height + 0.15, 0.0)),
			Vector3(0.34, 0.13, 0.20), accent_colour)
	var ribbon := MeshInstance3D.new()
	ribbon.name = "Ribbon"
	ribbon.mesh = batch.build()
	ribbon.material_override = SceneryKit.vertex_material()
	ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ribbon)


# --------------------------------------------------------------------------
# scenery

## Builds every solid piece of arena dressing under `root` and returns the grip
## hazard zones: [{centre: Vector3, radius: float, grip: float, spin: float}].
##
## `arena` carries the layout the theme must dress around:
##   half        - half the playfield width (the barrier sits here)
##   base_pads   - the two base centres
static func build_scenery(root: Node3D, theme: Dictionary, arena: Dictionary,
		stats: Dictionary) -> Array[Dictionary]:
	var hazards: Array[Dictionary] = []
	if root == null:
		return hazards
	var half: float = float(arena.get("half", 56.0))
	_scatter_nature(root, theme, half, stats)
	hazards = _build_hazards(root, theme)
	return hazards


static func _scatter_nature(root: Node3D, theme: Dictionary, half: float,
		stats: Dictionary) -> void:
	## Trees, bushes and rocks on a 16 m ring outside the barrier. The ring is
	## the same for every skin; only the tree species follows the palette.
	## Every trunk and rock carries a WORLD collider.
	var tree_model: String = str(theme.get("tree_model", "tree_default"))
	var tree_scale: float = float(theme.get("tree_scale", 1.0)) * TREE_SCALE
	var tree_transforms: Array = []
	for index in TREE_RING.size():
		var spot: Vector2 = TREE_RING[index]
		if absf(spot.x) < half + 4.0 and absf(spot.y) < half + 4.0:
			continue
		var scale: float = tree_scale * (0.86
			+ 0.28 * fposmod(float(index) * 0.61803398875, 1.0))
		tree_transforms.append(fit_transform(tree_model,
			Vector3(spot.x, 0.0, spot.y), float(index) * 1.7,
			Vector3.ONE * scale, true))
		var tree_size: Vector3 = scaled_size(tree_model, Vector3.ONE * scale,
			true)
		add_cylinder_collider(_nature_body(root), Vector3(spot.x, 0.0, spot.y),
			0.12 * scale, maxf(tree_size.y, 1.0))
	SceneryKit.bump(stats, "objects", tree_transforms.size())
	SceneryKit.bump(stats, "draw_calls")
	batch_model(root, tree_model, tree_transforms, "TreeRing", true, true)
	if not _model_exists(tree_model, true):
		push_warning("CargoTheme: missing tree model " + tree_model)

	var bush_transforms: Array = []
	for index in BUSH_SPOTS.size():
		var spot: Vector2 = BUSH_SPOTS[index]
		var scale: float = BUSH_SCALE * (0.9
			+ 0.2 * fposmod(float(index) * 0.41421356237, 1.0))
		bush_transforms.append(fit_transform("plant_bushLarge",
			Vector3(spot.x, 0.0, spot.y), float(index) * 2.3,
			Vector3.ONE * scale, true))
	SceneryKit.bump(stats, "objects", bush_transforms.size())
	SceneryKit.bump(stats, "draw_calls")
	batch_model(root, "plant_bushLarge", bush_transforms, "Bushes", true, true)

	var rock_transforms: Array = []
	for index in ROCK_SPOTS.size():
		var spot: Vector2 = ROCK_SPOTS[index]
		var scale: float = ROCK_SCALE * (0.9
			+ 0.2 * fposmod(float(index) * 0.73205080756, 1.0))
		rock_transforms.append(fit_transform("rock_largeA",
			Vector3(spot.x, 0.0, spot.y), float(index) * 1.1,
			Vector3.ONE * scale, true))
		var rock_size: Vector3 = scaled_size("rock_largeA",
			Vector3.ONE * scale, true)
		add_box_collider(_nature_body(root),
			Transform3D(Basis(Vector3.UP, float(index) * 1.1),
				Vector3(spot.x, 0.0, spot.y)
					+ Vector3.UP * (rock_size.y * 0.5)),
			Vector3(maxf(rock_size.x, 0.4), maxf(rock_size.y, 0.4),
				maxf(rock_size.z, 0.4)))
	SceneryKit.bump(stats, "objects", rock_transforms.size())
	SceneryKit.bump(stats, "draw_calls")
	batch_model(root, "rock_largeA", rock_transforms, "Rocks", true, true)
	SceneryKit.bump(stats, "solid_bodies")


static func _nature_body(root: Node3D) -> StaticBody3D:
	var existing: Node = root.get_node_or_null("NatureCollision")
	if existing is StaticBody3D:
		return existing as StaticBody3D
	return solid_root(root, "NatureCollision")


static func _model_exists(model: String, nature: bool = false) -> bool:
	return ResourceLoader.exists(_model_path(model, nature))


# --------------------------------------------------------------------------
# grip hazards

static func _build_hazards(root: Node3D, theme: Dictionary) -> Array[Dictionary]:
	## Visible floor markings that change grip. They carry no collider: a wet
	## patch is not a prop, and a kart must be able to drive through it.
	var hazards: Array[Dictionary] = []
	var data: Dictionary = theme.get("hazard", {}) as Dictionary
	if data.is_empty():
		return hazards
	var grip: float = float(data.get("grip", 0.8))
	var spin: float = float(data.get("spin", 0.0))
	var tint: Color = data.get("tint", Color(0.4, 0.5, 0.6)) as Color
	var kind: String = str(data.get("kind", "wet"))
	var spots: Array = data.get("spots", []) as Array
	for raw: Variant in spots:
		if not (raw is Vector2):
			continue
		var offset: Vector2 = raw as Vector2
		var spot := Vector3(offset.x, 0.0, offset.y)
		_add_hazard_disc(root, spot, HAZARD_RADIUS, tint, kind)
		hazards.append({
			"centre": spot,
			"radius": HAZARD_RADIUS,
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
	mat.albedo_color.a = 0.72
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.35
	mat.metallic = 0.0
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
# Kenney model plumbing
#
# Measured once per GLB and cached: AABB in model space plus the mesh parts and
# their node transforms. `fit_transform` centres a model on its plan-view AABB
# and sits its bottom on the requested point, so placement never depends on the
# export pivot. None of the Kenney GLBs ships collision; callers add it.

## Measured AABB and mesh parts of a Kenney GLB. Returns {ok, path, aabb,
## center: Vector2, size: Vector3, parts: Array[{mesh, transform}]}.
static func model_info(model: String, nature: bool = false) -> Dictionary:
	var path: String = _model_path(model, nature)
	if _model_cache.has(path):
		return _model_cache[path] as Dictionary
	var info: Dictionary = {"ok": false, "path": path}
	if not ResourceLoader.exists(path):
		push_warning("CargoTheme: missing model " + path)
		_model_cache[path] = info
		return info
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		push_warning("CargoTheme: cannot load " + path)
		_model_cache[path] = info
		return info
	var root: Node = packed.instantiate()
	var aabb: AABB = _aabb(root, Transform3D.IDENTITY)
	var parts: Array = []
	_collect_parts(root, Transform3D.IDENTITY, parts)
	root.free()
	info["ok"] = true
	info["aabb"] = aabb
	info["center"] = Vector2((aabb.position.x + aabb.end.x) * 0.5,
		(aabb.position.z + aabb.end.z) * 0.5)
	info["size"] = aabb.size
	info["parts"] = parts
	_model_cache[path] = info
	return info


## Transform that places `model` at `at`, yawed and scaled, bottom on the
## ground and plan-view centre on `at`.
static func fit_transform(model: String, at: Vector3, yaw: float,
		scale: Vector3, nature: bool = false) -> Transform3D:
	var info: Dictionary = model_info(model, nature)
	if not bool(info.get("ok", false)):
		return Transform3D(Basis(Vector3.UP, yaw).scaled(scale), at)
	var center: Vector2 = info["center"]
	var aabb: AABB = info["aabb"]
	var yaw_basis := Basis(Vector3.UP, yaw)
	var basis: Basis = yaw_basis * Basis.IDENTITY.scaled(scale)
	var center_m := Vector3(center.x * scale.x, 0.0, center.y * scale.z)
	var lift: float = -aabb.position.y * scale.y
	return Transform3D(basis, at - yaw_basis * center_m + Vector3.UP * lift)


## Scaled size of a model in metres.
static func scaled_size(model: String, scale: Vector3,
		nature: bool = false) -> Vector3:
	var info: Dictionary = model_info(model, nature)
	if not bool(info.get("ok", false)):
		return Vector3(0.1, 0.1, 0.1)
	return (info["aabb"] as AABB).size * scale


## Instantiates one Kenney model as a child of `parent` and returns it.
static func place_model(parent: Node3D, model: String, at: Vector3, yaw: float,
		scale: Vector3, node_name: String, nature: bool = false) -> Node3D:
	if parent == null:
		return null
	var info: Dictionary = model_info(model, nature)
	if not bool(info.get("ok", false)):
		return null
	var packed: PackedScene = load(str(info["path"])) as PackedScene
	if packed == null:
		return null
	var node: Node3D = packed.instantiate() as Node3D
	if node == null:
		return null
	node.name = node_name
	node.transform = fit_transform(model, at, yaw, scale, nature)
	parent.add_child(node)
	return node


## One MultiMesh per mesh part for every repeated model instance.
static func batch_model(parent: Node3D, model: String, transforms: Array,
		node_name: String, cast_shadow: bool = true,
		nature: bool = false) -> void:
	if parent == null or transforms.is_empty():
		return
	var info: Dictionary = model_info(model, nature)
	if not bool(info.get("ok", false)):
		return
	var parts: Array = info.get("parts", []) as Array
	for part_index in parts.size():
		var part: Dictionary = parts[part_index]
		var mesh: Mesh = part.get("mesh") as Mesh
		var local: Transform3D = part.get("transform", Transform3D.IDENTITY) \
			as Transform3D
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
		instance.name = node_name if parts.size() == 1 \
			else "%s_%d" % [node_name, part_index]
		instance.multimesh = multi
		instance.cast_shadow = \
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(instance)


# --------------------------------------------------------------------------
# colliders

## Creates a WORLD static body under `parent`.
static func solid_root(parent: Node3D, node_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = 0
	parent.add_child(body)
	return body


## Adds a box collider to `body`.
static func add_box_collider(body: StaticBody3D, xform: Transform3D,
		size: Vector3) -> void:
	if body == null:
		return
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = xform
	body.add_child(collision)


## Adds a vertical cylinder collider standing on `point`.
static func add_cylinder_collider(body: StaticBody3D, point: Vector3,
		radius: float, height: float) -> void:
	if body == null:
		return
	var shape := CylinderShape3D.new()
	shape.radius = maxf(radius, 0.05)
	shape.height = maxf(height, 0.1)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = point + Vector3.UP * (shape.height * 0.5)
	body.add_child(collision)


# --------------------------------------------------------------------------
# measurement

static func _model_path(model: String, nature: bool = false) -> String:
	if nature:
		return NATURE_ROOT + model + ".glb"
	if model == CRATE_MODEL:
		return CAR_ROOT + model + ".glb"
	return RACING_ROOT + model + ".glb"


static func _aabb(node: Node, xform: Transform3D) -> AABB:
	var local: Transform3D = xform
	if node is Node3D:
		local = xform * (node as Node3D).transform
	var result := AABB()
	var found: bool = false
	if node is MeshInstance3D:
		var instance: MeshInstance3D = node as MeshInstance3D
		if instance.mesh != null:
			result = local * instance.mesh.get_aabb()
			found = true
	for child: Node in node.get_children():
		var child_box: AABB = _aabb(child, local)
		if child is MeshInstance3D:
			result = result.merge(child_box) if found else child_box
			found = true
	return result


static func _collect_parts(node: Node, xform: Transform3D, parts: Array) -> void:
	var local: Transform3D = xform
	if node is Node3D:
		local = xform * (node as Node3D).transform
	if node is MeshInstance3D:
		var instance: MeshInstance3D = node as MeshInstance3D
		if instance.mesh != null:
			parts.append({"mesh": instance.mesh, "transform": local})
	for child: Node in node.get_children():
		_collect_parts(child, local, parts)
