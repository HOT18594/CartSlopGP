extends RefCounted
## Theme palettes for the tile maps.
##
## One theme is pure data: the road and shoulder materials (built from the
## Poly Haven CC0 scans), the kerb and fence colours, the ground the race scene
## should lay down, the foliage set and the horizon tint. The tile builders take
## a palette dictionary and never look a theme up themselves, so a new map is a
## preset plus a few lines here.
##
## Every material is created once and cached per theme id; a second build in the
## same process reuses the same ShaderMaterial instances.

const PBR_SHADER: String = "res://assets/materials/ground_pbr.gdshader"
const PBR_TEX: String = "res://assets/textures/polyhaven/"

const THEME_STADIUM: String = "stadium"
const THEME_DOCKYARD: String = "dockyard"
const THEME_GLACIER: String = "glacier"

const CREAM := Color("fff6e3")
const STEEL := Color("4a5560")
const CONCRETE := Color("b9b4a8")

static var _cache: Dictionary = {}


## Palette for `theme_id`. Unknown ids fall back to the stadium theme.
static func resolve(theme_id: String) -> Dictionary:
	var key: String = theme_id if theme_id in [
		THEME_STADIUM, THEME_DOCKYARD, THEME_GLACIER] else THEME_STADIUM
	if _cache.has(key):
		return _cache[key]
	var palette: Dictionary = {}
	match key:
		THEME_DOCKYARD:
			palette = _dockyard()
		THEME_GLACIER:
			palette = _glacier()
		_:
			palette = _stadium()
	palette["id"] = key
	_cache[key] = palette
	return palette


# --------------------------------------------------------------------------
# palettes


static func _stadium() -> Dictionary:
	return {
		"road": _pbr_material("asphalt_01", Color(0.78, 0.80, 0.84), 1.0,
			0.10, 0.035, 0.16),
		"shoulder": _pbr_material("grass", Color(0.72, 0.88, 0.65), 1.0,
			0.10, 0.05, 0.0),
		"concrete": _pbr_material("concrete_floor_worn_001",
			Color(0.84, 0.82, 0.78), 0.8, 0.12, 0.04, 0.0),
		"kerb": Color("c23a2c"),
		"kerb_alt": CREAM,
		"fence": STEEL,
		"accent": Color("c9553f"),
		"stand_roof": Color("c9553f"),
		"stand_seat": Color("8fa3b8"),
		"ground": {
			"diff": "grass_diff", "nor": "grass_nor", "rough": "grass_rough",
			"tint": Color(0.72, 0.88, 0.65), "uv_scale": 140.0, "detail": 0.10,
			"macro": 0.05,
		},
		"trees": PackedStringArray([
			"tree_oak", "tree_oak_dark", "tree_default", "tree_fat",
			"tree_tall", "tree_pineTallA", "tree_pineRoundA", "tree_simple",
		]),
		"tree_tint": Color(0.92, 1.0, 0.88),
		"bushes": PackedStringArray([
			"plant_bush", "plant_bushLarge", "plant_bushSmall", "grass_large",
		]),
		"haze": {
			"near": Color("5f8146"), "mid": Color("4c6b42"),
			"rock": Color("6a655c"), "peak": Color("9aa4ad"),
			"snow": 0.35, "fog": Color("bfe9ff"), "fog_begin": 90.0,
			"fog_end": 620.0,
		},
		"extras": "",
		"wet_sheen": Color(0.42, 0.52, 0.62, 0.0),
		"ice_sheen": Color(0.78, 0.90, 1.0, 0.0),
	}


static func _dockyard() -> Dictionary:
	return {
		"road": _pbr_material("asphalt_02", Color(0.62, 0.66, 0.72), 1.0,
			0.12, 0.04, 0.22),
		"shoulder": _pbr_material("concrete_floor_worn_001",
			Color(0.72, 0.70, 0.66), 0.9, 0.14, 0.05, 0.0),
		"concrete": _pbr_material("concrete_floor_worn_001",
			Color(0.78, 0.76, 0.72), 0.8, 0.12, 0.04, 0.0),
		"kerb": Color("e8c34a"),
		"kerb_alt": Color("2f2a26"),
		"fence": Color("7d8a94"),
		"accent": Color("2e86ab"),
		"stand_roof": Color("2e86ab"),
		"stand_seat": Color("d9d4c7"),
		"ground": {
			"diff": "concrete_floor_worn_001_diff",
			"nor": "concrete_floor_worn_001_nor",
			"rough": "concrete_floor_worn_001_rough",
			"tint": Color(0.70, 0.70, 0.68), "uv_scale": 120.0, "detail": 0.12,
			"macro": 0.06,
		},
		"trees": PackedStringArray([
			"tree_small", "tree_small_dark", "plant_bushLarge",
			"plant_bushDetailed",
		]),
		"tree_tint": Color(0.86, 0.95, 0.90),
		"bushes": PackedStringArray(["plant_bush", "plant_flatShort"]),
		"haze": {
			"near": Color("5c6a72"), "mid": Color("4a5760"),
			"rock": Color("5a5f63"), "peak": Color("8b99a2"),
			"snow": 0.0, "fog": Color("c4d6dd"), "fog_begin": 80.0,
			"fog_end": 560.0,
		},
		"extras": "containers",
		"wet_sheen": Color(0.30, 0.42, 0.55, 0.30),
		"ice_sheen": Color(0.78, 0.90, 1.0, 0.0),
	}


static func _glacier() -> Dictionary:
	return {
		"road": _pbr_material("asphalt_01", Color(0.84, 0.88, 0.95), 1.0,
			0.09, 0.03, 0.10),
		"shoulder": _pbr_material("snow_02", Color(0.96, 0.98, 1.0), 1.0,
			0.08, 0.04, 0.0),
		"concrete": _pbr_material("concrete_floor_worn_001",
			Color(0.80, 0.83, 0.86), 0.8, 0.12, 0.04, 0.0),
		"kerb": Color("2e86ab"),
		"kerb_alt": Color("f4f1e6"),
		"fence": Color("9fb4c4"),
		"accent": Color("38d6f0"),
		"stand_roof": Color("2e86ab"),
		"stand_seat": Color("dfe9f2"),
		"ground": {
			"diff": "snow_02_diff", "nor": "snow_02_nor",
			"rough": "snow_02_rough", "tint": Color(0.96, 0.98, 1.0),
			"uv_scale": 160.0, "detail": 0.08, "macro": 0.04,
		},
		"trees": PackedStringArray([
			"tree_pineTallA", "tree_pineTallB", "tree_pineTallC",
			"tree_pineTallD", "tree_pineRoundA", "tree_cone",
			"tree_pineSmallA", "tree_pineSmallB",
		]),
		"tree_tint": Color(0.86, 0.96, 0.94),
		"bushes": PackedStringArray([
			"plant_bushLargeTriangle", "plant_bushTriangle", "rock_largeA",
			"rock_smallA",
		]),
		"haze": {
			"near": Color("dbe8ef"), "mid": Color("b7cbd8"),
			"rock": Color("8d9ca8"), "peak": Color("e8f1f7"),
			"snow": 0.55, "fog": Color("e6f2fa"), "fog_begin": 120.0,
			"fog_end": 760.0,
		},
		"extras": "snow",
		"wet_sheen": Color(0.42, 0.52, 0.62, 0.0),
		"ice_sheen": Color(0.72, 0.88, 1.0, 0.34),
	}


# --------------------------------------------------------------------------
# materials


static func _pbr_material(prefix: String, tint: Color, uv_scale: float,
		detail: float, macro: float, tracks: float) -> Material:
	var diff: String = PBR_TEX + prefix + "_diff.jpg"
	var nor: String = PBR_TEX + prefix + "_nor.jpg"
	var rough: String = PBR_TEX + prefix + "_rough.jpg"
	# A source checkout without the imported scans still needs a road: fall back
	# to a flat tinted material instead of spraying load errors.
	if not (ResourceLoader.exists(diff) and ResourceLoader.exists(nor)
			and ResourceLoader.exists(rough)):
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = tint
		fallback.roughness = 0.94
		fallback.metallic = 0.0
		return fallback
	var mat := ShaderMaterial.new()
	mat.shader = load(PBR_SHADER) as Shader
	mat.set_shader_parameter("albedo_tex", load(diff))
	mat.set_shader_parameter("normal_tex", load(nor))
	mat.set_shader_parameter("rough_tex", load(rough))
	mat.set_shader_parameter("uv_scale", uv_scale)
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("detail_strength", detail)
	mat.set_shader_parameter("macro_variation", macro)
	mat.set_shader_parameter("roughness_min", 0.55)
	if tracks > 0.0:
		mat.set_shader_parameter("track_strength", tracks)
	return mat
