extends RefCounted
## The three CARGO RUSH arena skins, chosen by theme id.
##
## A theme owns the ground material, the solid yard dressing, the crate look
## (shipping crates, hay bales and produce, gift boxes) and the grip rule of
## the arena. The arena itself stays identical for every theme: same footprint,
## same delivery pads, same crate colliders, so the game rules never change.
##
## Textures are the CC0 Poly Haven scans already in the project. A source
## checkout that has not run the importer yet cannot load the JPGs, so every
## material falls back to a flat tint instead of spraying resource errors.
##
## Every solid piece built here (containers, bales, gifts) gets a box collider
## on CollisionLayers.WORLD. Ground hazards (ice patches, soft dirt) are not
## props: they are visible floor markings that change the carts' grip.

const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")
const SceneryKit := preload("res://scripts/minigames/scenery/scenery_kit.gd")
const PropBatch := preload("res://scripts/minigames/scenery/prop_batch.gd")

const PBR_SHADER: String = "res://assets/materials/ground_pbr.gdshader"
const PBR_TEX: String = "res://assets/textures/polyhaven/"
const DEFAULT_ID: String = "dockyard"
const THEME_IDS: PackedStringArray = ["dockyard", "farmyard", "snowfield"]

## One collider box for every crate, whatever it looks like. Keeping the
## physics shape identical across themes means a salt bale and a gift box can
## never disagree about where the kart can reach.
const CRATE_EXTENTS: Vector3 = Vector3(1.25, 1.05, 1.25)
## Ice: low lateral grip plus the arena's own spin wobble (see cargo_rush.gd).
const ICE_GRIP: float = 0.34
const ICE_SPIN: float = 2.8
## Farm dirt is soft: it slows the heavy crates as well as the karts.
const SOFT_GRIP: float = 0.82
const SOFT_CRATE_DAMP: float = 1.7

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
		"fog_density": 0.0022,
		"floor": ["asphalt_01_diff", "asphalt_01_nor", "asphalt_01_rough"],
		"floor_tint": Color(0.78, 0.83, 0.88),
		"floor_uv": 0.24,
		"floor_detail": 0.10,
		"floor_macro": 0.035,
		"floor_roughness": 0.34,
		"apron": ["concrete_floor_worn_001_diff", "concrete_floor_worn_001_nor",
			"concrete_floor_worn_001_rough"],
		"apron_tint": Color(0.90, 0.90, 0.87),
		"apron_uv": 0.15,
		"apron_roughness": 0.42,
		"grip": 0.94,
		"crate_mass": 46.0,
		"crate_damp": 0.20,
		"crate_kind": "crate",
		"crate_label": "SHIPPING CRATES",
		"hazard_label": "NO HAZARD",
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
		"fog_density": 0.0016,
		"floor": ["dirt_diff", "dirt_nor", "dirt_rough"],
		"floor_tint": Color(0.92, 0.85, 0.72),
		"floor_uv": 0.20,
		"floor_detail": 0.14,
		"floor_macro": 0.05,
		"floor_roughness": 0.86,
		"apron": [],
		"grip": SOFT_GRIP,
		"crate_mass": 58.0,
		"crate_damp": SOFT_CRATE_DAMP,
		"crate_kind": "hay",
		"crate_label": "HAY BALES & PRODUCE",
		"hazard_label": "SOFT GROUND SLOWS HEAVY LOADS",
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
		"fog_density": 0.0028,
		"floor": ["snow_02_diff", "snow_02_nor", "snow_02_rough"],
		"floor_tint": Color(0.94, 0.97, 1.0),
		"floor_uv": 0.22,
		"floor_detail": 0.08,
		"floor_macro": 0.03,
		"floor_roughness": 0.55,
		"apron": [],
		"grip": 0.90,
		"crate_mass": 38.0,
		"crate_damp": 0.10,
		"crate_kind": "gift",
		"crate_label": "GIFT BOXES",
		"hazard_label": "ICE PATCHES SPIN YOU",
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


## Ground material for the arena floor. Uses the Poly Haven scans when the
## importer has produced them, and a flat tint otherwise.
static func floor_material(theme: Dictionary) -> Material:
	var files: Array = _string_list(theme.get("floor", []))
	return _pbr_material(files, theme.get("floor_tint", Color.WHITE) as Color,
		float(theme.get("floor_uv", 1.0)),
		float(theme.get("floor_detail", 0.1)),
		float(theme.get("floor_macro", 0.04)),
		float(theme.get("floor_roughness", 0.7)))


## Quay slab laid over the dockyard asphalt; null when the theme has none.
static func apron_material(theme: Dictionary) -> Material:
	var files: Array = _string_list(theme.get("apron", []))
	if files.is_empty():
		return null
	return _pbr_material(files, theme.get("apron_tint", Color.WHITE) as Color,
		float(theme.get("apron_uv", 0.2)), 0.12, 0.04,
		float(theme.get("apron_roughness", 0.5)))


## Builds every solid piece of yard dressing under `root` and returns the grip
## hazard zones: [{centre: Vector3, radius: float, grip: float, spin: float}].
static func build_scenery(root: Node3D, theme: Dictionary) -> Array[Dictionary]:
	var hazards: Array[Dictionary] = []
	match str(theme.get("id", DEFAULT_ID)):
		"farmyard":
			_build_farmyard(root)
		"snowfield":
			hazards = _build_snowfield(root)
		_:
			_build_dockyard(root)
	return hazards


## The crate meshes for a theme, in cycle order. All variants share the same
## CRATE_EXTENTS collider.
static func crate_meshes(theme: Dictionary) -> Array[Mesh]:
	match str(theme.get("crate_kind", "crate")):
		"hay":
			return _hay_meshes()
		"gift":
			return _gift_meshes()
	return _shipping_meshes()


## One shared vertex-coloured material for every crate.
static func crate_material(theme: Dictionary) -> Material:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	# Gifts are glossy paper; bales and crates are rough.
	mat.roughness = 0.48 if str(theme.get("crate_kind", "crate")) == "gift" else 0.88
	return mat


static func crate_extents() -> Vector3:
	return CRATE_EXTENTS


static func crate_mass(theme: Dictionary) -> float:
	return float(theme.get("crate_mass", 46.0))


static func crate_damp(theme: Dictionary) -> float:
	return float(theme.get("crate_damp", 0.2))


static func crate_label(theme: Dictionary) -> String:
	return str(theme.get("crate_label", "CARGO"))


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
# dockyard: containers, tyre stacks and a concrete quay slab


static func _build_dockyard(root: Node3D) -> void:
	var body := _solid_root(root, "DockyardProps")
	var container_mesh := BoxMesh.new()
	container_mesh.size = Vector3.ONE
	# Corner position, yaw and colour. The harbour wall is 44 m from the
	# centre, so every container sits between the pads and the wall.
	var placements: Array[Dictionary] = [
		{"position": Vector3(-32.0, 1.40, 39.0), "yaw": 0.0,
			"size": Vector3(13.0, 2.8, 4.6), "colour": Color(0.16, 0.42, 0.50)},
		{"position": Vector3(0.0, 1.40, 39.0), "yaw": 0.0,
			"size": Vector3(13.0, 2.8, 4.6), "colour": Color(0.56, 0.22, 0.18)},
		{"position": Vector3(30.0, 1.40, 39.0), "yaw": 0.0,
			"size": Vector3(13.0, 2.8, 4.6), "colour": Color(0.20, 0.32, 0.54)},
		{"position": Vector3(-32.0, 1.40, -39.0), "yaw": 0.0,
			"size": Vector3(13.0, 2.8, 4.6), "colour": Color(0.30, 0.34, 0.36)},
		{"position": Vector3(0.0, 1.40, -39.0), "yaw": 0.0,
			"size": Vector3(13.0, 2.8, 4.6), "colour": Color(0.62, 0.38, 0.14)},
		{"position": Vector3(30.0, 1.40, -39.0), "yaw": 0.0,
			"size": Vector3(13.0, 2.8, 4.6), "colour": Color(0.18, 0.45, 0.38)},
		{"position": Vector3(39.0, 1.40, 8.0), "yaw": PI * 0.5,
			"size": Vector3(13.0, 2.8, 4.6), "colour": Color(0.52, 0.28, 0.42)},
		{"position": Vector3(-39.0, 1.40, -8.0), "yaw": PI * 0.5,
			"size": Vector3(13.0, 2.8, 4.6), "colour": Color(0.24, 0.40, 0.52)},
	]
	var transforms: Array = []
	var colours: Array = []
	for entry: Dictionary in placements:
		var size: Vector3 = entry["size"] as Vector3
		var yaw: float = float(entry["yaw"])
		var position: Vector3 = entry["position"] as Vector3
		var basis := Basis(Vector3.UP, yaw).scaled(size)
		transforms.append(Transform3D(basis, position))
		colours.append(entry["colour"] as Color)
		_add_box_collider(body, Transform3D(Basis(Vector3.UP, yaw), position), size)
	root.add_child(SceneryKit.multimesh(container_mesh,
		SceneryKit.instance_material(0.82), transforms, "ShippingContainers",
		false, colours))

	# Tyre stacks in the four corners, clear of both delivery lanes.
	var tyre_mesh := CylinderMesh.new()
	tyre_mesh.top_radius = 0.46
	tyre_mesh.bottom_radius = 0.46
	tyre_mesh.height = 0.30
	tyre_mesh.radial_segments = 12
	tyre_mesh.rings = 1
	var tyre_transforms: Array = []
	var tyre_colours: Array = []
	for corner: Vector2 in [Vector2(-1.0, -1.0), Vector2(1.0, -1.0),
			Vector2(-1.0, 1.0), Vector2(1.0, 1.0)]:
		var base := Vector3(corner.x * 35.0, 0.0, corner.y * 35.0)
		for level in 3:
			tyre_transforms.append(Transform3D(Basis.IDENTITY,
				base + Vector3.UP * (0.15 + float(level) * 0.30)))
			var colour: Color = Color(0.09, 0.08, 0.10)
			if level == 2:
				colour = Color(0.76, 0.23, 0.18) if base.x > 0.0 \
					else Color(0.96, 0.94, 0.86)
			tyre_colours.append(colour)
		_add_box_collider(body, Transform3D(Basis.IDENTITY,
			base + Vector3.UP * 0.45), Vector3(1.55, 0.90, 1.55))
	root.add_child(SceneryKit.multimesh(tyre_mesh,
		SceneryKit.instance_material(0.95), tyre_transforms, "TyreStacks",
		false, tyre_colours))


# --------------------------------------------------------------------------
# farmyard: round hay bales, rectangular bales and produce crates


static func _build_farmyard(root: Node3D) -> void:
	var body := _solid_root(root, "FarmyardProps")
	var bale_mesh := CylinderMesh.new()
	bale_mesh.top_radius = 0.80
	bale_mesh.bottom_radius = 0.80
	bale_mesh.height = 1.60
	bale_mesh.radial_segments = 12
	bale_mesh.rings = 1
	var bale_transforms: Array = []
	var bale_colours: Array = []
	var bale_spots: Array[Vector2] = [
		Vector2(-30.0, 38.0), Vector2(-15.0, 38.0), Vector2(0.0, 38.0),
		Vector2(15.0, 38.0), Vector2(30.0, 38.0),
		Vector2(-30.0, -38.0), Vector2(-15.0, -38.0), Vector2(0.0, -38.0),
		Vector2(15.0, -38.0), Vector2(30.0, -38.0),
		Vector2(38.0, 18.0), Vector2(-38.0, -18.0),
	]
	for i in bale_spots.size():
		var spot: Vector2 = bale_spots[i]
		var yaw: float = 0.0 if i % 2 == 0 else PI * 0.5
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3(0.0, 0.0, 1.0), PI * 0.5)
		bale_transforms.append(Transform3D(basis, Vector3(spot.x, 0.80, spot.y)))
		bale_colours.append(Color(0.83, 0.72, 0.38) if i % 3 != 0
			else Color(0.72, 0.60, 0.28))
		_add_box_collider(body, Transform3D(Basis(Vector3.UP, yaw),
			Vector3(spot.x, 0.80, spot.y)), Vector3(1.68, 1.58, 1.68))
	root.add_child(SceneryKit.multimesh(bale_mesh,
		SceneryKit.instance_material(0.98), bale_transforms, "HayBales",
		false, bale_colours))

	# Square bales and produce boxes stacked against the same walls.
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3.ONE
	var transforms: Array = []
	var colours: Array = []
	var stacks: Array[Dictionary] = [
		{"position": Vector3(-37.0, 0.60, 32.0), "size": Vector3(2.2, 1.2, 1.5),
			"colour": Color(0.78, 0.66, 0.32), "yaw": 0.0},
		{"position": Vector3(-37.0, 1.80, 32.0), "size": Vector3(2.2, 1.2, 1.5),
			"colour": Color(0.84, 0.72, 0.36), "yaw": 0.12},
		{"position": Vector3(37.0, 0.60, -32.0), "size": Vector3(2.2, 1.2, 1.5),
			"colour": Color(0.74, 0.62, 0.30), "yaw": 0.0},
		{"position": Vector3(37.0, 1.80, -32.0), "size": Vector3(2.2, 1.2, 1.5),
			"colour": Color(0.82, 0.70, 0.34), "yaw": -0.10},
		{"position": Vector3(-24.0, 0.42, -38.5), "size": Vector3(1.4, 0.84, 1.4),
			"colour": Color(0.36, 0.50, 0.22), "yaw": 0.0},
		{"position": Vector3(-22.2, 0.42, -38.5), "size": Vector3(1.4, 0.84, 1.4),
			"colour": Color(0.72, 0.30, 0.16), "yaw": 0.0},
		{"position": Vector3(24.0, 0.42, 38.5), "size": Vector3(1.4, 0.84, 1.4),
			"colour": Color(0.62, 0.44, 0.18), "yaw": 0.0},
		{"position": Vector3(22.2, 0.42, 38.5), "size": Vector3(1.4, 0.84, 1.4),
			"colour": Color(0.44, 0.54, 0.20), "yaw": 0.0},
	]
	for entry: Dictionary in stacks:
		var size: Vector3 = entry["size"] as Vector3
		var yaw: float = float(entry["yaw"])
		var position: Vector3 = entry["position"] as Vector3
		transforms.append(Transform3D(Basis(Vector3.UP, yaw).scaled(size), position))
		colours.append(entry["colour"] as Color)
		_add_box_collider(body, Transform3D(Basis(Vector3.UP, yaw), position), size)
	root.add_child(SceneryKit.multimesh(box_mesh,
		SceneryKit.instance_material(0.95), transforms, "ProduceStacks",
		false, colours))


# --------------------------------------------------------------------------
# snowfield: gift piles and visible ice patches


static func _build_snowfield(root: Node3D) -> Array[Dictionary]:
	var body := _solid_root(root, "SnowfieldProps")
	var gift_mesh := BoxMesh.new()
	gift_mesh.size = Vector3.ONE
	var transforms: Array = []
	var colours: Array = []
	var wrappers: Array[Color] = [
		Color(0.86, 0.20, 0.24), Color(0.20, 0.48, 0.84),
		Color(0.22, 0.62, 0.38), Color(0.88, 0.62, 0.18),
		Color(0.62, 0.28, 0.72),
	]
	var stacks: Array[Vector3] = [
		Vector3(-36.0, 0.0, 36.0), Vector3(-18.0, 0.0, 38.0),
		Vector3(18.0, 0.0, 38.0), Vector3(36.0, 0.0, 36.0),
		Vector3(-36.0, 0.0, -36.0), Vector3(-18.0, 0.0, -38.0),
		Vector3(18.0, 0.0, -38.0), Vector3(36.0, 0.0, -36.0),
		Vector3(38.0, 0.0, 16.0), Vector3(-38.0, 0.0, -16.0),
	]
	for i in stacks.size():
		var base: Vector3 = stacks[i]
		var size := Vector3(1.6, 1.05, 1.4) if i % 2 == 0 \
			else Vector3(1.2, 1.3, 1.2)
		var yaw: float = float(i) * 0.37
		transforms.append(Transform3D(Basis(Vector3.UP, yaw).scaled(size),
			base + Vector3.UP * size.y * 0.5))
		colours.append(wrappers[i % wrappers.size()])
		_add_box_collider(body, Transform3D(Basis(Vector3.UP, yaw),
			base + Vector3.UP * size.y * 0.5), size)
		# A smaller box stacked on top of every second pile.
		if i % 2 == 0:
			var top_size := Vector3(1.1, 0.9, 1.0)
			transforms.append(Transform3D(
				Basis(Vector3.UP, yaw + 0.5).scaled(top_size),
				base + Vector3.UP * (size.y + top_size.y * 0.5)))
			colours.append(wrappers[(i + 2) % wrappers.size()])
			_add_box_collider(body, Transform3D(Basis(Vector3.UP, yaw + 0.5),
				base + Vector3.UP * (size.y + top_size.y * 0.5)), top_size)
	root.add_child(SceneryKit.multimesh(gift_mesh,
		SceneryKit.instance_material(0.90), transforms, "GiftPiles",
		false, colours))

	var hazards: Array[Dictionary] = []
	var ice_spots: Array[Vector3] = [
		Vector3(-22.0, 0.0, 10.0), Vector3(21.0, 0.0, -12.0),
		Vector3(0.0, 0.0, -17.0),
	]
	for spot: Vector3 in ice_spots:
		_add_ice_patch(root, spot, 4.2)
		hazards.append({
			"centre": spot,
			"radius": 4.2,
			"grip": ICE_GRIP,
			"spin": ICE_SPIN,
		})
	return hazards


static func _add_ice_patch(root: Node3D, centre: Vector3, radius: float) -> void:
	## Two flat discs read as a glossy frozen puddle: a darker rim and a bright
	## sheen. They are floor markings, so they carry no collider.
	var rim := MeshInstance3D.new()
	rim.name = "IceRim"
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.05
	disc.radial_segments = 24
	disc.rings = 1
	rim.mesh = disc
	var rim_mat := _ice_material(Color(0.36, 0.58, 0.74))
	rim.material_override = rim_mat
	rim.position = centre + Vector3.UP * 0.025
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(rim)

	var sheen := MeshInstance3D.new()
	sheen.name = "IceSheen"
	var inner := CylinderMesh.new()
	inner.top_radius = radius * 0.74
	inner.bottom_radius = radius * 0.74
	inner.height = 0.05
	inner.radial_segments = 24
	inner.rings = 1
	sheen.mesh = inner
	sheen.material_override = _ice_material(Color(0.72, 0.90, 1.0))
	sheen.position = centre + Vector3.UP * 0.055
	sheen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(sheen)


static func _ice_material(tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	var texture: Texture2D = _texture("snow_02_diff")
	if texture != null:
		mat.albedo_texture = texture
		mat.uv1_scale = Vector3(1.8, 1.8, 1.0)
	mat.roughness = 0.10
	mat.metallic = 0.0
	mat.emission_enabled = true
	mat.emission = Color(0.16, 0.36, 0.50)
	mat.emission_energy_multiplier = 0.22
	return mat


# --------------------------------------------------------------------------
# crate meshes


static func _shipping_meshes() -> Array[Mesh]:
	## Planked shipping crate with corner battens and a painted stencil band.
	var meshes: Array[Mesh] = []
	var wood: Array[Color] = [Color(0.47, 0.32, 0.18), Color(0.55, 0.40, 0.24)]
	var band: Array[Color] = [Color(0.93, 0.72, 0.16), Color(0.36, 0.55, 0.66)]
	for i in 2:
		var batch := PropBatch.new()
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3.ZERO), CRATE_EXTENTS,
			wood[i])
		for side: float in [-1.0, 1.0]:
			batch.add_box(Transform3D(Basis.IDENTITY,
				Vector3(side * (CRATE_EXTENTS.x * 0.5 - 0.03), 0.0, 0.0)),
				Vector3(0.10, CRATE_EXTENTS.y + 0.02, CRATE_EXTENTS.z + 0.02),
				band[i].darkened(0.08))
			batch.add_box(Transform3D(Basis.IDENTITY,
				Vector3(0.0, side * (CRATE_EXTENTS.y * 0.5 - 0.08), 0.0)),
				Vector3(CRATE_EXTENTS.x + 0.02, 0.14, CRATE_EXTENTS.z + 0.02),
				band[i])
		batch.add_box(Transform3D(Basis.IDENTITY,
			Vector3(0.0, 0.0, CRATE_EXTENTS.z * 0.5 - 0.02)),
			Vector3(CRATE_EXTENTS.x * 0.62, CRATE_EXTENTS.y * 0.46, 0.05),
			band[i].lerp(Color(0.90, 0.88, 0.82), 0.45))
		meshes.append(batch.build())
	return meshes


static func _hay_meshes() -> Array[Mesh]:
	## Hay bale and produce crate. Both fit the shared crate collider.
	var meshes: Array[Mesh] = []
	var hay: Array[Color] = [Color(0.84, 0.72, 0.36), Color(0.74, 0.62, 0.28)]
	for i in 2:
		var batch := PropBatch.new()
		var lying := Basis(Vector3(0.0, 0.0, 1.0), PI * 0.5)
		batch.add_cylinder(Transform3D(lying, Vector3.ZERO), 0.60, 1.20, 10,
			hay[i])
		for strap: float in [-0.30, 0.30]:
			batch.add_box(Transform3D(Basis.IDENTITY,
				Vector3(strap * 1.7, 0.0, 0.0)),
				Vector3(0.08, CRATE_EXTENTS.y + 0.02, CRATE_EXTENTS.z + 0.02),
				Color(0.42, 0.34, 0.20))
		meshes.append(batch.build())
	# The second variant is a produce crate, so the yard shows both art kinds.
	var produce := PropBatch.new()
	produce.add_box(Transform3D(Basis.IDENTITY, Vector3.ZERO), CRATE_EXTENTS,
		Color(0.50, 0.34, 0.18))
	for offset: Vector3 in [Vector3(-0.30, 0.0, 0.30), Vector3(0.30, 0.0, 0.30),
			Vector3(-0.30, 0.0, -0.30), Vector3(0.30, 0.0, -0.30)]:
		produce.add_box(Transform3D(Basis.IDENTITY,
			offset * Vector3(1.0, 0.0, 1.0)
			+ Vector3.UP * (CRATE_EXTENTS.y * 0.5 + 0.04)),
			Vector3(0.42, 0.18, 0.42), Color(0.30, 0.56, 0.22))
	for side: float in [-1.0, 1.0]:
		produce.add_box(Transform3D(Basis.IDENTITY,
			Vector3(side * (CRATE_EXTENTS.x * 0.5 - 0.03), 0.0, 0.0)),
			Vector3(0.10, CRATE_EXTENTS.y + 0.02, CRATE_EXTENTS.z + 0.02),
			Color(0.86, 0.78, 0.60))
	meshes.append(produce.build())
	return meshes


static func _gift_meshes() -> Array[Mesh]:
	## Wrapped gift box with a ribbon cross. The bow is two small boxes so the
	## silhouette still reads as a present from the chase camera.
	var meshes: Array[Mesh] = []
	var paper: Array[Color] = [Color(0.84, 0.20, 0.24), Color(0.20, 0.46, 0.82),
		Color(0.24, 0.60, 0.36)]
	var ribbon: Array[Color] = [Color(0.98, 0.90, 0.42), Color(0.98, 0.90, 0.42),
		Color(0.94, 0.44, 0.56)]
	for i in 3:
		var batch := PropBatch.new()
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3.ZERO), CRATE_EXTENTS,
			paper[i])
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3.ZERO),
			Vector3(0.22, CRATE_EXTENTS.y + 0.02, CRATE_EXTENTS.z + 0.02),
			ribbon[i])
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3.ZERO),
			Vector3(CRATE_EXTENTS.x + 0.02, 0.20, CRATE_EXTENTS.z + 0.02),
			ribbon[i])
		for side: float in [-1.0, 1.0]:
			batch.add_box(Transform3D(Basis(Vector3.UP, side * 0.5),
				Vector3(side * 0.16, CRATE_EXTENTS.y * 0.5 + 0.10, 0.0)),
				Vector3(0.30, 0.14, 0.18), ribbon[i].darkened(0.10))
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
