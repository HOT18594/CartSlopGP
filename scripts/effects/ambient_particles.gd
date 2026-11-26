extends RefCounted
## Themed ambient particle layers for every race map and minigame arena (WS3).
##
## Replaces the old single CPU-updated `MultiMesh` weather ribbon plus one plain
## biome emitter with a small, quality-tiered set of GPU particle layers:
##
##   * a primary weather sheet (snow, dust, mist, ash, leaves, confetti) with a
##     wind direction, turbulence, lifetime/size/speed variance and a soft colour
##     ramp so nothing reads as identical dots;
##   * a detail sheet (spindrift / sand grains / pollen / embers) that hugs the
##     ground and moves faster, which is what sells "the world is alive";
##   * an optional sparkle sheet at the QUALITY preset (diamond dust, sun motes,
##     lava glow) that is faded away on the balanced/performance presets and on
##     Web.
##
## Motion is GPU-side (`GPUParticles3D` + `ParticleProcessMaterial`), never
## per-particle GDScript. The only per-frame work is moving the camera-following
## emitters, plus a low-frequency wind gust written to the process material - a
## handful of property writes, no allocations.
##
## ## Budgets and cross-platform policy
##
## `FxQuality` decides how many layers exist and how dense they are:
## Web / PERFORMANCE = 2 layers at ~0.62-0.34 density, BALANCED = 2-3 layers at
## full density, QUALITY = 3 layers at 1.3 density. Reduced-motion keeps the
## atmosphere but slows the lateral sweep. Particle simulation runs at
## `fixed_fps` 30 for slow sheets and 60 for fast weather.
##
## WebGL2/Compatibility renderer notes: only plain GPU particles with a
## translucency + unshaded material are used. There is no compute shader, no
## particle collision (GPU collision buffers are the heavy part on a browser
## tab), no sub-emitters and no GPUParticlesAttractor nodes. Ground contact is
## approximated with a low emission box, downward gravity and damping instead,
## which is visually enough for dust/snow and costs nothing.
##
## Draw budget: one QuadMesh per layer, so a map costs 2-3 draw passes for its
## whole weather system and 0 extra `MeshInstance3D` nodes. All counts are
## surfaced through the stats Dictionary (`get_fx_stats()` on AmbientWorld) and
## asserted by `scripts/effects/fx_budget_probe.gd`.

const FxQuality := preload("res://scripts/effects/fx_quality.gd")

const DUST_TEX: String = "res://assets/textures/foliage/dust_puff.png"
const LEAF_TEX: String = "res://assets/textures/foliage/drifting_leaf.png"
const CONFETTI_TEX: String = "res://assets/textures/fx/confetti.png"
## Ember/spark streaks already ship for the drift sparks; reuse the same art.
const SPARK_TEX: String = "res://assets/textures/fx/spark_streak.png"

## Slow ambient sheets simulate at 30 Hz; fast weather keeps 60 Hz.
const FPS_SLOW: int = 30
const FPS_FAST: int = 60
## Camera-following emitters are re-anchored every frame; this is the height
## above the chase camera that keeps a weather box around the player.
const FOLLOW_PAD: float = 8.0
## Below this distance from the world anchor the full density is used; further
## out the systems thin out instead of popping (visual LOD).
const LOD_FADE_START_SCALE: float = 2.4
const LOD_FADE_END_SCALE: float = 4.0
const LOD_MIN_RATIO: float = 0.35

## Shared soft round sprite, generated once instead of adding an image asset.
## Snow, pollen, diamond dust and sand grains all use it with different colour
## ramps and scales.
static var _soft_dot: GradientTexture2D


# --------------------------------------------------------------------------
# biome mapping
# --------------------------------------------------------------------------


static func normalise_biome(raw: String) -> String:
	## Every theme name used by the race maps and the three minigame families
	## folds onto one of the seven authored palettes below.
	match raw.to_lower():
		"glacier", "snowfield", "ko_iceberg", "iceberg":
			return "glacier"
		"canyon", "bt_labyrinth", "desert":
			return "canyon"
		"farmyard", "farm":
			return "farmyard"
		"foundry", "ko_foundry", "lava":
			return "foundry"
		"dockyard", "harbour", "bt_ferries":
			return "dockyard"
		"stadium", "bt_plaza", "ko_rooftop", "skyline":
			return "stadium"
		_:
			return "meadow"


static func biome_ids() -> PackedStringArray:
	return PackedStringArray(["glacier", "canyon", "farmyard", "foundry",
		"dockyard", "stadium", "meadow"])


# --------------------------------------------------------------------------
# public API
# --------------------------------------------------------------------------


static func build(parent: Node3D, biome: String, center: Vector3,
		extent: float, opts: Dictionary = {}) -> Dictionary:
	## Builds the themed layers under `parent` and returns the FX stats. Safe to
	## call for a map that already has the field: the existing stats are returned
	## so a second builder cannot double the weather.
	if parent == null:
		return {}
	var canonical: String = normalise_biome(biome)
	var existing: Dictionary = parent.get_meta("ambient_fx_stats", {})
	if not existing.is_empty():
		return existing
	var specs: Array[Dictionary] = layer_specs(canonical)
	var layer_cap: int = int(opts.get("max_layers", FxQuality.layer_budget()))
	var emitters: Array[GPUParticles3D] = []
	var amount_total: int = 0
	var draw_total: int = 0
	for index in mini(specs.size(), layer_cap):
		var spec: Dictionary = specs[index]
		var emitter: GPUParticles3D = _make_emitter(spec, center, extent)
		if emitter == null:
			continue
		parent.add_child(emitter)
		emitters.append(emitter)
		amount_total += emitter.amount
		draw_total += 1
	var stats: Dictionary = {
		"biome": canonical,
		"layers": emitters.size(),
		"nodes": emitters.size(),
		"amount": amount_total,
		"draws": draw_total,
		"quality": FxQuality.tier(),
		"web": FxQuality.is_web(),
		"reduced_motion": FxQuality.reduce_motion(),
		"anchor": center,
		"extent": extent,
		"emitters": emitters,
		"skid_trails": int(opts.get("skid_trails", 0)),
	}
	parent.set_meta("ambient_fx_stats", stats)
	return stats


static func update(emitters: Array, anchor: Vector3, time: float) -> void:
	## Camera-follow + wind-gust pass. Called from AmbientWorld._process with the
	## active camera position; headless never reaches here.
	for raw: Variant in emitters:
		var emitter: GPUParticles3D = raw as GPUParticles3D
		if not is_instance_valid(emitter):
			continue
		if bool(emitter.get_meta("follow_camera", false)):
			var offset: Vector3 = emitter.get_meta("follow_offset", Vector3.ZERO)
			emitter.global_position = anchor + offset
		var gust: float = float(emitter.get_meta("gust", 0.0))
		if gust <= 0.0:
			continue
		var base_dir: Vector3 = emitter.get_meta("direction", Vector3.ZERO)
		if base_dir == Vector3.ZERO:
			continue
		var phase: float = float(emitter.get_meta("gust_phase", 0.0))
		var band: float = sin(time * 0.37 + phase) * 0.70 \
			+ sin(time * 1.13 + phase * 2.0) * 0.30
		var wind: Vector3 = base_dir + Vector3(band * gust, 0.0, band * gust * 0.55)
		var process: ParticleProcessMaterial = emitter.process_material as ParticleProcessMaterial
		if process != null and wind.length_squared() > 0.0001:
			process.direction = wind.normalized()


static func set_density(emitters: Array, ratio: float) -> void:
	## Visual LOD for a whole world: when the viewer is very far outside the
	## themed oval (preview cameras, spectate fly-bys) the layers thin out but
	## never disappear. Returns the ratio actually applied.
	var clean: float = clampf(ratio, LOD_MIN_RATIO, 1.0)
	for raw: Variant in emitters:
		var emitter: GPUParticles3D = raw as GPUParticles3D
		if is_instance_valid(emitter):
			emitter.amount_ratio = clean
	return


static func describe(biome: String, tier: int, is_web: bool,
		reduced_motion: bool = false) -> Dictionary:
	## Pure budget description for the headless probe: no nodes are created.
	var canonical: String = normalise_biome(biome)
	var specs: Array[Dictionary] = layer_specs(canonical)
	var scale: float = _density_for(tier, is_web, reduced_motion)
	var layer_cap: int = _layer_cap_for(tier, is_web)
	var amount: int = 0
	var layers: int = mini(specs.size(), layer_cap)
	for index in layers:
		amount += maxi(int(round(float(specs[index]["amount"]) * scale)), 8)
	return {
		"biome": canonical, "layers": layers, "amount": amount,
		"draws": layers, "tier": tier, "web": is_web,
		"reduced_motion": reduced_motion,
	}


static func layer_specs(biome: String) -> Array[Dictionary]:
	## Authored layer list for one palette, most important layer first (the
	## layer cap trims from the tail, so detail goes before weather).
	var canonical: String = normalise_biome(biome)
	match canonical:
		"glacier":
			return [
				_layer({
					"name": "BlizzardSnow", "amount": 150, "lifetime": 5.2,
					"texture": "", "size": Vector2(0.17, 0.17),
					"extents": Vector3(30, 8, 30), "offset": Vector3(0, FOLLOW_PAD, 0),
					"direction": Vector3(0.9, -0.45, 0.25), "spread": 14.0,
					"velocity": Vector2(4.5, 9.5), "gravity": Vector3(0.9, -2.1, 0.4),
					"scale": Vector2(0.5, 1.35), "scale_curve": Vector2(0.85, 1.25),
					"damping": Vector2(0.05, 0.3), "turbulence": 2.6,
					"turbulence_scale": 1.1, "lifetime_randomness": 0.5,
					"color": Color(0.94, 0.98, 1.0, 0.92),
					"follow_camera": true, "gust": 0.45, "fixed_fps": FPS_FAST,
				}),
				_layer({
					"name": "Spindrift", "amount": 90, "lifetime": 2.3,
					"size": Vector2(0.34, 0.11),
					"extents": Vector3(26, 1.6, 26),
					"offset": Vector3(0, -1.6, 0),
					"direction": Vector3(1.0, -0.10, 0.3), "spread": 8.0,
					"velocity": Vector2(7.0, 14.0), "gravity": Vector3(0.4, -0.7, 0.1),
					"scale": Vector2(0.45, 1.05), "scale_curve": Vector2(1.0, 0.7),
					"damping": Vector2(0.2, 0.6), "turbulence": 1.4,
					"turbulence_scale": 0.9, "lifetime_randomness": 0.5,
					"color": Color(0.88, 0.96, 1.0, 0.62),
					"follow_camera": true, "gust": 0.6, "fixed_fps": FPS_SLOW,
				}),
				_layer({
					"name": "DiamondDust", "amount": 44, "lifetime": 3.6,
					"size": Vector2(0.10, 0.10),
					"extents": Vector3(24, 6, 24), "offset": Vector3(0, 5.0, 0),
					"direction": Vector3(0.35, -1.0, 0.15), "spread": 45.0,
					"velocity": Vector2(0.4, 1.2), "gravity": Vector3(0.1, -0.25, 0.0),
					"scale": Vector2(0.4, 1.0), "scale_curve": Vector2(0.8, 1.2),
					"turbulence": 0.9, "additive": true,
					"color": Color(0.72, 0.94, 1.0, 0.55),
					"follow_camera": true, "fixed_fps": FPS_SLOW,
				}),
			]
		"canyon":
			return [
				_layer({
					"name": "DustSheet", "amount": 120, "lifetime": 5.2,
					"texture": DUST_TEX, "size": Vector2(0.34, 0.20),
					"extents": Vector3(28, 6, 28), "offset": Vector3(0, 5.5, 0),
					"direction": Vector3(1.0, 0.08, 0.3), "spread": 20.0,
					"velocity": Vector2(3.5, 7.5), "gravity": Vector3(0.6, -0.25, 0.2),
					"scale": Vector2(0.7, 1.8), "scale_curve": Vector2(0.7, 1.35),
					"damping": Vector2(0.3, 0.9), "turbulence": 1.8,
					"turbulence_scale": 1.3, "lifetime_randomness": 0.45,
					"color": Color(0.92, 0.76, 0.52, 0.58),
					"follow_camera": true, "gust": 0.5, "fixed_fps": FPS_SLOW,
				}),
				_layer({
					"name": "SandGrains", "amount": 90, "lifetime": 2.2,
					"size": Vector2(0.10, 0.10),
					"extents": Vector3(24, 4, 24), "offset": Vector3(0, 2.0, 0),
					"direction": Vector3(1.0, -0.2, 0.25), "spread": 18.0,
					"velocity": Vector2(7.0, 13.0), "gravity": Vector3(0.3, -1.4, 0.1),
					"scale": Vector2(0.35, 0.9), "scale_curve": Vector2(1.0, 0.8),
					"damping": Vector2(0.1, 0.4), "turbulence": 0.8,
					"turbulence_scale": 0.8, "lifetime_randomness": 0.5,
					"color": Color(0.96, 0.78, 0.48, 0.85),
					"follow_camera": true, "gust": 0.55, "fixed_fps": FPS_FAST,
				}),
				_layer({
					"name": "SunMotes", "amount": 36, "lifetime": 4.0,
					"size": Vector2(0.08, 0.08),
					"extents": Vector3(22, 5, 22), "offset": Vector3(0, 3.5, 0),
					"direction": Vector3(0.3, 0.35, 0.2), "spread": 40.0,
					"velocity": Vector2(0.25, 0.85), "gravity": Vector3(0.05, 0.10, 0.0),
					"scale": Vector2(0.5, 1.1), "scale_curve": Vector2(0.9, 1.2),
					"turbulence": 1.2, "additive": true,
					"color": Color(1.0, 0.92, 0.62, 0.50),
					"follow_camera": true, "fixed_fps": FPS_SLOW,
				}),
			]
		"farmyard":
			return [
				_layer({
					"name": "ChaffDust", "amount": 90, "lifetime": 5.0,
					"texture": DUST_TEX, "size": Vector2(0.30, 0.22),
					"extents": Vector3(24, 5, 24), "offset": Vector3(0, 4.5, 0),
					"direction": Vector3(1.0, 0.15, 0.35), "spread": 26.0,
					"velocity": Vector2(2.5, 5.5), "gravity": Vector3(0.4, -0.2, 0.1),
					"scale": Vector2(0.6, 1.5), "scale_curve": Vector2(0.75, 1.3),
					"damping": Vector2(0.25, 0.8), "turbulence": 1.6,
					"turbulence_scale": 1.2, "lifetime_randomness": 0.5,
					"color": Color(0.96, 0.88, 0.62, 0.55),
					"follow_camera": true, "gust": 0.4, "fixed_fps": FPS_SLOW,
				}),
				_layer({
					"name": "PollenMotes", "amount": 54, "lifetime": 4.5,
					"size": Vector2(0.09, 0.09),
					"extents": Vector3(22, 4, 22), "offset": Vector3(0, 3.5, 0),
					"direction": Vector3(0.25, 0.4, 0.2), "spread": 55.0,
					"velocity": Vector2(0.3, 0.9), "gravity": Vector3(0.05, 0.05, 0.0),
					"scale": Vector2(0.45, 1.05), "scale_curve": Vector2(0.9, 1.25),
					"turbulence": 0.8, "additive": true,
					"color": Color(1.0, 0.94, 0.62, 0.52),
					"follow_camera": true, "fixed_fps": FPS_SLOW,
				}),
				_layer({
					"name": "StrawFlutter", "amount": 30, "lifetime": 6.0,
					"texture": LEAF_TEX, "size": Vector2(0.10, 0.22),
					"extents": Vector3(20, 3, 20), "offset": Vector3(0, 2.5, 0),
					"direction": Vector3(0.8, -0.2, 0.3), "spread": 40.0,
					"velocity": Vector2(0.6, 1.6), "gravity": Vector3(0.2, -0.3, 0.1),
					"scale": Vector2(0.6, 1.2), "angular_velocity": Vector2(-160.0, 160.0),
					"turbulence": 1.4, "lifetime_randomness": 0.5,
					"color": Color(0.94, 0.82, 0.5, 0.8),
					"follow_camera": true, "fixed_fps": FPS_SLOW,
				}),
			]
		"foundry":
			return [
				_layer({
					"name": "RisingEmbers", "amount": 110, "lifetime": 3.0,
					"texture": SPARK_TEX, "size": Vector2(0.07, 0.24),
					"extents": Vector3(26, 4, 26), "offset": Vector3(0, 3.0, 0),
					"direction": Vector3(0.15, 1.0, 0.1), "spread": 20.0,
					"velocity": Vector2(2.2, 5.5), "gravity": Vector3(0.2, 2.4, 0.0),
					"scale": Vector2(0.6, 1.4), "scale_curve": Vector2(1.1, 0.55),
					"damping": Vector2(0.2, 0.7),
					"angular_velocity": Vector2(-90.0, 90.0),
					"turbulence": 2.4, "turbulence_scale": 1.0,
					"lifetime_randomness": 0.55, "additive": true,
					"color": Color(1.0, 0.58, 0.18, 0.92),
					"ramp": PackedColorArray([
						Color(1.0, 0.9, 0.5, 0.0), Color(1.0, 0.72, 0.26, 1.0),
						Color(1.0, 0.38, 0.08, 0.85), Color(1.0, 0.22, 0.04, 0.0)]),
					"follow_camera": true, "fixed_fps": FPS_SLOW,
				}),
				_layer({
					"name": "AshFall", "amount": 80, "lifetime": 5.5,
					"texture": DUST_TEX, "size": Vector2(0.22, 0.22),
					"extents": Vector3(26, 7, 26), "offset": Vector3(0, 7.0, 0),
					"direction": Vector3(0.3, -1.0, 0.15), "spread": 30.0,
					"velocity": Vector2(0.8, 2.4), "gravity": Vector3(0.2, -0.8, 0.0),
					"scale": Vector2(0.5, 1.4), "scale_curve": Vector2(0.9, 1.3),
					"damping": Vector2(0.2, 0.7), "turbulence": 1.6,
					"turbulence_scale": 1.4, "lifetime_randomness": 0.45,
					"color": Color(0.28, 0.24, 0.23, 0.55),
					"follow_camera": true, "gust": 0.3, "fixed_fps": FPS_SLOW,
				}),
				_layer({
					"name": "LavaGlow", "amount": 40, "lifetime": 3.4,
					"size": Vector2(0.10, 0.10),
					"extents": Vector3(24, 3, 24), "offset": Vector3(0, 2.0, 0),
					"direction": Vector3(0.1, 0.5, 0.1), "spread": 50.0,
					"velocity": Vector2(0.5, 1.4), "gravity": Vector3(0.05, 0.35, 0.0),
					"scale": Vector2(0.5, 1.2), "scale_curve": Vector2(0.9, 1.3),
					"turbulence": 1.0, "additive": true,
					"color": Color(1.0, 0.46, 0.12, 0.5),
					"follow_camera": true, "fixed_fps": FPS_SLOW,
				}),
			]
		"dockyard":
			return [
				_layer({
					"name": "SeaMist", "amount": 100, "lifetime": 5.5,
					"texture": DUST_TEX, "size": Vector2(0.5, 0.4),
					"extents": Vector3(26, 6, 26), "offset": Vector3(0, 5.0, 0),
					"direction": Vector3(0.8, 0.05, 0.3), "spread": 30.0,
					"velocity": Vector2(1.6, 3.6), "gravity": Vector3(0.1, -0.15, 0.05),
					"scale": Vector2(0.7, 1.8), "scale_curve": Vector2(0.8, 1.3),
					"damping": Vector2(0.2, 0.6), "turbulence": 1.2,
					"turbulence_scale": 1.1, "lifetime_randomness": 0.45,
					"color": Color(0.76, 0.9, 1.0, 0.35),
					"follow_camera": true, "gust": 0.35, "fixed_fps": FPS_SLOW,
				}),
				_layer({
					"name": "SaltSpray", "amount": 60, "lifetime": 2.0,
					"size": Vector2(0.12, 0.12),
					"extents": Vector3(24, 3, 24), "offset": Vector3(0, -1.8, 0),
					"direction": Vector3(0.9, -0.3, 0.3), "spread": 22.0,
					"velocity": Vector2(4.0, 8.0), "gravity": Vector3(0.3, -1.2, 0.2),
					"scale": Vector2(0.4, 1.0), "scale_curve": Vector2(1.0, 0.75),
					"damping": Vector2(0.15, 0.5), "turbulence": 0.9,
					"turbulence_scale": 0.8, "lifetime_randomness": 0.5,
					"color": Color(0.9, 0.98, 1.0, 0.6),
					"follow_camera": true, "gust": 0.4, "fixed_fps": FPS_FAST,
				}),
				_layer({
					"name": "GullFeather", "amount": 26, "lifetime": 7.0,
					"texture": LEAF_TEX, "size": Vector2(0.12, 0.12),
					"extents": Vector3(22, 6, 22), "offset": Vector3(0, 5.0, 0),
					"direction": Vector3(0.6, -0.2, 0.2), "spread": 45.0,
					"velocity": Vector2(0.5, 1.4), "gravity": Vector3(0.15, -0.25, 0.05),
					"scale": Vector2(0.5, 1.2), "angular_velocity": Vector2(-120.0, 120.0),
					"turbulence": 1.6, "lifetime_randomness": 0.55,
					"color": Color(0.92, 0.95, 1.0, 0.55),
					"follow_camera": true, "fixed_fps": FPS_SLOW,
				}),
			]
		"stadium":
			return [
				_layer({
					"name": "ConfettiDrift", "amount": 90, "lifetime": 6.5,
					"texture": CONFETTI_TEX, "size": Vector2(0.14, 0.14),
					"extents": Vector3(28, 8, 28), "offset": Vector3(0, 8.0, 0),
					"direction": Vector3(0.3, -0.5, 0.2), "spread": 45.0,
					"velocity": Vector2(0.6, 1.8), "gravity": Vector3(0.2, -0.55, 0.1),
					"scale": Vector2(0.6, 1.3),
					"angular_velocity": Vector2(-180.0, 180.0),
					"turbulence": 1.0, "turbulence_scale": 1.0,
					"lifetime_randomness": 0.5,
					"color": Color(1.0, 0.95, 0.85, 0.9),
					"ramp": PackedColorArray([
						Color(1.0, 1.0, 1.0, 0.0), Color(1.0, 0.86, 0.25, 1.0),
						Color(0.32, 0.78, 0.95, 1.0), Color(0.95, 0.4, 0.65, 0.0)]),
					"follow_camera": true, "gust": 0.35, "fixed_fps": FPS_SLOW,
				}),
				_layer({
					"name": "PaperMotes", "amount": 50, "lifetime": 4.6,
					"size": Vector2(0.09, 0.09),
					"extents": Vector3(24, 5, 24), "offset": Vector3(0, 5.0, 0),
					"direction": Vector3(0.3, 0.25, 0.2), "spread": 50.0,
					"velocity": Vector2(0.25, 0.8), "gravity": Vector3(0.05, -0.1, 0.0),
					"scale": Vector2(0.45, 1.1), "scale_curve": Vector2(0.9, 1.2),
					"turbulence": 1.1, "additive": true,
					"color": Color(1.0, 0.9, 0.62, 0.55),
					"follow_camera": true, "fixed_fps": FPS_SLOW,
				}),
				_layer({
					"name": "SkySparkle", "amount": 30, "lifetime": 3.2,
					"size": Vector2(0.08, 0.08),
					"extents": Vector3(24, 5, 24), "offset": Vector3(0, 4.0, 0),
					"direction": Vector3(0.2, 0.4, 0.1), "spread": 55.0,
					"velocity": Vector2(0.3, 1.0), "gravity": Vector3(0.05, 0.15, 0.0),
					"scale": Vector2(0.4, 1.0), "turbulence": 1.3, "additive": true,
					"color": Color(0.55, 0.9, 1.0, 0.45),
					"follow_camera": true, "fixed_fps": FPS_SLOW,
				}),
			]
		_:
			return [
				_layer({
					"name": "LeafDrift", "amount": 80, "lifetime": 7.0,
					"texture": LEAF_TEX, "size": Vector2(0.18, 0.18),
					"extents": Vector3(28, 8, 28), "offset": Vector3(0, 6.0, 0),
					"direction": Vector3(0.6, -0.3, 0.2), "spread": 50.0,
					"velocity": Vector2(0.8, 2.2), "gravity": Vector3(0.3, -0.35, 0.1),
					"scale": Vector2(0.7, 1.4),
					"angular_velocity": Vector2(-120.0, 120.0),
					"turbulence": 2.0, "turbulence_scale": 1.2,
					"lifetime_randomness": 0.5,
					"color": Color(0.85, 0.95, 0.7, 0.85),
					"ramp": PackedColorArray([
						Color(1.0, 1.0, 1.0, 0.0), Color(0.62, 0.85, 0.42, 0.9),
						Color(0.93, 0.78, 0.35, 0.85), Color(0.75, 0.62, 0.25, 0.0)]),
					"follow_camera": true, "gust": 0.4, "fixed_fps": FPS_SLOW,
				}),
				_layer({
					"name": "PollenMotes", "amount": 60, "lifetime": 4.0,
					"size": Vector2(0.08, 0.08),
					"extents": Vector3(24, 4, 24), "offset": Vector3(0, 3.0, 0),
					"direction": Vector3(0.3, 0.3, 0.2), "spread": 60.0,
					"velocity": Vector2(0.25, 0.8), "gravity": Vector3(0.05, 0.08, 0.0),
					"scale": Vector2(0.4, 1.0), "turbulence": 0.9, "additive": true,
					"color": Color(1.0, 0.94, 0.62, 0.55),
					"follow_camera": true, "fixed_fps": FPS_SLOW,
				}),
				_layer({
					"name": "PetalFlutter", "amount": 30, "lifetime": 6.5,
					"texture": CONFETTI_TEX, "size": Vector2(0.1, 0.1),
					"extents": Vector3(20, 4, 20), "offset": Vector3(0, 4.0, 0),
					"direction": Vector3(0.5, -0.4, 0.2), "spread": 50.0,
					"velocity": Vector2(0.4, 1.2), "gravity": Vector3(0.15, -0.4, 0.05),
					"scale": Vector2(0.5, 1.2),
					"angular_velocity": Vector2(-200.0, 200.0),
					"turbulence": 1.5, "color": Color(1.0, 0.8, 0.9, 0.7),
					"follow_camera": true, "fixed_fps": FPS_SLOW,
				}),
			]


# --------------------------------------------------------------------------
# internals
# --------------------------------------------------------------------------


static func _layer(props: Dictionary) -> Dictionary:
	## Defaults for every layer, overridden by the per-biome values above. One
	## dictionary per layer keeps the theme tables readable and makes a missing
	## key harmless instead of a parse error.
	var spec: Dictionary = {
		"name": "Layer", "amount": 80, "lifetime": 4.0, "fixed_fps": FPS_SLOW,
		"texture": "", "size": Vector2(0.24, 0.24), "additive": false,
		"extents": Vector3(18, 6, 18), "offset": Vector3(0, 5.0, 0),
		"direction": Vector3(0.5, -0.4, 0.2), "spread": 30.0,
		"gravity": Vector3(0.0, -0.4, 0.0), "velocity": Vector2(1.0, 2.5),
		"scale": Vector2(0.6, 1.4), "scale_curve": Vector2(0.8, 1.15),
		"damping": Vector2(0.2, 0.8), "angular_velocity": Vector2(0.0, 0.0),
		"turbulence": 0.0, "turbulence_scale": 1.6,
		"lifetime_randomness": 0.4, "color": Color(1.0, 1.0, 1.0, 0.8),
		"ramp": PackedColorArray(), "follow_camera": true,
		"gust": 0.0,
	}
	spec.merge(props, true)
	return spec


static func _layer_cap_for(tier: int, is_web: bool) -> int:
	if is_web or tier <= FxQuality.QUALITY_PERFORMANCE:
		return 2
	return 3


static func _density_for(tier: int, is_web: bool, reduced: bool) -> float:
	var scale: float = 1.0
	match tier:
		FxQuality.QUALITY_PERFORMANCE:
			scale = 0.62
		FxQuality.QUALITY_QUALITY:
			scale = 1.30
	if is_web:
		scale *= 0.55
	if reduced:
		scale *= 0.80
	return scale


static func _make_emitter(spec: Dictionary, center: Vector3,
		extent: float) -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.name = "AmbientFX_" + str(spec["name"])
	var density: float = FxQuality.density_scale()
	var amount: int = maxi(int(round(float(spec["amount"]) * density)), 8)
	emitter.amount = amount
	emitter.lifetime = float(spec["lifetime"])
	emitter.fixed_fps = FxQuality.fixed_fps(int(spec["fixed_fps"]))
	emitter.local_coords = false
	emitter.emitting = true
	emitter.randomness = float(spec["lifetime_randomness"])
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var padding: float = maxf(extent, FOLLOW_PAD) + 40.0
	emitter.visibility_aabb = AABB(Vector3(-padding, -40.0, -padding),
		Vector3(padding * 2.0, padding * 2.0, padding * 2.0))
	if not bool(spec["follow_camera"]):
		emitter.visibility_range_end = padding * 2.5
		emitter.visibility_range_end_margin = padding * 0.5
		emitter.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	emitter.process_material = _process_material(spec)
	emitter.draw_pass_1 = _quad_mesh(spec)
	var offset: Vector3 = spec["offset"]
	emitter.position = center + offset
	emitter.set_meta("follow_camera", bool(spec["follow_camera"]))
	emitter.set_meta("follow_offset", offset)
	var direction: Vector3 = spec["direction"]
	emitter.set_meta("direction", direction)
	emitter.set_meta("gust", float(spec["gust"]))
	emitter.set_meta("gust_phase", float(absi(emitter.name.hash()) % 977) * 0.0128)
	emitter.set_meta("biome_layer", str(spec["name"]))
	return emitter


static func _process_material(spec: Dictionary) -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	var extents: Vector3 = spec["extents"]
	material.emission_box_extents = extents
	var direction: Vector3 = spec["direction"]
	material.direction = direction.normalized()
	material.spread = float(spec["spread"])
	var gravity: Vector3 = spec["gravity"]
	material.gravity = gravity
	var velocity: Vector2 = spec["velocity"]
	material.initial_velocity_min = velocity.x * FxQuality.motion_scale()
	material.initial_velocity_max = velocity.y * FxQuality.motion_scale()
	var damping: Vector2 = spec["damping"]
	material.damping_min = damping.x
	material.damping_max = damping.y
	var scale_range: Vector2 = spec["scale"]
	material.scale_min = scale_range.x
	material.scale_max = scale_range.y
	var curve_range: Vector2 = spec["scale_curve"]
	material.scale_curve = _scale_curve(curve_range)
	material.lifetime_randomness = float(spec["lifetime_randomness"])
	var angular: Vector2 = spec["angular_velocity"]
	if angular != Vector2.ZERO:
		material.angle_min = -180.0
		material.angle_max = 180.0
		material.angular_velocity_min = angular.x * FxQuality.motion_scale()
		material.angular_velocity_max = angular.y * FxQuality.motion_scale()
	var turbulence: float = float(spec["turbulence"])
	if turbulence > 0.0:
		material.turbulence_enabled = true
		material.turbulence_noise_strength = turbulence
		material.turbulence_noise_scale = float(spec["turbulence_scale"])
		material.turbulence_noise_speed = Vector3(0.12, 0.05, 0.10)
		material.turbulence_influence_min = 0.08
		material.turbulence_influence_max = 0.42
	var tint: Color = spec["color"]
	material.color = tint
	material.color_ramp = _color_ramp(spec)
	return material


static func _quad_mesh(spec: Dictionary) -> QuadMesh:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = _texture_for(str(spec["texture"]))
	if bool(spec["additive"]):
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var quad := QuadMesh.new()
	quad.size = spec["size"]
	quad.material = material
	return quad


static func _texture_for(path: String) -> Texture2D:
	if path != "" and ResourceLoader.exists(path):
		var loaded: Texture2D = load(path) as Texture2D
		if loaded != null:
			return loaded
	return _soft_dot_texture()


static func _soft_dot_texture() -> GradientTexture2D:
	## Round soft sprite generated once in memory: a 32x32 radial gradient. No
	## image asset, no import step, identical on every platform.
	if _soft_dot != null:
		return _soft_dot
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 0.78, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0, 0.85),
		Color(1.0, 1.0, 1.0, 0.28), Color(1.0, 1.0, 1.0, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 32
	texture.height = 32
	_soft_dot = texture
	return _soft_dot


static func _scale_curve(range_values: Vector2) -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, maxf(range_values.x, 0.01)))
	curve.add_point(Vector2(1.0, maxf(range_values.y, 0.01)))
	curve.min_value = 0.0
	curve.max_value = 2.0
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


static func _color_ramp(spec: Dictionary) -> GradientTexture1D:
	var base: Color = spec["color"]
	var ramp: PackedColorArray = spec["ramp"]
	if ramp.is_empty():
		ramp = PackedColorArray([
			Color(base.r, base.g, base.b, 0.0),
			Color(base.r, base.g, base.b, base.a),
			Color(base.r, base.g, base.b, base.a * 0.7),
			Color(base.r, base.g, base.b, 0.0),
		])
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.18, 0.72, 1.0])
	gradient.colors = ramp
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture
