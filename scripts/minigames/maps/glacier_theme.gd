extends RefCounted
## Glacier Pass: a fast alpine loop dressed entirely in flat Kenney cartoon art.
##
## Entry point, called by grass_race once per race:
##
##   static func build(race: Node3D, spline) -> void
##
## KenneyTiles owns the road, its colliders and the spline. This theme only
## dresses the map, and every solid piece is placed through
## scripts/minigames/tile_kit.gd, so the map batches into a handful of
## MultiMeshes and every prop collides on CollisionLayers.WORLD.
##
## Layout: a red barrier ring on both sides, two grandstands, a start gantry,
## eight floodlights, checkered start flags, ice warning flags and pylons,
## start banner towers, snowbank boulders on the corner exits and a four-cell
## pine band packed outside the loop. A flat white snow field replaces the
## meadow ground and a flat ice sheen marks the preset's `ice` spans. No photo
## texture is referenced anywhere in the theme.
##
## The build is idempotent: a second call finds GlacierDressing and returns, so
## a scene reload can never double the props.

const GlacierLayout := preload("res://scripts/minigames/maps/glacier/glacier_layout.gd")
const GlacierGround := preload("res://scripts/minigames/maps/glacier/glacier_ground.gd")
const GlacierIce := preload("res://scripts/minigames/maps/glacier/glacier_ice.gd")
const GlacierSurface := preload("res://scripts/minigames/maps/glacier/glacier_surface.gd")

const HOLDER_NAME: String = "GlacierDressing"


## Builds the whole glacier dressing under `race`. `spline` is the grid spline
## KenneyTiles.build returned, or the legacy TrackSpline while the race scene is
## still being wired; both expose the sample/total_length surface this theme
## reads through TileKit.
static func build(race: Node3D, spline) -> void:
	if race == null:
		push_warning("GlacierTheme: build() needs the race root.")
		return
	if spline == null:
		push_warning("GlacierTheme: build() needs the race spline; nothing was dressed.")
		return
	if race.has_node(HOLDER_NAME):
		return
	var preset: Dictionary = GlacierSurface.preset_for(race)
	var holder := Node3D.new()
	holder.name = HOLDER_NAME
	race.add_child(holder)
	var stats: Dictionary = GlacierLayout.build(holder, spline, preset)
	var ice: Dictionary = GlacierIce.build(holder, race, spline, preset)
	var ground: int = GlacierGround.build(race, preset)
	_apply_climate(race, preset)
	var objects: int = int(stats.get("objects", 0))
	var draws: int = int(stats.get("draws", 0)) \
		+ int(ice.get("draws", 0)) + ground
	print("GLACIER PASS: %d objects, ~%d draws, %d barrier pieces, %d pines, %d snowbanks, %d stands, %d lights, %d flags, %d signs" % [
		objects, draws, int(stats.get("barriers", 0)),
		int(stats.get("pines", 0)), int(stats.get("snowbanks", 0)),
		int(stats.get("stands", 0)), int(stats.get("lights", 0)),
		int(stats.get("flags", 0)), int(stats.get("signage", 0))])
	print("GLACIER PASS: ice %.0f%% of the lap in %d span(s) (%.0f m), white ground %s" % [
		GlacierSurface.ice_fraction(preset) * 100.0, int(ice.get("spans", 0)),
		float(ice.get("length", 0.0)), "on" if ground > 0 else "kept"])
	race.set_meta("glacier_stats", {
		"objects": objects,
		"draws": draws,
		"barriers": int(stats.get("barriers", 0)),
		"pines": int(stats.get("pines", 0)),
		"snowbanks": int(stats.get("snowbanks", 0)),
		"stands": int(stats.get("stands", 0)),
		"lights": int(stats.get("lights", 0)),
		"flags": int(stats.get("flags", 0)),
		"signage": int(stats.get("signage", 0)),
		"gantry": int(stats.get("gantry", 0)),
		"ice_spans": int(ice.get("spans", 0)),
		"ice_length": float(ice.get("length", 0.0)),
		"ice_top": float(ice.get("top", 0.0)),
		"ground": ground,
	})


## Cold alpine grade: pale blue depth fog, a snow-blue horizon under the sky and
## a neutral cold sun. The shared VisualGrade still owns exposure and post; the
## theme only pushes the palette towards ice.
static func _apply_climate(race: Node3D, preset: Dictionary) -> void:
	var world := race.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world != null and world.environment != null:
		var env: Environment = world.environment
		var haze: Color = GlacierSurface.fog_color(preset)
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_light_color = haze
		env.fog_light_energy = 0.95
		env.fog_density = 0.0018
		env.fog_aerial_perspective = 0.6
		env.fog_sky_affect = 0.0
		if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
			var sky: ProceduralSkyMaterial = \
				env.sky.sky_material as ProceduralSkyMaterial
			sky.ground_horizon_color = haze
			sky.ground_bottom_color = Color("8fa6b8")
	var sun := race.get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.light_color = Color(0.94, 0.97, 1.0)
