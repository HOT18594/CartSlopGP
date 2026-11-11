extends RefCounted
## Layered, noise-displaced horizon for Meadow Loop.
##
## The old horizon was a ring of eighteen grassy SphereMesh domes plus nine
## dark ones behind them. This builds four continuous bands instead - a grassy
## near ridge, a darker second ridge, a rock cliff wall and a snow-capped
## mountain wall - each one merged mesh with baked vertex colours. The whole
## horizon is four draw calls, casts no shadow and has no collision.
##
## Depth fog is tuned here rather than in VisualGrade because the fog is what
## turns the bands into layers; the near field stays crisp so the next corner
## is always readable.

const SceneryKit := preload("res://scripts/minigames/scenery/scenery_kit.gd")

const HOLDER_NAME: String = "HorizonLayers"
const SEGMENTS: int = 192
const RINGS: int = 7

## Bands, near to far. `profile` picks the silhouette: a rounded ridge, a cliff
## that climbs fast and then holds, or a mountain wall that keeps climbing.
## Adjacent bands overlap in radius so no ground gap shows through.
const BANDS: Array = [
	{"name": "NearRidge", "inner": 210.0, "outer": 320.0, "height": 28.0,
		"profile": "ridge", "seed": 4101, "frequency": 0.0060, "jag": 0.16,
		"low": Color("5f8146"), "high": Color("7f9a55"), "snow": 0.0},
	{"name": "MidRidge", "inner": 308.0, "outer": 428.0, "height": 56.0,
		"profile": "ridge", "seed": 5209, "frequency": 0.0048, "jag": 0.24,
		"low": Color("4c6b42"), "high": Color("6f8a52"), "snow": 0.0},
	{"name": "CliffWall", "inner": 414.0, "outer": 492.0, "height": 78.0,
		"profile": "cliff", "seed": 6337, "frequency": 0.0068, "jag": 0.30,
		"low": Color("6a655c"), "high": Color("6f7f52"), "snow": 0.0},
	{"name": "MountainWall", "inner": 520.0, "outer": 840.0, "height": 178.0,
		"profile": "peak", "seed": 7441, "frequency": 0.0039, "jag": 0.34,
		"low": Color("5d6a76"), "high": Color("9aa4ad"), "snow": 0.62},
]


## Builds the layered horizon under `parent`. Safe to call more than once: the
## second call is a no-op while the holder node exists.
static func build(parent: Node3D, stats: Dictionary) -> void:
	if parent == null or parent.has_node(HOLDER_NAME):
		return
	var holder := Node3D.new()
	holder.name = HOLDER_NAME
	parent.add_child(holder)
	var material: StandardMaterial3D = SceneryKit.vertex_material()
	for spec: Dictionary in BANDS:
		var mesh: ArrayMesh = _band_mesh(spec)
		if mesh == null:
			continue
		var band := MeshInstance3D.new()
		band.name = str(spec["name"])
		band.mesh = mesh
		band.material_override = material
		band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(band)
		SceneryKit.bump(stats, "bands")
		SceneryKit.bump(stats, "draw_calls")
	_apply_fog(parent)


# --------------------------------------------------------------------------
# band meshes


static func _band_mesh(spec: Dictionary) -> ArrayMesh:
	# Broad lobes are sampled around a circle, which is seamless by
	# construction; the detail noise roughens the surface without a seam.
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
	var low: Color = spec["low"]
	var high: Color = spec["high"]
	var snow: float = float(spec["snow"])

	var verts := PackedVector3Array()
	var colors := PackedColorArray()
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
				# A second, sharper noise turns the wall into separate peaks.
				crest *= 0.62 + 0.38 * absf(detail.get_noise_2d(direction.x * 1900.0,
					direction.z * 1900.0)) * 2.0
			var wobble: float = detail.get_noise_2d(direction.x * 130.0 + 17.0,
				direction.z * 130.0 - 29.0)
			var ring_radius: float = radius + wobble * (2.0 + radius * 0.035) * lift
			var y: float = crest * lift - 0.6
			y += detail.get_noise_2d(direction.x * 62.0 + 31.0,
				direction.z * 62.0 - 13.0) * 2.6 * lift
			verts.append(direction * ring_radius + Vector3.UP * y)
			var tint: float = 0.5 + 0.5 * _unit(
				detail.get_noise_2d(direction.x * 700.0, direction.z * 700.0))
			var color: Color = low.lerp(high, clampf(tint * 0.72 + lift * 0.28,
				0.0, 1.0))
			if snow > 0.0 and y > crest * snow:
				color = color.lerp(Color(0.94, 0.96, 0.98),
					smoothstep(crest * snow, crest * snow + 14.0, y))
			colors.append(color)
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
	return SceneryKit.mesh_from(verts, colors, indices, flat)


## Height profile across a band: 0 at the toe, 1 at the crest.
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


# --------------------------------------------------------------------------
# atmosphere


static func _apply_fog(parent: Node3D) -> void:
	# Depth fog keeps the near field crisp and layers the ridges into the sky.
	# Exponential fog at the shared density left the far mountains as hard
	# silhouettes; a depth curve ending just past them reads as aerial haze.
	var world := parent.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world == null or world.environment == null:
		return
	var env: Environment = world.environment
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color("bfe9ff")
	env.fog_light_energy = 0.9
	env.fog_depth_begin = 55.0
	env.fog_depth_end = 900.0
	env.fog_depth_curve = 0.9
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.0
