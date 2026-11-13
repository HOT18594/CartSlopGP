extends RefCounted
## Layered horizon and depth haze for a tile map.
##
## Four noise-displaced bands - a near ridge, a second ridge, a rock wall and a
## mountain wall - are built as one merged mesh each and tinted from the theme
## palette. Depth fog turns the bands into layers instead of hard silhouettes and
## keeps the next corner crisp. The whole horizon is four draw calls, casts no
## shadow and has no collision, which is how a map stays busy at the horizon
## without spending its draw-call budget there.

const SceneryKit := preload("res://scripts/minigames/scenery/scenery_kit.gd")

const HOLDER_NAME: String = "TileHorizon"
const SEGMENTS: int = 160
const RINGS: int = 6

## Band layout, near to far. Colours come from the theme palette.
const BANDS: Array = [
	{"name": "NearRidge", "inner": 230.0, "outer": 340.0, "height": 30.0,
		"profile": "ridge", "seed": 4101, "frequency": 0.0060, "jag": 0.16},
	{"name": "MidRidge", "inner": 330.0, "outer": 450.0, "height": 58.0,
		"profile": "ridge", "seed": 5209, "frequency": 0.0048, "jag": 0.24},
	{"name": "CliffWall", "inner": 440.0, "outer": 520.0, "height": 80.0,
		"profile": "cliff", "seed": 6337, "frequency": 0.0068, "jag": 0.30},
	{"name": "MountainWall", "inner": 540.0, "outer": 880.0, "height": 180.0,
		"profile": "peak", "seed": 7441, "frequency": 0.0039, "jag": 0.34},
]


## Builds the horizon under `parent`. The second call is a no-op.
static func build(parent: Node3D, palette: Dictionary) -> int:
	if parent == null or parent.has_node(HOLDER_NAME):
		return 0
	var haze: Dictionary = palette.get("haze", {})
	if haze.is_empty():
		return 0
	var holder := Node3D.new()
	holder.name = HOLDER_NAME
	parent.add_child(holder)
	var material: StandardMaterial3D = SceneryKit.vertex_material()
	var near: Color = haze.get("near", Color("5f8146"))
	var mid: Color = haze.get("mid", Color("4c6b42"))
	var rock: Color = haze.get("rock", Color("6a655c"))
	var peak: Color = haze.get("peak", Color("9aa4ad"))
	var snow: float = float(haze.get("snow", 0.0))
	var bands: int = 0
	for spec: Dictionary in BANDS:
		var profile: String = str(spec["profile"])
		var low: Color = near
		var high: Color = mid
		match profile:
			"cliff":
				low = rock
				high = rock.lightened(0.18)
			"peak":
				low = peak.darkened(0.18)
				high = peak
			_:
				low = near if bands == 0 else mid
				high = low.lightened(0.22)
		var mesh: ArrayMesh = _band_mesh(spec, low, high, snow)
		if mesh == null:
			continue
		var band := MeshInstance3D.new()
		band.name = str(spec["name"])
		band.mesh = mesh
		band.material_override = material
		band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(band)
		bands += 1
	_apply_fog(parent, haze)
	return bands


static func _band_mesh(spec: Dictionary, low: Color, high: Color,
		snow: float) -> ArrayMesh:
	var lobes := FastNoiseLite.new()
	lobes.seed = int(spec["seed"])
	lobes.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	lobes.frequency = float(spec["frequency"])
	lobes.fractal_type = FastNoiseLite.FRACTAL_FBM
	lobes.fractal_octaves = 5
	lobes.fractal_gain = 0.5
	var detail := FastNoiseLite.new()
	detail.seed = int(spec["seed"]) + 977
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail.frequency = 0.045
	detail.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail.fractal_octaves = 3
	var inner: float = float(spec["inner"])
	var outer: float = float(spec["outer"])
	var height: float = float(spec["height"])
	var profile: String = str(spec["profile"])
	var jag: float = float(spec["jag"])
	var verts := PackedVector3Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	for ring in RINGS:
		var t: float = float(ring) / float(RINGS - 1)
		var lift: float = _profile(profile, t)
		var radius: float = lerpf(inner, outer, t)
		for i in SEGMENTS:
			var angle: float = TAU * float(i) / float(SEGMENTS)
			var direction := Vector3(cos(angle), 0.0, sin(angle))
			var crest: float = height * (0.55 + 0.45 * _unit(
				lobes.get_noise_2d(direction.x * 900.0, direction.z * 900.0)))
			crest *= 1.0 + jag * detail.get_noise_2d(direction.x * 420.0,
				direction.z * 420.0)
			if profile == "peak":
				crest *= 0.62 + 0.38 * absf(detail.get_noise_2d(
					direction.x * 1900.0, direction.z * 1900.0)) * 2.0
			var wobble: float = detail.get_noise_2d(direction.x * 130.0 + 17.0,
				direction.z * 130.0 - 29.0)
			var ring_radius: float = radius + wobble * (2.0 + radius * 0.035) * lift
			var y: float = crest * lift - 0.6
			y += detail.get_noise_2d(direction.x * 62.0 + 31.0,
				direction.z * 62.0 - 13.0) * 2.6 * lift
			verts.append(direction * ring_radius + Vector3.UP * y)
			var tint: float = 0.5 + 0.5 * _unit(
				detail.get_noise_2d(direction.x * 700.0, direction.z * 700.0))
			var colour: Color = low.lerp(high, clampf(tint * 0.72 + lift * 0.28,
				0.0, 1.0))
			if snow > 0.0 and y > crest * snow:
				colour = colour.lerp(Color(0.94, 0.96, 0.98),
					smoothstep(crest * snow, crest * snow + 14.0, y))
			colours.append(colour)
	for ring in RINGS - 1:
		for i in SEGMENTS:
			var next: int = (i + 1) % SEGMENTS
			var a: int = ring * SEGMENTS + i
			var b: int = ring * SEGMENTS + next
			var c: int = (ring + 1) * SEGMENTS + i
			var d: int = (ring + 1) * SEGMENTS + next
			indices.append(a)
			indices.append(b)
			indices.append(c)
			indices.append(b)
			indices.append(d)
			indices.append(c)
	var flat: bool = profile == "cliff" or profile == "peak"
	return SceneryKit.mesh_from(verts, colours, indices, flat)


static func _profile(kind: String, t: float) -> float:
	match kind:
		"cliff":
			return smoothstep(0.0, 0.30, t)
		"peak":
			return pow(smoothstep(0.0, 0.72, t), 0.65)
		_:
			return pow(sin(PI * t), 0.85)


static func _unit(noise_value: float) -> float:
	return noise_value * 0.5 + 0.5


static func _apply_fog(parent: Node3D, haze: Dictionary) -> void:
	var world := parent.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world == null or world.environment == null:
		return
	var env: Environment = world.environment
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = haze.get("fog", Color("bfe9ff")) as Color
	env.fog_light_energy = 0.9
	env.fog_depth_begin = float(haze.get("fog_begin", 90.0))
	env.fog_depth_end = float(haze.get("fog_end", 620.0))
	env.fog_depth_curve = 0.9
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.0
