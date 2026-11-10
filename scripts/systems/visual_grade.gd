extends RefCounted
## Shared 3D look for every gameplay scene.
##
## The menus are flat cartoon art; the 3D scenes should feel like the same
## game. One place owns the sky, sun, fog and cheap post-processing so the
## race and the sandbox cannot drift apart, and so a quality change is a
## one-line edit instead of a scene-file hunt.
##
## No class_name on purpose: the global class cache is not populated on a cold
## headless boot (see docs/ARCHITECTURE.md). Consumers preload this script.

## Palette taken from the menu art: deeper sky blue, warm sun, green ground.
const SKY_TOP := Color("2f9fe8")
const SKY_HORIZON := Color("bfe9ff")
const GROUND_HORIZON := Color("bfe9ff")
const GROUND_BOTTOM := Color("2e6b2f")
const SUN_COLOR := Color("fff1d6")
const FOG_COLOR := Color("bfe9ff")


static func apply(world: WorldEnvironment, kind: String = "race") -> void:
	if world == null or world.environment == null:
		return
	var env: Environment = world.environment
	env.background_mode = Environment.BG_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.tonemap_white = 1.0

	# Sky: a deeper top and a horizon that still reads as haze. The default
	# near-white horizon was what made the old meadow look washed out.
	if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
		var sky: ProceduralSkyMaterial = env.sky.sky_material as ProceduralSkyMaterial
		sky.sky_top_color = SKY_TOP
		sky.sky_horizon_color = SKY_HORIZON
		sky.sky_curve = 0.18
		sky.ground_horizon_color = GROUND_HORIZON
		sky.ground_bottom_color = GROUND_BOTTOM
		sky.sun_angle_max = 20.0
		sky.sun_curve = 0.08
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	# Cheap post: a little bloom on boost pads and the sun, a little punch in
	# the colours. No SSAO/SSIL, which the Mobile renderer does not run.
	# Glow on Mobile is a fragment pass, not compute. Keep it low: enough to
	# make the start lamps and boost pads pop, not enough to cost a frame.
	env.glow_enabled = true
	env.glow_intensity = 0.18
	env.glow_strength = 1.0
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.15
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.08
	env.adjustment_brightness = 1.0

	if kind == "race":
		# Distance haze hides the edge of the meadow and adds depth. Keep it
		# light enough that the next corner is always readable.
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_light_color = FOG_COLOR
		env.fog_light_energy = 0.9
		env.fog_density = 0.0012
		env.fog_aerial_perspective = 0.5
		env.fog_sky_affect = 0.0
		env.fog_sun_scatter = 0.18
	else:
		# The park is a compact, readable stunt yard. Fog at any density that
		# layers the far hills also desaturates the bowl and grass, so keep the
		# sandbox crisp. The backdrop meshes already fade into the sky.
		env.fog_enabled = false


static func apply_sun(sun: DirectionalLight3D) -> void:
	if sun == null:
		return
	sun.light_color = SUN_COLOR
	sun.light_energy = 1.10
	sun.shadow_enabled = true
	# Two cascades over 90 m: the chase camera never sees beyond that clearly,
	# and four splits cost noticeably more on integrated GPUs.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 90.0
	sun.directional_shadow_fade_start = 0.9
	sun.directional_shadow_blend_splits = true
	sun.shadow_blur = 1.6
	sun.light_angular_distance = 0.9
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	sun.shadow_opacity = 0.75
